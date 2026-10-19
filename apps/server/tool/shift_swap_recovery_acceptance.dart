// Constructed recovery evidence only; every business write uses the real API.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'knowledge_acceptance.dart';

const swapRecoveryTables = <String, String>{
  'workforce_shift_swap_requests': 'company_id,id',
  'workforce_shift_swap_legs': 'company_id,request_id,leg',
  'workforce_shift_swap_commands': 'company_id,operation_id',
  'task_swap_links': 'company_id,request_id,leg,position',
};
const quantityRecoveryTables = <String, String>{
  'inventory_quantity_profiles': 'company_id,id',
  'inventory_quantity_revisions': 'company_id,profile_id,version',
  'inventory_quantity_commands': 'company_id,operation_id',
  'stock_quantity_bindings': 'company_id,stock_level_id',
  'stock_quantity_corrections': 'company_id,operation_id',
};

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

/// Whole rows, ordered by their declared keys, including immutable JSON content.
Future<Map<String, dynamic>> recoveryProjection(
  Connection connection,
  String schema,
  Map<String, String> tables,
) async {
  final s = quotedSchema(schema);
  final result = <String, dynamic>{};
  for (final table in tables.entries) {
    final rows = await connection.execute(
      'SELECT to_jsonb(t)::text FROM $s.${table.key} t ORDER BY ${table.value}',
    );
    result[table.key] = {
      'count': rows.length,
      'sha256': sha256
          .convert(
            utf8.encode(jsonEncode([for (final row in rows) row.single])),
          )
          .toString(),
    };
  }
  return result;
}

Future<List<Map<String, dynamic>>> seedRecoverySwaps(
  KnowledgeAcceptanceRequest manager,
  KnowledgeAcceptanceRequest a,
  KnowledgeAcceptanceRequest b,
  String location,
  String employeeA,
  String employeeB,
  String template,
  String revision,
) async {
  final records = <Map<String, dynamic>>[];
  final base = DateTime.now().toUtc().add(const Duration(days: 10));
  const cases = [
    'requested',
    'offered',
    'confirmed',
    'declined',
    'source_withdraw',
    'recipient_withdraw',
    'rejected',
    'approved',
  ];
  for (var n = 0; n < cases.length; n++) {
    final state = cases[n], id = newUuid();
    final shifts = <String>[];
    for (var leg = 0; leg < 2; leg++) {
      final shift = newUuid();
      shifts.add(shift);
      final start = base.add(Duration(hours: n * 6 + leg * 2));
      await manager('POST', '/api/v1/platform/shifts', {
        'id': shift,
        'locationId': location,
        'employeeId': leg == 0 ? employeeA : employeeB,
        'startsAt': start.toIso8601String(),
        'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
        'selections': [
          {'templateId': template, 'revisionId': revision},
        ],
      }, 201);
      await manager('POST', '/api/v1/platform/shifts/$shift/publish', {
        'expectedVersion': 1,
      }, 200);
    }
    Future<void> command(
      String actor,
      String action,
      Map<String, dynamic> body,
    ) async {
      final route = action == 'request'
          ? '/me/shift-swaps'
          : actor == 'manager'
          ? '/locations/$location/shift-swaps/$id/$action'
          : '/me/shift-swaps/$id/$action';
      final result =
          await (actor == 'a'
              ? a
              : actor == 'b'
              ? b
              : manager)(
            'POST',
            '/api/v1/platform$route',
            body,
            action == 'request' ? 201 : 200,
          );
      records.add({
        'actor': actor,
        'route': route,
        'body': body,
        'result': result,
        'requestId': id,
        'case': state,
        'statusCode': action == 'request' ? 201 : 200,
      });
    }

    await command('a', 'request', {
      'operationId': newUuid(),
      'requestId': id,
      'sourceShiftId': shifts[0],
      'expectedSourceVersion': 2,
      'recipientEmployeeId': employeeB,
    });
    if (state == 'requested') continue;
    await command('b', 'offer', {
      'operationId': newUuid(),
      'expectedVersion': 1,
      'counterpartShiftId': shifts[1],
      'expectedCounterpartVersion': 2,
    });
    if (state == 'offered') continue;
    if (state == 'declined') {
      await command('a', 'decline', {
        'operationId': newUuid(),
        'expectedVersion': 2,
      });
    } else if (state.endsWith('withdraw')) {
      await command(state.startsWith('source') ? 'a' : 'b', 'withdraw', {
        'operationId': newUuid(),
        'expectedVersion': 2,
        'reason': 'Explicit recovery fixture closure',
      });
    } else {
      await command('a', 'confirm', {
        'operationId': newUuid(),
        'expectedVersion': 2,
      });
      if (state != 'confirmed') {
        await command('manager', state == 'approved' ? 'approve' : 'reject', {
          'operationId': newUuid(),
          'expectedVersion': 3,
          if (state == 'rejected')
            'reason': 'Explicit recovery fixture rejection',
        });
      }
    }
  }
  return records;
}

