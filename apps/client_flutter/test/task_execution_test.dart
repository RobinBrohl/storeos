import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'shift_test.dart' as base;

class ExecutionApi extends base.Api {
  Map<String, dynamic> state = {
    'instanceId': base.taskId,
    'status': 'open',
    'version': 1,
    'results': <Map<String, dynamic>>[],
    'startedAt': null,
    'startedBy': null,
    'completedAt': null,
    'completedBy': null,
  };
  final receipts = <String, Map<String, dynamic>>{};
  final commands = <Map<String, dynamic>>[];
  bool loseCommand = false, failCommand = false, rejectCommand = false;
  String? failRoute;
  Completer<Map<String, dynamic>>? pendingCommand;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (failGet || route == failRoute) {
      throw const StoreApiException('network_unavailable', 'Offline');
    }
    if (route.endsWith('/execution')) return copy(state);
    if (route == '/employee-home/running-tasks') {
      return {
        'items': state['status'] == 'in_progress'
            ? records.values.single['tasks']
            : [],
        'nextCursor': null,
      };
    }
    final result = await super.get(token, route, after: after);
    if (route == '/context') {
      (result['permissions'] as List).add('tasks.instances.self.execute');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!route.startsWith('/employee-home/')) {
      return super.post(token, route, body);
    }
    commands.add(copy(body));
    if (pendingCommand != null) return pendingCommand!.future;
    if (failCommand) {
      throw const StoreApiException('network_unavailable', 'Offline');
    }
    if (rejectCommand) {
      throw const StoreApiException(
        'execution_conflict',
        'Conflict',
        statusCode: 409,
      );
    }
    final id = body['operationId'] as String;
    if (!receipts.containsKey(id)) {
      state = {...state, 'version': (state['version'] as int) + 1};
      if (route.endsWith('/start')) {
        state.addAll({
          'status': 'in_progress',
          'startedAt': base.Api.time,
          'startedBy': base.account,
        });
      } else if (route.endsWith('/confirm')) {
        state['results'] = [
          {
            'stepId': base.taskId,
            'confirmedAt': base.Api.time,
            'confirmedBy': base.account,
          },
        ];
      } else {
        state.addAll({
          'status': 'completed',
          'completedAt': base.Api.time,
          'completedBy': base.account,
        });
      }
      final t = records.values.single['tasks'][0] as Map<String, dynamic>;
      t['status'] = state['status'];
      t['version'] = state['version'];
      t['confirmedSteps'] = (state['results'] as List).length;
      receipts[id] = copy(state);
    }
    if (loseCommand) {
      throw const StoreApiException('network_unavailable', 'Lost response');
    }
    return copy(receipts[id]!);
  }
}

Future<({base.Fixture admin, ShiftController home, ExecutionApi api})> fixture({
  ExecutionApi? client,
}) async {
  final api = client ?? ExecutionApi(),
      session = SessionController(base.Session());
  final platform = PlatformController(session, api),
      adminController = ShiftController(session, platform, api);
  final admin = base.Fixture(session, platform, adminController, api);
  await admin.signIn();
  await admin.prepare();
  await admin.c.save();
  await admin.c.publish();
  final home = ShiftController(session, platform, api, self: true);
  await home.open(admin.c.selected!.id);
  await home.openTask(base.taskId);
  addTearDown(() {
    home.dispose();
    admin.dispose();
  });
  return (admin: admin, home: home, api: api);
}

