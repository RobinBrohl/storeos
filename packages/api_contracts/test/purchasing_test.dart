import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = '11111111-1111-4111-8111-111111111111';
void main() {
  test('positive exact thousandths survive canonicalization', () {
    for (final e in {
      '0.001': '0.001',
      '2.5': '2.500',
      '12': '12.000',
      '999999999999.999': '999999999999.999',
    }.entries) {
      expect(purchasingQuantity(e.key), e.value);
    }
  });
  for (final v in [
    0,
    2.5,
    '0',
    '-1',
    '1.0001',
    '1e3',
    '1000000000000',
    'NaN',
    '1.',
    ' 1',
    '0000000000001',
  ]) {
    test('reject invalid quantity $v', () {
      expect(() => purchasingQuantity(v), throwsFormatException);
    });
  }
  test('text Unicode bounds and literal content', () {
    expect(purchasingText('😀' * 200, 200), '😀' * 200);
    for (final s in ['😀' * 201, 'a\nb', '\u0000', '\ud800']) {
      expect(() => purchasingText(s, 200), throwsFormatException);
    }
  });
  test('strict input owns no server attribution', () {
    final j = {
      'id': id,
      'operationId': id,
      'name': ' Name ',
      'orderingReference': null,
    };
    expect(
      PurchasingCommandInput.fromJson('supplier_create', j).payload['name'],
      'Name',
    );
    expect(
      () => PurchasingCommandInput.fromJson('supplier_create', {
        ...j,
        'actorId': id,
      }),
      throwsFormatException,
    );
  });
  test('deep frozen line collection', () {
    final line = {
      'id': id,
      'articleId': id,
      'expectedArticleVersion': 1,
      'quantity': '2.5',
      'reselectArticle': true,
    };
    final j = {
      'operationId': id,
      'expectedVersion': 1,
      'reference': 'PO',
      'supplierId': id,
      'expectedSupplierVersion': 1,
      'reselectSupplier': false,
      'lines': [line],
    };
    final c = PurchasingCommandInput.fromJson('order_save', j);
    line['quantity'] = '12';
    expect((c.payload['lines'] as List).single['quantity'], '2.500');
    expect(
      () => ((c.payload['lines'] as List).single as Map)['quantity'] = '1',
      throwsUnsupportedError,
    );
  });
  test('ASCII fold reserves references without Unicode folding', () {
    expect(purchasingReferenceKey('AB-Ä'), 'ab-Ä');
  });
}
