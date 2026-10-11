import 'dart:js_interop';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/ui/shift_section.dart';
import 'package:storeos_client/src/ui/shift_transfer_section.dart';
import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;

@JS('eval')
external bool predicate(String expression);
const shift = String.fromEnvironment('STOREOS_TRANSFER_SHIFT'),
    recipient = String.fromEnvironment('STOREOS_TRANSFER_RECIPIENT');
ShiftTransferSection transfer(WidgetTester t) =>
    t.widget<ShiftTransferSection>(find.byType(ShiftTransferSection));
ShiftSection work(WidgetTester t) =>
    t.widget<ShiftSection>(find.byType(ShiftSection).last);
Future<void> settled(WidgetTester t) async {
  await wait(
    t,
    () =>
        find.byType(ShiftTransferSection).evaluate().isNotEmpty &&
        !transfer(t).controller.busy,
  );
  await t.pumpAndSettle();
}

Future<void> visible(WidgetTester t, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byType(ShiftTransferSection).evaluate().isNotEmpty
            ? find.byType(ShiftTransferSection)
            : find.byType(ShiftSection),
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    await t.drag(scroll, const Offset(0, 5000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(target, 200, scrollable: scroll);
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder target) async {
  await visible(t, target);
  await t.tap(target);
  await t.pump();
}

Future<void> confirm(WidgetTester t, String action) async {
  await tap(t, find.byKey(Key('transfer-$action')));
  await t.pumpAndSettle();
  await t.tap(find.widgetWithText(FilledButton, 'Confirm'));
  await t.pump();
  await settled(t);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome exact proposal, consent, independent approval, lost response restart retry and replacement execution',
    (t) async {
      app.main();
      await login(t, 'guided_worker');
      await section(t, 'Meine Arbeit');
      await tap(t, find.byKey(const Key('shift-$shift')));
      await wait(t, () => !work(t).controller.busy);
      await tap(t, find.byKey(const Key('propose-transfer')));
      await settled(t);
      expect(transfer(t).controller.source!.id, shift);
      expect(
        transfer(t).controller.sourceTasks.single['knowledgeGuidance'],
        isNotNull,
      );
      expect(
        transfer(t).controller.sourceTasks.single['planogramGuidance'],
        isNotNull,
      );
      await tap(t, find.byKey(const Key('transfer-recipient-$recipient')));
      await confirm(t, 'propose');
      final id = transfer(t).controller.detail!.id;
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await logout(t);
      await login(t, 'transfer_recipient');
      await section(t, 'My shift transfers');
      await tap(t, find.byKey(Key('transfer-$id')));
      await settled(t);
      await confirm(t, 'accept');
      expect(transfer(t).controller.detail!.status, 'accepted');
      await logout(t);
      await login(t, 'test_admin');
      await section(t, 'Shift transfer review');
      await tap(t, find.byKey(Key('transfer-$id')));
      await settled(t);
      await confirm(t, 'approve');
      expect(transfer(t).controller.pending, isNotNull);
      await tap(t, find.widgetWithText(FilledButton, 'Retry exact command'));
      await settled(t);
      expect(transfer(t).controller.error, isNull);
      expect(transfer(t).controller.lastConfirmed!['replayed'], true);
      final b =
          transfer(t).controller.detail!.json['replacementShiftId'] as String;
      await logout(t);
      await login(t, 'guided_worker');
      await section(t, 'Meine Arbeit');
      expect(find.byKey(const Key('shift-$shift')), findsNothing);
      await logout(t);
      await login(t, 'transfer_recipient');
      await section(t, 'Meine Arbeit');
      await tap(t, find.byKey(Key('shift-$b')));
      await wait(t, () => !work(t).controller.busy);
      final task = work(t).controller.tasks.single.id;
      await tap(t, find.byKey(Key('task-$task')));
      await wait(t, () => !work(t).controller.busy);
      final begins = work(t).controller.selected!.draft.startsAt;
      // This waits for the real scheduled execution interval, not race ordering.
      // The server still authorizes start against authoritative database time.
      final executionDeadline = DateTime.now().add(const Duration(minutes: 2));
      while (DateTime.now().toUtc().isBefore(begins)) {
        if (DateTime.now().isAfter(executionDeadline)) {
          fail('Scheduled replacement execution interval was not reached.');
        }
        await t.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await tap(t, find.byKey(const Key('start-task')));
      await wait(t, () => !work(t).controller.busy);
      expect(work(t).controller.execution!.status, 'in_progress');
      await tap(t, find.byKey(const Key('confirm-step')));
      await wait(t, () => !work(t).controller.busy);
      final number = find.byWidgetPredicate(
        (w) => w is TextFormField && w.key.toString().contains('number-'),
      );
      await visible(t, number);
      await t.enterText(number, '3');
      await tap(t, find.byKey(const Key('record-number')));
      await wait(t, () => !work(t).controller.busy);
      await tap(t, find.byKey(const Key('complete-task')));
      await wait(t, () => !work(t).controller.busy);
      expect(work(t).controller.execution!.status, 'completed');
      await logout(t);
      await login(t, 'guided_worker');
      await section(t, 'My shift transfers');
      await tap(t, find.byKey(Key('transfer-$id')));
      await settled(t);
      expect(
        jsonEncode(transfer(t).controller.detail!.json),
        isNot(contains('"results"')),
      );
      expect(
        jsonEncode(transfer(t).controller.detail!.json),
        isNot(contains('"value"')),
      );
      final extras =
          jsonDecode(const String.fromEnvironment('STOREOS_TRANSFER_EXTRAS'))
              as Map;
      Future<void> decision(
        String kind,
        String actor,
        String action,
        String expected, {
        bool reason = false,
      }) async {
        await logout(t);
        await login(t, actor);
        await section(
          t,
          actor == 'test_admin'
              ? 'Shift transfer review'
              : 'My shift transfers',
        );
        await tap(t, find.byKey(Key('transfer-${extras[kind]['requestId']}')));
        await settled(t);
        if (reason) {
          final field = find.byKey(const Key('transfer-reason'));
          await visible(t, field);
          await t.enterText(field, 'Coverage changed <literal>');
        }
        await confirm(t, action);
        expect(transfer(t).controller.detail!.status, expected);
      }

      await decision('decline', 'transfer_recipient', 'decline', 'declined');
      await decision(
        'source_withdraw',
        'guided_worker',
        'withdraw',
        'withdrawn',
        reason: true,
      );
      await decision(
        'recipient_withdraw',
        'transfer_recipient',
        'withdraw',
        'withdrawn',
        reason: true,
      );
      await decision(
        'reject',
        'test_admin',
        'reject',
        'rejected',
        reason: true,
      );
      for (final kind in ['overlap', 'stale', 'guidance']) {
        await tap(t, find.byKey(Key('transfer-${extras[kind]['requestId']}')));
        await settled(t);
        await confirm(t, 'approve');
        final code = switch (kind) {
          'overlap' => 'shift_overlap',
          'stale' => 'shift_conflict',
          _ => 'guidance_unavailable',
        };
        expect(transfer(t).controller.error, contains(code));
        expect(transfer(t).controller.pending, isNull);
        expect(transfer(t).controller.detail, isNull);
      }
      expect(
        predicate(
          "performance.getEntriesByType('resource').every(x => !x.name.includes('invalid.example'))",
        ),
        true,
      );
    },
  );
}
