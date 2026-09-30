// Run from apps/server with `dart run tool/capacity_fixture.dart`.
// The wrapper scripts/capacity/Run-CapacityMeasurement.ps1 creates the
// run-scoped `storeos_capacity_<run id>` database, grants the restricted
// runtime role CONNECT and drops the database again. The owner connection
// migrates, bootstraps and verifies; the restricted runtime role serves the
// API. The normal StoreOS database is never read, written, migrated, seeded or
// dropped.
//
// The fixture measures the existing stack; it does not optimize it. Timings
// are environment-specific observations and never decide the exit code.
// Failures are correctness failures: unexpected HTTP status, malformed
// response, missing business effect, integrity mismatch or cleanup problem.
//
// Environment (set by the wrapper or by the integration test):
//  STOREOS_CAPACITY_DATABASE, STOREOS_CAPACITY_DB_HOST,
//  STOREOS_CAPACITY_DB_PORT, STOREOS_CAPACITY_DB_USER,
//  STOREOS_CAPACITY_OWNER_PASSWORD_FILE, STOREOS_DB_USER,
//  STOREOS_DB_PASSWORD_FILE, STOREOS_CAPACITY_API_PORT,
//  STOREOS_CAPACITY_PROFILE, STOREOS_CAPACITY_EMPLOYEES,
//  STOREOS_CAPACITY_WORKERS, STOREOS_CAPACITY_TASKS_PER_EMPLOYEE,
//  STOREOS_CAPACITY_READ_ITERATIONS, STOREOS_CAPACITY_ABORT_AFTER,
//  STOREOS_CAPACITY_INJECT_INTEGRITY, STOREOS_CAPACITY_RESULT.
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
import 'package:storeos_server/src/platform/platform_database.dart';

const _schema = 'storeos_platform';
const _acceptedNumber = '1.5';
const _acceptedNumberScaled = 1500;
const _stepsPerTask = 2;
const _commandsPerTask = 4;
const _finalTaskVersion = _stepsPerTask + 3;
const _sampleInterval = Duration(milliseconds: 200);
const _requestTimeout = Duration(seconds: 30);
final _databasePattern = RegExp(r'^storeos_capacity_[a-f0-9]{16}$');
final _rolePattern = RegExp(r'^[a-z_][a-z0-9_]{0,62}$');
const _connectionSettings = ConnectionSettings(
  sslMode: SslMode.disable,
  timeZone: 'UTC',
  connectTimeout: Duration(seconds: 15),
);

/// Declared workload contract. Validated so no accidental run is unbounded.
class CapacityProfile {
  CapacityProfile({
    required this.name,
    required this.employees,
    required this.workers,
    required this.tasksPerEmployee,
    required this.readIterations,
  }) {
    if (employees < 1 || employees > 16) {
      throw ArgumentError.value(employees, 'employees', 'must be 1 to 16');
    }
    if (workers != employees) {
      throw ArgumentError.value(workers, 'workers', 'must equal employees');
    }
    if (tasksPerEmployee < 1 || tasksPerEmployee > 10) {
      throw ArgumentError.value(
        tasksPerEmployee,
        'tasksPerEmployee',
        'must be 1 to 10',
      );
    }
    if (readIterations < 1 || readIterations > 50) {
      throw ArgumentError.value(
        readIterations,
        'readIterations',
        'must be 1 to 50',
      );
    }
  }

  final String name;
  final int employees;
  final int workers;
  final int tasksPerEmployee;
  final int readIterations;

  int get taskCount => employees * tasksPerEmployee;

  Map<String, dynamic> toJson() => {
    'name': name,
    'employees': employees,
    'workers': workers,
    'tasksPerEmployee': tasksPerEmployee,
    'readIterations': readIterations,
    'stepsPerTask': _stepsPerTask,
    'commandsPerTask': _commandsPerTask,
    'acceptedNumber': _acceptedNumber,
  };
}

final CapacityProfile smokeCapacityProfile = CapacityProfile(
  name: 'smoke',
  employees: 2,
  workers: 2,
  tasksPerEmployee: 2,
  readIterations: 2,
);

final CapacityProfile fullCapacityProfile = CapacityProfile(
  name: 'full',
  employees: 8,
  workers: 8,
  tasksPerEmployee: 3,
  readIterations: 5,
);

enum CapacityAbortPhase { none, prepare, read, write }

/// Fully resolved harness configuration; credentials stay in memory only.
class CapacityHarnessConfig {
  CapacityHarnessConfig({
    required this.profile,
    required this.databaseHost,
    required this.databasePort,
    required this.databaseName,
    required this.ownerUser,
    required this.ownerPassword,
    required this.runtimeUser,
    required this.runtimePassword,
    required this.apiPort,
    this.abortAfter = CapacityAbortPhase.none,
    this.injectIntegrityMismatch = false,
  }) {
    if (!_databasePattern.hasMatch(databaseName)) {
      throw ArgumentError.value(
        databaseName,
        'databaseName',
        'must match storeos_capacity_<16 hex>',
      );
    }
    if (!{'127.0.0.1', 'localhost', '::1'}.contains(databaseHost)) {
      throw ArgumentError.value(
        databaseHost,
        'databaseHost',
        'must be loopback',
      );
    }
    if (databasePort < 1 || databasePort > 65535) {
      throw ArgumentError.value(databasePort, 'databasePort', 'invalid port');
    }
    if (apiPort < 0 || apiPort > 65535) {
      throw ArgumentError.value(apiPort, 'apiPort', 'invalid port');
    }
    if (!_rolePattern.hasMatch(ownerUser)) {
      throw ArgumentError.value(ownerUser, 'ownerUser', 'invalid role name');
    }
    if (!_rolePattern.hasMatch(runtimeUser)) {
      throw ArgumentError.value(
        runtimeUser,
        'runtimeUser',
        'invalid role name',
      );
    }
    if (ownerPassword.isEmpty || runtimePassword.isEmpty) {
      throw ArgumentError('Database passwords must not be empty.');
    }
  }

