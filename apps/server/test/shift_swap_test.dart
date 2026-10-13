import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/workforce/shift_swap.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

void main() {
  test(
    'current source can close after Account replacement without inheriting consent',
    () {
      final r = ShiftSwapRequest(
        status: 'confirmed',
        version: 3,
        sourceAccount: 'a',
        recipientAccount: 'b',
      );
      final c = ShiftSwapCommandInput.fromJson('source_withdraw', {
        'operationId': '11111111-1111-4111-8111-111111111111',
        'expectedVersion': 3,
        'reason': 'Explicit closure',
      });
      expect(
        () => r.transition(c, 'replacement'),
        throwsA(isA<PlatformFailure>()),
      );
      expect(
        r.transition(c, 'replacement', currentSourceAuthorized: true),
        'withdrawn',
      );
      final confirmation = ShiftSwapCommandInput.fromJson('confirm', {
        'operationId': '11111111-1111-4111-8111-111111111111',
        'expectedVersion': 2,
      });
      expect(
        () => r.transition(
          confirmation,
          'replacement',
          currentSourceAuthorized: true,
        ),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
    },
  );
  const matrix = {
    'requested': {'offer', 'decline', 'source_withdraw', 'manager_reject'},
    'offered': {
      'confirm',
      'decline',
      'source_withdraw',
      'recipient_withdraw',
      'manager_reject',
    },
    'confirmed': {
      'source_withdraw',
      'recipient_withdraw',
      'manager_reject',
      'manager_approve',
    },
  };
  for (final state in shiftSwapStates) {
    final version = switch (state) {
      'requested' => 1,
      'offered' => 2,
      _ => 3,
    };
    for (final kind in shiftSwapKinds.difference({'request'})) {
      test('$state $kind stage and actor matrix', () {
        final r = ShiftSwapRequest(
          status: state,
          version: version,
          sourceAccount: 'a',
          recipientAccount: 'b',
        );
        final actor = switch (kind) {
          'offer' || 'recipient_withdraw' => 'b',
          'confirm' || 'source_withdraw' => 'a',
          'decline' => state == 'requested' ? 'b' : 'a',
          _ => 'manager',
        };
        Map<String, dynamic> body(int v) => {
          'operationId': '11111111-1111-4111-8111-111111111111',
          'expectedVersion': v,
          if (kind == 'offer') ...{
            'counterpartShiftId': '22222222-2222-4222-8222-222222222222',
            'expectedCounterpartVersion': 2,
          },
          if ({
            'source_withdraw',
            'recipient_withdraw',
            'manager_reject',
          }.contains(kind))
            'reason': 'Coverage',
        };
        void attempt(int v, String who) =>
            r.transition(ShiftSwapCommandInput.fromJson(kind, body(v)), who);
        if (matrix[state]?.contains(kind) == true) {
          attempt(version, actor);
        } else {
          expect(
            () => attempt(version, actor),
            throwsA(anyOf(isA<PlatformFailure>(), isA<SwapInputException>())),
          );
        }
        expect(
          () => attempt(version + 1, actor),
          throwsA(anyOf(isA<PlatformFailure>(), isA<SwapInputException>())),
        );
        if ({
          'offer',
          'confirm',
          'decline',
          'recipient_withdraw',
          'manager_approve',
        }.contains(kind)) {
          expect(
            () =>
                attempt(version, kind == 'manager_approve' ? 'a' : 'outsider'),
            throwsA(anyOf(isA<PlatformFailure>(), isA<SwapInputException>())),
          );
        }
      });
    }
  }
}
