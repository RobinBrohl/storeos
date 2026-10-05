import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/ui/shift_section.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'shift_test.dart' as base;

void main() {
  test(
    'Shift guidance publication failure preserves the saved draft',
    () async {
      final f = await _Fixture.create(publish: false);
      addTearDown(f.dispose);
      final saved = jsonEncode(f.api.records);
      final shift = f.c.selected!.toJson();
      final input = [f.c.employeeId, f.c.startsAt, f.c.endsAt];
      final selections = f.c.selections.map((s) => s.toJson()).toList();
      f.api.failGuidancePublication = true;
      await f.c.publish();
      expect(f.c.error, contains('für neue Arbeit nicht mehr verfügbar'));
      expect(f.c.error, contains('Vorlagenauswahl prüfen'));
      expect(f.c.error, isNot(contains('für diesen Entwurf')));
      expect(f.c.selected!.status, 'draft');
      expect(f.c.selected!.toJson(), shift);
      expect([f.c.employeeId, f.c.startsAt, f.c.endsAt], input);
      expect(f.c.selections.map((s) => s.toJson()).toList(), selections);
      expect(jsonEncode(f.api.records), saved);
      expect(f.c.tasks, isEmpty);
      expect(f.c.unconfirmed, false);
      expect(f.c.editable, true);
      expect(f.c.notice, isNull);
    },
  );
  test(
    'exact historical instruction read and return preserve execution and inputs without writes',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final before = f.api.posts, execution = f.c.execution;
      f.c.setReason('retained reason');
      f.c.setNumber('3');
      await f.c.openInstruction();
      expect(f.c.taskKnowledge!.revisionId, _revision);
      expect(f.c.taskKnowledge!.articleRetired, true);
      expect(f.c.taskKnowledge!.superseded, true);
      expect(f.api.posts, before);
      expect(f.api.routes.last, endsWith('/tasks/${base.taskId}/knowledge'));
      f.c.closeInstruction();
      expect(f.c.taskKnowledge, isNull);
      expect(f.c.execution, same(execution));
      expect(f.c.reason, 'retained reason');
      expect(f.c.numberInput, '3');
    },
  );
  for (final actor in ['test', 'replacement']) {
    test(
      '$actor replacement fences pending and cached historical task content',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        await f.c.openInstruction();
        expect(f.c.taskKnowledge, isNotNull);
        f.api.pendingKnowledge = Completer<Map<String, dynamic>>();
        f.api.started = Completer<void>();
        final action = f.c.openInstruction();
        await f.api.started!.future;
        final token = f.api.knowledgeTokens.last;
        await f.session.signIn(username: actor, password: 'test');
        expect(f.c.taskKnowledge, isNull);
        expect(f.c.instructionOpen, false);
        expect(f.c.task, isNull);
        f.api.pendingKnowledge!.complete(f.api.instruction);
        await action;
        expect(f.c.taskKnowledge, isNull);
        expect(f.c.instructionError, isNull);
        expect(f.api.knowledgeTokens.last, token);
      },
    );
  }
  test('task without guidance issues no contextual request', () async {
    final f = await _Fixture.create(guidance: false);
    addTearDown(f.dispose);
    final count = f.api.routes.length;
    await f.c.openInstruction();
    expect(f.api.routes.length, count);
    expect(f.c.instructionOpen, false);
  });
  test(
    'instruction error is explicit and does not substitute current knowledge',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.failKnowledge = true;
      await f.c.openInstruction();
      expect(f.c.taskKnowledge, isNull);
      expect(f.c.instructionError, isNotNull);
      expect(f.api.routes.where((r) => r.startsWith('/knowledge')), isEmpty);
    },
  );
  testWidgets(
    'task panel renders exact plain text, lifecycle indicators and return',
    (tester) async {
      final f = await tester.runAsync(_Fixture.create);
      addTearDown(f!.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSection(controller: f.c)),
        ),
      );
      await tester.runAsync(f.c.openInstruction);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('task-instruction-body')),
        200,
      );
      expect(find.byKey(const Key('task-instruction-body')), findsOneWidget);
      expect(find.textContaining('Historisch'), findsOneWidget);
      expect(find.textContaining('stillgelegt'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('task-instruction-body')),
            )
            .data,
        f.api.instruction['body'],
      );
      await tester.ensureVisible(find.byKey(const Key('return-to-task')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('return-to-task')));
      await tester.pumpAndSettle();
      expect(f.c.execution!.status, 'open');
      expect(find.byKey(const Key('task-instruction-body')), findsNothing);
    },
  );
}

