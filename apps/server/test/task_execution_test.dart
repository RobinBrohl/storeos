import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/tasks/task_execution.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2030), end = DateTime.utc(2030, 1, 1, 8);
  final content = TaskTemplateContent(
    title: 'Work',
    steps: const [
      TemplateStep(id: 'one', instruction: 'First'),
      TemplateStep(id: 'two', instruction: 'Second'),
    ],
  );
  TaskExecution task({
    String status = 'open',
    int version = 1,
    int count = 0,
  }) => TaskExecution(
    TaskExecutionDto(
      instanceId: 'task',
      status: status,
      version: version,
      results: List.generate(
        count,
        (i) => TaskStepResultDto(content.steps[i].id, start, 'actor'),
      ),
    ),
    content,
  );
  test('start includes shift start and excludes shift end', () {
    task().validate('start', 1, null, start, start, end);
    for (final now in [start.subtract(const Duration(microseconds: 1)), end]) {
      expect(
        () => task().validate('start', 1, null, now, start, end),
        throwsA(isA<OutsideShift>()),
      );
    }
  });
  test('only next snapshot step can be confirmed', () {
    final active = task(status: 'in_progress', version: 2);
    active.validate('confirm', 2, 'one', start, start, end);
    for (final id in ['two', 'unknown', null]) {
      expect(
        () => active.validate('confirm', 2, id, start, start, end),
        throwsA(isA<InvalidExecution>()),
      );
    }
  });
  test(
    'completion requires all confirmations and continuation survives shift end',
    () {
      expect(
        () => task(
          status: 'in_progress',
          version: 3,
          count: 1,
        ).validate('complete', 3, null, end, start, end),
        throwsA(isA<InvalidExecution>()),
      );
      task(
        status: 'in_progress',
        version: 3,
        count: 1,
      ).validate('confirm', 3, 'two', end, start, end);
      task(
        status: 'in_progress',
        version: 4,
        count: 2,
      ).validate('complete', 4, null, end, start, end);
    },
  );
  test('stale versions and terminal states reject all new mutations', () {
    expect(
      () => task().validate('start', 2, null, start, start, end),
      throwsA(isA<ExecutionConflict>()),
    );
    for (final command in ['start', 'confirm', 'complete']) {
      expect(
        () => task(
          status: 'completed',
          version: 5,
          count: 2,
        ).validate(command, 5, 'one', end, start, end),
        throwsA(isA<ExecutionConflict>()),
      );
    }
  });
  test(
    'blocking and resuming require correct states and never bypass confirmations',
    () {
      task(
        status: 'in_progress',
        version: 8,
        count: 1,
      ).validate('block', 8, null, end, start, end);
      task(
        status: 'blocked',
        version: 9,
        count: 1,
      ).validate('resume', 9, null, end, start, end);
      for (final command in ['start', 'confirm', 'complete', 'block']) {
        expect(
          () => task(
            status: 'blocked',
            version: 9,
            count: 1,
          ).validate(command, 9, 'two', end, start, end),
          throwsA(isA<ExecutionConflict>()),
        );
      }
      expect(
        () => task(
          status: 'in_progress',
          version: 10,
          count: 1,
        ).validate('complete', 10, null, end, start, end),
        throwsA(isA<InvalidExecution>()),
      );
      expect(
        () => task(
          status: 'completed',
          version: 12,
          count: 2,
        ).validate('resume', 12, null, end, start, end),
        throwsA(isA<ExecutionConflict>()),
      );
    },
  );
  test('cancel only accepts blocked and all new commands reject cancelled', () {
    task(
      status: 'blocked',
      version: 3,
    ).validate('cancel', 3, null, end, start, end);
    for (final status in ['open', 'in_progress', 'completed', 'cancelled']) {
      expect(
        () => task(
          status: status,
          version: 4,
        ).validate('cancel', 4, null, end, start, end),
        throwsA(isA<ExecutionConflict>()),
      );
    }
    for (final command in [
      'start',
      'confirm',
      'complete',
      'block',
      'resume',
      'cancel',
    ]) {
      expect(
        () => task(
          status: 'cancelled',
          version: 5,
          count: 1,
        ).validate(command, 5, 'two', end, start, end),
        throwsA(isA<ExecutionConflict>()),
      );
    }
  });
}
