import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/shift_application.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/platform/plugin_service.dart';
import 'package:test/test.dart';

part 'task_execution_integration_cases.dart';
part 'task_blocking_integration_cases.dart';
part 'task_cancellation_integration_cases.dart';
part 'task_numeric_integration_cases.dart';
part 'shift_cancellation_integration_cases.dart';
part 'shift_amendment_integration_cases.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
const _password = 'employee-test-only-password-strong';
final _url = Platform.environment['STOREOS_TEST_DATABASE'];

void main() {
  executionTests();
  blockingTests();
  cancellationTests();
  numericTests();
  shiftCancellationTests();
  shiftAmendmentTests();
  test(
    'pinned selections reject mismatched templates and published foreign-location revisions without writes',
    () => _withFixture((f) async {
      final p = await _plan(f);
      final foreignTemplate = newUuid(), foreignRevision = newUuid();
      // Seed another site's persisted data; the local API cannot author it.
      await f.owner.execute(
        Sql.named(
          'INSERT INTO "${f.schema}".task_templates(id, company_id, location_id) '
          'VALUES(CAST(@id AS uuid), CAST(@company AS uuid), CAST(@location AS uuid))',
        ),
        parameters: {
          'id': foreignTemplate,
          'company': _company,
          'location': _other,
        },
      );
      await f.owner.execute(
        Sql.named(
          'INSERT INTO "${f.schema}".task_template_revisions '
          '(id, template_id, company_id, location_id, revision_number, status, content, published_at, published_by, publication_version) '
          'SELECT CAST(@id AS uuid), CAST(@template AS uuid), company_id, CAST(@location AS uuid), '
          '1, status, content, published_at, published_by, publication_version '
          'FROM "${f.schema}".task_template_revisions WHERE id=CAST(@source AS uuid)',
        ),
        parameters: {
          'id': foreignRevision,
          'template': foreignTemplate,
          'location': _other,
          'source': p.template['revisionId'],
        },
      );
      for (final selection in [
        {'templateId': foreignTemplate, 'revisionId': p.template['revisionId']},
        {'templateId': foreignTemplate, 'revisionId': foreignRevision},
      ]) {
        final reply = await f.call(
          'POST',
          '/shifts',
          body: {
            ...p.input,
            'selections': [selection],
          },
          expected: 422,
        );
        expect(reply.body['code'], 'invalid_selection');
      }
      expect((await f.call('GET', '/shifts')).body['items'], isEmpty);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'workforce.shift.%\'',
        )).single.first,
        0,
      );
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
    }),
    skip: _skip,
  );
  test(
    'publication races with deactivation and session revocation remain consistent',
    () => _withFixture((f) async {
      final p = await _plan(f);
      final token = await _linkedAccount(f, p.employee, 'race_worker');
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      final responses = await Future.wait([
        f.call(
          'POST',
          '/shifts/${p.id}/publish',
          body: {'expectedVersion': 1},
          expected: null,
        ),
        f.call(
          'POST',
          '/employees/${p.employee.id}/deactivate',
          body: {'expectedVersion': 1},
        ),
      ]);
      expect(responses.first.status, anyOf(200, 422));
      final state = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(
        state['shift']['status'],
        responses.first.status == 200 ? 'published' : 'draft',
      );
      expect(state['tasks'], hasLength(responses.first.status == 200 ? 1 : 0));
      await f.call('GET', '/employee-home/shifts', token: token, expected: 401);
      final admin = await f.account('second_admin', role: 'admin');
      final adminToken = await f.login(admin.username);
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        expected: 204,
        token: adminToken,
        platform: false,
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
        token: adminToken,
        expected: 401,
      );
    }),
    skip: _skip,
  );
  test(
    'valid plugin token cannot access shifts or employee home',
    () => _withFixture((f) async {
      final plugins = PluginService(f.database);
      final registration = await plugins.register(f.adminPrincipal, {
        'manifest': {
          'id': 'shift-denied',
          'name': 'Denied',
          'version': '1.0.0',
          'vendor': 'StoreOS tests',
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
      });
      final grant = await plugins.approve(f.adminPrincipal, 'shift-denied', {
        'expectedVersion': registration['version'],
        'locationId': _home,
        'permissions': ['organization.read'],
        'subscriptions': <String>[],
      });
      final token = grant['token'] as String;
      await plugins.organization(token);
      for (final route in [
        '/employee-home/shifts/${newUuid()}/tasks/${newUuid()}/block',
        '/shifts/${newUuid()}/tasks/${newUuid()}/resume',
        '/shifts/${newUuid()}/tasks/${newUuid()}/cancel',
      ]) {
        await f.call(
          'POST',
          route,
          body: _reasonCommand(2),
          token: token,
          expected: 401,
        );
      }
      final p = await _plan(f);
      await f.call(
        'POST',
        '/employee-home/shifts/${p.id}/tasks/${newUuid()}/start',
        body: _command(1),
        token: token,
        expected: 401,
      );
      for (final route in [
        '/shifts',
        '/employee-home/shifts',
        '/blocked-tasks',
        '/employee-home/blocked-tasks',
        '/cancelled-tasks',
        '/employee-home/cancelled-tasks',
        '/shifts/${p.id}/tasks/${newUuid()}/blockings',
      ]) {
        await f.call('GET', route, token: token, expected: 401);
      }
      await f.call(
        'POST',
        '/shifts',
        body: p.input,
        token: token,
        expected: 401,
      );
    }),
    skip: _skip,
  );
  test(
    'ten ordered instances are atomic even if the second insertion fails',
    () => _withFixture((f) async {
      final p = await _plan(f);
      final selections = p.input['selections'] as List;
      for (var i = 1; i < 10; i++) {
        final t = _input();
        await f.call('POST', '/task-templates', body: t, expected: 201);
        await f.call(
          'POST',
          '/task-templates/${t['id']}/revisions/${t['revisionId']}/publish',
          body: {'expectedVersion': 1},
        );
        selections.add({'templateId': t['id'], 'revisionId': t['revisionId']});
      }
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".reject_second() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.position=1 THEN RAISE EXCEPTION \'injected\'; END IF; RETURN NEW; END; \$\$',
      );
      await f.owner.execute(
        'CREATE TRIGGER reject_second BEFORE INSERT ON "${f.schema}".task_instances FOR EACH ROW EXECUTE FUNCTION "${f.schema}".reject_second()',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
        expected: 503,
      );
      expect((await f.call('GET', '/shifts/${p.id}')).body['tasks'], isEmpty);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'tasks.instance.created\'',
        )).single.first,
        0,
      );
      await f.owner.execute(
        'DROP TRIGGER reject_second ON "${f.schema}".task_instances',
      );
      final done = (await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      )).body;
      expect(done['tasks'], hasLength(10));
      expect(
        (done['tasks'] as List).map((t) => t['revisionId']).toList(),
        selections.map((s) => s['revisionId']).toList(),
      );
      await expectLater(
        f.pool.execute(
          'INSERT INTO "${f.schema}".task_instances SELECT * FROM "${f.schema}".task_instances LIMIT 1',
        ),
        throwsA(isA<ServerException>()),
      );
    }),
    skip: _skip,
  );
  test(
    'two-user workflow publishes exact snapshots, retries, audits and survives restart',
    () => _withFixture((f) async {
      final plan = await _plan(f);
      final employeeToken = await _linkedAccount(f, plan.employee, 'worker');
      final created = (await f.call(
        'POST',
        '/shifts',
        body: plan.input,
        expected: 201,
      )).body;
      expect(created['shift']['status'], 'draft');
      expect(
        (await f.call(
          'GET',
          '/employee-home/shifts',
          token: employeeToken,
        )).body['items'],
        isEmpty,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${plan.id}',
        token: employeeToken,
        expected: 404,
      );
      final publication = (await f.call(
        'POST',
        '/shifts/${plan.id}/publish',
        body: {'expectedVersion': 1},
      )).body;
      expect(publication['tasks'], hasLength(1));
      expect(publication['shift']['version'], 2);
      final taskId = publication['tasks'][0]['id'];
      final home = (await f.call(
        'GET',
        '/employee-home/shifts',
        token: employeeToken,
      )).body;
      expect(home['items'], hasLength(1));
      expect(jsonEncode(home), isNot(contains('Check equipment')));
      final task = (await f.call(
        'GET',
        '/employee-home/shifts/${plan.id}/tasks/$taskId',
        token: employeeToken,
      )).body;
      expect(task['content'], _content());
      final rid = newUuid();
      await f.call(
        'POST',
        '/task-templates/${plan.template['id']}/revisions',
        body: {'id': rid, 'expectedVersion': 2},
        expected: 201,
      );
      await f.call(
        'POST',
        '/task-templates/${plan.template['id']}/revisions/$rid/edit',
        body: {'expectedVersion': 3, 'content': _content('New instructions')},
      );
      await f.call(
        'POST',
        '/task-templates/${plan.template['id']}/revisions/$rid/publish',
        body: {'expectedVersion': 4},
      );
      final retry = (await f.call(
        'POST',
        '/shifts/${plan.id}/publish',
        body: {'expectedVersion': 1},
      )).body;
      expect(retry, publication);
      await f.call(
        'POST',
        '/shifts/${plan.id}/publish',
        body: {'expectedVersion': 2},
        expected: 409,
      );
      await f.call(
        'POST',
        '/shifts/${plan.id}/edit',
        body: {..._draft(plan.input), 'expectedVersion': 2},
        expected: 409,
      );
      final audit = await f.owner.execute(
        'SELECT action,correlation_id::text FROM "${f.schema}".audit_entries WHERE action IN (\'tasks.instance.created\',\'workforce.shift.published\') ORDER BY id',
      );
      expect(audit, hasLength(2));
      expect(audit.first[1], audit.last[1]);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".event_outbox WHERE type LIKE \'shift.%\'',
        )).single.first,
        0,
      );
      await f.restart();
      expect(
        (await f.call(
          'GET',
          '/employee-home/shifts/${plan.id}/tasks/$taskId',
          token: employeeToken,
        )).body,
        task,
      );
      final app = ShiftApplication(f.database);
      // Real runtime role cannot alter snapshots, assignments or published plans.
      await expectLater(
        f.pool.execute(
          'UPDATE "${f.schema}".task_instances SET content=content',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.pool.execute('UPDATE "${f.schema}".shifts SET starts_at=starts_at'),
        throwsA(isA<ServerException>()),
      );
      expect(
        (await app.get(f.adminPrincipal, plan.id))['tasks'],
        publication['tasks'],
      );
    }),
    skip: _skip,
  );

  test(
    'creation identity, edits and parallel publications have exactly one effect',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts',
        body: {
          ...p.input,
          'endsAt': DateTime.parse(
            p.input['endsAt'] as String,
          ).add(const Duration(hours: 1)).toIso8601String(),
        },
        expected: 409,
      );
      final edit = {
        ..._draft(p.input),
        'endsAt': DateTime.parse(
          p.input['endsAt'] as String,
        ).add(const Duration(hours: 1)).toIso8601String(),
        'expectedVersion': 1,
      };
      final edits = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call('POST', '/shifts/${p.id}/edit', body: edit, expected: null),
      ]);
      expect(edits.map((r) => r.status).toList()..sort(), [200, 409]);
      final publications = await Future.wait([
        for (var i = 0; i < 4; i++)
          f.call(
            'POST',
            '/shifts/${p.id}/publish',
            body: {'expectedVersion': 2},
          ),
      ]);
      expect(publications.map((r) => jsonEncode(r.body)).toSet(), hasLength(1));
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".shifts),(SELECT count(*) FROM "${f.schema}".task_instances),(SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'workforce.shift.%\')',
      );
      expect(counts.single, [1, 1, 3]);
    }),
    skip: _skip,
  );

  test(
    'failures at task insertion and both publication audit points roll back the whole publication',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      for (final target in [
        'tasks.instance.created',
        'workforce.shift.published',
      ]) {
        await f.owner.execute(
          'CREATE OR REPLACE FUNCTION "${f.schema}".reject_audit() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action=\'$target\' THEN RAISE EXCEPTION \'injected\'; END IF; RETURN NEW; END; \$\$',
        );
        await f.owner.execute(
          'CREATE TRIGGER reject_audit BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".reject_audit()',
        );
        await f.call(
          'POST',
          '/shifts/${p.id}/publish',
          body: {'expectedVersion': 1},
          expected: 503,
        );
        await f.owner.execute(
          'DROP TRIGGER reject_audit ON "${f.schema}".audit_entries',
        );
        final state = (await f.call('GET', '/shifts/${p.id}')).body;
        expect(state['shift']['status'], 'draft');
        expect(state['shift']['version'], 1);
        expect(state['tasks'], isEmpty);
      }
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".task_instances FROM "${f.runtimeUser}"',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
        expected: 503,
      );
      await f.owner.execute(
        'GRANT INSERT ON "${f.schema}".task_instances TO "${f.runtimeUser}"',
      );
      expect((await f.call('GET', '/shifts/${p.id}')).body['tasks'], isEmpty);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action IN (\'tasks.instance.created\',\'workforce.shift.published\')',
        )).single.first,
        0,
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
    }),
    skip: _skip,
  );

  test(
    'audit failure rolls back creation and edits including ordered selections',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      await f.call('POST', '/shifts', body: p.input, expected: 503);
      await f.owner.execute(
        'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
      );
      await f.call('GET', '/shifts/${p.id}', expected: 404);
      final before = (await f.call(
        'POST',
        '/shifts',
        body: p.input,
        expected: 201,
      )).body;
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/edit',
        body: {
          ..._draft(p.input),
          'selections': <Map<String, dynamic>>[],
          'expectedVersion': 1,
        },
        expected: 503,
      );
      await f.owner.execute(
        'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
      );
      expect((await f.call('GET', '/shifts/${p.id}')).body, before);
    }),
    skip: _skip,
  );

  test(
    'roles, links, tenant, location and object access are enforced on HTTP reads and writes',
    () => _withFixture((f) async {
      final p = await _plan(f);
      final token = await _linkedAccount(f, p.employee, 'own_worker');
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      final published = (await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      )).body;
      final otherEmployee = await f.employee('Other employee'),
          otherToken = await _linkedAccount(f, otherEmployee, 'other_worker');
      final path = '/employee-home/shifts/${p.id}';
      await f.call('GET', path, token: otherToken, expected: 404);
      await f.call(
        'GET',
        '$path/tasks/${published['tasks'][0]['id']}',
        token: otherToken,
        expected: 404,
      );
      for (final role in ['viewer', 'auditor', 'employee']) {
        final account = await f.account('role_$role', role: role),
            credential = await f.login(account.username);
        await f.call('GET', '/shifts', token: credential, expected: 403);
        await f.call(
          'POST',
          '/shifts/${p.id}/publish',
          body: {'expectedVersion': 1},
          token: credential,
          expected: 403,
        );
        await f.call(
          'GET',
          '/employee-home/shifts',
          token: credential,
          expected: role == 'employee' ? 404 : 403,
        );
      }
      await f.call('GET', '/shifts', token: '', expected: 401);
      final foreign = SessionPrincipal(
        id: f.adminPrincipal.id,
        username: 'foreign',
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        ShiftApplication(f.database).list(foreign),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      await f.call(
        'POST',
        '/shifts',
        body: {...p.input, 'id': newUuid(), 'locationId': _other},
        expected: 422,
      );
      final link = (await f.call(
        'GET',
        '/employees/${p.employee.id}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      await f.call('GET', path, token: token, expected: 401);
      expect(
        (await f.call('GET', '/shifts/${p.id}')).body['tasks'],
        hasLength(1),
      );
    }),
    skip: _skip,
  );

  test(
    'invalid plans, unpublished revisions, bounds, overlaps and concurrent overlap publication fail',
    () => _withFixture((f) async {
      final p = await _plan(f);
      for (final bad in [
        {...p.input, 'startsAt': '2026-02-30T08:00:00Z'},
        {...p.input, 'startsAt': '2030-01-01T08:00:00'},
        {...p.input, 'endsAt': p.input['startsAt']},
        {
          ...p.input,
          'selections': [
            ...(p.input['selections'] as List),
            ...(p.input['selections'] as List),
          ],
        },
        {
          ...p.input,
          'selections': List.generate(
            11,
            (_) => {'templateId': newUuid(), 'revisionId': newUuid()},
          ),
        },
      ]) {
        await f.call('POST', '/shifts', body: bad, expected: 400);
      }
      await f.call(
        'POST',
        '/shifts',
        body: {
          ...p.input,
          'selections': [
            {'templateId': newUuid(), 'revisionId': newUuid()},
          ],
        },
        expected: 422,
      );
      final draft = _input();
      await f.call('POST', '/task-templates', body: draft, expected: 201);
      await f.call(
        'POST',
        '/shifts',
        body: {
          ...p.input,
          'selections': [
            {'templateId': draft['id'], 'revisionId': draft['revisionId']},
          ],
        },
        expected: 422,
      );
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      final second = newUuid();
      await f.call(
        'POST',
        '/shifts',
        body: {...p.input, 'id': second},
        expected: 201,
      );
      final results = await Future.wait([
        for (final id in [p.id, second])
          f.call(
            'POST',
            '/shifts/$id/publish',
            body: {'expectedVersion': 1},
            expected: null,
          ),
      ]);
      expect(results.map((r) => r.status).toList()..sort(), [200, 409]);
      final empty = newUuid();
      await f.call(
        'POST',
        '/shifts',
        body: {...p.input, 'id': empty, 'selections': <Map<String, dynamic>>[]},
        expected: 201,
      );
      await f.call(
        'POST',
        '/shifts/$empty/publish',
        body: {'expectedVersion': 1},
        expected: 422,
      );
      final adjacent = newUuid();
      await f.call(
        'POST',
        '/shifts',
        body: {
          ...p.input,
          'id': adjacent,
          'startsAt': p.input['endsAt'],
          'endsAt': DateTime.parse(
            p.input['endsAt'] as String,
          ).add(const Duration(hours: 1)).toIso8601String(),
        },
        expected: 201,
      );
      await f.call(
        'POST',
        '/shifts/$adjacent/publish',
        body: {'expectedVersion': 1},
      );
      final inactive = await f.employee('Inactive');
      await f.call(
        'POST',
        '/employees/${inactive.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'POST',
        '/shifts',
        body: {...p.input, 'id': newUuid(), 'employeeId': inactive.id},
        expected: 422,
      );
    }),
    skip: _skip,
  );

  test(
    'bounded pages and current employee home omit old shifts and instruction bodies',
    () => _withFixture((f) async {
      final p = await _plan(f);
      final token = await _linkedAccount(f, p.employee, 'paged_worker');
      final start = DateTime.parse(p.input['startsAt'] as String);
      for (var i = 0; i < 51; i++) {
        final id = newUuid();
        await f.call(
          'POST',
          '/shifts',
          body: {
            ...p.input,
            'id': id,
            'startsAt': start.add(Duration(hours: i * 2)).toIso8601String(),
            'endsAt': start.add(Duration(hours: i * 2 + 1)).toIso8601String(),
          },
          expected: 201,
        );
        await f.call(
          'POST',
          '/shifts/$id/publish',
          body: {'expectedVersion': 1},
        );
      }
      for (final route in ['/shifts', '/employee-home/shifts']) {
        final credential = route == '/shifts' ? f.adminToken : token;
        final first = (await f.call('GET', route, token: credential)).body;
        final last = (await f.call(
          'GET',
          '$route?after=${Uri.encodeQueryComponent(first['nextCursor'] as String)}',
          token: credential,
        )).body;
        expect(first['items'], hasLength(50));
        expect(last['items'], hasLength(1));
        expect(last['nextCursor'], isNull);
        expect(jsonEncode(first), isNot(contains('Check equipment')));
        expect(
          [
            ...first['items'] as List,
            ...last['items'] as List,
          ].map((v) => v['shift']['id']).toSet(),
          hasLength(51),
        );
      }
      await f.call('GET', '/shifts?after=invalid', expected: 400);
    }),
    skip: _skip,
  );

  test(
    '0006 upgrades a populated 0005 database without altering existing records',
    () => _withFixture((f) async {
      final p = await _plan(f);
      Future<List<String>> state() async => [
        for (final table in [
          'accounts',
          'employees',
          'task_templates',
          'task_template_revisions',
          'audit_entries',
        ])
          (await f.owner.execute(
                'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id),\'[]\'::jsonb)::text FROM "${f.schema}".$table t',
              )).single.first
              as String,
      ];
      final before = await state();
      final runner = MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      );
      expect(await runner.apply(), [
        '0006_shifts_and_task_instances',
        '0007_task_execution',
        '0008_task_blocking',
        '0009_task_cancellation',
        '0010_task_numeric_steps',
        '0011_published_shift_cancellation',
        '0012_published_shift_amendment',
        '0013_article_master',
        '0014_location_assortment',
      ]);
      expect(await runner.apply(), isEmpty);
      expect(await state(), before);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
    }, legacy: true),
    skip: _skip,
  );
}

