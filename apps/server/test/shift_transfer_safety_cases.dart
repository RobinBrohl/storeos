part of 'shift_integration_test.dart';

// FIFO Company lock queue observed in PostgreSQL, never timer-selected order.
Future<List<_Reply>> _orderedTransfers(
  _Fixture f,
  Future<_Reply> Function() first,
  Future<_Reply> Function() second, {
  Future<void> Function()? beforeRelease,
}) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holding = f.database.runAuthorized(
    f.adminPrincipal,
    'workforce.transfers.manage',
    (tx, actor) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  Future<void> queued(int n) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10)) {
      final rows = await f.owner.execute(
        Sql.named(
          "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
        ),
        parameters: {'key': 'storeos_platform:${f.schema}:$_company'},
      );
      if (rows.single.first == n) return;
    }
    fail('Expected $n observed queued Company writers.');
  }

  try {
    final a = first();
    await queued(1);
    final b = second();
    await queued(2);
    if (beforeRelease != null) await beforeRelease();
    release.complete();
    await holding;
    return await Future.wait([a, b]);
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}

Future<String> _transferHash(_Fixture f) async => jsonEncode({
  for (final table in [
    'shifts',
    'shift_template_selections',
    'task_instances',
    'task_step_results',
    'task_numeric_attempts',
    'task_blockings',
    'task_execution_commands',
    'workforce_shift_transfer_requests',
    'workforce_shift_transfer_commands',
    'task_transfer_links',
    'audit_entries',
  ])
    table: (await f.owner.execute(
      "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
    )).single.toList(),
});

Future<void> _transferOutcome(
  _Fixture f,
  String shift,
  String request, {
  required bool approved,
}) async {
  final schema = '"${f.schema}"';
  expect(
    (await f.owner.execute(
      "SELECT status,replacement_shift_id FROM $schema.workforce_shift_transfer_requests WHERE id='$request'",
    )).single.toList(),
    [approved ? 'approved' : 'accepted', approved ? isNotNull : null],
  );
  expect(
    (await f.owner.execute(
      "SELECT status FROM $schema.shifts WHERE id='$shift'",
    )).single.first,
    approved ? 'cancelled' : 'published',
  );
  expect(
    (await f.owner.execute(
      "SELECT status,version FROM $schema.task_instances WHERE shift_id='$shift'",
    )).single.toList(),
    [approved ? 'cancelled' : 'open', approved ? 2 : 1],
  );
  for (final query in [
    "SELECT count(*) FROM $schema.workforce_shift_transfer_commands WHERE request_id='$request' AND kind='manager_approve'",
    "SELECT count(*) FROM $schema.audit_entries WHERE entity_id='$request' AND action='workforce.transfer.approved'",
    "SELECT count(*) FROM $schema.task_transfer_links WHERE request_id='$request'",
    "SELECT count(*) FROM $schema.shifts WHERE id<>'$shift'",
    "SELECT count(*) FROM $schema.task_instances WHERE shift_id<>'$shift'",
  ]) {
    expect((await f.owner.execute(query)).single.first, approved ? 1 : 0);
  }
  if (approved) {
    expect(
      (await f.owner.execute(
        "SELECT count(*) FROM $schema.task_transfer_links l JOIN $schema.task_instances s ON s.id=l.source_task_id JOIN $schema.task_instances r ON r.id=l.replacement_task_id JOIN $schema.workforce_shift_transfer_requests t ON t.id=l.request_id WHERE t.id='$request' AND s.shift_id=t.source_shift_id AND r.shift_id=t.replacement_shift_id AND s.employee_id=t.source_employee_id AND r.employee_id=t.recipient_employee_id AND s.content::jsonb=r.content::jsonb AND s.template_id=r.template_id AND s.revision_id=r.revision_id AND s.position=r.position AND r.status='open' AND r.version=1",
      )).single.first,
      1,
    );
  }
}

Future<DateTime> _transferDatabaseNow(_Fixture f) async =>
    (await f.owner.execute('SELECT clock_timestamp()')).single.first
        as DateTime;

Future<void> _transferWaitUntil(_Fixture f, DateTime starts) async {
  final deadline = Stopwatch()..start();
  while ((await _transferDatabaseNow(f)).isBefore(starts)) {
    if (deadline.elapsed > const Duration(seconds: 15)) {
      fail('Database clock did not cross the controlled source interval.');
    }
  }
}

