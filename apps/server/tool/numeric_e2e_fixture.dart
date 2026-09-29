// Run from apps/server with `dart run tool/numeric_e2e_fixture.dart`.
// A dedicated *_test database is mandatory. The HTTP server uses only its
// restricted runtime role; the owner connection is used for setup and cleanup.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/password_hasher.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/platform_app.dart';
import 'package:storeos_server/src/http/server_app.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/infrastructure/bootstrap_service.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/event_bus.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

Future<void> main() async {
  try {
    await _run();
  } catch (error) {
    // Neither the owner URI nor generated passwords may enter CI logs.
    stderr.writeln(
      'Numeric E2E fixture failed: '
      '${error is StateError ? error : error.runtimeType}.',
    );
    exitCode = 1;
  }
}

Future<void> _run() async {
  final env = Platform.environment;
  final ownerEndpoint = _testEndpoint(_required(env, 'STOREOS_TEST_DATABASE'));
  final runtimeUser = _required(env, 'STOREOS_DB_USER');
  final runtimePassword = File(
    _required(env, 'STOREOS_DB_PASSWORD_FILE'),
  ).readAsStringSync().trim();
  if (runtimePassword.isEmpty || runtimeUser == ownerEndpoint.username) {
    throw StateError('A separate runtime database role is required.');
  }
  final manifest = File(_required(env, 'STOREOS_E2E_MANIFEST'));
  final stopFile = File(_required(env, 'STOREOS_E2E_STOP_FILE'));
  if (!manifest.isAbsolute ||
      !stopFile.isAbsolute ||
      manifest.absolute.path == stopFile.absolute.path ||
      manifest.existsSync() ||
      stopFile.existsSync()) {
    throw StateError('Fixture paths must be new, distinct absolute paths.');
  }
  final allowedOrigin = _required(env, 'STOREOS_E2E_ALLOWED_ORIGIN');
  final origin = Uri.tryParse(allowedOrigin);
  if (origin == null ||
      origin.scheme != 'http' ||
      origin.host != '127.0.0.1' ||
      !origin.hasPort ||
      origin.origin != allowedOrigin) {
    throw StateError('Expected an exact loopback HTTP browser origin.');
  }

  final companyId = newUuid(), locationId = newUuid();
  final schema = 'storeos_e2e_${newUuid().replaceAll('-', '')}';
  final adminPassword = _password(), workerPassword = _password();
  const adminUser = 'numeric_e2e_admin', workerUser = 'numeric_e2e_worker';
  Connection? owner;
  Pool<void>? pool;
  HttpServer? server;
  HttpClient? client;
  EventBus? bus;
  var ownsSchema = false;
  var ownsManifest = false;
  try {
    owner = await Connection.open(
      ownerEndpoint,
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    final role = await owner.execute(
      Sql.named(
        'SELECT rolsuper, rolcreatedb, rolcreaterole FROM pg_roles '
        'WHERE rolname = @role',
      ),
      parameters: {'role': runtimeUser},
    );
    if (role.length != 1 ||
        role.single[0] != false ||
        role.single[1] != false ||
        role.single[2] != false) {
      throw StateError('Runtime role is missing or privileged.');
    }
    // CREATE (without IF NOT EXISTS) establishes ownership of precisely this
    // random schema before the cleanup path is allowed to remove anything.
    await owner.execute('CREATE SCHEMA "$schema"');
    ownsSchema = true;
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: schema,
      runtimeDatabaseUser: runtimeUser,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(),
      schemaName: schema,
    ).bootstrap(
      username: adminUser,
      password: adminPassword,
      companyId: companyId,
      locationId: locationId,
    );
    await owner.close();
    owner = null;

    pool = Pool<void>.withEndpoints(
      [
        Endpoint(
          host: ownerEndpoint.host,
          port: ownerEndpoint.port,
          database: ownerEndpoint.database,
          username: runtimeUser,
          password: runtimePassword,
        ),
      ],
      settings: const PoolSettings(
        sslMode: SslMode.disable,
        maxConnectionCount: 4,
      ),
    );
    final store = PostgresAuthStore(pool, schemaName: schema);
    final auth = await AuthService.create(
      store: store,
      companyId: companyId,
      locationId: locationId,
      sessionTtl: const Duration(hours: 1),
    );
    final database = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: companyId,
      locationId: locationId,
    );
    final app = ServerApp(
      config: ServerConfig(
        database: DatabaseConfig(
          host: ownerEndpoint.host,
          port: ownerEndpoint.port,
          name: ownerEndpoint.database,
          user: runtimeUser,
          password: runtimePassword,
        ),
        companyId: companyId,
        locationId: locationId,
        allowedOrigins: {allowedOrigin},
      ),
      auth: auth,
      store: store,
      platformHandler: createPlatformHandler(auth, database),
    );
    server = await shelf_io.serve(app.handler, '127.0.0.1', 0);
    bus = EventBus(database: database)..start();
    client = HttpClient();
    final api = _Api(client, 'http://127.0.0.1:${server.port}');
    await api.request('GET', '/ready');
    final ids = await _prepare(
      api,
      companyId: companyId,
      locationId: locationId,
      adminUser: adminUser,
      adminPassword: adminPassword,
      workerUser: workerUser,
      workerPassword: workerPassword,
    );

    final values = <String, String>{
      'STOREOS_API_URL': api.baseUrl,
      'STOREOS_E2E_ADMIN_USERNAME': adminUser,
      'STOREOS_E2E_ADMIN_PASSWORD': adminPassword,
      'STOREOS_E2E_WORKER_USERNAME': workerUser,
      'STOREOS_E2E_WORKER_PASSWORD': workerPassword,
      'STOREOS_E2E_SCHEMA': schema,
      'STOREOS_E2E_COMPANY_ID': companyId,
      'STOREOS_E2E_LOCATION_ID': locationId,
      ...ids,
    };
    await _writePrivateManifest(manifest, values);
    ownsManifest = true;
    stdout.writeln('numeric_e2e_fixture_ready');
    await _waitForStop(stopFile);
    await server.close(force: true);
    server = null;
    await bus.stop();
    bus = null;
    await pool.close();
    pool = null;
    owner = await Connection.open(
      ownerEndpoint,
      settings: const ConnectionSettings(sslMode: SslMode.disable),
    );
    await _verifyOutcome(owner, schema, values);
    stdout.writeln('numeric_e2e_fixture_verified');
  } finally {
    client?.close(force: true);
    await server?.close(force: true);
    await bus?.stop();
    await pool?.close();
    try {
      if (ownsSchema) {
        owner ??= await Connection.open(
          ownerEndpoint,
          settings: const ConnectionSettings(sslMode: SslMode.disable),
        );
        await owner.execute('DROP SCHEMA "$schema" CASCADE');
      }
    } finally {
      await owner?.close();
      if (ownsManifest && manifest.existsSync()) await manifest.delete();
      if (stopFile.existsSync()) await stopFile.delete();
    }
  }
}