  factory CapacityHarnessConfig.fromEnvironment(Map<String, String> env) {
    final profileName = env['STOREOS_CAPACITY_PROFILE'] ?? 'smoke';
    final base = switch (profileName) {
      'smoke' => smokeCapacityProfile,
      'full' => fullCapacityProfile,
      _ => throw StateError('STOREOS_CAPACITY_PROFILE is invalid.'),
    };
    final employees = _environmentInt(
      env,
      'STOREOS_CAPACITY_EMPLOYEES',
      base.employees,
    );
    final workers = _environmentInt(
      env,
      'STOREOS_CAPACITY_WORKERS',
      base.workers,
    );
    final tasks = _environmentInt(
      env,
      'STOREOS_CAPACITY_TASKS_PER_EMPLOYEE',
      base.tasksPerEmployee,
    );
    final reads = _environmentInt(
      env,
      'STOREOS_CAPACITY_READ_ITERATIONS',
      base.readIterations,
    );
    final abortName = env['STOREOS_CAPACITY_ABORT_AFTER'] ?? 'none';
    final abortAfter = CapacityAbortPhase.values.firstWhere(
      (phase) => phase.name == abortName,
      orElse: () =>
          throw StateError('STOREOS_CAPACITY_ABORT_AFTER is invalid.'),
    );
    return CapacityHarnessConfig(
      profile: CapacityProfile(
        name: profileName,
        employees: employees,
        workers: workers,
        tasksPerEmployee: tasks,
        readIterations: reads,
      ),
      databaseHost: env['STOREOS_CAPACITY_DB_HOST'] ?? '127.0.0.1',
      databasePort: _environmentInt(env, 'STOREOS_CAPACITY_DB_PORT', 5432),
      databaseName: _required(env, 'STOREOS_CAPACITY_DATABASE'),
      ownerUser: _required(env, 'STOREOS_CAPACITY_DB_USER'),
      ownerPassword: _secretFile(env, 'STOREOS_CAPACITY_OWNER_PASSWORD_FILE'),
      runtimeUser: _required(env, 'STOREOS_DB_USER'),
      runtimePassword: _secretFile(env, 'STOREOS_DB_PASSWORD_FILE'),
      apiPort: _environmentInt(env, 'STOREOS_CAPACITY_API_PORT', 0),
      abortAfter: abortAfter,
      injectIntegrityMismatch:
          (env['STOREOS_CAPACITY_INJECT_INTEGRITY'] ?? '0') == '1',
    );
  }

  final CapacityProfile profile;
  final String databaseHost;
  final int databasePort;
  final String databaseName;
  final String ownerUser;
  final String ownerPassword;
  final String runtimeUser;
  final String runtimePassword;
  final int apiPort;
  final CapacityAbortPhase abortAfter;
  final bool injectIntegrityMismatch;

  Endpoint get ownerEndpoint => Endpoint(
    host: databaseHost,
    port: databasePort,
    database: databaseName,
    username: ownerUser,
    password: ownerPassword,
  );

  Endpoint get runtimeEndpoint => Endpoint(
    host: databaseHost,
    port: databasePort,
    database: databaseName,
    username: runtimeUser,
    password: runtimePassword,
  );
}

/// Declared counts derived from the workload contract, never from observations.
class CapacityExpectations {
  CapacityExpectations(this.profile);

  final CapacityProfile profile;

  Map<String, int> metrics() {
    final tasks = profile.taskCount;
    return <String, int>{
      'shifts': profile.employees,
      'task_templates': profile.tasksPerEmployee,
      'task_template_revisions': profile.tasksPerEmployee,
      'task_instances': tasks,
      'task_instances_completed': tasks,
      'task_step_results': tasks * _stepsPerTask,
      'task_step_results_numeric_linked': tasks,
      'task_step_results_confirmation_linked': tasks,
      'task_numeric_attempts': tasks,
      'task_numeric_attempts_in_range': tasks,
      'task_execution_commands': tasks * _commandsPerTask,
      'task_instances_with_four_commands': tasks,
      'task_execution_commands_orphaned': 0,
      'audit_tasks_instance_started': tasks,
      'audit_tasks_step_number_recorded': tasks,
      'audit_tasks_step_confirmed': tasks * _stepsPerTask,
      'audit_tasks_instance_completed': tasks,
      'audit_read': profile.readIterations,
    };
  }
}

/// Independent integrity verdict; a mismatch is a correctness failure.
class CapacityIntegrityReport {
  CapacityIntegrityReport({
    required this.passed,
    required this.detail,
    required this.expected,
    required this.observed,
  });

