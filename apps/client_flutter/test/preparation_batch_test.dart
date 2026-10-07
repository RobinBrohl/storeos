import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/preparation_batch_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/preparation_batch_section.dart';
import 'recipe_test.dart'
    show company, location, article, revision, line, employeeJson, literal;

const evidence = '<script>literal evidence</script> ä 😀';
Finder get batchScrollable => find
    .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
    .first;

Map<String, dynamic> batchJson({
  bool completed = false,
  int actual = 1,
  int? effective,
}) => {
  'batchId': line,
  'companyId': company,
  'locationId': location,
  'recipeId': article,
  'revisionId': revision,
  'employeeId': company,
  'openedBy': company,
  'openedAt': '2030-01-01T08:00:00Z',
  'plannedDeclaredBatchCount': 3,
  'status': completed ? 'completed' : 'open',
  'version': completed ? 2 : 1,
  'openOperationId': article,
  'actualDeclaredBatchCount': completed ? actual : null,
  'completedBy': completed ? company : null,
  'completedAt': completed ? '2030-01-01T09:00:00Z' : null,
  'completionNote': completed ? literal : null,
  'cancelledBy': null,
  'cancelledAt': null,
  'cancellationReason': null,
  'terminalOperationId': completed ? revision : null,
  'terminalKind': completed ? 'complete' : null,
  'latestCorrectionNumber': effective != null && effective != actual ? 1 : 0,
  'effectiveDeclaredBatchCount': completed ? (effective ?? actual) : null,
  'corrections': [
    if (effective != null && effective != actual)
      {
        'correctionNumber': 1,
        'previousEffectiveCount': actual,
        'replacementDeclaredBatchCount': effective,
        'correctedAt': '2030-01-01T10:00:00Z',
        'correctedBy': company,
        'reason': literal,
      },
  ],
};

// POST returns a bare batch DTO or a correction row, never the GET projection.
Map<String, dynamic> commandResult(
  String kind,
  Map<String, dynamic> body, {
  int previous = 1,
  bool replayed = false,
}) {
  if (kind == 'count_correct') {
    return {
      'correction': {
        'companyId': company,
        'locationId': location,
        'batchId': line,
        'correctionNumber': (body['expectedLatestCorrectionNumber'] as int) + 1,
        'previousEffectiveCount': previous,
        'replacementDeclaredBatchCount': body['replacementDeclaredBatchCount'],
        'correctedAt': '2030-01-01T10:00:00Z',
        'correctedBy': company,
        'reason': body['reason'],
        'operationId': body['operationId'],
      },
      'replayed': replayed,
    };
  }
  final json =
      batchJson(
          completed: kind == 'complete',
          actual: body['actualDeclaredBatchCount'] as int? ?? 1,
        )
        ..remove('corrections')
        ..remove('latestCorrectionNumber')
        ..remove('effectiveDeclaredBatchCount');
  if (kind == 'open') json['batchId'] = body['batchId'];
  if (kind.endsWith('cancel')) {
    json.addAll({
      'status': 'cancelled',
      'version': 2,
      'cancelledBy': company,
      'cancelledAt': '2030-01-01T10:00:00Z',
      'cancellationReason': body['reason'],
      'terminalOperationId': body['operationId'],
      'terminalKind': kind,
    });
  }
  return {
    'batch': PreparationBatchDto.fromJson(json).toJson(),
    'replayed': replayed,
  };
}

Future<(SessionController, PreparationBatchController)> setup(
  BatchApi api, {
  bool self = true,
}) async {
  final s = SessionController(BatchAuth()),
      p = PlatformController(s, api),
      c = PreparationBatchController(s, p, api, self: self);
  final ready = Completer<void>();
  void loaded() {
    if (p.organization != null && !p.isBusy && !ready.isCompleted) {
      ready.complete();
    }
  }

  p.addListener(loaded);
  await s.signIn(username: 'employee', password: 'test');
  loaded();
  await ready.future;
  p.removeListener(loaded);
  addTearDown(() {
    c.dispose();
    p.dispose();
    s.dispose();
  });
  c.detail = PreparationBatchDto.fromJson(batchJson(completed: !self));
  return (s, c);
}

