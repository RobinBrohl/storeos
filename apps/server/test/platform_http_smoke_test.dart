import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/json_logger.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

final _databaseUrl = Platform.environment['STOREOS_TEST_DATABASE'];
const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
const _password = 'smoke-test-only-password-strong';

void main() {
  test(
    'HTTP smoke: organization, identities, RBAC, audit and plugin delivery',
    () async {
      final uri = Uri.parse(_databaseUrl!);
      final userInfo = uri.userInfo.split(':');
      final endpoint = Endpoint(
        host: uri.host,
        port: uri.hasPort ? uri.port : 5432,
        database: uri.pathSegments.single,
        username: Uri.decodeComponent(userInfo.first),
        password: Uri.decodeComponent(userInfo.sublist(1).join(':')),
      );
      final owner = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final schema = 'storeos_http_${newUuid().replaceAll('-', '')}';
      final pool = Pool<void>.withEndpoints([
        endpoint,
      ], settings: const PoolSettings(sslMode: SslMode.disable));
      HttpServer? server;
      final client = HttpClient();
      try {
        await MigrationRunner(
          connection: owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: schema,
        ).apply();
        final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
        await BootstrapService(
          connection: owner,
          passwordHasher: hasher,
          schemaName: schema,
        ).bootstrap(
          username: 'operator',
          password: _password,
          companyId: _company,
          locationId: _location,
        );
        final store = PostgresAuthStore(pool, schemaName: schema);
        final auth = await AuthService.create(
          store: store,
          companyId: _company,
          locationId: _location,
          sessionTtl: const Duration(hours: 1),
          passwordHasher: hasher,
        );
        final db = PlatformDatabase(
          pool,
          schemaName: schema,
          companyId: _company,
          locationId: _location,
        );
        final app = ServerApp(
          config: const ServerConfig(
            database: DatabaseConfig(
              host: 'localhost',
              port: 5432,
              name: 'unused',
              user: 'unused',
              password: 'unused',
            ),
            companyId: _company,
            locationId: _location,
          ),
          store: store,
          auth: auth,
          platformHandler: createPlatformHandler(auth, db),
          logger: const JsonLogger(),
        );
        server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
        final base = 'http://127.0.0.1:${server.port}';
        Future<Map<String, dynamic>> call(
          String method,
          String path, {
          String? token,
          Map<String, dynamic>? body,
          int expected = 200,
        }) async {
          final request = await client.openUrl(method, Uri.parse('$base$path'));
          if (token != null) {
            request.headers.set('authorization', 'Bearer $token');
          }
          if (body != null) {
            request.headers.contentType = ContentType.json;
            request.write(jsonEncode(body));
          }
          final response = await request.close();
          final text = await utf8.decodeStream(response);
          expect(response.statusCode, expected, reason: '$method $path: $text');
          return text.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(text) as Map<String, dynamic>;
        }

        await call('GET', '/ready');
        const prefix = '/api/v1/platform';
        await call('GET', '$prefix/context', expected: 401);
        final session = await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'operator', 'password': _password},
        );
        final token = session['token']! as String;
        final context = await call('GET', '$prefix/context', token: token);
        expect(context['role'], 'admin');
        final setup = await call(
          'POST',
          '$prefix/organization/setup',
          token: token,
          body: {
            'companyName': 'HTTP smoke company',
            'locationName': 'HTTP smoke location',
          },
        );
        expect((setup['company'] as Map)['id'], _company);
        await call(
          'POST',
          '$prefix/organization/setup',
          token: token,
          body: {'companyName': 'Again', 'locationName': 'Again'},
          expected: 409,
        );
        final otherLocation = newUuid();
        await call(
          'POST',
          '$prefix/locations',
          token: token,
          body: {'id': otherLocation, 'name': 'Other smoke location'},
          expected: 201,
        );
        final viewerId = newUuid();
        await call(
          'POST',
          '$prefix/users',
          token: token,
          body: {
            'id': viewerId,
            'username': 'smoke_viewer',
            'password': _password,
            'locationId': otherLocation,
            'role': 'viewer',
          },
          expected: 201,
        );
        final viewerSession = await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'smoke_viewer', 'password': _password},
        );
        final viewerToken = viewerSession['token']! as String;
        final restricted = await call(
          'GET',
          '$prefix/organization',
          token: viewerToken,
        );
        expect((restricted['locations'] as List).single['id'], otherLocation);
        await call(
          'GET',
          '/api/v1/locations/$otherLocation/system/status',
          token: viewerToken,
        );
        await call('GET', '$prefix/users', token: viewerToken, expected: 403);
        await call('GET', '$prefix/audit', token: viewerToken, expected: 403);
        await call('GET', '$prefix/plugins', token: viewerToken, expected: 403);
        await call(
          'POST',
          '$prefix/locations',
          token: viewerToken,
          body: {'id': newUuid(), 'name': 'Forbidden'},
          expected: 403,
        );

        final manifest = <String, dynamic>{
          'id': 'smoke.adapter',
          'name': 'Smoke adapter',
          'version': '1.0.0',
          'vendor': 'StoreOS tests',
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
        final registered = await call(
          'POST',
          '$prefix/plugins',
          token: token,
          body: {'manifest': manifest},
          expected: 201,
        );
        final pluginId = registered['id'];
        await call(
          'POST',
          '$prefix/plugins',
          token: token,
          body: {
            'manifest': {
              ...manifest,
              'id': 'invalid.adapter',
              'name': 'Bad\u0000name',
            },
          },
          expected: 400,
        );
        final approved = await call(
          'POST',
          '$prefix/plugins/$pluginId/approve',
          token: token,
          body: {
            'expectedVersion': registered['version'],
            'locationId': _location,
            'permissions': ['organization.read', 'events.read'],
            'subscriptions': ['organization.location.updated'],
          },
        );
        final pluginToken = approved['token']! as String;
        await call('GET', '$prefix/users', token: pluginToken, expected: 401);
        await call(
          'GET',
          '/api/plugin/v1/organization',
          token: viewerToken,
          expected: 401,
        );
        final pluginOrg = await call(
          'GET',
          '/api/plugin/v1/organization',
          token: pluginToken,
        );
        expect((pluginOrg['locations'] as List).single['id'], _location);
        final organization = await call(
          'GET',
          '$prefix/organization',
          token: token,
        );
        final local =
            (organization['locations'] as List).firstWhere(
                  (dynamic l) => l['id'] == _location,
                )
                as Map;
        await call(
          'POST',
          '$prefix/locations/$_location',
          token: token,
          body: {
            'name': 'Updated smoke location',
            'expectedVersion': local['version'],
          },
        );
        await call(
          'POST',
          '$prefix/locations/$_location',
          token: token,
          body: {'name': 'Stale version', 'expectedVersion': local['version']},
          expected: 409,
        );
        final bus = EventBus(database: db);
        await bus.dispatchOnce();
        await bus.dispatchOnce();
        final delivered = await call(
          'GET',
          '/api/plugin/v1/events',
          token: pluginToken,
        );
        final again = await call(
          'GET',
          '/api/plugin/v1/events',
          token: pluginToken,
        );
        expect(delivered['items'], isNotEmpty);
        expect(again['items'], delivered['items']);
        final event = (delivered['items'] as List).single as Map;
        await call(
          'POST',
          '/api/plugin/v1/events/${event['eventId']}/ack',
          token: pluginToken,
          body: {},
          expected: 204,
        );
        expect(
          (await call(
            'GET',
            '/api/plugin/v1/events',
            token: pluginToken,
          ))['items'],
          isEmpty,
        );
        final audit = await call('GET', '$prefix/audit', token: token);
        expect(audit['items'], isNotEmpty);
        expect(jsonEncode(audit), isNot(contains(_password)));
        expect(jsonEncode(audit), isNot(contains(pluginToken)));
        await call(
          'POST',
          '$prefix/plugins/$pluginId/disable',
          token: token,
          body: {'expectedVersion': (approved['plugin'] as Map)['version']},
        );
        await call(
          'GET',
          '/api/plugin/v1/organization',
          token: pluginToken,
          expected: 401,
        );
        await call(
          'POST',
          '$prefix/users/$viewerId/password',
          token: token,
          body: {
            'password': 'replacement-password-strong',
            'expectedVersion': 1,
          },
        );
        await call('GET', '$prefix/context', token: viewerToken, expected: 401);
        await call('POST', '/api/v1/auth/logout', token: token, expected: 204);
        await call('GET', '$prefix/context', token: token, expected: 401);
      } finally {
        client.close(force: true);
        await server?.close(force: true);
        await pool.close();
        await owner.execute('DROP SCHEMA IF EXISTS "$schema" CASCADE');
        await owner.close();
      }
    },
    skip: _databaseUrl == null ? 'STOREOS_TEST_DATABASE is not set' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