  final bool passed;
  final String? detail;
  final Map<String, int> expected;
  final Map<String, int> observed;

  Map<String, dynamic> toJson() => {
    'status': passed ? 'pass' : 'fail',
    'detail': detail,
    'expected': expected,
    'observed': observed,
  };
}

/// Aggregate observation of one scenario. Latency samples are successful
/// requests only; failures are counted by class and excluded from percentiles.
class CapacityMetrics {
  CapacityMetrics(this.name);

  final String name;
  final Map<String, _RequestTypeMetrics> _types =
      <String, _RequestTypeMetrics>{};
  final Stopwatch _stopwatch = Stopwatch();
  Duration elapsed = Duration.zero;
  int requests = 0;
  int successes = 0;
  int errors = 0;

  void start() {
    _stopwatch
      ..reset()
      ..start();
  }

  void finish() {
    _stopwatch.stop();
    elapsed = _stopwatch.elapsed;
  }

  void recordSuccess(String type, Duration duration) {
    requests++;
    successes++;
    (_types[type] ??= _RequestTypeMetrics()).recordSuccess(duration);
  }

  void recordError(String type, String errorClass) {
    requests++;
    errors++;
    (_types[type] ??= _RequestTypeMetrics()).recordError(errorClass);
  }

  double? get throughputPerSecond {
    final micros = elapsed.inMicroseconds;
    if (micros <= 0) return null;
    return _round3(successes * 1000000 / micros);
  }

  List<int> get _successMicros => [
    for (final type in _types.values) ...type.successMicros,
  ];

  Map<String, dynamic> toJson() {
    final micros = _successMicros;
    return {
      'requests': requests,
      'successes': successes,
      'errors': errors,
      'durationMs': elapsed.inMilliseconds,
      'throughputPerSecond': throughputPerSecond,
      'p50Ms': capacityPercentileMs(micros, 50),
      'p95Ms': capacityPercentileMs(micros, 95),
      'byRequestType': {
        for (final entry in _types.entries) entry.key: entry.value.toJson(),
      },
    };
  }
}

class _RequestTypeMetrics {
  final List<int> successMicros = <int>[];
  final Map<String, int> errorClasses = <String, int>{};

  void recordSuccess(Duration duration) =>
      successMicros.add(duration.inMicroseconds);

  void recordError(String errorClass) {
    errorClasses.update(errorClass, (value) => value + 1, ifAbsent: () => 1);
  }

  Map<String, dynamic> toJson() => {
    'requests': successMicros.length + _errorCount,
    'successes': successMicros.length,
    'errors': _errorCount,
    'p50Ms': capacityPercentileMs(successMicros, 50),
    'p95Ms': capacityPercentileMs(successMicros, 95),
    'errorClasses': errorClasses,
  };

  int get _errorCount =>
      errorClasses.values.fold(0, (total, value) => total + value);
}

/// Nearest-rank percentile in milliseconds over ascending sorted samples:
/// `rank = ceil(percent/100 * n)` clamped to `[1, n]`; `null` for no sample.
double? capacityPercentileMs(List<int> micros, int percent) {
  if (micros.isEmpty) return null;
  final sorted = List<int>.of(micros)..sort();
  var rank = (percent * sorted.length + 99) ~/ 100;
  if (rank < 1) rank = 1;
  if (rank > sorted.length) rank = sorted.length;
  return sorted[rank - 1] / 1000;
}

double? _round3(double? value) =>
    value == null ? null : (value * 1000).roundToDouble() / 1000;

/// Bounded observational contention sampler. It never changes privileges and
/// never terminates sessions; only safely observable fields are aggregated.
class CapacityContentionSampler {
  CapacityContentionSampler(this._connection, this._runtimeUser);

  final Connection _connection;
  final String _runtimeUser;
  final Set<String> waitingLockModes = <String>{};
  bool runtimeStateVisible = false;
  int samples = 0;
  int samplingErrors = 0;
  int maxTotalBackends = 0;
  int maxRuntimeBackends = 0;
  int maxUngrantedLocks = 0;
  bool _running = false;
  Future<void>? _loop;

  void start() {
    if (_running) return;
    _running = true;
    _loop = _run();
  }

  Future<void> stop() async {
    _running = false;
    final loop = _loop;
    _loop = null;
    await loop;
  }

  Future<void> _run() async {
    while (_running) {
      await _sample();
      if (!_running) break;
      await Future<void>.delayed(_sampleInterval);
    }
  }

