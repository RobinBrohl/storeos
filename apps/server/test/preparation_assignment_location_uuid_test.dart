import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart'
    show newUuid;
import 'package:test/test.dart';

import 'merchandising_fixture.dart';
import 'preparation_assignment_integration_test.dart'
    show assignmentEvidence, request;
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';

const _location = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _mixed = 'aAaAaAaA-aAaA-4aAa-8AaA-aAaAaAaAaAaA';
final _spellings = [_location, _location.toUpperCase(), _mixed];
final _skip = merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';

String _root(String location, {bool self = false}) =>
    '/production/${self ? 'self' : 'manage'}/locations/$location/preparation-assignments';

Future<void> _fixture(Future<void> Function(MerchandisingFixture) action) =>
    withMerchandisingFixture(action, homeLocationId: _location);

Future<BatchWorker> _worker(
  MerchandisingFixture f,
  String name, {
  String location = _location,
}) async {
  final account = newUuid(), employee = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': account,
      'username': name,
      'password': merchandisingTestPassword,
      'locationId': location,
      'role': 'employee',
    },
  );
  await f.call(
    'POST',
    '/employees',
    expected: 201,
    body: {'id': employee, 'displayName': name, 'locationId': location},
  );
  await f.call(
    'POST',
    '/employees/$employee/account-link',
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': account,
      'expectedEmployeeVersion': 1,
      'expectedAccountVersion': 1,
    },
  );
  return BatchWorker(account, employee, await f.login(name));
}

Future<void> _canonicalStored(
  MerchandisingFixture f,
  Map<String, dynamic> command,
) async {
  final rows = await f.owner.execute(
    Sql.named('''
SELECT a.location_id::text AS assignment_location,
       c.location_id::text AS receipt_location,
       e.location_id::text AS audit_location, e.changes->>'locationId' AS audit_scope
FROM "${f.schema}".production_preparation_assignments a
JOIN "${f.schema}".production_preparation_assignment_commands c
  ON c.company_id=a.company_id AND c.assignment_id=a.id AND c.kind='create'
JOIN "${f.schema}".audit_entries e
  ON e.entity_id=a.id::text AND e.action='production.preparation_assignment.created'
WHERE a.id=@id AND c.operation_id=@operation
'''),
    parameters: {'id': command['id'], 'operation': command['operationId']},
  );
  expect(rows, hasLength(1));
  expect(rows.single, everyElement(_location));
}

