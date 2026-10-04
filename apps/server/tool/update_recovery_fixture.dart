// Run from apps/server with `dart run tool/update_recovery_fixture.dart`.
// A dedicated, run-scoped acceptance database is mandatory. The wrapper
// scripts/update/Run-UpdateRecoveryAcceptance.ps1 creates the database, grants
// the restricted runtime role CONNECT and drops the database again. The owner
// connection builds the pre-update schema and seed; the runtime role serves the
// API only after the pending migrations (0011 through 0015) have been applied.
//
// Modes (STOREOS_UPDATE_MODE):
//  - prepare: apply exactly migrations 0001-0010 from a byte-identical copy of
//    the repository files, bootstrap identity, seed representative pre-update
//    evidence with owner SQL, capture stable projections and write the private
//    run manifest plus a non-secret prepare result.
//  - upgrade: apply the real repository migrations through the production
//    MigrationRunner (only 0011 through 0015 may be pending), verify checksums,
//    idempotency, preservation of the pre-update projections, the new
//    0011/0012 columns, constraints and the published-interval exclusion
//    invariant, the 0013 article master, 0014 assortment and 0015 manual stock
//    schema/grants, and that the new database protections reject invalid
//    writes.
//  - smoke: start the current server against the upgraded database with the
//    restricted runtime role and run the bounded real HTTP smoke, including
//    pre-execution cancellation of the all-open legacy published shift, a
//    bounded interval amendment, and an article/assortment/stock journey
//    (open, adjust by movement id, read back and movement history) through the
//    current API.
//  - recovery: verify the isolated restore target from the pre-update encrypted
//    restore point (exactly 0001-0010, unchanged pre-update evidence, fencing)
//    and prove the upgraded source stayed independent. The current server is
//    never started against the recovered 0010 database.
//
// Terminology: "recovery" means restoring the encrypted pre-update restore
// point into an isolated database. This fixture does not implement or prove
// database downgrade, application downgrade or replacement activation.
import 'dart:convert';
import 'merchandising_acceptance.dart';
import 'knowledge_acceptance.dart';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
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
import 'package:storeos_server/src/platform/platform_database.dart';

const _schema = 'storeos_platform';
const _sourcePattern = r'^storeos_update_[a-f0-9]{16}$';
const _targetPattern = r'^storeos_restore_upd_[a-f0-9]{16}$';
const _rolePattern = r'^[a-z_][a-z0-9_]{0,62}$';
const _prefixMaxNumber = '0010';
const _expectedPendingMigrations = [
  '0011_published_shift_cancellation',
  '0012_published_shift_amendment',
  '0013_article_master',
  '0014_location_assortment',
  '0015_manual_stock',
  '0016_local_planograms',
  '0017_approved_operational_knowledge',
];
const _connectionSettings = ConnectionSettings(
  sslMode: SslMode.disable,
  timeZone: 'UTC',
  connectTimeout: Duration(seconds: 15),
);

/// Explicit stable projections. Migration 0011 adds columns to `shifts` and
/// `task_instances`, so those tables are hashed over the columns that existed in
/// 0010 only. Every other evidence table is hashed over all columns. The new
/// 0011 columns are verified separately (existence and NULL/default state).
class _Projection {
  const _Projection(this.columns, this.orderBy);
  final String columns;
  final String orderBy;
}

const _projections = <String, _Projection>{
  'companies': _Projection(
    'id, singleton, name, version, created_at, updated_at',
    'id',
  ),
  'locations': _Projection(
    'id, company_id, name, version, created_at, updated_at',
    'id',
  ),
  'accounts': _Projection(
    'id, username, username_key, password_hash, company_id, location_id, '
        'is_active, created_at, role, version',
    'id',
  ),
  'bootstrap_state': _Projection(
    'singleton, account_id, completed_at',
    'singleton',
  ),
  'employees': _Projection(
    'id, company_id, location_id, display_name, is_active, version, '
        'created_at, updated_at, assigned_from, assigned_until',
    'id',
  ),
  'account_employee_links': _Projection(
    'id, account_id, employee_id, company_id, location_id, version, '
        'linked_at, revoked_at',
    'id',
  ),
  'task_templates': _Projection(
    'id, company_id, location_id, version, created_at, updated_at',
    'id',
  ),
  'task_template_revisions': _Projection(
    'id, template_id, company_id, location_id, revision_number, status, '
        'content, title, created_at, published_at, published_by, '
        'publication_version',
    'id',
  ),
  // Stable pre-0011 projection: cancellation columns are excluded.
  'shifts': _Projection(
    'id, company_id, location_id, employee_id, starts_at, ends_at, status, '
        'version, created_at, updated_at, created_by, creation_input, '
        'published_at, published_by, publication_version',
    'id',
  ),
  'shift_template_selections': _Projection(
    'shift_id, company_id, location_id, template_id, revision_id, position',
    'shift_id, position',
  ),
  // Stable pre-0011 projection: cancelled_at/cancelled_by are excluded.
  'task_instances': _Projection(
    'id, company_id, location_id, shift_id, employee_id, template_id, '
        'revision_id, position, content, title, status, version, created_at, '
        'started_at, started_by, completed_at, completed_by',
    'id',
  ),
  'task_step_results': _Projection(
    'instance_id, company_id, location_id, step_id, position, confirmed_at, '
        'confirmed_by, accepted_version, numeric_attempt_id',
    'instance_id, position, step_id',
  ),
  'task_numeric_attempts': _Projection(
    'id, instance_id, company_id, location_id, step_id, value_scaled, '
        'in_range, recorded_at, recorded_by, accepted_version',
    'instance_id, accepted_version, id',
  ),
  'task_blockings': _Projection(
    'id, instance_id, company_id, location_id, step_id, reason, reported_at, '
        'reported_by, reported_version, resolution, resolved_at, resolved_by, '
        'resolved_version, resolution_kind, numeric_attempt_id',
    'id',
  ),
  'task_execution_commands': _Projection(
    'operation_id, company_id, location_id, instance_id, actor_id, input, '
        'result, recorded_at',
    'operation_id',
  ),
  'audit_entries': _Projection(
    'id, occurred_at, actor_kind, actor_id, company_id, location_id, action, '
        'entity_type, entity_id, changes, correlation_id',
    'id',
  ),
  'plugin_registrations': _Projection(
    'id, company_id, manifest, status, version, location_id, permissions, '
        'subscriptions, approved_at, disabled_at, created_at',
    'id',
  ),
  'event_outbox': _Projection(
    'id, type, schema_version, aggregate_type, aggregate_id, aggregate_version, '
        'company_id, location_id, origin_node_id, actor_id, correlation_id, '
        'causation_id, payload, occurred_at, recorded_at, status, attempts, '
        'next_attempt_at, last_error, dispatched_at',
    'id',
  ),
  'plugin_inbox': _Projection(
    'id, plugin_id, event_id, status, created_at, acknowledged_at',
    'id',
  ),
};

/// Auth sessions and plugin tokens are deliberately not in `_projections`:
/// the restore fencing revokes them, so their rows legitimately change in the
/// recovered target. Active counts are checked separately.
const _sequenceNames = ['audit_entries_id_seq', 'plugin_inbox_id_seq'];

const _seededCounts = <String, int>{
  'companies': 1,
  'locations': 1,
  'accounts': 2,
  'bootstrap_state': 1,
  'employees': 1,
  'account_employee_links': 1,
  'task_templates': 5,
  'task_template_revisions': 5,
  'shifts': 2,
  'shift_template_selections': 5,
  'task_instances': 5,
  'task_step_results': 2,
  'task_numeric_attempts': 2,
  'task_blockings': 2,
  'task_execution_commands': 11,
  // 13 seeded history entries plus the bootstrap audit entry.
  'audit_entries': 14,
  'plugin_registrations': 1,
  'event_outbox': 0,
  'plugin_inbox': 0,
};

Future<void> main() async {
  try {
    await _run();
  } on ServerException catch (error) {
    // PostgreSQL messages name constraints/tables, never credentials.
    stderr.writeln(
      'Update recovery fixture failed: ${error.severity.name} '
      '${error.code ?? 'unknown'}: ${error.message}'
      '${error.constraintName == null ? '' : ' (${error.constraintName})'}',
    );
    exitCode = 1;
  } catch (error) {
    // Fixture-owned validation errors are safe to print; anything else is
    // reduced to its type so credentials and row content cannot enter CI logs.
    stderr.writeln(
      'Update recovery fixture failed: '
      '${error is StateError || error is ArgumentError || error is TypeError ? error : error.runtimeType}.',
    );
    exitCode = 1;
  }
}

Future<void> _run() async {
  final env = Platform.environment;
  final mode = _required(env, 'STOREOS_UPDATE_MODE');
  final source = _required(env, 'STOREOS_UPDATE_SOURCE_DATABASE');
  if (!RegExp(_sourcePattern).hasMatch(source)) {
    throw StateError('Source database name is not a strict update name.');
  }
  switch (mode) {
    case 'prepare':
      await _prepare(env, source);
    case 'upgrade':
      await _upgrade(env, source);
    case 'smoke':
      await _smoke(env, source);
    case 'recovery':
      await _recovery(env, source);
    default:
      throw StateError('Unknown STOREOS_UPDATE_MODE.');
  }
}

