import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/purchasing_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/purchasing_section.dart';

const company = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222',
    order = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    supplier = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    article = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    line = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
Map<String, dynamic> get document => {
  'id': order,
  'companyId': company,
  'locationId': location,
  'reference': 'Literal <script> 😀',
  'status': 'draft',
  'version': 2,
  'supplier': {
    'id': supplier,
    'version': 1,
    'name': 'Supplier <a href="https://invalid.example"> 😀',
    'orderingReference': null,
  },
  'lines': [
    {
      'id': line,
      'position': 1,
      'articleId': article,
      'articleVersion': 1,
      'sku': 'SKU',
      'name': 'Article',
      'unit': 'kg',
      'quantity': '2.500',
    },
  ],
  'createdBy': order,
  'createdAt': '2026-10-11T00:00:00Z',
  'changedBy': order,
  'changedAt': '2026-10-11T00:00:00Z',
  'issuedBy': null,
  'issuedAt': null,
  'terminalBy': null,
  'terminalAt': null,
  'reason': null,
};

class Auth implements StoreApi {
  int generation = 0;
  Completer<void>? hold;
  final started = Completer<void>();
  @override
  Future<SessionResponse> login(LoginRequest r) async => SessionResponse(
    token: '${r.username}:${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: r.username,
      username: r.username,
      companyId: company,
      locationId: location,
    ),
  );
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    if (hold != null) {
      if (!started.isCompleted) started.complete();
      await hold!.future;
    }
    return const SystemStatusResponse(companyId: company, locationId: location);
  }

  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

class Api implements PurchasingApi {
  final bodies = <Map<String, dynamic>>[], routes = <String>[];
  Completer<Map<String, dynamic>>? hold, readHold;
  StoreApiException? failure, readFailure;
  bool refreshFail = false;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': token.split(':').first,
        'companyId': company,
        'locationId': location,
        'role': 'admin',
        'permissions': [
          'purchasing.suppliers.manage',
          'purchasing.orders.manage',
          'purchasing.orders.issue',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Test', 'version': 1},
        'locations': [
          {'id': location, 'companyId': company, 'name': 'Home', 'version': 1},
        ],
      };
    }
    if (readHold != null) return readHold!.future;
    if (readFailure != null) throw readFailure!;
    if (route.endsWith('/$order')) {
      if (refreshFail) {
        throw const StoreApiException(
          'database_unavailable',
          'Unavailable',
          statusCode: 503,
        );
      }
      return document;
    }
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }

  Future<Map<String, dynamic>> write(
    String route,
    Map<String, dynamic> body,
  ) async {
    routes.add(route);
    bodies.add(body);
    if (hold != null) return hold!.future;
    if (failure != null) throw failure!;
    return {'order': document, 'replayed': false};
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) => write(route, body);
  @override
  Future<Map<String, dynamic>> put(
    String token,
    String route,
    Map<String, dynamic> body,
  ) => write(route, body);
}

Future<(SessionController, PlatformController, PurchasingController)> setup(
  Auth auth,
  Api api, {
  String Function()? ids,
}) async {
  final s = SessionController(auth),
      p = PlatformController(s, api),
      c = PurchasingController(
        s,
        p,
        api,
        idFactory: ids ?? () => 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
      );
  await s.signIn(username: 'admin', password: 'test');
  await ready(p);
  await c.select(order);
  addTearDown(() {
    c.dispose();
    p.dispose();
    s.dispose();
  });
  return (s, p, c);
}

Future<void> ready(PlatformController p) async {
  final done = Completer<void>();
  void changed() {
    if (p.organization != null && !p.isBusy && !done.isCompleted) {
      done.complete();
    }
  }

  p.addListener(changed);
  changed();
  await done.future;
  p.removeListener(changed);
}

