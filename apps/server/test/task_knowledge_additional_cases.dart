import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/shift_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'task_knowledge_fixture.dart';

void taskKnowledgeAdditionalCases(Object skip) {
  for (final path in ['create', 'replace']) {
    test(
      '$path unavailable guidance returns selection error without mutation or audit',
      () => withMerchandisingFixture((f) async {
        final s = await guidedScenario(f, publishTemplate: false);
        final superseded = await makeInstruction(f);
        await replaceInstruction(f, superseded.article.id);
        final retired = await makeInstruction(f);
        await retireInstruction(f, retired.article.id);
        final raw = (await f.call(
          'GET',
          '/task-templates/${s.template}/revisions/${s.revision}',
        )).body;
        final counts = {
          for (final table in [
            'task_templates',
            'task_template_revisions',
            'task_instances',
            'audit_entries',
          ])
            table: await rowCount(f, table),
        };
        final template = newUuid(), revision = newUuid();
        for (final pin in [
          KnowledgeGuidance(
            articleId: retired.article.id,
            revisionId: retired.revision.id,
          ),
          KnowledgeGuidance(
            articleId: superseded.article.id,
            revisionId: superseded.revision.id,
          ),
          KnowledgeGuidance(
            articleId: s.instruction.article.id,
            revisionId: newUuid(),
          ),
        ]) {
          final content = {
            ...raw['revision']['content'] as Map,
            'title': 'Unsaved selection input',
            'knowledgeGuidance': pin.toJson(),
          };
          final result = await f.call(
            'POST',
            path == 'create'
                ? '/task-templates'
                : '/task-templates/${s.template}/revisions/${s.revision}/edit',
            expected: 422,
            body: {
              if (path == 'create') ...{
                'id': template,
                'revisionId': revision,
                'locationId': merchandisingTestLocation,
              } else
                'expectedVersion': 1,
              'content': content,
            },
          );
          expect(result.body['code'], 'guidance_selection_unavailable');
          expect(result.body['code'], isNot('guidance_unavailable'));
          for (final entry in counts.entries) {
            expect(await rowCount(f, entry.key), entry.value);
          }
          expect(
            (await f.call(
              'GET',
              '/task-templates/${s.template}/revisions/${s.revision}',
            )).body,
            raw,
          );
          if (path == 'create') {
            await f.call('GET', '/task-templates/$template', expected: 404);
          }
        }
      }),
      skip: skip,
    );
  }
  for (final target in ['template', 'shift']) {
    test(
      'unknown unique audit defect rolls back $target publication with 500',
      () => withMerchandisingFixture((f) async {
        final s = await guidedScenario(
              f,
              publishTemplate: target == 'shift',
              publishShift: false,
            ),
            count = await rowCount(f, 'audit_entries');
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".unknown_guidance_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'test unknown unique defect\' USING ERRCODE=\'23505\',CONSTRAINT=\'p46_unknown_unique_fault\'; END \$\$; CREATE TRIGGER unknown_guidance_fault BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".unknown_guidance_fault()',
          queryMode: QueryMode.simple,
        );
        final result = await f.call(
          'POST',
          target == 'template'
              ? s.templatePublish
              : '/shifts/${s.shift}/publish',
          body: {'expectedVersion': 1},
          expected: 500,
        );
        expect(result.body['code'], 'internal_error');
        expect(await rowCount(f, 'audit_entries'), count);
        expect(await rowCount(f, 'task_instances'), 0);
        if (target == 'template') {
          expect(
            (await f.call(
              'GET',
              '/task-templates/${s.template}/revisions/${s.revision}',
            )).body['revision']['status'],
            'draft',
          );
        } else {
          expect(
            (await f.call('GET', '/shifts/${s.shift}')).body['shift']['status'],
            'draft',
          );
        }
      }),
      skip: skip,
    );
  }
  test(
    'company mismatch cannot retain a published Knowledge pin',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishShift: false);
      final content =
          (await f.call(
                'GET',
                '/task-templates/${s.template}/revisions/${s.revision}',
              )).body['revision']['content']
              as Map;
      await expectLater(
        f.owner.execute(
          Sql.named(
            'INSERT INTO "${f.schema}".task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)',
          ),
          parameters: {
            'id': newUuid(),
            'template': s.template,
            'company': newUuid(),
            'location': merchandisingTestLocation,
            'content': jsonEncode(content),
          },
        ),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'foreign key', '23503'),
        ),
      );
      final fk =
          (await f.owner.execute(
                "SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE connamespace='${f.schema}'::regnamespace AND conname='task_revision_knowledge_fk'",
              )).single.first
              as String;
      expect(
        fk,
        contains(
          'knowledge_revision_id, company_id, knowledge_article_id, knowledge_revision_state',
        ),
      );
    }),
    skip: skip,
  );
  test(
    'fresh selection rejects foreign, missing, draft and discarded revisions; replace and retired clone',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishTemplate: false);
      final other = await makeInstruction(f);
      final draft = WikiRevisionResultDto.fromJson(
        (await f.call(
          'POST',
          '$knowledgeRoot/${other.article.id}/revisions',
          expected: 201,
          body: NewWikiDraftRequest(newUuid(), 2).toJson(),
        )).body,
      );
      final raw = (await f.call(
        'GET',
        '/task-templates/${s.template}/revisions/${s.revision}',
      )).body;
      final content = Map<String, dynamic>.from(
        raw['revision']['content'] as Map,
      );
      final sqlTemplate = newUuid();
      await f.owner.execute(
        Sql.named(
          'INSERT INTO "${f.schema}".task_templates(id,company_id,location_id) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid))',
        ),
        parameters: {
          'id': sqlTemplate,
          'company': f.database.companyId,
          'location': merchandisingTestLocation,
        },
      );
      final pins = [
        KnowledgeGuidance(
          articleId: other.article.id,
          revisionId: s.instruction.revision.id,
        ),
        KnowledgeGuidance(
          articleId: other.article.id,
          revisionId: draft.revision.id,
        ),
        KnowledgeGuidance(
          articleId: s.instruction.article.id,
          revisionId: newUuid(),
        ),
        KnowledgeGuidance(
          articleId: newUuid(),
          revisionId: s.instruction.revision.id,
        ),
      ];
      for (final pin in pins) {
        final result = await f.call(
          'POST',
          '/task-templates/${s.template}/revisions/${s.revision}/edit',
          expected: 422,
          body: {
            'expectedVersion': 1,
            'content': {...content, 'knowledgeGuidance': pin.toJson()},
          },
        );
        expect(result.body['code'], 'guidance_selection_unavailable');
        await expectLater(
          f.owner.execute(
            Sql.named(
              'INSERT INTO "${f.schema}".task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)',
            ),
            parameters: {
              'id': newUuid(),
              'template': sqlTemplate,
              'company': f.database.companyId,
              'location': merchandisingTestLocation,
              'content': jsonEncode({
                ...content,
                'knowledgeGuidance': pin.toJson(),
              }),
            },
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'foreign key',
              '23503',
            ),
          ),
        );
      }
      await f.call(
        'POST',
        '$knowledgeRoot/${other.article.id}/revisions/${draft.revision.id}/discard',
        body: WikiVersionRequest(3).toJson(),
      );
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/${s.revision}/edit',
        expected: 422,
        body: {
          'expectedVersion': 1,
          'content': {...content, 'knowledgeGuidance': pins[1].toJson()},
        },
      );
      await expectLater(
        f.owner.execute(
          Sql.named(
            'INSERT INTO "${f.schema}".task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)',
          ),
          parameters: {
            'id': newUuid(),
            'template': sqlTemplate,
            'company': f.database.companyId,
            'location': merchandisingTestLocation,
            'content': jsonEncode({
              ...content,
              'knowledgeGuidance': pins[1].toJson(),
            }),
          },
        ),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'foreign key', '23503'),
        ),
      );
      content['knowledgeGuidance'] = {
        'articleId': other.article.id,
        'revisionId': other.revision.id,
      };
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/${s.revision}/edit',
        body: {'expectedVersion': 1, 'content': content},
      );
      await f.call('POST', s.templatePublish, body: {'expectedVersion': 2});
      await retireInstruction(f, other.article.id);
      final clone = (await f.call(
        'POST',
        '/task-templates/${s.template}/revisions',
        expected: 201,
        body: {'id': newUuid(), 'expectedVersion': 3},
      )).body;
      expect(
        clone['revision']['content']['knowledgeGuidance'],
        content['knowledgeGuidance'],
      );
      final rid = clone['revision']['id'];
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/$rid/edit',
        body: {
          'expectedVersion': 4,
          'content': {...content, 'title': 'Editable retired clone'},
        },
      );
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/$rid/publish',
        body: {'expectedVersion': 5},
        expected: 422,
      );
    }),
    skip: skip,
  );

  test(
    'scope, removed employee link, wrong location, plugin and infrastructure errors match OpenAPI',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f);
      final app = ShiftApplication(f.database);
      final foreign = SessionPrincipal(
        id: f.adminId,
        username: 'foreign',
        companyId: newUuid(),
        locationId: merchandisingTestLocation,
      );
      await expectLater(
        app.knowledge(foreign, s.shift, s.task!, self: false),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      final link =
          (await f.call(
                'GET',
                '/employees/${s.employee}/account-link',
              )).body['link']
              as Map;
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      await f.call(
        'GET',
        '${s.employeeTask}/knowledge',
        token: s.token,
        expected: 401,
      );
      await f.call(
        'GET',
        '${s.employeeTask}/knowledge',
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
        '${s.employeeTask}/knowledge',
        token: await f.login('other_location_worker'),
        expected: 404,
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
        '${s.managerTask}/knowledge',
        token: plugin,
        expected: 401,
      );
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".knowledge_revisions FROM "${f.runtimeUser}"',
      );
      await f.call('GET', '${s.managerTask}/knowledge', expected: 503);
      await f.owner.execute(
        'GRANT SELECT ON "${f.schema}".knowledge_revisions TO "${f.runtimeUser}"',
      );
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".guidance_read_fault() RETURNS boolean LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'test integrity\' USING ERRCODE=\'23514\'; END \$\$; ALTER TABLE "${f.schema}".knowledge_revisions ENABLE ROW LEVEL SECURITY; ALTER TABLE "${f.schema}".knowledge_revisions FORCE ROW LEVEL SECURITY; CREATE POLICY guidance_read_fault ON "${f.schema}".knowledge_revisions USING ("${f.schema}".guidance_read_fault())',
        queryMode: QueryMode.simple,
      );
      await f.call('GET', '${s.managerTask}/knowledge', expected: 500);
      await f.owner.execute(
        'ALTER TABLE "${f.schema}".knowledge_revisions DISABLE ROW LEVEL SECURITY',
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
            '/api/v1/platform/${self ? 'employee-home/' : ''}shifts/{id}/tasks/{task}/knowledge';
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

  for (final target in ['template', 'shift']) {
    for (final retireFirst in [true, false]) {
      test(
        'queued retirement vs $target publication (retirement first=$retireFirst)',
        () => withMerchandisingFixture((f) async {
          final s = await guidedScenario(
            f,
            publishTemplate: target != 'template',
            publishShift: false,
          );
          Future<MerchandisingReply> retired() => f.call(
            'POST',
            '$knowledgeRoot/${s.instruction.article.id}/retire',
            expected: null,
            body: WikiVersionRequest(2).toJson(),
          );
          Future<MerchandisingReply> published() => f.call(
            'POST',
            target == 'template'
                ? s.templatePublish
                : '/shifts/${s.shift}/publish',
            expected: null,
            body: {'expectedVersion': 1},
          );
          final results = await queuedCompanyRace(
            f,
            retireFirst ? retired : published,
            retireFirst ? published : retired,
          );
          expect(results[0].status, 200);
          expect(results[1].status, retireFirst ? 422 : 200);
          expect(
            await rowCount(f, 'task_instances'),
            target == 'shift' && !retireFirst ? 1 : 0,
          );
          if (target == 'shift' && !retireFirst) {
            final task = results[0].body['tasks'][0]['id'];
            final read = TaskKnowledgeDto.fromJson(
              (await f.call(
                'GET',
                '/shifts/${s.shift}/tasks/$task/knowledge',
              )).body,
            );
            expect(read.revisionId, s.instruction.revision.id);
            expect(read.articleRetired, true);
          }
        }),
        skip: skip,
      );
    }
  }
  test(
    'queued template edit vs publication preserves exactly one accepted version',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishTemplate: false);
      final content =
          (await f.call(
                'GET',
                '/task-templates/${s.template}/revisions/${s.revision}',
              )).body['revision']['content']
              as Map;
      final result = await queuedCompanyRace(
        f,
        () => f.call(
          'POST',
          '/task-templates/${s.template}/revisions/${s.revision}/edit',
          expected: null,
          body: {
            'expectedVersion': 1,
            'content': {...content, 'title': 'Concurrent edit'},
          },
        ),
        () => f.call(
          'POST',
          s.templatePublish,
          expected: null,
          body: {'expectedVersion': 1},
        ),
      );
      expect(result.map((r) => r.status), [200, 409]);
      expect(
        (await f.call(
          'GET',
          '/task-templates/${s.template}/revisions/${s.revision}',
        )).body['revision']['status'],
        'draft',
      );
    }),
    skip: skip,
  );
  test(
    'queued duplicate shift publication returns identical tasks without duplicate audit',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishShift: false),
          before = await rowCount(f, 'audit_entries');
      Future<MerchandisingReply> publish() => f.call(
        'POST',
        '/shifts/${s.shift}/publish',
        body: {'expectedVersion': 1},
      );
      final results = await queuedCompanyRace(f, publish, publish);
      expect(results[0].body, results[1].body);
      expect(await rowCount(f, 'task_instances'), 1);
      expect(await rowCount(f, 'audit_entries'), before + 2);
    }),
    skip: skip,
  );
}

