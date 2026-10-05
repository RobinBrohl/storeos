import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  test('decimal strings use exact thousandths and canonical normalization', () {
    for (final pair in {
      '-999999.999': -999999999,
      '999999.999': 999999999,
      '-0.001': -1,
      '1.234': 1234,
      '0001.200': 1200,
      '-0.000': 0,
    }.entries) {
      expect(taskNumber(pair.key), pair.value);
      expect(taskNumber(taskNumberText(pair.value)), pair.value);
    }
    expect(taskNumberText(taskNumber('0001.200')), '1.2');
    expect(taskNumberText(taskNumber('-0.000')), '0');
    for (final bad in [
      null,
      1,
      1.25,
      '',
      '1e2',
      'NaN',
      'Infinity',
      '+1',
      ' 1',
      '1 ',
      '.1',
      '1.',
      '1,2',
      '1,000.123',
      '1000000',
      '-1000000',
      '0.0001',
      '1\n',
    ]) {
      expect(() => taskNumber(bad), throwsFormatException, reason: '$bad');
    }
    expect(() => taskNumberText(1000000000), throwsFormatException);
  });
  const number = {
    'id': '11111111-1111-4111-8111-111111111111',
    'instruction': 'Read the value',
    'type': 'number',
    'unit': '°C',
    'minimum': '-2.125',
    'maximum': '4.5',
  };
  Map<String, dynamic> content(List<Object> steps) => {
    'schemaVersion': 2,
    'title': 'Check',
    'steps': steps,
  };
  test(
    'schema 2 mixes steps and validates rules, sizes and schema 1 compatibility',
    () {
      final confirmation = {
        'id': '22222222-2222-4222-8222-222222222222',
        'type': 'confirmation',
        'instruction': 'Done',
      };
      final raw = content([number, confirmation]);
      expect(TaskTemplateContent.fromJson(raw).toJson(), raw);
      expect(
        TaskTemplateContent.fromJson({
          ...content([confirmation]),
          'schemaVersion': 1,
        }).toJson()['schemaVersion'],
        1,
      );
      expect(
        () => TaskTemplateContent.fromJson({...raw, 'schemaVersion': 1}),
        throwsFormatException,
      );
      for (final change in [
        {'minimum': '5'},
        {'maximum': 'NaN'},
        {'minimum': '0.0001'},
        {'unit': ''},
        {'unit': 'x' * 33},
        {'unit': '\n'},
        {'extra': 1},
      ]) {
        expect(
          () => TaskTemplateContent.fromJson(
            content([
              {...number, ...change},
            ]),
          ),
          throwsFormatException,
        );
      }
      final steps = List.generate(
        20,
        (i) => {
          ...number,
          'id': '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}',
        },
      );
      expect(TaskTemplateContent.fromJson(content(steps)).steps, hasLength(20));
      expect(
        () => TaskTemplateContent.fromJson(content([...steps, number])),
        throwsFormatException,
      );
      expect(
        () => TaskTemplateContent.fromJson(
          content([
            for (final s in steps) {...s, 'instruction': 'x' * 1000},
          ]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'OpenAPI publishes numeric command and both authorized history routes',
    () {
      final api =
          jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map;
      final schemas = api['components']['schemas'] as Map;
      expect(schemas['RecordTaskNumber']['required'], contains('value'));
      expect(
        schemas['TaskNumericAttemptPage']['properties']['items']['maxItems'],
        50,
      );
      expect(
        (api['paths'] as Map).keys.where(
          (p) => (p as String).endsWith('/number-attempts'),
        ),
        hasLength(2),
      );
      expect(
        schemas['TaskTemplateContent']['properties']['schemaVersion']['enum'],
        [1, 2, 3, 4],
      );
    },
  );
}
