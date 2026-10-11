import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';

const _location = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _mixed = 'aBcDeFaB-cDeF-4aBc-8DeF-aBcDeFaBcDeF';
String _orders(String location) => '/purchasing/locations/$location/orders';

class _Command {
  _Command(this.method, this.suffix, this.body, this.status);
  final String method, suffix;
  final Map<String, dynamic> body;
  final int status;
  String route(String location) => '${_orders(location)}$suffix';
  Future<MerchandisingReply> send(
    MerchandisingFixture f,
    String location, {
    int? expected,
    String? token,
  }) => f.call(
    method,
    route(location),
    body: body,
    expected: expected ?? status,
    token: token,
  );
}

Future<_Command> _create(MerchandisingFixture f) async {
  final s = await supplier(f, name: 'Mixed CASE Supplier', reference: 'AbCd');
  return _Command('POST', '', {
    'id': newUuid(),
    'operationId': newUuid(),
    'reference': 'Case-${newUuid()}',
    'supplierId': s['id'],
    'expectedSupplierVersion': s['version'],
  }, 201);
}

Future<_Command> _save(MerchandisingFixture f, Map d) async {
  final a = await f.stockArticle(sku: 'CASE-${newUuid()}');
  return _Command(
    'PUT',
    '/${d['id']}',
    draftSave(d, [purchasingLine(a.toJson())]),
    200,
  );
}

_Command _transition(Map d, String kind) =>
    _Command('POST', '/${d['id']}/$kind', {
      'operationId': newUuid(),
      'expectedVersion': d['version'],
      if (kind != 'issue') 'reason': 'Mixed CASE reason',
    }, 200);

Future<Map<String, dynamic>> _evidence(MerchandisingFixture f) async => {
  'hashes': await purchasingEvidence(f),
  'counts': (await f.owner.execute(
    'SELECT (SELECT count(*) FROM "${f.schema}".purchasing_commands), '
    '(SELECT count(*) FROM "${f.schema}".audit_entries '
    "WHERE action LIKE 'purchasing.%')",
  )).single.toList(),
  'orders': (await f.call('GET', _orders(_location))).body,
};

Future<void> _replay(
  MerchandisingFixture f,
  _Command c,
  MerchandisingReply original,
  String location,
) async {
  final before = await _evidence(f);
  final reply = await c.send(f, location);
  expect(reply.status, original.status);
  expect(reply.body, {...original.body, 'replayed': true});
  expect(await _evidence(f), before);
  final id = (original.body['order'] as Map)['id'];
  final detail = (await f.call('GET', '${_orders(_location)}/$id')).body;
  expect(detail['version'], (original.body['order'] as Map)['version']);
  expect(detail['lines'], (original.body['order'] as Map)['lines']);
}

Future<void> _privateFailure(
  MerchandisingFixture f,
  _Command c,
  String location,
  int status,
  String code, {
  String? token,
}) async {
  final before = await _evidence(f);
  final reply = await c.send(f, location, expected: status, token: token);
  expect(reply.body['code'], code);
  expect(reply.body.keys, isNot(contains('order')));
  expect(reply.body.keys, isNot(contains('result')));
  expect(reply.body.keys, isNot(contains('payload')));
  expect(reply.body.keys, isNot(contains('replayed')));
  expect(await _evidence(f), before);
}

