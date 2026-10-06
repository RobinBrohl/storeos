import 'dart:convert';
import 'dart:io';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const location = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const article = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const movement = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

Map<String, dynamic> articleJson() => {
  'id': article,
  'sku': 'SKU-1',
  'barcode': null,
  'name': 'Mehl',
  'unit': 'kg',
  'isActive': true,
};

Map<String, dynamic> levelJson() => {
  'id': id,
  'locationId': location,
  'articleId': article,
  'stockUnit': 'kg',
  'quantity': '12.5',
  'version': 1,
  'createdAt': '2030-01-01T08:00:00Z',
  'updatedAt': '2030-01-01T08:00:00Z',
  'article': articleJson(),
  'assortmentIsActive': true,
};

Map<String, dynamic> movementJson() => {
  'id': movement,
  'kind': 'adjustment',
  'delta': '-2.5',
  'balanceAfter': '10',
  'balanceVersion': 2,
  'recordedAt': '2030-01-01T09:00:00Z',
  'recordedBy': id,
  'note': 'Korrektur',
};

void main() {
  test('quantity strings parse exactly and stay inside the 12+3 format', () {
    expect(stockQuantity('0'), 0);
    expect(stockQuantity('12'), 12000);
    expect(stockQuantity('12.5'), 12500);
    expect(stockQuantity('12.500'), 12500);
    expect(stockQuantity('0.001'), 1);
    expect(stockQuantity('999999999999.999'), stockMaxScaled);
    expect(stockQuantityText(0), '0');
    expect(stockQuantityText(12500), '12.5');
    expect(stockQuantityText(1), '0.001');
    expect(stockQuantityText(stockMaxScaled), '999999999999.999');
    for (final invalid in <Object?>[
      null,
      12,
      12.5,
      '-1',
      '1.0001',
      '1000000000000',
      '9999999999999',
      '1e3',
      '1,5',
      ' 1',
      '1 ',
      '+1',
      '',
      '.5',
      '1.',
      '00.0001',
    ]) {
      expect(
        () => stockQuantity(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
    expect(() => stockQuantityText(-1), throwsFormatException);
    expect(() => stockQuantityText(stockMaxScaled + 1), throwsFormatException);
  });

  test('deltas parse signed and canonicalize zero without a sign', () {
    expect(stockDelta('-2.5'), -2500);
    expect(stockDelta('0'), 0);
    expect(stockDelta('-0'), 0);
    expect(stockDelta('999999999999.999'), stockMaxScaled);
    expect(stockDelta('-999999999999.999'), -stockMaxScaled);
    expect(stockDeltaText(-2500), '-2.5');
    expect(stockDeltaText(0), '0');
    expect(stockDeltaText(-1), '-0.001');
    expect(stockDeltaText(stockMaxScaled), '999999999999.999');
    for (final invalid in <Object?>['1.0001', '1000000000000', '- 1', '--1']) {
      expect(
        () => stockDelta(invalid),
        throwsFormatException,
        reason: '$invalid',
      );
    }
  });

  test('note rules: optional open note, required correction reason', () {
    expect(normalizeStockOpenNote(null), isNull);
    expect(normalizeStockOpenNote('  Anfangsbestand  '), 'Anfangsbestand');
    expect(normalizeStockAdjustNote('Grund'), 'Grund');
    expect(() => normalizeStockOpenNote(''), throwsFormatException);
    expect(() => normalizeStockOpenNote('   '), throwsFormatException);
    expect(() => normalizeStockOpenNote('x' * 501), throwsFormatException);
    expect(() => normalizeStockOpenNote('a\u0000b'), throwsFormatException);
    expect(() => normalizeStockAdjustNote(null), throwsFormatException);
    expect(() => normalizeStockAdjustNote('  '), throwsFormatException);
    expect(
      normalizeStockOpenNote('x' * 500),
      'x' * 500,
      reason: '500 runes are allowed',
    );
  });

  test('stock level DTO round-trips strict keys and canonical quantities', () {
    final parsed = StockLevelDto.fromJson(levelJson());
    expect(parsed.quantity, '12.5');
    expect(parsed.stockUnit, 'kg');
    expect(parsed.assortmentIsActive, isTrue);
    expect(parsed.article.isActive, isTrue);
    expect(parsed.toJson(), {
      'id': id,
      'locationId': location,
      'articleId': article,
      'stockUnit': 'kg',
      'quantity': '12.5',
      'version': 1,
      'createdAt': '2030-01-01T08:00:00.000Z',
      'updatedAt': '2030-01-01T08:00:00.000Z',
      'article': {
        'id': article,
        'sku': 'SKU-1',
        'barcode': null,
        'name': 'Mehl',
        'unit': 'kg',
        'isActive': true,
      },
      'assortmentIsActive': true,
    });
    for (final bad in <Map<String, dynamic>>[
      {...levelJson()}..remove('stockUnit'),
      {...levelJson()}..remove('assortmentIsActive'),
      {...levelJson(), 'companyId': location},
      {...levelJson(), 'openingMovementId': movement},
      {...levelJson(), 'effectiveAvailability': true},
      {...levelJson(), 'extra': true},
      {...levelJson(), 'quantity': 12.5},
      {...levelJson(), 'quantity': '1.0001'},
      {...levelJson(), 'quantity': '-1'},
      {...levelJson(), 'version': 0},
      {...levelJson(), 'version': maxJsonSafeInteger + 1},
      {...levelJson(), 'assortmentIsActive': 'true'},
      {
        ...levelJson(),
        'article': {...articleJson()}..remove('unit'),
      },
      {
        ...levelJson(),
        'article': {...articleJson(), 'extra': true},
      },
    ]) {
      expect(
        () => StockLevelDto.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
    final boundary = StockLevelDto.fromJson({
      ...levelJson(),
      'quantity': '999999999999.999',
      'version': maxJsonSafeInteger,
    });
    expect(boundary.quantity, '999999999999.999');
  });

  test('movement DTO round-trips and rejects unknown kinds', () {
    final parsed = StockMovementDto.fromJson(movementJson());
    expect(parsed.kind, 'adjustment');
    expect(parsed.delta, '-2.5');
    expect(parsed.balanceAfter, '10');
    expect(parsed.note, 'Korrektur');
    expect(parsed.toJson(), {
      ...movementJson(),
      'recordedAt': '2030-01-01T09:00:00.000Z',
    });
    expect(
      StockMovementDto.fromJson({
        ...movementJson(),
        'kind': 'opening',
        'delta': '2.5',
        'balanceAfter': '2.5',
        'balanceVersion': 1,
        'note': null,
      }).note,
      isNull,
    );
    for (final bad in <Map<String, dynamic>>[
      {...movementJson(), 'kind': 'receiving'},
      {...movementJson(), 'kind': 'waste'},
      {...movementJson(), 'kind': 1},
      {...movementJson()}..remove('note'),
      {...movementJson(), 'extra': true},
      {...movementJson(), 'delta': '1.0001'},
      {...movementJson(), 'balanceAfter': '-1'},
      {...movementJson(), 'balanceVersion': 0},
      {...movementJson(), 'recordedBy': 'nope'},
      {...movementJson(), 'note': ' '},
    ]) {
      expect(
        () => StockMovementDto.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('open input requires exact keys with a nullable note', () {
    final parsed = StockOpenInput.fromJson({
      'id': id,
      'articleId': article,
      'quantity': '12.500',
      'note': null,
    });
    expect(parsed.quantity, '12.5');
    expect(parsed.note, isNull);
    expect(parsed.toJson()['id'], id);
    for (final bad in <Map<String, dynamic>>[
      {'id': id, 'articleId': article, 'quantity': '1'},
      {
        'id': id,
        'articleId': article,
        'quantity': '1',
        'note': null,
        'extra': 1,
      },
      {'id': 'nope', 'articleId': article, 'quantity': '1', 'note': null},
      {'id': id, 'articleId': 'nope', 'quantity': '1', 'note': null},
      {'id': id, 'articleId': article, 'quantity': '-1', 'note': null},
      {'id': id, 'articleId': article, 'quantity': '1', 'note': '  '},
      {'id': id, 'articleId': article, 'quantity': 1, 'note': null},
    ]) {
      expect(
        () => StockOpenInput.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('adjust input requires the movement id, version and reason', () {
    final parsed = StockAdjustInput.fromJson({
      'movementId': movement,
      'expectedVersion': 2,
      'quantity': '10',
      'note': 'Korrektur',
    });
    expect(parsed.expectedVersion, 2);
    expect(parsed.note, 'Korrektur');
    expect(
      StockAdjustInput.fromJson({
        'movementId': movement,
        'expectedVersion': maxIncrementableJsonSafeInteger,
        'quantity': '0',
        'note': 'Grenze',
      }).expectedVersion,
      maxIncrementableJsonSafeInteger,
    );
    for (final bad in <Map<String, dynamic>>[
      {'movementId': movement, 'expectedVersion': 1, 'quantity': '1'},
      {
        'movementId': movement,
        'expectedVersion': 1,
        'quantity': '1',
        'note': null,
      },
      {
        'movementId': movement,
        'expectedVersion': 1,
        'quantity': '1',
        'note': ' ',
      },
      {
        'movementId': movement,
        'expectedVersion': maxJsonSafeInteger,
        'quantity': '1',
        'note': 'x',
      },
      {
        'movementId': 'nope',
        'expectedVersion': 1,
        'quantity': '1',
        'note': 'x',
      },
      {
        'movementId': movement,
        'expectedVersion': 1,
        'quantity': '1',
        'note': 'x',
        'extra': true,
      },
    ]) {
      expect(
        () => StockAdjustInput.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('OpenAPI documents the five stock routes and schemas', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final paths = document['paths'] as Map;
    final schemas = document['components']['schemas'] as Map;
    final session = [
      {'session': <Object>[]},
    ];
    const operations = <String, Map<String, String>>{
      '/api/v1/platform/locations/{locationId}/stock': {
        'get': 'listStockLevels',
        'post': 'createStockLevel',
      },
      '/api/v1/platform/locations/{locationId}/stock/{levelId}': {
        'get': 'getStockLevel',
      },
      '/api/v1/platform/locations/{locationId}/stock/{levelId}/adjust': {
        'post': 'adjustStockLevel',
      },
      '/api/v1/platform/locations/{locationId}/stock/{levelId}/movements': {
        'get': 'listStockMovements',
      },
    };
    const statuses = <String, Set<String>>{
      'listStockLevels': {'200', '400', '401', '403', '404', '500', '503'},
      'createStockLevel': {
        '201',
        '400',
        '401',
        '403',
        '404',
        '409',
        '413',
        '415',
        '500',
        '503',
      },
      'getStockLevel': {'200', '400', '401', '403', '404', '500', '503'},
      'adjustStockLevel': {
        '200',
        '400',
        '401',
        '403',
        '404',
        '409',
        '413',
        '415',
        '500',
        '503',
      },
      'listStockMovements': {'200', '400', '401', '403', '404', '500', '503'},
    };
    for (final entry in operations.entries) {
      final path = paths[entry.key] as Map?;
      expect(path, isNotNull, reason: entry.key);
      expect(path!.keys.toSet(), entry.value.keys.toSet());
      for (final method in entry.value.keys) {
        final operation = path[method] as Map;
        final operationId = entry.value[method]!;
        expect(operation['operationId'], operationId);
        expect(operation['security'], session);
        expect(
          (operation['responses'] as Map).keys.toSet(),
          statuses[operationId],
          reason: operationId,
        );
      }
    }
    final list =
        paths['/api/v1/platform/locations/{locationId}/stock']['get'] as Map;
    final parameters = {
      for (final parameter in list['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(parameters.keys.toSet(), {'locationId', 'after', 'q'});
    expect(parameters['locationId']['in'], 'path');
    expect(parameters['locationId']['schema']['format'], 'uuid');
    expect(parameters['after']['schema']['format'], 'uuid');
    expect(parameters['q']['schema']['maxLength'], 64);
    expect(parameters['q']['schema']['minLength'], 1);
    final create =
        paths['/api/v1/platform/locations/{locationId}/stock']['post'] as Map;
    expect(
      create['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/CreateStockLevel',
    );
    expect(
      create['responses']['201']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/StockLevel',
    );
    final get =
        paths['/api/v1/platform/locations/{locationId}/stock/{levelId}']['get']
            as Map;
    final getParameters = {
      for (final parameter in get['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(getParameters.keys.toSet(), {'locationId', 'levelId'});
    final adjust =
        paths['/api/v1/platform/locations/{locationId}/stock/{levelId}/adjust']['post']
            as Map;
    expect(
      adjust['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/AdjustStockLevel',
    );
    final movements =
        paths['/api/v1/platform/locations/{locationId}/stock/{levelId}/movements']['get']
            as Map;
    final movementParameters = {
      for (final parameter in movements['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(movementParameters.keys.toSet(), {'locationId', 'levelId', 'after'});
    expect(movementParameters['after']['schema']['type'], 'integer');
    expect(movementParameters['after']['schema']['minimum'], 1);
    expect(
      movements['responses']['200']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/StockMovementPage',
    );

    final level = schemas['StockLevel'] as Map;
    expect(level['additionalProperties'], isFalse);
    expect((level['required'] as List).toSet(), {
      'id',
      'locationId',
      'articleId',
      'stockUnit',
      'quantity',
      'version',
      'createdAt',
      'updatedAt',
      'article',
      'assortmentIsActive',
    });
    final levelProperties = level['properties'] as Map;
    expect(
      levelProperties['quantity']['pattern'],
      r'^[0-9]{1,12}(\.[0-9]{1,3})?$',
    );
    expect(levelProperties['stockUnit']['maxLength'], 32);
    expect(levelProperties['version']['minimum'], 1);
    expect(levelProperties['version']['maximum'], maxJsonSafeInteger);
    expect(
      levelProperties['article']['\$ref'],
      '#/components/schemas/StockArticle',
    );
    expect(levelProperties.containsKey('companyId'), isFalse);
    expect(levelProperties.containsKey('openingMovementId'), isFalse);
    expect(levelProperties.containsKey('effectiveAvailability'), isFalse);
    final levelPage = schemas['StockLevelPage'] as Map;
    expect(levelPage['properties']['items']['maxItems'], 50);
    final movementKinds = schemas['StockMovement']['oneOf'] as List;
    expect(movementKinds, hasLength(2));
    final countCorrection = movementKinds[1] as Map;
    expect(countCorrection['properties']['kind']['const'], 'count_correction');
    expect(
      countCorrection['required'],
      containsAll(['countId', 'countLineId', 'countObservationId']),
    );
    final movementSchema = movementKinds.first as Map;
    expect(movementSchema['additionalProperties'], isFalse);
    expect((movementSchema['required'] as List).toSet(), {
      'id',
      'kind',
      'delta',
      'balanceAfter',
      'balanceVersion',
      'recordedAt',
      'recordedBy',
      'note',
    });
    expect((movementSchema['properties']['kind']['enum'] as List).toSet(), {
      'opening',
      'adjustment',
    });
    expect(
      movementSchema['properties']['delta']['pattern'],
      r'^-?[0-9]{1,12}(\.[0-9]{1,3})?$',
    );
    expect(movementSchema['properties']['note']['type'], contains('null'));
    expect(movementSchema['properties']['note']['maxLength'], 500);
    final movementPage = schemas['StockMovementPage'] as Map;
    expect(movementPage['properties']['items']['maxItems'], 50);
    final createSchema = schemas['CreateStockLevel'] as Map;
    expect(createSchema['additionalProperties'], isFalse);
    expect((createSchema['required'] as List).toSet(), {
      'id',
      'articleId',
      'quantity',
      'note',
    });
    expect(createSchema['properties']['note']['type'], contains('null'));
    final adjustSchema = schemas['AdjustStockLevel'] as Map;
    expect(adjustSchema['additionalProperties'], isFalse);
    expect((adjustSchema['required'] as List).toSet(), {
      'movementId',
      'expectedVersion',
      'quantity',
      'note',
    });
    expect(adjustSchema['properties']['note']['type'], 'string');
    expect(
      adjustSchema['properties']['expectedVersion']['maximum'],
      maxIncrementableJsonSafeInteger,
    );
    final yaml = File('openapi.yaml').readAsStringSync();
    for (final ref in [
      '/api/v1/platform/locations/{locationId}/stock:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1stock'",
      '/api/v1/platform/locations/{locationId}/stock/{levelId}:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1stock~1{levelId}'",
      '/api/v1/platform/locations/{locationId}/stock/{levelId}/adjust:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1stock~1{levelId}~1adjust'",
      '/api/v1/platform/locations/{locationId}/stock/{levelId}/movements:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1stock~1{levelId}~1movements'",
    ]) {
      expect(yaml, contains(ref));
    }
  });
}
