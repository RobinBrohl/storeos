import 'dart:convert';

import '../config.dart';
import 'platform_database.dart';

void requireFields(
  Map<String, dynamic> input, {
  required Set<String> required,
  Set<String> optional = const {},
}) {
  if (!input.keys.toSet().containsAll(required) ||
      input.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const PlatformFailure(
      400,
      'invalid_request',
      'Invalid request fields.',
    );
  }
}

String requireUuid(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value is! String || !isUuid(value)) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid UUID.');
  }
  return value.toLowerCase();
}

int requireVersion(Map<String, dynamic> input) {
  final value = input['expectedVersion'];
  if (value is! int || value < 1 || value > 9223372036854775806) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid version.');
  }
  return value;
}

String requireName(Map<String, dynamic> input, String key) {
  final value = input[key];
  if (value is! String) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid name.');
  }
  final name = value.trim();
  if (name.isEmpty ||
      name.length > 120 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid name.');
  }
  return name;
}

String requireUsername(Map<String, dynamic> input) {
  final value = input['username'];
  if (value is! String || !RegExp(r'^[A-Za-z0-9._@-]{3,64}$').hasMatch(value)) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid username.');
  }
  return value;
}

String requirePassword(Map<String, dynamic> input) {
  final value = input['password'];
  if (value is! String ||
      utf8.encode(value).length < 12 ||
      utf8.encode(value).length > 1024) {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid password.');
  }
  return value;
}

String requireRole(Map<String, dynamic> input) {
  final value = input['role'];
  if (value != 'admin' && value != 'auditor' && value != 'viewer') {
    throw const PlatformFailure(400, 'invalid_request', 'Invalid role.');
  }
  return value as String;
}

bool requireActive(Map<String, dynamic> input) {
  final value = input['isActive'];
  if (value is! bool) {
    throw const PlatformFailure(
      400,
      'invalid_request',
      'Invalid active state.',
    );
  }
  return value;
}