Future<void> _prepare(Map<String, String> env, String source) async {
  final manifestFile = File(_required(env, 'STOREOS_UPDATE_MANIFEST'));
  final resultFile = File(_required(env, 'STOREOS_UPDATE_RESULT'));
  if (!manifestFile.isAbsolute || manifestFile.existsSync()) {
    throw StateError('The acceptance manifest path must be new and absolute.');
  }
  if (!resultFile.isAbsolute || resultFile.existsSync()) {
    throw StateError('The prepare result path must be new and absolute.');
  }
  final ownerEndpoint = _ownerEndpoint(env, source);
  final runtimeUser = _runtimeUser(env);
  final companyId = newUuid();
  final locationId = newUuid();
  final adminUser = 'update_accept_admin';
  final workerUser = 'update_accept_worker';
  final adminPassword = _password();
  final workerPassword = _password();
  final ids = <String, String>{
    'workerAccount': newUuid(),
    'employee': newUuid(),
    'link': newUuid(),
    'tOpen': newUuid(),
    'rOpen': newUuid(),
    'sOpen': newUuid(),
    'tInProgress': newUuid(),
    'rInProgress': newUuid(),
    'sInProgress': newUuid(),
    'tBlocked': newUuid(),
    'rBlocked': newUuid(),
    'sBlocked': newUuid(),
    'tCompleted': newUuid(),
    'rCompleted': newUuid(),
    'sCompletedNumber': newUuid(),
    'sCompletedConfirm': newUuid(),
    'tCancelled': newUuid(),
    'rCancelled': newUuid(),
    'sCancelledNumber': newUuid(),
    'shiftOpen': newUuid(),
    'taskOpen': newUuid(),
    'shiftEvidence': newUuid(),
    'taskInProgress': newUuid(),
    'taskBlocked': newUuid(),
    'taskCompleted': newUuid(),
    'taskCancelled': newUuid(),
    'attemptAccepted': newUuid(),
    'attemptRejected': newUuid(),
    'blockingManual': newUuid(),
    'blockingRejected': newUuid(),
    'session': newUuid(),
    'pluginToken': newUuid(),
    'correlation': newUuid(),
  };
  for (var index = 0; index < 11; index++) {
    ids['receipt$index'] = newUuid();
  }

  Connection? owner;
  try {
    owner = await Connection.open(ownerEndpoint, settings: _connectionSettings);
    await _requireRestrictedRole(owner, runtimeUser);
    final base = DateTime.now().toUtc();

    final temporaryPrefix = Directory.systemTemp.createTempSync(
      'storeos-update-prefix-',
    );
    late List<_RepoMigration> prefix;
    List<String> applied;
    try {
      prefix = _copyPrefixMigrations(Directory('migrations'), temporaryPrefix);
      applied = await MigrationRunner(
        connection: owner,
        migrationsDirectory: temporaryPrefix,
        schemaName: _schema,
        runtimeDatabaseUser: runtimeUser,
      ).apply();
    } finally {
      if (temporaryPrefix.existsSync()) {
        temporaryPrefix.deleteSync(recursive: true);
      }
    }
    final prefixTempRemoved = !temporaryPrefix.existsSync();
    final prefixVersions = prefix
        .map((migration) => migration.version)
        .toList();
    if (!_sameList(applied, prefixVersions)) {
      throw StateError('The pre-update prefix did not apply exactly.');
    }
    await _assertPrefixState(owner, prefix);

    final adminId =
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

    await _seed(
      owner,
      companyId: companyId,
      locationId: locationId,
      adminId: adminId,
      workerUsername: workerUser,
      workerPassword: workerPassword,
      ids: ids,
      correlationId: ids['correlation']!,
      base: base,
    );
    await _assertSeeded(owner, ids);
    final snapshot = await _snapshot(owner);

    await _writePrivateManifest(manifestFile, {
      'runId': source.substring('storeos_update_'.length),
      'sourceDatabase': source,
      'companyId': companyId,
      'locationId': locationId,
      'adminAccountId': adminId,
      'adminUsername': adminUser,
      'adminPassword': adminPassword,
      'workerAccountId': ids['workerAccount'],
      'workerUsername': workerUser,
      'workerPassword': workerPassword,
      'employeeId': ids['employee'],
      'shiftOpenId': ids['shiftOpen'],
      'taskOpenId': ids['taskOpen'],
      'shiftEvidenceId': ids['shiftEvidence'],
      'taskInProgressId': ids['taskInProgress'],
      'taskBlockedId': ids['taskBlocked'],
      'taskCompletedId': ids['taskCompleted'],
      'taskCancelledId': ids['taskCancelled'],
      'prefixVersions': prefixVersions,
      'prefixChecksums': {
        for (final migration in prefix) migration.version: migration.checksum,
      },
      'snapshot': snapshot.toJson(),
    });
    await _writeJson(resultFile, {
      'sourceDatabase': source,
      'prefixVersions': prefixVersions,
      'prefixChecksumsVerified': true,
      'prefixByteCopiesVerified': true,
      'prefixTempDirectoryRemoved': prefixTempRemoved,
      'seed': {
        'shifts': 2,
        'taskInstances': 5,
        'states': {
          'open': 1,
          'in_progress': 1,
          'blocked': 1,
          'completed': 1,
          'cancelled': 1,
        },
        'stepResults': 2,
        'numericAttempts': 2,
        'blockings': 2,
        'receipts': 11,
        'auditEntries': 14,
        'activeSessions': 1,
        'activePluginTokens': 1,
      },
      'snapshot': snapshot.toJson(),
    });
    stdout.writeln('update_recovery_fixture_prepared');
  } finally {
    await owner?.close();
  }
}

Future<void> _upgrade(Map<String, String> env, String source) async {
  final manifest = await _readManifest(env, source);
  final resultFile = File(_required(env, 'STOREOS_UPDATE_RESULT'));
  if (!resultFile.isAbsolute || resultFile.existsSync()) {
    throw StateError('The upgrade result path must be new and absolute.');
  }
  final runtimeUser = _runtimeUser(env);
  Connection? owner;
  Connection? guard;
  try {
    owner = await Connection.open(
      _ownerEndpoint(env, source),
      settings: _connectionSettings,
    );
    final before = await _migrationRows(owner);
    final prefixVersions = (manifest['prefixVersions'] as List).cast<String>();
    if (!_sameList(before.versions, prefixVersions)) {
      throw StateError('The source is not at the expected pre-update prefix.');
    }
    final repository = _repositoryMigrations(Directory('migrations'));
    for (final version in prefixVersions) {
      final expected = repository[version];
      if (expected == null || expected != before.checksums[version]) {
        throw StateError('A pre-update migration checksum changed.');
      }
    }

    final applied = await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: _schema,
      runtimeDatabaseUser: runtimeUser,
    ).apply();
    if (!_sameList(applied, _expectedPendingMigrations)) {
      throw StateError(
        'The update did not apply exactly the pending migrations.',
      );
    }
    final second = await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: _schema,
      runtimeDatabaseUser: runtimeUser,
    ).apply();
    if (second.isNotEmpty) {
      throw StateError('A second migration run was not idempotent.');
    }
    final after = await _migrationRows(owner);
    if (after.versions.length != repository.length) {
      throw StateError('The updated migration count is wrong.');
    }
    var checksumsMatch = true;
    for (final entry in repository.entries) {
      if (after.checksums[entry.key] != entry.value) {
        checksumsMatch = false;
      }
    }
    if (!checksumsMatch) {
      throw StateError('An applied migration checksum changed.');
    }

    final expected = _Snapshot.fromJson(
      manifest['snapshot'] as Map<String, dynamic>,
    );
    final current = await _snapshot(owner);
    if (!current.sameTablesAndSequences(expected)) {
      throw StateError('Pre-update evidence changed during the update.');
    }
    if (current.activeSessions != expected.activeSessions ||
        current.activePluginTokens != expected.activePluginTokens) {
      throw StateError('Pre-update access state changed during the update.');
    }

    final newColumns = await _newCancellationColumns(owner);
    final newAmendmentColumns = await _newAmendmentColumns(owner);
    final legacyNull = await _legacyCancellationFieldsAreNull(owner);
    final constraints = await _constraintNames(owner);
    final triggers = await _triggerNames(owner);
    final articleSchema = await _articleMasterSchema(owner, runtimeUser);
    final assortmentSchema = await _assortmentSchema(owner, runtimeUser);
    final stockSchema = await _stockSchema(owner, runtimeUser);

    guard = await Connection.open(
      _ownerEndpoint(env, source),
      settings: _connectionSettings,
    );
    final rejected = <String, bool>{
      'published_shift_evidence_without_transition': await _rejected(
        guard,
        'UPDATE $_schema.shifts SET cancellation_reason = @reason '
        'WHERE id = CAST(@id AS uuid)',
        {'reason': 'not-allowed', 'id': manifest['shiftOpenId']},
      ),
      'cancel_without_evidence': await _rejected(
        guard,
        'UPDATE $_schema.shifts SET status = @status, version = 3 '
        'WHERE id = CAST(@id AS uuid)',
        {'status': 'cancelled', 'id': manifest['shiftOpenId']},
      ),
      'cancelled_instance_gains_unstarted_evidence': await _rejected(
        guard,
        'UPDATE $_schema.task_instances SET cancelled_at = now() '
        'WHERE id = CAST(@id AS uuid)',
        {'id': manifest['taskCancelledId']},
      ),
      'overlapping_published_interval': await _rejected(
        guard,
        'INSERT INTO $_schema.shifts '
        '(id,company_id,location_id,employee_id,starts_at,ends_at,status,'
        'version,created_by,creation_input,published_at,published_by,'
        'publication_version) '
        "SELECT gen_random_uuid(), company_id, location_id, employee_id, "
        "starts_at, ends_at, 'published', 2, created_by, '{}', "
        'clock_timestamp(), created_by, 1 '
        'FROM $_schema.shifts WHERE id = CAST(@id AS uuid)',
        {'id': manifest['shiftOpenId']},
      ),
    };
    if (rejected.values.any((value) => !value)) {
      throw StateError('A new 0011 protection accepted an invalid write.');
    }
    final unchanged = await _publishedShiftUnchanged(
      owner,
      manifest['shiftOpenId']! as String,
    );
    if (!unchanged) {
      throw StateError('An invalid write changed the source.');
    }

    await _writeJson(resultFile, {
      'migrationsBefore': before.versions,
      'applied': applied,
      'migrationsAfter': after.versions,
      'repositoryMigrationCount': repository.length,
      'checksumsMatchRepository': checksumsMatch,
      'secondRunApplied': second,
      'preservation': {
        'projectionsMatch': true,
        'sequencesMatch': true,
        'activeSessionsMatch': true,
        'activePluginTokensMatch': true,
      },
      'newColumns': newColumns,
      'newAmendmentColumns': newAmendmentColumns,
      'legacyCancellationFieldsNull': legacyNull,
      'constraintsPresent': constraints,
      'triggersPresent': triggers,
      'articleMasterSchema': articleSchema,
      'assortmentSchema': assortmentSchema,
      'stockSchema': stockSchema,
      'invalidWritesRejected': rejected,
      'invalidWritesLeftNoChange': true,
    });
    stdout.writeln('update_recovery_fixture_upgraded');
  } finally {
    await guard?.close();
    await owner?.close();
  }
}

