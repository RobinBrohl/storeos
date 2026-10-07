import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/production/recipe_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'recipe_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'task_planogram_fixture.dart';

final _skip = merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';
Future<RecipeDetailDto> _saved(MerchandisingFixture f) async {
  final p = await f.article(
        recipeArticleInput('P', unit: 'tray', name: 'Produced'),
      ),
      i = await f.article(recipeArticleInput('I'));
  return (await saveRecipe(f, (await createRecipe(f, p.id)).detail, [
    RecipeIngredientInput(newUuid(), i.id, '1.250', reselect: true),
  ])).detail;
}

void main() {
  test(
    'operation-specific business errors match Recipe OpenAPI metadata',
    () => withMerchandisingFixture((f) async {
      final paths =
          (jsonDecode(
                    File(
                      '../../packages/api_contracts/platform.openapi.json',
                    ).readAsStringSync(),
                  )
                  as Map)['paths']
              as Map;
      Future<void> probe(
        String route,
        String documented,
        int status,
        String code,
        Map<String, dynamic> body,
      ) async {
        final before = await recipeEvidence(f);
        final response = await f.call(
          'POST',
          route,
          expected: status,
          body: body,
        );
        expect(response.body['code'], code);
        final responses =
            ((paths['/api/v1/platform$documented'] as Map)['post']
                    as Map)['responses']
                as Map;
        expect((responses['$status'] as Map)['x-error-codes'], contains(code));
        expect(await recipeEvidence(f), before);
      }

      final produced = await f.article(recipeArticleInput('PARITY-P'));
      var d = (await createRecipe(f, produced.id)).detail;
      final id = d.recipe.id, revision = d.draft!.id;
      await probe(
        recipeRoot,
        recipeRoot,
        409,
        'already_exists',
        CreateRecipeRequest(newUuid(), newUuid(), produced.id).toJson(),
      );
      await probe(
        '$recipeRoot/$id/revisions',
        '$recipeRoot/{recipeId}/revisions',
        409,
        'draft_exists',
        NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      await probe(
        '$recipeRoot/$id/revisions/$revision/publish',
        '$recipeRoot/{recipeId}/revisions/{revisionId}/publish',
        422,
        'recipe_not_publishable',
        PublishRecipeRequest(newUuid(), d.recipe.version).toJson(),
      );
      await probe(
        '$recipeRoot/$id/retire',
        '$recipeRoot/{recipeId}/retire',
        409,
        'stale_version',
        RecipeVersionRequest(d.recipe.version + 1).toJson(),
      );
      await f.call(
        'POST',
        '$recipeRoot/$id/revisions/$revision/discard',
        body: RecipeVersionRequest(d.recipe.version).toJson(),
      );
      d = await recipeDetail(f, id);
      await f.call(
        'POST',
        '/articles/${produced.id}/deactivate',
        body: {'expectedVersion': produced.version},
      );
      await probe(
        '$recipeRoot/$id/revisions',
        '$recipeRoot/{recipeId}/revisions',
        422,
        'article_unavailable',
        NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      await f.call(
        'POST',
        '$recipeRoot/$id/retire',
        body: RecipeVersionRequest(d.recipe.version).toJson(),
      );
      d = await recipeDetail(f, id);
      await probe(
        '$recipeRoot/$id/revisions',
        '$recipeRoot/{recipeId}/revisions',
        409,
        'invalid_lifecycle',
        NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      d = await _saved(f);
      final op = newUuid();
      await publishRecipe(f, d, operation: op);
      await probe(
        '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
        '$recipeRoot/{recipeId}/revisions/{revisionId}/publish',
        409,
        'operation_conflict',
        PublishRecipeRequest(op, d.recipe.version + 1).toJson(),
      );
    }),
    skip: _skip,
  );
  test(
    'Recipe raw write duplicates reject decoded names with zero effects',
    () => withMerchandisingFixture((f) async {
      final d = await _saved(f), id = d.recipe.id, revision = d.draft!.id;
      final p = await f.article(recipeArticleInput('RAW-P'));
      final i = await f.article(recipeArticleInput('RAW-I'));
      final create = jsonEncode(
        CreateRecipeRequest(newUuid(), newUuid(), p.id).toJson(),
      );
      final edit = jsonEncode(
        SaveRecipeRequest(d.recipe.version, d.draft!.content.editable).toJson(),
      );
      final publish = jsonEncode(
        PublishRecipeRequest(newUuid(), d.recipe.version).toJson(),
      );
      final drafts = jsonEncode(
        NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      final version = jsonEncode(
        RecipeVersionRequest(d.recipe.version).toJson(),
      );
      String duplicate(String json, String key, String value) =>
          json.replaceFirst('"$key":', '"$key":$value,"$key":');
      final probes = <(String, String)>[
        (recipeRoot, duplicate(create, 'producedArticleId', jsonEncode(p.id))),
        (
          '$recipeRoot/$id/revisions',
          duplicate(drafts, 'expectedVersion', '1'),
        ),
        ('$recipeRoot/$id/retire', duplicate(version, 'expectedVersion', '1')),
        (
          '$recipeRoot/$id/revisions/$revision/discard',
          duplicate(version, 'expectedVersion', '1'),
        ),
        (
          '$recipeRoot/$id/revisions/$revision/edit',
          duplicate(edit, 'expectedVersion', '1'),
        ),
        (
          '$recipeRoot/$id/revisions/$revision/publish',
          duplicate(publish, 'operationId', jsonEncode(newUuid())),
        ),
        (
          '$recipeRoot/$id/revisions/$revision/edit',
          duplicate(edit, 'articleId', jsonEncode(i.id)),
        ),
        (
          '$recipeRoot/$id/revisions/$revision/edit',
          duplicate(edit, 'quantity', '"2"'),
        ),
        (
          '$recipeRoot/$id/revisions/$revision/edit',
          edit.replaceFirst('"quantity":', r'"\u0071uantity":"2","quantity":'),
        ),
      ];
      for (final (route, raw) in probes) {
        final before = await recipeEvidence(f);
        final response = await f.call('POST', route, raw: raw, expected: 400);
        expect(response.body, {
          'code': 'invalid_json',
          'message': 'Expected a JSON object.',
        });
        expect(response.correlation, isNotEmpty);
        expect(await recipeEvidence(f), before);
      }
      for (final (raw, code) in [
        ('{', 'invalid_json'),
        ('{"unknown":1}', 'invalid_request'),
      ]) {
        final before = await recipeEvidence(f);
        expect(
          (await f.call(
            'POST',
            recipeRoot,
            raw: raw,
            expected: 400,
          )).body['code'],
          code,
        );
        expect(await recipeEvidence(f), before);
      }
      final saved = await saveRecipe(f, d, [
        ...d.draft!.content.editable.ingredients,
        RecipeIngredientInput(newUuid(), i.id, '1.250', reselect: true),
      ], preparation: 'quantity quantity {"quantity":"same value"}');
      expect(saved.detail.draft!.content.ingredients, hasLength(2));
      // Same member names across separate ingredient objects are valid raw HTTP.
      await f.call(
        'POST',
        '$recipeRoot/$id/revisions/$revision/edit',
        raw: jsonEncode(
          SaveRecipeRequest(
            saved.detail.recipe.version,
            saved.detail.draft!.content.editable,
          ).toJson(),
        ),
      );
    }),
    skip: _skip,
  );
  test(
    'initial discard recovers as empty revision 2 and preserves discarded evidence',
    () => withMerchandisingFixture((f) async {
      await f.account('recovery_reader');
      final employee = await f.login('recovery_reader');
      var produced = await f.article(
        recipeArticleInput('RECOVERY-P', unit: 'tray'),
      );
      final ingredient = await f.article(recipeArticleInput('RECOVERY-I'));
      var d = (await createRecipe(f, produced.id)).detail;
      final id = d.recipe.id, first = d.draft!.id;
      final discarded = RecipeRevisionResultDto.fromJson(
        (await f.call(
          'POST',
          '$recipeRoot/$id/revisions/$first/discard',
          body: RecipeVersionRequest(d.recipe.version).toJson(),
        )).body,
      ).revision;
      d = await recipeDetail(f, id);
      expect(d.recipe.status, 'active');
      expect(d.draft, isNull);
      expect(d.currentPublished, isNull);
      final beforeRejected = await recipeEvidence(f);
      await f.call(
        'POST',
        '$recipeRoot/$id/revisions',
        token: employee,
        expected: 403,
        body: NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      await f.call(
        'POST',
        '$recipeRoot/${newUuid()}/revisions',
        expected: 404,
        body: NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      expect(await recipeEvidence(f), beforeRejected);
      produced = await editRecipeArticle(
        f,
        produced,
        name: 'Recovery produced',
      );
      d = (await replacementRecipe(f, d)).detail;
      expect(d.recipe.id, id);
      expect(d.draft!.id, isNot(first));
      expect(d.draft!.revisionNumber, 2);
      expect(d.draft!.content.produced.name, 'Recovery produced');
      expect(d.draft!.content.batchDescription, '');
      expect(d.draft!.content.preparation, '');
      expect(d.draft!.content.ingredients, isEmpty);
      await f.call(
        'POST',
        '$recipeRoot/$id/revisions/$first/edit',
        expected: 409,
        body: SaveRecipeRequest(
          d.recipe.version,
          d.draft!.content.editable,
        ).toJson(),
      );
      d = (await saveRecipe(f, d, [
        RecipeIngredientInput(
          newUuid(),
          ingredient.id,
          '1.250',
          reselect: true,
        ),
      ])).detail;
      await publishRecipe(f, d);
      final visible = PublishedRecipeDto.fromJson(
        (await f.call('GET', '$recipePublic/$id', token: employee)).body,
      );
      expect(visible.revisionNumber, 2);
      expect(visible.revisionId, d.draft!.id);
      expect(
        (await f.call(
          'GET',
          '$recipeRoot/$id/revisions/$first',
        )).body['revision'],
        discarded.toJson(),
      );
    }),
    skip: _skip,
  );
  for (final pair in ['recovery/recovery', 'recovery/retire']) {
    for (final reverse in [false, true]) {
      test(
        'observable $pair initial recovery ${reverse ? 'reverse' : 'forward'}',
        () => withMerchandisingFixture((f) async {
          final produced = await f.article(recipeArticleInput('RECOVERY-RACE'));
          var d = (await createRecipe(f, produced.id)).detail;
          final id = d.recipe.id, first = d.draft!.id;
          final discarded = (await f.call(
            'POST',
            '$recipeRoot/$id/revisions/$first/discard',
            body: RecipeVersionRequest(d.recipe.version).toJson(),
          )).body['revision'];
          d = await recipeDetail(f, id);
          final version = d.recipe.version;
          Future<MerchandisingReply> action(String kind) => f.call(
            'POST',
            kind == 'recovery'
                ? '$recipeRoot/$id/revisions'
                : '$recipeRoot/$id/retire',
            expected: null,
            body: kind == 'recovery'
                ? NewRecipeDraftRequest(newUuid(), version).toJson()
                : RecipeVersionRequest(version).toJson(),
          );
          final parts = pair.split('/');
          final firstKind = parts[reverse ? 1 : 0];
          final replies = await orderedRecipeCommands(
            f,
            () => action(firstKind),
            () => action(parts[reverse ? 0 : 1]),
          );
          expect(replies.first.status, firstKind == 'recovery' ? 201 : 200);
          expect(replies.last.status, 409);
          expect(replies.last.body['code'], 'stale_version');
          final result = await recipeDetail(f, id);
          expect(result.recipe.version, version + 1);
          expect(
            result.recipe.status,
            firstKind == 'retire' ? 'retired' : 'active',
          );
          expect(
            result.draft?.revisionNumber,
            firstKind == 'retire' ? null : 2,
          );
          final history =
              (await f.call('GET', '$recipeRoot/$id/revisions')).body['items']
                  as List;
          expect(history.length, firstKind == 'retire' ? 1 : 2);
          expect(history.last, discarded);
        }),
        skip: _skip,
      );
    }
  }
  test(
    'complete lifecycle, exact frozen reference, unit conflict, restart replay, retirement and Stock isolation',
    () => withMerchandisingFixture((f) async {
      await f.account('recipe_employee');
      final employee = await f.login('recipe_employee');
      final p = await f.article(
            recipeArticleInput('P', unit: 'tray', name: 'Produced'),
          ),
          i1 = await f.article(recipeArticleInput('I1', name: 'Flour'));
      var i2 = await f.article(recipeArticleInput('I2', name: 'Salt'));
      final stock = await seedRecipeCountEvidence(f);
      await createRecipe(
        f,
        i2.id,
      ); // Recipe-bearing Article remains an ordinary ingredient.
      final stockBefore = await recipeEvidence(f, stock: true);
      final stockHashes = await recipeStockHashes(f);
      print(
        'Recipe lifecycle Count evidence before: ${jsonEncode(stockHashes)}',
      );
      var d = (await createRecipe(f, p.id)).detail;
      final recipe = d.recipe.id, r1 = d.draft!.id;
      expect(recipe, isNot(p.id));
      expect(d.recipe.version, 1);
      expect(d.draft!.revisionNumber, 1);
      await f.call(
        'GET',
        '$recipePublic/$recipe',
        token: employee,
        expected: 404,
      );
      final line1 = newUuid(), line2 = newUuid();
      d = (await saveRecipe(f, d, [
        RecipeIngredientInput(line1, i1.id, '1.250', reselect: true),
        RecipeIngredientInput(line2, i2.id, '0.050', reselect: true),
      ])).detail;
      final op1 = newUuid(), v1 = d.recipe.version;
      final published1 = await publishRecipe(f, d, operation: op1);
      expect(published1.revision.content.ingredients.map((i) => i.quantity), [
        '1.250',
        '0.050',
      ]);
      final beforeRead = await recipeEvidence(f);
      final visible = PublishedRecipeDto.fromJson(
        (await f.call('GET', '$recipePublic/$recipe', token: employee)).body,
      );
      expect(visible.content.batchDescription, 'one 30 × 40 cm tray');
      expect(visible.revisionId, r1);
      expect(await recipeEvidence(f), beforeRead);
      d = (await replacementRecipe(f, await recipeDetail(f, recipe))).detail;
      expect(d.draft!.content.toJson(), published1.revision.content.toJson());
      d = (await saveRecipe(f, d, [
        RecipeIngredientInput(line1, i1.id, '1.250'),
        RecipeIngredientInput(line2, i2.id, '0.075'),
      ])).detail;
      expect(
        (await f.call(
          'GET',
          '$recipePublic/$recipe',
          token: employee,
        )).body['revisionId'],
        r1,
      );
      i2 = await editRecipeArticle(f, i2, unit: 'g', name: 'New Salt');
      final beforeFailed = await recipeEvidence(f);
      final conflict = await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/${d.draft!.id}/publish',
        expected: 422,
        body: PublishRecipeRequest(newUuid(), d.recipe.version).toJson(),
      );
      expect(conflict.body['code'], 'ingredient_unit_changed');
      expect(await recipeEvidence(f), beforeFailed);
      d = (await saveRecipe(f, d, [
        RecipeIngredientInput(line1, i1.id, '1.250'),
        RecipeIngredientInput(line2, i2.id, '0.075'),
      ])).detail;
      expect(d.draft!.content.ingredients.last.article.unit, 'kg');
      expect(d.draft!.content.ingredients.last.article.name, 'Salt');
      d = (await saveRecipe(f, d, [
        RecipeIngredientInput(line1, i1.id, '1.250'),
        RecipeIngredientInput(line2, i2.id, '0.075', reselect: true),
      ])).detail;
      expect(d.draft!.content.ingredients.last.article.unit, 'g');
      expect(d.draft!.content.ingredients.last.article.name, 'New Salt');
      final op2 = newUuid(), v2 = d.recipe.version, r2 = d.draft!.id;
      final publication = await publishRecipe(f, d, operation: op2),
          audits = await recipeAudits(f);
      await f.restart();
      final replay = RecipePublicationDto.fromJson(
        (await f.call(
          'POST',
          '$recipeRoot/$recipe/revisions/$r2/publish',
          body: PublishRecipeRequest(op2, v2).toJson(),
        )).body,
      );
      expect(replay.replayed, true);
      expect(replay.revision.toJson(), publication.revision.toJson());
      expect(await recipeAudits(f), audits);
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/$r1/publish',
        body: PublishRecipeRequest(op1, v1).toJson(),
      );
      expect(
        (await recipeDetail(f, recipe)).recipe.currentPublishedRevisionId,
        r2,
      );
      await f.call(
        'POST',
        '/articles/${i1.id}/deactivate',
        body: {'expectedVersion': i1.version},
      );
      final warning = PublishedRecipeDto.fromJson(
        (await f.call('GET', '$recipePublic/$recipe', token: employee)).body,
      );
      expect(
        warning.currentIngredients
            .singleWhere((i) => i.article.id == i1.id)
            .isActive,
        false,
      );
      await f.call(
        'POST',
        '/articles/${p.id}/deactivate',
        body: {'expectedVersion': p.version},
      );
      await f.call(
        'GET',
        '$recipePublic/$recipe',
        token: employee,
        expected: 404,
      );
      await f.call(
        'POST',
        '/articles/${p.id}/reactivate',
        body: {'expectedVersion': p.version + 1},
      );
      await f.call('GET', '$recipePublic/$recipe', token: employee);
      d = (await replacementRecipe(f, await recipeDetail(f, recipe))).detail;
      final retainedDraft = d.draft!.id;
      await f.call(
        'POST',
        '$recipeRoot/$recipe/retire',
        body: RecipeVersionRequest(d.recipe.version).toJson(),
      );
      final retired = await recipeDetail(f, recipe);
      expect(retired.recipe.status, 'retired');
      expect(retired.draft, isNull);
      expect(
        (await f.call(
          'GET',
          '$recipeRoot/$recipe/revisions/$retainedDraft',
        )).body['revision']['status'],
        'discarded',
      );
      await f.call(
        'GET',
        '$recipePublic/$recipe',
        token: employee,
        expected: 404,
      );
      final retiredBefore = await recipeEvidence(f);
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/$r2/publish',
        body: PublishRecipeRequest(op2, v2).toJson(),
      );
      expect(await recipeEvidence(f), retiredBefore);
      expect(
        (await f.call(
          'GET',
          '$recipeRoot/$recipe/revisions/$r1',
        )).body['revision'],
        published1.revision.toJson(),
      );
      expect(await recipeEvidence(f, stock: true), stockBefore);
      expect(await recipeStockHashes(f), stockHashes);
      print(
        'Recipe lifecycle Count evidence after: ${jsonEncode(await recipeStockHashes(f))}',
      );
      expect((await f.level(stock.id)).toJson(), stock.toJson());
    }),
    skip: _skip,
  );
  test(
    'one Recipe per Article, active gates, strict inputs and non-reused discarded numbers',
    () => withMerchandisingFixture((f) async {
      var d = await _saved(f);
      final recipe = d.recipe.id;
      await f.call(
        'POST',
        recipeRoot,
        expected: 409,
        body: CreateRecipeRequest(
          newUuid(),
          newUuid(),
          d.recipe.producedArticleId,
        ).toJson(),
      );
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions',
        expected: 409,
        body: NewRecipeDraftRequest(newUuid(), d.recipe.version).toJson(),
      );
      await publishRecipe(f, d);
      d = (await replacementRecipe(f, await recipeDetail(f, recipe))).detail;
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/${d.draft!.id}/discard',
        body: RecipeVersionRequest(d.recipe.version).toJson(),
      );
      final discarded = d.draft!.id;
      d = (await replacementRecipe(f, await recipeDetail(f, recipe))).detail;
      expect(d.draft!.revisionNumber, 3);
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/$discarded/edit',
        expected: 409,
        body: SaveRecipeRequest(
          d.recipe.version,
          d.draft!.content.editable,
        ).toJson(),
      );
      final inactive = await f.article(recipeArticleInput('INACTIVE'));
      await f.call(
        'POST',
        '/articles/${inactive.id}/deactivate',
        body: {'expectedVersion': inactive.version},
      );
      await f.call(
        'POST',
        recipeRoot,
        expected: 422,
        body: CreateRecipeRequest(newUuid(), newUuid(), inactive.id).toJson(),
      );
      final content = d.draft!.content.editable;
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/${d.draft!.id}/edit',
        expected: 422,
        body: SaveRecipeRequest(
          d.recipe.version,
          RecipeDraftContent(
            batchDescription: 'batch',
            preparation: 'prepare',
            ingredients: [
              RecipeIngredientInput(
                newUuid(),
                inactive.id,
                '1',
                reselect: true,
              ),
            ],
          ),
        ).toJson(),
      );
      await f.call(
        'POST',
        '$recipeRoot/$recipe/revisions/${d.draft!.id}/edit',
        expected: 400,
        body: {
          ...SaveRecipeRequest(d.recipe.version, content).toJson(),
          'companyId': merchandisingTestCompany,
        },
      );
      await f.call(
        'POST',
        recipeRoot,
        expected: 400,
        body: {
          'id': null,
          'revisionId': newUuid(),
          'producedArticleId': inactive.id,
        },
      );
      await f.call(
        'POST',
        recipeRoot,
        expected: 415,
        jsonContentType: false,
        raw: '{}',
      );
      await f.call('POST', recipeRoot, expected: 413, raw: ' ' * 262145);
      await f.call('POST', recipeRoot, expected: 400, raw: '{invalid');
    }),
    skip: _skip,
  );
  test(
    '50 exact ordered ingredients accepted; 51, duplicates, self and forged snapshots rejected',
    () => withMerchandisingFixture((f) async {
      final p = await f.article(recipeArticleInput('FIFTY', unit: 'tray'));
      var d = (await createRecipe(f, p.id)).detail;
      final ingredients = <RecipeIngredientInput>[];
      for (var i = 0; i < 50; i++) {
        final a = await f.article(recipeArticleInput('I-$i'));
        ingredients.add(
          RecipeIngredientInput(
            newUuid(),
            a.id,
            i == 49 ? '999999999999.999' : '0.001',
            reselect: true,
          ),
        );
      }
      d = (await saveRecipe(f, d, ingredients)).detail;
      expect(
        d.draft!.content.ingredients.map((i) => i.position),
        List.generate(50, (i) => i + 1),
      );
      final saved = d.draft!.content.toJson();
      await publishRecipe(f, d);
      expect(
        PublishedRecipeDto.fromJson(
          (await f.call('GET', '$recipePublic/${d.recipe.id}')).body,
        ).content.toJson(),
        saved,
      );
      d = (await replacementRecipe(
        f,
        await recipeDetail(f, d.recipe.id),
      )).detail;
      Future<void> bad(List<RecipeIngredientInput> lines, String code) async {
        final before = await recipeEvidence(f);
        final reply = await f.call(
          'POST',
          '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/edit',
          expected: 400,
          body: SaveRecipeRequest(
            d.recipe.version,
            RecipeDraftContent(
              batchDescription: 'batch',
              preparation: 'prepare',
              ingredients: lines,
            ),
          ).toJson(),
        );
        expect(reply.body['code'], code);
        expect(await recipeEvidence(f), before);
      }

      await bad([
        ...ingredients,
        RecipeIngredientInput(newUuid(), newUuid(), '1', reselect: true),
      ], 'invalid_content');
      await bad([
        ingredients.first,
        RecipeIngredientInput(
          newUuid(),
          ingredients.first.articleId,
          '1',
          reselect: true,
        ),
      ], 'duplicate_ingredient');
      await bad([
        RecipeIngredientInput(newUuid(), p.id, '1', reselect: true),
      ], 'self_ingredient');
      await bad([
        RecipeIngredientInput(newUuid(), newUuid(), '0', reselect: true),
      ], 'invalid_quantity');
      final forged = SaveRecipeRequest(
        d.recipe.version,
        d.draft!.content.editable,
      ).toJson();
      (((forged['content'] as Map)['ingredients'] as List).first
              as Map)['unit'] =
          'kg';
      await f.call(
        'POST',
        '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/edit',
        body: forged,
        expected: 400,
      );
    }),
    skip: _skip,
  );
  test(
    'current authorization precedes replay, scoped resources and denied roles',
    () => withMerchandisingFixture((f) async {
      final d = await _saved(f), op = newUuid();
      await publishRecipe(f, d, operation: op);
      for (final role in ['employee', 'viewer', 'auditor']) {
        await f.account('recipe_$role', role: role);
        final token = await f.login('recipe_$role');
        for (final route in [
          recipeRoot,
          '$recipeRoot/${d.recipe.id}',
          '/production/manage/article-candidates',
          '$recipeRoot/${d.recipe.id}/revisions',
        ]) {
          await f.call('GET', route, token: token, expected: 403);
        }
        await f.call(
          'POST',
          '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
          token: token,
          expected: 403,
          body: PublishRecipeRequest(op, d.recipe.version).toJson(),
        );
        await f.call(
          'GET',
          recipePublic,
          token: token,
          expected: role == 'employee' ? 200 : 403,
        );
      }
      await f.call('GET', '$recipeRoot/${newUuid()}', expected: 404);
      await f.call(
        'GET',
        '$recipeRoot/${d.recipe.id}/revisions/${newUuid()}',
        expected: 404,
      );
      final second = await f.article(recipeArticleInput('OTHER'));
      final other = (await createRecipe(f, second.id)).detail;
      for (final command in [
        PublishRecipeRequest(op, d.recipe.version + 1),
        PublishRecipeRequest(op, d.recipe.version),
      ]) {
        final route = command.expectedVersion == d.recipe.version
            ? '$recipeRoot/${other.recipe.id}/revisions/${other.draft!.id}/publish'
            : '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish';
        final reply = await f.call(
          'POST',
          route,
          expected: 409,
          body: command.toJson(),
        );
        expect(reply.body['code'], 'operation_conflict');
      }
      await f.account('second_publisher', role: 'admin');
      final token = await f.login('second_publisher');
      await f.call(
        'POST',
        '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
        token: token,
        expected: 409,
        body: PublishRecipeRequest(op, d.recipe.version).toJson(),
      );
      await f.call(
        'POST',
        '/api/v1/auth/logout',
        platform: false,
        token: token,
        expected: 204,
      );
      await f.call('GET', recipeRoot, token: token, expected: 401);
      final before = await recipeEvidence(f);
      await f.call(
        'POST',
        '/users/${f.adminId}',
        body: {'expectedVersion': 1, 'role': 'employee', 'isActive': true},
      );
      final replayRoute =
          '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish';
      await f.call(
        'POST',
        replayRoute,
        expected: 401,
        body: PublishRecipeRequest(op, d.recipe.version).toJson(),
      );
      final downgraded = await f.login('test_admin');
      final afterRoleChange = await recipeEvidence(f);
      await f.call(
        'POST',
        replayRoute,
        token: downgraded,
        expected: 403,
        body: PublishRecipeRequest(op, d.recipe.version).toJson(),
      );
      expect(await recipeEvidence(f), afterRoleChange);
      expect(afterRoleChange.take(3), before.take(3));
    }),
    skip: _skip,
  );
  for (final failure in ['revision', 'pointer', 'audit']) {
    test(
      '$failure failure rolls back all publication content/pointers/evidence',
      () => withMerchandisingFixture((f) async {
        final d = await _saved(f), before = await recipeEvidence(f);
        final table = switch (failure) {
          'revision' => 'production_recipe_revisions',
          'pointer' => 'production_recipes',
          _ => 'audit_entries',
        };
        final when = failure == 'audit' ? 'INSERT' : 'UPDATE';
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".fail_recipe() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION \'injected failure\'; END \$\$; CREATE TRIGGER fail_recipe BEFORE $when ON "${f.schema}".$table FOR EACH ROW EXECUTE FUNCTION "${f.schema}".fail_recipe()',
          queryMode: QueryMode.simple,
        );
        await f.call(
          'POST',
          '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
          expected: 500,
          body: PublishRecipeRequest(newUuid(), d.recipe.version).toJson(),
        );
        expect(await recipeEvidence(f), before);
      }),
      skip: _skip,
    );
  }
  test(
    'runtime grants, terminal ingredients/revisions, same Company and pointer ownership',
    () => withMerchandisingFixture((f) async {
      final d = await _saved(f);
      await publishRecipe(f, d);
      final r = d.draft!.id;
      for (final sql in [
        "UPDATE production_recipe_revisions SET preparation='changed' WHERE id='$r'",
        "DELETE FROM production_recipe_ingredients WHERE revision_id='$r'",
        "DELETE FROM production_recipes",
        "TRUNCATE production_recipe_revisions",
        "UPDATE production_recipe_ingredients SET quantity_scaled=1 WHERE revision_id='$r'",
      ]) {
        final qualified = sql.replaceFirst(
          RegExp(r'production_recipe[a-z_]*'),
          '"${f.schema}".${RegExp(r'production_recipe[a-z_]*').firstMatch(sql)!.group(0)}',
        );
        await expectLater(
          f.pool.execute(qualified),
          throwsA(isA<ServerException>()),
        );
      }
      final other = (await createRecipe(
        f,
        (await f.article(recipeArticleInput('SECOND'))).id,
      )).detail;
      await expectLater(
        f.owner.execute(
          'UPDATE "${f.schema}".production_recipes SET active_draft_revision_id=\'${other.draft!.id}\' WHERE id=\'${d.recipe.id}\'',
        ),
        throwsA(isA<ServerException>()),
      );
      final columns = await f.owner.execute(
        "SELECT has_table_privilege('${f.runtimeUser}','\"${f.schema}\".production_recipe_ingredients','UPDATE'),has_table_privilege('${f.runtimeUser}','\"${f.schema}\".production_recipes','DELETE'),has_table_privilege('${f.runtimeUser}','\"${f.schema}\".production_recipes','TRUNCATE')",
      );
      expect(columns.single.toList(), [false, false, false]);
    }),
    skip: _skip,
  );
  for (final pair in [
    'save/save',
    'save/publish',
    'save/discard',
    'publish/publish',
    'publish/retire',
    'draft/retire',
    'unit/publish',
    'inactive/publish',
  ]) {
    for (final reverse in [false, true]) {
      test(
        'observable $pair serialization ${reverse ? 'reverse' : 'forward'} has one valid atomic outcome',
        () => withMerchandisingFixture((f) async {
          var d = await _saved(f);
          if (pair == 'draft/retire') {
            await publishRecipe(f, d);
            d = await recipeDetail(f, d.recipe.id);
          }
          final id = d.recipe.id,
              rev = d.draft?.id,
              version = d.recipe.version,
              op = newUuid();
          Future<MerchandisingReply> action(String action) {
            final route = switch (action) {
              'save' => '$recipeRoot/$id/revisions/$rev/edit',
              'publish' => '$recipeRoot/$id/revisions/$rev/publish',
              'discard' => '$recipeRoot/$id/revisions/$rev/discard',
              'draft' => '$recipeRoot/$id/revisions',
              _ => '$recipeRoot/$id/retire',
            };
            final body = switch (action) {
              'save' => SaveRecipeRequest(
                version,
                d.draft!.content.editable,
              ).toJson(),
              'publish' => PublishRecipeRequest(op, version).toJson(),
              'draft' => NewRecipeDraftRequest(newUuid(), version).toJson(),
              _ => RecipeVersionRequest(version).toJson(),
            };
            if (action == 'unit' || action == 'inactive') {
              final ingredient = d.draft!.content.ingredients.single.article;
              return f.call(
                'POST',
                '/articles/${ingredient.id}/${action == 'unit' ? 'edit' : 'deactivate'}',
                expected: null,
                body: action == 'unit'
                    ? {
                        'expectedVersion': 1,
                        'sku': ingredient.sku,
                        'name': ingredient.name,
                        'unit': 'g',
                        'barcode': null,
                        'description': null,
                      }
                    : {'expectedVersion': 1},
              );
            }
            return f.call('POST', route, expected: null, body: body);
          }

          final parts = pair.split('/');
          final outcomes = await orderedRecipeCommands(
            f,
            () => action(parts[reverse ? 1 : 0]),
            () => action(parts[reverse ? 0 : 1]),
          );
          expect(
            outcomes.first.status,
            pair == 'draft/retire' && !reverse ? 201 : 200,
          );
          if (pair == 'publish/publish') {
            expect(outcomes.last.status, 200);
            expect(outcomes.last.body['replayed'], true);
          } else if (pair == 'unit/publish' || pair == 'inactive/publish') {
            expect(outcomes.last.status, reverse ? 200 : 422);
            if (!reverse) {
              expect(
                outcomes.last.body['code'],
                pair == 'unit/publish'
                    ? 'ingredient_unit_changed'
                    : 'article_unavailable',
              );
            }
          } else {
            expect(outcomes.last.status, 409);
            expect(outcomes.last.body['code'], 'stale_version');
          }
          final finalState = await recipeDetail(f, id);
          expect(
            finalState.recipe.version,
            (pair == 'unit/publish' || pair == 'inactive/publish') && !reverse
                ? version
                : version + 1,
          );
        }),
        skip: _skip,
      );
    }
  }
  test(
    'publication completeness and UTF-8 bounds return zero side effects',
    () => withMerchandisingFixture((f) async {
      var d = (await createRecipe(
        f,
        (await f.article(recipeArticleInput('EMPTY'))).id,
      )).detail;
      final before = await recipeEvidence(f);
      final fail = await f.call(
        'POST',
        '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/publish',
        expected: 422,
        body: PublishRecipeRequest(newUuid(), 1).toJson(),
      );
      expect(fail.body['code'], 'recipe_not_publishable');
      expect(await recipeEvidence(f), before);
      for (final batch in ['😀' * 121, '\uD800']) {
        await f.call(
          'POST',
          '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/edit',
          expected: 400,
          body: SaveRecipeRequest(
            1,
            RecipeDraftContent(
              batchDescription: batch,
              preparation: '',
              ingredients: [],
            ),
          ).toJson(),
        );
      }
      d = (await saveRecipe(
        f,
        d,
        [],
        batch: '😀' * 120,
        preparation: 'é' * 4096,
      )).detail;
      await f.call(
        'POST',
        '$recipeRoot/${d.recipe.id}/revisions/${d.draft!.id}/edit',
        expected: 400,
        body: SaveRecipeRequest(
          d.recipe.version,
          RecipeDraftContent(
            batchDescription: 'batch',
            preparation: 'é' * 4096 + 'x',
            ingredients: [],
          ),
        ).toJson(),
      );
    }),
    skip: _skip,
  );
  test(
    'discovery visibility before pagination, literal search, scoped manager history cursor',
    () => withMerchandisingFixture((f) async {
      final ingredient = await f.article(recipeArticleInput('PAGE-I'));
      final visible = <String>[];
      for (var n = 0; n < 54; n++) {
        final p = await f.article(
          recipeArticleInput('PAGE-$n', name: '100%_\\ $n'),
        );
        var d = (await createRecipe(f, p.id)).detail;
        if (n == 0) continue;
        d = (await saveRecipe(f, d, [
          RecipeIngredientInput(newUuid(), ingredient.id, '1', reselect: true),
        ])).detail;
        await publishRecipe(f, d);
        if (n == 1) {
          d = await recipeDetail(f, d.recipe.id);
          await f.call(
            'POST',
            '$recipeRoot/${d.recipe.id}/retire',
            body: RecipeVersionRequest(d.recipe.version).toJson(),
          );
        } else if (n == 2) {
          await f.call(
            'POST',
            '/articles/${p.id}/deactivate',
            body: {'expectedVersion': 1},
          );
        } else {
          visible.add(d.recipe.id);
        }
      }
      final first = RecipePage.fromJson(
        (await f.call('GET', '$recipePublic?q=100%25_%5C')).body,
        PublishedRecipeDto.fromJson,
      );
      expect(first.items, hasLength(50));
      expect(first.nextCursor, isNotNull);
      final second = RecipePage.fromJson(
        (await f.call(
          'GET',
          '$recipePublic?q=100%25_%5C&after=${first.nextCursor}',
        )).body,
        PublishedRecipeDto.fromJson,
      );
      expect(second.items, hasLength(1));
      expect(
        [...first.items, ...second.items].map((i) => i.recipe).toSet(),
        visible.toSet(),
      );
      await f.call('GET', '$recipePublic?after=garbage', expected: 400);
      await f.call(
        'GET',
        '$recipeRoot?after=${first.nextCursor}',
        expected: 400,
      );
      await f.call(
        'GET',
        '$recipePublic?q=different&after=${first.nextCursor}',
        expected: 400,
      );
      final j =
          jsonDecode(
                utf8.decode(
                  base64Url.decode(base64Url.normalize(first.nextCursor!)),
                ),
              )
              as Map;
      j['company'] = newUuid();
      final foreign = base64Url.encode(utf8.encode(jsonEncode(j)));
      await f.call(
        'GET',
        '$recipePublic?q=100%25_%5C&after=$foreign',
        expected: 400,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'bounded manager history and exact revision context remain Company/resource scoped',
    () => withMerchandisingFixture((f) async {
      var d = await _saved(f);
      await publishRecipe(f, d);
      final id = d.recipe.id;
      for (var n = 0; n < 50; n++) {
        d = (await replacementRecipe(f, await recipeDetail(f, id))).detail;
        await f.call(
          'POST',
          '$recipeRoot/$id/revisions/${d.draft!.id}/discard',
          body: RecipeVersionRequest(d.recipe.version).toJson(),
        );
      }
      final first = RecipePage.fromJson(
        (await f.call('GET', '$recipeRoot/$id/revisions')).body,
        RecipeRevisionDto.fromJson,
      );
      expect(first.items, hasLength(50));
      expect(first.items.first.revisionNumber, 51);
      expect(first.items.last.revisionNumber, 2);
      final last = RecipePage.fromJson(
        (await f.call(
          'GET',
          '$recipeRoot/$id/revisions?after=${Uri.encodeQueryComponent(first.nextCursor!)}',
        )).body,
        RecipeRevisionDto.fromJson,
      );
      expect(last.items.single.revisionNumber, 1);
      expect(last.nextCursor, isNull);
      final other = (await createRecipe(
        f,
        (await f.article(recipeArticleInput('HISTORY-OTHER'))).id,
      )).detail;
      await f.call(
        'GET',
        '$recipeRoot/${other.recipe.id}/revisions?after=${Uri.encodeQueryComponent(first.nextCursor!)}',
        expected: 400,
      );
      await f.call(
        'GET',
        '$recipeRoot/${other.recipe.id}/revisions/${last.items.single.id}',
        expected: 404,
      );
      final view = RecipeRevisionViewDto.fromJson(
        (await f.call(
          'GET',
          '$recipeRoot/$id/revisions/${last.items.single.id}',
        )).body,
      );
      expect(view.revision.status, 'published');
      expect(
        view.currentIngredients.single.article.id,
        view.revision.content.ingredients.single.article.id,
      );
      final p = f.adminPrincipal;
      final foreign = SessionPrincipal(
        id: p.id,
        username: p.username,
        companyId: newUuid(),
        locationId: p.locationId,
      );
      final app = RecipeService(f.database);
      for (final action in [
        () => app.detail(foreign, id),
        () => app.history(foreign, id),
        () => app.candidates(foreign),
        () => app.publish(
          foreign,
          id,
          last.items.single.id,
          PublishRecipeRequest(
            last.items.single.publishOperationId!,
            last.items.single.publishExpectedVersion!,
          ).toJson(),
        ),
      ]) {
        await expectLater(
          action,
          throwsA(
            isA<PlatformFailure>().having((e) => e.status, 'Company', 403),
          ),
        );
      }
      final before = await recipeEvidence(f);
      await f.call(
        'POST',
        recipeRoot,
        body: CreateRecipeRequest(newUuid(), newUuid(), newUuid()).toJson(),
        expected: 422,
      );
      expect(await recipeEvidence(f), before);
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
  test(
    'all Recipe endpoints enforce authentication/plugin denial and strict transport with OpenAPI parity',
    () => withMerchandisingFixture((f) async {
      final d = await _saved(f), id = d.recipe.id, r = d.draft!.id;
      const pluginId = 'recipe.denied-plugin';
      await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': pluginId,
            'name': 'Recipe denied plugin',
            'version': '1.0.0',
            'vendor': 'StoreOS Acceptance',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        },
      );
      final plugin =
          (await f.call(
                'POST',
                '/plugins/$pluginId/approve',
                body: {
                  'expectedVersion': 1,
                  'locationId': merchandisingTestLocation,
                  'permissions': ['organization.read'],
                  'subscriptions': <String>[],
                },
              )).body['token']
              as String;
      await f.call(
        'GET',
        '/api/plugin/v1/organization',
        platform: false,
        token: plugin,
      );
      final endpoints = <String, Map<String, dynamic>?>{
        'GET $recipePublic': null,
        'GET $recipePublic/$id': null,
        'GET /production/manage/article-candidates': null,
        'GET $recipeRoot': null,
        'POST $recipeRoot': CreateRecipeRequest(
          newUuid(),
          newUuid(),
          d.recipe.producedArticleId,
        ).toJson(),
        'GET $recipeRoot/$id': null,
        'POST $recipeRoot/$id/retire': RecipeVersionRequest(
          d.recipe.version,
        ).toJson(),
        'GET $recipeRoot/$id/revisions': null,
        'POST $recipeRoot/$id/revisions': NewRecipeDraftRequest(
          newUuid(),
          d.recipe.version,
        ).toJson(),
        'GET $recipeRoot/$id/revisions/$r': null,
        'POST $recipeRoot/$id/revisions/$r/edit': SaveRecipeRequest(
          d.recipe.version,
          d.draft!.content.editable,
        ).toJson(),
        'POST $recipeRoot/$id/revisions/$r/discard': RecipeVersionRequest(
          d.recipe.version,
        ).toJson(),
        'POST $recipeRoot/$id/revisions/$r/publish': PublishRecipeRequest(
          newUuid(),
          d.recipe.version,
        ).toJson(),
      };
      final openapi =
          jsonDecode(
                File(
                  '../../packages/api_contracts/platform.openapi.json',
                ).readAsStringSync(),
              )
              as Map;
      final paths = openapi['paths'] as Map;
      for (final entry in endpoints.entries) {
        final parts = entry.key.split(' '), method = parts[0], route = parts[1];
        final path =
            '/api/v1/platform${route.replaceAll(id, '{recipeId}').replaceAll(r, '{revisionId}')}';
        final responses =
            ((paths[path] as Map)[method.toLowerCase()] as Map)['responses']
                as Map;
        for (final token in ['', 'a' * 43, plugin]) {
          final denied = await f.call(
            method,
            route,
            token: token,
            body: entry.value,
            expected: 401,
          );
          expect(responses.containsKey('401'), isTrue);
          expect(
            (responses['401'] as Map)['x-error-codes'],
            contains(denied.body['code']),
          );
        }
        if (method == 'POST') {
          for (final raw in ['{', '[]', '{"unknown":1}']) {
            final invalid = await f.call(
              method,
              route,
              raw: raw,
              expected: 400,
            );
            expect(
              (responses['400'] as Map)['x-error-codes'],
              contains(invalid.body['code']),
            );
          }
          await f.call(
            method,
            route,
            raw: '{}',
            jsonContentType: false,
            expected: 415,
          );
          await f.call(method, route, raw: 'x' * 262145, expected: 413);
          for (final code in ['400', '413', '415']) {
            expect(responses.containsKey(code), isTrue);
          }
        }
      }
      await f.call(
        'POST',
        '/plugins/$pluginId/disable',
        body: {'expectedVersion': 2},
      );
      await f.call('GET', recipePublic, token: plugin, expected: 401);
    }),
    skip: _skip,
  );
  test(
    'populated 0020 to 0021 preserves old evidence, failed migration rollback and runner rerun',
    () => withMerchandisingFixture((f) async {
      for (final schema in [1, 2, 3]) {
        await guidedScenario(
          f,
          schema: schema,
          workerName: 'pre21_schema_$schema',
        );
      }
      final retained = await planogramTaskScenario(f, knowledge: true);
      await completePlanogramTask(f, retained);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".schema_migrations',
        )).single.first,
        20,
      );
      final level = await seedRecipeCountEvidence(f);
      final stockHashes = await recipeStockHashes(f);
      print('Populated 0020 Count evidence before: ${jsonEncode(stockHashes)}');
      Future<List<Object?>> legacy() async => [
        for (final table in [
          'articles',
          'article_location_assortment',
          'stock_levels',
          'stock_movements',
          'stock_counts',
          'stock_count_lines',
          'stock_count_rounds',
          'stock_count_observations',
          'stock_count_commands',
          'knowledge_articles',
          'knowledge_revisions',
          'merchandising_fixtures',
          'merchandising_planograms',
          'merchandising_planogram_revisions',
          'merchandising_planogram_zones',
          'merchandising_planogram_placements',
          'merchandising_planogram_assignments',
          'task_template_revisions',
          'task_instances',
          'task_step_results',
          'task_numeric_attempts',
          'task_execution_commands',
          'audit_entries',
        ])
          (await f.owner.execute(
            "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
          )).single.first,
      ];
      final before = await legacy();

      final temp = await Directory.systemTemp.createTemp('recipe_failed_');
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          await file.copy('${temp.path}/${file.uri.pathSegments.last}');
        }
        await File(
          '${temp.path}/0021_recipe_compositions.sql',
        ).writeAsString('\nSELECT 1/0;', mode: FileMode.append);
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: temp,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<ServerException>()),
        );
        for (final table in [
          'production_recipes',
          'production_recipe_revisions',
          'production_recipe_ingredients',
          'inventory_recipe_article_projection',
        ]) {
          expect(
            (await f.owner.execute(
              "SELECT to_regclass('\"${f.schema}\".$table')",
            )).single.first,
            isNull,
          );
        }
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' AND p.proname LIKE 'recipe_%'",
          )).single.first,
          0,
        );
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM \"${f.schema}\".schema_migrations WHERE version='0021_recipe_compositions'",
          )).single.first,
          0,
        );
        expect(await legacy(), before);
        expect(await recipeStockHashes(f), stockHashes);
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          ['0021_recipe_compositions', '0022_preparation_batches'],
        );
        expect(
          await MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          isEmpty,
        );
        expect(await legacy(), before);
        expect(await recipeStockHashes(f), stockHashes);
        print(
          'Populated 0021 Count evidence after: ${jsonEncode(await recipeStockHashes(f))}',
        );
        expect((await f.level(level.id)).toJson(), level.toJson());
        final d = await _saved(f);
        await publishRecipe(f, d);
        await f.call('GET', '$recipePublic/${d.recipe.id}');
        expect(await recipeStockHashes(f), stockHashes);
      } finally {
        await temp.delete(recursive: true);
      }
    }, legacyBefore: '0021_recipe_compositions.sql'),
    skip: _skip,
  );
}
