import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/employee_controller.dart';
import 'package:storeos_client/src/application/platform_models.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/application/shift_transfer_controller.dart';
import 'package:storeos_client/src/ui/platform_home_screen.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'package:storeos_client/src/ui/shift_swap_section.dart';
import 'package:storeos_client/src/ui/shift_transfer_section.dart';

import 'shift_swap_fixture.dart';
import 'shift_swap_test.dart' as fixture;
import 'shift_swap_ui_fixture.dart';
import 'shift_swap_ui_test.dart' as ui;

class _Routes extends NavigatorObserver {
  final pages = <Route<dynamic>>[];
  int pushes = 0;
  void Function()? onPush, onPop;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) {
      pages.add(route);
      pushes++;
      onPush?.call();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pages.remove(route);
    onPop?.call();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      pages.remove(route);
}

class _Swaps extends ShiftSwapController {
  _Swaps(SwapUiHarness h)
    : super(h.session, h.platform, h.api, idFactory: () => swapId(++h.ids));
  int loads = 0;
  bool throwSource = false;
  final gates = <int, Completer<void>>{};
  final loaded = <int, Completer<void>>{};
  @override
  Future<void> chooseSource(ShiftDto shift, {bool more = false}) async {
    final load = ++loads;
    if (throwSource) {
      throw StateError('Injected navigation preflight exception');
    }
    await super.chooseSource(shift, more: more);
    loaded[load]?.complete();
    await gates[load]?.future;
  }
}

class _Probe {
  _Probe(this.t) {
    h = SwapUiHarness(role: 'source')..tester = t;
    h.grants.addAll([
      'workforce.shifts.self.read',
      'workforce.transfers.self.read',
      'workforce.transfers.self.request',
    ]);
  }
  final WidgetTester t;
  late final SwapUiHarness h;
  late final _Swaps swaps;
  late final ShiftController home;
  late final EmployeeController employees;
  late final ShiftTransferController transfers;
  final routes = _Routes();
  final navigator = GlobalKey<NavigatorState>();
  late Future<void> Function(ShiftDto) callback;
  Future<void> open() => callback(h.ownShift);

