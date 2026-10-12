import 'dart:js_interop';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/application/article_quantity_controller.dart';
import 'package:storeos_client/src/ui/article_quantity_dialog.dart';
import 'knowledge_test.dart' show login, section, wait;

@JS('eval')
external bool predicate(String expression);
const articleIds = String.fromEnvironment('STOREOS_QUANTITY_ARTICLES'),
    levelIds = String.fromEnvironment('STOREOS_QUANTITY_LEVELS');
ArticleQuantityController controller(WidgetTester t) => t
    .widget<ArticleQuantityDialog>(find.byType(ArticleQuantityDialog))
    .controller;
Future<void> settled(WidgetTester t) async {
  await wait(
    t,
    () =>
        find.byType(ArticleQuantityDialog).evaluate().isNotEmpty &&
        !controller(t).busy,
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  await wait(t, () => target.evaluate().isNotEmpty);
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pump();
}

Future<void> enter(WidgetTester t, String key, String value) async {
  final target = find.byKey(Key(key));
  await t.ensureVisible(target);
  await t.tap(target);
  await t.pumpAndSettle();
  await t.enterText(target, value);
  await t.pump();
  expect(t.widget<TextField>(target).controller!.text, value);
}

Future<void> choose(WidgetTester t, String key, String label) async {
  await tap(t, key);
  await t.pumpAndSettle();
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
}

Future<void> stockSection(WidgetTester t) async {
  await section(t, 'Bestand');
  // The retry-scope fixture adds a second Location. Select the intended
  // resource context explicitly instead of relying on registry ordering.
  await choose(t, 'stock-location', 'Home');
  await wait(t, () => find.byType(LinearProgressIndicator).evaluate().isEmpty);
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'explicit configuration and reviewed exact targets for kg/g, mL/L, cartons/pieces and bottle/volume',
    (t) async {
      final previousErrorHandler = FlutterError.onError;
      final frameworkErrors = <String>[];
      FlutterError.onError = (details) {
        frameworkErrors.add(details.toString());
        previousErrorHandler?.call(details);
      };
      addTearDown(() => FlutterError.onError = previousErrorHandler);
      app.main();
      await login(t, 'test_admin');
      final articles = articleIds.split(','), levels = levelIds.split(',');
      for (var i = 0; i < 4; i++) {
        await section(t, 'Artikel');
        await tap(t, 'article-quantity-${articles[i]}');
        await settled(t);
        await choose(t, 'quantity-base-unit', ['kg', 'L', 'piece', 'L'][i]);
        if (i >= 2) {
          await tap(t, 'quantity-package-add');
          await enter(
            t,
            'quantity-package-label-0',
            i == 2 ? 'Carton' : '<script>literal</script>',
          );
          await enter(t, 'quantity-package-content-0', i == 2 ? '12' : '0.75');
        }
        await enter(t, 'quantity-reason', 'Explicit definition in Chrome');
        await tap(t, 'quantity-profile-save');
        await settled(t);
        expect(
          t.takeException(),
          isNull,
          reason: 'Profile case $i: ${frameworkErrors.join('\n\n')}',
        );
        expect(controller(t).profile!.version, 1);
        expect(controller(t).pending, isNull);
        await tap(t, 'quantity-close');
        await t.pumpAndSettle();
        await stockSection(t);
        await tap(t, 'stock-quantity-semantics-${levels[i]}');
        await settled(t);
        expect(
          t.takeException(),
          isNull,
          reason: 'Stock case $i: ${frameworkErrors.join('\n\n')}',
        );
        await enter(t, 'quantity-reason', 'Declare one frozen Stock unit');
        await tap(t, 'quantity-bind');
        await settled(t);
        expect(controller(t).binding!.unit, ['kg', 'L', 'piece', 'L'][i]);
        await tap(t, 'quantity-reload');
        await settled(t);
        final input = i == 0
            ? 'g'
            : i == 1
            ? 'mL'
            : 'pack:${controller(t).profile!.packages.single.id}';
        final label = i == 0
            ? 'g'
            : i == 1
            ? 'mL'
            : i == 2
            ? 'Carton (12 piece)'
            : '<script>literal</script> (0.75 L)';
        await choose(t, 'quantity-input-unit', label);
        await enter(t, 'quantity-reason', 'Reviewed physical target in Chrome');
        if (i == 0) {
          await enter(t, 'quantity-input-value', '0.000001');
          await tap(t, 'quantity-preview');
          await settled(t);
          expect(controller(t).review, isNull);
          expect(controller(t).error, contains('quantity_inexact'));
        }
        await enter(t, 'quantity-input-value', ['1250', '750', '2', '2'][i]);
        await tap(t, 'quantity-preview');
        await settled(t);
        expect(
          controller(t).review,
          isNotNull,
          reason:
              '${controller(t).error} · ${controller(t).profile?.toJson()} · ${controller(t).binding?.toJson()}',
        );
        expect(controller(t).review!.inputUnit, input);
        expect(
          controller(t).review!.targetQuantity,
          ['1.25', '0.75', '24', '1.5'][i],
        );
        expect(find.byKey(const Key('quantity-review')), findsOneWidget);
        await tap(t, 'quantity-correct');
        await settled(t);
        expect(
          t.takeException(),
          isNull,
          reason: 'Correction case $i: ${frameworkErrors.join('\n\n')}',
        );
        if (i == 0) {
          expect(controller(t).pending, isNotNull);
          final frozen = controller(t).pending;
          final payload = jsonEncode(frozen);
          final identity = controller(t).session.sessionIdentity;
          expect(
            t
                .widget<TextField>(
                  find.byKey(const Key('quantity-input-value')),
                )
                .enabled,
            false,
          );
          await tap(t, 'quantity-retry');
          await settled(t);
          expect(controller(t).error, contains('forbidden'));
          expect(controller(t).pending, same(frozen));
          expect(jsonEncode(controller(t).pending), payload);
          expect(controller(t).decisionRequired, false);
          expect(controller(t).live, true);
          expect(controller(t).session.sessionIdentity, same(identity));
          await tap(t, 'quantity-retry');
          await settled(t);
        }
        if (i == 1 || i == 2) {
          expect(controller(t).decisionRequired, true);
          expect(
            controller(t).error,
            contains(i == 1 ? 'stock_conflict' : 'quantity_conflict'),
          );
          await tap(t, 'quantity-reload');
          await settled(t);
          await choose(
            t,
            'quantity-input-unit',
            i == 1 ? 'mL' : 'Carton (24 piece)',
          );
          await enter(t, 'quantity-input-value', i == 1 ? '750' : '2');
          await enter(
            t,
            'quantity-reason',
            'Fresh review after explicit conflict',
          );
          await tap(t, 'quantity-preview');
          await settled(t);
          await tap(t, 'quantity-correct');
          await settled(t);
        }
        expect(controller(t).result, isNotNull);
        expect(controller(t).pending, isNull);
        await tap(t, 'quantity-evidence-load');
        await settled(t);
        expect(controller(t).evidence, hasLength(1));
        expect(predicate('globalThis.literal === undefined'), true);
        await tap(t, 'quantity-close');
        await t.pumpAndSettle();
      }
      // The proxy removes this package through a competing real API revision
      // after the binding commits, before its confirmed response is returned.
      await section(t, 'Artikel');
      await tap(t, 'article-quantity-${articles[4]}');
      await settled(t);
      await tap(t, 'quantity-package-add');
      await enter(t, 'quantity-package-label-0', 'Carton');
      await enter(t, 'quantity-package-content-0', '12');
      await enter(t, 'quantity-reason', 'Direct carton definition');
      await tap(t, 'quantity-profile-save');
      await settled(t);
      final package = controller(t).profile!.packages.single.id;
      await tap(t, 'quantity-close');
      await t.pumpAndSettle();
      await stockSection(t);
      await tap(t, 'stock-quantity-semantics-${levels[4]}');
      await settled(t);
      await choose(t, 'quantity-input-unit', 'Carton (12 piece)');
      await enter(t, 'quantity-reason', 'One Stock unit is this carton');
      await tap(t, 'quantity-bind');
      await settled(t);
      expect(t.takeException(), isNull, reason: frameworkErrors.join('\n\n'));
      expect(controller(t).result!['unit'], 'pack:$package');
      expect(controller(t).result!['profileVersion'], 1);
      expect(controller(t).binding!.numerator, '12');
      expect(controller(t).binding!.profileVersion, 1);
      expect(controller(t).profile!.version, 2);
      expect(controller(t).profile!.packages, isEmpty);
      final dropdown = find.byKey(const Key('quantity-input-unit'));
      expect(t.state<FormFieldState<String>>(dropdown).value, isNull);
      expect(
        find.byKey(const Key('quantity-unit-reselection')),
        findsOneWidget,
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('quantity-preview')))
            .onPressed,
        isNull,
      );
      await tap(t, 'quantity-reload');
      await settled(t);
      expect(t.state<FormFieldState<String>>(dropdown).value, isNull);
      await enter(t, 'quantity-input-value', '24');
      await enter(
        t,
        'quantity-reason',
        'Fresh piece target after package removal',
      );
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('quantity-preview')))
            .onPressed,
        isNull,
      );
      expect(controller(t).review, isNull);
      await choose(t, 'quantity-input-unit', 'piece');
      await tap(t, 'quantity-preview');
      await settled(t);
      expect(controller(t).review!.inputUnit, 'piece');
      expect(controller(t).review!.profileVersion, 2);
      expect(controller(t).review!.targetQuantity, '2');
      await tap(t, 'quantity-correct');
      await settled(t);
      expect(controller(t).result!['balanceVersion'], 2);
      expect(controller(t).binding!.unit, 'pack:$package');
      await tap(t, 'quantity-evidence-load');
      await settled(t);
      expect(controller(t).evidence, hasLength(1));
      expect(t.takeException(), isNull, reason: frameworkErrors.join('\n\n'));
      await tap(t, 'quantity-close');
      await t.pumpAndSettle();
      await section(t, 'Artikel');
      await tap(t, 'article-quantity-${articles[0]}');
      await settled(t);
      await tap(t, 'quantity-profile-suspend');
      await enter(
        t,
        'quantity-reason',
        'Erroneous anchor permanently suspended',
      );
      await tap(t, 'quantity-profile-save');
      await settled(t);
      expect(controller(t).profile!.status, 'suspended');
      await tap(t, 'quantity-profile-history');
      await settled(t);
      expect(controller(t).revisions, hasLength(2));
      await tap(t, 'quantity-close');
      await t.pumpAndSettle();
      await stockSection(t);
      await tap(t, 'stock-quantity-semantics-${levels[0]}');
      await settled(t);
      expect(find.byKey(const Key('quantity-preview')), findsNothing);
      await tap(t, 'quantity-evidence-load');
      await settled(t);
      expect(controller(t).evidence.single['review']['targetQuantity'], '1.25');
      await tap(t, 'quantity-close');
      await t.pumpAndSettle();
    },
  );
}
