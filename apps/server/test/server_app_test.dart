import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/login_limiter.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
const _otherLocation = '33333333-3333-4333-8333-333333333333';

void main() {
  test(
    'password hashes are salted, verifiable, and reject wrong passwords',
    () async {
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      final first = await hasher.hash('correct horse battery staple');
      final second = await hasher.hash('correct horse battery staple');
      expect(first, isNot(second));
      expect(
        await hasher.verify('correct horse battery staple', first),
        isTrue,
      );
      expect(await hasher.verify('wrong', first), isFalse);
      expect(await hasher.verify('anything', 'broken'), isFalse);
    },
  );

  test('login, scoped status, logout and invalidated session', () async {
    final harness = await _Harness.create();
    final login = await harness.call(
      'POST',
      '/api/v1/auth/login',
      body: {'username': 'operator', 'password': 'correct-password'},
    );
    expect(login.statusCode, 200);
    final session = SessionResponse.fromJson(await _body(login));
    expect(session.user.companyId, _company);
    expect(session.user.locationId, _location);
    expect(session.token, hasLength(43));

    final wrongLocation = await harness.call(
      'GET',
      '/api/v1/locations/$_otherLocation/system/status',
      token: session.token,
    );
    expect(wrongLocation.statusCode, 403);
    final correctLocation = await harness.call(
      'GET',
      '/api/v1/locations/$_location/system/status',
      token: session.token,
    );
    expect(correctLocation.statusCode, 200);
    expect(
      SystemStatusResponse.fromJson(await _body(correctLocation)).database,
      'reachable',
    );

    final logout = await harness.call(
      'POST',
      '/api/v1/auth/logout',
      token: session.token,
    );
    expect(logout.statusCode, 204);
    expect(
      (await harness.call(
        'GET',
        '/api/v1/locations/$_location/system/status',
        token: session.token,
      )).statusCode,
      401,
    );
  });

  test('health and readiness separate liveness from database state', () async {
    final harness = await _Harness.create();
    harness.store.ready = false;
    expect((await harness.call('GET', '/health')).statusCode, 200);
    final ready = await harness.call('GET', '/ready');
    expect(ready.statusCode, 503);
    expect(HealthResponse.fromJson(await _body(ready)).status, 'unavailable');
    harness.store.ready = true;
    expect((await harness.call('GET', '/ready')).statusCode, 200);
  });

  test(
    'rejects malformed requests and limits repeated failed logins',
    () async {
      final harness = await _Harness.create();
      expect(
        (await harness.call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 2},
        )).statusCode,
        400,
      );
      expect(
        (await harness.call(
          'GET',
          '/api/v1/locations/$_location/system/status',
        )).statusCode,
        401,
      );
      for (var i = 0; i < 2; i++) {
        expect(
          (await harness.call(
            'POST',
            '/api/v1/auth/login',
            body: {'username': 'operator', 'password': 'incorrect'},
          )).statusCode,
          401,
        );
      }
      expect(
        (await harness.call(
          'POST',
          '/api/v1/auth/login',
          body: {'username': 'operator', 'password': 'correct-password'},
        )).statusCode,
        429,
      );
    },
  );
}

Future<Map<String, dynamic>> _body(Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

class _Harness {
  _Harness(this.store, this.app);

  static Future<_Harness> create() async {
    final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
    final store = _MemoryStore(
      StoredAccount(
        id: '44444444-4444-4444-8444-444444444444',
        username: 'operator',
        passwordHash: await hasher.hash('correct-password'),
        companyId: _company,
        locationId: _location,
        isActive: true,
      ),
    );
    final auth = AuthService(
      store: store,
      passwordHasher: hasher,
      limiter: LoginLimiter(maxUserFailures: 2),
      companyId: _company,
      locationId: _location,
      sessionTtl: const Duration(hours: 1),
      dummyPasswordHash: await hasher.hash('dummy-password'),
    );
    final config = ServerConfig(
      database: const DatabaseConfig(
        host: 'localhost',
        port: 5432,
        name: 'unused',
        user: 'unused',
        password: 'unused',
      ),
      companyId: _company,
      locationId: _location,
    );
    return _Harness(store, ServerApp(config: config, auth: auth, store: store));
  }

  final _MemoryStore store;
  final ServerApp app;

  Future<Response> call(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? token,
  }) async => app.handler(
    Request(
      method,
      Uri.parse('http://localhost$path'),
      headers: {
        if (body != null) 'content-type': 'application/json',
        if (token != null) 'authorization': 'Bearer $token',
      },
      body: body == null ? null : jsonEncode(body),
    ),
  );
}

class _MemoryStore implements AuthStore {
  _MemoryStore(this.account);

  final StoredAccount account;
  bool ready = true;
  final Map<String, DateTime> sessions = {};

  @override
  Future<bool> isReady() async => ready;

  @override
  Future<StoredAccount?> findAccount(String usernameKey) async =>
      usernameKey == 'operator' ? account : null;

  @override
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
    String? expectedPasswordHash,
    String? expectedCompanyId,
  }) async => sessions[tokenHash] = expiresAt;

  @override
  Future<SessionPrincipal?> findSession(String tokenHash) async {
    final expiresAt = sessions[tokenHash];
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) return null;
    return SessionPrincipal(
      id: account.id,
      username: account.username,
      companyId: account.companyId,
      locationId: account.locationId,
    );
  }

  @override
  Future<bool> revokeSession(String tokenHash) async =>
      sessions.remove(tokenHash) != null;
}
