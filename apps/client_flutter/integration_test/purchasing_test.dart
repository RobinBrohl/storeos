import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/ui/purchasing_section.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:http/http.dart' as http;
import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;

@JS('eval')
external bool predicate(String expression);
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome complete bounded Purchasing workflow with stale unit, restart replay, literal content and closure',
    (t) async {
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
      await tap(t, find.byKey(const Key('purchasing-close')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('purchasing-terminal-reason')),
        'Administrative close <script> 😀',
      );
      await t.tap(find.byKey(const Key('purchasing-terminal-confirm')));
      await settled(t);
      expect(view(t).controller.detail!['status'], 'closed');
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
        } finally {
          await auth.logout(session.token);
        }
      } finally {
        client.close();
      }
      await logout(t);
    },
  );
}
