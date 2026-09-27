import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'task_execution_test.dart' as execution;
import 'shift_test.dart' as base;

class BlockingApi extends execution.ExecutionApi {
  final history = <Map<String, dynamic>>[];
  bool loseBlocking = false, rejectBlocking = false, failHistory = false;
  Completer<Map<String, dynamic>>? pendingBlocking;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    if (route.endsWith('/blockings')) {
      if (failHistory) {
        throw const StoreApiException('network_unavailable', 'Offline');
      }
      return {'items': history.reversed.map(copy).toList(), 'nextCursor': null};
    }
    if (route.endsWith('/blocked-tasks')) {
      return {
        'items': state['status'] == 'blocked'
            ? records.values.single['tasks']
            : [],
        'nextCursor': null,
      };
    }
    final result = await super.get(token, route, after: after);
    if (route == '/context') {
      (result['permissions'] as List).add('tasks.instances.resolve');
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!route.endsWith('/block') && !route.endsWith('/resume')) {
      return super.post(token, route, body);
    }
    commands.add(copy(body));
    if (pendingBlocking != null) return pendingBlocking!.future;
    if (rejectBlocking) {
      throw const StoreApiException(
        'execution_conflict',
        'Conflict',
        statusCode: 409,
      );
    }
    final id = body['operationId'] as String;
    if (!receipts.containsKey(id)) {
      state = {...state, 'version': (state['version'] as int) + 1};
      if (route.endsWith('/block')) {
        state.addAll({'status': 'blocked', 'activeBlockingId': id});
        history.add({
          'id': id,
          'instanceId': base.taskId,
          'stepId': base.taskId,
          'reason': body['reason'],
          'reportedAt': base.Api.time,
          'reportedBy': base.account,
          'reportedVersion': state['version'],
          'resolution': null,
          'resolvedAt': null,
          'resolvedBy': null,
          'resolvedVersion': null,
        });
      } else {
        state['status'] = 'in_progress';
        state.remove('activeBlockingId');
        history.last.addAll({
          'resolution': body['reason'],
          'resolvedAt': base.Api.time,
          'resolvedBy': base.account,
          'resolvedVersion': state['version'],
        });
      }
      final task = records.values.single['tasks'][0] as Map<String, dynamic>;
      task['status'] = state['status'];
      task['version'] = state['version'];
      receipts[id] = copy(state);
    }
    if (loseBlocking) {
      throw const StoreApiException('network_unavailable', 'Lost response');
    }
    return copy(receipts[id]!);
  }
}

void main() {
  testWidgets('reloading the same version clears the visible reason draft', (
    tester,
  ) async {
    final api = BlockingApi(), f = await execution.fixture(client: api);
    await f.home.executeTask('start');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.home)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField), 'Discard this draft');
    final version = f.home.execution!.version;
    await f.home.reloadExecution();
    await tester.pumpAndSettle();
    expect(f.home.execution!.version, version);
    expect(f.home.reason, isEmpty);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    await f.admin.session.signOut();
  });
  test(
    'a new shift draft clears the discarded task resolution context',
    () async {
      final api = BlockingApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('Missing equipment');
      await f.home.executeTask('block');
      await f.admin.c.openTask(base.taskId);
      f.admin.c.setReason('Unsent resolution');
      f.admin.c.newDraft();
      expect(f.admin.c.reason, isEmpty);
      expect(f.admin.c.execution, isNull);
      expect(f.admin.c.blockings, isEmpty);
      expect(f.admin.c.canResume, isFalse);
      await f.admin.session.signOut();
    },
  );
  test(
    'blocking validates reason, preserves draft on rejection and reloads consistent lists',
    () async {
      final api = BlockingApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setReason('   ');
      await f.home.executeTask('block');
      expect(f.home.error, isNotNull);
      expect(api.commands, hasLength(1));
      f.home.setReason('Equipment missing');
      api.rejectBlocking = true;
      await f.home.executeTask('block');
      expect(f.home.reason, 'Equipment missing');
      expect(f.home.executionConflict, isTrue);
      api.rejectBlocking = false;
      await f.home.reloadExecution();
      f.home.setReason('Equipment missing');
      await f.home.executeTask('block');
      expect(f.home.canConfirm, isFalse);
      expect(f.home.canComplete, isFalse);
      expect(f.home.blocked, hasLength(1));
      expect(f.home.running, isEmpty);
      expect(f.home.blockings.single.reason, 'Equipment missing');
      await f.admin.c.openTask(base.taskId);
      expect(f.admin.c.canResume, isTrue);
      f.admin.c.setReason('Replacement ready');
      await f.admin.c.executeTask('resume');
      await f.home.reloadExecution();
      expect(f.home.canConfirm, isTrue);
      expect(f.home.blocked, isEmpty);
      expect(f.home.blockings.single.resolution, 'Replacement ready');
    },
  );
  for (final command in ['block', 'resume']) {
    test(
      'lost $command response retries exact operation and history refresh failure stays locked',
      () async {
        final api = BlockingApi(), f = await execution.fixture(client: api);
        await f.home.executeTask('start');
        if (command == 'resume') {
          f.home.setReason('Missing');
          await f.home.executeTask('block');
          await f.admin.c.openTask(base.taskId);
        }
        final c = command == 'block' ? f.home : f.admin.c;
        c.setReason('Checked context');
        api.loseBlocking = true;
        await c.executeTask(command);
        expect(c.executionUnconfirmed, isTrue);
        expect(c.reason, 'Checked context');
        final original = api.commands.last;
        api.loseBlocking = false;
        api.failHistory = true;
        await c.retryExecution();
        expect(api.commands.last, original);
        expect(c.executionUnconfirmed, isFalse);
        expect(c.executionConflict, isTrue);
        api.failHistory = false;
        await c.reloadExecution();
        expect(c.executionConflict, isFalse);
        expect(api.history, hasLength(1));
      },
    );
  }
  test('late blocking cannot restore data after logout', () async {
    final api = BlockingApi(), f = await execution.fixture(client: api);
    await f.home.executeTask('start');
    f.home.setReason('Missing');
    api.pendingBlocking = Completer();
    final request = f.home.executeTask('block');
    await Future<void>.delayed(Duration.zero);
    await f.admin.session.signOut();
    api.pendingBlocking!.complete(api.copy(api.state));
    await request;
    expect(f.home.reason, isEmpty);
    expect(f.home.blockings, isEmpty);
    expect(f.home.blocked, isNull);
  });
  testWidgets('employee reports a blocker and admin explicitly releases it', (
    tester,
  ) async {
    final api = BlockingApi(), f = await execution.fixture(client: api);
    await f.home.executeTask('start');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.home)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField), 'Equipment unavailable');
    await tester.scrollUntilVisible(
      find.byKey(const Key('block-task')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('block-task')));
    await tester.pumpAndSettle();
    expect(f.home.execution!.status, 'blocked');
    await f.admin.c.openTask(base.taskId);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShiftSection(key: const Key('admin'), controller: f.admin.c),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byType(TextFormField),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextFormField), 'Replacement checked');
    await tester.scrollUntilVisible(
      find.byKey(const Key('resume-task')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('resume-task')));
    await tester.pumpAndSettle();
    expect(f.admin.c.execution!.status, 'in_progress');
    await tester.pumpWidget(const SizedBox());
    await f.admin.session.signOut();
  });
}
