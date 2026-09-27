import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/employee_application.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
const _password = 'employee-test-only-password-strong';
final _url = Platform.environment['STOREOS_TEST_DATABASE'];

void main() {
  test(
    'rename and link audit failures preserve profile, mapping and existing sessions',
    () => _withFixture((f) async {
      final employee = await f.employee('Preserved profile');
      final account = await f.account('preserved_account');
      final token = await f.login('preserved_account');
      final before = (await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".audit_entries',
      )).single.first;
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/employees/${employee.id}/rename',
          body: {'displayName': 'Must roll back', 'expectedVersion': 1},
          expected: 503,
        );
        await f.call(
          'POST',
          '/employees/${employee.id}/account-link',
          body: f.linkInput(employee, account),
          expected: 503,
        );
        // A read authenticates the same session without appending another audit entry.
        await f.call('GET', '/context', token: token);
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
      final current = (await f.call('GET', '/employees/${employee.id}')).body;
      expect(current['displayName'], employee.displayName);
      expect(current['version'], 1);
      expect(
        (await f.call(
          'GET',
          '/employees/${employee.id}/account-link',
        )).body['link'],
        isNull,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".account_employee_links',
        )).single.first,
        0,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries',
        )).single.first,
        before,
      );
      // Retrying a no-op rename does not increment version or create a false change.
      await f.call(
        'POST',
        '/employees/${employee.id}/rename',
        body: {'displayName': employee.displayName, 'expectedVersion': 1},
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries',
        )).single.first,
        before,
      );
    }),
    skip: _skip,
  );

  test(
    'employee HTTP workflow persists, correlates audit, revokes access and survives server restart',
    () => _withFixture((f) async {
      final employee = await f.employee('Operational name');
      final account = await f.account('employee_one');
      final beforeLink = await f.login('employee_one');
      final link = await f.link(employee, account);
      await f.call('GET', '/employees/me', token: beforeLink, expected: 401);
      var token = await f.login('employee_one');
      final mine = EmployeeDto.fromJson(
        (await f.call('GET', '/employees/me', token: token)).body,
      );
      expect(mine.id, employee.id);
      expect(mine.assignedUntil, isNull);
      final renamed = await f.call(
        'POST',
        '/employees/${employee.id}/rename',
        body: {'displayName': 'Renamed', 'expectedVersion': 1},
      );
      expect(renamed.body['version'], 2);
      await f.restart();
      expect(
        (await f.call(
          'GET',
          '/employees/me',
          token: token,
        )).body['displayName'],
        'Renamed',
      );
      final result = await f.call(
        'POST',
        '/employees/${employee.id}/deactivate',
        body: {'expectedVersion': 2},
      );
      expect(result.body['isActive'], false);
      expect(result.body['assignedUntil'], isNotNull);
      await f.call('GET', '/employees/me', token: token, expected: 401);
      token = await f.login('employee_one');
      await f.call('GET', '/employees/me', token: token, expected: 404);
      expect(
        (await f.call(
          'GET',
          '/employees/${employee.id}/account-link',
        )).body['link'],
        isNull,
      );
      final history = await f.owner.execute(
        'SELECT version, revoked_at FROM "${f.schema}".account_employee_links',
      );
      expect(history.single.toColumnMap()['version'], link.version + 1);
      expect(history.single.toColumnMap()['revoked_at'], isNotNull);
      final audit = await f.owner.execute(
        Sql.named(
          'SELECT action, changes FROM "${f.schema}".audit_entries '
          'WHERE correlation_id = CAST(@id AS uuid) ORDER BY id',
        ),
        parameters: {'id': result.correlation},
      );
      expect(audit.map((r) => r.toColumnMap()['action']), [
        'identity.employee.unlinked',
        'people.employee.deactivated',
      ]);
      final all = (await f.call('GET', '/audit')).body;
      expect(jsonEncode(all), isNot(contains('Operational name')));
      expect(jsonEncode(all), isNot(contains('Renamed')));
      expect(jsonEncode(all), isNot(contains(_password)));
      await f.call(
        'POST',
        '/employees/${employee.id}/rename',
        body: {'displayName': 'No', 'expectedVersion': 3},
        expected: 409,
      );
    }),
    skip: _skip,
  );

  test(
    'role matrix, foreign IDs and mismatched locations cannot expose or link profiles',
    () => _withFixture((f) async {
      final employee = await f.employee('Private employee');
      for (final role in ['viewer', 'auditor', 'employee']) {
        final account = await f.account('role_$role', role: role);
        final token = await f.login('role_$role');
        await f.call('GET', '/employees', token: token, expected: 403);
        await f.call(
          'GET',
          '/employees/${employee.id}',
          token: token,
          expected: 403,
        );
        await f.call(
          'GET',
          '/employees/${employee.id}/account-link',
          token: token,
          expected: 403,
        );
        await f.call(
          'POST',
          '/employees',
          token: token,
          body: {'id': newUuid(), 'displayName': 'No', 'locationId': _home},
          expected: 403,
        );
        await f.call(
          'POST',
          '/employees/${employee.id}/deactivate',
          token: token,
          body: {'expectedVersion': 1},
          expected: 403,
        );
        await f.call(
          'GET',
          '/employees/me',
          token: token,
          expected: role == 'employee' ? 404 : 403,
        );
        if (role == 'auditor') {
          await f.call('GET', '/audit', token: token);
          await f.call('GET', '/events', token: token);
          await f.call('GET', '/users', token: token, expected: 403);
        }
        if (role == 'employee') {
          await f.link(employee, account);
          final linkedToken = await f.login('role_employee');
          final org = (await f.call(
            'GET',
            '/organization',
            token: linkedToken,
          )).body;
          expect((org['locations'] as List), hasLength(1));
          final otherEmployee = await f.employee('Other private employee');
          await f.call(
            'GET',
            '/employees/${otherEmployee.id}',
            token: linkedToken,
            expected: 403,
          );
          expect(
            (await f.call(
              'GET',
              '/employees/me',
              token: linkedToken,
            )).body['id'],
            employee.id,
          );
        }
      }
      await f.call('GET', '/employees', token: '', expected: 401);
      await f.call('GET', '/employees/${newUuid()}', expected: 404);
      final another = await f.employee('Another profile');
      final remote = await f.account('other_location', location: _other);
      await f.call(
        'POST',
        '/employees/${another.id}/account-link',
        body: f.linkInput(another, remote),
        expected: 404,
      );
      final foreignDatabase = PlatformDatabase(
        f.pool,
        schemaName: f.schema,
        companyId: newUuid(),
        locationId: _home,
      );
      await expectLater(
        () => EmployeeApplication(foreignDatabase).list(f.adminPrincipal),
        throwsA(isA<PlatformFailure>()),
      );
      final registered = await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': 'employee.test',
            'name': 'Organization reader',
            'version': '1.0.0',
            'vendor': 'Tests',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        },
      );
      final approved = await f.call(
        'POST',
        '/plugins/employee.test/approve',
        body: {
          'expectedVersion': registered.body['version'],
          'locationId': _home,
          'permissions': ['organization.read'],
          'subscriptions': <String>[],
        },
      );
      await f.call(
        'GET',
        '/employees/me',
        token: approved.body['token'] as String,
        expected: 401,
      );
    }),
    skip: _skip,
  );

  test(
    'parallel links preserve one-to-one identity and retry/version constraints',
    () => _withFixture((f) async {
      final first = await f.employee('First');
      final second = await f.employee('Second');
      final a = await f.account('concurrent_a');
      final b = await f.account('concurrent_b');
      Future<int> attempt(
        EmployeeDto employee,
        PlatformUserDto account,
      ) async => (await f.call(
        'POST',
        '/employees/${employee.id}/account-link',
        body: f.linkInput(employee, account),
        expected: null,
      )).status;
      var results = await Future.wait([attempt(first, a), attempt(first, b)]);
      expect(results..sort(), [201, 409]);
      final linked = EmployeeLinkDto.fromJson(
        (await f.call(
              'GET',
              '/employees/${first.id}/account-link',
            )).body['link']
            as Map<String, dynamic>,
      );
      await f.call(
        'POST',
        '/employee-links/${linked.id}/revoke',
        body: {'expectedVersion': linked.version},
      );
      results = await Future.wait([attempt(first, a), attempt(second, a)]);
      expect(results..sort(), [201, 409]);
      await f.call(
        'POST',
        '/employees',
        body: {'id': first.id, 'displayName': 'First', 'locationId': _home},
        expected: 409,
      );
      await f.call(
        'POST',
        '/employees/${first.id}/rename',
        body: {'displayName': 'Changed', 'expectedVersion': 1},
      );
      await f.call(
        'POST',
        '/employees/${first.id}/rename',
        body: {'displayName': 'Stale', 'expectedVersion': 1},
        expected: 409,
      );
      await f.call(
        'POST',
        '/employees/${first.id}/deactivate',
        body: {'expectedVersion': 1},
        expected: 409,
      );
      await f.call(
        'POST',
        '/employees',
        body: {
          'id': newUuid(),
          'displayName': 'Bad\u0000name',
          'locationId': _home,
        },
        expected: 400,
      );
      await f.call(
        'POST',
        '/employees',
        body: {
          'id': newUuid(),
          'displayName': 'Bad',
          'locationId': _home,
          'companyId': newUuid(),
        },
        expected: 400,
      );
      final count = await f.owner.execute(
        'SELECT count(*)::int AS count FROM "${f.schema}".employees',
      );
      expect(count.single.toColumnMap()['count'], 2);
      // Constraints also protect the boundary without application checks.
      await expectLater(
        f.pool.execute(
          Sql.named(
            'INSERT INTO "${f.schema}".account_employee_links '
            '(id, account_id, employee_id, company_id, location_id) VALUES '
            '(gen_random_uuid(), CAST(@account AS uuid), CAST(@employee AS uuid), CAST(@company AS uuid), CAST(@location AS uuid))',
          ),
          parameters: {
            'account': b.id,
            'employee': second.id,
            'company': _company,
            'location': _other,
          },
        ),
        throwsA(isA<PgException>()),
      );
    }),
    skip: _skip,
  );

  test(
    'audit failure rolls back employee, link and session revocation together',
    () => _withFixture((f) async {
      final employee = await f.employee('Rollback profile');
      final account = await f.account('rollback_employee');
      final link = await f.link(employee, account);
      final token = await f.login('rollback_employee');
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/employees/${employee.id}/deactivate',
          body: {'expectedVersion': 1},
          expected: 503,
        );
        await f.call(
          'POST',
          '/employees',
          body: {
            'id': newUuid(),
            'displayName': 'No commit',
            'locationId': _home,
          },
          expected: 503,
        );
        await f.call(
          'POST',
          '/employee-links/${link.id}/revoke',
          body: {'expectedVersion': 1},
          expected: 503,
        );
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
      expect(
        (await f.call('GET', '/employees/me', token: token)).body['version'],
        1,
      );
      expect(
        (await f.call('GET', '/employees')).body['employees'],
        hasLength(1),
      );
      expect(
        (await f.call(
          'GET',
          '/employees/${employee.id}/account-link',
        )).body['link']['id'],
        link.id,
      );
      await expectLater(
        f.pool.execute(
          'UPDATE "${f.schema}".audit_entries SET correlation_id = gen_random_uuid()',
        ),
        throwsA(isA<PgException>()),
      );
    }),
    skip: _skip,
  );

  test(
    'link versus deactivation race never leaves active access to an inactive employee',
    () => _withFixture((f) async {
      final employee = await f.employee('Race profile');
      final account = await f.account('race_employee');
      final results = await Future.wait([
        f.call(
          'POST',
          '/employees/${employee.id}/account-link',
          body: f.linkInput(employee, account),
          expected: null,
        ),
        f.call(
          'POST',
          '/employees/${employee.id}/deactivate',
          body: {'expectedVersion': 1},
        ),
      ]);
      expect([201, 409], contains(results.first.status));
      expect(
        (await f.call(
          'GET',
          '/employees/${employee.id}/account-link',
        )).body['link'],
        isNull,
      );
      await f.call(
        'GET',
        '/employees/me',
        token: await f.login('race_employee'),
        expected: 404,
      );
    }),
    skip: _skip,
  );

  test(
    'link alone grants no role; explicit unlink and account disable remove self access',
    () => _withFixture((f) async {
      final employee = await f.employee('No implicit role');
      final viewer = await f.account('linked_viewer', role: 'viewer');
      final link = await f.link(employee, viewer);
      await f.call(
        'GET',
        '/employees/me',
        token: await f.login('linked_viewer'),
        expected: 403,
      );
      await f.call(
        'POST',
        '/users/${viewer.id}',
        body: {'role': 'employee', 'isActive': true, 'expectedVersion': 1},
      );
      final token = await f.login('linked_viewer');
      await f.call('GET', '/employees/me', token: token);
      await f.call(
        'POST',
        '/employee-links/${link.id}/revoke',
        body: {'expectedVersion': 1},
      );
      await f.call('GET', '/employees/me', token: token, expected: 401);
      await f.call(
        'GET',
        '/employees/me',
        token: await f.login('linked_viewer'),
        expected: 404,
      );
      final current = PlatformUserDto.fromJson(
        (await f.call('GET', '/users')).body['users'].firstWhere(
              (dynamic item) => item['id'] == viewer.id,
            )
            as Map<String, dynamic>,
      );
      await f.link(employee, current);
      final newToken = await f.login('linked_viewer');
      await f.call(
        'POST',
        '/users/${viewer.id}',
        body: {'role': 'employee', 'isActive': false, 'expectedVersion': 2},
      );
      await f.call('GET', '/employees/me', token: newToken, expected: 401);
    }),
    skip: _skip,
  );

  test(
    'HTTP correlation is shared by platform audit and outbox; legacy audit stays unknown',
    () => _withFixture((f) async {
      final result = await f.call(
        'POST',
        '/company',
        body: {'name': 'Correlation company', 'expectedVersion': 2},
      );
      final rows = await f.owner.execute(
        Sql.named(
          'SELECT a.correlation_id::text AS audit, e.correlation_id::text AS event '
          'FROM "${f.schema}".audit_entries a JOIN "${f.schema}".event_outbox e '
          'ON a.correlation_id = e.correlation_id WHERE a.correlation_id = CAST(@id AS uuid)',
        ),
        parameters: {'id': result.correlation},
      );
      expect(rows, hasLength(1));
      expect(rows.single.toColumnMap()['event'], result.correlation);
    }),
    skip: _skip,
  );
}

