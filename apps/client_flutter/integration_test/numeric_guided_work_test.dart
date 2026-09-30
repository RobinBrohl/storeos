import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;

const _adminUsername = String.fromEnvironment('STOREOS_E2E_ADMIN_USERNAME');
const _adminPassword = String.fromEnvironment('STOREOS_E2E_ADMIN_PASSWORD');
const _workerUsername = String.fromEnvironment('STOREOS_E2E_WORKER_USERNAME');
const _workerPassword = String.fromEnvironment('STOREOS_E2E_WORKER_PASSWORD');
const _shiftId = String.fromEnvironment('STOREOS_E2E_SHIFT_ID');
const _taskId = String.fromEnvironment('STOREOS_E2E_TASK_ID');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('numeric guided work completes through the real web client', (
    tester,
  ) async {
    for (final value in [
      _adminUsername,
      _adminPassword,
      _workerUsername,
      _workerPassword,
      _shiftId,
      _taskId,
    ]) {
      expect(value, isNotEmpty, reason: 'Missing E2E fixture dart-define.');
    }

    app.main();
    await _waitFor(tester, find.byKey(const Key('username-field')));
    await _signIn(tester, _workerUsername, _workerPassword);
    await _selectSection(tester, 'Meine Arbeit');
    await _openFixtureTask(tester);
    expect(_executionText(tester), 'Offen · 0/2 bestätigt');

    await _tapInList(tester, find.byKey(const Key('start-task')));
    await _enterNumber(tester, '5');
    await _tapInList(tester, find.byKey(const Key('record-number')));
    await _waitFor(tester, find.textContaining('Außerhalb der Grenzen'));
    expect(_executionText(tester), 'Blockiert · 0/2 bestätigt');
    expect(find.byKey(const Key('complete-task')), findsNothing);
    expect(find.textContaining('5 · Außerhalb der Grenzen'), findsOneWidget);

    await _signOut(tester);
    await _signIn(tester, _adminUsername, _adminPassword);
    await _selectSection(tester, 'Schichten');
    await _openFixtureTask(tester);
    expect(_executionText(tester), 'Blockiert · 0/2 bestätigt');
    await _tapInList(
      tester,
      find.widgetWithText(TextFormField, 'Klärung oder Stornierung begründen'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Klärung oder Stornierung begründen'),
      'Anzeige geprüft; neuen Wert erfassen.',
    );
    await _tapInList(tester, find.byKey(const Key('resume-task')));
    expect(_executionText(tester), 'In Bearbeitung · 0/2 bestätigt');
    expect(find.textContaining('5 · Außerhalb der Grenzen'), findsOneWidget);

    await _signOut(tester);
    await _signIn(tester, _workerUsername, _workerPassword);
    await _selectSection(tester, 'Meine Arbeit');
    await _openFixtureTask(tester);
    expect(_executionText(tester), 'In Bearbeitung · 0/2 bestätigt');
    await _enterNumber(tester, '4,5');
    await _tapInList(tester, find.byKey(const Key('record-number')));
    expect(_executionText(tester), 'In Bearbeitung · 1/2 bestätigt');
    expect(find.textContaining('4.5 · Innerhalb der Grenzen'), findsOneWidget);
    expect(find.textContaining('5 · Außerhalb der Grenzen'), findsOneWidget);
    await _tapInList(tester, find.byKey(const Key('confirm-step')));
    expect(_executionText(tester), 'In Bearbeitung · 2/2 bestätigt');
    await _tapInList(tester, find.byKey(const Key('complete-task')));
    await _waitFor(tester, find.byKey(const Key('execution-status')));
    expect(_executionText(tester), 'Abgeschlossen · 2/2 bestätigt');
    expect(find.byKey(const Key('complete-task')), findsNothing);

    // Discard the entire app/controller tree, as a browser reload would, and
    // create the production app again. No in-memory session or task is reused.
    await tester.pumpWidget(const SizedBox.shrink());
    app.main();
    await _waitFor(tester, find.byKey(const Key('username-field')));
    await _signIn(tester, _workerUsername, _workerPassword);
    await _selectSection(tester, 'Meine Arbeit');
    await _openFixtureTask(tester);
    expect(_executionText(tester), 'Abgeschlossen · 2/2 bestätigt');
    await _expectAttempt(tester, '4.5 · Innerhalb der Grenzen');
    await _expectAttempt(tester, '5 · Außerhalb der Grenzen');
    expect(find.byKey(const Key('complete-task')), findsNothing);
    await _signOut(tester);
  });
}

