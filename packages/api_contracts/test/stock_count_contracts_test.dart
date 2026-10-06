import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
Map<String, dynamic> open() => {
  'operationId': id,
  'id': id,
  'employeeId': id,
  'stockLevelIds': [id],
  'purpose': ' physical ',
  'precedingCountId': null,
};
Map<String, dynamic> employee() => {
  'id': id,
  'locationId': id,
  'employeeId': id,
  'purpose': 'Physical <script>literal</script>',
  'status': 'open',
  'version': 1,
  'openedAt': '2030-01-01T00:00:00Z',
  'lines': [
    {
      'id': id,
      'articleId': id,
      'position': 1,
      'sku': 'FLOUR',
      'name': 'Flour',
      'barcode': null,
      'stockUnit': 'kg',
      'round': {'id': id, 'number': 1, 'current': true, 'observation': null},
    },
  ],
};
void main() {
  test('all 12 operations document only their reachable validation errors', () {
    final doc =
        jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map;
    final operations = <String, Map>{
      for (final entry in (doc['paths'] as Map).entries)
        if (entry.key.toString().contains('/stock-counts'))
          for (final op in (entry.value as Map).values)
            op['operationId'] as String: op as Map,
    };
    final expected = <String, Set<String>>{
      'eligibleStockCounters': {'invalid_count'},
      'listStockCounts': {'invalid_count', 'invalid_cursor'},
      'openStockCount': {'invalid_json', 'invalid_count'},
      'reviewStockCount': {'invalid_count'},
      'reviewStockCountHistory': {'invalid_count', 'invalid_cursor'},
      'recountStockCount': {'invalid_json', 'invalid_count'},
      'approveStockCount': {'invalid_json', 'invalid_count'},
      'cancelStockCount': {'invalid_json', 'invalid_count'},
      'ownStockCounts': {'invalid_cursor'},
      'ownStockCount': {'invalid_count'},
      'ownStockCountHistory': {'invalid_count', 'invalid_cursor'},
      'recordStockCountObservation': {'invalid_json', 'invalid_count'},
    };
    expect(operations.keys.toSet(), expected.keys.toSet());
    final conflicts = <String, Set<String>>{
      'openStockCount': {
        'operation_conflict',
        'count_conflict',
        'version_exhausted',
      },
      'recountStockCount': {
        'operation_conflict',
        'count_conflict',
        'version_exhausted',
        'count_stale',
      },
      'approveStockCount': {
        'operation_conflict',
        'count_conflict',
        'version_exhausted',
        'count_stale',
      },
      'cancelStockCount': {
        'operation_conflict',
        'count_conflict',
        'version_exhausted',
      },
      'recordStockCountObservation': {
        'operation_conflict',
        'count_conflict',
        'version_exhausted',
        'round_conflict',
        'observation_exists',
      },
    };
    for (final entry in expected.entries) {
      final op = operations[entry.key]!;
      final responses = op['responses'] as Map;
      final description = responses['400']['description'] as String;
      expect(
        RegExp(r'(\w+):')
            .allMatches(responses['403']['description'] as String)
            .map((m) => m[1])
            .toSet(),
        {'forbidden', 'origin_forbidden'},
        reason: entry.key,
      );
      expect(
        RegExp(r'(\w+):').allMatches(description).map((m) => m[1]).toSet(),
        entry.value,
        reason: entry.key,
      );
      final write = op.containsKey('requestBody');
      expect(responses.keys.toSet(), {
        entry.key == 'openStockCount' ? '201' : '200',
        '400',
        '401',
        '403',
        '404',
        '500',
        '503',
        if (write) ...['409', '413', '415'],
        if ({
          'openStockCount',
          'recountStockCount',
          'approveStockCount',
        }.contains(entry.key))
          '422',
      }, reason: entry.key);
      if (write) {
        expect(
          RegExp(r'(\w+):')
              .allMatches(responses['409']['description'] as String)
              .map((m) => m[1])
              .toSet(),
          conflicts[entry.key],
          reason: entry.key,
        );
      }
      expect(responses.containsKey('413'), write, reason: entry.key);
      expect(responses.containsKey('415'), write, reason: entry.key);
      expect(responses.containsKey('409'), write, reason: entry.key);
      expect(
        responses.containsKey('422'),
        {
          'openStockCount',
          'recountStockCount',
          'approveStockCount',
        }.contains(entry.key),
        reason: entry.key,
      );
      if (entry.key == 'approveStockCount') {
        expect(responses['422']['description'], contains('count_incomplete:'));
        expect(
          responses['422']['description'],
          contains('self_approval_forbidden:'),
        );
        expect(
          responses['422']['description'],
          isNot(contains('assignee_unavailable')),
        );
      }
      if (entry.key == 'eligibleStockCounters' ||
          entry.key == 'listStockCounts') {
        expect(description, contains('Location identity'));
      }
      if (entry.key == 'ownStockCounts') {
        expect(description, isNot(contains('invalid_count')));
      }
    }
  });
  test(
    'selection bounds, duplicates and canonical immutable command payload',
    () {
      final parsed = StockCountCommandInput.fromJson('open', open());
      expect(parsed.toJson()['purpose'], 'physical');
      expect(
        () => parsed.values['purpose'] = 'changed',
        throwsUnsupportedError,
      );
      expect(
        () => (parsed.values['stockLevelIds'] as List).add(id),
        throwsUnsupportedError,
      );
      for (final levels in <List<String>>[
        [],
        [id, id],
        List.filled(101, id),
      ]) {
        expect(
          () => StockCountCommandInput.fromJson('open', {
            ...open(),
            'stockLevelIds': levels,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => StockCountCommandInput.fromJson('open', {
          ...open(),
          'locationId': id,
        }),
        throwsFormatException,
      );
    },
  );
  test('observation exact thousandths and bounded literal text', () {
    final body = {
      'operationId': id,
      'expectedVersion': 1,
      'roundId': id,
      'quantity': '0.500',
      'note': ' <script> literal ',
    };
    final c = StockCountCommandInput.fromJson('observation', body);
    expect(c.toJson()['quantity'], '0.5');
    expect(c.toJson()['note'], '<script> literal');
    for (final q in ['-1', '0.0001', '1e3', 1.5]) {
      expect(
        () => StockCountCommandInput.fromJson('observation', {
          ...body,
          'quantity': q,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => StockCountCommandInput.fromJson('observation', {
        ...body,
        'note': 'x' * 501,
      }),
      throwsFormatException,
    );
  });
  test('commands reject unknown fields, unsafe and exhausted versions', () {
    for (final v in [0, 1.5, 9007199254740991]) {
      expect(
        () => StockCountCommandInput.fromJson('approve', {
          'operationId': id,
          'expectedVersion': v,
        }),
        throwsFormatException,
      );
    }
    expect(
      () => StockCountCommandInput.fromJson('approve', {
        'operationId': id,
        'expectedVersion': 1,
        'note': 'extra',
      }),
      throwsFormatException,
    );
  });
  test('employee detail and history reject every manager evidence field', () {
    expect(EmployeeCountDto.fromJson(employee()).lines.single.stockUnit, 'kg');
    for (final key in [
      'baselineQuantity',
      'discrepancy',
      'currentStock',
      'approval',
      'recordedBy',
    ]) {
      expect(
        () => EmployeeCountDto.fromJson({...employee(), key: 'secret'}),
        throwsFormatException,
      );
      expect(
        () => EmployeeCountRoundDto.fromJson({
          'id': id,
          'number': 1,
          'current': false,
          'observation': null,
          key: 'secret',
        }),
        throwsFormatException,
      );
    }
  });
  test(
    'count movement requires exact typed provenance and legacy keys stay unchanged',
    () {
      final legacy = {
        'id': id,
        'kind': 'adjustment',
        'delta': '-1',
        'balanceAfter': '4',
        'balanceVersion': 2,
        'recordedAt': '2030-01-01T00:00:00Z',
        'recordedBy': id,
        'note': 'physical',
      };
      expect(
        StockMovementDto.fromJson(legacy).toJson().keys.toSet(),
        legacy.keys.toSet(),
      );
      expect(
        () => StockMovementDto.fromJson({...legacy, 'countId': id}),
        throwsFormatException,
      );
      final count = {
        ...legacy,
        'kind': 'count_correction',
        'countId': id,
        'countLineId': id,
        'countObservationId': id,
      };
      expect(
        StockMovementDto.fromJson(count).toJson()['countObservationId'],
        id,
      );
      expect(
        () => StockMovementDto.fromJson({...count, 'delta': '0'}),
        throwsFormatException,
      );
      for (final key in ['countId', 'countLineId', 'countObservationId']) {
        expect(
          () => StockMovementDto.fromJson({...count}..remove(key)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'OpenAPI covers production count routes, separate blind DTOs and exact movement union',
    () {
      final d = jsonDecode(File('platform.openapi.json').readAsStringSync());
      final paths = d['paths'] as Map;
      final counts = paths.keys
          .where((p) => p.toString().contains('/stock-counts'))
          .toList();
      expect(counts, hasLength(11));
      final yaml = File('openapi.yaml').readAsStringSync();
      for (final p in counts) {
        expect(yaml, contains('$p:'));
      }
      final schemas = d['components']['schemas'];
      expect(
        schemas['StockCountOpen']['properties']['stockLevelIds']['maxItems'],
        100,
      );
      for (final type in [
        'EmployeeCount',
        'EmployeeCountLine',
        'EmployeeCountRound',
        'EmployeeCountObservation',
      ]) {
        expect(schemas[type]['additionalProperties'], false);
        expect(jsonEncode(schemas[type]), isNot(contains('baselineQuantity')));
        expect(jsonEncode(schemas[type]), isNot(contains('discrepancy')));
      }
      expect(schemas['StockMovement']['oneOf'], hasLength(2));
    },
  );
}
