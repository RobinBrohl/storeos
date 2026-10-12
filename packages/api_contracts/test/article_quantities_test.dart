import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  test(
    'conversion evidence rejects altered outcomes and non-UTC timestamps and freezes nested review',
    () {
      const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
      final review = StockConversionPreviewDto(
        levelId: id,
        bindingId: id,
        profileId: id,
        profileVersion: 1,
        stockVersion: 1,
        baseUnit: 'piece',
        stockUnit: 'piece',
        inputUnit: 'piece',
        inputLabel: 'piece',
        inputQuantity: '1',
        numerator: '1',
        denominator: '1',
        currentQuantity: '2',
        targetQuantity: '1',
        delta: '-1',
      ).toJson();
      final evidence = {
        'operationId': id,
        'review': review,
        'reason': 'Physical target',
        'recordedBy': id,
        'recordedAt': '2026-10-12T12:00:00.000Z',
        'movementId': id,
        'balanceVersion': 2,
      };
      final parsed = stockQuantityEvidence(evidence);
      expect(
        () => quantityObject(parsed['review'])['delta'] = '0',
        throwsUnsupportedError,
      );
      for (final changes in [
        {'balanceVersion': 1},
        {'movementId': null},
        {'recordedAt': '2026-10-12T12:00:00'},
        {'reason': null},
      ]) {
        expect(
          () => stockQuantityEvidence({...evidence, ...changes}),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'decimal strings canonicalize exactly through six fractional places',
    () {
      expect(quantityDecimal('000000000012.340000'), '12.34');
      expect(quantityDecimal('999999999999.999999'), '999999999999.999999');
      expect(quantityDecimal('0.000001'), '0.000001');
      for (final value in [
        1,
        1.5,
        null,
        '',
        '-1',
        '+1',
        '1e3',
        '1,5',
        ' 1',
        '1.',
        '1.0000001',
        '1000000000000',
      ]) {
        expect(
          () => quantityDecimal(value),
          throwsFormatException,
          reason: '$value',
        );
      }
      expect(
        () => quantityDecimal('0.000000', positive: true),
        throwsFormatException,
      );
    },
  );
  test('dimension, strict wire fields and minimal direct package bounds', () {
    expect(quantityDimension('kg'), 'mass');
    expect(quantityDimension('mL'), 'volume');
    expect(quantityDimension('piece'), 'count');
    expect(() => quantityDimension('bottle'), throwsFormatException);
    final package = {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'label': 'Carton',
      'content': '12',
    };
    expect(quantityPackages([package]).single.content, '12');
    expect(() => quantityPackages([package, package]), throwsFormatException);
    expect(
      () => quantityPackages([
        {...package, 'nestedPackageId': package['id']},
      ]),
      throwsFormatException,
    );
    expect(
      () => quantityPackages([
        {...package, 'content': '0'},
      ]),
      throwsFormatException,
    );
    expect(
      () => quantityPackages(List.filled(17, package)),
      throwsFormatException,
    );
    expect(() => quantityVersion(1.0), throwsFormatException);
    expect(() => quantityVersion(maxJsonSafeInteger), throwsFormatException);
  });
  test('command canonicalization deeply freezes exact retry payloads', () {
    final input = {
      'operationId': 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
      'profileId': 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      'baseUnit': 'piece',
      'packages': [
        {
          'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
          'label': ' Carton ',
          'content': '012.000',
        },
      ],
      'reason': ' Explicit contents ',
    };
    final command = articleQuantityCommand('configure', input);
    expect(command['operationId'], 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa');
    expect((command['packages'] as List).single, {
      'id': 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      'label': 'Carton',
      'content': '12',
    });
    (input['packages'] as List).clear();
    expect(command['packages'], hasLength(1));
    expect(() => command['reason'] = 'changed', throwsUnsupportedError);
    expect(
      () => ((command['packages'] as List).single as Map)['content'] = '2',
      throwsUnsupportedError,
    );
    expect(
      () => articleQuantityCommand('configure', {
        ...command,
        'baseUnit': 'pack:cccccccc-cccc-4ccc-8ccc-cccccccccccc',
      }),
      throwsFormatException,
    );
  });
}
