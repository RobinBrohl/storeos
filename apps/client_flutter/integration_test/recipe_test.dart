import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'knowledge_test.dart' show login, section, wait;
import 'package:storeos_client/src/ui/recipe_section.dart';

@JS('eval')
external bool browserPredicate(String expression);
const literal =
    '<script>globalThis.recipeInjected=true</script>\n<a href="https://invalid.example/p49">literal</a>\n<img src="x" onerror="globalThis.recipeInjected=true">\n# plain ä 😀';
const batch = 'one 30 × 40 cm tray';
const literalBatch = '$batch <script>globalThis.recipeInjected=true</script>';
const produced = String.fromEnvironment('STOREOS_RECIPE_PRODUCED'),
    ingredient = String.fromEnvironment('STOREOS_RECIPE_INGREDIENT'),
    shift = String.fromEnvironment('STOREOS_RECIPE_SHIFT');
Finder sku(String prefix) => find.byWidgetPredicate(
  (w) =>
      w is ListTile &&
      w.title is Text &&
      ((w.title as Text).data ?? '').startsWith(prefix),
);
Future<void> enter(WidgetTester tester, Finder target, String value) async {
  if (target.evaluate().isEmpty) {
    await tester.drag(activeScrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 200, scrollable: activeScrollable);
  }
  await tester.ensureVisible(target);
  await tester.enterText(target, value);
  await tester.pump();
}

Future<void> settled(WidgetTester tester) async {
  await wait(
    tester,
    () =>
        find.byType(RecipeSection).evaluate().isNotEmpty &&
        !tester
            .widget<RecipeSection>(find.byType(RecipeSection))
            .controller
            .busy,
  );
  await tester.pumpAndSettle();
}

