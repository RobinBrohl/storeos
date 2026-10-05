part of 'shift_integration_test.dart';

Map<String, dynamic> _amendCommand(
  int version, {
  required DateTime startsAt,
  required DateTime endsAt,
}) => {
  'expectedVersion': version,
  'startsAt': startsAt.toUtc().toIso8601String(),
  'endsAt': endsAt.toUtc().toIso8601String(),
};

Future<String> _shiftJson(_Fixture f, String id) async =>
    (await f.owner.execute(
          'SELECT to_jsonb(s)::text FROM "${f.schema}".shifts s '
          "WHERE id='$id'",
        )).single.first
        as String;

Future<String> _instanceState(_Fixture f, String shiftId) async =>
    (await f.owner.execute(
          'SELECT COALESCE(jsonb_agg(jsonb_build_object('
          "'id',id::text,'status',status,'version',version,"
          "'employee',employee_id::text,'content',content) "
          'ORDER BY position),\'[]\'::jsonb)::text '
          'FROM "${f.schema}".task_instances WHERE shift_id=\'$shiftId\'',
        )).single.first
        as String;

Future<int> _amendmentAuditCount(_Fixture f) async =>
    (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".audit_entries '
          "WHERE action='workforce.shift.amended'",
        )).single.first
        as int;

Future<int> _amendmentAuditCountFor(_Fixture f, String shiftId) async =>
    (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".audit_entries '
          "WHERE action='workforce.shift.amended' AND entity_id='$shiftId'",
        )).single.first
        as int;

Future<String> _amendmentAudits(_Fixture f) async =>
    (await f.owner.execute(
          'SELECT COALESCE(jsonb_agg(jsonb_build_object('
          "'action',action,'changes',changes,'correlation',correlation_id::text) "
          'ORDER BY id),\'[]\'::jsonb)::text '
          'FROM "${f.schema}".audit_entries '
          "WHERE action='workforce.shift.amended'",
        )).single.first
        as String;

Future<void> _publishPlan(_Fixture f, _Plan p) async {
  await f.call('POST', '/shifts', body: p.input, expected: 201);
  await f.call('POST', '/shifts/${p.id}/publish', body: {'expectedVersion': 1});
}

