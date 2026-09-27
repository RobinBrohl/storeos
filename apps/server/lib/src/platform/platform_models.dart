class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.occurredAt,
    required this.actorKind,
    required this.actorId,
    required this.companyId,
    required this.locationId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.changes,
    this.correlationId,
  });

  factory AuditEntry.fromRow(Map<String, dynamic> row) => AuditEntry(
    id: row['id'] as int,
    occurredAt: row['occurred_at'] as DateTime,
    actorKind: row['actor_kind'] as String,
    actorId: row['actor_id'] as String,
    companyId: row['company_id'] as String,
    locationId: row['location_id'] as String?,
    action: row['action'] as String,
    entityType: row['entity_type'] as String,
    entityId: row['entity_id'] as String,
    changes: Map<String, dynamic>.from(row['changes'] as Map),
    correlationId: row['correlation_id'] as String?,
  );

  final int id;
  final DateTime occurredAt;
  final String actorKind;
  final String actorId;
  final String companyId;
  final String? locationId;
  final String action;
  final String entityType;
  final String entityId;
  final Map<String, dynamic> changes;
  final String? correlationId;

  Map<String, dynamic> toJson() => {
    'id': id.toString(),
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'actorKind': actorKind,
    'actorId': actorId,
    'companyId': companyId,
    'locationId': locationId,
    'action': action,
    'entityType': entityType,
    'entityId': entityId,
    'changes': changes,
    'correlationId': correlationId,
  };
}

class PlatformEvent {
  const PlatformEvent({
    required this.id,
    required this.type,
    required this.schemaVersion,
    required this.aggregateType,
    required this.aggregateId,
    required this.aggregateVersion,
    required this.companyId,
    required this.locationId,
    required this.originNodeId,
    required this.actorId,
    required this.correlationId,
    required this.causationId,
    required this.occurredAt,
    required this.recordedAt,
    required this.payload,
    required this.status,
    required this.attempts,
    required this.lastError,
  });

  factory PlatformEvent.fromRow(Map<String, dynamic> row) => PlatformEvent(
    id: row['id'] as String,
    type: row['type'] as String,
    schemaVersion: row['schema_version'] as int,
    aggregateType: row['aggregate_type'] as String,
    aggregateId: row['aggregate_id'] as String,
    aggregateVersion: row['aggregate_version'] as int,
    companyId: row['company_id'] as String,
    locationId: row['location_id'] as String?,
    originNodeId: row['origin_node_id'] as String,
    actorId: row['actor_id'] as String,
    correlationId: row['correlation_id'] as String,
    causationId: row['causation_id'] as String?,
    occurredAt: row['occurred_at'] as DateTime,
    recordedAt: row['recorded_at'] as DateTime,
    payload: Map<String, dynamic>.from(row['payload'] as Map),
    status: row['status'] as String,
    attempts: row['attempts'] as int,
    lastError: row['last_error'] as String?,
  );

  final String id;
  final String type;
  final int schemaVersion;
  final String aggregateType;
  final String aggregateId;
  final int aggregateVersion;
  final String companyId;
  final String? locationId;
  final String originNodeId;
  final String actorId;
  final String correlationId;
  final String? causationId;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final Map<String, dynamic> payload;
  final String status;
  final int attempts;
  final String? lastError;

  Map<String, dynamic> toJson() => {
    'eventId': id,
    'type': type,
    'schemaVersion': schemaVersion,
    'aggregateType': aggregateType,
    'aggregateId': aggregateId,
    'aggregateVersion': aggregateVersion,
    'companyId': companyId,
    'locationId': locationId,
    'originNodeId': originNodeId,
    'actorId': actorId,
    'correlationId': correlationId,
    'causationId': causationId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'payload': payload,
    'status': status,
    'attempts': attempts,
    'lastError': lastError,
  };
}

class PluginRegistration {
  const PluginRegistration({
    required this.id,
    required this.manifest,
    required this.status,
    required this.version,
    required this.locationId,
    required this.permissions,
    required this.subscriptions,
    required this.tokenExpiresAt,
  });

  factory PluginRegistration.fromRow(Map<String, dynamic> row) =>
      PluginRegistration(
        id: row['id'] as String,
        manifest: Map<String, dynamic>.from(row['manifest'] as Map),
        status: row['status'] as String,
        version: row['version'] as int,
        locationId: row['location_id'] as String?,
        permissions: (row['permissions'] as List).cast<String>(),
        subscriptions: (row['subscriptions'] as List).cast<String>(),
        tokenExpiresAt: row['token_expires_at'] as DateTime?,
      );

  final String id;
  final Map<String, dynamic> manifest;
  final String status;
  final int version;
  final String? locationId;
  final List<String> permissions;
  final List<String> subscriptions;
  final DateTime? tokenExpiresAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'manifest': manifest,
    'status': status,
    'version': version,
    'locationId': locationId,
    'permissions': permissions,
    'subscriptions': subscriptions,
    'tokenExpiresAt': tokenExpiresAt?.toUtc().toIso8601String(),
  };
}

class PluginGrant {
  const PluginGrant({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.approvedAt,
    required this.permissions,
    required this.subscriptions,
  });

  final String id;
  final String companyId;
  final String locationId;
  final DateTime approvedAt;
  final List<String> permissions;
  final List<String> subscriptions;
}

class PluginInboxEvent {
  const PluginInboxEvent({
    required this.inboxId,
    required this.eventId,
    required this.type,
    required this.schemaVersion,
    required this.companyId,
    required this.locationId,
    required this.originNodeId,
    required this.occurredAt,
    required this.recordedAt,
    required this.payload,
  });

  factory PluginInboxEvent.fromRow(Map<String, dynamic> row) =>
      PluginInboxEvent(
        inboxId: row['inbox_id'] as int,
        eventId: row['event_id'] as String,
        type: row['type'] as String,
        schemaVersion: row['schema_version'] as int,
        companyId: row['company_id'] as String,
        locationId: row['location_id'] as String?,
        originNodeId: row['origin_node_id'] as String,
        occurredAt: row['occurred_at'] as DateTime,
        recordedAt: row['recorded_at'] as DateTime,
        payload: Map<String, dynamic>.from(row['payload'] as Map),
      );

  final int inboxId;
  final String eventId;
  final String type;
  final int schemaVersion;
  final String companyId;
  final String? locationId;
  final String originNodeId;
  final DateTime occurredAt;
  final DateTime recordedAt;
  final Map<String, dynamic> payload;

  Map<String, dynamic> toJson() => {
    'eventId': eventId,
    'type': type,
    'schemaVersion': schemaVersion,
    'companyId': companyId,
    'locationId': locationId,
    'originNodeId': originNodeId,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'payload': payload,
  };
}

class PluginDeliveryState {
  const PluginDeliveryState({
    required this.status,
    required this.type,
    required this.companyId,
    required this.locationId,
    required this.recordedAt,
  });

  final String status;
  final String type;
  final String companyId;
  final String? locationId;
  final DateTime recordedAt;
}
