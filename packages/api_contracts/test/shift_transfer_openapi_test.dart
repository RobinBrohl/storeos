import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'all eleven transfer operations resolve concrete bounded schemas in canonical paths',
    () {
      final doc =
              jsonDecode(File('platform.openapi.json').readAsStringSync())
                  as Map,
          paths = doc['paths'] as Map,
          schemas = (doc['components'] as Map)['schemas'] as Map;
      final entries = paths.entries
          .where(
            (e) =>
                e.key.toString().contains('shift-transfers') ||
                e.key.toString().contains('transfer-recipients'),
          )
          .toList();
      expect(entries.expand((e) => (e.value as Map).values).length, 11);
      final yaml = File('openapi.yaml').readAsStringSync();
      expect(yaml, isNot(contains('x-shift-transfer-paths')));
      for (final entry in entries) {
        expect(yaml, contains('  ${entry.key}:'));
      }
      void resolve(Object? node) {
        if (node is Map) {
          if (node[r'$ref'] case final String ref) {
            if (ref.startsWith('#/components/schemas/')) {
              expect(schemas, contains(ref.split('/').last), reason: ref);
            } else {
              expect(ref, './openapi.yaml#/components/schemas/ApiError');
            }
          }
          for (final v in node.values) {
            resolve(v);
          }
        } else if (node is List) {
          for (final v in node) {
            resolve(v);
          }
        }
      }

      for (final entry in entries) {
        resolve(entry.value);
      }
      for (final name in [
        'ShiftTransferPropose',
        'ShiftTransferRespond',
        'ShiftTransferClose',
        'ShiftTransferTaskSummary',
        'TaskTransferLink',
        'ShiftTransferEvidence',
        'ShiftTransferDetail',
        'ShiftTransferRecipientPage',
        'ShiftTransferOutcome',
        'ShiftTransferPage',
      ]) {
        resolve(schemas[name]);
        expect(schemas[name]['additionalProperties'], false);
      }
      expect(
        schemas['ShiftTransferClose']['properties']['reason']['maxLength'],
        500,
      );
      expect(
        schemas['ShiftTransferPage']['properties']['items']['maxItems'],
        50,
      );
      expect(
        schemas['ShiftTransferEvidence']['properties']['tasks']['maxItems'],
        10,
      );
      final picker =
          paths['/api/v1/platform/employee-home/shifts/{shiftId}/transfer-recipients']['get'];
      expect(
        picker['responses']['422']['x-error-codes'],
        isNot(contains('recipient_unavailable')),
      );
      final reject =
          paths['/api/v1/platform/locations/{locationId}/shift-transfers/{requestId}/reject']['post'];
      expect(reject['responses'], isNot(contains('422')));
      final approve =
          paths['/api/v1/platform/locations/{locationId}/shift-transfers/{requestId}/approve']['post'];
      expect(
        approve['responses']['422']['x-error-codes'],
        contains('planogram_guidance_unavailable'),
      );
    },
  );
}
