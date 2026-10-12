import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import '../tool/article_quantity_openapi.dart';

void main() {
  test(
    'published quantity API binds strict decimal inputs, complete review evidence and scoped routes',
    () {
      final doc =
              jsonDecode(File('platform.openapi.json').readAsStringSync())
                  as Map<String, dynamic>,
          schemas = doc['components']['schemas'] as Map,
          paths = doc['paths'] as Map;
      final expected = <String, dynamic>{
        'components': {'schemas': <String, dynamic>{}},
        'paths': <String, dynamic>{},
      };
      addArticleQuantityOpenApi(expected);
      for (final entry in (expected['paths'] as Map).entries) {
        expect(paths[entry.key], entry.value, reason: '${entry.key}');
      }
      for (final entry in (expected['components']['schemas'] as Map).entries) {
        expect(schemas[entry.key], entry.value, reason: '${entry.key}');
      }
      expect(
        schemas['StockQuantityPreviewInput']['properties']['inputQuantity']['type'],
        'string',
      );
      expect(
        schemas['StockQuantityCorrect']['required'],
        containsAll(['operationId', 'review', 'reason']),
      );
      expect(
        schemas['StockQuantityPreview']['required'],
        containsAll([
          'bindingId',
          'profileVersion',
          'stockVersion',
          'targetQuantity',
          'delta',
          'numerator',
          'denominator',
        ]),
      );
      expect(
        schemas['ArticleQuantityReplace']['properties'].containsKey('baseUnit'),
        false,
      );
      expect(schemas['ArticleQuantityPackage']['additionalProperties'], false);
      expect(
        schemas['ArticleQuantityConfigure']['properties']['packages']['maxItems'],
        16,
      );
    },
  );
}
