import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/ui/preparation_assignment_section.dart';
import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;
import 'preparation_batch_test.dart'
    as batch
    show tap, enter, settled, view, instruction;

@JS('eval')
external bool predicate(String expression);
const recipe = String.fromEnvironment('STOREOS_ASSIGNMENT_RECIPE'),
    employee = String.fromEnvironment('STOREOS_ASSIGNMENT_EMPLOYEE');
PreparationAssignmentSection view(WidgetTester t) =>
    t.widget(find.byType(PreparationAssignmentSection).last);
Finder get scroll => find
    .descendant(
      of: find.byType(PreparationAssignmentSection).last,
      matching: find.byType(Scrollable),
    )
    .first;
Future<void> settled(WidgetTester t) async {
  await wait(
    t,
    () =>
        find.byType(PreparationAssignmentSection).evaluate().isNotEmpty &&
        !view(t).controller.busy,
  );
  await t.pumpAndSettle();
}

Future<void> visible(WidgetTester t, Finder target) async {
  if (target.evaluate().isEmpty) {
    await t.drag(scroll, const Offset(0, 5000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(target, 200, scrollable: scroll);
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome manager assignment, Employee retained R1 literal start, committed retry, completion and manager corrections',
    (t) async {
      app.main();
      await login(t, 'test_admin');
      await section(t, 'Preparation assignments');
      await settled(t);
      await tap(t, find.byKey(const Key('assignment-choose-recipe')));
      await settled(t);
      await tap(t, find.byKey(Key('assignment-recipe-$recipe')));
      await settled(t);
      expect(view(t).controller.selection!.revisionNumber, 1);
      await tap(t, find.byKey(const Key('assignment-choose-employee')));
      await settled(t);
      await tap(t, find.byKey(Key('assignment-employee-$employee')));
      await enter(t, find.byKey(const Key('assignment-planned')), '3');
      await tap(t, find.byKey(const Key('assignment-create')));
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await t.tap(find.byKey(const Key('assignment-confirm')));
      await t.pump();
      await settled(t);
      final id = view(t).controller.confirmedId!;
      await logout(t);
      await login(t, 'assignment_worker');
      await section(t, 'Meine Arbeit');
      await t.tap(find.byKey(const Key('work-preparation-assignments')));
      await t.pump();
      await settled(t);
      await tap(t, find.byKey(Key('assignment-$id')));
      await settled(t);
      await tap(t, find.byKey(const Key('assignment-read-recipe')));
      await settled(t);
      expect(view(t).controller.instruction!['revisionNumber'], 1);
      expect(
        view(t).controller.instruction!['warnings'],
        contains('recipe_replaced'),
      );
      await visible(t, find.widgetWithText(SelectableText, batch.instruction));
      expect(
        find.widgetWithText(SelectableText, batch.instruction),
        findsOneWidget,
      );
      expect(predicate('globalThis.preparationInjected !== true'), true);
      expect(
        predicate(
          "performance.getEntriesByType('resource').every(x=>!x.name.includes('invalid.example/p410'))",
        ),
        true,
      );
      await tap(t, find.byKey(const Key('assignment-start')));
      await settled(t);
      expect(view(t).controller.pending, isNotNull);
      await tap(t, find.byKey(const Key('assignment-retry')));
      await settled(t);
      expect(view(t).controller.lastConfirmed!['replayed'], true);
      await tap(t, find.byKey(const Key('assignment-open-batch')));
      await batch.settled(t);
      await batch.enter(t, find.byKey(const Key('batch-actual')), '2');
      await batch.enter(
        t,
        find.byKey(const Key('batch-note')),
        'Actual literal <script> 😀',
      );
      await batch.tap(t, find.byKey(const Key('batch-complete')));
      await batch.settled(t);
      expect(batch.view(t).controller.detail!.actual, 2);
      await t.tap(find.byType(BackButton).last);
      await t.pump();
      await settled(t);
      await t.tap(find.byType(BackButton).last);
      await t.pumpAndSettle();
      await logout(t);
      await login(t, 'test_admin');
      await section(t, 'Preparation assignments');
      await settled(t);
      await tap(t, find.byKey(Key('assignment-$id')));
      await settled(t);
      await tap(t, find.byKey(const Key('assignment-open-batch')));
      await batch.settled(t);
      for (final count in [1, 0]) {
        await batch.enter(
          t,
          find.byKey(const Key('batch-replacement')),
          '$count',
        );
        await batch.enter(
          t,
          find.byKey(const Key('batch-correction-reason')),
          'Reviewed $count literal <script> 😀',
        );
        await batch.tap(t, find.byKey(const Key('batch-correct')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('batch-confirm-correction')));
        await t.pump();
        await batch.settled(t);
        expect(batch.view(t).controller.detail!.actual, 2);
        expect(batch.view(t).controller.detail!.effective, count);
      }
      await t.tap(find.byType(BackButton).last);
      await t.pump();
      await settled(t);
      await tap(t, find.byKey(const Key('assignment-history')));
      await settled(t);
      expect(view(t).controller.detail!.status, 'started');
      expect(
        (view(t).controller.detail!.json['batch'] as Map)['corrections'],
        hasLength(2),
      );
      expect(view(t).controller.history, isNotNull);
      await logout(t);
    },
  );
}