Map<String, dynamic> _draft(Map<String, dynamic> input) => Map.from(input)
  ..remove('id')
  ..remove('locationId');

class _Plan {
  _Plan(this.employee, this.template, this.input);
  final EmployeeDto employee;
  final Map<String, dynamic> template, input;
  String get id => input['id'] as String;
}

Future<_Plan> _plan(
  _Fixture f, {
  bool numeric = false,
  int numericSteps = 1,
  int steps = 1,
}) async {
  final employee = await f.employee('Planned employee'), template = _input();
  for (var i = 1; i < steps; i++) {
    (template['content']['steps'] as List).add({
      'id': newUuid(),
      'type': 'confirmation',
      'instruction': 'Step ${i + 1}',
    });
  }
  if (numeric) {
    template['content']['schemaVersion'] = 2;
    for (var i = 0; i < numericSteps; i++) {
      template['content']['steps'][i].addAll({
        'type': 'number',
        'unit': 'C',
        'minimum': '-2.125',
        'maximum': '4.5',
      });
    }
  }
  await f.call('POST', '/task-templates', body: template, expected: 201);
  await f.call(
    'POST',
    '/task-templates/${template['id']}/revisions/${template['revisionId']}/publish',
    body: {'expectedVersion': 1},
  );
  final start = DateTime.now().toUtc().add(const Duration(days: 1));
  return _Plan(employee, template, {
    'id': newUuid(),
    'locationId': _home,
    'employeeId': employee.id,
    'startsAt': start.toIso8601String(),
    'endsAt': start.add(const Duration(hours: 8)).toIso8601String(),
    'selections': [
      {'templateId': template['id'], 'revisionId': template['revisionId']},
    ],
  });
}

