import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart'
    show newUuid;
import 'package:test/test.dart';

import '../tool/capacity_fixture.dart';

/// Real-PostgreSQL smoke of the capacity harness: isolated run database, real
/// HTTP API, bounded concurrent workers, owner-side integrity verification and
/// drop of the run database. No performance threshold is asserted.
void main() {
  final url = Platform.environment['STOREOS_TEST_DATABASE'];
  final runtimeUser = Platform.environment['STOREOS_DB_USER'];
  final runtimePasswordFile = Platform.environment['STOREOS_DB_PASSWORD_FILE'];
  final String? skipReason = url == null
      ? 'STOREOS_TEST_DATABASE is not set'
      : runtimeUser == null ||
            runtimePasswordFile == null ||
            !File(runtimePasswordFile).existsSync()
      ? 'STOREOS_DB_USER or STOREOS_DB_PASSWORD_FILE is not configured'
      : null;

  test(
    'capacity smoke: integrity holds and corrupted expectations fail',
    () async {
      final databaseUrl = url;
      final role = runtimeUser;
      final passwordPath = runtimePasswordFile;
      if (databaseUrl == null || role == null || passwordPath == null) {
        markTestSkipped(skipReason ?? 'capacity smoke prerequisites missing');
        return;
      }
      if (!RegExp(r'^[a-z_][a-z0-9_]{0,62}$').hasMatch(role)) {
        markTestSkipped('STOREOS_DB_USER is not a valid role name');
        return;
      }
      final uri = Uri.parse(databaseUrl);
      final userInfo = uri.userInfo.split(':');
      final ownerUser = Uri.decodeComponent(userInfo.first);
      final ownerPassword = Uri.decodeComponent(userInfo.sublist(1).join(':'));
      final endpoint = Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.single,
        username: ownerUser,
        password: ownerPassword,
      );
      final runtimePassword = File(passwordPath).readAsStringSync().trim();
      final database =
          'storeos_capacity_${newUuid().replaceAll('-', '').substring(0, 16)}';
      final owner = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      var created = false;
      try {
        try {
          await owner.execute('CREATE DATABASE "$database"');
        } on ServerException catch (error) {
          if (error.code == '42501') {
            markTestSkipped(
              'The test database owner may not create databases; '
              'remote CI covers this path.',
            );
            return;
          }
          rethrow;
        }
        created = true;
        await owner.execute('GRANT CONNECT ON DATABASE "$database" TO "$role"');
        final config = CapacityHarnessConfig(
          profile: CapacityProfile(
            name: 'smoke',
            employees: 2,
            workers: 2,
            tasksPerEmployee: 2,
            readIterations: 1,
          ),
          databaseHost: endpoint.host,
          databasePort: endpoint.port,
          databaseName: database,
          ownerUser: ownerUser,
          ownerPassword: ownerPassword,
          runtimeUser: role,
          runtimePassword: runtimePassword,
          apiPort: 0,
        );
        final measurement = await runCapacityMeasurement(config);
        expect(
          measurement.integrity.passed,
          isTrue,
          reason: measurement.integrity.detail,
        );
        expect(measurement.read['requests'], 7);
        expect(measurement.read['errors'], 0);
        expect(measurement.write['requests'], 16);
        expect(measurement.write['errors'], 0);
        expect(measurement.integrity.expected, measurement.integrity.observed);
        expect(measurement.integrity.observed['task_instances'], 4);
        expect(measurement.integrity.observed['task_execution_commands'], 16);
        expect(measurement.integrity.observed['audit_read'], 1);
        expect(measurement.environment['postgresVersion'], isA<String>());

        // A corrupted expectation must fail against the real database, not by
        // an artificial exception before the verifier.
        final capacityOwner = await Connection.open(
          Endpoint(
            host: endpoint.host,
            port: endpoint.port,
            database: database,
            username: ownerUser,
            password: ownerPassword,
          ),
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        try {
          final corrupted = await verifyCapacityIntegrity(
            capacityOwner,
            profile: config.profile,
            injectIntegrityMismatch: true,
          );
          expect(corrupted.passed, isFalse);
          expect(corrupted.detail, isNotNull);
          expect(corrupted.detail, contains('task_instances'));
        } finally {
          await capacityOwner.close(force: true);
        }
      } finally {
        if (created) {
          await owner.execute(
            'DROP DATABASE IF EXISTS "$database" WITH (FORCE)',
          );
        }
        final remaining = await owner.execute(
          Sql.named(
            'SELECT count(*)::int FROM pg_database WHERE datname = @name',
          ),
          parameters: {'name': database},
        );
        expect(remaining.single.single, 0);
        await owner.close();
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
