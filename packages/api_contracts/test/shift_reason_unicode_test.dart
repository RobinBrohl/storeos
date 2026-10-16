import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const _id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
String _decoded(String escaped) => jsonDecode('"$escaped"') as String;

void main() {
  for (final escaped in [
    r'\ud800',
    r'\udbff',
    r'\udc00',
    r'\udfff',
    r'\udc00\ud800',
    r'\ud800\ud800',
    r'\udfff\udfff',
    r'\ud800A',
    r'A\udc00',
    r'\ud800\u0061\udc00',
  ]) {
    test(
      'reason rejects malformed Unicode $escaped before canonical encoding',
      () {
        final reason = _decoded(escaped);
        expect(
          () => transferReason(reason),
          throwsA(
            isA<TransferInputException>().having(
              (e) => e.code,
              'code',
              'invalid_reason',
            ),
          ),
        );
        for (final kind in [
          'source_withdraw',
          'recipient_withdraw',
          'manager_reject',
        ]) {
          final body = {
            'operationId': _id,
            'expectedVersion': 2,
            'reason': reason,
          };
          expect(
            () => ShiftTransferCommandInput.fromJson(kind, body),
            throwsA(
              isA<TransferInputException>().having(
                (e) => e.code,
                'code',
                'invalid_reason',
              ),
            ),
          );
          expect(
            () => ShiftSwapCommandInput.fromJson(kind, body),
            throwsA(
              isA<SwapInputException>().having(
                (e) => e.message,
                'message',
                'Invalid swap reason.',
              ),
            ),
          );
        }
      },
    );
  }
  for (final escaped in [
    r'\ud800\udc00',
    r'\udbff\udfff',
    r'\ud83d\ude00',
    r'A\ud83d\ude00\u00e4',
  ]) {
    test(
      'valid supplementary reason $escaped preserves P4.11 and swap command identity',
      () {
        final reason = _decoded(escaped);
        expect(transferReason('  $reason  '), reason);
        for (final kind in [
          'source_withdraw',
          'recipient_withdraw',
          'manager_reject',
        ]) {
          final body = {
            'operationId': _id,
            'expectedVersion': 2,
            'reason': '  $reason  ',
          };
          final transfer = ShiftTransferCommandInput.fromJson(kind, body);
          final swap = ShiftSwapCommandInput.fromJson(kind, body);
          expect(transfer.toJson(), {...body, 'reason': reason});
          expect(swap.toJson(), {...body, 'reason': reason});
          expect(jsonDecode(transfer.canonical), transfer.toJson());
          expect(jsonDecode(swap.canonical), swap.toJson());
        }
      },
    );
  }
  test(
    'mixed BMP/supplementary scalar count retains exact 500 bound and forbidden controls',
    () {
      final reason = 'A😀' * 250;
      expect(reason.runes, hasLength(500));
      expect(transferReason(reason), reason);
      for (final invalid in [
        '${reason}A',
        '😀' * 501,
        'bad\u0000text',
        'bad\ntext',
        'bad\u0085text',
        'bad\u009ftext',
        '',
      ]) {
        expect(
          () => transferReason(invalid),
          throwsA(isA<TransferInputException>()),
        );
      }
    },
  );
}
