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
import 'task_planogram_response.dart';
import 'package:storeos_client/src/ui/retained_layout_panel.dart';

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
    'exact historical layout read and return preserve execution and inputs without writes',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      final before = f.api.posts, execution = f.c.execution;
      f.c.setReason('retained reason');
      f.c.setNumber('3');
      expect(f.c.error, isNull);
      expect(f.c.task, isNotNull);
      await f.c.openLayout();
      expect(f.c.layoutError, isNull);
      expect(f.c.taskPlanogram!.instruction.pin.toJson(), layoutPin);
      expect(f.c.taskPlanogram!.currentContext.fixtureRetired, true);
      expect(f.c.taskPlanogram!.currentContext.reassigned, true);
      expect(f.api.posts, before);
      expect(f.api.routes.last, endsWith('/tasks/${base.taskId}/planogram'));
      f.c.closeLayout();
      expect(f.c.taskPlanogram, isNull);
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
        await f.c.openLayout();
        expect(f.c.taskPlanogram, isNotNull);
        f.api.pendingPlanogram = Completer<Map<String, dynamic>>();
        f.api.started = Completer<void>();
        final action = f.c.openLayout();
        await f.api.started!.future;
        final token = f.api.planogramTokens.last;
        await f.session.signIn(username: actor, password: 'test');
        expect(f.c.taskPlanogram, isNull);
        expect(f.c.layoutOpen, false);
        expect(f.c.task, isNull);
        f.api.pendingPlanogram!.complete(f.api.layout);
        await action;
        expect(f.c.taskPlanogram, isNull);
        expect(f.c.layoutError, isNull);
        expect(f.api.planogramTokens.last, token);
      },
    );
  }
  test('task without guidance issues no contextual request', () async {
    final f = await _Fixture.create(guidance: false);
    addTearDown(f.dispose);
    final count = f.api.routes.length;
    await f.c.openLayout();
    expect(f.api.routes.length, count);
    expect(f.c.layoutOpen, false);
  });
  test(
    'layout error is explicit and does not substitute current planogram',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      f.api.failPlanogram = true;
      await f.c.openLayout();
      expect(f.c.taskPlanogram, isNull);
      expect(f.c.layoutError, isNotNull);
      expect(f.api.routes.where((r) => r.startsWith('/planogram')), isEmpty);
    },
  );
  for (final stock in ['zero', 'unavailable']) {
    testWidgets(
      'retained panel displays $stock without hiding frozen instruction',
      (tester) async {
        final raw = retainedLayout;
        raw['currentContext']['stockContextStatus'] = stock == 'zero'
            ? 'available'
            : 'unavailable';
        if (stock == 'zero') {
          raw['currentContext']['articles'][0]['stock'] = {
            'quantity': '0',
            'stockUnit': 'Stk',
          };
        }
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: RetainedLayoutPanel(
                  layout: RetainedLayoutDto.fromJson(raw),
                ),
              ),
            ),
          ),
        );
        expect(find.text(literalLayout), findsOneWidget);
        expect(find.text('Kein Bestand erfasst'), findsNothing);
        expect(
          stock == 'zero'
              ? find.text('Aktueller Bestand 0 Stk')
              : find.byKey(const Key('layout-stock-unavailable')),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'literal frozen panel separates current labels absent zero and unavailable stock',
    (tester) async {
      final f = await tester.runAsync(_Fixture.create);
      addTearDown(f!.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSection(controller: f.c)),
        ),
      );
      await tester.runAsync(f.c.openLayout);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('layout-frozen-instruction')),
        200,
      );
      expect(find.text(literalLayout), findsOneWidget);
      expect(find.byKey(const Key('layout-reassigned')), findsOneWidget);
      expect(find.byKey(const Key('layout-fixture-retired')), findsOneWidget);
      expect(find.byKey(const Key('layout-current-context')), findsOneWidget);
      expect(find.text('Kein Bestand erfasst'), findsOneWidget);
      f.c.closeLayout();
      await tester.pump();
      expect(f.c.execution!.status, 'open');
    },
  );
}

class _Api extends base.Api {
  bool guidance = true, failPlanogram = false;
  bool failGuidancePublication = false;
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (failGuidancePublication && route.endsWith('/publish')) {
      throw const StoreApiException(
        'planogram_guidance_unavailable',
        'Assigned layout unavailable for new work.',
        statusCode: 422,
      );
    }
    return super.post(token, route, body);
  }

  Completer<Map<String, dynamic>>? pendingPlanogram;
  Completer<void>? started;
  final routes = <String>[], tokens = <String>[], planogramTokens = <String>[];
  Map<String, dynamic> get layout => retainedLayout;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    routes.add(route);
    tokens.add(token);
    if (route.endsWith('/planogram')) {
      planogramTokens.add(token);
      if (pendingPlanogram != null) {
        started!.complete();
        return pendingPlanogram!.future;
      }
      if (failPlanogram) {
        throw const StoreApiException(
          'internal_error',
          'Assigned layout could not be read.',
          statusCode: 500,
        );
      }
      return layout;
    }
    final result = await super.get(token, route, after: after, query: query);
    if (route == '/context') {
      (result['permissions'] as List).add('merchandising.layouts.read');
    }
    if (result['content'] is Map && guidance) {
      final content = Map<String, dynamic>.from(result['content'] as Map);
      result['content'] = content;
      content['schemaVersion'] = 4;
      content['knowledgeGuidance'] = null;
      content['planogramGuidance'] = layoutPin;
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
