import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/application/password_verification_limiter.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/identity_service.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/audit_service.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/event_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/platform/organization_service.dart';
import 'package:storeos_server/src/platform/plugin_service.dart';
import 'package:test/test.dart';

part 'password_change_integration_cases.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
final _testDatabase = Platform.environment['STOREOS_TEST_DATABASE'];

void main() {
  passwordChangeTests();
  for (final operation in ['session', 'plugin', 'logout']) {
    test(
      '$operation rejects a credential that expires while waiting for the company lock',
      () => _withPlatform((fixture) async {
        final plugin = PluginService(fixture.database);
        final store = PostgresAuthStore(
          fixture.database.pool,
          schemaName: fixture.schema,
        );
        const sessionToken = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
        String token;
        String table;
        SessionPrincipal? principal;
        if (operation == 'plugin') {
          token =
              (await _approve(
                    plugin,
                    fixture.admin,
                    'expiry.adapter',
                    _home,
                  ))['token']
                  as String;
          table = 'plugin_tokens';
        } else {
          token = sessionToken;
          table = 'auth_sessions';
          await fixture.owner.execute(
            Sql.named(
              'INSERT INTO "${fixture.schema}".auth_sessions '
              '(account_id, token_hash, expires_at) '
              'VALUES (CAST(@id AS uuid), @hash, clock_timestamp() + interval \'1 hour\')',
            ),
            parameters: {'id': fixture.admin.id, 'hash': digestToken(token)},
          );
          principal = await store.findSession(digestToken(token));
          expect(principal, isNotNull);
        }
        final locked = Completer<void>();
        final release = Completer<void>();
        final key = 'storeos_platform:${fixture.schema}:$_company';
        final blocker = fixture.owner.runTx((tx) async {
          await tx.execute(
            Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
            parameters: {'key': key},
          );
          locked.complete();
          await release.future;
          // Set expiry after the waiting transaction began, before it can authorize.
          await tx.execute(
            Sql.named(
              'UPDATE "${fixture.schema}".$table '
              'SET expires_at = clock_timestamp() WHERE token_hash = @hash',
            ),
            parameters: {'hash': digestToken(token)},
          );
        });
        await locked.future;
        final Future<Object?> pending = switch (operation) {
          'plugin' => plugin.organization(token),
          'logout' => store.revokeSession(digestToken(token)),
          _ => OrganizationService(fixture.database).read(principal!),
        };
        final assertion = expectLater(
          pending,
          operation == 'logout'
              ? completion(isFalse)
              : throwsA(
                  isA<PlatformFailure>().having((e) => e.status, 'status', 401),
                ),
        );
        try {
          await _waitForCompanyLock(fixture.database.pool, key);
        } finally {
          release.complete();
          await blocker;
        }
        await assertion;
      }),
      skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
    );
  }

  test(
    'audit is append-only for runtime; failed audit rolls back state and event',
    () => _withPlatform((fixture) async {
      final rights = await fixture.owner.execute(
        Sql.named(
          'SELECT has_table_privilege(@role, @audit, \'INSERT\') AS insert_ok, '
          'has_table_privilege(@role, @audit, \'UPDATE\') AS update_ok, '
          'has_table_privilege(@role, @audit, \'DELETE\') AS delete_ok, '
          'has_table_privilege(@role, @audit, \'TRUNCATE\') AS truncate_ok',
        ),
        parameters: {
          'role': fixture.runtimeUser,
          'audit': '${fixture.schema}.audit_entries',
        },
      );
      final grants = rights.single.toColumnMap();
      expect(grants['insert_ok'], isTrue);
      expect(grants['update_ok'], isFalse);
      expect(grants['delete_ok'], isFalse);
      expect(grants['truncate_ok'], isFalse);
      await expectLater(
        fixture.database.pool.execute(
          'UPDATE "${fixture.schema}".audit_entries SET changes = \'{}\'::jsonb',
        ),
        throwsA(isA<PgException>()),
      );

      await fixture.owner.execute(
        'REVOKE INSERT ON "${fixture.schema}".audit_entries '
        'FROM "${fixture.runtimeUser}"',
      );
      try {
        await expectLater(
          fixture.database.runAuthorized(fixture.admin, 'organization.write', (
            tx,
            actor,
          ) async {
            await tx.execute(
              'UPDATE "${fixture.schema}".locations '
              "SET name = 'must roll back', version = version + 1 "
              "WHERE id = '$_home'::uuid",
            );
            await fixture.database.publishOrganizationEvent(
              tx,
              actor,
              'organization.location.updated',
              'location',
              _home,
              2,
              const {
                'id': _home,
                'companyId': _company,
                'name': 'must roll back',
                'version': 2,
              },
              locationId: _home,
            );
            await fixture.database.audit(
              tx,
              actor,
              'location.updated',
              'location',
              _home,
              locationId: _home,
              changes: const {'name': 'must roll back'},
            );
          }),
          throwsA(isA<PgException>()),
        );
      } finally {
        await fixture.owner.execute(
          'GRANT INSERT ON "${fixture.schema}".audit_entries '
          'TO "${fixture.runtimeUser}"',
        );
      }
      final state = await fixture.owner.execute(
        'SELECT name, version FROM "${fixture.schema}".locations '
        "WHERE id = '$_home'::uuid",
      );
      expect(state.single.toColumnMap()['name'], isNull);
      expect(state.single.toColumnMap()['version'], 1);
      final events = await fixture.owner.execute(
        'SELECT count(*)::int AS count FROM "${fixture.schema}".event_outbox',
      );
      expect(events.single.toColumnMap()['count'], 0);
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'concurrent dispatch and cursor pages preserve events without historical plugin grants',
    () => _withPlatform((fixture) async {
      Future<void> publish(int version) =>
          fixture.database.runAuthorized(fixture.admin, 'organization.write', (
            tx,
            actor,
          ) async {
            await fixture.database.publishOrganizationEvent(
              tx,
              actor,
              'organization.location.updated',
              'location',
              _home,
              version,
              {
                'id': _home,
                'companyId': _company,
                'name': 'Page $version',
                'version': version,
              },
              locationId: _home,
            );
            await fixture.database.audit(
              tx,
              actor,
              'organization.location.updated',
              'location',
              _home,
              locationId: _home,
              changes: {'version': version},
            );
          });
      await publish(1);
      final plugin = PluginService(fixture.database);
      final approval = await _approve(
        plugin,
        fixture.admin,
        'pages.adapter',
        _home,
      );
      final token = approval['token'] as String;
      for (var version = 2; version <= 54; version++) {
        await publish(version);
      }
      // Equal timestamps exercise the UUID tie-breaker in the admin cursor.
      await fixture.owner.execute(
        'UPDATE "${fixture.schema}".event_outbox '
        'SET recorded_at = statement_timestamp() WHERE aggregate_version > 1',
      );
      final dispatched = await Future.wait([
        EventBus(database: fixture.database).dispatchOnce(limit: 100),
        EventBus(database: fixture.database).dispatchOnce(limit: 100),
      ]);
      expect(dispatched.reduce((a, b) => a + b), 54);

      final events = EventService(fixture.database);
      final first = await events.list(fixture.admin);
      final second = await events.list(
        fixture.admin,
        after: first['nextCursor'] as String,
      );
      expect(first['items'], hasLength(50));
      expect(second['items'], hasLength(4));
      expect(second['nextCursor'], isNull);
      final ids = [
        ...first['items'] as List,
        ...second['items'] as List,
      ].map((dynamic item) => item['eventId']).toSet();
      expect(ids, hasLength(54));

      final inboxFirst = await plugin.events(token);
      final inboxSecond = await plugin.events(
        token,
        after: inboxFirst['nextCursor'] as String,
      );
      expect(inboxFirst['items'], hasLength(50));
      expect(inboxSecond['items'], hasLength(3));
      final deliveries = [
        ...inboxFirst['items'] as List,
        ...inboxSecond['items'] as List,
      ];
      expect(
        deliveries.map((dynamic item) => item['eventId']).toSet(),
        hasLength(53),
      );
      expect(
        deliveries.every(
          (dynamic item) => (item['payload']['version'] as int) > 1,
        ),
        isTrue,
      );

      final audit = AuditService(fixture.database);
      final auditFirst = await audit.list(fixture.admin);
      final auditSecond = await audit.list(
        fixture.admin,
        after: auditFirst['nextCursor'] as String,
      );
      expect(auditFirst['items'], hasLength(50));
      expect(auditSecond['nextCursor'], isNull);
      final auditIds = [
        ...auditFirst['items'] as List,
        ...auditSecond['items'] as List,
      ].map((dynamic item) => item['id']).toList();
      expect(auditIds.toSet(), hasLength(auditIds.length));
      expect(auditIds.length, greaterThan(54));
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'plugin approvals cannot expand manifest rights or cross company scope',
    () => _withPlatform((fixture) async {
      final plugin = PluginService(fixture.database);
      final approved = await _approve(
        plugin,
        fixture.admin,
        'rights.adapter',
        _home,
      );
      await plugin.disable(fixture.admin, 'rights.adapter', {
        'expectedVersion': 2,
      });
      await expectLater(
        plugin.approve(fixture.admin, 'rights.adapter', {
          'expectedVersion': 3,
          'locationId': _home,
          'permissions': ['identity.write'],
          'subscriptions': <String>[],
        }),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 400)),
      );
      final limited = await plugin.approve(fixture.admin, 'rights.adapter', {
        'expectedVersion': 3,
        'locationId': _home,
        'permissions': ['organization.read'],
        'subscriptions': <String>[],
      });
      final token = limited['token'] as String;
      await expectLater(
        plugin.events(token),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      await expectLater(
        plugin.organization(approved['token'] as String),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 401)),
      );
      final otherCompany = PlatformDatabase(
        fixture.database.pool,
        schemaName: fixture.schema,
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        PluginService(otherCompany).organization(token),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 401)),
      );
      await expectLater(
        () => OrganizationService(otherCompany).read(fixture.admin),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'event retry reaches dead letter, replay keeps id, and inbox receipt dedupes by scope',
    () => _withPlatform((fixture) async {
      await fixture.owner.execute(
        'INSERT INTO "${fixture.schema}".locations (id, company_id) '
        "VALUES ('$_other'::uuid, '$_company'::uuid)",
      );
      final plugin = PluginService(fixture.database);
      final home = await _approve(plugin, fixture.admin, 'home.adapter', _home);
      final foreign = await _approve(
        plugin,
        fixture.admin,
        'other.adapter',
        _other,
      );
      final token = home['token'] as String;
      final foreignToken = foreign['token'] as String;

      await fixture.database.runAuthorized(
        fixture.admin,
        'organization.write',
        (tx, actor) => fixture.database.publishOrganizationEvent(
          tx,
          actor,
          'organization.location.updated',
          'location',
          _home,
          2,
          const {
            'id': _home,
            'companyId': _company,
            'name': 'New',
            'version': 2,
          },
          locationId: _home,
        ),
      );
      final event = await fixture.owner.execute(
        'SELECT id::text AS id FROM "${fixture.schema}".event_outbox',
      );
      final eventId = event.single.toColumnMap()['id'] as String;
      final bus = EventBus(database: fixture.database);
      await fixture.owner.execute(
        'REVOKE INSERT ON "${fixture.schema}".plugin_inbox '
        'FROM "${fixture.runtimeUser}"',
      );
      try {
        for (var attempt = 1; attempt <= 5; attempt++) {
          expect(await bus.dispatchOnce(), 0);
          final state = await fixture.owner.execute(
            'SELECT attempts, status FROM "${fixture.schema}".event_outbox',
          );
          expect(state.single.toColumnMap()['attempts'], attempt);
          expect(
            state.single.toColumnMap()['status'],
            attempt == 5 ? 'dead_letter' : 'pending',
          );
          if (attempt < 5) {
            await fixture.owner.execute(
              'UPDATE "${fixture.schema}".event_outbox '
              'SET next_attempt_at = now()',
            );
          }
        }
      } finally {
        await fixture.owner.execute(
          'GRANT INSERT ON "${fixture.schema}".plugin_inbox '
          'TO "${fixture.runtimeUser}"',
        );
      }
      expect((await plugin.events(token))['items'], isEmpty);
      final replayed = await EventService(
        fixture.database,
      ).replay(fixture.admin, eventId);
      expect(replayed['eventId'], eventId);
      expect(await bus.dispatchOnce(), 1);
      expect(await bus.dispatchOnce(), 0);
      expect((await plugin.events(token))['items'], hasLength(1));
      expect((await plugin.events(foreignToken))['items'], isEmpty);
      final receipt = await fixture.owner.execute(
        'SELECT count(*)::int AS count FROM "${fixture.schema}".event_receipts',
      );
      final inbox = await fixture.owner.execute(
        'SELECT count(*)::int AS count FROM "${fixture.schema}".plugin_inbox',
      );
      expect(receipt.single.toColumnMap()['count'], 1);
      expect(inbox.single.toColumnMap()['count'], 1);
      final audit = await AuditService(fixture.database).list(fixture.admin);
      expect(
        (audit['items'] as List).any(
          (dynamic row) => row['action'] == 'event.replayed',
        ),
        isTrue,
      );
      expect(audit.toString(), isNot(contains(token)));
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );

  test(
    'token read waits for scope change and old token never revives on reapproval',
    () => _withPlatform((fixture) async {
      final plugin = PluginService(fixture.database);
      final first = await _approve(
        plugin,
        fixture.admin,
        'rotate.adapter',
        _home,
      );
      final oldToken = first['token'] as String;
      final gate = Completer<void>();
      final locked = Completer<void>();
      final blocker = fixture.owner.runTx((tx) async {
        await tx.execute(
          Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
          parameters: {'key': 'storeos_platform:${fixture.schema}:$_company'},
        );
        locked.complete();
        await gate.future;
        await tx.execute(
          'UPDATE "${fixture.schema}".plugin_tokens SET revoked_at = now() '
          "WHERE plugin_id = 'rotate.adapter' AND revoked_at IS NULL",
        );
        await tx.execute(
          'UPDATE "${fixture.schema}".plugin_registrations '
          "SET status = 'disabled', version = version + 1, "
          "location_id = NULL, permissions = '{}'::text[], "
          "subscriptions = '{}'::text[] WHERE id = 'rotate.adapter'",
        );
      });
      await locked.future;
      final pendingRead = plugin.organization(oldToken);
      gate.complete();
      await blocker;
      await expectLater(pendingRead, throwsA(isA<PlatformFailure>()));
      final disabled = (await plugin.list(fixture.admin))['plugins'] as List;
      final currentVersion = (disabled.single as Map)['version'] as int;
      final second = await plugin.approve(fixture.admin, 'rotate.adapter', {
        'expectedVersion': currentVersion,
        'locationId': _home,
        'permissions': ['organization.read', 'events.read'],
        'subscriptions': ['organization.location.updated'],
      });
      await expectLater(
        plugin.organization(oldToken),
        throwsA(isA<PlatformFailure>()),
      );
      expect(
        (await plugin.organization(second['token'] as String))['locations'],
        hasLength(1),
      );
    }),
    skip: _testDatabase == null ? 'STOREOS_TEST_DATABASE is not set' : false,
  );
}

Future<Map<String, dynamic>> _approve(
  PluginService plugin,
  SessionPrincipal admin,
  String id,
  String locationId,
) async {
  final registered = await plugin.register(admin, {
    'manifest': {
      'id': id,
      'name': id,
      'version': '1.0.0',
      'vendor': 'StoreOS integration tests',
      'coreApiVersion': 1,
      'capabilities': ['organization.read', 'events.read'],
      'permissions': ['organization.read', 'events.read'],
      'subscriptions': ['organization.location.updated'],
      'configurationSchema': {
        'type': 'object',
        'properties': <String, dynamic>{},
        'additionalProperties': false,
      },
    },
  });
  return plugin.approve(admin, id, {
    'expectedVersion': registered['version'],
    'locationId': locationId,
    'permissions': ['organization.read', 'events.read'],
    'subscriptions': ['organization.location.updated'],
  });
}

Future<void> _waitForCompanyLock(Pool<void> pool, String key) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final waiting = await pool.execute(
      Sql.named(
        'SELECT 1 FROM pg_locks WHERE locktype = \'advisory\' '
        'AND NOT granted AND objid = (hashtext(@key)::bigint & 4294967295)::oid',
      ),
      parameters: {'key': key},
    );
    if (waiting.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('The request did not wait for the company lock.');
}

class _Fixture {
  const _Fixture({
    required this.owner,
    required this.database,
    required this.admin,
    required this.schema,
    required this.runtimeUser,
  });

  final Connection owner;
  final PlatformDatabase database;
  final SessionPrincipal admin;
  final String schema;
  final String runtimeUser;
}

Future<void> _withPlatform(Future<void> Function(_Fixture) body) async {
  final uri = Uri.parse(_testDatabase!);
  final separator = uri.userInfo.indexOf(':');
  if (separator < 1 || uri.pathSegments.length != 1) {
    throw StateError(
      'STOREOS_TEST_DATABASE requires a user, password and database.',
    );
  }
  final endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: Uri.decodeComponent(uri.pathSegments.single),
    username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
    password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
  );
  final passwordFile = Platform.environment['STOREOS_DB_PASSWORD_FILE'];
  if (passwordFile == null) {
    throw StateError(
      'STOREOS_DB_PASSWORD_FILE required for runtime privilege tests.',
    );
  }
  final runtimeUser = Platform.environment['STOREOS_DB_USER'] ?? 'storeos';
  final runtimeEndpoint = Endpoint(
    host: endpoint.host,
    port: endpoint.port,
    database: endpoint.database,
    username: runtimeUser,
    password: File(passwordFile).readAsStringSync().trim(),
  );
  final owner = await Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final schema = 'storeos_security_${newUuid().replaceAll('-', '')}';
  Pool<void>? runtimePool;
  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: runtimeUser,
    ).apply();
    final id =
        await BootstrapService(
          connection: owner,
          passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
          schemaName: schema,
        ).bootstrap(
          username: 'security_admin',
          password: 'test-only-password-24-characters',
          companyId: _company,
          locationId: _home,
        );
    runtimePool = Pool<void>.withEndpoints(
      [runtimeEndpoint],
      settings: const PoolSettings(
        sslMode: SslMode.disable,
        maxConnectionCount: 4,
      ),
    );
    final database = PlatformDatabase(
      runtimePool,
      schemaName: schema,
      companyId: _company,
      locationId: _home,
    );
    await body(
      _Fixture(
        owner: owner,
        database: database,
        admin: SessionPrincipal(
          id: id,
          username: 'security_admin',
          companyId: _company,
          locationId: _home,
        ),
        schema: schema,
        runtimeUser: runtimeUser,
      ),
    );
  } finally {
    await runtimePool?.close();
    await owner.execute('DROP SCHEMA IF EXISTS "$schema" CASCADE');
    await owner.close();
  }
}
