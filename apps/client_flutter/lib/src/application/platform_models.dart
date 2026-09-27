import 'dart:convert';

import 'package:storeos_api_contracts/api_contracts.dart';

// UI/application aliases keep the public transport DTOs as the single parser.
typedef PlatformContext = PlatformContextResponse;
typedef CompanyRecord = CompanyDto;
typedef LocationRecord = LocationDto;
typedef OrganizationSnapshot = OrganizationResponse;
typedef PlatformUser = PlatformUserDto;

extension PlatformPermissions on PlatformContextResponse {
  bool allows(String permission) => permissions.contains(permission);
}

extension OrganizationSetupState on OrganizationResponse {
  bool get needsSetup =>
      company.name == null ||
      locations.any((location) => location.name == null);
}

Map<String, dynamic> objectOf(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  throw FormatException('$label muss ein JSON-Objekt sein.');
}

List<Map<String, dynamic>> objectsOf(Object? value, String label) {
  if (value is! List) throw FormatException('$label muss eine Liste sein.');
  return value.map((item) => objectOf(item, label)).toList(growable: false);
}

String stringOf(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('$key muss Text sein.');
}

String? nullableStringOf(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null || value is String) return value as String?;
  throw FormatException('$key muss Text oder null sein.');
}

int intOf(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException('$key muss eine ganze Zahl sein.');
}

List<String> stringsOf(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('$key muss eine Textliste sein.');
  }
  return value.cast<String>();
}

class CursorPage {
  const CursorPage({required this.items, required this.nextCursor});

  factory CursorPage.fromJson(Map<String, dynamic> json) => CursorPage(
    items: objectsOf(json['items'], 'items'),
    nextCursor: nullableStringOf(json, 'nextCursor'),
  );

  final List<Map<String, dynamic>> items;
  final String? nextCursor;
}

class PluginRecord {
  const PluginRecord({
    required this.id,
    required this.manifest,
    required this.status,
    required this.version,
    required this.locationId,
    required this.permissions,
    required this.subscriptions,
    required this.tokenExpiresAt,
  });

  factory PluginRecord.fromJson(Map<String, dynamic> json) => PluginRecord(
    id: stringOf(json, 'id'),
    manifest: PluginManifest.fromJson(
      objectOf(json['manifest'], 'manifest'),
    ).toJson(),
    status: stringOf(json, 'status'),
    version: intOf(json, 'version'),
    locationId: nullableStringOf(json, 'locationId'),
    permissions: stringsOf(json, 'permissions'),
    subscriptions: stringsOf(json, 'subscriptions'),
    tokenExpiresAt: nullableStringOf(json, 'tokenExpiresAt'),
  );

  final String id;
  final Map<String, dynamic> manifest;
  final String status;
  final int version;
  final String? locationId;
  final List<String> permissions;
  final List<String> subscriptions;
  final String? tokenExpiresAt;

  String get displayName =>
      manifest['name'] is String ? manifest['name'] as String : id;
  List<String> get requestedPermissions => stringsOf(manifest, 'permissions');
  List<String> get requestedSubscriptions =>
      stringsOf(manifest, 'subscriptions');
}

class PluginApproval {
  const PluginApproval({required this.token, required this.tokenExpiresAt});

  factory PluginApproval.fromJson(Map<String, dynamic> json) => PluginApproval(
    token: stringOf(json, 'token'),
    tokenExpiresAt: stringOf(json, 'expiresAt'),
  );

  final String token;
  final String tokenExpiresAt;
}

Map<String, dynamic> parseManifest(String source) {
  final value = jsonDecode(source);
  final manifest = objectOf(value, 'Manifest');
  try {
    return PluginManifest.fromJson(manifest).toJson();
  } on FormatException {
    throw const FormatException(
      'Das Manifest entspricht nicht dem unterstützten Plugin-API-Vertrag.',
    );
  }
}
