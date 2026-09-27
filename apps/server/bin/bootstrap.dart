import 'dart:io';

import 'package:postgres/postgres.dart';

import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/json_logger.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';

Future<void> main() async {
  const logger = JsonLogger();
  Connection? connection;
  try {
    final environment = Platform.environment;
    final ownerDatabase = DatabaseConfig.fromEnvironment(
      environment,
      migrationCredentials: true,
    );
    final companyId = environment['STOREOS_COMPANY_ID'];
    final locationId = environment['STOREOS_LOCATION_ID'];
    if (companyId == null ||
        locationId == null ||
        !isUuid(companyId) ||
        !isUuid(locationId)) {
      throw ConfigurationException(
        'STOREOS_COMPANY_ID and STOREOS_LOCATION_ID must be UUIDs.',
      );
    }
    final username = environment['STOREOS_BOOTSTRAP_USERNAME'];
    if (username == null || username.isEmpty) {
      throw ConfigurationException('STOREOS_BOOTSTRAP_USERNAME is required.');
    }
    final password = readFileSecret(environment, 'STOREOS_BOOTSTRAP_PASSWORD');
    connection = await Connection.open(
      ownerDatabase.endpoint,
      settings: ownerDatabase.connectionSettings,
    );
    final id =
        await BootstrapService(
          connection: connection,
          passwordHasher: PasswordHasher(),
        ).bootstrap(
          username: username,
          password: password,
          companyId: companyId.toLowerCase(),
          locationId: locationId.toLowerCase(),
        );
    logger.event('bootstrap_complete', fields: {'accountId': id});
  } catch (error) {
    logger.event(
      'bootstrap_failed',
      level: 'error',
      fields: {
        'type': error.runtimeType.toString(),
        'message':
            error is BootstrapException || error is ConfigurationException
            ? error.toString()
            : 'Bootstrap failed.',
      },
    );
    exitCode = 1;
  } finally {
    await connection?.close();
  }
}
