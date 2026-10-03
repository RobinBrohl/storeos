import 'dart:convert';
import 'dart:io';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const location = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const article = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

Map<String, dynamic> articleJson() => {
  'id': article,
  'sku': 'SKU-1',
  'barcode': null,
  'name': 'Mehl',
  'unit': 'kg',
  'isActive': true,
};

Map<String, dynamic> dtoJson() => {
  'id': id,
  'locationId': location,
  'isActive': true,
  'version': 1,
  'createdAt': '2030-01-01T08:00:00Z',
  'updatedAt': '2030-01-01T08:00:00Z',
  'article': articleJson(),
};

void main() {
  test('assortment DTO round-trips and keeps both active states separate', () {
    final parsed = ArticleAssortmentDto.fromJson(dtoJson());
    expect(parsed.locationId, location);
    expect(parsed.isActive, isTrue);
    expect(parsed.article.id, article);
    expect(parsed.article.isActive, isTrue);
    expect(parsed.version, 1);
    expect(parsed.toJson()['isActive'], isTrue);
    expect(parsed.toJson()['article'], {
      'id': article,
      'sku': 'SKU-1',
      'barcode': null,
      'name': 'Mehl',
      'unit': 'kg',
      'isActive': true,
    });

    final membershipActive = ArticleAssortmentDto.fromJson({
      ...dtoJson(),
      'article': {...articleJson(), 'isActive': false},
    });
    expect(membershipActive.isActive, isTrue);
    expect(membershipActive.article.isActive, isFalse);
  });

  test('assortment DTO requires exact keys and JSON-safe versions', () {
    expect(
      ArticleAssortmentDto.fromJson({
        ...dtoJson(),
        'version': maxJsonSafeInteger,
      }).version,
      maxJsonSafeInteger,
    );
    for (final bad in <Map<String, dynamic>>[
      {...dtoJson()}..remove('locationId'),
      {...dtoJson(), 'extra': true},
      {...dtoJson(), 'version': 0},
      {...dtoJson(), 'version': maxJsonSafeInteger + 1},
      {...dtoJson(), 'version': '1'},
      {...dtoJson(), 'isActive': 'true'},
      {...dtoJson(), 'id': 'not-a-uuid'},
      {
        ...dtoJson(),
        'article': {...articleJson()}..remove('unit'),
      },
      {
        ...dtoJson(),
        'article': {...articleJson(), 'extra': true},
      },
      {
        ...dtoJson(),
        'article': {...articleJson(), 'name': 'x' * 121},
      },
      {
        ...dtoJson(),
        'article': {...articleJson(), 'barcode': 'x' * 65},
      },
      {
        ...dtoJson(),
        'article': {...articleJson(), 'isActive': 'yes'},
      },
    ]) {
      expect(
        () => ArticleAssortmentDto.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('create input requires exactly id and articleId', () {
    final parsed = ArticleAssortmentCreateInput.fromJson({
      'id': id,
      'articleId': article,
    });
    expect(parsed.id, id);
    expect(parsed.articleId, article);
    expect(parsed.toJson(), {'id': id, 'articleId': article});
    for (final bad in <Map<String, dynamic>>[
      {'id': id},
      {'articleId': article},
      {'id': id, 'articleId': article, 'locationId': location},
      {'id': id, 'articleId': article, 'companyId': location},
      {'id': 'not-a-uuid', 'articleId': article},
      {'id': id, 'articleId': 'not-a-uuid'},
    ]) {
      expect(
        () => ArticleAssortmentCreateInput.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('lifecycle input accepts only an incrementable JSON-safe version', () {
    expect(
      ArticleAssortmentLifecycleInput.fromJson({
        'expectedVersion': 1,
      }).expectedVersion,
      1,
    );
    expect(
      ArticleAssortmentLifecycleInput.fromJson({
        'expectedVersion': maxIncrementableJsonSafeInteger,
      }).expectedVersion,
      maxIncrementableJsonSafeInteger,
    );
    expect(
      () => ArticleAssortmentLifecycleInput.fromJson({
        'expectedVersion': maxJsonSafeInteger,
      }),
      throwsFormatException,
    );
    for (final bad in <Map<String, dynamic>>[
      {'expectedVersion': 0},
      {'expectedVersion': '1'},
      {'expectedVersion': 1, 'extra': true},
      <String, dynamic>{},
    ]) {
      expect(
        () => ArticleAssortmentLifecycleInput.fromJson(bad),
        throwsFormatException,
        reason: '$bad',
      );
    }
  });

  test('OpenAPI documents the location assortment routes and schemas', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final paths = document['paths'] as Map;
    final schemas = document['components']['schemas'] as Map;
    final session = [
      {'session': <Object>[]},
    ];
    const operations = <String, Map<String, String>>{
      '/api/v1/platform/locations/{locationId}/assortment': {
        'get': 'listArticleAssortment',
        'post': 'createArticleAssortment',
      },
      '/api/v1/platform/locations/{locationId}/assortment/{id}': {
        'get': 'getArticleAssortment',
      },
      '/api/v1/platform/locations/{locationId}/assortment/{id}/deactivate': {
        'post': 'deactivateArticleAssortment',
      },
      '/api/v1/platform/locations/{locationId}/assortment/{id}/reactivate': {
        'post': 'reactivateArticleAssortment',
      },
    };
    const statuses = <String, Set<String>>{
      'listArticleAssortment': {
        '200',
        '400',
        '401',
        '403',
        '404',
        '500',
        '503',
      },
      'createArticleAssortment': {
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
      'getArticleAssortment': {'200', '400', '401', '403', '404', '500', '503'},
      'deactivateArticleAssortment': {
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
      'reactivateArticleAssortment': {
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
        paths['/api/v1/platform/locations/{locationId}/assortment']['get']
            as Map;
    final parameters = {
      for (final parameter in list['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(parameters.keys.toSet(), {'locationId', 'after', 'q', 'active'});
    expect(parameters['locationId']['in'], 'path');
    expect(parameters['locationId']['schema']['format'], 'uuid');
    expect(parameters['after']['schema']['format'], 'uuid');
    expect(parameters['q']['schema']['maxLength'], 64);
    expect(parameters['q']['schema']['minLength'], 1);
    expect(parameters['active']['schema']['enum'], ['true', 'false']);
    final create =
        paths['/api/v1/platform/locations/{locationId}/assortment']['post']
            as Map;
    expect(
      create['requestBody']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/CreateArticleAssortment',
    );
    expect(
      create['responses']['201']['content']['application/json']['schema']['\$ref'],
      '#/components/schemas/ArticleAssortment',
    );
    final get =
        paths['/api/v1/platform/locations/{locationId}/assortment/{id}']['get']
            as Map;
    final getParameters = {
      for (final parameter in get['parameters'] as List)
        parameter['name']: parameter,
    };
    expect(getParameters.keys.toSet(), {'locationId', 'id'});
    for (final route in ['deactivate', 'reactivate']) {
      final lifecycle =
          paths['/api/v1/platform/locations/{locationId}/assortment/{id}/$route']['post']
              as Map;
      expect(
        lifecycle['requestBody']['content']['application/json']['schema']['\$ref'],
        '#/components/schemas/ArticleAssortmentLifecycle',
      );
    }
    final assortment = schemas['ArticleAssortment'] as Map;
    expect(assortment['additionalProperties'], isFalse);
    expect((assortment['required'] as List).toSet(), {
      'id',
      'locationId',
      'isActive',
      'version',
      'createdAt',
      'updatedAt',
      'article',
    });
    final assortmentProperties = assortment['properties'] as Map;
    expect(assortmentProperties['version']['minimum'], 1);
    expect(assortmentProperties['version']['maximum'], maxJsonSafeInteger);
    expect(
      assortmentProperties['article']['\$ref'],
      '#/components/schemas/ArticleAssortmentArticle',
    );
    final summary = schemas['ArticleAssortmentArticle'] as Map;
    expect(summary['additionalProperties'], isFalse);
    expect((summary['required'] as List).toSet(), {
      'id',
      'sku',
      'barcode',
      'name',
      'unit',
      'isActive',
    });
    expect(summary['properties']['barcode']['type'], contains('null'));
    expect(summary['properties']['name']['maxLength'], 120);
    expect(summary['properties']['unit']['maxLength'], 32);
    final createSchema = schemas['CreateArticleAssortment'] as Map;
    expect(createSchema['additionalProperties'], isFalse);
    expect((createSchema['required'] as List).toSet(), {'id', 'articleId'});
    final lifecycleSchema = schemas['ArticleAssortmentLifecycle'] as Map;
    expect(lifecycleSchema['additionalProperties'], isFalse);
    expect(lifecycleSchema['required'], ['expectedVersion']);
    expect(
      lifecycleSchema['properties']['expectedVersion']['maximum'],
      maxIncrementableJsonSafeInteger,
    );
    final page = schemas['ArticleAssortmentPage'] as Map;
    expect(page['additionalProperties'], isFalse);
    expect((page['required'] as List).toSet(), {'items', 'nextCursor'});
    expect(page['properties']['items']['maxItems'], 50);
    expect(
      page['properties']['items']['items']['\$ref'],
      '#/components/schemas/ArticleAssortment',
    );
    final yaml = File('openapi.yaml').readAsStringSync();
    for (final ref in [
      '/api/v1/platform/locations/{locationId}/assortment:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1assortment'",
      '/api/v1/platform/locations/{locationId}/assortment/{id}:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1assortment~1{id}'",
      '/api/v1/platform/locations/{locationId}/assortment/{id}/deactivate:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1assortment~1{id}~1deactivate'",
      '/api/v1/platform/locations/{locationId}/assortment/{id}/reactivate:\n'
          "    \$ref: './platform.openapi.json#/paths/~1api~1v1~1platform~1locations~1{locationId}~1assortment~1{id}~1reactivate'",
    ]) {
      expect(yaml, contains(ref));
    }
  });
}
