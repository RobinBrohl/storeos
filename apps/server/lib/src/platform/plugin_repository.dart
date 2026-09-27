import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'platform_database.dart';
import 'platform_models.dart';

/// Persistence for registrations, scoped tokens and the local plugin inbox.
/// Manifest validation, approval policy and audit stay in PluginService.
class PluginRepository {
  PluginRepository(this.database);

  final PlatformDatabase database;

  Future<void> lockCompany(TxSession tx) async {
    await tx.execute(
      Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
      parameters: {
        'key': 'storeos_platform:${database.schemaName}:${database.companyId}',
      },
    );
  }

  Future<List<PluginRegistration>> list(TxSession tx, String companyId) async {
    final rows = await tx.execute(
      Sql.named(
        '${_viewSelect()} '
        'WHERE p.company_id = CAST(@companyId AS uuid) '
        'ORDER BY p.id LIMIT 101',
      ),
      parameters: {'companyId': companyId},
    );
    return rows
        .map((row) => PluginRegistration.fromRow(row.toColumnMap()))
        .toList();
  }

  Future<int> count(TxSession tx, String companyId) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT count(*)::int AS count '
        'FROM ${database.schema}.plugin_registrations '
        'WHERE company_id = CAST(@companyId AS uuid)',
      ),
      parameters: {'companyId': companyId},
    );
    return rows.single.toColumnMap()['count'] as int;
  }

  Future<bool> exists(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT 1 FROM ${database.schema}.plugin_registrations WHERE id = @id',
      ),
      parameters: {'id': id},
    );
    return rows.isNotEmpty;
  }

  Future<void> insert(
    TxSession tx,
    String companyId,
    PluginManifest manifest,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO ${database.schema}.plugin_registrations '
        '(id, company_id, manifest) '
        'VALUES (@id, CAST(@companyId AS uuid), CAST(@manifest AS jsonb))',
      ),
      parameters: {
        'id': manifest.id,
        'companyId': companyId,
        'manifest': jsonEncode(manifest.toJson()),
      },
    );
  }

  Future<PluginRegistration?> lock(
    TxSession tx,
    String id,
    String companyId,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        '${_viewSelect()} '
        'WHERE p.id = @id AND p.company_id = CAST(@companyId AS uuid) '
        'FOR UPDATE OF p',
      ),
      parameters: {'id': id, 'companyId': companyId},
    );
    return rows.isEmpty
        ? null
        : PluginRegistration.fromRow(rows.single.toColumnMap());
  }

  Future<PluginRegistration?> load(
    TxSession tx,
    String id,
    String companyId,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        '${_viewSelect()} '
        'WHERE p.id = @id AND p.company_id = CAST(@companyId AS uuid)',
      ),
      parameters: {'id': id, 'companyId': companyId},
    );
    return rows.isEmpty
        ? null
        : PluginRegistration.fromRow(rows.single.toColumnMap());
  }

  Future<void> revokeTokens(TxSession tx, String id) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.plugin_tokens SET revoked_at = now() '
        'WHERE plugin_id = @id AND revoked_at IS NULL',
      ),
      parameters: {'id': id},
    );
  }

  Future<void> revokePendingInbox(TxSession tx, String id) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.plugin_inbox '
        "SET status = 'revoked' WHERE plugin_id = @id AND status = 'pending'",
      ),
      parameters: {'id': id},
    );
  }

  Future<void> approve(
    TxSession tx, {
    required String id,
    required String locationId,
    required List<String> permissions,
    required List<String> subscriptions,
  }) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.plugin_registrations SET '
        "status = 'approved', version = version + 1, "
        'location_id = CAST(@locationId AS uuid), '
        'permissions = CAST(@permissions AS text[]), '
        'subscriptions = CAST(@subscriptions AS text[]), '
        'approved_at = clock_timestamp(), disabled_at = NULL '
        'WHERE id = @id',
      ),
      parameters: {
        'id': id,
        'locationId': locationId,
        'permissions': permissions,
        'subscriptions': subscriptions,
      },
    );
  }

  Future<void> issueToken(
    TxSession tx, {
    required String id,
    required String tokenHash,
    required DateTime expiresAt,
  }) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO ${database.schema}.plugin_tokens '
        '(plugin_id, token_hash, expires_at) '
        'VALUES (@id, @tokenHash, @expiresAt)',
      ),
      parameters: {'id': id, 'tokenHash': tokenHash, 'expiresAt': expiresAt},
    );
  }

  Future<void> disable(TxSession tx, String id) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.plugin_registrations SET '
        "status = 'disabled', version = version + 1, "
        "location_id = NULL, permissions = '{}'::text[], "
        "subscriptions = '{}'::text[], disabled_at = clock_timestamp() "
        'WHERE id = @id',
      ),
      parameters: {'id': id},
    );
  }

  Future<PluginGrant?> activeGrant(
    TxSession tx, {
    required String tokenHash,
    required String companyId,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT p.id, p.company_id::text AS company_id, '
        'p.location_id::text AS location_id, p.permissions, '
        'p.subscriptions, p.approved_at '
        'FROM ${database.schema}.plugin_tokens t '
        'JOIN ${database.schema}.plugin_registrations p ON p.id = t.plugin_id '
        'WHERE t.token_hash = @hash AND t.revoked_at IS NULL '
        "AND t.expires_at > clock_timestamp() AND p.status = 'approved' "
        'AND p.company_id = CAST(@companyId AS uuid)',
      ),
      parameters: {'hash': tokenHash, 'companyId': companyId},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return PluginGrant(
      id: row['id'] as String,
      companyId: row['company_id'] as String,
      locationId: row['location_id'] as String,
      approvedAt: row['approved_at'] as DateTime,
      permissions: (row['permissions'] as List).cast<String>(),
      subscriptions: (row['subscriptions'] as List).cast<String>(),
    );
  }

  Future<List<PluginInboxEvent>> inboxPage(
    TxSession tx,
    PluginGrant grant, {
    int? afterId,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT i.id AS inbox_id, e.id::text AS event_id, e.type, '
        'e.schema_version, e.company_id::text AS company_id, '
        'e.location_id::text AS location_id, '
        'e.origin_node_id::text AS origin_node_id, '
        'e.occurred_at, e.recorded_at, e.payload '
        'FROM ${database.schema}.plugin_inbox i '
        'JOIN ${database.schema}.event_outbox e ON e.id = i.event_id '
        "WHERE i.plugin_id = @pluginId AND i.status = 'pending' "
        'AND e.company_id = CAST(@companyId AS uuid) '
        'AND (e.location_id IS NULL OR e.location_id = CAST(@locationId AS uuid)) '
        'AND e.recorded_at >= @approvedAt '
        'AND e.type = ANY(CAST(@subscriptions AS text[])) '
        'AND (CAST(@after AS bigint) IS NULL OR i.id > CAST(@after AS bigint)) '
        'ORDER BY i.id LIMIT 51',
      ),
      parameters: {
        'pluginId': grant.id,
        'companyId': grant.companyId,
        'locationId': grant.locationId,
        'approvedAt': grant.approvedAt,
        'subscriptions': grant.subscriptions,
        'after': afterId,
      },
    );
    return rows
        .map((row) => PluginInboxEvent.fromRow(row.toColumnMap()))
        .toList();
  }

  Future<PluginDeliveryState?> lockDelivery(
    TxSession tx,
    String pluginId,
    String eventId,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT i.status, e.type, e.company_id::text AS company_id, '
        'e.location_id::text AS location_id, e.recorded_at '
        'FROM ${database.schema}.plugin_inbox i '
        'JOIN ${database.schema}.event_outbox e ON e.id = i.event_id '
        'WHERE i.plugin_id = @pluginId AND i.event_id = CAST(@eventId AS uuid) '
        'FOR UPDATE OF i',
      ),
      parameters: {'pluginId': pluginId, 'eventId': eventId},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return PluginDeliveryState(
      status: row['status'] as String,
      type: row['type'] as String,
      companyId: row['company_id'] as String,
      locationId: row['location_id'] as String?,
      recordedAt: row['recorded_at'] as DateTime,
    );
  }

  Future<void> acknowledge(
    TxSession tx,
    String pluginId,
    String eventId,
  ) async {
    await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.plugin_inbox SET '
        "status = 'acknowledged', acknowledged_at = clock_timestamp() "
        'WHERE plugin_id = @pluginId AND event_id = CAST(@eventId AS uuid)',
      ),
      parameters: {'pluginId': pluginId, 'eventId': eventId},
    );
  }

  Future<List<String>> eligiblePluginIds(
    TxSession tx, {
    required String companyId,
    required String? locationId,
    required String type,
    required DateTime recordedAt,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id FROM ${database.schema}.plugin_registrations '
        "WHERE status = 'approved' "
        'AND company_id = CAST(@companyId AS uuid) '
        'AND (CAST(@locationId AS uuid) IS NULL OR '
        'location_id = CAST(@locationId AS uuid)) '
        'AND approved_at <= @recordedAt '
        "AND permissions @> ARRAY['events.read']::text[] "
        'AND @eventType = ANY(subscriptions) FOR SHARE',
      ),
      parameters: {
        'companyId': companyId,
        'locationId': locationId,
        'recordedAt': recordedAt,
        'eventType': type,
      },
    );
    return rows.map((row) => row.toColumnMap()['id'] as String).toList();
  }

  Future<void> addInbox(TxSession tx, String pluginId, String eventId) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO ${database.schema}.plugin_inbox '
        '(plugin_id, event_id) '
        'VALUES (@pluginId, CAST(@eventId AS uuid)) '
        'ON CONFLICT (plugin_id, event_id) DO NOTHING',
      ),
      parameters: {'pluginId': pluginId, 'eventId': eventId},
    );
  }

  String _viewSelect() =>
      'SELECT p.id, p.manifest, p.status, p.version, '
      'p.location_id::text AS location_id, p.permissions, p.subscriptions, '
      '(SELECT t.expires_at FROM ${database.schema}.plugin_tokens t '
      'WHERE t.plugin_id = p.id AND t.revoked_at IS NULL '
      'ORDER BY t.created_at DESC LIMIT 1) AS token_expires_at '
      'FROM ${database.schema}.plugin_registrations p';
}
