// Run from apps/server with `dart run tool/backup_restore_fixture.dart`.
// A dedicated, run-scoped acceptance database is mandatory. The wrapper
// scripts/backup/Run-BackupRestoreAcceptance.ps1 creates the database, grants
// the restricted runtime role CONNECT and drops the database again. The owner
// connection is used for migration, bootstrap and verification; the runtime
// role serves the API.
//
// Modes (STOREOS_BACKUP_MODE):
//  - prepare: migrate and bootstrap the isolated acceptance source database,
//    seed the employee journey through the real HTTP API, capture the source
//    evidence snapshot and write the private run manifest.
//  - verify: compare source and restored databases, check revocation/fencing
//    and write a non-sensitive verification result file.
//
// The fixture never touches the normal StoreOS database: every connection uses
// the database name supplied through STOREOS_BACKUP_SOURCE_DATABASE or
// STOREOS_BACKUP_TARGET_DATABASE.
import 'dart:convert';
import 'merchandising_acceptance.dart';
import 'knowledge_acceptance.dart';
import 'task_guidance_acceptance.dart';
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

const _schema = 'storeos_platform';
const _sourcePattern = r'^storeos_backup_accept_[a-f0-9]{16}$';
const _targetPattern = r'^storeos_restore_bkacc_[a-f0-9]{16}c?$';
const _rolePattern = r'^[a-z_][a-z0-9_]{0,62}$';
const _connectionSettings = ConnectionSettings(
  sslMode: SslMode.disable,
  timeZone: 'UTC',
  connectTimeout: Duration(seconds: 15),
);

/// Evidence tables and their deterministic ordering keys. Identifiers are
/// compile-time constants, never user input.
const _evidenceTables = <String, String>{
  'knowledge_articles': 'id',
  'knowledge_revisions': 'id',
  'shifts': 'id',
  'merchandising_fixtures': 'id',
  'merchandising_planograms': 'id',
  'merchandising_planogram_revisions': 'id',
  'merchandising_planogram_zones': 'id',
  'merchandising_planogram_placements': 'id',
  'merchandising_planogram_assignments': 'id',

  'task_template_revisions': 'id',
  'task_instances': 'id',
  'task_step_results': 'instance_id, position, step_id',
  'task_numeric_attempts': 'instance_id, accepted_version, id',
  'task_blockings': 'id',
  'task_execution_commands': 'operation_id',
  'audit_entries': 'id',
};

Future<void> main() async {
  try {
    await _run();
  } catch (error) {
    // Credentials and row content must never enter CI logs.
    stderr.writeln(
      'Backup restore fixture failed: '
      '${error is StateError ? error : error.runtimeType}.',
    );
    exitCode = 1;
  }
}

Future<void> _run() async {
  final env = Platform.environment;
  final mode = _required(env, 'STOREOS_BACKUP_MODE');
  final source = _required(env, 'STOREOS_BACKUP_SOURCE_DATABASE');
  if (!RegExp(_sourcePattern).hasMatch(source)) {
    throw StateError('Source database name is not a strict acceptance name.');
  }
  switch (mode) {
    case 'prepare':
      await _prepare(env, source);
    case 'verify':
      await _verify(env, source);
    default:
      throw StateError('Unknown STOREOS_BACKUP_MODE.');
  }
}