void main() {
  test(
    'F01 manager picker and creation use one Location UUID identity',
    () => _fixture((f) async {
      final worker = await _worker(f, 'uuid_worker'),
          recipe = await batchRecipe(f);
      final results =
          <
            ({
              String location,
              MerchandisingReply picker,
              MerchandisingReply created,
              Map<String, dynamic> command,
            })
          >[];
      for (final spelling in _spellings) {
        final command = request(recipe, worker);
        results.add((
          location: spelling,
          picker: await f.call('GET', '${_root(spelling)}/assignees'),
          created: await f.call(
            'POST',
            _root(spelling),
            body: command,
            expected: null,
          ),
          command: command,
        ));
      }
      // Retain both symptoms before asserting, including on the pre-fix source.
      print(
        'F01_LOCATION_OBSERVATIONS:${jsonEncode([
          for (final result in results) {'location': result.location, 'pickerStatus': result.picker.status, 'eligibleCount': (result.picker.body['items'] as List).length, 'createStatus': result.created.status, 'createCode': result.created.body['code'], 'storedLocation': result.created.body['assignment']?['locationId']},
        ])}',
      );
      final projection = [
        {'id': worker.employee, 'displayName': 'uuid_worker', 'version': 1},
      ];
      for (final result in results) {
        expect(
          result.picker.body['items'],
          projection,
          reason: result.location,
        );
        expect(result.created.status, 201, reason: result.location);
        expect(result.created.body['assignment']['locationId'], _location);
        expect((result.picker.body['items'] as List).single.keys.toSet(), {
          'id',
          'displayName',
          'version',
        });
        await _canonicalStored(f, result.command);
        for (final spelling in _spellings) {
          for (final suffix in ['', '/recipe', '/history']) {
            await f.call(
              'GET',
              '${_root(spelling)}/${result.command['id']}$suffix',
            );
          }
        }
      }
    }),
    skip: _skip,
  );

  for (final pair in [
    (_location.toUpperCase(), _location.toUpperCase()),
    (_location.toUpperCase(), _location),
    (_location, _location.toUpperCase()),
    (_mixed, _location),
  ]) {
    test(
      'F01 create replay ${pair.$1} to ${pair.$2}',
      () => _fixture((f) async {
        final worker = await _worker(f, 'replay_worker'),
            recipe = await batchRecipe(f);
        final command = request(recipe, worker);
        final original = (await f.call(
          'POST',
          _root(pair.$1),
          body: command,
          expected: 201,
        )).body;
        final before = await assignmentEvidence(f);
        final replay = (await f.call(
          'POST',
          _root(pair.$2),
          body: command,
          expected: 201,
        )).body;
        expect(replay, {...original, 'replayed': true});
        expect(await assignmentEvidence(f), before);
        await _canonicalStored(f, command);
        for (final changed in [
          {...command, 'plannedDeclaredBatchCount': 4},
          {...command, 'id': newUuid()},
          {...command, 'expectedEmployeeVersion': 2},
        ]) {
          final conflict = await f.call(
            'POST',
            _root(pair.$2),
            body: changed,
            expected: 409,
          );
          expect(conflict.body['code'], 'operation_conflict');
        }
        await f.account('other_manager', role: 'admin');
        final other = await f.login('other_manager');
        final afterAccount = await assignmentEvidence(f);
        final conflict = await f.call(
          'POST',
          _root(pair.$2),
          token: other,
          body: command,
          expected: 409,
        );
        expect(conflict.body['code'], 'operation_conflict');
        expect(await assignmentEvidence(f), afterAccount);
      }),
      skip: _skip,
    );
  }

  test(
    'F01 distinct and registered nonconfigured Locations cannot alias evidence',
    () => _fixture((f) async {
      final worker = await _worker(f, 'scope_worker'),
          recipe = await batchRecipe(f);
      final command = request(recipe, worker);
      await f.call('POST', _root(_location), body: command, expected: 201);
      final away = await f.createLocation('Registered away');
      final foreign = await _worker(f, 'away_worker', location: away);
      final before = await assignmentEvidence(f);
      for (final location in [newUuid(), away, away.toUpperCase()]) {
        final picker = await f.call(
          'GET',
          '${_root(location)}/assignees',
          expected: 403,
        );
        expect(picker.body.containsKey('items'), false);
        for (final body in [command, request(recipe, worker)]) {
          final denied = await f.call(
            'POST',
            _root(location),
            body: body,
            expected: 403,
          );
          expect(denied.body.containsKey('assignment'), false);
        }
      }
      for (final spelling in _spellings) {
        expect(
          (await f.call('GET', '${_root(spelling)}/assignees')).body['items'],
          [
            {
              'id': worker.employee,
              'displayName': 'scope_worker',
              'version': 1,
            },
          ],
        );
        for (final target in [foreign.employee, newUuid()]) {
          final denied = await f.call(
            'POST',
            _root(spelling),
            body: {...request(recipe, worker), 'employeeId': target},
            expected: 422,
          );
          expect(denied.body['code'], 'assignee_unavailable');
        }
      }
      expect(await assignmentEvidence(f), before);
      await f.restart(companyId: newUuid());
      for (final spelling in _spellings) {
        final denied = await f.call(
          'GET',
          '${_root(spelling)}/assignees',
          expected: 401,
        );
        expect(denied.body.containsKey('items'), false);
        await f.call('POST', _root(spelling), body: command, expected: 401);
      }
      expect(await assignmentEvidence(f), before);
    }),
    skip: _skip,
  );

  for (final mutation in [
    'employee_inactive',
    'link_revoked',
    'account_inactive',
    'capability_revoked',
  ]) {
    test(
      'F01 $mutation remains unavailable under all UUID spellings',
      () => _fixture((f) async {
        final worker = await _worker(f, 'eligibility_worker'),
            recipe = await batchRecipe(f);
        if (mutation == 'employee_inactive') {
          await f.call(
            'POST',
            '/employees/${worker.employee}/deactivate',
            body: {'expectedVersion': 1},
          );
        } else if (mutation == 'link_revoked') {
          final link =
              (await f.call(
                    'GET',
                    '/employees/${worker.employee}/account-link',
                  )).body['link']
                  as Map;
          await f.call(
            'POST',
            '/employee-links/${link['id']}/revoke',
            body: {'expectedVersion': link['version']},
          );
        } else {
          await f.call(
            'POST',
            '/users/${worker.account}',
            body: {
              'expectedVersion': 1,
              'role': mutation == 'capability_revoked' ? 'viewer' : 'employee',
              'isActive': mutation != 'account_inactive',
            },
          );
        }
        final before = await assignmentEvidence(f);
        for (final spelling in _spellings) {
          expect(
            (await f.call('GET', '${_root(spelling)}/assignees')).body['items'],
            isEmpty,
          );
          final denied = await f.call(
            'POST',
            _root(spelling),
            body: request(recipe, worker),
            expected: 422,
          );
          expect(denied.body['code'], 'assignee_unavailable');
        }
        expect(await assignmentEvidence(f), before);
      }),
      skip: _skip,
    );
  }

  test(
    'F01 stale Employee versions remain conflicts for every UUID spelling',
    () => _fixture((f) async {
      final worker = await _worker(f, 'version_worker'),
          recipe = await batchRecipe(f);
      final before = await assignmentEvidence(f);
      for (final spelling in _spellings) {
        final denied = await f.call(
          'POST',
          _root(spelling),
          body: {...request(recipe, worker), 'expectedEmployeeVersion': 2},
          expected: 409,
        );
        expect(denied.body['code'], 'version_conflict');
      }
      expect(await assignmentEvidence(f), before);
    }),
    skip: _skip,
  );

  test(
    'F01 self routes retain R1 and ownership for every UUID spelling',
    () => _fixture((f) async {
      final worker = await _worker(f, 'self_worker'),
          other = await _worker(f, 'self_other'),
          recipe = await batchRecipe(f);
      final command = request(recipe, worker), id = command['id'];
      await f.call('POST', _root(_location), body: command, expected: 201);
      final r1 = recipe.detail.currentPublished!.id;
      recipe.detail = (await replacementRecipe(f, recipe.detail)).detail;
      await publishRecipe(f, recipe.detail);
      final before = await assignmentEvidence(f);
      for (final spelling in _spellings) {
        final own = _root(spelling, self: true);
        final page = (await f.call('GET', own, token: worker.token)).body;
        expect((page['items'] as List).single['id'], id);
        for (final suffix in ['', '/recipe', '/history']) {
          final result = (await f.call(
            'GET',
            '$own/$id$suffix',
            token: worker.token,
          )).body;
          if (suffix == '/recipe') expect(result['revisionId'], r1);
          await f.call(
            'GET',
            '$own/$id$suffix',
            token: other.token,
            expected: 404,
          );
        }
        await f.call(
          'POST',
          '$own/$id/start',
          token: other.token,
          body: {'operationId': newUuid(), 'expectedVersion': 1},
          expected: 404,
        );
      }
      await f.call(
        'POST',
        '/production/self/locations/$_location/batches',
        token: worker.token,
        body: {...batchOpening(recipe), 'revisionId': r1},
        expected: 422,
      );
      expect(await assignmentEvidence(f), before);
      for (final initial in _spellings) {
        final body = {'operationId': newUuid(), 'expectedVersion': 1};
        final next = request(recipe, worker)..['revisionId'] = r1;
        // The initial assignment retains R1; fresh assignments select current R2.
        final target = initial == _spellings.first ? id : next['id'];
        if (target != id) {
          recipe.detail = await recipeDetail(f, recipe.detail.recipe.id);
          next['revisionId'] = recipe.detail.currentPublished!.id;
          await f.call('POST', _root(_location), body: next, expected: 201);
        }
        final accepted = (await f.call(
          'POST',
          '${_root(initial, self: true)}/$target/start',
          token: worker.token,
          body: body,
        )).body;
        if (target == id) expect(accepted['batch']['revisionId'], r1);
        expect(accepted['batch']['locationId'], _location);
        final started = await assignmentEvidence(f);
        for (final spelling in _spellings) {
          final replay = (await f.call(
            'POST',
            '${_root(spelling, self: true)}/$target/start',
            token: worker.token,
            body: body,
          )).body;
          expect(replay, {...accepted, 'replayed': true});
          for (final suffix in ['', '/recipe', '/history']) {
            await f.call(
              'GET',
              '${_root(spelling, self: true)}/$target$suffix',
              token: worker.token,
            );
          }
        }
        expect(await assignmentEvidence(f), started);
      }
      final away = await f.createLocation('Self away');
      final afterAway = await assignmentEvidence(f);
      for (final suffix in ['', '/$id', '/$id/recipe', '/$id/history']) {
        await f.call(
          'GET',
          '${_root(away, self: true)}$suffix',
          token: worker.token,
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '${_root(away, self: true)}/$id/start',
        token: worker.token,
        body: {'operationId': newUuid(), 'expectedVersion': 1},
        expected: 403,
      );
      expect(await assignmentEvidence(f), afterAway);
    }),
    skip: _skip,
  );

  test(
    'F01 concurrent create spellings share one receipt and audit',
    () => _fixture((f) async {
      final worker = await _worker(f, 'concurrent_worker'),
          recipe = await batchRecipe(f),
          command = request(recipe, worker);
      final outcomes = await orderedBatchCommands(
        f,
        () => f.call(
          'POST',
          _root(_location.toUpperCase()),
          body: command,
          expected: 201,
        ),
        () => f.call('POST', _root(_mixed), body: command, expected: 201),
      );
      expect(outcomes.last.body, {...outcomes.first.body, 'replayed': true});
      expect(outcomes.first.body['replayed'], false);
      await _canonicalStored(f, command);
      for (final table in [
        'production_preparation_assignments',
        'production_preparation_assignment_commands',
      ]) {
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".$table',
          )).single.first,
          1,
        );
      }
      final before = await assignmentEvidence(f);
      await f.call('POST', _root(_location), body: command, expected: 201);
      expect(await assignmentEvidence(f), before);
    }),
    skip: _skip,
  );

  for (final self in [false, true]) {
    test(
      'F01 ${self ? 'self' : 'manager'} pagination binds canonical Location identity',
      () => _fixture((f) async {
        final worker = await _worker(f, 'page_worker'),
            recipe = await batchRecipe(f);
        for (var n = 0; n < 51; n++) {
          await f.call(
            'POST',
            _root(_location),
            body: request(recipe, worker),
            expected: 201,
          );
        }
        final before = await assignmentEvidence(f);
        for (final spelling in _spellings) {
          final page = (await f.call(
            'GET',
            _root(spelling, self: self),
            token: self ? worker.token : null,
          )).body;
          expect(page['items'], hasLength(50));
          final cursor = page['nextCursor'] as String;
          final scope =
              jsonDecode(
                    utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
                  )
                  as Map;
          expect(scope['location'], _location);
          for (final retry in _spellings) {
            final tail = (await f.call(
              'GET',
              '${_root(retry, self: self)}?after=${Uri.encodeQueryComponent(cursor)}',
              token: self ? worker.token : null,
            )).body;
            expect(tail['items'], hasLength(1));
            expect(tail['nextCursor'], null);
          }
        }
        expect(await assignmentEvidence(f), before);
      }),
      skip: _skip,
    );
  }
}