Future<String> _linkedAccount(
  _Fixture f,
  EmployeeDto employee,
  String name,
) async {
  final account = await f.account(name);
  await f.call(
    'POST',
    '/employees/${employee.id}/account-link',
    body: {
      'id': newUuid(),
      'accountId': account.id,
      'expectedEmployeeVersion': employee.version,
      'expectedAccountVersion': account.version,
    },
    expected: 201,
  );
  return f.login(name);
}

Future<String> _seedPublishedShift(
  _Fixture f,
  _Plan p, {
  required DateTime start,
  Duration duration = const Duration(hours: 8),
}) async {
  final id = newUuid(), taskId = newUuid();
  await f.owner.execute(
    Sql.named(
      'INSERT INTO "${f.schema}".shifts(id,company_id,location_id,employee_id,'
      'starts_at,ends_at,status,version,created_by,creation_input) '
      'VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),'
      'CAST(@employee AS uuid),@start,@end,\'draft\',1,CAST(@admin AS uuid),@input)',
    ),
    parameters: {
      'id': id,
      'company': _company,
      'location': _home,
      'employee': p.employee.id,
      'start': start,
      'end': start.add(duration),
      'admin': f.adminPrincipal.id,
      'input': jsonEncode(Map<String, dynamic>.from(p.input)..remove('id')),
    },
  );
  await f.owner.execute(
    Sql.named(
      'INSERT INTO "${f.schema}".shift_template_selections'
      '(shift_id,company_id,location_id,template_id,revision_id,position) '
      'VALUES(CAST(@shift AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),'
      'CAST(@template AS uuid),CAST(@revision AS uuid),0)',
    ),
    parameters: {
      'shift': id,
      'company': _company,
      'location': _home,
      'template': p.template['id'],
      'revision': p.template['revisionId'],
    },
  );
  await f.owner.execute(
    Sql.named(
      'INSERT INTO "${f.schema}".task_instances(id,company_id,location_id,'
      'shift_id,employee_id,template_id,revision_id,position,content) '
      'VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),'
      'CAST(@shift AS uuid),CAST(@employee AS uuid),CAST(@template AS uuid),'
      'CAST(@revision AS uuid),0,@content)',
    ),
    parameters: {
      'id': taskId,
      'company': _company,
      'location': _home,
      'shift': id,
      'employee': p.employee.id,
      'template': p.template['id'],
      'revision': p.template['revisionId'],
      'content': jsonEncode(p.template['content']),
    },
  );
  p.input['id'] = id;
  await f.owner.execute(
    Sql.named(
      'UPDATE "${f.schema}".shifts SET status=\'published\',version=2,'
      'published_at=clock_timestamp(),published_by=CAST(@admin AS uuid),'
      'publication_version=1 WHERE id=CAST(@id AS uuid)',
    ),
    parameters: {'id': id, 'admin': f.adminPrincipal.id},
  );
  return taskId;
}