Future<void> _smoke(Map<String, String> env, String source) async {
  final manifest = await _readManifest(env, source);
  final resultFile = File(_required(env, 'STOREOS_UPDATE_RESULT'));
  if (!resultFile.isAbsolute || resultFile.existsSync()) {
    throw StateError('The smoke result path must be new and absolute.');
  }
  final runtimeUser = _runtimeUser(env);
  final runtimePassword = _runtimePassword(env);
  final endpoint = _ownerEndpoint(env, source);
  final apiPort = _apiPort(env);
  final companyId = manifest['companyId']! as String;
  final locationId = manifest['locationId']! as String;
  final shiftOpen = manifest['shiftOpenId']! as String;
  final taskOpen = manifest['taskOpenId']! as String;
  final shiftEvidence = manifest['shiftEvidenceId']! as String;
  final taskInProgress = manifest['taskInProgressId']! as String;
  final taskBlocked = manifest['taskBlockedId']! as String;
  final taskCompleted = manifest['taskCompletedId']! as String;
  final taskCancelled = manifest['taskCancelledId']! as String;

  Pool<void>? pool;
  HttpServer? server;
  HttpClient? client;
  Connection? owner;
  try {
    pool = _runtimePool(endpoint, runtimeUser, runtimePassword);
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
      ServerApp(
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
          allowedOrigins: const {'http://127.0.0.1'},
        ),
        auth: auth,
        store: store,
        platformHandler: createPlatformHandler(auth, database),
      ).handler,
      '127.0.0.1',
      apiPort,
    );
    client = HttpClient();
    final api = _Api(client, 'http://127.0.0.1:${server.port}');
    final ready = await api.request('GET', '/ready');
    if (ready['status'] != 'ok') {
      throw StateError('The upgraded server is not ready.');
    }

    final adminLogin = await api.request(
      'POST',
      '/api/v1/auth/login',
      body: {
        'username': manifest['adminUsername'],
        'password': manifest['adminPassword'],
      },
    );
    final adminToken = adminLogin['token'] as String;
    final adminId =
        (adminLogin['user'] as Map<String, dynamic>)['id'] as String;
    final workerLogin = await api.request(
      'POST',
      '/api/v1/auth/login',
      body: {
        'username': manifest['workerUsername'],
        'password': manifest['workerPassword'],
      },
    );
    final workerToken = workerLogin['token'] as String;

    final detail = await api.request(
      'GET',
      '/api/v1/platform/shifts/$shiftEvidence',
      token: adminToken,
    );
    final detailShift = detail['shift'] as Map<String, dynamic>;
    final detailTasks = (detail['tasks'] as List).cast<Map<String, dynamic>>();
    if (detailShift['status'] != 'published' || detailTasks.length != 4) {
      throw StateError('The migrated evidence shift is not readable.');
    }
    final taskById = {
      for (final task in detailTasks) task['id'] as String: task,
    };
    if (taskById[taskInProgress]?['status'] != 'in_progress' ||
        taskById[taskInProgress]?['version'] != 2 ||
        taskById[taskBlocked]?['status'] != 'blocked' ||
        taskById[taskBlocked]?['version'] != 3 ||
        taskById[taskCompleted]?['status'] != 'completed' ||
        taskById[taskCompleted]?['version'] != 5 ||
        taskById[taskCancelled]?['status'] != 'cancelled' ||
        taskById[taskCancelled]?['version'] != 4) {
      throw StateError('Migrated task states differ from the seed plan.');
    }

    Future<Map<String, dynamic>> execution(String task) => api.request(
      'GET',
      '/api/v1/platform/shifts/$shiftEvidence/tasks/$task/execution',
      token: adminToken,
    );
    final blocked = await execution(taskBlocked);
    final completed = await execution(taskCompleted);
    final cancelled = await execution(taskCancelled);
    final running = await execution(taskInProgress);
    if (blocked['status'] != 'blocked' ||
        blocked['activeBlockingId'] is! String ||
        completed['status'] != 'completed' ||
        (completed['results'] as List).length != 2 ||
        cancelled['status'] != 'cancelled' ||
        cancelled['cancelledBlockingId'] is! String ||
        cancelled['cancelledAt'] == null ||
        running['status'] != 'in_progress') {
      throw StateError('Migrated execution evidence is not readable.');
    }

    final home = await api.request(
      'GET',
      '/api/v1/platform/employee-home/shifts',
      token: workerToken,
    );
    final items = (home['items'] as List).cast<Map<String, dynamic>>();
    if (items.length != 1 ||
        (items.single['shift'] as Map)['id'] != shiftOpen) {
      throw StateError('Employee Home does not show the migrated open shift.');
    }
    final homeTasks = (items.single['tasks'] as List)
        .cast<Map<String, dynamic>>();
    if (homeTasks.length != 1 || homeTasks.single['status'] != 'open') {
      throw StateError('Employee Home does not show the pristine open task.');
    }

    final cancelResponse = await api.request(
      'POST',
      '/api/v1/platform/shifts/$shiftOpen/cancel',
      token: adminToken,
      body: {
        'expectedVersion': 2,
        'reason': 'Acceptance cancellation of a pristine published shift',
      },
    );
    final cancelledShift = cancelResponse['shift'] as Map<String, dynamic>;
    final cancelledTasks = (cancelResponse['tasks'] as List)
        .cast<Map<String, dynamic>>();
    if (cancelledShift['status'] != 'cancelled' ||
        cancelledShift['version'] != 3 ||
        cancelledShift['cancellationVersion'] != 2 ||
        cancelledShift['cancelledBy'] != adminId ||
        cancelledTasks.length != 1 ||
        cancelledTasks.single['id'] != taskOpen ||
        cancelledTasks.single['status'] != 'cancelled' ||
        cancelledTasks.single['version'] != 2) {
      throw StateError('The migrated pre-execution cancellation is wrong.');
    }
    final readBack = await api.request(
      'GET',
      '/api/v1/platform/shifts/$shiftOpen/tasks/$taskOpen/execution',
      token: adminToken,
    );
    if (readBack['status'] != 'cancelled' ||
        readBack['version'] != 2 ||
        readBack['cancelledAt'] == null ||
        readBack['cancelledBy'] == null ||
        readBack.containsKey('cancelledBlockingId')) {
      throw StateError('The cancelled task read-back does not match 0011.');
    }

    owner = await Connection.open(
      _ownerEndpoint(env, source),
      settings: _connectionSettings,
    );
    final shiftRow = await owner.execute(
      Sql.named(
        'SELECT status, version, cancellation_version::int, '
        'cancelled_by::text FROM $_schema.shifts WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'id': shiftOpen},
    );
    final shift = shiftRow.single.toColumnMap();
    if (shift['status'] != 'cancelled' ||
        shift['version'] != 3 ||
        shift['cancellation_version'] != 2 ||
        shift['cancelled_by'] != adminId) {
      throw StateError('The persisted migration cancellation is wrong.');
    }
    final taskRow = await owner.execute(
      Sql.named(
        'SELECT status, version FROM $_schema.task_instances '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'id': taskOpen},
    );
    final task = taskRow.single.toColumnMap();
    if (task['status'] != 'cancelled' || task['version'] != 2) {
      throw StateError('The persisted cancelled task is wrong.');
    }
    final audits = await owner.execute(
      Sql.named(
        'SELECT action, entity_id, correlation_id::text AS correlation_id '
        'FROM $_schema.audit_entries '
        'WHERE entity_id IN (@shift, @task) '
        'AND action IN (@shiftAction, @taskAction)',
      ),
      parameters: {
        'shift': shiftOpen,
        'task': taskOpen,
        'shiftAction': 'workforce.shift.cancelled',
        'taskAction': 'tasks.instance.cancelled',
      },
    );
    final auditRows = audits.map((row) => row.toColumnMap()).toList();
    final sharedCorrelation =
        auditRows.isNotEmpty &&
        auditRows.every((row) => row['correlation_id'] != null) &&
        auditRows.map((row) => row['correlation_id']).toSet().length == 1;
    if (auditRows.length != 2 || !sharedCorrelation) {
      throw StateError('The cancellation audit evidence is incomplete.');
    }

    await api.request(
      'POST',
      '/api/v1/platform/organization/setup',
      token: adminToken,
      body: {
        'companyName': 'Update acceptance company',
        'locationName': 'Update acceptance location',
      },
    );
    final templates = await api.request(
      'GET',
      '/api/v1/platform/task-templates',
      token: adminToken,
    );
    final templateItems = (templates['items'] as List)
        .cast<Map<String, dynamic>>();
    final employees = await api.request(
      'GET',
      '/api/v1/platform/employees',
      token: adminToken,
    );
    final employeeItems = (employees['employees'] as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic>? amendmentEmployee;
    for (final item in employeeItems) {
      if (item['isActive'] == true) {
        amendmentEmployee = item;
        break;
      }
    }
    if (templateItems.isEmpty || amendmentEmployee == null) {
      throw StateError('The upgraded server has no amendment prerequisites.');
    }
    final template = templateItems.first;
    final publishedId = template['publishedId'];
    if (publishedId is! String) {
      throw StateError('The seeded template has no published revision.');
    }
    final amendmentShift = newUuid();
    final amendmentStart = DateTime.now().toUtc().add(const Duration(days: 30));
    final amendmentEnd = amendmentStart.add(const Duration(hours: 8));
    await api.request(
      'POST',
      '/api/v1/platform/shifts',
      token: adminToken,
      expected: 201,
      body: {
        'id': amendmentShift,
        'locationId': locationId,
        'employeeId': amendmentEmployee['id'],
        'startsAt': amendmentStart.toIso8601String(),
        'endsAt': amendmentEnd.toIso8601String(),
        'selections': [
          {'templateId': template['id'], 'revisionId': publishedId},
        ],
      },
    );
    await api.request(
      'POST',
      '/api/v1/platform/shifts/$amendmentShift/publish',
      token: adminToken,
      body: {'expectedVersion': 1},
    );
    final amendedStart = amendmentStart.add(const Duration(hours: 1));
    final amendedEnd = amendmentEnd.add(const Duration(hours: 1));
    final amended = await api.request(
      'POST',
      '/api/v1/platform/shifts/$amendmentShift/amend',
      token: adminToken,
      body: {
        'expectedVersion': 2,
        'startsAt': amendedStart.toIso8601String(),
        'endsAt': amendedEnd.toIso8601String(),
      },
    );
    final amendedShift = amended['shift'] as Map<String, dynamic>;
    if (amendedShift['status'] != 'published' ||
        amendedShift['version'] != 3 ||
        amendedShift['amendmentVersion'] != 2 ||
        amendedShift['amendedBy'] != adminId ||
        !DateTime.parse(
          amendedShift['startsAt'] as String,
        ).isAtSameMomentAs(amendedStart) ||
        !DateTime.parse(
          amendedShift['endsAt'] as String,
        ).isAtSameMomentAs(amendedEnd)) {
      throw StateError('The upgraded interval amendment is wrong.');
    }
    final amendmentAudits = await owner.execute(
      Sql.named(
        'SELECT changes FROM $_schema.audit_entries '
        'WHERE entity_id = @id AND action = @action',
      ),
      parameters: {'id': amendmentShift, 'action': 'workforce.shift.amended'},
    );
    if (amendmentAudits.length != 1) {
      throw StateError('The amendment audit evidence is incomplete.');
    }

    final articleId = newUuid();
    final articleCreated = await api.request(
      'POST',
      '/api/v1/platform/articles',
      token: adminToken,
      expected: 201,
      body: {
        'id': articleId,
        'sku': 'UPDATE-PROBE-1',
        'barcode': null,
        'name': 'Migration probe article',
        'description': null,
        'unit': 'Stk',
      },
    );
    final articleRead = await api.request(
      'GET',
      '/api/v1/platform/articles/$articleId',
      token: adminToken,
    );
    if (articleCreated['sku'] != 'UPDATE-PROBE-1' ||
        articleCreated['version'] != 1 ||
        articleCreated['isActive'] != true ||
        articleRead['id'] != articleId ||
        articleRead['name'] != 'Migration probe article') {
      throw StateError('The upgraded article master route is wrong.');
    }
    final articleAudits = await owner.execute(
      Sql.named(
        'SELECT changes FROM $_schema.audit_entries '
        'WHERE entity_id = @id AND action = @action',
      ),
      parameters: {'id': articleId, 'action': 'inventory.article.created'},
    );
    if (articleAudits.length != 1) {
      throw StateError('The article creation audit evidence is incomplete.');
    }

    final assortmentId = newUuid();
    final assortmentCreated = await api.request(
      'POST',
      '/api/v1/platform/locations/$locationId/assortment',
      token: adminToken,
      expected: 201,
      body: {'id': assortmentId, 'articleId': articleId},
    );
    final assortmentRead = await api.request(
      'GET',
      '/api/v1/platform/locations/$locationId/assortment/$assortmentId',
      token: adminToken,
    );
    final embeddedArticle =
        assortmentCreated['article'] as Map<String, dynamic>;
    if (assortmentCreated['locationId'] != locationId ||
        assortmentCreated['isActive'] != true ||
        assortmentCreated['version'] != 1 ||
        embeddedArticle['id'] != articleId ||
        embeddedArticle['isActive'] != true ||
        assortmentRead['id'] != assortmentId ||
        assortmentRead['isActive'] != true) {
      throw StateError('The upgraded assortment route is wrong.');
    }
    final assortmentAudits = await owner.execute(
      Sql.named(
        'SELECT changes FROM $_schema.audit_entries '
        'WHERE entity_id = @id AND action = @action',
      ),
      parameters: {
        'id': assortmentId,
        'action': 'inventory.assortment.created',
      },
    );
    if (assortmentAudits.length != 1) {
      throw StateError('The assortment creation audit evidence is incomplete.');
    }

    final stockLevelId = newUuid();
    final stockOpen = await api.request(
      'POST',
      '/api/v1/platform/locations/$locationId/stock',
      token: adminToken,
      expected: 201,
      body: {
        'id': stockLevelId,
        'articleId': articleId,
        'quantity': '12.5',
        'note': null,
      },
    );
    if (stockOpen['id'] != stockLevelId ||
        stockOpen['articleId'] != articleId ||
        stockOpen['stockUnit'] != 'Stk' ||
        stockOpen['quantity'] != '12.5' ||
        stockOpen['version'] != 1 ||
        stockOpen['assortmentIsActive'] != true) {
      throw StateError('The upgraded stock opening is wrong.');
    }
    final stockMovementId = newUuid();
    final stockAdjusted = await api.request(
      'POST',
      '/api/v1/platform/locations/$locationId/stock/$stockLevelId/adjust',
      token: adminToken,
      body: {
        'movementId': stockMovementId,
        'expectedVersion': 1,
        'quantity': '10',
        'note': 'Update acceptance correction',
      },
    );
    if (stockAdjusted['quantity'] != '10' || stockAdjusted['version'] != 2) {
      throw StateError('The upgraded stock adjustment is wrong.');
    }
    final stockRead = await api.request(
      'GET',
      '/api/v1/platform/locations/$locationId/stock/$stockLevelId',
      token: adminToken,
    );
    final stockHistory = await api.request(
      'GET',
      '/api/v1/platform/locations/$locationId/stock/$stockLevelId/movements',
      token: adminToken,
    );
    final historyItems = (stockHistory['items'] as List)
        .cast<Map<String, dynamic>>();
    if (stockRead['quantity'] != '10' ||
        stockRead['version'] != 2 ||
        historyItems.length != 2 ||
        historyItems.first['kind'] != 'adjustment' ||
        historyItems.first['id'] != stockMovementId ||
        historyItems.first['delta'] != '-2.5' ||
        historyItems.first['balanceAfter'] != '10' ||
        historyItems.first['balanceVersion'] != 2 ||
        historyItems.last['kind'] != 'opening' ||
        historyItems.last['balanceAfter'] != '12.5') {
      throw StateError('The upgraded stock read-back is wrong.');
    }
    final stockAudits = await owner.execute(
      Sql.named(
        'SELECT action FROM $_schema.audit_entries '
        'WHERE entity_id = @id AND action IN (@opened, @adjusted)',
      ),
      parameters: {
        'id': stockLevelId,
        'opened': 'stock.level.opened',
        'adjusted': 'stock.level.adjusted',
      },
    );
    if (stockAudits.length != 2) {
      throw StateError('The stock audit evidence is incomplete.');
    }

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
    await seedApprovedKnowledge(
      (method, route, body, status) => api.request(
        method,
        route,
        token: adminToken,
        body: body,
        expected: status,
      ),
    );
    await verifyKnowledgeEvidence(owner, _schema, runtimeUser);
    await _writeJson(resultFile, {
      'knowledge': {
        'migration': '0017_approved_operational_knowledge',
        'articleCount': 2,
        'revisionCount': 6,
        'replayVerified': true,
        'runtimeProtections': true,
      },
      'merchandising': {
        'revisionCount': 2,
        'assignmentCount': 2,
        'pinnedPrint': true,
      },
      'ready': true,
      'adminLogin': true,
      'workerLogin': true,
      'shiftDetail': {
        'status': 'published',
        'taskCount': 4,
        'states': {
          'in_progress': 1,
          'blocked': 1,
          'completed': 1,
          'cancelled': 1,
        },
      },
      'executionReads': {
        'in_progress': 'in_progress',
        'blocked': 'blocked',
        'completed': 'completed',
        'cancelled': 'cancelled',
      },
      'employeeHome': {
        'itemCount': 1,
        'openShiftVisible': true,
        'openTaskVisible': true,
      },
      'cancellation': {
        'shiftStatus': 'cancelled',
        'shiftVersion': 3,
        'taskStatus': 'cancelled',
        'taskVersion': 2,
        'cancellationVersion': 2,
      },
      'readBack': {
        'status': 'cancelled',
        'version': 2,
        'hasCancellationEvidence': true,
      },
      'amendment': {
        'shiftStatus': 'published',
        'shiftVersion': 3,
        'amendmentVersion': 2,
        'auditVerified': true,
      },
      'articleMaster': {
        'created': true,
        'readBack': true,
        'auditVerified': true,
      },
      'assortment': {'created': true, 'readBack': true, 'auditVerified': true},
      'stock': {
        'opened': true,
        'adjusted': true,
        'readBack': true,
        'movementHistory': 2,
        'auditVerified': true,
      },
      'auditVerified': true,
      'correlationShared': true,
    });
    stdout.writeln('update_recovery_fixture_smoked');
  } finally {
    client?.close(force: true);
    await server?.close(force: true);
    await owner?.close();
    await pool?.close();
  }
}

