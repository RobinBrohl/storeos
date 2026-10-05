import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const fixture = '11111111-1111-4111-8111-111111111111',
    assignment = '22222222-2222-4222-8222-222222222222',
    revision = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> content(int schema) => {
  'schemaVersion': schema,
  'title': 'Work',
  'steps': [
    {'id': fixture, 'type': 'confirmation', 'instruction': 'Do work'},
  ],
  if (schema >= 3) 'knowledgeGuidance': null,
  if (schema == 4) 'planogramGuidance': null,
};
void main() {
  test('OpenAPI precise selectors and contextual routes have bounded errors', () {
    final doc =
            jsonDecode(File('platform.openapi.json').readAsStringSync()) as Map,
        paths = doc['paths'] as Map;
    final selector =
        paths['/api/v1/platform/locations/{locationId}/merchandising/fixtures/{fixtureId}/guidance-selection']['get'];
    expect((selector['responses'] as Map).keys.toSet(), {
      '200',
      '400',
      '401',
      '403',
      '404',
      '422',
      '500',
      '503',
    });
    expect(
      selector['responses']['422']['description'],
      contains('planogram_selection_unavailable'),
    );
    expect(
      (selector['parameters'] as List).every((p) => p['in'] == 'path'),
      true,
    );
    // Existing fresh-publication conflicts remain part of their own contracts.
    for (final path in [
      '/api/v1/platform/task-templates/{id}/revisions/{revisionId}/publish',
      '/api/v1/platform/shifts/{id}/publish',
    ]) {
      expect(paths[path]['post']['responses'], contains('409'));
    }
    for (final path in paths.keys.where(
      (p) => p.toString().endsWith('/planogram'),
    )) {
      final get = paths[path]['get'];
      expect((get['parameters'] as List).every((p) => p['in'] == 'path'), true);
      expect((get['responses'] as Map).keys.toSet(), {
        '200',
        '400',
        '401',
        '403',
        '404',
        '500',
        '503',
      });
      expect(get['description'], contains('No query parameters'));
      expect(
        get['responses']['200']['content']['application/json']['schema']['\$ref'],
        '#/components/schemas/RetainedLayout',
      );
    }
    final schema = doc['components']['schemas']['TaskTemplateContent'];
    expect(schema['properties']['schemaVersion']['enum'], [1, 2, 3, 4]);
    expect(doc['components']['schemas']['PlanogramGuidance']['required'], [
      'fixtureId',
      'assignmentId',
      'revisionId',
    ]);
  });
  for (final knowledge in [false, true]) {
    for (final planogram in [false, true]) {
      test(
        'schema 4 independent Knowledge=$knowledge Planogram=$planogram',
        () {
          final json = content(4);
          if (knowledge) {
            json['knowledgeGuidance'] = {
              'articleId': fixture,
              'revisionId': revision,
            };
          }
          if (planogram) {
            json['planogramGuidance'] = {
              'fixtureId': fixture,
              'assignmentId': assignment,
              'revisionId': revision,
            };
          }
          expect(TaskTemplateContent.fromJson(json).toJson(), json);
        },
      );
    }
  }
  for (final schema in [1, 2, 3]) {
    test('schema $schema unchanged and rejects Planogram field', () {
      final json = content(schema);
      expect(TaskTemplateContent.fromJson(json).toJson(), json);
      json['planogramGuidance'] = null;
      expect(() => TaskTemplateContent.fromJson(json), throwsFormatException);
    });
  }
  test(
    'partial malformed extra and noncanonical deployment identities rejected',
    () {
      final pin = {
        'fixtureId': fixture,
        'assignmentId': assignment,
        'revisionId': revision,
      };
      for (final field in pin.keys) {
        expect(
          () => PlanogramGuidance.fromJson({...pin}..remove(field)),
          throwsFormatException,
        );
        expect(
          () => PlanogramGuidance.fromJson({...pin, field: 'invalid'}),
          throwsFormatException,
        );
      }
      expect(
        () => PlanogramGuidance.fromJson({...pin, 'planogramId': fixture}),
        throwsFormatException,
      );
      expect(
        () => TaskTemplateContent.fromJson(
          content(4)..remove('planogramGuidance'),
        ),
        throwsFormatException,
      );
      expect(
        () => TaskTemplateContent.fromJson(
          content(4)..remove('knowledgeGuidance'),
        ),
        throwsFormatException,
      );
    },
  );
  test('schema 4 preserves numeric execution and exact pin', () {
    final json = content(4);
    json['steps'] = [
      {
        'id': fixture,
        'type': 'number',
        'instruction': 'Measure',
        'unit': 'C',
        'minimum': '1.000',
        'maximum': '5',
      },
    ];
    json['planogramGuidance'] = {
      'fixtureId': fixture,
      'assignmentId': assignment,
      'revisionId': revision,
    };
    final value = TaskTemplateContent.fromJson(json);
    expect(value.steps.single.minimum, '1');
    expect(value.planogramGuidance!.assignmentId, assignment);
    expect(value.toJson()['planogramGuidance'], json['planogramGuidance']);
  });
}
