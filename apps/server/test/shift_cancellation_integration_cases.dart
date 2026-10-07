part of 'shift_integration_test.dart';

Map<String, dynamic> _cancelCommand(
  int version, {
  String reason = 'Wrong employee planned',
}) => {'expectedVersion': version, 'reason': reason};

Future<String> _shiftState(_Fixture f, String id) async =>
    (await f.owner.execute(
          'SELECT jsonb_build_object(\'shift\',to_jsonb(s),\'tasks\','
          'COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.position) '
          'FROM "${f.schema}".task_instances t WHERE t.shift_id=s.id),\'[]\'::jsonb))::text '
          'FROM "${f.schema}".shifts s WHERE s.id=\'$id\'',
        )).single.first
        as String;

Future<List<String>> _cancellationAuditRows(
  _Fixture f,
) async => (await f.owner.execute(
  'SELECT jsonb_build_object(\'action\',action,\'changes\',changes,'
  '\'correlation\',correlation_id::text)::text '
  'FROM "${f.schema}".audit_entries '
  "WHERE action IN ('workforce.shift.cancelled','tasks.instance.cancelled') ORDER BY id",
)).map((row) => row.first as String).toList();

Future<int> _workforceCancelAudits(_Fixture f) async =>
    (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".audit_entries '
          "WHERE action='workforce.shift.cancelled'",
        )).single.first
        as int;

Future<int> _taskShiftCancelAudits(_Fixture f) async =>
    (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".audit_entries '
          "WHERE action='tasks.instance.cancelled' AND changes->>'origin'='shift_cancellation'",
        )).single.first
        as int;

Future<_Plan> _twoTaskPlan(_Fixture f) async {
  final p = await _plan(f);
  final extra = _input();
  await f.call('POST', '/task-templates', body: extra, expected: 201);
  await f.call(
    'POST',
    '/task-templates/${extra['id']}/revisions/${extra['revisionId']}/publish',
    body: {'expectedVersion': 1},
  );
  (p.input['selections'] as List).add({
    'templateId': extra['id'],
    'revisionId': extra['revisionId'],
  });
  return p;
}

