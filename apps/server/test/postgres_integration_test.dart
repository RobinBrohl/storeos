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
import 'package:storeos_server/src/platform/identity_service.dart';
import 'package:storeos_server/src/platform/organization_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
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
    'P0 bootstrap account upgrades without changing IDs or password hash',
    () => _withSchema((connection, endpoint, schema) async {
      final p0Directory = await _migrationCopy();
      try {
        await MigrationRunner(
          connection: connection,
          migrationsDirectory: p0Directory,
          schemaName: schema,
        ).apply();
        final passwordHash = await PasswordHasher(
          memoryKiB: 64,
          iterations: 1,
        ).hash('unchanged-p0-password');
        final originalId = newUuid();
        await connection.execute(
          Sql.named(
            'INSERT INTO "$schema".accounts '
            '(id, username, username_key, password_hash, company_id, location_id) '
            'VALUES (CAST(@id AS uuid), @username, @usernameKey, @hash, '
            'CAST(@companyId AS uuid), CAST(@locationId AS uuid))',
          ),
          parameters: {
            'id': originalId,
            'username': 'operator',
            'usernameKey': 'operator',
            'hash': passwordHash,
            'companyId': _company,
            'locationId': _location,
          },
        );
        await connection.execute(
          Sql.named(
            'INSERT INTO "$schema".bootstrap_state (account_id) '
            'VALUES (CAST(@id AS uuid))',
          ),
          parameters: {'id': originalId},
        );
        expect(
          await MigrationRunner(
            connection: connection,
            migrationsDirectory: _sourceMigrations(),
            schemaName: schema,
          ).apply(),
          [
            '0002_platform_organization',
            '0003_platform_events_plugins',
            '0004_employee_identity_and_audit',
            '0005_task_templates',
            '0006_shifts_and_task_instances',
          ],
        );
        final account = await connection.execute(
          'SELECT id::text AS id, password_hash, role, version '
          'FROM "$schema".accounts',
        );
        final row = account.single.toColumnMap();
        expect(row['id'], originalId);
        expect(row['password_hash'], passwordHash);
        expect(row['role'], 'admin');
        expect(row['version'], 1);
        final company = await connection.execute(
          'SELECT id::text AS id, name FROM "$schema".companies',
        );
        expect(company.single.toColumnMap()['id'], _company);
        expect(company.single.toColumnMap()['name'], isNull);
        final location = await connection.execute(
          'SELECT id::text AS id, name FROM "$schema".locations',
        );
        expect(location.single.toColumnMap()['id'], _location);
        expect(location.single.toColumnMap()['name'], isNull);
      } finally {
        await p0Directory.delete(recursive: true);
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
          final previouslyValid = await auth.authenticate(second.token);
          await connection.execute(
            'UPDATE "$schema".auth_sessions SET revoked_at = now() '
            'WHERE revoked_at IS NULL',
          );
          expect(await store.findSession(digestToken(second.token)), isNull);
          final platform = PlatformDatabase(
            pool,
            schemaName: schema,
            companyId: _company,
            locationId: _location,
          );
          await expectLater(
            IdentityService(platform, hasher).context(previouslyValid),
            throwsA(
              isA<PlatformFailure>().having(
                (failure) => failure.status,
                'status',
                401,
              ),
            ),
          );

          final oldAccount = await store.findAccount('operator');
          await connection.execute(
            Sql.named('UPDATE "$schema".accounts SET password_hash = @hash'),
            parameters: {'hash': await hasher.hash('new-test-password')},
          );
          await expectLater(
            store.createSession(
              accountId: oldAccount!.id,
              tokenHash: digestToken('test-invalid-after-password-reset'),
              expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
              expectedPasswordHash: oldAccount.passwordHash,
              expectedCompanyId: _company,
            ),
            throwsA(isA<SessionCreationRejected>()),
          );
        } finally {
          await pool.close();
        }
      } finally {
        await concurrentConnection.close();
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'organization setup cannot be bypassed and audit failure rolls back state and event',
    () => _withSchema((connection, endpoint, schema) async {
      await MigrationRunner(
        connection: connection,
        migrationsDirectory: _sourceMigrations(),
        schemaName: schema,
      ).apply();
      final adminId =
          await BootstrapService(
            connection: connection,
            passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
            schemaName: schema,
          ).bootstrap(
            username: 'operator',
            password: 'test-only-password-24-characters',
            companyId: _company,
            locationId: _location,
          );
      final bootstrapAudit = await connection.execute(
        'SELECT actor_kind, action, changes FROM "$schema".audit_entries '
        "WHERE action = 'platform.bootstrapped'",
      );
      expect(bootstrapAudit, hasLength(1));
      expect(bootstrapAudit.single.toColumnMap()['actor_kind'], 'system');
      expect(
        bootstrapAudit.single.toColumnMap()['changes'].toString(),
        isNot(contains('password')),
      );
      final pool = Pool<void>.withEndpoints([
        endpoint,
      ], settings: const PoolSettings(sslMode: SslMode.disable));
      try {
        final service = OrganizationService(
          PlatformDatabase(
            pool,
            schemaName: schema,
            companyId: _company,
            locationId: _location,
          ),
        );
        final principal = SessionPrincipal(
          id: adminId,
          username: 'operator',
          companyId: _company,
          locationId: _location,
        );
        await expectLater(
          service.renameLocation(principal, _location, {
            'name': 'Bypass',
            'expectedVersion': 1,
          }),
          throwsA(
            isA<PlatformFailure>().having(
              (failure) => failure.code,
              'code',
              'setup_required',
            ),
          ),
        );
        final setup = await service.setup(principal, {
          'companyName': 'First company',
          'locationName': 'First location',
        });
        final company = setup['company']! as Map<String, dynamic>;
        expect(company['version'], 2);
        final beforeEvents = await connection.execute(
          'SELECT count(*)::int AS count FROM "$schema".event_outbox',
        );
        await connection.execute(
          'ALTER TABLE "$schema".audit_entries '
          "ADD CONSTRAINT reject_company_change CHECK (action <> 'organization.company.updated')",
        );
        await expectLater(
          service.renameCompany(principal, {
            'name': 'Must rollback',
            'expectedVersion': 2,
          }),
          throwsA(isA<PgException>()),
        );
        final after = await service.read(principal);
        final unchanged = after['company']! as Map<String, dynamic>;
        expect(unchanged['name'], 'First company');
        expect(unchanged['version'], 2);
        final afterEvents = await connection.execute(
          'SELECT count(*)::int AS count FROM "$schema".event_outbox',
        );
        expect(
          afterEvents.single.toColumnMap()['count'],
          beforeEvents.single.toColumnMap()['count'],
        );
      } finally {
        await pool.close();
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'concurrent demotions preserve one active administrator',
    () => _withSchema((connection, endpoint, schema) async {
      await MigrationRunner(
        connection: connection,
        migrationsDirectory: _sourceMigrations(),
        schemaName: schema,
      ).apply();
      final firstId =
          await BootstrapService(
            connection: connection,
            passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
            schemaName: schema,
          ).bootstrap(
            username: 'operator',
            password: 'test-only-password-24-characters',
            companyId: _company,
            locationId: _location,
          );
      final pool = Pool<void>.withEndpoints([
        endpoint,
      ], settings: const PoolSettings(sslMode: SslMode.disable));
      try {
        final database = PlatformDatabase(
          pool,
          schemaName: schema,
          companyId: _company,
          locationId: _location,
        );
        final organization = OrganizationService(database);
        final identity = IdentityService(
          database,
          PasswordHasher(memoryKiB: 64, iterations: 1),
        );
        final first = SessionPrincipal(
          id: firstId,
          username: 'operator',
          companyId: _company,
          locationId: _location,
        );
        await organization.setup(first, {
          'companyName': 'Admin company',
          'locationName': 'Admin location',
        });
        final secondId = newUuid();
        await identity.createUser(first, {
          'id': secondId,
          'username': 'second_admin',
          'password': 'test-only-password-24-characters',
          'locationId': _location,
          'role': 'admin',
        });
        final second = SessionPrincipal(
          id: secondId,
          username: 'second_admin',
          companyId: _company,
          locationId: _location,
        );
        Future<int> demote(SessionPrincipal principal) async {
          try {
            await identity.updateUser(principal, principal.id, {
              'role': 'viewer',
              'isActive': true,
              'expectedVersion': 1,
            });
            return 200;
          } on PlatformFailure catch (failure) {
            return failure.status;
          }
        }

        final outcomes = await Future.wait([demote(first), demote(second)]);
        expect(outcomes..sort(), [200, 409]);
        final administrators = await connection.execute(
          'SELECT count(*)::int AS count FROM "$schema".accounts '
          "WHERE role = 'admin' AND is_active",
        );
        expect(administrators.single.toColumnMap()['count'], 1);
      } finally {
        await pool.close();
      }
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'P1 upgrade preserves populated identity and audit history without inventing correlations',
    () => _withSchema((connection, endpoint, schema) async {
      final directory = await Directory.systemTemp.createTemp(
        'storeos_p1_upgrade_',
      );
      try {
        for (final name in [
          '0001_platform_auth',
          '0002_platform_organization',
          '0003_platform_events_plugins',
        ]) {
          await File(
            '${_sourceMigrations().path}/$name.sql',
          ).copy('${directory.path}/$name.sql');
        }
        await MigrationRunner(
          connection: connection,
          migrationsDirectory: directory,
          schemaName: schema,
        ).apply();
        final id = newUuid();
        final hash = await PasswordHasher(
          memoryKiB: 64,
          iterations: 1,
        ).hash('preserved-test-password');
        await connection.execute(
          'INSERT INTO "$schema".companies(id, name) VALUES (\'$_company\', \'Existing\')',
        );
        await connection.execute(
          'INSERT INTO "$schema".locations(id, company_id, name) VALUES (\'$_location\', \'$_company\', \'Home\')',
        );
        await connection.execute(
          Sql.named(
            'INSERT INTO "$schema".accounts(id, username, username_key, password_hash, company_id, location_id, role) '
            'VALUES (CAST(@id AS uuid), \'existing\', \'existing\', @hash, CAST(@company AS uuid), CAST(@location AS uuid), \'admin\')',
          ),
          parameters: {
            'id': id,
            'hash': hash,
            'company': _company,
            'location': _location,
          },
        );
        await connection.execute(
          'INSERT INTO "$schema".audit_entries(actor_kind, actor_id, company_id, location_id, action, entity_type, entity_id) '
          'VALUES (\'user\', \'$id\', \'$_company\', \'$_location\', \'identity.user.created\', \'user\', \'$id\')',
        );
        final before = await connection.execute(
          'SELECT occurred_at FROM "$schema".audit_entries',
        );
        final runner = MigrationRunner(
          connection: connection,
          migrationsDirectory: _sourceMigrations(),
          schemaName: schema,
          runtimeDatabaseUser:
              Platform.environment['STOREOS_DB_USER'] ?? 'storeos',
        );
        expect(await runner.apply(), [
          '0004_employee_identity_and_audit',
          '0005_task_templates',
          '0006_shifts_and_task_instances',
        ]);
        expect(await runner.apply(), isEmpty);
        final account = (await connection.execute(
          'SELECT id::text, password_hash, role, version FROM "$schema".accounts',
        )).single.toColumnMap();
        expect(account['id'], id);
        expect(account['password_hash'], hash);
        expect(account['role'], 'admin');
        expect(account['version'], 1);
        final audit = (await connection.execute(
          'SELECT occurred_at, correlation_id, changes FROM "$schema".audit_entries',
        )).single.toColumnMap();
        expect(
          audit['occurred_at'],
          before.single.toColumnMap()['occurred_at'],
        );
        expect(audit['correlation_id'], isNull);
        expect(audit['changes'], isEmpty);
      } finally {
        await directory.delete(recursive: true);
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
