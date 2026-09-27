// Isolated, opt-in browser fixture. Never point STOREOS_TEST_DATABASE at live data.
import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

Future<void> main() async {
  final uri = Uri.parse(Platform.environment['STOREOS_TEST_DATABASE'] ?? '');
  final runtimePassword = Platform.environment['STOREOS_TEST_RUNTIME_PASSWORD'];
  final smokePassword = Platform.environment['STOREOS_SMOKE_PASSWORD'];
  if (!['postgres', 'postgresql'].contains(uri.scheme) ||
      uri.pathSegments.length != 1 ||
      !uri.pathSegments.single.endsWith('_test') ||
      runtimePassword == null ||
      smokePassword == null) {
    throw ArgumentError(
      'Requires STOREOS_TEST_DATABASE (database ending _test), '
      'STOREOS_TEST_RUNTIME_PASSWORD and STOREOS_SMOKE_PASSWORD.',
    );
  }
  final separator = uri.userInfo.indexOf(':');
  if (separator < 1) {
    throw ArgumentError('Test owner credentials are required.');
  }
  final ownerEndpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.single,
    username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
    password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
  );
  final databaseConfig = DatabaseConfig(
    host: ownerEndpoint.host,
    port: ownerEndpoint.port,
    name: ownerEndpoint.database,
    user: Platform.environment['STOREOS_TEST_RUNTIME_USER'] ?? 'storeos',
    password: runtimePassword,
  );
  final schema = 'storeos_browser_${newUuid().replaceAll('-', '')}';
  final companyId = newUuid();
  final locationId = newUuid();
  final owner = await Connection.open(
    ownerEndpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final pool = Pool<void>.withEndpoints([
    databaseConfig.endpoint,
  ], settings: databaseConfig.poolSettings);
  HttpServer? server;
  EventBus? bus;
  final signals = <StreamSubscription<ProcessSignal>>[];
  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: databaseConfig.user,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(),
      schemaName: schema,
    ).bootstrap(
      username: 'smoke_admin',
      password: smokePassword,
      companyId: companyId,
      locationId: locationId,
    );
    final config = ServerConfig(
      database: databaseConfig,
      companyId: companyId,
      locationId: locationId,
      allowedOrigins: const {'http://127.0.0.1:8085', 'http://localhost:8085'},
    );
    final store = PostgresAuthStore(pool, schemaName: schema);
    final auth = await AuthService.create(
      store: store,
      companyId: companyId,
      locationId: locationId,
      sessionTtl: const Duration(hours: 1),
    );
    final database = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: companyId,
      locationId: locationId,
    );
    final app = ServerApp(
      config: config,
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 8080);
    bus = EventBus(database: database)..start();
    stdout.writeln(
      'Isolated browser smoke API: http://127.0.0.1:8080; user smoke_admin. Ctrl+C removes fixture schema.',
    );
    final stop = Completer<void>();
    void finish(ProcessSignal _) {
      if (!stop.isCompleted) stop.complete();
    }

    signals.add(ProcessSignal.sigint.watch().listen(finish));
    if (!Platform.isWindows) {
      signals.add(ProcessSignal.sigterm.watch().listen(finish));
    }
    await stop.future;
  } finally {
    for (final signal in signals) {
      await signal.cancel();
    }
    await server?.close(force: true);
    await bus?.stop();
    await pool.close();
    // The name is generated here, never supplied by the caller.
    await owner.execute('DROP SCHEMA IF EXISTS "$schema" CASCADE');
    await owner.close();
  }
}
