import 'shifts.dart';

class TaskStepResultDto {
  const TaskStepResultDto(this.stepId, this.confirmedAt, this.confirmedBy);
  final String stepId, confirmedBy;
  final DateTime confirmedAt;
  factory TaskStepResultDto.fromJson(Map<String, dynamic> j) =>
      TaskStepResultDto(
        shiftUuid(j['stepId']),
        shiftInstant(j['confirmedAt']),
        shiftUuid(j['confirmedBy']),
      );
  Map<String, dynamic> toJson() => {
    'stepId': stepId,
    'confirmedAt': confirmedAt.toUtc().toIso8601String(),
    'confirmedBy': confirmedBy,
  };
}

/// Execution state is independent of the immutable instruction snapshot.
class TaskExecutionDto {
  TaskExecutionDto({
    required this.instanceId,
    required this.status,
    required this.version,
    required List<TaskStepResultDto> results,
    this.startedAt,
    this.startedBy,
    this.completedAt,
    this.completedBy,
  }) : results = List.unmodifiable(results);
  final String instanceId, status;
  final int version;
  final DateTime? startedAt, completedAt;
  final String? startedBy, completedBy;
  final List<TaskStepResultDto> results;
  factory TaskExecutionDto.fromJson(Map<String, dynamic> j) {
    final status = j['status'];
    final version = j['version'];
    final results = (j['results'] as List)
        .map((r) => TaskStepResultDto.fromJson(r as Map<String, dynamic>))
        .toList();
    final start = j['startedAt'] == null ? null : shiftInstant(j['startedAt']);
    final end = j['completedAt'] == null
        ? null
        : shiftInstant(j['completedAt']);
    final startBy = j['startedBy'] == null ? null : shiftUuid(j['startedBy']);
    final endBy = j['completedBy'] == null ? null : shiftUuid(j['completedBy']);
    if (!{'open', 'in_progress', 'completed'}.contains(status) ||
        version is! int ||
        version < 1 ||
        results.length > 20 ||
        results.map((r) => r.stepId).toSet().length != results.length ||
        (status == 'open'
            ? version != 1 ||
                  results.isNotEmpty ||
                  start != null ||
                  startBy != null ||
                  end != null ||
                  endBy != null
            : start == null ||
                  startBy == null ||
                  version != results.length + (status == 'completed' ? 3 : 2) ||
                  results.any((r) => r.confirmedAt.isBefore(start)) ||
                  (status == 'completed'
                      ? end == null || endBy == null || end.isBefore(start)
                      : end != null || endBy != null))) {
      throw const FormatException('Ungültiger Ausführungsstand.');
    }
    return TaskExecutionDto(
      instanceId: shiftUuid(j['instanceId']),
      status: status as String,
      version: version,
      results: results,
      startedAt: start,
      startedBy: startBy,
      completedAt: end,
      completedBy: endBy,
    );
  }
  Map<String, dynamic> toJson() => {
    'instanceId': instanceId,
    'status': status,
    'version': version,
    'startedAt': startedAt?.toUtc().toIso8601String(),
    'startedBy': startedBy,
    'completedAt': completedAt?.toUtc().toIso8601String(),
    'completedBy': completedBy,
    'results': results.map((r) => r.toJson()).toList(),
  };
}
