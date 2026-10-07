import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  final paths =
      (jsonDecode(File('platform.openapi.json').readAsStringSync())
              as Map)['paths']
          as Map;
  final expected = <String, Map<String, List<String>>>{
    'listPublishedRecipes': {
      '400': ['invalid_content', 'invalid_cursor'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'readPublishedRecipe': {
      '400': ['invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'recipeArticleCandidates': {
      '400': [
        'invalid_content',
        'invalid_cursor',
        'invalid_input',
        'invalid_request',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'listManagedRecipes': {
      '400': ['invalid_cursor'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'createRecipe': {
      '400': ['invalid_json', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '409': ['already_exists'],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '422': ['article_unavailable'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'recipeDetail': {
      '400': ['invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'retireRecipe': {
      '400': ['invalid_json', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '409': ['invalid_lifecycle', 'stale_version'],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'recipeHistory': {
      '400': ['invalid_cursor', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'newRecipeDraft': {
      '400': ['invalid_json', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '409': [
        'already_exists',
        'draft_exists',
        'invalid_lifecycle',
        'stale_version',
      ],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '422': ['article_unavailable'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'recipeRevision': {
      '400': ['invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'saveRecipeDraft': {
      '400': [
        'duplicate_ingredient',
        'invalid_content',
        'invalid_json',
        'invalid_quantity',
        'invalid_request',
        'self_ingredient',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '409': ['invalid_lifecycle', 'stale_version'],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '422': ['article_unavailable'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'discardRecipeDraft': {
      '400': ['invalid_json', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '409': ['invalid_lifecycle', 'stale_version'],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
    'publishRecipe': {
      '400': ['invalid_json', 'invalid_request'],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      '409': ['invalid_lifecycle', 'operation_conflict', 'stale_version'],
      '413': ['body_too_large'],
      '415': ['unsupported_media_type'],
      '422': [
        'article_unavailable',
        'ingredient_unit_changed',
        'recipe_not_publishable',
      ],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    },
  };
  final operations = <String, Map>{
    for (final path in paths.entries)
      if (RegExp(
        r'^/api/v1/platform/production/(recipes(?:/|$)|manage/(recipes(?:/|$)|article-candidates$))',
      ).hasMatch(path.key as String))
        for (final op in (path.value as Map).values)
          (op as Map)['operationId'] as String: op,
  };
  test(
    'all thirteen Recipe operations have exact status and error-code contracts',
    () {
      expect(operations.keys.toSet(), expected.keys.toSet());
      for (final entry in expected.entries) {
        final responses = operations[entry.key]!['responses'] as Map;
        final success = {'createRecipe', 'newRecipeDraft'}.contains(entry.key)
            ? '201'
            : '200';
        expect(responses.keys.toSet(), {
          success,
          ...entry.value.keys,
        }, reason: entry.key);
        for (final error in entry.value.entries) {
          final response = responses[error.key] as Map;
          expect(
            response['x-error-codes'],
            error.value,
            reason: '${entry.key} ${error.key}',
          );
          expect(
            response['description'],
            startsWith('Codes: ${error.value.join(', ')}.'),
            reason: entry.key,
          );
        }
      }
    },
  );
}
