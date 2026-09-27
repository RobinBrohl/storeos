import 'dart:convert';

import 'package:postgres/postgres.dart';

import 'platform_models.dart';

class EventCursor {
  const EventCursor(this.time, this.id);

  final DateTime time;
  final String id;
}

class DispatchCandidate {
  const DispatchCandidate({
    required this.id,
    required this.type,
    required this.companyId,
    required this.locationId,
    required this.recordedAt,
  });

  final String id;
  final String type;
  final String companyId;
  final String? locationId;
  final DateTime recordedAt;
}

class ReplayState {
  const ReplayState(this.status, this.locationId);

  final String status;
  final String? locationId;
}

class EventRepository {
  EventRepository({
    required this.pool,
    required this.schema,
    required this.companyId,
  });

  final Pool<void> pool;
  final String schema;
  final String companyId;

  Future<void> appendOrganization(
    TxSession tx, {
    required String actorId,
    required String type,
    required String aggregateType,
    required String aggregateId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
    required String? locationId,
    required String correlationId,
    required String? causationId,
    required String eventId,
  }) async {
    if (!const {
      'organization.company.setup',
      'organization.company.updated',
      'organization.location.created',
      'organization.location.updated',
    }.contains(type)) {
      throw ArgumentError.value(
        type,
        'type',
        'Unsupported organization event.',
      );
    }
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.event_outbox '
        '(id, type, schema_version, aggregate_type, aggregate_id, '
        'aggregate_version, company_id, location_id, actor_id, payload, '
        'origin_node_id, occurred_at, correlation_id, causation_id) '
        'VALUES (CAST(@id AS uuid), @type, 1, @aggregateType, '
        'CAST(@aggregateId AS uuid), @aggregateVersion, '
        'CAST(@companyId AS uuid), CAST(@locationId AS uuid), '
        '@actorId, CAST(@payload AS jsonb), '
        '(SELECT id FROM $schema.platform_node LIMIT 1), now(), '
        'CAST(@correlationId AS uuid), CAST(@causationId AS uuid))',
      ),
      parameters: {
        'id': eventId,
        'type': type,
        'aggregateType': aggregateType,
        'aggregateId': aggregateId,
        'aggregateVersion': aggregateVersion,
        'companyId': companyId,
        'locationId': locationId,
        'actorId': actorId,
        'payload': jsonEncode(payload),
        'correlationId': correlationId,
        'causationId': causationId,
      },
    );
  }

  Future<List<PlatformEvent>> page(
    TxSession tx, {
    required String companyId,
    EventCursor? before,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, type, schema_version, aggregate_type, '
        'aggregate_id::text AS aggregate_id, aggregate_version, '
        'company_id::text AS company_id, location_id::text AS location_id, '
        'origin_node_id::text AS origin_node_id, actor_id, '
        'correlation_id::text AS correlation_id, '
        'causation_id::text AS causation_id, occurred_at, recorded_at, '
        'payload, status, attempts, last_error '
        'FROM $schema.event_outbox '
        'WHERE company_id = CAST(@companyId AS uuid) '
        'AND (CAST(@afterAt AS timestamptz) IS NULL OR '
        '(recorded_at, id) < (CAST(@afterAt AS timestamptz), '
        'CAST(@afterId AS uuid))) '
        'ORDER BY recorded_at DESC, id DESC LIMIT 51',
      ),
      parameters: {
        'companyId': companyId,
        'afterAt': before?.time,
        'afterId': before?.id,
      },
    );
    return rows.map((row) => PlatformEvent.fromRow(row.toColumnMap())).toList();
  }

  Future<ReplayState?> lockReplay(
    TxSession tx,
    String eventId,
    String companyId,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT status, location_id::text AS location_id '
        'FROM $schema.event_outbox '
        'WHERE id = CAST(@id AS uuid) AND company_id = CAST(@companyId AS uuid) '
        'FOR UPDATE',
      ),
      parameters: {'id': eventId, 'companyId': companyId},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return ReplayState(row['status'] as String, row['location_id'] as String?);
  }

  Future<void> requeue(TxSession tx, String eventId) async {
    await tx.execute(
      Sql.named(
        'UPDATE $schema.event_outbox SET '
        "status = 'pending', attempts = 0, next_attempt_at = now(), "
        'last_error = NULL, dispatched_at = NULL '
        'WHERE id = CAST(@id AS uuid)',
      ),
      parameters: {'id': eventId},
    );
  }

  Future<DispatchCandidate?> claimDue(TxSession tx) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, type, company_id::text AS company_id, '
        'location_id::text AS location_id, recorded_at '
        'FROM $schema.event_outbox '
        "WHERE status = 'pending' AND next_attempt_at <= now() "
        'AND company_id = CAST(@companyId AS uuid) '
        'ORDER BY next_attempt_at, recorded_at, id '
        'FOR UPDATE SKIP LOCKED LIMIT 1',
      ),
      parameters: {'companyId': companyId},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return DispatchCandidate(
      id: row['id'] as String,
      type: row['type'] as String,
      companyId: row['company_id'] as String,
      locationId: row['location_id'] as String?,
      recordedAt: row['recorded_at'] as DateTime,
    );
  }

  Future<bool> hasReceipt(TxSession tx, String eventId) async {
    final receipt = await tx.execute(
      Sql.named(
        'SELECT 1 FROM $schema.event_receipts '
        "WHERE event_id = CAST(@eventId AS uuid) AND consumer = 'plugin_inbox'",
      ),
      parameters: {'eventId': eventId},
    );
    return receipt.isNotEmpty;
  }

  Future<void> addReceipt(TxSession tx, String eventId) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.event_receipts '
        '(event_id, consumer) '
        "VALUES (CAST(@eventId AS uuid), 'plugin_inbox') "
        'ON CONFLICT (event_id, consumer) DO NOTHING',
      ),
      parameters: {'eventId': eventId},
    );
  }

  Future<void> markDispatched(TxSession tx, String eventId) async {
    await tx.execute(
      Sql.named(
        'UPDATE $schema.event_outbox SET '
        "status = 'dispatched', dispatched_at = clock_timestamp(), "
        'last_error = NULL WHERE id = CAST(@eventId AS uuid)',
      ),
      parameters: {'eventId': eventId},
    );
  }

  Future<void> recordFailure(String eventId) async {
    await pool.execute(
      Sql.named(
        'UPDATE $schema.event_outbox SET '
        'attempts = LEAST(attempts + 1, 5), '
        "status = CASE WHEN attempts + 1 >= 5 THEN 'dead_letter' "
        "ELSE 'pending' END, "
        "next_attempt_at = now() + (5 * (attempts + 1)) * interval '1 second', "
        "last_error = 'plugin_inbox_delivery_failed' "
        "WHERE id = CAST(@eventId AS uuid) AND status = 'pending'",
      ),
      parameters: {'eventId': eventId},
    );
  }
}