  Future<void> _sample() async {
    try {
      final activity = await _connection.execute(
        Sql.named(
          'SELECT count(*)::int AS total, '
          'count(*) FILTER (WHERE usename = @runtimeUser)::int AS runtime, '
          'count(*) FILTER (WHERE usename = @runtimeUser '
          'AND state IS NOT NULL)::int AS runtime_states '
          'FROM pg_stat_activity WHERE datname = current_database()',
        ),
        parameters: {'runtimeUser': _runtimeUser},
      );
      final activityRow = activity.single.toColumnMap();
      final total = activityRow['total']! as int;
      final runtime = activityRow['runtime']! as int;
      final runtimeStates = activityRow['runtime_states']! as int;
      if (total > maxTotalBackends) maxTotalBackends = total;
      if (runtime > maxRuntimeBackends) maxRuntimeBackends = runtime;
      if (runtimeStates > 0) runtimeStateVisible = true;

      final locks = await _connection.execute(
        'SELECT l.mode, l.granted, count(*)::int AS lock_count '
        'FROM pg_locks l JOIN pg_stat_activity a ON a.pid = l.pid '
        'WHERE a.datname = current_database() GROUP BY l.mode, l.granted',
      );
      var ungranted = 0;
      for (final lock in locks) {
        final lockRow = lock.toColumnMap();
        if (lockRow['granted'] == false) {
          ungranted += lockRow['lock_count']! as int;
          waitingLockModes.add(lockRow['mode']! as String);
        }
      }
      if (ungranted > maxUngrantedLocks) maxUngrantedLocks = ungranted;
      samples++;
    } on Object {
      samplingErrors++;
    }
  }

  Map<String, dynamic> toJson() {
    final modes = waitingLockModes.toList()..sort();
    return {
      'samples': samples,
      'samplingErrors': samplingErrors,
      'maxTotalBackends': maxTotalBackends,
      'maxRuntimeBackends': maxRuntimeBackends,
      'maxUngrantedLocks': maxUngrantedLocks,
      'waitingLockModes': modes,
      'runtimeStateVisible': runtimeStateVisible,
      'note':
          'Observational samples only; PostgreSQL may hide state/wait fields '
          'for the owner role and no query text is retained.',
    };
  }
}

/// Sanitized measurement result. Contains aggregate numbers and environment
/// metadata only: no identifiers, credentials, URLs, rows or SQL text.
class CapacityMeasurement {
  CapacityMeasurement({
    required this.profile,
    required this.read,
    required this.write,
    required this.contention,
    required this.integrity,
    required this.environment,
  });

  final CapacityProfile profile;
  final Map<String, dynamic> read;
  final Map<String, dynamic> write;
  final Map<String, dynamic> contention;
  final CapacityIntegrityReport integrity;
  final Map<String, dynamic> environment;

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'profile': profile.toJson(),
    'environment': environment,
    'read': read,
    'write': write,
    'contention': contention,
    'integrity': integrity.toJson(),
  };
}

Future<CapacityMeasurement> runCapacityMeasurement(
  CapacityHarnessConfig config,
) async {
  final profile = config.profile;
  final ownerEndpoint = config.ownerEndpoint;
  final runtimeEndpoint = config.runtimeEndpoint;
  final companyId = newUuid();
  final locationId = newUuid();
  final adminUser = 'capacity_admin';
  final adminPassword = _randomSecret();
  final runKey = config.databaseName
      .substring('storeos_capacity_'.length)
      .substring(0, 8);

  Connection? owner;
  Connection? samplerConnection;
  Pool<void>? pool;
  HttpServer? server;
  HttpClient? client;
  CapacityContentionSampler? sampler;
  try {
    owner = await Connection.open(ownerEndpoint, settings: _connectionSettings);
    await _requireRestrictedRole(owner, config.runtimeUser);
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: Directory('migrations'),
      schemaName: _schema,
      runtimeDatabaseUser: config.runtimeUser,
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

    // The runtime pool matches the production pool configuration.
    pool = Pool<void>.withEndpoints([runtimeEndpoint], settings: _poolSettings);
    final store = PostgresAuthStore(pool, schemaName: _schema);
    final auth = await AuthService.create(
      store: store,
      companyId: companyId,
      locationId: locationId,
      sessionTtl: const Duration(minutes: 30),
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
            host: ownerEndpoint.host,
            port: ownerEndpoint.port,
            name: ownerEndpoint.database,
            user: config.runtimeUser,
            password: config.runtimePassword,
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
      config.apiPort,
    );
    client = HttpClient();
    final api = _CapacityApi(client, 'http://127.0.0.1:${server.port}');
    final ready = await api.call('GET', '/ready');
    if (!ready.isSuccess) {
      throw StateError('The capacity API is not ready (${ready.errorClass}).');
    }

    final journey = await _seed(
      api,
      profile: profile,
      companyId: companyId,
      locationId: locationId,
      adminUser: adminUser,
      adminPassword: adminPassword,
      runKey: runKey,
    );
    _abortAfter(config, CapacityAbortPhase.prepare);

    samplerConnection = await Connection.open(
      ownerEndpoint,
      settings: _connectionSettings,
    );
    sampler = CapacityContentionSampler(samplerConnection, config.runtimeUser)
      ..start();

    final readMetrics = CapacityMetrics('read');
    final writeMetrics = CapacityMetrics('write');
    await _runReadScenario(api, journey, readMetrics, profile);
    _abortAfter(config, CapacityAbortPhase.read);
    await _runWriteScenario(api, journey, writeMetrics);
    _abortAfter(config, CapacityAbortPhase.write);

    await sampler.stop();
    final contention = sampler.toJson();
    sampler = null;
    await samplerConnection.close();
    samplerConnection = null;

    owner = await Connection.open(ownerEndpoint, settings: _connectionSettings);
    final integrity = await verifyCapacityIntegrity(
      owner,
      profile: profile,
      injectIntegrityMismatch: config.injectIntegrityMismatch,
    );
    final postgresVersion = await _serverVersion(owner);
    await owner.close();
    owner = null;

    return CapacityMeasurement(
      profile: profile,
      read: readMetrics.toJson(),
      write: writeMetrics.toJson(),
      contention: contention,
      integrity: integrity,
      environment: {
        'os': Platform.operatingSystem,
        'osVersion': Platform.operatingSystemVersion,
        'dartVersion': Platform.version,
        'postgresVersion': postgresVersion,
        'logicalProcessors': Platform.numberOfProcessors,
      },
    );
  } finally {
    try {
      await sampler?.stop();
    } on Object {
      // Best-effort sampler shutdown; the owning connection is closed below.
    }
    client?.close(force: true);
    await server?.close(force: true);
    await pool?.close();
    await samplerConnection?.close(force: true);
    await owner?.close(force: true);
  }
}