Future<Map<String, String>> _prepare(
  _Api api, {
  required String companyId,
  required String locationId,
  required String adminUser,
  required String adminPassword,
  required String workerUser,
  required String workerPassword,
}) async {
  final login = await api.request(
    'POST',
    '/api/v1/auth/login',
    body: {'username': adminUser, 'password': adminPassword},
  );
  final token = login['token'] as String;
  const root = '/api/v1/platform';
  await api.request(
    'POST',
    '$root/organization/setup',
    token: token,
    body: {
      'companyName': 'Numeric E2E Company',
      'locationName': 'Numeric E2E Location',
    },
  );
  final employeeId = newUuid(), workerId = newUuid();
  final employee = await api.request(
    'POST',
    '$root/employees',
    token: token,
    expected: 201,
    body: {
      'id': employeeId,
      'displayName': 'Numeric E2E Employee',
      'locationId': locationId,
    },
  );
  final worker = await api.request(
    'POST',
    '$root/users',
    token: token,
    expected: 201,
    body: {
      'id': workerId,
      'username': workerUser,
      'password': workerPassword,
      'locationId': locationId,
      'role': 'employee',
    },
  );
  await api.request(
    'POST',
    '$root/employees/$employeeId/account-link',
    token: token,
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': workerId,
      'expectedEmployeeVersion': employee['version'],
      'expectedAccountVersion': worker['version'],
    },
  );

  final templateId = newUuid(), revisionId = newUuid();
  final numberStepId = newUuid(), confirmationStepId = newUuid();
  await api.request(
    'POST',
    '$root/task-templates',
    token: token,
    expected: 201,
    body: {
      'id': templateId,
      'revisionId': revisionId,
      'locationId': locationId,
      'content': {
        'schemaVersion': 2,
        'title': 'Numeric E2E Work',
        'steps': [
          {
            'id': numberStepId,
            'type': 'number',
            'instruction': 'Record E2E measurement',
            'unit': 'C',
            'minimum': '-2.125',
            'maximum': '4.5',
          },
          {
            'id': confirmationStepId,
            'type': 'confirmation',
            'instruction': 'Confirm E2E work',
          },
        ],
      },
    },
  );
  await api.request(
    'POST',
    '$root/task-templates/$templateId/revisions/$revisionId/publish',
    token: token,
    body: {'expectedVersion': 1},
  );

  final shiftId = newUuid();
  final start = DateTime.parse(employee['assignedFrom'] as String).toUtc();
  final end = DateTime.now().toUtc().add(const Duration(hours: 4));
  await api.request(
    'POST',
    '$root/shifts',
    token: token,
    expected: 201,
    body: {
      'id': shiftId,
      'locationId': locationId,
      'employeeId': employeeId,
      'startsAt': start.toIso8601String(),
      'endsAt': end.toIso8601String(),
      'selections': [
        {'templateId': templateId, 'revisionId': revisionId},
      ],
    },
  );
  final published = await api.request(
    'POST',
    '$root/shifts/$shiftId/publish',
    token: token,
    body: {'expectedVersion': 1},
  );
  final tasks = published['tasks'] as List;
  if (tasks.length != 1) {
    throw StateError('Expected exactly one published task.');
  }
  final taskId = (tasks.single as Map<String, dynamic>)['id'] as String;
  await api.request('POST', '/api/v1/auth/logout', token: token, expected: 204);
  return {
    'STOREOS_E2E_ADMIN_ID':
        (login['user'] as Map<String, dynamic>)['id'] as String,
    'STOREOS_E2E_WORKER_ID': workerId,
    'STOREOS_E2E_EMPLOYEE_ID': employeeId,
    'STOREOS_E2E_SHIFT_ID': shiftId,
    'STOREOS_E2E_TASK_ID': taskId,
    'STOREOS_E2E_TEMPLATE_ID': templateId,
    'STOREOS_E2E_REVISION_ID': revisionId,
    'STOREOS_E2E_NUMBER_STEP_ID': numberStepId,
    'STOREOS_E2E_CONFIRMATION_STEP_ID': confirmationStepId,
  };
}

