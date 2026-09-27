import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const step = {
  'id': '11111111-1111-4111-8111-111111111111',
  'type': 'confirmation',
  'instruction': 'Gerät prüfen',
};
Map<String, dynamic> content() => {
  'schemaVersion': 1,
  'title': 'Öffnen',
  'steps': [step],
};
void main() {
  test(
    'content rejects isolated UTF-16 surrogates but accepts valid pairs',
    () {
      for (final malformed in ['\uD800', '\uDC00', '\uD800A', 'A\uDC00']) {
        expect(
          () =>
              TaskTemplateContent.fromJson({...content(), 'title': malformed}),
          throwsFormatException,
        );
        expect(
          () => TaskTemplateContent.fromJson({
            ...content(),
            'steps': [
              {...step, 'instruction': malformed},
            ],
          }),
          throwsFormatException,
        );
      }
      final valid = TaskTemplateContent.fromJson({
        ...content(),
        'title': '🧹' * 120,
        'steps': [
          {...step, 'instruction': '🧹' * 1000},
        ],
      });
      expect(valid.title.runes.length, 120);
      expect(valid.steps.single.instruction.runes.length, 1000);
    },
  );
  test('content preserves ordered IDs, schema and normalized Unicode text', () {
    final raw = {
      ...content(),
      'title': '  Öffnen  ',
      'steps': [
        {...step, 'instruction': ' A\r\nB '},
      ],
    };
    final parsed = TaskTemplateContent.fromJson(raw);
    expect(parsed.title, 'Öffnen');
    expect(parsed.steps.single.instruction, 'A\nB');
    expect(
      TaskTemplateContent.fromJson(
        jsonDecode(jsonEncode(parsed.toJson())) as Map<String, dynamic>,
      ).toJson(),
      parsed.toJson(),
    );
    expect(() => parsed.steps.clear(), throwsUnsupportedError);
  });
  test(
    'content rejects malformed schemas, duplicates, controls and size overflows',
    () {
      for (final change in [
        {'schemaVersion': 2},
        {'schemaVersion': 1.0},
        {'extra': true},
        {'title': ' '},
        {'title': 'x' * 121},
        {'title': 'x\u0000'},
        {
          'steps': [step, step],
        },
        {
          'steps': [
            {...step, 'type': 'script'},
          ],
        },
        {
          'steps': [
            {...step, 'instruction': ''},
          ],
        },
        {
          'steps': [
            {...step, 'instruction': 'x' * 1001},
          ],
        },
        {
          'steps': [
            {...step, 'instruction': 'x\u0000'},
          ],
        },
        {
          'steps': List.generate(
            21,
            (i) => {
              ...step,
              'id': '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}',
            },
          ),
        },
        {
          'steps': List.generate(
            4,
            (i) => {
              ...step,
              'id': '11111111-1111-4111-8111-${i.toString().padLeft(12, '0')}',
              'instruction': '漢' * 1000,
            },
          ),
        },
      ]) {
        expect(
          () => TaskTemplateContent.fromJson({...content(), ...change}),
          throwsFormatException,
          reason: change.keys.toString(),
        );
      }
      expect(
        TaskTemplateContent.fromJson({...content(), 'steps': <Object>[]}).steps,
        isEmpty,
      );
    },
  );
  test(
    'revision state requires UTC publication metadata and matching content',
    () {
      final raw = {
        'id': step['id'],
        'templateId': step['id'],
        'number': 1,
        'status': 'published',
        'title': 'Öffnen',
        'createdAt': '2026-01-01T00:00:00Z',
        'publishedAt': '2026-01-01T01:00:00Z',
        'publishedBy': step['id'],
        'content': content(),
      };
      expect(TemplateRevisionDto.fromJson(raw).content!.title, 'Öffnen');
      for (final change in [
        {'publishedBy': null},
        {'publishedAt': '2026-01-01T01:00:00'},
        {'status': 'draft'},
        {'title': 'Wrong'},
      ]) {
        expect(
          () => TemplateRevisionDto.fromJson({...raw, ...change}),
          throwsFormatException,
        );
      }
    },
  );
}
