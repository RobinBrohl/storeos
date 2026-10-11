import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> command(String kind) => {
  'operationId': id,
  if (kind == 'propose') ...{
    'requestId': id,
    'sourceShiftId': id,
    'expectedSourceVersion': 2,
    'recipientEmployeeId': id,
  } else
    'expectedVersion': 1,
  if ({
    'source_withdraw',
    'recipient_withdraw',
    'manager_reject',
  }.contains(kind))
    'reason': 'Coverage changed 😀',
};
void main() {
  for (final kind in shiftTransferKinds) {
    test('$kind strict canonical command roundtrip', () {
      final c = ShiftTransferCommandInput.fromJson(kind, command(kind));
      expect(c.toJson(), command(kind));
      expect(c.operationId, id);
    });
    for (final mutation in ['unknown', 'missing', 'uuid', 'version', 'float']) {
      test('$kind rejects $mutation fields', () {
        final j = command(kind),
            version = kind == 'propose'
                ? 'expectedSourceVersion'
                : 'expectedVersion';
        switch (mutation) {
          case 'unknown':
            j['sourceEmployeeId'] = id;
          case 'missing':
            j.remove('operationId');
          case 'uuid':
            j['operationId'] = 'bad';
          case 'version':
            j[version] = 0;
          case 'float':
            j[version] = 1.0;
        }
        expect(
          () => ShiftTransferCommandInput.fromJson(kind, j),
          throwsA(isA<TransferInputException>()),
        );
      });
    }
  }
  test('withdrawal reasons count Unicode code points and exclude controls', () {
    expect(
      transferReason(' ${List.filled(500, '😀').join()} '),
      List.filled(500, '😀').join(),
    );
    for (final bad in [
      '',
      '   ',
      List.filled(501, '😀').join(),
      'reason\nprivate',
      'reason\u0085private',
      'reason\u009fprivate',
      null,
    ]) {
      expect(() => transferReason(bad), throwsA(isA<TransferInputException>()));
    }
  });
}
