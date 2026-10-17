import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/employee_controller.dart';
import 'package:storeos_client/src/application/platform_models.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/shift_transfer_controller.dart';
import 'package:storeos_client/src/ui/platform_home_screen.dart';
import 'package:storeos_client/src/ui/shift_swap_section.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'package:storeos_client/src/ui/shift_transfer_section.dart';

import 'shift_swap_fixture.dart';
import 'shift_swap_test.dart' as fixture;
import 'shift_swap_ui_fixture.dart';

void main() {
  for (final narrow in [false, true]) {
    testWidgets(
      '${narrow ? 'Drawer' : 'NavigationRail'} capability-gated swap navigation, refresh and P4.11 coexistence',
      (t) async {
        final h = SwapUiHarness(role: 'source')..tester = t;
        h.grants.addAll([
          'workforce.transfers.self.read',
          'workforce.transfers.manage',
          'organization.read',
        ]);
        await h.login();
        final manager = ShiftSwapController(
          h.session,
          h.platform,
          h.api,
          self: false,
        );
        final employees = EmployeeController(h.session, h.platform, h.api);
        final transfers = ShiftTransferController(
          h.session,
          h.platform,
          h.api,
          self: false,
        );
        final ownTransfers = ShiftTransferController(
          h.session,
          h.platform,
          h.api,
        );
        t.view.physicalSize = Size(narrow ? 400 : 1200, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox.shrink());
          manager.dispose();
          employees.dispose();
          transfers.dispose();
          ownTransfers.dispose();
          h.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await t.pumpWidget(
          MaterialApp(
            home: PlatformHomeScreen(
              session: h.session,
              platform: h.platform,
              employees: employees,
              swaps: manager,
              ownSwaps: h.controller,
              transfers: transfers,
              ownTransfers: ownTransfers,
              baseUri: Uri.parse('http://fixture.invalid'),
            ),
          ),
        );
        await t.pumpAndSettle();
        Future<void> section(String label) async {
          if (narrow) {
            await t.tap(find.byKey(const Key('open-navigation')));
            await t.pumpAndSettle();
          }
          await t.tap(find.text(label).last);
          await t.pumpAndSettle();
        }

        expect(
          find.byType(NavigationRail),
          narrow ? findsNothing : findsOneWidget,
        );
        await section('Meine Schichttausche');
        expect(
          t.widget<ShiftSwapSection>(find.byType(ShiftSwapSection)).controller,
          same(h.controller),
        );
        final reads = h.reads.length;
        await t.tap(find.byKey(const Key('platform-refresh')));
        await t.pumpAndSettle();
        expect(h.reads.length, reads + 1);
        await section('My shift transfers');
        expect(find.byType(ShiftTransferSection), findsOneWidget);
        await section('Schichttausch prüfen');
        expect(
          t.widget<ShiftSwapSection>(find.byType(ShiftSwapSection)).controller,
          same(manager),
        );
        final old = h.platform.context!;
        h.platform.context = PlatformContext(
          userId: old.userId,
          companyId: old.companyId,
          locationId: old.locationId,
          role: 'viewer',
          permissions: const ['organization.read'],
        );
        await t.pumpAndSettle();
        expect(find.byType(ShiftSwapSection), findsNothing);
        if (narrow &&
            find.byKey(const Key('open-navigation')).evaluate().isNotEmpty) {
          await t.tap(find.byKey(const Key('open-navigation')));
          await t.pumpAndSettle();
        }
        expect(find.text('Meine Schichttausche'), findsNothing);
        expect(find.text('Schichttausch prüfen'), findsNothing);
        expect(manager.canRead, false);
        expect(h.controller.canRead, false);
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final boundary in ['discovery', 'navigation']) {
    testWidgets(
      'Own-work shortcut fences context replacement during $boundary',
      (t) async {
        final h = SwapUiHarness(role: 'source')..tester = t;
        h.grants.add('workforce.shifts.self.read');
        await h.login();
        final employees = EmployeeController(h.session, h.platform, h.api);
        final home = ShiftController(h.session, h.platform, h.api, self: true);
        h.read = (r) async => fixture.response({
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
        t.view.physicalSize = const Size(1200, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(() async {
          await t.pumpWidget(const SizedBox.shrink());
          home.dispose();
          employees.dispose();
          h.dispose();
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        await t.pumpWidget(
          MaterialApp(
            home: PlatformHomeScreen(
              session: h.session,
              platform: h.platform,
              employees: employees,
              home: home,
              ownSwaps: h.controller,
              baseUri: Uri.parse('http://fixture.invalid'),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Meine Arbeit').last);
        await t.pumpAndSettle();
        final callback = t
            .widget<ShiftSection>(find.byType(ShiftSection))
            .swapShortcut!;
        if (boundary == 'discovery') {
          h.readHold = Completer<http.Response>();
        }
        callback(h.ownShift);
        if (boundary == 'discovery') {
          await t.pump();
          expect(h.controller.busy, true);
        } else {
          await t.pumpAndSettle();
          expect(find.byType(ShiftSwapSection), findsOneWidget);
        }
        final homeReads = h.reads
            .where((r) => r.url.path.endsWith('/employee-home/shifts'))
            .length;
        h.platform.context = h.platform.context;
        if (boundary == 'discovery') {
          h.readHold!.complete(
            fixture.response({
              'items': [
                {'employeeId': swapId(5), 'displayName': 'B'},
              ],
              'nextCursor': null,
            }),
          );
        } else {
          await t.pumpAndSettle();
          expect(find.byType(ShiftSwapSection), findsNothing);
          await t.pageBack();
        }
        await t.pumpAndSettle();
        expect(find.byType(ShiftSwapSection), findsNothing);
        expect(h.controller.source, isNull);
        expect(h.posts, isEmpty);
        expect(
          h.reads
              .where((r) => r.url.path.endsWith('/employee-home/shifts'))
              .length,
          homeReads,
        );
        expect(t.takeException(), isNull);
      },
    );
  }

  for (final change in [
    'context',
    'location',
    'logout',
    'expiry',
    'same-account',
    'different-account',
    'dispose',
  ]) {
    test('Own source Task read fences held response after $change', () async {
      final h = SwapUiHarness(role: 'source');
      await h.login();
      await h.controller.chooseSource(h.ownShift);
      h.workHold = Completer<http.Response>();
      final read = h.controller.loadSourceWork();
      if (change == 'logout') {
        await h.session.signOut();
      } else if (change == 'expiry') {
        h.auth.now = h.auth.now.add(const Duration(hours: 2));
      } else if (change == 'same-account' || change == 'different-account') {
        if (change == 'different-account') h.auth.account = swapId(77);
        await h.login();
      } else if (change == 'dispose') {
        h.controller.dispose();
      } else {
        final old = h.platform.context!;
        h.platform.context = PlatformContext(
          userId: old.userId,
          companyId: old.companyId,
          locationId: change == 'location' ? swapId(88) : old.locationId,
          role: old.role,
          permissions: old.permissions,
        );
      }
      h.workHold!.complete(
        fixture.response({
          'shift': h.ownShift.toJson(),
          'tasks': [h.ownTask],
        }),
      );
      await read;
      expect(h.controller.sourceWork, isEmpty);
      expect(h.controller.source, isNull);
      if (change != 'dispose') h.controller.dispose();
      h.platform.dispose();
      h.session.dispose();
      h.client.close();
    });
  }
}