/// Compares the declared workload contract with owner-side database outcomes.
/// Corrupted expectations (injection) are detected against the real data.
Future<CapacityIntegrityReport> verifyCapacityIntegrity(
  Connection owner, {
  required CapacityProfile profile,
  bool injectIntegrityMismatch = false,
}) async {
  final expected = CapacityExpectations(profile).metrics();
  if (injectIntegrityMismatch) {
    expected['task_instances'] = (expected['task_instances'] ?? 0) + 1;
  }
  final observed = await _observeCounts(owner);
  final mismatches = <String>[
    for (final entry in expected.entries)
      if (observed[entry.key] != entry.value)
        '${entry.key}: observed ${observed[entry.key]}, expected ${entry.value}',
  ];
  return CapacityIntegrityReport(
    passed: mismatches.isEmpty,
    detail: mismatches.isEmpty ? null : mismatches.join('; '),
    expected: expected,
    observed: observed,
  );
}

Future<Map<String, int>> _observeCounts(Connection owner) async {
  Future<int> scalar(String sql) async =>
      (await owner.execute(sql)).single.single! as int;

  return <String, int>{
    'shifts': await scalar('SELECT count(*)::int FROM "$_schema".shifts'),
    'task_templates': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_templates',
    ),
    'task_template_revisions': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_template_revisions',
    ),
    'task_instances': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_instances',
    ),
    'task_instances_completed': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_instances '
      "WHERE status = 'completed' AND version = $_finalTaskVersion "
      'AND started_at IS NOT NULL AND completed_at IS NOT NULL '
      'AND completed_at >= started_at',
    ),
    'task_step_results': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_step_results',
    ),
    'task_step_results_numeric_linked': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_step_results '
      'WHERE position = 0 AND numeric_attempt_id IS NOT NULL',
    ),
    'task_step_results_confirmation_linked': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_step_results '
      'WHERE position = 1 AND numeric_attempt_id IS NULL',
    ),
    'task_numeric_attempts': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_numeric_attempts',
    ),
    'task_numeric_attempts_in_range': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_numeric_attempts '
      'WHERE in_range AND value_scaled = $_acceptedNumberScaled '
      'AND accepted_version = 3',
    ),
    'task_execution_commands': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_execution_commands',
    ),
    'task_instances_with_four_commands': await scalar(
      'SELECT count(*)::int FROM ('
      'SELECT instance_id FROM "$_schema".task_execution_commands '
      'GROUP BY instance_id '
      'HAVING count(*) = $_commandsPerTask) AS grouped',
    ),
    'task_execution_commands_orphaned': await scalar(
      'SELECT count(*)::int FROM "$_schema".task_execution_commands c '
      'WHERE NOT EXISTS ('
      'SELECT 1 FROM "$_schema".task_instances t WHERE t.id = c.instance_id)',
    ),
    'audit_tasks_instance_started': await scalar(
      'SELECT count(*)::int FROM "$_schema".audit_entries '
      "WHERE action = 'tasks.instance.started'",
    ),
    'audit_tasks_step_number_recorded': await scalar(
      'SELECT count(*)::int FROM "$_schema".audit_entries '
      "WHERE action = 'tasks.step.number_recorded'",
    ),
    'audit_tasks_step_confirmed': await scalar(
      'SELECT count(*)::int FROM "$_schema".audit_entries '
      "WHERE action = 'tasks.step.confirmed'",
    ),
    'audit_tasks_instance_completed': await scalar(
      'SELECT count(*)::int FROM "$_schema".audit_entries '
      "WHERE action = 'tasks.instance.completed'",
    ),
    'audit_read': await scalar(
      'SELECT count(*)::int FROM "$_schema".audit_entries '
      "WHERE action = 'audit.read'",
    ),
  };
}

Future<void> _runReadScenario(
  _CapacityApi api,
  _SeededJourney journey,
  CapacityMetrics metrics,
  CapacityProfile profile,
) async {
  metrics.start();
  final workers = <Future<void>>[
    for (final worker in journey.workers)
      (() async {
        for (
          var iteration = 0;
          iteration < profile.readIterations;
          iteration++
        ) {
          await _readRequest(
            api,
            metrics,
            type: 'employee-home-shifts',
            path: '/api/v1/platform/employee-home/shifts',
            token: worker.token,
          );
          await _readRequest(
            api,
            metrics,
            type: 'employee-home-running-tasks',
            path: '/api/v1/platform/employee-home/running-tasks',
            token: worker.token,
          );
        }
      })(),
    (() async {
      for (var iteration = 0; iteration < profile.readIterations; iteration++) {
        await _readRequest(
          api,
          metrics,
          type: 'admin-shifts',
          path: '/api/v1/platform/shifts',
          token: journey.adminToken,
        );
        await _readRequest(
          api,
          metrics,
          type: 'admin-blocked-tasks',
          path: '/api/v1/platform/blocked-tasks',
          token: journey.adminToken,
        );
        await _readRequest(
          api,
          metrics,
          type: 'admin-audit',
          path: '/api/v1/platform/audit',
          token: journey.adminToken,
        );
      }
    })(),
  ];
  await Future.wait(workers);
  metrics.finish();
}

