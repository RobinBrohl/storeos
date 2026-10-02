import '../application/correlation.dart';
export '../application/correlation.dart' show newUuid;

import 'package:postgres/postgres.dart';

import '../infrastructure/auth_store.dart';
import 'audit_repository.dart';
import 'event_repository.dart';

class PlatformFailure implements Exception {
  const PlatformFailure(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'PlatformFailure($status, $code): $message';
}

class PlatformActor {
  const PlatformActor({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.role,
  });

  final String id;
  final String companyId;
  final String locationId;
  final String role;
}

const _permissions = <String>[
  'context.read',
  'organization.read',
  'organization.write',
  'identity.read',
  'identity.write',
  'identity.self.password',
  'audit.read',
  'events.read',
  'events.write',
  'plugins.read',
  'plugins.write',
  'people.manage',
  'tasks.templates.manage',
  'workforce.shifts.manage',
  'workforce.shifts.self.read',
  'tasks.instances.read',
  'tasks.instances.resolve',
  'tasks.instances.cancel',
  'tasks.instances.self.read',
  'tasks.instances.self.execute',
  'people.self.read',
];

List<String> permissionsForRole(String role) => switch (role) {
  'admin' => _permissions,
  'auditor' => const [
    'context.read',
    'organization.read',
    'identity.self.password',
    'audit.read',
    'events.read',
  ],
  'employee' => const [
    'context.read',
    'organization.read',
    'identity.self.password',
    'people.self.read',
    'workforce.shifts.self.read',
    'tasks.instances.self.read',
    'tasks.instances.self.execute',
  ],
  'viewer' => const [
    'context.read',
    'organization.read',
    'identity.self.password',
  ],
  _ => const [],
};

/// Single-company transaction boundary for authorization, state, audit, and events.
class PlatformDatabase {
  PlatformDatabase(
    this.pool, {
    this.schemaName = 'storeos_platform',
    required this.companyId,
    required this.locationId,
  }) : schema = quotedSchema(schemaName);

  final Pool<void> pool;
  final String schemaName;
  final String schema;
  final String companyId;
  final String locationId;

  Future<T> runAuthorized<T>(
    SessionPrincipal principal,
    String permission,
    Future<T> Function(TxSession tx, PlatformActor actor) action,
  ) {
    if (principal.companyId != companyId) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
    return withCorrelation(
      () => pool.runTx((tx) async {
        // One company writer lock also protects the last-admin invariant. Re-read
        // rights after acquiring it so role and account changes take effect now.
        await tx.execute(
          Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
          parameters: {'key': 'storeos_platform:$schemaName:$companyId'},
        );
        final found = await tx.execute(
          Sql.named(
            'SELECT id::text AS id, company_id::text AS company_id, '
            'location_id::text AS location_id, role, is_active '
            'FROM $schema.accounts WHERE id = CAST(@accountId AS uuid)',
          ),
          parameters: {'accountId': principal.id},
        );
        if (found.isEmpty) {
          throw const PlatformFailure(
            401,
            'unauthorized',
            'Session is invalid.',
          );
        }
        final account = found.single.toColumnMap();
        if (account['is_active'] != true ||
            account['company_id'] != companyId ||
            account['company_id'] != principal.companyId ||
            account['location_id'] != principal.locationId) {
          throw const PlatformFailure(
            401,
            'unauthorized',
            'Session is invalid.',
          );
        }
        final tokenHash = principal.tokenHash;
        if (tokenHash != null) {
          final currentSession = await tx.execute(
            Sql.named(
              'SELECT 1 FROM $schema.auth_sessions '
              'WHERE token_hash = @tokenHash AND account_id = CAST(@accountId AS uuid) '
              'AND revoked_at IS NULL AND expires_at > clock_timestamp()',
            ),
            parameters: {'tokenHash': tokenHash, 'accountId': principal.id},
          );
          if (currentSession.isEmpty) {
            throw const PlatformFailure(
              401,
              'unauthorized',
              'Session is invalid.',
            );
          }
        }
        final role = account['role']! as String;
        if (!permissionsForRole(role).contains(permission)) {
          throw const PlatformFailure(403, 'forbidden', 'Access denied.');
        }
        return action(
          tx,
          PlatformActor(
            id: principal.id,
            companyId: companyId,
            locationId: account['location_id']! as String,
            role: role,
          ),
        );
      }),
    );
  }

  Future<void> audit(
    TxSession tx,
    PlatformActor actor,
    String action,
    String entityType,
    String entityId, {
    String? locationId,
    Map<String, dynamic> changes = const {},
  }) => AuditRepository(schema).append(
    tx,
    actorId: actor.id,
    companyId: actor.companyId,
    locationId: locationId,
    action: action,
    entityType: entityType,
    entityId: entityId,
    changes: changes,
  );

  Future<void> publishOrganizationEvent(
    TxSession tx,
    PlatformActor actor,
    String type,
    String aggregateType,
    String aggregateId,
    int aggregateVersion,
    Map<String, dynamic> payload, {
    String? locationId,
    String? correlationId,
    String? causationId,
  }) => EventRepository(pool: pool, schema: schema, companyId: companyId)
      .appendOrganization(
        tx,
        actorId: actor.id,
        type: type,
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        aggregateVersion: aggregateVersion,
        payload: payload,
        locationId: locationId,
        correlationId: correlationId ?? currentCorrelationId,
        causationId: causationId,
        eventId: newUuid(),
      );
}