void main() {
  test(
    'start confirm and completion expose only confirmed server state',
    () async {
      final f = await fixture();
      expect(f.home.canComplete, isFalse);
      await f.home.executeTask('start');
      expect(f.home.nextStep!.instruction, 'Check equipment');
      await f.home.executeTask('confirm');
      expect(f.home.canComplete, isTrue);
      await f.home.executeTask('complete');
      expect(f.home.execution!.status, 'completed');
      expect(f.home.canStart, isFalse);
      expect(f.home.canConfirm, isFalse);
      expect(f.home.running, isEmpty);
      await f.home.openTask(base.taskId);
      expect(f.home.execution!.status, 'completed');
    },
  );
  for (final received in [false, true]) {
    test(
      'unknown start outcome retains exact command for explicit retry received=$received',
      () async {
        final f = await fixture();
        f.api.failCommand = !received;
        f.api.loseCommand = received;
        await f.home.executeTask('start');
        expect(f.home.executionUnconfirmed, isTrue);
        expect(f.home.execution!.status, 'open');
        expect(f.home.canStart, isFalse);
        expect(f.api.commands, hasLength(1));
        f.api.failCommand = f.api.loseCommand = false;
        await f.home.retryExecution();
        expect(f.home.executionUnconfirmed, isFalse);
        expect(f.home.execution!.status, 'in_progress');
        expect(f.api.commands[0], f.api.commands[1]);
        expect(f.api.receipts, hasLength(1));
      },
    );
  }
  test(
    'real conflict requires explicit reload and never resends automatically',
    () async {
      final f = await fixture();
      f.api.rejectCommand = true;
      await f.home.executeTask('start');
      expect(f.home.executionConflict, isTrue);
      expect(f.home.canStart, isFalse);
      await f.home.retryExecution();
      expect(f.api.commands, hasLength(1));
      f.api.rejectCommand = false;
      await f.home.reloadExecution();
      expect(f.home.canStart, isTrue);
    },
  );
  test(
    'confirmed command remains confirmed if follow-up refresh fails',
    () async {
      final f = await fixture();
      f.api.failGet = true;
      await f.home.executeTask('start');
      expect(f.home.execution!.status, 'in_progress');
      expect(f.home.executionUnconfirmed, isFalse);
      expect(f.home.executionConflict, isTrue);
      expect(f.home.canConfirm, isFalse);
      f.api.failGet = false;
      await f.home.reloadExecution();
      expect(f.home.canConfirm, isTrue);
    },
  );
  test(
    'reload reconciles task lists after a lost completion response',
    () async {
      final f = await fixture();
      await f.home.load();
      await f.home.executeTask('start');
      await f.home.executeTask('confirm');
      expect(f.home.running, hasLength(1));
      f.api.loseCommand = true;
      await f.home.executeTask('complete');
      expect(f.home.executionUnconfirmed, isTrue);
      await f.home.reloadExecution();
      expect(f.home.execution!.status, 'completed');
      expect(f.home.tasks.single.status, 'completed');
      expect(f.home.running, isEmpty);
      expect(f.home.items!.single['tasks'][0]['status'], 'completed');
      expect(f.home.executionUnconfirmed, isFalse);
      expect(f.api.commands, hasLength(3));
    },
  );
  test(
    'failed list refresh blocks work until a complete reload succeeds',
    () async {
      final f = await fixture();
      f.api.failRoute = '/employee-home/running-tasks';
      await f.home.executeTask('start');
      expect(f.home.execution!.status, 'in_progress');
      expect(f.home.executionUnconfirmed, isFalse);
      expect(f.home.canConfirm, isFalse);
      expect(f.home.error, isNotNull);
      f.api.failRoute = null;
      await f.home.reloadExecution();
      expect(f.home.canConfirm, isTrue);
      expect(f.home.tasks.single.status, 'in_progress');
      expect(f.home.running, hasLength(1));
      expect(f.api.commands, hasLength(1));
    },
  );
  test('late response and pending command cannot cross logout', () async {
    final f = await fixture();
    f.api.pendingCommand = Completer();
    final request = f.home.executeTask('start');
    await Future<void>.delayed(Duration.zero);
    await f.admin.session.signOut();
    f.api.pendingCommand!.complete(f.api.copy(f.api.state));
    await request;
    expect(f.home.execution, isNull);
    expect(f.home.executionUnconfirmed, isFalse);
    expect(f.home.running, isEmpty);
  });
  testWidgets(
    'guided work presents current step and explicit final completion',
    (tester) async {
      final f = await fixture();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSection(controller: f.home)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('start-task')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('start-task')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('confirm-step')),
        300,

        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('1. Check equipment'), findsOneWidget);
      await tester.tap(find.byKey(const Key('confirm-step')));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('complete-task')),
        300,

        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('complete-task')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('execution-status'))).data,
        'Abgeschlossen · 1/1 bestätigt',
      );
      expect(find.byKey(const Key('complete-task')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await f.admin.session.signOut();
    },
  );
}
