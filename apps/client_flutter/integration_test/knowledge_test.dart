import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;

const password = String.fromEnvironment('STOREOS_KNOWLEDGE_PASSWORD');
const shiftId = String.fromEnvironment('STOREOS_KNOWLEDGE_SHIFT_ID');
const literal = '# markdown\n<script>literal</script>\n<a href="x">**\n  ä 😀';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'browser Knowledge author, preview, publish, employee read, replacement and work navigation',
    (tester) async {
      app.main();
      await login(tester, 'test_admin');
      await section(tester, 'Wissen');
      await tap(tester, find.text('Verwalten'));
      await tap(tester, find.byKey(const Key('knowledge-create')));
      await wait(
        tester,
        () => find.byKey(const Key('knowledge-title')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('knowledge-title')),
        'Browser Closing',
      );
      await tester.enterText(find.byKey(const Key('knowledge-body')), literal);
      await tap(tester, find.byKey(const Key('knowledge-save')));
      await wait(
        tester,
        () => find.text('Gespeicherter Entwurf.').evaluate().isNotEmpty,
      );
      await tap(tester, find.text('Gespeicherten Entwurf ansehen'));
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        200,
        scrollable: knowledgeScrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      await tap(tester, find.byKey(const Key('knowledge-publish')));
      await wait(
        tester,
        () =>
            find.byKey(const Key('knowledge-new-draft')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('logout-button')));
      await login(tester, 'knowledge_worker');
      await section(tester, 'Meine Arbeit');
      await tap(tester, find.byKey(Key('shift-$shiftId')));
      await wait(
        tester,
        () => find.text('Schicht · Veröffentlicht').evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('work-knowledge-shortcut')));
      await wait(
        tester,
        () => find.byKey(const Key('knowledge-search')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('knowledge-search')),
        'browser',
      );
      await tap(tester, find.text('Suchen'));
      await wait(
        tester,
        () => find
            .widgetWithText(ListTile, 'Browser Closing')
            .evaluate()
            .isNotEmpty,
      );
      await tap(tester, find.widgetWithText(ListTile, 'Browser Closing'));
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        200,
        scrollable: knowledgeScrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      await tap(tester, find.byType(BackButton));
      await wait(
        tester,
        () => find.text('StoreOS · Meine Arbeit').evaluate().isNotEmpty,
      );
      expect(find.text('Schicht · Veröffentlicht'), findsOneWidget);
      await tester.tap(find.byKey(const Key('logout-button')));
      await login(tester, 'test_admin');
      await section(tester, 'Wissen');
      await tap(tester, find.text('Verwalten'));
      await tap(tester, find.widgetWithText(ListTile, 'Browser Closing'));
      await tap(tester, find.byKey(const Key('knowledge-new-draft')));
      await wait(
        tester,
        () => find.byKey(const Key('knowledge-title')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('knowledge-body')),
        'Browser replacement',
      );
      await tap(tester, find.byKey(const Key('knowledge-save')));
      await wait(
        tester,
        () => find.text('Gespeicherter Entwurf.').evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('knowledge-publish')));
      await wait(
        tester,
        () =>
            find.byKey(const Key('knowledge-new-draft')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const Key('logout-button')));
      await login(tester, 'knowledge_worker');
      await section(tester, 'Wissen');
      await tap(tester, find.widgetWithText(ListTile, 'Browser Closing'));
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, 'Browser replacement'),
        200,
        scrollable: knowledgeScrollable,
      );
      expect(
        find.widgetWithText(SelectableText, 'Browser replacement'),
        findsOneWidget,
      );
    },
  );
}

Future<void> wait(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) fail('Browser outcome timed out.');
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<void> login(WidgetTester tester, String user) async {
  await wait(
    tester,
    () => find.byKey(const Key('username-field')).evaluate().isNotEmpty,
  );
  await tester.enterText(find.byKey(const Key('username-field')), user);
  await tester.enterText(find.byKey(const Key('password-field')), password);
  await tester.tap(find.byKey(const Key('login-button')));
  await wait(
    tester,
    () => find.byKey(const Key('logout-button')).evaluate().isNotEmpty,
  );
}

Future<void> section(WidgetTester tester, String name) async {
  final drawer = find.byKey(const Key('open-navigation'));
  await wait(
    tester,
    () => drawer.evaluate().isNotEmpty || find.text(name).evaluate().isNotEmpty,
  );
  if (drawer.evaluate().isNotEmpty) {
    await tester.tap(drawer);
    await tester.pumpAndSettle();
  }
  await tap(tester, find.text(name).last);
  await wait(tester, () => find.text('StoreOS · $name').evaluate().isNotEmpty);
  await wait(
    tester,
    () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
  );
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  try {
    await readyTap(tester, target);
  } catch (error) {
    throw StateError('Knowledge browser action $target failed: $error');
  }
}

Future<void> readyTap(WidgetTester tester, Finder target) async {
  await wait(
    tester,
    () =>
        target.evaluate().isNotEmpty || activeScrollable.evaluate().isNotEmpty,
  );
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(target, 200, scrollable: activeScrollable);
  }
  await wait(tester, () {
    if (target.evaluate().isEmpty) return false;
    final buttons = find
        .ancestor(
          of: target,
          matching: find.byWidgetPredicate(
            (widget) => widget is ButtonStyleButton,
          ),
        )
        .evaluate();
    if (buttons.isNotEmpty &&
        (buttons.first.widget as ButtonStyleButton).onPressed == null) {
      return false;
    }
    final widget = target.evaluate().first.widget;
    return switch (widget) {
      ButtonStyleButton() => widget.onPressed != null,
      ListTile() => widget.onTap != null,
      _ => true,
    };
  });
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
}

Finder get knowledgeScrollable => find
    .descendant(
      of: find.byKey(const Key('knowledge-list')),
      matching: find.byType(Scrollable),
    )
    .first;

Finder get activeScrollable => knowledgeScrollable.evaluate().isNotEmpty
    ? knowledgeScrollable
    : find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
