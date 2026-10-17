import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_models.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_swap_section.dart';

import 'shift_swap_fixture.dart';
import 'shift_swap_ui_fixture.dart';
import 'shift_swap_test.dart' as fixture;

Future<void> mount(WidgetTester t, SwapUiHarness h) async {
  await t.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ShiftSwapSection(controller: h.controller)),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> tap(WidgetTester t, String key) async {
  final target = find.byKey(Key(key));
  if (target.evaluate().isEmpty) {
    final scroll = find.byKey(const Key('swap-scroll'));
    await t.drag(scroll, const Offset(0, 20000));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      target,
      2000,
      scrollable: find
          .descendant(of: scroll, matching: find.byType(Scrollable))
          .first,
      maxScrolls: 500,
    );
  }
  await t.ensureVisible(target);
  await t.pumpAndSettle();
  await t.tap(target);
  await t.pump();
}

Future<void> act(WidgetTester t, String action, {String? reason}) async {
  await tap(t, 'swap-$action');
  await t.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
  if (reason != null) {
    await t.enterText(find.byKey(const Key('swap-reason')), reason);
  }
  await tap(t, 'swap-dialog-confirm');
  await t.pumpAndSettle();
}

void clean(WidgetTester t, SwapUiHarness h) {
  h.tester = t;
  addTearDown(() async {
    await t.pumpWidget(const SizedBox.shrink());
    h.dispose();
    expect(t.takeException(), isNull);
  });
}

