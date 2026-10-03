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
          String? raw,
          int expected = 200,
        }) async {
          final request = await client.openUrl(method, Uri.parse('$base$path'));
          if (token != null) {
            request.headers.set('authorization', 'Bearer $token');
          }
          if (raw != null) {
            request.headers.contentType = ContentType.json;
            request.write(raw);
          } else if (body != null) {
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
        final smokeArticle = newUuid();
        final createdArticle = await call(
          'POST',
          '$prefix/articles',
          token: token,
          body: {
            'id': smokeArticle,
            'sku': 'SMOKE-1',
            'barcode': null,
            'name': 'Smoke article',
            'description': null,
            'unit': 'Stk',
          },
          expected: 201,
        );
        expect(createdArticle['sku'], 'SMOKE-1');
        expect(createdArticle['isActive'], true);
        final readArticle = await call(
          'GET',
          '$prefix/articles/$smokeArticle',
          token: token,
        );
        expect(readArticle['id'], smokeArticle);
        final listedArticles = await call(
          'GET',
          '$prefix/articles?active=true&q=SMOKE',
          token: token,
        );
        expect(
          (listedArticles['items'] as List).map((item) => item['id']),
          contains(smokeArticle),
        );
        final editedArticle = await call(
          'POST',
          '$prefix/articles/$smokeArticle/edit',
          token: token,
          body: {
            'expectedVersion': 1,
            'sku': 'SMOKE-1',
            'barcode': '000123',
            'name': 'Smoke article edited',
            'description': null,
            'unit': 'Stk',
          },
        );
        expect(editedArticle['version'], 2);
        final deactivatedArticle = await call(
          'POST',
          '$prefix/articles/$smokeArticle/deactivate',
          token: token,
          body: {'expectedVersion': 2},
        );
        expect(deactivatedArticle['isActive'], false);
        final reactivatedArticle = await call(
          'POST',
          '$prefix/articles/$smokeArticle/reactivate',
          token: token,
          body: {'expectedVersion': 3},
        );
        expect(reactivatedArticle['isActive'], true);
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
          '$prefix/articles',
          token: viewerToken,
          expected: 403,
        );
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
          'POST',
          '$prefix/profile/password',
          token: pluginToken,
          body: {
            'currentPassword': _password,
            'newPassword': 'plugin-token-must-not-work',
          },
          expected: 401,
        );
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

        const selfOld = 'smoke-self-old-password-strong';
        const selfNew = 'smoke-self-new-password-strong';
        final selfId = newUuid();
        await call(
          'POST',
          '$prefix/users',
          token: token,
          body: {
            'id': selfId,
            'username': 'smoke_self',
            'password': selfOld,
            'locationId': otherLocation,
            'role': 'viewer',
          },
          expected: 201,
        );
        final selfSession = await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'smoke_self', 'password': selfOld},
        );
        final selfToken = selfSession['token']! as String;
        await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          expected: 415,
        );
        await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          raw: '[]',
          expected: 400,
        );
        final invalid = await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          body: {'currentPassword': selfOld},
          expected: 400,
        );
        expect(invalid['code'], 'invalid_request');
        await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          body: {'currentPassword': selfOld, 'newPassword': selfOld},
          expected: 400,
        );
        final wrongCurrent = await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          body: {
            'currentPassword': 'wrong-current-password',
            'newPassword': selfNew,
          },
          expected: 422,
        );
        expect(wrongCurrent['code'], 'invalid_current_password');
        await call(
          'POST',
          '$prefix/profile/password',
          body: {'currentPassword': selfOld, 'newPassword': selfNew},
          expected: 401,
        );
        await call(
          'POST',
          '$prefix/profile/password',
          token: selfToken,
          body: {'currentPassword': selfOld, 'newPassword': selfNew},
          expected: 204,
        );
        await call('GET', '$prefix/context', token: selfToken, expected: 401);
        await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'smoke_self', 'password': selfOld},
          expected: 401,
        );
        final selfRelogin = await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'smoke_self', 'password': selfNew},
        );
        expect((selfRelogin['user'] as Map)['username'], 'smoke_self');

        const limitedOld = 'smoke-limited-old-password';
        final limitedId = newUuid();
        await call(
          'POST',
          '$prefix/users',
          token: token,
          body: {
            'id': limitedId,
            'username': 'smoke_limited',
            'password': limitedOld,
            'locationId': otherLocation,
            'role': 'viewer',
          },
          expected: 201,
        );
        final limitedSession = await call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'smoke_limited', 'password': limitedOld},
        );
        final limitedToken = limitedSession['token']! as String;
        for (var attempt = 0; attempt < 5; attempt++) {
          await call(
            'POST',
            '$prefix/profile/password',
            token: limitedToken,
            body: {
              'currentPassword': 'wrong-current-password',
              'newPassword': 'smoke-limited-new-password',
            },
            expected: 422,
          );
        }
        final throttled = await call(
          'POST',
          '$prefix/profile/password',
          token: limitedToken,
          body: {
            'currentPassword': limitedOld,
            'newPassword': 'smoke-limited-new-password',
          },
          expected: 429,
        );
        expect(throttled['code'], 'rate_limited');
        await call(
          'GET',
          '$prefix/context',
          token: limitedToken,
          expected: 200,
        );

        final amendEmployee = await call(
          'POST',
          '$prefix/employees',
          token: token,
          body: {
            'id': newUuid(),
            'displayName': 'Smoke amendment employee',
            'locationId': _location,
          },
          expected: 201,
        );
        final amendTemplate = newUuid(), amendRevision = newUuid();
        await call(
          'POST',
          '$prefix/task-templates',
          token: token,
          body: {
            'id': amendTemplate,
            'revisionId': amendRevision,
            'locationId': _location,
            'content': {
              'schemaVersion': 1,
              'title': 'Smoke amendment task',
              'steps': [
                {
                  'id': newUuid(),
                  'type': 'confirmation',
                  'instruction': 'Confirm',
                },
              ],
            },
          },
          expected: 201,
        );
        await call(
          'POST',
          '$prefix/task-templates/$amendTemplate/revisions/$amendRevision/publish',
          token: token,
          body: {'expectedVersion': 1},
        );
        final amendStart = DateTime.now().toUtc().add(const Duration(days: 1));
        Map<String, dynamic> amendBody(
          int version,
          DateTime startsAt,
          DateTime endsAt,
        ) => {
          'expectedVersion': version,
          'startsAt': startsAt.toIso8601String(),
          'endsAt': endsAt.toIso8601String(),
        };
        final amendShift = newUuid(), secondShift = newUuid();
        for (final entry in [
          (amendShift, amendStart, amendStart.add(const Duration(hours: 4))),
          (
            secondShift,
            amendStart.add(const Duration(hours: 4)),
            amendStart.add(const Duration(hours: 8)),
          ),
        ]) {
          await call(
            'POST',
            '$prefix/shifts',
            token: token,
            body: {
              'id': entry.$1,
              'locationId': _location,
              'employeeId': amendEmployee['id'],
              'startsAt': entry.$2.toIso8601String(),
              'endsAt': entry.$3.toIso8601String(),
              'selections': [
                {'templateId': amendTemplate, 'revisionId': amendRevision},
              ],
            },
            expected: 201,
          );
          await call(
            'POST',
            '$prefix/shifts/${entry.$1}/publish',
            token: token,
            body: {'expectedVersion': 1},
          );
        }
        final overlapping = await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 2)),
            amendStart.add(const Duration(hours: 6)),
          ),
          expected: 409,
        );
        expect(overlapping['code'], 'shift_overlap');
        await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: {
            ...amendBody(
              2,
              amendStart,
              amendStart.add(const Duration(hours: 4)),
            ),
            'employeeId': amendEmployee['id'],
          },
          expected: 400,
        );
        final pastWindow = await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: amendBody(
            2,
            DateTime.now().toUtc().subtract(const Duration(hours: 2)),
            DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          ),
          expected: 422,
        );
        expect(pastWindow['code'], 'shift_not_amendable');
        await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 1)),
            amendStart.add(const Duration(hours: 4)),
          ),
          expected: 401,
        );
        await call(
          'POST',
          '$prefix/shifts/${newUuid()}/amend',
          token: token,
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 1)),
            amendStart.add(const Duration(hours: 4)),
          ),
          expected: 404,
        );
        final amended = await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 1)),
            amendStart.add(const Duration(hours: 4)),
          ),
        );
        expect((amended['shift'] as Map)['version'], 3);
        expect((amended['shift'] as Map)['amendmentVersion'], 2);
        final amendedRetry = await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 1)),
            amendStart.add(const Duration(hours: 4)),
          ),
        );
        expect((amendedRetry['shift'] as Map)['version'], 3);
        await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          body: amendBody(
            2,
            amendStart.add(const Duration(hours: 3)),
            amendStart.add(const Duration(hours: 4)),
          ),
          expected: 409,
        );
        await call(
          'POST',
          '$prefix/shifts/$amendShift/amend',
          token: token,
          raw: '[]',
          expected: 400,
        );
        final wrongTypeRequest = await client.postUrl(
          Uri.parse('$base$prefix/shifts/$amendShift/amend'),
        );
        wrongTypeRequest.headers.set('authorization', 'Bearer $token');
        wrongTypeRequest.headers.contentType = ContentType.text;
        wrongTypeRequest.write('{}');
        final wrongTypeResponse = await wrongTypeRequest.close();
        await wrongTypeResponse.drain<void>();
        expect(wrongTypeResponse.statusCode, 415);
        // Body-size (413) semantics for the shared body reader are asserted by
        // api_support_test.dart; an oversized HTTP write can be refused before
        // the client reads the response on some platforms.

        final finalAudit = await call('GET', '$prefix/audit', token: token);
        expect(
          jsonEncode(finalAudit),
          contains('identity.user.password_changed'),
        );
        expect(jsonEncode(finalAudit), contains('workforce.shift.amended'));
        expect(jsonEncode(finalAudit), isNot(contains(selfOld)));
        expect(jsonEncode(finalAudit), isNot(contains(selfNew)));
        expect(jsonEncode(finalAudit), isNot(contains(limitedOld)));

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
