import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';

void purchasingCases() {
  test(
    'all eight commands, frozen snapshots, restart/late replay and minimized atomic audit',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(
              f,
              name: '<script>literal Supplier 😀</script>',
              reference: 'CUSTOMER',
            ),
            d = await populated(f, s: s);
        final issuedBody = {
          'operationId': newUuid(),
          'expectedVersion': d['version'],
        };
        final issued = (await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/issue',
          body: issuedBody,
        )).body;
        final frozen = issued['order'] as Map;
        await f.restart();
        var before = await purchasingEvidence(f);
        expect(
          (await f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: issuedBody,
          )).body,
          {...issued, 'replayed': true},
        );
        await purchasingUnchanged(f, before);
        final edit = {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'name': 'Renamed',
          'orderingReference': 'NEW',
        };
        final edited =
            (await f.call(
                  'PUT',
                  '/purchasing/suppliers/${s['id']}',
                  body: edit,
                )).body['supplier']
                as Map;
        await f.call(
          'POST',
          '/purchasing/suppliers/${s['id']}/retire',
          body: {
            'operationId': newUuid(),
            'expectedVersion': edited['version'],
          },
        );
        final closed =
            (await f.call(
                  'POST',
                  '$purchasingOrders/${d['id']}/close',
                  body: {
                    'operationId': newUuid(),
                    'expectedVersion': frozen['version'],
                    'reason': 'Administrative close <script> 😀',
                  },
                )).body['order']
                as Map;
        expect(closed['supplier'], frozen['supplier']);
        expect(closed['lines'], frozen['lines']);
        before = await purchasingEvidence(f);
        expect(
          (await f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: issuedBody,
          )).body['order'],
          frozen,
        );
        await purchasingUnchanged(f, before);
        final s2 = await supplier(f), cancelled = await draft(f, s2);
        await f.call(
          'POST',
          '$purchasingOrders/${cancelled['id']}/cancel',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'Cancelled empty draft',
          },
        );
        final history =
            (await f.call(
                  'GET',
                  '$purchasingOrders/${d['id']}/history',
                )).body['items']
                as List;
        expect(history.map((h) => h['kind']), [
          'order_create',
          'order_save',
          'order_issue',
          'order_close',
        ]);
        expect(history[1]['result']['order']['lines'], d['lines']);
        final actions = await f.owner.execute(
          'SELECT changes FROM "${f.schema}".audit_entries WHERE action LIKE \'purchasing.%\'',
        );
        for (final a in actions) {
          final text = jsonEncode(a.first);
          for (final secret in [
            'CUSTOMER',
            'Renamed',
            'Administrative close',
            'literal Supplier',
            '2.500',
            'NEW',
          ]) {
            expect(text, isNot(contains(secret)));
          }
        }
      });
    },
  );
  test(
    'saved references require explicit review; unit and metadata conflicts have no effects',
    () async {
      await withMerchandisingFixture((f) async {
        final d = await populated(f), line = (d['lines'] as List).single as Map;
        final a = ArticleDto.fromJson(
          (await f.call('GET', '/articles/${line['articleId']}')).body,
        );
        await f.call(
          'POST',
          '/articles/${a.id}/edit',
          body: {
            'expectedVersion': a.version,
            'sku': a.sku,
            'barcode': a.barcode,
            'name': 'Changed',
            'description': a.description,
            'unit': 'bag',
          },
        );
        final body = {
              'operationId': newUuid(),
              'expectedVersion': d['version'],
            },
            before = await purchasingEvidence(f);
        expect(
          (await f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: body,
            expected: 409,
          )).body['code'],
          'article_unit_changed',
        );
        await purchasingUnchanged(f, before);
        final saved =
            (await f.call(
                  'PUT',
                  '$purchasingOrders/${d['id']}',
                  body: draftSave(d, [
                    {...retainedLine(line), 'quantity': '12'},
                  ]),
                )).body['order']
                as Map;
        expect(saved['lines'][0]['unit'], line['unit']);
        final current = (await f.call('GET', '/articles/${a.id}')).body;
        final reselected =
            (await f.call(
                  'PUT',
                  '$purchasingOrders/${d['id']}',
                  body: draftSave(saved, [
                    purchasingLine(
                      current,
                      id: line['id'] as String,
                      quantity: '12',
                    ),
                  ]),
                )).body['order']
                as Map;
        expect(reselected['lines'][0]['unit'], 'bag');
        await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/issue',
          body: {...body, 'expectedVersion': reselected['version']},
        );
      });
    },
  );
  test(
    'reference reservations, duplicates, zero-line issue, no-change and reusable failed UUID',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f), d = await draft(f, s, reference: 'Case-Ä');
        final empty = {'operationId': newUuid(), 'expectedVersion': 1},
            before = await purchasingEvidence(f);
        expect(
          (await f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: empty,
            expected: 422,
          )).body['code'],
          'order_not_issuable',
        );
        expect(
          (await f.call(
            'PUT',
            '$purchasingOrders/${d['id']}',
            body: draftSave(d, []),
            expected: 409,
          )).body['code'],
          'no_change',
        );
        expect(
          (await f.call(
            'PUT',
            '/purchasing/suppliers/${s['id']}',
            body: {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'name': s['name'],
              'orderingReference': null,
            },
            expected: 409,
          )).body['code'],
          'no_change',
        );
        await purchasingUnchanged(f, before);
        await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/cancel',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'Cancelled',
          },
        );
        expect(
          (await f.call(
            'POST',
            purchasingOrders,
            expected: 409,
            body: {
              'id': newUuid(),
              'operationId': newUuid(),
              'reference': 'cASE-Ä',
              'supplierId': s['id'],
              'expectedSupplierVersion': 1,
            },
          )).body['code'],
          'order_reference_conflict',
        );
        final p = await populated(f);
        final l = p['lines'][0] as Map;
        expect(
          (await f.call(
            'PUT',
            '$purchasingOrders/${p['id']}',
            body: draftSave(p, [
              retainedLine(l),
              {...retainedLine(l), 'id': newUuid()},
            ]),
            expected: 400,
          )).body['code'],
          'invalid_request',
        );
      });
    },
  );
  test(
    'current roles, configured Location, foreign resources, strict JSON/media/queries and cursor denial',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f), d = await populated(f, s: s);
        for (final role in ['employee', 'viewer', 'auditor']) {
          final username = await f.account('po_$role', role: role),
              token = await f.login(username);
          for (final route in [
            '/purchasing/suppliers',
            '/purchasing/suppliers/${s['id']}',
            '/purchasing/suppliers/${s['id']}/history',
            purchasingOrders,
            '$purchasingOrders/${d['id']}',
            '$purchasingOrders/${d['id']}/history',
          ]) {
            await f.call('GET', route, token: token, expected: 403);
          }
        }
        final other = await f.createLocation('Other registered Location');
        await f.call(
          'POST',
          '/users',
          expected: 201,
          body: {
            'id': newUuid(),
            'username': 'other_admin',
            'password': merchandisingTestPassword,
            'locationId': other,
            'role': 'admin',
          },
        );
        final token = await f.login('other_admin');
        await f.call(
          'GET',
          '$purchasingOrders/${d['id']}',
          token: token,
          expected: 403,
        );
        await f.call(
          'GET',
          '/purchasing/locations/$other/orders/${d['id']}',
          expected: 403,
        );
        await f.call('GET', '$purchasingOrders/${newUuid()}', expected: 404);
        await f.call(
          'POST',
          purchasingOrders,
          expected: 422,
          body: {
            'id': newUuid(),
            'operationId': newUuid(),
            'reference': 'foreign',
            'supplierId': newUuid(),
            'expectedSupplierVersion': 1,
          },
        );
        for (final raw in [
          '{"id":"$other","id":"${s['id']}"}',
          '{"name":"a","na\\u006de":"b"}',
          '{"unexpected":true}',
        ]) {
          await f.call(
            'POST',
            '/purchasing/suppliers',
            raw: raw,
            expected: 400,
          );
        }
        await f.call(
          'POST',
          '/purchasing/suppliers',
          raw: '{}',
          jsonContentType: false,
          expected: 415,
        );
        await f.call(
          'POST',
          '/purchasing/suppliers',
          raw: 'x' * 16385,
          expected: 413,
        );
        await f.call(
          'GET',
          '$purchasingOrders?status=draft&status=issued',
          expected: 400,
        );
        await f.call('GET', '$purchasingOrders?unknown=x', expected: 400);
        final cursor = base64Url
            .encode(
              utf8.encode(
                jsonEncode({
                  'endpoint': 'orders',
                  'company': newUuid(),
                  'location': merchandisingTestLocation,
                  'status': null,
                  'supplier': null,
                  'q': '',
                  'last': d['id'],
                }),
              ),
            )
            .replaceAll('=', '');
        expect(
          (await f.call(
            'GET',
            '$purchasingOrders?after=$cursor',
            expected: 400,
          )).body['code'],
          'invalid_cursor',
        );
      });
    },
  );
  test(
    'runtime grants and terminal/receipt/line invariants resist direct SQL',
    () async {
      await withMerchandisingFixture((f) async {
        final d = await populated(f), id = d['id'];
        await f.call(
          'POST',
          '$purchasingOrders/$id/issue',
          body: {'operationId': newUuid(), 'expectedVersion': d['version']},
        );
        final before = await purchasingEvidence(f);
        for (final sql in [
          'DELETE FROM purchasing_orders',
          'DELETE FROM purchasing_suppliers',
          'TRUNCATE purchasing_commands',
          'UPDATE purchasing_commands SET kind=kind',
          'UPDATE purchasing_order_lines SET quantity_scaled=1',
          'DELETE FROM purchasing_order_lines',
          "UPDATE purchasing_orders SET reference='forged',version=version+1 WHERE id='$id'",
          "UPDATE purchasing_orders SET status='draft',version=version+1 WHERE id='$id'",
        ]) {
          final qualified = sql.replaceAllMapped(
            RegExp(r'\b(purchasing_[a-z_]+)\b'),
            (m) => '"${f.schema}".${m[0]}',
          );
          await expectLater(
            f.pool.runTx((tx) => tx.execute(qualified)),
            throwsA(isA<ServerException>()),
          );
          await purchasingUnchanged(f, before);
        }
      });
    },
  );
  for (final firstIssue in [false, true]) {
    test(
      'observed save/issue queue both orders: issue first $firstIssue',
      () async {
        await withMerchandisingFixture((f) async {
          final d = await populated(f);
          final save = draftSave(d, [
            {...retainedLine(d['lines'][0] as Map), 'quantity': '12'},
          ]);
          Future<MerchandisingReply> s() => f.call(
            'PUT',
            '$purchasingOrders/${d['id']}',
            body: save,
            expected: null,
          );
          Future<MerchandisingReply> i() => f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: {'operationId': newUuid(), 'expectedVersion': d['version']},
            expected: null,
          );
          final r = await orderedPurchasing(
            f,
            firstIssue ? i : s,
            firstIssue ? s : i,
          );
          expect(r.map((x) => x.status), [200, 409]);
          final current = (await f.call(
            'GET',
            '$purchasingOrders/${d['id']}',
          )).body;
          expect(
            current['lines'][0]['quantity'],
            firstIssue ? '2.500' : '12.000',
          );
        });
      },
    );
  }
  for (final table in [
    'purchasing_suppliers',
    'purchasing_orders',
    'purchasing_order_lines',
    'purchasing_commands',
    'audit_entries',
  ]) {
    test(
      'injected $table insert failure rolls back all Purchasing effects and leaves UUID reusable',
      () async {
        await withMerchandisingFixture((f) async {
          Map<String, dynamic>? d;
          if (table != 'purchasing_suppliers') {
            d = await draft(f, await supplier(f));
          }
          final a = table == 'purchasing_order_lines'
              ? await f.stockArticle(sku: 'FAULT')
              : null;
          final body = table == 'purchasing_suppliers'
              ? {
                  'id': newUuid(),
                  'operationId': newUuid(),
                  'name': 'Fault',
                  'orderingReference': null,
                }
              : table == 'purchasing_orders'
              ? {
                  'id': newUuid(),
                  'operationId': newUuid(),
                  'reference': 'Fault',
                  'supplierId': d!['supplier']['id'],
                  'expectedSupplierVersion': 1,
                }
              : draftSave(d!, a == null ? [] : [purchasingLine(a.toJson())]);
          if (table == 'purchasing_commands' || table == 'audit_entries') {
            body['reference'] = 'Changed';
          }
          final route = table == 'purchasing_suppliers'
              ? '/purchasing/suppliers'
              : table == 'purchasing_orders'
              ? purchasingOrders
              : '$purchasingOrders/${d!['id']}';
          final method =
              table == 'purchasing_suppliers' || table == 'purchasing_orders'
              ? 'POST'
              : 'PUT';
          final before = await purchasingEvidence(f);
          await f.owner.execute(
            'CREATE FUNCTION "${f.schema}".po_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'injected\' USING ERRCODE=\'23514\'; END \$\$; CREATE TRIGGER po_fault BEFORE INSERT ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".po_fault()',
            queryMode: QueryMode.simple,
          );
          await f.call(method, route, body: body, expected: 500);
          await purchasingUnchanged(f, before);
          await f.owner.execute(
            'DROP TRIGGER po_fault ON "${f.schema}".$table',
          );
          await f.call(
            method,
            route,
            body: body,
            expected: method == 'POST' ? 201 : 200,
          );
        });
      },
    );
  }
  test(
    'populated 0023 upgrade late failure preserves full catalog, data and grants',
    () async {
      await withMerchandisingFixture((f) async {
        final article = await f.stockArticle(sku: 'LEGACY');
        final before = await f.owner.execute(
          'SELECT to_jsonb(a) FROM "${f.schema}".articles a',
        );
        final temporary = await Directory.systemTemp.createTemp(
          'storeos_po_migrations_',
        );
        try {
          for (final file in Directory(
            'migrations',
          ).listSync().whereType<File>()) {
            await file.copy('${temporary.path}/${file.uri.pathSegments.last}');
          }
          await File(
            '${temporary.path}/0024_bounded_purchase_orders.sql',
          ).writeAsString("\nSELECT 1/0;\n", mode: FileMode.append);
          await expectLater(
            MigrationRunner(
              connection: f.owner,
              migrationsDirectory: temporary,
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            throwsA(isA<ServerException>()),
          );
          expect(
            (await f.owner.execute(
              "SELECT to_regclass('\"${f.schema}\".purchasing_orders')",
            )).single.first,
            isNull,
          );
          expect(
            (await f.owner.execute(
              'SELECT to_jsonb(a) FROM "${f.schema}".articles a',
            )).map((r) => r.first),
            before.map((r) => r.first),
          );
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply();
          expect(
            (await f.call('GET', '/articles/${article.id}')).body['id'],
            article.id,
          );
          await populated(f);
        } finally {
          await temporary.delete(recursive: true);
        }
      }, legacyBefore: '0024_bounded_purchase_orders.sql');
    },
  );
}