Future<void> _recovery(Map<String, String> env, String source) async {
  final manifest = await _readManifest(env, source);
  final target = _required(env, 'STOREOS_UPDATE_TARGET_DATABASE');
  if (!RegExp(_targetPattern).hasMatch(target)) {
    throw StateError('Target database name is not a strict recovery name.');
  }
  final resultFile = File(_required(env, 'STOREOS_UPDATE_RESULT'));
  if (!resultFile.isAbsolute || resultFile.existsSync()) {
    throw StateError('The recovery result path must be new and absolute.');
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

    final targetMigrations = await _migrationRows(targetOwner);
    final targetVersions = targetMigrations.versions;
    if (targetVersions.length != 10 ||
        targetVersions.last.substring(0, 4) != _prefixMaxNumber ||
        targetVersions.any(_expectedPendingMigrations.contains)) {
      throw StateError('The recovered database is not at the prefix.');
    }
    final targetColumns = await _newCancellationColumns(targetOwner);
    final targetAmendmentColumns = await _newAmendmentColumns(targetOwner);
    if (targetColumns.values.any((present) => present) ||
        targetAmendmentColumns.values.any((present) => present)) {
      throw StateError(
        'The recovered database already has post-prefix columns.',
      );
    }

    final expected = _Snapshot.fromJson(
      manifest['snapshot'] as Map<String, dynamic>,
    );
    final recovered = await _snapshot(targetOwner);
    if (!recovered.sameTablesAndSequences(expected)) {
      throw StateError('Recovered pre-update evidence differs from the seed.');
    }
    final recoveredSessions = await _activeSessions(targetOwner);
    final recoveredTokens = await _activePluginTokens(targetOwner);
    if (recoveredSessions != 0) {
      throw StateError('The recovered database still has active sessions.');
    }
    if (recoveredTokens != 0) {
      throw StateError(
        'The recovered database still has active plugin tokens.',
      );
    }
    final recoveredConnect = await _runtimeConnect(targetOwner, runtimeUser);
    if (recoveredConnect) {
      throw StateError('The recovered database still allows runtime CONNECT.');
    }
    await _requireRuntimeTargetRejected(
      _runtimeEndpoint(env, target, runtimeUser, runtimePassword),
    );
    final targetAccounts = await targetOwner.execute(
      'SELECT (SELECT count(*)::bigint FROM $_schema.accounts) AS accounts, '
      '(SELECT count(*)::bigint FROM $_schema.bootstrap_state) AS bootstrap',
    );
    final bootstrap = targetAccounts.single.toColumnMap();
    if (bootstrap['accounts'] != 2 || bootstrap['bootstrap'] != 1) {
      throw StateError('The recovered identity rows are incomplete.');
    }
    final recoveredState = await targetOwner.execute(
      Sql.named(
        'SELECT status, version FROM $_schema.shifts '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'id': manifest['shiftOpenId']},
    );
    final recoveredShift = recoveredState.single.toColumnMap();
    if (recoveredShift['status'] != 'published' ||
        recoveredShift['version'] != 2) {
      throw StateError('The recovered database contains post-update effects.');
    }

    final sourceMigrations = await _migrationRows(sourceOwner);
    if (sourceMigrations.versions.length !=
            10 + _expectedPendingMigrations.length ||
        sourceMigrations.versions.last != _expectedPendingMigrations.last) {
      throw StateError('The upgraded source is not at the latest migration.');
    }
    final sourceState = await sourceOwner.execute(
      Sql.named(
        'SELECT status, version FROM $_schema.shifts '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'id': manifest['shiftOpenId']},
    );
    final sourceShift = sourceState.single.toColumnMap();
    if (sourceShift['status'] != 'cancelled' || sourceShift['version'] != 3) {
      throw StateError('The upgraded source lost its smoke result.');
    }
    final sourceAudits = await sourceOwner.execute(
      Sql.named(
        'SELECT count(*)::bigint FROM $_schema.audit_entries '
        'WHERE action IN (@shiftAction, @taskAction)',
      ),
      parameters: {
        'shiftAction': 'workforce.shift.cancelled',
        'taskAction': 'tasks.instance.cancelled',
      },
    );
    final sourceAuditCount = sourceAudits.single.single! as int;
    if (sourceAuditCount < 2) {
      throw StateError('The upgraded source lost its cancellation audit.');
    }
    final distinct = await sourceOwner.execute(
      Sql.named(
        'SELECT current_database() AS source_name, '
        '(SELECT datname FROM pg_database WHERE datname = @target) AS target_name',
      ),
      parameters: {'target': target},
    );
    final names = distinct.single.toColumnMap();
    if (names['source_name'] == names['target_name']) {
      throw StateError('Source and recovery target are the same database.');
    }

    await _writeJson(resultFile, {
      'targetDatabase': target,
      'targetMigrationCount': targetVersions.length,
      'targetVersions': targetVersions,
      'targetHasNoPostPrefixColumns': true,
      'evidenceProjectionsMatchPreUpdate': true,
      'sequencesMatchPreUpdate': true,
      'activeSessions': recoveredSessions,
      'activePluginTokens': recoveredTokens,
      'runtimeConnectCatalog': recoveredConnect,
      'runtimeConnectionRejected': true,
      'accountsPresent': true,
      'bootstrapSingleton': true,
      'targetPreUpdateBusinessState': true,
      'sourceAtLatest': true,
      'sourceSmokeEvidencePresent': true,
      'sourceDistinctFromTarget': true,
    });
    stdout.writeln('update_recovery_fixture_recovered');
  } finally {
    await targetOwner?.close();
    await sourceOwner?.close();
  }
}

