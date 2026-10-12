import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/production/preparation_assignment_service.dart';
import 'knowledge_acceptance.dart';

/// Nonempty recovery evidence created exclusively through the authorized APIs.
Future<void> seedPreparationAssignments(
  KnowledgeAcceptanceRequest manager,
  KnowledgeAcceptanceRequest employee,
  String location,
  String employeeId,
  String otherEmployeeId, {
  String recipeSku = 'RECIPE-PRODUCED-0',
}) async {
  final page = await manager(
    'GET',
    '/api/v1/platform/production/recipes?q=$recipeSku',
    null,
    200,
  );
  final recipe = PublishedRecipeDto.fromJson(
    (page['items'] as List).single as Map<String, dynamic>,
  );
  final manage =
      '/api/v1/platform/production/manage/locations/$location/preparation-assignments';
  final own =
      '/api/v1/platform/production/self/locations/$location/preparation-assignments';
  final batches =
      '/api/v1/platform/production/self/locations/$location/batches';
  final managedBatches =
      '/api/v1/platform/production/manage/locations/$location/batches';
  final eligible =
      (await manager('GET', '$manage/assignees', null, 200))['items'] as List;
  for (var n = 0; n < 7; n++) {
    final target = n == 6 ? otherEmployeeId : employeeId;
    final e = eligible.cast<Map>().singleWhere((e) => e['id'] == target);
    final id = newUuid();
    await manager('POST', manage, {
      'id': id,
      'operationId': newUuid(),
      'recipeId': recipe.recipe,
      'revisionId': recipe.revisionId,
      'employeeId': target,
      'expectedEmployeeVersion': e['version'],
      'plannedDeclaredBatchCount': 3,
    }, 201);
    if (n == 1) {
      await manager('POST', '$manage/$id/withdraw', {
        'operationId': newUuid(),
        'expectedVersion': 1,
        'reason': 'Recovery withdrawal <script>literal</script> 😀',
      }, 200);
    } else if (n >= 2 && n <= 5) {
      final result = await employee('POST', '$own/$id/start', {
        'operationId': newUuid(),
        'expectedVersion': 1,
      }, 200);
      final batch = (result['batch'] as Map)['batchId'];
      if (n == 3 || n == 5) {
        await employee('POST', '$batches/$batch/complete', {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'actualDeclaredBatchCount': 2,
          'note': 'Assignment recovery literal 😀',
        }, 200);
      } else if (n == 4) {
        await employee('POST', '$batches/$batch/cancel', {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'reason': 'Assignment recovery cancellation 😀',
        }, 200);
      }
      if (n == 3) {
        for (var correction = 0; correction < 2; correction++) {
          await manager('POST', '$managedBatches/$batch/count-corrections', {
            'operationId': newUuid(),
            'expectedVersion': 2,
            'expectedLatestCorrectionNumber': correction,
            'replacementDeclaredBatchCount': 1 - correction,
            'reason':
                'Assignment correction ${correction + 1} <script>literal</script> 😀',
          }, 200);
        }
      }
    }
  }
}

