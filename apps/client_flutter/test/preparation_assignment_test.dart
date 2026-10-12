import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/preparation_assignment_controller.dart';
import 'package:storeos_client/src/application/preparation_batch_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/preparation_assignment_section.dart';
import 'preparation_batch_test.dart' show BatchAuth, BatchApi, batchJson;
import 'recipe_test.dart'
    show company, location, article, revision, line, employeeJson;

Map<String, dynamic> assignment({String status = 'assigned'}) => {
  'id': line,
  'companyId': company,
  'locationId': location,
  'employeeId': company,
  'recipeId': article,
  'revisionId': revision,
  'createdBy': company,
  'createdAt': '2030-01-01T08:00:00Z',
  'createOperationId': article,
  'plannedDeclaredBatchCount': 3,
  'status': status,
  'version': status == 'assigned' ? 1 : 2,
  'batchId': status == 'started' ? line : null,
  'batchOperationId': status == 'started' ? article : null,
  'startedBy': status == 'started' ? company : null,
  'startedAt': status == 'started' ? '2030-01-01T08:10:00Z' : null,
  'withdrawnBy': status == 'withdrawn' ? company : null,
  'withdrawnAt': status == 'withdrawn' ? '2030-01-01T08:10:00Z' : null,
  'withdrawalReason': status == 'withdrawn' ? 'Reason' : null,
  'terminalOperationId': status == 'assigned' ? null : revision,
};

class AssignmentApi extends BatchApi {
  Map<String, dynamic> current = assignment();
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      final j = await super.get(token, route);
      if (token.startsWith('other:')) j['userId'] = article;
      (j['permissions'] as List<String>).addAll([
        'production.assignments.manage',
        'production.assignments.self.read',
        'production.assignments.self.start',
      ]);
      return j;
    }
    if (route == '/organization') return super.get(token, route);
    if (readHold != null) return readHold!.future;
    if (readFailure != null) throw readFailure!;
    if (route.endsWith('/$line')) return {...current, 'batch': null};
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }

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
    final status = route.endsWith('/start')
        ? 'started'
        : route.endsWith('/withdraw')
        ? 'withdrawn'
        : 'assigned';
    final a = assignment(status: status);
    if (!route.endsWith('/start') && !route.endsWith('/withdraw')) {
      a['id'] = body['id'];
    }
    current = a;
    return reply ??
        {
          'assignment': a,
          if (status == 'started') 'batch': batchJson(),
          'replayed': false,
        };
  }
}

class AssignmentAuth extends BatchAuth {
  Completer<SystemStatusResponse>? heldStatus;
  @override
  Future<SessionResponse> login(LoginRequest r) async {
    final original = await super.login(r);
    return SessionResponse(
      token: r.username == 'other'
          ? original.token.replaceFirst('employee:', 'other:')
          : original.token,
      expiresAt: original.expiresAt,
      user: SessionUser(
        id: r.username == 'other' ? article : company,
        username: r.username,
        companyId: company,
        locationId: location,
      ),
    );
  }

  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    final held = heldStatus;
    if (held != null) {
      heldStatus = null;
      return held.future;
    }
    return super.systemStatus(token: token, locationId: locationId);
  }
}

Future<
  (
    SessionController,
    PreparationAssignmentController,
    PreparationBatchController,
  )
>
setup(AssignmentApi api, {bool self = false, AssignmentAuth? auth}) async {
  final s = SessionController(auth ?? AssignmentAuth()),
      p = PlatformController(s, api),
      c = PreparationAssignmentController(s, p, api, self: self),
      b = PreparationBatchController(s, p, api, self: self);
  final ready = Completer<void>();
  void changed() {
    if (p.organization != null && !p.isBusy && !ready.isCompleted) {
      ready.complete();
    }
  }

  p.addListener(changed);
  await s.signIn(username: 'employee', password: 'test');
  changed();
  await ready.future.timeout(
    const Duration(seconds: 5),
    onTimeout: () {
      throw StateError('Platform setup failed: ${p.error}; session ${s.error}');
    },
  );
  p.removeListener(changed);
  addTearDown(() {
    c.dispose();
    b.dispose();
    p.dispose();
    s.dispose();
  });
  c.detail = PreparationAssignmentDto.fromJson(assignment());
  c.selection = PublishedRecipeDto.fromJson(employeeJson);
  c.employeeSelection = {'id': company, 'displayName': 'Worker', 'version': 1};
  return (s, c, b);
}

