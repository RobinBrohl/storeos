import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/production/preparation_batch_service.dart';
import 'package:storeos_server/src/production/recipe_service.dart';
import 'package:crypto/crypto.dart';
import 'knowledge_acceptance.dart';

/// Recovery evidence uses normal production API commands exclusively.
Future<void> seedPreparationBatches(
  KnowledgeAcceptanceRequest manager,
  KnowledgeAcceptanceRequest employee,
  String location, {
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
  await manager('POST', '/api/v1/platform/locations/$location/assortment', {
    'id': newUuid(),
    'articleId': recipe.content.produced.id,
  }, 201);
  final own = '/api/v1/platform/production/self/locations/$location/batches',
      managed =
          '/api/v1/platform/production/manage/locations/$location/batches';
  for (var n = 0; n < 5; n++) {
    final id = newUuid();
    await employee('POST', own, {
      'batchId': id,
      'operationId': newUuid(),
      'recipeId': recipe.recipe,
      'revisionId': recipe.revisionId,
      'plannedDeclaredBatchCount': n == 0 ? null : 3,
    }, 201);
    if (n == 1 || n == 4) {
      await employee('POST', '$own/$id/complete', {
        'operationId': newUuid(),
        'expectedVersion': 1,
        'actualDeclaredBatchCount': 2,
        'note': 'Recovery <script>literal</script> 😀',
      }, 200);
    } else if (n == 2 || n == 3) {
      await (n == 2
          ? employee
          : manager)('POST', '${n == 2 ? own : managed}/$id/cancel', {
        'operationId': newUuid(),
        'expectedVersion': 1,
        'reason': 'Retained cancellation 😀',
      }, 200);
    }
    if (n == 4) {
      for (var correction = 0; correction < 2; correction++) {
        await manager('POST', '$managed/$id/count-corrections', {
          'operationId': newUuid(),
          'expectedVersion': 2,
          'expectedLatestCorrectionNumber': correction,
          'replacementDeclaredBatchCount': 1 - correction,
          'reason':
              'Recovery correction ${correction + 1} <script>literal</script>',
        }, 200);
      }
    }
  }
}

/// The same source/restore probe proves exceptional access without mutating evidence.
Future<Map<String, dynamic>> verifyHistoricalPreparation(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal employee,
  SessionPrincipal otherEmployee,
) async {
  final batches = PreparationBatchService(db), recipes = RecipeService(db);
  Future<String> evidenceHash() async {
    final hashes = <Object?>[];
    for (final table in [
      'production_recipes',
      'production_recipe_revisions',
      'production_recipe_ingredients',
      'production_preparation_batches',
      'production_preparation_batch_commands',
      'production_preparation_batch_count_corrections',
      'audit_entries',
    ]) {
      hashes.add(
        (await db.pool.execute(
          "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
        )).single.first,
      );
    }
    return sha256.convert(utf8.encode(jsonEncode(hashes))).toString();
  }

  final before = await evidenceHash();
  final page = await batches.list(employee, db.locationId);
  final b = (page['items'] as List).first as Map<String, dynamic>;
  final id = b['batchId'] as String, recipeId = b['recipeId'] as String;
  final detail = RecipeDetailDto.fromJson(
    await recipes.detail(manager, recipeId),
  );
  final history = RecipePage.fromJson(
    await recipes.history(manager, recipeId),
    RecipeRevisionDto.fromJson,
  );
  final r1 = history.items.singleWhere((r) => r.revisionNumber == 1);
  final r2 = history.items.singleWhere((r) => r.revisionNumber == 2);
  if (b['revisionId'] != r1.id ||
      detail.recipe.status != 'retired' ||
      r1.status != 'published' ||
      r2.status != 'published' ||
      r1.content.batchDescription == r2.content.batchDescription ||
      r1.content.preparation == r2.content.preparation ||
      r1.content.ingredients.first.quantity ==
          r2.content.ingredients.first.quantity) {
    throw StateError('Historical preparation fixture is not exceptional.');
  }
  Future<void> denied(Future<Map<String, dynamic>> action) async {
    try {
      await action;
    } on PlatformFailure catch (e) {
      if (e.status == 404) return;
      rethrow;
    }
    throw StateError('Historical preparation exclusion failed.');
  }

  final visible = await recipes.listPublished(employee, q: 'RECIPE-PRODUCED-1');
  if ((visible['items'] as List).isNotEmpty) {
    throw StateError('Retired Recipe leaked through discovery.');
  }
  await denied(recipes.readPublished(employee, recipeId));
  await denied(batches.detail(otherEmployee, db.locationId, id));
  await denied(batches.recipe(otherEmployee, db.locationId, id));
  await batches.detail(employee, db.locationId, id);
  await batches.detail(manager, db.locationId, id, self: false);
  final own = await batches.recipe(employee, db.locationId, id);
  final managed = await batches.recipe(manager, db.locationId, id, self: false);
  // Parse/re-serialize the frozen contract so labels, units, order and quantities
  // are compared completely, independently of database JSON object key order.
  String contentHash(RecipeContent content) =>
      sha256.convert(utf8.encode(jsonEncode(content.toJson()))).toString();
  final frozenHash = contentHash(r1.content);
  for (final context in [own, managed]) {
    if (context['revisionId'] != r1.id ||
        context['revisionNumber'] != 1 ||
        contentHash(
              RecipeContent.fromJson(
                context['content'] as Map<String, dynamic>,
              ),
            ) !=
            frozenHash ||
        !(context['warnings'] as List).contains('recipe_retired')) {
      throw StateError(
        'Historical preparation contextual content or warning differs.',
      );
    }
  }
  if (await evidenceHash() != before) {
    throw StateError(
      'Historical contextual probe changed business or audit evidence.',
    );
  }
  return {
    'batchId': id,
    'recipeId': recipeId,
    'pinnedR1Id': r1.id,
    'laterR2Id': r2.id,
    'recipeRetired': true,
    'laterPublicationExists': true,
    'employeeContextR1Verified': true,
    'managerContextR1Verified': true,
    'standaloneEmployeeExcluded': true,
    'otherEmployeeDenied': true,
    'retiredWarningVerified': true,
    'contextReadsPreserveBusinessAndAudit': true,
    'frozenContentSha256': frozenHash,
    'laterContentSha256': contentHash(r2.content),
  };
}

Future<void> verifyRestoredPreparation(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal employee, {
  SessionPrincipal? otherEmployee,
}) async {
  final app = PreparationBatchService(db), location = db.locationId;
  final rows = await db.pool.execute(
    'SELECT id::text,status FROM ${db.schema}.production_preparation_batches ORDER BY id',
  );
  if (rows.length != 5) {
    throw StateError('Restored preparation evidence missing.');
  }
  Future<List<Object?>> fingerprint() async => [
    for (final table in [
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
      'stock_count_lines',
      'stock_count_rounds',
      'stock_count_observations',
      'stock_count_commands',
    ])
      (await db.pool.execute(
        "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
      )).single.first,
  ];
  final before = await fingerprint();
  final history = await app.list(manager, location, self: false);
  if ((history['items'] as List).length != 5) {
    throw StateError('Restored manager preparation history missing.');
  }
  final own = await app.list(employee, location);
  if ((own['items'] as List).length != 5) {
    throw StateError('Restored self preparation history missing.');
  }
  for (final row in rows) {
    final id = row[0] as String;
    final detail = await app.detail(employee, location, id);
    final recipe = await app.recipe(employee, location, id);
    if (recipe['revisionId'] != detail['revisionId'] ||
        recipe['recipeId'] != detail['recipeId']) {
      throw StateError('Restored preparation pin differs.');
    }
    if (detail['latestCorrectionNumber'] == 2 &&
        (detail['actualDeclaredBatchCount'] != 2 ||
            detail['effectiveDeclaredBatchCount'] != 0 ||
            detail['status'] != 'completed')) {
      throw StateError('Restored zero correction evidence differs.');
    }
    if (otherEmployee != null) {
      for (final instruction in [false, true]) {
        try {
          if (instruction) {
            await app.recipe(otherEmployee, location, id);
          } else {
            await app.detail(otherEmployee, location, id);
          }
          throw StateError(
            'Restored foreign Employee preparation access accepted.',
          );
        } on PlatformFailure catch (e) {
          if (e.status != 404) rethrow;
        }
      }
    }
  }
  final receipts = await db.pool.execute(
    'SELECT batch_id::text,kind,actor_id::text,payload,result FROM ${db.schema}.production_preparation_batch_commands ORDER BY operation_id',
  );
  if (receipts.length != 11) {
    throw StateError('Restored preparation receipts missing.');
  }
  for (final r in receipts) {
    final actor = r[2] == manager.id ? manager : employee,
        kind = r[1] as String;
    final replay = await app.command(
      actor,
      location,
      kind == 'open' ? null : r[0] as String,
      kind,
      Map<String, dynamic>.from(r[3] as Map),
      self: kind != 'manager_cancel' && kind != 'count_correct',
    );
    final original = Map<String, dynamic>.from(r[4] as Map);
    if (replay['replayed'] != true) {
      throw StateError('Restored preparation receipt was not replayed.');
    }
    replay.remove('replayed');
    original.remove('replayed');
    if (jsonEncode(replay) != jsonEncode(original)) {
      throw StateError('Restored preparation replay differs.');
    }
  }
  if (jsonEncode(before) != jsonEncode(await fingerprint())) {
    throw StateError('Preparation recovery probe changed evidence.');
  }
}

Future<void> verifyPreparationGrants(
  Connection owner,
  String schema,
  String runtime,
) async {
  for (final table in [
    'production_preparation_batches',
    'production_preparation_batch_commands',
    'production_preparation_batch_count_corrections',
  ]) {
    final result = await owner.execute(
      Sql.named(
        'SELECT has_table_privilege(@role,@table,\'DELETE\'), has_table_privilege(@role,@table,\'TRUNCATE\'), has_table_privilege(@role,@table,\'UPDATE\')',
      ),
      parameters: {'role': runtime, 'table': '$schema.$table'},
    );
    if (result.single.any((v) => v == true)) {
      throw StateError('Preparation runtime table grants too broad.');
    }
  }
}