Future<void> _verifyOutcome(
  Connection owner,
  String schema,
  Map<String, String> values,
) async {
  final taskId = values['STOREOS_E2E_TASK_ID']!;
  final companyId = values['STOREOS_E2E_COMPANY_ID']!;
  final locationId = values['STOREOS_E2E_LOCATION_ID']!;
  final workerId = values['STOREOS_E2E_WORKER_ID']!;
  final adminId = values['STOREOS_E2E_ADMIN_ID']!;
  final taskRows = await owner.execute(
    Sql.named(
      'SELECT status, version, company_id::text AS company_id, '
      'location_id::text AS location_id, completed_by::text AS completed_by '
      'FROM "$schema".task_instances WHERE id=CAST(@id AS uuid)',
    ),
    parameters: {'id': taskId},
  );
  if (taskRows.length != 1) throw StateError('E2E task is missing.');
  final task = taskRows.single.toColumnMap();
  if (task['status'] != 'completed' ||
      task['version'] != 7 ||
      task['company_id'] != companyId ||
      task['location_id'] != locationId ||
      task['completed_by'] != workerId) {
    throw StateError('E2E task did not complete in its expected scope.');
  }
  final attempts = await owner.execute(
    Sql.named(
      'SELECT step_id::text AS step_id, value_scaled, in_range, '
      'recorded_by::text AS recorded_by, accepted_version, '
      'company_id::text AS company_id, location_id::text AS location_id '
      'FROM "$schema".task_numeric_attempts '
      'WHERE instance_id=CAST(@id AS uuid) ORDER BY accepted_version',
    ),
    parameters: {'id': taskId},
  );
  if (attempts.length != 2) {
    throw StateError('Expected exactly two numeric attempts.');
  }
  for (var i = 0; i < 2; i++) {
    final attempt = attempts[i].toColumnMap();
    if (attempt['step_id'] != values['STOREOS_E2E_NUMBER_STEP_ID'] ||
        attempt['value_scaled'] != (i == 0 ? 5000 : 4500) ||
        attempt['in_range'] != (i == 1) ||
        attempt['accepted_version'] != (i == 0 ? 3 : 5) ||
        attempt['recorded_by'] != workerId ||
        attempt['company_id'] != companyId ||
        attempt['location_id'] != locationId) {
      throw StateError('Numeric attempts differ from the browser workflow.');
    }
  }
  final results = await owner.execute(
    Sql.named(
      'SELECT position, step_id::text AS step_id, '
      'numeric_attempt_id::text AS numeric_attempt_id, '
      'confirmed_by::text AS confirmed_by '
      'FROM "$schema".task_step_results '
      'WHERE instance_id=CAST(@id AS uuid) ORDER BY position',
    ),
    parameters: {'id': taskId},
  );
  if (results.length != 2 ||
      results[0].toColumnMap()['position'] != 0 ||
      results[1].toColumnMap()['position'] != 1 ||
      results[0].toColumnMap()['step_id'] !=
          values['STOREOS_E2E_NUMBER_STEP_ID'] ||
      results[1].toColumnMap()['step_id'] !=
          values['STOREOS_E2E_CONFIRMATION_STEP_ID'] ||
      results[0].toColumnMap()['numeric_attempt_id'] == null ||
      results[1].toColumnMap()['numeric_attempt_id'] != null ||
      results.any((r) => r.toColumnMap()['confirmed_by'] != workerId)) {
    throw StateError('Expected one numeric and one confirmation result.');
  }
  final actions = await owner.execute(
    Sql.named(
      'SELECT action, actor_kind, actor_id, company_id::text AS company_id, '
      'location_id::text AS location_id, changes '
      'FROM "$schema".audit_entries WHERE entity_type=\'task_instance\' '
      'AND entity_id=@id',
    ),
    parameters: {'id': taskId},
  );
  const expected = {
    'tasks.instance.created': 1,
    'tasks.instance.started': 1,
    'tasks.step.number_recorded': 2,
    'tasks.instance.blocked': 1,
    'tasks.instance.resumed': 1,
    'tasks.step.confirmed': 2,
    'tasks.instance.completed': 1,
  };
  final counts = <String, int>{};
  for (final item in actions) {
    final row = item.toColumnMap();
    final action = row['action'] as String;
    counts[action] = (counts[action] ?? 0) + 1;
    final actorId =
        action == 'tasks.instance.resumed' || action == 'tasks.instance.created'
        ? adminId
        : workerId;
    if (row['actor_kind'] != 'user') {
      throw StateError('Audit actor kind differs for $action.');
    }
    if (row['actor_id'] != actorId) {
      throw StateError('Audit actor differs for $action.');
    }
    if (row['company_id'] != companyId) {
      throw StateError('Audit company differs for $action.');
    }
    if (row['location_id'] != locationId) {
      throw StateError('Audit location differs for $action.');
    }
    final changes = row['changes'] as Map;
    if (changes.keys.any(
      (key) =>
          {'value', 'valueScaled', 'rawValue', 'measurement'}.contains(key),
    )) {
      throw StateError('Audit contains a raw numeric value.');
    }
  }
  if (counts.length != expected.length ||
      expected.entries.any((entry) => counts[entry.key] != entry.value)) {
    throw StateError('Audit actions do not match the browser workflow.');
  }
}