const _article = '88888888-8888-4888-8888-888888888888',
    _revision = '99999999-9999-4999-8999-999999999999';

class _Api extends base.Api {
  bool guidance = true, failKnowledge = false;
  bool failGuidancePublication = false;
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (failGuidancePublication && route.endsWith('/publish')) {
      throw const StoreApiException(
        'guidance_unavailable',
        'Assigned instruction unavailable for new work.',
        statusCode: 422,
      );
    }
    return super.post(token, route, body);
  }

  Completer<Map<String, dynamic>>? pendingKnowledge;
  Completer<void>? started;
  final routes = <String>[], tokens = <String>[], knowledgeTokens = <String>[];
  Map<String, dynamic> get instruction => {
    'taskId': base.taskId,
    'articleId': _article,
    'revisionId': _revision,
    'revisionNumber': 1,
    'title': 'Pinned v1',
    'body':
        '<script>literal</script>\n<a href="x">literal</a>\n<img onerror="x">\n**Markdown plain**',
    'publishedAt': base.Api.time,
    'superseded': true,
    'articleRetired': true,
  };
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    routes.add(route);
    tokens.add(token);
    if (route.endsWith('/knowledge')) {
      knowledgeTokens.add(token);
      if (pendingKnowledge != null) {
        started!.complete();
        return pendingKnowledge!.future;
      }
      if (failKnowledge) {
        throw const StoreApiException(
          'internal_error',
          'Assigned instruction could not be read.',
          statusCode: 500,
        );
      }
      return instruction;
    }
    final result = await super.get(token, route, after: after, query: query);
    if (route == '/context') {
      (result['permissions'] as List).add('knowledge.articles.read');
    }
    if (result['content'] is Map && guidance) {
      final content = result['content'] as Map;
      content['schemaVersion'] = 3;
      content['knowledgeGuidance'] = {
        'articleId': _article,
        'revisionId': _revision,
      };
    }
    return result;
  }
}

class _Session extends base.Session {
  int generation = 0;
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'token-${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: request.username == 'test'
          ? base.account
          : 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      username: request.username,
      companyId: base.company,
      locationId: base.location,
    ),
  );
}

class _Fixture {
  _Fixture(this.api, this.session, this.platform, this.c);
  final _Api api;
  final SessionController session;
  final PlatformController platform;
  final ShiftController c;
  static Future<_Fixture> create({
    bool guidance = true,
    bool publish = true,
  }) async {
    final api = _Api()..guidance = guidance,
        session = SessionController(_Session()),
        p = PlatformController(session, api),
        c = ShiftController(session, p, api);
    await session.signIn(username: 'test', password: 'test');
    while (p.isBusy) {
      await Future<void>.value();
    }
    final f = _Fixture(api, session, p, c);
    await c.loadChoices();
    c.newDraft();
    c.chooseEmployee(base.employee);
    c.setTimes(start: '2030-01-01T08:00:00Z', end: '2030-01-01T18:00:00Z');
    await c.loadRevisions(base.template);
    c.addRevision(c.revisions.single);
    await c.save();
    if (publish) {
      await c.publish();
      await c.openTask(base.taskId);
    }
    return f;
  }

  void dispose() {
    c.dispose();
    platform.dispose();
    session.dispose();
  }
}