Future<void> _readRequest(
  _CapacityApi api,
  CapacityMetrics metrics, {
  required String type,
  required String path,
  required String token,
}) async {
  final result = await api.call('GET', path, token: token);
  if (!result.isSuccess) {
    metrics.recordError(type, result.errorClass);
    throw StateError('Capacity read $type failed (${result.errorClass}).');
  }
  metrics.recordSuccess(type, result.duration);
}

Future<void> _runWriteScenario(
  _CapacityApi api,
  _SeededJourney journey,
  CapacityMetrics metrics,
) async {
  metrics.start();
  final workers = <Future<void>>[];
  for (final worker in journey.workers) {
    workers.add(_runWorkerLifecycle(api, worker, metrics));
  }
  await Future.wait(workers);
  metrics.finish();
}

Future<void> _runWorkerLifecycle(
  _CapacityApi api,
  _SeededWorker worker,
  CapacityMetrics metrics,
) async {
  for (final task in worker.tasks) {
    await _executeCommand(
      api,
      metrics,
      type: 'task-start',
      token: worker.token,
      shiftId: worker.shiftId,
      taskId: task.taskId,
      suffix: 'start',
      body: {'operationId': newUuid(), 'expectedVersion': 1},
      expectedVersion: 2,
      expectedStatus: 'in_progress',
    );
    await _executeCommand(
      api,
      metrics,
      type: 'task-record-number',
      token: worker.token,
      shiftId: worker.shiftId,
      taskId: task.taskId,
      suffix: 'steps/${task.numberStepId}/record-number',
      body: {
        'operationId': newUuid(),
        'expectedVersion': 2,
        'value': _acceptedNumber,
      },
      expectedVersion: 3,
      expectedStatus: 'in_progress',
    );
    await _executeCommand(
      api,
      metrics,
      type: 'task-confirm',
      token: worker.token,
      shiftId: worker.shiftId,
      taskId: task.taskId,
      suffix: 'steps/${task.confirmationStepId}/confirm',
      body: {'operationId': newUuid(), 'expectedVersion': 3},
      expectedVersion: 4,
      expectedStatus: 'in_progress',
    );
    await _executeCommand(
      api,
      metrics,
      type: 'task-complete',
      token: worker.token,
      shiftId: worker.shiftId,
      taskId: task.taskId,
      suffix: 'complete',
      body: {'operationId': newUuid(), 'expectedVersion': 4},
      expectedVersion: _finalTaskVersion,
      expectedStatus: 'completed',
    );
  }
}

Future<void> _executeCommand(
  _CapacityApi api,
  CapacityMetrics metrics, {
  required String type,
  required String token,
  required String shiftId,
  required String taskId,
  required String suffix,
  required Map<String, dynamic> body,
  required int expectedVersion,
  required String expectedStatus,
}) async {
  final path =
      '/api/v1/platform/employee-home/shifts/$shiftId/tasks/$taskId/$suffix';
  final result = await api.call('POST', path, token: token, body: body);
  if (!result.isSuccess) {
    metrics.recordError(type, result.errorClass);
    throw StateError('Capacity write $type failed (${result.errorClass}).');
  }
  final decoded = result.decoded! as Map<String, dynamic>;
  if (decoded['status'] != expectedStatus ||
      decoded['version'] != expectedVersion ||
      decoded['instanceId'] != taskId) {
    metrics.recordError(type, 'contract_mismatch');
    throw StateError('Capacity write $type reported an unexpected result.');
  }
  metrics.recordSuccess(type, result.duration);
}