  Future<void> mount() async {
    final warningPolicy = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    await h.login();
    swaps = _Swaps(h);
    home = ShiftController(h.session, h.platform, h.api, self: true);
    employees = EmployeeController(h.session, h.platform, h.api);
    transfers = ShiftTransferController(h.session, h.platform, h.api);
    h.read = (r) async {
      if (r.url.path.endsWith('/transfer-recipients')) {
        return fixture.response({
          'shift': h.ownShift.toJson(),
          'sourceName': 'A',
          'tasks': (swapEvidence()['legs'] as List).first['tasks'],
          'items': [
            {'employeeId': swapId(5), 'displayName': 'B'},
          ],
          'nextCursor': null,
        });
      }
      return fixture.response({
        'items': r.url.path.endsWith('/employee-home/shifts')
            ? [
                {
                  'shift': h.ownShift.toJson(),
                  'tasks': [h.ownTask],
                },
              ]
            : r.url.path.endsWith('/swap-colleagues')
            ? [
                {'employeeId': swapId(5), 'displayName': 'B'},
              ]
            : [],
        'nextCursor': null,
      });
    };
    t.view.physicalSize = const Size(1200, 1000);
    t.view.devicePixelRatio = 1;
    addTearDown(() async {
      await t.pumpWidget(const SizedBox.shrink());
      home.dispose();
      employees.dispose();
      transfers.dispose();
      swaps.dispose();
      h.dispose();
      t.view.resetPhysicalSize();
      t.view.resetDevicePixelRatio();
      WidgetController.hitTestWarningShouldBeFatal = warningPolicy;
      expect(t.takeException(), isNull);
    });
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: [routes],
        home: PlatformHomeScreen(
          session: h.session,
          platform: h.platform,
          employees: employees,
          home: home,
          ownSwaps: swaps,
          ownTransfers: transfers,
          baseUri: Uri.parse('http://fixture.invalid'),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Meine Arbeit').last);
    await t.pumpAndSettle();
    await home.open(h.ownShift.id);
    await t.pumpAndSettle();
    callback =
        t.widget<ShiftSection>(find.byType(ShiftSection)).swapShortcut!
            as Future<void> Function(ShiftDto);
    await t.ensureVisible(find.byKey(const Key('request-swap')));
    await t.pumpAndSettle();
    expect(routes.pages, hasLength(1));
  }

  void expectPage({int loads = 1}) {
    expect(
      routes.pages,
      hasLength(2),
      reason: 'Home plus exactly one request page',
    );
    expect(find.byType(ShiftSwapSection, skipOffstage: false), findsOneWidget);
    expect(swaps.loads, loads);
    expect(h.posts, isEmpty);
  }

  Future<void> physicalTaps(int count) async {
    final button = find.byKey(const Key('request-swap'));
    await t.ensureVisible(button);
    await t.pumpAndSettle();
    final position = t.getCenter(button);
    for (var i = 0; i < count; i++) {
      if (i < 2) {
        await t.tap(button);
      } else {
        // A third physical tap may already land on the new route's barrier.
        await t.tapAt(position);
      }
    }
  }

  Future<void> pop() async {
    navigator.currentState!.pop();
    await t.pumpAndSettle();
  }

  Future<void> replace(String kind) async {
    if (kind == 'logout') {
      await h.session.signOut();
      return;
    }
    if (kind == 'same-account' || kind == 'different-account') {
      if (kind == 'different-account') h.auth.account = swapId(77);
      await h.login();
      return;
    }
    final old = h.platform.context!;
    h.platform.context = PlatformContext(
      userId: old.userId,
      companyId: old.companyId,
      locationId: kind == 'location' ? swapId(88) : old.locationId,
      role: old.role,
      permissions: old.permissions,
    );
  }
}

void main() {
  for (final count in [2, 3]) {
    testWidgets(
      'B3B-01 $count rapid physical taps before the next frame create one page',
      (t) async {
        final p = _Probe(t);
        await p.mount();
        await p.physicalTaps(count);
        await t.pumpAndSettle();
        p.expectPage();
        await p.pop();
        final reopened = p.open();
        await t.pumpAndSettle();
        p.expectPage(loads: 2);
        await p.pop();
        await reopened;
      },
    );
    testWidgets(
      'B3B-01 $count rapid physical taps while source HTTP is held create one page',
      (t) async {
        final p = _Probe(t);
        await p.mount();
        p.h.readHold = Completer<http.Response>();
        await p.physicalTaps(count);
        expect(p.routes.pages, hasLength(1));
        expect(p.swaps.loads, 1);
        p.h.readHold!.complete(
          fixture.response({
            'items': [
              {'employeeId': swapId(5), 'displayName': 'B'},
            ],
            'nextCursor': null,
          }),
        );
        p.h.readHold = null;
        await t.pumpAndSettle();
        p.expectPage();
      },
    );
  }

  testWidgets(
    'B3B-01 three synchronous activations after source loading before route push stay single',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      p.swaps.gates[1] = Completer<void>();
      p.swaps.loaded[1] = Completer<void>();
      final first = p.open();
      await p.swaps.loaded[1]!.future;
      expect(p.swaps.locked, false);
      expect(p.routes.pages, hasLength(1));
      final second = p.open(), third = p.open(), fourth = p.open();
      await Future.wait([second, third, fourth]);
      expect(p.swaps.loads, 1);
      expect(p.h.posts, isEmpty);
      p.swaps.gates[1]!.complete();
      await t.pumpAndSettle();
      p.expectPage();
      await p.pop();
      await first;
    },
  );

  testWidgets('B3B-01 route creation observer cannot reenter navigation', (
    t,
  ) async {
    final p = _Probe(t);
    await p.mount();
    Future<void>? reentry;
    p.routes.onPush = () {
      reentry = p.open();
    };
    final first = p.open();
    await t.pumpAndSettle();
    await reentry;
    p.expectPage();
    p.routes.onPush = null;
    await p.pop();
    await first;
  });