void purchasingUuidReplayCases() {
  for (final spelling in ['uppercase', 'mixed-case', 'lowercase']) {
    final initialLocation = switch (spelling) {
      'uppercase' => _location.toUpperCase(),
      'mixed-case' => _mixed,
      _ => _location,
    };
    for (final kind in ['create', 'save', 'issue', 'close', 'cancel']) {
      test('F01 $kind $spelling identical and cross-spelling replay', () async {
        await withMerchandisingFixture((f) async {
          expect(
            (await f.pool.execute('SELECT current_user')).single.first,
            f.runtimeUser,
          );
          var c = await _create(f);
          if (kind != 'create') {
            var d = (await c.send(f, _location)).body['order'] as Map;
            c = await _save(f, d);
            if (kind != 'save') {
              d = (await c.send(f, _location)).body['order'] as Map;
              c = _transition(d, 'issue');
              if (kind != 'issue') {
                d = (await c.send(f, _location)).body['order'] as Map;
                c = _transition(d, kind);
              }
            }
          }
          final before = await _evidence(f);
          final original = await c.send(f, initialLocation);
          expect(original.body['replayed'], false);
          final after = await _evidence(f);
          expect(after['counts'], [
            for (final n in before['counts'] as List) (n as int) + 1,
          ]);
          final receipt = await f.row(
            'SELECT location_id::text, response_status, result FROM '
            '"${f.schema}".purchasing_commands WHERE operation_id=CAST(@op AS uuid)',
            {'op': c.body['operationId']},
          );
          expect(receipt['location_id'], _location);
          expect(receipt['response_status'], original.status);
          expect(receipt['result'], original.body);
          expect((original.body['order'] as Map)['locationId'], _location);
          for (final retry in {
            initialLocation,
            _location,
            _location.toUpperCase(),
            _mixed,
          }) {
            await _replay(f, c, original, retry);
          }
          expect(await _evidence(f), after);
        }, homeLocationId: _location);
      });
    }
  }

  for (final terminal in ['close', 'cancel']) {
    test(
      'F01 historical $terminal replay survives restart and stale catalog',
      () async {
        await withMerchandisingFixture((f) async {
          final create = await _create(f);
          final created = await create.send(f, _location.toUpperCase());
          final save = await _save(f, created.body['order'] as Map);
          final saved = await save.send(f, _mixed);
          final issue = _transition(saved.body['order'] as Map, 'issue');
          final issued = await issue.send(f, _location.toUpperCase());
          final issuedOrder = issued.body['order'] as Map;
          final closed = await _transition(
            issuedOrder,
            terminal,
          ).send(f, _mixed);
          expect(closed.body['order']['lines'], issuedOrder['lines']);
          final s = issuedOrder['supplier'] as Map;
          await f.call(
            'POST',
            '/purchasing/suppliers/${s['id']}/retire',
            body: {'operationId': newUuid(), 'expectedVersion': s['version']},
          );
          final line = (issuedOrder['lines'] as List).single as Map;
          await f.call(
            'POST',
            '/articles/${line['articleId']}/deactivate',
            body: {'expectedVersion': line['articleVersion']},
          );
          await f.restart();
          final before = await _evidence(f);
          for (final pair in [
            (create, created),
            (save, saved),
            (issue, issued),
          ]) {
            for (final location in [
              _location.toUpperCase(),
              _mixed,
              _location,
            ]) {
              final replay = await pair.$1.send(f, location);
              expect(replay.status, pair.$2.status);
              expect(replay.body, {...pair.$2.body, 'replayed': true});
            }
          }
          expect(await _evidence(f), before);
          final current = (await f.call(
            'GET',
            '${_orders(_mixed)}/${issuedOrder['id']}',
          )).body;
          expect(current, closed.body['order']);
          expect(current['version'], 4);
          expect(current['lines'], issuedOrder['lines']);
        }, homeLocationId: _location);
      },
    );
  }

  test(
    'F01 conflicting bindings and foreign Location never disclose receipts',
    () async {
      await withMerchandisingFixture((f) async {
        final create = await _create(f);
        final created = await create.send(f, _location.toUpperCase());
        final save = await _save(f, created.body['order'] as Map);
        final saved = await save.send(f, _mixed);
        final issue = _transition(saved.body['order'] as Map, 'issue');
        final issued = await issue.send(f, _location.toUpperCase());
        await f.account('other_case_admin', role: 'admin');
        final other = await f.login('other_case_admin');
        await _privateFailure(
          f,
          issue,
          _mixed,
          409,
          'operation_conflict',
          token: other,
        );
        final target =
            (await (await _create(f)).send(f, _location)).body['order'] as Map;
        for (final conflict in [
          _Command('POST', '/${target['id']}/issue', issue.body, 200),
          _Command('POST', '/${issued.body['order']['id']}/close', {
            ...issue.body,
            'reason': 'Changed kind',
          }, 200),
          _Command('POST', issue.suffix, {
            ...issue.body,
            'expectedVersion': 3,
          }, 200),
          _Command('PUT', save.suffix, {
            ...save.body,
            'reference': 'Changed payload',
          }, 200),
          _Command('POST', '', {...create.body, 'id': newUuid()}, 201),
          _Command('POST', '', {
            ...create.body,
            'reference': 'CASE-CHANGED',
          }, 201),
        ]) {
          await _privateFailure(f, conflict, _mixed, 409, 'operation_conflict');
        }
        final foreign = await f.createLocation('Other Location');
        for (final c in [create, save, issue]) {
          await _privateFailure(f, c, foreign.toUpperCase(), 403, 'forbidden');
        }
        await _privateFailure(
          f,
          create,
          _mixed,
          401,
          'unauthorized',
          token: '',
        );
      }, homeLocationId: _location);
    },
  );

  test(
    'F01 failed Create UUID remains reusable across Location spellings',
    () async {
      await withMerchandisingFixture((f) async {
        final c = await _create(f);
        final failed = _Command(c.method, c.suffix, {
          ...c.body,
          'expectedSupplierVersion': 2,
        }, c.status);
        await _privateFailure(
          f,
          failed,
          _location.toUpperCase(),
          409,
          'supplier_changed',
        );
        final accepted = await c.send(f, _mixed);
        await _replay(f, c, accepted, _location.toUpperCase());
        expect(
          accepted.body['order']['supplier']['name'],
          'Mixed CASE Supplier',
        );
        expect(accepted.body['order']['supplier']['orderingReference'], 'AbCd');
        expect(accepted.body['order']['reference'], c.body['reference']);
      }, homeLocationId: _location);
    },
  );

  test(
    'F01 current Account revocation precedes uppercase receipt disclosure',
    () async {
      await withMerchandisingFixture((f) async {
        await f.account('case_actor', role: 'admin');
        final token = await f.login('case_actor');
        final c = await _create(f);
        await c.send(f, _location.toUpperCase(), token: token);
        final users = (await f.call('GET', '/users')).body['users'] as List;
        final actor =
            users.firstWhere((u) => u['username'] == 'case_actor') as Map;
        await f.call(
          'POST',
          '/users/${actor['id']}',
          body: {
            'expectedVersion': actor['version'],
            'role': 'viewer',
            'isActive': false,
          },
        );
        await _privateFailure(f, c, _mixed, 401, 'unauthorized', token: token);
      }, homeLocationId: _location);
    },
  );
}