Future<void> _prepare(Map<String, String> env, String source) async {
  final manifest = File(_required(env, 'STOREOS_BACKUP_MANIFEST'));
  if (!manifest.isAbsolute || manifest.existsSync()) {
    throw StateError('The acceptance manifest path must be new and absolute.');
  }
  final ownerEndpoint = _ownerEndpoint(env, source);
  final runtimeUser = _runtimeUser(env);
  final runtimePassword = _runtimePassword(env);
  final apiPort = _apiPort(env);
  final companyId = newUuid(), locationId = newUuid();
  final adminUser = 'backup_accept_admin', workerUser = 'backup_accept_worker';
  final adminPassword = _password(), workerPassword = _password();

  Connection? owner;
  Pool<void>? pool;
  HttpServer? server;
  HttpClient? client;
  EventBus? bus;
  try {
    owner = await Connection.open(ownerEndpoint, settings: _connectionSettings);
    await _requireRestrictedRole(owner, runtimeUser);
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: _schema,
      runtimeDatabaseUser: runtimeUser,
    ).apply();
    await BootstrapService(
      connection: owner,
      passwordHasher: PasswordHasher(),
      schemaName: _schema,
    ).bootstrap(
      username: adminUser,
      password: adminPassword,
      companyId: companyId,
      locationId: locationId,
    );
    await owner.close();
    owner = null;

    pool = _runtimePool(ownerEndpoint, runtimeUser, runtimePassword);
    final store = PostgresAuthStore(pool, schemaName: _schema);
    final auth = await AuthService.create(
      store: store,
      companyId: companyId,
      locationId: locationId,
      sessionTtl: const Duration(hours: 1),
    );
    final database = PlatformDatabase(
      pool,
      schemaName: _schema,
      companyId: companyId,
      locationId: locationId,
    );
    server = await shelf_io.serve(
      _serverApp(
        endpoint: ownerEndpoint,
        runtimeUser: runtimeUser,
        runtimePassword: runtimePassword,
        companyId: companyId,
        locationId: locationId,
        auth: auth,
        store: store,
        database: database,
      ).handler,
      '127.0.0.1',
      apiPort,
    );
    bus = EventBus(database: database)..start();
    client = HttpClient();
    final api = _Api(client, 'http://127.0.0.1:${server.port}');
    await api.request('GET', '/ready');
    final ids = await _seed(
      api,
      companyId: companyId,
      locationId: locationId,
      adminUser: adminUser,
      adminPassword: adminPassword,
      workerUser: workerUser,
      workerPassword: workerPassword,
    );

    // Capture the source snapshot only after the journey is fully persisted.
    owner = await Connection.open(ownerEndpoint, settings: _connectionSettings);
    final snapshot = await _snapshot(owner, _schema);
    await _assertSeededJourney(owner, _schema, runtimeUser, snapshot);
    await owner.close();
    owner = null;

    await _writePrivateManifest(manifest, {
      'runId': source.substring('storeos_backup_accept_'.length),
      'sourceDatabase': source,
      ...ids,
      'workerRecoveryPassword': workerPassword,
      'snapshot': snapshot.toJson(),
    });
    stdout.writeln('backup_restore_fixture_prepared');
  } finally {
    client?.close(force: true);
    await server?.close(force: true);
    await bus?.stop();
    await pool?.close();
    await owner?.close();
  }
}

