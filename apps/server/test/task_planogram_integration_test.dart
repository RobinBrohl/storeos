import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'merchandising_integration_test.dart' as m;
import 'task_knowledge_fixture.dart';
import 'task_knowledge_additional_cases.dart' show queuedCompanyRace;
import 'task_planogram_fixture.dart';
import 'package:storeos_server/src/application/shift_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/merchandising/merchandising_service.dart';
import 'package:storeos_server/src/http/merchandising_routes.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/config.dart';
import 'package:shelf/shelf.dart';

class _FaultSelector extends MerchandisingService {
  _FaultSelector(super.database);
  @override
  Future<Map<String, dynamic>> guidanceSelection(
    SessionPrincipal p,
    String location,
    String id,
  ) async {
    throw StateError('Injected selector internal fault');
  }
}

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'STOREOS_TEST_DATABASE required';
  test(
    'configured Location scope denies real retained B work at A and permits B again',
    () => withMerchandisingFixture((f) async {
      // The default execution Location is B. All business evidence is API-created.
      final d = await deployment(
        f,
        fixtureName: 'Private B fixture descriptor',
        articleName: 'Private B article label',
      );
      await f.openStock(d.articleId, quantity: '12.5');
      final s = await planogramTaskScenario(f, selectedDeployment: d);
      final content =
          (await f.call('GET', s.templateRoute)).body['revision']['content']
              as Map<String, dynamic>;
      final draftId = newUuid(),
          draftRevision = newUuid(),
          freshShift = newUuid();
      final draftRoute = '/task-templates/$draftId/revisions/$draftRevision';
      await f.call(
        'POST',
        '/task-templates',
        expected: 201,
        body: {
          'id': draftId,
          'revisionId': draftRevision,
          'locationId': merchandisingTestLocation,
          'content': content,
        },
      );
      final later = DateTime.now().toUtc().add(const Duration(hours: 2));
      await f.call(
        'POST',
        '/shifts',
        expected: 201,
        body: {
          'id': freshShift,
          'locationId': merchandisingTestLocation,
          'employeeId': s.employeeId,
          'startsAt': later.toIso8601String(),
          'endsAt': later.add(const Duration(hours: 1)).toIso8601String(),
          'selections': [
            {'templateId': s.templateId, 'revisionId': s.templateRevisionId},
          ],
        },
      );
      final a = await f.createLocation('Execution A');
      await f.call(
        'POST',
        '/users',
        expected: 201,
        body: {
          'id': newUuid(),
          'username': 'scope_admin_a',
          'password': merchandisingTestPassword,
          'locationId': a,
          'role': 'admin',
        },
      );
      final originalTasks = await rowCount(f, 'task_instances');
      var originalAudit = await rowCount(f, 'audit_entries');
      Future<void> allowed() async {
        for (final route in [
          '${s.templateRoute}/planogram',
          '${s.managerTask}/planogram',
        ]) {
          final layout = RetainedLayoutDto.fromJson(
            (await f.call('GET', route)).body,
          );
          expect(layout.instruction.pin.sameAs(d.pin), isTrue);
          expect(
            layout.currentContext.fixtureName,
            'Private B fixture descriptor',
          );
          expect(
            layout.currentContext.articles.single['name'],
            'Private B article label',
          );
          expect(
            layout.currentContext.articles.single['stock']['quantity'],
            '12.5',
          );
        }
        await f.call('GET', '${s.employeeTask}/planogram', token: s.token);
        await f.call(
          'POST',
          '${s.templateRoute}/publish',
          body: {'expectedVersion': 1},
        );
        final replay = await f.call(
          'POST',
          '/shifts/${s.shiftId}/publish',
          body: {'expectedVersion': 1},
        );
        expect(replay.body['tasks'][0]['id'], s.taskId);
        expect(await rowCount(f, 'task_instances'), originalTasks);
        expect(await rowCount(f, 'audit_entries'), originalAudit);
      }

      await allowed();
      await f.restart(locationId: a);
      f.adminToken = await f.login('scope_admin_a');
      originalAudit = await rowCount(f, 'audit_entries');
      expect((await f.call('GET', '/context')).body['locationId'], a);
      Future<void> denied(
        String method,
        String route, {
        Map<String, dynamic>? body,
      }) async {
        final reply = await f.call(method, route, body: body, expected: 403);
        expect(reply.body['code'], 'forbidden');
        final encoded = jsonEncode(reply.body);
        for (final secret in [
          'Private B fixture descriptor',
          'Private B article label',
          '12.5',
          d.pin.assignmentId,
          d.pin.revisionId,
        ]) {
          expect(encoded, isNot(contains(secret)), reason: route);
        }
      }

      for (final route in [
        '${s.templateRoute}/planogram',
        '$draftRoute/planogram',
        '${s.managerTask}/planogram',
        '${m.froot}/${d.fixtureId}/guidance-selection',
      ]) {
        await denied('GET', route);
      }
      await denied('POST', '$draftRoute/publish', body: {'expectedVersion': 1});
      await denied(
        'POST',
        '/shifts/$freshShift/publish',
        body: {'expectedVersion': 1},
      );
      await denied(
        'POST',
        '${s.templateRoute}/publish',
        body: {'expectedVersion': 1},
      );
      await denied(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      await denied(
        'POST',
        '/task-templates/${s.templateId}/revisions',
        body: {'id': newUuid(), 'expectedVersion': 2},
      );
      await denied(
        'POST',
        '$draftRoute/edit',
        body: {
          'expectedVersion': 1,
          'content': {...content, 'title': 'Unchanged retained pin edit'},
        },
      );
      final replacement = {
        ...content,
        'planogramGuidance': {...d.pin.toJson(), 'assignmentId': newUuid()},
      };
      await denied(
        'POST',
        '$draftRoute/edit',
        body: {'expectedVersion': 1, 'content': replacement},
      );
      await denied(
        'POST',
        '/task-templates',
        body: {
          'id': newUuid(),
          'revisionId': newUuid(),
          'locationId': merchandisingTestLocation,
          'content': content,
        },
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: s.token,
        expected: 403,
      );
      // A mandatory layout-table outage cannot precede the scope denial.
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".merchandising_fixtures FROM "${f.runtimeUser}"',
      );
      await denied('GET', '${s.templateRoute}/planogram');
      await denied('GET', '${s.managerTask}/planogram');
      await denied('POST', '$draftRoute/publish', body: {'expectedVersion': 1});
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".merchandising_fixtures TO "${f.runtimeUser}"',
      );
      expect(await rowCount(f, 'task_instances'), originalTasks);
      expect(await rowCount(f, 'audit_entries'), originalAudit);
      await f.restart();
      f.adminToken = await f.login('test_admin');
      originalAudit = await rowCount(f, 'audit_entries');
      await allowed();
      await replaceDeployment(f, d);
      await retireDeployment(f, d);
      var lifecycleAudit = await rowCount(f, 'audit_entries');
      for (final route in [
        '${s.templateRoute}/planogram',
        '${s.managerTask}/planogram',
      ]) {
        final retained = RetainedLayoutDto.fromJson(
          (await f.call('GET', route)).body,
        );
        expect(retained.instruction.pin.sameAs(d.pin), isTrue);
        expect(retained.currentContext.reassigned, isTrue);
        expect(retained.currentContext.fixtureRetired, isTrue);
        expect(retained.currentContext.planogramRetired, isTrue);
      }
      await f.call('GET', '${s.employeeTask}/planogram', token: s.token);
      await f.call(
        'POST',
        '${s.templateRoute}/publish',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      expect(await rowCount(f, 'task_instances'), originalTasks);
      expect(await rowCount(f, 'audit_entries'), lifecycleAudit);
      // Lifecycle exception does not turn off current scope for reads or replay.
      await f.restart(locationId: a);
      f.adminToken = await f.login('scope_admin_a');
      lifecycleAudit = await rowCount(f, 'audit_entries');
      await denied('GET', '${s.templateRoute}/planogram');
      await denied('GET', '${s.managerTask}/planogram');
      await denied(
        'POST',
        '${s.templateRoute}/publish',
        body: {'expectedVersion': 1},
      );
      await denied(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      expect(await rowCount(f, 'task_instances'), originalTasks);
      expect(await rowCount(f, 'audit_entries'), lifecycleAudit);
      await f.restart();
      f.adminToken = await f.login('test_admin');
      lifecycleAudit = await rowCount(f, 'audit_entries');
      await f.call('GET', '${s.managerTask}/planogram');
      await f.call(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      expect(await rowCount(f, 'task_instances'), originalTasks);
      expect(await rowCount(f, 'audit_entries'), lifecycleAudit);
    }),
    skip: skip,
  );
  test(
    'selector internal fault uses bounded 500 without changing lifecycle behavior',
    () => withMerchandisingFixture((f) async {
      final app = ServerApp(
        config: ServerConfig(
          database: const DatabaseConfig(
            host: 'localhost',
            port: 5432,
            name: 'unused',
            user: 'unused',
            password: 'unused',
          ),
          companyId: merchandisingTestCompany,
          locationId: merchandisingTestLocation,
        ),
        auth: f.auth,
        store: PostgresAuthStore(f.pool, schemaName: f.schema),
        platformHandler: MerchandisingRoutes(
          f.auth,
          _FaultSelector(f.database),
        ).router.call,
      );
      final response = await app.handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/api/v1/platform/locations/$merchandisingTestLocation/merchandising/fixtures/${newUuid()}/guidance-selection',
          ),
          headers: {'authorization': 'Bearer ${f.adminToken}'},
        ),
      );
      expect(response.statusCode, 500);
      expect(
        (jsonDecode(await response.readAsString()) as Map)['code'],
        'internal_error',
      );
    }),
    skip: skip,
  );
  test(
    'current deployment selector validates lifecycle without opening arbitrary history',
    () => withMerchandisingFixture((f) async {
      final d = await deployment(f),
          route = '${m.froot}/${d.fixtureId}/guidance-selection';
      await f.account('selector_employee');
      final selectorToken = await f.login('selector_employee');
      final before = await rowCount(f, 'audit_entries');
      final view = LayoutViewDto.fromJson((await f.call('GET', route)).body);
      expect(view.assignment!.id, d.pin.assignmentId);
      await f.call('GET', route, token: selectorToken, expected: 403);
      await f.call('GET', route, token: '', expected: 401);
      await f.call(
        'GET',
        '${m.froot}/${newUuid()}/guidance-selection',
        expected: 404,
      );
      await f.call(
        'GET',
        '${m.froot}/malformed/guidance-selection',
        expected: 400,
      );
      await f.call(
        'GET',
        '$route?revisionId=${d.pin.revisionId}',
        expected: 400,
      );
      expect(await rowCount(f, 'audit_entries'), before);
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".merchandising_planogram_revisions FROM "${f.runtimeUser}"',
      );
      expect(
        (await f.call('GET', route, expected: 503)).body['code'],
        'database_unavailable',
      );
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".merchandising_planogram_revisions TO "${f.runtimeUser}"',
      );
      await retireDeployment(f, d, fixture: false);
      expect(
        (await f.call('GET', route, expected: 422)).body['code'],
        'planogram_selection_unavailable',
      );
      await retireDeployment(f, d, planogram: false);
      expect(
        (await f.call('GET', route, expected: 422)).body['code'],
        'planogram_selection_unavailable',
      );
      final empty = await m.fixture(f, name: 'Unassigned selector fixture');
      expect(
        (await f.call(
          'GET',
          '${m.froot}/${empty['id']}/guidance-selection',
          expected: 422,
        )).body['code'],
        'planogram_selection_unavailable',
      );
      for (final kind in [
        'retireFixture',
        'deactivateArticle',
        'deactivateAssortment',
      ]) {
        final unavailable = await deployment(f);
        await invalidate(f, unavailable, kind);
        expect(
          (await f.call(
            'GET',
            '${m.froot}/${unavailable.fixtureId}/guidance-selection',
            expected: 422,
          )).body['code'],
          'planogram_selection_unavailable',
          reason: kind,
        );
      }
      final published = await planogramTaskScenario(f);
      expect(
        (await f.call(
          'POST',
          '${published.templateRoute}/publish',
          body: {'expectedVersion': 999},
          expected: 409,
        )).body['code'],
        'template_conflict',
      );
      expect(
        (await f.call(
          'POST',
          '/shifts/${published.shiftId}/publish',
          body: {'expectedVersion': 999},
          expected: 409,
        )).body['code'],
        'shift_conflict',
      );
    }),
    skip: skip,
  );
  test(
    'scope, removed employee link, wrong location, plugin and infrastructure errors match OpenAPI',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f);
      final app = ShiftApplication(f.database);
      final foreign = SessionPrincipal(
        id: f.adminId,
        username: 'foreign',
        companyId: newUuid(),
        locationId: merchandisingTestLocation,
      );
      await expectLater(
        app.planogram(foreign, s.shiftId, s.taskId!, self: false),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      final link =
          (await f.call(
                'GET',
                '/employees/${s.employeeId}/account-link',
              )).body['link']
              as Map;
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: s.token,
        expected: 401,
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: await f.login('guided_worker'),
        expected: 404,
      );
      final location = await f.createLocation('Other execution location');
      final otherAccount = newUuid(), otherEmployee = newUuid();
      await f.call(
        'POST',
        '/users',
        expected: 201,
        body: {
          'id': otherAccount,
          'username': 'other_location_worker',
          'password': merchandisingTestPassword,
          'locationId': location,
          'role': 'employee',
        },
      );
      await f.call(
        'POST',
        '/employees',
        expected: 201,
        body: {
          'id': otherEmployee,
          'displayName': 'Other location worker',
          'locationId': location,
        },
      );
      await f.call(
        'POST',
        '/employees/$otherEmployee/account-link',
        expected: 201,
        body: {
          'id': newUuid(),
          'accountId': otherAccount,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: await f.login('other_location_worker'),
        expected: 403,
      );
      const pluginId = 'guidance.denied-plugin';
      await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': pluginId,
            'name': 'Guidance denied plugin',
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
      final plugin =
          (await f.call(
                'POST',
                '/plugins/$pluginId/approve',
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
        '${s.managerTask}/planogram',
        token: plugin,
        expected: 401,
      );
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".merchandising_planogram_revisions FROM "${f.runtimeUser}"',
      );
      await f.call('GET', '${s.managerTask}/planogram', expected: 503);
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".merchandising_planogram_revisions TO "${f.runtimeUser}"',
      );
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".guidance_read_fault() RETURNS boolean LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'test integrity\' USING ERRCODE=\'23514\'; END \$\$; ALTER TABLE "${f.schema}".merchandising_planogram_revisions ENABLE ROW LEVEL SECURITY; ALTER TABLE "${f.schema}".merchandising_planogram_revisions FORCE ROW LEVEL SECURITY; CREATE POLICY guidance_read_fault ON "${f.schema}".merchandising_planogram_revisions USING ("${f.schema}".guidance_read_fault())',
        queryMode: QueryMode.simple,
      );
      await f.call('GET', '${s.managerTask}/planogram', expected: 500);
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".merchandising_planogram_revisions DISABLE ROW LEVEL SECURITY',
      );
      final doc =
          jsonDecode(
                File(
                  '../../packages/api_contracts/platform.openapi.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final self in [true, false]) {
        final path =
            '/api/v1/platform/${self ? 'employee-home/' : ''}shifts/{id}/tasks/{task}/planogram';
        final operation = doc['paths'][path]['get'] as Map;
        expect(
          (operation['responses'] as Map).keys,
          containsAll(['200', '400', '401', '403', '404', '500', '503']),
        );
        expect(
          (operation['parameters'] as List).where((p) => p['in'] == 'query'),
          isEmpty,
        );
      }
    }),
    skip: skip,
  );

  test(
    'real Flutter HTTP PostgreSQL exact deployment journey',
    () => withMerchandisingFixture((f) async {
      final employee = await prepareGuidedWorker(f);
      final d = await deployment(f);
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        ['test', '--no-pub', 'test/task_planogram_http_journey.dart'],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: {
          'STOREOS_P47_JOURNEY_URL': f.base,
          'STOREOS_KNOWLEDGE_JOURNEY_PASSWORD': merchandisingTestPassword,
          'STOREOS_GUIDANCE_EMPLOYEE': employee,
        },
      );
      stdout.write(
        result.stdout.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      stderr.write(
        result.stderr.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      expect(result.exitCode, 0);
      final row = (await f.owner.execute(
        'SELECT status,planogram_assignment_id::text,planogram_revision_id::text,knowledge_revision_id IS NOT NULL FROM "${f.schema}".task_instances',
      )).single;
      expect(row.toList(), [
        'completed',
        d.pin.assignmentId,
        d.pin.revisionId,
        true,
      ]);
      expect(await rowCount(f, 'task_execution_commands'), 4);
      await f.restart();
      final task = (await f.owner.execute(
        'SELECT id::text,shift_id::text FROM "${f.schema}".task_instances',
      )).single;
      final read = RetainedLayoutDto.fromJson(
        (await f.call(
          'GET',
          '/employee-home/shifts/${task[1]}/tasks/${task[0]}/planogram',
          token: await f.login('guided_worker'),
        )).body,
      );
      expect(read.instruction.pin.toJson(), d.pin.toJson());
      expect(read.currentContext.reassigned, true);
      expect(read.currentContext.fixtureRetired, true);
    }),
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'exact historical deployment survives replacement retirement completion replay and restart with independent Knowledge',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f, knowledge: true),
          pin = s.deployment.pin;
      final original = RetainedLayoutDto.fromJson(
        (await f.call(
          'GET',
          '${s.employeeTask}/planogram',
          token: s.token,
        )).body,
      );
      final template = (await f.call('GET', s.templateRoute)).body['revision'];
      final r2 = await replaceDeployment(f, s.deployment);
      final current = LayoutViewDto.fromJson(
        (await f.call(
          'GET',
          '${m.froot}/${pin.fixtureId}/layout',
          token: s.token,
        )).body,
      );
      expect(current.assignment!.id, r2.assignmentId);
      expect(current.revision!.content.title, 'Replacement layout R2');
      expect(original.instruction.content.title, 'Original layout R1');
      await replaceInstruction(f, s.knowledge!.article.id);
      await retireInstruction(f, s.knowledge!.article.id);
      await retireDeployment(f, s.deployment);
      final audit = await rowCount(f, 'audit_entries');
      for (final route in [s.employeeTask, s.managerTask, (s.templateRoute)]) {
        final layout = RetainedLayoutDto.fromJson(
          (await f.call(
            'GET',
            '$route/planogram',
            token: route == s.employeeTask ? s.token : null,
          )).body,
        );
        expect(layout.instruction.toJson(), original.instruction.toJson());
        expect(layout.currentContext.reassigned, true);
        expect(layout.currentContext.fixtureRetired, true);
        expect(layout.currentContext.planogramRetired, true);
        expect(jsonEncode(layout.toJson()), isNot(contains('assignedBy')));
      }
      expect(
        (await f.call(
          'POST',
          '${s.templateRoute}/publish',
          body: {'expectedVersion': 1},
        )).body['revision'],
        template,
      );
      final replay = await f.call(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      expect(replay.body['tasks'][0]['id'], s.taskId);
      expect(await rowCount(f, 'audit_entries'), audit);
      expect(await rowCount(f, 'task_instances'), 1);
      final knowledge = TaskKnowledgeDto.fromJson(
        (await f.call(
          'GET',
          '${s.employeeTask}/knowledge',
          token: s.token,
        )).body,
      );
      expect(knowledge.revisionId, s.knowledge!.revision.id);
      expect(knowledge.articleRetired, true);
      await completePlanogramTask(f, s);
      final rows = await f.owner.execute(
        'SELECT content,status,planogram_fixture_id::text,planogram_assignment_id::text,planogram_revision_id::text FROM "${f.schema}".task_instances',
      );
      expect(rows.single[1], 'completed');
      expect(rows.single.skip(2), [
        pin.fixtureId,
        pin.assignmentId,
        pin.revisionId,
      ]);
      expect(rows.single[0], isNot(contains('Original layout R1')));
      final completion =
          (await f.owner.execute(
                "SELECT changes FROM \"${f.schema}\".audit_entries WHERE action='tasks.instance.completed'",
              )).single.first
              as Map;
      expect(completion['planogramAssignmentId'], pin.assignmentId);
      expect(completion['knowledgeRevisionId'], s.knowledge!.revision.id);
      expect(await rowCount(f, 'task_execution_commands'), 4);
      await f.restart();
      final retained = RetainedLayoutDto.fromJson(
        (await f.call(
          'GET',
          '${s.employeeTask}/planogram',
          token: await f.login('guided_worker'),
        )).body,
      );
      expect(retained.instruction.toJson(), original.instruction.toJson());
    }),
    skip: skip,
  );

  for (final target in ['template', 'shift']) {
    for (final change in [
      'reassign',
      'retireFixture',
      'retirePlanogram',
      'deactivateArticle',
      'deactivateAssortment',
    ]) {
      test(
        '$change rejects fresh $target publication atomically but retained editing remains possible',
        () => withMerchandisingFixture((f) async {
          final s = await planogramTaskScenario(
            f,
            publishTemplate: target == 'shift',
            publishShift: false,
          );
          await invalidate(f, s.deployment, change);
          final count = await rowCount(f, 'audit_entries');
          final result = await f.call(
            'POST',
            target == 'template'
                ? '${s.templateRoute}/publish'
                : '/shifts/${s.shiftId}/publish',
            body: {'expectedVersion': 1},
            expected: 422,
          );
          expect(result.body['code'], 'planogram_guidance_unavailable');
          expect(await rowCount(f, 'audit_entries'), count);
          expect(await rowCount(f, 'task_instances'), 0);
          if (target == 'template') {
            final before = (await f.call('GET', s.templateRoute)).body;
            expect(before['template']['version'], 1);
            expect(before['revision']['status'], 'draft');
            await f.call(
              'POST',
              '${s.templateRoute}/edit',
              body: {
                'expectedVersion': 1,
                'content': {
                  ...before['revision']['content'] as Map,
                  'title': 'Retained editable pin',
                },
              },
            );
            expect(
              (await f.call(
                'GET',
                s.templateRoute,
              )).body['revision']['content']['planogramGuidance'],
              s.deployment.pin.toJson(),
            );
          } else {
            expect(
              (await f.call(
                'GET',
                '/shifts/${s.shiftId}',
              )).body['shift']['status'],
              'draft',
            );
          }
        }),
        skip: skip,
      );
    }
  }
  test(
    'publishing R2 alone permits A1 and reassigning away/back never revives A1',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f, publishTemplate: false);
      final published = await replaceDeployment(f, s.deployment, assign: false);
      await f.call(
        'POST',
        '${s.templateRoute}/publish',
        body: {'expectedVersion': 1},
      );
      final draftId = newUuid();
      await f.call(
        'POST',
        '/task-templates/${s.templateId}/revisions',
        body: {'id': draftId, 'expectedVersion': 2},
        expected: 201,
      );
      await assignDeployment(f, s.deployment.fixtureId, published.revisionId);
      final a3 = await assignDeployment(
        f,
        s.deployment.fixtureId,
        s.deployment.pin.revisionId,
      );
      expect(a3.assignmentId, isNot(s.deployment.pin.assignmentId));
      expect(
        (await f.call(
          'POST',
          '/task-templates/${s.templateId}/revisions/$draftId/publish',
          body: {'expectedVersion': 3},
          expected: 422,
        )).body['code'],
        'planogram_guidance_unavailable',
      );
    }),
    skip: skip,
  );

  for (final operation in ['create', 'replace']) {
    test(
      '$operation selection errors preserve saved input and evidence',
      () => withMerchandisingFixture((f) async {
        final s = await planogramTaskScenario(f, publishTemplate: false),
            other = await deployment(f);
        final stale = s.deployment.pin;
        await replaceDeployment(f, s.deployment);
        if (operation == 'replace') {
          final saved = (await f.call('GET', s.templateRoute)).body;
          await f.call(
            'POST',
            '${s.templateRoute}/edit',
            body: {
              'expectedVersion': 1,
              'content': {
                ...saved['revision']['content'] as Map,
                'planogramGuidance': null,
              },
            },
          );
        }
        final raw = (await f.call('GET', s.templateRoute)).body,
            audit = await rowCount(f, 'audit_entries');
        for (final pin in [
          stale,
          PlanogramGuidance(
            fixtureId: stale.fixtureId,
            assignmentId: other.pin.assignmentId,
            revisionId: other.pin.revisionId,
          ),
          PlanogramGuidance(
            fixtureId: other.fixtureId,
            assignmentId: other.pin.assignmentId,
            revisionId: stale.revisionId,
          ),
        ]) {
          final result = await f.call(
            'POST',
            operation == 'create'
                ? '/task-templates'
                : '${s.templateRoute}/edit',
            expected: 422,
            body: {
              if (operation == 'create') ...{
                'id': newUuid(),
                'revisionId': newUuid(),
                'locationId': merchandisingTestLocation,
              } else
                'expectedVersion': raw['template']['version'],
              'content': {
                ...raw['revision']['content'] as Map,
                'planogramGuidance': pin.toJson(),
              },
            },
          );
          expect(result.body['code'], 'planogram_selection_unavailable');
          expect(await rowCount(f, 'audit_entries'), audit);
          expect((await f.call('GET', s.templateRoute)).body, raw);
        }
      }),
      skip: skip,
    );
  }
  test(
    'historical contextual authorization guesses missing pins queries and revoked session',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f);
      for (final route in [
        '${s.employeeTask}/planogram',
        '${s.managerTask}/planogram',
        '${s.templateRoute}/planogram',
      ]) {
        await f.call('GET', route, token: '', expected: 401);
        await f.call(
          'GET',
          '$route?assignmentId=${s.deployment.pin.assignmentId}',
          expected: 400,
        );
        for (final role in ['viewer', 'auditor']) {
          final name = '${role}_${route.hashCode.abs()}';
          await f.account(name, role: role);
          await f.call('GET', route, token: await f.login(name), expected: 403);
        }
      }
      final other = await guidedScenario(
        f,
        workerName: 'other_guidance_worker',
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: other.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${s.shiftId}/tasks/${other.task}/planogram',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/shifts/${s.shiftId}/tasks/${other.task}/planogram',
        expected: 404,
      );
      await f.account('unlinked');
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: await f.login('unlinked'),
        expected: 404,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${newUuid()}/tasks/${s.taskId}/planogram',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${s.shiftId}/tasks/${newUuid()}/planogram',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/shifts/invalid/tasks/${s.taskId}/planogram',
        expected: 400,
      );
      await f.call(
        'GET',
        '${s.managerTask}/planogram',
        token: s.token,
        expected: 403,
      );
      await f.call(
        'GET',
        '${s.templateRoute}/planogram',
        token: s.token,
        expected: 403,
      );
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        token: s.token,
        expected: 204,
        platform: false,
      );
      await f.call(
        'GET',
        '${s.employeeTask}/planogram',
        token: s.token,
        expected: 401,
      );
    }),
    skip: skip,
  );
  test(
    'schema 4 without layout retains normal execution and returns bounded missing-pin error',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f, guidance: false);
      for (final route in [s.employeeTask, s.managerTask, s.templateRoute]) {
        await f.call(
          'GET',
          '$route/planogram',
          token: route == s.employeeTask ? s.token : null,
          expected: 404,
        );
      }
      await completePlanogramTask(f, s);
    }),
    skip: skip,
  );
  test(
    'optional Stock absent zero and permission outage preserve exact instructions',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f);
      Future<RetainedLayoutDto> read() async => RetainedLayoutDto.fromJson(
        (await f.call(
          'GET',
          '${s.employeeTask}/planogram',
          token: s.token,
        )).body,
      );
      final absent = await read();
      expect(absent.currentContext.articles.single['stock'], null);
      await f.openStock(s.deployment.articleId, quantity: '0');
      final zero = await read();
      expect(zero.currentContext.articles.single['stock']['quantity'], '0');
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".stock_levels FROM "${f.runtimeUser}"',
      );
      final unavailable = await read();
      expect(
        unavailable.currentContext.stockContextStatus,
        StockContextStatus.unavailable,
      );
      expect(unavailable.instruction.toJson(), absent.instruction.toJson());
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".stock_levels TO "${f.runtimeUser}"',
      );
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".merchandising_planogram_assignments FROM "${f.runtimeUser}"',
      );
      await f.call('GET', '${s.managerTask}/planogram', expected: 503);
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".merchandising_planogram_assignments TO "${f.runtimeUser}"',
      );
    }),
    skip: skip,
  );

  test(
    'durable FK generated identities immutable snapshots and strict content reject forged tuples',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f), other = await deployment(f);
      final source =
          (await f.call('GET', s.templateRoute)).body['revision']['content']
              as Map;
      final freshTemplate = newUuid(), freshRevision = newUuid();
      await f.call(
        'POST',
        '/task-templates',
        expected: 201,
        body: {
          'id': freshTemplate,
          'revisionId': freshRevision,
          'locationId': merchandisingTestLocation,
          'content': {...source, 'planogramGuidance': null},
        },
      );
      await f.call(
        'POST',
        '/task-templates/$freshTemplate/revisions/$freshRevision/publish',
        body: {'expectedVersion': 1},
      );
      Future<void> insert(
        Map pin, {
        String? company,
        String? location,
      }) async => f.owner.execute(
        Sql.named(
          'INSERT INTO "${f.schema}".task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)',
        ),
        parameters: {
          'id': newUuid(),
          'template': freshTemplate,
          'company': company ?? merchandisingTestCompany,
          'location': location ?? merchandisingTestLocation,
          'content': jsonEncode({...source, 'planogramGuidance': pin}),
        },
      );
      final company =
          (await f.owner.execute(
                'SELECT company_id::text FROM "${f.schema}".task_instances',
              )).single.first
              as String;
      for (final pin in [
        {...s.deployment.pin.toJson(), 'fixtureId': other.fixtureId},
        {...s.deployment.pin.toJson(), 'revisionId': other.pin.revisionId},
        {...s.deployment.pin.toJson(), 'assignmentId': other.pin.assignmentId},
      ]) {
        await expectLater(
          insert(pin, company: company),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'tuple FK', '23503'),
          ),
        );
      }
      for (final scope in ['company', 'location']) {
        await expectLater(
          insert(
            s.deployment.pin.toJson(),
            company: scope == 'company' ? newUuid() : company,
            location: scope == 'location'
                ? newUuid()
                : merchandisingTestLocation,
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'scope FK', '23503'),
          ),
        );
      }
      for (final bad in [
        {...s.deployment.pin.toJson()}..remove('fixtureId'),
        {...s.deployment.pin.toJson(), 'fixtureId': 'bad'},
      ]) {
        await expectLater(
          insert(bad, company: company),
          throwsA(isA<ServerException>()),
        );
      }
      final columns = (await f.owner.execute(
        'SELECT planogram_fixture_id::text,planogram_assignment_id::text,planogram_revision_id::text FROM "${f.schema}".task_instances',
      )).single;
      expect(columns, [
        s.deployment.pin.fixtureId,
        s.deployment.pin.assignmentId,
        s.deployment.pin.revisionId,
      ]);
      await expectLater(
        f.owner.execute(
          "UPDATE \"${f.schema}\".task_instances SET planogram_revision_id='${other.pin.revisionId}'",
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          "UPDATE \"${f.schema}\".task_instances SET content='${jsonEncode({...source, 'planogramGuidance': other.pin.toJson()})}'",
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          "UPDATE \"${f.schema}\".task_template_revisions SET content='${jsonEncode({...source, 'planogramGuidance': other.pin.toJson()})}' WHERE id='${s.templateRevisionId}'",
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          "INSERT INTO \"${f.schema}\".task_instances(id,company_id,location_id,shift_id,employee_id,template_id,revision_id,position,content) SELECT '${newUuid()}',company_id,location_id,shift_id,employee_id,template_id,revision_id,2,'${jsonEncode({...source, 'planogramGuidance': other.pin.toJson()})}' FROM \"${f.schema}\".task_instances LIMIT 1",
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.constraintName,
            'snapshot',
            'task_guidance_snapshot',
          ),
        ),
      );
      await f.pool.run((tx) async {
        await expectLater(
          tx.execute(
            "UPDATE \"${f.schema}\".task_instances SET content=content",
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'runtime content permission',
              '42501',
            ),
          ),
        );
      });
    }),
    skip: skip,
  );

  for (final target in ['template', 'shift']) {
    for (final change in ['reassign', 'retireFixture', 'retirePlanogram']) {
      for (final changeFirst in [false, true]) {
        test(
          'queued $change vs $target publication change first=$changeFirst',
          () => withMerchandisingFixture((f) async {
            final s = await planogramTaskScenario(
              f,
              publishTemplate: target == 'shift',
              publishShift: false,
            );
            final r2 = change == 'reassign'
                ? await replaceDeployment(f, s.deployment, assign: false)
                : null;
            final path = change == 'retirePlanogram'
                ? '${m.proot}/${s.deployment.planogramId}'
                : '${m.froot}/${s.deployment.fixtureId}';
            final resource = (await f.call('GET', path)).body;
            Future<MerchandisingReply> changed() => f.call(
              'POST',
              '$path/${change == 'reassign' ? 'assignments' : 'retire'}',
              expected: null,
              body: {
                'expectedVersion': resource['version'],
                if (r2 != null) ...{
                  'operationId': newUuid(),
                  'revisionId': r2.revisionId,
                },
              },
            );
            Future<MerchandisingReply> published() => f.call(
              'POST',
              target == 'template'
                  ? '${s.templateRoute}/publish'
                  : '/shifts/${s.shiftId}/publish',
              expected: null,
              body: {'expectedVersion': 1},
            );
            final result = await queuedCompanyRace(
              f,
              changeFirst ? changed : published,
              changeFirst ? published : changed,
            );
            expect(result[0].status, 200);
            expect(result[1].status, changeFirst ? 422 : 200);
            expect(
              await rowCount(f, 'task_instances'),
              target == 'shift' && !changeFirst ? 1 : 0,
            );
            if (target == 'shift' && !changeFirst) {
              final task = result[0].body['tasks'][0]['id'];
              final retained = RetainedLayoutDto.fromJson(
                (await f.call(
                  'GET',
                  '/shifts/${s.shiftId}/tasks/$task/planogram',
                )).body,
              );
              expect(
                retained.instruction.pin.toJson(),
                s.deployment.pin.toJson(),
              );
            }
          }),
          skip: skip,
        );
      }
    }
  }
  for (final target in ['template', 'shift']) {
    test(
      'unknown audit integrity fault rolls back $target publication with 500',
      () => withMerchandisingFixture((f) async {
        final s = await planogramTaskScenario(
              f,
              publishTemplate: target == 'shift',
              publishShift: false,
            ),
            audit = await rowCount(f, 'audit_entries');
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".p47_audit_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'test defect\' USING ERRCODE=\'23514\'; END \$\$; CREATE TRIGGER p47_audit_fault BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p47_audit_fault()',
          queryMode: QueryMode.simple,
        );
        await f.call(
          'POST',
          target == 'template'
              ? '${s.templateRoute}/publish'
              : '/shifts/${s.shiftId}/publish',
          body: {'expectedVersion': 1},
          expected: 500,
        );
        expect(await rowCount(f, 'audit_entries'), audit);
        expect(await rowCount(f, 'task_instances'), 0);
      }),
      skip: skip,
    );
  }
  test(
    'duplicate publication uses original tasks and pristine amendment preserves stale pin',
    () => withMerchandisingFixture((f) async {
      final s = await planogramTaskScenario(f, publishShift: false),
          audit = await rowCount(f, 'audit_entries');
      Future<MerchandisingReply> publish() => f.call(
        'POST',
        '/shifts/${s.shiftId}/publish',
        body: {'expectedVersion': 1},
      );
      final results = await queuedCompanyRace(f, publish, publish);
      expect(results[0].body, results[1].body);
      expect(await rowCount(f, 'audit_entries'), audit + 2);
      final before = (await f.owner.execute(
        'SELECT content FROM "${f.schema}".task_instances',
      )).single.first;
      await replaceDeployment(f, s.deployment);
      final shift = ShiftDto.fromJson(
        results[0].body['shift'] as Map<String, dynamic>,
      );
      await f.call(
        'POST',
        '/shifts/${s.shiftId}/amend',
        body: {
          'expectedVersion': shift.version,
          'startsAt': shift.draft.startsAt
              .add(const Duration(minutes: 1))
              .toIso8601String(),
          'endsAt': shift.draft.endsAt
              .add(const Duration(minutes: 1))
              .toIso8601String(),
        },
      );
      expect(
        (await f.owner.execute(
          'SELECT content FROM "${f.schema}".task_instances',
        )).single.first,
        before,
      );
    }),
    skip: skip,
  );

  for (final editFirst in [true, false]) {
    test(
      'queued exact-pin replacement vs Template publication edit first=$editFirst',
      () => withMerchandisingFixture((f) async {
        final scenario = await planogramTaskScenario(
              f,
              publishTemplate: false,
              publishShift: false,
            ),
            other = await deployment(f);
        final raw = (await f.call('GET', scenario.templateRoute)).body;
        final audit = await rowCount(f, 'audit_entries');
        Future<MerchandisingReply> edit() => f.call(
          'POST',
          '${scenario.templateRoute}/edit',
          expected: null,
          body: {
            'expectedVersion': 1,
            'content': {
              ...raw['revision']['content'] as Map,
              'planogramGuidance': other.pin.toJson(),
            },
          },
        );
        Future<MerchandisingReply> publish() => f.call(
          'POST',
          '${scenario.templateRoute}/publish',
          expected: null,
          body: {'expectedVersion': 1},
        );
        final result = await queuedCompanyRace(
          f,
          editFirst ? edit : publish,
          editFirst ? publish : edit,
        );
        expect(result[0].status, 200);
        expect(result[1].status, 409);
        final retained = (await f.call('GET', scenario.templateRoute)).body;
        expect(
          retained['revision']['status'],
          editFirst ? 'draft' : 'published',
        );
        expect(
          retained['revision']['content']['planogramGuidance'],
          (editFirst ? other.pin : scenario.deployment.pin).toJson(),
        );
        expect(retained['template']['version'], 2);
        expect(await rowCount(f, 'audit_entries'), audit + 1);
        expect(await rowCount(f, 'task_instances'), 0);
      }),
      skip: skip,
    );
  }
  test(
    'populated 0018 migration failure rolls back and successful 0019 preserves source evidence',
    () => withMerchandisingFixture((f) async {
      final schema3 = await guidedScenario(f, workerName: 'legacy3');
      await f.call(
        'POST',
        '${schema3.employeeTask}/start',
        token: schema3.token,
        body: {'operationId': newUuid(), 'expectedVersion': 1},
      );
      for (final state in ['open', 'blocked', 'completed', 'cancelled']) {
        final legacy = await guidedScenario(
          f,
          schema: state == 'open' ? 1 : 2,
          guidance: false,
          workerName: 'legacy_$state',
        );
        if (state == 'open') continue;
        var version = 1;
        Future<void> command(String route, {String? value}) async {
          await f.call(
            'POST',
            '${legacy.employeeTask}/$route',
            token: legacy.token,
            body: {
              'operationId': newUuid(),
              'expectedVersion': version++,
              'value': ?value,
            },
          );
        }

        await command('start');
        await command('steps/${legacy.steps[0]}/confirm');
        if (state == 'completed') {
          await command('steps/${legacy.steps[1]}/record-number', value: '3');
          await command('complete');
        } else {
          await command('steps/${legacy.steps[1]}/record-number', value: '6');
          if (state == 'cancelled') {
            await f.call(
              'POST',
              '${legacy.managerTask}/cancel',
              body: {
                'operationId': newUuid(),
                'expectedVersion': 4,
                'reason': 'Legacy cancellation evidence',
              },
            );
          }
        }
      }
      await guidedScenario(
        f,
        schema: 1,
        guidance: false,
        publishTemplate: false,
        workerName: 'legacy_draft',
      );
      Future<List<Object?>> source() async {
        final result = <Object?>[];
        for (final table in [
          'task_template_revisions',
          'task_instances',
          'task_execution_commands',
          'task_step_results',
          'task_numeric_attempts',
          'task_blockings',
          'audit_entries',
        ]) {
          result.add(
            (await f.owner.execute(
              "SELECT jsonb_agg(to_jsonb(t)-'planogram_fixture_id'-'planogram_assignment_id'-'planogram_revision_id' ORDER BY ${table == 'task_execution_commands'
                  ? 'operation_id'
                  : table == 'task_step_results'
                  ? 'instance_id,position'
                  : 'id'})::text FROM \"${f.schema}\".$table t",
            )).single.first,
          );
        }
        return result;
      }

      final before = await source(),
          temp = await Directory.systemTemp.createTemp(
            'storeos_p47_migrations_',
          );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${temp.path}/${file.uri.pathSegments.last}');
        }
        final target = File('${temp.path}/0019_task_planogram_guidance.sql');
        await target.writeAsString(
          '${await target.readAsString()}\nSELECT 1/0;',
        );
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: temp,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<ServerException>()),
        );
        expect(await rowCount(f, 'schema_migrations'), 18);
        expect(await source(), before);
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM information_schema.columns WHERE table_schema='${f.schema}' AND column_name='planogram_assignment_id'",
          )).single.first,
          0,
        );
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          [
            '0019_task_planogram_guidance',
            '0020_stock_counts',
            '0021_recipe_compositions',
          ],
        );
        expect(await source(), before);
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".task_instances WHERE planogram_assignment_id IS NOT NULL',
          )).single.first,
          0,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    }, legacyBefore: '0019_task_planogram_guidance.sql'),
    skip: skip,
  );
}

Future<void> invalidate(
  MerchandisingFixture f,
  DeploymentScenario d,
  String kind,
) async {
  switch (kind) {
    case 'reassign':
      await replaceDeployment(f, d);
    case 'retireFixture':
      await retireDeployment(f, d, planogram: false);
    case 'retirePlanogram':
      await retireDeployment(f, d, fixture: false);
    case 'deactivateArticle':
      final article = ArticleDto.fromJson(
        (await f.call('GET', '/articles/${d.articleId}')).body,
      );
      await f.call(
        'POST',
        '/articles/${d.articleId}/deactivate',
        body: {'expectedVersion': article.version},
      );
    case 'deactivateAssortment':
      final page = (await f.call(
        'GET',
        '/locations/$merchandisingTestLocation/assortment',
      )).body;
      final membership = (page['items'] as List).singleWhere(
        (a) => a['article']['id'] == d.articleId,
      );
      await f.call(
        'POST',
        '/locations/$merchandisingTestLocation/assortment/${membership['id']}/deactivate',
        body: {'expectedVersion': membership['version']},
      );
  }
}