Future<void> logout(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('logout-button')));
  await wait(
    tester,
    () => find.byKey(const Key('username-field')).evaluate().isNotEmpty,
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome complete Recipe composition workflow and exact restart replay',
    (tester) async {
      app.main();
      await login(tester, 'test_admin');
      await section(tester, 'Rezepte');
      await tap(tester, find.text('Verwalten'));
      await settled(tester);
      await enter(
        tester,
        find.byKey(const Key('recipe-article-search')),
        'BROWSER-P',
      );
      await tap(tester, find.text('Artikel suchen'));
      await settled(tester);
      await tap(tester, sku('BROWSER-P'));
      await tap(tester, find.byKey(const Key('recipe-create')));
      await settled(tester);
      final initialRecipe = tester
          .widget<RecipeSection>(find.byType(RecipeSection))
          .controller
          .detail!
          .recipe
          .id;
      await tap(tester, find.byKey(const Key('recipe-discard')));
      await settled(tester);
      expect(find.text('Neuen leeren Entwurf erstellen'), findsOneWidget);
      await tap(tester, find.byKey(const Key('recipe-new-draft')));
      await settled(tester);
      final recovered = tester
          .widget<RecipeSection>(find.byType(RecipeSection))
          .controller
          .detail!;
      expect(recovered.recipe.id, initialRecipe);
      expect(recovered.draft!.revisionNumber, 2);
      expect(recovered.draft!.content.ingredients, isEmpty);
      await enter(tester, find.byKey(const Key('recipe-batch')), batch);
      for (final code in ['BROWSER-I1', 'BROWSER-I2']) {
        await enter(
          tester,
          find.byKey(const Key('recipe-article-search')),
          code,
        );
        await tap(tester, find.text('Artikel suchen'));
        await settled(tester);
        await tap(tester, sku(code));
      }
      final quantity = find.byWidgetPredicate(
        (w) =>
            w is TextField &&
            w.key is ValueKey<String> &&
            ((w.key as ValueKey<String>).value).startsWith('recipe-quantity-'),
      );
      await enter(tester, quantity.first, '1.250');
      await enter(tester, quantity.last, '0.050');
      await tap(tester, find.byTooltip('Nach unten').first);
      await tap(tester, find.byTooltip('Nach oben').last);
      await enter(tester, find.byKey(const Key('recipe-preparation')), literal);
      await tap(tester, find.byKey(const Key('recipe-save')));
      await settled(tester);
      await tap(tester, find.text('Gespeicherten Entwurf ansehen'));
      await settled(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        200,
        scrollable: recipeScrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      checkLiteral();
      await tap(tester, find.byKey(const Key('recipe-publish')));
      await settled(tester);
      await tap(tester, find.byKey(const Key('recipe-new-draft')));
      await settled(tester);
      await enter(tester, find.byKey(const Key('recipe-batch')), literalBatch);
      await enter(tester, quantity.last, '0.075');
      await enter(
        tester,
        find.byKey(const Key('recipe-preparation')),
        'Replacement\n$literal',
      );
      await tap(tester, find.byKey(const Key('recipe-save')));
      await settled(tester);
      await logout(tester);
      await login(tester, 'recipe_worker');
      await section(tester, 'Meine Arbeit');
      await tap(tester, find.byKey(Key('shift-$shift')));
      await tap(tester, find.byKey(const Key('work-recipes-shortcut')));
      await settled(tester);
      await tap(tester, sku('BROWSER-P'));
      await settled(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        200,
        scrollable: recipeScrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      expect(
        find.text('Zutaten für einen deklarierten Rezept-Batch'),
        findsOneWidget,
      );
      checkLiteral();
      await tap(tester, find.byType(BackButton));
      expect(find.text('Schicht · Veröffentlicht'), findsOneWidget);
      await logout(tester);
      await login(tester, 'test_admin');
      await section(tester, 'Rezepte');
      await tap(tester, find.text('Verwalten'));
      await settled(tester);
      await tap(tester, sku('BROWSER-P'));
      await settled(tester);
      final client = http.Client(),
          base = Uri.parse(const String.fromEnvironment('STOREOS_API_URL'));
      final store = HttpStoreApi(baseUri: base, client: client),
          api = HttpPlatformApi(baseUri: base, client: client);
      final auth = await store.login(
        const LoginRequest(
          username: 'test_admin',
          password: String.fromEnvironment('STOREOS_RECIPE_PASSWORD'),
        ),
      );
      addTearDown(client.close);
      final a = await api.get(auth.token, '/articles/$ingredient');
      await api.post(auth.token, '/articles/$ingredient/edit', {
        'expectedVersion': a['version'],
        'sku': a['sku'],
        'barcode': a['barcode'],
        'name': a['name'],
        'description': a['description'],
        'unit': 'g',
      });
      await tap(tester, find.byKey(const Key('recipe-publish')));
      await settled(tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('recipe-error')),
        -200,
        scrollable: recipeScrollable,
      );
      expect(find.textContaining('ingredient_unit_changed'), findsOneWidget);
      await tap(tester, find.text('Referenz ausdrücklich neu auswählen').last);
      await settled(tester);
      expect(find.text('Ausgewählte aktuelle Einheit: g'), findsOneWidget);
      await enter(tester, quantity.last, '0.075');
      await tap(tester, find.byKey(const Key('recipe-save')));
      await settled(tester);
      await tap(tester, find.byKey(const Key('recipe-publish')));
      await settled(tester);
      await tap(tester, find.text('Identische Veröffentlichung erneut senden'));
      await settled(tester);
      expect(find.text('Veröffentlichung bestätigt.'), findsOneWidget);
      final approved = tester
          .widget<RecipeSection>(find.byType(RecipeSection))
          .controller
          .confirmedPublication!;
      final recipeId = approved.revision.recipeIdValue;
      final replayBody = PublishRecipeRequest(
        approved.revision.publishOperationId!,
        approved.revision.publishExpectedVersion!,
      ).toJson();
      await tap(
        tester,
        find.widgetWithText(ListTile, 'PUBLISHED · Revision 2'),
      );
      await settled(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        200,
        scrollable: recipeScrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      checkLiteral();
      await logout(tester);
      await login(tester, 'recipe_worker');
      await section(tester, 'Rezepte');
      await tap(tester, sku('BROWSER-P'));
      await settled(tester);
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, 'Replacement\n$literal'),
        200,
        scrollable: recipeScrollable,
      );
      expect(
        find.widgetWithText(SelectableText, 'Replacement\n$literal'),
        findsOneWidget,
      );
      checkLiteral();
      var p = await api.get(auth.token, '/articles/$produced');
      await api.post(auth.token, '/articles/$produced/deactivate', {
        'expectedVersion': p['version'],
      });
      await tap(tester, find.text('Rezept schließen'));
      await tap(tester, find.text('Suchen'));
      await settled(tester);
      expect(sku('BROWSER-P'), findsNothing);
      p = await api.get(auth.token, '/articles/$produced');
      await api.post(auth.token, '/articles/$produced/reactivate', {
        'expectedVersion': p['version'],
      });
      await tap(tester, find.text('Suchen'));
      await settled(tester);
      expect(sku('BROWSER-P'), findsOneWidget);
      await logout(tester);
      await login(tester, 'test_admin');
      await section(tester, 'Rezepte');
      await tap(tester, find.text('Verwalten'));
      await settled(tester);
      await tap(tester, sku('BROWSER-P'));
      await settled(tester);
      await tap(tester, find.byKey(const Key('recipe-new-draft')));
      await settled(tester);
      await tap(tester, find.byKey(const Key('recipe-retire')));
      await settled(tester);
      expect(find.textContaining('RETIRED · Version'), findsOneWidget);
      final retired = await api.get(
        auth.token,
        '/production/manage/recipes/$recipeId',
      );
      final replay = RecipePublicationDto.fromJson(
        await api.post(
          auth.token,
          '/production/manage/recipes/$recipeId/revisions/${approved.revision.id}/publish',
          replayBody,
        ),
      );
      expect(replay.replayed, isTrue);
      expect(replay.revision.toJson(), approved.revision.toJson());
      expect(
        await api.get(auth.token, '/production/manage/recipes/$recipeId'),
        retired,
      );
      for (final row in ['PUBLISHED · Revision 2', 'PUBLISHED · Revision 3']) {
        await tap(tester, find.widgetWithText(ListTile, row));
        await settled(tester);
      }
      await logout(tester);
      await login(tester, 'recipe_worker');
      await section(tester, 'Rezepte');
      expect(sku('BROWSER-P'), findsNothing);
      expect(find.text('Verwalten'), findsNothing);
    },
  );
}

