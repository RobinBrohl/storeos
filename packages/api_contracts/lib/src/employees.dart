/// Minimal operational employee and identity-link wire contracts.
class EmployeeDto {
  const EmployeeDto({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.displayName,
    required this.isActive,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.assignedFrom,
    required this.assignedUntil,
  });

  factory EmployeeDto.fromJson(Map<String, dynamic> json) {
    if (json['isActive'] is! bool ||
        json['version'] is! int ||
        (json['version'] as int) < 1) {
      throw const FormatException('Invalid employee state.');
    }
    final active = json['isActive'] as bool;
    final from = _time(json, 'assignedFrom');
    final until = json['assignedUntil'] == null
        ? null
        : _time(json, 'assignedUntil');
    if (active != (until == null) || (until != null && until.isBefore(from))) {
      throw const FormatException('Invalid assignment interval.');
    }
    return EmployeeDto(
      id: _text(json, 'id'),
      companyId: _text(json, 'companyId'),
      locationId: _text(json, 'locationId'),
      displayName: _text(json, 'displayName'),
      isActive: active,
      version: json['version'] as int,
      createdAt: _time(json, 'createdAt'),
      updatedAt: _time(json, 'updatedAt'),
      assignedFrom: from,
      assignedUntil: until,
    );
  }

  final String id, companyId, locationId, displayName;
  final bool isActive;
  final int version;
  final DateTime createdAt, updatedAt, assignedFrom;
  final DateTime? assignedUntil;

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'locationId': locationId,
    'displayName': displayName,
    'isActive': isActive,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'assignedFrom': assignedFrom.toUtc().toIso8601String(),
    'assignedUntil': assignedUntil?.toUtc().toIso8601String(),
  };
}

class EmployeeLinkDto {
  const EmployeeLinkDto({
    required this.id,
    required this.accountId,
    required this.employeeId,
    required this.companyId,
    required this.locationId,
    required this.version,
    required this.linkedAt,
    required this.revokedAt,
  });

  factory EmployeeLinkDto.fromJson(Map<String, dynamic> json) {
    if (json['version'] is! int || (json['version'] as int) < 1) {
      throw const FormatException('Invalid link version.');
    }
    return EmployeeLinkDto(
      id: _text(json, 'id'),
      accountId: _text(json, 'accountId'),
      employeeId: _text(json, 'employeeId'),
      companyId: _text(json, 'companyId'),
      locationId: _text(json, 'locationId'),
      version: json['version'] as int,
      linkedAt: _time(json, 'linkedAt'),
      revokedAt: json['revokedAt'] == null ? null : _time(json, 'revokedAt'),
    );
  }

  final String id, accountId, employeeId, companyId, locationId;
  final int version;
  final DateTime linkedAt;
  final DateTime? revokedAt;
  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'employeeId': employeeId,
    'companyId': companyId,
    'locationId': locationId,
    'version': version,
    'linkedAt': linkedAt.toUtc().toIso8601String(),
    'revokedAt': revokedAt?.toUtc().toIso8601String(),
  };
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) throw FormatException('Invalid $key.');
  return value;
}

DateTime _time(Map<String, dynamic> json, String key) {
  final time = DateTime.tryParse(_text(json, key));
  if (time == null || !time.isUtc) throw FormatException('Invalid $key.');
  return time;
}
