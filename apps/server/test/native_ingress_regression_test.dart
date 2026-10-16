import 'dart:async';

import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/login_limiter.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/api_support.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:test/test.dart';

import 'native_ingress_fixture.dart';

const ingressToken = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const ingressConfig = ServerConfig(
  database: DatabaseConfig(
    host: 'localhost',
    port: 5432,
    name: 'unused',
    user: 'unused',
    password: 'unused',
  ),
  companyId: SessionStore.company,
  locationId: SessionStore.location,
);

AuthService ingressAuth(AuthStore store) => AuthService(
  store: store,
  passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
  limiter: LoginLimiter(),
  companyId: SessionStore.company,
  locationId: SessionStore.location,
  sessionTtl: const Duration(hours: 1),
  dummyPasswordHash: 'unused',
);

ServerApp ingressApp(AuthStore store) =>
    ServerApp(config: ingressConfig, auth: ingressAuth(store), store: store);

String logout({
  String body = '',
  int? length,
  bool framed = true,
  bool chunked = false,
  String token = ingressToken,
}) => nativeRequest(
  'POST',
  '/api/v1/auth/logout',
  body: body,
  length: length,
  withLength: framed && !chunked,
  extra:
      'Authorization: Bearer $token\r\n${chunked ? 'Transfer-Encoding: chunked\r\n' : ''}',
);

