import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_delivery_sql_fixture.dart';

Future<Map<String, dynamic>> issued(MerchandisingFixture f) async {
  final d = await populated(f);
  final saved =
      (await f.call(
            'PUT',
            '$purchasingOrders/${d['id']}',
            body: draftSave(d, [
              {...retainedLine(d['lines'][0] as Map), 'quantity': '12.000'},
            ]),
          )).body['order']
          as Map<String, dynamic>;
  return (await f.call(
        'POST',
        '$purchasingOrders/${d['id']}/issue',
        body: {'operationId': newUuid(), 'expectedVersion': saved['version']},
      )).body['order']
      as Map<String, dynamic>;
}

Map<String, dynamic> declareBody(
  Map o, {
  int ledger = 0,
  String quantity = '5',
  String? reference,
  String? operation,
  String? delivery,
  String? reason,
}) => {
  'deliveryId': delivery ?? newUuid(),
  'operationId': operation ?? newUuid(),
  'expectedOrderVersion': o['version'],
  'expectedLedgerVersion': ledger,
  'localReference': reference ?? 'Delivery-${newUuid()}',
  'reason': reason,
  'lines': [
    {'orderLineId': o['lines'][0]['id'], 'quantity': quantity},
  ],
};
Map<String, dynamic> changeBody(
  Map o,
  Map d,
  int ledger, {
  String quantity = '4',
  bool voided = false,
}) => {
  'operationId': newUuid(),
  'expectedOrderVersion': o['version'],
  'expectedLedgerVersion': ledger,
  'expectedRevision': d['revision'],
  'reason': 'Operator correction',
  if (!voided)
    'lines': [
      {'orderLineId': o['lines'][0]['id'], 'quantity': quantity},
    ],
};
Future<List<Object?>> deliveryEvidence(MerchandisingFixture f) async => [
  ...await purchasingEvidence(f),
  for (final table in [
    'purchasing_delivery_revisions',
    'purchasing_delivery_revision_lines',
    'purchasing_delivery_commands',
    'purchasing_delivery_terminal_snapshots',
  ])
    (await f.owner.execute(
      "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
    )).single.first,
];
void main() {
  if (Platform.environment['STOREOS_TEST_DATABASE'] == null) {
    test(
      'isolated restricted PostgreSQL delivery acceptance',
      () {},
      skip: 'Explicit disposable database required.',
    );
    return;
  }
  test(
    '12 ordered: partial, overdelivery, replacement, void, restore, close, post-close correction and restart replay',
    () async {
      await withMerchandisingFixture((f) async {
        var o = await issued(f);
        final root = '$purchasingOrders/${o['id']}', body = declareBody(o);
        final original = (await f.call(
          'POST',
          '$root/deliveries',
          body: body,
          expected: 201,
        )).body;
        final a = original['delivery'] as Map;
        final b =
            (await f.call(
                  'POST',
                  '$root/deliveries',
                  body: declareBody(o, ledger: 1, quantity: '7'),
                  expected: 201,
                )).body['delivery']
                as Map;
        expect(
          (await f.call(
            'GET',
            '$root/delivery-summary',
          )).body['summary']['lines'][0]['effectiveDelivered'],
          '12.000',
        );
        await f.call(
          'POST',
          '$root/deliveries',
          body: declareBody(o, ledger: 2, quantity: '1'),
          expected: 422,
        );
        final extra =
            (await f.call(
                  'POST',
                  '$root/deliveries',
                  body: declareBody(
                    o,
                    ledger: 2,
                    quantity: '1',
                    reason: 'Accepted extra',
                  ),
                  expected: 201,
                )).body['delivery']
                as Map;
        expect(
          (await f.call(
            'GET',
            '$root/delivery-summary',
          )).body['summary']['lines'][0]['overdelivery'],
          '1.000',
        );
        await f.call(
          'POST',
          '$root/deliveries/${extra['deliveryId']}/void',
          body: changeBody(o, extra, 3, voided: true),
        );
        final v =
            (await f.call(
                  'POST',
                  '$root/deliveries/${b['deliveryId']}/void',
                  body: changeBody(o, b, 4, voided: true),
                )).body['delivery']
                as Map;
        final restored = (await f.call(
          'POST',
          '$root/deliveries/${b['deliveryId']}/correct',
          body: changeBody(o, v, 5, quantity: '7'),
        )).body['delivery'];
        expect(restored['revision'], 3);
        o =
            (await f.call(
                  'POST',
                  '$root/close',
                  body: {
                    'operationId': newUuid(),
                    'expectedVersion': o['version'],
                    'reason': 'Administrative close',
                  },
                )).body['order']
                as Map<String, dynamic>;
        final closed = (await f.call('GET', '$root/delivery-summary')).body;
        expect(
          closed['terminalSnapshot']['summary']['lines'][0]['effectiveDelivered'],
          '12.000',
        );
        await f.call(
          'POST',
          '$root/deliveries/${a['deliveryId']}/correct',
          body: changeBody(o, a, 6),
        );
        final current = (await f.call('GET', '$root/delivery-summary')).body;
        expect(current['summary']['lines'][0]['effectiveDelivered'], '11.000');
        expect(current['summary']['lines'][0]['recordedRemainder'], '1.000');
        expect(current['terminalSnapshot'], closed['terminalSnapshot']);
        expect((await f.call('GET', root)).body, o);
        await f.call(
          'POST',
          '$root/deliveries',
          body: declareBody(o, ledger: 7),
          expected: 409,
        );
        final before = await deliveryEvidence(f);
        await f.restart();
        final replay = (await f.call(
          'POST',
          '$root/deliveries',
          body: body,
          expected: 201,
        )).body;
        expect(replay, {...original, 'replayed': true});
        expect(await deliveryEvidence(f), before);
        final history =
            (await f.call(
                  'GET',
                  '$root/deliveries/${a['deliveryId']}/history',
                )).body['items']
                as List;
        expect(history.map((r) => r['revision']), [1, 2]);
        expect(history[0]['lines'][0]['quantity'], '5.000');
      });
    },
  );
  for (final action in ['close', 'cancel']) {
    for (final deliveryFirst in [false, true]) {
      for (final correction in [false, true]) {
        test(
          'observed ${correction ? 'correction' : 'declaration'} vs $action, delivery first $deliveryFirst',
          () async {
            await withMerchandisingFixture((f) async {
              final o = await issued(f), root = '$purchasingOrders/${o['id']}';
              Map? a;
              if (correction) {
                a =
                    (await f.call(
                          'POST',
                          '$root/deliveries',
                          body: declareBody(o),
                          expected: 201,
                        )).body['delivery']
                        as Map;
              }
              final body = correction ? changeBody(o, a!, 1) : declareBody(o);
              Future<MerchandisingReply> write() => f.call(
                'POST',
                correction
                    ? '$root/deliveries/${a!['deliveryId']}/correct'
                    : '$root/deliveries',
                body: body,
                expected: null,
              );
              Future<MerchandisingReply> terminal() => f.call(
                'POST',
                '$root/$action',
                body: {
                  'operationId': newUuid(),
                  'expectedVersion': o['version'],
                  'reason': 'Administrative',
                },
                expected: null,
              );
              final results = await orderedPurchasing(
                f,
                deliveryFirst ? write : terminal,
                deliveryFirst ? terminal : write,
              );
              expect(
                results[deliveryFirst ? 0 : 1].status,
                deliveryFirst ? (correction ? 200 : 201) : 409,
              );
              expect(results[deliveryFirst ? 1 : 0].status, 200);
              final summary = (await f.call(
                'GET',
                '$root/delivery-summary',
              )).body;
              expect(
                summary['terminalSnapshot']['summary']['lines'][0]['effectiveDelivered'],
                deliveryFirst
                    ? (correction ? '4.000' : '5.000')
                    : (correction ? '5.000' : '0.000'),
              );
              if (!deliveryFirst && correction) {
                await f.call(
                  'POST',
                  '$root/deliveries/${a!['deliveryId']}/correct',
                  body: {...body, 'expectedOrderVersion': o['version'] + 1},
                );
              }
            });
          },
        );
      }
    }
  }
  for (final identical in [false, true]) {
    test('observed concurrent declaration, identical $identical', () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            route = '$purchasingOrders/${o['id']}/deliveries',
            a = declareBody(o),
            b = identical ? a : declareBody(o);
        final r = await orderedPurchasing(
          f,
          () => f.call('POST', route, body: a, expected: null),
          () => f.call('POST', route, body: b, expected: null),
        );
        expect(r.map((r) => r.status), [201, identical ? 201 : 409]);
        if (identical) expect(r[1].body, {...r[0].body, 'replayed': true});
        expect(
          (await f.call(
            'GET',
            '$purchasingOrders/${o['id']}/delivery-summary',
          )).body['summary']['ledgerVersion'],
          1,
        );
      });
    });
  }
  for (final deliveryFirst in [false, true]) {
    test(
      'observed old/new same-operation namespace, delivery first $deliveryFirst',
      () async {
        await withMerchandisingFixture((f) async {
          final o = await issued(f), op = newUuid();
          Future<MerchandisingReply> old() => f.call(
            'POST',
            '/purchasing/suppliers',
            body: {
              'id': newUuid(),
              'operationId': op,
              'name': 'Namespace',
              'orderingReference': null,
            },
            expected: null,
          );
          Future<MerchandisingReply> fresh() => f.call(
            'POST',
            '$purchasingOrders/${o['id']}/deliveries',
            body: declareBody(o, operation: op),
            expected: null,
          );
          final r = await orderedPurchasing(
            f,
            deliveryFirst ? fresh : old,
            deliveryFirst ? old : fresh,
          );
          expect(r.map((r) => r.status), [201, 409]);
          expect(r[1].body['code'], 'operation_conflict');
        });
      },
    );
  }
  for (final table in [
    'purchasing_delivery_revisions',
    'purchasing_delivery_revision_lines',
    'purchasing_delivery_commands',
    'audit_entries',
  ]) {
    test(
      'declaration fault at $table rolls back and failed UUID remains reusable',
      () async {
        await withMerchandisingFixture((f) async {
          final o = await issued(f),
              body = declareBody(o),
              before = await deliveryEvidence(f);
          await f.owner.execute(
            'CREATE FUNCTION "${f.schema}".p414_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Injected\' USING ERRCODE=\'23514\'; END \$\$; CREATE TRIGGER p414_fault BEFORE INSERT ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p414_fault()',
            queryMode: QueryMode.simple,
          );
          await f.call(
            'POST',
            '$purchasingOrders/${o['id']}/deliveries',
            body: body,
            expected: 500,
          );
          expect(await deliveryEvidence(f), before);
          await f.owner.execute(
            'DROP TRIGGER p414_fault ON "${f.schema}".$table',
          );
          await f.call(
            'POST',
            '$purchasingOrders/${o['id']}/deliveries',
            body: body,
            expected: 201,
          );
        });
      },
    );
  }
  for (final table in [
    'purchasing_orders',
    'purchasing_commands',
    'purchasing_delivery_terminal_snapshots',
    'audit_entries',
  ]) {
    test('close fault at $table preserves lifecycle and snapshot', () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            body = {
              'operationId': newUuid(),
              'expectedVersion': o['version'],
              'reason': 'Close',
            },
            before = await deliveryEvidence(f);
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".p414_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'Injected\' USING ERRCODE=\'23514\'; END \$\$; CREATE TRIGGER p414_fault BEFORE ${table == 'purchasing_orders' ? 'UPDATE' : 'INSERT'} ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p414_fault()',
          queryMode: QueryMode.simple,
        );
        await f.call(
          'POST',
          '$purchasingOrders/${o['id']}/close',
          body: body,
          expected: 500,
        );
        expect(await deliveryEvidence(f), before);
        await f.owner.execute(
          'DROP TRIGGER p414_fault ON "${f.schema}".$table',
        );
        await f.call('POST', '$purchasingOrders/${o['id']}/close', body: body);
      });
    });
  }
  test(
    'strict DTOs, decoded duplicates, unknown query, foreign line, overdelivery and failed UUID reuse',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f),
            route = '$purchasingOrders/${o['id']}/deliveries',
            body = declareBody(o),
            before = await deliveryEvidence(f);
        for (final quantity in [
          0,
          0.5,
          '0',
          '-1',
          '1.0001',
          '9999999999999',
          'NaN',
          '1e2',
        ]) {
          await f.call(
            'POST',
            route,
            body: {
              ...body,
              'lines': [
                {'orderLineId': o['lines'][0]['id'], 'quantity': quantity},
              ],
            },
            expected: 400,
          );
        }
        for (final extra in ['unit', 'actorId', 'summary', 'companyId']) {
          await f.call(
            'POST',
            route,
            body: {...body, extra: 'forged'},
            expected: 400,
          );
        }
        await f.call(
          'POST',
          route,
          body: {
            ...body,
            'lines': [...body['lines'] as List, ...body['lines'] as List],
          },
          expected: 400,
        );
        await f.call(
          'POST',
          route,
          body: {
            ...body,
            'lines': [
              {'orderLineId': newUuid(), 'quantity': '1'},
            ],
          },
          expected: 422,
        );
        await f.call(
          'POST',
          route,
          raw:
              '{"operationId":"${newUuid()}","\\u006fperationId":"${newUuid()}"}',
          expected: 400,
        );
        await f.call('GET', '$route?after=x&after=y', expected: 400);
        await f.call(
          'POST',
          route,
          body: body,
          jsonContentType: false,
          expected: 415,
        );
        await f.call('POST', route, raw: ' ' * 16385, expected: 413);
        expect(await deliveryEvidence(f), before);
        await f.call('POST', route, body: body, expected: 201);
      });
    },
  );
  test(
    'restricted SQL: immutable grants and NULL-safe complete receipts',
    () async {
      await withMerchandisingFixture((f) async {
        final o = await issued(f);
        await f.call(
          'POST',
          '$purchasingOrders/${o['id']}/deliveries',
          body: declareBody(o),
          expected: 201,
        );
        final before = await deliveryEvidence(f);
        for (final table in [
          'purchasing_delivery_revisions',
          'purchasing_delivery_revision_lines',
          'purchasing_delivery_commands',
          'purchasing_delivery_terminal_snapshots',
        ]) {
          for (final command in [
            'UPDATE "$table" SET company_id=company_id',
            'DELETE FROM "$table"',
            'TRUNCATE "$table"',
          ]) {
            await expectLater(
              f.pool.runTx(
                (tx) => tx.execute(
                  command.replaceAll('"$table"', '"${f.schema}".$table'),
                ),
              ),
              throwsA(
                isA<ServerException>()
                    .having((e) => e.code, 'SQLSTATE', '42501')
                    .having(
                      (e) => e.message,
                      'message',
                      'permission denied for table $table',
                    ),
              ),
            );
          }
        }
        final columns =
            'company_id,location_id,order_id,delivery_id,revision,ledger_version,kind,local_reference,actor_id,operation_id';
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              "INSERT INTO \"${f.schema}\".purchasing_delivery_revisions($columns) VALUES('$merchandisingTestCompany','$merchandisingTestLocation','${o['id']}','${newUuid()}',1,2,'delivery_declare','Incomplete','${f.adminId}','${newUuid()}')",
            ),
          ),
          throwsA(
            isA<ServerException>()
                .having((e) => e.code, 'SQLSTATE', '23503')
                .having(
                  (e) => e.constraintName,
                  'constraint',
                  'purchasing_delivery_receipt',
                ),
          ),
        );
        expect(await deliveryEvidence(f), before);
        var ledger = 1;
        for (final mutation in [
          'payload_sql_null',
          'payload_null',
          'payload_empty_object',
          'payload_operation_null',
        ]) {
          final body = declareBody(
                o,
                ledger: ledger,
                quantity: '1.000',
                reason: 'Reason',
              ),
              beforeMutation = await deliveryEvidence(f);
          var rejection = isA<ServerException>().having(
            (e) => e.code,
            'SQLSTATE',
            mutation == 'payload_sql_null' ? '23502' : '23514',
          );
          if (mutation == 'payload_sql_null') {
            rejection = rejection.having(
              (e) => e.columnName,
              'column',
              'payload',
            );
          } else if (mutation == 'payload_null') {
            rejection = rejection.having(
              (e) => e.constraintName,
              'constraint',
              'purchasing_delivery_commands_payload_check',
            );
          } else {
            rejection = rejection.having(
              (e) => e.message,
              'message',
              'Invalid delivery receipt intent/result',
            );
          }
          await expectLater(
            insertSqlDeclaration(f, o, body, mutation: mutation),
            throwsA(rejection),
          );
          expect(await deliveryEvidence(f), beforeMutation);
          await insertSqlDeclaration(f, o, body);
          await verifySqlDeclaration(f, o, body);
          ledger++;
        }
      });
    },
  );
}