/// Validate the current projection independently of PostgreSQL's write triggers.
/// This also detects evidence lost by an incomplete/corrupt recovery operation.
Future<Map<String, dynamic>> verifyRecoverySwaps(
  Connection connection,
  String schema, {
  int expectedActiveClaims = 5,
  bool initialInventory = true,
}) async {
  final s = quotedSchema(schema);
  final invalid = await connection.execute('''
    SELECT count(*) FROM $s.workforce_shift_swap_requests r
    WHERE r.version <> CASE r.status WHEN 'requested' THEN 1 WHEN 'offered' THEN 2
      WHEN 'confirmed' THEN 3 ELSE CASE WHEN r.confirmed_at IS NOT NULL THEN 4
      WHEN r.offered_at IS NOT NULL THEN 3 ELSE 2 END END
    OR (SELECT count(*) FROM $s.workforce_shift_swap_legs l
      WHERE l.company_id=r.company_id AND l.request_id=r.id
        AND l.location_id=r.location_id) <> CASE WHEN r.offered_at IS NULL THEN 1 ELSE 2 END
    OR (SELECT count(*) FROM $s.workforce_shift_handoff_claims c
      WHERE c.company_id=r.company_id AND c.swap_request_id=r.id)
      <> CASE r.status WHEN 'requested' THEN 1 WHEN 'offered' THEN 2 WHEN 'confirmed' THEN 2 ELSE 0 END
    OR NOT EXISTS (SELECT 1 FROM $s.workforce_shift_swap_commands c
      WHERE c.company_id=r.company_id AND c.operation_id=r.request_operation_id
        AND c.request_id=r.id AND c.actor_id=r.source_account_id AND c.kind='request')
  ''');
  final claims = await connection.execute('''
    SELECT count(*) FROM $s.workforce_shift_handoff_claims c
    LEFT JOIN $s.workforce_shift_swap_legs l ON l.company_id=c.company_id
      AND l.request_id=c.swap_request_id AND l.leg=c.leg AND l.source_shift_id=c.shift_id
      AND l.location_id=c.location_id
    LEFT JOIN $s.workforce_shift_swap_requests r ON r.company_id=l.company_id
      AND r.id=l.request_id AND r.location_id=l.location_id
    WHERE c.swap_request_id IS NOT NULL AND (l.request_id IS NULL OR r.id IS NULL
      OR c.transfer_request_id IS NOT NULL OR r.status NOT IN ('requested','offered','confirmed'))
  ''');
  final legs = await connection.execute('''
    SELECT count(*) FROM $s.workforce_shift_swap_legs l
    LEFT JOIN $s.workforce_shift_swap_requests r ON r.company_id=l.company_id
      AND r.id=l.request_id AND r.location_id=l.location_id
    LEFT JOIN $s.shifts o ON o.company_id=l.company_id AND o.id=l.source_shift_id
      AND o.location_id=l.location_id AND o.employee_id=l.source_employee_id
    LEFT JOIN $s.shifts n ON n.company_id=l.company_id AND n.id=l.replacement_shift_id
      AND n.location_id=l.location_id AND n.employee_id=l.incoming_employee_id
    WHERE r.id IS NULL OR o.id IS NULL
      OR l.work_references IS DISTINCT FROM $s.tasks_swap_references(l.company_id,l.source_shift_id,l.location_id)
      OR (r.status='approved' AND (n.id IS NULL OR o.status<>'cancelled'
        OR o.version<>l.source_version+1 OR n.status<>'published'
        OR n.starts_at<>l.starts_at OR n.ends_at<>l.ends_at
        OR n.swap_request_id IS DISTINCT FROM r.id OR n.swap_leg IS DISTINCT FROM l.leg
        OR (SELECT count(*) FROM $s.task_swap_links t WHERE t.company_id=l.company_id
          AND t.request_id=l.request_id AND t.leg=l.leg)<>jsonb_array_length(l.work_references)))
      OR (r.status<>'approved' AND l.replacement_shift_id IS NOT NULL)
  ''');
  final links = await connection.execute('''
    SELECT count(*) FROM $s.task_swap_links t
    LEFT JOIN $s.workforce_shift_swap_legs l ON l.company_id=t.company_id
      AND l.request_id=t.request_id AND l.location_id=t.location_id AND l.leg=t.leg
      AND l.source_shift_id=t.source_shift_id AND l.replacement_shift_id=t.replacement_shift_id
    LEFT JOIN $s.task_instances o ON o.company_id=t.company_id AND o.id=t.source_task_id
      AND o.location_id=t.location_id AND o.shift_id=t.source_shift_id AND o.position=t.position
      AND o.template_id=t.template_id AND o.revision_id=t.revision_id
    LEFT JOIN $s.task_instances n ON n.company_id=t.company_id AND n.id=t.replacement_task_id
      AND n.location_id=t.location_id AND n.shift_id=t.replacement_shift_id AND n.position=t.position
      AND n.template_id=t.template_id AND n.revision_id=t.revision_id
    WHERE l.request_id IS NULL OR o.id IS NULL OR n.id IS NULL OR o.content IS DISTINCT FROM n.content
  ''');
  final active = (await connection.execute(
    'SELECT count(*) FROM $s.workforce_shift_handoff_claims WHERE swap_request_id IS NOT NULL',
  )).single.single;
  if ([invalid, claims, legs, links].any((r) => r.single.single != 0) ||
      active != expectedActiveClaims) {
    throw StateError('Swap recovery integrity verification failed.');
  }
  final projection = await recoveryProjection(
    connection,
    schema,
    swapRecoveryTables,
  );
  if (initialInventory) {
    const expected = [8, 15, 23, 2];
    var index = 0;
    for (final table in swapRecoveryTables.keys) {
      if ((projection[table] as Map)['count'] != expected[index++]) {
        throw StateError('Swap recovery inventory differs from seeded plan.');
      }
    }
    final statuses = (await connection.execute(
      'SELECT status,version,count(*) FROM $s.workforce_shift_swap_requests GROUP BY status,version ORDER BY status',
    )).map((r) => r.toList()).toList();
    if (jsonEncode(statuses) !=
        '[["approved",4,1],["confirmed",3,1],["declined",3,1],["offered",2,1],["rejected",4,1],["requested",1,1],["withdrawn",3,2]]') {
      throw StateError('Swap recovery lifecycle inventory differs.');
    }
  }
  return {
    'classification': 'PASS',
    'tables': projection,
    'activeSwapClaims': active,
  };
}

