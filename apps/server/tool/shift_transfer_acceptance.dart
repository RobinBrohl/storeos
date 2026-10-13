import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/application/shift_transfer_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'knowledge_acceptance.dart';

Object? _stable(Object? value) {
  if (value is Map) {
    return {
      for (final key in value.keys.map((k) => k.toString()).toList()..sort())
        key: _stable(value[key]),
    };
  }
  if (value is List) return value.map(_stable).toList();
  return value;
}

/// Production-path evidence for all request states and all seven receipt kinds.
Future<List<Map<String, dynamic>>> seedShiftTransfers(
  KnowledgeAcceptanceRequest manager,
  KnowledgeAcceptanceRequest source,
  KnowledgeAcceptanceRequest recipient,
  String location,
  String sourceEmployee,
  String recipientEmployee,
  String template,
  String revision,
) async {
  final records = <Map<String, dynamic>>[];
  final start = DateTime.now().toUtc().add(const Duration(days: 2));
  const cases = [
    'proposed',
    'accepted',
    'declined',
    'source_proposed',
    'source_accepted',
    'recipient_accepted',
    'reject_proposed',
    'reject_accepted',
    'approved',
  ];
  for (var n = 0; n < cases.length; n++) {
    final state = cases[n],
        shift = newUuid(),
        request = newUuid(),
        begins = start.add(Duration(hours: n * 3));
    await manager('POST', '/api/v1/platform/shifts', {
      'id': shift,
      'locationId': location,
      'employeeId': sourceEmployee,
      'startsAt': begins.toIso8601String(),
      'endsAt': begins.add(const Duration(hours: 1)).toIso8601String(),
      'selections': [
        {'templateId': template, 'revisionId': revision},
      ],
    }, 201);
    await manager('POST', '/api/v1/platform/shifts/$shift/publish', {
      'expectedVersion': 1,
    }, 200);
    final proposal = {
      'operationId': newUuid(),
      'requestId': request,
      'sourceShiftId': shift,
      'expectedSourceVersion': 2,
      'recipientEmployeeId': recipientEmployee,
    };
    final result = await source(
      'POST',
      '/api/v1/platform/me/shift-transfers',
      proposal,
      201,
    );
    records.add({
      'actor': 'source',
      'route': '/me/shift-transfers',
      'requestId': request,
      'kind': 'propose',
      'body': proposal,
      'result': result,
    });
    var version = 1;
    if (state == 'accepted' ||
        state.endsWith('_accepted') ||
        state == 'approved') {
      final body = {'operationId': newUuid(), 'expectedVersion': 1};
      final result = await recipient(
        'POST',
        '/api/v1/platform/me/shift-transfers/$request/accept',
        body,
        200,
      );
      records.add({
        'actor': 'recipient',
        'requestId': request,
        'kind': 'accept',
        'body': body,
        'result': result,
      });
      version = 2;
    }
    final kind = state == 'declined'
        ? 'decline'
        : state.startsWith('source_')
        ? 'source_withdraw'
        : state.startsWith('recipient_')
        ? 'recipient_withdraw'
        : state.startsWith('reject_')
        ? 'manager_reject'
        : state == 'approved'
        ? 'manager_approve'
        : null;
    if (kind == null) continue;
    final action = kind.startsWith('manager_')
        ? kind.substring(8)
        : kind.endsWith('withdraw')
        ? 'withdraw'
        : kind;
    final own = !kind.startsWith('manager_'),
        route = own
            ? '/me/shift-transfers/$request/$action'
            : '/locations/$location/shift-transfers/$request/$action';
    final body = {
      'operationId': newUuid(),
      'expectedVersion': version,
      if (kind.endsWith('withdraw') || kind == 'manager_reject')
        'reason': 'Retained transfer decision <script>literal</script> 😀',
    };
    final actor = kind == 'source_withdraw'
        ? 'source'
        : own
        ? 'recipient'
        : 'manager';
    final terminal = await (actor == 'source'
        ? source
        : own
        ? recipient
        : manager)('POST', '/api/v1/platform$route', body, 200);
    records.add({
      'actor': actor,
      'requestId': request,
      'kind': kind,
      'body': body,
      'result': terminal,
    });
  }
  return records;
}

