import 'package:postgres/postgres.dart';

import '../platform/platform_database.dart';
import 'user_model.dart';

class IdentityRepository {
  IdentityRepository(this.database);

  final PlatformDatabase database;

  String get _columns =>
      'id::text AS id, username, company_id::text AS company_id, '
      'location_id::text AS location_id, role, is_active, version';

  Future<List<UserRecord>> users(TxSession tx) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM ${database.schema}.accounts '
        'WHERE company_id = CAST(@companyId AS uuid) '
        'ORDER BY username_key LIMIT 201',
      ),
      parameters: {'companyId': database.companyId},
    );
    return result.map(_userFromRow).toList();
  }

  Future<UserRecord?> user(TxSession tx, String userId) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM ${database.schema}.accounts '
        'WHERE id = CAST(@userId AS uuid) '
        'AND company_id = CAST(@companyId AS uuid)',
      ),
      parameters: {'userId': userId, 'companyId': database.companyId},
    );
    return result.isEmpty ? null : _userFromRow(result.single);
  }

  Future<bool> usernameExists(TxSession tx, String usernameKey) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT 1 FROM ${database.schema}.accounts '
        'WHERE username_key = @usernameKey LIMIT 1',
      ),
      parameters: {'usernameKey': usernameKey},
    );
    return result.isNotEmpty;
  }

  Future<int> activeAdminCount(TxSession tx) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT count(*)::int AS count FROM ${database.schema}.accounts '
        "WHERE company_id = CAST(@companyId AS uuid) AND role = 'admin' "
        'AND is_active',
      ),
      parameters: {'companyId': database.companyId},
    );
    return result.single.toColumnMap()['count']! as int;
  }

  Future<UserRecord> createUser(
    TxSession tx, {
    required String id,
    required String username,
    required String usernameKey,
    required String passwordHash,
    required String locationId,
    required String role,
  }) async {
    final result = await tx.execute(
      Sql.named(
        'INSERT INTO ${database.schema}.accounts '
        '(id, username, username_key, password_hash, company_id, '
        'location_id, role) '
        'VALUES (CAST(@id AS uuid), @username, @usernameKey, @passwordHash, '
        'CAST(@companyId AS uuid), CAST(@locationId AS uuid), @role) '
        'RETURNING $_columns',
      ),
      parameters: {
        'id': id,
        'username': username,
        'usernameKey': usernameKey,
        'passwordHash': passwordHash,
        'companyId': database.companyId,
        'locationId': locationId,
        'role': role,
      },
    );
    return _userFromRow(result.single);
  }

  Future<UserRecord> setRoleAndActive(
    TxSession tx, {
    required String userId,
    required String role,
    required bool isActive,
    required int expectedVersion,
  }) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.accounts '
        'SET role = @role, is_active = @isActive, version = version + 1 '
        'WHERE id = CAST(@userId AS uuid) '
        'AND company_id = CAST(@companyId AS uuid) '
        'AND version = @expectedVersion '
        'RETURNING $_columns',
      ),
      parameters: {
        'userId': userId,
        'companyId': database.companyId,
        'role': role,
        'isActive': isActive,
        'expectedVersion': expectedVersion,
      },
    );
    if (result.isEmpty) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    return _userFromRow(result.single);
  }

  Future<UserRecord> setPassword(
    TxSession tx, {
    required String userId,
    required String passwordHash,
    required int expectedVersion,
  }) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.accounts '
        'SET password_hash = @passwordHash, version = version + 1 '
        'WHERE id = CAST(@userId AS uuid) '
        'AND company_id = CAST(@companyId AS uuid) '
        'AND version = @expectedVersion '
        'RETURNING $_columns',
      ),
      parameters: {
        'userId': userId,
        'companyId': database.companyId,
        'passwordHash': passwordHash,
        'expectedVersion': expectedVersion,
      },
    );
    if (result.isEmpty) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    return _userFromRow(result.single);
  }

  Future<void> revokeSessions(TxSession tx, String userId) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.auth_sessions SET revoked_at = now() '
        'WHERE account_id = CAST(@userId AS uuid) AND revoked_at IS NULL',
      ),
      parameters: {'userId': userId},
    );
  }
}

UserRecord _userFromRow(ResultRow row) {
  final values = row.toColumnMap();
  return UserRecord(
    id: values['id']! as String,
    username: values['username']! as String,
    companyId: values['company_id']! as String,
    locationId: values['location_id']! as String,
    role: values['role']! as String,
    isActive: values['is_active']! as bool,
    version: values['version']! as int,
  );
}
