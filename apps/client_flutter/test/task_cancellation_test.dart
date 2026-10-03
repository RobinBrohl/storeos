import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'task_execution_test.dart' as execution;
import 'task_blocking_test.dart' as blocking;
import 'shift_test.dart' as base;

class CancellationApi extends blocking.BlockingApi {
  bool loseCancel = false, rejectCancel = false, failCancelled = false;
  Completer<Map<String, dynamic>>? pendingCancel;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route.endsWith('/cancelled-tasks')) {
      if (failCancelled) {
        throw const StoreApiException('network_unavailable', 'Offline');
      }
      return {
        'items': state['status'] == 'cancelled'
            ? records.values.single['tasks']
            : [],
        'nextCursor': null,
      };
    }
    final result = await super.get(token, route, after: after);
    if (route == '/context') {
      (result['permissions'] as List).add('tasks.instances.cancel');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!route.endsWith('/cancel')) return super.post(token, route, body);
    commands.add(copy(body));
    if (pendingCancel != null) return pendingCancel!.future;
    if (rejectCancel) {
      throw const StoreApiException(
        'execution_conflict',
        'Conflict',
        statusCode: 409,
      );
    }
    final id = body['operationId'] as String;
    if (!receipts.containsKey(id)) {
      final blockingId = state['activeBlockingId'];
      state = {
        ...state,
        'status': 'cancelled',
        'version': (state['version'] as int) + 1,
        'cancelledAt': base.Api.time,
        'cancelledBy': base.account,
        'cancelledBlockingId': blockingId,
      }..remove('activeBlockingId');
      history.last.addAll({
        'resolution': body['reason'],
        'resolutionKind': 'cancelled',
        'resolvedAt': base.Api.time,
        'resolvedBy': base.account,
        'resolvedVersion': state['version'],
      });
      final task = records.values.single['tasks'][0] as Map<String, dynamic>;
      task['status'] = 'cancelled';
      task['version'] = state['version'];
      receipts[id] = copy(state);
    }
    if (loseCancel) {
      throw const StoreApiException('network_unavailable', 'Lost response');
    }
    return copy(receipts[id]!);
  }
}

