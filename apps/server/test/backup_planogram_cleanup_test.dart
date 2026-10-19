import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/login_limiter.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:test/test.dart';

import '../tool/backup_planogram_acceptance.dart';
import 'merchandising_fixture.dart';

const _token = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _other = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';

void main() {
  late _Store store;
  late _Pool pool;
  late AuthService auth;
  late List<String> messages;
  setUp(() {
    store = _Store();
    pool = _Pool(store);
    messages = [];
    auth = AuthService(
      store: store,
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
      limiter: LoginLimiter(),
      companyId: _company,
      locationId: _location,
      sessionTtl: const Duration(minutes: 1),
      dummyPasswordHash: 'unused',
      clock: () => store.now,
    );
  });
  Future<void> cleanup({Object? primary, List<String>? tokens}) =>
      cleanupBackupPlanogramReads(
        pool,
        'fixture',
        [
          for (final token in tokens ?? [_token]) (auth: auth, token: token),
        ],
        primaryError: primary,
        diagnostic: messages.add,
      );

  test('live session is revoked and pool closes', () async {
    await cleanup();
    expect(store.revoked, {digestToken(_token)});
    expect(pool.queries, 0);
    expect(pool.closes, 1);
    expect(messages, isEmpty);
  });
  test(
    'verified expiry succeeds without claiming logout or revoking',
    () async {
      store.now = store.expires;
      await expectLater(auth.logout(_token), throwsA(isA<AuthFailure>()));
      await cleanup();
      expect(store.revoked, isEmpty);
      expect(pool.queries, 1);
      expect(pool.closes, 1);
      expect(messages.single, contains('logout not performed'));
    },
  );
  test(
    'primary body error retains identity and stack after cleanup expiry',
    () async {
      final primary = StateError('body');
      store.now = store.expires;
      Future<void> body() async {
        Object? failure;
        try {
          Error.throwWithStackTrace(
            primary,
            StackTrace.fromString('body-origin'),
          );
        } on Object catch (error) {
          failure = error;
          rethrow;
        } finally {
          await cleanup(primary: failure);
        }
      }

      try {
        await body();
        fail('Body failure must propagate.');
      } catch (error, stack) {
        expect(error, same(primary));
        expect(stack.toString(), contains('body-origin'));
      }
      expect(pool.closes, 1);
    },
  );
  for (final reason in AuthFailureReason.values) {
    test(
      'unexpected ${reason.name} remains visible and later logout runs',
      () async {
        final error = AuthFailure(reason);
        store.failure = error;
        await expectLater(
          cleanup(tokens: [_token, _other]),
          throwsA(same(error)),
        );
        expect(store.lookups, 2);
        expect(store.revoked, {digestToken(_other)});
        expect(pool.closes, 1);
        expect(messages.single, contains(reason.name));
        expect(messages.single, isNot(contains(_token)));
      },
    );
  }
  test('expired revoked session is not excused', () async {
    store.now = store.expires;
    store.revoked.add(digestToken(_token));
    await expectLater(cleanup(), throwsA(isA<AuthFailure>()));
    expect(pool.closes, 1);
  });
  test('expired inactive account is not excused', () async {
    store.now = store.expires;
    store.active = false;
    await expectLater(cleanup(), throwsA(isA<AuthFailure>()));
    expect(pool.closes, 1);
  });
  test('expiry query failure remains visible and pool closes', () async {
    store.now = store.expires;
    pool.queryError = StateError('private-query-detail');
    await expectLater(cleanup(), throwsA(same(pool.queryError)));
    expect(pool.closes, 1);
    expect(messages.single, isNot(contains('private-query-detail')));
  });
  test('pool close failure propagates with original stack', () async {
    pool.closeError = StateError('private-close-detail');
    try {
      await cleanup();
      fail('Close failure must propagate.');
    } catch (error, stack) {
      expect(error, same(pool.closeError));
      expect(stack.toString(), contains('pool-close-origin'));
    }
    expect(pool.closes, 1);
    expect(messages.single, contains('pool close failed'));
    expect(messages.single, isNot(contains('private-close-detail')));
  });
  test('primary error wins over both logout and close errors', () async {
    store.failure = const AuthFailure(AuthFailureReason.forbidden);
    pool.closeError = StateError('close');
    await cleanup(primary: StateError('body'));
    expect(pool.closes, 1);
    expect(messages, hasLength(2));
    expect(
      messages.every((m) => m.contains('primary error preserved: true')),
      isTrue,
    );
  });
  test('multiple expired sessions all checked before pool closes', () async {
    store.now = store.expires;
    await cleanup(tokens: [_token, _other]);
    expect(pool.queries, 2);
    expect(store.lookups, 2);
    expect(store.revoked, isEmpty);
    expect(messages, hasLength(2));
    expect(pool.closes, 1);
  });
  test('diagnostic failure cannot prevent resource cleanup', () async {
    store.now = store.expires;
    await expectLater(
      cleanupBackupPlanogramReads(pool, 'fixture', [
        (auth: auth, token: _token),
      ], diagnostic: (_) => throw StateError('sink')),
      throwsStateError,
    );
    expect(pool.closes, 1);
  });
  test(
    'PostgreSQL expiry cleanup preserves business rows and closes real pool',
    () async {
      await withMerchandisingFixture((f) async {
        final article = await f.stockArticle(sku: 'cleanup-evidence');
        final level = await f.openStock(article.id);
        final s = quotedSchema(f.schema);
        final before = await f.owner.execute(
          'SELECT row_to_json(l)::text FROM $s.stock_levels l ORDER BY id',
        );
        final sessionsBefore = await f.owner.execute(
          'SELECT count(*) FROM $s.auth_sessions',
        );
        final account =
            (await f.owner.execute(
                  'SELECT password_hash FROM $s.accounts WHERE id = \'${f.adminId}\'',
                )).single.single
                as String;
        // Only this disposable *_test fixture receives historical session state.
        await PostgresAuthStore(f.pool, schemaName: f.schema).createSession(
          accountId: f.adminId,
          tokenHash: digestToken(_token),
          expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
          expectedPasswordHash: account,
          expectedCompanyId: _company,
        );
        await f.owner.execute(
          Sql.named(
            'UPDATE $s.auth_sessions '
            "SET created_at = clock_timestamp() - interval '2 minutes', "
            "expires_at = clock_timestamp() - interval '1 minute' "
            'WHERE token_hash = @hash',
          ),
          parameters: {'hash': digestToken(_token)},
        );
        await expectLater(f.auth.logout(_token), throwsA(isA<AuthFailure>()));
        final diagnostic = <String>[];
        await cleanupBackupPlanogramReads(f.pool, f.schema, [
          (auth: f.auth, token: _token),
        ], diagnostic: diagnostic.add);
        expect(diagnostic.single, contains('verified expired session'));
        expect(f.pool.isOpen, isFalse);
        await f.pool.closed;
        final after = await f.owner.execute(
          'SELECT row_to_json(l)::text FROM $s.stock_levels l ORDER BY id',
        );
        expect(
          after.map((r) => r.toList()).toList(),
          before.map((r) => r.toList()).toList(),
        );
        expect(
          (await f.owner.execute(
            'SELECT revoked_at FROM $s.auth_sessions WHERE token_hash = \'${digestToken(_token)}\'',
          )).single.single,
          isNull,
        );
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM $s.auth_sessions',
          )).single.single,
          (sessionsBefore.single.single as int) + 1,
        );
        await f.assertLedgerInvariant(level.id);
      });
    },
    skip: !merchandisingDatabaseAvailable
        ? 'Needs disposable PostgreSQL *_test database.'
        : false,
  );
}