class _Api {
  const _Api(this.client, this.baseUrl);
  final HttpClient client;
  final String baseUrl;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    int expected = 200,
  }) async {
    final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
    if (token != null) request.headers.set('authorization', 'Bearer $token');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      final bytes = utf8.encode(jsonEncode(body));
      request.contentLength = bytes.length;
      request.add(bytes);
    }
    final response = await request.close();
    final responseText = await utf8.decodeStream(response);
    if (response.statusCode != expected) {
      // Deliberately omit request/response payloads: setup includes passwords.
      throw StateError(
        'Fixture API $method $path returned ${response.statusCode}, expected $expected.',
      );
    }
    if (responseText.isEmpty) return {};
    final decoded = jsonDecode(responseText);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Fixture API returned a non-object response.');
    }
    return decoded;
  }
}

Endpoint _testEndpoint(String text) {
  final uri = Uri.tryParse(text);
  if (uri == null ||
      !{'postgres', 'postgresql'}.contains(uri.scheme) ||
      !{'127.0.0.1', 'localhost', '::1'}.contains(uri.host) ||
      uri.pathSegments.length != 1 ||
      !uri.pathSegments.single.endsWith('_test') ||
      !uri.userInfo.contains(':') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw StateError('An explicit loopback *_test PostgreSQL URL is required.');
  }
  final separator = uri.userInfo.indexOf(':');
  return Endpoint(
    host: uri.host,
    port: uri.hasPort ? uri.port : 5432,
    database: uri.pathSegments.single,
    username: Uri.decodeComponent(uri.userInfo.substring(0, separator)),
    password: Uri.decodeComponent(uri.userInfo.substring(separator + 1)),
  );
}