void shiftAmendmentTests() {
  test(
    'published shift interval amendment persists, keeps instances and audits one change',
    () => _withFixture((f) async {
      final p = await _twoTaskPlan(f);
      final employeeToken = await _linkedAccount(f, p.employee, 'amend_worker');
      await _publishPlan(f, p);
      final published = (await f.call('GET', '/shifts/${p.id}')).body;
      final instancesBefore = await _instanceState(f, p.id);
      final auditsBefore = await f.owner.execute(
        'SELECT count(*)::int FROM "${f.schema}".audit_entries',
      );
      final start = DateTime.parse(p.input['startsAt'] as String),
          oldEnd = DateTime.parse(p.input['endsAt'] as String);
      final newStart = start.add(const Duration(hours: 2)),
          newEnd = start.add(const Duration(hours: 6));

      final amended = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(2, startsAt: newStart, endsAt: newEnd),
      )).body;
      final shift = amended['shift'] as Map<String, dynamic>;
      expect(shift['status'], 'published');
      expect(shift['version'], 3);
      expect(shift['startsAt'], newStart.toIso8601String());
      expect(shift['endsAt'], newEnd.toIso8601String());
      expect(shift['employeeId'], p.employee.id);
      expect(shift['selections'], (published['shift'] as Map)['selections']);
      expect(shift['publicationVersion'], 1);
      expect(shift['amendedAt'], isNotNull);
      expect(shift['amendedBy'], f.adminPrincipal.id);
      expect(shift['amendmentVersion'], 2);
      expect(amended['tasks'], hasLength(2));
      expect(await _instanceState(f, p.id), instancesBefore);
      expect(
        (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".audit_entries',
        )).single.first,
        (auditsBefore.single.first as int) + 1,
      );

      final audit = (await f.owner.execute(
        'SELECT changes, correlation_id::text AS correlation '
        'FROM "${f.schema}".audit_entries '
        "WHERE action='workforce.shift.amended'",
      )).single.toColumnMap();
      final changes = audit['changes'] as Map;
      expect(changes['oldStartsAt'], start.toIso8601String());
      expect(changes['oldEndsAt'], oldEnd.toIso8601String());
      expect(changes['startsAt'], newStart.toIso8601String());
      expect(changes['endsAt'], newEnd.toIso8601String());
      expect(changes['employeeId'], p.employee.id);
      expect(changes['version'], 3);
      expect(changes['amendmentVersion'], 2);
      expect(changes['changedFields'], containsAll(['startsAt', 'endsAt']));
      expect(audit['correlation'], isNotNull);

      final detail = (await f.call('GET', '/shifts/${p.id}')).body;
      expect((detail['shift'] as Map)['startsAt'], newStart.toIso8601String());
      final home = (await f.call(
        'GET',
        '/employee-home/shifts',
        token: employeeToken,
      )).body;
      expect(
        ((home['items'] as List).single as Map)['shift']['startsAt'],
        newStart.toIso8601String(),
      );

      await f.restart();
      final afterRestart = (await f.call('GET', '/shifts/${p.id}')).body;
      expect(
        (afterRestart['shift'] as Map)['endsAt'],
        newEnd.toIso8601String(),
      );
      expect((afterRestart['shift'] as Map)['amendmentVersion'], 2);
    }),
    skip: _skip,
  );

  test(
    'amendment no-op and exact retry are side-effect free',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String),
          end = DateTime.parse(p.input['endsAt'] as String);

      final noop = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(2, startsAt: start, endsAt: end),
      )).body;
      expect((noop['shift'] as Map)['version'], 2);
      expect((noop['shift'] as Map)['amendmentVersion'], isNull);
      expect(await _amendmentAuditCount(f), 0);

      final newStart = start.add(const Duration(hours: 1)),
          newEnd = start.add(const Duration(hours: 7));
      final body = _amendCommand(2, startsAt: newStart, endsAt: newEnd);
      final first = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: body,
      )).body;
      final audits = await _amendmentAudits(f);
      final retry = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: body,
      )).body;
      expect(jsonEncode(retry), jsonEncode(first));
      expect((retry['shift'] as Map)['version'], 3);
      expect(await _amendmentAudits(f), audits);

      final sameWindow = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(3, startsAt: newStart, endsAt: newEnd),
      )).body;
      expect((sameWindow['shift'] as Map)['version'], 3);
      expect(await _amendmentAuditCount(f), 1);

      final stale = await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(2, startsAt: start, endsAt: newEnd),
        expected: 409,
      );
      expect(stale.body['code'], 'shift_conflict');
      final other = await f.account('second_amend_admin', role: 'admin');
      final otherToken = await f.login(other.username);
      await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: body,
        token: otherToken,
        expected: 409,
      );

      final second = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          3,
          startsAt: start.add(const Duration(hours: 2)),
          endsAt: start.add(const Duration(hours: 8)),
        ),
      )).body;
      expect((second['shift'] as Map)['version'], 4);
      expect((second['shift'] as Map)['amendmentVersion'], 3);
      await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: body,
        expected: 409,
        token: otherToken,
      );
      await f.call('POST', '/shifts/${p.id}/amend', body: body, expected: 409);
      expect(await _amendmentAuditCount(f), 2);
    }),
    skip: _skip,
  );

  test(
    'amendment is refused with zero writes once any task left open',
    () => _withFixture((f) async {
      Future<void> expectRefused(
        ({String root, String task, String token, _Plan plan}) p,
      ) async {
        final before = await _shiftJson(f, p.plan.id);
        final audits = await _amendmentAudits(f);
        final start = DateTime.parse(p.plan.input['startsAt'] as String),
            end = DateTime.parse(p.plan.input['endsAt'] as String);
        final reply = await f.call(
          'POST',
          '/shifts/${p.plan.id}/amend',
          body: _amendCommand(
            2,
            startsAt: start.add(const Duration(hours: 1)),
            endsAt: end.add(const Duration(hours: 1)),
          ),
          expected: 422,
        );
        expect(reply.body['code'], 'shift_in_progress');
        expect(reply.body['message'], contains(p.task));
        expect(await _shiftJson(f, p.plan.id), before);
        expect(await _amendmentAudits(f), audits);
      }

      final started = await _executionPlan(f, accountName: 'amend_started');
      await f.call(
        'POST',
        '${started.root}/start',
        body: _command(1),
        token: started.token,
      );
      await expectRefused(started);

      final blocked = await _executionPlan(f, accountName: 'amend_blocked');
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

      final completed = await _executionPlan(f, accountName: 'amend_completed');
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
        accountName: 'amend_cancelled',
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

      expect(await _amendmentAuditCount(f), 0);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'amendment validation, authorization and scope are server-side',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String),
          end = DateTime.parse(p.input['endsAt'] as String);
      final valid = _amendCommand(
        2,
        startsAt: start.add(const Duration(hours: 1)),
        endsAt: end.add(const Duration(hours: 1)),
      );
      for (final bad in [
        {'expectedVersion': 2, 'startsAt': start.toIso8601String()},
        {...valid, 'employeeId': p.employee.id},
        {...valid, 'expectedVersion': 0},
        {
          'expectedVersion': 2,
          'startsAt': '2030-01-01T08:00:00',
          'endsAt': end.toIso8601String(),
        },
        {
          'expectedVersion': 2,
          'startsAt': start.toIso8601String(),
          'endsAt': start.toIso8601String(),
        },
        {
          'expectedVersion': 2,
          'startsAt': end.toIso8601String(),
          'endsAt': start.toIso8601String(),
        },
      ]) {
        final reply = await f.call(
          'POST',
          '/shifts/${p.id}/amend',
          body: bad,
          expected: 400,
        );
        expect(reply.body['code'], anyOf('invalid_request', 'invalid_shift'));
      }
      await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: valid,
        token: '',
        expected: 401,
      );
      for (final role in ['employee', 'viewer', 'auditor']) {
        final account = await f.account('amend_$role', role: role);
        final token = await f.login(account.username);
        await f.call(
          'POST',
          '/shifts/${p.id}/amend',
          body: valid,
          token: token,
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '/shifts/${newUuid()}/amend',
        body: valid,
        expected: 404,
      );

      final draft = await _plan(f);
      await f.call('POST', '/shifts', body: draft.input, expected: 201);
      final draftReply = await f.call(
        'POST',
        '/shifts/${draft.id}/amend',
        body: _amendCommand(1, startsAt: start, endsAt: end),
        expected: 409,
      );
      expect(draftReply.body['code'], 'shift_conflict');

      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2, reason: 'Amend after cancel refused'),
      );
      final cancelledReply = await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          3,
          startsAt: start.add(const Duration(hours: 2)),
          endsAt: end.add(const Duration(hours: 2)),
        ),
        expected: 409,
      );
      expect(cancelledReply.body['code'], 'shift_conflict');
      expect(await _amendmentAuditCount(f), 0);
      expect(
        ((await f.call('GET', '/shifts/${p.id}')).body['shift']
            as Map)['status'],
        'cancelled',
      );
      expect(
        ((await f.call('GET', '/shifts/${draft.id}')).body['shift']
            as Map)['startsAt'],
        draft.input['startsAt'],
      );
    }),
    skip: _skip,
  );

  test(
    'amendment applies publish eligibility to the new interval',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String);
      await f.call(
        'POST',
        '/employees/${p.employee.id}/deactivate',
        body: {'expectedVersion': 1},
      );
      final before = await _shiftJson(f, p.id);
      final reply = await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          2,
          startsAt: start.add(const Duration(hours: 1)),
          endsAt: start.add(const Duration(hours: 5)),
        ),
        expected: 422,
      );
      expect(reply.body['code'], 'employee_unavailable');
      expect(await _shiftJson(f, p.id), before);
      expect(await _amendmentAuditCount(f), 0);
    }),
    skip: _skip,
  );

  test(
    'amendment overlap, back-to-back and cancelled intervals behave exactly',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String),
          end = DateTime.parse(p.input['endsAt'] as String);
      final adjacentId = newUuid();
      await f.call(
        'POST',
        '/shifts',
        body: {
          ...p.input,
          'id': adjacentId,
          'startsAt': end.toIso8601String(),
          'endsAt': end.add(const Duration(hours: 8)).toIso8601String(),
        },
        expected: 201,
      );
      await f.call(
        'POST',
        '/shifts/$adjacentId/publish',
        body: {'expectedVersion': 1},
      );

      final overlap = await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          2,
          startsAt: start.add(const Duration(hours: 4)),
          endsAt: end.add(const Duration(hours: 4)),
        ),
        expected: 409,
      );
      expect(overlap.body['code'], 'shift_overlap');
      expect(
        (await f.call('GET', '/shifts/${p.id}')).body['shift']['version'],
        2,
      );
      expect(await _amendmentAuditCount(f), 0);

      final backToBack = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          2,
          startsAt: start.subtract(const Duration(hours: 2)),
          endsAt: end,
        ),
      )).body;
      expect((backToBack['shift'] as Map)['version'], 3);

      await f.call(
        'POST',
        '/shifts/$adjacentId/cancel',
        body: _cancelCommand(2, reason: 'Window no longer needed'),
      );
      final freed = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(
          3,
          startsAt: end,
          endsAt: end.add(const Duration(hours: 8)),
        ),
      )).body;
      expect((freed['shift'] as Map)['startsAt'], end.toIso8601String());
      expect((freed['shift'] as Map)['version'], 4);
    }),
    skip: _skip,
  );

  test(
    'published interval exclusion constraint rejects raw writers',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String),
          end = DateTime.parse(p.input['endsAt'] as String);
      Future<void> insertPublished(
        String id,
        DateTime startsAt,
        DateTime endsAt,
      ) => f.owner.execute(
        Sql.named(
          'INSERT INTO "${f.schema}".shifts(id,company_id,location_id,'
          'employee_id,starts_at,ends_at,status,version,created_by,creation_input,'
          'published_at,published_by,publication_version) '
          'VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),'
          'CAST(@employee AS uuid),@start,@end,\'published\',2,CAST(@actor AS uuid),'
          '\'{}\',clock_timestamp(),CAST(@actor AS uuid),1)',
        ),
        parameters: {
          'id': id,
          'company': _company,
          'location': _home,
          'employee': p.employee.id,
          'actor': f.adminPrincipal.id,
          'start': startsAt,
          'end': endsAt,
        },
      );

      await expectLater(
        insertPublished(
          newUuid(),
          start.add(const Duration(hours: 1)),
          end.add(const Duration(hours: 1)),
        ),
        throwsA(
          isA<ServerException>()
              .having((e) => e.code, 'code', '23P01')
              .having(
                (e) => e.constraintName,
                'constraint',
                'shifts_published_no_overlap',
              ),
        ),
      );
      await insertPublished(newUuid(), end, end.add(const Duration(hours: 8)));
      await f.call(
        'POST',
        '/shifts/${p.id}/cancel',
        body: _cancelCommand(2, reason: 'Freed interval'),
      );
      await insertPublished(
        newUuid(),
        start.add(const Duration(hours: 1)),
        end.subtract(const Duration(hours: 1)),
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*)::int FROM "${f.schema}".shifts',
        )).single.first,
        3,
      );
    }),
    skip: _skip,
  );

  test(
    'protection triggers preserve the 0011 invariants on the 0012 schema',
    () => _withFixture((f) async {
      final p = await _plan(f);
      await _publishPlan(f, p);
      final actor = f.adminPrincipal.id;
      final other = await f.account('raw_amend_admin', role: 'admin');
      for (final sql in [
        "UPDATE \"${f.schema}\".shifts SET employee_id='${other.id}' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET location_id='$_other' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET company_id='${newUuid()}' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET published_by='${other.id}' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET publication_version=9 WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET cancellation_reason='injected' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET amendment_version=2 WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET amended_at=clock_timestamp() WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET starts_at=starts_at, "
            "amended_at=clock_timestamp(),amended_by='$actor',"
            "amendment_version=2,version=version+1 WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET starts_at=starts_at+interval '1 hour' WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET starts_at=starts_at+interval '1 hour',"
            "version=version+1,amended_at=clock_timestamp(),amended_by='$actor',"
            "amendment_version=99 WHERE id='${p.id}'",
        "UPDATE \"${f.schema}\".shifts SET version=version+1,"
            "amended_at=clock_timestamp(),amended_by='$actor',"
            "amendment_version=2 WHERE id='${p.id}'",
        "DELETE FROM \"${f.schema}\".shifts WHERE id='${p.id}'",
      ]) {
        await expectLater(
          f.owner.execute(sql),
          throwsA(isA<ServerException>()),
          reason: sql,
        );
      }
      await expectLater(
        f.pool.execute(
          'UPDATE "${f.schema}".shifts SET creation_input=\'{}\' '
          "WHERE id='${p.id}'",
        ),
        throwsA(isA<PgException>()),
      );
      await f.pool.execute(
        'UPDATE "${f.schema}".shifts SET starts_at=starts_at+interval \'1 hour\','
        "ends_at=ends_at+interval '1 hour',version=version+1,"
        "updated_at=clock_timestamp(),amended_at=clock_timestamp(),"
        "amended_by='$actor',amendment_version=2 WHERE id='${p.id}'",
      );
      final row = (await f.owner.execute(
        'SELECT version, amendment_version FROM "${f.schema}".shifts '
        "WHERE id='${p.id}'",
      )).single.toColumnMap();
      expect(row['version'], 3);
      expect(row['amendment_version'], 2);
    }),
    skip: _skip,
  );

  test(
    'amendment and task start serialize, and tasks use the amended window',
    () => _withFixture((f) async {
      final p = await _executionPlan(f, accountName: 'amend_race_worker');
      final now = DateTime.now().toUtc();
      final future = _amendCommand(
        2,
        startsAt: now.add(const Duration(hours: 1)),
        endsAt: now.add(const Duration(hours: 2)),
      );
      final results = await Future.wait([
        f.call(
          'POST',
          '/shifts/${p.plan.id}/amend',
          body: future,
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
      final amend = results[0], start = results[1];
      expect([amend.status, start.status]..sort(), [200, 422]);
      if (amend.status == 200) {
        expect(start.body['code'], 'outside_shift');
        expect((amend.body['shift'] as Map)['version'], 3);
        expect(
          ((await f.call('GET', '/shifts/${p.plan.id}')).body['tasks'] as List)
              .single['status'],
          'open',
        );
      } else {
        expect(amend.body['code'], 'shift_in_progress');
        expect(start.status, 200);
        expect(
          ((await f.call('GET', '/shifts/${p.plan.id}')).body['tasks'] as List)
              .single['status'],
          'in_progress',
        );
      }

      final sequential = await _executionPlan(
        f,
        accountName: 'amend_window_worker',
      );
      final at = DateTime.now().toUtc();
      await f.call(
        'POST',
        '/shifts/${sequential.plan.id}/amend',
        body: _amendCommand(
          2,
          startsAt: at.add(const Duration(hours: 1)),
          endsAt: at.add(const Duration(hours: 2)),
        ),
      );
      final refused = await f.call(
        'POST',
        '${sequential.root}/start',
        body: _command(1),
        token: sequential.token,
        expected: 422,
      );
      expect(refused.body['code'], 'outside_shift');
      await f.call(
        'POST',
        '/shifts/${sequential.plan.id}/amend',
        body: _amendCommand(
          3,
          startsAt: sequential.plan.employee.assignedFrom,
          endsAt: at.add(const Duration(minutes: 30)),
        ),
      );
      await f.call(
        'POST',
        '${sequential.root}/start',
        body: _command(1),
        token: sequential.token,
      );
      expect(
        ((await f.call('GET', '/shifts/${sequential.plan.id}')).body['tasks']
                as List)
            .single['status'],
        'in_progress',
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'amendment and cancellation, and concurrent amendments, serialize deterministically',
    () => _withFixture((f) async {
      final raced = await _executionPlan(f, accountName: 'amend_cancel_worker');
      final results = await Future.wait([
        f.call(
          'POST',
          '/shifts/${raced.plan.id}/amend',
          body: _amendCommand(
            2,
            startsAt: raced.plan.employee.assignedFrom,
            endsAt: raced.plan.employee.assignedFrom.add(
              const Duration(hours: 2),
            ),
          ),
          expected: null,
        ),
        f.call(
          'POST',
          '/shifts/${raced.plan.id}/cancel',
          body: _cancelCommand(2),
          expected: null,
        ),
      ]);
      final amend = results[0], cancel = results[1];
      expect([amend.status, cancel.status]..sort(), [200, 409]);
      final racedState =
          (await f.call('GET', '/shifts/${raced.plan.id}')).body['shift']
              as Map;
      if (amend.status == 200) {
        expect(racedState['version'], 3);
        expect(racedState['status'], 'published');
      } else {
        expect(racedState['status'], 'cancelled');
      }

      final same = await _plan(f);
      await _publishPlan(f, same);
      final sameStart = DateTime.parse(same.input['startsAt'] as String);
      final body = _amendCommand(
        2,
        startsAt: sameStart.add(const Duration(hours: 1)),
        endsAt: sameStart.add(const Duration(hours: 7)),
      );
      final identical = await Future.wait([
        f.call('POST', '/shifts/${same.id}/amend', body: body, expected: null),
        f.call('POST', '/shifts/${same.id}/amend', body: body, expected: null),
      ]);
      expect(identical.map((r) => r.status), everyElement(200));
      expect(
        (await f.call('GET', '/shifts/${same.id}')).body['shift']['version'],
        3,
      );
      expect(await _amendmentAuditCountFor(f, same.id), 1);

      final different = await _plan(f);
      await _publishPlan(f, different);
      final differentStart = DateTime.parse(
        different.input['startsAt'] as String,
      );
      final conflicting = await Future.wait([
        f.call(
          'POST',
          '/shifts/${different.id}/amend',
          body: _amendCommand(
            2,
            startsAt: differentStart.add(const Duration(hours: 1)),
            endsAt: differentStart.add(const Duration(hours: 5)),
          ),
          expected: null,
        ),
        f.call(
          'POST',
          '/shifts/${different.id}/amend',
          body: _amendCommand(
            2,
            startsAt: differentStart.add(const Duration(hours: 2)),
            endsAt: differentStart.add(const Duration(hours: 6)),
          ),
          expected: null,
        ),
      ]);
      expect(conflicting.map((r) => r.status).toList()..sort(), [200, 409]);
      expect(
        (await f.call(
          'GET',
          '/shifts/${different.id}',
        )).body['shift']['version'],
        3,
      );
      expect(await _amendmentAuditCountFor(f, different.id), 1);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'a failing audit append rolls back the amendment atomically',
    () => _withFixture((f) async {
      final p = await _twoTaskPlan(f);
      await _publishPlan(f, p);
      final start = DateTime.parse(p.input['startsAt'] as String),
          newStart = start.add(const Duration(hours: 1)),
          newEnd = start.add(const Duration(hours: 5));
      final before = await _shiftJson(f, p.id);
      final instances = await _instanceState(f, p.id);
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries '
        'FROM "${f.runtimeUser}"',
      );
      await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(2, startsAt: newStart, endsAt: newEnd),
        expected: 503,
      );
      expect(await _shiftJson(f, p.id), before);
      expect(await _instanceState(f, p.id), instances);
      expect(await _amendmentAuditCount(f), 0);
      await f.owner.execute(
        'GRANT INSERT ON "${f.schema}".audit_entries '
        'TO "${f.runtimeUser}"',
      );
      final ok = (await f.call(
        'POST',
        '/shifts/${p.id}/amend',
        body: _amendCommand(2, startsAt: newStart, endsAt: newEnd),
      )).body;
      expect((ok['shift'] as Map)['version'], 3);
      expect(await _amendmentAuditCount(f), 1);
    }),
    skip: _skip,
  );

  test(
    '0012 preserves populated 0011 data and enables bounded amendment',
    () => _withFixture(
      (f) async {
        final pristine = await _plan(f), legacy = await _plan(f);
        await _seedPublishedShift(
          f,
          pristine,
          start: DateTime.now().toUtc().add(const Duration(days: 1)),
        );
        final legacyTask = await _seedPublishedShift(
          f,
          legacy,
          start: DateTime.now().toUtc().add(const Duration(days: 2)),
        );
        final actor = f.adminPrincipal.id;
        await f.owner.execute(
          'UPDATE "${f.schema}".shifts SET status=\'cancelled\',version=3,'
          'cancelled_at=clock_timestamp(),cancelled_by=\'$actor\','
          'cancellation_reason=\'Wrong employee planned\',cancellation_version=2 '
          "WHERE id='${legacy.id}'",
        );
        await f.owner.execute(
          'UPDATE "${f.schema}".task_instances SET status=\'cancelled\',version=2,'
          "cancelled_at=clock_timestamp(),cancelled_by='$actor' "
          "WHERE id='$legacyTask'",
        );
        Future<List<String>> snapshot() async => [
          (await f.owner.execute(
                'SELECT jsonb_agg((to_jsonb(s)-ARRAY[\'amended_at\','
                "'amended_by','amendment_version']) ORDER BY id)::text "
                'FROM "${f.schema}".shifts s',
              )).single.first
              as String,
          (await f.owner.execute(
                'SELECT jsonb_agg((to_jsonb(t)-ARRAY[\'knowledge_article_id\','
                '\'knowledge_revision_id\',\'knowledge_revision_state\',\'planogram_fixture_id\',\'planogram_assignment_id\',\'planogram_revision_id\']) ORDER BY id)::text '
                'FROM "${f.schema}".task_instances t',
              )).single.first
              as String,
          (await f.owner.execute(
                'SELECT jsonb_agg(to_jsonb(a) ORDER BY id)::text '
                'FROM "${f.schema}".audit_entries a',
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
          '0012_published_shift_amendment',
          '0013_article_master',
          '0014_location_assortment',
          '0015_manual_stock',
          '0016_local_planograms',
          '0017_approved_operational_knowledge',
          '0018_task_knowledge_guidance',
          '0019_task_planogram_guidance',
        ]);
        expect(await runner.apply(), isEmpty);
        expect(await snapshot(), before);
        await _expectLegacyGuidanceNull(f);

        final readPristine =
            (await f.call('GET', '/shifts/${pristine.id}')).body['shift']
                as Map;
        expect(readPristine['status'], 'published');
        expect(readPristine['amendmentVersion'], isNull);
        final readLegacy =
            (await f.call('GET', '/shifts/${legacy.id}')).body['shift'] as Map;
        expect(readLegacy['status'], 'cancelled');
        expect(readLegacy['cancellationVersion'], 2);

        final amended = (await f.call(
          'POST',
          '/shifts/${pristine.id}/amend',
          body: _amendCommand(
            2,
            startsAt: DateTime.parse(
              pristine.input['startsAt'] as String,
            ).add(const Duration(hours: 1)),
            endsAt: DateTime.parse(
              pristine.input['endsAt'] as String,
            ).add(const Duration(hours: 1)),
          ),
        )).body;
        expect((amended['shift'] as Map)['version'], 3);
        expect((amended['shift'] as Map)['amendmentVersion'], 2);
        final cancelledAfterAmend = (await f.call(
          'POST',
          '/shifts/${pristine.id}/cancel',
          body: _cancelCommand(3, reason: 'Upgraded cancellation'),
        )).body;
        final finalShift = cancelledAfterAmend['shift'] as Map;
        expect(finalShift['status'], 'cancelled');
        expect(finalShift['version'], 4);
        expect(finalShift['amendmentVersion'], 2);
        expect(finalShift['cancellationVersion'], 3);
      },
      legacy: true,
      legacyBefore: '0012',
    ),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '0012 fails closed and rolls back when published intervals already overlap',
    () => _withFixture(
      (f) async {
        final p = await _plan(f);
        final first = DateTime.now().toUtc().add(const Duration(days: 1));
        await _seedPublishedShift(f, p, start: first);
        await _seedPublishedShift(
          f,
          p,
          start: first.add(const Duration(hours: 2)),
        );
        final runner = MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        );
        await expectLater(runner.apply(), throwsA(isA<PgException>()));
        final ledger = await f.owner.execute(
          'SELECT version FROM "${f.schema}".schema_migrations '
          "WHERE version='0012_published_shift_amendment'",
        );
        expect(ledger, isEmpty);
        final columns = await f.owner.execute(
          'SELECT count(*)::int FROM information_schema.columns '
          "WHERE table_schema='${f.schema}' AND table_name='shifts' "
          "AND column_name IN ('amended_at','amended_by','amendment_version')",
        );
        expect(columns.single.first, 0);
        expect(
          (await f.owner.execute(
            'SELECT count(*)::int FROM "${f.schema}".shifts',
          )).single.first,
          2,
        );
      },
      legacy: true,
      legacyBefore: '0012',
    ),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
