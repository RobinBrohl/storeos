import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  final time = DateTime.utc(2030);
  final cancelled = TaskExecutionDto(
    instanceId: id,
    status: 'cancelled',
    version: 4,
    results: [],
    startedAt: time,
    startedBy: id,
    cancelledAt: time,
    cancelledBy: id,
    cancelledBlockingId: id,
  ).toJson();
  test('OpenAPI detail describes the serialized cancelled task', () {
    final document = jsonDecode(
      File('platform.openapi.json').readAsStringSync(),
    );
    final schema =
        document['components']['schemas']['TaskInstanceDetail'] as Map;
    final properties = schema['properties'] as Map;
    final detail = TaskInstanceDto(
      id: id,
      shiftId: id,
      employeeId: id,
      templateId: id,
      revisionId: id,
      title: 'Check',
      position: 0,
      status: 'cancelled',
      version: 5,
      confirmedSteps: 1,
      totalSteps: 1,
      content: TaskTemplateContent(
        title: 'Check',
        steps: [const TemplateStep(id: id, instruction: 'Inspect')],
      ),
    ).toJson();
    expect(properties.keys, containsAll(detail.keys));
    expect(detail.keys, containsAll(schema['required'] as List));
    expect(properties['status']['enum'], contains(detail['status']));
    for (final name in ['version', 'confirmedSteps', 'totalSteps']) {
      final field = properties[name] as Map;
      expect(field['type'], 'integer');
      if (field.containsKey('const')) expect(detail[name], field['const']);
      expect(detail[name], greaterThanOrEqualTo(field['minimum'] as int));
      if (field.containsKey('maximum')) {
        expect(detail[name], lessThanOrEqualTo(field['maximum'] as int));
      }
    }
  });
  test('cancellation requires complete metadata and is not completion', () {
    expect(TaskExecutionDto.fromJson(cancelled).cancelledBlockingId, id);
    for (final key in ['cancelledAt', 'cancelledBy', 'cancelledBlockingId']) {
      expect(
        () => TaskExecutionDto.fromJson({...cancelled, key: null}),
        throwsFormatException,
      );
    }
    expect(
      () => TaskExecutionDto.fromJson({
        ...cancelled,
        'completedAt': time.toIso8601String(),
        'completedBy': id,
      }),
      throwsFormatException,
    );
    expect(
      () => TaskExecutionDto.fromJson({...cancelled, 'status': 'in_progress'}),
      throwsFormatException,
    );
    expect(
      () => TaskExecutionDto.fromJson({...cancelled, 'version': 3}),
      throwsFormatException,
    );
  });
  test(
    'history distinguishes cancellation from resumed and reads legacy closure',
    () {
      final history = TaskBlockingDto(
        id: id,
        instanceId: id,
        reason: 'Missing',
        reportedAt: time,
        reportedBy: id,
        reportedVersion: 3,
        resolution: 'Not possible',
        resolvedAt: time,
        resolvedBy: id,
        resolvedVersion: 4,
        resolutionKind: 'cancelled',
      ).toJson();
      expect(TaskBlockingDto.fromJson(history).resolutionKind, 'cancelled');
      final legacy = {...history}..remove('resolutionKind');
      expect(TaskBlockingDto.fromJson(legacy).resolutionKind, 'resumed');
      expect(
        () =>
            TaskBlockingDto.fromJson({...history, 'resolutionKind': 'unknown'}),
        throwsFormatException,
      );
      expect(
        () => TaskBlockingDto.fromJson({...history, 'resolvedAt': null}),
        throwsFormatException,
      );
    },
  );
}
