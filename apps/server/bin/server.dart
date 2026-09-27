import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/json_logger.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

Future<void> main() async {
  const logger = JsonLogger();
  Pool<void>? pool;
  HttpServer? server;
  EventBus? eventBus;
  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];
  try {
    final config = ServerConfig.fromEnvironment(Platform.environment);
    pool = Pool<void>.withEndpoints([
      config.database.endpoint,
    ], settings: config.database.poolSettings);
    final store = PostgresAuthStore(pool);
    final auth = await AuthService.create(
      store: store,
      companyId: config.companyId,
      locationId: config.locationId,
      sessionTtl: config.sessionTtl,
    );
    final database = PlatformDatabase(
      pool,
      companyId: config.companyId,
      locationId: config.locationId,
    );
    final app = ServerApp(
      config: config,
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, config.host, config.port);
    eventBus = EventBus(database: database)..start();
    logger.event(
      'server_started',
      fields: {'host': config.host, 'port': config.port},
    );
    final stop = Completer<void>();
    void onSignal(ProcessSignal _) {
      if (!stop.isCompleted) stop.complete();
    }

    signalSubscriptions.add(ProcessSignal.sigint.watch().listen(onSignal));
    if (!Platform.isWindows) {
      signalSubscriptions.add(ProcessSignal.sigterm.watch().listen(onSignal));
    }
    await stop.future;
    logger.event('server_stopping');
  } catch (error) {
    logger.event(
      'server_failed',
      level: 'error',
      fields: {
        'type': error.runtimeType.toString(),
        'message': error is ConfigurationException
            ? error.toString()
            : 'Server startup failed.',
      },
    );
    exitCode = 1;
  } finally {
    for (final subscription in signalSubscriptions) {
      await subscription.cancel();
    }
    await server?.close(force: false);
    await eventBus?.stop();
    await pool?.close();
  }
}
