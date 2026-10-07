part of 'preparation_batch_integration_test.dart';

void registerBatchOpeningRaces() {
  for (final mutation in [
    'publish',
    'retire',
    'produced_deactivate',
    'assortment_deactivate',
    'ingredient_deactivate',
    'ingredient_unit',
    'employee_deactivate',
    'employee_unlink',
  ]) {
    for (final mutationFirst in [true, false]) {
      test(
        'coherent opening $mutation ${mutationFirst ? 'before' : 'after'} open',
        () => withMerchandisingFixture((f) async {
          final w = await batchWorker(f, 'opening_race'),
              r = await batchRecipe(f),
              open = batchOpening(r);
          final id = open['batchId'] as String;
          String route;
          Map<String, dynamic> payload;
          final selectionError = mutation == 'publish' || mutation == 'retire';
          if (mutation == 'publish') {
            r.detail = (await replacementRecipe(f, r.detail)).detail;
            route =
                '$recipeRoot/${r.detail.recipe.id}/revisions/${r.detail.draft!.id}/publish';
            payload = PublishRecipeRequest(
              newUuid(),
              r.detail.recipe.version,
            ).toJson();
          } else if (mutation == 'retire') {
            route = '$recipeRoot/${r.detail.recipe.id}/retire';
            payload = RecipeVersionRequest(r.detail.recipe.version).toJson();
          } else if (mutation == 'assortment_deactivate') {
            final assortment = (await f.call(
              'GET',
              '/locations/$merchandisingTestLocation/assortment',
            )).body;
            final member = (assortment['items'] as List).single as Map;
            route =
                '/locations/$merchandisingTestLocation/assortment/${member['id']}/deactivate';
            payload = {'expectedVersion': member['version']};
          } else if (mutation == 'employee_unlink') {
            final link =
                (await f.call(
                      'GET',
                      '/employees/${w.employee}/account-link',
                    )).body['link']
                    as Map;
            route = '/employee-links/${link['id']}/revoke';
            payload = {'expectedVersion': link['version']};
          } else if (mutation == 'employee_deactivate') {
            final employee = (await f.call(
              'GET',
              '/employees/${w.employee}',
            )).body;
            route = '/employees/${w.employee}/deactivate';
            payload = {'expectedVersion': employee['version']};
          } else if (mutation == 'ingredient_unit') {
            route = '/articles/${r.ingredient.id}/edit';
            payload = {
              'expectedVersion': r.ingredient.version,
              'sku': r.ingredient.sku,
              'barcode': r.ingredient.barcode,
              'name': r.ingredient.name,
              'description': r.ingredient.description,
              'unit': 'g',
            };
          } else {
            final article = mutation == 'produced_deactivate'
                ? r.produced
                : r.ingredient;
            route = '/articles/${article.id}/deactivate';
            payload = {'expectedVersion': article.version};
          }
          final identity = mutation.startsWith('employee_');
          Future<MerchandisingReply> change() =>
              f.call('POST', route, body: payload);
          Future<MerchandisingReply> opening() => f.call(
            'POST',
            batchSelf,
            token: w.token,
            body: open,
            expected: mutationFirst ? (identity ? 401 : 422) : 201,
          );
          final results = await orderedBatchCommands(
            f,
            mutationFirst ? change : opening,
            mutationFirst ? opening : change,
          );
          final result = results[mutationFirst ? 1 : 0];
          if (mutationFirst) {
            expect(
              result.body['code'],
              identity
                  ? 'unauthorized'
                  : selectionError
                  ? 'recipe_selection_unavailable'
                  : mutation == 'ingredient_unit'
                  ? 'ingredient_unit_changed'
                  : mutation == 'assortment_deactivate'
                  ? 'not_in_assortment'
                  : 'article_unavailable',
            );
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM "${f.schema}".production_preparation_batches',
              )).single.first,
              0,
            );
          } else {
            expect(
              ((await f.call('GET', '$batchManage/$id/recipe')).body['content']
                  as Map)['preparation'],
              contains('Mix'),
            );
            expect(
              (await f.call('GET', '$batchManage/$id')).body['revisionId'],
              open['revisionId'],
            );
            if (!identity) {
              await f.call(
                'POST',
                '$batchSelf/$id/complete',
                token: w.token,
                body: batchComplete(),
              );
            } else {
              await f.call(
                'POST',
                '$batchManage/$id/cancel',
                body: batchCancel(),
              );
            }
          }
        }),
        skip: skip,
      );
    }
  }
}