/// Seeds one extra shift/task pair in a terminal execution state without going
/// through the API. [startsAt]/[endsAt] of blocked clones must not overlap
/// another published shift of the same employee (database invariant).
Future<void> _seedTaskState(
  _Fixture f, {
  required String sourceShift,
  required String sourceTask,
  required DateTime startsAt,
  required DateTime endsAt,
  required String state,
}) async {
  final shift = newUuid(), task = newUuid(), actor = f.adminPrincipal.id;
  if (state == 'cancelled') {
    await f.owner.execute(
      Sql.named('''INSERT INTO "${f.schema}".shifts
        (id,company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version,cancelled_at,cancelled_by,cancellation_reason,cancellation_version)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,@start,@end,'cancelled',3,created_by,creation_input,published_at,published_by,publication_version,clock_timestamp(),CAST(@actor AS uuid),'Seeded cancellation',2
        FROM "${f.schema}".shifts WHERE id=CAST(@source AS uuid)'''),
      parameters: {
        'id': shift,
        'source': sourceShift,
        'start': startsAt,
        'end': endsAt,
        'actor': actor,
      },
    );
    await f.owner.execute(
      Sql.named('''INSERT INTO "${f.schema}".task_instances
        (id,company_id,location_id,employee_id,shift_id,template_id,revision_id,position,content,status,version,cancelled_at,cancelled_by)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,CAST(@shift AS uuid),template_id,revision_id,position,content,'cancelled',2,clock_timestamp(),CAST(@actor AS uuid)
        FROM "${f.schema}".task_instances WHERE id=CAST(@source AS uuid)'''),
      parameters: {
        'id': task,
        'shift': shift,
        'source': sourceTask,
        'actor': actor,
      },
    );
    return;
  }
  await f.owner.execute(
    Sql.named('''INSERT INTO "${f.schema}".shifts
      (id,company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version)
      SELECT CAST(@id AS uuid),company_id,location_id,employee_id,@start,@end,'published',2,created_by,creation_input,published_at,published_by,publication_version
      FROM "${f.schema}".shifts WHERE id=CAST(@source AS uuid)'''),
    parameters: {
      'id': shift,
      'source': sourceShift,
      'start': startsAt,
      'end': endsAt,
    },
  );
  await f.owner.execute(
    Sql.named('''INSERT INTO "${f.schema}".task_instances
      (id,company_id,location_id,employee_id,shift_id,template_id,revision_id,position,content)
      SELECT CAST(@id AS uuid),company_id,location_id,employee_id,CAST(@shift AS uuid),template_id,revision_id,position,content
      FROM "${f.schema}".task_instances WHERE id=CAST(@source AS uuid)'''),
    parameters: {'id': task, 'shift': shift, 'source': sourceTask},
  );
  await f.owner.execute(
    Sql.named(
      'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=2,'
      'started_at=@at,started_by=CAST(@actor AS uuid) '
      'WHERE id=CAST(@task AS uuid)',
    ),
    parameters: {'at': startsAt, 'actor': actor, 'task': task},
  );
  await f.owner.execute(
    Sql.named('''INSERT INTO "${f.schema}".task_step_results
      (instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by,accepted_version)
      SELECT id,company_id,location_id,(content::jsonb->'steps'->0->>'id')::uuid,0,@at,CAST(@actor AS uuid),3
      FROM "${f.schema}".task_instances WHERE id=CAST(@task AS uuid)'''),
    parameters: {'at': startsAt, 'actor': actor, 'task': task},
  );
  await f.owner.execute(
    Sql.named(
      'UPDATE "${f.schema}".task_instances SET version=3 '
      'WHERE id=CAST(@task AS uuid)',
    ),
    parameters: {'task': task},
  );
  await f.owner.execute(
    Sql.named('''INSERT INTO "${f.schema}".task_blockings
      (id,instance_id,company_id,location_id,step_id,reason,reported_at,reported_by,reported_version)
      SELECT CAST(@id AS uuid),id,company_id,location_id,NULL,'Seeded obstacle',@at,CAST(@actor AS uuid),4
      FROM "${f.schema}".task_instances WHERE id=CAST(@task AS uuid)'''),
    parameters: {'id': newUuid(), 'at': startsAt, 'actor': actor, 'task': task},
  );
  await f.owner.execute(
    Sql.named(
      'UPDATE "${f.schema}".task_instances SET status=\'blocked\',version=4 '
      'WHERE id=CAST(@task AS uuid)',
    ),
    parameters: {'task': task},
  );
}

