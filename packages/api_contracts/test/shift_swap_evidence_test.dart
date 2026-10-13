import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'shift_swap_fixture.dart';

void main() {
  for (final stage in [1, 2, 3]) {
    for (final kind in [
      'decline',
      'source_withdraw',
      'recipient_withdraw',
      'manager_reject',
      'manager_approve',
    ]) {
      if ((kind == 'decline' && stage == 3) ||
          (kind == 'recipient_withdraw' && stage == 1) ||
          (kind == 'manager_approve' && stage != 3)) {
        continue;
      }
      test('terminal result binds exact $kind from stage $stage', () {
        final state = switch (kind) {
          'decline' => 'declined',
          'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
          'manager_reject' => 'rejected',
          _ => 'approved',
        };
        final request = swapEvidence(state: state, stage: stage);
        request['terminalKind'] = kind;
        final result = {
          'operationId': request['terminalOperationId'],
          'kind': kind,
          'acceptedVersion': request['version'],
          'statusCode': 200,
          'request': request,
          'replayed': false,
        };
        expect(ShiftSwapCommandResult.fromJson(result).toJson(), result);
        for (final other in shiftSwapKinds.where((k) => k != kind)) {
          expect(
            () => ShiftSwapCommandResult.fromJson({...result, 'kind': other}),
            throwsFormatException,
          );
        }
      });
    }
  }
  for (final stage in [1, 2, 3]) {
    final active = ['requested', 'offered', 'confirmed'][stage - 1];
    for (final state in [
      active,
      'withdrawn',
      'rejected',
      if (stage < 3) 'declined',
      if (stage == 3) 'approved',
    ]) {
      test('$state from stage $stage exact immutable evidence', () {
        final j = swapEvidence(state: state, stage: stage, tasks: 10),
            dto = ShiftSwapDto.fromJson(j);
        expect(dto.toJson(), j);
        expect(() => dto.json['status'] = 'requested', throwsUnsupportedError);
        expect(
          () => ((dto.json['legs'] as List).first as Map)['sourceShiftId'] =
              swapId(999),
          throwsUnsupportedError,
        );
        for (final key in [
          'sourceAccountId',
          'recipientLinkId',
          'executionValues',
          'instructionBody',
        ]) {
          expect(
            () => ShiftSwapDto.fromJson({...j, key: swapId(55)}),
            throwsFormatException,
          );
        }
        for (final patch in [
          {'version': 9},
          {'version': (j['version'] as int) + 1},
          {'recipientEmployeeId': j['sourceEmployeeId']},
          {'offeredAt': null},
          {'confirmedAt': stage == 3 ? null : '2029-01-01T12:00:00Z'},
        ]) {
          if (patch.entries.every((e) => j[e.key] == e.value)) continue;
          expect(
            () => ShiftSwapDto.fromJson({...j, ...patch}),
            throwsFormatException,
          );
        }
        (j['legs'] as List).clear();
        expect(dto.json['legs'], hasLength(stage == 1 ? 1 : 2));
      });
    }
  }
  test('forged pair, work, lineage and original receipt binding reject', () {
    final valid = swapEvidence(state: 'approved', stage: 3);
    final result = {
      'operationId': swapId(9),
      'kind': 'manager_approve',
      'acceptedVersion': 4,
      'statusCode': 200,
      'request': valid,
      'replayed': false,
    };
    expect(ShiftSwapCommandResult.fromJson(result).toJson(), result);
    expect(
      ShiftSwapCommandResult.fromJson({
        ...result,
        'replayed': true,
      }).json['request'],
      valid,
    );
    for (final patch in [
      {'kind': 'confirm'},
      {'operationId': swapId(8)},
      {'acceptedVersion': 3},
      {'statusCode': 201},
      {'request': null},
      {'replayed': 'true'},
    ]) {
      expect(
        () => ShiftSwapCommandResult.fromJson({...result, ...patch}),
        throwsFormatException,
      );
    }
    for (final key in [
      'sourceShiftId',
      'sourceEmployeeId',
      'incomingEmployeeId',
      'tasks',
      'taskLinks',
    ]) {
      final j = swapEvidence(state: 'approved', stage: 3),
          a = (j['legs'] as List).first as Map<String, dynamic>;
      a[key] = switch (key) {
        'tasks' => <Object?>[],
        'taskLinks' => <Object?>[],
        _ => swapId(999),
      };
      expect(() => ShiftSwapDto.fromJson(j), throwsFormatException);
    }
  });
  test(
    'detail and discovery enforce roles, bounded pages and private-field exclusion',
    () {
      final detail = {
        'request': swapEvidence(state: 'offered', stage: 2),
        'participantRole': 'source',
        'actionable': true,
        'nonActionableReason': null,
        'availableActions': ['confirm', 'decline', 'source_withdraw'],
      };
      expect(ShiftSwapDetailDto.fromJson(detail).toJson(), detail);
      for (final patch in [
        {'participantRole': 'recipient'},
        {
          'availableActions': ['manager_approve'],
        },
        {'nonActionableReason': 'identity_changed'},
      ]) {
        expect(
          () => ShiftSwapDetailDto.fromJson({...detail, ...patch}),
          throwsFormatException,
        );
      }
      final row = {'employeeId': swapId(5), 'displayName': 'Named colleague'};
      final page = {
        'items': [row],
        'nextCursor': null,
      };
      expect(ShiftSwapColleaguePageDto.fromJson(page).toJson(), page);
      for (final key in [
        'accountId',
        'linkId',
        'startsAt',
        'shiftCount',
        'eligibilityReason',
      ]) {
        expect(
          () => ShiftSwapColleaguePageDto.fromJson({
            'items': [
              {...row, key: swapId(10)},
            ],
            'nextCursor': null,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => ShiftSwapColleaguePageDto.fromJson({
          ...page,
          'items': List.filled(51, row),
        }),
        throwsFormatException,
      );
      expect(
        () => ShiftSwapColleaguePageDto.fromJson({
          ...page,
          'nextCursor': 'x' * 2049,
        }),
        throwsFormatException,
      );
      final candidate = {
        'shiftId': swapId(20),
        'version': 2,
        'startsAt': '2030-01-01T10:00:00Z',
        'endsAt': '2030-01-01T11:00:00Z',
      };
      expect(
        ShiftSwapCounterpartPageDto.fromJson({
          'items': [candidate],
          'nextCursor': null,
        }).json['items'],
        hasLength(1),
      );
      expect(
        () => ShiftSwapCounterpartPageDto.fromJson({
          'items': [
            {...candidate, 'employeeId': swapId(5)},
          ],
          'nextCursor': null,
        }),
        throwsFormatException,
      );
      expect(
        ShiftSwapPageDto.fromJson({
          'items': [swapEvidence()],
          'nextCursor': null,
        }).json['items'],
        hasLength(1),
      );
    },
  );
}