void main() {
  for (final kind in ['create', 'start', 'withdraw']) {
    test(
      '$kind frozen exact retry and deep immutable confirmed outcome',
      () async {
        final api = AssignmentApi();
        final (_, c, _) = await setup(api, self: kind == 'start');
        api.failure = const StoreApiException(
          'database_unavailable',
          'Unknown',
          statusCode: 503,
        );
        final outcome = await switch (kind) {
          'create' => c.create(3),
          'start' => c.start(),
          _ => c.withdraw('Reason'),
        };
        expect(outcome, AssignmentOutcome.uncertain);
        final pending = c.pending!;
        expect(
          () => pending.body['operationId'] = line,
          throwsUnsupportedError,
        );
        expect(
          await c.create(4),
          kind == 'start' ? AssignmentOutcome.rejected : AssignmentOutcome.busy,
        );
        api.failure = const StoreApiException(
          'forbidden',
          'Rights changed',
          statusCode: 403,
        );
        expect(await c.retry(), AssignmentOutcome.uncertain);
        expect(c.pending, same(pending));
        api.failure = null;
        api.reply = {
          'assignment': assignment(
            status: kind == 'start'
                ? 'started'
                : kind == 'withdraw'
                ? 'withdrawn'
                : 'assigned',
          ),
          'replayed': true,
          if (kind == 'start') 'batch': batchJson(),
        };
        expect(await c.retry(), AssignmentOutcome.confirmed);
        expect(api.bodies.first, api.bodies.last);
        expect(api.routes.first, api.routes.last);
        expect(c.lastConfirmed!['replayed'], true);
        expect(
          () => (c.lastConfirmed!['assignment'] as Map)['status'] = 'fake',
          throwsUnsupportedError,
        );
      },
    );
  }
  for (final status in [400, 403, 409, 413, 415, 422]) {
    test('definitive $status preserves editable selection', () async {
      final api = AssignmentApi();
      final (_, c, _) = await setup(api);
      api.failure = StoreApiException(
        'rejected',
        'Rejected',
        statusCode: status,
      );
      expect(await c.create(3), AssignmentOutcome.rejected);
      expect(c.pending, isNull);
      expect(c.selection, isNotNull);
      expect(c.employeeSelection, isNotNull);
    });
  }
  test(
    'confirmed result survives failed detail refresh and blocks stale mutations',
    () async {
      final api = AssignmentApi();
      final (_, c, _) = await setup(api);
      api.readFailure = const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
      expect(await c.create(3), AssignmentOutcome.confirmed);
      expect(c.detail, isNull);
      expect(c.lastConfirmed, isNotNull);
      expect(c.pending, isNull);
      expect(c.refreshWarning, contains('Command confirmed'));
      expect(await c.withdraw('Follow up'), AssignmentOutcome.rejected);
    },
  );
  for (final username in ['employee', 'other']) {
    for (final write in [true, false]) {
      test(
        '$username Account replacement fences held ${write ? 'POST' : 'GET'} and all state',
        () async {
          final api = AssignmentApi();
          final (s, c, _) = await setup(api);
          final hold = Completer<Map<String, dynamic>>();
          if (write) {
            api.postHold = hold;
          } else {
            api.readHold = hold;
          }
          final future = write ? c.create(3) : c.select(line);
          await Future<void>.delayed(Duration.zero);
          final old = c.sessionIdentity;
          await s.signIn(username: username, password: 'test');
          expect(identical(old, c.sessionIdentity), false);
          expect(c.detail, isNull);
          expect(c.selection, isNull);
          expect(c.employeeSelection, isNull);
          expect(c.pending, isNull);
          hold.complete(
            write
                ? {'assignment': assignment(), 'replayed': false}
                : assignment(),
          );
          await future;
          expect(c.detail, isNull);
          expect(c.lastConfirmed, isNull);
          expect(c.error, isNull);
        },
      );
    }
  }
  test(
    'delayed old status cannot restore cleared assignment state after session replacement',
    () async {
      final auth = AssignmentAuth(), api = AssignmentApi();
      final (s, c, _) = await setup(api, auth: auth);
      final held = Completer<SystemStatusResponse>();
      auth.heldStatus = held;
      final old = s.refreshStatus();
      await Future<void>.delayed(Duration.zero);
      s.invalidateSession();
      held.complete(
        const SystemStatusResponse(companyId: company, locationId: location),
      );
      await old;
      await s.signIn(username: 'other', password: 'test');
      expect(s.user!.id, article);
      expect(c.detail, isNull);
      expect(c.selection, isNull);
      expect(c.instruction, isNull);
      expect(c.history, isNull);
      expect(c.lastConfirmed, isNull);
      expect(c.pending, isNull);
    },
  );
  for (final username in ['employee', 'other']) {
    testWidgets(
      'mounted fields and confirmation dialog clear on $username Account replacement',
      (t) async {
        final api = AssignmentApi();
        final (s, c, b) = await setup(api);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PreparationAssignmentSection(controller: c, batches: b),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('assignment-planned')));
        await t.enterText(find.byKey(const Key('assignment-planned')), '3');
        await t.tap(find.byKey(const Key('assignment-create')));
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await s.signIn(username: username, password: 'test');
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(api.bodies, isEmpty);
        expect(c.selection, isNull);
        await s.signOut();
      },
    );
  }
}