Future<({String root, String task, String token, _Plan plan})>
_legacyExecutionPlan(
  _Fixture f, {
  Duration duration = const Duration(hours: 1),
}) async {
  final p = await _plan(f);
  final task = await _seedPublishedShift(
    f,
    p,
    start: p.employee.assignedFrom,
    duration: duration,
  );
  return (
    root: '/employee-home/shifts/${p.id}/tasks/$task',
    task: task,
    token: await _linkedAccount(f, p.employee, 'executor'),
    plan: p,
  );
}

Map<String, dynamic> _content([String title = 'Opening']) => {
  'schemaVersion': 1,
  'title': title,
  'steps': [
    {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'type': 'confirmation',
      'instruction': 'Check equipment',
    },
  ],
};
Map<String, dynamic> _input() => {
  'id': newUuid(),
  'revisionId': newUuid(),
  'locationId': _home,
  'content': _content(),
};

Object get _skip => _url == null ? 'STOREOS_TEST_DATABASE is not set' : false;

class _Reply {
  _Reply(this.status, this.body, this.correlation);
  final int status;
  final Map<String, dynamic> body;
  final String? correlation;
}

class _Fixture {
  _Fixture(this.owner, this.pool, this.schema, this.runtimeUser);
  final Connection owner;
  final Pool<void> pool;
  final String schema, runtimeUser;
  final HttpClient client = HttpClient();
  late PlatformDatabase database;
  late SessionPrincipal adminPrincipal;
  late AuthService auth;
  HttpServer? server;
  String? adminToken;
  String get base => 'http://127.0.0.1:${server!.port}';