Future<_SeededJourney> _seed(
  _CapacityApi api, {
  required CapacityProfile profile,
  required String companyId,
  required String locationId,
  required String adminUser,
  required String adminPassword,
  required String runKey,
}) async {
  const root = '/api/v1/platform';
  final adminLogin = await api.callStrict(
    'POST',
    '/api/v1/auth/login',
    body: {'username': adminUser, 'password': adminPassword},
  );
  final adminToken = adminLogin['token']! as String;
  await api.callStrict(
    'POST',
    '$root/organization/setup',
    token: adminToken,
    body: {
      'companyName': 'Capacity Company',
      'locationName': 'Capacity Location',
    },
  );

  final templates = <_Template>[];
  for (var index = 0; index < profile.tasksPerEmployee; index++) {
    templates.add(await _publishTemplate(api, adminToken, locationId, index));
  }

  final workers = <_SeededWorker>[];
  for (var index = 0; index < profile.employees; index++) {
    final employeeId = newUuid();
    final accountId = newUuid();
    final username = 'cap_${runKey}_e$index';
    final password = _randomSecret();
    final employee = await api.callStrict(
      'POST',
      '$root/employees',
      token: adminToken,
      expectedStatuses: const {201},
      body: {
        'id': employeeId,
        'displayName': 'Capacity Employee ${index + 1}',
        'locationId': locationId,
      },
    );
    final account = await api.callStrict(
      'POST',
      '$root/users',
      token: adminToken,
      expectedStatuses: const {201},
      body: {
        'id': accountId,
        'username': username,
        'password': password,
        'locationId': locationId,
        'role': 'employee',
      },
    );
    await api.callStrict(
      'POST',
      '$root/employees/$employeeId/account-link',
      token: adminToken,
      expectedStatuses: const {201},
      body: {
        'id': newUuid(),
        'accountId': accountId,
        'expectedEmployeeVersion': employee['version'],
        'expectedAccountVersion': account['version'],
      },
    );

    final shiftId = newUuid();
    final startsAt = DateTime.parse(
      employee['assignedFrom']! as String,
    ).toUtc();
    final endsAt = DateTime.now().toUtc().add(const Duration(hours: 4));
    await api.callStrict(
      'POST',
      '$root/shifts',
      token: adminToken,
      expectedStatuses: const {201},
      body: {
        'id': shiftId,
        'locationId': locationId,
        'employeeId': employeeId,
        'startsAt': startsAt.toIso8601String(),
        'endsAt': endsAt.toIso8601String(),
        'selections': [
          for (final template in templates)
            {
              'templateId': template.templateId,
              'revisionId': template.revisionId,
            },
        ],
      },
    );
    final published = await api.callStrict(
      'POST',
      '$root/shifts/$shiftId/publish',
      token: adminToken,
      body: {'expectedVersion': 1},
    );
    final tasks = (published['tasks']! as List).cast<Map<String, dynamic>>();
    if (tasks.length != templates.length) {
      throw StateError('Published task count differs from the profile.');
    }
    final taskByTemplate = <String, String>{
      for (final task in tasks)
        task['templateId']! as String: task['id']! as String,
    };
    final seededTasks = <_SeededTask>[];
    for (final template in templates) {
      final taskId = taskByTemplate[template.templateId];
      if (taskId == null) {
        throw StateError('Published tasks do not match the templates.');
      }
      seededTasks.add(
        _SeededTask(
          taskId: taskId,
          numberStepId: template.numberStepId,
          confirmationStepId: template.confirmationStepId,
        ),
      );
    }

    final login = await api.callStrict(
      'POST',
      '/api/v1/auth/login',
      body: {'username': username, 'password': password},
    );
    workers.add(
      _SeededWorker(
        token: login['token']! as String,
        shiftId: shiftId,
        tasks: seededTasks,
      ),
    );
  }
  return _SeededJourney(adminToken: adminToken, workers: workers);
}

Future<_Template> _publishTemplate(
  _CapacityApi api,
  String token,
  String locationId,
  int index,
) async {
  final templateId = newUuid();
  final revisionId = newUuid();
  final numberStepId = newUuid();
  final confirmationStepId = newUuid();
  await api.callStrict(
    'POST',
    '/api/v1/platform/task-templates',
    token: token,
    expectedStatuses: const {201},
    body: {
      'id': templateId,
      'revisionId': revisionId,
      'locationId': locationId,
      'content': {
        'schemaVersion': 2,
        'title': 'Capacity task ${index + 1}',
        'steps': [
          {
            'id': numberStepId,
            'type': 'number',
            'instruction': 'Record measurement',
            'unit': 'C',
            'minimum': '-2.125',
            'maximum': '4.5',
          },
          {
            'id': confirmationStepId,
            'type': 'confirmation',
            'instruction': 'Confirm completion',
          },
        ],
      },
    },
  );
  await api.callStrict(
    'POST',
    '/api/v1/platform/task-templates/$templateId/revisions/$revisionId/publish',
    token: token,
    body: {'expectedVersion': 1},
  );
  return _Template(
    templateId: templateId,
    revisionId: revisionId,
    numberStepId: numberStepId,
    confirmationStepId: confirmationStepId,
  );
}

void _abortAfter(CapacityHarnessConfig config, CapacityAbortPhase phase) {
  if (config.abortAfter == phase) {
    throw StateError('Injected abort after ${phase.name}.');
  }
}

Future<void> main() async {
  try {
    final env = Platform.environment;
    final config = CapacityHarnessConfig.fromEnvironment(env);
    final measurement = await runCapacityMeasurement(config);
    final resultFile = File(_required(env, 'STOREOS_CAPACITY_RESULT'));
    if (!resultFile.isAbsolute) {
      throw StateError('STOREOS_CAPACITY_RESULT must be absolute.');
    }
    await _writeJsonAtomic(resultFile, measurement.toJson());
    stdout.writeln('capacity_fixture_measured');
    if (!measurement.integrity.passed) {
      stderr.writeln('capacity_fixture_integrity_failed');
      exitCode = 1;
    }
  } on Object catch (error) {
    // StateError messages are crafted here and contain no secrets; any other
    // error is reduced to its runtime type.
    stderr.writeln(
      'Capacity fixture failed: '
      '${error is StateError ? error : error.runtimeType}.',
    );
    stderr.writeln('capacity_fixture_failed');
    exitCode = 1;
  }
}

