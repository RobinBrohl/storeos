import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import '../tool/purchasing_delivery_openapi.dart';

const op = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
Map<String, dynamic> body() => {
  'operationId': op,
  'deliveryId': op,
  'expectedOrderVersion': 1,
  'expectedLedgerVersion': 0,
  'localReference': ' Delivery ',
  'reason': null,
  'lines': [
    {'orderLineId': op, 'quantity': '5'},
  ],
};
void main() {
  test(
    'canonical UUID, exact thousandths, trimmed reference, complete DTO and deep freeze',
    () {
      final raw = body(),
          c = PurchasingDeliveryInput.fromJson('delivery_declare', raw);
      final other = body()
        ..['operationId'] = op.toUpperCase()
        ..['deliveryId'] = op.toUpperCase()
        ..['localReference'] = 'Delivery'
        ..['lines'] = [
          {'orderLineId': op.toUpperCase(), 'quantity': '5.000'},
        ];
      expect(
        PurchasingDeliveryInput.fromJson('delivery_declare', other).canonical,
        c.canonical,
      );
      (raw['lines'] as List).clear();
      expect(c.payload['lines'], hasLength(1));
      expect(
        () => c.payload['lines'][0]['quantity'] = '6',
        throwsUnsupportedError,
      );
    },
  );
  for (final value in [
    null,
    0,
    -1,
    1.5,
    '0',
    '-1',
    '1.0001',
    '1e2',
    'NaN',
    '9999999999999.000',
    '1,2',
  ]) {
    test('reject delivery quantity $value', () {
      expect(
        () => PurchasingDeliveryInput.fromJson('delivery_declare', {
          ...body(),
          'lines': [
            {'orderLineId': op, 'quantity': value},
          ],
        }),
        throwsFormatException,
      );
    });
  }
  for (final field in [
    'companyId',
    'unit',
    'actor',
    'recordedAt',
    'ledgerVersion',
    'terminalSnapshot',
  ]) {
    test('reject forged $field', () {
      expect(
        () => PurchasingDeliveryInput.fromJson('delivery_declare', {
          ...body(),
          field: op,
        }),
        throwsFormatException,
      );
    });
  }
  for (final value in [null, -1, '0', 0.5, 9007199254740992]) {
    test('reject ledger $value', () {
      expect(
        () => PurchasingDeliveryInput.fromJson('delivery_declare', {
          ...body(),
          'expectedLedgerVersion': value,
        }),
        throwsFormatException,
      );
    });
  }
  test('line set, reasons, malformed Unicode, and arithmetic limits', () {
    for (final lines in <List<Map<String, dynamic>>>[
      [],
      [
        {'orderLineId': op, 'quantity': '1'},
        {'orderLineId': op.toUpperCase(), 'quantity': '2'},
      ],
      List.filled(51, {'orderLineId': op, 'quantity': '1'}),
    ]) {
      expect(
        () => PurchasingDeliveryInput.fromJson('delivery_declare', {
          ...body(),
          'lines': lines,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => PurchasingDeliveryInput.fromJson('delivery_declare', {
        ...body(),
        'localReference': 'bad\ud800',
      }),
      throwsFormatException,
    );
    expect(
      () => PurchasingDeliveryInput.fromJson('delivery_void', {
        'operationId': op,
        'expectedOrderVersion': 1,
        'expectedLedgerVersion': 0,
        'expectedRevision': 1,
        'reason': null,
      }),
      throwsFormatException,
    );
    expect(purchasingDeliveryQuantityText(BigInt.zero), '0.000');
    expect(
      purchasingDeliveryQuantityText(
        purchasingDeliveryScaled('999999999999.999'),
      ),
      '999999999999.999',
    );
    expect(
      () => purchasingDeliveryQuantityText(
        BigInt.from(purchasingDeliveryMaxQuantity) + BigInt.one,
      ),
      throwsFormatException,
    );
  });
  test(
    'both OpenAPI representations match all eight endpoint operations; old Purchasing contracts preserved',
    () {
      final doc =
          jsonDecode(File('platform.openapi.json').readAsStringSync())
              as Map<String, dynamic>;
      final expected = jsonDecode(jsonEncode(doc)) as Map<String, dynamic>;
      addPurchasingDeliveryOpenApi(expected);
      for (final e in (expected['paths'] as Map).entries) {
        if (e.key.toString().contains('deliver')) {
          expect(doc['paths'][e.key], e.value);
          expect(
            File('openapi.yaml').readAsStringSync(),
            contains('  ${e.key}:'),
          );
        }
      }
      for (final e in (expected['components']['schemas'] as Map).entries) {
        if (e.key.toString().startsWith('PurchasingDelivery')) {
          expect(doc['components']['schemas'][e.key], e.value);
        }
      }
      final baseline = Process.runSync('git', [
        'show',
        'HEAD:packages/api_contracts/platform.openapi.json',
      ]);
      expect(baseline.exitCode, 0);
      final old = jsonDecode(baseline.stdout as String) as Map;
      for (final e in (old['paths'] as Map).entries) {
        if (e.key.toString().contains('/purchasing/')) {
          expect(doc['paths'][e.key], e.value);
        }
      }
    },
  );
}
