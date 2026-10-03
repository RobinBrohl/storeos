import 'dart:convert';
import 'dart:io';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';

Map<String, dynamic> createJson() => {
  'id': id,
  'sku': 'SKU-1',
  'barcode': '000123',
  'name': 'Mehl',
  'description': 'Weizenmehl Type 405',
  'unit': 'kg',
};

Map<String, dynamic> dtoJson() => {
  'id': id,
  'companyId': other,
  'sku': 'SKU-1',
  'barcode': '000123',
  'name': 'Mehl',
  'description': 'Weizenmehl Type 405',
  'unit': 'kg',
  'isActive': true,
  'version': 1,
  'createdAt': '2030-01-01T08:00:00Z',
  'updatedAt': '2030-01-01T08:00:00Z',
};

void main() {
  test('SKU key folds ASCII only, deterministically and locale-free', () {
    expect(articleSkuKey('SKU-AbC'), 'sku-abc');
    expect(articleSkuKey('ÄÖÜ'), 'ÄÖÜ');
    expect(articleSkuKey('Straße'), 'straße');
    expect(articleSkuKey('a b+c:d/e_f.g'), 'a b+c:d/e_f.g');
    expect(articleSkuKey(''), '');
    expect(articleSkuKey('SKU-AbC'), articleSkuKey('SKU-AbC'));
  });
  test(
    'create input requires exact keys and canonicalizes optional blanks',
    () {
      final parsed = ArticleCreateInput.fromJson(createJson());
      expect(parsed.sku, 'SKU-1');
      expect(parsed.barcode, '000123');
      expect(parsed.description, 'Weizenmehl Type 405');
      expect(parsed.unit, 'kg');
      expect(
        ArticleCreateInput.fromJson({...createJson(), 'barcode': null}).barcode,
        isNull,
      );
      expect(
        ArticleCreateInput.fromJson({
          ...createJson(),
          'barcode': '   ',
          'description': '  ',
        }).barcode,
        isNull,
      );
      expect(
        ArticleCreateInput.fromJson({
          ...createJson(),
          'barcode': '   ',
          'description': '  ',
        }).description,
        isNull,
      );
      expect(
        ArticleCreateInput.fromJson({
          ...createJson(),
          'barcode': ' 000123 ',
        }).barcode,
        '000123',
        reason: 'barcode is opaque text; leading zeroes are preserved',
      );
      expect(
        ArticleCreateInput.fromJson({
          ...createJson(),
          'description': ' A\r\nB ',
        }).description,
        'A\nB',
      );
      expect(
        ArticleCreateInput.fromJson({...createJson(), 'sku': '  SKU 1  '}).sku,
        'SKU 1',
      );
      for (final bad in <Map<String, dynamic>>[
        {...createJson()}..remove('barcode'),
        {...createJson(), 'extra': true},
        {...createJson(), 'sku': ' '},
        {...createJson(), 'sku': 'x' * 65},
        {...createJson(), 'sku': 'a\u0000b'},
        {...createJson(), 'name': 'x' * 121},
        {...createJson(), 'unit': 'x' * 33},
        {...createJson(), 'barcode': 'x' * 65},
        {...createJson(), 'description': 'x' * 2001},
        {...createJson(), 'description': 'a\u0000b'},
        {...createJson(), 'id': 'not-a-uuid'},
        {...createJson(), 'sku': 1},
        {...createJson(), 'barcode': 1},
        {...createJson(), 'name': '\uD800'},
      ]) {
        expect(
          () => ArticleCreateInput.fromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
      expect(
        ArticleCreateInput.fromJson({
          ...createJson(),
          'sku': 'Artikel Ä+1: Größe/2_3.4',
          'unit': 'Stück',
        }).sku,
        'Artikel Ä+1: Größe/2_3.4',
        reason: 'the minimal SKU policy does not invent a charset restriction',
      );
      final round = ArticleCreateInput.fromJson(
        jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
      );
      expect(round.toJson(), parsed.toJson());
    },
  );
  test('edit input is a full replacement with a valid expectedVersion', () {
    final parsed = ArticleEditInput.fromJson({
      ...createJson()..remove('id'),
      'expectedVersion': 3,
    });
    expect(parsed.expectedVersion, 3);
    expect(parsed.sku, 'SKU-1');
    expect(
      ArticleEditInput.fromJson({
        ...parsed.toJson(),
        'expectedVersion': 3,
      }).toJson(),
      parsed.toJson(),
    );
    for (final bad in <Map<String, dynamic>>[
      {...parsed.toJson()}..remove('expectedVersion'),
      {...parsed.toJson()}..remove('description'),
      {...parsed.toJson(), 'expectedVersion': 0},
      {...parsed.toJson(), 'expectedVersion': '3'},
      {...parsed.toJson(), 'id': id},
    ]) {
      expect(() => ArticleEditInput.fromJson(bad), throwsFormatException);
    }
  });
  test('lifecycle input accepts exactly expectedVersion', () {
    expect(
      ArticleLifecycleInput.fromJson({'expectedVersion': 2}).expectedVersion,
      2,
    );
    for (final bad in <Map<String, dynamic>>[
      <String, dynamic>{},
      {'expectedVersion': 0},
      {'expectedVersion': null},
      {'expectedVersion': 2, 'isActive': false},
    ]) {
      expect(() => ArticleLifecycleInput.fromJson(bad), throwsFormatException);
    }
  });
  test('article DTO round-trips and rejects impossible shapes', () {
    final dto = ArticleDto.fromJson(dtoJson());
    expect(dto.id, id);
    expect(dto.companyId, other);
    expect(dto.barcode, '000123');
    expect(dto.isActive, isTrue);
    expect(dto.version, 1);
    expect(dto.createdAt, DateTime.utc(2030, 1, 1, 8));
    expect(
      ArticleDto.fromJson(
        jsonDecode(jsonEncode(dto.toJson())) as Map<String, dynamic>,
      ).toJson(),
      dto.toJson(),
    );
    final inactive = ArticleDto.fromJson({
      ...dtoJson(),
      'isActive': false,
      'barcode': null,
      'description': null,
    });
    expect(inactive.isActive, isFalse);
    expect(inactive.barcode, isNull);
    for (final bad in <Map<String, dynamic>>[
      {...dtoJson()}..remove('barcode'),
      {...dtoJson(), 'version': 0},
      {...dtoJson(), 'version': '1'},
      {...dtoJson(), 'isActive': 'true'},
      {...dtoJson(), 'createdAt': '2030-01-01T08:00:00'},
      {...dtoJson(), 'updatedAt': 'not-a-time'},
      {...dtoJson(), 'extra': 1},
    ]) {
      expect(() => ArticleDto.fromJson(bad), throwsFormatException);
    }
  });
  test('article version bounds stay JavaScript-safe for Flutter Web', () {
    expect(ArticleDto.fromJson({...dtoJson(), 'version': 1}).version, 1);
    expect(
      ArticleDto.fromJson({
        ...dtoJson(),
        'version': maxJsonSafeInteger,
      }).version,
      maxJsonSafeInteger,
    );
    expect(
      () => ArticleDto.fromJson({
        ...dtoJson(),
        'version': maxJsonSafeInteger + 1,
      }),
      throwsFormatException,
    );
    expect(
      ArticleEditInput.fromJson({
        ...createJson()..remove('id'),
        'expectedVersion': 1,
      }).expectedVersion,
      1,
    );
    expect(
      ArticleEditInput.fromJson({
        ...createJson()..remove('id'),
        'expectedVersion': maxIncrementableJsonSafeInteger,
      }).expectedVersion,
      maxIncrementableJsonSafeInteger,
    );
    expect(
      () => ArticleEditInput.fromJson({
        ...createJson()..remove('id'),
        'expectedVersion': maxJsonSafeInteger,
      }),
      throwsFormatException,
    );
    expect(
      ArticleLifecycleInput.fromJson({
        'expectedVersion': maxIncrementableJsonSafeInteger,
      }).expectedVersion,
      maxIncrementableJsonSafeInteger,
    );
    expect(
      () => ArticleLifecycleInput.fromJson({
        'expectedVersion': maxJsonSafeInteger,
      }),
      throwsFormatException,
    );
  });
  test('OpenAPI documents the article master routes and schemas', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final paths = document['paths'] as Map;
    final schemas = document['components']['schemas'] as Map;
    final session = [
      {'session': <Object>[]},
    ];
    const operations = <String, Map<String, String>>{
      '/api/v1/platform/articles': {
        'get': 'listArticles',
        'post': 'createArticle',
      },
      '/api/v1/platform/articles/{id}': {'get': 'getArticle'},
      '/api/v1/platform/articles/{id}/edit': {'post': 'editArticle'},
      '/api/v1/platform/articles/{id}/deactivate': {
        'post': 'deactivateArticle',
      },
      '/api/v1/platform/articles/{id}/reactivate': {
        'post': 'reactivateArticle',
      },
    };
    const statuses = <String, Set<String>>{
      'listArticles': {'200', '400', '401', '403', '500', '503'},
      'createArticle': {
        '201',
        '400',
        '401',
        '403',
        '409',
        '413',
        '415',
        '500',
        '503',
      },
      'getArticle': {'200', '400', '401', '403', '404', '500', '503'},
      'editArticle': {
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
      'deactivateArticle': {
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
      'reactivateArticle': {
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
    };
    for (final entry in operations.entries) {
      final path = paths[entry.key] as Map?;
      expect(path, isNotNull, reason: entry.key);
      expect((path!.keys.toSet()), entry.value.keys.toSet());
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
    final create = paths['/api/v1/platform/articles']['post'] as Map;
    expect(
      create['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/CreateArticle',
    );
    expect(
      create['responses']['201']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/Article',
    );
    final list = paths['/api/v1/platform/articles']['get'] as Map;
    final parameters = {
      for (final parameter in list['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(parameters.keys.toSet(), {'after', 'q', 'active'});
    expect(parameters['q']['schema']['maxLength'], articleSearchMaxLength);
    expect(parameters['q']['schema']['minLength'], 1);
    expect(parameters['active']['schema']['enum'], ['true', 'false']);
    expect(parameters['after']['schema']['format'], 'uuid');
    final edit = paths['/api/v1/platform/articles/{id}/edit']['post'] as Map;
    expect(
      edit['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/EditArticle',
    );
    for (final route in ['deactivate', 'reactivate']) {
      final lifecycle =
          paths['/api/v1/platform/articles/{id}/$route']['post'] as Map;
      expect(
        lifecycle['requestBody']['content']['application/json']['schema']['\$ref'],
        '#/components/schemas/ArticleLifecycle',
      );
    }
    final article = schemas['Article'] as Map;
    expect(article['additionalProperties'], isFalse);
    expect((article['required'] as List).toSet(), {
      'id',
      'companyId',
      'sku',
      'barcode',
      'name',
      'description',
      'unit',
      'isActive',
      'version',
      'createdAt',
      'updatedAt',
    });
    final articleProperties = article['properties'] as Map;
    expect(articleProperties['sku']['maxLength'], articleSkuMaxLength);
    expect(articleProperties['name']['maxLength'], articleNameMaxLength);
    expect(articleProperties['unit']['maxLength'], articleUnitMaxLength);
    expect(articleProperties['barcode']['maxLength'], articleBarcodeMaxLength);
    expect(
      articleProperties['description']['maxLength'],
      articleDescriptionMaxLength,
    );
    expect(articleProperties['barcode']['type'], contains('null'));
    expect(articleProperties['version']['minimum'], 1);
    expect(articleProperties['version']['maximum'], maxJsonSafeInteger);
    final createSchema = schemas['CreateArticle'] as Map;
    expect(createSchema['additionalProperties'], isFalse);
    expect((createSchema['required'] as List).toSet(), {
      'id',
      'sku',
      'barcode',
      'name',
      'description',
      'unit',
    });
    final editSchema = schemas['EditArticle'] as Map;
    expect(editSchema['additionalProperties'], isFalse);
    expect((editSchema['required'] as List).toSet(), {
      'expectedVersion',
      'sku',
      'barcode',
      'name',
      'description',
      'unit',
    });
    expect(
      editSchema['properties']['expectedVersion']['maximum'],
      maxIncrementableJsonSafeInteger,
    );
    final lifecycleSchema = schemas['ArticleLifecycle'] as Map;
    expect(lifecycleSchema['additionalProperties'], isFalse);
    expect(lifecycleSchema['required'], ['expectedVersion']);
    expect(
      lifecycleSchema['properties']['expectedVersion']['maximum'],
      maxIncrementableJsonSafeInteger,
    );
    final page = schemas['ArticlePage'] as Map;
    expect(page['additionalProperties'], isFalse);
    expect((page['required'] as List).toSet(), {'items', 'nextCursor'});
    expect(page['properties']['items']['maxItems'], 50);
    expect(
      page['properties']['items']['items']['\$ref'],
      '#/components/schemas/Article',
    );
    final yaml = File('openapi.yaml').readAsStringSync();
    for (final ref in [
      '/api/v1/platform/articles:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1articles'",
      '/api/v1/platform/articles/{id}:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1articles~1{id}'",
      '/api/v1/platform/articles/{id}/edit:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1articles~1{id}~1edit'",
      '/api/v1/platform/articles/{id}/deactivate:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1articles~1{id}~1deactivate'",
      '/api/v1/platform/articles/{id}/reactivate:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1articles~1{id}~1reactivate'",
    ]) {
      expect(yaml, contains(ref));
    }
  });
}
