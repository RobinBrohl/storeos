import 'package:postgres/postgres.dart';

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
  });

  final String id;
  final String username;
  final String companyId;
  final String locationId;
}

abstract interface class AuthStore {
  Future<bool> isReady();
  Future<StoredAccount?> findAccount(String usernameKey);
  Future<void> createSession({
    required String accountId,
    required String tokenHash,
    required DateTime expiresAt,
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
        "SELECT 1 FROM $_schema.schema_migrations "
        "WHERE version = '0001_platform_auth' LIMIT 1",
        timeout: const Duration(seconds: 2),
      );
      return migration.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<StoredAccount?> findAccount(String usernameKey) async {
    final result = await pool.execute(
      Sql.named(
        'SELECT id::text AS id, username, password_hash, '
        'company_id::text AS company_id, location_id::text AS location_id, '
        'is_active FROM $_schema.accounts WHERE username_key = @usernameKey',
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
  }) async {
    await pool.execute(
      Sql.named(
        'INSERT INTO $_schema.auth_sessions '
        '(account_id, token_hash, expires_at) '
        'VALUES (CAST(@accountId AS uuid), @tokenHash, @expiresAt)',
      ),
      parameters: {
        'accountId': accountId,
        'tokenHash': tokenHash,
        'expiresAt': expiresAt.toUtc(),
      },
    );
  }

  @override
  Future<SessionPrincipal?> findSession(String tokenHash) async {
    final result = await pool.execute(
      Sql.named(
        'SELECT a.id::text AS id, a.username, '
        'a.company_id::text AS company_id, '
        'a.location_id::text AS location_id '
        'FROM $_schema.auth_sessions s '
        'JOIN $_schema.accounts a ON a.id = s.account_id '
        'WHERE s.token_hash = @tokenHash AND s.revoked_at IS NULL '
        'AND s.expires_at > now() AND a.is_active',
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
    );
  }

  @override
  Future<bool> revokeSession(String tokenHash) async {
    final result = await pool.execute(
      Sql.named(
        'UPDATE $_schema.auth_sessions SET revoked_at = now() '
        'WHERE token_hash = @tokenHash AND revoked_at IS NULL '
        'AND expires_at > now()',
      ),
      parameters: {'tokenHash': tokenHash},
    );
    return result.affectedRows > 0;
  }
}