Future<void> _seed(
  Connection owner, {
  required String companyId,
  required String locationId,
  required String adminId,
  required String workerUsername,
  required String workerPassword,
  required Map<String, String> ids,
  required String correlationId,
  required DateTime base,
}) async {
  String u(String key) => ids[key]!;
  final workerHash = await PasswordHasher().hash(workerPassword);
  final at = base;
  final assignedFrom = base.subtract(const Duration(hours: 24));
  final shiftOpenStart = base.add(const Duration(hours: 2));
  final shiftOpenEnd = base.add(const Duration(hours: 6));
  final shiftEvidenceStart = base.subtract(const Duration(hours: 6));
  final shiftEvidenceEnd = base.subtract(const Duration(hours: 2));
  final startInProgress = base.subtract(const Duration(hours: 4));
  final startBlocked = base.subtract(const Duration(hours: 5));
  final blockedReported = base.subtract(const Duration(hours: 4, minutes: 55));
  final startCompleted = base.subtract(const Duration(hours: 5));
  final acceptedAttemptAt = base.subtract(
    const Duration(hours: 4, minutes: 50),
  );
  final acceptedConfirmAt = base.subtract(
    const Duration(hours: 4, minutes: 45),
  );
  final startCancelled = base.subtract(const Duration(hours: 4, minutes: 30));
  final rejectedAttemptAt = base.subtract(
    const Duration(hours: 4, minutes: 25),
  );
  final rejectedResolvedAt = base.subtract(
    const Duration(hours: 4, minutes: 20),
  );

  String confirmationContent(String title, String stepId) => jsonEncode({
    'schemaVersion': 2,
    'title': title,
    'steps': [
      {'id': stepId, 'type': 'confirmation', 'instruction': 'Confirm $title'},
    ],
  });
  final completedContent = jsonEncode({
    'schemaVersion': 2,
    'title': 'Update acceptance completed work',
    'steps': [
      {
        'id': u('sCompletedNumber'),
        'type': 'number',
        'instruction': 'Record the accepted measurement',
        'unit': 'C',
        'minimum': '-2.125',
        'maximum': '4.5',
      },
      {
        'id': u('sCompletedConfirm'),
        'type': 'confirmation',
        'instruction': 'Confirm the accepted measurement',
      },
    ],
  });
  final cancelledContent = jsonEncode({
    'schemaVersion': 2,
    'title': 'Update acceptance rejected measurement',
    'steps': [
      {
        'id': u('sCancelledNumber'),
        'type': 'number',
        'instruction': 'Record the rejected measurement',
        'unit': 'C',
        'minimum': '-2.125',
        'maximum': '4.5',
      },
    ],
  });

  await owner.runTx((tx) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.accounts '
        '(id, username, username_key, password_hash, company_id, location_id, '
        'is_active, role, version) '
        "VALUES (CAST(@id AS uuid), @username, @usernameKey, @hash, "
        "CAST(@company AS uuid), CAST(@location AS uuid), true, 'employee', 1)",
      ),
      parameters: {
        'id': u('workerAccount'),
        'username': workerUsername,
        'usernameKey': workerUsername,
        'hash': workerHash,
        'company': companyId,
        'location': locationId,
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.employees '
        '(id, company_id, location_id, display_name, is_active, version, '
        'created_at, updated_at, assigned_from, assigned_until) '
        "VALUES (CAST(@id AS uuid), CAST(@company AS uuid), "
        "CAST(@location AS uuid), 'Update Acceptance Worker', true, 1, "
        '@at, @at, @assignedFrom, NULL)',
      ),
      parameters: {
        'id': u('employee'),
        'company': companyId,
        'location': locationId,
        'at': at,
        'assignedFrom': assignedFrom,
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.account_employee_links '
        '(id, account_id, employee_id, company_id, location_id, version, '
        'linked_at, revoked_at) '
        'VALUES (CAST(@id AS uuid), CAST(@account AS uuid), '
        'CAST(@employee AS uuid), CAST(@company AS uuid), '
        'CAST(@location AS uuid), 1, @at, NULL)',
      ),
      parameters: {
        'id': u('link'),
        'account': u('workerAccount'),
        'employee': u('employee'),
        'company': companyId,
        'location': locationId,
        'at': at,
      },
    );

    Future<void> template(
      String templateId,
      String revisionId,
      String content,
    ) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.task_templates '
          '(id, company_id, location_id, version, created_at, updated_at) '
          'VALUES (CAST(@id AS uuid), CAST(@company AS uuid), '
          'CAST(@location AS uuid), 2, @at, @at)',
        ),
        parameters: {
          'id': templateId,
          'company': companyId,
          'location': locationId,
          'at': at,
        },
      );
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.task_template_revisions '
          '(id, template_id, company_id, location_id, revision_number, '
          'status, content, created_at, published_at, published_by, '
          'publication_version) '
          "VALUES (CAST(@id AS uuid), CAST(@template AS uuid), "
          "CAST(@company AS uuid), CAST(@location AS uuid), 1, 'published', "
          'CAST(@content AS jsonb), @at, @at, CAST(@admin AS uuid), 1)',
        ),
        parameters: {
          'id': revisionId,
          'template': templateId,
          'company': companyId,
          'location': locationId,
          'content': content,
          'at': at,
          'admin': adminId,
        },
      );
    }

    await template(
      u('tOpen'),
      u('rOpen'),
      confirmationContent('Update acceptance open work', u('sOpen')),
    );
    await template(
      u('tInProgress'),
      u('rInProgress'),
      confirmationContent('Update acceptance running work', u('sInProgress')),
    );
    await template(
      u('tBlocked'),
      u('rBlocked'),
      confirmationContent('Update acceptance blocked work', u('sBlocked')),
    );
    await template(u('tCompleted'), u('rCompleted'), completedContent);
    await template(u('tCancelled'), u('rCancelled'), cancelledContent);

    Future<void> shiftDraft(
      String shiftId,
      DateTime startsAt,
      DateTime endsAt, {
      required List<(String template, String revision)> selections,
    }) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.shifts '
          '(id, company_id, location_id, employee_id, starts_at, ends_at, '
          'status, version, created_at, updated_at, created_by, '
          'creation_input) '
          "VALUES (CAST(@id AS uuid), CAST(@company AS uuid), "
          "CAST(@location AS uuid), CAST(@employee AS uuid), @startsAt, "
          "@endsAt, 'draft', 1, @at, @at, CAST(@admin AS uuid), "
          '@creationInput)',
        ),
        parameters: {
          'id': shiftId,
          'company': companyId,
          'location': locationId,
          'employee': u('employee'),
          'startsAt': startsAt,
          'endsAt': endsAt,
          'at': at,
          'admin': adminId,
          'creationInput': jsonEncode({
            'employeeId': u('employee'),
            'startsAt': startsAt.toIso8601String(),
            'endsAt': endsAt.toIso8601String(),
            'selections': [
              for (final selection in selections)
                {'templateId': selection.$1, 'revisionId': selection.$2},
            ],
          }),
        },
      );
      for (var position = 0; position < selections.length; position++) {
        final selection = selections[position];
        await tx.execute(
          Sql.named(
            'INSERT INTO $_schema.shift_template_selections '
            '(shift_id, company_id, location_id, template_id, revision_id, '
            'position) '
            'VALUES (CAST(@shift AS uuid), CAST(@company AS uuid), '
            'CAST(@location AS uuid), CAST(@template AS uuid), '
            'CAST(@revision AS uuid), @position)',
          ),
          parameters: {
            'shift': shiftId,
            'company': companyId,
            'location': locationId,
            'template': selection.$1,
            'revision': selection.$2,
            'position': position,
          },
        );
      }
    }

    Future<void> task(
      String taskId,
      String shiftId,
      String templateId,
      String revisionId,
      String content,
      int position,
    ) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.task_instances '
          '(id, company_id, location_id, shift_id, employee_id, template_id, '
          'revision_id, position, content, status, version, created_at) '
          "VALUES (CAST(@id AS uuid), CAST(@company AS uuid), "
          "CAST(@location AS uuid), CAST(@shift AS uuid), "
          "CAST(@employee AS uuid), CAST(@template AS uuid), "
          "CAST(@revision AS uuid), @position, CAST(@content AS jsonb), "
          "'open', 1, @at)",
        ),
        parameters: {
          'id': taskId,
          'company': companyId,
          'location': locationId,
          'shift': shiftId,
          'employee': u('employee'),
          'template': templateId,
          'revision': revisionId,
          'position': position,
          'content': content,
          'at': at,
        },
      );
    }

    Future<void> publish(String shiftId) async {
      await tx.execute(
        Sql.named(
          'UPDATE $_schema.shifts SET status = @status, version = 2, '
          'updated_at = @at, published_at = @at, '
          'published_by = CAST(@admin AS uuid), publication_version = 1 '
          'WHERE id = CAST(@id AS uuid)',
        ),
        parameters: {
          'status': 'published',
          'at': at,
          'admin': adminId,
          'id': shiftId,
        },
      );
    }

    Future<void> start(String taskId, DateTime startedAt) async {
      await tx.execute(
        Sql.named(
          'UPDATE $_schema.task_instances SET status = @status, version = 2, '
          'started_at = @startedAt, started_by = CAST(@worker AS uuid) '
          'WHERE id = CAST(@id AS uuid)',
        ),
        parameters: {
          'status': 'in_progress',
          'startedAt': startedAt,
          'worker': u('workerAccount'),
          'id': taskId,
        },
      );
    }

    // Shift A: one pristine open task; used by the post-upgrade cancellation.
    await shiftDraft(
      u('shiftOpen'),
      shiftOpenStart,
      shiftOpenEnd,
      selections: [(u('tOpen'), u('rOpen'))],
    );
    await task(
      u('taskOpen'),
      u('shiftOpen'),
      u('tOpen'),
      u('rOpen'),
      confirmationContent('Update acceptance open work', u('sOpen')),
      0,
    );
    await publish(u('shiftOpen'));

    // Shift B: legacy execution evidence in every supported task state.
    await shiftDraft(
      u('shiftEvidence'),
      shiftEvidenceStart,
      shiftEvidenceEnd,
      selections: [
        (u('tInProgress'), u('rInProgress')),
        (u('tBlocked'), u('rBlocked')),
        (u('tCompleted'), u('rCompleted')),
        (u('tCancelled'), u('rCancelled')),
      ],
    );
    await task(
      u('taskInProgress'),
      u('shiftEvidence'),
      u('tInProgress'),
      u('rInProgress'),
      confirmationContent('Update acceptance running work', u('sInProgress')),
      0,
    );
    await task(
      u('taskBlocked'),
      u('shiftEvidence'),
      u('tBlocked'),
      u('rBlocked'),
      confirmationContent('Update acceptance blocked work', u('sBlocked')),
      1,
    );
    await task(
      u('taskCompleted'),
      u('shiftEvidence'),
      u('tCompleted'),
      u('rCompleted'),
      completedContent,
      2,
    );
    await task(
      u('taskCancelled'),
      u('shiftEvidence'),
      u('tCancelled'),
      u('rCancelled'),
      cancelledContent,
      3,
    );
    await publish(u('shiftEvidence'));

    // in_progress: started, no results yet.
    await start(u('taskInProgress'), startInProgress);

    // blocked: manual blocked-origin state with an active blocking.
    await start(u('taskBlocked'), startBlocked);
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_blockings '
        '(id, instance_id, company_id, location_id, step_id, reason, '
        'reported_at, reported_by, reported_version, resolution, resolved_at, '
        'resolved_by, resolved_version, resolution_kind, numeric_attempt_id) '
        "VALUES (CAST(@id AS uuid), CAST(@task AS uuid), "
        "CAST(@company AS uuid), CAST(@location AS uuid), "
        "CAST(@step AS uuid), @reason, @reportedAt, "
        'CAST(@worker AS uuid), 3, NULL, NULL, NULL, NULL, NULL, NULL)',
      ),
      parameters: {
        'id': u('blockingManual'),
        'task': u('taskBlocked'),
        'company': companyId,
        'location': locationId,
        'step': u('sBlocked'),
        'reason': 'Manual block recorded for acceptance seed',
        'reportedAt': blockedReported,
        'worker': u('workerAccount'),
      },
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 3 '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'status': 'blocked', 'id': u('taskBlocked')},
    );

    // cancelled: rejected numeric attempt resolved as blocked-origin
    // cancellation. Instance-level cancellation evidence stays NULL.
    await start(u('taskCancelled'), startCancelled);
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_numeric_attempts '
        '(id, instance_id, company_id, location_id, step_id, value_scaled, '
        'in_range, recorded_at, recorded_by, accepted_version) '
        'VALUES (CAST(@id AS uuid), CAST(@task AS uuid), '
        'CAST(@company AS uuid), CAST(@location AS uuid), '
        'CAST(@step AS uuid), 5000, false, @recordedAt, '
        'CAST(@worker AS uuid), 3)',
      ),
      parameters: {
        'id': u('attemptRejected'),
        'task': u('taskCancelled'),
        'company': companyId,
        'location': locationId,
        'step': u('sCancelledNumber'),
        'recordedAt': rejectedAttemptAt,
        'worker': u('workerAccount'),
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_blockings '
        '(id, instance_id, company_id, location_id, step_id, reason, '
        'reported_at, reported_by, reported_version, resolution, resolved_at, '
        'resolved_by, resolved_version, resolution_kind, numeric_attempt_id) '
        "VALUES (CAST(@id AS uuid), CAST(@task AS uuid), "
        "CAST(@company AS uuid), CAST(@location AS uuid), "
        "CAST(@step AS uuid), @reason, @reportedAt, "
        'CAST(@worker AS uuid), 3, NULL, NULL, NULL, NULL, NULL, '
        'CAST(@attempt AS uuid))',
      ),
      parameters: {
        'id': u('blockingRejected'),
        'task': u('taskCancelled'),
        'company': companyId,
        'location': locationId,
        'step': u('sCancelledNumber'),
        'reason': 'Rejected measurement recorded for acceptance seed',
        'reportedAt': rejectedAttemptAt,
        'worker': u('workerAccount'),
        'attempt': u('attemptRejected'),
      },
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 3 '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'status': 'blocked', 'id': u('taskCancelled')},
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_blockings SET resolution = @resolution, '
        'resolved_at = @resolvedAt, resolved_by = CAST(@worker AS uuid), '
        'resolved_version = 4, resolution_kind = @kind '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {
        'resolution': 'Cancelled after acceptance review',
        'resolvedAt': rejectedResolvedAt,
        'worker': u('workerAccount'),
        'kind': 'cancelled',
        'id': u('blockingRejected'),
      },
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 4 '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'status': 'cancelled', 'id': u('taskCancelled')},
    );

    // completed: accepted numeric attempt then a confirmation.
    await start(u('taskCompleted'), startCompleted);
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_numeric_attempts '
        '(id, instance_id, company_id, location_id, step_id, value_scaled, '
        'in_range, recorded_at, recorded_by, accepted_version) '
        'VALUES (CAST(@id AS uuid), CAST(@task AS uuid), '
        'CAST(@company AS uuid), CAST(@location AS uuid), '
        'CAST(@step AS uuid), 1500, true, @recordedAt, '
        'CAST(@worker AS uuid), 3)',
      ),
      parameters: {
        'id': u('attemptAccepted'),
        'task': u('taskCompleted'),
        'company': companyId,
        'location': locationId,
        'step': u('sCompletedNumber'),
        'recordedAt': acceptedAttemptAt,
        'worker': u('workerAccount'),
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_step_results '
        '(instance_id, company_id, location_id, step_id, position, '
        'confirmed_at, confirmed_by, accepted_version, numeric_attempt_id) '
        'VALUES (CAST(@task AS uuid), CAST(@company AS uuid), '
        'CAST(@location AS uuid), CAST(@step AS uuid), 0, @confirmedAt, '
        'CAST(@worker AS uuid), 3, CAST(@attempt AS uuid))',
      ),
      parameters: {
        'task': u('taskCompleted'),
        'company': companyId,
        'location': locationId,
        'step': u('sCompletedNumber'),
        'confirmedAt': acceptedAttemptAt,
        'worker': u('workerAccount'),
        'attempt': u('attemptAccepted'),
      },
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 3 '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'status': 'in_progress', 'id': u('taskCompleted')},
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.task_step_results '
        '(instance_id, company_id, location_id, step_id, position, '
        'confirmed_at, confirmed_by, accepted_version, numeric_attempt_id) '
        'VALUES (CAST(@task AS uuid), CAST(@company AS uuid), '
        'CAST(@location AS uuid), CAST(@step AS uuid), 1, @confirmedAt, '
        'CAST(@worker AS uuid), 4, NULL)',
      ),
      parameters: {
        'task': u('taskCompleted'),
        'company': companyId,
        'location': locationId,
        'step': u('sCompletedConfirm'),
        'confirmedAt': acceptedConfirmAt,
        'worker': u('workerAccount'),
      },
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 4 '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'status': 'in_progress', 'id': u('taskCompleted')},
    );
    await tx.execute(
      Sql.named(
        'UPDATE $_schema.task_instances SET status = @status, version = 5, '
        'completed_at = @completedAt, completed_by = CAST(@worker AS uuid) '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {
        'status': 'completed',
        'completedAt': acceptedConfirmAt,
        'worker': u('workerAccount'),
        'id': u('taskCompleted'),
      },
    );

    Future<void> receipt(
      String key,
      String taskId,
      String input,
      String result,
      DateTime recordedAt,
    ) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.task_execution_commands '
          '(operation_id, company_id, location_id, instance_id, actor_id, '
          'input, result, recorded_at) '
          'VALUES (CAST(@id AS uuid), CAST(@company AS uuid), '
          'CAST(@location AS uuid), CAST(@task AS uuid), '
          'CAST(@actor AS uuid), @input, @result, @recordedAt)',
        ),
        parameters: {
          'id': ids[key],
          'company': companyId,
          'location': locationId,
          'task': taskId,
          'actor': u('workerAccount'),
          'input': input,
          'result': result,
          'recordedAt': recordedAt,
        },
      );
    }

    const startInput = '{"expectedVersion":1}';
    const startResult = '{"status":"in_progress","version":2}';
    await receipt(
      'receipt0',
      u('taskBlocked'),
      startInput,
      startResult,
      startBlocked,
    );
    await receipt(
      'receipt1',
      u('taskBlocked'),
      '{"expectedVersion":2,"reason":"Manual block recorded for acceptance seed"}',
      '{"status":"blocked","version":3}',
      blockedReported,
    );
    await receipt(
      'receipt2',
      u('taskInProgress'),
      startInput,
      startResult,
      startInProgress,
    );
    await receipt(
      'receipt3',
      u('taskCancelled'),
      startInput,
      startResult,
      startCancelled,
    );
    await receipt(
      'receipt4',
      u('taskCancelled'),
      '{"expectedVersion":2,"value":"5"}',
      '{"status":"blocked","version":3}',
      rejectedAttemptAt,
    );
    await receipt(
      'receipt5',
      u('taskCancelled'),
      '{"expectedVersion":3,"reason":"Cancelled after acceptance review"}',
      '{"status":"cancelled","version":4}',
      rejectedResolvedAt,
    );
    await receipt(
      'receipt6',
      u('taskCompleted'),
      startInput,
      startResult,
      startCompleted,
    );
    await receipt(
      'receipt7',
      u('taskCompleted'),
      '{"expectedVersion":2,"value":"1.5"}',
      '{"status":"in_progress","version":3}',
      acceptedAttemptAt,
    );
    await receipt(
      'receipt8',
      u('taskCompleted'),
      '{"expectedVersion":3}',
      '{"status":"in_progress","version":4}',
      acceptedConfirmAt,
    );
    await receipt(
      'receipt9',
      u('taskCompleted'),
      '{"expectedVersion":4}',
      '{"status":"completed","version":5}',
      acceptedConfirmAt,
    );
    await receipt(
      'receipt10',
      u('taskInProgress'),
      '{"expectedVersion":2}',
      '{"status":"in_progress","version":3}',
      startInProgress,
    );

    Future<void> audit(
      String action,
      String entityType,
      String entityId,
      DateTime occurredAt,
      Map<String, dynamic> changes,
      String actorId,
    ) async {
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.audit_entries '
          '(occurred_at, actor_kind, actor_id, company_id, location_id, '
          'action, entity_type, entity_id, changes, correlation_id) '
          "VALUES (@occurredAt, 'user', @actor, CAST(@company AS uuid), "
          'CAST(@location AS uuid), @action, @entityType, @entityId, '
          'CAST(@changes AS jsonb), CAST(@correlation AS uuid))',
        ),
        parameters: {
          'occurredAt': occurredAt,
          'actor': actorId,
          'company': companyId,
          'location': locationId,
          'action': action,
          'entityType': entityType,
          'entityId': entityId,
          'changes': jsonEncode(changes),
          'correlation': correlationId,
        },
      );
    }

    await audit('workforce.shift.published', 'shift', u('shiftOpen'), at, {
      'status': 'published',
      'version': 2,
    }, adminId);
    await audit('workforce.shift.published', 'shift', u('shiftEvidence'), at, {
      'status': 'published',
      'version': 2,
    }, adminId);
    await audit(
      'tasks.instance.started',
      'task_instance',
      u('taskBlocked'),
      startBlocked,
      {'status': 'in_progress', 'version': 2},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.blocked',
      'task_instance',
      u('taskBlocked'),
      blockedReported,
      {'status': 'blocked', 'version': 3},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.started',
      'task_instance',
      u('taskCompleted'),
      startCompleted,
      {'status': 'in_progress', 'version': 2},
      u('workerAccount'),
    );
    await audit(
      'tasks.step.number_recorded',
      'task_instance',
      u('taskCompleted'),
      acceptedAttemptAt,
      {'stepId': u('sCompletedNumber'), 'inRange': true},
      u('workerAccount'),
    );
    await audit(
      'tasks.step.confirmed',
      'task_instance',
      u('taskCompleted'),
      acceptedConfirmAt,
      {'stepId': u('sCompletedConfirm')},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.completed',
      'task_instance',
      u('taskCompleted'),
      acceptedConfirmAt,
      {'status': 'completed', 'version': 5},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.started',
      'task_instance',
      u('taskCancelled'),
      startCancelled,
      {'status': 'in_progress', 'version': 2},
      u('workerAccount'),
    );
    await audit(
      'tasks.step.number_recorded',
      'task_instance',
      u('taskCancelled'),
      rejectedAttemptAt,
      {'stepId': u('sCancelledNumber'), 'inRange': false},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.blocked',
      'task_instance',
      u('taskCancelled'),
      rejectedAttemptAt,
      {'status': 'blocked', 'version': 3},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.cancelled',
      'task_instance',
      u('taskCancelled'),
      rejectedResolvedAt,
      {'status': 'cancelled', 'version': 4, 'origin': 'blocked'},
      u('workerAccount'),
    );
    await audit(
      'tasks.instance.started',
      'task_instance',
      u('taskInProgress'),
      startInProgress,
      {'status': 'in_progress', 'version': 2},
      u('workerAccount'),
    );

    final sessionTokenHash = sha256
        .convert(utf8.encode(_password()))
        .toString();
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.auth_sessions '
        '(id, account_id, token_hash, created_at, expires_at, revoked_at) '
        'VALUES (CAST(@id AS uuid), CAST(@account AS uuid), @hash, @createdAt, '
        '@expiresAt, NULL)',
      ),
      parameters: {
        'id': u('session'),
        'account': adminId,
        'hash': sessionTokenHash,
        'createdAt': at,
        'expiresAt': at.add(const Duration(hours: 24)),
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.plugin_registrations '
        '(id, company_id, manifest, status, version, location_id, '
        'permissions, subscriptions, approved_at, created_at) '
        "VALUES (@id, CAST(@company AS uuid), CAST(@manifest AS jsonb), "
        "'approved', 1, CAST(@location AS uuid), '{}', '{}', @at, @at)",
      ),
      parameters: {
        'id': 'update.acceptance-observer',
        'company': companyId,
        'manifest': jsonEncode({
          'id': 'update.acceptance-observer',
          'name': 'Update Acceptance Observer',
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
        }),
        'location': locationId,
        'at': at,
      },
    );
    await tx.execute(
      Sql.named(
        'INSERT INTO $_schema.plugin_tokens '
        '(id, plugin_id, token_hash, created_at, expires_at, revoked_at) '
        'VALUES (CAST(@id AS uuid), @plugin, @hash, @createdAt, @expiresAt, '
        'NULL)',
      ),
      parameters: {
        'id': u('pluginToken'),
        'plugin': 'update.acceptance-observer',
        'hash': sha256.convert(utf8.encode(_password())).toString(),
        'createdAt': at,
        'expiresAt': at.add(const Duration(hours: 24)),
      },
    );
  });
}

