import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/production/recipe_service.dart';
import 'knowledge_acceptance.dart';

/// All business evidence is created through the normal authorized API.
Future<void> seedRecipeCompositions(KnowledgeAcceptanceRequest request) async {
  const root = '/api/v1/platform/production/manage/recipes';
  Future<ArticleDto> article(String sku, String unit) async =>
      ArticleDto.fromJson(
        await request('POST', '/api/v1/platform/articles', {
          'id': newUuid(),
          'sku': sku,
          'barcode': null,
          'name': 'Recipe ä 😀 <script>literal</script> $sku',
          'description': null,
          'unit': unit,
        }, 201),
      );
  final ingredients = [
    await article('RECIPE-ING-1', 'kg'),
    await article('RECIPE-ING-2', 'L'),
  ];
  for (var n = 0; n < 3; n++) {
    final produced = await article('RECIPE-PRODUCED-$n', 'Stk');
    final id = newUuid(), revision = newUuid(), op = newUuid();
    var result = RecipeRevisionResultDto.fromJson(
      await request(
        'POST',
        root,
        CreateRecipeRequest(id, revision, produced.id).toJson(),
        201,
      ),
    );
    final input = RecipeDraftContent(
      batchDescription: 'One declared tray ä 😀',
      preparation: 'Mix <script>plain</script>\nNo yield or conversion.',
      ingredients: [
        RecipeIngredientInput(
          newUuid(),
          ingredients[0].id,
          '999999999999.999',
          reselect: true,
        ),
        RecipeIngredientInput(
          newUuid(),
          ingredients[1].id,
          '0.001',
          reselect: true,
        ),
      ],
    );
    result = RecipeRevisionResultDto.fromJson(
      await request(
        'POST',
        '$root/$id/revisions/$revision/edit',
        SaveRecipeRequest(result.detail.recipe.version, input).toJson(),
        200,
      ),
    );
    final expected = result.detail.recipe.version;
    await request(
      'POST',
      '$root/$id/revisions/$revision/publish',
      PublishRecipeRequest(op, expected).toJson(),
      200,
    );
    if (n < 2) {
      var detail = RecipeDetailDto.fromJson(
        await request('GET', '$root/$id', null, 200),
      );
      final replacement = newUuid();
      result = RecipeRevisionResultDto.fromJson(
        await request(
          'POST',
          '$root/$id/revisions',
          NewRecipeDraftRequest(replacement, detail.recipe.version).toJson(),
          201,
        ),
      );
      if (n == 0) {
        await request(
          'POST',
          '$root/$id/revisions/$replacement/publish',
          PublishRecipeRequest(
            newUuid(),
            result.detail.recipe.version,
          ).toJson(),
          200,
        );
        detail = RecipeDetailDto.fromJson(
          await request('GET', '$root/$id', null, 200),
        );
        final discarded = newUuid();
        result = RecipeRevisionResultDto.fromJson(
          await request(
            'POST',
            '$root/$id/revisions',
            NewRecipeDraftRequest(discarded, detail.recipe.version).toJson(),
            201,
          ),
        );
        await request(
          'POST',
          '$root/$id/revisions/$discarded/discard',
          RecipeVersionRequest(result.detail.recipe.version).toJson(),
          200,
        );
        detail = RecipeDetailDto.fromJson(
          await request('GET', '$root/$id', null, 200),
        );
        await request(
          'POST',
          '$root/$id/revisions',
          NewRecipeDraftRequest(newUuid(), detail.recipe.version).toJson(),
          201,
        );
      } else {
        await request(
          'POST',
          '$root/$id/retire',
          RecipeVersionRequest(result.detail.recipe.version).toJson(),
          200,
        );
      }
    } else {
      await request(
        'POST',
        '/api/v1/platform/articles/${produced.id}/deactivate',
        {'expectedVersion': produced.version},
        200,
      );
    }
    final replay = RecipePublicationDto.fromJson(
      await request(
        'POST',
        '$root/$id/revisions/$revision/publish',
        PublishRecipeRequest(op, expected).toJson(),
        200,
      ),
    );
    if (!replay.replayed || replay.revision.id != revision) {
      throw StateError('Recipe late replay evidence differs.');
    }
  }
}

