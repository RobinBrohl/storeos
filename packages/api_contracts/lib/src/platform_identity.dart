/// JSON contracts for the P1 organization and identity API.
library;

import 'dart:convert';

class CompanyDto {
  const CompanyDto({
    required this.id,
    required this.name,
    required this.version,
  });

  factory CompanyDto.fromJson(Map<String, dynamic> json) => CompanyDto(
    id: _string(json, 'id'),
    name: _nullableString(json, 'name'),
    version: _integer(json, 'version'),
  );

  final String id;
  final String? name;
  final int version;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'version': version};
}

class LocationDto {
  const LocationDto({
    required this.id,
    required this.companyId,
    required this.name,
    required this.version,
  });

  factory LocationDto.fromJson(Map<String, dynamic> json) => LocationDto(
    id: _string(json, 'id'),
    companyId: _string(json, 'companyId'),
    name: _nullableString(json, 'name'),
    version: _integer(json, 'version'),
  );

  final String id;
  final String companyId;
  final String? name;
  final int version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'name': name,
    'version': version,
  };
}

class OrganizationResponse {
  const OrganizationResponse({required this.company, required this.locations});

  factory OrganizationResponse.fromJson(Map<String, dynamic> json) =>
      OrganizationResponse(
        company: CompanyDto.fromJson(_object(json, 'company')),
        locations: _objects(
          json,
          'locations',
        ).map(LocationDto.fromJson).toList(),
      );

  final CompanyDto company;
  final List<LocationDto> locations;

  Map<String, dynamic> toJson() => {
    'company': company.toJson(),
    'locations': locations.map((location) => location.toJson()).toList(),
  };
}

class PlatformUserDto {
  const PlatformUserDto({
    required this.id,
    required this.username,
    required this.companyId,
    required this.locationId,
    required this.role,
    required this.isActive,
    required this.version,
  });

  factory PlatformUserDto.fromJson(Map<String, dynamic> json) =>
      PlatformUserDto(
        id: _string(json, 'id'),
        username: _string(json, 'username'),
        companyId: _string(json, 'companyId'),
        locationId: _string(json, 'locationId'),
        role: _string(json, 'role'),
        isActive: _boolean(json, 'isActive'),
        version: _integer(json, 'version'),
      );

  final String id;
  final String username;
  final String companyId;
  final String locationId;
  final String role;
  final bool isActive;
  final int version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'companyId': companyId,
    'locationId': locationId,
    'role': role,
    'isActive': isActive,
    'version': version,
  };
}

class UsersResponse {
  const UsersResponse({required this.users});

  factory UsersResponse.fromJson(Map<String, dynamic> json) => UsersResponse(
    users: _objects(json, 'users').map(PlatformUserDto.fromJson).toList(),
  );

  final List<PlatformUserDto> users;

  Map<String, dynamic> toJson() => {
    'users': users.map((user) => user.toJson()).toList(),
  };
}

class PlatformContextResponse {
  const PlatformContextResponse({
    required this.userId,
    required this.companyId,
    required this.locationId,
    required this.role,
    required this.permissions,
  });

  factory PlatformContextResponse.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'];
    if (permissions is! List || permissions.any((item) => item is! String)) {
      throw const FormatException('permissions must be strings.');
    }
    return PlatformContextResponse(
      userId: _string(json, 'userId'),
      companyId: _string(json, 'companyId'),
      locationId: _string(json, 'locationId'),
      role: _string(json, 'role'),
      permissions: permissions.cast<String>(),
    );
  }

  final String userId;
  final String companyId;
  final String locationId;
  final String role;
  final List<String> permissions;

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'companyId': companyId,
    'locationId': locationId,
    'role': role,
    'permissions': permissions,
  };
}

/// Minimum UTF-8 byte length of a new password accepted by StoreOS.
const int passwordMinUtf8Bytes = 12;

/// Maximum UTF-8 byte length accepted for current and new passwords.
const int passwordMaxUtf8Bytes = 1024;

/// Byte length of [value] under the password policy.
///
/// Deliberately counts UTF-8 bytes, not UTF-16 units, code points or
/// grapheme clusters.
int passwordUtf8ByteLength(String value) => utf8.encode(value).length;

/// Returns a static, value-free problem description for a current password.
String? currentPasswordProblem(String value) {
  final bytes = passwordUtf8ByteLength(value);
  if (bytes == 0 || bytes > passwordMaxUtf8Bytes) {
    return 'Current password must be 1 to $passwordMaxUtf8Bytes UTF-8 bytes.';
  }
  return null;
}

/// Returns a static, value-free problem description for a new password.
String? newPasswordProblem(String value) {
  final bytes = passwordUtf8ByteLength(value);
  if (bytes < passwordMinUtf8Bytes || bytes > passwordMaxUtf8Bytes) {
    return 'New password must be $passwordMinUtf8Bytes to '
        '$passwordMaxUtf8Bytes UTF-8 bytes.';
  }
  return null;
}

/// Returns a static, value-free problem description for a password change.
String? changePasswordProblem(ChangePasswordRequest request) {
  final current = currentPasswordProblem(request.currentPassword);
  if (current != null) return current;
  final replacement = newPasswordProblem(request.newPassword);
  if (replacement != null) return replacement;
  if (request.currentPassword == request.newPassword) {
    return 'New password must differ from the current password.';
  }
  return null;
}

/// Self-service password-change request.
///
/// Accepts exactly `currentPassword` and `newPassword`; no account identifier
/// or expected version is part of the contract. It intentionally has no
/// `toString` override so plaintext is never rendered into logs or diagnostics.
class ChangePasswordRequest {
  const ChangePasswordRequest({
    required this.currentPassword,
    required this.newPassword,
  });

  factory ChangePasswordRequest.fromJson(Map<String, dynamic> json) {
    if (json.keys.toSet().difference(const {
          'currentPassword',
          'newPassword',
        }).isNotEmpty ||
        !json.containsKey('currentPassword') ||
        !json.containsKey('newPassword')) {
      throw const FormatException('Unsupported change-password fields.');
    }
    return ChangePasswordRequest(
      currentPassword: _string(json, 'currentPassword'),
      newPassword: _string(json, 'newPassword'),
    );
  }

  final String currentPassword;
  final String newPassword;

  Map<String, dynamic> toJson() => {
    'currentPassword': currentPassword,
    'newPassword': newPassword,
  };
}

String _string(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string.');
  return value;
}

String? _nullableString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value != null && value is! String) {
    throw FormatException('$key must be a string or null.');
  }
  return value as String?;
}

int _integer(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

bool _boolean(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

Map<String, dynamic> _object(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! Map<String, dynamic>) {
    throw FormatException('$key must be an object.');
  }
  return value;
}

List<Map<String, dynamic>> _objects(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! Map<String, dynamic>)) {
    throw FormatException('$key must be a list of objects.');
  }
  return value.cast<Map<String, dynamic>>();
}