Future<void> _signIn(
  WidgetTester tester,
  String username,
  String password,
) async {
  await _waitFor(tester, find.byKey(const Key('username-field')));
  await tester.enterText(find.byKey(const Key('username-field')), username);
  await tester.enterText(find.byKey(const Key('password-field')), password);
  await tester.tap(find.byKey(const Key('login-button')));
  await _waitFor(tester, find.byKey(const Key('logout-button')));
}

Future<void> _signOut(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('logout-button')));
  await _waitFor(tester, find.byKey(const Key('username-field')));
}

Future<void> _selectSection(WidgetTester tester, String label) async {
  final drawer = find.byKey(const Key('open-navigation'));
  await _waitForAny(tester, [find.text(label), drawer]);
  if (drawer.evaluate().isNotEmpty) {
    await tester.tap(drawer);
    await tester.pumpAndSettle();
  }
  await _waitFor(tester, find.text(label));
  await tester.tap(find.text(label).last);
  await _waitFor(tester, find.text('StoreOS · $label'));
}

Future<void> _openFixtureTask(WidgetTester tester) async {
  await _tapWhenActionable(
    tester,
    find.byKey(Key('shift-$_shiftId')),
    find.text('Schicht · Veröffentlicht'),
  );
  await _tapInList(tester, find.byKey(Key('task-$_taskId')));
  await _waitFor(tester, find.byKey(const Key('execution-status')));
}

/// The shift section disables a tile while a controller operation is in
/// flight. Tap only once the tile reports an active handler, and keep waiting
/// for the observable outcome instead of assuming the tap was accepted.
Future<void> _tapWhenActionable(
  WidgetTester tester,
  Finder target,
  Finder outcome,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (outcome.evaluate().isNotEmpty) return;
    if (_isActionable(tester, target)) {
      await _tapInList(tester, target);
      if (outcome.evaluate().isNotEmpty) return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for $target to open $outcome.');
}

bool _isActionable(WidgetTester tester, Finder target) {
  final elements = target.evaluate();
  if (elements.isEmpty) return false;
  final widget = elements.first.widget;
  return widget is ListTile && widget.onTap != null;
}

Future<void> _enterNumber(WidgetTester tester, String value) async {
  final input = find.widgetWithText(TextFormField, 'Zahlenwert (C)');
  await tester.scrollUntilVisible(
    input,
    220,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.enterText(input, value);
  await tester.pump();
}

String? _executionText(WidgetTester tester) {
  final status = find.byKey(const Key('execution-status'));
  expect(status, findsOneWidget);
  return tester.widget<Text>(status).data;
}

Future<void> _expectAttempt(WidgetTester tester, String text) async {
  final attempt = find.textContaining(text);
  await tester.scrollUntilVisible(
    attempt,
    220,
    scrollable: find.byType(Scrollable).last,
  );
  expect(attempt, findsOneWidget);
}

Future<void> _tapInList(WidgetTester tester, Finder target) async {
  try {
    await tester.scrollUntilVisible(
      target,
      220,
      scrollable: find.byType(Scrollable).last,
    );
  } on StateError {
    final status = find.byKey(const Key('execution-status'));
    final error = find.byKey(const Key('shift-error'));
    fail(
      'Cannot find $target; '
      'execution status: ${status.evaluate().isNotEmpty ? tester.widget<Text>(status).data : 'not visible'}; '
      'shift error: ${error.evaluate().isNotEmpty ? tester.widget<Text>(error).data : 'none'}.',
    );
  }
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _waitFor(WidgetTester tester, Finder target) async {
  await _waitForAny(tester, [target]);
}

Future<void> _waitForAny(WidgetTester tester, List<Finder> targets) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (targets.any((target) => target.evaluate().isNotEmpty)) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('Timed out waiting for ${targets.join(' or ')}.');
}
