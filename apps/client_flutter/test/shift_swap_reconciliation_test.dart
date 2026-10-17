import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';

import 'shift_swap_fixture.dart';
import 'shift_swap_test.dart' as h;

String snapshot(ShiftSwapController c) => jsonEncode({
  'items': c.items.map((r) => r.json).toList(),
  'detail': c.detail?.json,
  'history': c.history.map((r) => r.json).toList(),
  'colleagues': c.colleagues,
  'counterparts': c.counterparts,
  'source': c.source?.toJson(),
  'colleague': c.colleague,
  'counterpart': c.counterpart,
  'selected': c.selectedCounterpart?.json,
  'pending': c.pending == null
      ? null
      : {
          'canonical': c.pending!.canonical,
          'evidence': c.pending!.evidence,
          'state': c.pending!.state.name,
        },
  'confirmed': c.lastConfirmed?.json,
  'cursors': [
    c.nextCursor,
    c.historyCursor,
    c.colleagueCursor,
    c.counterpartCursor,
  ],
  'error': c.error,
  'warning': c.refreshWarning,
  'busy': c.busy,
  'locked': c.locked,
});

void expectCleared(ShiftSwapController c) {
  expect(c.pending, isNull);
  expect(c.lastConfirmed, isNull);
  expect(c.detail, isNull);
  expect(c.source, isNull);
  expect(c.colleague, isNull);
  expect(c.counterpart, isNull);
  expect(c.selectedCounterpart, isNull);
  expect(c.items, isEmpty);
  expect(c.history, isEmpty);
  expect(c.colleagues, isEmpty);
  expect(c.counterparts, isEmpty);
  expect([
    c.nextCursor,
    c.historyCursor,
    c.colleagueCursor,
    c.counterpartCursor,
  ], everyElement(isNull));
  expect(c.busy, false);
  expect(c.locked, false);
  expect(c.can('offer'), false);
  expect(c.can('manager_approve'), false);
  expect(c.error, isNull);
  expect(c.refreshWarning, isNull);
}

void replaceContext(h.SwapHarness x, String change) {
  if (change == 'expiry') {
    x.session.invalidateSession();
    return;
  }
  final raw = x.platform.context!.toJson();
  if (change == 'denied-context') {
    raw['role'] = 'viewer';
    raw['permissions'] = <String>[];
  }
  if (change == 'location') raw['locationId'] = swapId(13);
  x.platform.context = PlatformContextResponse.fromJson(raw);
}

Future<h.SwapHarness> uncertain(String kind) async {
  final x = await h.setup(kind: kind);
  x.read = (_) async => h.response({
    'items': [x.evidence],
    'nextCursor': 'old-list-cursor',
  });
  await x.controller.load();
  x.read = null;
  x.postError = http.ClientException('Completed response unavailable');
  expect(await x.invoke(kind), SwapOutcome.uncertain);
  expect(x.controller.items, isNotEmpty);
  expect(x.controller.nextCursor, isNotNull);
  return x;
}

Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class HeldBootstrapApi implements PlatformApi {
  HeldBootstrapApi(this.delegate, this.route);
  final PlatformApi delegate;
  final String route;
  final hold = Completer<Map<String, dynamic>>();
  final dispatched = Completer<void>();
  final routes = <String>[];
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) {
    routes.add(route);
    if (route == this.route && !dispatched.isCompleted) {
      dispatched.complete();
      return hold.future;
    }
    return delegate.get(token, route, after: after, query: query);
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) => delegate.post(token, route, body);
}