Future<void> _assertPrefixState(
  Connection owner,
  List<_RepoMigration> expected,
) async {
  final rows = await owner.execute(
    'SELECT version, checksum FROM $_schema.schema_migrations '
    'ORDER BY version',
  );
  final actual = rows.map((row) => row.toColumnMap()).toList();
  if (actual.length != expected.length) {
    throw StateError('The pre-update prefix is not exactly 0001-0010.');
  }
  for (var index = 0; index < expected.length; index++) {
    final migration = expected[index];
    if (actual[index]['version'] != migration.version ||
        (actual[index]['checksum']! as String).trim() != migration.checksum) {
      throw StateError('A pre-update migration checksum differs.');
    }
  }
}

Future<void> _assertSeeded(Connection owner, Map<String, String> ids) async {
  for (final entry in _seededCounts.entries) {
    final result = await owner.execute(
      'SELECT count(*)::bigint FROM $_schema."${entry.key}"',
    );
    if (result.single.single != entry.value) {
      throw StateError('Seeded ${entry.key} count differs from the plan.');
    }
  }
  final states = await owner.execute(
    'SELECT id::text, status, version FROM $_schema.task_instances '
    'ORDER BY id',
  );
  final byId = {
    for (final row in states)
      row.toColumnMap()['id'] as String: row.toColumnMap(),
  };
  void expectState(String id, String status, int version) {
    final row = byId[ids[id]];
    if (row == null || row['status'] != status || row['version'] != version) {
      throw StateError('Seeded task state differs from the plan.');
    }
  }

  expectState('taskOpen', 'open', 1);
  expectState('taskInProgress', 'in_progress', 2);
  expectState('taskBlocked', 'blocked', 3);
  expectState('taskCompleted', 'completed', 5);
  expectState('taskCancelled', 'cancelled', 4);
  final attempts = await owner.execute(
    'SELECT in_range FROM $_schema.task_numeric_attempts ORDER BY in_range',
  );
  final flags = attempts.map((row) => row.single).toList();
  if (flags.length != 2 || flags[0] != false || flags[1] != true) {
    throw StateError('Seeded numeric attempts differ from the plan.');
  }
  final blockings = await owner.execute(
    'SELECT resolution_kind FROM $_schema.task_blockings ORDER BY id',
  );
  final kinds = blockings.map((row) => row.single).toList();
  if (kinds.length != 2 ||
      !kinds.contains(null) ||
      !kinds.contains('cancelled')) {
    throw StateError('Seeded blockings differ from the plan.');
  }
  final active = await _activeSessions(owner);
  final tokens = await _activePluginTokens(owner);
  if (active != 1 || tokens != 1) {
    throw StateError('Seeded access state differs from the plan.');
  }
}

