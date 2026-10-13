import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'shift_swap_fixture.dart';

void main() {
  for (final kind in shiftSwapKinds) {
    final version = switch (kind) {
      'request' => 2,
      'offer' => 1,
      'confirm' => 2,
      'recipient_withdraw' => 2,
      'manager_approve' => 3,
      _ => 1,
    };
    test('$kind strict command and stable canonical retry', () {
      final body = swapCommand(kind, version);
      final c = ShiftSwapCommandInput.fromJson(kind, body);
      expect(c.toJson(), body);
      expect(
        ShiftSwapCommandInput.fromJson(
          kind,
          Map.fromEntries(body.entries.toList().reversed),
        ).canonical,
        c.canonical,
      );
      for (final key in [
        'actorId',
        'sourceEmployeeId',
        'snapshot',
        'replacementShiftId',
        'exclusions',
        'timestamp',
      ]) {
        expect(
          () =>
              ShiftSwapCommandInput.fromJson(kind, {...body, key: swapId(12)}),
          throwsA(isA<SwapInputException>()),
        );
      }
      for (final key in body.keys) {
        expect(
          () => ShiftSwapCommandInput.fromJson(kind, {...body}..remove(key)),
          throwsA(isA<SwapInputException>()),
        );
        expect(
          () => ShiftSwapCommandInput.fromJson(kind, {...body, key: null}),
          throwsA(isA<SwapInputException>()),
        );
      }
      expect(
        () => c.payload['operationId'] = swapId(4),
        throwsUnsupportedError,
      );
      body['operationId'] = swapId(4);
      expect(c.operationId, swapId(900));
    });
  }
  test('UUID and version types, exact stages and code-point reasons', () {
    for (final bad in [0, -1, 2147483648, 1.0, '1', true]) {
      expect(
        () => ShiftSwapCommandInput.fromJson('request', {
          ...swapCommand('request', 2),
          'expectedSourceVersion': bad,
        }),
        throwsA(isA<SwapInputException>()),
      );
    }
    for (final bad in ['', '${swapId(1)} ', '{${swapId(1)}}', 4]) {
      expect(
        () => ShiftSwapCommandInput.fromJson('request', {
          ...swapCommand('request', 2),
          'requestId': bad,
        }),
        throwsA(isA<SwapInputException>()),
      );
    }
    for (final pair in [
      ('offer', 2),
      ('confirm', 1),
      ('manager_approve', 2),
      ('decline', 3),
      ('recipient_withdraw', 1),
    ]) {
      expect(
        () => ShiftSwapCommandInput.fromJson(
          pair.$1,
          swapCommand(pair.$1, pair.$2),
        ),
        throwsA(isA<SwapInputException>()),
      );
    }
    expect(
      ShiftSwapCommandInput.fromJson('source_withdraw', {
        ...swapCommand('source_withdraw', 1),
        'reason': '  ${'😀' * 500}  ',
      }).payload['reason'],
      '😀' * 500,
    );
    for (final bad in [
      '',
      '😀' * 501,
      'reason\ncontrol',
      'reason\u0080control',
    ]) {
      expect(
        () => ShiftSwapCommandInput.fromJson('source_withdraw', {
          ...swapCommand('source_withdraw', 1),
          'reason': bad,
        }),
        throwsA(isA<SwapInputException>()),
      );
    }
  });
}
