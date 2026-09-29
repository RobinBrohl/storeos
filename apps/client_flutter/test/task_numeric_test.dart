import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'task_execution_test.dart' as execution;
import 'task_blocking_test.dart' as blocking;
import 'shift_test.dart' as base;

class NumericApi extends blocking.BlockingApi {
  final attempts = <Map<String, dynamic>>[];
  bool loseNumber = false, rejectNumber = false, failNumbers = false;
  Completer<Map<String, dynamic>>? pendingNumber;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    if (route.endsWith('/number-attempts')) {
      if (failNumbers) {
        throw const StoreApiException('network_unavailable', 'Offline');
      }
      return {
        'items': attempts.reversed.map(copy).toList(),
        'nextCursor': null,
      };
    }
    final result = await super.get(token, route, after: after);
    if (result['content'] is Map) {
      result['content']['schemaVersion'] = 2;
      result['content']['steps'][0].addAll({
        'type': 'number',
        'unit': '°C',
        'minimum': '-2.125',
        'maximum': '4.5',
      });
    }
    return result;
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!route.endsWith('/record-number')) {
      return super.post(token, route, body);
    }
    if (pendingNumber != null) return pendingNumber!.future;
    if (rejectNumber) {
      throw const StoreApiException(
        'execution_conflict',
        'Conflict',
        statusCode: 409,
      );
    }
    final id = body['operationId'] as String, fresh = !receipts.containsKey(id);
    // The fake only supplies server responses; production evaluation is tested against PostgreSQL.
    final good = body['value'] == '4.5';
    final result = await super.post(
      token,
      good
          ? route.replaceFirst('/record-number', '/confirm')
          : "${route.substring(0, route.indexOf('/steps/'))}/block",
      {
        ...body,
        if (!good) 'reason': 'Zahlenwert außerhalb der erlaubten Grenzen.',
      },
    );
    if (fresh) {
      attempts.add({
        'id': id,
        'instanceId': base.taskId,
        'stepId': base.taskId,
        'value': body['value'],
        'inRange': good,
        'recordedAt': base.Api.time,
        'recordedBy': base.account,
        'acceptedVersion': result['version'],
      });
    }
    if (loseNumber) {
      throw const StoreApiException('network_unavailable', 'Lost response');
    }
    return result;
  }
}

void main() {
  test(
    'number input validates precision, normalizes comma and preserves exact retry',
    () async {
      final api = NumericApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      expect(f.home.canConfirm, isFalse);
      expect(f.home.canRecordNumber, isTrue);
      for (final invalid in ['NaN', '1e3', '4,5000', '1.000,25']) {
        f.home.setNumber(invalid);
        final count = api.commands.length;
        await f.home.executeTask('record-number');
        expect(f.home.error, isNotNull);
        expect(api.commands.length, count);
        expect(f.home.numberInput, invalid);
      }
      f.home.setNumber(' 04,500 ');
      api.loseNumber = true;
      await f.home.executeTask('record-number');
      expect(f.home.executionUnconfirmed, isTrue);
      expect(f.home.numberInput, ' 04,500 ');
      expect(api.commands.last['value'], '4.5');
      expect(f.home.canRecordNumber, isFalse);
      api.loseNumber = false;
      await f.home.retryExecution();
      expect(api.commands.last, api.commands[api.commands.length - 2]);
      expect(api.attempts, hasLength(1));
      expect(f.home.numberInput, isEmpty);
      expect(f.home.canComplete, isTrue);
      expect(f.home.numberAttempts!.single.inRange, true);
      await f.home.executeTask('complete');
      expect(f.home.execution!.status, 'completed');
    },
  );
  test(
    'out-of-range blocks, resume retains the pending step and history',
    () async {
      final api = NumericApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setNumber('5');
      await f.home.executeTask('record-number');
      expect(f.home.execution!.status, 'blocked');
      expect(f.home.execution!.results, isEmpty);
      expect(f.home.numberAttempts!.single.inRange, isFalse);
      await f.admin.c.openTask(base.taskId);
      f.admin.c.setReason('Ready again');
      await f.admin.c.executeTask('resume');
      await f.home.reloadExecution();
      expect(f.home.canRecordNumber, isTrue);
      expect(f.home.canComplete, isFalse);
      f.home.setNumber('4.5');
      await f.home.executeTask('record-number');
      expect(f.home.numberAttempts, hasLength(2));
      expect(f.home.canComplete, isTrue);
    },
  );
  test(
    'conflict preserves draft and failed history refresh cannot show an empty history',
    () async {
      final api = NumericApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setNumber('4.5');
      api.rejectNumber = true;
      await f.home.executeTask('record-number');
      expect(f.home.executionConflict, isTrue);
      expect(f.home.numberInput, '4.5');
      api.rejectNumber = false;
      await f.home.reloadExecution();
      api.failNumbers = true;
      f.home.setNumber('4.5');
      await f.home.executeTask('record-number');
      expect(f.home.executionUnconfirmed, isFalse);
      expect(f.home.executionConflict, isTrue);
      expect(f.home.numberAttempts, isNull);
      expect(f.home.error, isNotNull);
      api.failNumbers = false;
      await f.home.reloadExecution();
      expect(f.home.numberAttempts, hasLength(1));
      expect(f.home.canComplete, isTrue);
    },
  );
  test(
    'logout erases value and attempts and ignores late numeric replies',
    () async {
      final api = NumericApi(), f = await execution.fixture(client: api);
      await f.home.executeTask('start');
      f.home.setNumber('4.5');
      api.pendingNumber = Completer<Map<String, dynamic>>();
      final pending = f.home.executeTask('record-number');
      await f.admin.session.signOut();
      api.pendingNumber!.complete({});
      await pending;
      expect(f.home.numberInput, isEmpty);
      expect(f.home.numberAttempts, isNull);
      expect(f.home.execution, isNull);
      expect(f.home.error, isNull);
    },
  );
  testWidgets('numeric widget shows bounds, input, evaluation and history', (
    tester,
  ) async {
    final api = NumericApi(), f = await execution.fixture(client: api);
    await f.home.executeTask('start');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.home)),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.widgetWithText(TextFormField, 'Zahlenwert (°C)');
    await tester.scrollUntilVisible(
      input,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(input, '5');
    await tester.ensureVisible(find.byKey(const Key('record-number')));
    await tester.tap(find.byKey(const Key('record-number')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Außerhalb der Grenzen'), findsOneWidget);
    expect(find.textContaining('-2.125 bis 4.5 °C'), findsOneWidget);
    expect(f.home.execution!.results, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await f.admin.session.signOut();
  });
}
