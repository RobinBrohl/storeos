import 'dart:async';
import 'dart:io';

import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/guarded_http_server.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/event_repository.dart';
import 'package:storeos_server/src/platform/event_service.dart';
import 'package:storeos_server/src/platform/plugin_service.dart';
import 'package:test/test.dart';

import 'merchandising_fixture.dart';
import 'native_ingress_fixture.dart';

ServerApp _app(MerchandisingFixture f, AuthService auth, AuthStore store) =>
    ServerApp(
      config: ServerConfig(
        database: DatabaseConfig(
          host: 'localhost',
          port: 5432,
          name: 'unused',
          user: 'unused',
          password: 'unused',
        ),
        companyId: merchandisingTestCompany,
        locationId: merchandisingTestLocation,
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, f.database),
    );

void main() {
  for (final replay in [false, true]) {
    test(
      'INGRESS-01 shared completion gate protects ${replay ? 'event replay' : 'plugin acknowledgement'}',
      () => withMerchandisingFixture((f) async {
        final plugins = PluginService(f.database);
        final registered = await plugins.register(f.adminPrincipal, {
          'manifest': {
            'id': 'ingress.adapter',
            'name': 'Ingress adapter',
            'version': '1.0.0',
            'vendor': 'StoreOS tests',
            'coreApiVersion': 1,
            'capabilities': ['events.read'],
            'permissions': ['events.read'],
            'subscriptions': ['organization.location.updated'],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        });
        final approved = await plugins.approve(
          f.adminPrincipal,
          'ingress.adapter',
          {
            'expectedVersion': registered['version'],
            'locationId': merchandisingTestLocation,
            'permissions': ['events.read'],
            'subscriptions': ['organization.location.updated'],
          },
        );
        final pluginToken = approved['token']! as String;
        await f.database.runAuthorized(
          f.adminPrincipal,
          'organization.write',
          (tx, actor) => f.database.publishOrganizationEvent(
            tx,
            actor,
            'organization.location.updated',
            'location',
            merchandisingTestLocation,
            2,
            {
              'id': merchandisingTestLocation,
              'companyId': merchandisingTestCompany,
              'name': 'Ingress fixture',
              'version': 2,
            },
            locationId: merchandisingTestLocation,
          ),
        );
        final events = EventService(f.database);
        final eventId =
            ((await events.list(f.adminPrincipal))['items'] as List)
                    .singleWhere(
                      (dynamic e) =>
                          (e['payload'] as Map)['name'] == 'Ingress fixture',
                    )['eventId']
                as String;
        if (replay) {
          // Fixture setup through the dispatcher's existing failure transition.
          final repository = EventRepository(
            pool: f.pool,
            schema: f.database.schema,
            companyId: merchandisingTestCompany,
          );
          for (var i = 0; i < 5; i++) {
            await repository.recordFailure(eventId);
          }
        } else {
          await EventBus(database: f.database).dispatchOnce();
        }
        Future<void> unchanged() async {
          if (replay) {
            expect(
              ((await events.list(f.adminPrincipal))['items'] as List)
                  .singleWhere(
                    (dynamic e) => e['eventId'] == eventId,
                  )['status'],
              'dead_letter',
            );
          } else {
            expect(
              ((await plugins.events(pluginToken))['items'] as List)
                  .single['eventId'],
              eventId,
            );
          }
        }

        await unchanged();
        final store = PostgresAuthStore(f.pool, schemaName: f.schema);
        final guarded = await NativeIngressFixture.make(
          _app(f, f.auth, store).handler,
        );
        try {
          final path = replay
              ? '/api/v1/platform/events/$eventId/replay'
              : '/api/plugin/v1/events/$eventId/ack';
          final credential = replay ? f.adminToken! : pluginToken;
          final partial = await guarded.accept();
          partial.feed(
            nativeRequest(
              'POST',
              path,
              length: 2,
              body: 'a',
              extra: 'Authorization: Bearer $credential\r\n',
            ),
          );
          await pumpIngress();
          await unchanged();
          guarded.clock.elapse(const Duration(seconds: 30));
          await pumpIngress();
          await unchanged();
          expect(partial.output, isEmpty);
          // A separate completed request preserves finite-body compatibility.
          await f.call(
            'POST',
            path,
            raw: 'ab',
            platform: false,
            token: credential,
            expected: replay ? 200 : 204,
          );
          if (replay) {
            expect(
              ((await events.list(f.adminPrincipal))['items'] as List)
                  .singleWhere(
                    (dynamic e) => e['eventId'] == eventId,
                  )['status'],
              'pending',
            );
          } else {
            expect((await plugins.events(pluginToken))['items'], isEmpty);
          }
        } finally {
          await guarded.close();
        }
      }),
    );
  }

  test(
    'INGRESS-01 restricted PostgreSQL partial logout survives abort and expiry',
    () => withMerchandisingFixture((f) async {
      final store = PostgresAuthStore(f.pool, schemaName: f.schema);
      final role = await f.pool.execute('SELECT current_user');
      expect(role.single[0], f.runtimeUser);
      final token = f.adminToken!;
      Future<int> logoutAudits() async =>
          (await f.pool.execute(
                'SELECT count(*)::int FROM "${f.schema}".audit_entries WHERE action = \'auth.logout\'',
              )).single[0]!
              as int;
      final before = await logoutAudits();
      for (final chunked in [false, true]) {
        final observed = _ObservedStore(store);
        final auth = await AuthService.create(
          store: observed,
          companyId: merchandisingTestCompany,
          locationId: merchandisingTestLocation,
          sessionTtl: const Duration(hours: 1),
          passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
        );
        final guarded = await NativeIngressFixture.make(
          _app(f, auth, observed).handler,
        );
        try {
          final socket = await guarded.accept();
          socket.feed(
            nativeRequest(
              'POST',
              '/api/v1/auth/logout',
              length: 2,
              withLength: !chunked,
              body: chunked ? '2\r\n{}\r\n' : '{',
              extra:
                  'Authorization: Bearer $token\r\n${chunked ? 'Transfer-Encoding: chunked\r\n' : ''}',
            ),
          );
          await observed.lookedUp.future;
          await pumpIngress();
          expect(observed.revocations, 0);
          expect(await store.findSession(digestToken(token)), isNotNull);
          expect(await logoutAudits(), before);
          if (chunked) {
            socket.destroy();
          } else {
            guarded.clock.elapse(const Duration(seconds: 30));
          }
          await pumpIngress();
          expect(observed.revocations, 0);
          expect(socket.output, isEmpty);
          expect(guarded.server.incompleteBodies, 0);
          expect(await store.findSession(digestToken(token)), isNotNull);
          expect(await logoutAudits(), before);
          // This is a normal, fully completed HTTP request using the same session.
          await f.call(
            'GET',
            '/api/v1/locations/$merchandisingTestLocation/system/status',
            platform: false,
            token: token,
          );
        } finally {
          await guarded.close();
        }
      }
    }),
  );

  test(
    'INGRESS-01 restricted PostgreSQL finite logout commits once after EOF',
    () => withMerchandisingFixture((f) async {
      final store = PostgresAuthStore(f.pool, schemaName: f.schema);
      final observed = _ObservedStore(store);
      final auth = await AuthService.create(
        store: observed,
        companyId: merchandisingTestCompany,
        locationId: merchandisingTestLocation,
        sessionTtl: const Duration(hours: 1),
        passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
      );
      final guarded = await NativeIngressFixture.make(
        _app(f, auth, observed).handler,
      );
      try {
        final token = f.adminToken!;
        Future<int> logoutAudits() async =>
            (await f.pool.execute(
                  'SELECT count(*)::int FROM "${f.schema}".audit_entries WHERE action = \'auth.logout\'',
                )).single[0]!
                as int;
        final before = await logoutAudits();
        final socket = await guarded.accept();
        socket.feed(
          nativeRequest(
            'POST',
            '/api/v1/auth/logout',
            length: 2,
            body: 'a',
            extra: 'Authorization: Bearer $token\r\n',
          ),
        );
        await observed.lookedUp.future;
        await pumpIngress();
        expect(observed.revocations, 0);
        expect(await store.findSession(digestToken(token)), isNotNull);
        expect(await logoutAudits(), before);
        socket.feed('b');
        await observed.revoked.future;
        await pumpIngress();
        expect(observed.revocations, 1);
        expect(await store.findSession(digestToken(token)), isNull);
        expect(await logoutAudits(), before + 1);
        expect(socket.output, contains('204 No Content'));
        await f.call(
          'GET',
          '/api/v1/locations/$merchandisingTestLocation/system/status',
          platform: false,
          token: token,
          expected: 401,
        );
      } finally {
        await guarded.close();
      }
    }),
  );

  test(
    'INGRESS-02 completed real HTTP health ready and platform GET reuse one socket',
    () => withMerchandisingFixture((f) async {
      final client = HttpClient()..maxConnectionsPerHost = 1;
      final peers = <int>[];
      final store = PostgresAuthStore(f.pool, schemaName: f.schema);
      final app = _app(f, f.auth, store);
      final guarded = await GuardedHttpServer.bind(
        (r) {
          peers.add(
            (r.context['shelf.io.connection_info'] as HttpConnectionInfo)
                .remotePort,
          );
          return app.handler(r);
        },
        '127.0.0.1',
        0,
      );
      try {
        for (final path in [
          '/health',
          '/ready',
          '/api/v1/platform/organization',
          '/health',
        ]) {
          final request = await client.get('127.0.0.1', guarded.port, path);
          request.headers.set('authorization', 'Bearer ${f.adminToken}');
          final response = await request.close();
          expect(response.statusCode, 200);
          expect(response.persistentConnection, true);
          await response.drain<void>();
          expect(guarded.incompleteBodies, 0);
        }
        expect(peers.length, 4);
        expect(
          peers.toSet().length,
          1,
          reason:
              'All four requests must arrive from the same actual TCP peer port.',
        );
        expect(guarded.activeConnections, 1);
      } finally {
        client.close(force: true);
        await guarded.close();
      }
      expect(guarded.activeConnections, 0);
      expect(guarded.activeRequests, 0);
      expect(guarded.incompleteBodies, 0);
    }),
  );
}

class _ObservedStore implements AuthStore {
  _ObservedStore(this.store);
  final AuthStore store;
  final lookedUp = Completer<void>(), revoked = Completer<void>();
  int revocations = 0;
  @override
  Future<bool> isReady() => store.isReady();
  @override
  Future<StoredAccount?> findAccount(String username) =>
      store.findAccount(username);
  @override
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
    String? expectedPasswordHash,
    String? expectedCompanyId,
  }) => store.createSession(
    accountId: accountId,
    tokenHash: tokenHash,
    expiresAt: expiresAt,
    expectedPasswordHash: expectedPasswordHash,
    expectedCompanyId: expectedCompanyId,
  );
  @override
  Future<SessionPrincipal?> findSession(String hash) async {
    final result = await store.findSession(hash);
    if (!lookedUp.isCompleted) lookedUp.complete();
    return result;
  }

  @override
  Future<bool> revokeSession(String hash) async {
    revocations++;
    final result = await store.revokeSession(hash);
    if (!revoked.isCompleted) revoked.complete();
    return result;
  }
}
