import 'dart:async';
import 'dart:convert';
import 'task_planogram_response.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/task_template_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/task_template_section.dart';

const company = '11111111-1111-4111-8111-111111111111';
const location = '22222222-2222-4222-8222-222222222222';
const account = '33333333-3333-4333-8333-333333333333';

void main() {
  test(
    'Planogram and Knowledge remain independent through select save replace clear and schema 4 numeric editing',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await f.c.loadGuidance();
      f.c.selectGuidance(f.c.guidanceChoices!.first);
      LayoutViewDto.fromJson(selectionLayout);
      await f.c.loadPlanograms();
      expect(f.c.error, isNull);
      expect(f.c.planogramChoices, isNotNull);
      final candidate = f.c.planogramChoices!.single;
      f.c.selectPlanogram(candidate);
      expect(f.c.canPublish, false);
      final pin = f.c.planogramGuidance!.toJson();
      f.c.clearGuidance();
      expect(f.c.planogramGuidance!.toJson(), pin);
      await f.c.loadGuidance();
      f.c.selectGuidance(f.c.guidanceChoices!.first);
      f.c.clearPlanogram();
      expect(f.c.knowledgeGuidance, isNotNull);
      await f.c.loadPlanograms();
      f.c.selectPlanogram(f.c.planogramChoices!.single);
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.revision!.content!.schemaVersion, 4);
      expect(f.c.canPublish, true);
      await f.c.previewPlanogram();
      expect(f.c.planogramPreview!.instruction.pin.toJson(), pin);
      f.c.addStep(numeric: true);
      final id = f.c.steps.last.id;
      f.c.setInstruction(id, 'Measure');
      f.c.setNumberRule(id, 'unit', 'C');
      f.c.setNumberRule(id, 'minimum', '1');
      f.c.setNumberRule(id, 'maximum', '5');
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.revision!.content!.schemaVersion, 4);
      f.api.planogramUnavailable = true;
      final saved = jsonEncode(f.api.records);
      final version = f.c.selected!.version;
      await f.c.publish();
      expect(f.c.error, contains('neu auswählen'));
      expect(jsonEncode(f.api.records), saved);
      expect(f.c.selected!.version, version);
      f.c.setTitle('Retained stale draft edit');
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.planogramGuidance!.toJson(), pin);
      f.c.clearPlanogram();
      await f.c.save();
      expect(f.c.revision!.content!.schemaVersion, 4);
      expect(f.c.knowledgeGuidance, isNotNull);
    },
  );
  test(
    'Planogram selection failure preserves input and explicit replacement captures a new occurrence',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await f.c.loadGuidance();
      f.c.selectGuidance(f.c.guidanceChoices!.first);
      await f.c.loadPlanograms();
      f.c.selectPlanogram(f.c.planogramChoices!.single);
      final original = f.c.planogramGuidance!.toJson();
      f.c.setTitle('Unsaved local title');
      f.c.setInstruction(f.c.steps.single.id, 'Unsaved local instruction');
      final saved = f.api.copy(f.api.records[f.c.revision!.id]!);
      final version = f.c.selected!.version;
      f.api.selectionUnavailable = true;
      await f.c.save();
      expect(f.c.error, contains('Eingaben bleiben erhalten'));
      expect(f.c.title, 'Unsaved local title');
      expect(f.c.steps.single.instruction, 'Unsaved local instruction');
      expect(f.c.planogramGuidance!.toJson(), original);
      expect(f.c.knowledgeGuidance, isNotNull);
      expect(f.c.dirty, true);
      expect(f.c.canPublish, false);
      expect(f.c.selected!.version, version);
      expect(f.api.records[f.c.revision!.id], saved);
      f.api.selectionUnavailable = false;
      await f.c.save();
      const replacement = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      f.api.layout['assignment']['id'] = replacement;
      f.api.layout['fixture']['currentAssignmentId'] = replacement;
      await f.c.loadPlanograms();
      f.c.selectPlanogram(f.c.planogramChoices!.single);
      expect(f.c.planogramGuidance!.assignmentId, replacement);
      expect(f.c.knowledgeGuidance, isNotNull);
      await f.c.save();
      expect(f.c.error, isNull);
      expect(
        f.c.revision!.content!.planogramGuidance!.assignmentId,
        replacement,
      );
      f.c.clearPlanogram();
      await f.c.save();
      expect(f.c.revision!.content!.planogramGuidance, isNull);
      expect(f.c.revision!.content!.knowledgeGuidance, isNotNull);
    },
  );
  testWidgets(
    'dual previews remain stable while the scrolled editor changes height',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TaskTemplateSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      await f.c.loadPlanograms();
      f.c.selectPlanogram(f.c.planogramChoices!.single);
      await f.c.previewPlanogram();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('choose-guidance')));
      await f.c.loadGuidance();
      await tester.pumpAndSettle();
      f.c.selectGuidance(f.c.guidanceChoices!.first);
      await f.c.previewGuidance();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('save-template')));
      f.c.clearPlanogram();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(f.c.knowledgeGuidance, isNotNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  for (final actor in ['test', 'replacement']) {
    for (final surface in ['picker', 'preview']) {
      test(
        'Planogram $actor session replacement fences pending $surface and stale callbacks',
        () async {
          final f = await _Fixture.create();
          addTearDown(f.dispose);
          await f.ready();
          await f.c.loadPlanograms();
          final cached = f.c.planogramChoices!.single;
          f.c.selectPlanogram(cached);
          await f.c.save();
          f.api.planogramPending = Completer<Map<String, dynamic>>();
          f.api.planogramStarted = Completer<void>();
          final action = surface == 'picker'
              ? f.c.loadPlanograms()
              : f.c.previewPlanogram();
          await f.api.planogramStarted!.future;
          final oldToken = f.api.planogramTokens.last;
          final oldRequests = f.api.planogramTokens.length;
          await f.session.signIn(username: actor, password: 'test');
          expect(f.c.planogramGuidance, isNull);
          expect(f.c.planogramChoices, isNull);
          expect(f.c.planogramPreview, isNull);
          expect(f.c.planogramSelectionPreview, isNull);
          f.api.planogramPending!.complete(
            surface == 'picker'
                ? {
                    'items': [selectionFixture],
                    'nextCursor': null,
                  }
                : retainedLayout,
          );
          await action;
          expect(f.c.selected, isNull);
          expect(f.c.planogramChoices, isNull);
          expect(f.c.planogramPreview, isNull);
          expect(f.c.error, isNull);
          expect(f.api.planogramTokens.length, oldRequests);
          expect(f.api.planogramTokens.last, oldToken);
          f.c.selectPlanogram(cached);
          expect(f.c.planogramGuidance, isNull);
        },
      );
    }
  }
  test(
    'selection failure preserves local edit input and saved draft',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      final saved = f.api.copy(f.api.records[f.c.revision!.id]!);
      final version = f.c.selected!.version;
      await f.c.loadGuidance();
      final selected = f.c.guidanceChoices!.last;
      f.c.selectGuidance(selected);
      f.c.setTitle('Local draft input');
      final step = f.c.steps.single.id;
      f.c.setInstruction(step, 'Local step input');
      f.api.retired = true;
      await f.c.save();
      expect(f.c.error, contains('für diesen Entwurf nicht verfügbar'));
      expect(f.c.error, contains('Eingaben bleiben erhalten'));
      expect(f.c.error, isNot(contains('für neue Arbeit')));
      expect(f.c.title, 'Local draft input');
      expect(f.c.steps.single.instruction, 'Local step input');
      expect(f.c.knowledgeGuidance!.revisionId, selected.revisionId);
      expect(f.c.revision!.isDraft, true);
      expect(f.c.revision!.content!.knowledgeGuidance, isNull);
      expect(f.c.dirty, true);
      expect(f.c.editable, true);
      expect(f.c.canPublish, false);
      expect(f.c.selected!.version, version);
      expect(f.api.records[f.c.revision!.id], saved);
      f.api.retired = false;
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.dirty, false);
      expect(f.c.knowledgeGuidance!.revisionId, selected.revisionId);
    },
  );
  test(
    'guidance selects, previews exact revision, retains, replaces and clears without publishing unsaved state',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await f.c.loadGuidance();
      final first = f.c.guidanceChoices!.first;
      f.c.selectGuidance(first);
      expect(f.c.canPublish, false);
      await f.c.previewGuidance();
      expect(f.c.guidancePreview!.revisionId, first.revisionId);
      expect(f.c.guidancePreview!.body, '<script>literal</script>');
      await f.c.save();
      expect(f.c.dirty, false);
      expect(f.c.canPublish, true);
      f.c.setTitle('Unrelated change');
      await f.c.save();
      expect(f.c.knowledgeGuidance!.revisionId, first.revisionId);
      await f.c.loadGuidance();
      final replacement = f.c.guidanceChoices!.last;
      f.c.selectGuidance(replacement);
      await f.c.save();
      expect(f.c.knowledgeGuidance!.revisionId, replacement.revisionId);
      f.c.clearGuidance();
      expect(f.c.canPublish, false);
      await f.c.save();
      expect(f.c.revision!.content!.schemaVersion, 3);
      expect(f.c.knowledgeGuidance, isNull);
      await f.c.loadGuidance();
      f.c.selectGuidance(f.c.guidanceChoices!.first);
      await f.c.save();
      f.api.retired = true;
      final saved = f.api.copy(f.api.records[f.c.revision!.id]!);
      final version = f.c.selected!.version;
      await f.c.publish();
      expect(f.c.error, contains('nicht mehr verfügbar'));
      expect(f.c.error, contains('für neue Arbeit'));
      expect(f.c.error, contains('entfernen oder ersetzen'));
      expect(f.c.revision!.isDraft, true);
      expect(f.c.knowledgeGuidance!.revisionId, first.revisionId);
      expect(f.c.selected!.version, version);
      expect(f.api.records[f.c.revision!.id], saved);
      expect(f.c.dirty, false);
      expect(f.c.editable, true);
    },
  );
  for (final actor in ['test', 'replacement']) {
    for (final surface in ['picker', 'preview']) {
      test(
        '$actor replacement fences pending $surface and cached guidance',
        () async {
          final f = await _Fixture.create();
          addTearDown(f.dispose);
          await f.ready();
          await f.c.loadGuidance();
          f.c.selectGuidance(f.c.guidanceChoices!.first);
          final cached = f.c.guidancePreview!;
          f.api.guidancePending = Completer<Map<String, dynamic>>();
          f.api.guidanceStarted = Completer<void>();
          final pending = surface == 'picker'
              ? f.c.loadGuidance()
              : f.c.previewGuidance();
          await f.api.guidanceStarted!.future;
          await f.session.signIn(username: actor, password: 'test');
          expect(f.c.guidanceChoices, isNull);
          expect(f.c.guidancePreview, isNull);
          expect(f.c.knowledgeGuidance, isNull);
          f.api.guidancePending!.complete(
            surface == 'picker'
                ? {
                    'items': [cached.toJson()],
                    'nextCursor': null,
                  }
                : f.api.knowledgeRevision(cached),
          );
          await pending;
          expect(f.c.guidanceChoices, isNull);
          expect(f.c.guidancePreview, isNull);
          expect(f.c.selected, isNull);
          expect(f.c.error, isNull);
          f.c.selectGuidance(cached);
          expect(f.c.knowledgeGuidance, isNull);
        },
      );
    }
  }
  test(
    'numeric template editing validates bounds, publishes schema 2 and preserves immutable revisions',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.c.addStep(numeric: true);
      final id = f.c.steps.last.id;
      f.c.setInstruction(id, 'Record temperature');
      f.c.setNumberRule(id, 'unit', 'C');
      f.c.setNumberRule(id, 'minimum', '-2,125');
      f.c.setNumberRule(id, 'maximum', '-3');
      await f.c.save();
      expect(f.c.error, isNotNull);
      expect(f.c.steps.last.minimum, '-2,125');
      f.c.setNumberRule(id, 'maximum', '4,5');
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.revision!.content!.schemaVersion, 2);
      expect(f.c.steps.last.minimum, '-2.125');
      f.c.setInstruction(id, 'Read display');
      await f.c.save();
      expect(f.c.steps.last.type, 'number');
      expect(f.c.steps.last.maximum, '4.5');
      await f.c.publish();
      final published = f.c.revision!.id;
      await f.c.newDraft();
      f.c.setNumberRule(id, 'maximum', '5');
      await f.c.save();
      expect(
        f.api.records[published]!['content']['steps'][1]['maximum'],
        '4.5',
      );
      expect(f.c.steps.last.maximum, '5');
    },
  );

  test('failed overview refresh preserves a confirmed creation', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.failList = true;
    await f.c.create('Opening', location);
    expect(f.c.error, isNotNull);
    expect(f.c.notice, contains('gespeichert'));
    expect(f.c.confirmed, isTrue);
    expect(f.c.selected, isNotNull);
    expect(f.c.title, 'Opening');
    expect(f.api.records.length, 1);
    f.api.failList = false;
    await f.c.loadList();
    expect(f.c.error, isNull);
    expect(f.c.templates!.single.id, f.c.selected!.id);
    expect(f.api.records.length, 1);
  });

  test(
    'lost publication response cannot confirm different published content',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      final original = f.c.title;
      f.api.conflict = true;
      f.api.concurrentPublish = true;
      f.api.loseResponse = true;
      await f.c.publish();
      expect(f.c.notice, isNull);
      expect(f.c.conflict, isTrue);
      expect(f.c.title, original);
      expect(f.c.dirty, isTrue);
      expect(f.c.canNewDraft, isFalse);
      expect(f.c.error, isNotNull);
    },
  );
  test('creation refreshes the overview without another user action', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.c.loadList();
    expect(f.c.templates, isEmpty);
    await f.c.create('Opening', location);
    expect(f.c.templates, isNotNull);
    expect(f.c.templates!.single.id, f.c.selected!.id);
    expect(f.c.templates!.single.title, 'Opening');
  });

  for (final operation in ['create', 'save', 'publish', 'newDraft']) {
    test(
      'lost $operation response reconciles the same stable revision',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        if (operation != 'create') await f.ready();
        if (operation == 'newDraft') await f.c.publish();
        f.api.loseResponse = true;
        await f.act(operation);
        expect(f.c.error, isNull);
        expect(f.c.confirmed, isTrue);
        expect(f.c.notice, isNotNull);
        expect(f.api.records.length, operation == 'newDraft' ? 2 : 1);
      },
    );
    test('late $operation does not continue in a new session', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      if (operation != 'create') await f.ready();
      if (operation == 'newDraft') await f.c.publish();
      final pending = Completer<Map<String, dynamic>>();
      f.api.pending = pending;
      final action = f.act(operation);
      await f.session.signOut();
      await f.signIn();
      await f.c.loadList();
      final count = f.api.requests;
      pending.complete({});
      await action;
      expect(f.api.requests, count);
      expect(f.c.selected, isNull);
      expect(f.c.revision, isNull);
      expect(f.c.error, isNull);
    });
  }
  test(
    'conflicts preserve local input and require explicit server adoption',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.c.setTitle('Local edit');
      f.api.conflict = true;
      await f.c.save();
      expect(f.c.conflict, isTrue);
      expect(f.c.title, 'Local edit');
      expect(f.c.editable, isFalse);
      expect(f.c.notice, isNull);
      expect(f.c.error, contains('Serverstand'));
      f.c.useServerVersion();
      expect(f.c.title, 'Remote edit');
      expect(f.c.dirty, isFalse);
      expect(f.c.editable, isTrue);
    },
  );
  test('concurrent publication preserves unconfirmed local content', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.ready();
    f.c.setTitle('Local edit');
    f.api.conflict = true;
    f.api.concurrentPublish = true;
    await f.c.save();
    expect(f.c.revision!.isDraft, isFalse);
    expect(f.c.dirty, isTrue);
    expect(f.c.title, 'Local edit');
    expect(f.c.conflict, isTrue);
    expect(f.c.canNewDraft, isFalse);
    expect(f.c.canPublish, isFalse);
    f.c.useServerVersion();
    expect(f.c.dirty, isFalse);
    expect(f.c.title, 'Remote edit');
  });
  test(
    'failed reconciliation keeps local text but removes confirmation and write actions',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.c.setTitle('Local');
      f.api.failGet = true;
      await f.c.save();
      expect(f.c.confirmed, isFalse);
      expect(f.c.editable, isFalse);
      expect(f.c.title, 'Local');
      expect(f.c.error, isNotNull);
      expect(f.c.notice, isNull);
      f.api.failGet = false;
      await f.c.open(f.api.head!['id'] as String);
      expect(f.c.title, 'Local');
      expect(f.c.confirmed, isTrue);
    },
  );
  test(
    'viewer cannot request or create templates through controller entry points',
    () async {
      final f = await _Fixture.create(role: 'viewer');
      addTearDown(f.dispose);
      final count = f.api.requests;
      await f.c.loadList();
      await f.c.create('Denied', location);
      expect(f.api.requests, count);
      expect(f.c.templates, isNull);
    },
  );
  test(
    'list and history continuation use the returned cursors without loading content',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.api.paging = true;
      await f.c.loadList();
      expect(f.c.nextCursor, 'list-page');
      await f.c.loadList(more: true);
      expect(f.c.nextCursor, isNull);
      await f.c.open(f.c.selected!.id);
      expect(f.c.revisionCursor, 'revision-page');
      await f.c.moreHistory();
      expect(f.c.revisionCursor, isNull);
      expect(f.api.cursors, containsAll(['list-page', 'revision-page']));
    },
  );
  testWidgets(
    'editor persists steps, ordering, publication and immutable history',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TaskTemplateSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Noch keine Arbeitsvorlagen vorhanden.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('create-template')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-template-title')),
        'Opening',
      );
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.number, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('publish-template')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Schritt hinzufügen'));
      await tester.tap(find.text('Schritt hinzufügen'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Anleitungstext');
      await tester.enterText(field, 'Check door');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-dirty')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('save-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('save-template')));
      await tester.pumpAndSettle();
      expect(f.c.dirty, isFalse);
      await tester.ensureVisible(find.byKey(const Key('publish-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('publish-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.isDraft, isFalse);
      expect(find.byKey(const Key('save-template')), findsNothing);
      await tester.ensureVisible(
        find.text('Neue Revision aus letzter Freigabe'),
      );
      await tester.tap(find.text('Neue Revision aus letzter Freigabe'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.number, 2);
      f.c.addStep();
      final second = f.c.steps.last.id;
      f.c.setInstruction(second, 'Check light');
      f.c.moveStep(second, -1);
      await f.c.save();
      expect(f.c.steps.first.instruction, 'Check light');
      await f.c.open(f.c.selected!.id, revisionId: f.api.records.keys.first);
      await tester.pumpAndSettle();
      expect(f.c.steps.single.instruction, 'Check door');
      expect(f.c.editable, isFalse);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets(
    'invalid text shows error and session expiry clears an open editor',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TaskTemplateSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      f.c.setTitle('');
      await f.c.save();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-error')), findsOneWidget);
      expect(f.c.dirty, isTrue);
      await f.session.signOut();
      await tester.pumpAndSettle();
      expect(f.c.steps, isEmpty);
      expect(find.text('Revisionshistorie'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}

class _Fixture {
  _Fixture(this.session, this.platform, this.c, this.api);
  final SessionController session;
  final PlatformController platform;
  final TaskTemplateController c;
  final _Api api;
  bool disposed = false;
  static Future<_Fixture> create({String role = 'admin'}) async {
    final api = _Api(role), session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final c = TaskTemplateController(session, platform, api);
    final f = _Fixture(session, platform, c, api);
    await f.signIn();
    return f;
  }

  Future<void> signIn() async {
    await session.signIn(username: 'test', password: 'test');
    while (platform.isBusy) {
      await Future<void>.value();
    }
  }

  Future<void> ready() async {
    await c.create('Opening', location);
    c.addStep();
    c.setInstruction(c.steps.single.id, 'Check');
    await c.save();
  }

  Future<void> act(String operation) => switch (operation) {
    'create' => c.create('Opening', location),
    'publish' => c.publish(),
    'newDraft' => c.newDraft(),
    _ => (() {
      c.setTitle('Changed');
      return c.save();
    })(),
  };
  void dispose() {
    if (disposed) return;
    disposed = true;
    c.dispose();
    platform.dispose();
    session.dispose();
  }
}

class _Session implements StoreApi {
  int generation = 0;
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'token-${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: request.username == 'test'
          ? account
          : 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      username: request.username,
      companyId: company,
      locationId: location,
    ),
  );
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> logout(String token) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      const SystemStatusResponse(companyId: company, locationId: location);
}

class _Api implements PlatformApi {
  _Api(this.role);
  final String role;
  Map<String, dynamic>? head;
  final records = <String, Map<String, dynamic>>{};
  bool loseResponse = false, conflict = false, failGet = false, paging = false;
  bool concurrentPublish = false, failList = false;
  int requests = 0;
  final cursors = <String>[];
  Completer<Map<String, dynamic>>? pending;
  Completer<Map<String, dynamic>>? guidancePending;
  Completer<void>? guidanceStarted;
  bool retired = false,
      planogramUnavailable = false,
      selectionUnavailable = false;
  final layout =
      jsonDecode(jsonEncode(selectionLayout)) as Map<String, dynamic>;
  final planogramTokens = <String>[];
  Completer<Map<String, dynamic>>? planogramPending;
  Completer<void>? planogramStarted;
  final knowledge = [
    for (final n in [1, 2])
      PublishedWikiDto.fromJson({
        'articleId': '88888888-8888-4888-8888-888888888888',
        'revisionId': n == 1
            ? '99999999-9999-4999-8999-999999999999'
            : 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        'revisionNumber': n,
        'title': 'Instruction $n',
        'body': '<script>literal</script>',
        'publishedAt': '2026-09-27T00:00:00Z',
      }),
  ];
  Map<String, dynamic> knowledgeRevision(PublishedWikiDto pin) => {
    'id': pin.revisionId,
    'companyId': company,
    'articleId': pin.articleId,
    'revisionNumber': pin.revisionNumber,
    'status': 'published',
    'content': {'title': pin.title, 'body': pin.body},
    'createdAt': time,
    'createdBy': account,
    'publishedAt': time,
    'publishedBy': account,
  };
  static const time = '2026-09-27T00:00:00Z';
  Map<String, dynamic> copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    requests++;
    if (route == '/context') {
      return {
        'userId': account,
        'companyId': company,
        'locationId': location,
        'role': role,
        'permissions': [
          'context.read',
          'organization.read',
          if (role == 'admin') 'tasks.templates.manage',
          if (role == 'admin') 'knowledge.articles.read',
          if (role == 'admin') 'merchandising.layouts.read',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Company', 'version': 1},
        'locations': [
          {'id': location, 'companyId': company, 'name': 'Home', 'version': 1},
        ],
      };
    }
    if (failGet) {
      throw const StoreApiException('network_unavailable', 'Nicht erreichbar.');
    }
    if (route.contains('/merchandising/fixtures') ||
        route.endsWith('/planogram')) {
      planogramTokens.add(token);
      if (planogramPending != null) {
        planogramStarted!.complete();
        return planogramPending!.future;
      }
      if (route.endsWith('/guidance-selection')) return copy(layout);
      if (route.endsWith('/planogram')) return retainedLayout;
      return {
        'items': [copy(layout['fixture'] as Map<String, dynamic>)],
        'nextCursor': null,
      };
    }
    if (route.startsWith('/knowledge/')) {
      if (guidancePending != null) {
        guidanceStarted?.complete();
        return guidancePending!.future;
      }
      if (route == '/knowledge/articles') {
        return {
          'items': retired ? [] : knowledge.map((k) => k.toJson()).toList(),
          'nextCursor': null,
        };
      }
      return knowledgeRevision(
        knowledge.singleWhere((k) => route.endsWith(k.revisionId)),
      );
    }
    if (after != null) cursors.add(after);
    if (route == '/task-templates') {
      if (failList) {
        throw const StoreApiException(
          'network_unavailable',
          'Liste nicht erreichbar.',
        );
      }
      return {
        'items': head == null || after != null ? [] : [copy(head!)],
        'nextCursor': paging && after == null ? 'list-page' : null,
      };
    }
    if (head == null) {
      throw const StoreApiException('not_found', 'Missing', statusCode: 404);
    }
    if (route.endsWith('/revisions')) {
      return {
        'items': after != null
            ? []
            : records.values
                  .toList()
                  .reversed
                  .map((r) => copy(r)..remove('content'))
                  .toList(),
        'nextCursor': paging && after == null ? 'revision-page' : null,
      };
    }
    if (route == '/task-templates/${head!['id']}') return copy(head!);
    final revision = records[route.split('/').last];
    if (revision == null) {
      throw const StoreApiException('not_found', 'Missing', statusCode: 404);
    }
    return copy({'template': head, 'revision': revision});
  }

  Map<String, dynamic> makeRevision(String id, Map<String, dynamic> content) =>
      {
        'id': id,
        'templateId': head!['id'],
        'number': records.length + 1,
        'status': 'draft',
        'title': content['title'],
        'createdAt': time,
        'publishedAt': null,
        'publishedBy': null,
        'content': copy(content),
      };
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    requests++;
    if (selectionUnavailable && route.endsWith('/edit')) {
      throw const StoreApiException(
        'planogram_selection_unavailable',
        'Unavailable selection',
        statusCode: 422,
      );
    }
    if (planogramUnavailable &&
        route.endsWith('/publish') &&
        records[route.split('/')[4]]!['content']['planogramGuidance'] != null) {
      throw const StoreApiException(
        'planogram_guidance_unavailable',
        'Unavailable for new work',
        statusCode: 422,
      );
    }

    if (retired &&
        (route == '/task-templates' || route.endsWith('/edit')) &&
        body['content']['knowledgeGuidance'] != null &&
        jsonEncode(body['content']['knowledgeGuidance']) !=
            jsonEncode(
              route == '/task-templates'
                  ? null
                  : records[route.split(
                      '/',
                    )[4]]!['content']['knowledgeGuidance'],
            )) {
      throw const StoreApiException(
        'guidance_selection_unavailable',
        'Selected instruction unavailable.',
        statusCode: 422,
      );
    }
    if (retired && route.endsWith('/publish')) {
      throw const StoreApiException(
        'guidance_unavailable',
        'Assigned instruction unavailable.',
        statusCode: 422,
      );
    }
    if (pending case final pending?) return pending.future;
    String rid;
    if (route == '/task-templates') {
      rid = body['revisionId'] as String;
      head = {
        'id': body['id'],
        'companyId': company,
        'locationId': location,
        'version': 1,
        'title': body['content']['title'],
        'createdAt': time,
        'updatedAt': time,
        'draftId': rid,
        'publishedId': null,
      };
      records[rid] = makeRevision(rid, body['content'] as Map<String, dynamic>);
    } else if (route.endsWith('/revisions')) {
      rid = body['id'] as String;
      records[rid] = makeRevision(
        rid,
        records[head!['publishedId']]!['content'] as Map<String, dynamic>,
      );
      head!['draftId'] = rid;
      head!['version'] = (head!['version'] as int) + 1;
    } else {
      rid = route.split('/')[4];
      final revision = records[rid]!;
      if (conflict) {
        if (concurrentPublish) {
          revision['status'] = 'published';
          revision['publishedAt'] = time;
          revision['publishedBy'] = account;
          head!['publishedId'] = rid;
          head!['draftId'] = null;
        }
        revision['title'] = 'Remote edit';
        revision['content']['title'] = 'Remote edit';
        head!['version'] = (head!['version'] as int) + 1;
        if (loseResponse) {
          throw const StoreApiException('timeout', 'Antwort verloren.');
        }
        throw const StoreApiException(
          'template_conflict',
          'Conflict',
          statusCode: 409,
        );
      }
      if (route.endsWith('/edit')) {
        revision['content'] = copy(body['content'] as Map<String, dynamic>);
        revision['title'] = body['content']['title'];
        head!['title'] = revision['title'];
      } else {
        revision['status'] = 'published';
        revision['publishedAt'] = time;
        revision['publishedBy'] = account;
        head!['publishedId'] = rid;
        head!['draftId'] = null;
      }
      head!['version'] = (head!['version'] as int) + 1;
    }
    if (loseResponse) {
      throw const StoreApiException('timeout', 'Antwort verloren.');
    }
    return copy({'template': head, 'revision': records[rid]});
  }
}
