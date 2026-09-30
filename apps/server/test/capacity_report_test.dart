import 'package:test/test.dart';

import '../tool/capacity_fixture.dart';

void main() {
  group('capacityPercentileMs', () {
    test('returns null for no samples', () {
      expect(capacityPercentileMs(const <int>[], 50), isNull);
      expect(capacityPercentileMs(const <int>[], 95), isNull);
    });

    test('returns the single sample for every percentile', () {
      expect(capacityPercentileMs(const [7000], 50), 7);
      expect(capacityPercentileMs(const [7000], 95), 7);
    });

    test('uses the nearest rank for an even count (lower middle p50)', () {
      expect(capacityPercentileMs(const [1000, 2000, 3000, 4000], 50), 2);
      expect(capacityPercentileMs(const [1000, 2000, 3000, 4000], 95), 4);
    });

    test('uses the nearest rank for an odd count over unsorted input', () {
      expect(capacityPercentileMs(const [5000, 1000, 3000, 2000, 4000], 50), 3);
      expect(capacityPercentileMs(const [5000, 1000, 3000, 2000, 4000], 95), 5);
    });

    test('clamps percent bounds without mutating the input', () {
      final samples = <int>[3000, 1000, 2000];
      expect(capacityPercentileMs(samples, 0), 1);
      expect(capacityPercentileMs(samples, 100), 3);
      expect(samples, <int>[3000, 1000, 2000]);
    });
  });

  group('CapacityMetrics', () {
    test('empty metrics report no throughput and null percentiles', () {
      final metrics = CapacityMetrics('read');
      metrics.finish();
      final json = metrics.toJson();
      expect(json['requests'], 0);
      expect(json['successes'], 0);
      expect(json['errors'], 0);
      expect(json['throughputPerSecond'], isNull);
      expect(json['p50Ms'], isNull);
      expect(json['p95Ms'], isNull);
    });

    test('latency percentiles come from successes; errors are counted', () {
      final metrics = CapacityMetrics('write');
      metrics.start();
      metrics.recordSuccess('task-start', const Duration(milliseconds: 10));
      metrics.recordSuccess('task-start', const Duration(milliseconds: 20));
      metrics.recordSuccess('task-complete', const Duration(milliseconds: 30));
      metrics.recordError('task-start', 'http_500');
      metrics.recordError('task-start', 'malformed_response');
      metrics.finish();
      final json = metrics.toJson();
      expect(json['requests'], 5);
      expect(json['successes'], 3);
      expect(json['errors'], 2);
      expect(json['p50Ms'], 20);
      expect(json['p95Ms'], 30);
      final byType = json['byRequestType']! as Map<String, dynamic>;
      final start = byType['task-start']! as Map<String, dynamic>;
      expect(start['requests'], 4);
      expect(start['successes'], 2);
      expect(start['errors'], 2);
      expect(start['p50Ms'], 10);
      expect((start['errorClasses']! as Map<String, dynamic>)['http_500'], 1);
      final complete = byType['task-complete']! as Map<String, dynamic>;
      expect(complete['successes'], 1);
    });

    test('throughput is successes per elapsed second', () {
      final metrics = CapacityMetrics('read');
      metrics.start();
      metrics.recordSuccess('admin-audit', Duration.zero);
      metrics.finish();
      expect(metrics.throughputPerSecond, greaterThan(0));
      final json = metrics.toJson();
      expect(json['durationMs'], isA<int>());
      expect(json['throughputPerSecond'], isA<double>());
    });
  });

  group('CapacityExpectations', () {
    test('smoke profile derives the declared counts', () {
      final metrics = CapacityExpectations(smokeCapacityProfile).metrics();
      expect(metrics['shifts'], 2);
      expect(metrics['task_templates'], 2);
      expect(metrics['task_instances'], 4);
      expect(metrics['task_instances_completed'], 4);
      expect(metrics['task_step_results'], 8);
      expect(metrics['task_numeric_attempts'], 4);
      expect(metrics['task_numeric_attempts_in_range'], 4);
      expect(metrics['task_execution_commands'], 16);
      expect(metrics['task_instances_with_four_commands'], 4);
      expect(metrics['task_execution_commands_orphaned'], 0);
      expect(metrics['audit_tasks_instance_started'], 4);
      expect(metrics['audit_tasks_step_number_recorded'], 4);
      expect(metrics['audit_tasks_step_confirmed'], 8);
      expect(metrics['audit_tasks_instance_completed'], 4);
      expect(metrics['audit_read'], 2);
    });

    test('full profile derives the declared counts', () {
      final metrics = CapacityExpectations(fullCapacityProfile).metrics();
      expect(metrics['shifts'], 8);
      expect(metrics['task_instances'], 24);
      expect(metrics['task_step_results'], 48);
      expect(metrics['task_execution_commands'], 96);
      expect(metrics['audit_tasks_step_confirmed'], 48);
      expect(metrics['audit_read'], 5);
    });
  });

  group('CapacityProfile validation', () {
    test('rejects a workers/employees mismatch', () {
      expect(
        () => CapacityProfile(
          name: 'invalid',
          employees: 2,
          workers: 3,
          tasksPerEmployee: 1,
          readIterations: 1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects out-of-bounds profiles', () {
      expect(
        () => CapacityProfile(
          name: 'invalid',
          employees: 0,
          workers: 0,
          tasksPerEmployee: 1,
          readIterations: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CapacityProfile(
          name: 'invalid',
          employees: 1,
          workers: 1,
          tasksPerEmployee: 11,
          readIterations: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => CapacityProfile(
          name: 'invalid',
          employees: 1,
          workers: 1,
          tasksPerEmployee: 1,
          readIterations: 51,
        ),
        throwsArgumentError,
      );
    });
  });
}
