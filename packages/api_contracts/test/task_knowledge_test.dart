import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const article = '11111111-1111-4111-8111-111111111111',
    revision = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> content(int schema) => {
  'schemaVersion': schema,
  'title': 'Work',
  'steps': <Object>[],
  if (schema == 3) 'knowledgeGuidance': null,
};
void main() {
  test('OpenAPI bounds guidance errors to selection and fresh publication', () {
    final paths =
        (jsonDecode(File('platform.openapi.json').readAsStringSync())
                as Map)['paths']
            as Map;
    const root = '/api/v1/platform/task-templates';
    for (final path in [root, '$root/{id}/revisions/{revisionId}/edit']) {
      final description =
          paths[path]['post']['responses']['422']['description'] as String;
      expect(description, contains('guidance_selection_unavailable:'));
      expect(description, isNot(contains('guidance_unavailable:')));
      expect(description, isNot(contains('empty_template')));
    }
    for (final path in [
      '$root/{id}/revisions/{revisionId}/publish',
      '/api/v1/platform/shifts/{id}/publish',
    ]) {
      final description =
          paths[path]['post']['responses']['422']['description'] as String;
      expect(description, contains('guidance_unavailable:'));
      expect(description, isNot(contains('guidance_selection_unavailable')));
      expect(
        description,
        contains('replay precedes fresh lifecycle validation'),
      );
    }
    expect(
      paths['$root/{id}/revisions']['post']['responses'],
      isNot(contains('422')),
    );
  });
  for (final schema in [1, 2, 3]) {
    test('schema $schema keeps exact shape with optional guidance', () {
      final json = content(schema);
      expect(TaskTemplateContent.fromJson(json).toJson(), json);
      expect(TaskTemplateContent.fromJson(json).knowledgeGuidance, isNull);
    });
  }
  test('schema 3 exact pin round trips without Knowledge text', () {
    final json = content(3)
      ..['knowledgeGuidance'] = {'articleId': article, 'revisionId': revision};
    final pin = TaskTemplateContent.fromJson(json).knowledgeGuidance!;
    expect(pin.articleId, article);
    expect(pin.revisionId, revision);
    expect(pin.toJson().keys, hasLength(2));
    expect(TaskTemplateContent.fromJson(json).toJson(), json);
  });
  for (final schema in [1, 2]) {
    test('schema $schema cannot be silently widened', () {
      expect(
        () => TaskTemplateContent.fromJson(
          content(schema)..['knowledgeGuidance'] = null,
        ),
        throwsFormatException,
      );
    });
  }
  for (final bad in [
    <String, dynamic>{},
    {'articleId': article},
    {'articleId': article, 'revisionId': null},
    {'articleId': article, 'revisionId': 'bad'},
    {'articleId': article, 'revisionId': revision, 'title': 'copied'},
    <Object>[],
    'bad',
  ]) {
    test('strict guidance rejects $bad', () {
      expect(
        () => TaskTemplateContent.fromJson(
          content(3)..['knowledgeGuidance'] = bad,
        ),
        throwsFormatException,
      );
    });
  }
  test(
    'schema 3 requires explicit nullable field and rejects unknown fields',
    () {
      expect(
        () => TaskTemplateContent.fromJson(
          content(3)..remove('knowledgeGuidance'),
        ),
        throwsFormatException,
      );
      expect(
        () => TaskTemplateContent.fromJson(content(3)..['other'] = null),
        throwsFormatException,
      );
    },
  );
  test('safe historical instruction decoder rejects publication internals', () {
    final json = {
      'taskId': article,
      'articleId': article,
      'revisionId': revision,
      'revisionNumber': 1,
      'title': 'Instruction',
      'body': 'Plain text',
      'publishedAt': '2026-10-04T12:00:00.000Z',
      'superseded': true,
      'articleRetired': true,
    };
    expect(TaskKnowledgeDto.fromJson(json).toJson(), json);
    expect(
      () => TaskKnowledgeDto.fromJson({...json, 'operationId': article}),
      throwsFormatException,
    );
  });
}