void shiftTransferSafetyTests() {
  for (final crossStart in [false, true]) {
    test(
      'P4.11 final approval boundary ${crossStart ? 'cross-start full rollback and UUID reuse' : 'before-start success and historical replay after start'}',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        // The audit barrier is reached only after replacement publication,
        // approval persistence and receipt insertion in the production path.
        final key = 'p411-final:${f.schema}';
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".p411_boundary_barrier() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action=\'workforce.transfer.approved\' THEN PERFORM pg_advisory_xact_lock(hashtext(\'$key\')); END IF; RETURN NEW; END \$\$',
        );
        await f.owner.execute(
          'CREATE TRIGGER p411_boundary_barrier BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p411_boundary_barrier()',
        );
        await f.owner.execute("SELECT pg_advisory_lock(hashtext('$key'))");
        Future<_Reply>? pending;
        try {
          final starts = (await _transferDatabaseNow(
            f,
          )).add(const Duration(seconds: 6));
          await f.call(
            'POST',
            '/shifts/${p.plan.id}/amend',
            body: {
              'expectedVersion': 2,
              'startsAt': starts.toIso8601String(),
              'endsAt': starts.add(const Duration(hours: 1)).toIso8601String(),
            },
          );
          p.proposal['expectedSourceVersion'] = 3;
          await _accepted(f, p);
          final command = _command(2), before = await _transferHash(f);
          expect((await _transferDatabaseNow(f)).isBefore(starts), isTrue);
          pending = f.call(
            'POST',
            '${_manage(id)}/approve',
            body: command,
            expected: null,
          );
          final watch = Stopwatch()..start();
          while (true) {
            final waits = await f.owner.execute(
              "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext('$key')::bigint & 4294967295)::oid AND classid=((hashtext('$key')::bigint >> 32) & 4294967295)::oid",
            );
            if (waits.single.first == 1) break;
            if (watch.elapsed > const Duration(seconds: 10)) {
              fail('Final approval audit barrier was not reached.');
            }
          }
          // This observed wait proves that the early clock check passed and
          // all replacement effects have been attempted before crossing time.
          expect((await _transferDatabaseNow(f)).isBefore(starts), isTrue);
          if (crossStart) await _transferWaitUntil(f, starts);
          await f.owner.execute("SELECT pg_advisory_unlock(hashtext('$key'))");
          final outcome = await pending;
          expect(
            outcome.status,
            crossStart ? 422 : 200,
            reason: jsonEncode(outcome.body),
          );
          if (crossStart) {
            expect(outcome.body['code'], 'shift_not_transferable');
            expect(await _transferHash(f), before);
            await _transferOutcome(f, p.plan.id, id, approved: false);
            // A different valid command can reuse the failed approval UUID.
            await f.call(
              'POST',
              '${_manage(id)}/reject',
              body: {...command, 'reason': 'Source interval started'},
            );
          } else {
            expect(
              DateTime.parse(
                outcome.body['request']['terminalAt'] as String,
              ).isBefore(starts),
              isTrue,
            );
            expect((await _transferDatabaseNow(f)).isBefore(starts), isTrue);
            await _transferOutcome(f, p.plan.id, id, approved: true);
            final committed = await _transferHash(f);
            await _transferWaitUntil(f, starts);
            await f.restart();
            expect(
              (await f.call(
                'POST',
                '${_manage(id)}/approve',
                body: command,
              )).body,
              {...outcome.body, 'replayed': true},
            );
            expect(await _transferHash(f), committed);
          }
        } finally {
          await f.owner.execute("SELECT pg_advisory_unlock_all()");
          if (pending != null) await pending;
        }
      }),
      skip: _skip,
    );
  }
  for (final manager in [false, true]) {
    test(
      'P4.11 ${manager ? 'rejection' : 'withdrawal'} reason controls reject before receipt consumption',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        await _accepted(f, p);
        final route = manager
                ? '${_manage(id)}/reject'
                : '/me/shift-transfers/$id/withdraw',
            command = {..._command(2), 'reason': 'Coverage\u0085changed'},
            before = await _transferHash(f);
        final outcome = await f.call(
          'POST',
          route,
          token: manager ? f.adminToken : p.source,
          body: command,
          expected: 400,
        );
        expect(outcome.body['code'], 'invalid_reason');
        expect(await _transferHash(f), before);
        command['reason'] = 'Coverage changed';
        await f.call(
          'POST',
          route,
          token: manager ? f.adminToken : p.source,
          body: command,
        );
      }),
      skip: _skip,
    );
  }
  test(
    'P4.11 minimal recipient picker filters before fifty and fences Shift cursor',
    () => _withFixture((f) async {
      final p = await _transferPlan(f);
      for (var n = 0; n < 60; n++) {
        await f.call(
          'POST',
          '/employees',
          body: {
            'id':
                '10000000-0000-4000-8000-${(n + 1).toRadixString(16).padLeft(12, '0')}',
            'displayName': 'Unlinked $n',
            'locationId': _home,
          },
          expected: 201,
        );
      }
      for (var n = 0; n < 51; n++) {
        final person = EmployeeDto.fromJson(
          (await f.call(
            'POST',
            '/employees',
            body: {
              'id':
                  '20000000-0000-4000-8000-${(n + 1).toRadixString(16).padLeft(12, '0')}',
              'displayName': 'Candidate $n',
              'locationId': _home,
            },
            expected: 201,
          )).body,
        );
        await _linkedAccount(f, person, 'picker_$n');
      }
      final route = '/employee-home/shifts/${p.plan.id}/transfer-recipients',
          first = (await f.call('GET', route, token: p.source)).body;
      expect(first['items'], hasLength(50));
      final cursor = first['nextCursor'] as String,
          second = (await f.call(
            'GET',
            '$route?after=${Uri.encodeQueryComponent(cursor)}',
            token: p.source,
          )).body;
      expect(second['items'], hasLength(2));
      final ids = <Object?>{
        for (final row in [
          ...(first['items'] as List),
          ...(second['items'] as List),
        ])
          row['employeeId'],
      };
      expect(ids, hasLength(52));
      expect(ids, contains(p.person.id));
      expect(ids, isNot(contains(p.plan.employee.id)));
      for (final row in [
        ...(first['items'] as List),
        ...(second['items'] as List),
      ]) {
        expect((row as Map).keys.toSet(), {'employeeId', 'displayName'});
        expect(row['displayName'], isNot(startsWith('Unlinked')));
      }
      final starts = DateTime.parse(
        p.plan.input['startsAt'] as String,
      ).add(const Duration(minutes: 1));
      await f.call(
        'POST',
        '/shifts/${p.plan.id}/amend',
        body: {
          'expectedVersion': 2,
          'startsAt': starts.toIso8601String(),
          'endsAt': p.plan.input['endsAt'],
        },
      );
      await f.call(
        'GET',
        '$route?after=${Uri.encodeQueryComponent(cursor)}',
        token: p.source,
        expected: 400,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  for (final kind in shiftTransferKinds) {
    test(
      'P4.11 $kind durable replay after restart, changed UUID payload and nonparticipant denial',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        final accepted = {
          'recipient_withdraw',
          'manager_approve',
        }.contains(kind);
        if (kind != 'propose') {
          if (accepted) {
            await _accepted(f, p);
          } else {
            await _proposed(f, p);
          }
        }
        final version = accepted ? 2 : 1,
            body = kind == 'propose'
                ? p.proposal
                : {
                    ..._command(version),
                    if ({
                      'source_withdraw',
                      'recipient_withdraw',
                      'manager_reject',
                    }.contains(kind))
                      'reason': 'Coverage changed',
                  },
            token = kind == 'propose' || kind == 'source_withdraw'
                ? p.source
                : kind.startsWith('manager_')
                ? f.adminToken!
                : p.recipient,
            action = switch (kind) {
              'source_withdraw' || 'recipient_withdraw' => 'withdraw',
              'manager_reject' => 'reject',
              'manager_approve' => 'approve',
              _ => kind,
            },
            route = kind == 'propose'
                ? '/me/shift-transfers'
                : kind.startsWith('manager_')
                ? '${_manage(id)}/$action'
                : '/me/shift-transfers/$id/$action',
            status = kind == 'propose' ? 201 : 200;
        final committed = (await f.call(
              'POST',
              route,
              token: token,
              body: body,
              expected: status,
            )).body,
            before = await _transferHash(f);
        await f.restart();
        final replay = (await f.call(
          'POST',
          route,
          token: token,
          body: body,
          expected: status,
        )).body;
        expect(replay, {...committed, 'replayed': true});
        expect(await _transferHash(f), before);
        await f.call(
          'POST',
          route,
          token: token,
          body: {
            ...body,
            kind == 'propose' ? 'expectedSourceVersion' : 'expectedVersion':
                version + 2,
          },
          expected: 409,
        );
        final outsider = await _linkedAccount(
          f,
          await f.employee('Replay outsider'),
          'receipt_outsider',
        );
        await f.call(
          'POST',
          route,
          token: outsider,
          body: body,
          expected: kind.startsWith('manager_')
              ? 403
              : kind == 'propose'
              ? 404
              : 404,
        );
        if (kind.startsWith('manager_')) {
          await f.call(
            'POST',
            '/locations/$_other/shift-transfers/$id/$action',
            body: body,
            expected: 403,
          );
        }
      }),
      skip: _skip,
    );
  }
  test(
    'P4.11 history filters before keyset limit and scoped cursor rejects reuse',
    () => _withFixture((f) async {
      final p = await _transferPlan(f);
      for (var n = 0; n < 52; n++) {
        final id =
            '40000000-0000-4000-8000-${(n + 1).toRadixString(16).padLeft(12, '0')}';
        await f.call(
          'POST',
          '/me/shift-transfers',
          token: p.source,
          body: {...p.proposal, 'requestId': id, 'operationId': newUuid()},
          expected: 201,
        );
        await f.call(
          'POST',
          '/me/shift-transfers/$id/decline',
          token: p.recipient,
          body: _command(1),
        );
      }
      const query = '?direction=outgoing&status=declined';
      final first = (await f.call(
        'GET',
        '/me/shift-transfers$query',
        token: p.source,
      )).body;
      expect(first['items'], hasLength(50));
      final cursor = first['nextCursor'] as String;
      final second = (await f.call(
        'GET',
        '/me/shift-transfers$query&after=${Uri.encodeQueryComponent(cursor)}',
        token: p.source,
      )).body;
      expect(second['items'], hasLength(2));
      expect(second['nextCursor'], isNull);
      expect(<Object?>{
        ...(first['items'] as List).cast<Map>().map((r) => r['id']),
        ...(second['items'] as List).cast<Map>().map((r) => r['id']),
      }, hasLength(52));
      await f.call(
        'GET',
        '/me/shift-transfers$query&after=${Uri.encodeQueryComponent(cursor)}',
        token: p.recipient,
        expected: 400,
      );
      await f.call(
        'GET',
        '/me/shift-transfers?direction=incoming&status=declined&after=${Uri.encodeQueryComponent(cursor)}',
        token: p.source,
        expected: 400,
      );
      await f.call(
        'GET',
        '/locations/$_home/shift-transfers?status=declined&after=${Uri.encodeQueryComponent(cursor)}',
        expected: 400,
      );
      final scopes = jsonDecode(utf8.decode(base64Url.decode(cursor))) as List;
      for (final position in [1, 2]) {
        final changed = [...scopes]..[position] = newUuid();
        final bad = base64Url.encode(utf8.encode(jsonEncode(changed)));
        await f.call(
          'GET',
          '/me/shift-transfers$query&after=${Uri.encodeQueryComponent(bad)}',
          token: p.source,
          expected: 400,
        );
      }
      final incoming = (await f.call(
        'GET',
        '/me/shift-transfers?direction=incoming&status=proposed',
        token: p.source,
      )).body;
      expect(incoming['items'], isEmpty);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'P4.11 receipt bindings, reauthorization and failed UUID reuse',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      final proposed = await _proposed(f, p);
      expect((await _proposed(f, p)), {...proposed, 'replayed': true});
      for (final change in [
        {'requestId': newUuid()},
        {'expectedSourceVersion': 3},
        {'recipientEmployeeId': newUuid()},
      ]) {
        expect(
          (await f.call(
            'POST',
            '/me/shift-transfers',
            token: p.source,
            body: {...p.proposal, ...change},
            expected: 409,
          )).body['code'],
          'operation_conflict',
        );
      }
      final op = p.proposal['operationId'];
      expect(
        (await f.call(
          'POST',
          '/me/shift-transfers/$id/decline',
          token: p.recipient,
          body: _command(1, op as String),
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      final failOp = newUuid();
      await f.call(
        'POST',
        '/me/shift-transfers/$id/accept',
        token: p.recipient,
        body: _command(2, failOp),
        expected: 409,
      );
      await f.call(
        'POST',
        '/me/shift-transfers/$id/accept',
        token: p.recipient,
        body: _command(1, failOp),
      );
      final users = (await f.call('GET', '/users')).body['users'] as List,
          source = users.cast<Map>().singleWhere(
            (u) => u['username'] == 'transfer_source',
          );
      await f.call(
        'POST',
        '/users/${source['id']}',
        body: {
          'expectedVersion': source['version'],
          'role': 'viewer',
          'isActive': true,
        },
      );
      await f.call(
        'POST',
        '/me/shift-transfers',
        token: p.source,
        body: p.proposal,
        expected: 401,
      );
      final token = await f.login('transfer_source');
      await f.call(
        'POST',
        '/me/shift-transfers',
        token: token,
        body: p.proposal,
        expected: 403,
      );
    }),
    skip: _skip,
  );
  for (final executionFirst in [true, false]) {
    test(
      'P4.11 observed source execution ${executionFirst ? 'before' : 'after'} approval at database clock boundary',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        final now =
            (await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime;
        final starts = now.add(Duration(seconds: executionFirst ? 3 : 30));
        await f.call(
          'POST',
          '/shifts/${p.plan.id}/amend',
          body: {
            'expectedVersion': 2,
            'startsAt': starts.toIso8601String(),
            'endsAt': starts.add(const Duration(hours: 1)).toIso8601String(),
          },
        );
        p.proposal['expectedSourceVersion'] = 3;
        await _accepted(f, p);
        final detail = (await f.call('GET', '/shifts/${p.plan.id}')).body,
            task = detail['tasks'][0]['id'];
        Future<_Reply> execute() => f.call(
          'POST',
          '/employee-home/shifts/${p.plan.id}/tasks/$task/start',
          token: p.source,
          body: _command(1),
          expected: null,
        );
        Future<_Reply> approve() => f.call(
          'POST',
          '${_manage(id)}/approve',
          body: _command(2),
          expected: null,
        );
        final results = await _orderedTransfers(
          f,
          executionFirst ? execute : approve,
          executionFirst ? approve : execute,
          beforeRelease: executionFirst
              ? () async {
                  while (((await f.owner.execute(
                            'SELECT clock_timestamp()',
                          )).single.first
                          as DateTime)
                      .isBefore(starts)) {}
                }
              : null,
        );
        expect(results.first.status, 200);
        expect(results.last.status, executionFirst ? 422 : 404);
        if (!executionFirst) {
          expect((await _transferDatabaseNow(f)).isBefore(starts), isTrue);
          expect(
            DateTime.parse(
              results.first.body['request']['terminalAt'] as String,
            ).isBefore(starts),
            isTrue,
          );
          await _transferOutcome(f, p.plan.id, id, approved: true);
        } else {
          expect((await f.call('GET', _manage(id))).body['status'], 'accepted');
          expect(
            (await f.call(
              'GET',
              '/shifts/${p.plan.id}',
            )).body['shift']['status'],
            'published',
          );
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".workforce_shift_transfer_commands WHERE kind=\'manager_approve\'',
            )).single.first,
            0,
          );
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'workforce.transfer.approved\'',
            )).single.first,
            0,
          );
        }
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".task_transfer_links',
          )).single.first,
          executionFirst ? 0 : 1,
        );
      }),
      skip: _skip,
    );
  }
  for (final change in [
    'amend',
    'cancel',
    'overlap',
    'unlink',
    'recipient_deactivate',
    'source_unlink',
    'source_deactivate',
    'source_account_deactivate',
    'source_withdraw',
    'recipient_withdraw',
    'reject',
  ]) {
    for (final changeFirst in [true, false]) {
      test(
        'P4.11 observed serialized $change ${changeFirst ? 'before' : 'after'} approval',
        () => _withFixture((f) async {
          final p = await _transferPlan(f),
              id = p.proposal['requestId'] as String;
          await _accepted(f, p);
          String route;
          String? token;
          Map<String, dynamic> body;
          if (change == 'amend') {
            final start = DateTime.parse(
              p.plan.input['startsAt'] as String,
            ).add(const Duration(hours: 1));
            route = '/shifts/${p.plan.id}/amend';
            body = {
              'expectedVersion': 2,
              'startsAt': start.toIso8601String(),
              'endsAt': start.add(const Duration(hours: 2)).toIso8601String(),
            };
          } else if (change == 'cancel') {
            route = '/shifts/${p.plan.id}/cancel';
            body = {'expectedVersion': 2, 'reason': 'Cancel source'};
          } else if (change == 'overlap') {
            final other = {
              ...p.plan.input,
              'id': newUuid(),
              'employeeId': p.person.id,
            };
            await f.call('POST', '/shifts', body: other, expected: 201);
            route = '/shifts/${other['id']}/publish';
            body = {'expectedVersion': 1};
          } else if (change == 'unlink' || change == 'source_unlink') {
            final link =
                (await f.call(
                      'GET',
                      '/employees/${change == 'source_unlink' ? p.plan.employee.id : p.person.id}/account-link',
                    )).body['link']
                    as Map;
            route = '/employee-links/${link['id']}/revoke';
            body = {'expectedVersion': link['version']};
          } else if (change == 'recipient_deactivate' ||
              change == 'source_deactivate') {
            route =
                '/employees/${change == 'source_deactivate' ? p.plan.employee.id : p.person.id}/deactivate';
            body = {'expectedVersion': 1};
          } else if (change == 'source_account_deactivate') {
            final users = (await f.call('GET', '/users')).body['users'] as List;
            final user = users.cast<Map>().singleWhere(
              (u) => u['username'] == 'transfer_source',
            );
            route = '/users/${user['id']}';
            body = {
              'expectedVersion': user['version'],
              'role': 'employee',
              'isActive': false,
            };
          } else {
            route = change == 'reject'
                ? '${_manage(id)}/reject'
                : '/me/shift-transfers/$id/withdraw';
            token = change == 'source_withdraw'
                ? p.source
                : change == 'recipient_withdraw'
                ? p.recipient
                : null;
            body = {
              'operationId': newUuid(),
              'expectedVersion': 2,
              'reason': 'Explicit terminal decision',
            };
          }
          Future<_Reply> mutation() =>
              f.call('POST', route, token: token, body: body, expected: null);
          Future<_Reply> approve() => f.call(
            'POST',
            '${_manage(id)}/approve',
            body: _command(2),
            expected: null,
          );
          final results = await _orderedTransfers(
            f,
            changeFirst ? mutation : approve,
            changeFirst ? approve : mutation,
          );
          expect(
            results.first.status,
            200,
            reason: jsonEncode(results.first.body),
          );
          final approval = results[changeFirst ? 1 : 0];
          expect(
            approval.status,
            changeFirst ? anyOf(409, 422) : 200,
            reason: jsonEncode(approval.body),
          );
          if (!changeFirst &&
              {
                'amend',
                'cancel',
                'overlap',
                'source_withdraw',
                'recipient_withdraw',
                'reject',
              }.contains(change)) {
            expect(results.last.status, anyOf(409, 422));
          }
          final count = (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".task_transfer_links',
          )).single.first;
          expect(count, changeFirst ? 0 : 1);
          if ({
            'unlink',
            'recipient_deactivate',
            'source_unlink',
            'source_deactivate',
            'source_account_deactivate',
          }.contains(change)) {
            expect(results[changeFirst ? 0 : 1].status, 200);
            if (changeFirst) {
              expect(
                approval.body['code'],
                change.startsWith('source_')
                    ? 'employee_unavailable'
                    : 'recipient_unavailable',
              );
            }
            await _transferOutcome(f, p.plan.id, id, approved: !changeFirst);
          }
        }),
        skip: _skip,
      );
    }
  }

  for (final source in [true, false]) {
    for (final replacementAccount in [true, false]) {
      for (final linkFirst in [true, false]) {
        test(
          'P4.11 observed ${source ? 'source' : 'recipient'} ${replacementAccount ? 'replacement-account link' : 'same-account relink'} ${linkFirst ? 'before' : 'after'} approval never revives L1 consent',
          () => _withFixture((f) async {
            final p = await _transferPlan(f),
                id = p.proposal['requestId'] as String;
            await _accepted(f, p);
            final person = source ? p.plan.employee.id : p.person.id;
            final old =
                (await f.call(
                      'GET',
                      '/employees/$person/account-link',
                    )).body['link']
                    as Map;
            // There is no atomic replace-link command. Creation requires an
            // already revoked L1; approval must reject in either creation order.
            await f.call(
              'POST',
              '/employee-links/${old['id']}/revoke',
              body: {'expectedVersion': old['version']},
            );
            final account = replacementAccount
                ? await f.account('identity_replacement')
                : null;
            final newLink = newUuid();
            Future<_Reply> relink() => f.call(
              'POST',
              '/employees/$person/account-link',
              body: {
                'id': newLink,
                'accountId': account?.id ?? old['accountId'],
                'expectedEmployeeVersion': 1,
                'expectedAccountVersion': 1,
              },
              expected: null,
            );
            Future<_Reply> approve() => f.call(
              'POST',
              '${_manage(id)}/approve',
              body: _command(2),
              expected: null,
            );
            final results = await _orderedTransfers(
              f,
              linkFirst ? relink : approve,
              linkFirst ? approve : relink,
            );
            expect(results[linkFirst ? 0 : 1].status, 201);
            final approval = results[linkFirst ? 1 : 0];
            expect(approval.status, 422);
            expect(
              approval.body['code'],
              source ? 'employee_unavailable' : 'recipient_unavailable',
            );
            await _transferOutcome(f, p.plan.id, id, approved: false);
            expect(
              (await f.call(
                'GET',
                '/employees/$person/account-link',
              )).body['link']['id'],
              newLink,
            );
            expect(
              (await f.owner.execute(
                'SELECT ${source ? 'source_link_id' : 'recipient_link_id'} FROM "${f.schema}".workforce_shift_transfer_requests',
              )).single.first,
              old['id'],
            );
            if (!source) {
              final token = await f.login(
                account?.username ?? 'transfer_recipient',
              );
              await f.call(
                'POST',
                '/me/shift-transfers/$id/accept',
                token: token,
                body: _command(1),
                expected: 404,
              );
            }
          }),
          skip: _skip,
        );
      }
    }
  }

  test(
    'P4.11 participant privacy, current auth, independent manager and configured Location',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      final outsider = await _linkedAccount(
        f,
        await f.employee('Unrelated'),
        'transfer_outsider',
      );
      for (final token in [outsider, p.source]) {
        await f.call(
          'POST',
          '/me/shift-transfers/$id/accept',
          token: token,
          body: _command(2),
          expected: 404,
        );
      }
      await f.call(
        'GET',
        '/me/shift-transfers/$id',
        token: outsider,
        expected: 404,
      );
      for (final role in ['viewer', 'auditor']) {
        final a = await f.account('transfer_$role', role: role),
            token = await f.login(a.username);
        await f.call('GET', '/me/shift-transfers', token: token, expected: 403);
        await f.call('GET', _manage(id), token: token, expected: 403);
      }
      final remote = await f.account(
        'transfer_remote',
        role: 'admin',
        location: _other,
      );
      await f.call(
        'GET',
        _manage(id),
        token: await f.login(remote.username),
        expected: 403,
      );
      await f.call(
        'GET',
        '/locations/$_other/shift-transfers/$id',
        expected: 403,
      );
      for (final name in ['transfer_source', 'transfer_recipient']) {
        final user = (await f.call('GET', '/users')).body['users'] as List;
        final account = user.cast<Map>().singleWhere(
          (u) => u['username'] == name,
        );
        await f.call(
          'POST',
          '/users/${account['id']}',
          body: {
            'expectedVersion': account['version'],
            'role': 'admin',
            'isActive': true,
          },
        );
        final newToken = await f.login(name);
        final outcome = await f.call(
          'POST',
          '${_manage(id)}/approve',
          token: newToken,
          body: _command(2),
          expected: 403,
        );
        expect(outcome.body['code'], 'forbidden');
      }
      expect((await f.call('GET', _manage(id))).body['status'], 'accepted');
    }),
    skip: _skip,
  );

  test(
    'P4.11 link replacement never revives accepted consent',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      final link =
          (await f.call(
                'GET',
                '/employees/${p.person.id}/account-link',
              )).body['link']
              as Map;
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      final account = await f.account('replacement_recipient');
      await f.call(
        'POST',
        '/employees/${p.person.id}/account-link',
        body: {
          'id': newUuid(),
          'accountId': account.id,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
        expected: 201,
      );
      final fresh = await f.login(account.username);
      await f.call(
        'POST',
        '/me/shift-transfers/$id/accept',
        token: fresh,
        body: _command(1),
        expected: 404,
      );
      expect(
        (await f.call(
          'POST',
          '${_manage(id)}/approve',
          body: _command(2),
          expected: 422,
        )).body['code'],
        'recipient_unavailable',
      );
      await f.call(
        'POST',
        '${_manage(id)}/reject',
        body: {..._command(2), 'reason': 'Identity basis changed'},
      );
      await f.call(
        'POST',
        '/me/shift-transfers',
        token: p.source,
        body: {...p.proposal, 'requestId': newUuid(), 'operationId': newUuid()},
        expected: 201,
      );
    }),
    skip: _skip,
  );

  test(
    'P4.11 every write rejects duplicate decoded names, unknown fields and oversized body',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      for (final route in [
        '/me/shift-transfers',
        '/me/shift-transfers/$id/accept',
        '/me/shift-transfers/$id/decline',
        '/me/shift-transfers/$id/withdraw',
        '${_manage(id)}/approve',
        '${_manage(id)}/reject',
      ]) {
        for (final raw in [
          r'{"operationId":"a","operationId":"b"}',
          r'{"operationId":"a","operat\u0069onId":"b"}',
          jsonEncode({'unexpected': true}),
          '{"operationId":',
          jsonEncode({'operationId': 'not-a-uuid', 'expectedVersion': 2}),
          jsonEncode({'reason': 'x' * 8192}),
        ]) {
          final request = await f.client.openUrl(
            'POST',
            Uri.parse('${f.base}/api/v1/platform$route'),
          );
          request.headers.set(
            'authorization',
            'Bearer ${route.contains('/locations/')
                ? f.adminToken
                : route.endsWith('/accept') || route.endsWith('/decline')
                ? p.recipient
                : p.source}',
          );
          request.headers.contentType = ContentType.json;
          request.contentLength = utf8.encode(raw).length;
          request.add(utf8.encode(raw));
          final response = await request.close();
          await response.drain<void>();
          expect(
            response.statusCode,
            raw.length > 8192 ? 413 : 400,
            reason: route,
          );
        }
      }
    }),
    skip: _skip,
  );

  for (final stage in [
    'source_cancel',
    'replacement_shift',
    'replacement_task',
    'task_link',
    'receipt',
    'transfer_audit',
  ]) {
    test(
      'P4.11 injected $stage rollback matches full pre-command evidence',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        await _accepted(f, p);
        final before = await _transferHash(f);
        final table = switch (stage) {
          'source_cancel' => 'shifts',
          'replacement_shift' => 'shifts',
          'replacement_task' => 'task_instances',
          'task_link' => 'task_transfer_links',
          'receipt' => 'workforce_shift_transfer_commands',
          _ => 'audit_entries',
        };
        final condition = switch (stage) {
          'source_cancel' => "NEW.status='cancelled'",
          'transfer_audit' => "NEW.action='workforce.transfer.approved'",
          _ => 'true',
        };
        final event = stage == 'source_cancel' ? 'UPDATE' : 'INSERT';
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".p411_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF $condition THEN RAISE EXCEPTION \'Injected P4.11 stage\' USING ERRCODE=\'23514\'; END IF; RETURN NEW; END \$\$',
        );
        await f.owner.execute(
          'CREATE TRIGGER p411_fault BEFORE $event ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".p411_fault()',
        );
        final command = _command(2);
        await f.call(
          'POST',
          '${_manage(id)}/approve',
          body: command,
          expected: 500,
        );
        expect(await _transferHash(f), before);
        await f.owner.execute(
          'DROP TRIGGER p411_fault ON "${f.schema}".$table',
        );
        await f.owner.execute('DROP FUNCTION "${f.schema}".p411_fault()');
        await f.call('POST', '${_manage(id)}/approve', body: command);
      }),
      skip: _skip,
    );
  }

  test(
    'P4.11 runtime grants and append-only terminal, receipt and lineage guards',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      await f.call('POST', '${_manage(id)}/approve', body: _command(2));
      final before = await _transferHash(f);
      for (final mutation in [
        'source_shift_id',
        'source_employee_id',
        'recipient_employee_id',
        'starts_at',
        'ends_at',
        'source_version',
        'accepted_by',
        'accepted_at',
        'status',
        'replacement_shift_id',
      ]) {
        final value = switch (mutation) {
          'starts_at' || 'ends_at' || 'accepted_at' => "clock_timestamp()",
          'source_version' => 'source_version+1',
          'status' => "'proposed'",
          _ => "'${newUuid()}'::uuid",
        };
        await expectLater(
          f.owner.runTx((tx) async {
            await tx.execute('SET LOCAL ROLE "${f.runtimeUser}"');
            await tx.execute(
              'UPDATE "${f.schema}".workforce_shift_transfer_requests SET $mutation=$value',
            );
          }),
          throwsA(isA<ServerException>()),
        );
      }
      for (final table in [
        'workforce_shift_transfer_requests',
        'workforce_shift_transfer_commands',
        'task_transfer_links',
      ]) {
        for (final action in ['DELETE', 'TRUNCATE']) {
          expect(
            (await f.owner.execute(
              "SELECT has_table_privilege('${f.runtimeUser}','\"${f.schema}\".$table','$action')",
            )).single.first,
            false,
          );
          await expectLater(
            f.owner.runTx((tx) async {
              await tx.execute('SET LOCAL ROLE "${f.runtimeUser}"');
              await tx.execute(
                action == 'DELETE'
                    ? 'DELETE FROM "${f.schema}".$table'
                    : 'TRUNCATE "${f.schema}".$table',
              );
            }),
            throwsA(isA<ServerException>()),
          );
        }
        await expectLater(
          f.owner.execute('DELETE FROM "${f.schema}".$table'),
          throwsA(isA<ServerException>()),
        );
      }
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".workforce_shift_transfer_requests SET version=version+1',
        ),
        throwsA(isA<ServerException>()),
      );
      for (final table in [
        'workforce_shift_transfer_commands',
        'task_transfer_links',
      ]) {
        await expectLater(
          f.owner.runTx((tx) async {
            await tx.execute('SET LOCAL ROLE "${f.runtimeUser}"');
            await tx.execute(
              'UPDATE "${f.schema}".$table SET company_id=company_id',
            );
          }),
          throwsA(isA<ServerException>()),
        );
      }
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".workforce_shift_transfer_commands SET committed_at=clock_timestamp()',
        ),
        throwsA(isA<ServerException>()),
      );
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".task_transfer_links SET position=9',
        ),
        throwsA(isA<ServerException>()),
      );
      expect(await _transferHash(f), before);
    }),
    skip: _skip,
  );
}