void main() {
  for (final (name, wire) in [
    ('unframed bodyless', logout(framed: false)),
    ('explicit zero', logout()),
    ('finite non-JSON content', logout(body: 'ignored content')),
    ('completed zero chunked', logout(chunked: true, body: '0\r\n\r\n')),
    (
      'completed finite chunked',
      logout(chunked: true, body: '3\r\nabc\r\n0\r\n\r\n'),
    ),
  ]) {
    test('INGRESS-01 $name logout preserves 204 compatibility', () async {
      final store = SessionStore();
      final f = await NativeIngressFixture.make(ingressApp(store).handler);
      addTearDown(f.close);
      final socket = await f.accept();
      socket.feed(wire);
      await pumpIngress();
      expect(store.revocations, 1);
      expect(socket.output, contains('204 No Content'));
      expect(socket.destroys, 0);
      expect(f.server.incompleteBodies, 0);
      expect(f.server.activeRequests, 0);
    });
  }

  for (final chunked in [false, true]) {
    test(
      'INGRESS-01 started ${chunked ? 'chunked' : 'declared'} logout waits for genuine EOF exactly once',
      () async {
        final store = SessionStore();
        final f = await NativeIngressFixture.make(ingressApp(store).handler);
        addTearDown(f.close);
        final socket = await f.accept();
        socket.feed(
          logout(
            length: 2,
            chunked: chunked,
            body: chunked ? '2\r\n{}\r\n' : '{',
          ),
        );
        await pumpIngress();
        expect(store.lookups, 1);
        expect(store.revocations, 0);
        expect(f.server.incompleteBodies, 1);
        // The one-second discard window must not replace the valid upload gate.
        f.clock.elapse(const Duration(seconds: 1));
        await pumpIngress();
        expect(socket.destroys, 0);
        expect(store.revocations, 0);
        socket.feed(chunked ? '0\r\n\r\n' : '}');
        await pumpIngress();
        expect(store.revocations, 1);
        expect(socket.output, contains('204 No Content'));
        f.clock.elapse(const Duration(seconds: 29));
        await pumpIngress();
        expect(store.revocations, 1);
        expect(f.server.incompleteBodies, 0);
      },
    );
  }

  for (final kind in [
    'disconnect',
    'input error',
    'malformed chunk',
    'deadline',
    'shutdown',
  ]) {
    test('INGRESS-01 $kind before EOF preserves the usable session', () async {
      final store = SessionStore();
      final app = ingressApp(store);
      final f = await NativeIngressFixture.make(app.handler);
      addTearDown(f.close);
      final socket = await f.accept();
      socket.feed(
        logout(
          length: 2,
          chunked: kind == 'malformed chunk',
          body: kind == 'malformed chunk' ? '2\r\n{}\r\n' : '{',
        ),
      );
      await pumpIngress();
      expect(store.revocations, 0);
      switch (kind) {
        case 'disconnect':
          socket.destroy();
        case 'input error':
          socket.input.addError(StateError('finite transport failure'));
          await pumpIngress();
          expect(store.revocations, 0);
          // The SDK queues socket-level errors on its paused request parser.
          // The independent upload deadline still bounds this retained request.
          f.clock.elapse(const Duration(seconds: 30));
        case 'malformed chunk':
          socket.feed('z\r\n');
        case 'deadline':
          f.clock.elapse(const Duration(seconds: 30));
        case 'shutdown':
          await f.close();
      }
      await pumpIngress();
      expect(store.revocations, 0);
      expect(socket.output, isEmpty);
      expect(f.server.incompleteBodies, 0);
      expect(f.server.activeRequests, 0);
      expect(
        (await app.auth.authenticate(ingressToken)).id,
        SessionStore.account,
      );
    });
  }

  for (final eofFirst in [false, true]) {
    test(
      'INGRESS-01 ${eofFirst ? 'EOF' : 'abort'} wins the finite completion race',
      () async {
        final store = SessionStore();
        final f = await NativeIngressFixture.make(ingressApp(store).handler);
        addTearDown(f.close);
        final socket = await f.accept();
        socket.feed(logout(length: 2, body: '{'));
        await pumpIngress();
        socket.feed('}');
        if (eofFirst) await pumpIngress();
        f.clock.elapse(const Duration(seconds: 30));
        await pumpIngress();
        socket.destroy();
        await pumpIngress();
        expect(store.revocations, eofFirst ? 1 : 0);
        expect(f.server.incompleteBodies, 0);
      },
    );
  }

  for (final revoked in [false, true]) {
    test(
      'INGRESS-01 ${revoked ? 'revoked' : 'invalid'} session remains 401',
      () async {
        final store = SessionStore()..revoked = revoked;
        final f = await NativeIngressFixture.make(ingressApp(store).handler);
        addTearDown(f.close);
        final socket = await f.accept();
        socket.feed(
          logout(body: 'finite', token: revoked ? ingressToken : 'invalid'),
        );
        await pumpIngress();
        expect(store.revocations, 0);
        expect(socket.output, contains('401 Unauthorized'));
      },
    );
  }

  test(
    'INGRESS-02 health ready and authenticated status reuse the same native transport',
    () async {
      final f = await NativeIngressFixture.make(
        ingressApp(SessionStore()).handler,
      );
      addTearDown(f.close);
      final socket = await f.accept();
      for (final path in [
        '/health',
        '/ready',
        '/api/v1/locations/${SessionStore.location}/system/status',
        '/health',
      ]) {
        socket.feed(
          nativeRequest(
            'GET',
            path,
            withLength: false,
            extra: 'Authorization: Bearer $ingressToken\r\n',
          ),
        );
        await pumpIngress();
        expect(socket.destroys, 0);
        expect(f.peers, 1);
        expect(f.server.activeConnections, 1);
        expect(f.server.incompleteBodies, 0);
        expect(f.server.activeRequests, 0);
      }
      expect('HTTP/1.1 200 OK'.allMatches(socket.output).length, 4);
      expect(socket.output, isNot(contains('connection: close')));
      await f.close();
      expect(f.server.activeConnections, 0);
      expect(f.clock.active, 0);
    },
  );

  test(
    'INGRESS-02 explicit zero GET reuses a single admitted connection',
    () async {
      final f = await NativeIngressFixture.make((_) => Response.ok('ok'));
      addTearDown(f.close);
      final socket = await f.accept();
      for (var i = 0; i < 2; i++) {
        socket.feed(nativeRequest('GET', '/'));
        await pumpIngress();
      }
      expect('HTTP/1.1 200 OK'.allMatches(socket.output).length, 2);
      expect(socket.destroys, 0);
      expect(f.server.incompleteBodies, 0);
    },
  );

  test(
    'INGRESS-02 completed zero chunked and finite GET bodies retain their framing',
    () async {
      final sizes = <int>[];
      final f = await NativeIngressFixture.make((r) async {
        sizes.add((await r.read().expand((x) => x).toList()).length);
        return Response.ok('ok');
      });
      addTearDown(f.close);
      final socket = await f.accept();
      socket.feed(
        nativeRequest(
          'GET',
          '/',
          withLength: false,
          extra: 'Transfer-Encoding: chunked\r\n',
          body: '0\r\n\r\n',
        ),
      );
      await pumpIngress();
      socket.feed(nativeRequest('GET', '/', body: 'finite'));
      await pumpIngress();
      expect(sizes, [0, 6]);
      expect(socket.destroys, 0);
      expect(f.server.incompleteBodies, 0);
      expect('HTTP/1.1 200 OK'.allMatches(socket.output).length, 2);
    },
  );

  test(
    'INGRESS-02 chunked GET without terminator is protected until expiry',
    () async {
      var mutations = 0;
      final f = await NativeIngressFixture.make((r) async {
        await completeRequestBody(r);
        mutations++;
        return Response.ok('ok');
      });
      addTearDown(f.close);
      final socket = await f.accept();
      socket.feed(
        nativeRequest(
          'GET',
          '/',
          withLength: false,
          extra: 'Transfer-Encoding: chunked\r\n',
          body: '1\r\nx\r\n',
        ),
      );
      await pumpIngress();
      expect(f.server.incompleteBodies, 1);
      expect(mutations, 0);
      f.clock.elapse(const Duration(seconds: 30));
      await pumpIngress();
      expect(mutations, 0);
      expect(socket.destroys, 1);
      expect(f.server.incompleteBodies, 0);
    },
  );

  test(
    'INGRESS-02 rejected completed body releases admission for bodyless GET',
    () async {
      final f = await NativeIngressFixture.make(
        (r) => r.url.path == 'reject' ? Response(415) : Response.ok('ok'),
      );
      addTearDown(f.close);
      final rejected = await f.accept();
      rejected.feed(nativeRequest('GET', '/reject', body: 'unexpected'));
      await pumpIngress();
      expect(rejected.output, contains('415 Unsupported Media Type'));
      expect(rejected.destroys, 1);
      expect(f.server.incompleteBodies, 0);
      final next = await f.accept();
      next.feed(nativeRequest('GET', '/', withLength: false));
      await pumpIngress();
      expect(next.output, contains('200 OK'));
      expect(next.destroys, 0);
      expect(f.server.activeRequests, 0);
      expect(f.server.incompleteBodies, 0);
    },
  );
}

class SessionStore implements AuthStore {
  static const company = '11111111-1111-4111-8111-111111111111';
  static const location = '22222222-2222-4222-8222-222222222222';
  static const account = '44444444-4444-4444-8444-444444444444';
  bool revoked = false;
  int revocations = 0, lookups = 0;
  @override
  Future<bool> isReady() async => true;
  @override
  Future<StoredAccount?> findAccount(String name) async => null;
  @override
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
    String? expectedPasswordHash,
    String? expectedCompanyId,
  }) async {}
  @override
  Future<SessionPrincipal?> findSession(String hash) async {
    lookups++;
    return revoked || hash != digestToken(ingressToken)
        ? null
        : const SessionPrincipal(
            id: account,
            username: 'test',
            companyId: company,
            locationId: location,
          );
  }

  @override
  Future<bool> revokeSession(String hash) async {
    revocations++;
    revoked = true;
    return true;
  }
}