Future<void> _verify(Map<String, String> env, String source) async {
  final manifest = File(_required(env, 'STOREOS_BACKUP_MANIFEST'));
  if (!manifest.isAbsolute || !manifest.existsSync()) {
    throw StateError('The acceptance manifest is missing.');
  }
  final expected = jsonDecode(await manifest.readAsString());
  if (expected is! Map<String, dynamic> ||
      expected['sourceDatabase'] != source ||
      expected['snapshot'] is! Map<String, dynamic>) {
    throw StateError('The acceptance manifest does not match this run.');
  }
  final target = _required(env, 'STOREOS_BACKUP_TARGET_DATABASE');
  if (!RegExp(_targetPattern).hasMatch(target)) {
    throw StateError('Target database name is not a strict restore name.');
  }
  final resultFile = File(_required(env, 'STOREOS_BACKUP_RESULT'));
  if (!resultFile.isAbsolute || resultFile.existsSync()) {
    throw StateError('The verification result path must be new and absolute.');
  }
  final runtimeUser = _runtimeUser(env);
  final runtimePassword = _runtimePassword(env);

  Connection? sourceOwner;
  Connection? targetOwner;
  try {
    sourceOwner = await Connection.open(
      _ownerEndpoint(env, source),
      settings: _connectionSettings,
    );
    targetOwner = await Connection.open(
      _ownerEndpoint(env, target),
      settings: _connectionSettings,
    );
    await _requireRestrictedRole(sourceOwner, runtimeUser);

    final before = _Snapshot.fromJson(
      expected['snapshot'] as Map<String, dynamic>,
    );
    final current = await _snapshot(sourceOwner, _schema);
    if (!current.sameEvidence(before)) {
      throw StateError('The acceptance source changed after the backup.');
    }
    final restored = await _snapshot(targetOwner, _schema);
    if (!restored.sameEvidence(current)) {
      throw StateError('Restored evidence differs from the source.');
    }
    await verifyKnowledgeEvidence(
      sourceOwner,
      _schema,
      runtimeUser,
      additionalPublished: 2,
    );
    await verifyKnowledgeEvidence(
      targetOwner,
      _schema,
      runtimeUser,
      additionalPublished: 2,
    );
    await verifyGuidanceEvidence(sourceOwner, _schema, runtimeUser);
    await verifyGuidanceEvidence(targetOwner, _schema, runtimeUser);

    final sourceSessions = await _activeSessions(sourceOwner, _schema);
    final restoredSessions = await _activeSessions(targetOwner, _schema);
    final sourceTokens = await _activePluginTokens(sourceOwner, _schema);
    final restoredTokens = await _activePluginTokens(targetOwner, _schema);
    if (sourceSessions != before.activeSessions ||
        sourceTokens != before.activePluginTokens) {
      throw StateError('Source access state changed after the backup.');
    }
    if (restoredSessions != 0) {
      throw StateError('The restored database still has active sessions.');
    }
    if (restoredTokens != 0) {
      throw StateError('The restored database still has active plugin tokens.');
    }
    final sourceConnect = await _runtimeConnect(sourceOwner, runtimeUser);
    final restoredConnect = await _runtimeConnect(targetOwner, runtimeUser);
    if (!sourceConnect) {
      throw StateError('The runtime role cannot connect to the source.');
    }
    if (restoredConnect) {
      throw StateError('The restored database still allows runtime CONNECT.');
    }

    // A real connection attempt proves the catalog flag matches behavior.
    await _requireRuntimeSourceAccess(
      _runtimeEndpoint(env, source, runtimeUser, runtimePassword),
    );
    await _requireRuntimeTargetRejected(
      _runtimeEndpoint(env, target, runtimeUser, runtimePassword),
    );
    await verifyRestoredGuidanceRead(
      _ownerEndpoint(env, target),
      _schema,
      expected['companyId'] as String,
      expected['locationId'] as String,
      'backup_accept_worker',
      expected['workerRecoveryPassword'] as String,
    );
    if (await _activeSessions(targetOwner, _schema) != 0 ||
        await _runtimeConnect(targetOwner, runtimeUser)) {
      throw StateError('Restore verification changed fencing.');
    }

    await _writeJson(resultFile, {
      'runId': expected['runId'],
      'sourceDatabase': source,
      'targetDatabase': target,
      'sourcePreserved': true,
      'tables': current.toTableJson(restored),
      'sequences': current.toSequenceJson(restored),
      'sourceActiveSessions': sourceSessions,
      'restoredActiveSessions': restoredSessions,
      'sourceActivePluginTokens': sourceTokens,
      'restoredActivePluginTokens': restoredTokens,
      'sourceRuntimeConnect': sourceConnect,
      'restoredRuntimeConnect': restoredConnect,
      'restoredRuntimeConnectionRejected': true,
      'guidance': {
        'schemaVersion': 3,
        'historicalRevision': 1,
        'completedPinPreserved': true,
        'contextualReadVerified': true,
        'arbitraryHistoryDenied': true,
        'runtimeProtections': true,
      },
    });
    stdout.writeln('backup_restore_fixture_verified');
  } finally {
    await sourceOwner?.close();
    await targetOwner?.close();
  }
}

