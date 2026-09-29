import 'shifts.dart';

class TaskStepResultDto {
  const TaskStepResultDto(
    this.stepId,
    this.confirmedAt,
    this.confirmedBy, {
    this.acceptedVersion,
    this.numericAttemptId,
  });
  final String stepId, confirmedBy;
  final String? numericAttemptId;
  final DateTime confirmedAt;
  final int? acceptedVersion;
  factory TaskStepResultDto.fromJson(Map<String, dynamic> j) =>
      TaskStepResultDto(
        shiftUuid(j['stepId']),
        shiftInstant(j['confirmedAt']),
        shiftUuid(j['confirmedBy']),
        acceptedVersion: j['acceptedVersion'] as int?,
        numericAttemptId: j['numericAttemptId'] == null
            ? null
            : shiftUuid(j['numericAttemptId']),
      );
  Map<String, dynamic> toJson() => {
    'stepId': stepId,
    if (numericAttemptId != null) 'numericAttemptId': numericAttemptId,
    'confirmedAt': confirmedAt.toUtc().toIso8601String(),
    'confirmedBy': confirmedBy,
    if (acceptedVersion != null) 'acceptedVersion': acceptedVersion,
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
    this.activeBlockingId,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelledBlockingId,
  }) : results = List.unmodifiable(results);
  final String instanceId, status;
  final int version;
  final DateTime? startedAt, completedAt, cancelledAt;
  final String? startedBy,
      completedBy,
      activeBlockingId,
      cancelledBy,
      cancelledBlockingId;
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
    final blocking = j['activeBlockingId'] == null
        ? null
        : shiftUuid(j['activeBlockingId']);
    final cancelledAt = j['cancelledAt'] == null
        ? null
        : shiftInstant(j['cancelledAt']);
    final cancelledBy = j['cancelledBy'] == null
        ? null
        : shiftUuid(j['cancelledBy']);
    final cancelledBlockingId = j['cancelledBlockingId'] == null
        ? null
        : shiftUuid(j['cancelledBlockingId']);
    if (!{
          'open',
          'in_progress',
          'blocked',
          'completed',
          'cancelled',
        }.contains(status) ||
        (status == 'cancelled'
            ? cancelledAt == null ||
                  cancelledBy == null ||
                  cancelledBlockingId == null ||
                  start == null ||
                  cancelledAt.isBefore(start)
            : cancelledAt != null ||
                  cancelledBy != null ||
                  cancelledBlockingId != null) ||
        (status == 'blocked') != (blocking != null) ||
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
                  version <
                      results.length +
                          (status == 'cancelled'
                              ? 4
                              : status == 'completed'
                              ? 3
                              : status == 'blocked'
                              ? 3
                              : 2) ||
                  results.any((r) => r.confirmedAt.isBefore(start)) ||
                  (status == 'completed'
                      ? end == null || endBy == null || end.isBefore(start)
                      : end != null || endBy != null))) {
      throw const FormatException('Ungültiger Ausführungsstand.');
    }
    var priorVersion = 2;
    for (final result in results) {
      final accepted = result.acceptedVersion;
      if (accepted != null) {
        if (accepted <= priorVersion ||
            accepted > version ||
            (status != 'in_progress' && accepted == version)) {
          throw const FormatException('Ungültige Bestätigungsversion.');
        }
        priorVersion = accepted;
      }
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
      activeBlockingId: blocking,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancelledBlockingId: cancelledBlockingId,
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
    if (activeBlockingId != null) 'activeBlockingId': activeBlockingId,
    if (cancelledAt != null)
      'cancelledAt': cancelledAt!.toUtc().toIso8601String(),
    if (cancelledBy != null) 'cancelledBy': cancelledBy,
    if (cancelledBlockingId != null) 'cancelledBlockingId': cancelledBlockingId,
    'results': results.map((r) => r.toJson()).toList(),
  };
}

/// Bounded plain text shared by both reporting and resolution commands.
String blockingReason(Object? value) {
  if (value is! String) throw const FormatException('Begründung erforderlich.');
  final normalized = value.replaceAll('\r\n', '\n').trim();
  if (normalized.isEmpty ||
      normalized.runes.length > 500 ||
      RegExp(r'[\x00-\x08\x0b-\x1f\x7f]').hasMatch(normalized)) {
    throw const FormatException(
      'Begründung: 1 bis 500 Zeichen ohne Steuerzeichen.',
    );
  }
  return normalized;
}

class TaskBlockingDto {
  const TaskBlockingDto({
    required this.id,
    required this.instanceId,
    this.stepId,
    required this.reason,
    required this.reportedAt,
    required this.reportedBy,
    required this.reportedVersion,
    this.resolution,
    this.resolutionKind,
    this.resolvedAt,
    this.resolvedBy,
    this.resolvedVersion,
    this.numericAttemptId,
  });
  final String id, instanceId, reason, reportedBy;
  final String? numericAttemptId;
  final String? stepId, resolution, resolvedBy, resolutionKind;
  final DateTime reportedAt;
  final DateTime? resolvedAt;
  final int reportedVersion;
  final int? resolvedVersion;
  factory TaskBlockingDto.fromJson(Map<String, dynamic> j) {
    final reported = j['reportedVersion'], resolved = j['resolvedVersion'];
    final at = shiftInstant(j['reportedAt']);
    final end = j['resolvedAt'] == null ? null : shiftInstant(j['resolvedAt']);
    final kind = j['resolutionKind'] ?? (end == null ? null : 'resumed');
    if ((end == null
            ? kind != null
            : !{'resumed', 'cancelled'}.contains(kind)) ||
        reported is! int ||
        reported < 3 ||
        (end == null
            ? j['resolution'] != null ||
                  j['resolvedBy'] != null ||
                  resolved != null
            : resolved is! int ||
                  resolved <= reported ||
                  end.isBefore(at) ||
                  j['resolvedBy'] == null ||
                  j['resolution'] == null)) {
      throw const FormatException('Ungültige Blockierung.');
    }
    return TaskBlockingDto(
      id: shiftUuid(j['id']),
      instanceId: shiftUuid(j['instanceId']),
      stepId: j['stepId'] == null ? null : shiftUuid(j['stepId']),
      reason: blockingReason(j['reason']),
      reportedAt: at,
      reportedBy: shiftUuid(j['reportedBy']),
      reportedVersion: reported,
      numericAttemptId: j['numericAttemptId'] == null
          ? null
          : shiftUuid(j['numericAttemptId']),
      resolutionKind: kind as String?,
      resolution: j['resolution'] == null
          ? null
          : blockingReason(j['resolution']),
      resolvedAt: end,
      resolvedBy: j['resolvedBy'] == null ? null : shiftUuid(j['resolvedBy']),
      resolvedVersion: resolved as int?,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'instanceId': instanceId,
    'stepId': stepId,
    'reason': reason,
    if (numericAttemptId != null) 'numericAttemptId': numericAttemptId,
    'reportedAt': reportedAt.toUtc().toIso8601String(),
    'reportedBy': reportedBy,
    'reportedVersion': reportedVersion,
    'resolution': resolution,
    if (resolutionKind != null) 'resolutionKind': resolutionKind,
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
    'resolvedBy': resolvedBy,
    'resolvedVersion': resolvedVersion,
  };
}
