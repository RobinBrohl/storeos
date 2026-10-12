import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/ui/purchasing_section.dart';
import 'package:storeos_client/src/application/purchasing_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:http/http.dart' as http;
import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;

@JS('eval')
external bool predicate(String expression);
@JS('eval')
external JSAny? evaluate(String expression);
const a = String.fromEnvironment('STOREOS_PURCHASING_A'),
    b = String.fromEnvironment('STOREOS_PURCHASING_B');
PurchasingSection view(WidgetTester t) =>
    t.widget<PurchasingSection>(find.byType(PurchasingSection));
Finder get scroll => find
    .descendant(
      of: find.byType(PurchasingSection),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> visible(WidgetTester t, Finder target) async {
  final position = t.state<ScrollableState>(scroll).position;
  position.jumpTo(position.minScrollExtent);
  await t.pumpAndSettle();
  try {
    await t.scrollUntilVisible(
      target,
      250,
      scrollable: scroll,
      maxScrolls: 100,
    );
    await t.pumpAndSettle();
  } catch (e) {
    throw StateError(
      'Purchasing Chrome target $target could not be reached: $e',
    );
  }
  await t.ensureVisible(target);
}

Future<void> tap(WidgetTester t, Finder target) async {
  await visible(t, target);
  await t.tap(target);
  await t.pump();
}

Future<void> enter(WidgetTester t, Finder target, String text) async {
  await visible(t, target);
  await t.enterText(target, text);
  await t.pump();
}

Future<void> settled(WidgetTester t) async {
  await wait(t, () => !view(t).controller.busy);
  await t.pumpAndSettle();
}

Future<void> deliveryForm(
  WidgetTester t,
  String action,
  String line, {
  String? reference,
  String? quantity,
  String reason = 'Reasoned evidence',
}) async {
  await tap(t, find.byKey(Key('delivery-$action')));
  await t.pumpAndSettle();
  if (reference != null) {
    await t.enterText(find.byKey(const Key('delivery-reference')), reference);
  }
  if (quantity != null) {
    final choice = find.byKey(Key('delivery-select-$line'));
    if (!t.widget<CheckboxListTile>(choice).value!) {
      await t.tap(choice);
      await t.pumpAndSettle();
    }
    await t.enterText(find.byKey(Key('delivery-quantity-$line')), quantity);
  }
  await t.enterText(find.byKey(const Key('delivery-reason')), reason);
  await t.tap(find.byKey(const Key('delivery-confirm')));
  await settled(t);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  if (predicate('sessionStorage.getItem("p414ReloadOrder") !== null')) {
    testWidgets(
      'actual page reload retains the fifty-line server declaration',
      (t) async {
        app.main();
        await login(t, 'test_admin');
        await section(t, 'Purchasing');
        await settled(t);
        final order =
            (evaluate('sessionStorage.getItem("p414ReloadOrder")') as JSString)
                .toDart;
        await view(t).controller.select(order);
        await settled(t);
        expect(
          view(t).controller.deliveryItems.any(
            (d) => (d['lines'] as List).length == 50,
          ),
          true,
        );
        final restoredLines =
            view(t).controller.deliverySummary!['summary']['lines'] as List;
        expect(restoredLines[0]['effectiveDelivered'], '1.003');
        expect(
          restoredLines
              .skip(1)
              .every((l) => l['effectiveDelivered'] == '1.000'),
          true,
        );
        evaluate('window.__p414ReloadVerified = true');
      },
    );
    return;
  }
  testWidgets(
    'Chrome complete bounded Purchasing workflow with stale unit, restart replay, literal content and closure',
    (t) async {
      final original = FlutterError.onError;
      final errors = <String>[];
      binding.reportData = {'flutterErrors': errors};
      FlutterError.onError = (details) {
        errors.add('${details.exceptionAsString()}\n${details.stack}');
        original?.call(details);
      };
      addTearDown(() => FlutterError.onError = original);
      app.main();
      await login(t, 'test_admin');
      await section(t, 'Purchasing');
      await settled(t);
      await enter(
        t,
        find.byKey(const Key('purchasing-supplier-name')),
        'Supplier <a href="https://invalid.example/p412"> 😀',
      );
      await enter(
        t,
        find.byKey(const Key('purchasing-supplier-reference')),
        'CUSTOMER',
      );
      await tap(t, find.byKey(const Key('purchasing-supplier-create')));
      await settled(t);
      final s = view(t).controller.supplierDetail!;
      await tap(t, find.byKey(const Key('purchasing-new')));
      await tap(t, find.byKey(const Key('purchasing-suppliers')));
      await settled(t);
      await tap(t, find.byKey(Key('purchasing-supplier-${s['id']}')));
      await enter(
        t,
        find.byKey(const Key('purchasing-reference')),
        'P412 Chrome',
      );
      await tap(t, find.byKey(const Key('purchasing-create')));
      await settled(t);
      await tap(t, find.byKey(const Key('purchasing-articles')));
      await settled(t);
      await tap(t, find.byKey(const Key('purchasing-article-$a')));
      await tap(t, find.byKey(const Key('purchasing-article-$b')));
      final ids = view(t).controller.lines.map((l) => l['id']).toList();
      await enter(t, find.byKey(Key('purchasing-quantity-${ids[0]}')), '2.5');
      await enter(t, find.byKey(Key('purchasing-quantity-${ids[1]}')), '12');
      await tap(t, find.byKey(const Key('purchasing-save')));
      await settled(t);
      expect(
        view(t).controller.detail!['lines'].map((l) => l['quantity']).toList(),
        ['2.500', '12.000'],
      );
      await tap(t, find.byKey(const Key('purchasing-review')));
      await tap(t, find.byKey(const Key('purchasing-issue')));
      await settled(t);
      expect(view(t).controller.error, contains('article_unit_changed'));
      expect(view(t).controller.detail!['status'], 'draft');
      await tap(t, find.byKey(Key('purchasing-reselect-${ids[0]}')));
      await settled(t);
      await tap(t, find.byKey(const Key('purchasing-article-$a')));
      await tap(t, find.byKey(const Key('purchasing-save')));
      await settled(t);
      expect(view(t).controller.detail!['lines'][0]['unit'], 'bag');
      await tap(t, find.byKey(const Key('purchasing-review')));
      await tap(t, find.byKey(const Key('purchasing-issue')));
      await settled(t);
      final pending = view(t).controller.pending!;
      await tap(t, find.byKey(const Key('purchasing-retry')));
      await settled(t);
      final frozen = view(t).controller.detail!;
      expect(view(t).controller.lastConfirmed!['replayed'], true);
      await enter(
        t,
        find.byKey(const Key('purchasing-supplier-name')),
        'Later Supplier',
      );
      await enter(
        t,
        find.byKey(const Key('purchasing-supplier-reference')),
        'LATER',
      );
      await tap(t, find.widgetWithText(OutlinedButton, 'Save Supplier'));
      await settled(t);
      await tap(
        t,
        find.widgetWithText(OutlinedButton, 'Retire Supplier permanently'),
      );
      await settled(t);
      expect(view(t).controller.supplierDetail!['status'], 'retired');
      expect(view(t).controller.detail!['supplier'], frozen['supplier']);
      await visible(t, find.byKey(const Key('purchasing-saved-content')));
      final content = t
          .widget<SelectableText>(
            find.byKey(const Key('purchasing-saved-content')),
          )
          .data!;
      expect(content, contains('2.500 bag'));
      expect(content, contains('12.000 piece'));
      expect(content, contains('globalThis.purchasingInjected=true'));
      expect(predicate('globalThis.purchasingInjected !== true'), true);
      expect(
        predicate(
          "performance.getEntriesByType('resource').every(x => !x.name.includes('invalid.example/p412'))",
        ),
        true,
      );
      final deliveryLine =
          view(t).controller.detail!['lines'][1]['id'] as String;
      await deliveryForm(
        t,
        'declare',
        deliveryLine,
        reference: 'Delivery A <script>',
        quantity: '5',
      );
      expect(view(t).controller.pending, isNotNull);
      final deliveryPending = view(t).controller.pending!;
      await t.tap(find.widgetWithText(TextButton, 'Retry exact command'));
      await settled(t);
      final deliveryA =
          view(t).controller.deliveryDetail!['deliveryId'] as String;
      await deliveryForm(
        t,
        'declare',
        deliveryLine,
        reference: 'Delivery B',
        quantity: '7',
      );
      await deliveryForm(
        t,
        'declare',
        deliveryLine,
        reference: 'Delivery extra',
        quantity: '1',
        reason: 'Accepted overdelivery',
      );
      expect(
        view(
          t,
        ).controller.deliverySummary!['summary']['lines'][1]['overdelivery'],
        '1.000',
      );
      await deliveryForm(t, 'void', deliveryLine, reason: 'Mistaken duplicate');
      await view(t).controller.selectDelivery(deliveryA);
      await settled(t);
      await deliveryForm(t, 'correct', deliveryLine, quantity: '4');
      await deliveryForm(t, 'correct', deliveryLine, quantity: '5');
      await tap(t, find.byKey(const Key('purchasing-close')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('purchasing-terminal-reason')),
        'Administrative close <script> 😀',
      );
      await t.tap(find.byKey(const Key('purchasing-terminal-confirm')));
      await settled(t);
      expect(view(t).controller.detail!['status'], 'closed');
      await view(t).controller.selectDelivery(deliveryA);
      await settled(t);
      await deliveryForm(
        t,
        'correct',
        deliveryLine,
        quantity: '4',
        reason: 'After closure correction',
      );
      expect(
        view(t)
            .controller
            .deliverySummary!['summary']['lines'][1]['effectiveDelivered'],
        '11.000',
      );
      expect(
        view(t)
            .controller
            .deliverySummary!['terminalSnapshot']['summary']['lines'][1]['effectiveDelivered'],
        '12.000',
      );
      await tap(t, find.widgetWithText(OutlinedButton, 'Order history'));
      await settled(t);
      expect(view(t).controller.history.map((h) => h['kind']), [
        'order_create',
        'order_save',
        'order_save',
        'order_issue',
        'order_close',
      ]);
      final client = http.Client(),
          base = Uri.parse(const String.fromEnvironment('STOREOS_API_URL')),
          auth = HttpStoreApi(baseUri: base, client: client),
          api = HttpPlatformApi(baseUri: base, client: client);
      try {
        final session = await auth.login(
          const LoginRequest(
            username: 'test_admin',
            password: String.fromEnvironment('STOREOS_KNOWLEDGE_PASSWORD'),
          ),
        );
        try {
          final r = await api.post(session.token, pending.route, pending.body);
          expect(r['order'], frozen);
          expect(r['replayed'], true);
          final deliveryReplay = await api.post(
            session.token,
            deliveryPending.route,
            deliveryPending.body,
          );
          expect(deliveryReplay['replayed'], true);
          expect(
            deliveryReplay['summary']['lines'][1]['effectiveDelivered'],
            '5.000',
          );
        } finally {
          await auth.logout(session.token);
        }
      } finally {
        client.close();
      }
      final c = view(t).controller;
      expect(
        await c.supplierCreate('Large declaration supplier', null),
        PurchasingOutcome.confirmed,
      );
      final largeSupplier = c.supplierDetail!;
      c.newDraft();
      c.chooseSupplier(largeSupplier);
      c.reference = 'P414 50-line Chrome';
      expect(await c.create(), PurchasingOutcome.confirmed);
      final largeIds = const String.fromEnvironment(
        'STOREOS_PURCHASING_LARGE',
      ).split(',');
      expect(largeIds, hasLength(50));
      await c.articleChoices();
      while (c.articleCursor != null) {
        await c.articleChoices(more: true);
      }
      for (final id in largeIds) {
        c.addArticle(c.articles.firstWhere((a) => a['id'] == id));
      }
      expect(c.lines, hasLength(50));
      expect(await c.save(), PurchasingOutcome.confirmed);
      c.reviewSaved();
      expect(await c.lifecycle('issue'), PurchasingOutcome.confirmed);
      await settled(t);
      final largeLines = (c.detail!['lines'] as List)
          .map((l) => l['id'] as String)
          .toList();
      await tap(t, find.byKey(const Key('delivery-declare')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('delivery-reference')),
        '50 lines <a href="https://invalid.example">',
      );
      for (final id in largeLines) {
        final check = find.byKey(Key('delivery-select-$id'));
        await t.ensureVisible(check);
        await t.pumpAndSettle();
        await t.tap(check);
        await t.pumpAndSettle();
        final quantity = find.byKey(Key('delivery-quantity-$id'));
        await t.ensureVisible(quantity);
        await t.pumpAndSettle();
        await t.enterText(quantity, '1');
      }
      await t.ensureVisible(find.byKey(const Key('delivery-confirm')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('delivery-confirm')));
      await settled(t);
      expect(c.deliveryDetail!['lines'], hasLength(50));
      expect(c.deliverySummary!['summary']['lines'], hasLength(50));
      expect(
        predicate(
          'document.querySelectorAll("script[src*=invalid], a[href*=invalid], img[src*=invalid]").length === 0',
        ),
        true,
      );
      final largeOrder = c.detail!['id'] as String;
      binding.reportData!['reloadOrder'] = largeOrder;
      Future<Map<String, dynamic>> gate(String action) => c.session.authorized(
        (token) => c.api.post(token, '/p414-test-gate', {'action': action}),
      );
      Future<void> observedHold() async {
        final watch = Stopwatch()..start();
        while (watch.elapsed < const Duration(seconds: 10)) {
          if ((await gate('status'))['held'] == true) return;
          await t.pump(const Duration(milliseconds: 20));
        }
        throw StateError('Observed HTTP gate did not hold a response.');
      }

      for (final user in ['test_admin', 'p414_replacement_admin']) {
        for (final mode in ['hold_read', 'hold_write']) {
          await c.select(largeOrder);
          await settled(t);
          await tap(t, find.byKey(const Key('delivery-declare')));
          await t.pumpAndSettle();
          await t.enterText(
            find.byKey(const Key('delivery-reference')),
            'Private mounted reference',
          );
          await t.enterText(
            find.byKey(const Key('delivery-reason')),
            'Private mounted reason',
          );
          await gate(mode);
          final Future<Object?> work = mode == 'hold_read'
              ? c.select(largeOrder)
              : c.deliveryCommand(
                  'declare',
                  reference: 'Held-$user-$mode',
                  reason: 'Accepted small excess',
                  lines: [
                    {'orderLineId': largeLines.first, 'quantity': '0.001'},
                  ],
                );
          await observedHold();
          await c.session.signIn(
            username: user,
            password: const String.fromEnvironment(
              'STOREOS_KNOWLEDGE_PASSWORD',
            ),
          );
          await t.pumpAndSettle();
          expect(c.pending, null);
          expect(c.detail, null);
          expect(c.deliverySummary, null);
          expect(c.deliveryHistory, isEmpty);
          expect(
            t
                .widget<TextField>(find.byKey(const Key('delivery-reference')))
                .controller!
                .text,
            isEmpty,
          );
          expect(
            t
                .widget<TextField>(find.byKey(const Key('delivery-reason')))
                .controller!
                .text,
            isEmpty,
          );
          expect(
            t
                .widget<TextButton>(find.byKey(const Key('delivery-confirm')))
                .onPressed,
            null,
          );
          await gate('release');
          final outcome = await work;
          if (mode == 'hold_write') expect(outcome, PurchasingOutcome.fenced);
          await t.pumpAndSettle();
          expect(c.lastConfirmed, null);
          expect(c.detail, null);
          await t.tap(find.widgetWithText(TextButton, 'Back'));
          await t.pumpAndSettle();
          await wait(t, () => c.canRead);
        }
      }
      await c.select(largeOrder);
      await settled(t);
      await gate('fail_refresh');
      expect(
        await c.deliveryCommand(
          'declare',
          reference: 'Confirmed failed refresh',
          reason: 'Accepted excess',
          lines: [
            {'orderLineId': largeLines.first, 'quantity': '0.001'},
          ],
        ),
        PurchasingOutcome.confirmed,
      );
      expect(c.lastConfirmed, isNotNull);
      expect(c.detail, null);
      expect(c.deliverySummary, null);
      expect(c.refreshWarning, isNotNull);
      expect(c.pending, null);
      await c.select(largeOrder);
      await settled(t);
      await logout(t);
      await login(t, 'test_admin');
      await section(t, 'Purchasing');
      await view(t).controller.select(largeOrder);
      await settled(t);
      expect(
        view(t).controller.deliveryItems.any(
          (d) => (d['lines'] as List).length == 50,
        ),
        true,
      );
      await logout(t);
    },
  );
}
