import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/stock_count_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/stock_count_section.dart';

const id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
Map<String, dynamic> detail({bool self = false}) => {
  'id': id,
  'locationId': id,
  'employeeId': id,
  'purpose': 'Physical <script>literal</script>',
  'status': 'open',
  'version': 1,
  'openedAt': '2030-01-01T00:00:00Z',
  if (!self) ...{
    'createdBy': id,
    'precedingCountId': null,
    'approval': null,
    'cancellation': null,
  },
  'lines': [
    {
      'id': id,
      'articleId': id,
      'position': 1,
      'sku': 'FLOUR',
      'name': 'Flour',
      'barcode': null,
      'stockUnit': 'kg',
      'round': {
        'id': id,
        'number': 1,
        'current': true,
        'observation': null,
        if (!self) ...{
          'baselineQuantity': '10',
          'baselineVersion': 1,
          'stockUnit': 'kg',
          'capturedAt': '2030-01-01T00:00:00Z',
          'provenance': 'open',
          'requestedBy': id,
          'reason': null,
          'discrepancy': null,
        },
      },
      if (!self) ...{
        'stockLevelId': id,
        'currentStock': {
          'quantity': '12',
          'version': 2,
          'stockUnit': 'kg',
          'updatedAt': '2030-01-01T01:00:00Z',
        },
        'stale': true,
        'discrepancy': null,
        'outcome': null,
      },
    },
  ],
};
void main() {
  for (final roles in [
    (before: false, after: false, username: 'account'),
    (before: false, after: true, username: 'employeeB'),
    (before: true, after: false, username: 'managerB'),
    (before: true, after: true, username: 'account'),
  ]) {
    testWidgets(
      'history resident state clears ${roles.before ? 'employee' : 'manager'} to ${roles.after ? 'employee' : 'manager'} ${roles.username} replacement with outstanding page',
      (tester) async {
        final f = await Fixture.create(self: roles.before);
        addTearDown(f.dispose);
        f.api.historyPages = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StockCountSection(controller: f.c)),
          ),
        );
        await tester.pumpAndSettle();
        await f.c.select(id);
        await tester.pumpAndSettle();
        final historyButton = find.text(
          roles.before ? 'Eigene Runden' : 'Rundenverlauf',
        );
        await tester.ensureVisible(historyButton);
        await tester.tap(historyButton);
        await tester.pumpAndSettle();
        final dialogFinder = find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_HistoryDialog',
        );
        final dynamic state = tester.state(dialogFinder);
        final List oldRows = state.rows as List;
        expect(oldRows, hasLength(2));
        if (!roles.before) {
          expect(oldRows.first['baselineQuantity'], '10');
          expect(oldRows.first['baselineVersion'], 1);
          expect(oldRows.first.containsKey('discrepancy'), true);
        }
        expect(state.cursor, 'old-principal-page');
        f.api.failHistory = true;
        await tester.tap(find.text('Weitere Runden'));
        await tester.pumpAndSettle();
        expect(state.error, isNotNull);
        f.api.failHistory = false;
        f.api.gate = Completer<void>();
        f.api.started = Completer<void>();
        await tester.tap(find.text('Weitere Runden'));
        await tester.pump();
        await f.api.started!.future;
        expect(state.busy, true);
        final oldTokens = [...f.api.tokens];
        final oldIdentity = f.session.sessionIdentity;
        f.api.self = roles.after;
        await f.session.signIn(username: roles.username, password: 'password');
        await f.ready();
        expect(identical(oldIdentity, f.session.sessionIdentity), false);
        // Inspect before a render: hiding the old maps cannot satisfy this proof.
        expect(oldRows, isEmpty);
        expect(state.rows, isEmpty);
        expect(state.cursor, isNull);
        expect(state.error, isNull);
        expect(state.busy, false);
        f.api.gate!.complete();
        f.api.gate = null;
        await tester.pumpAndSettle();
        expect(state.rows, isEmpty);
        expect(state.cursor, isNull);
        expect(state.error, isNull);
        expect(state.busy, false);
        expect(
          f.api.tokens
              .skip(oldTokens.length)
              .every((t) => t.startsWith('${roles.username}:')),
          true,
        );
        expect(find.textContaining('Eingefrorene Basis'), findsNothing);
        await tester.tap(find.text('Schließen'));
        await tester.pumpAndSettle();
        final current = StockCountController(
          f.session,
          f.platform,
          f.api,
          self: roles.after,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: StockCountSection(controller: current)),
          ),
        );
        await tester.pumpAndSettle();
        await current.select(id);
        await tester.pumpAndSettle();
        final reopened = find.text(
          roles.after ? 'Eigene Runden' : 'Rundenverlauf',
        );
        await tester.ensureVisible(reopened);
        await tester.tap(reopened);
        await tester.pumpAndSettle();
        final dynamic newState = tester.state(dialogFinder);
        expect(newState.rows, hasLength(2));
        expect(f.api.historyTokens.last, startsWith('${roles.username}:'));
        if (roles.after) {
          for (final row in newState.rows as List) {
            expect(row.containsKey('baselineQuantity'), false);
            expect(row.containsKey('baselineVersion'), false);
            expect(row.containsKey('discrepancy'), false);
          }
        }
        await tester.pumpWidget(const SizedBox());
        current.dispose();
        f.dispose();
      },
    );
  }
  for (final self in [true, false]) {
    for (final replacement in ['account', 'different']) {
      for (final action in ['list', 'detail', 'choices', 'history', 'write']) {
        test(
          '${self ? 'employee' : 'manager'} $action fences $replacement session replacement',
          () async {
            final f = await Fixture.create(self: self);
            addTearDown(f.dispose);
            await f.c.select(id);
            f.api.gate = Completer<void>();
            f.api.started = Completer<void>();
            final old = switch (action) {
              'list' => f.c.load(),
              'detail' => f.c.select(id),
              'choices' => self ? f.c.load() : f.c.choices(),
              'history' =>
                f.c.history(id, id).then<void>((_) {}).catchError((_) {}),
              _ =>
                self
                    ? f.c
                          .record(f.c.employeeDetail!.lines.single, '1', null)
                          .then<void>((_) {})
                    : f.c.approve().then<void>((_) {}),
            };
            await f.api.started!.future;
            final tokensBefore = [...f.api.tokens];
            await f.session.signIn(username: replacement, password: 'password');
            await f.ready();
            expect(f.c.managerDetail, isNull);
            expect(f.c.employeeDetail, isNull);
            expect(f.c.stockChoices, isNull);
            expect(f.c.assignees, isNull);
            expect(f.c.pending, isNull);
            f.api.gate!.complete();
            await old;
            expect(f.c.items, isNull);
            expect(f.c.managerDetail, isNull);
            expect(f.c.employeeDetail, isNull);
            expect(f.c.pending, isNull);
            expect(f.api.tokens, tokensBefore);
          },
        );
      }
    }
  }
  test(
    'uncertain command retains canonical deeply immutable route/body and exact retry',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.c.select(id);
      f.api.lose = true;
      expect(await f.c.recount([id], ' reason '), false);
      final pending = f.c.pending!;
      expect(pending.body['reason'], 'reason');
      expect(
        () => (pending.body['lineIds'] as List).add(id),
        throwsUnsupportedError,
      );
      expect(await f.c.cancel('different'), false);
      expect(f.api.bodies, hasLength(1));
      f.api.lose = false;
      expect(await f.c.retry(), true);
      expect(f.api.bodies.first, f.api.bodies.last);
      expect(f.c.pending, isNull);
    },
  );
  test(
    'confirmed command refresh failure never invites duplicate command',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.c.select(id);
      f.api.failRefresh = true;
      expect(await f.c.approve(), true);
      expect(f.c.lastConfirmed, isNotNull);
      expect(f.c.refreshError, isNotNull);
      expect(f.c.pending, isNull);
      expect(await f.c.retry(), false);
      expect(f.api.bodies, hasLength(1));
    },
  );
  test(
    'capability gates and duplicate submission block unsupported writes',
    () async {
      final f = await Fixture.create(deny: true);
      addTearDown(f.dispose);
      await f.c.load();
      await f.c.choices();
      expect(f.api.tokens, isEmpty);
      expect(await f.c.open(id, [id], 'purpose'), false);
    },
  );
  testWidgets(
    'blind employee UI renders literals and clears quantity/note after same-account replacement',
    (tester) async {
      final f = await Fixture.create(self: true);
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StockCountSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      await f.c.select(id);
      await tester.pumpAndSettle();
      expect(find.text('Physical <script>literal</script>'), findsOneWidget);
      expect(find.textContaining('Eingefrorene Basis'), findsNothing);
      expect(find.textContaining('Aktueller Bestand'), findsNothing);
      expect(find.textContaining('Abweichung'), findsNothing);
      await tester.enterText(find.byType(TextField).first, '9');
      await tester.enterText(find.byType(TextField).last, 'secret note');
      await f.session.signIn(username: 'account', password: 'password');
      await f.ready();
      await tester.pumpAndSettle();
      await f.c.select(id);
      await tester.pumpAndSettle();
      for (final field in tester.widgetList<TextField>(
        find.byType(TextField),
      )) {
        expect(field.controller!.text, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}

class Fixture {
  Fixture(this.session, this.platform, this.c, this.api);
  final SessionController session;
  final PlatformController platform;
  final StockCountController c;
  final Api api;
  static Future<Fixture> create({bool self = false, bool deny = false}) async {
    final api = Api(self, deny);
    final session = SessionController(Login());
    final p = PlatformController(session, api);
    final c = StockCountController(
      session,
      p,
      api,
      self: self,
      operationIdFactory: () => id,
    );
    final f = Fixture(session, p, c, api);
    await session.signIn(username: 'account', password: 'password');
    await f.ready();
    return f;
  }

  Future<void> ready() async {
    while (platform.isBusy) {
      await Future<void>.value();
    }
  }

  bool disposed = false;
  void dispose() {
    if (disposed) return;
    disposed = true;
    c.dispose();
    platform.dispose();
    session.dispose();
  }
}

class Login implements StoreApi {
  int generation = 0;
  @override
  Future<SessionResponse> login(LoginRequest r) async => SessionResponse(
    token: '${r.username}:${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: r.username,
      username: r.username,
      companyId: id,
      locationId: id,
    ),
  );
  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async => const SystemStatusResponse(companyId: id, locationId: id);
}

class Api implements PlatformApi {
  Api(this.self, this.deny);
  bool self;
  final bool deny;
  Completer<void>? gate, started;
  bool lose = false, failRefresh = false;
  bool historyPages = false, failHistory = false;
  final historyTokens = <String>[];
  final tokens = <String>[], bodies = <Map<String, dynamic>>[];
  Future<void> wait(String token) async {
    tokens.add(token);
    if (started != null && !started!.isCompleted) started!.complete();
    await gate?.future;
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
        'userId': token.split(':').first,
        'companyId': id,
        'locationId': id,
        'role': self ? 'employee' : 'admin',
        'permissions': deny
            ? ['context.read', 'organization.read']
            : [
                'context.read',
                'organization.read',
                if (!self) ...[
                  'stock.levels.manage',
                  'stock.counts.manage',
                  'stock.counts.approve',
                ],
                'stock.counts.self.read',
                'stock.counts.self.record',
              ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': id, 'name': 'Company', 'version': 1},
        'locations': [
          {'id': id, 'companyId': id, 'name': 'Location', 'version': 1},
        ],
      };
    }
    final responseSelf = self;
    await wait(token);
    if (failRefresh) throw const StoreApiException('timeout', 'refresh lost');
    if (route.endsWith('/rounds')) {
      historyTokens.add(token);
      if (failHistory) throw const StoreApiException('timeout', 'history lost');
      return {
        'items': [
          detail(self: responseSelf)['lines'][0]['round'],
          if (historyPages)
            <String, dynamic>{
              ...detail(self: responseSelf)['lines'][0]['round'],
              'number': 2,
            },
        ],
        'nextCursor': historyPages ? 'old-principal-page' : null,
      };
    }
    if (route.endsWith('/stock') || route.endsWith('/assignees')) {
      return {'items': [], 'nextCursor': null};
    }
    if (route.endsWith('/$id')) return detail(self: self);
    return {
      'items': [detail(self: self)..remove('lines')],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    await wait(token);
    bodies.add(jsonDecode(jsonEncode(body)) as Map<String, dynamic>);
    if (lose) {
      throw const StoreApiException('timeout', 'committed response lost');
    }
    return detail(self: self);
  }
}
