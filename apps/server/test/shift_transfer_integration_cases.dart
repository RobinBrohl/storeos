part of 'shift_integration_test.dart';

Future<
  ({
    _Plan plan,
    String source,
    String recipient,
    EmployeeDto person,
    Map<String, dynamic> proposal,
  })
>
_transferPlan(_Fixture f, {int tasks = 1}) async {
  final p = await _plan(f, numeric: true, steps: 2),
      source = await _linkedAccount(f, p.employee, 'transfer_source');
  final person = await f.employee('Transfer recipient'),
      recipient = await _linkedAccount(f, person, 'transfer_recipient');
  for (var n = 1; n < tasks; n++) {
    final template = _input();
    await f.call('POST', '/task-templates', body: template, expected: 201);
    await f.call(
      'POST',
      '/task-templates/${template['id']}/revisions/${template['revisionId']}/publish',
      body: {'expectedVersion': 1},
    );
    (p.input['selections'] as List).add({
      'templateId': template['id'],
      'revisionId': template['revisionId'],
    });
  }
  await f.call('POST', '/shifts', body: p.input, expected: 201);
  await f.call('POST', '/shifts/${p.id}/publish', body: {'expectedVersion': 1});
  return (
    plan: p,
    source: source,
    recipient: recipient,
    person: person,
    proposal: {
      'requestId': newUuid(),
      'operationId': newUuid(),
      'sourceShiftId': p.id,
      'expectedSourceVersion': 2,
      'recipientEmployeeId': person.id,
    },
  );
}

Future<Map<String, dynamic>> _proposed(_Fixture f, dynamic p) async =>
    (await f.call(
      'POST',
      '/me/shift-transfers',
      token: p.source as String,
      body: p.proposal as Map<String, dynamic>,
      expected: 201,
    )).body;
Future<Map<String, dynamic>> _accepted(_Fixture f, dynamic p) async {
  await _proposed(f, p);
  return (await f.call(
    'POST',
    '/me/shift-transfers/${p.proposal['requestId']}/accept',
    token: p.recipient as String,
    body: {'operationId': newUuid(), 'expectedVersion': 1},
  )).body;
}

