import 'dart:io';

import 'package:storeos_server/src/config.dart';
import 'package:test/test.dart';

const _base = <String, String>{
  'STOREOS_DB_NAME': 'storeos',
  'STOREOS_DB_USER': 'storeos',
  'STOREOS_DB_PASSWORD': 'runtime-secret',
  'STOREOS_COMPANY_ID': '11111111-1111-4111-8111-111111111111',
  'STOREOS_LOCATION_ID': '22222222-2222-4222-8222-222222222222',
};

void main() {
  test('HTTP ingress defaults, explicit host and valid bounds', () {
    final config = ServerConfig.fromEnvironment({
      ..._base,
      'STOREOS_HOST': '0.0.0.0',
    });
    expect(config.host, '0.0.0.0');
    final policy = config.httpIngress;
    expect([policy.connections, policy.requests, policy.bodies], [64, 32, 16]);
    expect(policy.bodyLifetime, const Duration(seconds: 30));
    expect(policy.discardWindow, const Duration(seconds: 1));
    expect(policy.idleTimeout, const Duration(seconds: 15));
    final custom = HttpIngressPolicy.fromEnvironment({
      'STOREOS_HTTP_MAX_CONNECTIONS': '3',
      'STOREOS_HTTP_MAX_REQUESTS': '2',
      'STOREOS_HTTP_MAX_BODIES': '1',
      'STOREOS_HTTP_BODY_SECONDS': '2',
      'STOREOS_HTTP_DISCARD_MILLISECONDS': '500',
      'STOREOS_HTTP_IDLE_SECONDS': '1',
    });
    expect([custom.connections, custom.requests, custom.bodies], [3, 2, 1]);
  });

  test(
    'HTTP ingress rejects invalid and inconsistent configuration fail closed',
    () {
      for (final bad in [
        {'STOREOS_HTTP_MAX_CONNECTIONS': '0'},
        {'STOREOS_HTTP_MAX_CONNECTIONS': '4097'},
        {'STOREOS_HTTP_MAX_REQUESTS': '-1'},
        {'STOREOS_HTTP_MAX_BODIES': 'NaN'},
        {'STOREOS_HTTP_BODY_SECONDS': 'Infinity'},
        {'STOREOS_HTTP_BODY_SECONDS': '301'},
        {'STOREOS_HTTP_DISCARD_MILLISECONDS': '0'},
        {'STOREOS_HTTP_DISCARD_MILLISECONDS': '30001'},
        {'STOREOS_HTTP_IDLE_SECONDS': '0'},
        {'STOREOS_HTTP_MAX_CONNECTIONS': '31'},
        {'STOREOS_HTTP_MAX_BODIES': '33'},
      ]) {
        expect(
          () => ServerConfig.fromEnvironment({..._base, ...bad}),
          throwsA(isA<ConfigurationException>()),
        );
      }
      expect(
        () => const HttpIngressPolicy(bodies: 0).validate(),
        throwsA(isA<ConfigurationException>()),
      );
      expect(
        () => const HttpIngressPolicy(bodyLifetime: Duration.zero).validate(),
        throwsA(isA<ConfigurationException>()),
      );
    },
  );

  test(
    'defaults bind to loopback and accept only explicit browser origins',
    () {
      final config = ServerConfig.fromEnvironment({
        ..._base,
        'STOREOS_ALLOWED_ORIGINS': 'https://example.org, http://localhost:3000',
      });
      expect(config.host, '127.0.0.1');
      expect(config.allowedOrigins, {
        'https://example.org',
        'http://localhost:3000',
      });
      expect(config.database.user, 'storeos');
    },
  );

  test(
    'rejects invalid tenant IDs, network settings and permissive origins',
    () {
      for (final bad in [
        {'STOREOS_COMPANY_ID': 'not-a-uuid'},
        {'STOREOS_PORT': '0'},
        {'STOREOS_SESSION_TTL_SECONDS': '1'},
        {'STOREOS_DB_SSL_MODE': 'unknown'},
        {'STOREOS_ALLOWED_ORIGINS': '*'},
        {'STOREOS_ALLOWED_ORIGINS': 'https://example.org/path'},
        {'STOREOS_ALLOWED_ORIGINS': 'https://example.org?token=secret'},
      ]) {
        expect(
          () => ServerConfig.fromEnvironment({..._base, ...bad}),
          throwsA(isA<ConfigurationException>()),
          reason: '$bad',
        );
      }
    },
  );

  test(
    'owner credentials and file secrets are selected without ambiguity',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'storeos_secrets_',
      );
      try {
        final file = File('${directory.path}/owner.txt');
        await file.writeAsString('owner-secret\n');
        final environment = {
          ..._base,
          'STOREOS_DB_MIGRATION_USER': 'storeos_owner',
          'STOREOS_DB_MIGRATION_PASSWORD_FILE': file.path,
        };
        final runtime = DatabaseConfig.fromEnvironment(environment);
        final migration = DatabaseConfig.fromEnvironment(
          environment,
          migrationCredentials: true,
        );
        expect(runtime.user, 'storeos');
        expect(runtime.password, 'runtime-secret');
        expect(migration.user, 'storeos_owner');
        expect(migration.password, 'owner-secret');
        expect(
          () =>
              DatabaseConfig.fromEnvironment(_base, migrationCredentials: true),
          throwsA(isA<ConfigurationException>()),
        );
        expect(
          () => DatabaseConfig.fromEnvironment({
            ...environment,
            'STOREOS_DB_MIGRATION_PASSWORD': 'conflicting-secret',
          }, migrationCredentials: true),
          throwsA(isA<ConfigurationException>()),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