/// Runs the bounded employee journey through the real HTTP API and returns the
/// non-secret identifiers needed for later verification.
Future<Map<String, String>> _seed(
  _Api api, {
  required String companyId,
  required String locationId,
  required String adminUser,
  required String adminPassword,
  required String workerUser,
  required String workerPassword,
}) async {
  const root = '/api/v1/platform';
  final login = await api.request(
    'POST',
    '/api/v1/auth/login',
    body: {'username': adminUser, 'password': adminPassword},
  );
  final adminToken = login['token'] as String;
  final adminId = (login['user'] as Map<String, dynamic>)['id'] as String;
  await api.request(
    'POST',
    '$root/organization/setup',
    token: adminToken,
    body: {
      'companyName': 'Backup Acceptance Company',
      'locationName': 'Backup Acceptance Location',
    },
  );
  await seedLocalPlanogram(
    (method, route, body, status) => api.request(
      method,
      route,
      token: adminToken,
      body: body,
      expected: status,
    ),
    locationId,
  );
  final employeeId = newUuid(), workerId = newUuid();
  await seedApprovedKnowledge(
    (method, route, body, status) => api.request(
      method,
      route,
      token: adminToken,
      body: body,
      expected: status,
    ),
  );
  final employee = await api.request(
    'POST',
    '$root/employees',
    token: adminToken,
    expected: 201,
    body: {
      'id': employeeId,
      'displayName': 'Backup Acceptance Employee',
      'locationId': locationId,
    },
  );
  final worker = await api.request(
    'POST',
    '$root/users',
    token: adminToken,
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
    token: adminToken,
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': workerId,
      'expectedEmployeeVersion': employee['version'],
      'expectedAccountVersion': worker['version'],
    },
  );

  final inProgressTemplate = await _publishTemplate(
    api,
    adminToken,
    locationId,
    'Backup Acceptance Open Work',
    [
      {
        'id': newUuid(),
        'type': 'confirmation',
        'instruction': 'Confirm open work',
      },
    ],
    schemaVersion: 1,
  );
  final numberStepId = newUuid();
  final blockedTemplate = await _publishTemplate(
    api,
    adminToken,
    locationId,
    'Backup Acceptance Number Exception',
    [
      {
        'id': numberStepId,
        'type': 'number',
        'instruction': 'Record exception measurement',
        'unit': 'C',
        'minimum': '-2.125',
        'maximum': '4.5',
      },
    ],
  );
  final acceptedNumberStepId = newUuid(), confirmationStepId = newUuid();
  Future<Map<String, dynamic>> guidanceRequest(
    String method,
    String route,
    Map<String, dynamic>? body,
    int status,
  ) => api.request(
    method,
    route,
    token: adminToken,
    body: body,
    expected: status,
  );
  final guidance = await seedGuidanceInstruction(guidanceRequest);
  final completedTemplate = await _publishTemplate(
    api,
    adminToken,
    locationId,
    'Backup Acceptance Completed Work',
    [
      {
        'id': acceptedNumberStepId,
        'type': 'number',
        'instruction': 'Record accepted measurement',
        'unit': 'C',
        'minimum': '-2.125',
        'maximum': '4.5',
      },
      {
        'id': confirmationStepId,
        'type': 'confirmation',
        'instruction': 'Confirm completed work',
      },
    ],
    schemaVersion: 3,
    guidance: guidance.toJson(),
  );

  final shiftId = newUuid();
  final start = DateTime.parse(employee['assignedFrom'] as String).toUtc();
  final end = DateTime.now().toUtc().add(const Duration(hours: 4));
  await api.request(
    'POST',
    '$root/shifts',
    token: adminToken,
    expected: 201,
    body: {
      'id': shiftId,
      'locationId': locationId,
      'employeeId': employeeId,
      'startsAt': start.toIso8601String(),
      'endsAt': end.toIso8601String(),
      'selections': [
        {
          'templateId': inProgressTemplate['templateId'],
          'revisionId': inProgressTemplate['revisionId'],
        },
        {
          'templateId': blockedTemplate['templateId'],
          'revisionId': blockedTemplate['revisionId'],
        },
        {
          'templateId': completedTemplate['templateId'],
          'revisionId': completedTemplate['revisionId'],
        },
      ],
    },
  );
  final published = await api.request(
    'POST',
    '$root/shifts/$shiftId/publish',
    token: adminToken,
    body: {'expectedVersion': 1},
  );
  final tasks = (published['tasks'] as List).cast<Map<String, dynamic>>();
  if (tasks.length != 3) {
    throw StateError('Expected exactly three published tasks.');
  }
  final taskByTemplate = {
    for (final task in tasks)
      task['templateId'] as String: task['id'] as String,
  };
  final inProgressTaskId = taskByTemplate[inProgressTemplate['templateId']];
  final blockedTaskId = taskByTemplate[blockedTemplate['templateId']];
  final completedTaskId = taskByTemplate[completedTemplate['templateId']];
  if (inProgressTaskId == null ||
      blockedTaskId == null ||
      completedTaskId == null) {
    throw StateError('Published tasks do not match the selected templates.');
  }

  final workerLogin = await api.request(
    'POST',
    '/api/v1/auth/login',
    body: {'username': workerUser, 'password': workerPassword},
  );
  final workerToken = workerLogin['token'] as String;
  await replaceAndRetireGuidance(guidanceRequest, guidance);
  final assigned = await api.request(
    'GET',
    '$root/employee-home/shifts/$shiftId/tasks/$completedTaskId/knowledge',
    token: workerToken,
  );
  if (assigned['revisionId'] != guidance.revisionId ||
      assigned['articleRetired'] != true) {
    throw StateError('Seed contextual guidance did not retain v1.');
  }
  await _execute(api, workerToken, shiftId, inProgressTaskId, 'start', {
    'operationId': newUuid(),
    'expectedVersion': 1,
  });

  await _execute(api, workerToken, shiftId, blockedTaskId, 'start', {
    'operationId': newUuid(),
    'expectedVersion': 1,
  });
  final blocked = await _execute(
    api,
    workerToken,
    shiftId,
    blockedTaskId,
    'steps/$numberStepId/record-number',
    {'operationId': newUuid(), 'expectedVersion': 2, 'value': '5'},
  );
  if (blocked['status'] != 'blocked') {
    throw StateError('Out-of-range numeric input did not block the task.');
  }

  await _execute(api, workerToken, shiftId, completedTaskId, 'start', {
    'operationId': newUuid(),
    'expectedVersion': 1,
  });
  await _execute(
    api,
    workerToken,
    shiftId,
    completedTaskId,
    'steps/$acceptedNumberStepId/record-number',
    {'operationId': newUuid(), 'expectedVersion': 2, 'value': '4.5'},
  );
  await _execute(
    api,
    workerToken,
    shiftId,
    completedTaskId,
    'steps/$confirmationStepId/confirm',
    {'operationId': newUuid(), 'expectedVersion': 3},
  );
  final completed = await _execute(
    api,
    workerToken,
    shiftId,
    completedTaskId,
    'complete',
    {'operationId': newUuid(), 'expectedVersion': 4},
  );
  if (completed['status'] != 'completed') {
    throw StateError('The worked task did not complete.');
  }

  const pluginId = 'backup.acceptance-evidence';
  await api.request(
    'POST',
    '$root/plugins',
    token: adminToken,
    expected: 201,
    body: {
      'manifest': {
        'id': pluginId,
        'name': 'Backup Acceptance Evidence',
        'version': '1.0.0',
        'vendor': 'StoreOS Acceptance',
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
  await api.request(
    'POST',
    '$root/plugins/$pluginId/approve',
    token: adminToken,
    body: {
      'expectedVersion': 1,
      'locationId': locationId,
      'permissions': ['organization.read'],
      'subscriptions': <String>[],
    },
  );
  // The approved plugin token stays active; its value is deliberately discarded.
  // The admin session also stays active so the backup contains live access rows.
  await api.request(
    'POST',
    '/api/v1/auth/logout',
    token: workerToken,
    expected: 204,
  );
  return {
    'companyId': companyId,
    'locationId': locationId,
    'adminAccountId': adminId,
    'workerAccountId': workerId,
    'employeeId': employeeId,
    'shiftId': shiftId,
    'inProgressTaskId': inProgressTaskId,
    'blockedTaskId': blockedTaskId,
    'completedTaskId': completedTaskId,
    'inProgressTemplateId': inProgressTemplate['templateId']!,
    'blockedTemplateId': blockedTemplate['templateId']!,
    'completedTemplateId': completedTemplate['templateId']!,
    'pluginId': pluginId,
  };
}

Future<Map<String, String>> _publishTemplate(
  _Api api,
  String token,
  String locationId,
  String title,
  List<Map<String, dynamic>> steps, {
  int schemaVersion = 2,
  Map<String, dynamic>? guidance,
}) async {
  final templateId = newUuid(), revisionId = newUuid();
  await api.request(
    'POST',
    '/api/v1/platform/task-templates',
    token: token,
    expected: 201,
    body: {
      'id': templateId,
      'revisionId': revisionId,
      'locationId': locationId,
      'content': {
        'schemaVersion': schemaVersion,
        'title': title,
        'steps': steps,
        if (schemaVersion == 3) 'knowledgeGuidance': guidance,
      },
    },
  );
  await api.request(
    'POST',
    '/api/v1/platform/task-templates/$templateId/revisions/$revisionId/publish',
    token: token,
    body: {'expectedVersion': 1},
  );
  return {'templateId': templateId, 'revisionId': revisionId};
}

Future<Map<String, dynamic>> _execute(
  _Api api,
  String token,
  String shiftId,
  String taskId,
  String suffix,
  Map<String, dynamic> body,
) => api.request(
  'POST',
  '/api/v1/platform/employee-home/shifts/$shiftId/tasks/$taskId/$suffix',
  token: token,
  body: body,
);

Future<void> _assertSeededJourney(
  Connection owner,
  String schema,
  String runtimeUser,
  _Snapshot snapshot,
) async {
  if (snapshot.activeSessions != 1) {
    throw StateError('Expected exactly one active source session.');
  }
  if (snapshot.activePluginTokens != 1) {
    throw StateError('Expected exactly one active source plugin token.');
  }
  const expectedCounts = {
    'knowledge_articles': 3,
    'knowledge_revisions': 8,
    'merchandising_fixtures': 1,
    'merchandising_planograms': 1,
    'merchandising_planogram_revisions': 2,
    'merchandising_planogram_zones': 2,
    'merchandising_planogram_placements': 2,
    'merchandising_planogram_assignments': 2,

    'shifts': 1,
    'task_template_revisions': 3,
    'task_instances': 3,
    'task_step_results': 2,
    'task_numeric_attempts': 2,
    'task_blockings': 1,
    'task_execution_commands': 7,
  };
  for (final entry in expectedCounts.entries) {
    if (snapshot.tables[entry.key]?.count != entry.value) {
      throw StateError('Seeded ${entry.key} count differs from the plan.');
    }
  }
  final statuses = await owner.execute(
    'SELECT status FROM "$schema".task_instances ORDER BY status',
  );
  final seeded = statuses.map((row) => row.single as String).toList();
  if (seeded.length != 3 ||
      seeded[0] != 'blocked' ||
      seeded[1] != 'completed' ||
      seeded[2] != 'in_progress') {
    throw StateError('Seeded task states differ from the plan.');
  }
  final attempts = await owner.execute(
    'SELECT in_range FROM "$schema".task_numeric_attempts '
    'ORDER BY accepted_version',
  );
  if (attempts.length != 2 ||
      attempts[0].single != false ||
      attempts[1].single != true) {
    throw StateError('Seeded numeric attempts differ from the plan.');
  }
  final approvals = await owner.execute(
    'SELECT count(*)::bigint FROM "$schema".plugin_registrations '
    "WHERE status='approved'",
  );
  if (approvals.single.single != 1) {
    throw StateError('Expected exactly one approved plugin.');
  }
  final connect = await _runtimeConnect(owner, runtimeUser);
  if (!connect) {
    throw StateError('The runtime role cannot connect to the source.');
  }
}

Future<_Snapshot> _snapshot(Connection owner, String schema) async {
  final tables = <String, Map<String, dynamic>>{};
  for (final entry in _evidenceTables.entries) {
    final result = await owner.execute(
      'SELECT count(*)::bigint AS row_count, '
      "coalesce(md5(string_agg(md5(row_to_json(t)::text), '' "
      'ORDER BY ${entry.value})), \'empty\') AS content_hash '
      'FROM "$schema"."${entry.key}" t',
    );
    final row = result.single.toColumnMap();
    tables[entry.key] = {
      'count': row['row_count'],
      'hash': row['content_hash'],
    };
  }
  final sequences = <String, Map<String, dynamic>>{};
  for (final name in const ['audit_entries_id_seq', 'plugin_inbox_id_seq']) {
    final result = await owner.execute(
      'SELECT last_value::text AS last_value, is_called '
      'FROM "$schema"."$name"',
    );
    final row = result.single.toColumnMap();
    sequences[name] = {
      'lastValue': row['last_value'],
      'isCalled': row['is_called'],
    };
  }
  return _Snapshot(
    tables: {
      for (final entry in tables.entries)
        entry.key: _TableState(
          entry.value['count'] as int,
          entry.value['hash'] as String,
        ),
    },
    sequences: {
      for (final entry in sequences.entries)
        entry.key: _SequenceState(
          entry.value['lastValue'] as String,
          entry.value['isCalled'] as bool,
        ),
    },
    activeSessions: await _activeSessions(owner, schema),
    activePluginTokens: await _activePluginTokens(owner, schema),
  );
}

Future<int> _activeSessions(Connection owner, String schema) async {
  final result = await owner.execute(
    'SELECT count(*)::bigint FROM "$schema".auth_sessions '
    'WHERE revoked_at IS NULL AND expires_at > now()',
  );
  return result.single.single! as int;
}

Future<int> _activePluginTokens(Connection owner, String schema) async {
  final result = await owner.execute(
    'SELECT count(*)::bigint FROM "$schema".plugin_tokens '
    'WHERE revoked_at IS NULL AND expires_at > now()',
  );
  return result.single.single! as int;
}

Future<bool> _runtimeConnect(Connection owner, String runtimeUser) async {
  final result = await owner.execute(
    Sql.named(
      "SELECT has_database_privilege(@role, current_database(), 'CONNECT')",
    ),
    parameters: {'role': runtimeUser},
  );
  return result.single.single! as bool;
}

Future<void> _requireRuntimeSourceAccess(Endpoint endpoint) async {
  Connection? connection;
  try {
    connection = await Connection.open(endpoint, settings: _connectionSettings);
    await connection.execute('SELECT 1');
  } finally {
    await connection?.close(force: true);
  }
}

Future<void> _requireRuntimeTargetRejected(Endpoint endpoint) async {
  Connection? accepted;
  try {
    accepted = await Connection.open(endpoint, settings: _connectionSettings);
  } on Object {
    return;
  }
  await accepted.close(force: true);
  throw StateError('The restored database accepted the runtime role.');
}

class _Snapshot {
  const _Snapshot({
    required this.tables,
    required this.sequences,
    required this.activeSessions,
    required this.activePluginTokens,
  });

  factory _Snapshot.fromJson(Map<String, dynamic> json) {
    final tables = <String, _TableState>{};
    for (final entry in (json['tables'] as Map<String, dynamic>).entries) {
      final value = entry.value as Map<String, dynamic>;
      tables[entry.key] = _TableState(
        value['count'] as int,
        value['hash'] as String,
      );
    }
    final sequences = <String, _SequenceState>{};
    for (final entry in (json['sequences'] as Map<String, dynamic>).entries) {
      final value = entry.value as Map<String, dynamic>;
      sequences[entry.key] = _SequenceState(
        value['lastValue'] as String,
        value['isCalled'] as bool,
      );
    }
    return _Snapshot(
      tables: tables,
      sequences: sequences,
      activeSessions: json['activeSessions'] as int,
      activePluginTokens: json['activePluginTokens'] as int,
    );
  }

  final Map<String, _TableState> tables;
  final Map<String, _SequenceState> sequences;
  final int activeSessions;
  final int activePluginTokens;

  Map<String, dynamic> toJson() => {
    'tables': {
      for (final entry in tables.entries)
        entry.key: {'count': entry.value.count, 'hash': entry.value.hash},
    },
    'sequences': {
      for (final entry in sequences.entries)
        entry.key: {
          'lastValue': entry.value.lastValue,
          'isCalled': entry.value.isCalled,
        },
    },
    'activeSessions': activeSessions,
    'activePluginTokens': activePluginTokens,
  };

  bool sameEvidence(_Snapshot other) {
    if (tables.length != other.tables.length ||
        sequences.length != other.sequences.length) {
      return false;
    }
    for (final entry in tables.entries) {
      final otherTable = other.tables[entry.key];
      if (otherTable == null ||
          otherTable.count != entry.value.count ||
          otherTable.hash != entry.value.hash) {
        return false;
      }
    }
    for (final entry in sequences.entries) {
      final otherSequence = other.sequences[entry.key];
      if (otherSequence == null ||
          otherSequence.lastValue != entry.value.lastValue ||
          otherSequence.isCalled != entry.value.isCalled) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toTableJson(_Snapshot restored) => {
    for (final entry in tables.entries)
      entry.key: {
        'sourceCount': entry.value.count,
        'sourceHash': entry.value.hash,
        'restoredCount': restored.tables[entry.key]!.count,
        'restoredHash': restored.tables[entry.key]!.hash,
      },
  };

  Map<String, dynamic> toSequenceJson(_Snapshot restored) => {
    for (final entry in sequences.entries)
      entry.key: {
        'sourceLastValue': entry.value.lastValue,
        'sourceIsCalled': entry.value.isCalled,
        'restoredLastValue': restored.sequences[entry.key]!.lastValue,
        'restoredIsCalled': restored.sequences[entry.key]!.isCalled,
      },
  };
}

class _TableState {
  const _TableState(this.count, this.hash);
  final int count;
  final String hash;
}

class _SequenceState {
  const _SequenceState(this.lastValue, this.isCalled);
  final String lastValue;
  final bool isCalled;
}

Endpoint _ownerEndpoint(Map<String, String> env, String database) {
  final host = env['STOREOS_BACKUP_DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['STOREOS_BACKUP_DB_PORT'] ?? '5432');
  final user = _required(env, 'STOREOS_BACKUP_DB_USER');
  final password = File(
    _required(env, 'STOREOS_BACKUP_OWNER_PASSWORD_FILE'),
  ).readAsStringSync().trim();
  if (!{'127.0.0.1', 'localhost', '::1'}.contains(host)) {
    throw StateError('The acceptance database host must be loopback.');
  }
  if (port == null || port < 1 || port > 65535) {
    throw StateError('The acceptance database port is invalid.');
  }
  if (!RegExp(_rolePattern).hasMatch(user) || password.isEmpty) {
    throw StateError('The acceptance owner credentials are invalid.');
  }
  return Endpoint(
    host: host,
    port: port,
    database: database,
    username: user,
    password: password,
  );
}

Endpoint _runtimeEndpoint(
  Map<String, String> env,
  String database,
  String runtimeUser,
  String runtimePassword,
) {
  final host = env['STOREOS_BACKUP_DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['STOREOS_BACKUP_DB_PORT'] ?? '5432');
  return Endpoint(
    host: host,
    port: port ?? 5432,
    database: database,
    username: runtimeUser,
    password: runtimePassword,
  );
}

String _runtimeUser(Map<String, String> env) {
  final user = _required(env, 'STOREOS_DB_USER');
  if (!RegExp(_rolePattern).hasMatch(user)) {
    throw StateError('STOREOS_DB_USER is not a valid role name.');
  }
  return user;
}

String _runtimePassword(Map<String, String> env) {
  final password = File(
    _required(env, 'STOREOS_DB_PASSWORD_FILE'),
  ).readAsStringSync().trim();
  if (password.isEmpty) throw StateError('The runtime password is empty.');
  return password;
}

int _apiPort(Map<String, String> env) {
  final value = int.tryParse(_required(env, 'STOREOS_BACKUP_API_PORT'));
  if (value == null || value < 1024 || value > 65535) {
    throw StateError('STOREOS_BACKUP_API_PORT must be a TCP port.');
  }
  return value;
}

Pool<void> _runtimePool(
  Endpoint endpoint,
  String runtimeUser,
  String runtimePassword,
) => Pool<void>.withEndpoints(
  [
    Endpoint(
      host: endpoint.host,
      port: endpoint.port,
      database: endpoint.database,
      username: runtimeUser,
      password: runtimePassword,
    ),
  ],
  settings: const PoolSettings(sslMode: SslMode.disable, maxConnectionCount: 4),
);

ServerApp _serverApp({
  required Endpoint endpoint,
  required String runtimeUser,
  required String runtimePassword,
  required String companyId,
  required String locationId,
  required AuthService auth,
  required PostgresAuthStore store,
  required PlatformDatabase database,
}) => ServerApp(
  config: ServerConfig(
    database: DatabaseConfig(
      host: endpoint.host,
      port: endpoint.port,
      name: endpoint.database,
      user: runtimeUser,
      password: runtimePassword,
    ),
    companyId: companyId,
    locationId: locationId,
    allowedOrigins: {'http://127.0.0.1'},
  ),
  auth: auth,
  store: store,
  platformHandler: createPlatformHandler(auth, database),
);

Future<void> _requireRestrictedRole(
  Connection owner,
  String runtimeUser,
) async {
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

Future<void> _writeJson(File file, Map<String, dynamic> values) async {
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(values));
}

Future<void> _writePrivateManifest(
  File manifest,
  Map<String, dynamic> values,
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
      // Deliberately omit request and response payloads: setup uses passwords.
      throw StateError(
        'Fixture API $method $path returned ${response.statusCode}, '
        'expected $expected.',
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
