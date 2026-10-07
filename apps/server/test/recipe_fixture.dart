import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

const recipeRoot = '/production/manage/recipes',
    recipePublic = '/production/recipes';
Map<String, dynamic> recipeArticleInput(
  String sku, {
  String unit = 'kg',
  String? id,
  String name = 'Ingredient',
}) => {
  'id': id ?? newUuid(),
  'sku': sku,
  'name': name,
  'unit': unit,
  'barcode': null,
  'description': null,
};
Future<RecipeRevisionResultDto> createRecipe(
  MerchandisingFixture f,
  String produced,
) async => RecipeRevisionResultDto.fromJson(
  (await f.call(
    'POST',
    recipeRoot,
    expected: 201,
    body: CreateRecipeRequest(newUuid(), newUuid(), produced).toJson(),
  )).body,
);
Future<RecipeDetailDto> recipeDetail(MerchandisingFixture f, String id) async =>
    RecipeDetailDto.fromJson((await f.call('GET', '$recipeRoot/$id')).body);
Future<RecipeRevisionResultDto> saveRecipe(
  MerchandisingFixture f,
  RecipeDetailDto d,
  List<RecipeIngredientInput> ingredients, {
  String batch = 'one 30 × 40 cm tray',
  String preparation = 'Mix <script>literal</script>\n# plain text',
}) async => RecipeRevisionResultDto.fromJson(
  (await f.call(
    'POST',
    '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/edit',
    body: SaveRecipeRequest(
      d.recipe.version,
      RecipeDraftContent(
        batchDescription: batch,
        preparation: preparation,
        ingredients: ingredients,
      ),
    ).toJson(),
  )).body,
);
Future<RecipePublicationDto> publishRecipe(
  MerchandisingFixture f,
  RecipeDetailDto d, {
  String? operation,
}) async => RecipePublicationDto.fromJson(
  (await f.call(
    'POST',
    '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
    body: PublishRecipeRequest(
      operation ?? newUuid(),
      d.recipe.version,
    ).toJson(),
  )).body,
);
Future<RecipeRevisionResultDto> replacementRecipe(
  MerchandisingFixture f,
  RecipeDetailDto d,
) async => RecipeRevisionResultDto.fromJson(
  (await f.call(
    'POST',
    '$recipeRoot/${d.recipe.id}/revisions',
    expected: 201,
    body: NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
  )).body,
);
Future<int> recipeAudits(MerchandisingFixture f) async =>
    (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action LIKE \'production.recipe.%\'',
        )).single.first
        as int;
Future<ArticleDto> editRecipeArticle(
  MerchandisingFixture f,
  ArticleDto a, {
  String? unit,
  String? name,
}) async => ArticleDto.fromJson(
  (await f.call(
    'POST',
    '/articles/${a.id}/edit',
    body: {
      'expectedVersion': a.version,
      'sku': a.sku,
      'barcode': a.barcode,
      'name': name ?? a.name,
      'description': a.description,
      'unit': unit ?? a.unit,
    },
  )).body,
);
Future<List<Object?>> recipeEvidence(
  MerchandisingFixture f, {
  bool stock = false,
}) async => [
  for (final table
      in stock
          ? [
              'stock_levels',
              'stock_movements',
              'stock_counts',
              'stock_count_lines',
              'stock_count_rounds',
              'stock_count_observations',
              'stock_count_commands',
            ]
          : [
              'production_recipes',
              'production_recipe_revisions',
              'production_recipe_ingredients',
              'audit_entries',
            ])
    (await f.owner.execute(
      'SELECT md5(string_agg(to_jsonb(t)::text,\'\' ORDER BY to_jsonb(t)::text)) FROM "${f.schema}".$table t',
    )).single.first,
];

