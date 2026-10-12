import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  final doc =
          jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map,
      paths = doc['paths'] as Map,
      schemas = doc['components']['schemas'] as Map;
  const s = '/api/v1/platform/purchasing/suppliers',
      o = '/api/v1/platform/purchasing/locations/{locationId}/orders';
  final writes = <String, Map<String, Map<String, List<String>>>>{
    s: {
      'post': {
        '409': ['already_exists', 'operation_conflict'],
      },
    },
    '$s/{supplierId}': {
      'put': {
        '409': [
          'version_conflict',
          'version_limit',
          'supplier_state_conflict',
          'no_change',
          'operation_conflict',
        ],
      },
    },
    '$s/{supplierId}/retire': {
      'post': {
        '409': [
          'version_conflict',
          'version_limit',
          'supplier_state_conflict',
          'operation_conflict',
        ],
      },
    },
    o: {
      'post': {
        '409': [
          'already_exists',
          'operation_conflict',
          'order_reference_conflict',
          'supplier_changed',
        ],
        '422': ['supplier_selection_unavailable'],
      },
    },
    '$o/{orderId}': {
      'put': {
        '409': [
          'version_conflict',
          'version_limit',
          'operation_conflict',
          'order_state_conflict',
          'order_reference_conflict',
          'no_change',
          'supplier_changed',
          'article_reference_changed',
        ],
        '422': [
          'supplier_selection_unavailable',
          'article_selection_unavailable',
          'not_in_assortment',
        ],
      },
    },
    '$o/{orderId}/issue': {
      'post': {
        '409': [
          'version_conflict',
          'version_limit',
          'operation_conflict',
          'order_state_conflict',
          'supplier_changed',
          'article_reference_changed',
          'article_unit_changed',
        ],
        '422': [
          'supplier_selection_unavailable',
          'article_selection_unavailable',
          'not_in_assortment',
          'order_not_issuable',
        ],
      },
    },
    for (final action in ['close', 'cancel'])
      '$o/{orderId}/$action': {
        'post': {
          '409': [
            'version_conflict',
            'version_limit',
            'operation_conflict',
            'order_state_conflict',
          ],
        },
      },
  };
  for (final p in writes.entries) {
    for (final m in p.value.entries) {
      test('endpoint-local ${m.key} ${p.key} errors', () {
        final responses = paths[p.key][m.key]['responses'] as Map;
        for (final e in m.value.entries) {
          expect(responses[e.key]['x-error-codes'], unorderedEquals(e.value));
        }
        expect(responses.containsKey('422'), m.value.containsKey('422'));
        expect(responses['413']['x-error-codes'], ['body_too_large']);
        expect(responses['415']['x-error-codes'], ['unsupported_media_type']);
        expect(responses['500']['x-error-codes'], ['internal_error']);
        expect(responses['503']['x-error-codes'], ['database_unavailable']);
      });
    }
  }
  test('all 15 scoped operations, strict DTOs and resolvable refs', () {
    final purchasing = paths.entries.where(
      (e) =>
          e.key.toString().contains('/purchasing/') &&
          !e.key.toString().contains('deliver'),
    );
    expect(purchasing.fold<int>(0, (n, e) => n + (e.value as Map).length), 15);
    final index = File('openapi.yaml').readAsStringSync();
    void refs(Object? node) {
      if (node is Map) {
        for (final e in node.entries) {
          if (e.key == r'$ref') {
            final ref = e.value as String;
            if (ref.startsWith('#/components/schemas/')) {
              expect(schemas.containsKey(ref.split('/').last), true);
            } else {
              expect(ref, './openapi.yaml#/components/schemas/ApiError');
              expect(index, contains('  schemas:'));
            }
          } else {
            refs(e.value);
          }
        }
      } else if (node is List) {
        for (final n in node) {
          refs(n);
        }
      }
    }

    for (final e in purchasing) {
      expect(index, contains('  ${e.key}:'));
      refs(e.value);
    }
    for (final e in schemas.entries.where(
      (e) => e.key.toString().startsWith('Purchasing'),
    )) {
      refs(e.value);
      expect(e.value['additionalProperties'], false);
      expect(
        e.value['required'],
        unorderedEquals((e.value['properties'] as Map).keys),
      );
    }
  });
  test(
    'existing OpenAPI contracts are byte-preserved in the generated baseline blocks',
    () {
      final baseline = Process.runSync('git', [
        'show',
        'HEAD:packages/api_contracts/platform.openapi.json',
      ], stdoutEncoding: null);
      expect(baseline.exitCode, 0);
      final original =
          jsonDecode(utf8.decode(baseline.stdout as List<int>)) as Map;
      for (final p in (original['paths'] as Map).entries) {
        expect(paths[p.key], p.value);
      }
      for (final s in (original['components']['schemas'] as Map).entries) {
        expect(schemas[s.key], s.value);
      }
    },
  );
}
