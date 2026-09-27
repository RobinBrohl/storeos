import 'dart:convert';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> manifest() => {
  'id': 'test.organization',
  'name': 'Organization reader',
  'version': '1.0.0',
  'vendor': 'Test',
  'coreApiVersion': 1,
  'capabilities': ['organization.read', 'events.read'],
  'permissions': ['organization.read', 'events.read'],
  'subscriptions': ['organization.location.updated'],
  'configurationSchema': {
    'type': 'object',
    'properties': <String, dynamic>{},
    'additionalProperties': false,
  },
};

void main() {
  test('manifest names and vendors reject embedded control characters', () {
    for (final key in ['name', 'vendor']) {
      for (final control in ['\u0000', '\n', '\t', '\u007f']) {
        expect(
          () => PluginManifest.fromJson({
            ...manifest(),
            key: 'value${control}value',
          }),
          throwsFormatException,
        );
      }
    }
  });
  test('unconfigured organization names survive JSON transport', () {
    final original = OrganizationResponse(
      company: const CompanyDto(id: 'company', name: null, version: 1),
      locations: const [
        LocationDto(
          id: 'location',
          companyId: 'company',
          name: null,
          version: 1,
        ),
      ],
    );
    final restored = OrganizationResponse.fromJson(
      jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
    );
    expect(restored.company.name, isNull);
    expect(restored.locations.single.companyId, 'company');
    expect(restored.toJson(), original.toJson());
  });

  test('user DTO excludes authentication secrets and carries current role', () {
    final user = PlatformUserDto.fromJson({
      'id': 'user',
      'username': 'operator',
      'companyId': 'company',
      'locationId': 'location',
      'role': 'admin',
      'isActive': true,
      'version': 4,
      'passwordHash': 'never transport this field',
    });
    expect(user.toJson().containsKey('passwordHash'), isFalse);
    expect(user.toJson()['version'], 4);
    expect(user.role, 'admin');
  });

  test(
    'supported manifest round trips without executable or secret fields',
    () {
      expect(PluginManifest.fromJson(manifest()).toJson(), manifest());
    },
  );

  test('unknown capabilities, subscriptions, code and secrets fail closed', () {
    for (final change in <Map<String, dynamic>>[
      {
        'permissions': ['identity.write'],
      },
      {
        'subscriptions': ['identity.user.created'],
      },
      {'entrypoint': 'untrusted.dart'},
      {'token': 'do-not-store-secrets'},
      {'coreApiVersion': 2},
      {
        'configurationSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'additionalProperties': true,
        },
      },
    ]) {
      expect(
        () => PluginManifest.fromJson({...manifest(), ...change}),
        throwsFormatException,
      );
    }
  });

  test(
    'subscriptions require events permission and all permissions capabilities',
    () {
      expect(
        () => PluginManifest.fromJson({
          ...manifest(),
          'permissions': ['organization.read'],
        }),
        throwsFormatException,
      );
      expect(
        () => PluginManifest.fromJson({
          ...manifest(),
          'capabilities': ['organization.read'],
        }),
        throwsFormatException,
      );
      expect(
        () => PluginManifest.fromJson({
          ...manifest(),
          'permissions': ['events.read', 'events.read'],
        }),
        throwsFormatException,
      );
    },
  );
}