Future<void> verifyShiftTransfers(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal source,
  SessionPrincipal recipient,
  List<dynamic> records, {
  SessionPrincipal? outsider,
  String? deniedLocation,
  List<SessionPrincipal> deniedRoles = const [],
}) async {
  final app = ShiftTransferApplication(db);
  Future<String> hash() async => jsonEncode({
    for (final table in [
      'workforce_shift_transfer_requests',
      'workforce_shift_transfer_commands',
      'task_transfer_links',
      'shifts',
      'shift_template_selections',
      'task_instances',
      'audit_entries',
    ])
      table: (await db.pool.execute(
        "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
      )).single.toList(),
  });
  final before = await hash();
  final states = <String>{};
  for (final raw in records) {
    final record = raw as Map, kind = record['kind'] as String;
    final p = record['actor'] == 'source'
        ? source
        : record['actor'] == 'recipient'
        ? recipient
        : manager;
    final result = await app.command(
      p,
      kind == 'propose' ? null : record['requestId'] as String,
      kind,
      Map<String, dynamic>.from(record['body'] as Map),
      self: !kind.startsWith('manager_'),
      location: kind.startsWith('manager_') ? db.locationId : null,
    );
    if (jsonEncode(_stable(result)) !=
        jsonEncode(
          _stable({
            ...Map<String, dynamic>.from(record['result'] as Map),
            'replayed': true,
          }),
        )) {
      throw StateError('Restored exact transfer receipt changed.');
    }
    final detail = await app.detail(source, record['requestId'] as String);
    states.add(detail['status'] as String);
    if (jsonEncode(detail).contains('"results"') ||
        jsonEncode(detail).contains('"content"')) {
      throw StateError('Transfer leaked execution evidence.');
    }
    await app.detail(recipient, record['requestId'] as String);
    await app.detail(
      manager,
      record['requestId'] as String,
      self: false,
      location: db.locationId,
    );
    Future<void> denied(Future<Object?> operation, int status) async {
      try {
        await operation;
        throw StateError('Restored transfer authorization denial missing.');
      } on PlatformFailure catch (e) {
        if (e.status != status) rethrow;
      }
    }

    if (deniedLocation != null) {
      await denied(
        app.detail(
          manager,
          record['requestId'] as String,
          self: false,
          location: deniedLocation,
        ),
        403,
      );
      await denied(
        app.command(
          manager,
          record['requestId'] as String,
          kind.startsWith('manager_') ? kind : 'manager_approve',
          Map<String, dynamic>.from(record['body'] as Map),
          self: false,
          location: deniedLocation,
        ),
        403,
      );
    }
    for (final role in deniedRoles) {
      await denied(app.detail(role, record['requestId'] as String), 403);
      await denied(
        app.detail(
          role,
          record['requestId'] as String,
          self: false,
          location: db.locationId,
        ),
        403,
      );
    }
    if (outsider != null) {
      try {
        await app.detail(outsider, record['requestId'] as String);
        throw StateError('Nonparticipant transfer exposed.');
      } on PlatformFailure catch (e) {
        if (e.status != 404) rethrow;
      }
    }
  }
  if (states.length != 6 || await hash() != before) {
    throw StateError('Transfer state/replay conservation failed.');
  }
}

Future<void> verifyTransferGrants(
  Connection owner,
  String schema,
  String runtime,
) async {
  for (final table in [
    'workforce_shift_transfer_requests',
    'workforce_shift_transfer_commands',
    'task_transfer_links',
  ]) {
    for (final privilege in ['DELETE', 'TRUNCATE']) {
      final result = await owner.execute(
        Sql.named('SELECT has_table_privilege(@role,@table,@privilege)'),
        parameters: {
          'role': runtime,
          'table': '"$schema".$table',
          'privilege': privilege,
        },
      );
      if (result.single.first != false) {
        throw StateError('Transfer runtime grant too broad.');
      }
    }
  }
}

/// Bounded recovery evidence for the active P4.11 parents seeded by these tools.
Future<Map<String, dynamic>> verifyTransferHandoffClaims(
  Connection owner,
  String schema, {
  int expectedActive = 2,
}) async {
  final s = quotedSchema(schema);
  final inconsistentParents = await owner.execute('''
    SELECT count(*) FROM $s.workforce_shift_transfer_requests r
    WHERE (SELECT count(*) FROM $s.workforce_shift_handoff_claims c
      WHERE c.company_id=r.company_id AND c.location_id=r.location_id
        AND c.transfer_request_id=r.id AND c.shift_id=r.source_shift_id)
      <> CASE WHEN r.status IN ('proposed','accepted') THEN 1 ELSE 0 END
  ''');
  final inconsistentClaims = await owner.execute('''
    SELECT count(*) FROM $s.workforce_shift_handoff_claims c
    LEFT JOIN $s.workforce_shift_transfer_requests r
      ON r.company_id=c.company_id AND r.location_id=c.location_id
        AND r.id=c.transfer_request_id AND r.source_shift_id=c.shift_id
    LEFT JOIN $s.shifts s ON s.company_id=c.company_id
      AND s.location_id=c.location_id AND s.id=c.shift_id
    WHERE r.id IS NULL OR s.id IS NULL
      OR r.status NOT IN ('proposed','accepted')
      OR c.swap_request_id IS NOT NULL OR c.leg IS NOT NULL
  ''');
  final evidence = (await owner.execute('''
    SELECT count(*), md5(coalesce(string_agg(
      to_jsonb(c)::text || to_jsonb(r)::text, ''
      ORDER BY c.company_id,c.shift_id),''))
    FROM $s.workforce_shift_handoff_claims c
    JOIN $s.workforce_shift_transfer_requests r
      ON r.company_id=c.company_id AND r.id=c.transfer_request_id
  ''')).single;
  if (inconsistentParents.single.first != 0 ||
      inconsistentClaims.single.first != 0 ||
      evidence.first != expectedActive) {
    throw StateError('Active transfer handoff claims are inconsistent.');
  }
  return {
    'activeTransferClaims': evidence.first,
    'claimsAndParentsDigest': evidence[1],
    'exactScopedParentConsistencyVerified': true,
  };
}