String _manage(String id) => '/locations/$_home/shift-transfers/$id';
void shiftTransferTests() {
  test(
    'P4.11 complete ten-Task replacement and one-to-one ordered lineage',
    () => _withFixture((f) async {
      final p = await _transferPlan(f, tasks: 10),
          id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      final result = (await f.call(
        'POST',
        '${_manage(id)}/approve',
        body: _command(2),
      )).body;
      expect(result['request']['tasks'], hasLength(10));
      expect(result['request']['taskLinks'], hasLength(10));
      final links = result['request']['taskLinks'] as List;
      expect(links.map((l) => l['sourceTaskId']).toSet(), hasLength(10));
      expect(links.map((l) => l['replacementTaskId']).toSet(), hasLength(10));
      for (var n = 0; n < 10; n++) {
        expect(links[n]['position'], n);
      }
    }),
    skip: _skip,
  );
  test(
    'P4.11 exact approval, ordinary ownership, retained history and restart replay',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      final picker = (await f.call(
        'GET',
        '/employee-home/shifts/${p.plan.id}/transfer-recipients',
        token: p.source,
      )).body;
      expect(
        (picker['items'] as List).map((r) => r['employeeId']),
        contains(p.person.id),
      );
      expect(
        (picker['items'] as List).map((r) => r['employeeId']),
        isNot(contains(p.plan.employee.id)),
      );
      final original = (await f.call('GET', '/shifts/${p.plan.id}')).body;
      final proposed = await _proposed(f, p);
      expect(proposed['request']['status'], 'proposed');
      expect((await f.call('GET', '/shifts/${p.plan.id}')).body, original);
      final accept = {'operationId': newUuid(), 'expectedVersion': 1};
      final consent = (await f.call(
        'POST',
        '/me/shift-transfers/$id/accept',
        token: p.recipient,
        body: accept,
      )).body;
      expect(consent['request']['status'], 'accepted');
      await f.call(
        'GET',
        '/employee-home/shifts/${p.plan.id}',
        token: p.recipient,
        expected: 404,
      );
      expect((await f.call('GET', '/shifts/${p.plan.id}')).body, original);
      final approval = {'operationId': newUuid(), 'expectedVersion': 2};
      final result = (await f.call(
        'POST',
        '${_manage(id)}/approve',
        body: approval,
      )).body;
      final b = result['request']['replacementShiftId'] as String;
      final cancelled = (await f.call('GET', '/shifts/${p.plan.id}')).body;
      final replacement = (await f.call('GET', '/shifts/$b')).body;
      expect(cancelled['shift']['employeeId'], p.plan.employee.id);
      expect(cancelled['shift']['status'], 'cancelled');
      expect(
        (cancelled['tasks'] as List).every((t) => t['status'] == 'cancelled'),
        true,
      );
      expect(replacement['shift']['employeeId'], p.person.id);
      expect(replacement['shift']['startsAt'], original['shift']['startsAt']);
      expect(replacement['shift']['endsAt'], original['shift']['endsAt']);
      expect(
        replacement['shift']['selections'],
        original['shift']['selections'],
      );
      expect(
        result['request']['taskLinks'],
        hasLength((original['tasks'] as List).length),
      );
      expect(
        result['request']['taskLinks'][0]['sourceTaskId'],
        original['tasks'][0]['id'],
      );
      expect(
        result['request']['taskLinks'][0]['replacementTaskId'],
        replacement['tasks'][0]['id'],
      );
      await f.call(
        'GET',
        '/employee-home/shifts/${p.plan.id}',
        token: p.source,
        expected: 404,
      );
      await f.call('GET', '/employee-home/shifts/$b', token: p.recipient);
      await f.call(
        'GET',
        '/employee-home/shifts/$b',
        token: p.source,
        expected: 404,
      );
      final history = (await f.call(
        'GET',
        '/me/shift-transfers/$id',
        token: p.source,
      )).body;
      for (final sensitive in [
        'confirmedSteps',
        'value',
        'results',
        'content',
        'startedAt',
      ]) {
        expect(jsonEncode(history), isNot(contains('"$sensitive"')));
      }
      final audits = (await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".audit_entries',
      )).single.first;
      await f.restart();
      final replay = (await f.call(
        'POST',
        '${_manage(id)}/approve',
        body: approval,
      )).body;
      expect(replay, {...result, 'replayed': true});
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries',
        )).single.first,
        audits,
      );
      await f.call(
        'POST',
        '${_manage(id)}/approve',
        body: {...approval, 'expectedVersion': 3},
        expected: 409,
      );
      final acceptReplay = (await f.call(
        'POST',
        '/me/shift-transfers/$id/accept',
        token: p.recipient,
        body: accept,
      )).body;
      expect(acceptReplay, {...consent, 'replayed': true});
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".shifts',
        )).single.first,
        2,
      );
    }),
    skip: _skip,
  );

  for (final terminal in [
    'decline',
    'source_withdraw',
    'recipient_withdraw',
    'manager_reject',
  ]) {
    test(
      'P4.11 $terminal retains consent, terminal evidence and exact replay',
      () => _withFixture((f) async {
        final p = await _transferPlan(f),
            id = p.proposal['requestId'] as String;
        if (terminal == 'recipient_withdraw') {
          await _accepted(f, p);
        } else {
          await _proposed(f, p);
        }
        final route = terminal == 'manager_reject'
            ? '${_manage(id)}/reject'
            : '/me/shift-transfers/$id/${terminal == 'decline' ? 'decline' : 'withdraw'}';
        final token = terminal == 'source_withdraw'
            ? p.source
            : terminal == 'manager_reject'
            ? f.adminToken
            : p.recipient;
        final command = {
          'operationId': newUuid(),
          'expectedVersion': terminal == 'recipient_withdraw' ? 2 : 1,
          if (terminal != 'decline') 'reason': 'Coverage changed 😀',
        };
        final result = (await f.call(
          'POST',
          route,
          token: token,
          body: command,
        )).body;
        expect(
          result['request']['status'],
          terminal == 'decline'
              ? 'declined'
              : terminal == 'manager_reject'
              ? 'rejected'
              : 'withdrawn',
        );
        expect(
          result['request']['acceptedAt'],
          terminal == 'recipient_withdraw' ? isNotNull : isNull,
        );
        expect(
          (await f.call('POST', route, token: token, body: command)).body,
          {...result, 'replayed': true},
        );
        await f.call(
          'POST',
          route,
          token: token,
          body: {...command, 'operationId': newUuid()},
          expected: 409,
        );
        expect(
          (await f.call('GET', '/shifts/${p.plan.id}')).body['shift']['status'],
          'published',
        );
      }),
      skip: _skip,
    );
  }

  test(
    'P4.11 source amendment and recipient overlap refuse approval without effects',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      final other = {
        ...p.plan.input,
        'id': newUuid(),
        'employeeId': p.person.id,
      };
      await f.call('POST', '/shifts', body: other, expected: 201);
      await f.call(
        'POST',
        '/shifts/${other['id']}/publish',
        body: {'expectedVersion': 1},
      );
      final approval = {'operationId': newUuid(), 'expectedVersion': 2};
      final denied = await f.call(
        'POST',
        '${_manage(id)}/approve',
        body: approval,
        expected: 409,
      );
      expect(denied.body['code'], 'shift_overlap');
      expect(
        (await f.call('GET', '/shifts/${p.plan.id}')).body['shift']['status'],
        'published',
      );
      await f.call(
        'POST',
        '/shifts/${other['id']}/cancel',
        body: {'expectedVersion': 2, 'reason': 'Remove conflict'},
      );
      final start = DateTime.parse(
        p.plan.input['startsAt'] as String,
      ).add(const Duration(hours: 1));
      await f.call(
        'POST',
        '/shifts/${p.plan.id}/amend',
        body: {
          'expectedVersion': 2,
          'startsAt': start.toIso8601String(),
          'endsAt': start.add(const Duration(hours: 2)).toIso8601String(),
        },
      );
      expect(
        (await f.call(
          'POST',
          '${_manage(id)}/approve',
          body: approval,
          expected: 409,
        )).body['code'],
        'shift_conflict',
      );
      final detail = (await f.call('GET', _manage(id))).body;
      expect(detail['status'], 'accepted');
      expect(detail['actionable'], false);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".task_transfer_links',
        )).single.first,
        0,
      );
    }),
    skip: _skip,
  );

  test(
    'P4.11 receipt, audit and Task link failures roll back every approval effect',
    () => _withFixture((f) async {
      final p = await _transferPlan(f), id = p.proposal['requestId'] as String;
      await _accepted(f, p);
      final original = (await f.call('GET', '/shifts/${p.plan.id}')).body;
      final approval = {'operationId': newUuid(), 'expectedVersion': 2};
      for (final table in [
        'task_transfer_links',
        'workforce_shift_transfer_commands',
        'audit_entries',
      ]) {
        await f.owner.execute(
          'REVOKE INSERT ON "${f.schema}".$table FROM "${f.runtimeUser}"',
        );
        await f.call(
          'POST',
          '${_manage(id)}/approve',
          body: approval,
          expected: 503,
        );
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".$table TO "${f.runtimeUser}"',
        );
        expect((await f.call('GET', '/shifts/${p.plan.id}')).body, original);
        expect((await f.call('GET', _manage(id))).body['status'], 'accepted');
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".shifts',
          )).single.first,
          1,
        );
      }
      await f.call('POST', '${_manage(id)}/approve', body: approval);
    }),
    skip: _skip,
  );
}