void main() {
  for (final kind in [
    'open',
    'complete',
    'employee_cancel',
    'manager_cancel',
    'count_correct',
  ]) {
    test(
      '$kind uncertain command exact immutable retry without fresh operation',
      () async {
        final api = BatchApi();
        final (_, c) = await setup(
          api,
          self: kind != 'manager_cancel' && kind != 'count_correct',
        );
        c.selection = PublishedRecipeDto.fromJson(employeeJson);
        api.failure = const StoreApiException(
          'database_unavailable',
          'Unconfirmed',
          statusCode: 503,
        );
        final result = await switch (kind) {
          'open' => c.open(3),
          'complete' => c.complete(1, evidence),
          'employee_cancel' || 'manager_cancel' => c.cancel(evidence),
          _ => c.correct(0, evidence),
        };
        expect(result, PreparationOutcome.uncertain);
        final pending = c.pending!;
        expect(
          () => pending.body['operationId'] = article,
          throwsUnsupportedError,
        );
        expect(await c.cancel('different intent'), PreparationOutcome.busy);
        api.failure = null;
        api.reply = commandResult(kind, pending.body, replayed: true);
        expect(await c.retry(), PreparationOutcome.confirmed);
        expect(api.routes[0], api.routes[1]);
        expect(api.bodies[0], api.bodies[1]);
        expect(c.pending, isNull);
        expect(c.lastConfirmed!['replayed'], true);
      },
    );
  }
  test(
    'confirmed command and failed refresh preserve confirmation without pending retry',
    () async {
      final api = BatchApi();
      final (_, c) = await setup(api);
      api.readFailure = const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
      expect(await c.complete(1, evidence), PreparationOutcome.confirmed);
      expect(c.lastConfirmed, isNotNull);
      expect(c.pending, isNull);
      expect(c.refreshWarning, contains('Command confirmed.'));
    },
  );
  for (final scenario in [(2, 1), (1, 0)]) {
    testWidgets(
      'confirmed correction ${scenario.$1} → ${scenario.$2}, failed GET, reload and session fencing',
      (tester) async {
        final api = BatchApi()..previous = scenario.$1;
        final (s, c) = await setup(api, self: false);
        c.detail = PreparationBatchDto.fromJson(
          batchJson(completed: true, actual: scenario.$1),
        );
        c.items = [c.detail!];
        api.readFailure = const StoreApiException(
          'database_unavailable',
          'Unavailable',
          statusCode: 503,
        );
        expect(
          await c.correct(scenario.$2, evidence),
          PreparationOutcome.confirmed,
        );
        expect(c.detail, isNull);
        expect(c.items, isEmpty);
        expect(c.pending, isNull);
        expect(await c.correct(0, 'second'), PreparationOutcome.rejected);
        expect(api.bodies.length, 1);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: PreparationBatchSection(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            'Correction 1 confirmed: ${scenario.$1} → ${scenario.$2} declared Recipe batches',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'Confirmed original completion: ${scenario.$1} declared Recipe batches',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining('Current batch detail is unavailable'),
          findsOneWidget,
        );
        expect(find.textContaining('Effective count:'), findsNothing);
        expect(find.byKey(const Key('batch-correct')), findsNothing);
        if (scenario.$2 == 0) {
          expect(
            find.text(
              'Reported completion corrected to 0 declared Recipe batches. Lifecycle remains completed.',
            ),
            findsOneWidget,
          );
        }
        api.readFailure = null;
        api.detailReply = batchJson(
          completed: true,
          actual: scenario.$1,
          effective: scenario.$2,
        );
        await tester.tap(find.byKey(const Key('batch-reload-detail')));
        await tester.pumpAndSettle();
        expect(c.refreshWarning, isNull);
        expect(c.detail!.effective, scenario.$2);
        expect(c.detail!.latestCorrectionNumber, 1);
        expect(
          (c.detail!.json['corrections'] as List)
              .single['previousEffectiveCount'],
          scenario.$1,
        );
        expect(
          find.textContaining('Current batch detail is unavailable'),
          findsNothing,
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('batch-correct')),
          200,
          scrollable: batchScrollable,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('batch-correct')))
              .onPressed,
          isNotNull,
        );
        // Re-enter refresh-failed state, then fence a delayed authoritative reload.
        api.readFailure = const StoreApiException(
          'database_unavailable',
          'Unavailable',
          statusCode: 503,
        );
        expect(await c.correct(0, evidence), PreparationOutcome.confirmed);
        final hold = Completer<Map<String, dynamic>>();
        api.readHold = hold;
        final reload = c.select(line);
        await s.signIn(username: 'employee', password: 'test');
        hold.complete(api.detailReply!);
        await reload;
        expect(c.detail, isNull);
        expect(c.lastConfirmed, isNull);
        expect(c.confirmedBatchId, isNull);
        expect(c.confirmedOriginalCount, isNull);
        expect(c.lastConfirmedKind, isNull);
        expect(c.refreshWarning, isNull);
        expect(c.notice, isNull);
        await tester.pumpAndSettle();
        expect(find.textContaining('Correction 1 confirmed'), findsNothing);
        await s.signOut();
      },
    );
  }
  testWidgets(
    'completion two confirmed with bare POST response and failed GET; no null effective count',
    (tester) async {
      final api = BatchApi();
      final (_, c) = await setup(api);
      api.readFailure = const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
      expect(await c.complete(2, evidence), PreparationOutcome.confirmed);
      expect(
        (c.lastConfirmed!['batch'] as Map).containsKey(
          'effectiveDeclaredBatchCount',
        ),
        false,
      );
      expect(c.detail, isNull);
      expect(await c.complete(1, evidence), PreparationOutcome.rejected);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PreparationBatchSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Completion confirmed: 2 declared Recipe batches'),
        findsOneWidget,
      );
      expect(find.text('completed · version 2'), findsOneWidget);
      expect(
        find.textContaining('Current batch detail is unavailable'),
        findsOneWidget,
      );
      expect(find.textContaining('Effective count:'), findsNothing);
      expect(find.byKey(const Key('batch-complete')), findsNothing);
      await c.session.signOut();
    },
  );
  for (final kind in ['open', 'employee_cancel', 'manager_cancel']) {
    test(
      '$kind confirmed result with failed detail GET blocks stale terminal commands',
      () async {
        final api = BatchApi();
        final (_, c) = await setup(api, self: kind != 'manager_cancel');
        c.selection = PublishedRecipeDto.fromJson(employeeJson);
        api.readFailure = const StoreApiException(
          'database_unavailable',
          'Unavailable',
          statusCode: 503,
        );
        expect(
          await (kind == 'open' ? c.open(3) : c.cancel(evidence)),
          PreparationOutcome.confirmed,
        );
        expect(c.detail, isNull);
        expect(c.lastConfirmedKind, kind);
        expect(
          c.refreshWarning,
          contains('Current batch detail is unavailable'),
        );
        expect(await c.cancel('second'), PreparationOutcome.rejected);
      },
    );
  }
  test(
    'successful detail GET remains authoritative when history refresh fails',
    () async {
      final api = BatchApi()..historyFailure = true;
      final (_, c) = await setup(api);
      expect(await c.complete(1, evidence), PreparationOutcome.confirmed);
      expect(c.detail!.effective, 1);
      expect(c.refreshWarning, contains('Current history'));
    },
  );
  test(
    'definite rejection leaves current form resource available and clears pending intent',
    () async {
      final api = BatchApi();
      final (_, c) = await setup(api);
      api.failure = const StoreApiException(
        'stale_version',
        'Conflict',
        statusCode: 409,
      );
      expect(await c.complete(1, evidence), PreparationOutcome.rejected);
      expect(c.detail!.status, 'open');
      expect(c.pending, isNull);
      expect(c.error, contains('stale_version'));
    },
  );
  for (final command in [false, true]) {
    test(
      'same-account replacement clears every resident state and fences delayed ${command ? 'command' : 'read'}',
      () async {
        final api = BatchApi();
        final (s, c) = await setup(api);
        final hold = Completer<Map<String, dynamic>>();
        if (command) {
          api.postHold = hold;
        } else {
          api.readHold = hold;
        }
        c.items = [c.detail!];
        c.instruction = employeeJson;
        c.recipes = [PublishedRecipeDto.fromJson(employeeJson)];
        c.selection = c.recipes.single;
        c.nextCursor = 'old';
        c.recipeCursor = 'old';
        c.error = 'old';
        c.notice = 'old';
        final old = s.sessionIdentity;
        final request = command ? c.complete(1, evidence) : c.load();
        await s.signIn(username: 'employee', password: 'test');
        expect(identical(old, s.sessionIdentity), false);
        expect(c.items, isEmpty);
        expect(c.recipes, isEmpty);
        expect(c.selection, isNull);
        expect(c.detail, isNull);
        expect(c.instruction, isNull);
        expect(c.nextCursor, isNull);
        expect(c.recipeCursor, isNull);
        expect(c.error, isNull);
        expect(c.pending, isNull);
        expect(c.lastConfirmed, isNull);
        hold.complete(
          command
              ? commandResult('complete', api.bodies.single)
              : {
                  'items': [batchJson()],
                  'nextCursor': 'stale',
                },
        );
        await request;
        expect(c.detail, isNull);
        expect(c.items, isEmpty);
        expect(c.notice, isNull);
      },
    );
  }
  testWidgets(
    'literal retained instructions and explicit original-one corrected-zero evidence',
    (tester) async {
      final api = BatchApi();
      final (_, c) = await setup(api, self: false);
      c.detail = PreparationBatchDto.fromJson(
        batchJson(completed: true, effective: 0),
      );
      c.instruction = {
        ...employeeJson,
        'warnings': ['recipe_retired'],
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PreparationBatchSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(SelectableText, literal), findsWidgets);
      await tester.scrollUntilVisible(
        find.text(
          'Reported completion corrected to 0 declared Recipe batches.',
        ),
        200,
        scrollable: batchScrollable,
      );
      expect(
        find.text('Original completion: 1 declared Recipe batches'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Reported completion corrected to 0 declared Recipe batches.',
        ),
        findsOneWidget,
      );
      await c.session.signOut();
    },
  );
  testWidgets(
    'rejected completion retains typed note and count; uncertain disables alternative submission',
    (tester) async {
      final api = BatchApi();
      final (_, c) = await setup(api);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PreparationBatchSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      final count = find.byKey(const Key('batch-actual')),
          note = find.byKey(const Key('batch-note'));
      await tester.scrollUntilVisible(count, 200, scrollable: batchScrollable);
      await tester.enterText(count, '1');
      await tester.enterText(note, evidence);
      api.failure = const StoreApiException(
        'stale_version',
        'Conflict',
        statusCode: 409,
      );
      await tester.ensureVisible(find.byKey(const Key('batch-complete')));
      await tester.tap(find.byKey(const Key('batch-complete')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(count).controller!.text, '1');
      expect(tester.widget<TextField>(note).controller!.text, evidence);
      api.failure = const StoreApiException(
        'database_unavailable',
        'Unknown',
        statusCode: 503,
      );
      await tester.tap(find.byKey(const Key('batch-complete')));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(count).enabled, false);
      await tester.scrollUntilVisible(
        find.byKey(const Key('batch-retry')),
        -200,
        scrollable: batchScrollable,
      );
      expect(find.byKey(const Key('batch-retry')), findsOneWidget);
      await c.session.signOut();
    },
  );
}