String _required(Map<String, String> env, String name) {
  final value = env[name];
  if (value == null || value.isEmpty) throw StateError('$name is required.');
  return value;
}

String _password() {
  final random = Random.secure();
  return base64UrlEncode(
    List.generate(32, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

Future<void> _writePrivateManifest(
  File manifest,
  Map<String, String> values,
) async {
  await manifest.parent.create(recursive: true);
  final temporary = File('${manifest.path}.${newUuid()}.tmp');
  try {
    await temporary.create(exclusive: true);
    final permission = Platform.isWindows
        ? await _restrictWindows(temporary.path)
        : await Process.run('chmod', ['600', temporary.path]);
    if (permission.exitCode != 0) {
      throw StateError('Cannot restrict fixture manifest permissions.');
    }
    await temporary.writeAsString(jsonEncode(values));
    await temporary.rename(manifest.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<ProcessResult> _restrictWindows(String path) async {
  final identity = await Process.run('whoami', ['/user', '/fo', 'csv', '/nh']);
  final sid = RegExp(r'S-1-\d+(?:-\d+)+').firstMatch(identity.stdout as String);
  if (identity.exitCode != 0 || sid == null) {
    throw StateError('Cannot identify the current Windows user.');
  }
  return Process.run('icacls.exe', [
    path,
    '/inheritance:r',
    '/grant:r',
    '*${sid.group(0)}:F',
  ]);
}

Future<void> _waitForStop(File stopFile) async {
  final stopped = Completer<void>();
  final timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
    if (stopFile.existsSync() && !stopped.isCompleted) stopped.complete();
  });
  final signals = <StreamSubscription<ProcessSignal>>[
    ProcessSignal.sigint.watch().listen((_) {
      if (!stopped.isCompleted) stopped.complete();
    }),
  ];
  if (!Platform.isWindows) {
    signals.add(
      ProcessSignal.sigterm.watch().listen((_) {
        if (!stopped.isCompleted) stopped.complete();
      }),
    );
  }
  try {
    await stopped.future;
  } finally {
    timer.cancel();
    for (final signal in signals) {
      await signal.cancel();
    }
  }
}
