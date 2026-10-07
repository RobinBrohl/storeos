import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/stock/stock_count_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

import 'merchandising_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'task_planogram_fixture.dart';
part 'stock_count_integrity_cases.dart';
part 'stock_count_concurrency_cases.dart';

final _skip = merchandisingDatabaseAvailable
    ? false
    : 'Set explicit isolated test database.';
final _location = merchandisingTestLocation;
String _root(String id) => '/locations/$_location/stock-counts/$id';
Map<String, dynamic> _command(int version, {String? operation}) => {
  'operationId': operation ?? newUuid(),
  'expectedVersion': version,
};
List<Map<String, dynamic>> _lines(Map<String, dynamic> c) =>
    (c['lines'] as List).cast<Map<String, dynamic>>();

void _blind(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      expect({
        'baselineQuantity',
        'baselineVersion',
        'discrepancy',
        'currentStock',
        'checkedStockVersion',
        'recordedBy',
        'approval',
        'outcome',
        'capturedAt',
        'requestedBy',
        'stockLevelId',
      }, isNot(contains(entry.key)));
      _blind(entry.value);
    }
  } else if (value is List) {
    for (final item in value) {
      _blind(item);
    }
  }
}

extension _CountFixture on MerchandisingFixture {
  Future<({String employee, String account, String token})> counter(
    String username, {
    String role = 'employee',
  }) async {
    final accountId = newUuid();
    await call(
      'POST',
      '/users',
      expected: 201,
      body: {
        'id': accountId,
        'username': username,
        'password': merchandisingTestPassword,
        'locationId': _location,
        'role': role,
      },
    );
    final employeeId = newUuid();
    await call(
      'POST',
      '/employees',
      expected: 201,
      body: {
        'id': employeeId,
        'displayName': username,
        'locationId': _location,
      },
    );
    await call(
      'POST',
      '/employees/$employeeId/account-link',
      expected: 201,
      body: {
        'id': newUuid(),
        'accountId': accountId,
        'expectedEmployeeVersion': 1,
        'expectedAccountVersion': 1,
      },
    );
    return (
      employee: employeeId,
      account: accountId,
      token: await login(username),
    );
  }

  Future<Map<String, dynamic>> openCount(
    String employee,
    List<StockLevelDto> levels, {
    String? preceding,
    Map<String, dynamic>? payload,
  }) async => (await call(
    'POST',
    '/locations/$_location/stock-counts',
    expected: 201,
    body:
        payload ??
        {
          'operationId': newUuid(),
          'id': newUuid(),
          'employeeId': employee,
          'stockLevelIds': levels.map((l) => l.id).toList(),
          'purpose': 'Physical count <script>literal</script>',
          'precedingCountId': preceding,
        },
  )).body;
  Future<Map<String, dynamic>> review(String id) async =>
      (await call('GET', _root(id))).body;
  Future<Map<String, dynamic>> observeCount(
    Map<String, dynamic> c,
    int position,
    String token,
    String quantity, {
    String? operation,
    String? note,
  }) async {
    final line = _lines(c)[position];
    final r = await call(
      'POST',
      '/me/stock-counts/${c['id']}/lines/${line['id']}/observations',
      token: token,
      body: {
        ..._command(c['version'] as int, operation: operation),
        'roundId': line['round']['id'],
        'quantity': quantity,
        'note': note,
      },
    );
    _blind(r.body);
    EmployeeCountDto.fromJson(r.body);
    return review(c['id'] as String);
  }

  Future<Map<String, dynamic>> countState(
    String id,
  ) async => (await owner.execute(
    Sql.named(
      'SELECT (SELECT count(*) FROM "$schema".stock_movements WHERE count_id=CAST(@id AS uuid)) AS movements,(SELECT count(*) FROM "$schema".stock_count_commands WHERE count_id=CAST(@id AS uuid) AND kind=\'approve\') AS receipts,(SELECT count(*) FROM "$schema".audit_entries WHERE entity_id=CAST(@id AS text) AND action=\'stock.count.approved\') AS audits,(SELECT status FROM "$schema".stock_counts WHERE id=CAST(@id AS uuid)) AS status',
    ),
    parameters: {'id': id},
  )).single.toColumnMap();
}