void main() {
  testWidgets('failed cancellation list refresh never claims an empty list', (
    tester,
  ) async {
    final api = CancellationApi(), f = await execution.fixture(client: api);
    await f.home.executeTask('start');
    f.home.setReason('Missing');
    await f.home.executeTask('block');
    await f.admin.c.openTask(base.taskId);
    f.admin.c.setReason('Cannot perform');
    api.failCancelled = true;
    await f.admin.c.executeTask('cancel');
    expect(f.admin.c.execution!.status, 'cancelled');
    expect(f.admin.c.executionUnconfirmed, isFalse);
    expect(f.admin.c.error, isNotNull);
    expect(f.admin.c.cancelled, isNull);
    expect(f.admin.c.blockings.single.resolutionKind, 'cancelled');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.admin.c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Keine stornierten Aufgaben.'), findsNothing);
    expect(find.textContaining('Noch ungeklärt'), findsNothing);
    api.failCancelled = false;
    await f.admin.c.reloadExecution();
    await tester.pumpAndSettle();
    expect(f.admin.c.cancelled, hasLength(1));
    expect(f.admin.c.executionConflict, isFalse);
    await tester.pumpWidget(const SizedBox());
    await f.admin.session.signOut();
  });
  test(
    'failed cancellation history refresh discards obsolete open blocking',
    () async {
      final api = CancellationApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('Missing');
      await f.home.executeTask('block');
      await f.admin.c.openTask(base.taskId);
      expect(f.admin.c.blockings.single.resolutionKind, isNull);
      f.admin.c.setReason('Cannot perform');
      api.failHistory = true;
      await f.admin.c.executeTask('cancel');
      expect(f.admin.c.execution!.status, 'cancelled');
      expect(f.admin.c.error, isNotNull);
      expect(f.admin.c.blockings, isEmpty);
      expect(f.admin.c.blockingCursor, isNull);
      expect(f.admin.c.canCancel, isFalse);
      expect(f.admin.c.canResume, isFalse);
      api.failHistory = false;
      await f.admin.c.reloadExecution();
      expect(f.admin.c.blockings.single.resolution, 'Cannot perform');
      expect(f.admin.c.cancelled, hasLength(1));
      await f.admin.session.signOut();
    },
  );
  test(
    'cancel validates, preserves drafts on conflict and replays exact lost command',
    () async {
      final api = CancellationApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('Missing');
      await f.home.executeTask('block');
      await f.admin.c.openTask(base.taskId);
      expect(f.home.canCancel, isFalse);
      f.admin.c.setReason(' ');
      await f.admin.c.executeTask('cancel');
      expect(f.admin.c.error, isNotNull);
      f.admin.c.setReason('Cannot perform');
      api.rejectCancel = true;
      await f.admin.c.executeTask('cancel');
      expect(f.admin.c.reason, 'Cannot perform');
      expect(f.admin.c.executionConflict, isTrue);
      api.rejectCancel = false;
      await f.admin.c.reloadExecution();
      f.admin.c.setReason('Cannot perform');
      api.loseCancel = true;
      await f.admin.c.executeTask('cancel');
      expect(f.admin.c.executionUnconfirmed, isTrue);
      final command = api.commands.last;
      api.loseCancel = false;
      api.failCancelled = true;
      await f.admin.c.retryExecution();
      expect(api.commands.last, command);
      expect(f.admin.c.executionConflict, isTrue);
      expect(f.admin.c.executionUnconfirmed, isFalse);
      api.failCancelled = false;
      await f.admin.c.reloadExecution();
      expect(f.admin.c.execution!.status, 'cancelled');
      expect(f.admin.c.canResume, isFalse);
      expect(f.admin.c.canCancel, isFalse);
      expect(f.admin.c.cancelled, hasLength(1));
      expect(f.admin.c.blocked, isEmpty);
      await f.home.loadCancelled();
      await f.home.openRunning(f.home.cancelled!.single);
      expect(f.home.canComplete, isFalse);
      expect(f.home.canConfirm, isFalse);
      expect(f.home.blockings.single.resolutionKind, 'cancelled');
      await f.admin.session.signOut();
    },
  );
  test(
    'late cancellation response does not restore data after logout',
    () async {
      final api = CancellationApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('Missing');
      await f.home.executeTask('block');
      await f.admin.c.openTask(base.taskId);
      f.admin.c.setReason('Cannot perform');
      api.pendingCancel = Completer();
      final request = f.admin.c.executeTask('cancel');
      await Future<void>.delayed(Duration.zero);
      await f.admin.session.signOut();
      api.pendingCancel!.complete(api.copy(api.state));
      await request;
      expect(f.admin.c.cancelled, isNull);
      expect(f.admin.c.execution, isNull);
      expect(f.admin.c.reason, isEmpty);
    },
  );
  testWidgets(
    'admin must confirm cancellation and worker sees terminal history',
    (tester) async {
      final api = CancellationApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('Missing');
      await f.home.executeTask('block');
      await f.admin.c.openTask(base.taskId);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSection(controller: f.admin.c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(TextFormField),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(
        find.byType(TextFormField),
        'Permanently unavailable',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('cancel-task')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('cancel-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      expect(api.state['status'], 'blocked');
      expect(f.admin.c.reason, 'Permanently unavailable');
      await tester.tap(find.byKey(const Key('cancel-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();
      expect(api.state['status'], 'cancelled');
      expect(find.byKey(const Key('cancel-task')), findsNothing);
      await f.home.reloadExecution();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSection(key: const Key('worker'), controller: f.home),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Stornierungsgrund:'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.textContaining('Stornierungsgrund: Permanently unavailable'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('confirm-step')), findsNothing);
      expect(find.byKey(const Key('complete-task')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await f.admin.session.signOut();
    },
  );
}
