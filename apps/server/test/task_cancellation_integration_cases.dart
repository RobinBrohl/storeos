part of 'shift_integration_test.dart';

void cancellationTests() {
  test(
    'cancellation preserves results and history, replays and survives restart',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, steps: 2);
      final admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      final step = p.plan.template['content']['steps'][0]['id'];
      final progress = (await f.call(
        'POST',
        '${p.root}/steps/$step/confirm',
        body: _command(2),
        token: p.token,
      )).body;
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(3),
        token: p.token,
      );
      await f.call('POST', '$admin/resume', body: _reasonCommand(4));
      final blockCommand = _reasonCommand(5);
      final blocked = (await f.call(
        'POST',
        '${p.root}/block',
        body: blockCommand,
        token: p.token,
      )).body;
      final command = _reasonCommand(
        6,
        reason: '  Cannot safely perform this work  ',
      );
      final result = (await f.call(
        'POST',
        '$admin/cancel',
        body: command,
      )).body;
      expect(result['status'], 'cancelled');
      expect(result['version'], 7);
      expect(result['results'], progress['results']);
      expect(result['activeBlockingId'], isNull);
      expect(result['completedAt'], isNull);
      expect(result['cancelledAt'], isNotNull);
      expect(result['cancelledBy'], f.adminPrincipal.id);
      expect(result['cancelledBlockingId'], blocked['activeBlockingId']);
      expect(
        (await f.call('POST', '$admin/cancel', body: command)).body,
        result,
      );
      expect(
        (await f.call(
          'POST',
          '${p.root}/block',
          body: blockCommand,
          token: p.token,
        )).body,
        blocked,
      );
      await f.call(
        'POST',
        '$admin/cancel',
        body: {...command, 'reason': 'Different'},
        expected: 409,
      );
      for (final action in ['cancel', 'resume']) {
        await f.call(
          'POST',
          '$admin/$action',
          body: _reasonCommand(7),
          expected: 409,
        );
      }
      for (final action in [
        'start',
        'complete',
        'block',
        'steps/${p.plan.template['content']['steps'][1]['id']}/confirm',
      ]) {
        await f.call(
          'POST',
          '${p.root}/$action',
          body: action == 'block' ? _reasonCommand(7) : _command(7),
          token: p.token,
          expected: 409,
        );
      }
      final history =
          (await f.call('GET', '$admin/blockings')).body['items'] as List;
      expect(history.map((v) => v['resolutionKind']), ['cancelled', 'resumed']);
      expect(history.first['resolution'], 'Cannot safely perform this work');
      expect(
        (await f.call('GET', p.root, token: p.token)).body['content'],
        p.plan.template['content'],
      );
      final audits = await f.owner.execute(
        'SELECT changes FROM "${f.schema}".audit_entries WHERE action=\'tasks.instance.cancelled\'',
      );
      expect(audits, hasLength(1));
      expect(
        (audits.single.first as Map)['blockingId'],
        blocked['activeBlockingId'],
      );
      expect((audits.single.first as Map)['reason'], isNull);
      for (final sql in [
        'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=version+1 WHERE id=\'${p.task}\'',
        'UPDATE "${f.schema}".task_blockings SET resolution_kind=\'resumed\' WHERE resolution_kind=\'cancelled\'',
        'DELETE FROM "${f.schema}".task_blockings',
      ]) {
        await expectLater(f.pool.execute(sql), throwsA(isA<ServerException>()));
      }
      await f.restart();
      final token = await f.login('executor');
      expect(
        (await f.call('GET', '${p.root}/execution', token: token)).body,
        result,
      );
      for (final root in [
        '/cancelled-tasks',
        '/employee-home/cancelled-tasks',
      ]) {
        final rows =
            (await f.call(
                  'GET',
                  root,
                  token: root.startsWith('/employee') ? token : null,
                )).body['items']
                as List;
        expect(rows.single['id'], p.task);
        expect(rows.single['content'], isNull);
      }
      expect((await f.call('GET', '/blocked-tasks')).body['items'], isEmpty);
      expect(
        (await f.call(
          'GET',
          '/employee-home/running-tasks',
          token: token,
        )).body['items'],
        isEmpty,
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation rolls back every persistence boundary and serializes racing commands',
    () => _withFixture((f) async {
      final p = await _executionPlan(f),
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(2),
        token: p.token,
      );
      Future<List<String>> snapshot() async => [
        for (final table in [
          'task_instances',
          'task_blockings',
          'task_execution_commands',
          'audit_entries',
        ])
          (await f.owner.execute(
                'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),\'[]\'::jsonb)::text FROM "${f.schema}".$table t',
              )).single.first
              as String,
      ];
      final before = await snapshot(), command = _reasonCommand(3);
      for (final entry in {
        'task_blockings':
            'UPDATE (resolution,resolved_at,resolved_by,resolved_version,resolution_kind)',
        'task_instances':
            'UPDATE (status,version,started_at,started_by,completed_at,completed_by)',
        'audit_entries': 'INSERT',
        'task_execution_commands': 'INSERT',
      }.entries) {
        await f.owner.execute(
          'REVOKE ${entry.value} ON "${f.schema}".${entry.key} FROM "${f.runtimeUser}"',
        );
        await f.call('POST', '$admin/cancel', body: command, expected: 503);
        await f.owner.execute(
          'GRANT ${entry.value} ON "${f.schema}".${entry.key} TO "${f.runtimeUser}"',
        );
        expect(await snapshot(), before);
      }
      final race = await Future.wait([
        f.call('POST', '$admin/cancel', body: command, expected: null),
        f.call(
          'POST',
          '$admin/resume',
          body: _reasonCommand(3),
          expected: null,
        ),
      ]);
      expect(race.map((r) => r.status).toList()..sort(), [200, 409]);
      if (race.first.status == 409) {
        await f.call(
          'POST',
          '${p.root}/block',
          body: _reasonCommand(4),
          token: p.token,
        );
        command['expectedVersion'] = 5;
      }
      final copies = await Future.wait(
        List.generate(3, (_) => f.call('POST', '$admin/cancel', body: command)),
      );
      expect(copies.map((r) => jsonEncode(r.body)).toSet(), hasLength(1));
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'tasks.instance.cancelled\'',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation validates roles, input, scope and revoked replay rights',
    () => _withFixture((f) async {
      final p = await _executionPlan(f),
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '$admin/cancel',
        body: _reasonCommand(1),
        expected: 409,
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      await f.call(
        'POST',
        '$admin/cancel',
        body: _reasonCommand(2),
        expected: 409,
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(2),
        token: p.token,
      );
      for (final reason in ['', ' ', 'x' * 501, 'bad\u0000text', 42]) {
        await f.call(
          'POST',
          '$admin/cancel',
          body: {..._command(3), 'reason': reason},
          expected: 400,
        );
      }
      await f.call(
        'POST',
        '$admin/cancel',
        body: _reasonCommand(3),
        token: '',
        expected: 401,
      );
      for (final role in ['employee', 'viewer', 'auditor']) {
        await f.account('cancel_$role', role: role);
        final token = await f.login('cancel_$role');
        await f.call(
          'POST',
          '$admin/cancel',
          body: _reasonCommand(3),
          token: token,
          expected: 403,
        );
        await f.call('GET', '/cancelled-tasks', token: token, expected: 403);
      }
      final other = await f.employee('Other'),
          otherToken = await _linkedAccount(f, other, 'other_cancel');
      await f.call(
        'GET',
        '${p.root}/execution',
        token: otherToken,
        expected: 404,
      );
      expect(
        (await f.call(
          'GET',
          '/employee-home/cancelled-tasks',
          token: otherToken,
        )).body['items'],
        isEmpty,
      );
      await f.call('GET', '/cancelled-tasks?after=bad', expected: 400);
      final resolver = await f.account('canceller', role: 'admin'),
          token = await f.login('canceller');
      final command = _reasonCommand(3, reason: '🔧' * 500);
      await f.call('POST', '$admin/cancel', body: command, token: token);
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET role=\'viewer\' WHERE id=\'${resolver.id}\'',
      );
      await f.call(
        'POST',
        '$admin/cancel',
        body: command,
        token: token,
        expected: 403,
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET role=\'admin\',location_id=\'$_other\' WHERE id=\'${resolver.id}\'',
      );
      final foreign = SessionPrincipal(
        id: resolver.id,
        username: resolver.username,
        companyId: _company,
        locationId: _other,
      );
      for (final action in [
        () => ShiftApplication(
          f.database,
        ).execute(foreign, p.plan.id, p.task, 'cancel', command),
        () => ShiftApplication(
          f.database,
        ).blocked(foreign, self: false, cancelled: true),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<PlatformFailure>().having((e) => e.status, 'status', 404),
          ),
        );
      }
      final tenant = SessionPrincipal(
        id: resolver.id,
        username: resolver.username,
        companyId: newUuid(),
        locationId: _other,
      );
      await expectLater(
        ShiftApplication(
          f.database,
        ).execute(tenant, p.plan.id, p.task, 'cancel', command),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation after shift end works without active employee or account link and never completes work',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, duration: const Duration(seconds: 4));
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      final step = p.plan.template['content']['steps'][0]['id'];
      await f.call(
        'POST',
        '${p.root}/steps/$step/confirm',
        body: _command(2),
        token: p.token,
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(3),
        token: p.token,
      );
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
        '/employees/${p.plan.employee.id}/deactivate',
        body: {'expectedVersion': p.plan.employee.version},
      );
      await Future<void>.delayed(const Duration(seconds: 4));
      final result = (await f.call(
        'POST',
        '/shifts/${p.plan.id}/tasks/${p.task}/cancel',
        body: _reasonCommand(4),
      )).body;
      expect(result['status'], 'cancelled');
      expect(result['results'], hasLength(1));
      expect(result['completedAt'], isNull);
      expect(
        (await f.call('GET', '/cancelled-tasks')).body['items'],
        hasLength(1),
      );
      await f.call(
        'GET',
        '/employee-home/cancelled-tasks',
        token: p.token,
        expected: 401,
      );
    }),
    skip: _skip,
  );
  test(
    'cancelled lists paginate 51 items with strict employee visibility',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      for (var i = 0; i < 51; i++) {
        final shift = newUuid(), task = newUuid();
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".shifts
        (id,company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version FROM "${f.schema}".shifts WHERE id=CAST(@source AS uuid)''',
          ),
          parameters: {'id': shift, 'source': p.plan.id},
        );
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".task_instances
        (id,company_id,location_id,employee_id,shift_id,template_id,revision_id,position,content)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,CAST(@shift AS uuid),template_id,revision_id,position,content FROM "${f.schema}".task_instances WHERE id=CAST(@source AS uuid)''',
          ),
          parameters: {'id': task, 'shift': shift, 'source': p.task},
        );
        final root = '/employee-home/shifts/$shift/tasks/$task';
        await f.call('POST', '$root/start', body: _command(1), token: p.token);
        await f.call(
          'POST',
          '$root/block',
          body: _reasonCommand(2),
          token: p.token,
        );
        await f.call(
          'POST',
          '/shifts/$shift/tasks/$task/cancel',
          body: _reasonCommand(3),
        );
      }
      for (final root in [
        '/cancelled-tasks',
        '/employee-home/cancelled-tasks',
      ]) {
        final token = root.startsWith('/employee') ? p.token : null;
        final first = (await f.call('GET', root, token: token)).body;
        final last = (await f.call(
          'GET',
          '$root?after=${first['nextCursor']}',
          token: token,
        )).body;
        expect(first['items'], hasLength(50));
        expect(last['items'], hasLength(1));
        expect(last['nextCursor'], isNull);
        expect(
          [
            ...(first['items'] as List),
            ...(last['items'] as List),
          ].map((v) => v['id']).toSet(),
          hasLength(51),
        );
      }
      final other = await f.employee('Other'),
          token = await _linkedAccount(f, other, 'cancel_list_other');
      expect(
        (await f.call(
          'GET',
          '/employee-home/cancelled-tasks',
          token: token,
        )).body['items'],
        isEmpty,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '0009 preserves populated blocking history, confirmations and old receipts',
    () => _withFixture(
      (f) async {
        final p = await _executionPlan(f);
        final id = p.task,
            actor = f.adminPrincipal.id,
            step = p.plan.template['content']['steps'][0]['id'];
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=2,started_at=clock_timestamp(),started_by=\'$actor\' WHERE id=\'$id\'',
        );
        await f.owner.execute(
          'INSERT INTO "${f.schema}".task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by,accepted_version) VALUES(\'$id\',\'$_company\',\'$_home\',\'$step\',0,clock_timestamp(),\'$actor\',3)',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET version=3 WHERE id=\'$id\'',
        );
        final blocks = [newUuid(), newUuid()];
        for (var i = 0; i < 2; i++) {
          final v = 4 + i * 2;
          await f.owner.execute(
            'INSERT INTO "${f.schema}".task_blockings(id,instance_id,company_id,location_id,reason,reported_at,reported_by,reported_version) VALUES(\'${blocks[i]}\',\'$id\',\'$_company\',\'$_home\',\'Missing\',clock_timestamp(),\'$actor\',$v)',
          );
          await f.owner.execute(
            'UPDATE "${f.schema}".task_instances SET status=\'blocked\',version=$v WHERE id=\'$id\'',
          );
          if (i == 0) {
            await f.owner.execute(
              'UPDATE "${f.schema}".task_blockings SET resolution=\'Ready\',resolved_at=clock_timestamp(),resolved_by=\'$actor\',resolved_version=5 WHERE id=\'${blocks[i]}\'',
            );
            await f.owner.execute(
              'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=5 WHERE id=\'$id\'',
            );
          }
        }
        final started =
            (await f.owner.execute(
                  'SELECT started_at FROM "${f.schema}".task_instances WHERE id=\'$id\'',
                )).single.first
                as DateTime;
        final receipt = TaskExecutionDto(
          instanceId: id,
          status: 'in_progress',
          version: 2,
          results: [],
          startedAt: started,
          startedBy: actor,
        ).toJson();
        final command = _command(1);
        final worker = (await f.owner.execute(
          'SELECT id::text FROM "${f.schema}".accounts WHERE username=\'executor\'',
        )).single.first;
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".task_execution_commands(operation_id,company_id,location_id,instance_id,actor_id,input,result)
      VALUES(CAST(@op AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@input,@result)''',
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
        Future<List<String>> snapshot() async => [
          for (final table in [
            'task_instances',
            'task_step_results',
            'task_execution_commands',
            'task_blockings',
          ])
            (await f.owner.execute(
                  'SELECT jsonb_agg(${table == 'task_blockings' ? "to_jsonb(t)-'resolution_kind'-'numeric_attempt_id'" : "to_jsonb(t)-'numeric_attempt_id'"} ORDER BY to_jsonb(t)::text)::text FROM "${f.schema}".$table t',
                )).single.first
                as String,
        ];
        final before = await snapshot();
        final runner = MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        );
        expect(await runner.apply(), [
          '0009_task_cancellation',
          '0010_task_numeric_steps',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        final history = (await f.call(
          'GET',
          '${p.root}/blockings',
          token: p.token,
        )).body['items'];
        expect(history[0]['resolutionKind'], isNull);
        expect(history[1]['resolutionKind'], 'resumed');
        expect(
          (await f.call(
            'POST',
            '${p.root}/start',
            body: command,
            token: p.token,
          )).body,
          receipt,
        );
        final result = (await f.call(
          'POST',
          '/shifts/${p.plan.id}/tasks/$id/cancel',
          body: _reasonCommand(6),
        )).body;
        expect(result['status'], 'cancelled');
        expect(result['results'], hasLength(1));
      },
      legacy: true,
      legacyBefore: '0009',
    ),
    skip: _skip,
  );
}
