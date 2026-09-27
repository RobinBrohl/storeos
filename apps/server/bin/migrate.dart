import 'dart:io';

import 'package:postgres/postgres.dart';

import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/json_logger.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';

Future<void> main() async {
  const logger = JsonLogger();
  Connection? connection;
  try {
    final environment = Platform.environment;
    final config = DatabaseConfig.fromEnvironment(
      environment,
      migrationCredentials: true,
    );
    connection = await Connection.open(
      config.endpoint,
      settings: config.connectionSettings,
    );
    final versions = await MigrationRunner(
      connection: connection,
      migrationsDirectory: Directory.fromUri(
        Platform.script.resolve('../migrations/'),
      ),
      runtimeDatabaseUser: environment['STOREOS_DB_USER'],
    ).apply();
    logger.event('migrations_applied', fields: {'versions': versions});
  } catch (error) {
    logger.event(
      'migration_failed',
      level: 'error',
      fields: {
        'type': error.runtimeType.toString(),
        'message':
            error is MigrationException || error is ConfigurationException
            ? error.toString()
            : 'Database migration failed.',
      },
    );
    exitCode = 1;
  } finally {
    await connection?.close();
  }
}