void main() {
  registerCountIntegrityCases();
  registerCountConcurrencyCases();
  test(
    'malformed list/history cursors normalize to private invalid_cursor HTTP responses',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('cursor_worker');
      final level = await f.openStock((await f.stockArticle(sku: 'CURSOR')).id);
      final c = await f.openCount(worker.employee, [level]);
      final id = c['id'] as String;
      final line = _lines(c).single['id'] as String;
      String encode(Object? value) =>
          base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
      Future<void> invalid(String route, String cursor, {String? token}) async {
        final response = (await f.call(
          'GET',
          '$route?after=${Uri.encodeQueryComponent(cursor)}',
          token: token,
          expected: 400,
        )).body;
        expect(response, {
          'code': 'invalid_cursor',
          'message': 'Invalid scoped cursor.',
        });
      }

      for (final self in [false, true]) {
        final route = self
            ? '/me/stock-counts'
            : '/locations/$_location/stock-counts';
        final scope = <String, dynamic>{'location': _location, 'self': self};
        final token = self ? worker.token : null;
        for (final value in [
          null,
          7,
          'malformed-uuid',
          true,
          <Object?>[],
          <String, Object?>{},
        ]) {
          await invalid(route, encode({...scope, 'id': value}), token: token);
        }
        for (final cursor in [
          encode(scope),
          encode({...scope, 'id': id, 'extra': 1}),
          encode({...scope, 'self': 'false', 'id': id}),
          encode([]),
          encode(null),
          '%%%',
          '',
          'x' * 513,
        ]) {
          await invalid(route, cursor, token: token);
        }
        final historyRoute = '$route/$id/lines/$line/rounds';
        final historyScope = {...scope, 'count': id, 'line': line};
        for (final value in [
          null,
          '1',
          1.5,
          true,
          0,
          -1,
          maxJsonSafeInteger + 1,
        ]) {
          await invalid(
            historyRoute,
            encode({...historyScope, 'number': value}),
            token: token,
          );
        }
        for (final cursor in [
          encode(historyScope),
          encode({...historyScope, 'number': 1, 'extra': 1}),
          encode({...historyScope, 'count': newUuid(), 'number': 1}),
          '%%%',
        ]) {
          await invalid(historyRoute, cursor, token: token);
        }
      }
    }),
    skip: _skip,
  );
  test(
    'all count routes preserve actual malformed path/location validation codes',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('path_worker');
      final count = newUuid(), line = newUuid();
      for (final operation in [
        ('GET', '/locations/$_location/stock-counts'),
        ('POST', '/locations/$_location/stock-counts'),
        ('GET', '/locations/$_location/stock-counts/assignees'),
        ('GET', '/locations/$_location/stock-counts/$count'),
        ('GET', '/locations/$_location/stock-counts/$count/lines/$line/rounds'),
        for (final kind in ['recount', 'approve', 'cancel'])
          ('POST', '/locations/$_location/stock-counts/$count/$kind'),
        ('GET', '/me/stock-counts'),
        ('GET', '/me/stock-counts/$count'),
        ('GET', '/me/stock-counts/$count/lines/$line/rounds'),
        ('POST', '/me/stock-counts/$count/lines/$line/observations'),
      ]) {
        final request = await f.client.openUrl(
          operation.$1,
          Uri.parse('${f.base}/api/v1/platform${operation.$2}'),
        );
        request.headers.set('authorization', 'Bearer ${worker.token}');
        request.headers.set('origin', 'https://untrusted.invalid');
        final response = await request.close();
        expect(response.statusCode, 403);
        expect(
          jsonDecode(await utf8.decodeStream(response))['code'],
          'origin_forbidden',
        );
      }
      for (final route in [
        '/locations/malformed/stock-counts',
        '/locations/malformed/stock-counts/assignees',
        '/locations/malformed/stock-counts/${newUuid()}',
        '/locations/malformed/stock-counts/${newUuid()}/lines/${newUuid()}/rounds',
        '/me/stock-counts/malformed',
        '/me/stock-counts/${newUuid()}/lines/malformed/rounds',
      ]) {
        expect(
          (await f.call(
            'GET',
            route,
            token: route.startsWith('/me/') ? worker.token : null,
            expected: 400,
          )).body['code'],
          'invalid_count',
        );
      }
      for (final route in [
        '/locations/malformed/stock-counts',
        for (final kind in ['recount', 'approve', 'cancel'])
          '/locations/malformed/stock-counts/${newUuid()}/$kind',
        '/me/stock-counts/malformed/lines/${newUuid()}/observations',
      ]) {
        expect(
          (await f.call(
            'POST',
            route,
            token: route.startsWith('/me/') ? worker.token : null,
            body: {},
            expected: 400,
          )).body['code'],
          'invalid_count',
        );
      }
    }),
    skip: _skip,
  );
  test(
    'real two-line stale/recount approval, zero variance, lost response and restart replay',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('count_worker');
      final a = await f.openStock(
        (await f.stockArticle(sku: 'COUNT-A')).id,
        quantity: '10',
      );
      final b = await f.openStock(
        (await f.stockArticle(sku: 'COUNT-B', unit: 'Stk')).id,
        quantity: '5',
      );
      var c = await f.openCount(worker.employee, [a, b]);
      final id = c['id'] as String;
      expect(_lines(c).map((l) => l['round']['baselineQuantity']), ['10', '5']);
      final blind = (await f.call(
        'GET',
        '/me/stock-counts/$id',
        token: worker.token,
      )).body;
      _blind(blind);
      EmployeeCountDto.fromJson(blind);
      c = await f.observeCount(c, 0, worker.token, '9');
      c = await f.observeCount(c, 1, worker.token, '5');
      expect(_lines(c).map((l) => l['discrepancy']), ['-1', '0']);
      await f.adjustStock(
        a,
        movementId: newUuid(),
        quantity: '12',
        note: 'Recorded movement during count',
      );
      expect(
        (await f.call(
          'POST',
          '${_root(id)}/approve',
          body: _command(c['version'] as int),
          expected: 409,
        )).body['code'],
        'count_stale',
      );
      expect(await f.countState(id), {
        'movements': 0,
        'receipts': 0,
        'audits': 0,
        'status': 'open',
      });
      c = (await f.call(
        'POST',
        '${_root(id)}/recount',
        body: {
          ..._command(c['version'] as int),
          'lineIds': [_lines(c).first['id']],
          'reason': 'Stock changed',
        },
      )).body;
      expect(_lines(c).first['round']['baselineQuantity'], '12');
      expect(_lines(c).first['round']['baselineVersion'], 2);
      final history = (await f.call(
        'GET',
        '/me/stock-counts/$id/lines/${_lines(c).first['id']}/rounds',
        token: worker.token,
      )).body;
      _blind(history);
      expect(history['items'], hasLength(2));
      expect(history['items'][1]['observation']['quantity'], '9');
      c = await f.observeCount(c, 0, worker.token, '11');
      final beforeB = await f.level(b.id);
      final approval = _command(c['version'] as int);
      final approved = (await f.call(
        'POST',
        '${_root(id)}/approve',
        body: approval,
      )).body;
      expect(approved['status'], 'approved');
      final outcomes = _lines(approved).map((l) => l['outcome']).toList();
      expect(outcomes[0]['discrepancy'], '-1');
      expect(outcomes[1]['discrepancy'], '0');
      expect(outcomes[1]['movementId'], isNull);
      expect(outcomes[1]['checkedStockVersion'], 1);
      final afterA = await f.level(a.id);
      final afterB = await f.level(b.id);
      expect(afterA.quantity, '11');
      expect(afterA.version, 3);
      expect(afterB.toJson(), beforeB.toJson());
      final movement = (await f.movements(a.id)).items.first;
      expect(movement.kind, 'count_correction');
      expect(movement.countId, id);
      expect(movement.countLineId, _lines(c).first['id']);
      expect(
        movement.countObservationId,
        _lines(c).first['round']['observation']['id'],
      );
      await f.assertLedgerInvariant(a.id);
      await f.assertLedgerInvariant(b.id);
      await f.adjustStock(
        afterA,
        movementId: newUuid(),
        quantity: '13',
        note: 'Later correction',
      );
      // Deliberately discard the first accepted result, then retry exactly after
      // later Stock effects and a real server replacement.
      expect(
        (await f.call('POST', '${_root(id)}/approve', body: approval)).body,
        approved,
      );
      await f.restart();
      f.adminToken = await f.login('test_admin');
      expect(
        (await f.call('POST', '${_root(id)}/approve', body: approval)).body,
        approved,
      );
      expect(await f.countState(id), {
        'movements': 1,
        'receipts': 1,
        'audits': 1,
        'status': 'approved',
      });
      expect((await f.level(a.id)).quantity, '13');
      final evidence = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".stock_count_rounds),(SELECT count(*) FROM "${f.schema}".stock_count_observations)',
      );
      expect(evidence.single, [3, 3]);
    }),
    skip: _skip,
  );

  test(
    'all 100 lines approve atomically with 50 corrections and 50 explicit zero outcomes; 101 rejected',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('hundred_worker');
      final boundedUnicode = List.filled(500, '界').join();
      final levels = <StockLevelDto>[];
      for (var i = 0; i < 100; i++) {
        levels.add(
          await f.openStock(
            (await f.stockArticle(
              sku: 'BOUND-$i',
              name: List.filled(120, '界').join(),
            )).id,
            quantity: '5',
          ),
        );
      }
      var c = await f.openCount(worker.employee, levels);
      final initial = Map<String, dynamic>.of(c);
      c = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/recount',
        body: {
          ..._command(c['version'] as int),
          'lineIds': _lines(c).map((l) => l['id']).toList(),
          'reason': boundedUnicode,
        },
      )).body;
      for (var i = 0; i < 100; i++) {
        c = await f.observeCount(
          c,
          i,
          worker.token,
          i.isEven ? '4' : '5',
          note: boundedUnicode,
        );
      }
      final approved = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/approve',
        body: _command(c['version'] as int),
      )).body;
      expect(_lines(approved), hasLength(100));
      expect(
        _lines(approved).where((l) => l['outcome']['movementId'] != null),
        hasLength(50),
      );
      expect((await f.countState(c['id'] as String))['movements'], 50);
      final receiptBytes =
          (await f.owner.execute(
                'SELECT max(octet_length(result::text)) FROM "${f.schema}".stock_count_commands',
              )).single.first
              as int;
      expect(receiptBytes, greaterThan(262144));
      expect(receiptBytes, lessThanOrEqualTo(1048576));
      for (var i = 0; i < 100; i++) {
        final level = await f.level(levels[i].id);
        expect(level.version, i.isEven ? 2 : 1);
        expect(level.quantity, i.isEven ? '4' : '5');
        if (i.isOdd) expect(level.updatedAt, levels[i].updatedAt);
      }
      final invalid = await f.call(
        'POST',
        '/locations/$_location/stock-counts',
        expected: 400,
        body: {
          'operationId': newUuid(),
          'id': newUuid(),
          'employeeId': worker.employee,
          'purpose': 'Bound',
          'precedingCountId': null,
          'stockLevelIds': [...levels.map((l) => l.id), newUuid()],
        },
      );
      expect(invalid.body['code'], 'invalid_count');
      expect(initial['version'], 1);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'opening bounds, missing levels, duplicate selection, assignment and exact opening replay',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('open_worker');
      final level = await f.openStock(
        (await f.stockArticle(sku: 'OPEN-COUNT')).id,
      );
      final payload = {
        'operationId': newUuid(),
        'id': newUuid(),
        'employeeId': worker.employee,
        'purpose': 'Count',
        'precedingCountId': null,
        'stockLevelIds': [level.id],
      };
      final first = await f.openCount(worker.employee, [
        level,
      ], payload: payload);
      expect(
        await f.openCount(worker.employee, [level], payload: payload),
        first,
      );
      expect(
        (await f.call(
          'POST',
          '/locations/$_location/stock-counts',
          body: {...payload, 'purpose': 'Different'},
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      for (final selection in <List<String>>[
        [],
        [level.id, level.id],
      ]) {
        expect(
          (await f.call(
            'POST',
            '/locations/$_location/stock-counts',
            expected: 400,
            body: {
              ...payload,
              'operationId': newUuid(),
              'id': newUuid(),
              'stockLevelIds': selection,
            },
          )).body['code'],
          'invalid_count',
        );
      }
      expect(
        (await f.call(
          'POST',
          '/locations/$_location/stock-counts',
          expected: 404,
          body: {
            ...payload,
            'operationId': newUuid(),
            'id': newUuid(),
            'stockLevelIds': [newUuid()],
          },
        )).body['code'],
        'not_found',
      );
      expect(
        (await f.call(
          'POST',
          '/locations/$_location/stock-counts',
          expected: 422,
          body: {
            ...payload,
            'operationId': newUuid(),
            'id': newUuid(),
            'employeeId': newUuid(),
          },
        )).body['code'],
        'assignee_unavailable',
      );
    }),
    skip: _skip,
  );

  test(
    'immutable observations, canonical replay, conflict and superseded-round rejection',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('observe_worker');
      var c = await f.openCount(worker.employee, [
        await f.openStock((await f.stockArticle(sku: 'OBS')).id),
      ]);
      final id = c['id'] as String;
      final line = _lines(c).single;
      final route = '/me/stock-counts/$id/lines/${line['id']}/observations';
      final body = {
        ..._command(1),
        'roundId': line['round']['id'],
        'quantity': '0.500',
        'note': null,
      };
      final first = (await f.call(
        'POST',
        route,
        token: worker.token,
        body: body,
      )).body;
      _blind(first);
      expect(
        (await f.call(
          'POST',
          route,
          token: worker.token,
          body: {...body, 'quantity': '0.5'},
        )).body,
        first,
      );
      expect(
        (await f.call(
          'POST',
          route,
          token: worker.token,
          body: {...body, 'quantity': '1'},
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      expect(
        (await f.call(
          'POST',
          route,
          token: worker.token,
          body: {...body, ..._command(2)},
          expected: 409,
        )).body['code'],
        'observation_exists',
      );
      c = (await f.call(
        'POST',
        '${_root(id)}/recount',
        body: {
          ..._command(2),
          'lineIds': [line['id']],
          'reason': 'Check again',
        },
      )).body;
      expect(
        (await f.call(
          'POST',
          route,
          token: worker.token,
          body: {...body, ..._command(3)},
          expected: 409,
        )).body['code'],
        'round_conflict',
      );
      expect(
        (await f.call('POST', route, token: worker.token, body: body)).body,
        first,
      );
      final blindHistory = (await f.call(
        'GET',
        '/me/stock-counts/$id/lines/${line['id']}/rounds',
        token: worker.token,
      )).body;
      _blind(blindHistory);
      expect(blindHistory['items'], hasLength(2));
      expect(_lines(c).single['round']['observation'], isNull);
    }),
    skip: _skip,
  );

  test(
    'recording Account separation applies only to CURRENT observations',
    () => withMerchandisingFixture((f) async {
      final manager = await f.counter('self_manager', role: 'admin');
      final level = await f.openStock((await f.stockArticle(sku: 'SELF')).id);
      var c = await f.openCount(manager.employee, [level]);
      c = await f.observeCount(c, 0, manager.token, '2');
      expect(
        (await f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          token: manager.token,
          body: _command(c['version'] as int),
          expected: 422,
        )).body['code'],
        'self_approval_forbidden',
      );
      c = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/recount',
        body: {
          ..._command(c['version'] as int),
          'lineIds': [_lines(c).single['id']],
          'reason': 'New independent recorder',
        },
      )).body;
      final link = (await f.call(
        'GET',
        '/employees/${manager.employee}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      final replacementId = newUuid();
      await f.call(
        'POST',
        '/users',
        expected: 201,
        body: {
          'id': replacementId,
          'username': 'new_recorder',
          'password': merchandisingTestPassword,
          'locationId': _location,
          'role': 'employee',
        },
      );
      await f.call(
        'POST',
        '/employees/${manager.employee}/account-link',
        expected: 201,
        body: {
          'id': newUuid(),
          'accountId': replacementId,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
      );
      c = await f.observeCount(c, 0, await f.login('new_recorder'), '2');
      final freshManager = await f.login('self_manager');
      expect(
        (await f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          token: freshManager,
          body: _command(c['version'] as int),
        )).body['status'],
        'approved',
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation and linked replacement preserve evidence without Stock effects',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('cancel_worker');
      final level = await f.openStock((await f.stockArticle(sku: 'CANCEL')).id);
      var c = await f.openCount(worker.employee, [level]);
      c = await f.observeCount(c, 0, worker.token, '0');
      final body = {
        ..._command(c['version'] as int),
        'reason': 'Replacement required',
      };
      final cancelled = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/cancel',
        body: body,
      )).body;
      expect(cancelled['status'], 'cancelled');
      expect(
        (await f.call(
          'POST',
          '${_root(c['id'] as String)}/cancel',
          body: body,
        )).body,
        cancelled,
      );
      expect((await f.countState(c['id'] as String))['movements'], 0);
      expect((await f.level(level.id)).toJson(), level.toJson());
      final next = await f.openCount(worker.employee, [
        level,
      ], preceding: c['id'] as String);
      expect(next['precedingCountId'], c['id']);
      expect(_lines(next).single['round']['observation'], isNull);
      expect(
        (await f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          body: _command(cancelled['version'] as int),
          expected: 409,
        )).body['code'],
        'count_conflict',
      );
    }),
    skip: _skip,
  );

  test(
    'Location equality precedes resources and replay; role/own scope/session/link are enforced',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('scope_worker');
      final other = await f.counter('other_worker');
      var c = await f.openCount(worker.employee, [
        await f.openStock((await f.stockArticle(sku: 'SCOPE')).id),
      ]);
      final id = c['id'] as String;
      await f.call(
        'GET',
        '/me/stock-counts/$id',
        token: other.token,
        expected: 404,
      );
      await f.call('GET', _root(id), token: worker.token, expected: 403);
      await f.call('GET', _root(id), token: '', expected: 401);
      final away = await f.createLocation('Registered but unconfigured');
      await f.call('GET', '/locations/$away/stock-counts/$id', expected: 403);
      for (final role in ['viewer', 'auditor']) {
        await f.account(role, role: role);
        final token = await f.login(role);
        await f.call('GET', _root(id), token: token, expected: 403);
        await f.call('GET', '/me/stock-counts', token: token, expected: 403);
      }
      final body = {
        ..._command(1),
        'roundId': _lines(c).single['round']['id'],
        'quantity': '1',
        'note': null,
      };
      await f.call(
        'POST',
        '/me/stock-counts/$id/lines/${_lines(c).single['id']}/observations',
        token: worker.token,
        body: body,
      );
      c = await f.review(id);
      final approve = _command(c['version'] as int);
      await f.call('POST', '${_root(id)}/approve', body: approve);
      await f.call(
        'POST',
        '/locations/$away/stock-counts/$id/approve',
        body: approve,
        expected: 403,
      );
      await f.restart(locationId: away);
      // The account still belongs to the original Location. Both detail and an
      // exact committed receipt remain forbidden even with a persisted session.
      await f.call('GET', _root(id), expected: 403);
      await f.call(
        'POST',
        '${_root(id)}/approve',
        body: approve,
        expected: 403,
      );
    }),
    skip: _skip,
  );

  test(
    'Stock changing back to baseline is stale and overlapping counts revalidate versions',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('overlap_worker');
      var level = await f.openStock(
        (await f.stockArticle(sku: 'ABA')).id,
        quantity: '10',
      );
      var first = await f.openCount(worker.employee, [level]);
      var second = await f.openCount(worker.employee, [level]);
      first = await f.observeCount(first, 0, worker.token, '9');
      second = await f.observeCount(second, 0, worker.token, '9');
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '12',
        note: 'First movement',
      );
      level = await f.adjustStock(
        level,
        movementId: newUuid(),
        quantity: '10',
        note: 'Second movement',
      );
      expect(
        (await f.call(
          'POST',
          '${_root(first['id'] as String)}/approve',
          body: _command(first['version'] as int),
          expected: 409,
        )).body['code'],
        'count_stale',
      );
      for (var c in [first, second]) {
        c = (await f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          body: {
            ..._command(c['version'] as int),
            'lineIds': [_lines(c).single['id']],
            'reason': 'Fresh baseline',
          },
        )).body;
        c = await f.observeCount(c, 0, worker.token, '9');
        if (c['id'] == first['id']) {
          first = c;
        } else {
          second = c;
        }
      }
      await f.call(
        'POST',
        '${_root(first['id'] as String)}/approve',
        body: _command(first['version'] as int),
      );
      expect(
        (await f.call(
          'POST',
          '${_root(second['id'] as String)}/approve',
          body: _command(second['version'] as int),
          expected: 409,
        )).body['code'],
        'count_stale',
      );
    }),
    skip: _skip,
  );

  for (final failure in ['movement', 'line outcome', 'audit']) {
    test(
      '$failure persistence failure rolls back whole mixed approval',
      () => withMerchandisingFixture((f) async {
        final worker = await f.counter('rollback_worker');
        final levels = <StockLevelDto>[];
        for (var i = 0; i < 3; i++) {
          levels.add(
            await f.openStock(
              (await f.stockArticle(sku: 'ROLLBACK-$i')).id,
              quantity: '5',
            ),
          );
        }
        var c = await f.openCount(worker.employee, levels);
        for (var i = 0; i < 3; i++) {
          c = await f.observeCount(c, i, worker.token, i == 1 ? '5' : '4');
        }
        final table = switch (failure) {
          'movement' => 'stock_movements',
          'line outcome' => 'stock_count_lines',
          _ => 'audit_entries',
        };
        final condition = switch (failure) {
          'movement' => "NEW.kind='count_correction'",
          'line outcome' => 'NEW.approved_observation_id IS NOT NULL',
          _ => "NEW.action='stock.count.approved'",
        };
        final operation = failure == 'line outcome' ? 'UPDATE' : 'INSERT';
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".count_failure() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF $condition THEN RAISE EXCEPTION \'Injected acceptance failure\'; END IF; RETURN NEW; END \$\$; CREATE TRIGGER count_failure BEFORE $operation ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".count_failure()',
          queryMode: QueryMode.simple,
        );
        await f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          body: _command(c['version'] as int),
          expected: 500,
        );
        expect(await f.countState(c['id'] as String), {
          'movements': 0,
          'receipts': 0,
          'audits': 0,
          'status': 'open',
        });
        for (final level in levels) {
          expect((await f.level(level.id)).toJson(), level.toJson());
        }
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".stock_count_observations',
          )).single.first,
          3,
        );
        expect(
          _lines(
            await f.review(c['id'] as String),
          ).every((l) => l['outcome'] == null),
          isTrue,
        );
      }),
      skip: _skip,
    );
  }

  test(
    '0020 populated upgrade and injected failed migration preserve legacy ledger and grant rollback',
    () => withMerchandisingFixture((f) async {
      for (final schema in [1, 2, 3]) {
        await guidedScenario(
          f,
          schema: schema,
          workerName: 'pre20_schema_$schema',
        );
      }
      final retained = await planogramTaskScenario(f, knowledge: true);
      await completePlanogramTask(f, retained);
      final level = await f.openStock(
        (await f.stockArticle(sku: 'UPGRADE')).id,
        quantity: '10',
      );
      final before = (await f.owner.execute(
        'SELECT to_jsonb(s) FROM "${f.schema}".stock_levels s',
      )).single.first;
      Future<List<Object?>> legacyEvidence() async {
        final values = <Object?>[];
        for (final table in [
          'articles',
          'article_location_assortment',
          'stock_levels',
          'stock_movements',
          'knowledge_articles',
          'knowledge_revisions',
          'merchandising_fixtures',
          'merchandising_planograms',
          'merchandising_planogram_revisions',
          'merchandising_planogram_assignments',
          'task_template_revisions',
          'task_instances',
          'task_step_results',
          'task_numeric_attempts',
          'task_execution_commands',
        ]) {
          final projection = table == 'stock_movements'
              ? "to_jsonb(t)-'count_id'-'count_line_id'-'count_observation_id'"
              : 'to_jsonb(t)';
          values.add(
            (await f.owner.execute(
              "SELECT md5(string_agg(($projection)::text,'' ORDER BY ($projection)::text)) FROM \"${f.schema}\".$table t",
            )).single.first,
          );
        }
        return values;
      }

      final preserved = await legacyEvidence();
      final temp = await Directory.systemTemp.createTemp('stock_count_failed_');
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${temp.path}/${file.uri.pathSegments.last}');
        }
        await File(
          '${temp.path}/0020_stock_counts.sql',
        ).writeAsString('\nSELECT 1/0;', mode: FileMode.append);
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: temp,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<ServerException>()),
        );
        expect(
          (await f.owner.execute(
            "SELECT to_regclass('\"${f.schema}\".stock_counts')",
          )).single.first,
          isNull,
        );
        expect(
          (await f.owner.execute(
            'SELECT to_jsonb(s) FROM "${f.schema}".stock_levels s',
          )).single.first,
          before,
        );
        expect(await legacyEvidence(), preserved);
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          ['0020_stock_counts', '0021_recipe_compositions'],
        );
        expect(await legacyEvidence(), preserved);
        expect(
          (await f.owner.execute(
            'SELECT DISTINCT (content::jsonb->>\'schemaVersion\')::int FROM "${f.schema}".task_instances ORDER BY 1',
          )).map((r) => r.first),
          [1, 2, 3, 4],
        );
        expect((await f.level(level.id)).toJson(), level.toJson());
        expect((await f.movements(level.id)).items.single.kind, 'opening');
        final worker = await f.counter('upgrade_worker');
        final c = await f.openCount(worker.employee, [level]);
        expect(c['status'], 'open');
      } finally {
        await temp.delete(recursive: true);
      }
    }, legacyBefore: '0020_stock_counts.sql'),
    skip: _skip,
  );
}
