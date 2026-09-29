/// Public, JSON-serializable API v1 contracts. No database or domain models.
library;

export 'src/task_execution.dart';
export 'src/task_numbers.dart';

export 'src/shifts.dart';

export 'src/platform_identity.dart';
export 'src/employees.dart';
export 'src/task_templates.dart';
export 'src/platform_plugins.dart';

class HealthResponse {
  const HealthResponse({required this.status});

  factory HealthResponse.fromJson(Map<String, dynamic> json) =>
      HealthResponse(status: _string(json, 'status'));

  final String status;
  Map<String, dynamic> toJson() => {'status': status};
}

class LoginRequest {
  const LoginRequest({required this.username, required this.password});

  factory LoginRequest.fromJson(Map<String, dynamic> json) => LoginRequest(
    username: _string(json, 'username'),
    password: _string(json, 'password'),
  );

  final String username;
  final String password;
  Map<String, dynamic> toJson() => {'username': username, 'password': password};
}

class SessionUser {
  const SessionUser({
    required this.id,
    required this.username,
    required this.companyId,
    required this.locationId,
  });

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
    id: _string(json, 'id'),
    username: _string(json, 'username'),
    companyId: _string(json, 'companyId'),
    locationId: _string(json, 'locationId'),
  );

  final String id;
  final String username;
  final String companyId;
  final String locationId;
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'companyId': companyId,
    'locationId': locationId,
  };
}

class SessionResponse {
  const SessionResponse({
    required this.token,
    required this.expiresAt,
    required this.user,
  });

  factory SessionResponse.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(_string(json, 'expiresAt'));
    final user = json['user'];
    if (expiresAt == null ||
        !expiresAt.isUtc ||
        user is! Map<String, dynamic>) {
      throw const FormatException('Invalid session response.');
    }
    return SessionResponse(
      token: _string(json, 'token'),
      expiresAt: expiresAt,
      user: SessionUser.fromJson(user),
    );
  }

  final String token;
  final DateTime expiresAt;
  final SessionUser user;
  Map<String, dynamic> toJson() => {
    'token': token,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'user': user.toJson(),
  };
}

class SystemStatusResponse {
  const SystemStatusResponse({
    required this.companyId,
    required this.locationId,
    this.service = 'storeos',
    this.apiVersion = 1,
    this.database = 'reachable',
  });

  factory SystemStatusResponse.fromJson(Map<String, dynamic> json) {
    if (json['apiVersion'] is! int) {
      throw const FormatException('apiVersion must be an integer.');
    }
    return SystemStatusResponse(
      companyId: _string(json, 'companyId'),
      locationId: _string(json, 'locationId'),
      service: _string(json, 'service'),
      apiVersion: json['apiVersion'] as int,
      database: _string(json, 'database'),
    );
  }

  final String service;
  final int apiVersion;
  final String companyId;
  final String locationId;
  final String database;
  Map<String, dynamic> toJson() => {
    'service': service,
    'apiVersion': apiVersion,
    'companyId': companyId,
    'locationId': locationId,
    'database': database,
  };
}

class ApiError {
  const ApiError({required this.code, required this.message});

  factory ApiError.fromJson(Map<String, dynamic> json) =>
      ApiError(code: _string(json, 'code'), message: _string(json, 'message'));

  final String code;
  final String message;
  Map<String, dynamic> toJson() => {'code': code, 'message': message};
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string.');
  }
  return value;
}
