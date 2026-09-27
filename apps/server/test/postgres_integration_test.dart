import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/login_limiter.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
final _testDatabase = Platform.environment['STOREOS_TEST_DATABASE'];

void main() {
  test(
    'migration is idempotent and detects changed applied SQL',
    () => _withSchema((connection, endpoint, schema) async {
      final directory = await _migrationCopy();
      try {
        final runner = MigrationRunner(
          connection: connection,
          migrationsDirectory: directory,
          schemaName: schema,
          runtimeDatabaseUser:
              Platform.environment['STOREOS_DB_USER'] ?? 'storeos',
        );
        expect(await runner.apply(), ['0001_platform_auth']);
        expect(await runner.apply(), isEmpty);
        final role = Platform.environment['STOREOS_DB_USER'] ?? 'storeos';
        final rights = await connection.execute(
          Sql.named(
            'SELECT '
            "has_table_privilege(@role, @accounts, 'SELECT') AS accounts_read, "
            "has_table_privilege(@role, @accounts, 'UPDATE') AS accounts_write, "
            "has_table_privilege(@role, @sessions, 'INSERT') AS sessions_create, "
            "has_table_privilege(@role, @sessions, 'DELETE') AS sessions_delete, "
            "has_table_privilege(@role, @state, 'SELECT') AS bootstrap_read, "
            "has_column_privilege(@role, @sessions, 'revoked_at', 'UPDATE') "
            'AS sessions_revoke',
          ),
          parameters: {
            'role': role,
            'accounts': '$schema.accounts',
            'sessions': '$schema.auth_sessions',
            'state': '$schema.bootstrap_state',
          },
        );
        final permissions = rights.single.toColumnMap();
        expect(permissions['accounts_read'], isTrue);
        expect(permissions['accounts_write'], isFalse);
        expect(permissions['sessions_create'], isTrue);
        expect(permissions['sessions_delete'], isTrue);
        expect(permissions['sessions_revoke'], isTrue);
        expect(permissions['bootstrap_read'], isFalse);
        final migrationFile = File('${directory.path}/0001_platform_auth.sql');
        await migrationFile.writeAsString(
          '\n-- changed after application\n',
          mode: FileMode.append,
        );
        await expectLater(runner.apply(), throwsA(isA<MigrationException>()));
        final count = await connection.execute(
          'SELECT count(*)::int AS count FROM "$schema".schema_migrations',
        );
        expect(count.single.toColumnMap()['count'], 1);
      } finally {
        await directory.delete(recursive: true);
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'failed migration rolls back all SQL in that run',
    () => _withSchema((connection, endpoint, schema) async {
      final directory = await _migrationCopy();
      try {
        await File('${directory.path}/0002_bad.sql').writeAsString(
          'CREATE TABLE {{schema}}.marker (id integer); '
          'SELECT this_statement_must_fail;',
        );
        final runner = MigrationRunner(
          connection: connection,
          migrationsDirectory: directory,
          schemaName: schema,
        );
        await expectLater(runner.apply(), throwsA(isA<PgException>()));
        final tables = await connection.execute(
          Sql.named('SELECT to_regclass(@tableName) AS table_name'),
          parameters: {'tableName': '$schema.accounts'},
        );
        expect(tables.single.toColumnMap()['table_name'], isNull);
      } finally {
        await directory.delete(recursive: true);
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'concurrent bootstrap creates one account; sessions honor disable, expiry and revocation',
    () => _withSchema((connection, endpoint, schema) async {
      await MigrationRunner(
        connection: connection,
        migrationsDirectory: _sourceMigrations(),
        schemaName: schema,
        runtimeDatabaseUser:
            Platform.environment['STOREOS_DB_USER'] ?? 'storeos',
      ).apply();
      final concurrentConnection = await Connection.open(
        endpoint,
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final hasher = PasswordHasher(memoryKiB: 64, iterations: 1);
      try {
        final attempts = await Future.wait([
          BootstrapService(
                connection: connection,
                passwordHasher: hasher,
                schemaName: schema,
              )
              .bootstrap(
                username: 'operator',
                password: 'test-only-password-24-characters',
                companyId: _company,
                locationId: _location,
              )
              .then<bool>((_) => true, onError: (_) => false),
          BootstrapService(
                connection: concurrentConnection,
                passwordHasher: hasher,
                schemaName: schema,
              )
              .bootstrap(
                username: 'operator',
                password: 'test-only-password-24-characters',
                companyId: _company,
                locationId: _location,
              )
              .then<bool>((_) => true, onError: (_) => false),
        ]);
        expect(attempts.where((success) => success), hasLength(1));
        final accounts = await connection.execute(
          'SELECT count(*)::int AS count FROM "$schema".accounts',
        );
        expect(accounts.single.toColumnMap()['count'], 1);

        final pool = Pool<void>.withEndpoints([
          endpoint,
        ], settings: const PoolSettings(sslMode: SslMode.disable));
        try {
          final store = PostgresAuthStore(pool, schemaName: schema);
          expect(await store.isReady(), isTrue);
          final auth = AuthService(
            store: store,
            passwordHasher: hasher,
            limiter: LoginLimiter(),
            companyId: _company,
            locationId: _location,
            sessionTtl: const Duration(hours: 1),
            dummyPasswordHash: await hasher.hash('test-only-dummy-password'),
          );
          final login = await auth.login(
            const LoginRequest(
              username: 'operator',
              password: 'test-only-password-24-characters',
            ),
            remoteKey: 'integration-test',
          );
          final hash = digestToken(login.token);
          expect(await store.findSession(hash), isNotNull);

          await connection.execute(
            'UPDATE "$schema".accounts SET is_active = false',
          );
          expect(await store.findSession(hash), isNull);
          await connection.execute(
            'UPDATE "$schema".accounts SET is_active = true',
          );
          await connection.execute(
            'UPDATE "$schema".auth_sessions '
            "SET created_at = now() - interval '2 hours', "
            "expires_at = now() - interval '1 hour'",
          );
          expect(await store.findSession(hash), isNull);

          final second = await auth.login(
            const LoginRequest(
              username: 'operator',
              password: 'test-only-password-24-characters',
            ),
            remoteKey: 'integration-test',
          );
          await connection.execute(
            'UPDATE "$schema".auth_sessions SET revoked_at = now() '
            'WHERE revoked_at IS NULL',
          );
          expect(await store.findSession(digestToken(second.token)), isNull);
        } finally {
          await pool.close();
        }
      } finally {
        await concurrentConnection.close();
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );
}

Future<void> _withSchema(
  Future<void> Function(Connection, Endpoint, String) testBody,
) async {
  final endpoint = _parseEndpoint(_testDatabase!);
  final connection = await Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final random = Random.secure();
  final schema =
      'storeos_test_${List<int>.generate(12, (_) => random.nextInt(256)).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join()}';
  var created = false;
  try {
    await connection.execute('CREATE SCHEMA "$schema"');
    created = true;
    await testBody(connection, endpoint, schema);
  } finally {
    if (created) {
      await connection.execute('DROP SCHEMA "$schema" CASCADE');
    }
    await connection.close();
  }
}

Endpoint _parseEndpoint(String url) {
  final uri = Uri.parse(url);
  if ((uri.scheme != 'postgres' && uri.scheme != 'postgresql') ||
      uri.host.isEmpty ||
      uri.userInfo.isEmpty ||
      uri.pathSegments.length != 1) {
    throw ArgumentError('STOREOS_TEST_DATABASE must be a PostgreSQL URL.');
  }
  final separator = uri.userInfo.indexOf(':');
  if (separator < 1) {
    throw ArgumentError('STOREOS_TEST_DATABASE must include credentials.');
  }
  return Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: Uri.decodeComponent(uri.pathSegments.single),
    username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
    password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
  );
}

Directory _sourceMigrations() =>
    Directory('${Directory.current.path}/migrations');

Future<Directory> _migrationCopy() async {
  final directory = await Directory.systemTemp.createTemp(
    'storeos_migrations_',
  );
  final source = File('${_sourceMigrations().path}/0001_platform_auth.sql');
  await source.copy('${directory.path}/0001_platform_auth.sql');
  return directory;
}