/// Hold the actual company writer lock, observe both queued waiters, then release.
/// No timer/sleep decides ordering. A separate owner connection observes pg_locks.
Future<List<MerchandisingReply>> queuedCompanyRace(
  MerchandisingFixture f,
  Future<MerchandisingReply> Function() first,
  Future<MerchandisingReply> Function() second,
) async {
  final uri = Uri.parse(Platform.environment['STOREOS_TEST_DATABASE']!),
      split = uri.userInfo.indexOf(':');
  final observer = await Connection.open(
    Endpoint(
      host: uri.host,
      port: uri.port,
      database: uri.pathSegments.single,
      username: Uri.decodeComponent(uri.userInfo.substring(0, split)),
      password: Uri.decodeComponent(uri.userInfo.substring(split + 1)),
    ),
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final acquired = Completer<void>(), release = Completer<void>();
  final key = 'storeos_platform:${f.schema}:${f.database.companyId}';
  final held = f.owner.runTx((tx) async {
    await tx.execute(
      Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
      parameters: {'key': key},
    );
    acquired.complete();
    await release.future;
  });
  Future<void> queued(int count) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (true) {
      final rows = await observer.execute(
        Sql.named(
          'SELECT count(*) FROM pg_locks WHERE locktype=\'advisory\' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid',
        ),
        parameters: {'key': key},
      );
      if ((rows.single.first as int) >= count) return;
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Writer did not reach lock barrier.');
      }
    }
  }

  try {
    await acquired.future;
    final a = first();
    await queued(1);
    final b = second();
    await queued(2);
    release.complete();
    await held;
    return await Future.wait([a, b]);
  } finally {
    if (!release.isCompleted) release.complete();
    await held;
    await observer.close();
  }
}