void main() {
  testWidgets(
    'Employee A reviews own work and sends one exact named invitation',
    (t) async {
      final h = SwapUiHarness(role: 'source');
      clean(t, h);
      await h.login();
      await h.controller.chooseSource(h.ownShift);
      await mount(t, h);
      expect(h.controller.sourceWork.single.id, swapId(120));
      await tap(t, 'swap-colleague-${swapId(5)}');
      await tap(t, 'swap-request');
      await t.pumpAndSettle();
      expect(find.textContaining('Diese Einladung ändert'), findsOneWidget);
      expect(find.textContaining('Exact work 0'), findsWidgets);
      await tap(t, 'swap-dialog-confirm');
      await t.pumpAndSettle();
      expect(h.posts, hasLength(1));
      final body = jsonDecode(h.posts.single.body) as Map;
      expect(body['sourceShiftId'], swapId(20));
      expect(body['expectedSourceVersion'], 2);
      expect(body['recipientEmployeeId'], swapId(5));
      expect(h.controller.lastConfirmed!.request.json['status'], 'requested');
    },
  );

  testWidgets(
    'Recipient B discovers only own candidates and offers selected exact evidence',
    (t) async {
      final h = SwapUiHarness();
      clean(t, h);
      await h.start();
      await mount(t, h);
      await tap(t, 'swap-counterparts');
      await t.pumpAndSettle();
      await tap(t, 'swap-counterpart-${swapId(40)}');
      await t.pumpAndSettle();
      await act(t, 'offer');
      expect(h.posts.single.url.path, endsWith('/offer'));
      expect(jsonDecode(h.posts.single.body)['counterpartShiftId'], swapId(40));
      expect(jsonDecode(h.posts.single.body)['expectedCounterpartVersion'], 2);
      expect(h.controller.lastConfirmed!.request.json['legs'], hasLength(2));
    },
  );

  for (final scenario in [
    ('source', 'offered', 2, 'confirm', 'confirmed', true),
    ('recipient', 'requested', 1, 'decline', 'declined', true),
    ('source', 'offered', 2, 'decline', 'declined', true),
    ('source', 'confirmed', 3, 'withdraw', 'withdrawn', true),
    ('recipient', 'offered', 2, 'withdraw', 'withdrawn', true),
    ('manager', 'confirmed', 3, 'approve', 'approved', false),
    ('manager', 'confirmed', 3, 'reject', 'rejected', false),
  ]) {
    testWidgets(
      '${scenario.$1} ${scenario.$4} binds exact pair, route, version and terminal evidence',
      (t) async {
        final h = SwapUiHarness(
          role: scenario.$1,
          state: scenario.$2,
          stage: scenario.$3,
          self: scenario.$6,
        );
        clean(t, h);
        await h.start();
        await mount(t, h);
        final reads = h.reads.length;
        await act(
          t,
          scenario.$4,
          reason: {'withdraw', 'reject'}.contains(scenario.$4)
              ? 'Coverage changed'
              : null,
        );
        expect(h.posts, hasLength(1));
        final body = jsonDecode(h.posts.single.body) as Map;
        expect(body['expectedVersion'], scenario.$3);
        expect(body.containsKey('actor'), false);
        expect(body.containsKey('kind'), false);
        expect(h.posts.single.url.path, endsWith('/${scenario.$4}'));
        expect(h.controller.lastConfirmed!.request.json['status'], scenario.$5);
        if (!scenario.$6) expect(h.reads.length, greaterThan(reads + 1));
        if (scenario.$4 == 'approve') {
          final legs = h.controller.detail!.json['request']['legs'] as List;
          expect(legs.map((l) => l['replacementShiftId']), [
            swapId(30),
            swapId(50),
          ]);
          expect(legs.every((l) => (l['taskLinks'] as List).length == 1), true);
          expect(h.controller.can('manager_approve'), false);
        }
        await tap(t, 'swap-history');
        await t.pumpAndSettle();
        expect(h.controller.history, hasLength(2));
        if (h.controller.historyCursor != null) {
          await tap(t, 'swap-history-more');
          await t.pumpAndSettle();
        }
        expect(h.controller.history, hasLength(h.evidence['version'] as int));
      },
    );
  }

  testWidgets(
    'Reason contract validates trimmed Unicode scalar bound and cancellation writes nothing',
    (t) async {
      final h = SwapUiHarness(role: 'source');
      clean(t, h);
      await h.start();
      await mount(t, h);
      await tap(t, 'swap-withdraw');
      await t.pumpAndSettle();
      await tap(t, 'swap-dialog-confirm');
      await t.pumpAndSettle();
      expect(h.posts, isEmpty);
      await t.enterText(find.byKey(const Key('swap-reason')), '😀' * 501);
      await tap(t, 'swap-dialog-confirm');
      await t.pumpAndSettle();
      expect(h.posts, isEmpty);
      await tap(t, 'swap-cancel');
      await t.pumpAndSettle();
      expect(h.posts, isEmpty);
      await act(t, 'withdraw', reason: '  ${'😀' * 500}  ');
      expect(
        (jsonDecode(h.posts.single.body)['reason'] as String).runes.length,
        500,
      );
    },
  );

  testWidgets(
    'Unknown command, later denial and absent receipt retain original intent; exact retry resolves',
    (t) async {
      final h = SwapUiHarness(role: 'source', state: 'offered', stage: 2);
      clean(t, h);
      await h.start();
      await mount(t, h);
      h.postError = Exception('lost response');
      await act(t, 'confirm');
      final pending = h.controller.pending!,
          first = h.posts.single.body,
          ids = h.ids;
      expect(find.byKey(const Key('swap-uncertain')), findsOneWidget);
      h.postError = null;
      h.postStatus = 403;
      await tap(t, 'swap-retry');
      await t.pumpAndSettle();
      expect(
        h.controller.pending!.state,
        SwapSubmission.reconciliationRequired,
      );
      await tap(t, 'swap-reconcile');
      await t.pumpAndSettle();
      expect(h.controller.pending!.operationId, pending.operationId);
      expect(h.controller.locked, true);
      expect(h.ids, ids);
      h.postStatus = null;
      await tap(t, 'swap-retry');
      await t.pumpAndSettle();
      expect(h.posts.map((r) => r.body), everyElement(first));
      expect(h.ids, ids);
      expect(h.controller.pending, isNull);
      expect(h.controller.lastConfirmed, isNotNull);
    },
  );

  testWidgets(
    'Receipt reconciliation confirms original accepted evidence without another POST',
    (t) async {
      final h = SwapUiHarness(role: 'source', state: 'offered', stage: 2);
      clean(t, h);
      await h.start();
      await mount(t, h);
      h.postError = Exception('lost');
      await act(t, 'confirm');
      final pending = h.controller.pending!;
      h.accept('${h.root}/${h.id}/confirm', pending.body);
      h.postError = null;
      await tap(t, 'swap-reconcile');
      await t.pumpAndSettle();
      expect(h.posts, hasLength(1));
      expect(h.controller.pending, isNull);
      expect(
        h.controller.lastConfirmed!.json['operationId'],
        pending.operationId,
      );
    },
  );

  testWidgets(
    'Accepted approval survives failed refresh and cannot be approved again',
    (t) async {
      final h = SwapUiHarness(
        role: 'manager',
        state: 'confirmed',
        stage: 3,
        self: false,
      );
      clean(t, h);
      await h.start();
      await mount(t, h);
      await tap(t, 'swap-approve');
      await t.pumpAndSettle();
      h.readError = Exception('refresh unavailable');
      await tap(t, 'swap-dialog-confirm');
      await t.pumpAndSettle();
      expect(h.controller.lastConfirmed!.request.json['status'], 'approved');
      expect(h.controller.detail, isNull);
      expect(h.controller.pending, isNull);
      expect(h.posts, hasLength(1));
      expect(find.byKey(const Key('swap-refresh-warning')), findsOneWidget);
      expect(h.controller.can('manager_approve'), false);
    },
  );

  testWidgets(
    'Stale version refusal removes action evidence and requires fresh confirmation',
    (t) async {
      final h = SwapUiHarness(role: 'source', state: 'offered', stage: 2);
      clean(t, h);
      await h.start();
      await mount(t, h);
      h.postStatus = 409;
      await act(t, 'confirm');
      expect(h.controller.detail, isNull);
      expect(h.controller.pending, isNull);
      expect(h.controller.can('confirm'), false);
      expect(h.posts, hasLength(1));
      h.postStatus = null;
      await h.controller.select(h.id);
      await t.pumpAndSettle();
      expect(h.posts, hasLength(1));
      await act(t, 'confirm');
      expect(h.posts, hasLength(2));
    },
  );

  testWidgets(
    'Double activation opens one dialog and held submission suppresses duplicates',
    (t) async {
      final h = SwapUiHarness(role: 'source', state: 'offered', stage: 2);
      clean(t, h);
      await h.start();
      await mount(t, h);
      await tap(t, 'swap-confirm');
      await t.pumpAndSettle();
      h.postHold = Completer<http.Response>();
      await tap(t, 'swap-dialog-confirm');
      await t.pump();
      expect(h.posts, hasLength(1));
      expect(h.controller.busy, true);
      expect(h.controller.locked, true);
      h.postHold!.complete(
        fixture.response(
          h.accept(
            '${h.root}/${h.id}/confirm',
            jsonDecode(h.posts.single.body),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(h.posts, hasLength(1));
    },
  );

  for (final action in ['request', 'offer', 'confirm', 'approve', 'withdraw']) {
    for (final change in [
      'context',
      'location',
      'logout',
      'expiry',
      'same-account',
      'different-account',
      'selection',
      'dispose',
    ]) {
      testWidgets(
        '$action modal fences $change and clears private evidence/reason',
        (t) async {
          final h = SwapUiHarness(
            role: action == 'offer'
                ? 'recipient'
                : action == 'approve'
                ? 'manager'
                : 'source',
            state: action == 'offer' || action == 'request'
                ? 'requested'
                : action == 'approve'
                ? 'confirmed'
                : 'offered',
            stage: action == 'offer' || action == 'request'
                ? 1
                : action == 'approve'
                ? 3
                : 2,
            self: action != 'approve',
          );
          clean(t, h);
          await h.start();
          if (action == 'offer') await h.prepare('offer');
          if (action == 'request') await h.prepare('request');
          await mount(t, h);
          await tap(t, 'swap-$action');
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsOneWidget);
          if (action == 'withdraw') {
            await t.enterText(
              find.byKey(const Key('swap-reason')),
              'PRIVATE DIALOG REASON',
            );
          }
          if (change == 'context' || change == 'location') {
            final old = h.platform.context!;
            h.platform.context = PlatformContext(
              userId: old.userId,
              companyId: old.companyId,
              locationId: change == 'location' ? swapId(99) : old.locationId,
              role: old.role,
              permissions: old.permissions,
            );
          } else if (change == 'logout') {
            await h.session.signOut();
          } else if (change == 'expiry') {
            h.auth.now = h.auth.now.add(const Duration(hours: 2));
            await expectLater(
              h.session.authorized((_) async => null),
              throwsA(isA<StoreApiException>()),
            );
          } else if (change == 'dispose') {
            h.controller.dispose();
          } else if (change == 'selection') {
            await h.controller.select(h.id);
          } else {
            if (change == 'different-account') h.auth.account = swapId(88);
            await h.login();
          }
          await t.pumpAndSettle();
          expect(find.byType(AlertDialog), findsNothing);
          expect(find.text('PRIVATE DIALOG REASON'), findsNothing);
          expect(h.posts, isEmpty);
          if (change != 'selection') expect(h.controller.detail, isNull);
        },
      );
    }
  }

  testWidgets(
    'Loading, empty, error retry, status/direction filters and opaque page cursor',
    (t) async {
      final h = SwapUiHarness();
      clean(t, h);
      await h.login();
      h.showList = false;
      h.readHold = Completer<http.Response>();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSwapSection(controller: h.controller)),
        ),
      );
      await t.pump();
      expect(find.byKey(const Key('swap-loading')), findsOneWidget);
      h.readHold!.complete(fixture.response({'items': [], 'nextCursor': null}));
      h.readHold = null;
      await t.pumpAndSettle();
      expect(find.byKey(const Key('swap-empty')), findsOneWidget);
      h.readError = Exception('offline');
      await tap(t, 'swap-refresh');
      await t.pumpAndSettle();
      expect(find.byKey(const Key('swap-error')), findsOneWidget);
      h.readError = null;
      h.read = (r) async => fixture.response({
        'items': [h.evidence],
        'nextCursor': r.url.queryParameters['after'] == null ? 'opaque' : null,
      });
      await tap(t, 'swap-direction-incoming');
      await t.pumpAndSettle();
      await tap(t, 'swap-status-requested');
      await t.pumpAndSettle();
      expect(h.reads.last.url.queryParameters, {
        'direction': 'incoming',
        'status': 'requested',
      });
      await tap(t, 'swap-more');
      await t.pumpAndSettle();
      expect(h.reads.last.url.queryParameters['after'], 'opaque');
      expect(h.controller.items, hasLength(1));
    },
  );

  testWidgets(
    'Two ten-task legs, long Unicode names, literal pins and terminal lineage fit narrow scaled layout',
    (t) async {
      final h = SwapUiHarness(
        role: 'manager',
        state: 'approved',
        stage: 3,
        self: false,
      );
      clean(t, h);
      h.evidence = swapEvidence(state: 'approved', stage: 3, tasks: 10);
      h.evidence['sourceName'] = '😀長 <script>plain</script> ' * 4;
      h.evidence['recipientName'] = 'Ä <a href="x">literal</a> ' * 4;
      for (final leg in h.evidence['legs'] as List) {
        for (final task in leg['tasks'] as List) {
          task['title'] = '😀ä長 <script>literal</script> **plain** ' * 2;
          task['knowledgeGuidance'] = {
            'articleId': swapId(700),
            'revisionId': swapId(701),
          };
          task['planogramGuidance'] = {
            'fixtureId': swapId(702),
            'assignmentId': swapId(703),
            'revisionId': swapId(704),
          };
        }
      }
      ShiftSwapDetailDto.fromJson(h.detail());
      await h.start();
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(body: ShiftSwapSection(controller: h.controller)),
          ),
        ),
      );
      await t.pumpAndSettle();
      await tap(t, 'swap-history');
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(h.controller.detail!.json['request']['legs'], hasLength(2));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );

  test(
    'Own work read is immutable, exact-version checked and fenced after held response',
    () async {
      final h = SwapUiHarness(role: 'source');
      addTearDown(h.dispose);
      await h.login();
      await h.controller.chooseSource(h.ownShift);
      await h.controller.loadSourceWork();
      expect(h.controller.sourceWork.single.content!.title, 'Exact work 0');
      expect(() => h.controller.sourceWork.clear(), throwsUnsupportedError);
      h.sourceChanged = true;
      await h.controller.loadSourceWork();
      expect(h.controller.sourceWork, isEmpty);
      expect(h.controller.error, isNotNull);
      h.sourceChanged = false;
      h.workHold = Completer<http.Response>();
      final read = h.controller.loadSourceWork();
      h.platform.context = h.platform.context;
      h.workHold!.complete(
        fixture.response({
          'shift': h.ownShift.toJson(),
          'tasks': [h.ownTask],
        }),
      );
      await read;
      expect(h.controller.sourceWork, isEmpty);
      expect(h.controller.source, isNull);
    },
  );
}