/// Nonempty P4.8 evidence written exclusively through authorized business APIs.
Future<StockLevelDto> seedRecipeCountEvidence(MerchandisingFixture f) async {
  final account = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': account,
      'username': 'recipe_counter',
      'password': merchandisingTestPassword,
      'locationId': merchandisingTestLocation,
      'role': 'employee',
    },
  );
  final employee = newUuid();
  await f.call(
    'POST',
    '/employees',
    expected: 201,
    body: {
      'id': employee,
      'displayName': 'Recipe preservation counter',
      'locationId': merchandisingTestLocation,
    },
  );
  await f.call(
    'POST',
    '/employees/$employee/account-link',
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': account,
      'expectedEmployeeVersion': 1,
      'expectedAccountVersion': 1,
    },
  );
  final token = await f.login('recipe_counter');
  final a = await f.openStock(
    (await f.stockArticle(sku: 'PRESERVE-A')).id,
    quantity: '12.250',
  );
  final b = await f.openStock(
    (await f.stockArticle(sku: 'PRESERVE-B')).id,
    quantity: '5',
  );
  final root = '/locations/$merchandisingTestLocation/stock-counts';
  var count = (await f.call(
    'POST',
    root,
    expected: 201,
    body: {
      'operationId': newUuid(),
      'id': newUuid(),
      'employeeId': employee,
      'stockLevelIds': [a.id, b.id],
      'purpose': 'P4.9 preservation evidence',
      'precedingCountId': null,
    },
  )).body;
  final id = count['id'] as String;
  List<Map<String, dynamic>> lines() =>
      (count['lines'] as List).cast<Map<String, dynamic>>();
  Future<void> observe(int index, String quantity) async {
    final line = lines()[index];
    await f.call(
      'POST',
      '/me/stock-counts/$id/lines/${line['id']}/observations',
      token: token,
      body: {
        'operationId': newUuid(),
        'expectedVersion': count['version'],
        'roundId': line['round']['id'],
        'quantity': quantity,
        'note': null,
      },
    );
    count = (await f.call('GET', '$root/$id')).body;
  }

  await observe(0, '11.250');
  await observe(1, '5');
  count = (await f.call(
    'POST',
    '$root/$id/recount',
    body: {
      'operationId': newUuid(),
      'expectedVersion': count['version'],
      'lineIds': [lines().first['id']],
      'reason': 'Preserve superseded round',
    },
  )).body;
  await observe(0, '10.250');
  count = (await f.call(
    'POST',
    '$root/$id/approve',
    body: {'operationId': newUuid(), 'expectedVersion': count['version']},
  )).body;
  expect(count['status'], 'approved');
  expect(lines().map((l) => l['outcome']['discrepancy']), ['-2', '0']);
  expect(lines().first['outcome']['observationId'], isNotNull);
  expect(lines().last['outcome']['movementId'], isNull);
  final level = await f.level(a.id);
  expect(level.quantity, '10.25');
  expect(level.version, 2);
  final correction = (await f.movements(a.id)).items.first;
  expect(correction.kind, 'count_correction');
  expect(correction.countId, id);
  expect(correction.countObservationId, isNotNull);
  for (final table in [
    'stock_levels',
    'stock_movements',
    'stock_counts',
    'stock_count_lines',
    'stock_count_rounds',
    'stock_count_observations',
    'stock_count_commands',
  ]) {
    expect(
      (await f.owner.execute(
        'SELECT count(*) FROM "${f.schema}".$table',
      )).single.first,
      greaterThan(0),
      reason: table,
    );
  }
  expect(
    (await f.owner.execute(
      'SELECT count(*) FROM "${f.schema}".stock_count_observations WHERE recorded_by=\'$account\' AND employee_id=\'$employee\'',
    )).single.first,
    3,
  );
  return level;
}

Future<Map<String, Object?>> recipeStockHashes(
  MerchandisingFixture f,
) async => {
  for (final table in [
    'stock_levels',
    'stock_movements',
    'stock_counts',
    'stock_count_lines',
    'stock_count_rounds',
    'stock_count_observations',
    'stock_count_commands',
  ])
    table: (await f.owner.execute(
      'SELECT count(*), md5(string_agg(to_jsonb(t)::text,\'\' ORDER BY to_jsonb(t)::text)) FROM "${f.schema}".$table t',
    )).single.toList(),
};
Future<List<MerchandisingReply>> orderedRecipeCommands(
  MerchandisingFixture f,
  Future<MerchandisingReply> Function() first,
  Future<MerchandisingReply> Function() second,
) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holding = f.database.runAuthorized(
    f.adminPrincipal,
    'production.recipes.manage',
    (tx, actor) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  Future<void> queued(int expected) async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < const Duration(seconds: 10)) {
      final rows = await f.owner.execute(
        Sql.named(
          "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
        ),
        parameters: {
          'key': 'storeos_platform:${f.schema}:$merchandisingTestCompany',
        },
      );
      if (rows.single.first == expected) return;
    }
    fail('Expected observable queued Company transactions.');
  }

  try {
    final a = first();
    await queued(1);
    final b = second();
    await queued(2);
    release.complete();
    await holding;
    return await Future.wait([a, b]);
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}
