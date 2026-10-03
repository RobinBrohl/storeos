part of 'shift_integration_test.dart';

Future<({String root, String task, String token, _Plan plan})> _executionPlan(
  _Fixture f, {
  Duration duration = const Duration(hours: 1),
  int steps = 1,
  bool numeric = false,
  int numericSteps = 1,
  String accountName = 'executor',
}) async {
  final p = await _plan(
    f,
    steps: steps,
    numeric: numeric,
    numericSteps: numericSteps,
  );
  p.input['startsAt'] = p.employee.assignedFrom.toIso8601String();
  p.input['endsAt'] = DateTime.now().toUtc().add(duration).toIso8601String();
  await f.call('POST', '/shifts', body: p.input, expected: 201);
  final published = (await f.call(
    'POST',
    '/shifts/${p.id}/publish',
    body: {'expectedVersion': 1},
  )).body;
  final id = published['tasks'][0]['id'] as String;
  return (
    root: '/employee-home/shifts/${p.id}/tasks/$id',
    task: id,
    token: await _linkedAccount(f, p.employee, accountName),
    plan: p,
  );
}

Map<String, dynamic> _command(int version, [String? id]) => {
  'operationId': id ?? newUuid(),
  'expectedVersion': version,
};

void executionTests() {
  test(
    'execution uses pinned ordered steps even after a new template publication',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, steps: 2), command = _command(1);
      final steps = p.plan.template['content']['steps'] as List;
      await f.call('POST', '${p.root}/start', body: command, token: p.token);
      final revision = newUuid(), template = p.plan.template['id'];
      await f.call(
        'POST',
        '/task-templates/$template/revisions',
        body: {'id': revision, 'expectedVersion': 2},
        expected: 201,
      );
      await f.call(
        'POST',
        '/task-templates/$template/revisions/$revision/edit',
        body: {
          'expectedVersion': 3,
          'content': _content('Changed future work'),
        },
      );
      await f.call(
        'POST',
        '/task-templates/$template/revisions/$revision/publish',
        body: {'expectedVersion': 4},
      );
      expect(
        (await f.call('GET', p.root, token: p.token)).body['content'],
        p.plan.template['content'],
      );
      await f.call(
        'POST',
        '${p.root}/steps/${steps[1]['id']}/confirm',
        body: _command(2),
        token: p.token,
        expected: 422,
      );
      await f.call(
        'POST',
        '${p.root}/steps/${steps[0]['id']}/confirm',
        body: _command(2),
        token: p.token,
      );
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(3),
        token: p.token,
        expected: 422,
      );
      await f.call(
        'POST',
        '${p.root}/steps/${steps[1]['id']}/confirm',
        body: _command(3),
        token: p.token,
      );
      expect(
        (await f.call(
          'POST',
          '${p.root}/complete',
          body: _command(4),
          token: p.token,
        )).body['version'],
        5,
      );
    }),
    skip: _skip,
  );
  test(
    'future shifts, invalid commands and foreign scope are denied without execution writes',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      final task = (await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      )).body['tasks'][0]['id'];
      final token = await _linkedAccount(f, p.employee, 'future_worker'),
          root = '/employee-home/shifts/${p.id}/tasks/$task';
      await f.call(
        'POST',
        '$root/start',
        body: _command(1),
        token: token,
        expected: 422,
      );
      for (final bad in [
        {'expectedVersion': 1, 'operationId': 'invalid'},
        {'expectedVersion': 0, 'operationId': newUuid()},
        {..._command(1), 'status': 'completed'},
      ]) {
        await f.call(
          'POST',
          '$root/start',
          body: bad,
          token: token,
          expected: 400,
        );
      }
      await f.call(
        'GET',
        '/employee-home/shifts/${newUuid()}/tasks/$task/execution',
        token: token,
        expected: 404,
      );
      final foreign = SessionPrincipal(
        id: f.adminPrincipal.id,
        username: 'foreign',
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        ShiftApplication(
          f.database,
        ).execute(foreign, p.id, task as String, 'start', _command(1)),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_execution_commands',
        )).single.first,
        0,
      );
    }),
    skip: _skip,
  );
  test(
    '0007 preserves populated 0006 snapshots and enables execution with narrow runtime grants',
    () => _withFixture(
      (f) async {
        final p = await _plan(f), id = newUuid();
        final params = {
          'shift': p.id,
          'company': _company,
          'location': _home,
          'employee': p.employee.id,
          'actor': f.adminPrincipal.id,
          'template': p.template['id'],
          'revision': p.template['revisionId'],
          'task': id,
          'content': jsonEncode(p.template['content']),
        };
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".shifts(id,company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version)
      VALUES(CAST(@shift AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@employee AS uuid),clock_timestamp(),clock_timestamp()+interval '1 hour','published',2,CAST(@actor AS uuid),'{}',clock_timestamp(),CAST(@actor AS uuid),1)''',
          ),
          parameters: Map.fromEntries(
            params.entries.where(
              (e) => {
                'shift',
                'company',
                'location',
                'employee',
                'actor',
              }.contains(e.key),
            ),
          ),
        );
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".task_instances(id,company_id,location_id,employee_id,shift_id,template_id,revision_id,position,content)
      VALUES(CAST(@task AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@employee AS uuid),CAST(@shift AS uuid),CAST(@template AS uuid),CAST(@revision AS uuid),0,@content)''',
          ),
          parameters: Map<String, dynamic>.from(params)..remove('actor'),
        );
        Future<String> snapshot() async =>
            (await f.owner.execute(
                  'SELECT (to_jsonb(t)-ARRAY[\'started_at\',\'started_by\',\'completed_at\',\'completed_by\',\'cancelled_at\',\'cancelled_by\'])::text FROM "${f.schema}".task_instances t',
                )).single.first
                as String;
        final before = await snapshot();
        final runner = MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        );
        expect(await runner.apply(), [
          '0007_task_execution',
          '0008_task_blocking',
          '0009_task_cancellation',
          '0010_task_numeric_steps',
          '0011_published_shift_cancellation',
          '0012_published_shift_amendment',
          '0013_article_master',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        final token = await _linkedAccount(f, p.employee, 'upgrade_executor');
        final root = '/employee-home/shifts/${p.id}/tasks/$id';
        final started = (await f.call(
          'POST',
          '$root/start',
          body: _command(1),
          token: token,
        )).body;
        expect(started['status'], 'in_progress');
        await expectLater(
          f.pool.execute(
            'UPDATE "${f.schema}".task_instances SET content=content',
          ),
          throwsA(isA<ServerException>()),
        );
        expect(
          (await f.call('GET', root, token: token)).body['content'],
          p.template['content'],
        );
      },
      legacy: true,
      legacyBefore: '0007',
    ),
    skip: _skip,
  );
  test(
    'execution persists ordered steps, completion, replay receipts, audit and restart',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      final start = _command(1);
      final started = (await f.call(
        'POST',
        '${p.root}/start',
        body: start,
        token: p.token,
      )).body;
      expect(started['status'], 'in_progress');
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(2),
        token: p.token,
        expected: 422,
      );
      await f.call(
        'POST',
        '${p.root}/steps/${newUuid()}/confirm',
        body: _command(2),
        token: p.token,
        expected: 422,
      );
      final confirm = _command(2);
      final step = p.plan.template['content']['steps'][0]['id'];
      final confirmed = (await f.call(
        'POST',
        '${p.root}/steps/$step/confirm',
        body: confirm,
        token: p.token,
      )).body;
      expect(confirmed['results'], hasLength(1));
      await f.restart();
      final token = await f.login('executor');
      expect(
        (await f.call('GET', '${p.root}/execution', token: token)).body,
        confirmed,
      );
      expect(
        (await f.call(
          'POST',
          '${p.root}/start',
          body: start,
          token: token,
        )).body,
        started,
      );
      expect(
        (await f.call('GET', '${p.root}/execution', token: token)).body,
        confirmed,
      );
      await f.call(
        'POST',
        '${p.root}/complete',
        body: confirm,
        token: token,
        expected: 409,
      );
      final complete = _command(3);
      final completed = (await f.call(
        'POST',
        '${p.root}/complete',
        body: complete,
        token: token,
      )).body;
      expect(completed['status'], 'completed');
      expect(completed['version'], 4);
      expect(
        (await f.call(
          'POST',
          '${p.root}/complete',
          body: complete,
          token: token,
        )).body,
        completed,
      );
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(4),
        token: token,
        expected: 409,
      );
      expect(
        (await f.call(
          'GET',
          '/shifts/${p.plan.id}',
        )).body['tasks'][0]['status'],
        'completed',
      );
      expect(
        (await f.call(
          'GET',
          '/employee-home/running-tasks',
          token: token,
        )).body['items'],
        isEmpty,
      );
      final audit = await f.owner.execute(
        "SELECT action, changes FROM \"${f.schema}\".audit_entries WHERE action IN ('tasks.instance.started','tasks.step.confirmed','tasks.instance.completed') ORDER BY occurred_at,id",
      );
      expect(audit, hasLength(3));
      expect(audit.map((r) => r.first).toSet(), {
        'tasks.instance.started',
        'tasks.step.confirmed',
        'tasks.instance.completed',
      });
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_execution_commands',
        )).single.first,
        3,
      );
      for (final sql in [
        'UPDATE "${f.schema}".task_instances SET content=content',
        'UPDATE "${f.schema}".task_instances SET status=\'open\',version=version+1',
        'UPDATE "${f.schema}".task_step_results SET confirmed_at=clock_timestamp()',
        'DELETE FROM "${f.schema}".task_execution_commands',
      ]) {
        await expectLater(f.pool.execute(sql), throwsA(isA<ServerException>()));
      }
    }),
    skip: _skip,
  );

  test(
    'execution concurrent commands have one effect and same-key replay is stable',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      final command = _command(1);
      final starts = await Future.wait(
        List.generate(
          3,
          (_) =>
              f.call('POST', '${p.root}/start', body: command, token: p.token),
        ),
      );
      expect(starts.map((r) => jsonEncode(r.body)).toSet(), hasLength(1));
      final step = p.plan.template['content']['steps'][0]['id'];
      final results = await Future.wait(
        List.generate(
          2,
          (_) => f.call(
            'POST',
            '${p.root}/steps/$step/confirm',
            body: _command(2),
            token: p.token,
            expected: null,
          ),
        ),
      );
      expect(results.map((r) => r.status).toList()..sort(), [200, 409]);
      final completions = await Future.wait(
        List.generate(
          2,
          (_) => f.call(
            'POST',
            '${p.root}/complete',
            body: _command(3),
            token: p.token,
            expected: null,
          ),
        ),
      );
      expect(completions.map((r) => r.status).toList()..sort(), [200, 409]);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_step_results',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );

  test(
    'every execution persistence failure rolls back state audit and command receipt',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      final step = p.plan.template['content']['steps'][0]['id'];
      for (final stage in [
        (suffix: 'start', version: 1),
        (suffix: 'steps/$step/confirm', version: 2),
        (suffix: 'complete', version: 3),
      ]) {
        final before = (await f.call(
          'GET',
          '${p.root}/execution',
          token: p.token,
        )).body;
        for (final table in [
          'audit_entries',
          'task_execution_commands',
          if (stage.version == 2) 'task_step_results',
        ]) {
          final command = _command(stage.version);
          await f.owner.execute(
            'REVOKE INSERT ON "${f.schema}".$table FROM "${f.runtimeUser}"',
          );
          await f.call(
            'POST',
            '${p.root}/${stage.suffix}',
            body: command,
            token: p.token,
            expected: 503,
          );
          expect(
            (await f.call('GET', '${p.root}/execution', token: p.token)).body,
            before,
          );
          expect(
            (await f.owner.execute(
              Sql.named(
                'SELECT count(*) FROM "${f.schema}".task_execution_commands WHERE operation_id=CAST(@id AS uuid)',
              ),
              parameters: {'id': command['operationId']},
            )).single.first,
            0,
          );
          await f.owner.execute(
            'GRANT INSERT ON "${f.schema}".$table TO "${f.runtimeUser}"',
          );
        }
        await f.call(
          'POST',
          '${p.root}/${stage.suffix}',
          body: _command(stage.version),
          token: p.token,
        );
      }
    }),
    skip: _skip,
  );

  test(
    'execution authorization denies other users admin proxy plugins and revoked links even on replay',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      final command = _command(1);
      await f.call('POST', '${p.root}/start', body: command, expected: 404);
      final other = await f.employee('Other');
      final token = await _linkedAccount(f, other, 'other_executor');
      await f.call(
        'POST',
        '${p.root}/start',
        body: command,
        token: token,
        expected: 404,
      );
      for (final role in ['viewer', 'auditor']) {
        final account = await f.account('execute_$role', role: role);
        await f.call(
          'POST',
          '${p.root}/start',
          body: command,
          token: await f.login(account.username),
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '${p.root}/start',
        body: command,
        token: '',
        expected: 401,
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: {...command, 'employeeId': other.id},
        token: p.token,
        expected: 400,
      );
      await f.call('POST', '${p.root}/start', body: command, token: p.token);
      final link = (await f.call(
        'GET',
        '/employees/${p.plan.employee.id}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: command,
        token: p.token,
        expected: 401,
      );
      await f.call('GET', '${p.root}/execution', token: p.token, expected: 401);
    }),
    skip: _skip,
  );

  test(
    'running work survives shift end but expired employee assignment prevents further writes',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, duration: const Duration(seconds: 3));
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        (await f.call(
          'GET',
          '/employee-home/shifts',
          token: p.token,
        )).body['items'],
        isEmpty,
      );
      expect(
        (await f.call(
          'GET',
          '/employee-home/running-tasks',
          token: p.token,
        )).body['items'][0]['id'],
        p.task,
      );
      final step = p.plan.template['content']['steps'][0]['id'];
      await f.call(
        'POST',
        '${p.root}/steps/$step/confirm',
        body: _command(2),
        token: p.token,
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".employees SET is_active=false, assigned_until=clock_timestamp() WHERE id=\'${p.plan.employee.id}\'',
      );
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(3),
        token: p.token,
        expected: 404,
      );
    }),
    skip: _skip,
  );
}
