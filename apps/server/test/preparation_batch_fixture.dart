import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'recipe_fixture.dart';

String get batchSelf =>
    '/production/self/locations/$merchandisingTestLocation/batches';
String get batchManage =>
    '/production/manage/locations/$merchandisingTestLocation/batches';

class BatchWorker {
  const BatchWorker(this.account, this.employee, this.token);
  final String account, employee, token;
}

Future<BatchWorker> batchWorker(MerchandisingFixture f, String name) async {
  final account = newUuid(), employee = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': account,
      'username': name,
      'password': merchandisingTestPassword,
      'locationId': merchandisingTestLocation,
      'role': 'employee',
    },
  );
  await f.call(
    'POST',
    '/employees',
    expected: 201,
    body: {
      'id': employee,
      'displayName': name,
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
  return BatchWorker(account, employee, await f.login(name));
}

class BatchRecipe {
  BatchRecipe(this.produced, this.ingredient, this.detail);
  final ArticleDto produced, ingredient;
  RecipeDetailDto detail;
}

Future<BatchRecipe> batchRecipe(MerchandisingFixture f) async {
  final p = await f.stockArticle(sku: 'BATCH-P', unit: 'tray'),
      i = await f.article(recipeArticleInput('BATCH-I'));
  var d = (await createRecipe(f, p.id)).detail;
  d = (await saveRecipe(
    f,
    d,
    [RecipeIngredientInput(newUuid(), i.id, '1.250', reselect: true)],
    preparation:
        'Mix <script>globalThis.preparationInjected=true</script>\n<a href="https://invalid.example/p410">literal</a>\n# plain ä 😀',
  )).detail;
  await publishRecipe(f, d);
  return BatchRecipe(p, i, await recipeDetail(f, d.recipe.id));
}

Map<String, dynamic> batchOpening(BatchRecipe recipe, {int? planned = 3}) => {
  'batchId': newUuid(),
  'operationId': newUuid(),
  'recipeId': recipe.detail.recipe.id,
  'revisionId': recipe.detail.currentPublished!.id,
  'plannedDeclaredBatchCount': planned,
};
Map<String, dynamic> batchComplete({int count = 2}) => {
  'operationId': newUuid(),
  'expectedVersion': 1,
  'actualDeclaredBatchCount': count,
  'note': 'Literal <script> completion 😀',
};
Map<String, dynamic> batchCancel() => {
  'operationId': newUuid(),
  'expectedVersion': 1,
  'reason': 'Operator cancelled <script> 😀',
};
Map<String, dynamic> batchCorrection({int latest = 0, int replacement = 1}) => {
  'operationId': newUuid(),
  'expectedVersion': 2,
  'expectedLatestCorrectionNumber': latest,
  'replacementDeclaredBatchCount': replacement,
  'reason': 'Reasoned correction <script> 😀',
};
Future<List<Object?>> batchEvidence(MerchandisingFixture f) async => [
  for (final table in [
    'production_preparation_batches',
    'production_preparation_batch_commands',
    'production_preparation_batch_count_corrections',
    'audit_entries',
  ])
    (await f.owner.execute(
      'SELECT md5(string_agg(to_jsonb(t)::text,\'\' ORDER BY to_jsonb(t)::text)) FROM "${f.schema}".$table t',
    )).single.first,
];
Future<List<MerchandisingReply>> orderedBatchCommands(
  MerchandisingFixture f,
  Future<MerchandisingReply> Function() first,
  Future<MerchandisingReply> Function() second,
) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holding = f.database.runAuthorized(
    f.adminPrincipal,
    'production.batches.manage',
    (tx, actor) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  Future<void> queued(int n) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10)) {
      final r = await f.owner.execute(
        Sql.named(
          "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
        ),
        parameters: {
          'key': 'storeos_platform:${f.schema}:$merchandisingTestCompany',
        },
      );
      if (r.single.first == n) return;
    }
    fail('Expected $n queued Company transactions.');
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
