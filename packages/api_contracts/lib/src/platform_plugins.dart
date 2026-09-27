/// The supported P1 external-client manifest. This is data, never executable code.
const supportedPluginPermissions = <String>{'organization.read', 'events.read'};

const supportedPluginSubscriptions = <String>{
  'organization.company.updated',
  'organization.location.created',
  'organization.location.updated',
};

final _pluginId = RegExp(r'^[a-z][a-z0-9._-]{2,63}$');
final _semver = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');

class PluginManifest {
  PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.vendor,
    required this.capabilities,
    required this.permissions,
    required this.subscriptions,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    const keys = {
      'id',
      'name',
      'version',
      'vendor',
      'coreApiVersion',
      'capabilities',
      'permissions',
      'subscriptions',
      'configurationSchema',
    };
    if (json.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Unsupported plugin manifest fields.');
    }
    final id = _boundedString(json, 'id', 64);
    final name = _boundedString(json, 'name', 100);
    final version = _boundedString(json, 'version', 32);
    final vendor = _boundedString(json, 'vendor', 100);
    if (!_pluginId.hasMatch(id) || !_semver.hasMatch(version)) {
      throw const FormatException('Invalid plugin id or version.');
    }
    if (json['coreApiVersion'] != 1) {
      throw const FormatException('Unsupported core API version.');
    }
    final capabilities = _strings(
      json,
      'capabilities',
      supportedPluginPermissions,
    );
    final permissions = _strings(
      json,
      'permissions',
      supportedPluginPermissions,
    );
    final subscriptions = _strings(
      json,
      'subscriptions',
      supportedPluginSubscriptions,
    );
    if (!capabilities.toSet().containsAll(permissions) ||
        (subscriptions.isNotEmpty && !permissions.contains('events.read'))) {
      throw const FormatException(
        'Plugin subscriptions or permissions mismatch.',
      );
    }
    final schema = json['configurationSchema'];
    if (schema is! Map<String, dynamic> ||
        schema.length != 3 ||
        schema['type'] != 'object' ||
        schema['additionalProperties'] != false ||
        schema['properties'] is! Map<String, dynamic> ||
        (schema['properties'] as Map<String, dynamic>).isNotEmpty) {
      throw const FormatException('Only an empty configuration is supported.');
    }
    return PluginManifest(
      id: id,
      name: name,
      version: version,
      vendor: vendor,
      capabilities: capabilities,
      permissions: permissions,
      subscriptions: subscriptions,
    );
  }

  final String id;
  final String name;
  final String version;
  final String vendor;
  final List<String> capabilities;
  final List<String> permissions;
  final List<String> subscriptions;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'version': version,
    'vendor': vendor,
    'coreApiVersion': 1,
    'capabilities': capabilities,
    'permissions': permissions,
    'subscriptions': subscriptions,
    'configurationSchema': {
      'type': 'object',
      'properties': <String, dynamic>{},
      'additionalProperties': false,
    },
  };
}

String _boundedString(Map<String, dynamic> json, String key, int maxLength) {
  final value = json[key];
  if (value is! String ||
      value.trim() != value ||
      value.isEmpty ||
      value.length > maxLength ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw FormatException('Invalid $key.');
  }
  return value;
}

List<String> _strings(
  Map<String, dynamic> json,
  String key,
  Set<String> allowed,
) {
  final value = json[key];
  if (value is! List || value.length > allowed.length) {
    throw FormatException('Invalid $key.');
  }
  final strings = <String>[];
  for (final item in value) {
    if (item is! String || !allowed.contains(item) || strings.contains(item)) {
      throw FormatException('Invalid $key.');
    }
    strings.add(item);
  }
  return List.unmodifiable(strings);
}