Future<void> verifyRecipeEvidence(
  Connection owner,
  String schema,
  String runtime,
) async {
  final s = quotedSchema(schema), role = quotedSchema(runtime);
  final rows = await owner.execute(
    'SELECT status,count(*) FROM $s.production_recipe_revisions GROUP BY status',
  );
  final states = {for (final row in rows) row[0] as String: row[1] as int};
  if (states['published'] != 4 ||
      states['discarded'] != 2 ||
      states['draft'] != 1) {
    throw StateError('Recipe retained states incomplete.');
  }
  final invalid = await owner.execute(
    "SELECT count(*) FROM $s.production_recipes a LEFT JOIN $s.production_recipe_revisions p ON p.id=a.current_published_revision_id AND p.recipe_id=a.id AND p.company_id=a.company_id AND p.status='published' LEFT JOIN $s.production_recipe_revisions d ON d.id=a.active_draft_revision_id AND d.recipe_id=a.id AND d.company_id=a.company_id AND d.status='draft' WHERE (a.current_published_revision_id IS NOT NULL AND p.id IS NULL) OR (a.active_draft_revision_id IS NOT NULL AND d.id IS NULL) OR (a.status='retired' AND a.active_draft_revision_id IS NOT NULL)",
  );
  if (invalid.single.first != 0) {
    throw StateError('Recipe pointer ownership differs.');
  }
  Future<void> denied(String sql, String state) async {
    try {
      await owner.runTx((tx) async {
        await tx.execute('SET LOCAL ROLE $role');
        await tx.execute(sql);
      });
    } on ServerException catch (e) {
      if (e.code == state) return;
      rethrow;
    }
    throw StateError('Recipe runtime protection failed.');
  }

  for (final state in ['published', 'discarded']) {
    await denied(
      "UPDATE $s.production_recipe_revisions SET preparation='changed' WHERE id=(SELECT id FROM $s.production_recipe_revisions WHERE status='$state' LIMIT 1)",
      '23514',
    );
    await denied(
      "DELETE FROM $s.production_recipe_ingredients WHERE revision_id=(SELECT id FROM $s.production_recipe_revisions WHERE status='$state' LIMIT 1)",
      '23514',
    );
  }
  for (final table in ['production_recipes', 'production_recipe_revisions']) {
    await denied('DELETE FROM $s.$table', '42501');
  }
  for (final table in [
    'production_recipes',
    'production_recipe_revisions',
    'production_recipe_ingredients',
  ]) {
    await denied('TRUNCATE $s.$table CASCADE', '42501');
  }
}

Future<void> verifyRestoredRecipes(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal employee,
) async {
  final app = RecipeService(db);
  final before = await db.pool.execute(
    "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.audit_entries t",
  );
  final managed = RecipePage.fromJson(
    await app.listManaged(manager),
    RecipeDetailDto.fromJson,
  );
  final seeded = managed.items
      .where(
        (d) => d.currentProduced.article.sku.startsWith('RECIPE-PRODUCED-'),
      )
      .toList();
  if (seeded.length != 3) {
    throw StateError('Restored Recipe history missing.');
  }
  final visible = RecipePage.fromJson(
    await app.listPublished(employee, q: 'RECIPE-PRODUCED-'),
    PublishedRecipeDto.fromJson,
  );
  if (visible.items.length != 1 || visible.items.single.revisionNumber != 2) {
    throw StateError('Restored Recipe employee visibility differs.');
  }
  Future<void> denied(Future<Map<String, dynamic>> action, int status) async {
    try {
      await action;
    } on PlatformFailure catch (e) {
      if (e.status == status) return;
      rethrow;
    }
    throw StateError('Restored unauthorized Recipe access accepted.');
  }

  for (final d in seeded) {
    final history = RecipePage.fromJson(
      await app.history(manager, d.recipe.id),
      RecipeRevisionDto.fromJson,
    );
    final original = history.items.singleWhere((r) => r.revisionNumber == 1);
    final exact = RecipeRevisionViewDto.fromJson(
      await app.revision(manager, d.recipe.id, original.id),
    );
    if (exact.revision.toJson().toString() != original.toJson().toString() ||
        original.content.ingredients[0].quantity != '999999999999.999' ||
        original.content.ingredients[1].quantity != '0.001') {
      throw StateError('Restored frozen Recipe composition differs.');
    }
    final replay = RecipePublicationDto.fromJson(
      await app.publish(
        manager,
        d.recipe.id,
        original.id,
        PublishRecipeRequest(
          original.publishOperationId!,
          original.publishExpectedVersion!,
        ).toJson(),
      ),
    );
    if (!replay.replayed ||
        replay.revision.toJson().toString() != original.toJson().toString()) {
      throw StateError('Restored Recipe replay differs.');
    }
    await denied(app.detail(employee, d.recipe.id), 403);
    await denied(app.revision(employee, d.recipe.id, original.id), 403);
    await denied(
      app.publish(
        employee,
        d.recipe.id,
        original.id,
        PublishRecipeRequest(
          original.publishOperationId!,
          original.publishExpectedVersion!,
        ).toJson(),
      ),
      403,
    );
    if (d.currentProduced.article.sku != 'RECIPE-PRODUCED-0') {
      await denied(app.readPublished(employee, d.recipe.id), 404);
    }
  }
  final after = await db.pool.execute(
    "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.audit_entries t",
  );
  if (before.single.first != after.single.first) {
    throw StateError('Restored Recipe reads/replay changed audit.');
  }
}