void checkLiteral() {
  expect(browserPredicate('globalThis.recipeInjected !== true'), true);
  expect(
    browserPredicate(
      '!Array.from(document.querySelectorAll("a")).some(a => a.href.includes("invalid.example/p49")) && document.querySelectorAll("img[onerror]").length === 0',
    ),
    true,
  );
  expect(
    browserPredicate(
      '!Array.from(document.scripts).some(s => s.textContent.includes("recipeInjected"))',
    ),
    true,
  );
}

Future<void> tap(WidgetTester tester, Finder target) async {
  try {
    await readyTap(tester, target);
  } catch (error) {
    throw StateError('Recipe browser action $target failed: $error');
  }
}

Future<void> readyTap(WidgetTester tester, Finder target) async {
  await wait(
    tester,
    () =>
        target.evaluate().isNotEmpty || activeScrollable.evaluate().isNotEmpty,
  );
  if (target.evaluate().isEmpty) {
    await tester.drag(activeScrollable, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 200, scrollable: activeScrollable);
  }
  await wait(tester, () {
    if (target.evaluate().isEmpty) return false;
    final buttons = find
        .ancestor(
          of: target,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        )
        .evaluate();
    if (buttons.isNotEmpty &&
        (buttons.first.widget as ButtonStyleButton).onPressed == null) {
      return false;
    }
    final widget = target.evaluate().first.widget;
    return switch (widget) {
      ButtonStyleButton() => widget.onPressed != null,
      ListTile() => widget.onTap != null,
      _ => true,
    };
  });
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Finder get recipeScrollable => find
    .descendant(
      of: find.byKey(const Key('recipe-list')),
      matching: find.byType(Scrollable),
    )
    .first;

Finder get activeScrollable => recipeScrollable.evaluate().isNotEmpty
    ? recipeScrollable
    : find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
