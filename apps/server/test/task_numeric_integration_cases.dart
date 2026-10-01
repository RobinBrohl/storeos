part of 'shift_integration_test.dart';

void numericTests() {
  test(
    'twenty numeric steps fit bounded snapshots and receipts',
    () => _withFixture((f) async {
      final p = await _executionPlan(
        f,
        numeric: true,
        numericSteps: 20,
        steps: 20,
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      var version = 2;
      for (final step in p.plan.template['content']['steps'] as List) {
        await f.call(
          'POST',
          '${p.root}/steps/${step['id']}/record-number',
          body: {..._command(version++), 'value': '4.500'},
          token: p.token,
        );
      }
      final completed = (await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(version),
        token: p.token,
      )).body;
      expect(completed['results'], hasLength(20));
      expect(completed['status'], 'completed');
      expect(
        (await f.owner.execute(
              'SELECT max(octet_length(result)) FROM "${f.schema}".task_execution_commands',
            )).single.first
            as int,
        lessThanOrEqualTo(8192),
      );
    }),
    skip: _skip,
  );
  test(
    '0010 preserves populated schema-1 snapshots, results and receipts from 0009',
    () => _withFixture(
      (f) async {
        final p = await _legacyExecutionPlan(f);
        final id = p.task,
            step = p.plan.template['content']['steps'][0]['id'],
            actor = f.adminPrincipal.id;
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=2,started_at=clock_timestamp(),started_by=\'$actor\' WHERE id=\'$id\'',
        );
        await f.owner.execute(
          'INSERT INTO "${f.schema}".task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by,accepted_version) VALUES(\'$id\',\'$_company\',\'$_home\',\'$step\',0,clock_timestamp(),\'$actor\',3)',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET version=3 WHERE id=\'$id\'',
        );
        final at =
            (await f.owner.execute(
                  'SELECT started_at FROM "${f.schema}".task_instances WHERE id=\'$id\'',
                )).single.first
                as DateTime;
        final receipt = TaskExecutionDto(
          instanceId: id,
          status: 'in_progress',
          version: 2,
          results: [],
          startedAt: at,
          startedBy: actor,
        ).toJson();
        final command = _command(1),
            worker = (await f.owner.execute(
              'SELECT id::text FROM "${f.schema}".accounts WHERE username=\'executor\'',
            )).single.first;
        await f.owner.execute(
          Sql.named(
            'INSERT INTO "${f.schema}".task_execution_commands(operation_id,company_id,location_id,instance_id,actor_id,input,result) VALUES(CAST(@op AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@input,@result)',
          ),
          parameters: {
            'op': command['operationId'],
            'company': _company,
            'location': _home,
            'id': id,
            'actor': worker,
            'input': jsonEncode({
              'command': 'start',
              'expectedVersion': 1,
              'stepId': null,
            }),
            'result': jsonEncode(receipt),
          },
        );
        Future<List<Object?>> snapshot() async => [
          for (final table in [
            'task_template_revisions',
            'task_instances',
            'task_step_results',
            'task_execution_commands',
          ])
            (await f.owner.execute(
              'SELECT jsonb_agg(${table == 'task_instances' ? "to_jsonb(t)-'numeric_attempt_id'-'cancelled_at'-'cancelled_by'" : "to_jsonb(t)-'numeric_attempt_id'"} ORDER BY to_jsonb(t)::text)::text FROM "${f.schema}".$table t',
            )).single.first,
        ];
        final before = await snapshot();
        final runner = MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        );
        expect(await runner.apply(), [
          '0010_task_numeric_steps',
          '0011_published_shift_cancellation',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        expect(
          (await f.call(
            'POST',
            '${p.root}/start',
            body: command,
            token: p.token,
          )).body,
          receipt,
        );
        expect(
          (await f.call(
            'GET',
            '${p.root}/number-attempts',
            token: p.token,
          )).body['items'],
          isEmpty,
        );
        expect(
          (await f.call(
            'POST',
            '${p.root}/complete',
            body: _command(3),
            token: p.token,
          )).body['status'],
          'completed',
        );
      },
      legacy: true,
      legacyBefore: '0010',
    ),
    skip: _skip,
  );
  test(
    'number block, resume, boundary acceptance, mixed completion, replay and restart',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, numeric: true, steps: 2);
      final step = p.plan.template['content']['steps'][0]['id'];
      final path = '${p.root}/steps/$step/record-number',
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      await f.call(
        'POST',
        '${p.root}/steps/$step/confirm',
        body: _command(2),
        token: p.token,
        expected: 422,
      );
      for (final value in ['NaN', '1e2', '0.0001', 3, '1000000', '1,2']) {
        await f.call(
          'POST',
          path,
          body: {..._command(2), 'value': value},
          token: p.token,
          expected: 400,
        );
      }
      final command = {..._command(2), 'value': '4.501'};
      final blocked = (await f.call(
        'POST',
        path,
        body: command,
        token: p.token,
      )).body;
      expect(blocked['status'], 'blocked');
      expect(blocked['results'], isEmpty);
      expect(
        (await f.call('POST', path, body: command, token: p.token)).body,
        blocked,
      );
      await f.call(
        'POST',
        path,
        body: {...command, 'value': '4.502'},
        token: p.token,
        expected: 409,
      );
      await f.call(
        'POST',
        path,
        body: {..._command(3), 'value': '4'},
        token: p.token,
        expected: 409,
      );
      await f.call('POST', '$admin/resume', body: _reasonCommand(3));
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(4),
        token: p.token,
        expected: 422,
      );
      final good = {..._command(4), 'value': '-2.125'};
      final accepted = (await f.call(
        'POST',
        path,
        body: good,
        token: p.token,
      )).body;
      expect(accepted['status'], 'in_progress');
      expect(accepted['results'], hasLength(1));
      final history = (await f.call('GET', '$admin/number-attempts')).body;
      expect(history['items'], hasLength(2));
      expect(history['items'][0]['inRange'], true);
      expect(history['items'][1]['inRange'], false);
      expect(
        accepted['results'][0]['numericAttemptId'],
        history['items'][0]['id'],
      );
      expect(
        (await f.call(
          'GET',
          '$admin/blockings',
        )).body['items'][0]['numericAttemptId'],
        history['items'][1]['id'],
      );
      final second = p.plan.template['content']['steps'][1]['id'];
      await f.call(
        'POST',
        '${p.root}/steps/$second/record-number',
        body: {..._command(5), 'value': '1'},
        token: p.token,
        expected: 422,
      );
      await f.call(
        'POST',
        '${p.root}/steps/$second/confirm',
        body: _command(5),
        token: p.token,
      );
      await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(6),
        token: p.token,
      );
      await f.restart();
      final token = await f.login('executor');
      expect(
        (await f.call('GET', '${p.root}/number-attempts', token: token)).body,
        history,
      );
      expect(
        (await f.call('POST', path, body: good, token: token)).body,
        accepted,
      );
      final audits = await f.owner.execute(
        'SELECT changes FROM "${f.schema}".audit_entries WHERE action=\'tasks.step.number_recorded\'',
      );
      expect(audits, hasLength(2));
      for (final a in audits) {
        expect((a.first as Map)['value'], isNull);
        expect((a.first as Map)['revisionId'], p.plan.template['revisionId']);
      }
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_execution_commands',
        )).single.first,
        6,
      );
    }),
    skip: _skip,
  );

  test(
    'numeric commands authorize history, scope, replay and race atomically',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, numeric: true);
      final step = p.plan.template['content']['steps'][0]['id'],
          path = '${p.root}/steps/$step/record-number';
      final other = await _linkedAccount(
        f,
        await f.employee('Other'),
        'other_numeric',
      );
      await f.call(
        'GET',
        '${p.root}/number-attempts',
        token: other,
        expected: 404,
      );
      await f.call(
        'POST',
        path,
        body: {..._command(1), 'value': '1'},
        token: other,
        expected: 404,
      );
      for (final role in ['viewer', 'auditor']) {
        final user = await f.account('numeric_$role', role: role),
            token = await f.login('numeric_$role');
        expect(user.role, role);
        await f.call(
          'GET',
          '/shifts/${p.plan.id}/tasks/${p.task}/number-attempts',
          token: token,
          expected: 403,
        );
        await f.call(
          'POST',
          path,
          body: {..._command(1), 'value': '1'},
          token: token,
          expected: 403,
        );
      }
      await f.call(
        'GET',
        '${p.root}/number-attempts',
        token: '',
        expected: 401,
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      final command = {..._command(2), 'value': '04.500'};
      final replies = await Future.wait(
        List.generate(
          2,
          (_) => f.call('POST', path, body: command, token: p.token),
        ),
      );
      expect(replies[0].body, replies[1].body);
      expect(
        (await f.call(
          'POST',
          path,
          body: {...command, 'value': '4.5'},
          token: p.token,
        )).body,
        replies[0].body,
      );
      await f.call(
        'POST',
        path,
        body: {..._command(2), 'value': '4.5'},
        token: p.token,
        expected: 409,
      );
      expect(
        (await f.call(
          'GET',
          '${p.root}/number-attempts',
          token: p.token,
        )).body['items'],
        hasLength(1),
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET role=\'viewer\' WHERE username=\'executor\'',
      );
      await f.call('POST', path, body: command, token: p.token, expected: 403);
      await f.call(
        'GET',
        '${p.root}/number-attempts',
        token: p.token,
        expected: 403,
      );
    }),
    skip: _skip,
  );

  test(
    'numeric outcomes survive cancellation and paginate without duplicates',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, numeric: true), admin = '/shifts';
      final step = p.plan.template['content']['steps'][0]['id'];
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      var version = 2;
      for (var i = 0; i < 51; i++) {
        await f.call(
          'POST',
          '${p.root}/steps/$step/record-number',
          body: {..._command(version++), 'value': '5'},
          token: p.token,
        );
        if (i < 50) {
          await f.call(
            'POST',
            '$admin/${p.plan.id}/tasks/${p.task}/resume',
            body: _reasonCommand(version++),
          );
        }
      }
      await f.call(
        'POST',
        '$admin/${p.plan.id}/tasks/${p.task}/cancel',
        body: _reasonCommand(version),
      );
      final first = (await f.call(
        'GET',
        '${p.root}/number-attempts',
        token: p.token,
      )).body;
      expect(first['items'], hasLength(50));
      expect(first['nextCursor'], isNotNull);
      final second = (await f.call(
        'GET',
        '${p.root}/number-attempts?after=${first['nextCursor']}',
        token: p.token,
      )).body;
      expect(second['items'], hasLength(1));
      expect(second['nextCursor'], isNull);
      expect(
        [
          ...first['items'] as List,
          ...second['items'] as List,
        ].map((v) => v['id']).toSet(),
        hasLength(51),
      );
      await f.call(
        'GET',
        '${p.root}/number-attempts?after=bad',
        token: p.token,
        expected: 400,
      );
      expect(
        (await f.call(
          'GET',
          '${p.root}/execution',
          token: p.token,
        )).body['results'],
        isEmpty,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'numeric runtime SQL cannot skip evidence or commit orphan attempts',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, numeric: true);
      final step = p.plan.template['content']['steps'][0]['id'],
          actor = f.adminPrincipal.id;
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      await expectLater(
        f.pool.execute(
          'INSERT INTO "${f.schema}".task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by,accepted_version) VALUES(\'${p.task}\',\'$_company\',\'$_home\',\'$step\',0,clock_timestamp(),\'$actor\',3)',
        ),
        throwsA(isA<ServerException>()),
      );
      for (final valid in [true, false]) {
        await expectLater(
          f.pool.execute(
            'INSERT INTO "${f.schema}".task_numeric_attempts(id,instance_id,company_id,location_id,step_id,value_scaled,in_range,recorded_at,recorded_by,accepted_version) VALUES(\'${newUuid()}\',\'${p.task}\',\'$_company\',\'$_home\',\'$step\',1000,$valid,clock_timestamp(),\'$actor\',3)',
          ),
          throwsA(isA<ServerException>()),
        );
      }
      await f.call(
        'POST',
        '${p.root}/steps/$step/record-number',
        body: {..._command(2), 'value': '1'},
        token: p.token,
      );
      for (final sql in [
        'UPDATE "${f.schema}".task_numeric_attempts SET value_scaled=2000',
        'DELETE FROM "${f.schema}".task_numeric_attempts',
        'TRUNCATE "${f.schema}".task_numeric_attempts',
      ]) {
        await expectLater(f.pool.execute(sql), throwsA(isA<ServerException>()));
      }
    }),
    skip: _skip,
  );

  test(
    'each numeric write failure rolls back attempt, outcome, audit and receipt',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, numeric: true),
          step = p.plan.template['content']['steps'][0]['id'];
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      for (final table in [
        'task_numeric_attempts',
        'task_step_results',
        'task_blockings',
        'audit_entries',
        'task_execution_commands',
      ]) {
        await f.owner.execute(
          'REVOKE INSERT ON "${f.schema}".$table FROM "${f.runtimeUser}"',
        );
        for (final value
            in table == 'task_step_results'
                ? ['1']
                : table == 'task_blockings'
                ? ['5']
                : ['1', '5']) {
          await f.call(
            'POST',
            '${p.root}/steps/$step/record-number',
            body: {..._command(2), 'value': value},
            token: p.token,
            expected: 503,
          );
          expect(
            (await f.call(
              'GET',
              '${p.root}/execution',
              token: p.token,
            )).body['version'],
            2,
          );
          expect(
            (await f.call(
              'GET',
              '${p.root}/number-attempts',
              token: p.token,
            )).body['items'],
            isEmpty,
          );
        }
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".$table TO "${f.runtimeUser}"',
        );
      }
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'tasks.step.number_recorded\'',
        )).single.first,
        0,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_execution_commands',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );
}