class _Template {
  const _Template({
    required this.templateId,
    required this.revisionId,
    required this.numberStepId,
    required this.confirmationStepId,
  });

  final String templateId;
  final String revisionId;
  final String numberStepId;
  final String confirmationStepId;
}

class _SeededTask {
  const _SeededTask({
    required this.taskId,
    required this.numberStepId,
    required this.confirmationStepId,
  });

  final String taskId;
  final String numberStepId;
  final String confirmationStepId;
}

class _SeededWorker {
  const _SeededWorker({
    required this.token,
    required this.shiftId,
    required this.tasks,
  });

  final String token;
  final String shiftId;
  final List<_SeededTask> tasks;
}

class _SeededJourney {
  const _SeededJourney({required this.adminToken, required this.workers});

  final String adminToken;
  final List<_SeededWorker> workers;
}

class _ApiCallResult {
  const _ApiCallResult({
    required this.statusCode,
    required this.duration,
    required this.decoded,
    required this.expected,
    required this.malformed,
    required this.transportError,
  });

  final int? statusCode;
  final Duration duration;
  final Object? decoded;
  final bool expected;
  final bool malformed;
  final String? transportError;

  bool get isSuccess =>
      transportError == null && expected && !malformed && decoded is Map;

  String get errorClass {
    final transport = transportError;
    if (transport != null) return 'transport_$transport';
    if (malformed) return 'malformed_response';
    final status = statusCode;
    return status == null ? 'no_response' : 'http_$status';
  }
}

class _CapacityApi {
  _CapacityApi(this.client, this.baseUrl);

  final HttpClient client;
  final String baseUrl;

  Future<Map<String, dynamic>> callStrict(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    Set<int> expectedStatuses = const {200},
  }) async {
    final result = await call(
      method,
      path,
      body: body,
      token: token,
      expectedStatuses: expectedStatuses,
    );
    if (!result.isSuccess) {
      throw StateError(
        'Capacity setup $method $path failed '
        '(${result.errorClass}${_errorCode(result)}).',
      );
    }
    return result.decoded! as Map<String, dynamic>;
  }

  Future<_ApiCallResult> call(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? token,
    Set<int> expectedStatuses = const {200},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final request = await client
          .openUrl(method, Uri.parse('$baseUrl$path'))
          .timeout(_requestTimeout);
      if (token != null) request.headers.set('authorization', 'Bearer $token');
      if (body != null) {
        request.headers.contentType = ContentType.json;
        final bytes = utf8.encode(jsonEncode(body));
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      final response = await request.close().timeout(_requestTimeout);
      final text = await utf8.decodeStream(response).timeout(_requestTimeout);
      stopwatch.stop();
      Object? decoded;
      var malformed = false;
      if (text.isNotEmpty) {
        try {
          decoded = jsonDecode(text);
        } on FormatException {
          malformed = true;
        }
      }
      final expected = expectedStatuses.contains(response.statusCode);
      if (expected && !malformed && decoded is! Map) malformed = true;
      return _ApiCallResult(
        statusCode: response.statusCode,
        duration: stopwatch.elapsed,
        decoded: decoded,
        expected: expected,
        malformed: malformed,
        transportError: null,
      );
    } on Object catch (error) {
      stopwatch.stop();
      return _ApiCallResult(
        statusCode: null,
        duration: stopwatch.elapsed,
        decoded: null,
        expected: false,
        malformed: false,
        transportError: error.runtimeType.toString(),
      );
    }
  }

  String _errorCode(_ApiCallResult result) {
    final decoded = result.decoded;
    if (decoded is Map && decoded['code'] is String) {
      return ', ${decoded['code']}';
    }
    return '';
  }
}

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

Future<String> _serverVersion(Connection owner) async {
  final result = await owner.execute('SHOW server_version');
  return result.single.single! as String;
}

PoolSettings get _poolSettings => const PoolSettings(
  sslMode: SslMode.disable,
  maxConnectionCount: 8,
  connectTimeout: Duration(seconds: 3),
  queryTimeout: Duration(seconds: 15),
  applicationName: 'storeos_capacity',
  timeZone: 'UTC',
);

String _required(Map<String, String> env, String name) {
  final value = env[name];
  if (value == null || value.isEmpty) throw StateError('$name is required.');
  return value;
}

int _environmentInt(Map<String, String> env, String name, int fallback) {
  final raw = env[name];
  if (raw == null || raw.isEmpty) return fallback;
  final value = int.tryParse(raw);
  if (value == null) throw StateError('$name must be an integer.');
  return value;
}

String _secretFile(Map<String, String> env, String name) {
  final path = _required(env, name);
  final file = File(path);
  if (!file.existsSync()) throw StateError('$name is missing.');
  return file.readAsStringSync().trim();
}

String _randomSecret() {
  final random = Random.secure();
  return base64UrlEncode(
    List<int>.generate(32, (_) => random.nextInt(256)),
  ).replaceAll('=', '');
}

Future<void> _writeJsonAtomic(File file, Map<String, dynamic> values) async {
  await file.parent.create(recursive: true);
  final temporary = File('${file.path}.${newUuid()}.tmp');
  try {
    await temporary.writeAsString(jsonEncode(values));
    await temporary.rename(file.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}
