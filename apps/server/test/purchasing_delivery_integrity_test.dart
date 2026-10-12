import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_delivery_sql_fixture.dart';
import 'purchasing_delivery_test.dart'
    show issued, declareBody, changeBody, deliveryEvidence;

void main() {
  if (Platform.environment['STOREOS_TEST_DATABASE'] == null) {
    test(
      'isolated delivery integrity',
      () {},
      skip: 'Explicit disposable PostgreSQL required.',
    );
    return;
  }
  test(
    'restricted SQL enforces the cross-table operation namespace in both insertion directions',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            root = '$purchasingOrders/${o['id']}',
            a =
                (await f.call(
                      'POST',
                      '$root/deliveries',
                      body: declareBody(o),
                      expected: 201,
                    )).body['delivery']
                    as Map;
        final old =
            (await f.owner.execute(
                  'SELECT operation_id::text FROM "${f.schema}".purchasing_commands LIMIT 1',
                )).single.first
                as String;
        final namespace = isA<ServerException>().having(
          (e) => e.constraintName,
          'constraint',
          'purchasing_operation_namespace',
        );
        final before = await deliveryEvidence(f);
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              "INSERT INTO \"${f.schema}\".purchasing_delivery_commands SELECT company_id,'$old'::uuid,location_id,order_id,delivery_id,actor_id,kind,expected_order_version,expected_ledger_version,expected_revision,revision,ledger_version,response_status,payload,result,accepted_at FROM \"${f.schema}\".purchasing_delivery_commands WHERE operation_id='${a['operationId']}'",
            ),
          ),
          throwsA(namespace),
        );
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              "INSERT INTO \"${f.schema}\".purchasing_commands SELECT company_id,'${a['operationId']}'::uuid,supplier_id,order_id,location_id,actor_id,kind,expected_version,applied_version,response_status,payload,result,accepted_at FROM \"${f.schema}\".purchasing_commands WHERE operation_id='$old'",
            ),
          ),
          throwsA(namespace),
        );
        for (final isolation in ['REPEATABLE READ', 'SERIALIZABLE']) {
          for (final sql in [
            "INSERT INTO \"${f.schema}\".purchasing_commands SELECT * FROM \"${f.schema}\".purchasing_commands WHERE operation_id='$old'",
            "INSERT INTO \"${f.schema}\".purchasing_delivery_commands SELECT * FROM \"${f.schema}\".purchasing_delivery_commands WHERE operation_id='${a['operationId']}'",
          ]) {
            await expectLater(
              f.pool.runTx((tx) async {
                await tx.execute('SET TRANSACTION ISOLATION LEVEL $isolation');
                await tx.execute(sql);
              }),
              throwsA(
                isA<ServerException>().having(
                  (e) => e.constraintName,
                  'constraint',
                  'purchasing_operation_isolation',
                ),
              ),
            );
          }
        }
        expect(await deliveryEvidence(f), before);
      });
    },
  );
  for (final replay in [false, true]) {
    for (final logoutFirst in [false, true]) {
      test(
        'observed session logout vs ${replay ? 'replay' : 'fresh write'}, logout first $logoutFirst',
        () async {
          await withMerchandisingFixture((f) async {
            final o = await issued(f), root = '$purchasingOrders/${o['id']}';
            final token = await f.login(
                  await f.account('delivery_logout_actor', role: 'admin'),
                ),
                body = declareBody(o);
            if (replay) {
              await f.call(
                'POST',
                '$root/deliveries',
                token: token,
                body: body,
                expected: 201,
              );
            }
            Future<MerchandisingReply> logout() => f.call(
              'POST',
              '/api/v1/auth/logout',
              platform: false,
              token: token,
              expected: 204,
            );
            Future<MerchandisingReply> write() => f.call(
              'POST',
              '$root/deliveries',
              token: token,
              body: body,
              expected: null,
            );
            final results = await orderedPurchasing(
              f,
              logoutFirst ? logout : write,
              logoutFirst ? write : logout,
            );
            expect(
              results[logoutFirst ? 1 : 0].status,
              logoutFirst ? 401 : 201,
            );
          });
        },
      );
    }
  }
  test(
    'canonical mixed-case Location, Order, Delivery, line and operation UUIDs preserve exact original replay and cursor scope',
    () async {
      const location = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
      await withMerchandisingFixture((f) async {
        final root = '/purchasing/locations/$location/orders',
            s = await supplier(f),
            a = await f.stockArticle(sku: 'CANONICAL');
        var o =
            (await f.call(
                  'POST',
                  root,
                  expected: 201,
                  body: {
                    'id': newUuid(),
                    'operationId': newUuid(),
                    'reference': 'Canonical',
                    'supplierId': s['id'],
                    'expectedSupplierVersion': 1,
                  },
                )).body['order']
                as Map;
        o =
            (await f.call(
                  'PUT',
                  '$root/${o['id']}',
                  body: draftSave(o, [
                    purchasingLine(a.toJson(), quantity: '12'),
                  ]),
                )).body['order']
                as Map;
        o =
            (await f.call(
                  'POST',
                  '$root/${o['id']}/issue',
                  body: {
                    'operationId': newUuid(),
                    'expectedVersion': o['version'],
                  },
                )).body['order']
                as Map;
        final body = declareBody(o),
            accepted = (await f.call(
              'POST',
              '$root/${o['id']}/deliveries',
              body: body,
              expected: 201,
            )).body;
        final altered = {
          ...body,
          'operationId': (body['operationId'] as String).toUpperCase(),
          'deliveryId': (body['deliveryId'] as String).toUpperCase(),
          'lines': [
            {
              'orderLineId': (o['lines'][0]['id'] as String).toUpperCase(),
              'quantity': '5.000',
            },
          ],
        };
        final before = await deliveryEvidence(f);
        for (final loc in [
          location.toUpperCase(),
          'aBcDeFaB-cDeF-4aBc-8DeF-aBcDeFaBcDeF',
        ]) {
          final replay = (await f.call(
            'POST',
            '/purchasing/locations/$loc/orders/${(o['id'] as String).toUpperCase()}/deliveries',
            body: altered,
            expected: 201,
          )).body;
          expect(replay, {...accepted, 'replayed': true});
          expect(
            (await f.call(
              'GET',
              '/purchasing/locations/$loc/orders/${o['id']}/deliveries/${(body['deliveryId'] as String).toUpperCase()}',
            )).body,
            accepted['delivery'],
          );
        }
        expect(await deliveryEvidence(f), before);
      }, homeLocationId: location);
    },
  );
  test(
    'concurrent corrections: one new ledger revision and one stale response, observed lock barrier',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f), root = '$purchasingOrders/${o['id']}';
        final a =
            (await f.call(
                  'POST',
                  '$root/deliveries',
                  body: declareBody(o),
                  expected: 201,
                )).body['delivery']
                as Map;
        final one = changeBody(o, a, 1),
            two = changeBody(o, a, 1, quantity: '3');
        final replies = await orderedPurchasing(
          f,
          () => f.call(
            'POST',
            '$root/deliveries/${a['deliveryId']}/correct',
            body: one,
            expected: null,
          ),
          () => f.call(
            'POST',
            '$root/deliveries/${a['deliveryId']}/correct',
            body: two,
            expected: null,
          ),
        );
        expect(replies.map((r) => r.status), [200, 409]);
        expect(replies[1].body['code'], 'ledger_version_conflict');
      });
    },
  );
  for (final injection in ['deferred', 'projection']) {
    test(
      'terminal $injection failure rolls back old receipt, audit and snapshot',
      () async {
        await withMerchandisingFixture((f) async {
          final o = await issued(f),
              root = '$purchasingOrders/${o['id']}',
              body = {
                'operationId': newUuid(),
                'expectedVersion': o['version'],
                'reason': 'Terminal fault',
              },
              before = await deliveryEvidence(f);
          if (injection == 'deferred') {
            await f.owner.execute(
              'CREATE FUNCTION "${f.schema}".p414_late() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Late\' USING ERRCODE=\'23514\'; END \$\$; CREATE CONSTRAINT TRIGGER p414_late AFTER INSERT ON "${f.schema}".purchasing_delivery_terminal_snapshots DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p414_late()',
              queryMode: QueryMode.simple,
            );
          } else {
            await f.owner.execute(
              'ALTER FUNCTION "${f.schema}".purchasing_order_json(uuid,uuid) RENAME TO p414_original_order_json; CREATE FUNCTION "${f.schema}".purchasing_order_json(c uuid,i uuid) RETURNS jsonb LANGUAGE plpgsql AS \$\$ BEGIN IF EXISTS(SELECT 1 FROM "${f.schema}".purchasing_orders WHERE company_id=c AND id=i AND status=\'closed\') THEN RAISE EXCEPTION \'Projection\'; END IF; RETURN "${f.schema}".p414_original_order_json(c,i); END \$\$',
              queryMode: QueryMode.simple,
            );
          }
          await f.call('POST', '$root/close', body: body, expected: 500);
          expect(await deliveryEvidence(f), before);
          if (injection == 'deferred') {
            await f.owner.execute(
              'DROP TRIGGER p414_late ON "${f.schema}".purchasing_delivery_terminal_snapshots',
            );
          } else {
            await f.owner.execute(
              'DROP FUNCTION "${f.schema}".purchasing_order_json(uuid,uuid); ALTER FUNCTION "${f.schema}".p414_original_order_json(uuid,uuid) RENAME TO purchasing_order_json',
              queryMode: QueryMode.simple,
            );
          }
          await f.call('POST', '$root/close', body: body);
        });
      },
    );
  }
  test(
    'unmodified restricted SQL declaration control commits and replays',
    () async {
      await withMerchandisingFixture((f) async {
        final order = await issued(f),
            body = declareBody(order, quantity: '1.000', reason: 'Reason');
        await insertSqlDeclaration(f, order, body);
        await verifySqlDeclaration(f, order, body);
      });
    },
  );
  for (final mutation in [
    'payload_null',
    'result_null',
    'missing_key',
    'wrong_type',
    'missing_lines',
    'foreign_line',
    'foreign_location',
    'duplicate_sequence',
    'bad_scale',
    'nonpositive_quantity',
    'excess_total',
  ]) {
    test(
      'restricted runtime rejects complete malformed final transaction: $mutation',
      () async {
        await withMerchandisingFixture((f) async {
          final o = await issued(f);
          final seeded = {
            'duplicate_sequence',
            'excess_total',
          }.contains(mutation);
          if (seeded) {
            await f.call(
              'POST',
              '$purchasingOrders/${o['id']}/deliveries',
              body: declareBody(
                o,
                quantity: mutation == 'excess_total'
                    ? '999999999999.000'
                    : '5.000',
                reason: 'Reason',
              ),
              expected: 201,
            );
          }
          final before = await deliveryEvidence(f),
              body = declareBody(
                o,
                ledger: seeded ? 1 : 0,
                quantity: mutation == 'excess_total' ? '0.999' : '1.000',
                reason: 'Reason',
              );
          final foreignLineConstraint = mutation == 'foreign_line'
              ? (await f.owner.execute(
                      "SELECT conname FROM pg_constraint WHERE conrelid='\"${f.schema}\".purchasing_delivery_revision_lines'::regclass AND confrelid='\"${f.schema}\".purchasing_order_lines'::regclass AND contype='f'",
                    )).single.first
                    as String
              : null;
          final (code, constraint, message) = switch (mutation) {
            'payload_null' => (
              '23514',
              'purchasing_delivery_commands_payload_check',
              null,
            ),
            'result_null' => (
              '23514',
              'purchasing_delivery_commands_result_check',
              null,
            ),
            'missing_key' || 'wrong_type' => (
              '23514',
              null,
              'Invalid delivery receipt intent/result',
            ),
            'missing_lines' => ('23514', null, 'Incomplete delivery evidence'),
            'foreign_line' => ('23503', foreignLineConstraint, null),
            'foreign_location' => (
              '23514',
              null,
              'Issued scoped Order required',
            ),
            'duplicate_sequence' => (
              '23514',
              null,
              'Invalid delivery sequence or lifecycle',
            ),
            'bad_scale' => (
              '22P02',
              null,
              'invalid input syntax for type bigint: "0.5"',
            ),
            'nonpositive_quantity' => (
              '23514',
              'purchasing_delivery_revision_lines_quantity_scaled_check',
              null,
            ),
            'excess_total' => ('23514', null, 'Delivery quantity limit'),
            _ => throw StateError('Unknown mutation'),
          };
          var rejection = isA<ServerException>().having(
            (e) => e.code,
            'SQLSTATE',
            code,
          );
          if (constraint != null) {
            rejection = rejection.having(
              (e) => e.constraintName,
              'constraint',
              constraint,
            );
          }
          if (message != null) {
            rejection = rejection.having((e) => e.message, 'message', message);
          }
          await expectLater(
            insertSqlDeclaration(f, o, body, mutation: mutation),
            throwsA(rejection),
          );
          expect(await deliveryEvidence(f), before);
          // The identical unmodified intent must commit using the rolled-back IDs.
          await insertSqlDeclaration(f, o, body);
          await verifySqlDeclaration(f, o, body);
        });
      },
    );
  }
}