void shiftCancellationTests() {
  test(
    'published shift cancellation cancels pristine tasks with evidence and audit',
    () => _withFixture((f) async {
      final p = await _twoTaskPlan(f);
      final employeeToken = await _linkedAccount(
        f,
        p.employee,
        'cancel_worker',
      );
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      final published = (await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      )).body;
      expect(published['shift']['status'], 'published');
      expect(published['shift']['version'], 2);
      expect(published['tasks'], hasLength(2));
      final taskIds = (published['tasks'] as List)
          .map((t) => (t as Map)['id'] as String)
          .toList();
      final home = (await f.call(
        'GET',
        '/employee-home/shifts',
        token: employeeToken,
      )).body;
      expect((home['items'] as List).single['shift']['id'], p.id);

      final cancelled = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2, reason: '  Wrong employee planned  '),
      )).body;
      final shift = cancelled['shift'] as Map<String, dynamic>;
      expect(shift['status'], 'cancelled');
      expect(shift['version'], 3);
      expect(shift['publicationVersion'], 1);
      expect(shift['cancellationVersion'], 2);
      expect(shift['cancellationReason'], 'Wrong employee planned');
      expect(shift['cancelledBy'], f.adminPrincipal.id);
      expect(shift['cancelledAt'], isNotNull);
      for (final task in cancelled['tasks'] as List) {
        expect((task as Map)['status'], 'cancelled');
        expect(task['version'], 2);
      }
      final execution = (await f.call(
        'GET',
        '/shifts/${p.id}/tasks/${taskIds.first}/execution',
      )).body;
      expect(execution['status'], 'cancelled');
      expect(execution['version'], 2);
      expect(execution['startedAt'], isNull);
      expect(execution['cancelledAt'], isNotNull);
      expect(execution['cancelledBy'], f.adminPrincipal.id);
      expect(execution['cancelledBlockingId'], isNull);

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
        '/employee-home/shifts/${p.id}',
        token: employeeToken,
        expected: 404,
      );
      await f.call(
        'POST',
        '/employee-home/shifts/${p.id}/tasks/${taskIds.first}/start',
        body: _command(1),
        token: employeeToken,
        expected: 404,
      );
      final detail = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(detail['shift']['cancellationReason'], 'Wrong employee planned');
      final cancelledPage =
          (await f.call('GET', '/cancelled-tasks')).body['items'] as List;
      expect(cancelledPage.map((t) => (t as Map)['id']), containsAll(taskIds));

      final shiftAudit = (await f.owner.execute(
        'SELECT changes, correlation_id::text AS correlation '
        'FROM "${f.schema}".audit_entries '
        "WHERE action='workforce.shift.cancelled'",
      )).single.toColumnMap();
      final shiftChanges = shiftAudit['changes'] as Map;
      expect(shiftChanges['oldStatus'], 'published');
      expect(shiftChanges['status'], 'cancelled');
      expect(shiftChanges['oldVersion'], 2);
      expect(shiftChanges['version'], 3);
      expect(shiftChanges['cancellationVersion'], 2);
      expect(shiftChanges['reason'], 'Wrong employee planned');
      expect(shiftChanges['employeeId'], p.employee.id);
      final taskAudits = (await f.owner.execute(
        'SELECT changes, correlation_id::text AS correlation '
        'FROM "${f.schema}".audit_entries '
        "WHERE action='tasks.instance.cancelled' AND changes->>'origin'='shift_cancellation' "
        'ORDER BY id',
      )).map((row) => row.toColumnMap()).toList();
      expect(taskAudits, hasLength(2));
      for (final audit in taskAudits) {
        final changes = audit['changes'] as Map;
        expect(changes['oldStatus'], 'open');
        expect(changes['status'], 'cancelled');
        expect(changes['oldVersion'], 1);
        expect(changes['version'], 2);
        expect(changes['reason'], 'Wrong employee planned');
        expect(changes['shiftId'], p.id);
        expect(audit['correlation'], shiftAudit['correlation']);
      }

      await f.restart();
      final afterRestart = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(afterRestart['shift']['status'], 'cancelled');
      expect(afterRestart['tasks'], hasLength(2));
      expect(
        (afterRestart['tasks'] as List).every(
          (t) => (t as Map)['status'] == 'cancelled',
        ),
        isTrue,
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation retry identity is strict and side-effect free',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      final body = _cancelCommand(2, reason: 'Duplicate publication');
      final first = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: body,
      )).body;
      final audits = await _cancellationAuditRows(f);
      final second = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: body,
      )).body;
      expect(jsonEncode(second), jsonEncode(first));
      expect((second['shift'] as Map)['version'], 3);
      expect(await _cancellationAuditRows(f), audits);

      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: {...body, 'reason': 'Different reason'},
        expected: 409,
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(3, reason: body['reason'] as String),
        expected: 409,
      );
      final other = await f.account('second_admin', role: 'admin');
      final otherToken = await f.login(other.username);
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: body,
        token: otherToken,
        expected: 409,
      );
      expect(
        (await f.call('GET', '/shifts/${p.id}')).body['shift']['version'],
        3,
      );
      expect(await _cancellationAuditRows(f), audits);
    }),
    skip: _skip,
  );

  test(
    'cancellation reason boundary and retry identity count Unicode code points',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      final tooLong = '${'😀' * 251}${'x' * 250}';
      expect(tooLong.runes.length, 501);
      final refused = await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: {'expectedVersion': 2, 'reason': tooLong},
        expected: 400,
      );
      expect(refused.body['code'], 'invalid_reason');
      expect(
        (await f.call('GET', '/shifts/${p.id}')).body['shift']['status'],
        'published',
      );

      final boundary = '${'😀' * 250}${'x' * 250}';
      expect(boundary.runes.length, 500);
      expect(boundary.length, greaterThan(512));
      final cancelled = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: {'expectedVersion': 2, 'reason': '  $boundary  '},
      )).body;
      final shift = ShiftDto.fromJson(
        cancelled['shift'] as Map<String, dynamic>,
      );
      expect(shift.status, 'cancelled');
      expect(shift.cancellationReason, boundary);
      expect(
        (await f.owner.execute(
          'SELECT cancellation_reason FROM "${f.schema}".shifts '
          "WHERE id='${p.id}'",
        )).single.first,
        boundary,
      );
      final audits = await _cancellationAuditRows(f);
      expect(
        (await f.owner.execute(
          'SELECT changes->>\'reason\' FROM "${f.schema}".audit_entries '
          "WHERE action='workforce.shift.cancelled'",
        )).single.first,
        boundary,
      );

      final retried = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: {'expectedVersion': 2, 'reason': '$boundary '},
      )).body;
      expect(retried['shift']['version'], 3);
      expect(await _cancellationAuditRows(f), audits);

      final different = '${'😀' * 250}${'x' * 249}y';
      expect(different.runes.length, 500);
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: {'expectedVersion': 2, 'reason': different},
        expected: 409,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'cancellation is refused with zero writes once any task left open',
    () => _withFixture((f) async {
      Future<void> expectRefused(
        ({String root, String task, String token, _Plan plan}) p,
      ) async {
        final before = await _shiftState(f, p.plan.id);
        final shiftAudits = await _workforceCancelAudits(f);
        final taskAudits = await _taskShiftCancelAudits(f);
        final reply = await f.call(
          'POST',
          '/shifts/${p.plan.id}/cancel',
          body: _cancelCommand(2),
          expected: 422,
        );
        expect(reply.body['code'], 'shift_in_progress');
        expect(reply.body['message'], contains(p.task));
        expect(await _shiftState(f, p.plan.id), before);
        expect(await _workforceCancelAudits(f), shiftAudits);
        expect(await _taskShiftCancelAudits(f), taskAudits);
      }

      final started = await _executionPlan(f, accountName: 'started_worker');
      await f.call(
        'POST',
        '${started.root}/start',
        body: _command(1),
        token: started.token,
      );
      await expectRefused(started);

      final blocked = await _executionPlan(f, accountName: 'blocked_worker');
      await f.call(
        'POST',
        '${blocked.root}/start',
        body: _command(1),
        token: blocked.token,
      );
      await f.call(
        'POST',
        '${blocked.root}/block',
        body: _reasonCommand(2),
        token: blocked.token,
      );
      await expectRefused(blocked);

      final completed = await _executionPlan(
        f,
        accountName: 'completed_worker',
      );
      final step = completed.plan.template['content']['steps'][0]['id'];
      await f.call(
        'POST',
        '${completed.root}/start',
        body: _command(1),
        token: completed.token,
      );
      await f.call(
        'POST',
        '${completed.root}/steps/$step/confirm',
        body: _command(2),
        token: completed.token,
      );
      await f.call(
        'POST',
        '${completed.root}/complete',
        body: _command(3),
        token: completed.token,
      );
      await expectRefused(completed);

      final alreadyCancelled = await _executionPlan(
        f,
        accountName: 'cancelled_worker',
      );
      final admin =
          '/shifts/${alreadyCancelled.plan.id}/tasks/${alreadyCancelled.task}';
      await f.call(
        'POST',
        '${alreadyCancelled.root}/start',
        body: _command(1),
        token: alreadyCancelled.token,
      );
      await f.call(
        'POST',
        '${alreadyCancelled.root}/block',
        body: _reasonCommand(2),
        token: alreadyCancelled.token,
      );
      await f.call('POST', '$admin/resume', body: _reasonCommand(3));
      await f.call(
        'POST',
        '${alreadyCancelled.root}/block',
        body: _reasonCommand(4),
        token: alreadyCancelled.token,
      );
      await f.call('POST', '$admin/cancel', body: _reasonCommand(5));
      await expectRefused(alreadyCancelled);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'cancellation frees the employee interval for a corrected publication',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      final corrected = {...p.input, 'id': newUuid()};
      await f.call('POST', '/shifts', body: corrected, expected: 201);
      await f.call(
        'POST',
        '/shifts/${corrected['id']}/publish',
        body: {'expectedVersion': 1},
        expected: 409,
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2, reason: 'Replace with corrected shift'),
      );
      final republished = (await f.call(
        'POST',
        '/shifts/${corrected['id']}/publish',
        body: {'expectedVersion': 1},
      )).body;
      expect(republished['shift']['status'], 'published');
      expect(republished['tasks'], hasLength(1));
      expect(republished['shift']['startsAt'], p.input['startsAt']);
      expect(republished['shift']['endsAt'], p.input['endsAt']);
    }),
    skip: _skip,
  );

  test(
    'cancellation authorization is server-side and concealed',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      for (final role in ['employee', 'viewer', 'auditor']) {
        final account = await f.account('cancel_$role', role: role);
        final token = await f.login(account.username);
        await f.call(
          'POST',
          '/shifts/${p.id}/cancel',
          body: _cancelCommand(2),
          token: token,
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '/shifts/${newUuid()}/cancel',
        body: _cancelCommand(1),
        expected: 404,
      );
      final plugins = PluginService(f.database);
      final registration = await plugins.register(f.adminPrincipal, {
        'manifest': {
          'id': 'shift-cancel-denied',
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
      final grant = await plugins.approve(
        f.adminPrincipal,
        'shift-cancel-denied',
        {
          'expectedVersion': registration['version'],
          'locationId': _home,
          'permissions': ['organization.read'],
          'subscriptions': <String>[],
        },
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2),
        token: grant['token'] as String,
        expected: 401,
      );
    }),
    skip: _skip,
  );

  test(
    'concurrent cancellation retries commit one business cancellation',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      final body = _cancelCommand(2, reason: 'Parallel duplicate');
      final responses = await Future.wait([
        f.call('POST', '/shifts/${p.id}/cancel', body: body, expected: null),
        f.call('POST', '/shifts/${p.id}/cancel', body: body, expected: null),
      ]);
      expect(responses.map((r) => r.status), everyElement(200));
      final state = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(state['shift']['version'], 3);
      expect(state['shift']['cancellationVersion'], 2);
      expect(await _workforceCancelAudits(f), 1);
      expect(await _taskShiftCancelAudits(f), 1);

      final other = await _plan(f);
      await f.call('POST', '/shifts', body: other.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${other.id}/publish',
        body: {'expectedVersion': 1},
      );
      final conflicting = await Future.wait([
        f.call(
          'POST',
          '/shifts/${other.id}/cancel',
          body: _cancelCommand(2, reason: 'First reason'),
          expected: null,
        ),
        f.call(
          'POST',
          '/shifts/${other.id}/cancel',
          body: _cancelCommand(2, reason: 'Second reason'),
          expected: null,
        ),
      ]);
      expect(conflicting.map((r) => r.status).toList()..sort(), [200, 409]);
      expect(
        (await f.call('GET', '/shifts/${other.id}')).body['shift']['version'],
        3,
      );
    }),
    skip: _skip,
  );

  test(
    'cancellation and task start cannot both succeed',
    () => _withFixture((f) async {
      final p = await _executionPlan(f);
      final results = await Future.wait([
        f.call(
          'POST',
          '/shifts/${p.plan.id}/cancel',
          body: _cancelCommand(2),
          expected: null,
        ),
        f.call(
          'POST',
          '${p.root}/start',
          body: _command(1),
          token: p.token,
          expected: null,
        ),
      ]);
      final cancelResult = results[0], startResult = results[1];
      expect(
        [cancelResult.status, startResult.status],
        anyOf([
          equals([200, 404]),
          equals([422, 200]),
        ]),
      );
      final state = (await f.call('GET', '/shifts/${p.plan.id}')).body;
      if (cancelResult.status == 200) {
        expect(state['shift']['status'], 'cancelled');
        expect((state['tasks'] as List).single['status'], 'cancelled');
        expect(startResult.status, 404);
      } else {
        expect(state['shift']['status'], 'published');
        expect((state['tasks'] as List).single['status'], 'in_progress');
        expect(startResult.status, 200);
      }
    }),
    skip: _skip,
  );

  test(
    'a failing task transition rolls back the whole cancellation',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".reject_cancel() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'injected cancel failure\'; END; \$\$',
      );
      await f.owner.execute(
        'CREATE TRIGGER reject_cancel BEFORE UPDATE ON "${f.schema}".task_instances FOR EACH ROW EXECUTE FUNCTION "${f.schema}".reject_cancel()',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2),
        expected: 500,
      );
      final state = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(state['shift']['status'], 'published');
      expect((state['tasks'] as List).single['status'], 'open');
      expect(await _workforceCancelAudits(f), 0);
      expect(await _taskShiftCancelAudits(f), 0);
      await f.owner.execute(
        'DROP TRIGGER reject_cancel ON "${f.schema}".task_instances',
      );
      final cancelled = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2),
      )).body;
      expect(cancelled['shift']['status'], 'cancelled');
    }),
    skip: _skip,
  );

  test(
    'a failing shift update rolls back prior task cancellations and audits',
    () => _withFixture((f) async {
      final p = await _twoTaskPlan(f);
      await f.call('POST', '/shifts', body: p.input, expected: 201);
      await f.call(
        'POST',
        '/shifts/${p.id}/publish',
        body: {'expectedVersion': 1},
      );
      final before = await _shiftState(f, p.id);
      await f.owner.execute(
        'CREATE FUNCTION "${f.schema}".reject_shift_cancel() RETURNS trigger '
        'LANGUAGE plpgsql AS \$\$ DECLARE cancelled integer; total integer; '
        'BEGIN SELECT count(*) INTO cancelled FROM "${f.schema}".task_instances '
        'WHERE shift_id=NEW.id AND status=\'cancelled\'; '
        'SELECT count(*) INTO total FROM "${f.schema}".task_instances '
        'WHERE shift_id=NEW.id; '
        'IF NEW.status=\'cancelled\' AND total>0 AND cancelled=total THEN '
        'RAISE EXCEPTION \'injected shift cancel failure\'; END IF; '
        'RETURN NEW; END; \$\$',
      );
      await f.owner.execute(
        'CREATE TRIGGER reject_shift_cancel BEFORE UPDATE ON '
        '"${f.schema}".shifts FOR EACH ROW '
        'EXECUTE FUNCTION "${f.schema}".reject_shift_cancel()',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2),
        expected: 500,
      );
      final shift = (await f.owner.execute(
        'SELECT status, version, cancelled_at, cancelled_by, '
        'cancellation_reason, cancellation_version FROM "${f.schema}".shifts '
        "WHERE id='${p.id}'",
      )).single.toColumnMap();
      expect(shift['status'], 'published');
      expect(shift['version'], 2);
      expect(shift['cancelled_at'], isNull);
      expect(shift['cancelled_by'], isNull);
      expect(shift['cancellation_reason'], isNull);
      expect(shift['cancellation_version'], isNull);
      final tasks = (await f.owner.execute(
        'SELECT status, version, cancelled_at, cancelled_by '
        'FROM "${f.schema}".task_instances '
        "WHERE shift_id='${p.id}' ORDER BY position",
      )).map((row) => row.toColumnMap()).toList();
      expect(tasks, hasLength(2));
      for (final task in tasks) {
        expect(task['status'], 'open');
        expect(task['version'], 1);
        expect(task['cancelled_at'], isNull);
        expect(task['cancelled_by'], isNull);
      }
      expect(await _workforceCancelAudits(f), 0);
      expect(await _taskShiftCancelAudits(f), 0);
      expect(await _shiftState(f, p.id), before);
      await f.owner.execute(
        'DROP TRIGGER reject_shift_cancel ON "${f.schema}".shifts',
      );
      final cancelled = (await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2),
      )).body;
      expect(cancelled['shift']['status'], 'cancelled');
      expect(cancelled['tasks'], hasLength(2));
      expect(
        (cancelled['tasks'] as List).every(
          (t) => (t as Map)['status'] == 'cancelled',
        ),
        isTrue,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '0011 preserves populated shifts and blocked cancellations, then enables cancellation',
    () => _withFixture(
      (f) async {
        final pristine = await _plan(f);
        final legacy = await _plan(f);
        final legacyStart = DateTime.now().toUtc().add(const Duration(days: 2));
        await _seedPublishedShift(
          f,
          pristine,
          start: legacyStart.add(const Duration(days: 1)),
        );
        final actor = f.adminPrincipal.id;
        final legacyTask = await _seedPublishedShift(
          f,
          legacy,
          start: legacyStart,
        );
        final step = legacy.template['content']['steps'][0]['id'];
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'in_progress\','
          'version=2,started_at=clock_timestamp(),started_by=\'$actor\' '
          'WHERE id=\'$legacyTask\'',
        );
        await f.owner.execute(
          'INSERT INTO "${f.schema}".task_step_results(instance_id,company_id,'
          'location_id,step_id,position,confirmed_at,confirmed_by,accepted_version) '
          'VALUES(\'$legacyTask\',\'$_company\',\'$_home\',\'$step\',0,'
          'clock_timestamp(),\'$actor\',3)',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET version=3 '
          'WHERE id=\'$legacyTask\'',
        );
        final blockingId = newUuid();
        await f.owner.execute(
          'INSERT INTO "${f.schema}".task_blockings(id,instance_id,company_id,'
          'location_id,reason,reported_at,reported_by,reported_version) '
          'VALUES(\'$blockingId\',\'$legacyTask\',\'$_company\',\'$_home\','
          '\'Missing\',clock_timestamp(),\'$actor\',4)',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'blocked\',version=4 '
          'WHERE id=\'$legacyTask\'',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_blockings SET resolution=\'Not possible\','
          'resolved_at=clock_timestamp(),resolved_by=\'$actor\','
          'resolved_version=5,resolution_kind=\'cancelled\' WHERE id=\'$blockingId\'',
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'cancelled\',version=5 '
          'WHERE id=\'$legacyTask\'',
        );
        Future<List<String>> snapshot() async => [
          (await f.owner.execute(
                'SELECT jsonb_agg((to_jsonb(s)-ARRAY[\'cancelled_at\',\'cancelled_by\','
                '\'cancellation_reason\',\'cancellation_version\',\'amended_at\','
                '\'amended_by\',\'amendment_version\']) ORDER BY id)::text '
                'FROM "${f.schema}".shifts s',
              )).single.first
              as String,
          (await f.owner.execute(
                'SELECT jsonb_agg((to_jsonb(t)-ARRAY[\'cancelled_at\',\'cancelled_by\','
                '\'knowledge_article_id\',\'knowledge_revision_id\','
                '\'knowledge_revision_state\',\'planogram_fixture_id\',\'planogram_assignment_id\',\'planogram_revision_id\']) '
                'ORDER BY id)::text FROM "${f.schema}".task_instances t',
              )).single.first
              as String,
          (await f.owner.execute(
                'SELECT jsonb_agg(to_jsonb(b) ORDER BY id)::text '
                'FROM "${f.schema}".task_blockings b',
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
          '0011_published_shift_cancellation',
          '0012_published_shift_amendment',
          '0013_article_master',
          '0014_location_assortment',
          '0015_manual_stock',
          '0016_local_planograms',
          '0017_approved_operational_knowledge',
          '0018_task_knowledge_guidance',
          '0019_task_planogram_guidance',
          '0020_stock_counts',
          '0021_recipe_compositions',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        await _expectLegacyGuidanceNull(f);

        final refused = await f.call(
          'POST',
          '/shifts/${legacy.id}/cancel',
          body: _cancelCommand(2),
          expected: 422,
        );
        expect(refused.body['code'], 'shift_in_progress');

        final cancelled = (await f.call(
          'POST',
          '/shifts/${pristine.id}/cancel',
          body: _cancelCommand(2, reason: 'Upgraded cancellation'),
        )).body;
        expect(cancelled['shift']['status'], 'cancelled');
        expect(cancelled['tasks'], hasLength(1));
        expect((cancelled['tasks'] as List).single['version'], 2);
        expect((cancelled['tasks'] as List).single['status'], 'cancelled');

        final fresh = await _plan(f);
        final openTask = await _seedPublishedShift(
          f,
          fresh,
          start: DateTime.now().toUtc(),
        );
        for (final sql in [
          'UPDATE "${f.schema}".task_instances SET status=\'cancelled\','
              'version=2,cancelled_at=clock_timestamp() WHERE id=\'$openTask\'',
          'UPDATE "${f.schema}".task_instances SET status=\'cancelled\','
              'version=2,cancelled_by=\'$actor\' WHERE id=\'$openTask\'',
          'UPDATE "${f.schema}".task_instances SET status=\'cancelled\','
              'version=version+1,cancelled_at=clock_timestamp(),cancelled_by=\'$actor\' '
              'WHERE id=\'$legacyTask\'',
        ]) {
          await expectLater(
            f.owner.execute(sql),
            throwsA(isA<ServerException>()),
          );
        }
        await expectLater(
          f.owner.execute(
            'UPDATE "${f.schema}".shifts SET cancellation_reason=\'changed\' '
            'WHERE id=\'${pristine.id}\'',
          ),
          throwsA(isA<ServerException>()),
        );
      },
      legacy: true,
      legacyBefore: '0011',
    ),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
