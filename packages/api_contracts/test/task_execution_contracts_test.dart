import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  final start = DateTime.utc(2030);
  final active = TaskExecutionDto(
    instanceId: id,
    status: 'in_progress',
    version: 3,
    startedAt: start,
    startedBy: id,
    results: [TaskStepResultDto(id, start, id)],
  );
  test('execution round trips actual version confirmations and timestamps', () {
    expect(
      TaskExecutionDto.fromJson(active.toJson()).toJson(),
      active.toJson(),
    );
  });
  test('inconsistent execution states are rejected', () {
    for (final invalid in [
      {...active.toJson(), 'status': 'unknown'},
      {...active.toJson(), 'version': 1},
      {...active.toJson(), 'startedBy': null},
      {
        ...active.toJson(),
        'results': [
          ...active.results.map((r) => r.toJson()),
          ...active.results.map((r) => r.toJson()),
        ],
      },
      {...active.toJson(), 'status': 'completed'},
    ]) {
      expect(() => TaskExecutionDto.fromJson(invalid), throwsFormatException);
    }
  });
}
