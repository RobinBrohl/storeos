part of 'shift_integration_test.dart';

Map<String, dynamic> _reasonCommand(
  int version, {
  String reason = 'Equipment unavailable',
  String? id,
}) => {..._command(version, id), 'reason': reason};

void blockingTests() {
  test(
    'blocking two-user lifecycle preserves work, receipts, history and audit after restart',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, steps: 2),
          step = p.plan.template['content']['steps'][0]['id'];
      final admin = '/shifts/${p.plan.id}/tasks/${p.task}';
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
      );
      final command = _reasonCommand(3, reason: '  Missing equipment 🔧  ');
      final blocked = (await f.call(
        'POST',
        '${p.root}/block',
        body: command,
        token: p.token,
      )).body;
      expect(blocked['status'], 'blocked');
      expect(blocked['version'], 4);
      for (final suffix in [
        'complete',
        'steps/${p.plan.template['content']['steps'][1]['id']}/confirm',
      ]) {
        await f.call(
          'POST',
          '${p.root}/$suffix',
          body: _command(4),
          token: p.token,
          expected: 409,
        );
      }
      final history =
          (await f.call(
                'GET',
                '${p.root}/blockings',
                token: p.token,
              )).body['items']
              as List;
      expect(history.single['reason'], 'Missing equipment 🔧');
      expect(
        history.single['stepId'],
        p.plan.template['content']['steps'][1]['id'],
      );
      expect(
        (await f.call('GET', '/blocked-tasks')).body['items'],
        hasLength(1),
      );
      expect(
        (await f.call(
          'GET',
          '/employee-home/running-tasks',
          token: p.token,
        )).body['items'],
        isEmpty,
      );
      final resume = _reasonCommand(4, reason: 'Replacement checked');
      await f.call('POST', '$admin/resume', body: resume);
      expect(
        (await f.call(
          'POST',
          '${p.root}/block',
          body: command,
          token: p.token,
        )).body,
        blocked,
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: {...command, 'reason': 'Changed'},
        token: p.token,
        expected: 409,
      );
      await f.restart();
      final token = await f.login('executor');
      expect(
        (await f.call(
          'GET',
          '${p.root}/execution',
          token: token,
        )).body['version'],
        5,
      );
      final next = p.plan.template['content']['steps'][1]['id'];
      await f.call(
        'POST',
        '${p.root}/steps/$next/confirm',
        body: _command(5),
        token: token,
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(6),
        token: token,
      );
      expect(
        (await f.call('GET', '$admin/blockings')).body['items'][0]['stepId'],
        isNull,
      );
      await f.call('POST', '$admin/resume', body: _reasonCommand(7));
      final completed = (await f.call(
        'POST',
        '${p.root}/complete',
        body: _command(8),
        token: token,
      )).body;
      expect(completed['version'], 9);
      expect(completed['results'], hasLength(2));
      expect(completed['results'][0]['acceptedVersion'], 3);
      expect(completed['results'][1]['acceptedVersion'], 6);
      expect(
        (await f.call('GET', '$admin/blockings')).body['items'],
        hasLength(2),
      );
      final audit = await f.owner.execute(
        'SELECT action,changes FROM "${f.schema}".audit_entries WHERE action IN (\'tasks.instance.blocked\',\'tasks.instance.resumed\')',
      );
      expect(audit, hasLength(4));
      for (final row in audit) {
        final changes = row[1] as Map;
        expect(changes['blockingId'], isNotNull);
        expect(changes['reason'], isNull);
        expect(changes['resolution'], isNull);
        expect(changes['operationId'], isNotNull);
      }
      for (final sql in [
        'UPDATE "${f.schema}".task_blockings SET reason=\'changed\'',
        'DELETE FROM "${f.schema}".task_blockings',
        'UPDATE "${f.schema}".task_blockings SET resolution=\'changed\'',
        'UPDATE "${f.schema}".task_step_results SET accepted_version=999',
      ]) {
        await expectLater(f.pool.execute(sql), throwsA(isA<ServerException>()));
      }
    }),
    skip: _skip,
  );

  test(
    'blocking races, same-key replay and rollback protect all persistence boundaries',
    () => _withFixture((f) async {
      final p = await _executionPlan(f),
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      final command = _reasonCommand(2);
      for (final table in [
        'task_blockings',
        'audit_entries',
        'task_execution_commands',
      ]) {
        final before = (await f.call(
          'GET',
          '${p.root}/execution',
          token: p.token,
        )).body;
        await f.owner.execute(
          'REVOKE INSERT ON "${f.schema}".$table FROM "${f.runtimeUser}"',
        );
        await f.call(
          'POST',
          '${p.root}/block',
          body: command,
          token: p.token,
          expected: 503,
        );
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".$table TO "${f.runtimeUser}"',
        );
        expect(
          (await f.call('GET', '${p.root}/execution', token: p.token)).body,
          before,
        );
        expect(
          (await f.call('GET', '$admin/blockings')).body['items'],
          isEmpty,
        );
      }
      final same = await Future.wait(
        List.generate(
          3,
          (_) =>
              f.call('POST', '${p.root}/block', body: command, token: p.token),
        ),
      );
      expect(same.map((r) => jsonEncode(r.body)).toSet(), hasLength(1));
      for (final table in [
        'task_blockings',
        'audit_entries',
        'task_execution_commands',
      ]) {
        final privilege = table == 'task_blockings'
            ? 'UPDATE (resolution,resolved_at,resolved_by,resolved_version,resolution_kind)'
            : 'INSERT';
        await f.owner.execute(
          'REVOKE $privilege ON "${f.schema}".$table FROM "${f.runtimeUser}"',
        );
        await f.call(
          'POST',
          '$admin/resume',
          body: _reasonCommand(3),
          expected: 503,
        );
        await f.owner.execute(
          'GRANT $privilege ON "${f.schema}".$table TO "${f.runtimeUser}"',
        );
        expect(
          (await f.call(
            'GET',
            '$admin/blockings',
          )).body['items'][0]['resolution'],
          isNull,
        );
        expect(
          (await f.call(
            'GET',
            '${p.root}/execution',
            token: p.token,
          )).body['status'],
          'blocked',
        );
      }
      final resolutions = await Future.wait(
        List.generate(
          2,
          (_) => f.call(
            'POST',
            '$admin/resume',
            body: _reasonCommand(3),
            expected: null,
          ),
        ),
      );
      expect(resolutions.map((r) => r.status).toList()..sort(), [200, 409]);
      final step = p.plan.template['content']['steps'][0]['id'];
      final race = await Future.wait([
        f.call(
          'POST',
          '${p.root}/block',
          body: _reasonCommand(4),
          token: p.token,
          expected: null,
        ),
        f.call(
          'POST',
          '${p.root}/steps/$step/confirm',
          body: _command(4),
          token: p.token,
          expected: null,
        ),
      ]);
      expect(race.map((r) => r.status).toList()..sort(), [200, 409]);
    }),
    skip: _skip,
  );

  test(
    'blocking validates input permissions scope and revoked replay',
    () => _withFixture((f) async {
      final p = await _executionPlan(f),
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(1),
        token: p.token,
        expected: 409,
      );
      await f.call(
        'POST',
        '${p.root}/start',
        body: _command(1),
        token: p.token,
      );
      for (final reason in ['', '   ', 'x' * 501, 'bad\u0000text', 123]) {
        await f.call(
          'POST',
          '${p.root}/block',
          body: {..._command(2), 'reason': reason},
          token: p.token,
          expected: 400,
        );
      }
      for (final role in ['viewer', 'auditor']) {
        final user = await f.account('blocking_$role', role: role),
            token = await f.login('blocking_$role');
        expect(user.role, role);
        await f.call(
          'POST',
          '$admin/resume',
          body: _reasonCommand(3),
          token: token,
          expected: 403,
        );
        await f.call('GET', '/blocked-tasks', token: token, expected: 403);
        await f.call('GET', '$admin/blockings', token: token, expected: 403);
      }
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(2),
        expected: 404,
      );
      await f.call('GET', '$admin/blockings', token: p.token, expected: 403);
      await f.call(
        'POST',
        '$admin/resume',
        body: _reasonCommand(3),
        token: p.token,
        expected: 403,
      );
      await f.call(
        'GET',
        '/employee-home/blocked-tasks',
        token: '',
        expected: 401,
      );
      await f.call(
        'GET',
        '${p.root}/blockings?after=invalid',
        token: p.token,
        expected: 400,
      );
      final command = _reasonCommand(2, reason: '🔧' * 500);
      await f.call('POST', '${p.root}/block', body: command, token: p.token);
      final foreign = SessionPrincipal(
        id: f.adminPrincipal.id,
        username: 'foreign',
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        ShiftApplication(f.database).blocked(foreign, self: false),
        throwsA(isA<PlatformFailure>()),
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
        '${p.root}/block',
        body: command,
        token: p.token,
        expected: 401,
      );
    }),
    skip: _skip,
  );

  test(
    'blocked work survives shift end and invalid assignment prevents new resolution',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, duration: const Duration(seconds: 3));
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
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(
        (await f.call(
          'GET',
          '/employee-home/blocked-tasks',
          token: p.token,
        )).body['items'],
        hasLength(1),
      );
      await f.call(
        'POST',
        '/shifts/${p.plan.id}/tasks/${p.task}/resume',
        body: _reasonCommand(3),
      );
      await f.call(
        'POST',
        '${p.root}/block',
        body: _reasonCommand(4),
        token: p.token,
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".employees SET is_active=false,assigned_until=clock_timestamp() WHERE id=\'${p.plan.employee.id}\'',
      );
      await f.call(
        'POST',
        '/shifts/${p.plan.id}/tasks/${p.task}/resume',
        body: _reasonCommand(5),
        expected: 422,
      );
      expect(
        (await f.call('GET', '/blocked-tasks')).body['items'],
        hasLength(1),
      );
    }),
    skip: _skip,
  );
  test(
    'blocking history and blocked lists paginate beyond 50 without exposing instructions',
    () => _withFixture((f) async {
      final p = await _executionPlan(f),
          admin = '/shifts/${p.plan.id}/tasks/${p.task}';
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
          '${p.root}/block',
          body: _reasonCommand(version++),
          token: p.token,
        );
        await f.call('POST', '$admin/resume', body: _reasonCommand(version++));
      }
      for (final root in [p.root, admin]) {
        final first = (await f.call(
          'GET',
          '$root/blockings',
          token: root == p.root ? p.token : null,
        )).body;
        final last = (await f.call(
          'GET',
          '$root/blockings?after=${first['nextCursor']}',
          token: root == p.root ? p.token : null,
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
      for (var i = 0; i < 51; i++) {
        final shift = newUuid(), task = newUuid();
        await f.owner.execute(
          Sql.named('''INSERT INTO "${f.schema}".shifts
        (id,company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,starts_at,ends_at,status,version,created_by,creation_input,published_at,published_by,publication_version
        FROM "${f.schema}".shifts WHERE id=CAST(@source AS uuid)'''),
          parameters: {'id': shift, 'source': p.plan.id},
        );
        await f.owner.execute(
          Sql.named('''INSERT INTO "${f.schema}".task_instances
        (id,company_id,location_id,employee_id,shift_id,template_id,revision_id,position,content)
        SELECT CAST(@id AS uuid),company_id,location_id,employee_id,CAST(@shift AS uuid),template_id,revision_id,position,content
        FROM "${f.schema}".task_instances WHERE id=CAST(@source AS uuid)'''),
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
      }
      for (final root in ['/blocked-tasks', '/employee-home/blocked-tasks']) {
        final first = (await f.call(
          'GET',
          root,
          token: root.startsWith('/employee') ? p.token : null,
        )).body;
        final last = (await f.call(
          'GET',
          '$root?after=${first['nextCursor']}',
          token: root.startsWith('/employee') ? p.token : null,
        )).body;
        expect(first['items'], hasLength(50));
        expect(last['items'], hasLength(1));
        expect(last['nextCursor'], isNull);
        expect(jsonEncode(first), isNot(contains('Check equipment')));
        expect(
          [
            ...(first['items'] as List),
            ...(last['items'] as List),
          ].map((v) => v['id']).toSet(),
          hasLength(51),
        );
      }
      final other = await f.employee('No access');
      final token = await _linkedAccount(f, other, 'unrelated_worker');
      expect(
        (await f.call(
          'GET',
          '/employee-home/blocked-tasks',
          token: token,
        )).body['items'],
        isEmpty,
      );
      await f.call('GET', '${p.root}/blockings', token: token, expected: 404);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '0008 upgrades populated 0007 states and preserves old replay results',
    () => _withFixture(
      (f) async {
        final ids = <String>[], plans = <_Plan>[];
        for (var i = 0; i < 3; i++) {
          final p = await _plan(f);
          plans.add(p);
          await f.call('POST', '/shifts', body: p.input, expected: 201);
          final id =
              (await f.call(
                    'POST',
                    '/shifts/${p.id}/publish',
                    body: {'expectedVersion': 1},
                  )).body['tasks'][0]['id']
                  as String;
          ids.add(id);
          if (i > 0) {
            await f.owner.execute(
              'UPDATE "${f.schema}".task_instances SET status=\'in_progress\',version=2,started_at=clock_timestamp(),started_by=\'${f.adminPrincipal.id}\' WHERE id=\'$id\'',
            );
          }
          if (i == 2) {
            await f.owner.execute(
              'INSERT INTO "${f.schema}".task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by) VALUES(\'$id\',\'$_company\',\'$_home\',\'${p.template['content']['steps'][0]['id']}\',0,clock_timestamp(),\'${f.adminPrincipal.id}\')',
            );
            await f.owner.execute(
              'UPDATE "${f.schema}".task_instances SET version=3 WHERE id=\'$id\'',
            );
            await f.owner.execute(
              'UPDATE "${f.schema}".task_instances SET status=\'completed\',version=4,completed_at=clock_timestamp(),completed_by=\'${f.adminPrincipal.id}\' WHERE id=\'$id\'',
            );
          }
        }
        final token = await _linkedAccount(
          f,
          plans.last.employee,
          'upgrade_worker',
        );
        final actor = (await f.owner.execute(
          'SELECT id::text FROM "${f.schema}".accounts WHERE username=\'upgrade_worker\'',
        )).single.first;
        final at =
            (await f.owner.execute(
                  'SELECT started_at FROM "${f.schema}".task_instances WHERE id=\'${ids.last}\'',
                )).single.first
                as DateTime;
        final receipt = TaskExecutionDto(
          instanceId: ids.last,
          status: 'in_progress',
          version: 2,
          results: [],
          startedAt: at,
          startedBy: f.adminPrincipal.id,
        ).toJson();
        final command = _command(1);
        await f.owner.execute(
          Sql.named(
            '''INSERT INTO "${f.schema}".task_execution_commands(operation_id,company_id,location_id,instance_id,actor_id,input,result)
      VALUES(CAST(@op AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@task AS uuid),CAST(@actor AS uuid),@input,@result)''',
          ),
          parameters: {
            'op': command['operationId'],
            'company': _company,
            'location': _home,
            'task': ids.last,
            'actor': actor,
            'input': jsonEncode({
              'command': 'start',
              'expectedVersion': 1,
              'stepId': null,
            }),
            'result': jsonEncode(receipt),
          },
        );
        Future<List<String>> snapshot() async => [
          for (final table in ['task_instances', 'task_execution_commands'])
            (await f.owner.execute(
                  'SELECT jsonb_agg(to_jsonb(t) ORDER BY ${table == 'task_instances' ? 'id' : 'operation_id'})::text FROM "${f.schema}".$table t',
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
          '0008_task_blocking',
          '0009_task_cancellation',
          '0010_task_numeric_steps',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        expect(
          (await f.owner.execute(
            'SELECT accepted_version FROM "${f.schema}".task_step_results',
          )).single.first,
          3,
        );
        for (var i = 0; i < 3; i++) {
          expect(
            (await f.call(
              'GET',
              '/shifts/${plans[i].id}/tasks/${ids[i]}/execution',
            )).body['status'],
            ['open', 'in_progress', 'completed'][i],
          );
        }
        expect(
          (await f.call(
            'POST',
            '/employee-home/shifts/${plans.last.id}/tasks/${ids.last}/start',
            body: command,
            token: token,
          )).body,
          receipt,
        );
      },
      legacy: true,
      legacyBefore: '0008',
    ),
    skip: _skip,
  );
  test(
    'resolution replay requires current role and location',
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
      final manager = await f.account('resolver', role: 'admin'),
          token = await f.login('resolver');
      final command = _reasonCommand(3);
      final result = (await f.call(
        'POST',
        '$admin/resume',
        body: command,
        token: token,
      )).body;
      expect(
        (await f.call(
          'POST',
          '$admin/resume',
          body: command,
          token: token,
        )).body,
        result,
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET role=\'viewer\' WHERE id=\'${manager.id}\'',
      );
      await f.call(
        'POST',
        '$admin/resume',
        body: command,
        token: token,
        expected: 403,
      );
      await f.owner.execute(
        'UPDATE "${f.schema}".accounts SET role=\'admin\',location_id=\'$_other\' WHERE id=\'${manager.id}\'',
      );
      final foreign = SessionPrincipal(
        id: manager.id,
        username: manager.username,
        companyId: _company,
        locationId: _other,
      );
      for (final action in [
        () => ShiftApplication(f.database).blocked(foreign, self: false),
        () => ShiftApplication(
          f.database,
        ).blockings(foreign, p.plan.id, p.task, self: false),
        () => ShiftApplication(
          f.database,
        ).execute(foreign, p.plan.id, p.task, 'resume', command),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<PlatformFailure>().having((e) => e.status, 'status', 404),
          ),
        );
      }
    }),
    skip: _skip,
  );
}