class BatchAuth implements StoreApi {
  int generation = 0;
  @override
  Future<SessionResponse> login(LoginRequest r) async => SessionResponse(
    token: 'employee:${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const SessionUser(
      id: company,
      username: 'employee',
      companyId: company,
      locationId: location,
    ),
  );
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      const SystemStatusResponse(companyId: company, locationId: location);
  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

class BatchApi implements PlatformApi {
  final routes = <String>[], bodies = <Map<String, dynamic>>[];
  StoreApiException? failure, readFailure;
  Completer<Map<String, dynamic>>? readHold, postHold;
  Map<String, dynamic>? reply;
  Map<String, dynamic>? detailReply;
  int previous = 1;
  bool historyFailure = false;
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    routes.add(route);
    bodies.add(Map.of(body));
    if (postHold != null) return postHold!.future;
    if (failure != null) throw failure!;
    final kind = route.endsWith('/count-corrections')
        ? 'count_correct'
        : route.endsWith('/complete')
        ? 'complete'
        : route.endsWith('/cancel')
        ? (route.contains('/manage/') ? 'manager_cancel' : 'employee_cancel')
        : 'open';
    return reply ?? commandResult(kind, body, previous: previous);
  }

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': company,
        'companyId': company,
        'locationId': location,
        'role': 'admin',
        'permissions': [
          'production.batches.self.read',
          'production.batches.self.execute',
          'production.batches.manage',
          'production.recipes.read',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Company', 'version': 1},
        'locations': [
          {
            'id': location,
            'companyId': company,
            'name': 'Location',
            'version': 1,
          },
        ],
      };
    }
    if (readHold != null) return readHold!.future;
    if (readFailure != null) throw readFailure!;
    if (route.endsWith('/$line')) {
      return detailReply ?? batchJson(completed: true);
    }
    if (historyFailure) {
      throw const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
    }
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }
}
