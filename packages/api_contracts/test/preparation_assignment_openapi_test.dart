import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  final doc =
          jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map,
      paths = doc['paths'] as Map,
      schemas = doc['components']['schemas'] as Map;
  const manager =
          '/api/v1/platform/production/manage/locations/{locationId}/preparation-assignments',
      self =
          '/api/v1/platform/production/self/locations/{locationId}/preparation-assignments';
  final operations = <String, List<String>>{
    manager: ['get', 'post'],
    '$manager/assignees': ['get'],
    for (final root in [manager, self]) ...{
      if (root == self) root: ['get'],
      '$root/{assignmentId}': ['get'],
      '$root/{assignmentId}/recipe': ['get'],
      '$root/{assignmentId}/history': ['get'],
    },
    '$manager/{assignmentId}/withdraw': ['post'],
    '$self/{assignmentId}/start': ['post'],
  };
  for (final p in operations.entries) {
    for (final method in p.value) {
      test('$method ${p.key} exact local status/code and YAML parity', () {
        final op = paths[p.key][method] as Map,
            r = op['responses'] as Map,
            create = method == 'post' && p.key == manager,
            start = p.key.endsWith('/start'),
            withdraw = p.key.endsWith('/withdraw'),
            write = method == 'post',
            page =
                method == 'get' &&
                (p.key == manager ||
                    p.key == self ||
                    p.key.endsWith('/assignees'));
        final expected = <String, List<String>>{
          '400': [
            'invalid_request',
            if (page) 'invalid_cursor',
            if (write) 'invalid_json',
            if (create) 'invalid_count',
            if (withdraw) 'invalid_content',
          ],
          '401': ['unauthorized'],
          '403': ['forbidden', 'origin_forbidden'],
          '404': ['not_found'],
          if (write)
            '409': [
              if (create) 'already_exists',
              'operation_conflict',
              'version_conflict',
              if (!create) 'assignment_state_conflict',
            ],
          if (write) '413': ['body_too_large'],
          if (write) '415': ['unsupported_media_type'],
          if (create || start)
            '422': [
              if (create) 'assignee_unavailable',
              create ? 'recipe_selection_unavailable' : 'recipe_unavailable',
              'article_unavailable',
              'not_in_assortment',
              'ingredient_unit_changed',
            ],
          '500': ['internal_error'],
          '503': ['database_unavailable'],
        };
        expect(r.keys.toSet(), {create ? '201' : '200', ...expected.keys});
        for (final e in expected.entries) {
          expect((r[e.key] as Map)['x-error-codes'], unorderedEquals(e.value));
        }
        expect(op['security'], [
          {'session': <String>[]},
        ]);
        final parameters = (op['parameters'] as List).cast<Map>();
        expect(
          parameters.any(
            (p) => p['name'] == 'locationId' && p['required'] == true,
          ),
          true,
        );
        expect(File('openapi.yaml').readAsStringSync(), contains(p.key));
        if (write) {
          final ref =
              op['requestBody']['content']['application/json']['schema'][r'$ref']
                  as String;
          final s = schemas[ref.split('/').last] as Map;
          expect(s['additionalProperties'], false);
          expect(s['required'].toSet(), (s['properties'] as Map).keys.toSet());
        }
      });
    }
  }
  test(
    'complete 12 operations, bounded lists/counts/versions and immutable baseline',
    () {
      expect(operations.values.fold<int>(0, (n, v) => n + v.length), 12);
      expect(
        schemas['PreparationAssignmentPage']['properties']['items']['maxItems'],
        50,
      );
      expect(
        schemas['PreparationAssigneePage']['properties']['items']['maxItems'],
        50,
      );
      expect(
        schemas['PreparationAssignmentCreateRequest']['properties']['plannedDeclaredBatchCount']['minimum'],
        1,
      );
      expect(
        schemas['PreparationAssignmentCreateRequest']['properties']['plannedDeclaredBatchCount']['maximum'],
        9999,
      );
      expect(
        schemas['PreparationAssignmentCreateRequest']['properties']['expectedEmployeeVersion']['maximum'],
        9007199254740991,
      );
      final original =
          jsonDecode(
                utf8.decode(
                  Process.runSync('git', [
                        'show',
                        'HEAD:packages/api_contracts/platform.openapi.json',
                      ], stdoutEncoding: null).stdout
                      as List<int>,
                ),
              )
              as Map;
      for (final p in (original['paths'] as Map).entries) {
        expect(paths[p.key], p.value);
      }
      for (final s in (original['components']['schemas'] as Map).entries) {
        expect(schemas[s.key], s.value);
      }
    },
  );
}
