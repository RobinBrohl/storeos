import 'package:test/test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

void main() {
  const id = '11111111-1111-4111-8111-111111111111';
  test(
    'reason normalizes and counts unicode codepoints with strict bounds',
    () {
      expect(blockingReason('  A\r\nB  '.replaceAll(r'\r\n', '\r\n')), 'A\nB');
      expect(blockingReason('🔧' * 500).runes.length, 500);
      for (final value in [null, 123, '  ', 'x' * 501, 'bad\u0000text']) {
        expect(() => blockingReason(value), throwsFormatException);
      }
    },
  );
  test(
    'execution accepts legacy receipts and versions with blocking cycles',
    () {
      final state = {
        'instanceId': id,
        'status': 'in_progress',
        'version': 2,
        'results': <Map<String, dynamic>>[],
        'startedAt': '2030-01-01T00:00:00Z',
        'startedBy': id,
        'completedAt': null,
        'completedBy': null,
      };
      expect(TaskExecutionDto.fromJson(state).version, 2);
      expect(TaskExecutionDto.fromJson({...state, 'version': 12}).version, 12);
      expect(
        TaskExecutionDto.fromJson({
          ...state,
          'status': 'blocked',
          'version': 3,
          'activeBlockingId': id,
        }).activeBlockingId,
        id,
      );
      expect(
        () => TaskExecutionDto.fromJson({...state, 'status': 'blocked'}),
        throwsFormatException,
      );
    },
  );
  test(
    'confirmation versions cannot duplicate, exceed or equal a terminal version',
    () {
      final s = TaskExecutionDto(
        instanceId: id,
        status: 'completed',
        version: 4,
        startedAt: DateTime.utc(2030),
        startedBy: id,
        completedAt: DateTime.utc(2030),
        completedBy: id,
        results: [
          TaskStepResultDto(id, DateTime.utc(2030), id, acceptedVersion: 4),
        ],
      );
      expect(
        () => TaskExecutionDto.fromJson(s.toJson()),
        throwsFormatException,
      );
    },
  );
}
