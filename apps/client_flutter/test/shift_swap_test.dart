import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

import 'shift_swap_fixture.dart';

const permissions = [
  'workforce.swaps.self.read',
  'workforce.swaps.self.request',
  'workforce.swaps.self.respond',
  'workforce.swaps.manage',
  'workforce.shifts.manage',
  'tasks.instances.read',
];

class SwapAuth implements StoreApi {
  String account = swapId(10), location = swapId(3);
  int generation = 0;
  DateTime now = DateTime.utc(2029);
  @override
  Future<SessionResponse> login(LoginRequest input) async => SessionResponse(
    token: 'fixture-session-${++generation}',
    expiresAt: now.add(const Duration(hours: 1)),
    user: SessionUser(
      id: account,
      username: 'fixture',
      companyId: swapId(2),
      locationId: location,
    ),
  );
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      SystemStatusResponse(companyId: swapId(2), locationId: locationId);
  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

http.Response response(Object data, [int status = 200]) =>
    http.Response(jsonEncode(data), status);
Map<String, dynamic> copy(Map<String, dynamic> j) =>
    jsonDecode(jsonEncode(j)) as Map<String, dynamic>;
List<String> actions(String role, String state) => switch ((role, state)) {
  ('source', 'requested') => ['source_withdraw'],
  ('source', 'offered') => ['confirm', 'decline', 'source_withdraw'],
  ('source', 'confirmed') => ['source_withdraw'],
  ('recipient', 'requested') => ['offer', 'decline'],
  ('recipient', 'offered' || 'confirmed') => ['recipient_withdraw'],
  ('manager', 'requested' || 'offered') => ['manager_reject'],
  ('manager', 'confirmed') => ['manager_reject', 'manager_approve'],
  _ => [],
};

class SwapHarness {
  SwapHarness({
    this.role = 'recipient',
    String state = 'requested',
    int stage = 1,
    this.self = true,
  }) {
    evidence = swapEvidence(state: state, stage: stage);
    client = MockClient(handle);
    api = HttpPlatformApi(
      baseUri: Uri.parse('http://fixture.invalid'),
      client: client,
    );
    session = SessionController(auth, now: () => auth.now);
    platform = PlatformController(session, api);
    controller = ShiftSwapController(
      session,
      platform,
      api,
      self: self,
      idFactory: () => swapId(++ids),
    );
  }
  final bool self;
  final auth = SwapAuth();
  late final http.Client client;
  late final HttpPlatformApi api;
  late final SessionController session;
  late final PlatformController platform;
  late final ShiftSwapController controller;
  late Map<String, dynamic> evidence;
  String role;
  int ids = 900;
  List<String> grants = List.of(permissions);
  final requests = <http.Request>[];
  Object? postError, readError;
  String? rawPost;
  Map<String, dynamic>? resultOverride, detailOverride;
  int? postStatus;
  bool replay = false, actionable = true;
  Completer<http.Response>? postHold, readHold;
  Future<http.Response> Function(http.Request)? read;
  String get id => evidence['id'] as String;
  String get root =>
      self ? '/me/shift-swaps' : '/locations/${auth.location}/shift-swaps';
  List<http.Request> get posts =>
      requests.where((r) => r.method == 'POST').toList();
  List<http.Request> get reads =>
      requests.where((r) => r.method == 'GET').toList();

