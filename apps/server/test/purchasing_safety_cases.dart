import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/purchasing/purchasing_service.dart';
import '../tool/purchasing_acceptance.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';

void purchasingSafetyCases() {
  test(
    'foreign Company principal cannot read, write or disclose committed receipts',
    () async {
      await withMerchandisingFixture((f) async {
        final body = {
          'id': newUuid(),
          'operationId': newUuid(),
          'name': 'Company Supplier',
          'orderingReference': null,
        };
        await f.call(
          'POST',
          '/purchasing/suppliers',
          body: body,
          expected: 201,
        );
        final p = f.adminPrincipal;
        final foreign = SessionPrincipal(
          id: p.id,
          username: p.username,
          companyId: newUuid(),
          locationId: p.locationId,
          tokenHash: p.tokenHash,
        );
        final service = PurchasingService(f.database),
            before = await purchasingEvidence(f);
        final forbidden = isA<PlatformFailure>().having(
          (e) => e.status,
          'status',
          403,
        );
        await expectLater(
          service.detail(foreign, null, body['id']!, supplier: true),
          throwsA(forbidden),
        );
        await expectLater(
          service.command(foreign, null, null, 'supplier_create', body),
          throwsA(forbidden),
        );
        await expectLater(
          service.command(foreign, null, null, 'supplier_create', {
            ...body,
            'operationId': newUuid(),
            'id': newUuid(),
          }),
          throwsA(forbidden),
        );
        await purchasingUnchanged(f, before);
      });
    },
  );
  for (final action in ['issue', 'cancel', 'close']) {
    for (final stage in ['aggregate', 'receipt', 'audit', 'deferred']) {
      test(
        '$action $stage failure preserves all evidence and exact failed UUID is reusable',
        () async {
          await withMerchandisingFixture((f) async {
            var d = await populated(f);
            if (action == 'close') {
              d =
                  (await f.call(
                        'POST',
                        '$purchasingOrders/${d['id']}/issue',
                        body: {
                          'operationId': newUuid(),
                          'expectedVersion': d['version'],
                        },
                      )).body['order']
                      as Map<String, dynamic>;
            }
            final body = {
                  'operationId': newUuid(),
                  'expectedVersion': d['version'],
                  if (action != 'issue') 'reason': 'Administrative reason',
                },
                before = await purchasingEvidence(f),
                table = stage == 'receipt'
                    ? 'purchasing_commands'
                    : stage == 'audit'
                    ? 'audit_entries'
                    : 'purchasing_orders';
            await f.owner.execute(
              'CREATE FUNCTION "${f.schema}".p412_transition_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Injected transition failure\' USING ERRCODE=\'23514\'; END \$\$; CREATE ${stage == 'deferred' ? 'CONSTRAINT ' : ''}TRIGGER p412_transition_fault ${stage == 'deferred'
                  ? 'AFTER UPDATE'
                  : stage == 'aggregate'
                  ? 'BEFORE UPDATE'
                  : 'BEFORE INSERT'} ON "${f.schema}".$table ${stage == 'deferred' ? 'DEFERRABLE INITIALLY DEFERRED ' : ''}FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p412_transition_fault()',
              queryMode: QueryMode.simple,
            );
            final failed = await f.call(
              'POST',
              '$purchasingOrders/${d['id']}/$action',
              body: body,
              expected: 500,
            );
            expect(failed.body['code'], 'internal_error');
            expect(failed.body.toString(), isNot(contains('Injected')));
            await purchasingUnchanged(f, before);
            await f.owner.execute(
              'DROP TRIGGER p412_transition_fault ON "${f.schema}".$table',
            );
            await f.call(
              'POST',
              '$purchasingOrders/${d['id']}/$action',
              body: body,
            );
          });
        },
      );
    }
  }
  test(
    'draft line deletion and aggregate update without complete matching receipt roll back at commit',
    () async {
      await withMerchandisingFixture((f) async {
        final d = await populated(f), before = await purchasingEvidence(f);
        for (final sql in [
          'DELETE FROM "${f.schema}".purchasing_order_lines WHERE order_id=\'${d['id']}\'',
          "UPDATE \"${f.schema}\".purchasing_orders SET reference='Forged',version=version+1,last_operation_id='${newUuid()}',last_kind='order_save' WHERE id='${d['id']}'",
        ]) {
          await expectLater(
            f.pool.runTx((tx) => tx.execute(sql)),
            throwsA(isA<ServerException>()),
          );
          await purchasingUnchanged(f, before);
        }
      });
    },
  );
  test(
    'all eight durable kinds replay original accepted evidence after restart and terminal changes; every binding conflicts',
    () async {
      await withMerchandisingFixture((f) async {
        await f.stockArticle(sku: 'REPLAY');
        final records = await seedPurchasing(
          (method, route, body, status) async => (await f.call(
            method,
            route.substring('/api/v1/platform'.length),
            body: body,
            expected: status,
          )).body,
          merchandisingTestLocation,
        );
        await f.restart();
        await f.account('other_replay_actor', role: 'admin');
        final other = await f.login('other_replay_actor'),
            before = await purchasingEvidence(f);
        expect(records.map((r) => r['kind']).toSet(), hasLength(8));
        for (final r in records) {
          final body = Map<String, dynamic>.from(r['body'] as Map);
          final route = r['route'] as String,
              method = r['method'] as String,
              status = (r['kind'] as String).endsWith('_create') ? 201 : 200;
          expect(
            (await f.call(method, route, body: body, expected: status)).body,
            {...r['result'] as Map, 'replayed': true},
          );
          expect(
            (await f.call(
              method,
              route,
              token: other,
              body: body,
              expected: 409,
            )).body['code'],
            'operation_conflict',
          );
          final changed = {...body};
          if (changed.containsKey('name')) {
            changed['name'] = 'Changed binding';
          } else if (changed.containsKey('expectedVersion')) {
            changed['expectedVersion'] =
                (changed['expectedVersion'] as int) + 1;
          } else {
            changed['reference'] = 'Changed binding';
          }
          expect(
            (await f.call(
              method,
              route,
              body: changed,
              expected: 409,
            )).body['code'],
            'operation_conflict',
          );
        }
        await purchasingUnchanged(f, before);
        final first = records.first;
        expect(
          (await f.call(
            'POST',
            '/purchasing/suppliers',
            expected: 409,
            body: {
              'id': newUuid(),
              'operationId': first['body']['operationId'],
              'name': 'Different target',
              'orderingReference': null,
            },
          )).body['code'],
          'operation_conflict',
        );
        await purchasingUnchanged(f, before);
      });
    },
  );
  test(
    'all 15 routes authenticate sessions, deny plugin tokens and reject forged fields before any effects',
    () async {
      await withMerchandisingFixture((f) async {
        const id = 'purchasing.denied-plugin';
        await f.call(
          'POST',
          '/plugins',
          expected: 201,
          body: {
            'manifest': {
              'id': id,
              'name': 'Denied Purchasing plugin',
              'version': '1.0.0',
              'vendor': 'StoreOS Acceptance',
              'coreApiVersion': 1,
              'capabilities': ['organization.read'],
              'permissions': ['organization.read'],
              'subscriptions': <String>[],
              'configurationSchema': {
                'type': 'object',
                'properties': <String, dynamic>{},
                'additionalProperties': false,
              },
            },
          },
        );
        final token =
            (await f.call(
                  'POST',
                  '/plugins/$id/approve',
                  body: {
                    'expectedVersion': 1,
                    'locationId': merchandisingTestLocation,
                    'permissions': ['organization.read'],
                    'subscriptions': <String>[],
                  },
                )).body['token']
                as String;
        final s = await supplier(f),
            d = await draft(f, s),
            before = await purchasingEvidence(f);
        final routes = [
          ('GET', '/purchasing/suppliers'),
          ('POST', '/purchasing/suppliers'),
          ('GET', '/purchasing/suppliers/${s['id']}'),
          ('PUT', '/purchasing/suppliers/${s['id']}'),
          ('POST', '/purchasing/suppliers/${s['id']}/retire'),
          ('GET', '/purchasing/suppliers/${s['id']}/history'),
          (
            'GET',
            '/purchasing/locations/$merchandisingTestLocation/article-selections',
          ),
          ('GET', purchasingOrders),
          ('POST', purchasingOrders),
          ('GET', '$purchasingOrders/${d['id']}'),
          ('PUT', '$purchasingOrders/${d['id']}'),
          for (final action in ['issue', 'cancel', 'close'])
            ('POST', '$purchasingOrders/${d['id']}/$action'),
          ('GET', '$purchasingOrders/${d['id']}/history'),
        ];
        expect(routes, hasLength(15));
        for (final r in routes) {
          for (final credential in ['', token]) {
            await f.call(
              r.$1,
              r.$2,
              token: credential,
              body: r.$1 == 'GET' ? null : {},
              expected: 401,
            );
          }
        }
        for (final field in [
          'companyId',
          'locationId',
          'actorId',
          'employeeId',
          'status',
          'supplierName',
          'createdAt',
        ]) {
          await f.call(
            'POST',
            purchasingOrders,
            expected: 400,
            body: {
              'id': newUuid(),
              'operationId': newUuid(),
              'reference': 'Forged',
              'supplierId': s['id'],
              'expectedSupplierVersion': 1,
              field: 'forged',
            },
          );
        }
        await purchasingUnchanged(f, before);
      });
    },
  );
  test(
    'inactive/missing/stale Supplier and Article, absent assortment, reselection and reason bounds reject atomically',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f),
            d = await draft(f, s),
            a = await f.article({
              'id': newUuid(),
              'sku': 'UNASSORTED',
              'name': 'Unassorted',
              'unit': 'kg',
              'barcode': null,
              'description': null,
            });
        final before = await purchasingEvidence(f);
        for (final article in [
          a.toJson(),
          {'id': newUuid(), 'version': 1},
        ]) {
          final r = await f.call(
            'PUT',
            '$purchasingOrders/${d['id']}',
            body: draftSave(d, [purchasingLine(article)]),
            expected: 422,
          );
          expect(
            r.body['code'],
            article['id'] == a.id
                ? 'not_in_assortment'
                : 'article_selection_unavailable',
          );
        }
        await f.call(
          'PUT',
          '$purchasingOrders/${d['id']}',
          body: draftSave(d, [purchasingLine(a.toJson(), reselect: false)]),
          expected: 422,
        );
        await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/cancel',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': '😀' * 501,
          },
          expected: 400,
        );
        await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/close',
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'close',
          },
          expected: 409,
        );
        await f.call(
          'POST',
          purchasingOrders,
          body: {
            'id': newUuid(),
            'operationId': newUuid(),
            'reference': 'Stale',
            'supplierId': s['id'],
            'expectedSupplierVersion': 2,
          },
          expected: 409,
        );
        await purchasingUnchanged(f, before);
        await f.assortment(a.id);
        await f.call(
          'POST',
          '/articles/${a.id}/deactivate',
          body: {'expectedVersion': 1},
        );
        final beforeInactive = await purchasingEvidence(f);
        await f.call(
          'PUT',
          '$purchasingOrders/${d['id']}',
          body: draftSave(d, [purchasingLine(a.toJson())]),
          expected: 422,
        );
        await purchasingUnchanged(f, beforeInactive);
        await f.call(
          'POST',
          '/purchasing/suppliers/${s['id']}/retire',
          body: {'operationId': newUuid(), 'expectedVersion': 1},
        );
        final retired = await purchasingEvidence(f);
        await f.call(
          'POST',
          purchasingOrders,
          body: {
            'id': newUuid(),
            'operationId': newUuid(),
            'reference': 'Retired',
            'supplierId': s['id'],
            'expectedSupplierVersion': 2,
          },
          expected: 422,
        );
        await purchasingUnchanged(f, retired);
      });
    },
  );
  test(
    '50 maximum Unicode snapshots agree in Dart/SQL and issue; over-50 replacement leaves original intact',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f, name: '😀' * 200, reference: '😀' * 64),
            d = await draft(f, s, reference: '😀' * 64),
            lines = <Map<String, dynamic>>[];
        for (var n = 0; n < 50; n++) {
          final a = await f.stockArticle(
            sku: '$n${'😀' * 60}',
            name: '😀' * 120,
            unit: '😀' * 32,
          );
          lines.add(purchasingLine(a.toJson(), quantity: '999999999999.999'));
        }
        final saved =
            (await f.call(
                  'PUT',
                  '$purchasingOrders/${d['id']}',
                  body: draftSave(d, lines),
                )).body['order']
                as Map<String, dynamic>;
        expect(saved['lines'], hasLength(50));
        expect(saved['lines'].last['position'], 50);
        final sql = await f.owner.execute(
          "SELECT octet_length(o.id::text)+octet_length(o.company_id::text)+octet_length(o.location_id::text)+octet_length(reference)+octet_length(supplier_id::text)+octet_length(supplier_version::text)+octet_length(supplier_name)+octet_length(coalesce(supplier_reference,''))+(SELECT sum(octet_length(id::text)+octet_length(position::text)+octet_length(article_id::text)+octet_length(article_version::text)+octet_length(sku)+octet_length(name)+octet_length(unit)+octet_length((quantity_scaled/1000)::text||'.'||lpad((quantity_scaled%1000)::text,3,'0'))) FROM \"${f.schema}\".purchasing_order_lines WHERE order_id=o.id) FROM \"${f.schema}\".purchasing_orders o WHERE id='${d['id']}'",
        );
        expect(sql.single.first, purchasingDocumentSize(saved));
        expect(purchasingDocumentSize(saved), lessThanOrEqualTo(98304));
        final before = await purchasingEvidence(f);
        await f.call(
          'PUT',
          '$purchasingOrders/${d['id']}',
          body: draftSave(saved, [
            ...lines,
            {...lines.first, 'id': newUuid(), 'articleId': newUuid()},
          ]),
          expected: 400,
        );
        await purchasingUnchanged(f, before);
        await f.call(
          'POST',
          '$purchasingOrders/${d['id']}/issue',
          body: {'operationId': newUuid(), 'expectedVersion': saved['version']},
        );
      });
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'filter-before-limit keyset pages and cursor endpoint/filter/resource bindings',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f, name: 'Literal%_\\ 😀');
        for (var n = 0; n < 51; n++) {
          await supplier(f, name: 'Page $n');
          await draft(f, s, reference: 'PAGE-$n');
        }
        final page = (await f.call(
          'GET',
          '$purchasingOrders?status=draft&supplierId=${s['id']}',
        )).body;
        expect(page['items'], hasLength(50));
        final cursor = page['nextCursor'] as String;
        final next = (await f.call(
          'GET',
          '$purchasingOrders?status=draft&supplierId=${s['id']}&after=$cursor',
        )).body;
        expect(next['items'], hasLength(1));
        expect(next['nextCursor'], isNull);
        expect(<Object?>{
          ...(page['items'] as List).map((dynamic x) => x['id']),
          ...(next['items'] as List).map((dynamic x) => x['id']),
        }, hasLength(51));
        await f.call(
          'GET',
          '$purchasingOrders?status=issued&supplierId=${s['id']}&after=$cursor',
          expected: 400,
        );
        await f.call(
          'GET',
          '/purchasing/suppliers?after=$cursor',
          expected: 400,
        );
        await f.call(
          'GET',
          '$purchasingOrders?after=${'x' * 2049}',
          expected: 400,
        );
        final literal = (await f.call(
          'GET',
          '/purchasing/suppliers?q=${Uri.encodeQueryComponent('%_\\')}',
        )).body;
        expect(literal['items'], hasLength(1));
        expect(literal['items'][0]['id'], s['id']);
      });
    },
  );
  for (final stage in [
    'supplier_update',
    'line_delete',
    'order_update',
    'deferred',
    'result_projection',
  ]) {
    test(
      'injected $stage failure rolls back aggregate/receipt/audit and allows exact UUID reuse',
      () async {
        await withMerchandisingFixture((f) async {
          final d = await populated(f),
              s = d['supplier'] as Map,
              body = stage == 'supplier_update'
                  ? {
                      'operationId': newUuid(),
                      'expectedVersion': 1,
                      'name': 'Changed',
                      'orderingReference': null,
                    }
                  : draftSave(d, [
                      {...retainedLine(d['lines'][0] as Map), 'quantity': '12'},
                    ]),
              route = stage == 'supplier_update'
                  ? '/purchasing/suppliers/${s['id']}'
                  : '$purchasingOrders/${d['id']}',
              table = stage == 'supplier_update'
                  ? 'purchasing_suppliers'
                  : stage == 'line_delete'
                  ? 'purchasing_order_lines'
                  : stage == 'result_projection'
                  ? 'purchasing_commands'
                  : 'purchasing_orders';
          final before = await purchasingEvidence(f);
          final code = stage == 'result_projection'
              ? "NEW.result=jsonb_set(NEW.result,'{order,version}','999'::jsonb); RETURN NEW;"
              : "RAISE EXCEPTION 'Injected acceptance failure' USING ERRCODE='23514';";
          await f.owner.execute(
            'CREATE FUNCTION "${f.schema}".p412_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN $code END \$\$; CREATE ${stage == 'deferred' ? 'CONSTRAINT ' : ''}TRIGGER p412_fault ${stage == 'deferred'
                ? 'AFTER UPDATE'
                : stage == 'line_delete'
                ? 'BEFORE DELETE'
                : stage == 'result_projection'
                ? 'BEFORE INSERT'
                : 'BEFORE UPDATE'} ON "${f.schema}".$table ${stage == 'deferred' ? 'DEFERRABLE INITIALLY DEFERRED ' : ''}FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p412_fault()',
            queryMode: QueryMode.simple,
          );
          await f.call('PUT', route, body: body, expected: 500);
          await purchasingUnchanged(f, before);
          await f.owner.execute(
            'DROP TRIGGER p412_fault ON "${f.schema}".$table',
          );
          await f.call('PUT', route, body: body);
        });
      },
    );
  }
}
