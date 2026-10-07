import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/recipe_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test(
    'real Recipe lifecycle, exact lost-response retry and employee isolation',
    () async {
      final env = Platform.environment,
          base = Uri.parse(Platform.environment['STOREOS_RECIPE_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client);
      final faults = Faults(api);
      final manager = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          ),
          worker = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          );
      final mp = PlatformController(manager, api),
          wp = PlatformController(worker, api);
      final m = RecipeController(manager, mp, faults),
          w = RecipeController(worker, wp, api),
          other = RecipeController(manager, mp, api);
      addTearDown(() {
        m.dispose();
        w.dispose();
        other.dispose();
        mp.dispose();
        wp.dispose();
        manager.dispose();
        worker.dispose();
        client.close();
      });
      Future<void> ready(PlatformController p) async {
        final c = Completer<void>();
        void changed() {
          if (!p.isBusy && p.organization != null && !c.isCompleted) {
            c.complete();
          }
        }

        p.addListener(changed);
        try {
          changed();
          await c.future.timeout(const Duration(seconds: 10));
        } finally {
          p.removeListener(changed);
        }
      }

      await manager.signIn(
        username: 'test_admin',
        password: 'stock-test-only-password-strong',
      );
      await worker.signIn(
        username: 'recipe_worker',
        password: 'stock-test-only-password-strong',
      );
      await ready(mp);
      await ready(wp);
      expect(w.canManage, isFalse);
      expect(
        await m.create(env['STOREOS_RECIPE_PRODUCED']!),
        RecipeOutcome.confirmed,
      );
      final id = m.detail!.recipe.id;
      final discarded = m.detail!.draft!.id;
      expect(await m.discard(), RecipeOutcome.confirmed);
      expect(m.detail!.draft, isNull);
      expect(m.detail!.currentPublished, isNull);
      expect(await m.newDraft(), RecipeOutcome.confirmed);
      expect(m.detail!.recipe.id, id);
      expect(m.detail!.draft!.revisionNumber, 2);
      expect(m.editing!.ingredients, isEmpty);
      await m.findArticles('CLIENT-I');
      m.addIngredient(m.candidates.single);
      m.changeQuantity(m.editing!.ingredients.single.id, '2.125');
      m.setEditing(
        RecipeDraftContent(
          batchDescription: 'One tray',
          preparation: 'Mix <script>literal</script>',
          ingredients: m.editing!.ingredients,
        ),
      );
      expect(await m.publish(), RecipeOutcome.rejected);
      expect(await m.save(), RecipeOutcome.confirmed);
      final line = m.editing!.ingredients.single.id;
      await m.refreshIngredient(line);
      expect(m.selectedSnapshots[line]!.unit, 'kg');
      await other.openManaged(id);
      final ingredient = ArticleDto.fromJson(
        await manager.authorized(
          (token) =>
              api.get(token, '/articles/${env['STOREOS_RECIPE_INGREDIENT']}'),
        ),
      );
      await manager.authorized(
        (token) => api.post(token, '/articles/${ingredient.id}/edit', {
          'expectedVersion': ingredient.version,
          'sku': ingredient.sku,
          'barcode': ingredient.barcode,
          'name': 'Authoritative mg ingredient',
          'description': ingredient.description,
          'unit': 'mg',
        }),
      );
      await other.refreshIngredient(line);
      expect(await other.save(), RecipeOutcome.confirmed);
      expect(
        other.detail!.draft!.content.ingredients.single.article.unit,
        'mg',
      );
      expect(await m.save(), RecipeOutcome.rejected);
      expect(m.error, contains('stale_version'));
      await m.reloadForReview();
      expect(m.selectedSnapshots[line]!.unit, 'kg');
      m.acceptReviewedState();
      expect(m.selectedSnapshots, isEmpty);
      expect(m.ingredientSnapshot(m.editing!.ingredients.single)!.unit, 'mg');
      expect(await m.save(), RecipeOutcome.confirmed);
      expect(m.detail!.draft!.content.ingredients.single.article.unit, 'mg');
      expect(await m.publish(), RecipeOutcome.confirmed);
      await w.search('CLIENT-P');
      expect(w.published, hasLength(1));
      await w.openInstruction(id);
      expect(w.instruction!.content.ingredients.single.quantity, '2.125');
      expect(w.instruction!.content.ingredients.single.article.unit, 'mg');
      expect(w.instruction!.revisionNumber, 2);
      expect(await m.newDraft(), RecipeOutcome.confirmed);
      m.setEditing(
        RecipeDraftContent(
          batchDescription: 'One tray',
          preparation: 'Replacement',
          ingredients: m.editing!.ingredients,
        ),
      );
      expect(await m.save(), RecipeOutcome.confirmed);
      await w.refreshInstruction();
      expect(w.instruction!.revisionNumber, 2);
      faults.drop = true;
      expect(await m.publish(), RecipeOutcome.uncertain);
      final pending = m.pending!;
      expect(await m.retryPublication(), RecipeOutcome.confirmed);
      expect(m.confirmedPublication!.replayed, isTrue);
      expect(faults.lastRetry, pending.body);
      await w.refreshInstruction();
      expect(w.instruction!.revisionNumber, 3);
      expect(w.instruction!.content.preparation, 'Replacement');
      expect(m.history, hasLength(3));
      expect(m.history.last.id, discarded);
      expect(m.history.last.status, 'discarded');
      expect(await m.newDraft(), RecipeOutcome.confirmed);
      expect(await m.retire(), RecipeOutcome.confirmed);
      await w.search('CLIENT-P');
      expect(w.published, isEmpty);
      await w.openInstruction(id);
      expect(w.error, contains('not_found'));
    },
    skip: Platform.environment['STOREOS_RECIPE_URL'] == null
        ? 'Isolated server host required.'
        : false,
  );
}

class Faults implements PlatformApi {
  Faults(this.api);
  final PlatformApi api;
  bool drop = false;
  Map<String, dynamic>? lastRetry;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) => api.get(token, route, after: after, query: query);
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    final result = await api.post(token, route, body);
    if (drop && route.endsWith('/publish')) {
      drop = false;
      throw const StoreApiException('network', 'Committed response lost.');
    }
    if (route.endsWith('/publish')) lastRetry = body;
    return result;
  }
}
