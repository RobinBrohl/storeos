import 'package:postgres/postgres.dart';

import '../platform/audit_repository.dart';

final _schemaPattern = RegExp(r'^[a-z][a-z0-9_]*$');

String quotedSchema(String schemaName) {
  if (!_schemaPattern.hasMatch(schemaName) || schemaName.length > 63) {
    throw ArgumentError.value(schemaName, 'schemaName', 'Invalid schema name.');
  }
  return '"$schemaName"';
}

class StoredAccount {
  const StoredAccount({
    required this.id,
    required this.username,
    required this.passwordHash,
    required this.companyId,
    required this.locationId,
    required this.isActive,
  });

  final String id;
  final String username;
  final String passwordHash;
  final String companyId;
  final String locationId;
  final bool isActive;
}

class SessionPrincipal {
  const SessionPrincipal({
    required this.id,
    required this.username,
    required this.companyId,
    required this.locationId,
    this.tokenHash,
  });

  final String id;
  final String username;
  final String companyId;
  final String locationId;
  final String? tokenHash;
}

class SessionCreationRejected implements Exception {
  const SessionCreationRejected();
}

abstract interface class AuthStore {
  Future<bool> isReady();
  Future<StoredAccount?> findAccount(String usernameKey);
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
    String? expectedPasswordHash,
    String? expectedCompanyId,
  });
  Future<SessionPrincipal?> findSession(String tokenHash);
  Future<bool> revokeSession(String tokenHash);
}

class PostgresAuthStore implements AuthStore {
  PostgresAuthStore(this.pool, {this.schemaName = 'storeos_platform'})
    : _schema = quotedSchema(schemaName);

  final Pool<void> pool;
  final String schemaName;
  final String _schema;

  @override
  Future<bool> isReady() async {
    try {
      await pool.execute(
        'SELECT 1 FROM $_schema.accounts LIMIT 0',
        timeout: const Duration(seconds: 2),
      );
      final migration = await pool.execute(
        'SELECT count(*)::int AS count FROM $_schema.schema_migrations '
        "WHERE version IN ('0001_platform_auth', "
        "'0002_platform_organization', '0003_platform_events_plugins', '"
        "0004_employee_identity_and_audit')",
        timeout: const Duration(seconds: 2),
      );
      return migration.single.toColumnMap()['count'] == 4;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StoredAccount?> findAccount(String usernameKey) async {
    final result = await pool.execute(
      Sql.named(
        'SELECT a.id::text AS id, a.username, a.password_hash, '
        'a.company_id::text AS company_id, '
        'a.location_id::text AS location_id, a.is_active '
        'FROM $_schema.accounts a '
        'JOIN $_schema.locations l ON l.id = a.location_id '
        'AND l.company_id = a.company_id '
        'WHERE username_key = @usernameKey',
      ),
      parameters: {'usernameKey': usernameKey},
    );
    if (result.isEmpty) return null;
    final row = result.first.toColumnMap();
    return StoredAccount(
      id: row['id']! as String,
      username: row['username']! as String,
      passwordHash: row['password_hash']! as String,
      companyId: row['company_id']! as String,
      locationId: row['location_id']! as String,
      isActive: row['is_active']! as bool,
    );
  }

  @override
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
    String? expectedPasswordHash,
    String? expectedCompanyId,
  }) async {
    if (expectedCompanyId == null || expectedPasswordHash == null) {
      throw ArgumentError('Expected account state is required.');
    }
    await pool.runTx((tx) async {
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
        parameters: {'key': 'storeos_platform:$schemaName:$expectedCompanyId'},
      );
      final current = await tx.execute(
        Sql.named(
          'SELECT location_id::text AS location_id FROM $_schema.accounts '
          'WHERE id = CAST(@accountId AS uuid) '
          'AND company_id = CAST(@companyId AS uuid) '
          'AND password_hash = @passwordHash AND is_active',
        ),
        parameters: {
          'accountId': accountId,
          'companyId': expectedCompanyId,
          'passwordHash': expectedPasswordHash,
        },
      );
      if (current.isEmpty) throw const SessionCreationRejected();
      final session = await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.auth_sessions '
          '(account_id, token_hash, expires_at) '
          'VALUES (CAST(@accountId AS uuid), @tokenHash, @expiresAt) '
          'RETURNING id::text AS id',
        ),
        parameters: {
          'accountId': accountId,
          'tokenHash': tokenHash,
          'expiresAt': expiresAt.toUtc(),
        },
      );
      await AuditRepository(_schema).append(
        tx,
        actorId: accountId,
        companyId: expectedCompanyId,
        locationId: current.single.toColumnMap()['location_id']! as String,
        action: 'auth.login',
        entityType: 'session',
        entityId: session.single.toColumnMap()['id']! as String,
        changes: const {},
      );
    });
  }

  @override
  Future<SessionPrincipal?> findSession(String tokenHash) async {
    final result = await pool.execute(
      Sql.named(
        'SELECT a.id::text AS id, a.username, s.token_hash, '
        'a.company_id::text AS company_id, '
        'a.location_id::text AS location_id '
        'FROM $_schema.auth_sessions s '
        'JOIN $_schema.accounts a ON a.id = s.account_id '
        'JOIN $_schema.locations l ON l.id = a.location_id '
        'AND l.company_id = a.company_id '
        'WHERE s.token_hash = @tokenHash AND s.revoked_at IS NULL '
        'AND s.expires_at > clock_timestamp() AND a.is_active',
      ),
      parameters: {'tokenHash': tokenHash},
    );
    if (result.isEmpty) return null;
    final row = result.first.toColumnMap();
    return SessionPrincipal(
      id: row['id']! as String,
      username: row['username']! as String,
      companyId: row['company_id']! as String,
      locationId: row['location_id']! as String,
      tokenHash: (row['token_hash']! as String).trim(),
    );
  }

  @override
  Future<bool> revokeSession(String tokenHash) async {
    return pool.runTx((tx) async {
      final owner = await tx.execute(
        Sql.named(
          'SELECT a.id::text AS account_id, '
          'a.company_id::text AS company_id, '
          'a.location_id::text AS location_id '
          'FROM $_schema.auth_sessions s '
          'JOIN $_schema.accounts a ON a.id = s.account_id '
          'WHERE s.token_hash = @tokenHash',
        ),
        parameters: {'tokenHash': tokenHash},
      );
      if (owner.isEmpty) return false;
      final account = owner.single.toColumnMap();
      final companyId = account['company_id']! as String;
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
        parameters: {'key': 'storeos_platform:$schemaName:$companyId'},
      );
      final revoked = await tx.execute(
        Sql.named(
          'UPDATE $_schema.auth_sessions SET revoked_at = now() '
          'WHERE token_hash = @tokenHash AND revoked_at IS NULL '
          'AND expires_at > clock_timestamp() RETURNING id::text AS id',
        ),
        parameters: {'tokenHash': tokenHash},
      );
      if (revoked.isEmpty) return false;
      await AuditRepository(_schema).append(
        tx,
        actorId: account['account_id']! as String,
        companyId: companyId,
        locationId: account['location_id']! as String,
        action: 'auth.logout',
        entityType: 'session',
        entityId: revoked.single.toColumnMap()['id']! as String,
        changes: const {},
      );
      return true;
    });
  }
}