Object get _skip => _url == null ? 'STOREOS_TEST_DATABASE is not set' : false;

class _Reply {
  _Reply(this.status, this.body, this.correlation);
  final int status;
  final Map<String, dynamic> body;
  final String? correlation;
}

class _Fixture {
  _Fixture(this.owner, this.pool, this.schema, this.runtimeUser);
  final Connection owner;
  final Pool<void> pool;
  final String schema, runtimeUser;
  final HttpClient client = HttpClient();
  late PlatformDatabase database;
  late SessionPrincipal adminPrincipal;
  late AuthService auth;
  HttpServer? server;
  String? adminToken;
  String get base => 'http://127.0.0.1:${server!.port}';

  Future<void> restart() async {
    await server?.close(force: true);
    final store = PostgresAuthStore(pool, schemaName: schema);
    auth = await AuthService.create(
      store: store,
      companyId: _company,
      locationId: _home,
      sessionTtl: const Duration(hours: 1),
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
    );
    database = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: _company,
      locationId: _home,
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
        locationId: _home,
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
  }

  Future<_Reply> call(
    String method,
    String route, {
    Map<String, dynamic>? body,
    String? token,
    int? expected = 200,
    bool platform = true,
  }) async {
    final request = await client.openUrl(
      method,
      Uri.parse('$base${platform ? '/api/v1/platform' : ''}$route'),
    );
    final credential = token ?? adminToken;
    if (credential != null && credential.isNotEmpty) {
      request.headers.set('authorization', 'Bearer $credential');
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decodeStream(response);
    if (expected != null) {
      expect(response.statusCode, expected, reason: '$method $route: $text');
    }
    return _Reply(
      response.statusCode,
      text.isEmpty ? {} : jsonDecode(text) as Map<String, dynamic>,
      response.headers.value('x-request-id'),
    );
  }

  Future<String> login(String username) async =>
      (await call(
            'POST',
            '/api/v1/auth/login',
            platform: false,
            body: {'username': username, 'password': _password},
          )).body['token']
          as String;
  Future<EmployeeDto> employee(String name) async => EmployeeDto.fromJson(
    (await call(
      'POST',
      '/employees',
      expected: 201,
      body: {'id': newUuid(), 'displayName': name, 'locationId': _home},
    )).body,
  );
  Future<PlatformUserDto> account(
    String username, {
    String role = 'employee',
    String location = _home,
  }) async => PlatformUserDto.fromJson(
    (await call(
      'POST',
      '/users',
      expected: 201,
      body: {
        'id': newUuid(),
        'username': username,
        'password': _password,
        'locationId': location,
        'role': role,
      },
    )).body,
  );
  Map<String, dynamic> linkInput(
    EmployeeDto employee,
    PlatformUserDto account,
  ) => {
    'id': newUuid(),
    'accountId': account.id,
    'expectedEmployeeVersion': employee.version,
    'expectedAccountVersion': account.version,
  };
  Future<EmployeeLinkDto> link(
    EmployeeDto employee,
    PlatformUserDto account,
  ) async {
    final result = await call(
      'POST',
      '/employees/${employee.id}/account-link',
      body: linkInput(employee, account),
      expected: 201,
    );
    return EmployeeLinkDto.fromJson(result.body);
  }
}

Future<void> _withFixture(Future<void> Function(_Fixture) action) async {
  final uri = Uri.parse(_url!);
  final split = uri.userInfo.indexOf(':');
  final endpoint = Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.single,
    username: Uri.decodeComponent(uri.userInfo.substring(0, split)),
    password: Uri.decodeComponent(uri.userInfo.substring(split + 1)),
  );
  if (!endpoint.database.endsWith('_test')) {
    throw StateError('An explicit *_test database is required.');
  }
  final runtime = Platform.environment['STOREOS_DB_USER'] ?? 'storeos';
  final secret = File(
    Platform.environment['STOREOS_DB_PASSWORD_FILE']!,
  ).readAsStringSync().trim();
  final owner = await Connection.open(
    endpoint,
    settings: const ConnectionSettings(sslMode: SslMode.disable),
  );
  final schema = 'storeos_employee_${newUuid().replaceAll('-', '')}';
  final pool = Pool<void>.withEndpoints(
    [
      Endpoint(
        host: endpoint.host,
        port: endpoint.port,
        database: endpoint.database,
        username: runtime,
        password: secret,
      ),
    ],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 4,
    ),
  );
  final fixture = _Fixture(owner, pool, schema, runtime);
  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: runtime,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(memoryKiB: 64, iterations: 1),
      schemaName: schema,
    ).bootstrap(
      username: 'test_admin',
      password: _password,
      companyId: _company,
      locationId: _home,
    );
    await fixture.restart();
    fixture.adminToken = await fixture.login('test_admin');
    fixture.adminPrincipal = await fixture.auth.authenticate(
      fixture.adminToken,
    );
    await fixture.call(
      'POST',
      '/organization/setup',
      body: {'companyName': 'Employee test company', 'locationName': 'Home'},
    );
    await fixture.call(
      'POST',
      '/locations',
      expected: 201,
      body: {'id': _other, 'name': 'Other location'},
    );
    await action(fixture);
  } finally {
    fixture.client.close(force: true);
    await fixture.server?.close(force: true);
    await pool.close();
    await owner.execute('DROP SCHEMA "$schema" CASCADE');
    await owner.close();
  }
}
