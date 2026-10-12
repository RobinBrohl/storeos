import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_delivery_test.dart'
    show issued, declareBody, changeBody, deliveryEvidence;
import 'preparation_assignment_upgrade_recovery_test.dart'
    show catalog, priorEvidence;

void main() {
  if (Platform.environment['STOREOS_TEST_DATABASE'] == null) {
    test(
      'isolated delivery safety',
      () {},
      skip: 'Explicit disposable database required.',
    );
    return;
  }
  test(
    'accepted delivery operation rejects changed authorized actor, kind and scoped Order without disclosure',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            other = await issued(f),
            root = '$purchasingOrders/${o['id']}',
            body = declareBody(o);
        final a =
            (await f.call(
                  'POST',
                  '$root/deliveries',
                  body: body,
                  expected: 201,
                )).body['delivery']
                as Map;
        final token = await f.login(
          await f.account('delivery_replay_other_admin', role: 'admin'),
        );
        final before = await deliveryEvidence(f);
        for (final reply in [
          await f.call(
            'POST',
            '$root/deliveries',
            body: body,
            token: token,
            expected: 409,
          ),
          await f.call(
            'POST',
            '$root/deliveries/${a['deliveryId']}/correct',
            body: {...changeBody(o, a, 1), 'operationId': body['operationId']},
            expected: 409,
          ),
          await f.call(
            'POST',
            '$purchasingOrders/${other['id']}/deliveries',
            body: body,
            expected: 409,
          ),
        ]) {
          expect(reply.body['code'], 'operation_conflict');
          expect(reply.body.containsKey('delivery'), false);
        }
        expect(await deliveryEvidence(f), before);
      });
    },
  );
  test(
    'approved plugin credentials cannot reach any delivery endpoint; draft cancellation has no issued ledger',
    () async {
      await withMerchandisingFixture((f) async {
        const plugin = 'delivery.denied-plugin';
        await f.call(
          'POST',
          '/plugins',
          expected: 201,
          body: {
            'manifest': {
              'id': plugin,
              'name': 'Delivery denied plugin',
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
                  '/plugins/$plugin/approve',
                  body: {
                    'expectedVersion': 1,
                    'locationId': merchandisingTestLocation,
                    'permissions': ['organization.read'],
                    'subscriptions': <String>[],
                  },
                )).body['token']
                as String;
        await f.call(
          'GET',
          '/api/plugin/v1/organization',
          platform: false,
          token: token,
        );
        final o = await issued(f),
            root = '$purchasingOrders/${o['id']}',
            body = declareBody(o),
            a =
                (await f.call(
                      'POST',
                      '$root/deliveries',
                      body: body,
                      expected: 201,
                    )).body['delivery']
                    as Map;
        final before = await deliveryEvidence(f);
        for (final route in [
          '/purchasing/locations/$merchandisingTestLocation/delivery-register',
          '$root/delivery-summary',
          '$root/deliveries',
          '$root/deliveries/${a['deliveryId']}',
          '$root/deliveries/${a['deliveryId']}/history',
        ]) {
          await f.call('GET', route, token: token, expected: 401);
        }
        await f.call(
          'POST',
          '$root/deliveries',
          body: body,
          token: token,
          expected: 401,
        );
        await f.call(
          'POST',
          '$root/deliveries/${a['deliveryId']}/correct',
          body: changeBody(o, a, 1),
          token: token,
          expected: 401,
        );
        await f.call(
          'POST',
          '$root/deliveries/${a['deliveryId']}/void',
          body: changeBody(o, a, 1, voided: true),
          token: token,
          expected: 401,
        );
        expect(await deliveryEvidence(f), before);
        final d = await draft(f, await supplier(f)),
            draftRoot = '$purchasingOrders/${d['id']}';
        await f.call(
          'POST',
          '$draftRoot/deliveries',
          body: declareBody({...d, 'lines': o['lines']}),
          expected: 409,
        );
        await f.call(
          'POST',
          '$draftRoot/cancel',
          body: {
            'operationId': newUuid(),
            'expectedVersion': d['version'],
            'reason': 'Before issue',
          },
        );
        final summary = (await f.call(
          'GET',
          '$draftRoot/delivery-summary',
        )).body;
        expect(summary['trackingAtClosure'], 'not_issued');
        expect(summary['terminalSnapshot'], null);
        expect(summary['summary']['ledgerVersion'], 0);
      });
    },
  );
  test(
    'roles, configured Location, foreign Order and Delivery, reference reservation and every replay binding',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            root = '$purchasingOrders/${o['id']}',
            body = declareBody(o, reference: 'Case-Ä');
        final accepted = (await f.call(
              'POST',
              '$root/deliveries',
              body: body,
              expected: 201,
            )).body,
            delivery = accepted['delivery'] as Map;
        for (final role in ['employee', 'viewer', 'auditor']) {
          final token = await f.login(
            await f.account('delivery_$role', role: role),
          );
          final deniedBefore = await deliveryEvidence(f);
          for (final suffix in [
            '/delivery-summary',
            '/deliveries',
            '/deliveries/${delivery['deliveryId']}',
            '/deliveries/${delivery['deliveryId']}/history',
          ]) {
            await f.call('GET', '$root$suffix', token: token, expected: 403);
          }
          await f.call(
            'POST',
            '$root/deliveries',
            token: token,
            body: body,
            expected: 403,
          );
          await f.call(
            'POST',
            '$root/deliveries/${delivery['deliveryId']}/correct',
            token: token,
            body: changeBody(o, delivery, 1),
            expected: 403,
          );
          expect(await deliveryEvidence(f), deniedBefore);
        }
        final other = await f.createLocation(
          'Registered foreign execution Location',
        );
        final before = await deliveryEvidence(f);
        await f.call(
          'GET',
          '${root.replaceFirst(merchandisingTestLocation, other)}/delivery-summary',
          expected: 403,
        );
        await f.call(
          'GET',
          '$purchasingOrders/${newUuid()}/delivery-summary',
          expected: 404,
        );
        await f.call('GET', '$root/deliveries/${newUuid()}', expected: 404);
        for (final entry in <String, dynamic>{
          'expectedOrderVersion': 1,
          'expectedLedgerVersion': 2,
          'localReference': 'Other',
          'reason': 'Changed',
          'deliveryId': newUuid(),
          'lines': [
            {'orderLineId': o['lines'][0]['id'], 'quantity': '4'},
          ],
        }.entries) {
          final r = await f.call(
            'POST',
            '$root/deliveries',
            body: {...body, entry.key: entry.value},
            expected: 409,
          );
          expect(r.body['code'], 'operation_conflict');
          expect(r.body.containsKey('delivery'), false);
        }
        await f.call(
          'POST',
          '$root/deliveries',
          body: declareBody(o, ledger: 1, reference: 'cASE-Ä'),
          expected: 409,
        );
        expect(await deliveryEvidence(f), before);
        await f.call(
          'POST',
          '$root/deliveries/${delivery['deliveryId']}/correct',
          body: changeBody(o, delivery, 1, quantity: '5'),
          expected: 409,
        );
        await f.call(
          'POST',
          '$root/deliveries/${delivery['deliveryId']}/void',
          body: changeBody(o, delivery, 1, voided: true),
        );
        final voided = (await f.call(
          'GET',
          '$root/deliveries/${delivery['deliveryId']}',
        )).body;
        await f.call(
          'POST',
          '$root/deliveries/${delivery['deliveryId']}/void',
          body: changeBody(o, voided, 2, voided: true),
          expected: 409,
        );
      });
    },
  );
  test(
    '52 delivery identities: stable bounded pages, filter and endpoint bound cursors, literal references',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f), root = '$purchasingOrders/${o['id']}';
        for (var i = 0; i < 52; i++) {
          await f.call(
            'POST',
            '$root/deliveries',
            body: declareBody(
              o,
              ledger: i,
              quantity: '0.001',
              reference: '<script>delivery-$i',
            ),
            expected: 201,
          );
        }
        final first = (await f.call('GET', '$root/deliveries')).body,
            cursor = first['nextCursor'] as String;
        final second = (await f.call(
          'GET',
          '$root/deliveries?after=$cursor',
        )).body;
        final all = [...first['items'] as List, ...second['items'] as List];
        expect(first['items'], hasLength(50));
        expect(second['items'], hasLength(2));
        expect(second['nextCursor'], null);
        expect(all.map((d) => d['deliveryId']).toSet(), hasLength(52));
        await f.call(
          'GET',
          '/purchasing/locations/$merchandisingTestLocation/delivery-register?after=$cursor',
          expected: 400,
        );
        await f.call(
          'GET',
          '$root/deliveries/${all[0]['deliveryId']}/history?after=$cursor',
          expected: 400,
        );
        await f.call(
          'GET',
          '$root/deliveries?after=${'a' * 2049}',
          expected: 400,
        );
        expect(
          (await f.call(
            'GET',
            '$root/delivery-summary',
          )).body['summary']['lines'][0]['effectiveDelivered'],
          '0.052',
        );
      });
    },
  );
  test(
    '50 frozen lines, full replacement removes omitted lines, exact aggregate ceiling',
    () async {
      await withMerchandisingFixture((f) async {
        final s = await supplier(f),
            draftOrder = await draft(f, s),
            lines = <Map<String, dynamic>>[];
        for (var i = 0; i < 50; i++) {
          lines.add(
            purchasingLine(
              (await f.stockArticle(
                sku: 'MAX-$i',
                unit: i.isEven ? 'kg' : 'piece',
              )).toJson(),
              quantity: '1',
            ),
          );
        }
        final saved =
            (await f.call(
                  'PUT',
                  '$purchasingOrders/${draftOrder['id']}',
                  body: draftSave(draftOrder, lines),
                )).body['order']
                as Map;
        final o =
            (await f.call(
                  'POST',
                  '$purchasingOrders/${saved['id']}/issue',
                  body: {
                    'operationId': newUuid(),
                    'expectedVersion': saved['version'],
                  },
                )).body['order']
                as Map;
        final root = '$purchasingOrders/${o['id']}',
            body = {
              ...declareBody(o),
              'lines': [
                for (final l in o['lines'] as List)
                  {'orderLineId': l['id'], 'quantity': '1'},
              ],
            };
        final a =
            (await f.call(
                  'POST',
                  '$root/deliveries',
                  body: body,
                  expected: 201,
                )).body['delivery']
                as Map;
        expect(a['lines'], hasLength(50));
        await f.call(
          'POST',
          '$root/deliveries/${a['deliveryId']}/correct',
          body: changeBody(o, a, 1, quantity: '999999999999.999'),
        );
        final current = (await f.call(
          'GET',
          '$root/delivery-summary',
        )).body['summary'];
        expect(current['lines'][0]['effectiveDelivered'], '999999999999.999');
        expect(current['lines'][1]['effectiveDelivered'], '0.000');
        final r = await f.call(
          'POST',
          '$root/deliveries',
          body: declareBody(
            o,
            ledger: 2,
            quantity: '0.001',
            reason: 'Exceeds numeric bounds',
          ),
          expected: 409,
        );
        expect(r.body['code'], 'quantity_limit');
      });
    },
  );
  for (final replay in [false, true]) {
    for (final revokeFirst in [false, true]) {
      test(
        'observed revocation vs ${replay ? 'replay' : 'write'}, revoke first $revokeFirst',
        () async {
          await withMerchandisingFixture((f) async {
            final o = await issued(f), root = '$purchasingOrders/${o['id']}';
            final token = await f.login(
              await f.account('delivery_actor', role: 'admin'),
            );
            final users = (await f.call('GET', '/users')).body['users'] as List,
                actor =
                    users.firstWhere((u) => u['username'] == 'delivery_actor')
                        as Map;
            final body = declareBody(o);
            if (replay) {
              await f.call(
                'POST',
                '$root/deliveries',
                token: token,
                body: body,
                expected: 201,
              );
            }
            Future<MerchandisingReply> revoke() => f.call(
              'POST',
              '/users/${actor['id']}',
              body: {
                'expectedVersion': actor['version'],
                'role': 'viewer',
                'isActive': false,
              },
            );
            Future<MerchandisingReply> write() => f.call(
              'POST',
              '$root/deliveries',
              token: token,
              body: body,
              expected: null,
            );
            final r = await orderedPurchasing(
              f,
              revokeFirst ? revoke : write,
              revokeFirst ? write : revoke,
            );
            expect(r[revokeFirst ? 1 : 0].status, revokeFirst ? 401 : 201);
          });
        },
      );
    }
  }
  test(
    'populated 0025 upgrade preserves byte-identical old evidence; late rollback, forward, no-op and legacy terminal distinction',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f), root = '$purchasingOrders/${o['id']}';
        await f.call(
          'POST',
          '$root/close',
          body: {
            'operationId': newUuid(),
            'expectedVersion': o['version'],
            'reason': 'Before tracking',
          },
        );
        final before = await priorEvidence(f), schemaBefore = await catalog(f);
        final temporary = await Directory.systemTemp.createTemp(
          'storeos_p414_migrations_',
        );
        try {
          for (final file in Directory(
            'migrations',
          ).listSync().whereType<File>()) {
            await file.copy('${temporary.path}/${file.uri.pathSegments.last}');
          }
          await File(
            '${temporary.path}/0026_purchase_order_delivery_evidence.sql',
          ).writeAsString('\nSELECT 1/0;\n', mode: FileMode.append);
          await expectLater(
            MigrationRunner(
              connection: f.owner,
              migrationsDirectory: temporary,
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            throwsA(isA<ServerException>()),
          );
          expect(await priorEvidence(f), before);
          expect(await catalog(f), schemaBefore);
          expect(
            await MigrationRunner(
              connection: f.owner,
              migrationsDirectory: Directory('migrations'),
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            ['0026_purchase_order_delivery_evidence'],
          );
          expect(await priorEvidence(f), before);
          expect(
            await MigrationRunner(
              connection: f.owner,
              migrationsDirectory: Directory('migrations'),
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            isEmpty,
          );
          final summary = (await f.call('GET', '$root/delivery-summary')).body;
          expect(summary['terminalSnapshot'], null);
          expect(summary['trackingAtClosure'], 'unavailable');
          final next = await issued(f);
          await f.call(
            'POST',
            '$purchasingOrders/${next['id']}/deliveries',
            body: declareBody(next),
            expected: 201,
          );
        } finally {
          await temporary.delete(recursive: true);
        }
      }, legacyBefore: '0026_purchase_order_delivery_evidence.sql');
    },
  );
}