class _Store implements AuthStore {
  DateTime now = DateTime.utc(2026);
  final expires = DateTime.utc(2026).add(const Duration(minutes: 1));
  final revoked = <String>{};
  bool active = true;
  AuthFailure? failure;
  int lookups = 0;
  @override
  Future<SessionPrincipal?> findSession(String hash) async {
    lookups++;
    if (hash == digestToken(_token) && failure != null) throw failure!;
    if (!active || revoked.contains(hash) || !now.isBefore(expires)) {
      return null;
    }
    return const SessionPrincipal(
      id: 'account',
      username: 'fixture',
      companyId: _company,
      locationId: _location,
    );
  }

  @override
  Future<bool> revokeSession(String hash) async => revoked.add(hash);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Pool implements Pool<void> {
  _Pool(this.store);
  final _Store store;
  int closes = 0, queries = 0;
  Object? closeError, queryError;
  @override
  Future<void> close({bool force = false}) async {
    closes++;
    if (closeError != null) {
      Error.throwWithStackTrace(
        closeError!,
        StackTrace.fromString('pool-close-origin'),
      );
    }
  }

  @override
  Future<Result> execute(
    Object query, {
    Object? parameters,
    bool ignoreRows = false,
    QueryMode? queryMode,
    Duration? timeout,
  }) async {
    final values = parameters as Map<String, Object?>;
    queries++;
    if (queryError != null) throw queryError!;
    expect(values['companyId'], _company);
    expect(values['locationId'], _location);
    expect(values['tokenHash'], isNot(_token));
    expect(timeout, const Duration(seconds: 3));
    final schema = ResultSchema([]);
    return Result(
      rows: [
        ResultRow(
          values: [
            !store.now.isBefore(store.expires) &&
                store.active &&
                !store.revoked.contains(values['tokenHash']),
          ],
          schema: schema,
        ),
      ],
      affectedRows: 1,
      schema: schema,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