  Map<String, dynamic> detail() =>
      detailOverride ??
      {
        'request': evidence,
        'participantRole': role,
        'actionable':
            actionable &&
            {'requested', 'offered', 'confirmed'}.contains(evidence['status']),
        'nonActionableReason': actionable ? null : 'shift_conflict',
        'availableActions': actions(role, evidence['status'] as String),
      };
  Future<http.Response> handle(http.Request r) async {
    requests.add(r);
    final route = r.url.path.substring('/api/v1/platform'.length);
    if (route == '/context') {
      return response({
        'userId': auth.account,
        'companyId': swapId(2),
        'locationId': auth.location,
        'role': 'admin',
        'permissions': grants,
      });
    }
    if (route == '/organization') {
      return response({
        'company': {'id': swapId(2), 'name': 'Fixture', 'version': 1},
        'locations': [
          {
            'id': auth.location,
            'companyId': swapId(2),
            'name': 'Fixture',
            'version': 1,
          },
        ],
      });
    }
    if (r.method == 'POST') {
      if (postHold != null) return postHold!.future;
      if (postError != null) throw postError!;
      if (rawPost != null) return http.Response(rawPost!, postStatus ?? 200);
      if (postStatus != null && postStatus! >= 400) {
        return response({
          'code': 'fixture_denied',
          'message': 'Denied',
        }, postStatus!);
      }
      final result =
          resultOverride ??
          accept(route, jsonDecode(r.body) as Map<String, dynamic>);
      return response(result, postStatus ?? result['statusCode'] as int);
    }
    if (readHold != null) return readHold!.future;
    if (readError != null) throw readError!;
    if (read != null) return read!(r);
    if (route.endsWith('/swap-colleagues')) {
      return response({
        'items': [
          {'employeeId': swapId(5), 'displayName': 'B'},
        ],
        'nextCursor': null,
      });
    }
    if (route.endsWith('/counterparts')) {
      return response({
        'items': [candidate()],
        'nextCursor': null,
      });
    }
    if (route.contains('/counterparts/')) {
      return response(
        (swapEvidence(state: 'offered', stage: 2)['legs'] as List)[1],
      );
    }
    if (route.endsWith('/history') || route == root) {
      return response({'items': [], 'nextCursor': null});
    }
    return response(detail());
  }

  Map<String, dynamic> candidate({int n = 40, int version = 2}) => {
    'shiftId': swapId(n),
    'version': version,
    'startsAt': '2030-01-01T10:00:00Z',
    'endsAt': '2030-01-01T11:00:00Z',
  };
  Map<String, dynamic> accept(String route, Map<String, dynamic> body) {
    final kind = route == root
        ? 'request'
        : route.endsWith('/withdraw')
        ? '${role}_withdraw'
        : route.endsWith('/approve')
        ? 'manager_approve'
        : route.endsWith('/reject')
        ? 'manager_reject'
        : route.split('/').last;
    final stage = kind == 'request' ? 1 : body['expectedVersion'] as int;
    final state = switch (kind) {
      'request' => 'requested',
      'offer' => 'offered',
      'confirm' => 'confirmed',
      'decline' => 'declined',
      'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
      'manager_reject' => 'rejected',
      _ => 'approved',
    };
    final next = swapEvidence(
      state: state,
      stage: kind == 'offer'
          ? 2
          : kind == 'confirm'
          ? 3
          : stage,
    );
    for (final key in [
      'id',
      'requestOperationId',
      'offerOperationId',
      'confirmationOperationId',
    ]) {
      if (evidence[key] != null) next[key] = evidence[key];
    }
    final key = kind == 'request'
        ? 'requestOperationId'
        : kind == 'offer'
        ? 'offerOperationId'
        : kind == 'confirm'
        ? 'confirmationOperationId'
        : 'terminalOperationId';
    next[key] = body['operationId'];
    if (kind == 'request') next['id'] = body['requestId'];
    if (body.containsKey('reason')) next['terminalReason'] = body['reason'];
    if (kind.endsWith('withdraw')) next['terminalKind'] = kind;
    evidence = next;
    return {
      'operationId': body['operationId'],
      'kind': kind,
      'acceptedVersion': next['version'],
      'statusCode': kind == 'request' ? 201 : 200,
      'request': next,
      'replayed': replay,
    };
  }

  Future<void> login() async {
    final ready = Completer<void>();
    void changed() {
      if (platform.organization != null &&
          !platform.isBusy &&
          !ready.isCompleted) {
        ready.complete();
      }
    }

    platform.addListener(changed);
    await session.signIn(username: 'fixture', password: 'fixture');
    changed();
    await ready.future.timeout(const Duration(seconds: 5));
    platform.removeListener(changed);
  }

  Future<void> start() async {
    await login();
    await controller.select(id);
    expect(controller.error, isNull);
  }

  Future<void> prepare(String kind) async {
    if (kind == 'request') {
      final shift = ShiftDto(
        id: swapId(20),
        companyId: swapId(2),
        locationId: swapId(3),
        version: 2,
        status: 'published',
        draft: ShiftDraftInput(
          employeeId: swapId(4),
          startsAt: DateTime.utc(2030, 1, 1, 10),
          endsAt: DateTime.utc(2030, 1, 1, 11),
          selections: [ShiftTemplateSelection(swapId(500), swapId(600))],
        ),
        createdAt: DateTime.utc(2029),
        updatedAt: DateTime.utc(2029),
      );
      await controller.chooseSource(shift);
      controller.chooseColleague(swapId(5));
    }
    if (kind == 'offer') {
      await controller.loadCounterparts();
      await controller.chooseCounterpart(swapId(40));
    }
  }