  testWidgets(
    'B3B-01 repeated callbacks while page is open cannot push another route',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      final first = p.open();
      await t.pumpAndSettle();
      await Future.wait([p.open(), p.open(), p.open()]);
      await t.pumpAndSettle();
      p.expectPage();
      await p.pop();
      await first;
      expect(p.routes.pages, hasLength(1));
    },
  );

  testWidgets(
    'B3B-01 source read failure releases guard for successful retry',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      p.h.readError = StateError('offline');
      await p.open();
      await t.pumpAndSettle();
      expect(p.routes.pages, hasLength(1));
      expect(p.swaps.source, isNull);
      p.h.readError = null;
      final retry = p.open();
      await t.pumpAndSettle();
      p.expectPage(loads: 2);
      await p.pop();
      await retry;
    },
  );

  testWidgets(
    'B3B-01 exceptional preflight releases guard without a stuck route',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      p.swaps.throwSource = true;
      await expectLater(p.open(), throwsStateError);
      expect(p.routes.pages, hasLength(1));
      p.swaps.throwSource = false;
      final retry = p.open();
      await t.pumpAndSettle();
      p.expectPage(loads: 2);
      await p.pop();
      await retry;
    },
  );

  for (final change in [
    'logout',
    'same-account',
    'different-account',
    'context',
    'location',
  ]) {
    testWidgets('B3B-01 held source loading is fenced after $change', (
      t,
    ) async {
      final p = _Probe(t);
      await p.mount();
      p.h.readHold = Completer<http.Response>();
      final first = p.open();
      await t.pump();
      await p.replace(change);
      p.h.readHold!.complete(
        fixture.response({
          'items': [
            {'employeeId': swapId(5), 'displayName': 'B'},
          ],
          'nextCursor': null,
        }),
      );
      p.h.readHold = null;
      await first;
      await t.pumpAndSettle();
      expect(p.routes.pages, hasLength(1));
      expect(find.byType(ShiftSwapSection, skipOffstage: false), findsNothing);
      expect(p.swaps.source, isNull);
      expect(p.swaps.sourceWork, isEmpty);
      expect(p.h.posts, isEmpty);
    });
  }

  for (final change in [
    'same-account',
    'different-account',
    'context',
    'location',
  ]) {
    testWidgets(
      'B3B-01 $change during navigation cannot retain or reactivate private page',
      (t) async {
        final p = _Probe(t);
        await p.mount();
        final first = p.open();
        await t.pumpAndSettle();
        p.expectPage();
        final homeReads = p.h.reads
            .where((r) => r.url.path.endsWith('/employee-home/shifts'))
            .length;
        await p.replace(change);
        await t.pumpAndSettle();
        expect(
          find.byType(ShiftSwapSection, skipOffstage: false),
          findsNothing,
        );
        expect(p.swaps.source, isNull);
        await p.pop();
        await first;
        expect(
          p.h.reads
              .where((r) => r.url.path.endsWith('/employee-home/shifts'))
              .length,
          homeReads,
        );
        if (change == 'location') {
          p.h.platform.context = null;
          await p.h.login();
        }
        final next = p.open();
        await t.pumpAndSettle();
        p.expectPage(loads: 2);
        await p.pop();
        await next;
      },
    );
  }

  testWidgets(
    'B3B-01 old navigation completion cannot release newer identity ownership',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      final first = p.open();
      await t.pumpAndSettle();
      await p.replace('context');
      await t.pumpAndSettle();
      p.swaps.gates[2] = Completer<void>();
      p.swaps.loaded[2] = Completer<void>();
      Future<void>? next;
      p.routes.onPop = () {
        p.routes.onPop = null;
        next = p.open();
      };
      p.navigator.currentState!.pop();
      await p.swaps.loaded[2]!.future;
      await first;
      expect(p.swaps.locked, false);
      expect(p.routes.pages, hasLength(1));
      await Future.wait([p.open(), p.open()]);
      expect(p.swaps.loads, 2);
      p.swaps.gates[2]!.complete();
      await t.pumpAndSettle();
      p.expectPage(loads: 2);
      await p.pop();
      await next;
    },
  );

  testWidgets(
    'B3B-01 old preflight finally cannot release newer context ownership',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      for (final n in [1, 2]) {
        p.swaps.gates[n] = Completer<void>();
        p.swaps.loaded[n] = Completer<void>();
      }
      final first = p.open();
      await p.swaps.loaded[1]!.future;
      await p.replace('context');
      final next = p.open();
      await p.swaps.loaded[2]!.future;
      p.swaps.gates[1]!.complete();
      await first;
      await p.open();
      expect(p.swaps.loads, 2);
      expect(p.routes.pages, hasLength(1));
      p.swaps.gates[2]!.complete();
      await t.pumpAndSettle();
      p.expectPage(loads: 2);
      await p.pop();
      await next;
    },
  );

  testWidgets(
    'B3B-01 parent disposal during preflight cannot push an obsolete page',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      p.swaps.gates[1] = Completer<void>();
      p.swaps.loaded[1] = Completer<void>();
      final first = p.open();
      await p.swaps.loaded[1]!.future;
      await t.pumpWidget(const SizedBox.shrink());
      p.swaps.gates[1]!.complete();
      await first;
      await t.pumpAndSettle();
      expect(p.routes.pushes, 1);
      expect(find.byType(ShiftSwapSection, skipOffstage: false), findsNothing);
      expect(p.h.posts, isEmpty);
    },
  );

  testWidgets('B3B-01 browser back releases navigation and allows reopening', (
    t,
  ) async {
    final p = _Probe(t);
    await p.mount();
    final first = p.open();
    await t.pumpAndSettle();
    p.expectPage();
    await t.binding.handlePopRoute();
    await t.pumpAndSettle();
    await first;
    expect(p.routes.pages, hasLength(1));
    final second = p.open();
    await t.pumpAndSettle();
    p.expectPage(loads: 2);
    await p.pop();
    await second;
  });

  testWidgets(
    'B3B-01 swap guard does not block the existing one-way Transfer shortcut',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      final first = p.open();
      await t.pumpAndSettle();
      final transfer = t
          .widget<ShiftSection>(find.byType(ShiftSection, skipOffstage: false))
          .transferShortcut!;
      transfer(p.h.ownShift);
      await t.pumpAndSettle();
      expect(p.routes.pages, hasLength(3));
      expect(find.byType(ShiftTransferSection), findsOneWidget);
      expect(p.h.posts, isEmpty);
      await p.pop();
      p.expectPage();
      await p.pop();
      await first;
      final second = p.open();
      await t.pumpAndSettle();
      p.expectPage(loads: 2);
      await p.pop();
      await second;
    },
  );

  testWidgets(
    'B3B-01 rapid shortcut navigation and explicit request produce one POST and accepted effect',
    (t) async {
      final p = _Probe(t);
      await p.mount();
      await p.physicalTaps(3);
      await t.pumpAndSettle();
      p.expectPage();
      await ui.tap(t, 'swap-colleague-${swapId(5)}');
      await ui.act(t, 'request');
      expect(p.h.posts, hasLength(1));
      expect(p.h.receipts, hasLength(1));
      expect(p.h.evidence['status'], 'requested');
      expect(p.swaps.lastConfirmed, isNotNull);
      expect(p.swaps.pending, isNull);
      expect(p.swaps.source, isNull);
      await Future.wait([p.open(), p.open()]);
      await t.pumpAndSettle();
      expect(p.routes.pages, hasLength(2));
      expect(p.swaps.loads, 1);
      expect(p.h.posts, hasLength(1));
      final receipt = p.swaps.lastConfirmed;
      await p.pop();
      expect(p.routes.pages, hasLength(1));
      expect(p.swaps.lastConfirmed, same(receipt));
      expect(p.h.receipts, hasLength(1));
    },
  );
}
