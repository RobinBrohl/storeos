import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/tasks/task_template_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/platform/plugin_service.dart';
import 'package:test/test.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _home = '22222222-2222-4222-8222-222222222222';
const _other = '33333333-3333-4333-8333-333333333333';
const _password = 'employee-test-only-password-strong';
final _url = Platform.environment['STOREOS_TEST_DATABASE'];

void main() {
  test(
    'invalid Unicode is rejected by the content contract without writes',
    () => _withFixture((f) async {
      for (final invalid in ['\uD800', '\uDC00']) {
        final reply = await f.call(
          'POST',
          '/task-templates',
          body: {..._input(), 'content': _content(invalid)},
          expected: 400,
        );
        expect(reply.body['code'], 'invalid_template_content');
        final content = _content();
        (content['steps'] as List).first['instruction'] = invalid;
        final stepReply = await f.call(
          'POST',
          '/task-templates',
          body: {..._input(), 'content': content},
          expected: 400,
        );
        expect(stepReply.body['code'], 'invalid_template_content');
      }
      final counts = await f.owner.execute(
        'SELECT (SELECT count(*) FROM "${f.schema}".task_templates), '
        '(SELECT count(*) FROM "${f.schema}".task_template_revisions), '
        '(SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'tasks.template.%\')',
      );
      expect(counts.single, [0, 0, 0]);
    }),
    skip: _skip,
  );

  test(
    'migration 0005 preserves populated 0004 identities, employee profiles and audit',
    () => _withFixture((f) async {
      await f.employee('Existing employee');
      Future<List<String>> preserved() async {
        final rows = <String>[];
        for (final table in [
          'accounts',
          'employees',
          'audit_entries',
          'account_employee_links',
        ]) {
          rows.add(
            (await f.owner.execute(
                  'SELECT COALESCE(jsonb_agg(to_jsonb(t) ORDER BY id), \'[]\'::jsonb)::text FROM "${f.schema}".$table t',
                )).single.first
                as String,
          );
        }
        return rows;
      }

      final before = await preserved();
      final runner = MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      );
      expect(await runner.apply(), [
        '0005_task_templates',
        '0006_shifts_and_task_instances',
        '0007_task_execution',
        '0008_task_blocking',
        '0009_task_cancellation',
        '0010_task_numeric_steps',
        '0011_published_shift_cancellation',
        '0012_published_shift_amendment',
        '0013_article_master',
        '0014_location_assortment',
        '0015_manual_stock',
        '0016_local_planograms',
        '0017_approved_operational_knowledge',
        '0018_task_knowledge_guidance',
      ]);
      expect(await runner.apply(), isEmpty);
      expect(await preserved(), before);
      await f.call('POST', '/task-templates', body: _input(), expected: 201);
    }, legacy: true),
    skip: _skip,
  );

  test(
    'template and revision pages return bounded metadata without gaps or bodies',
    () => _withFixture((f) async {
      final ids = <String>[];
      Map<String, dynamic>? first;
      for (var i = 0; i < 51; i++) {
        final input = _input();
        first ??= input;
        ids.add(input['id'] as String);
        await f.call('POST', '/task-templates', body: input, expected: 201);
      }
      final page = (await f.call('GET', '/task-templates')).body;
      expect(page['items'], hasLength(50));
      final tail = (await f.call(
        'GET',
        '/task-templates?after=${page['nextCursor']}',
      )).body;
      expect(tail['items'], hasLength(1));
      expect(tail['nextCursor'], isNull);
      final seen = [
        ...page['items'] as List,
        ...tail['items'] as List,
      ].map((r) => r['id']).toSet();
      expect(seen, ids.toSet());
      expect(jsonEncode(page), isNot(contains('Check equipment')));
      final id = first!['id'];
      var rid = first['revisionId'] as String;
      var version = 1;
      for (var n = 1; n <= 51; n++) {
        await f.call(
          'POST',
          '/task-templates/$id/revisions/$rid/publish',
          body: {'expectedVersion': version++},
        );
        if (n < 51) {
          rid = newUuid();
          await f.call(
            'POST',
            '/task-templates/$id/revisions',
            body: {'id': rid, 'expectedVersion': version++},
            expected: 201,
          );
        }
      }
      final revisions = (await f.call(
        'GET',
        '/task-templates/$id/revisions',
      )).body;
      expect(revisions['items'], hasLength(50));
      final oldest = (await f.call(
        'GET',
        '/task-templates/$id/revisions?after=${revisions['nextCursor']}',
      )).body;
      expect((oldest['items'] as List).single['number'], 1);
      expect(oldest['nextCursor'], isNull);
      expect(jsonEncode(revisions), isNot(contains('Check equipment')));
    }),
    skip: _skip,
  );

  test(
    'template workflow freezes revisions, retries publication, audits and survives restart',
    () => _withFixture((f) async {
      final input = _input();
      final created = await f.call(
        'POST',
        '/task-templates',
        body: input,
        expected: 201,
      );
      final id = input['id'] as String, rid = input['revisionId'] as String;
      final path = '/task-templates/$id/revisions/$rid';
      expect(created.body['template']['version'], 1);
      final noOp = await f.call(
        'POST',
        '$path/edit',
        body: {'expectedVersion': 1, 'content': input['content']},
      );
      expect(noOp.body['template']['version'], 1);
      final published = await f.call(
        'POST',
        '$path/publish',
        body: {'expectedVersion': 1},
      );
      final snapshot = published.body['revision'];
      expect(published.body['template']['version'], 2);
      await f.call('POST', '$path/publish', body: {'expectedVersion': 1});
      await f.call(
        'POST',
        '$path/edit',
        body: {'expectedVersion': 2, 'content': _content('Forbidden')},
        expected: 409,
      );
      await f.call('POST', '/task-templates', body: input, expected: 409);
      final nextId = newUuid();
      final draft = await f.call(
        'POST',
        '/task-templates/$id/revisions',
        body: {'id': nextId, 'expectedVersion': 2},
        expected: 201,
      );
      expect(draft.body['revision']['content'], snapshot['content']);
      final next = '/task-templates/$id/revisions/$nextId';
      await f.call(
        'POST',
        '$next/edit',
        body: {'expectedVersion': 3, 'content': _content('Revision 2')},
      );
      await f.call('POST', '$next/publish', body: {'expectedVersion': 4});
      await f.restart();
      expect((await f.call('GET', path)).body['revision'], snapshot);
      final history =
          (await f.call('GET', '/task-templates/$id/revisions')).body['items']
              as List;
      expect(history.map((r) => r['number']), [2, 1]);
      expect(
        history.every(
          (r) => !(r as Map<String, dynamic>).containsKey('content'),
        ),
        isTrue,
      );
      final audit = await f.owner.execute(
        'SELECT action, changes, correlation_id::text FROM "${f.schema}".audit_entries WHERE entity_id=\'$id\' ORDER BY id',
      );
      expect(audit.map((r) => r[0]), [
        'tasks.template.created',
        'tasks.template.published',
        'tasks.template.revision_created',
        'tasks.template.draft_updated',
        'tasks.template.published',
      ]);
      expect(audit.first[2], created.correlation);
      expect(
        jsonEncode(audit.map((r) => r[1]).toList()),
        isNot(contains('Revision 2')),
      );
      await expectLater(
        f.pool.execute(
          'UPDATE "${f.schema}".task_template_revisions SET content=content WHERE id=\'$rid\'',
        ),
        throwsA(isA<PgException>()),
      );
      await expectLater(
        f.pool.execute(
          'DELETE FROM "${f.schema}".task_template_revisions WHERE id=\'$rid\'',
        ),
        throwsA(isA<PgException>()),
      );
      await expectLater(
        f.pool.execute('TRUNCATE "${f.schema}".task_template_revisions'),
        throwsA(isA<PgException>()),
      );
    }),
    skip: _skip,
  );

  test(
    'template routes deny roles, anonymous tokens, foreign companies and mismatched objects',
    () => _withFixture((f) async {
      final input = _input();
      await f.call('POST', '/task-templates', body: input, expected: 201);
      final id = input['id'], rid = input['revisionId'];
      final path = '/task-templates/$id/revisions/$rid';
      for (final role in ['employee', 'viewer', 'auditor']) {
        await f.account('denied_$role', role: role);
        final token = await f.login('denied_$role');
        for (final route in [
          '/task-templates',
          '/task-templates/$id',
          '/task-templates/$id/revisions',
          path,
        ]) {
          await f.call('GET', route, token: token, expected: 403);
        }
        await f.call(
          'POST',
          '/task-templates',
          token: token,
          body: _input(),
          expected: 403,
        );
        await f.call(
          'POST',
          '/task-templates/$id/revisions',
          token: token,
          body: {'id': newUuid(), 'expectedVersion': 1},
          expected: 403,
        );
        await f.call(
          'POST',
          '$path/edit',
          token: token,
          body: {'expectedVersion': 1, 'content': _content()},
          expected: 403,
        );
        await f.call(
          'POST',
          '$path/publish',
          token: token,
          body: {'expectedVersion': 1},
          expected: 403,
        );
      }
      final plugins = PluginService(f.database);
      final registration = await plugins.register(f.adminPrincipal, {
        'manifest': {
          'id': 'template-denied',
          'name': 'Template denied',
          'version': '1.0.0',
          'vendor': 'StoreOS tests',
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
      });
      final grant = await plugins.approve(f.adminPrincipal, 'template-denied', {
        'expectedVersion': registration['version'],
        'locationId': _home,
        'permissions': ['organization.read'],
        'subscriptions': <String>[],
      });
      final pluginToken = grant['token'] as String;
      await plugins.organization(pluginToken);
      await f.call('GET', '/task-templates', token: pluginToken, expected: 401);
      await f.call(
        'POST',
        '/task-templates',
        token: pluginToken,
        body: _input(),
        expected: 401,
      );
      await f.call('GET', '/task-templates', token: '', expected: 401);
      await f.call('GET', '/task-templates', token: 'x' * 43, expected: 401);
      await f.call(
        'POST',
        '/task-templates',
        body: {..._input(), 'locationId': newUuid()},
        expected: 404,
      );
      await f.call(
        'GET',
        '/task-templates/${newUuid()}/revisions/$rid',
        expected: 404,
      );
      final foreign = TaskTemplateService(
        PlatformDatabase(
          f.pool,
          schemaName: f.schema,
          companyId: newUuid(),
          locationId: _home,
        ),
      );
      await expectLater(
        foreign.get(f.adminPrincipal, id as String),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
      final other = {..._input(), 'locationId': _other};
      await f.call('POST', '/task-templates', body: other, expected: 201);
      expect(
        (await f.call(
          'GET',
          '/task-templates/${other['id']}',
        )).body['locationId'],
        _other,
      );
    }),
    skip: _skip,
  );

  test(
    'concurrent edit, publication and revision creation preserve one ordered history',
    () => _withFixture((f) async {
      final input = _input();
      await f.call('POST', '/task-templates', body: input, expected: 201);
      final id = input['id'], rid = input['revisionId'];
      final path = '/task-templates/$id/revisions/$rid';
      final edits = await Future.wait([
        for (final name in ['First', 'Second'])
          f.call(
            'POST',
            '$path/edit',
            body: {'expectedVersion': 1, 'content': _content(name)},
            expected: null,
          ),
      ]);
      expect(edits.map((r) => r.status).toList()..sort(), [200, 409]);
      final pubs = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call('POST', '$path/publish', body: {'expectedVersion': 2}),
      ]);
      expect(pubs[0].body['revision'], pubs[1].body['revision']);
      final drafts = await Future.wait([
        for (var i = 0; i < 2; i++)
          f.call(
            'POST',
            '/task-templates/$id/revisions',
            body: {'id': newUuid(), 'expectedVersion': 3},
            expected: null,
          ),
      ]);
      expect(drafts.map((r) => r.status).toList()..sort(), [201, 409]);
      final rows = await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'tasks.template.published\'',
      );
      expect(rows.single.first, 1);
    }),
    skip: _skip,
  );

  test(
    'invalid and empty templates cannot be published; malformed cursor and body fail safely',
    () => _withFixture((f) async {
      final input = {
        ..._input(),
        'content': {..._content(), 'steps': <Object>[]},
      };
      await f.call('POST', '/task-templates', body: input, expected: 201);
      await f.call(
        'POST',
        '/task-templates/${input['id']}/revisions/${input['revisionId']}/publish',
        body: {'expectedVersion': 1},
        expected: 422,
      );
      for (final content in [
        {..._content(), 'schemaVersion': 3},
        {..._content(), 'title': ''},
        {..._content(), 'steps': 'wrong'},
      ]) {
        await f.call(
          'POST',
          '/task-templates',
          body: {..._input(), 'content': content},
          expected: 400,
        );
      }
      await f.call(
        'POST',
        '/task-templates',
        body: {..._input(), 'companyId': newUuid()},
        expected: 400,
      );
      await f.call(
        'POST',
        '/task-templates',
        body: {..._input(), 'content': _content('x' * 17000)},
        expected: 413,
      );
      await f.call('GET', '/task-templates?after=bad', expected: 400);
      await f.call(
        'GET',
        '/task-templates/${input['id']}/revisions?after=0',
        expected: 400,
      );
    }),
    skip: _skip,
  );

  test(
    'all four audit failures roll back state and leave no orphan revisions',
    () => _withFixture((f) async {
      final input = _input();
      await f.call('POST', '/task-templates', body: input, expected: 201);
      final id = input['id'],
          rid = input['revisionId'],
          path =
              '/task-templates/${input['id']}/revisions/${input['revisionId']}';
      Future<String> state() async =>
          jsonEncode(
            (await f.owner.execute(
              'SELECT row_to_json(t)::text FROM "${f.schema}".task_templates t ORDER BY id',
            )).map((r) => r.first).toList(),
          ) +
          jsonEncode(
            (await f.owner.execute(
              'SELECT row_to_json(r)::text FROM "${f.schema}".task_template_revisions r ORDER BY id',
            )).map((r) => r.first).toList(),
          );
      final before = await state();
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call('POST', '/task-templates', body: _input(), expected: 503);
        await f.call(
          'POST',
          '$path/edit',
          body: {'expectedVersion': 1, 'content': _content('Must roll back')},
          expected: 503,
        );
        await f.call(
          'POST',
          '$path/publish',
          body: {'expectedVersion': 1},
          expected: 503,
        );
        expect(await state(), before);
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
      await f.call(
        'POST',
        '/task-templates/$id/revisions/$rid/publish',
        body: {'expectedVersion': 1},
      );
      final published = await state();
      await f.owner.execute(
        'REVOKE INSERT ON "${f.schema}".audit_entries FROM "${f.runtimeUser}"',
      );
      try {
        await f.call(
          'POST',
          '/task-templates/$id/revisions',
          body: {'id': newUuid(), 'expectedVersion': 2},
          expected: 503,
        );
        expect(await state(), published);
      } finally {
        await f.owner.execute(
          'GRANT INSERT ON "${f.schema}".audit_entries TO "${f.runtimeUser}"',
        );
      }
    }),
    skip: _skip,
  );
}

Map<String, dynamic> _content([String title = 'Opening']) => {
  'schemaVersion': 1,
  'title': title,
  'steps': [
    {
      'id': 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      'type': 'confirmation',
      'instruction': 'Check equipment',
    },
  ],
};
Map<String, dynamic> _input() => {
  'id': newUuid(),
  'revisionId': newUuid(),
  'locationId': _home,
  'content': _content(),
};

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
      final encoded = utf8.encode(jsonEncode(body));
      request.contentLength = encoded.length;
      request.add(encoded);
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
}

Future<void> _withFixture(
  Future<void> Function(_Fixture) action, {
  bool legacy = false,
}) async {
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
  final schema = 'storeos_templates_${newUuid().replaceAll('-', '')}';
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
  Directory? legacyDirectory;
  if (legacy) {
    legacyDirectory = await Directory.systemTemp.createTemp(
      'storeos_templates_legacy_',
    );
    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (file.uri.pathSegments.last.compareTo('0005') < 0) {
        await file.copy(
          '${legacyDirectory.path}/${file.uri.pathSegments.last}',
        );
      }
    }
  }

  try {
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: legacyDirectory ?? Directory('migrations'),
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
    await legacyDirectory?.delete(recursive: true);
  }
}