Future<_Snapshot> _snapshot(Connection owner) async {
  final tables = <String, _TableState>{};
  for (final entry in _projections.entries) {
    final state = await _tableState(owner, entry.key, entry.value);
    tables[entry.key] = state;
  }
  final sequences = <String, _SequenceState>{};
  for (final name in _sequenceNames) {
    final result = await owner.execute(
      'SELECT last_value::text AS last_value, is_called '
      'FROM "$_schema"."$name"',
    );
    final row = result.single.toColumnMap();
    sequences[name] = _SequenceState(
      row['last_value']! as String,
      row['is_called']! as bool,
    );
  }
  return _Snapshot(
    tables: tables,
    sequences: sequences,
    activeSessions: await _activeSessions(owner),
    activePluginTokens: await _activePluginTokens(owner),
  );
}

Future<_TableState> _tableState(
  Connection owner,
  String table,
  _Projection projection,
) async {
  final result = await owner.execute(
    'SELECT count(*)::bigint AS row_count, '
    "coalesce(md5(string_agg(md5(row_to_json(t)::text), '' "
    'ORDER BY ${projection.orderBy})), \'empty\') AS content_hash '
    'FROM (SELECT ${projection.columns} FROM "$_schema"."$table") AS t',
  );
  final row = result.single.toColumnMap();
  return _TableState(row['row_count']! as int, row['content_hash']! as String);
}

Future<int> _activeSessions(Connection owner) async {
  final result = await owner.execute(
    'SELECT count(*)::bigint FROM $_schema.auth_sessions '
    'WHERE revoked_at IS NULL AND expires_at > now()',
  );
  return result.single.single! as int;
}

Future<int> _activePluginTokens(Connection owner) async {
  final result = await owner.execute(
    'SELECT count(*)::bigint FROM $_schema.plugin_tokens '
    'WHERE revoked_at IS NULL AND expires_at > now()',
  );
  return result.single.single! as int;
}

Future<Map<String, bool>> _newCancellationColumns(Connection owner) async {
  const expected = {
    'shifts': [
      'cancelled_at',
      'cancelled_by',
      'cancellation_reason',
      'cancellation_version',
    ],
    'task_instances': ['cancelled_at', 'cancelled_by'],
  };
  final result = await owner.execute(
    "SELECT table_name, column_name FROM information_schema.columns "
    "WHERE table_schema = '$_schema' AND table_name IN "
    "('shifts', 'task_instances')",
  );
  final present = <String, bool>{};
  for (final entry in expected.entries) {
    for (final column in entry.value) {
      present['${entry.key}.$column'] = false;
    }
  }
  for (final row in result) {
    final map = row.toColumnMap();
    final key = '${map['table_name']}.${map['column_name']}';
    if (present.containsKey(key)) present[key] = true;
  }
  return present;
}

Future<Map<String, bool>> _newAmendmentColumns(Connection owner) async {
  const expected = ['amended_at', 'amended_by', 'amendment_version'];
  final result = await owner.execute(
    "SELECT column_name FROM information_schema.columns "
    "WHERE table_schema = '$_schema' AND table_name = 'shifts'",
  );
  final columns = result.map((row) => row.single! as String).toSet();
  return {
    for (final column in expected) 'shifts.$column': columns.contains(column),
  };
}

Future<bool> _legacyCancellationFieldsAreNull(Connection owner) async {
  final shifts = await owner.execute(
    'SELECT count(*)::bigint FROM $_schema.shifts WHERE '
    'cancelled_at IS NOT NULL OR cancelled_by IS NOT NULL OR '
    'cancellation_reason IS NOT NULL OR cancellation_version IS NOT NULL',
  );
  final tasks = await owner.execute(
    'SELECT count(*)::bigint FROM $_schema.task_instances WHERE '
    'cancelled_at IS NOT NULL OR cancelled_by IS NOT NULL',
  );
  return shifts.single.single == 0 && tasks.single.single == 0;
}

Future<Map<String, bool>> _constraintNames(Connection owner) async {
  final result = await owner.execute(
    "SELECT conname FROM pg_constraint WHERE conrelid IN "
    "('$_schema.shifts'::regclass, '$_schema.task_instances'::regclass)",
  );
  final names = result.map((row) => row.single! as String).toSet();
  return {
    'shifts_status': names.contains('shifts_status'),
    'shifts_state': names.contains('shifts_state'),
    'shifts_published_no_overlap': names.contains(
      'shifts_published_no_overlap',
    ),
    'task_execution_status': names.contains('task_execution_status'),
    'task_execution_times': names.contains('task_execution_times'),
  };
}

Future<Map<String, bool>> _triggerNames(Connection owner) async {
  final result = await owner.execute(
    "SELECT tgname FROM pg_trigger WHERE tgrelid IN "
    "('$_schema.shifts'::regclass, '$_schema.task_instances'::regclass) "
    'AND NOT tgisinternal',
  );
  final names = result.map((row) => row.single! as String).toSet();
  return {
    'shifts_immutable': names.contains('shifts_immutable'),
    'instances_immutable': names.contains('instances_immutable'),
  };
}

