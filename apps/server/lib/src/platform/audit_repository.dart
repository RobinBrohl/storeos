import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'platform_models.dart';
import '../application/correlation.dart';

/// Persists audit records in the caller's transaction and reads bounded pages.
class AuditRepository {
  AuditRepository(this.schema);

  final String schema;

  Future<void> append(
    TxSession tx, {
    String actorKind = 'user',
    required String actorId,
    required String companyId,
    required String? locationId,
    required String action,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> changes,
  }) async {
    if (!const {'user', 'system', 'plugin'}.contains(actorKind)) {
      throw ArgumentError.value(actorKind, 'actorKind', 'Invalid audit actor.');
    }
    const allowedFields = {
      'name',
      'oldName',
      'newName',
      'role',
      'oldRole',
      'isActive',
      'oldIsActive',
      'locationId',
      'oldLocationId',
      'username',
      'permissions',
      'subscriptions',
      'status',
      'version',
      'accountId',
      'employeeId',
      'revisionId',
      'revisionIds',
      'shiftId',
      'sku',
      'barcode',
      'unit',
      'startsAt',
      'endsAt',
      'revisionNumber',
      'changedFields',
      'stepId',
      'attemptId',
      'inRange',
      'blockingId',
      'operationId',
      'oldVersion',
      'oldStatus',
      'oldStartsAt',
      'oldEndsAt',
      'reason',
      'origin',
      'cancellationVersion',
      'amendmentVersion',
    };
    for (final entry in changes.entries) {
      if (!allowedFields.contains(entry.key) || !_safeAuditValue(entry.value)) {
        throw ArgumentError.value(entry.key, 'changes', 'Unsafe audit field.');
      }
    }
    if (utf8.encode(jsonEncode(changes)).length > 4096) {
      throw ArgumentError.value(changes, 'changes', 'Audit changes too large.');
    }
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.audit_entries '
        '(actor_kind, actor_id, company_id, location_id, action, '
        'entity_type, entity_id, changes, correlation_id) '
        'VALUES (@actorKind, @actorId, CAST(@companyId AS uuid), '
        'CAST(@locationId AS uuid), @action, @entityType, @entityId, '
        'CAST(@changes AS jsonb), CAST(@correlationId AS uuid))',
      ),
      parameters: {
        'actorKind': actorKind,
        'actorId': actorId,
        'companyId': companyId,
        'locationId': locationId,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'changes': jsonEncode(changes),
        'correlationId': currentCorrelationId,
      },
    );
  }

  Future<List<AuditEntry>> page(
    TxSession tx, {
    required String companyId,
    required int? beforeId,
    int limit = 51,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id, occurred_at, actor_kind, actor_id, '
        'company_id::text AS company_id, '
        'location_id::text AS location_id, action, entity_type, entity_id, '
        'changes, correlation_id::text AS correlation_id FROM $schema.audit_entries '
        'WHERE company_id = CAST(@companyId AS uuid) '
        'AND (CAST(@after AS bigint) IS NULL OR id < CAST(@after AS bigint)) '
        'ORDER BY id DESC LIMIT @limit',
      ),
      parameters: {'companyId': companyId, 'after': beforeId, 'limit': limit},
    );
    return rows.map((row) => AuditEntry.fromRow(row.toColumnMap())).toList();
  }
}

bool _safeAuditValue(Object? value) {
  if (value == null || value is bool || value is num) return true;
  if (value is String) return value.runes.length <= 512;
  if (value is List && value.length <= 32) {
    return value.every((item) => item is String && item.length <= 128);
  }
  return false;
}
