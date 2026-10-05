import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:storeos_client/main.dart' as app;
import 'knowledge_test.dart' show login, section, wait;
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/merchandising_controller.dart'
    show layoutUuid;

@JS('eval')
external bool browserPredicate(String expression);

const literal =
    '<script>window.storeosGuidanceInjected=true</script>\n<a href="https://invalid.example/p46">literal link</a>\n<img src="https://invalid.example/p46" onerror="window.storeosGuidanceInjected=true">\n# Markdown **plain** [link](https://invalid.example/p46)';
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Chrome exact deployment selection preview publication historical read and completion',
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
        'Browser instruction v1',
      );
      await tester.enterText(find.byKey(const Key('knowledge-body')), literal);
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
      await section(tester, 'Arbeitsvorlagen');
      await tap(tester, find.byKey(const Key('create-template')));
      await wait(
        tester,
        () => find.byKey(const Key('new-template-title')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('new-template-title')),
        'Browser guided work',
      );
      await tap(tester, find.text('Anlegen'));
      await wait(
        tester,
        () => find.text('Revision 1 · Entwurf').evaluate().isNotEmpty,
      );
      await tap(tester, find.text('Schritt hinzufügen'));
      await enter(tester, prefix('instruction-').first, 'Confirm normal work');
      await tap(tester, find.text('Zahlenschritt hinzufügen'));
      await enter(tester, prefix('instruction-').last, 'Record normal number');
      await enter(tester, prefix('unit-'), 'C');
      await enter(tester, prefix('minimum-'), '1');
      await enter(tester, prefix('maximum-'), '5');
      await tap(tester, find.byKey(const Key('choose-planogram')));
      await tap(tester, prefix('planogram-choice-').first);
      await tap(tester, find.byKey(const Key('preview-planogram')));
      await show(tester, find.byKey(const Key('layout-frozen-instruction')));
      expect(find.text(layoutLiteral), findsOneWidget);
      await show(tester, find.byKey(const Key('publish-template')));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('publish-template')))
            .onPressed,
        isNull,
      );
      await tap(tester, find.byKey(const Key('choose-guidance')));
      await tap(
        tester,
        find.widgetWithText(ListTile, 'Browser instruction v1'),
      );
      await tap(tester, find.text('Zugewiesene Revision ansehen'));
      await wait(
        tester,
        () => find
            .byKey(const Key('template-guidance-body'))
            .evaluate()
            .isNotEmpty,
      );
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('template-guidance-body')),
            )
            .data,
        literal,
      );
      await tap(tester, find.byKey(const Key('save-template')));
      await show(tester, find.text('Entwurf gespeichert und bestätigt.'));
      await wait(
        tester,
        () => find
            .text('Entwurf gespeichert und bestätigt.')
            .evaluate()
            .isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('publish-template')));
      await tap(tester, find.text('Bestätigen'));
      await show(tester, find.text('Revision 1 · Freigegeben'));
      await wait(
        tester,
        () => find.text('Revision 1 · Freigegeben').evaluate().isNotEmpty,
      );
      await section(tester, 'Schichten');
      await tap(tester, find.byKey(const Key('new-shift')));
      await tap(tester, find.byType(DropdownButtonFormField<String>));
      await tap(tester, find.text('Guided worker').last);
      final now = DateTime.now().toUtc();
      await enter(tester, prefix('start-'), now.toIso8601String());
      await enter(
        tester,
        prefix('end-'),
        now.add(const Duration(hours: 1)).toIso8601String(),
      );
      await tap(tester, find.text('Revision wählen: Browser guided work'));
      await tap(
        tester,
        find.text('Revision 1: Browser guided work hinzufügen'),
      );
      await tap(tester, find.byKey(const Key('save-shift')));
      await show(tester, find.byKey(const Key('publish-shift')));
      await wait(
        tester,
        () => find.byKey(const Key('publish-shift')).evaluate().isNotEmpty,
      );
      await tap(tester, find.text('Anleitungsreferenzen prüfen'));
      await wait(
        tester,
        () => find.textContaining('WikiArticle').evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('publish-shift')));
      await tap(tester, find.text('Bestätigen'));
      await show(tester, find.text('Schicht · Veröffentlicht'));
      await wait(
        tester,
        () => find.text('Schicht · Veröffentlicht').evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('logout-button')));
      await login(tester, 'guided_worker');
      await section(tester, 'Meine Arbeit');
      await tap(tester, prefix('shift-').first);
      await tap(tester, prefix('task-').first);
      await tap(tester, find.byKey(const Key('assigned-layout')));
      await show(tester, find.byKey(const Key('layout-frozen-instruction')));
      expect(find.text(layoutLiteral), findsOneWidget);
      await tap(tester, find.byKey(const Key('return-from-layout')));
      await tap(tester, find.byKey(const Key('assigned-instruction')));
      await verifyLiteral(tester);
      await tap(tester, find.byKey(const Key('return-to-task')));
      await tester.runAsync(replaceRetireDeployment);
      await tap(tester, find.byKey(const Key('assigned-layout')));
      await show(tester, find.byKey(const Key('layout-frozen-instruction')));
      expect(find.text(layoutLiteral), findsOneWidget);
      expect(find.byKey(const Key('layout-reassigned')), findsOneWidget);
      expect(find.byKey(const Key('layout-fixture-retired')), findsOneWidget);
      expect(find.byKey(const Key('layout-planogram-retired')), findsOneWidget);
      expect(
        find.textContaining('<img src="https://invalid.example/p47"'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '<a href="https://invalid.example/p47">Current article</a>',
        ),
        findsOneWidget,
      );
      expect(
        browserPredicate('globalThis.storeosLayoutInjected !== true'),
        true,
      );
      expect(
        browserPredicate(
          '!Array.from(document.scripts).some(s=>s.textContent.includes("storeosLayoutInjected"))',
        ),
        true,
      );
      expect(
        browserPredicate(
          r"""document.querySelectorAll('img[onerror], a[href*="invalid.example/p47"], img[src*="invalid.example/p47"]').length===0""",
        ),
        true,
      );
      await tap(tester, find.byKey(const Key('return-from-layout')));
      await tap(tester, find.byKey(const Key('start-task')));
      await show(tester, find.byKey(const Key('confirm-step')));
      await wait(
        tester,
        () => find.byKey(const Key('confirm-step')).evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('confirm-step')));
      await show(tester, find.byKey(const Key('record-number')));
      await wait(
        tester,
        () => find.byKey(const Key('record-number')).evaluate().isNotEmpty,
      );
      await enter(tester, prefix('number-'), '3');
      await tap(tester, find.byKey(const Key('record-number')));
      await show(tester, find.byKey(const Key('complete-task')));
      await wait(
        tester,
        () => find.byKey(const Key('complete-task')).evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('complete-task')));
      await show(tester, find.byKey(const Key('execution-status')));
      await wait(
        tester,
        () =>
            tester
                .widget<Text>(find.byKey(const Key('execution-status')))
                .data ==
            'Abgeschlossen · 2/2 bestätigt',
      );
      await tap(tester, find.byKey(const Key('logout-button')));
      await login(tester, 'test_admin');
      await section(tester, 'Wissen');
      await tap(tester, find.text('Verwalten'));
      await tap(
        tester,
        find.widgetWithText(ListTile, 'Browser instruction v1'),
      );
      await tap(tester, find.byKey(const Key('knowledge-new-draft')));
      await wait(
        tester,
        () => find.byKey(const Key('knowledge-body')).evaluate().isNotEmpty,
      );
      await tester.enterText(
        find.byKey(const Key('knowledge-body')),
        'Browser replacement v2',
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
      await tap(tester, find.byKey(const Key('knowledge-retire')));
      await show(tester, find.text('RETIRED ARTICLE'));
      await wait(
        tester,
        () => find.text('RETIRED ARTICLE').evaluate().isNotEmpty,
      );
      await tap(tester, find.byKey(const Key('logout-button')));
      await login(tester, 'guided_worker');
      await section(tester, 'Meine Arbeit');
      await tap(tester, prefix('shift-').first);
      await tap(tester, prefix('task-').first);
      await tap(tester, find.byKey(const Key('assigned-instruction')));
      await verifyLiteral(tester);
      expect(find.textContaining('Historische Revision'), findsOneWidget);
      expect(find.textContaining('Artikel stillgelegt'), findsOneWidget);
      expect(find.text('Browser replacement v2'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

Finder prefix(String value) => find.byWidgetPredicate(
  (widget) =>
      widget.key is ValueKey<String> &&
      (widget.key as ValueKey<String>).value.startsWith(value),
);
Future<void> enter(WidgetTester tester, Finder finder, String text) async {
  if (finder.evaluate().isEmpty) await tester.scrollUntilVisible(finder, 200);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pump();
}

Future<void> tap(WidgetTester tester, Finder target) async {
  await show(tester, target);
  await tester.tap(target);
  await tester.pump();
}

Future<void> show(WidgetTester tester, Finder target) async {
  try {
    // Mount the operation status before waiting; long retained previews can leave it offscreen.
    final list = find.byType(ListView).last;
    final scroll = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    if (scroll.evaluate().isNotEmpty) {
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await tester.pump();
    }
    await wait(
      tester,
      () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(target, 150, scrollable: scroll);
    }
    await wait(tester, () => target.evaluate().isNotEmpty);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    final error = tester.takeException();
    if (error != null) throw StateError('Rendering $target failed: $error');
  } catch (error) {
    throw StateError('P47 browser could not reveal $target: $error');
  }
}

Future<void> verifyLiteral(WidgetTester tester) async {
  await wait(
    tester,
    () => find.byKey(const Key('task-instruction-body')).evaluate().isNotEmpty,
  );
  await tester.ensureVisible(find.byKey(const Key('task-instruction-body')));
  expect(
    tester
        .widget<SelectableText>(find.byKey(const Key('task-instruction-body')))
        .data,
    literal,
  );
  expect(browserPredicate('globalThis.storeosGuidanceInjected !== true'), true);
  expect(
    browserPredicate(
      'document.querySelectorAll("a[href*=\\"invalid.example/p46\\"], img[src*=\\"invalid.example/p46\\"], img[onerror], script").length === Array.from(document.scripts).filter(s => !s.textContent.includes("storeosGuidanceInjected")).length',
    ),
    true,
  );
  expect(
    browserPredicate(
      '!Array.from(document.scripts).some(s => s.textContent.includes("storeosGuidanceInjected"))',
    ),
    true,
  );
}

const layoutLiteral =
    '<script>window.storeosLayoutInjected=true</script> <img onerror="x"> **plain**';
Future<void> replaceRetireDeployment() async {
  final base = Uri.parse(const String.fromEnvironment('STOREOS_API_URL'));
  if (base.host != '127.0.0.1') throw StateError('Isolated loopback required.');
  final client = http.Client();
  try {
    final api = HttpPlatformApi(baseUri: base, client: client),
        auth = HttpStoreApi(baseUri: base, client: client);
    final session = await auth.login(
      const LoginRequest(
        username: 'test_admin',
        password: String.fromEnvironment('STOREOS_KNOWLEDGE_PASSWORD'),
      ),
    );
    final token = session.token,
        fixture = const String.fromEnvironment('STOREOS_P47_FIXTURE'),
        pg = const String.fromEnvironment('STOREOS_P47_PLANOGRAM');
    final root =
            '/locations/${session.user.locationId}/merchandising/fixtures/$fixture',
        plans = '/merchandising/planograms/$pg';
    final original = LayoutViewDto.fromJson(
      await api.get(token, '$root/layout'),
    );
    final plan = await api.get(token, plans), revision = layoutUuid();
    final draft = await api.post(token, '$plans/revisions', {
      'id': revision,
      'expectedVersion': plan['version'],
      'content': LayoutContent(
        title: 'Browser replacement layout R2',
        zones: [
          LayoutZone(
            id: layoutUuid(),
            label: 'Replacement zone',
            placements: [
              LayoutPlacement(
                id: layoutUuid(),
                articleId: original.articles.single['id'] as String,
                facings: 5,
              ),
            ],
          ),
        ],
      ).toJson(),
    });
    final published = await api
        .post(token, '$plans/revisions/$revision/publish', {
          'operationId': layoutUuid(),
          'expectedVersion': draft['planogram']['version'],
        });
    final f = await api.get(token, root);
    final assigned = await api.post(token, '$root/assignments', {
      'operationId': layoutUuid(),
      'expectedVersion': f['version'],
      'revisionId': revision,
    });
    final current = LayoutViewDto.fromJson(
      await api.get(token, '$root/layout'),
    );
    expect(current.revision!.id, revision);
    expect(current.assignment!.id, isNot(original.assignment!.id));
    await api.post(token, '$root/retire', {
      'expectedVersion': assigned['appliedVersion'],
    });
    await api.post(token, '$plans/retire', {
      'expectedVersion': published['appliedVersion'],
    });
    await auth.logout(token);
  } finally {
    client.close();
  }
}