void main() {
  for (final kind in shiftSwapKinds) {
    for (final status in [401, 403, 404, 409, 422]) {
      test(
        'B3A-01 $kind exact replay after unresolved attempt and $status',
        () async {
          final x = await h.setup(kind: kind), c = x.controller;
          x.postError = http.ClientException('Response lost');
          expect(await x.invoke(kind), SwapOutcome.uncertain);
          final command = c.pending!, ids = x.ids;
          final evidence = jsonEncode(command.evidence);
          expect(
            () => command.body['expectedVersion'] = 99,
            throwsUnsupportedError,
          );
          expect(() => command.evidence.clear(), throwsUnsupportedError);
          x.postError = null;
          x.postStatus = status;
          expect(
            await c.retry(),
            status == 401
                ? SwapOutcome.fenced
                : SwapOutcome.reconciliationRequired,
          );
          expect(x.ids, ids);
          expect(x.posts.map((r) => r.body), [
            command.canonical,
            command.canonical,
          ]);
          expect(x.posts[0].url, x.posts[1].url);
          if (status == 401) {
            expect(x.session.isAuthenticated, false);
            expectCleared(c);
            final count = x.posts.length;
            expect(await c.retry(), SwapOutcome.busy);
            expect(x.posts.length, count);
            return;
          }
          expect(c.pending!.operationId, command.operationId);
          expect(c.pending!.requestId, command.requestId);
          expect(c.pending!.expectedVersion, command.expectedVersion);
          expect(c.pending!.route, command.route);
          expect(jsonEncode(c.pending!.evidence), evidence);
          expect(await x.invoke(kind), SwapOutcome.busy);
          expect(x.ids, ids);
          x.postStatus = null;
          x.replay = true;
          x.readError = http.ClientException('Fresh detail unavailable');
          expect(await c.retry(), SwapOutcome.confirmed);
          expect(x.ids, ids);
          expect(x.posts.last.body, command.canonical);
          expect(c.lastConfirmed!.json['operationId'], command.operationId);
          expect(c.lastConfirmed!.json['replayed'], true);
          expect(
            c.lastConfirmed!.json['statusCode'],
            kind == 'request' ? 201 : 200,
          );
          expect(c.pending, isNull);
          expect(c.detail, isNull);
          expect(c.refreshWarning, isNotNull);
          final count = x.posts.length;
          expect(await x.invoke(kind), SwapOutcome.rejected);
          expect(await c.retry(), SwapOutcome.busy);
          expect(x.posts.length, count);
        },
      );
    }
  }
  for (final kind in ['offer', 'manager_approve']) {
    for (final change in ['context', 'denied-context', 'location', 'expiry']) {
      for (final response in ['empty', 'denied', 'exception']) {
        test(
          'B3A-01 $kind $change during $response reconciliation completion',
          () async {
            final x = await uncertain(kind), c = x.controller;
            x.read = (_) async {
              if (response == 'exception') {
                throw StateError('Receipt unavailable');
              }
              return response == 'denied'
                  ? h.response({'code': 'forbidden', 'message': 'Denied'}, 403)
                  : h.response({'items': [], 'nextCursor': null});
            };
            var changed = false, notifications = 0, atInvalidation = 0;
            void listener() {
              notifications++;
              if (!changed && !c.busy && c.pending != null && c.error != null) {
                changed = true;
                replaceContext(x, change);
                atInvalidation = notifications;
              }
            }

            c.addListener(listener);
            final outcome = await c.reconcile();
            c.removeListener(listener);
            expect(changed, true);
            expect(outcome, SwapOutcome.fenced);
            expectCleared(c);
            expect(notifications, atInvalidation);
            final posts = x.posts.length;
            expect(await c.retry(), SwapOutcome.busy);
            expect(x.posts.length, posts);
          },
        );
      }
    }

    for (final change in [
      'expiry',
      'logout',
      'same-account',
      'different-account',
      'location',
      'context',
      'dispose',
    ]) {
      for (final reply in ['accepted', 'denied', 'malformed', 'exception']) {
        test(
          'B3A-01 held $kind receipt $reply after $change stays fenced',
          () async {
            final x = await uncertain(kind), c = x.controller;
            final command = c.pending!, held = Completer<http.Response>();
            final receipt = h.copy(x.accept(command.route, command.body));
            x.read = (r) => r.url.path.endsWith('/history')
                ? held.future
                : Future.value(h.response(x.detail()));
            final reconciling = c.reconcile();
            await settle();
            if (change == 'same-account' || change == 'different-account') {
              if (change == 'different-account') x.auth.account = swapId(11);
              await x.login();
            } else if (change == 'logout') {
              await x.session.signOut();
            } else if (change == 'dispose') {
              c.dispose();
            } else {
              replaceContext(x, change);
            }
            expectCleared(c);
            final posts = x.posts.length;
            expect(await c.retry(), SwapOutcome.busy);
            expect(x.posts.length, posts);
            var notifications = 0;
            if (change != 'dispose') c.addListener(() => notifications++);
            // A legitimate new identity may load evidence before the old read ends.
            if (c.canRead) {
              x.evidence =
                  swapEvidence(
                      state: kind == 'offer' ? 'requested' : 'confirmed',
                      stage: kind == 'offer' ? 1 : 3,
                    )
                    ..['id'] = swapId(1001)
                    ..['sourceName'] = 'New authorized evidence';
              await c.select(x.id);
              expect(
                c.detail!.json['request']['sourceName'],
                'New authorized evidence',
              );
            }
            final before = snapshot(c), count = notifications;
            switch (reply) {
              case 'accepted':
                held.complete(
                  h.response({
                    'items': [receipt],
                    'nextCursor': null,
                  }),
                );
              case 'denied':
                held.complete(
                  h.response({'code': 'forbidden', 'message': 'Denied'}, 403),
                );
              case 'malformed':
                held.complete(http.Response('{', 200));
              case 'exception':
                held.completeError(StateError('Old receipt failure'));
            }
            expect(await reconciling, SwapOutcome.fenced);
            expect(snapshot(c), before);
            expect(notifications, count);
            expect(c.pending, isNull);
            expect(c.lastConfirmed, isNull);
            expect(c.locked, false);
          },
        );
      }
    }

    test(
      'B3A-01 overlapping $kind reconciliation and retry do not dispatch',
      () async {
        final x = await uncertain(kind), c = x.controller;
        final command = c.pending!, held = Completer<http.Response>();
        x.read = (_) => held.future;
        final first = c.reconcile();
        await settle();
        final reads = x.reads.length, posts = x.posts.length;
        expect(await c.reconcile(), SwapOutcome.busy);
        expect(await c.retry(), SwapOutcome.busy);
        expect(await x.invoke(kind), SwapOutcome.busy);
        expect(x.reads.length, reads);
        expect(x.posts.length, posts);
        held.complete(h.response({'items': [], 'nextCursor': null}));
        expect(await first, SwapOutcome.reconciliationRequired);
        expect(c.pending!.canonical, command.canonical);
        expect(c.locked, true);
        expect(c.busy, false);
      },
    );

    for (final next in ['retry', 'reconcile']) {
      test(
        'B3A-01 $kind completion listener may start $next without stale overwrite',
        () async {
          final x = await uncertain(kind), c = x.controller;
          final command = c.pending!, held = Completer<http.Response>();
          x.postError = null;
          x.postHold = held;
          var readCount = 0;
          x.read = (r) => r.url.path.endsWith('/history')
              ? (++readCount == 1
                    ? Future.value(
                        h.response({'items': [], 'nextCursor': null}),
                      )
                    : held.future)
              : Future.value(h.response(x.detail()));
          Future<SwapOutcome>? second;
          void listener() {
            if (second == null &&
                !c.busy &&
                c.pending != null &&
                c.error != null) {
              // Remove before starting another operation, which itself notifies.
              c.removeListener(listener);
              second = next == 'retry' ? c.retry() : c.reconcile();
            }
          }

          c.addListener(listener);
          expect(await c.reconcile(), SwapOutcome.fenced);
          expect(second, isNotNull);
          expect(c.busy, true);
          final active = c.pending!;
          expect(active.canonical, command.canonical);
          if (next == 'retry') expect(active.state, SwapSubmission.submitting);
          final receipt = x.accept(command.route, command.body);
          held.complete(
            next == 'retry'
                ? h.response(receipt)
                : h.response({
                    'items': [receipt],
                    'nextCursor': null,
                  }),
          );
          expect(await second, SwapOutcome.confirmed);
          expect(c.pending, isNull);
          expect(c.lastConfirmed!.json['operationId'], command.operationId);
        },
      );
    }

    for (final path in [
      'confirmed',
      'rejected',
      'uncertain',
      'reconciliationRequired',
    ]) {
      test(
        'B3A-01 $kind $path submission completion rechecks its owner',
        () async {
          final x = path == 'reconciliationRequired'
              ? await uncertain(kind)
              : await h.setup(kind: kind);
          final c = x.controller;
          if (path == 'uncertain') {
            x.postError = http.ClientException('Unknown');
          }
          if (path == 'rejected' || path == 'reconciliationRequired') {
            x.postError = null;
            x.postStatus = 403;
          }
          var changed = false;
          void listener() {
            if (!changed &&
                !c.busy &&
                (c.error != null || c.lastConfirmed != null)) {
              changed = true;
              replaceContext(x, 'context');
            }
          }

          c.addListener(listener);
          final outcome = await (path == 'reconciliationRequired'
              ? c.retry()
              : x.invoke(kind));
          c.removeListener(listener);
          expect(changed, true);
          expect(outcome, SwapOutcome.fenced);
          expectCleared(c);
        },
      );
    }

    for (final route in ['/context', '/organization']) {
      for (final change in [
        'context',
        'denied-context',
        'location',
        'invalid',
      ]) {
        test(
          'B3A-01 old platform $route for $kind cannot reverse $change invalidation',
          () async {
            final x = h.SwapHarness(
              role: kind == 'offer' ? 'recipient' : 'manager',
              self: kind == 'offer',
              state: kind == 'offer' ? 'requested' : 'confirmed',
              stage: kind == 'offer' ? 1 : 3,
            );
            addTearDown(x.dispose);
            final session = SessionController(x.auth, now: () => x.auth.now);
            final api = HeldBootstrapApi(x.api, route),
                platform = PlatformController(session, api);
            final c = ShiftSwapController(
              session,
              platform,
              api,
              self: kind == 'offer',
            );
            addTearDown(() {
              c.dispose();
              platform.dispose();
              session.dispose();
            });
            await session.signIn(username: 'fixture', password: 'fixture');
            await api.dispatched.future;
            final context = await x.api.get('fixture', '/context');
            if (route == '/context') {
              platform.context = PlatformContextResponse.fromJson(context);
            }
            await c.select(x.id);
            if (kind == 'offer') {
              await c.loadCounterparts();
              await c.chooseCounterpart(swapId(40));
            }
            x.postError = http.ClientException('Unknown');
            expect(await c.act(kind), SwapOutcome.uncertain);
            final raw = h.copy(context);
            if (change == 'denied-context') {
              raw['role'] = 'viewer';
              raw['permissions'] = <String>[];
            }
            if (change == 'location') raw['locationId'] = swapId(13);
            platform.context = change == 'invalid'
                ? null
                : PlatformContextResponse.fromJson(raw);
            final identity = platform.contextIdentity,
                before = snapshot(c),
                calls = api.routes.length;
            var notifications = 0;
            c.addListener(() => notifications++);
            api.hold.complete(
              route == '/context'
                  ? context
                  : await x.api.get('fixture', '/organization'),
            );
            await settle();
            expect(platform.contextIdentity, same(identity));
            expect(snapshot(c), before);
            expect(notifications, 0);
            expect(platform.isBusy, false);
            expect(platform.error, isNull);
            expect(platform.organization, isNull);
            expect(api.routes.length, calls);
            expectCleared(c);
          },
        );
      }
    }
  }

  test(
    'B3A-01 context publication callback fences old organization dispatch',
    () async {
      final x = h.SwapHarness();
      addTearDown(x.dispose);
      final session = SessionController(x.auth, now: () => x.auth.now);
      final api = HeldBootstrapApi(x.api, '/never'),
          platform = PlatformController(session, api);
      final c = ShiftSwapController(session, platform, api);
      addTearDown(() {
        c.dispose();
        platform.dispose();
        session.dispose();
      });
      var changed = false;
      void listener() {
        if (!changed && platform.context != null) {
          changed = true;
          final raw = platform.context!.toJson()..['permissions'] = <String>[];
          platform.context = PlatformContextResponse.fromJson(raw);
        }
      }

      platform.addListener(listener);
      await session.signIn(username: 'fixture', password: 'fixture');
      await settle();
      platform.removeListener(listener);
      expect(changed, true);
      expect(platform.context!.permissions, isEmpty);
      expect(api.routes, ['/context']);
      expect(platform.organization, isNull);
      expect(platform.isBusy, false);
      expect(c.canRead, false);
      expectCleared(c);
    },
  );
}
