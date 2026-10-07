import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/ui/preparation_batch_section.dart';
import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;

@JS('eval')
external bool predicate(String expression);
Finder get batchScroll => find
    .descendant(
      of: find.byType(PreparationBatchSection),
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> visible(WidgetTester t, Finder target) async {
  if (target.evaluate().isEmpty) {
    await t.drag(batchScroll, const Offset(0, 5000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(target, 200, scrollable: batchScroll);
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

const recipe = String.fromEnvironment('STOREOS_PREPARATION_RECIPE'),
    zero = String.fromEnvironment('STOREOS_PREPARATION_ZERO');
const instruction =
    'Mix <script>globalThis.preparationInjected=true</script>\n<a href="https://invalid.example/p410">literal</a>\n# plain ä 😀';
PreparationBatchSection view(WidgetTester t) =>
    t.widget<PreparationBatchSection>(find.byType(PreparationBatchSection));
Future<void> settled(WidgetTester t) async {
  await wait(
    t,
    () =>
        find.byType(PreparationBatchSection).evaluate().isNotEmpty &&
        !view(t).controller.busy,
  );
  await t.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome preparation declarations, retained R1, committed response loss and exact retry, manager correction and explicit zero',
    (t) async {
      app.main();
      await login(t, 'batch_worker');
      await section(t, 'My preparation batches');
      await tap(t, find.byKey(const Key('batch-choose-recipe')));
      await settled(t);
      await tap(t, find.byKey(const Key('batch-recipe-$recipe')));
      await settled(t);
      expect(view(t).controller.selection!.revisionNumber, 1);
      expect(
        find.widgetWithText(SelectableText, 'one 30 × 40 cm tray'),
        findsOneWidget,
      );
      await enter(t, find.byKey(const Key('batch-planned')), '3');
      await tap(t, find.byKey(const Key('batch-open')));
      await settled(t);
      final id = view(t).controller.detail!.id;
      await tap(t, find.byKey(const Key('batch-instruction')));
      await settled(t);
      expect(view(t).controller.instruction!['revisionNumber'], 1);
      expect(
        view(t).controller.instruction!['warnings'],
        contains('recipe_retired'),
      );
      await visible(t, find.widgetWithText(SelectableText, instruction));
      expect(find.widgetWithText(SelectableText, instruction), findsOneWidget);
      await enter(t, find.byKey(const Key('batch-actual')), '2');
      await enter(
        t,
        find.byKey(const Key('batch-note')),
        'Completion <script>literal</script> 😀',
      );
      await tap(t, find.byKey(const Key('batch-complete')));
      await settled(t);
      final pending = view(t).controller.pending!;
      expect(pending.body['actualDeclaredBatchCount'], 2);
      await tap(t, find.byKey(const Key('batch-retry')));
      await settled(t);
      expect(view(t).controller.detail!.actual, 2);
      expect(view(t).controller.lastConfirmed!['replayed'], true);
      expect(predicate('globalThis.preparationInjected !== true'), true);
      expect(
        predicate(
          "performance.getEntriesByType('resource').every(x => !x.name.includes('invalid.example/p410'))",
        ),
        true,
      );
      await logout(t);
      await login(t, 'test_admin');
      await section(t, 'Preparation history');
      await tap(t, find.byKey(Key('batch-$id')));
      await settled(t);
      expect(view(t).controller.detail!.actual, 2);
      expect(view(t).controller.detail!.json['plannedDeclaredBatchCount'], 3);
      await enter(t, find.byKey(const Key('batch-replacement')), '1');
      await enter(
        t,
        find.byKey(const Key('batch-correction-reason')),
        'Manager reviewed declaration <script> 😀',
      );
      await tap(t, find.byKey(const Key('batch-correct')));
      expect(
        find.textContaining('Original: 2 declared Recipe batches'),
        findsOneWidget,
      );
      await tap(t, find.byKey(const Key('batch-confirm-correction')));
      await settled(t);
      expect(view(t).controller.detail!.actual, 2);
      expect(view(t).controller.detail!.effective, 1);
      final client = http.Client(),
          base = Uri.parse(const String.fromEnvironment('STOREOS_API_URL'));
      try {
        final auth = HttpStoreApi(baseUri: base, client: client),
            api = HttpPlatformApi(baseUri: base, client: client);
        final session = await auth.login(
          const LoginRequest(
            username: 'batch_worker',
            password: String.fromEnvironment('STOREOS_KNOWLEDGE_PASSWORD'),
          ),
        );
        try {
          final result = await api.post(
            session.token,
            pending.route,
            pending.body,
          );
          expect((result['batch'] as Map)['actualDeclaredBatchCount'], 2);
          expect(result['replayed'], true);
          expect(
            (await api.get(
              session.token,
              pending.route.substring(0, pending.route.lastIndexOf('/')),
            ))['effectiveDeclaredBatchCount'],
            1,
          );
        } finally {
          await auth.logout(session.token);
        }
      } finally {
        client.close();
      }
      await tap(t, find.byKey(Key('batch-$zero')));
      await settled(t);
      expect(view(t).controller.detail!.actual, 1);
      await enter(t, find.byKey(const Key('batch-replacement')), '0');
      await enter(
        t,
        find.byKey(const Key('batch-correction-reason')),
        'Reported completion in error <script> 😀',
      );
      await tap(t, find.byKey(const Key('batch-correct')));
      await tap(t, find.byKey(const Key('batch-confirm-correction')));
      await settled(t);
      expect(view(t).controller.detail!.status, 'completed');
      expect(view(t).controller.detail!.actual, 1);
      expect(view(t).controller.detail!.effective, 0);
      await tap(
        t,
        find.text(
          'Reported completion corrected to 0 declared Recipe batches.',
        ),
      );
      expect(
        find.text('Original completion: 1 declared Recipe batches'),
        findsOneWidget,
      );
      await logout(t);
    },
  );
}
