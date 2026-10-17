import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/platform_home_screen.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'package:storeos_client/src/ui/shift_swap_section.dart';

import 'knowledge_test.dart' show login, section, wait;
import 'recipe_test.dart' show logout;

@JS('eval')
external bool predicate(String expression);
const shiftA = String.fromEnvironment('STOREOS_SWAP_SHIFT_A'),
    shiftB = String.fromEnvironment('STOREOS_SWAP_SHIFT_B'),
    employeeB = String.fromEnvironment('STOREOS_SWAP_EMPLOYEE_B'),
    url = String.fromEnvironment('STOREOS_SWAP_BROWSER_URL');
ShiftSwapSection swaps(WidgetTester t) =>
    t.widget<ShiftSwapSection>(find.byType(ShiftSwapSection).last);
ShiftSection work(WidgetTester t) =>
    t.widget<ShiftSection>(find.byType(ShiftSection).last);
Future<void> settled(WidgetTester t) async {
  await wait(
    t,
    () =>
        find.byType(ShiftSwapSection).evaluate().isNotEmpty &&
        !swaps(t).controller.busy,
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, Finder target) async {
  final scroll = find
      .descendant(
        of: find.byType(ShiftSwapSection).evaluate().isNotEmpty
            ? find.byType(ShiftSwapSection).last
            : find.byType(ShiftSection).last,
        matching: find.byType(Scrollable),
      )
      .first;
  if (target.evaluate().isEmpty) {
    await t.drag(scroll, const Offset(0, 200000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      target,
      1600,
      scrollable: scroll,
      maxScrolls: 500,
    );
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pump();
}

Future<void> act(WidgetTester t, String action, {bool reason = false}) async {
  await tap(t, find.byKey(Key('swap-$action')));
  await t.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  if (reason) {
    await t.enterText(
      find.byKey(const Key('swap-reason')),
      'Coverage changed <script>literal</script> ä😀',
    );
  }
  await t.ensureVisible(find.byKey(const Key('swap-dialog-confirm')));
  await t.tap(find.byKey(const Key('swap-dialog-confirm')));
  await t.pump();
  await settled(t);
}

Future<void> denied(Future<Object?> Function() call, Set<int> statuses) async {
  try {
    await call();
    fail('Unauthorized request succeeded.');
  } on StoreApiException catch (e) {
    expect(statuses, contains(e.statusCode));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'four actors exchange exact ten-Task legs, retry uncertain approval and execute both replacements',
    (t) async {
      app.main();
      await login(t, 'swap_fixture_a');
      await section(t, 'Meine Arbeit');
      await tap(t, find.byKey(const Key('shift-$shiftA')));
      await wait(t, () => !work(t).controller.busy);
      expect(find.byKey(const Key('propose-transfer')), findsOneWidget);
      await tap(t, find.byKey(const Key('request-swap')));
      await settled(t);
      expect(swaps(t).controller.source!.id, shiftA);
      expect(swaps(t).controller.sourceWork, hasLength(10));
      await tap(t, find.byKey(const Key('swap-colleague-$employeeB')));
      await act(t, 'request');
      final c = swaps(t).controller,
          id = c.detail!.json['request']['id'] as String;
      expect(
        c.detail!.json['request']['sourceName'],
        'A ${'ä😀長 <script>literal</script> ' * 3}'.trim(),
      );
      expect(
        c.detail!.json['request']['recipientName'],
        'B ${'ä😀長 <script>literal</script> ' * 3}'.trim(),
      );
      expect(
        c.detail!.json['request']['legs'][0]['tasks'][0]['title'],
        'ä😀 長 <script>globalThis.swapInjected=true</script> **literal**',
      );
      await denied(
        () => c.session.authorized(
          (token) => c.api.get(token, '/me/shift-swaps/$id/counterparts'),
        ),
        {404},
      );
      await denied(
        () => c.session.authorized(
          (token) =>
              c.api.get(token, '/employee-home/shifts/$shiftB/swap-colleagues'),
        ),
        {404},
      );
      await denied(
        () => c.session.authorized(
          (token) => c.api.get(
            token,
            '/locations/00000000-0000-4000-8000-000000000099/shift-swaps',
          ),
        ),
        {403},
      );
      await t.tap(find.byType(BackButton));
      await t.pumpAndSettle();
      await logout(t);
      await login(t, 'swap_fixture_b');
      await section(t, 'Meine Schichttausche');
      await tap(t, find.byKey(Key('swap-$id')));
      await settled(t);
      expect(swaps(t).controller.detail!.json['participantRole'], 'recipient');
      await tap(t, find.byKey(const Key('swap-counterparts')));
      await settled(t);
      expect(swaps(t).controller.counterparts.map((r) => r['shiftId']), [
        shiftB,
      ]);
      await tap(t, find.byKey(const Key('swap-counterpart-$shiftB')));
      await settled(t);
      final pairB = swaps(t).controller.selectedCounterpart!.json;
      await act(t, 'offer');
      expect(swaps(t).controller.detail!.json['request']['legs'][1], pairB);
      await logout(t);
      await login(t, 'swap_fixture_a');
      await section(t, 'Meine Schichttausche');
      await tap(t, find.byKey(Key('swap-$id')));
      await settled(t);
      await tap(t, find.byKey(const Key('swap-confirm')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('Ihre Originalarbeit geht an B'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('swap-cancel')));
      await t.pumpAndSettle();
      expect(swaps(t).controller.detail!.json['request']['status'], 'offered');
      await act(t, 'confirm');
      expect(
        swaps(t).controller.detail!.json['request']['status'],
        'confirmed',
      );
      // A is also an admin in this fixture; independent approval still excludes A.
      await section(t, 'Schichttausch prüfen');
      await tap(t, find.byKey(Key('swap-$id')));
      await settled(t);
      final participantManager = swaps(t).controller;
      expect(participantManager.can('manager_approve'), false);
      await denied(
        () => participantManager.session.authorized(
          (token) => participantManager.api.post(
            token,
            '/locations/${participantManager.session.user!.locationId}/shift-swaps/$id/approve',
            {
              'operationId': '00000000-0000-4000-8000-000000000077',
              'expectedVersion': 3,
            },
          ),
        ),
        {403},
      );
      await logout(t);
      await login(t, 'test_admin');
      await section(t, 'Schichttausch prüfen');
      await tap(t, find.byKey(Key('swap-$id')));
      await settled(t);
      await act(t, 'approve');
      expect(swaps(t).controller.pending, isNotNull);
      final original = swaps(t).controller.pending!;
      await tap(t, find.byKey(const Key('swap-retry')));
      await settled(t);
      expect(swaps(t).controller.lastConfirmed!.json['replayed'], true);
      expect(
        swaps(t).controller.lastConfirmed!.json['operationId'],
        original.operationId,
      );
      final legs = swaps(t).controller.detail!.json['request']['legs'] as List;
      expect(legs.every((l) => (l['taskLinks'] as List).length == 10), true);
      expect(swaps(t).controller.can('manager_approve'), false);
      final incomingA = legs[1]['replacementShiftId'] as String,
          incomingB = legs[0]['replacementShiftId'] as String;
      for (final entry in [
        ('swap_fixture_a', incomingA),
        ('swap_fixture_b', incomingB),
      ]) {
        await logout(t);
        await login(t, entry.$1);
        await section(t, 'Meine Arbeit');
        await tap(t, find.byKey(Key('shift-${entry.$2}')));
        await wait(t, () => !work(t).controller.busy);
        expect(work(t).controller.tasks, hasLength(10));
        final task = work(t).controller.tasks.first.id;
        await tap(t, find.byKey(Key('task-$task')));
        await wait(t, () => !work(t).controller.busy);
        final begins = work(t).controller.selected!.draft.startsAt,
            deadline = DateTime.now().add(const Duration(minutes: 3));
        while (DateTime.now().toUtc().isBefore(begins)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Replacement interval not reached.');
          }
          await t.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await tap(t, find.byKey(const Key('start-task')));
        await wait(t, () => !work(t).controller.busy);
        await tap(t, find.byKey(const Key('confirm-step')));
        await wait(t, () => !work(t).controller.busy);
        await tap(t, find.byKey(const Key('complete-task')));
        await wait(t, () => !work(t).controller.busy);
        expect(work(t).controller.execution!.status, 'completed');
      }
      // Hold a completed real HTTP detail response across a same-scope context replacement.
      await section(t, 'Meine Schichttausche');
      final fenced = swaps(t).controller;
      await http.get(Uri.parse('$url/__swap_probe/arm'));
      final oldRead = fenced.select(id);
      await http.get(Uri.parse('$url/__swap_probe/held'));
      fenced.platform.context = fenced.platform.context;
      await http.get(Uri.parse('$url/__swap_probe/release'));
      await oldRead;
      await t.pumpAndSettle();
      expect(fenced.detail, isNull);
      expect(fenced.pending, isNull);
      final extras =
          jsonDecode(const String.fromEnvironment('STOREOS_SWAP_EXTRAS'))
              as Map;
      for (final kind in ['decline', 'withdraw', 'reject', 'stale']) {
        await logout(t);
        await login(
          t,
          kind == 'withdraw'
              ? 'swap_fixture_a'
              : kind == 'reject' || kind == 'stale'
              ? 'test_admin'
              : 'swap_fixture_b',
        );
        await section(
          t,
          kind == 'reject' || kind == 'stale'
              ? 'Schichttausch prüfen'
              : 'Meine Schichttausche',
        );
        await tap(t, find.byKey(Key('swap-${extras[kind]}')));
        await settled(t);
        await act(
          t,
          kind == 'stale' ? 'reject' : kind,
          reason: {'withdraw', 'reject', 'stale'}.contains(kind),
        );
        if (kind == 'stale') {
          expect(swaps(t).controller.error, isNotNull);
          expect(swaps(t).controller.detail, isNull);
          await swaps(t).controller.select(extras[kind] as String);
          await settled(t);
          expect(
            swaps(t).controller.detail!.json['request']['status'],
            'offered',
          );
          await act(t, 'reject', reason: true);
        }
        expect(
          swaps(t).controller.detail!.json['request']['status'],
          switch (kind) {
            'decline' => 'declined',
            'withdraw' => 'withdrawn',
            _ => 'rejected',
          },
        );
      }
      final home = t.widget<PlatformHomeScreen>(
        find.byType(PlatformHomeScreen),
      );
      final auth = HttpStoreApi(baseUri: Uri.parse(url), client: http.Client());
      await home.session.authorized(auth.logout);
      await home.ownSwaps!.load();
      await t.pumpAndSettle();
      expect(home.session.isAuthenticated, false);
      await login(t, 'swap_observer');
      final observer = t.widget<PlatformHomeScreen>(
        find.byType(PlatformHomeScreen),
      );
      expect(observer.platform.allows('workforce.swaps.self.read'), false);
      expect(observer.platform.allows('workforce.swaps.manage'), false);
      final drawer = find.byKey(const Key('open-navigation'));
      if (drawer.evaluate().isNotEmpty) {
        await t.tap(drawer);
        await t.pumpAndSettle();
      }
      expect(find.text('Meine Schichttausche'), findsNothing);
      expect(find.text('Schichttausch prüfen'), findsNothing);
      expect(predicate('globalThis.swapInjected !== true'), true);
      expect(t.takeException(), isNull);
    },
  );
}