void main() {
  test(
    'guard precedes IDs; pending route, nested lines and exact quantity stay frozen',
    () async {
      final api = Api()..hold = Completer();
      var ids = 0;
      final (_, _, c) = await setup(
        Auth(),
        api,
        ids: () {
          ids++;
          return 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
        },
      );
      c.quantity(line, '12');
      final submitting = c.save();
      expect(await c.save(), PurchasingOutcome.busy);
      expect(ids, 1);
      final pending = c.pending!;
      expect(
        () => pending.body['lines'][0]['quantity'] = '99',
        throwsUnsupportedError,
      );
      expect(
        () => (pending.body['lines'] as List).clear(),
        throwsUnsupportedError,
      );
      c.lines[0]['quantity'] = '99';
      c.reference = 'different';
      api.hold!.completeError(const StoreApiException('network', 'Lost'));
      expect(await submitting, PurchasingOutcome.uncertain);
      expect(c.pending, same(pending));
      api.hold = null;
      expect(await c.retry(), PurchasingOutcome.confirmed);
      expect(api.bodies[1], same(api.bodies[0]));
      expect(api.routes[1], api.routes[0]);
      expect(api.bodies.last['lines'][0]['quantity'], '12.000');
      expect(ids, 1);
    },
  );
  for (final status in [400, 403, 404, 409, 413, 415, 422]) {
    test(
      'definitive $status preserves editor and permits new explicit command',
      () async {
        final api = Api()
          ..failure = StoreApiException(
            'rejected',
            'Review input',
            statusCode: status,
          );
        final (_, _, c) = await setup(Auth(), api);
        c.quantity(line, '12');
        expect(await c.save(), PurchasingOutcome.rejected);
        expect(c.pending, isNull);
        expect(c.lines[0]['quantity'], '12');
        expect(c.detail!['version'], 2);
        expect(c.error, contains('rejected'));
      },
    );
  }
  for (final status in [500, 503]) {
    test('unconfirmed $status retains exact pending command', () async {
      final api = Api()
        ..failure = StoreApiException(
          'unconfirmed',
          'Unknown',
          statusCode: status,
        );
      final (_, _, c) = await setup(Auth(), api);
      expect(await c.save(), PurchasingOutcome.uncertain);
      expect(c.pending, isNotNull);
      expect(c.locked, true);
    });
  }
  test(
    'confirmation survives failed refresh while actionable current detail is cleared',
    () async {
      final api = Api();
      final (_, _, c) = await setup(Auth(), api);
      api.refreshFail = true;
      expect(await c.save(), PurchasingOutcome.confirmed);
      expect(c.lastConfirmed!['order']['version'], 2);
      expect(c.detail, isNull);
      expect(c.lines, isEmpty);
      expect(c.refreshWarning, contains('Reload authoritative'));
      expect(c.pending, isNull);
    },
  );
  for (final username in ['admin', 'different']) {
    test(
      'delayed dispatched result fenced on $username session replacement',
      () async {
        final api = Api();
        final (s, p, c) = await setup(Auth(), api);
        api.hold = Completer();
        final result = c.save();
        await s.signIn(username: username, password: 'test');
        await ready(p);
        expect(c.pending, isNull);
        expect(c.detail, isNull);
        expect(c.reference, isEmpty);
        api.hold!.complete({'order': document, 'replayed': false});
        expect(await result, PurchasingOutcome.fenced);
        expect(c.lastConfirmed, isNull);
      },
    );
    test(
      'held login status already clears pending command on $username replacement',
      () async {
        final auth = Auth(), api = Api();
        final (s, p, c) = await setup(auth, api);
        api.failure = const StoreApiException('network', 'Lost');
        expect(await c.save(), PurchasingOutcome.uncertain);
        auth.hold = Completer();
        final signingIn = s.signIn(username: username, password: 'test');
        await auth.started.future;
        final held = auth.hold!;
        expect(c.pending, isNull);
        expect(c.detail, isNull);
        expect(await c.retry(), PurchasingOutcome.busy);
        expect(api.bodies, hasLength(1));
        held.complete();
        await signingIn;
        await ready(p);
      },
    );
    test('delayed GET cannot repopulate $username replaced session', () async {
      final api = Api();
      final (s, p, c) = await setup(Auth(), api);
      api.readHold = Completer();
      final reading = c.select(order);
      await s.signIn(username: username, password: 'test');
      await ready(p);
      api.readHold!.complete(document);
      await reading;
      expect(c.detail, isNull);
      expect(c.lines, isEmpty);
    });
    testWidgets(
      'mounted fields and reason dialog clear on $username replacement',
      (t) async {
        final api = Api(), result = await t.runAsync(() => setup(Auth(), api));
        final (s, p, c) = result!;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(body: PurchasingSection(controller: c)),
          ),
        );
        await t.pumpAndSettle();
        Future<void> show(Finder f) async {
          await t.scrollUntilVisible(
            f,
            350,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(f);
        }

        final name = find.byKey(const Key('purchasing-supplier-name'));
        await show(name);
        await t.enterText(name, 'Private supplier');
        final cancel = find.widgetWithText(OutlinedButton, 'Cancel order');
        await show(cancel);
        await t.tap(cancel);
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('purchasing-terminal-reason')),
          'Private reason',
        );
        await t.runAsync(() async {
          await s.signIn(username: username, password: 'test');
          await ready(p);
        });
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(
                find.byKey(const Key('purchasing-terminal-reason')),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(
          t
              .widget<TextButton>(
                find.byKey(const Key('purchasing-terminal-confirm')),
              )
              .onPressed,
          isNull,
        );
        expect(c.reference, isEmpty);
        expect(c.lines, isEmpty);
        expect(c.lastConfirmed, isNull);
        expect(c.selectedSupplier, isNull);
        await t.tap(find.widgetWithText(TextButton, 'Back'));
        await t.pumpAndSettle();
        await show(name);
        expect(t.widget<TextField>(name).controller!.text, isEmpty);
      },
    );
  }
  testWidgets(
    'uncertain retry remains actionable while other writes are disabled',
    (t) async {
      final api = Api(), r = await t.runAsync(() => setup(Auth(), api));
      final (_, _, c) = r!;
      api.failure = const StoreApiException('network', 'Lost');
      await c.save();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingSection(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('purchasing-retry')))
            .onPressed,
        isNotNull,
      );
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('purchasing-new')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'cached fields and action callbacks cannot change a replacement session',
    (t) async {
      final result = await t.runAsync(() => setup(Auth(), Api()));
      final (s, p, c) = result!;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PurchasingSection(controller: c)),
        ),
      );
      await t.pumpAndSettle();
      final oldNew = t
          .widget<OutlinedButton>(find.byKey(const Key('purchasing-new')))
          .onPressed!;
      final field = find.byKey(const Key('purchasing-reference'));
      await t.scrollUntilVisible(
        field,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      final oldField = t.widget<TextField>(field).onChanged!;
      final review = find.byKey(const Key('purchasing-review'));
      await t.scrollUntilVisible(
        review,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      final oldReview = t.widget<CheckboxListTile>(review).onChanged!;
      await t.runAsync(() async {
        await s.signIn(username: 'admin', password: 'test');
        await ready(p);
      });
      await t.pumpAndSettle();
      c.reference = 'Current session';
      final revision = c.editorRevision;
      oldNew();
      oldField('Old private reference');
      oldReview(true);
      expect(c.reference, 'Current session');
      expect(c.editorRevision, revision);
      expect(c.reviewed, false);
      expect(c.pending, isNull);
    },
  );
}