/// HTTP reads/replays under freshly authenticated, restricted runtime actors.
Future<void> verifyRecoverySwapReplay(
  KnowledgeAcceptanceRequest manager,
  KnowledgeAcceptanceRequest a,
  KnowledgeAcceptanceRequest b,
  List<dynamic> records,
  String location,
) async {
  final requests = <String>{};
  for (final raw in records) {
    final record = raw as Map;
    final actor = record['actor'] == 'a'
        ? a
        : record['actor'] == 'b'
        ? b
        : manager;
    final replay = await actor(
      'POST',
      '/api/v1/platform${record['route']}',
      Map<String, dynamic>.from(record['body'] as Map),
      record['statusCode'] as int,
    );
    if (jsonEncode(_stable(replay)) !=
        jsonEncode(
          _stable({
            ...Map<String, dynamic>.from(record['result'] as Map),
            'replayed': true,
          }),
        )) {
      throw StateError('Recovered exact swap receipt differs.');
    }
    requests.add(record['requestId'] as String);
  }
  for (final id in requests) {
    for (final actor in [a, b]) {
      await actor('GET', '/api/v1/platform/me/shift-swaps/$id', null, 200);
      await actor(
        'GET',
        '/api/v1/platform/me/shift-swaps/$id/history',
        null,
        200,
      );
      await actor(
        'GET',
        '/api/v1/platform/locations/$location/shift-swaps/$id',
        null,
        403,
      );
    }
    await manager(
      'GET',
      '/api/v1/platform/locations/$location/shift-swaps/$id',
      null,
      200,
    );
  }
}

/// Existing Stock evidence is left intact: this binds prospectively and records
/// an exact zero-delta alternate-unit correction at the same physical target.
Future<Map<String, dynamic>> seedRecoveryQuantity(
  KnowledgeAcceptanceRequest manager,
  String location,
  Map<String, dynamic> level,
) async {
  final profileBody = {
    'operationId': newUuid(),
    'profileId': newUuid(),
    'baseUnit': 'kg',
    'packages': [
      {'id': newUuid(), 'label': 'case', 'content': '2.5'},
    ],
    'reason': 'Explicit acceptance semantics',
  };
  final profile = await manager(
    'POST',
    '/api/v1/platform/articles/${level['articleId']}/quantity/configure',
    profileBody,
    200,
  );
  final root =
      '/api/v1/platform/locations/$location/stock/${level['id']}/quantity';
  final bindingBody = {
    'operationId': newUuid(),
    'profileId': profile['id'],
    'profileVersion': profile['version'],
    'stockVersion': level['version'],
    'unit': 'kg',
    'reason': 'Explicit frozen unit meaning',
  };
  final binding = await manager('POST', '$root/bind', bindingBody, 200);
  final review = await manager('POST', '$root/preview', {
    'profileVersion': profile['version'],
    'stockVersion': level['version'],
    'inputUnit': 'g',
    'inputQuantity': switch (level['quantity']) {
      '12.5' => '12500',
      '10' => '10000',
      _ => throw StateError('Unexpected recovery quantity fixture target.'),
    },
  }, 200);
  final correctionBody = {
    'operationId': newUuid(),
    'review': review,
    'reason': 'Exact retained zero-delta review',
  };
  final result = await manager('POST', '$root/correct', correctionBody, 200);
  if (review['delta'] != '0' ||
      review['targetQuantity'] != level['quantity'] ||
      result['movementId'] != null ||
      result['balanceVersion'] != level['version']) {
    throw StateError('Recovery fixture changed the retained Stock target.');
  }
  final replay = await manager('POST', '$root/correct', correctionBody, 200);
  if (jsonEncode(_stable(replay)) != jsonEncode(_stable(result))) {
    throw StateError('Quantity recovery replay changed.');
  }
  return {'profile': profile, 'binding': binding, 'receipt': result};
}
