import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'task_knowledge_additional_cases.dart';

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'STOREOS_TEST_DATABASE required';
  taskKnowledgeAdditionalCases(skip);
  test(
    'real Flutter authoring and historical task journey',
    () => withMerchandisingFixture((f) async {
      final employee = await prepareGuidedWorker(f);
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        ['test', '--no-pub', 'test/task_knowledge_http_journey.dart'],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: {
          'STOREOS_KNOWLEDGE_JOURNEY_URL': f.base,
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
      final rows = await f.owner.execute(
        'SELECT t.id::text,t.content,t.status,r.revision_number,a.status FROM "${f.schema}".task_instances t JOIN "${f.schema}".knowledge_revisions r ON r.id=t.knowledge_revision_id JOIN "${f.schema}".knowledge_articles a ON a.id=t.knowledge_article_id',
      );
      expect(rows, hasLength(1));
      expect(rows.single[2], 'completed');
      expect(rows.single[3], 1);
      expect(rows.single[4], 'retired');
      final pin = TaskTemplateContent.fromJson(
        jsonDecode(rows.single[1] as String) as Map<String, dynamic>,
      ).knowledgeGuidance!;
      await f.restart();
      final shift = (await f.owner.execute(
        'SELECT shift_id::text FROM "${f.schema}".task_instances',
      )).single.first;
      final read = TaskKnowledgeDto.fromJson(
        (await f.call(
          'GET',
          '/employee-home/shifts/$shift/tasks/${rows.single[0]}/knowledge',
          token: await f.login('guided_worker'),
        )).body,
      );
      expect(read.revisionId, pin.revisionId);
      expect(read.superseded, true);
      expect(read.articleRetired, true);
      expect(await rowCount(f, 'task_execution_commands'), 4);
    }),
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'stored v1 survives replacement, retirement, completion replay and restart',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f);
      final beforeAudit = await rowCount(f, 'audit_entries');
      TaskKnowledgeDto read(MerchandisingReply r) =>
          TaskKnowledgeDto.fromJson(r.body);
      final first = read(
        await f.call('GET', '${s.employeeTask}/knowledge', token: s.token),
      );
      expect(first.revisionId, s.instruction.revision.id);
      expect(first.body, instructionBody);
      expect(first.superseded, false);
      expect(first.articleRetired, false);
      expect(await rowCount(f, 'audit_entries'), beforeAudit);
      final committedTemplate = (await f.call(
        'GET',
        '/task-templates/${s.template}/revisions/${s.revision}',
      )).body['revision'];
      final v2 = await replaceInstruction(f, s.instruction.article.id);
      await retireInstruction(f, s.instruction.article.id);
      for (final route in [s.employeeTask, s.managerTask]) {
        final result = read(
          await f.call(
            'GET',
            '$route/knowledge',
            token: route == s.employeeTask ? s.token : null,
          ),
        );
        expect(result.revisionId, first.revisionId);
        expect(result.body, first.body);
        expect(result.superseded, true);
        expect(result.articleRetired, true);
        expect(result.toJson().keys, hasLength(9));
      }
      await f.call(
        'GET',
        '/knowledge/articles/${s.instruction.article.id}',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '${s.employeeTask}/knowledge?revisionId=${v2.id}',
        token: s.token,
        expected: 400,
      );
      final audit = await rowCount(f, 'audit_entries');
      final replay = await f.call(
        'POST',
        '/shifts/${s.shift}/publish',
        body: {'expectedVersion': 1},
      );
      expect((replay.body['tasks'] as List).single['id'], s.task);
      expect(replay.body['shift']['id'], s.shift);
      expect(
        (await f.owner.execute(
          'SELECT knowledge_article_id::text,knowledge_revision_id::text FROM "${f.schema}".task_instances',
        )).single,
        [first.articleId, first.revisionId],
      );
      expect(replay.body, isNot(contains('code')));
      final templateReplay = await f.call(
        'POST',
        s.templatePublish,
        body: {'expectedVersion': 1},
      );
      expect(templateReplay.body['revision'], committedTemplate);
      expect(templateReplay.body, isNot(contains('code')));
      expect(await rowCount(f, 'audit_entries'), audit);
      expect(await rowCount(f, 'task_instances'), 1);
      var version = 1;
      final commands = [
        'start',
        'steps/${s.steps[0]}/confirm',
        'steps/${s.steps[1]}/record-number',
        'complete',
      ];
      String? completion;
      for (final command in commands) {
        final op = newUuid();
        if (command == 'complete') completion = op;
        await f.call(
          'POST',
          '${s.employeeTask}/$command',
          token: s.token,
          body: {
            'operationId': op,
            'expectedVersion': version++,
            if (command.endsWith('record-number')) 'value': '3',
          },
        );
      }
      final finalAudit = await rowCount(f, 'audit_entries');
      await f.restart();
      await f.call(
        'POST',
        '${s.employeeTask}/complete',
        token: s.token,
        body: {'operationId': completion, 'expectedVersion': 4},
      );
      expect(await rowCount(f, 'audit_entries'), finalAudit);
      expect(
        read(
          await f.call('GET', '${s.employeeTask}/knowledge', token: s.token),
        ).revisionId,
        first.revisionId,
      );
      final task = (await f.owner.execute(
        'SELECT content,status,knowledge_article_id::text,knowledge_revision_id::text FROM "${f.schema}".task_instances',
      )).single;
      expect(task[1], 'completed');
      expect(task[2], s.instruction.article.id);
      expect(task[3], first.revisionId);
      expect(task[0], isNot(contains(instructionBody)));
      expect(task[0], isNot(contains('Pinned instruction v1')));
      final evidence =
          (await f.owner.execute(
                "SELECT changes FROM \"${f.schema}\".audit_entries WHERE action='tasks.instance.completed'",
              )).single.first
              as Map;
      expect(evidence['knowledgeRevisionId'], first.revisionId);
      expect(jsonEncode(evidence), isNot(contains(instructionBody)));
    }),
    skip: skip,
  );

  test(
    'retirement blocks fresh template publication but retains editable draft and clone',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishTemplate: false);
      await retireInstruction(f, s.instruction.article.id);
      final count = await rowCount(f, 'audit_entries');
      final result = await f.call(
        'POST',
        s.templatePublish,
        body: {'expectedVersion': 1},
        expected: 422,
      );
      expect(result.body['code'], 'guidance_unavailable');
      expect(await rowCount(f, 'audit_entries'), count);
      var raw = (await f.call(
        'GET',
        '/task-templates/${s.template}/revisions/${s.revision}',
      )).body;
      final content = Map<String, dynamic>.from(
        (raw['revision'] as Map)['content'] as Map,
      )..['title'] = 'Retained editable draft';
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/${s.revision}/edit',
        body: {'expectedVersion': 1, 'content': content},
      );
      content['knowledgeGuidance'] = null;
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions/${s.revision}/edit',
        body: {'expectedVersion': 2, 'content': content},
      );
      await f.call('POST', s.templatePublish, body: {'expectedVersion': 3});
    }),
    skip: skip,
  );

  test(
    'retirement before fresh shift publication rejects all tasks and audit atomically',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishShift: false);
      await retireInstruction(f, s.instruction.article.id);
      final audit = await rowCount(f, 'audit_entries');
      expect(
        (await f.call(
          'POST',
          '/shifts/${s.shift}/publish',
          body: {'expectedVersion': 1},
          expected: 422,
        )).body['code'],
        'guidance_unavailable',
      );
      expect(await rowCount(f, 'task_instances'), 0);
      expect(await rowCount(f, 'audit_entries'), audit);
      expect(
        (await f.call('GET', '/shifts/${s.shift}')).body['shift']['status'],
        'draft',
      );
    }),
    skip: skip,
  );

  test(
    'newer publication permits retained older exact pin without silent upgrade',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishTemplate: false);
      final newer = await replaceInstruction(f, s.instruction.article.id);
      await f.call('POST', s.templatePublish, body: {'expectedVersion': 1});
      final raw = (await f.call(
        'GET',
        '/task-templates/${s.template}/revisions/${s.revision}',
      )).body;
      expect(
        raw['revision']['content']['knowledgeGuidance']['revisionId'],
        s.instruction.revision.id,
      );
      expect(newer.id, isNot(s.instruction.revision.id));
      await f.call(
        'POST',
        '/task-templates/${s.template}/revisions',
        expected: 201,
        body: {'id': newUuid(), 'expectedVersion': 2},
      );
    }),
    skip: skip,
  );

  test(
    'HTTP task visibility, roles, no guidance, guessing and session revocation',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f);
      await f.call(
        'GET',
        '${s.employeeTask}/knowledge',
        token: '',
        expected: 401,
      );
      for (final role in ['viewer', 'auditor', 'employee']) {
        final name = await f.account('denied_$role', role: role),
            token = await f.login(name);
        await f.call(
          'GET',
          '${s.employeeTask}/knowledge',
          token: token,
          expected: role == 'employee' ? 404 : 403,
        );
        await f.call(
          'GET',
          '${s.managerTask}/knowledge',
          token: token,
          expected: 403,
        );
      }
      await f.call(
        'GET',
        '/employee-home/shifts/${newUuid()}/tasks/${s.task}/knowledge',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${s.shift}/tasks/${newUuid()}/knowledge',
        token: s.token,
        expected: 404,
      );
      await f.call(
        'GET',
        '/employee-home/shifts/bad/tasks/${s.task}/knowledge',
        token: s.token,
        expected: 400,
      );
      final guessed = await f.client.getUrl(
        Uri.parse(
          '${f.base}/api/v1/platform${s.employeeTask}/knowledge/${s.instruction.revision.id}',
        ),
      );
      guessed.headers.set('authorization', 'Bearer ${s.token}');
      final deniedGuess = await guessed.close();
      expect(deniedGuess.statusCode, 404);
      await deniedGuess.drain<void>();
      await f.call(
        'GET',
        '$knowledgeRoot/${s.instruction.article.id}/revisions/${s.instruction.revision.id}',
        token: s.token,
        expected: 403,
      );
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        expected: 204,
        platform: false,
        token: s.token,
        body: {},
      );
      await f.call(
        'GET',
        '${s.employeeTask}/knowledge',
        token: s.token,
        expected: 401,
      );
    }),
    skip: skip,
  );
  for (final schema in [1, 2, 3]) {
    test(
      'schema 1/2/3 without guidance return no instruction and remain executable',
      () => withMerchandisingFixture((f) async {
        final s = await guidedScenario(f, guidance: false, schema: schema);
        await f.call(
          'GET',
          '${s.employeeTask}/knowledge',
          token: s.token,
          expected: 404,
        );
        await f.call(
          'POST',
          '${s.employeeTask}/start',
          token: s.token,
          body: {'operationId': newUuid(), 'expectedVersion': 1},
        );
      }),
      skip: skip,
    );
  }

  test(
    'generated references bind state and article; malformed pins and immutable drift rejected',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f), other = await makeInstruction(f);
      final root = '"${f.schema}"';
      final content =
          (await f.call(
                'GET',
                '/task-templates/${s.template}/revisions/${s.revision}',
              )).body['revision']['content']
              as Map;
      for (final pin in [
        {'articleId': s.instruction.article.id},
        {'articleId': s.instruction.article.id, 'revisionId': null},
        {'articleId': 'bad', 'revisionId': s.instruction.revision.id},
        {
          'articleId': other.article.id,
          'revisionId': s.instruction.revision.id,
        },
        {'articleId': s.instruction.article.id, 'revisionId': newUuid()},
      ]) {
        await expectLater(
          f.owner.execute(
            Sql.named(
              'INSERT INTO $root.task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)',
            ),
            parameters: {
              'id': newUuid(),
              'template': s.template,
              'company': s.instruction.article.companyId,
              'location': merchandisingTestLocation,
              'content': jsonEncode({...content, 'knowledgeGuidance': pin}),
            },
          ),
          throwsA(isA<ServerException>()),
        );
      }
      await expectLater(
        f.pool.execute(
          'UPDATE $root.task_instances SET knowledge_revision_id=NULL',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.pool.execute('UPDATE $root.task_instances SET content=content'),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE $root.task_template_revisions SET content=content',
        ),
        throwsA(isA<ServerException>()),
      );
      await retireInstruction(f, s.instruction.article.id);
      expect(await rowCount(f, 'task_instances'), 1);
    }),
    skip: skip,
  );

  test(
    'task/template pin correspondence rejects forged snapshot',
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
            'INSERT INTO "${f.schema}".task_instances(id,company_id,location_id,shift_id,employee_id,template_id,revision_id,position,content) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@shift AS uuid),CAST(@employee AS uuid),CAST(@template AS uuid),CAST(@revision AS uuid),0,@content)',
          ),
          parameters: {
            'id': newUuid(),
            'company': s.instruction.article.companyId,
            'location': merchandisingTestLocation,
            'shift': s.shift,
            'employee': s.employee,
            'template': s.template,
            'revision': s.revision,
            'content': jsonEncode({...content, 'knowledgeGuidance': null}),
          },
        ),
        throwsA(isA<ServerException>()),
      );
    }),
    skip: skip,
  );

  test(
    'publication and task creation audit failure rolls back',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, publishShift: false);
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".fail_guidance_audit() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'test audit failure\'; END \$\$; CREATE TRIGGER fail_guidance_audit BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".fail_guidance_audit()',
        queryMode: QueryMode.simple,
      );
      await f.call(
        'POST',
        '/shifts/${s.shift}/publish',
        body: {'expectedVersion': 1},
        expected: 500,
      );
      expect(await rowCount(f, 'task_instances'), 0);
      expect(
        (await f.call('GET', '/shifts/${s.shift}')).body['shift']['status'],
        'draft',
      );
    }),
    skip: skip,
  );

  test(
    'populated 0017 upgrade preserves old bytes, receipts and history; failed 0018 rolls back',
    () => withMerchandisingFixture((f) async {
      final s = await guidedScenario(f, schema: 2, guidance: false);
      await f.call(
        'POST',
        '${s.employeeTask}/start',
        token: s.token,
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
      const tables = [
        'task_template_revisions',
        'task_instances',
        'task_execution_commands',
        'knowledge_revisions',
        'audit_entries',
        'task_step_results',
        'task_numeric_attempts',
        'task_blockings',
      ];
      String order(String table) => table == 'task_execution_commands'
          ? 'operation_id'
          : table == 'task_step_results'
          ? 'instance_id,position'
          : 'id';
      Future<List<Object?>> preserved() async {
        final values = <Object?>[];
        for (final table in tables) {
          // Generated columns are additive; compare the complete pre-upgrade source columns.
          values.add(
            (await f.owner.execute(
              'SELECT jsonb_agg(to_jsonb(t) ORDER BY ${order(table)})::text FROM "${f.schema}".$table t',
            )).single.first,
          );
        }
        return values;
      }

      final before = await preserved();
      final temp = await Directory.systemTemp.createTemp(
        'storeos_p46_migrations_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${temp.path}/${file.uri.pathSegments.last}');
        }
        final target = File('${temp.path}/0018_task_knowledge_guidance.sql');
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
        expect(await preserved(), before);
        expect(await rowCount(f, 'schema_migrations'), 17);
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM information_schema.columns WHERE table_schema='${f.schema}' AND column_name='knowledge_revision_id'",
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
          ['0018_task_knowledge_guidance', '0019_task_planogram_guidance'],
        );
        for (var i = 0; i < tables.length; i++) {
          final table = tables[i];
          final result = (await f.owner.execute(
            "SELECT jsonb_agg(to_jsonb(t)-'knowledge_article_id'-'knowledge_revision_id'-'knowledge_revision_state'-'planogram_fixture_id'-'planogram_assignment_id'-'planogram_revision_id' ORDER BY ${order(table)})::text FROM \"${f.schema}\".$table t",
          )).single.first;
          expect(result, before[i]);
        }
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          isEmpty,
        );
      } finally {
        await temp.delete(recursive: true);
      }
    }, legacyBefore: '0018_task_knowledge_guidance.sql'),
    skip: skip,
  );
}
