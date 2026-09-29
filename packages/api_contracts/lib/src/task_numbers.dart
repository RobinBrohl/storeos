import 'shifts.dart';

/// Exact decimal wire format. No floating point arithmetic or rounding.
int taskNumber(Object? value) {
  if (value is! String ||
      RegExp(r'[^0-9.\-]').hasMatch(value) ||
      !RegExp(r'^-?[0-9]{1,6}(\.[0-9]{1,3})?$').hasMatch(value)) {
    throw const FormatException('Zahl: maximal 6 Vor- und 3 Nachkommastellen.');
  }
  final parts = value.replaceFirst('-', '').split('.');
  final scaled =
      int.parse(parts[0]) * 1000 +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
  return value.startsWith('-') ? -scaled : scaled;
}

String taskNumberText(int scaled) {
  if (scaled.abs() > 999999999) {
    throw const FormatException('Zahl außerhalb des Formats.');
  }
  final absolute = scaled.abs();
  final fraction = (absolute % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${scaled < 0 ? '-' : ''}${absolute ~/ 1000}${fraction.isEmpty ? '' : '.$fraction'}';
}

class TaskNumericAttemptDto {
  const TaskNumericAttemptDto({
    required this.id,
    required this.instanceId,
    required this.stepId,
    required this.value,
    required this.inRange,
    required this.recordedAt,
    required this.recordedBy,
    required this.acceptedVersion,
  });
  final String id, instanceId, stepId, value, recordedBy;
  final bool inRange;
  final DateTime recordedAt;
  final int acceptedVersion;
  factory TaskNumericAttemptDto.fromJson(Map<String, dynamic> j) {
    if (j['inRange'] is! bool ||
        j['acceptedVersion'] is! int ||
        (j['acceptedVersion'] as int) < 3) {
      throw const FormatException('Ungültiger Zahlenversuch.');
    }
    return TaskNumericAttemptDto(
      id: shiftUuid(j['id']),
      instanceId: shiftUuid(j['instanceId']),
      stepId: shiftUuid(j['stepId']),
      value: taskNumberText(taskNumber(j['value'])),
      inRange: j['inRange'] as bool,
      recordedAt: shiftInstant(j['recordedAt']),
      recordedBy: shiftUuid(j['recordedBy']),
      acceptedVersion: j['acceptedVersion'] as int,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'instanceId': instanceId,
    'stepId': stepId,
    'value': value,
    'inRange': inRange,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'recordedBy': recordedBy,
    'acceptedVersion': acceptedVersion,
  };
}
