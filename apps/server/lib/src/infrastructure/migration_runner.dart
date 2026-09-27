import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';

import 'auth_store.dart';

class MigrationException implements Exception {
  MigrationException(this.message);

  final String message;

  @override
  String toString() => 'MigrationException: $message';
}

class MigrationRunner {
  MigrationRunner({
    required this.connection,
    required this.migrationsDirectory,
    this.schemaName = 'storeos_platform',
    this.runtimeDatabaseUser,
  }) : _schema = quotedSchema(schemaName);

  final Connection connection;
  final Directory migrationsDirectory;
  final String schemaName;
  final String? runtimeDatabaseUser;
  final String _schema;

  Future<List<String>> apply() async {
    final migrations = _loadMigrations();
    final applied = <String>[];
    await connection.runTx((tx) async {
      await tx.execute(
        Sql.named('SELECT pg_advisory_xact_lock(hashtext(@lockKey))'),
        parameters: {'lockKey': 'storeos_migrations:$schemaName'},
      );
      await tx.execute('CREATE SCHEMA IF NOT EXISTS $_schema');
      await tx.execute(
        'CREATE TABLE IF NOT EXISTS $_schema.schema_migrations ('
        'version text PRIMARY KEY, '
        'checksum char(64) NOT NULL, '
        'applied_at timestamptz NOT NULL DEFAULT now())',
      );
      final records = await tx.execute(
        'SELECT version, checksum FROM $_schema.schema_migrations '
        'ORDER BY version',
      );
      final checksums = <String, String>{};
      for (final record in records) {
        final columns = record.toColumnMap();
        checksums[columns['version']! as String] =
            (columns['checksum']! as String).trim();
      }
      final known = {
        for (final migration in migrations) migration.version: migration,
      };
      for (final entry in checksums.entries) {
        final migration = known[entry.key];
        if (migration == null) {
          throw MigrationException('Unknown applied migration: ${entry.key}.');
        }
        if (migration.checksum != entry.value) {
          throw MigrationException('Checksum changed: ${entry.key}.');
        }
      }
      final orderedApplied = migrations
          .where((migration) => checksums.containsKey(migration.version))
          .map((migration) => migration.version)
          .toList();
      if (orderedApplied.length != checksums.length ||
          !_isPrefix(
            orderedApplied,
            migrations.map((m) => m.version).toList(),
          )) {
        throw MigrationException('Applied migrations are not a known prefix.');
      }
      for (final migration in migrations) {
        if (checksums.containsKey(migration.version)) continue;
        final sql = migration.sql.replaceAll('{{schema}}', _schema);
        await tx.execute(sql, queryMode: QueryMode.simple, ignoreRows: true);
        await tx.execute(
          Sql.named(
            'INSERT INTO $_schema.schema_migrations (version, checksum) '
            'VALUES (@version, @checksum)',
          ),
          parameters: {
            'version': migration.version,
            'checksum': migration.checksum,
          },
        );
        applied.add(migration.version);
      }
      final runtimeUser = runtimeDatabaseUser;
      if (runtimeUser != null && runtimeUser.isNotEmpty) {
        final role = '"${runtimeUser.replaceAll('"', '""')}"';
        await tx.execute('GRANT USAGE ON SCHEMA $_schema TO $role');
        await tx.execute('GRANT SELECT ON $_schema.schema_migrations TO $role');
        await tx.execute('GRANT SELECT ON $_schema.accounts TO $role');
        await tx.execute(
          'GRANT SELECT, INSERT, DELETE ON $_schema.auth_sessions TO $role',
        );
        await tx.execute(
          'GRANT UPDATE (revoked_at) ON $_schema.auth_sessions TO $role',
        );
        if (known.containsKey('0002_platform_organization')) {
          await tx.execute('GRANT SELECT ON $_schema.companies TO $role');
          await tx.execute(
            'GRANT UPDATE (name, version, updated_at) '
            'ON $_schema.companies TO $role',
          );
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.locations TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (name, version, updated_at) '
            'ON $_schema.locations TO $role',
          );
          await tx.execute('GRANT INSERT ON $_schema.accounts TO $role');
          await tx.execute(
            'GRANT UPDATE (role, is_active, password_hash, version) '
            'ON $_schema.accounts TO $role',
          );
        }
        if (known.containsKey('0003_platform_events_plugins')) {
          await tx.execute('GRANT SELECT ON $_schema.platform_node TO $role');
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.audit_entries, '
            '$_schema.event_outbox, $_schema.event_receipts, '
            '$_schema.plugin_registrations, $_schema.plugin_tokens, '
            '$_schema.plugin_inbox TO $role',
          );
          await tx.execute(
            'GRANT USAGE ON SEQUENCE $_schema.audit_entries_id_seq, '
            '$_schema.plugin_inbox_id_seq TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (status, attempts, next_attempt_at, last_error, '
            'dispatched_at) ON $_schema.event_outbox TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (status, version, location_id, permissions, '
            'subscriptions, approved_at, disabled_at) '
            'ON $_schema.plugin_registrations TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (revoked_at) ON $_schema.plugin_tokens TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (status, acknowledged_at) '
            'ON $_schema.plugin_inbox TO $role',
          );
          await tx.execute(
            'REVOKE UPDATE, DELETE, TRUNCATE ON $_schema.audit_entries '
            'FROM $role',
          );
        }
        if (known.containsKey('0006_shifts_and_task_instances')) {
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.shifts, $_schema.shift_template_selections, $_schema.task_instances TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (employee_id, starts_at, ends_at, status, version, updated_at, published_at, published_by, publication_version) ON $_schema.shifts TO $role',
          );
          await tx.execute(
            'GRANT DELETE ON $_schema.shift_template_selections TO $role',
          );
          await tx.execute(
            'REVOKE UPDATE, DELETE, TRUNCATE ON $_schema.task_instances FROM $role',
          );
          await tx.execute(
            'REVOKE DELETE, TRUNCATE ON $_schema.shifts FROM $role',
          );
        }
        if (known.containsKey('0007_task_execution')) {
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.task_step_results, $_schema.task_execution_commands TO $role',
          );
          await tx.execute(
            'REVOKE UPDATE, DELETE, TRUNCATE ON $_schema.task_step_results, $_schema.task_execution_commands FROM $role',
          );
          await tx.execute(
            'GRANT UPDATE (status, version, started_at, started_by, completed_at, completed_by) ON $_schema.task_instances TO $role',
          );
        }
        if (known.containsKey('0008_task_blocking')) {
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.task_blockings TO $role',
          );
          await tx.execute(
            'REVOKE UPDATE, DELETE, TRUNCATE ON $_schema.task_blockings FROM $role',
          );
          await tx.execute(
            'GRANT UPDATE (resolution, resolved_at, resolved_by, resolved_version) ON $_schema.task_blockings TO $role',
          );
        }
        if (known.containsKey('0009_task_cancellation')) {
          await tx.execute(
            'GRANT UPDATE (resolution_kind) ON $_schema.task_blockings TO $role',
          );
        }
        if (known.containsKey('0005_task_templates')) {
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.task_templates, $_schema.task_template_revisions TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (version, updated_at) ON $_schema.task_templates TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (content, status, published_at, published_by, publication_version) ON $_schema.task_template_revisions TO $role',
          );
          await tx.execute(
            'REVOKE DELETE, TRUNCATE ON $_schema.task_templates, $_schema.task_template_revisions FROM $role',
          );
        }
        if (known.containsKey('0004_employee_identity_and_audit')) {
          await tx.execute(
            'GRANT SELECT, INSERT ON $_schema.employees, '
            '$_schema.account_employee_links TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (display_name, is_active, version, '
            'updated_at, assigned_until) ON $_schema.employees TO $role',
          );
          await tx.execute(
            'GRANT UPDATE (version, revoked_at) '
            'ON $_schema.account_employee_links TO $role',
          );
        }
      }
    });
    return applied;
  }

  List<_Migration> _loadMigrations() {
    if (!migrationsDirectory.existsSync()) {
      throw MigrationException('Migrations directory is missing.');
    }
    final files =
        migrationsDirectory
            .listSync(followLinks: false)
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    if (files.isEmpty) {
      throw MigrationException('No SQL migrations found.');
    }
    final migrations = <_Migration>[];
    final versionPattern = RegExp(r'^\d{4}_[a-z0-9_]+$');
    for (final file in files) {
      final fileName = file.uri.pathSegments.last;
      final version = fileName.substring(0, fileName.length - '.sql'.length);
      if (!versionPattern.hasMatch(version)) {
        throw MigrationException('Invalid migration filename: $fileName.');
      }
      final sql = file.readAsStringSync();
      if (sql.trim().isEmpty) {
        throw MigrationException('Empty migration: $fileName.');
      }
      migrations.add(
        _Migration(
          version: version,
          sql: sql,
          checksum: sha256.convert(utf8.encode(sql)).toString(),
        ),
      );
    }
    return migrations;
  }

  bool _isPrefix(List<String> applied, List<String> known) {
    if (applied.length > known.length) return false;
    for (var i = 0; i < applied.length; i++) {
      if (applied[i] != known[i]) return false;
    }
    return true;
  }
}

class _Migration {
  const _Migration({
    required this.version,
    required this.sql,
    required this.checksum,
  });

  final String version;
  final String sql;
  final String checksum;
}
