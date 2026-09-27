import 'dart:convert';

import 'package:postgres/postgres.dart';

import '../application/auth_service.dart';
import '../application/password_hasher.dart';
import '../config.dart';
import '../platform/audit_repository.dart';
import 'auth_store.dart';

class BootstrapException implements Exception {
  BootstrapException(this.message);

  final String message;

  @override
  String toString() => 'BootstrapException: $message';
}

/// One-time local operator account creation. Run only with migration credentials.
class BootstrapService {
  BootstrapService({
    required this.connection,
    required this.passwordHasher,
    this.schemaName = 'storeos_platform',
  }) : _schema = quotedSchema(schemaName);

  final Connection connection;
  final PasswordHasher passwordHasher;
  final String schemaName;
  final String _schema;

  Future<String> bootstrap({
    required String username,
    required String password,
    required String companyId,
    required String locationId,
  }) async {
    final usernameKey = normalizeUsername(username);
    if (!isUuid(companyId) || !isUuid(locationId)) {
      throw BootstrapException('Company and location IDs must be UUIDs.');
    }
    final passwordBytes = utf8.encode(password).length;
    if (passwordBytes < 24 || passwordBytes > 1024) {
      throw BootstrapException('Bootstrap password must be 24 to 1024 bytes.');
    }
    final passwordHash = await passwordHasher.hash(password);
    return connection.runTx((tx) async {
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(hashtext(@lockKey))'),
        parameters: {'lockKey': 'storeos_bootstrap:$schemaName'},
      );
      final state = await tx.execute(
        'SELECT 1 FROM $_schema.bootstrap_state LIMIT 1',
      );
      final accounts = await tx.execute(
        'SELECT 1 FROM $_schema.accounts LIMIT 1',
      );
      if (state.isNotEmpty || accounts.isNotEmpty) {
        throw BootstrapException('Initial account already exists.');
      }
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.companies (id) '
          'VALUES (CAST(@companyId AS uuid)) ON CONFLICT (id) DO NOTHING',
        ),
        parameters: {'companyId': companyId},
      );
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.locations (id, company_id) '
          'VALUES (CAST(@locationId AS uuid), CAST(@companyId AS uuid)) '
          'ON CONFLICT (id) DO NOTHING',
        ),
        parameters: {'locationId': locationId, 'companyId': companyId},
      );
      final location = await tx.execute(
        Sql.named(
          'SELECT 1 FROM $_schema.locations '
          'WHERE id = CAST(@locationId AS uuid) '
          'AND company_id = CAST(@companyId AS uuid)',
        ),
        parameters: {'locationId': locationId, 'companyId': companyId},
      );
      if (location.isEmpty) {
        throw BootstrapException('Bootstrap location has a different company.');
      }
      final inserted = await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.accounts '
          '(username, username_key, password_hash, company_id, location_id, role) '
          'VALUES (@username, @usernameKey, @passwordHash, '
          "CAST(@companyId AS uuid), CAST(@locationId AS uuid), 'admin') "
          'RETURNING id::text AS id',
        ),
        parameters: {
          'username': username.trim(),
          'usernameKey': usernameKey,
          'passwordHash': passwordHash,
          'companyId': companyId,
          'locationId': locationId,
        },
      );
      final accountId = inserted.single.toColumnMap()['id']! as String;
      await tx.execute(
        Sql.named(
          'INSERT INTO $_schema.bootstrap_state (singleton, account_id) '
          'VALUES (true, CAST(@accountId AS uuid))',
        ),
        parameters: {'accountId': accountId},
      );
      await AuditRepository(_schema).append(
        tx,
        actorKind: 'system',
        actorId: 'bootstrap-cli',
        companyId: companyId,
        locationId: locationId,
        action: 'platform.bootstrapped',
        entityType: 'user',
        entityId: accountId,
        changes: const {'role': 'admin'},
      );
      return accountId;
    });
  }
}