  Future<void> restart() async {
    await server?.close(force: true);
    final store = PostgresAuthStore(pool, schemaName: schema);
    auth = await AuthService.create(
      store: store,
      companyId: _company,
      locationId: _home,
      sessionTtl: const Duration(hours: 1),
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
    );
    database = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: _company,
      locationId: _home,
    );
    final app = ServerApp(
      config: const ServerConfig(
        database: DatabaseConfig(
          host: 'localhost',
          port: 5432,
          name: 'unused',
          user: 'unused',
          password: 'unused',
        ),
        companyId: _company,
        locationId: _home,
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
  }

  Future<_Reply> call(
    String method,
    String route, {
    Map<String, dynamic>? body,
    String? token,
    int? expected = 200,
    bool platform = true,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('$base${platform ? '/api/v1/platform' : ''}$route'),
    );
    final credential = token ?? adminToken;
    if (credential != null && credential.isNotEmpty) {
      request.headers.set('authorization', 'Bearer $credential');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (expected != null) {
      expect(response.statusCode, expected, reason: '$method $route: $text');
    }
    return _Reply(
      response.statusCode,
      text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>,
      response.headers.value('x-request-id'),
    );
  }

  Future<String> login(String username) async =>
      (await call(
            'POST',
            '/api/v1/auth/login',
            platform: false,
            body: {'username': username, 'password': _password},
          )).body['token']
          as String;
  Future<EmployeeDto> employee(String name) async => EmployeeDto.fromJson(
    (await call(
      'POST',
      '/employees',
      expected: 201,
      body: {'id': newUuid(), 'displayName': name, 'locationId': _home},
    )).body,
  );
  Future<PlatformUserDto> account(
    String username, {
    String role = 'employee',
    String location = _home,
  }) async => PlatformUserDto.fromJson(
    (await call(
      'POST',
      '/users',
      expected: 201,
      body: {
        'id': newUuid(),
        'username': username,
        'password': _password,
        'locationId': location,
        'role': role,
      },
    )).body,
  );
}

Future<void> _withFixture(
  Future<void> Function(_Fixture) action, {
  bool legacy = false,
  String legacyBefore = '0006',
}) async {
  final uri = Uri.parse(_url!);
  final split = uri.userInfo.indexOf(':');
  final endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.single,
    username: Uri.decodeComponent(uri.userInfo.substring(0, split)),
    password: Uri.decodeComponent(uri.userInfo.substring(split + 1)),
  );
  if (!endpoint.database.endsWith('_test')) {
    throw StateError('An explicit *_test database is required.');
  }
  final runtime = Platform.environment['STOREOS_DB_USER'] ?? 'storeos';
  final secret = File(
    Platform.environment['STOREOS_DB_PASSWORD_FILE']!,
  ).readAsStringSync().trim();
  final owner = await Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final schema = 'storeos_shifts_${newUuid().replaceAll('-', '')}';
  final pool = Pool<void>.withEndpoints(
    [
      Endpoint(
        host: endpoint.host,
        port: endpoint.port,
        database: endpoint.database,
        username: runtime,
        password: secret,
      ),
    ],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 4,
    ),
  );
  final fixture = _Fixture(owner, pool, schema, runtime);
  Directory? legacyDirectory;
  if (legacy) {
    legacyDirectory = await Directory.systemTemp.createTemp(
      'storeos_shifts_legacy_',
    );
    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (file.uri.pathSegments.last.compareTo(legacyBefore) < 0) {
        await file.copy(
          '${legacyDirectory.path}/${file.uri.pathSegments.last}',
        );
      }
    }
  }

  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: legacyDirectory ?? Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: runtime,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
      schemaName: schema,
    ).bootstrap(
      username: 'test_admin',
      password: _password,
      companyId: _company,
      locationId: _home,
    );
    await fixture.restart();
    fixture.adminToken = await fixture.login('test_admin');
    fixture.adminPrincipal = await fixture.auth.authenticate(
      fixture.adminToken,
    );
    await fixture.call(
      'POST',
      '/organization/setup',
      body: {'companyName': 'Employee test company', 'locationName': 'Home'},
    );
    await fixture.call(
      'POST',
      '/locations',
      expected: 201,
      body: {'id': _other, 'name': 'Other location'},
    );
    await action(fixture);
  } finally {
    fixture.client.close(force: true);
    await fixture.server?.close(force: true);
    await pool.close();
    await owner.execute('DROP SCHEMA "$schema" CASCADE');
    await owner.close();
    await legacyDirectory?.delete(recursive: true);
  }
}