Future<Map<String, bool>> _articleMasterSchema(
  Connection owner,
  String runtimeUser,
) async {
  final table = await owner.execute(
    "SELECT to_regclass('$_schema.articles')::text AS name",
  );
  final indexes = await owner.execute(
    "SELECT indexname FROM pg_indexes "
    "WHERE schemaname = '$_schema' AND tablename = 'articles'",
  );
  final names = indexes.map((row) => row.single! as String).toSet();
  final grants = await owner.execute(
    Sql.named(
      'SELECT privilege_type FROM information_schema.role_table_grants '
      "WHERE table_schema = '$_schema' AND table_name = 'articles' "
      'AND grantee = @grantee',
    ),
    parameters: {'grantee': runtimeUser},
  );
  final privileges = grants.map((row) => row.single! as String).toSet();
  final result = <String, bool>{
    'tablePresent': table.single.single != null,
    'skuIndexPresent': names.contains('articles_company_sku_key'),
    'barcodeIndexPresent': names.contains('articles_company_barcode'),
    'selectGranted': privileges.contains('SELECT'),
    'insertGranted': privileges.contains('INSERT'),
    'deleteNotGranted': !privileges.contains('DELETE'),
    'truncateNotGranted': !privileges.contains('TRUNCATE'),
  };
  if (result.values.any((value) => !value)) {
    throw StateError('The article master schema probe failed.');
  }
  return result;
}

Future<Map<String, bool>> _assortmentSchema(
  Connection owner,
  String runtimeUser,
) async {
  final table = await owner.execute(
    "SELECT to_regclass('$_schema.article_location_assortment')::text AS name",
  );
  final indexes = await owner.execute(
    "SELECT indexname FROM pg_indexes "
    "WHERE schemaname = '$_schema' "
    "AND tablename = 'article_location_assortment'",
  );
  final names = indexes.map((row) => row.single! as String).toSet();
  final grants = await owner.execute(
    Sql.named(
      'SELECT privilege_type FROM information_schema.role_table_grants '
      "WHERE table_schema = '$_schema' "
      "AND table_name = 'article_location_assortment' "
      'AND grantee = @grantee',
    ),
    parameters: {'grantee': runtimeUser},
  );
  final privileges = grants.map((row) => row.single! as String).toSet();
  final result = <String, bool>{
    'tablePresent': table.single.single != null,
    'pairIndexPresent': names.contains(
      'article_location_assortment_pair_unique',
    ),
    'pageIndexPresent': names.contains(
      'article_location_assortment_location_page',
    ),
    'selectGranted': privileges.contains('SELECT'),
    'insertGranted': privileges.contains('INSERT'),
    'deleteNotGranted': !privileges.contains('DELETE'),
    'truncateNotGranted': !privileges.contains('TRUNCATE'),
  };
  if (result.values.any((value) => !value)) {
    throw StateError('The assortment schema probe failed.');
  }
  return result;
}

Future<Map<String, bool>> _stockSchema(
  Connection owner,
  String runtimeUser,
) async {
  final view = await owner.execute(
    "SELECT to_regclass('$_schema.inventory_article_location_projection')::text AS name",
  );
  final levels = await owner.execute(
    "SELECT to_regclass('$_schema.stock_levels')::text AS name",
  );
  final movements = await owner.execute(
    "SELECT to_regclass('$_schema.stock_movements')::text AS name",
  );
  final constraints = await owner.execute(
    "SELECT conname FROM pg_constraint WHERE conrelid IN "
    "('$_schema.stock_levels'::regclass, "
    "'$_schema.stock_movements'::regclass)",
  );
  final names = constraints.map((row) => row.single! as String).toSet();
  final levelUpdate = await owner.execute(
    Sql.named(
      'SELECT column_name FROM information_schema.column_privileges '
      "WHERE table_schema = '$_schema' AND table_name = 'stock_levels' "
      "AND grantee = @grantee AND privilege_type = 'UPDATE'",
    ),
    parameters: {'grantee': runtimeUser},
  );
  final levelColumns = levelUpdate.map((row) => row.single! as String).toSet();
  final movementGrants = await owner.execute(
    Sql.named(
      'SELECT privilege_type FROM information_schema.role_table_grants '
      "WHERE table_schema = '$_schema' AND table_name = 'stock_movements' "
      'AND grantee = @grantee',
    ),
    parameters: {'grantee': runtimeUser},
  );
  final movementPrivileges = movementGrants
      .map((row) => row.single! as String)
      .toSet();
  final viewGrants = await owner.execute(
    Sql.named(
      'SELECT privilege_type FROM information_schema.role_table_grants '
      "WHERE table_schema = '$_schema' AND "
      "table_name = 'inventory_article_location_projection' "
      'AND grantee = @grantee',
    ),
    parameters: {'grantee': runtimeUser},
  );
  final viewPrivileges = viewGrants.map((row) => row.single! as String).toSet();
  final result = <String, bool>{
    'projectionViewPresent': view.single.single != null,
    'levelTablePresent': levels.single.single != null,
    'movementTablePresent': movements.single.single != null,
    'scopeUniquePresent': names.contains('stock_levels_scope_unique'),
    'movementScopeFkPresent': names.contains('stock_movements_level_fk'),
    'movementVersionUniquePresent': names.contains(
      'stock_movements_level_version_unique',
    ),
    'levelUpdateColumnsExact':
        levelColumns.length == 3 &&
        levelColumns.containsAll({'quantity_scaled', 'version', 'updated_at'}),
    'movementAppendOnly':
        movementPrivileges.containsAll({'SELECT', 'INSERT'}) &&
        !movementPrivileges.contains('UPDATE') &&
        !movementPrivileges.contains('DELETE') &&
        !movementPrivileges.contains('TRUNCATE'),
    'projectionSelectGranted': viewPrivileges.contains('SELECT'),
  };
  if (result.values.any((value) => !value)) {
    throw StateError('The manual stock schema probe failed.');
  }
  return result;
}

Future<bool> _rejected(
  Connection guard,
  String statement,
  Map<String, Object?> parameters,
) async {
  try {
    await guard.execute(Sql.named(statement), parameters: parameters);
    return false;
  } on Object {
    return true;
  }
}

Future<bool> _publishedShiftUnchanged(Connection owner, String shiftId) async {
  final result = await owner.execute(
    Sql.named(
      'SELECT status, version, cancellation_reason FROM $_schema.shifts '
      'WHERE id = CAST(@id AS uuid)',
    ),
    parameters: {'id': shiftId},
  );
  final row = result.single.toColumnMap();
  return row['status'] == 'published' &&
      row['version'] == 2 &&
      row['cancellation_reason'] == null;
}

Future<Map<String, dynamic>> _readManifest(
  Map<String, String> env,
  String source,
) async {
  final manifest = File(_required(env, 'STOREOS_UPDATE_MANIFEST'));
  if (!manifest.isAbsolute || !manifest.existsSync()) {
    throw StateError('The acceptance manifest is missing.');
  }
  final decoded = jsonDecode(await manifest.readAsString());
  if (decoded is! Map<String, dynamic> ||
      decoded['sourceDatabase'] != source ||
      decoded['snapshot'] is! Map<String, dynamic> ||
      decoded['adminPassword'] is! String ||
      decoded['workerPassword'] is! String) {
    throw StateError('The acceptance manifest does not match this run.');
  }
  return decoded;
}

class _MigrationState {
  const _MigrationState(this.versions, this.checksums);
  final List<String> versions;
  final Map<String, String> checksums;
}

Future<_MigrationState> _migrationRows(Connection owner) async {
  final result = await owner.execute(
    'SELECT version, checksum FROM $_schema.schema_migrations '
    'ORDER BY version',
  );
  final versions = <String>[];
  final checksums = <String, String>{};
  for (final row in result) {
    final map = row.toColumnMap();
    final version = map['version']! as String;
    versions.add(version);
    checksums[version] = (map['checksum']! as String).trim();
  }
  return _MigrationState(versions, checksums);
}

Map<String, String> _repositoryMigrations(Directory directory) {
  final files =
      directory
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final checksums = <String, String>{};
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final version = name.substring(0, name.length - '.sql'.length);
    checksums[version] = sha256
        .convert(utf8.encode(file.readAsStringSync()))
        .toString();
  }
  return checksums;
}

class _RepoMigration {
  const _RepoMigration(this.version, this.checksum);
  final String version;
  final String checksum;
}

List<_RepoMigration> _copyPrefixMigrations(
  Directory repositoryMigrations,
  Directory target,
) {
  if (!repositoryMigrations.existsSync()) {
    throw StateError('The repository migrations directory is missing.');
  }
  final files =
      repositoryMigrations
          .listSync(followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final selected = <_RepoMigration>[];
  for (final file in files) {
    final name = file.uri.pathSegments.last;
    final version = name.substring(0, name.length - '.sql'.length);
    if (version.substring(0, 4).compareTo(_prefixMaxNumber) > 0) continue;
    final sourceBytes = file.readAsBytesSync();
    final copy = File('${target.path}/$name');
    copy.writeAsBytesSync(sourceBytes, flush: true);
    if (!_bytesEqual(sourceBytes, copy.readAsBytesSync())) {
      throw StateError('A copied migration is not byte-identical.');
    }
    selected.add(
      _RepoMigration(
        version,
        sha256.convert(utf8.encode(file.readAsStringSync())).toString(),
      ),
    );
  }
  if (selected.isEmpty ||
      selected.last.version.substring(0, 4) != _prefixMaxNumber) {
    throw StateError('The repository prefix migrations are incomplete.');
  }
  return selected;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
}

bool _sameList(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (a[index] != b[index]) return false;
  }
  return true;
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
        value['count']! as int,
        value['hash']! as String,
      );
    }
    final sequences = <String, _SequenceState>{};
    for (final entry in (json['sequences'] as Map<String, dynamic>).entries) {
      final value = entry.value as Map<String, dynamic>;
      sequences[entry.key] = _SequenceState(
        value['lastValue']! as String,
        value['isCalled']! as bool,
      );
    }
    return _Snapshot(
      tables: tables,
      sequences: sequences,
      activeSessions: json['activeSessions']! as int,
      activePluginTokens: json['activePluginTokens']! as int,
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

  bool sameTablesAndSequences(_Snapshot other) {
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
  final host = env['STOREOS_UPDATE_DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['STOREOS_UPDATE_DB_PORT'] ?? '5432');
  final user = _required(env, 'STOREOS_UPDATE_DB_USER');
  final password = File(
    _required(env, 'STOREOS_UPDATE_OWNER_PASSWORD_FILE'),
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
  final host = env['STOREOS_UPDATE_DB_HOST'] ?? '127.0.0.1';
  final port = int.tryParse(env['STOREOS_UPDATE_DB_PORT'] ?? '5432') ?? 5432;
  return Endpoint(
    host: host,
    port: port,
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
  final value = int.tryParse(_required(env, 'STOREOS_UPDATE_API_PORT'));
  if (value == null || value < 1024 || value > 65535) {
    throw StateError('STOREOS_UPDATE_API_PORT must be a TCP port.');
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

Future<bool> _runtimeConnect(Connection owner, String runtimeUser) async {
  final result = await owner.execute(
    Sql.named(
      "SELECT has_database_privilege(@role, current_database(), 'CONNECT')",
    ),
    parameters: {'role': runtimeUser},
  );
  return result.single.single! as bool;
}

Future<void> _requireRuntimeTargetRejected(Endpoint endpoint) async {
  Connection? accepted;
  try {
    accepted = await Connection.open(endpoint, settings: _connectionSettings);
  } on Object {
    return;
  }
  await accepted.close(force: true);
  throw StateError('The recovered database accepted the runtime role.');
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