  Future<SwapOutcome> invoke(
    String kind, {
    String reason = 'Coverage changed',
  }) => kind == 'request'
      ? controller.request()
      : controller.act(
          kind.endsWith('withdraw') ? 'withdraw' : kind,
          reason: reason,
        );
  void dispose() {
    controller.dispose();
    platform.dispose();
    session.dispose();
    client.close();
  }
}

Future<SwapHarness> setup({String kind = 'offer'}) async {
  final manager = kind.startsWith('manager_');
  final role = manager
      ? 'manager'
      : {'confirm', 'source_withdraw', 'request'}.contains(kind)
      ? 'source'
      : 'recipient';
  final stage = kind == 'confirm' || kind == 'recipient_withdraw'
      ? 2
      : kind == 'manager_approve'
      ? 3
      : 1;
  final h = SwapHarness(
    role: role,
    self: !manager,
    stage: stage,
    state: stage == 3
        ? 'confirmed'
        : stage == 2
        ? 'offered'
        : 'requested',
  );
  addTearDown(h.dispose);
  await h.start();
  await h.prepare(kind);
  return h;
}

void main() {
  test(
    'stale fresh detail cannot enable a second confirmed approval',
    () async {
      final h = await setup(kind: 'manager_approve'), c = h.controller;
      final stale = copy(h.detail());
      h.detailOverride = stale;
      expect(await c.act('approve'), SwapOutcome.confirmed);
      expect(c.lastConfirmed!.json['kind'], 'manager_approve');
      expect(c.detail, isNull);
      expect(c.refreshWarning, isNotNull);
      await c.select(h.id);
      expect(c.detail, isNull);
      expect(c.error, isNotNull);
      expect(await c.act('approve'), SwapOutcome.rejected);
      expect(h.posts, hasLength(1));
    },
  );
  for (final kind in ['request', 'offer']) {
    test(
      '$kind rejects a receipt for changed selected Shift evidence',
      () async {
        final h = await setup(kind: kind), c = h.controller;
        final body = kind == 'request'
            ? {
                'operationId': swapId(h.ids + 1),
                'requestId': swapId(h.ids + 2),
                'sourceShiftId': swapId(20),
                'expectedSourceVersion': 2,
                'recipientEmployeeId': swapId(5),
              }
            : {
                'operationId': swapId(h.ids + 1),
                'expectedVersion': 1,
                'counterpartShiftId': swapId(40),
                'expectedCounterpartVersion': 2,
              };
        final result = copy(
          h.accept(
            kind == 'request' ? h.root : '${h.root}/${h.id}/offer',
            body,
          ),
        );
        result['request']['legs'][kind == 'request' ? 0 : 1]['sourceVersion'] =
            3;
        h.resultOverride = result;
        expect(await h.invoke(kind), SwapOutcome.uncertain);
        expect(c.lastConfirmed, isNull);
        expect(c.pending, isNotNull);
      },
    );
  }
  test(
    'same-scope context replacement fences a held write and freezes capability hints',
    () async {
      final h = await setup(), c = h.controller;
      h.postHold = Completer<http.Response>();
      final future = c.act('offer');
      await Future<void>.delayed(Duration.zero);
      final raw = copy(h.platform.context!.toJson());
      h.platform.context = PlatformContextResponse.fromJson(raw);
      (raw['permissions'] as List).clear();
      expect(h.platform.allows('workforce.swaps.self.read'), true);
      expect(
        () => h.platform.context!.permissions.clear(),
        throwsUnsupportedError,
      );
      h.postHold!.complete(response({}));
      expect(await future, SwapOutcome.fenced);
      expect(c.pending, isNull);
      expect(c.canRead, true);
      expect(c.selectedCounterpart, isNull);
    },
  );
  for (final status in [201, 202]) {
    test('HTTP $status with a 200 receipt is unusable confirmation', () async {
      final h = await setup(kind: 'decline');
      h.postStatus = status;
      expect(await h.controller.act('decline'), SwapOutcome.uncertain);
      expect(h.controller.pending, isNotNull);
      expect(h.controller.lastConfirmed, isNull);
    });
  }
  test(
    'manager list uses bound Location and refuses direction; DTO scope and page bounds are enforced',
    () async {
      final h = await setup(kind: 'manager_reject'), c = h.controller;
      h.read = (_) async => response({
        'items': [h.evidence],
        'nextCursor': null,
      });
      await c.filter(state: 'requested');
      expect(
        h.reads.last.url.path,
        '/api/v1/platform/locations/${swapId(3)}/shift-swaps',
      );
      expect(c.items, hasLength(1));
      final reads = h.reads.length;
      await c.filter(way: 'incoming');
      expect(h.reads.length, reads);
      final foreign = copy(h.evidence)..['companyId'] = swapId(12);
      h.read = (_) async => response({
        'items': [foreign],
        'nextCursor': null,
      });
      await c.load();
      expect(c.error, isNotNull);
      expect(c.items, isEmpty);
      h.read = (_) async => response({
        'items': List.generate(
          51,
          (i) => copy(h.evidence)..['id'] = swapId(1000 + i),
        ),
        'nextCursor': null,
      });
      await c.load();
      expect(c.error, isNotNull);
      h.read = (_) async => http.Response('{', 200);
      await c.select(h.id);
      expect(c.detail, isNull);
      expect(c.error, isNotNull);
    },
  );
  test(
    'rejected request leaves original confirmation and unrelated list intact',
    () async {
      final h = await setup(kind: 'request'), c = h.controller;
      expect(await c.request(), SwapOutcome.confirmed);
      final accepted = c.lastConfirmed;
      h.read = (_) async => response({
        'items': [h.evidence],
        'nextCursor': null,
      });
      await c.load();
      h.read = null;
      await h.prepare('request');
      h.postStatus = 422;
      expect(await c.request(), SwapOutcome.rejected);
      expect(c.lastConfirmed, same(accepted));
      expect(c.items, hasLength(1));
      expect(c.pending, isNull);
      expect(c.source, isNull);
    },
  );
  for (final kind in shiftSwapKinds) {
    test(
      '$kind strict HTTP accepted semantics, deep immutable intent and exact replay',
      () async {
        final h = await setup(kind: kind), c = h.controller;
        h.postError = http.ClientException('Dropped response');
        expect(await h.invoke(kind), SwapOutcome.uncertain);
        final pending = c.pending!, count = h.ids, before = pending.canonical;
        expect(pending.kind, kind);
        expect(pending.state, SwapSubmission.uncertain);
        expect(
          () => pending.body['operationId'] = swapId(99),
          throwsUnsupportedError,
        );
        expect(() => pending.evidence['other'] = true, throwsUnsupportedError);
        if (kind != 'request') {
          expect(
            () => (pending.evidence['request']['legs'] as List).clear(),
            throwsUnsupportedError,
          );
          expect(
            () => pending.evidence['request']['legs'][0]['tasks'][0]['title'] =
                'Changed',
            throwsUnsupportedError,
          );
        }
        expect(await h.invoke(kind, reason: 'Changed body'), SwapOutcome.busy);
        expect(await c.request(), SwapOutcome.busy);
        expect(h.ids, count);
        h.postError = null;
        h.replay = true;
        expect(await c.retry(), SwapOutcome.confirmed);
        expect(h.posts, hasLength(2));
        expect(h.posts[0].url, h.posts[1].url);
        expect(h.posts[0].body, h.posts[1].body);
        expect(h.posts[0].body, before);
        expect(h.ids, count);
        expect(c.pending, isNull);
        expect(c.lastConfirmed!.json['kind'], kind);
        expect(
          c.lastConfirmed!.json['statusCode'],
          kind == 'request' ? 201 : 200,
        );
        expect(c.lastConfirmed!.json['replayed'], true);
        expect(c.detail, isNotNull);
        expect(jsonDecode(h.posts.last.body), isNot(contains('kind')));
        expect(jsonDecode(h.posts.last.body), isNot(contains('actor')));
        if (kind.endsWith('withdraw')) {
          expect(h.posts.last.url.path, endsWith('/withdraw'));
        }
      },
    );
    test(
      '$kind same-account session replacement fences held command',
      () async {
        final h = await setup(kind: kind), c = h.controller;
        h.postHold = Completer<http.Response>();
        final future = h.invoke(kind), identity = c.sessionIdentity;
        await Future<void>.delayed(Duration.zero);
        final r = h.posts.single;
        final accepted = h.accept(
          r.url.path.substring('/api/v1/platform'.length),
          jsonDecode(r.body) as Map<String, dynamic>,
        );
        await h.login();
        expect(identical(identity, c.sessionIdentity), false);
        h.postHold!.complete(response(accepted, accepted['statusCode'] as int));
        expect(await future, SwapOutcome.fenced);
        expect(c.pending, isNull);
        expect(c.lastConfirmed, isNull);
        expect(c.detail, isNull);
        expect(c.counterparts, isEmpty);
        expect(c.colleagues, isEmpty);
        expect(c.items, isEmpty);
      },
    );
  }

  for (final status in [400, 403, 404, 409, 413, 415, 422]) {
    test(
      'later $status preserves unknown original outcome and requires explicit reconciliation',
      () async {
        final h = await setup(), c = h.controller;
        h.postError = http.ClientException('Lost');
        expect(await c.act('offer'), SwapOutcome.uncertain);
        final original = c.pending!, count = h.ids;
        h.postError = null;
        h.postStatus = status;
        expect(await c.retry(), SwapOutcome.reconciliationRequired);
        expect(c.pending!.canonical, original.canonical);
        expect(c.pending!.state, SwapSubmission.reconciliationRequired);
        expect(c.error, contains('earlier outcome remains unknown'));
        expect(await c.act('decline'), SwapOutcome.busy);
        expect(h.ids, count);
        h.read = (_) async => response({'items': [], 'nextCursor': null});
        expect(await c.reconcile(), SwapOutcome.reconciliationRequired);
        expect(c.pending, isNotNull);
        h.postStatus = null;
        final accepted = h.accept(original.route, original.body);
        h.read = (_) async => response({
          'items': [accepted],
          'nextCursor': null,
        });
        expect(await c.reconcile(), SwapOutcome.confirmed);
        expect(h.posts, hasLength(2));
        expect(c.lastConfirmed, isNotNull);
        expect(c.pending, isNull);
      },
    );
    test(
      'first $status is rejected and leaves unrelated list/history evidence intact',
      () async {
        final h = await setup(kind: 'decline'), c = h.controller;
        h.read = (_) async => response({
          'items': [h.evidence],
          'nextCursor': null,
        });
        await c.load();
        h.read = null;
        h.postStatus = status;
        expect(await c.act('decline'), SwapOutcome.rejected);
        expect(c.pending, isNull);
        expect(c.lastConfirmed, isNull);
        expect(c.items.single.json['id'], h.id);
        expect(c.detail, isNull);
      },
    );
  }

  test(
    '401 after uncertain outcome expires and fences rather than proving rollback',
    () async {
      final h = await setup(), c = h.controller;
      h.postError = http.ClientException('Lost');
      expect(await c.act('offer'), SwapOutcome.uncertain);
      h.postError = null;
      h.postStatus = 401;
      expect(await c.retry(), SwapOutcome.fenced);
      expect(h.session.isAuthenticated, false);
      expect(c.pending, isNull);
      expect(c.lastConfirmed, isNull);
    },
  );
  test(
    'confirmed approval survives failed fresh GET and cannot submit twice',
    () async {
      final h = await setup(kind: 'manager_approve'), c = h.controller;
      h.readError = http.ClientException('Unavailable');
      expect(await c.act('approve'), SwapOutcome.confirmed);
      final accepted = c.lastConfirmed;
      expect(accepted!.json['request']['status'], 'approved');
      expect(c.detail, isNull);
      expect(c.refreshWarning, contains('Command confirmed'));
      expect(await c.act('approve'), SwapOutcome.rejected);
      expect(await c.retry(), SwapOutcome.busy);
      expect(h.posts, hasLength(1));
      final legs = accepted.request.json['legs'] as List;
      expect(legs.map((l) => l['replacementShiftId']).toSet(), hasLength(2));
      expect(
        legs[0]['taskLinks'][0]['sourceTaskId'],
        legs[0]['tasks'][0]['id'],
      );
      h.readError = null;
      await c.select(h.id);
      expect(c.lastConfirmed, same(accepted));
      expect(c.detail, isNotNull);
      expect(c.refreshWarning, isNull);
    },
  );

  for (final change in [
    'account',
    'location',
    'context',
    'logout',
    'expiry',
    'dispose',
  ]) {
    for (final command in [false, true]) {
      test(
        '$change fences held ${command ? 'POST' : 'GET'} and clears private state',
        () async {
          final h = await setup(), c = h.controller;
          var notifications = 0;
          c.addListener(() => notifications++);
          final hold = Completer<http.Response>();
          late Future<dynamic> future;
          if (command) {
            h.postHold = hold;
            future = c.act('offer');
          } else {
            h.readHold = hold;
            future = c.select(h.id);
          }
          await Future<void>.delayed(Duration.zero);
          final oldDetail = copy(h.detail());
          if (change == 'account') {
            h.auth.account = swapId(11);
            await h.login();
          }
          if (change == 'location') {
            h.auth.location = swapId(13);
            await h.login();
          }
          if (change == 'context') {
            final raw = h.platform.context!.toJson();
            raw['locationId'] = swapId(13);
            h.platform.context = PlatformContextResponse.fromJson(raw);
          }
          if (change == 'logout') await h.session.signOut();
          if (change == 'expiry') {
            h.auth.now = h.auth.now.add(const Duration(hours: 2));
            await expectLater(
              h.session.authorized((_) async => true),
              throwsA(isA<StoreApiException>()),
            );
          }
          if (change == 'dispose') c.dispose();
          final count = notifications;
          hold.complete(response(oldDetail));
          final outcome = await future;
          if (command) expect(outcome, SwapOutcome.fenced);
          expect(notifications, count);
          expect(c.detail, isNull);
          expect(c.pending, isNull);
          expect(c.lastConfirmed, isNull);
          expect(c.counterparts, isEmpty);
          expect(c.history, isEmpty);
          expect(c.nextCursor, isNull);
        },
      );
    }
  }

  test(
    'manager hints require all approval prerequisites and server independent availableActions',
    () async {
      final h = await setup(kind: 'manager_approve'), c = h.controller;
      expect(c.can('manager_approve'), true);
      h.detailOverride = {
        ...h.detail(),
        'availableActions': ['manager_reject'],
      };
      await c.select(h.id);
      expect(c.can('manager_approve'), false);
      expect(c.can('manager_reject'), true);
      h.detailOverride = null;
      for (final missing in [
        'workforce.swaps.manage',
        'workforce.shifts.manage',
        'tasks.instances.read',
      ]) {
        h.grants = permissions.where((p) => p != missing).toList();
        await h.login();
        await c.select(h.id);
        expect(c.can('manager_approve'), false);
        expect(await c.act('approve'), SwapOutcome.rejected);
      }
      expect(h.posts, isEmpty);
    },
  );
  test(
    'only recipient may discover own counterparts; candidate and selected detail stay distinct',
    () async {
      final h = await setup(), c = h.controller;
      await c.select(h.id);
      await c.loadCounterparts();
      expect(c.counterparts, hasLength(1));
      expect(c.selectedCounterpart, isNull);
      expect(c.can('offer'), false);
      h.read = (_) async {
        final leg = copy(
          (swapEvidence(state: 'offered', stage: 2)['legs'] as List)[1]
              as Map<String, dynamic>,
        );
        leg['sourceVersion'] = 3;
        return response(leg);
      };
      await c.chooseCounterpart(swapId(40));
      expect(c.selectedCounterpart, isNull);
      expect(c.can('offer'), false);
      expect(c.error, isNotNull);
      h.read = null;
      h.role = 'source';
      await c.select(h.id);
      final reads = h.reads.length;
      await c.loadCounterparts();
      await c.chooseCounterpart(swapId(40));
      expect(h.reads.length, reads);
    },
  );
  test(
    'no private identities/evidence leak between composed self and manager modes',
    () async {
      final h = await setup();
      final manager = ShiftSwapController(
        h.session,
        h.platform,
        h.api,
        self: false,
      );
      addTearDown(manager.dispose);
      await manager.select(
        h.id,
      ); // A participant projection must not enter manager mode.
      expect(manager.detail, isNull);
      expect(manager.error, isNotNull);
      h.role = 'manager';
      await manager.select(h.id);
      expect(manager.detail!.json['participantRole'], 'manager');
      expect(h.controller.detail!.json['participantRole'], 'recipient');
      await h.controller.select(h.id);
      expect(h.controller.detail, isNull);
      final wire = jsonEncode(manager.detail!.json);
      for (final private in [
        'accountId',
        'linkId',
        'source_account_id',
        'token',
      ]) {
        expect(wire, isNot(contains(private)));
      }
    },
  );

  for (final broken in [
    'malformed',
    'empty',
    'wrongId',
    'wrongKind',
    'wrongOperation',
    'wrongPair',
    'wrongPin',
    'version',
    'status',
  ]) {
    test('$broken successful response remains uncertain', () async {
      final h = await setup(kind: 'confirm'), c = h.controller;
      if (broken == 'malformed' || broken == 'empty') {
        h.rawPost = broken == 'empty' ? '' : '{';
      } else {
        final body = {'operationId': swapId(h.ids + 1), 'expectedVersion': 2};
        final result = copy(h.accept('${h.root}/${h.id}/confirm', body));
        switch (broken) {
          case 'wrongId':
            result['request']['id'] = swapId(999);
          case 'wrongKind':
            result['kind'] = 'offer';
          case 'wrongOperation':
            result['operationId'] = swapId(777);
            result['request']['confirmationOperationId'] = swapId(777);
          case 'wrongPair':
            result['request']['legs'][1]['sourceShiftId'] = swapId(888);
          case 'wrongPin':
            result['request']['legs'][1]['tasks'][0]['knowledgeGuidance'] = {
              'articleId': swapId(300),
              'revisionId': swapId(301),
            };
          case 'version':
            result['acceptedVersion'] = 4;
          case 'status':
            result['statusCode'] = 201;
        }
        h.resultOverride = result;
      }
      expect(await c.act('confirm'), SwapOutcome.uncertain);
      expect(c.lastConfirmed, isNull);
      expect(c.pending, isNotNull);
      expect(c.detail, isNull);
    });
  }
  test(
    'timeouts, unexpected transport failures and 5xx preserve the intent',
    () async {
      for (final failure in [
        TimeoutException('Timeout'),
        StateError('Unexpected'),
        http.ClientException('Connection lost'),
      ]) {
        final h = await setup(kind: 'decline');
        h.postError = failure;
        expect(await h.controller.act('decline'), SwapOutcome.uncertain);
        expect(h.controller.pending, isNotNull);
      }
      final h = await setup(kind: 'decline');
      h.postStatus = 503;
      expect(await h.controller.act('decline'), SwapOutcome.uncertain);
    },
  );
  test(
    'invalid command reason rejected before dispatch; rejected request preserves existing detail',
    () async {
      final h = await setup(kind: 'source_withdraw'),
          c = h.controller,
          original = c.detail;
      expect(await c.act('withdraw', reason: ''), SwapOutcome.rejected);
      expect(h.posts, isEmpty);
      expect(c.pending, isNull);
      expect(c.detail, same(original));
      expect(await c.request(), SwapOutcome.rejected);
      expect(c.detail, same(original));
    },
  );

  test(
    'scoped list pagination keeps filters, deduplicates and rejects invalid/foreign cursor without empty evidence',
    () async {
      final h = await setup(), c = h.controller;
      final row = copy(h.evidence), second = copy(row)..['id'] = swapId(12);
      h.read = (r) async => response({
        'items': r.url.queryParameters.containsKey('after')
            ? [row, second]
            : [row],
        'nextCursor': r.url.queryParameters.containsKey('after')
            ? null
            : 'opaque+cursor/=',
      });
      await c.filter(state: 'requested', way: 'incoming');
      await c.load(more: true);
      expect(c.items, hasLength(2));
      expect(h.reads.last.url.queryParameters, {
        'status': 'requested',
        'direction': 'incoming',
        'after': 'opaque+cursor/=',
      });
      expect(() => c.items.clear(), throwsUnsupportedError);
      await c.filter(state: 'requested', way: 'incoming');
      h.read = (_) async =>
          response({'code': 'invalid_cursor', 'message': 'Foreign scope'}, 400);
      await c.load(more: true);
      expect(c.items, hasLength(1));
      expect(c.error, contains('invalid_cursor'));
      h.read = (_) async => response({
        'items': [row],
        'nextCursor': 'x' * 2049,
      });
      await c.load(more: true);
      expect(c.error, isNotNull);
      expect(c.items, hasLength(1));
      final count = h.reads.length;
      await c.filter(state: 'bad');
      await c.filter(way: 'sideways');
      expect(h.reads.length, count);
      h.read = (_) async => response({'items': [], 'nextCursor': null});
      await c.filter(state: 'offered');
      expect(h.reads.last.url.queryParameters, {'status': 'offered'});
      await h.login();
      final beforeMore = h.reads.length;
      await c.load(more: true);
      expect(h.reads.length, beforeMore);
    },
  );
  test('stale filters and pages cannot publish after newer read', () async {
    final h = await setup(), c = h.controller;
    final hold = Completer<http.Response>();
    h.read = (r) async => r.url.queryParameters['status'] == 'requested'
        ? hold.future
        : response({'items': [], 'nextCursor': null});
    final old = c.filter(state: 'requested', way: 'incoming');
    await c.filter(state: 'offered', way: 'outgoing');
    hold.complete(
      response({
        'items': [h.evidence],
        'nextCursor': 'old',
      }),
    );
    await old;
    expect(c.items, isEmpty);
    expect(c.nextCursor, isNull);
    expect(c.status, 'offered');
    expect(c.error, isNull);
  });
  test(
    'history uses strict receipt DTOs, two-page cursor, deduplicates original evidence',
    () async {
      final h = await setup(kind: 'manager_approve'), c = h.controller;
      Map<String, dynamic> receipt(
        String kind,
        String state,
        int stage,
        int op,
      ) {
        final request = swapEvidence(state: state, stage: stage);
        return {
          'operationId': swapId(op),
          'kind': kind,
          'acceptedVersion': request['version'],
          'statusCode': kind == 'request' ? 201 : 200,
          'request': request,
          'replayed': false,
        };
      }

      final receipts = [
        receipt('request', 'requested', 1, 6),
        receipt('offer', 'offered', 2, 7),
        receipt('confirm', 'confirmed', 3, 8),
        receipt('manager_approve', 'approved', 3, 9),
      ];
      h.read = (r) async => response({
        'items': r.url.queryParameters['after'] == null
            ? receipts.take(2).toList()
            : receipts.skip(2).toList(),
        'nextCursor': r.url.queryParameters['after'] == null ? 'history' : null,
      });
      await c.loadHistory(h.id);
      await c.loadHistory(h.id, more: true);
      expect(c.history.map((r) => r.json['acceptedVersion']), [1, 2, 3, 4]);
      expect(c.historyCursor, isNull);
      expect(h.reads.last.url.queryParameters['after'], 'history');
      await c.loadHistory(h.id);
      h.read = (_) async => response({
        'items': [receipts[1]],
        'nextCursor': null,
      });
      await c.loadHistory(h.id, more: true);
      expect(c.history, hasLength(2));
      h.read = (_) async => response({'items': receipts, 'nextCursor': null});
      await c.loadHistory(h.id);
      expect(c.error, isNotNull);
    },
  );
  test(
    'candidate/colleague pagination is scoped and never retains mutable response maps',
    () async {
      final h = await setup(), c = h.controller;
      await c.select(h.id);
      final row = h.candidate();
      h.read = (r) async => response({
        'items': r.url.queryParameters['after'] == null
            ? [row]
            : [row, h.candidate(n: 41)],
        'nextCursor': r.url.queryParameters['after'] == null
            ? 'own-candidates'
            : null,
      });
      await c.loadCounterparts();
      row['version'] = 99;
      expect(c.counterparts.single['version'], 2);
      expect(
        () => c.counterparts.single['version'] = 3,
        throwsUnsupportedError,
      );
      row['version'] = 2;
      await c.loadCounterparts(more: true);
      expect(c.counterparts, hasLength(2));
      expect(h.reads.last.url.queryParameters['after'], 'own-candidates');
      h.read = null;
      await h.prepare('request');
      final shift = c.source!;
      h.read = (r) async => response({
        'items': [
          {
            'employeeId': swapId(
              r.url.queryParameters['after'] == null ? 5 : 15,
            ),
            'displayName': 'Literal',
          },
        ],
        'nextCursor': r.url.queryParameters['after'] == null
            ? 'colleagues'
            : null,
      });
      await c.chooseSource(shift);
      await c.chooseSource(shift, more: true);
      expect(c.colleagues, hasLength(2));
      expect(h.reads.last.url.queryParameters['after'], 'colleagues');
      expect(
        () => c.colleagues.first['displayName'] = 'Changed',
        throwsUnsupportedError,
      );
    },
  );
}
