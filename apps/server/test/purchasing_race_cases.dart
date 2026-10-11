import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';

void purchasingRaceCases() {
  for (final mutation in [
    'supplier_edit',
    'supplier_retire',
    'article_metadata',
    'article_unit',
    'article_deactivate',
    'assortment_deactivate',
  ]) {
    for (final mutationFirst in [false, true]) {
      test('observed $mutation vs issue: mutation first $mutationFirst', () async {
        await withMerchandisingFixture((f) async {
          final d = await populated(f),
              s = d['supplier'] as Map,
              l = d['lines'][0] as Map,
              op = newUuid();
          String method = 'POST', route;
          Map<String, dynamic> body;
          if (mutation.startsWith('supplier_')) {
            method = mutation == 'supplier_edit' ? 'PUT' : 'POST';
            route =
                '/purchasing/suppliers/${s['id']}${mutation == 'supplier_retire' ? '/retire' : ''}';
            body = {
              'operationId': newUuid(),
              'expectedVersion': s['version'],
              if (mutation == 'supplier_edit') ...{
                'name': 'Changed Supplier',
                'orderingReference': null,
              },
            };
          } else if (mutation == 'assortment_deactivate') {
            final page = (await f.call(
              'GET',
              '/locations/$merchandisingTestLocation/assortment',
            )).body;
            final member = (page['items'] as List).single as Map;
            route =
                '/locations/$merchandisingTestLocation/assortment/${member['id']}/deactivate';
            body = {'expectedVersion': member['version']};
          } else {
            final a = (await f.call('GET', '/articles/${l['articleId']}')).body;
            route =
                '/articles/${a['id']}/${mutation == 'article_deactivate' ? 'deactivate' : 'edit'}';
            body = {
              'expectedVersion': a['version'],
              if (mutation != 'article_deactivate') ...{
                'sku': a['sku'],
                'barcode': a['barcode'],
                'name': mutation == 'article_metadata'
                    ? 'Changed Article'
                    : a['name'],
                'description': a['description'],
                'unit': mutation == 'article_unit' ? 'bag' : a['unit'],
              },
            };
          }
          Future<MerchandisingReply> change() =>
              f.call(method, route, body: body);
          Future<MerchandisingReply> issue() => f.call(
            'POST',
            '$purchasingOrders/${d['id']}/issue',
            body: {'operationId': op, 'expectedVersion': d['version']},
            expected: null,
          );
          final r = await orderedPurchasing(
                f,
                mutationFirst ? change : issue,
                mutationFirst ? issue : change,
              ),
              reply = r[mutationFirst ? 1 : 0];
          expect(
            reply.status,
            mutationFirst
                ? ({
                        'supplier_retire',
                        'article_deactivate',
                        'assortment_deactivate',
                      }.contains(mutation)
                      ? 422
                      : 409)
                : 200,
          );
          if (mutationFirst) {
            expect(reply.body['code'], switch (mutation) {
              'supplier_retire' => 'supplier_selection_unavailable',
              'supplier_edit' => 'supplier_changed',
              'article_unit' => 'article_unit_changed',
              'article_deactivate' => 'article_selection_unavailable',
              'assortment_deactivate' => 'not_in_assortment',
              _ => 'article_reference_changed',
            });
          }
          final current = (await f.call(
            'GET',
            '$purchasingOrders/${d['id']}',
          )).body;
          expect(current['version'], mutationFirst ? 2 : 3);
          expect(current['supplier'], d['supplier']);
          expect(current['lines'], d['lines']);
          expect(
            (await f.owner.execute(
              "SELECT count(*) FROM \"${f.schema}\".purchasing_commands WHERE operation_id='$op'",
            )).single.first,
            mutationFirst ? 0 : 1,
          );
          expect(
            (await f.owner.execute(
              "SELECT count(*) FROM \"${f.schema}\".audit_entries WHERE action='purchasing.order.issued'",
            )).single.first,
            mutationFirst ? 0 : 1,
          );
        });
      });
    }
  }
  for (final reversed in [false, true]) {
    test(
      'observed concurrent whole draft saves in both orders $reversed',
      () async {
        await withMerchandisingFixture((f) async {
          final d = await populated(f);
          Future<MerchandisingReply> save(String q) => f.call(
            'PUT',
            '$purchasingOrders/${d['id']}',
            expected: null,
            body: draftSave(d, [
              {...retainedLine(d['lines'][0] as Map), 'quantity': q},
            ]),
          );
          final r = await orderedPurchasing(
            f,
            () => save(reversed ? '12' : '3'),
            () => save(reversed ? '3' : '12'),
          );
          expect(r.map((e) => e.status), [200, 409]);
          expect(r[1].body['code'], 'version_conflict');
          expect(
            (await f.call(
              'GET',
              '$purchasingOrders/${d['id']}',
            )).body['lines'][0]['quantity'],
            reversed ? '12.000' : '3.000',
          );
        });
      },
    );
    test(
      'observed close vs cancel preserves first terminal decision $reversed',
      () async {
        await withMerchandisingFixture((f) async {
          var d = await populated(f);
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
          Future<MerchandisingReply> act(String action) => f.call(
            'POST',
            '$purchasingOrders/${d['id']}/$action',
            expected: null,
            body: {
              'operationId': newUuid(),
              'expectedVersion': d['version'],
              'reason': action,
            },
          );
          final r = await orderedPurchasing(
            f,
            () => act(reversed ? 'cancel' : 'close'),
            () => act(reversed ? 'close' : 'cancel'),
          );
          expect(r.map((e) => e.status), [200, 409]);
          expect(
            (await f.call(
              'GET',
              '$purchasingOrders/${d['id']}',
            )).body['status'],
            reversed ? 'cancelled' : 'closed',
          );
        });
      },
    );
    test(
      'observed duplicate exact operation submits one effect $reversed',
      () async {
        await withMerchandisingFixture((f) async {
          final d = await populated(f),
              body = draftSave(d, [
                {...retainedLine(d['lines'][0] as Map), 'quantity': '12'},
              ]);
          Future<MerchandisingReply> save() =>
              f.call('PUT', '$purchasingOrders/${d['id']}', body: body);
          final before =
              (await f.owner.execute(
                    'SELECT count(*) FROM "${f.schema}".purchasing_commands',
                  )).single.first
                  as int;
          final r = await orderedPurchasing(f, save, save);
          expect(r[0].body['replayed'], false);
          expect(r[1].body, {...r[0].body, 'replayed': true});
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".purchasing_commands',
            )).single.first,
            before + 1,
          );
        });
      },
    );
  }
  for (final replay in [false, true]) {
    for (final revokeFirst in [false, true]) {
      test(
        'observed Account revocation vs ${replay ? 'receipt replay' : 'write'}: revoke first $revokeFirst',
        () async {
          await withMerchandisingFixture((f) async {
            await f.account('purchasing_actor', role: 'admin');
            final token = await f.login('purchasing_actor'),
                users = (await f.call('GET', '/users')).body['users'] as List;
            final actor =
                users.firstWhere((e) => e['username'] == 'purchasing_actor')
                    as Map;
            final d = await populated(f),
                body = draftSave(d, [
                  {...retainedLine(d['lines'][0] as Map), 'quantity': '12'},
                ]);
            if (replay) {
              await f.call(
                'PUT',
                '$purchasingOrders/${d['id']}',
                token: token,
                body: body,
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
              'PUT',
              '$purchasingOrders/${d['id']}',
              token: token,
              body: body,
              expected: null,
            );
            final before =
                (await f.owner.execute(
                      'SELECT count(*) FROM "${f.schema}".purchasing_commands',
                    )).single.first
                    as int;
            final r = await orderedPurchasing(
              f,
              revokeFirst ? revoke : write,
              revokeFirst ? write : revoke,
            );
            expect(r[revokeFirst ? 1 : 0].status, revokeFirst ? 401 : 200);
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM "${f.schema}".purchasing_commands',
              )).single.first,
              before + (!replay && !revokeFirst ? 1 : 0),
            );
          });
        },
      );
    }
  }
}