Future<void> verifyRestoredAssignments(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal employee,
  SessionPrincipal otherEmployee,
) async {
  final service = PreparationAssignmentService(db), location = db.locationId;
  Future<List<Object?>> fingerprint() async => [
    for (final table in [
      'production_preparation_assignments',
      'production_preparation_assignment_commands',
      'production_preparation_batches',
      'production_preparation_batch_commands',
      'production_preparation_batch_count_corrections',
      'production_recipes',
      'production_recipe_revisions',
      'production_recipe_ingredients',
      'audit_entries',
      'stock_levels',
      'stock_movements',
      'stock_counts',
      'task_instances',
      'workforce_shift_transfer_commands',
      'purchasing_commands',
    ])
      (await db.pool.execute(
        "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
      )).single.first,
  ];
  final before = await fingerprint();
  final managed = await service.list(manager, location),
      own = await service.list(employee, location, self: true),
      other = await service.list(otherEmployee, location, self: true);
  if ((managed['items'] as List).length != 7 ||
      (own['items'] as List).length != 6 ||
      (other['items'] as List).length != 1) {
    throw StateError('Assignment recovery ownership or count differs.');
  }
  final states = <String, int>{};
  var correctedZero = false, completed = false, cancelled = false, open = false;
  for (final item in (own['items'] as List).cast<Map>()) {
    final id = item['id'] as String;
    final d = await service.detail(employee, location, id, self: true),
        context = await service.recipe(employee, location, id, self: true);
    await service.history(manager, location, id);
    states.update(d['status'] as String, (n) => n + 1, ifAbsent: () => 1);
    if (context['revisionId'] != d['revisionId'] ||
        (context['content'] as Map)['batchDescription'] == null) {
      throw StateError('Retained assignment context differs.');
    }
    final b = d['batch'] as Map?;
    if (b != null) {
      if (b['batchId'] != d['batchId'] ||
          b['plannedDeclaredBatchCount'] != 3 ||
          b['revisionId'] != d['revisionId'] ||
          b['employeeId'] != d['employeeId']) {
        throw StateError('Exact recovery linkage differs.');
      }
      open |= b['status'] == 'open';
      cancelled |= b['status'] == 'cancelled';
      completed |=
          b['status'] == 'completed' && b['effectiveDeclaredBatchCount'] == 2;
      correctedZero |=
          b['status'] == 'completed' &&
          b['actualDeclaredBatchCount'] == 2 &&
          b['effectiveDeclaredBatchCount'] == 0 &&
          (b['corrections'] as List).length == 2;
    }
    for (final action in [
      () => service.detail(otherEmployee, location, id, self: true),
      () => service.recipe(otherEmployee, location, id, self: true),
      () => service.history(otherEmployee, location, id, self: true),
      () => service.command(otherEmployee, location, id, 'start', {
        'operationId': newUuid(),
        'expectedVersion': 1,
      }, self: true),
    ]) {
      try {
        await action();
        throw StateError('Foreign Employee recovery access accepted.');
      } on PlatformFailure catch (e) {
        if (e.status != 404) rethrow;
      }
    }
  }
  if (states['assigned'] != 1 ||
      states['withdrawn'] != 1 ||
      states['started'] != 4 ||
      !correctedZero ||
      !completed ||
      !cancelled ||
      !open) {
    throw StateError('Assignment recovery lifecycle evidence incomplete.');
  }
  final receipts = await db.pool.execute(
    'SELECT assignment_id::text,kind,actor_id::text,payload,result FROM ${db.schema}.production_preparation_assignment_commands ORDER BY operation_id',
  );
  if (receipts.length != 12) {
    throw StateError('Assignment recovery receipts missing.');
  }
  for (final r in receipts) {
    final kind = r[1] as String;
    final replay = await service.command(
      r[2] == manager.id ? manager : employee,
      location,
      kind == 'create' ? null : r[0] as String,
      kind,
      Map<String, dynamic>.from(r[3] as Map),
      self: kind == 'start',
    );
    if (replay['replayed'] != true) {
      throw StateError('Assignment command not replayed.');
    }
    final original = Map<String, dynamic>.from(r[4] as Map);
    replay.remove('replayed');
    original.remove('replayed');
    // Compare recursively through PostgreSQL jsonb to ignore object key ordering.
    final same = await db.pool.execute(
      Sql.named('SELECT @a::jsonb = @b::jsonb'),
      parameters: {'a': jsonEncode(replay), 'b': jsonEncode(original)},
    );
    if (same.single.first != true) {
      throw StateError('Original assignment replay evidence differs.');
    }
  }
  for (final self in [false, true]) {
    try {
      await service.list(self ? employee : manager, newUuid(), self: self);
      throw StateError('Foreign Location accepted.');
    } on PlatformFailure catch (e) {
      if (e.status != 403) rethrow;
    }
  }
  final foreign = PreparationAssignmentService(
    PlatformDatabase(
      db.pool,
      schemaName: db.schemaName,
      companyId: newUuid(),
      locationId: location,
    ),
  );
  for (final actor in [manager, employee, otherEmployee]) {
    try {
      await foreign.list(actor, location, self: actor != manager);
      throw StateError('Foreign Company recovery access accepted.');
    } on PlatformFailure catch (e) {
      if (e.status != 403) rethrow;
    }
  }
  if (jsonEncode(before) != jsonEncode(await fingerprint())) {
    throw StateError('Assignment recovery probe changed evidence.');
  }
}

Future<void> verifyAssignmentGrants(
  Connection owner,
  String schema,
  String runtime,
) async {
  for (final table in [
    'production_preparation_assignments',
    'production_preparation_assignment_commands',
  ]) {
    final row = (await owner.execute(
      Sql.named(
        "SELECT has_table_privilege(@role,@table,'UPDATE'),has_table_privilege(@role,@table,'DELETE'),has_table_privilege(@role,@table,'TRUNCATE')",
      ),
      parameters: {'role': runtime, 'table': '$schema.$table'},
    )).single;
    if (row.any((v) => v == true)) {
      throw StateError('Assignment runtime grants too broad.');
    }
  }
}
