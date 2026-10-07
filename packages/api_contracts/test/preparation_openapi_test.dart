import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  final doc =
      jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map;
  final paths = doc['paths'] as Map;
  final operations = [
    for (final entry in paths.entries.where(
      (e) => e.key.toString().contains('/batches'),
    ))
      for (final op in (entry.value as Map).values) op as Map,
  ];
  test('exact eleven Preparation operations indexed', () {
    expect(operations.length, 11);
    void resolve(Object? node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == r'$ref') {
            final ref = entry.value as String;
            if (ref.startsWith('#/components/schemas/')) {
              expect(
                (doc['components'] as Map)['schemas'],
                contains(ref.split('/').last),
                reason: ref,
              );
            } else {
              expect(ref, './openapi.yaml#/components/schemas/ApiError');
              expect(
                File('openapi.yaml').readAsStringSync(),
                matches(RegExp(r'^\s+ApiError:\s*$', multiLine: true)),
              );
            }
          }
          resolve(entry.value);
        }
      } else if (node is List) {
        for (final value in node) {
          resolve(value);
        }
      }
    }

    for (final operation in operations) {
      resolve(operation);
    }
    final schemas = (doc['components'] as Map)['schemas'] as Map;
    for (final entry in schemas.entries.where(
      (e) => e.key.toString().startsWith('Preparation'),
    )) {
      resolve(entry.value);
    }
    for (final p in paths.keys.where(
      (p) => p.toString().contains('/batches'),
    )) {
      expect(File('openapi.yaml').readAsStringSync(), contains('  $p:'));
    }
  });
  for (final op in operations) {
    test('operation-specific errors ${op['operationId']}', () {
      final responses = op['responses'] as Map;
      final id = op['operationId'] as String;
      final opening = id == 'openPreparationBatch';
      final correction = id == 'correctPreparationBatchCount';
      final command = op.containsKey('requestBody');
      final completion = id == 'completePreparationBatch';
      final list = id.startsWith('list');
      final expected = <String, List<String>>{
        '400': [
          'invalid_request',
          if (list) 'invalid_cursor',
          if (command) 'invalid_json',
          if (opening || completion || correction) 'invalid_count',
          if (command && !opening) 'invalid_content',
        ],
        '401': ['unauthorized'],
        '403': ['forbidden', 'origin_forbidden'],
        '404': ['not_found'],
        if (command)
          '409': [
            if (!opening) 'invalid_lifecycle',
            if (!opening) 'stale_version',
            'operation_conflict',
            if (correction) 'correction_conflict',
          ],
        if (command) '413': ['body_too_large'],
        if (command) '415': ['unsupported_media_type'],
        if (opening)
          '422': [
            'recipe_selection_unavailable',
            'article_unavailable',
            'not_in_assortment',
            'ingredient_unit_changed',
            'operator_unavailable',
          ],
        '500': ['internal_error'],
        '503': ['database_unavailable'],
      };
      expect(
        responses.keys.where((k) => int.parse(k as String) >= 400),
        unorderedEquals(expected.keys),
      );
      for (final entry in expected.entries) {
        final codes = entry.value..sort();
        expect((responses[entry.key] as Map)['x-error-codes'], codes);
        expect(
          (responses[entry.key] as Map)['description'],
          '${entry.key}: ${codes.join(', ')}.',
        );
      }
      for (final e in responses.entries) {
        if (int.parse(e.key.toString()) < 400) continue;
        final response = e.value as Map;
        expect(response['x-error-codes'], isA<List>());
        for (final code in response['x-error-codes'] as List) {
          expect(response['description'], contains(code));
        }
      }
      final open = op['operationId'] == 'openPreparationBatch';
      expect(responses.containsKey('422'), open);
      expect(responses.containsKey('409'), op.containsKey('requestBody'));
      if (!open && responses.containsKey('409')) {
        expect(
          (responses['409'] as Map)['x-error-codes'],
          containsAll([
            'invalid_lifecycle',
            'operation_conflict',
            'stale_version',
          ]),
        );
      }
      if (op['operationId'] == 'correctPreparationBatchCount') {
        expect(
          (responses['409'] as Map)['x-error-codes'],
          contains('correction_conflict'),
        );
      }
      if (op['operationId'].toString().contains('Recipe')) {
        expect((responses['400'] as Map)['x-error-codes'], ['invalid_request']);
      }
    });
  }
}
