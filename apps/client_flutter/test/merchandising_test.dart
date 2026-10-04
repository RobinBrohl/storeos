import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/merchandising_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/merchandising_section.dart';

const company = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222',
    resource = '33333333-3333-4333-8333-333333333333';
Map<String, dynamic> get fixtureJson => {
  'id': resource,
  'locationId': location,
  'name': 'Theke',
  'kind': 'counter',
  'status': 'active',
  'version': 1,
  'currentAssignmentId': null,
};
void seed(MerchandisingController c) {
  c.fixture = FixtureDto.fromJson(fixtureJson);
  c.planogram = PlanogramDto.fromJson({
    'id': resource,
    'status': 'active',
    'version': 2,
  });
  c.revision = RevisionDto.fromJson({
    'id': resource,
    'planogramId': resource,
    'status': 'draft',
    'revisionNumber': 1,
    'content': {'title': 'Layout', 'zones': []},
  });
  c.editing = c.revision!.content;
}

Future<(SessionController, PlatformController, MerchandisingController)> _setup(
  _Session auth,
  _Api api,
) async {
  final session = SessionController(auth);
  final platform = PlatformController(session, api);
  final c = MerchandisingController(session, platform, api);
  await session.signIn(username: 'admin', password: 'password');
  return (session, platform, c);
}

void main() {
  for (final role in ['employee', 'admin']) {
    for (final status in ['available', 'unavailable']) {
      testWidgets(
        '$role retains full assigned instruction with Stock $status',
        (tester) async {
          final auth = _Session(), api = _Api(role: role);
          final (s, p, c) = await _setup(auth, api);
          final layout = {
            'fixture': fixtureJson,
            'assignment': {
              'id': resource,
              'fixtureId': resource,
              'revisionId': resource,
              'appliedVersion': 2,
            },
            'revision': {
              'id': resource,
              'planogramId': resource,
              'status': 'published',
              'revisionNumber': 1,
              'content': LayoutContent(
                title: 'Assigned instruction',
                zones: [
                  LayoutZone(
                    id: company,
                    label: 'Zone Süd',
                    placements: [
                      LayoutPlacement(
                        id: resource,
                        articleId: resource,
                        facings: 3,
                      ),
                    ],
                  ),
                ],
              ).toJson(),
            },
            'articles': [
              {
                'id': resource,
                'name': 'Brot',
                'sku': 'A',
                'unit': 'kg',
                'isActive': true,
                'assortmentIsActive': true,
                'stock': status == 'available'
                    ? {'quantity': '12.5', 'stockUnit': 'kg'}
                    : null,
              },
            ],
            'stockContextStatus': status,
            'queriedAt': '2026-10-04T12:00:00Z',
            'historical': false,
          };
          api.reads['${c.fixtureRoot}/$resource/layout'] = layout;
          await c.openFixture(FixtureDto.fromJson(fixtureJson));
          expect(c.error, isNull);
          expect(c.view!.stockContextStatus.name, status);
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(body: MerchandisingSection(controller: c)),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('Assigned instruction'), findsOneWidget);
          expect(find.text('Zone Süd'), findsOneWidget);
          expect(find.text('1. Brot'), findsOneWidget);
          expect(find.textContaining('Facings 3'), findsOneWidget);
          expect(
            find.textContaining(
              status == 'available'
                  ? 'Bestand 12.5 kg'
                  : 'Bestandsdaten derzeit nicht verfügbar',
            ),
            findsOneWidget,
          );
          expect(find.textContaining('Kein Bestand erfasst'), findsNothing);
          expect(find.textContaining('Bestand 0'), findsNothing);
          expect(find.text('Zugewiesenes Layout drucken'), findsOneWidget);
          await tester.pumpWidget(const SizedBox());
          c.dispose();
          p.dispose();
          s.dispose();
        },
      );
    }
  }
  test(
    'duplicate publish guards synchronously and uncertain exact retry retains immutable payload',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      api.hold = Completer();
      final first = c.publish();
      final pending = c.pending!;
      expect(await c.publish(), LayoutCommandOutcome.busy);
      expect(api.bodies, hasLength(1));
      api.hold!.completeError(
        const StoreApiException('network_unavailable', 'lost'),
      );
      expect(await first, LayoutCommandOutcome.uncertain);
      expect(c.pending, same(pending));
      api.hold = null;
      api.fail = const StoreApiException('timeout', 'lost');
      expect(await c.retryPending(), LayoutCommandOutcome.uncertain);
      expect(api.bodies.last, pending.body);
      expect(c.pending, same(pending));
    },
  );
  for (final replacement in ['admin', 'other']) {
    test(
      'replacement $replacement fences command and stale result while status held',
      () async {
        final auth = _Session(), api = _Api();
        final (s, p, c) = await _setup(auth, api);
        addTearDown(() {
          c.dispose();
          p.dispose();
          s.dispose();
        });
        seed(c);
        api.hold = Completer();
        final first = c.publish();
        auth.gate = Completer();
        final login = s.signIn(username: replacement, password: 'password');
        await auth.started.future;
        expect(c.pending, isNull);
        expect(c.revision, isNull);
        expect(await c.retryPending(), LayoutCommandOutcome.fenced);
        api.hold!.completeError(
          const StoreApiException('timeout', 'old result'),
        );
        expect(await first, LayoutCommandOutcome.fenced);
        expect(c.error, isNull);
        auth.gate!.complete();
        await login;
      },
    );
  }
  test(
    'uncertain save requires authoritative review and preserves draft input',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      c.setEditing(LayoutContent(title: 'Changed', zones: []));
      api.fail = const StoreApiException('timeout', 'lost');
      expect(await c.saveDraft(), LayoutCommandOutcome.uncertain);
      expect(c.pending, isNull);
      expect(c.needsReview, true);
      expect(c.editing!.title, 'Changed');
      expect(await c.saveDraft(), LayoutCommandOutcome.busy);
    },
  );
  for (final status in [413, 415]) {
    test('$status is a definitive publish rejection', () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      api.fail = StoreApiException(
        'http_$status',
        'rejected',
        statusCode: status,
      );
      expect(await c.publish(), LayoutCommandOutcome.rejected);
      expect(c.pending, isNull);
    });
  }
  test(
    'assignment duplicate guard and uncertain retry preserve operation identity',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      api.hold = Completer();
      final first = c.assign(c.revision!);
      final command = c.pending!;
      expect(await c.assign(c.revision!), LayoutCommandOutcome.busy);
      expect(api.bodies.length, 1);
      api.hold!.completeError(const StoreApiException('timeout', 'lost'));
      expect(await first, LayoutCommandOutcome.uncertain);
      api.hold = null;
      api.fail = const StoreApiException('timeout', 'lost');
      expect(await c.retryPending(), LayoutCommandOutcome.uncertain);
      expect(api.bodies.last, command.body);
      expect(c.pending, same(command));
    },
  );
  test(
    'assignment result and pending identity are fenced during held session replacement',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      api.hold = Completer();
      final first = c.assign(c.revision!);
      auth.gate = Completer();
      final login = s.signIn(username: 'other', password: 'password');
      await auth.started.future;
      expect(c.pending, isNull);
      expect(c.fixture, isNull);
      api.hold!.complete({});
      expect(await first, LayoutCommandOutcome.fenced);
      expect(c.notice, isNull);
      auth.gate!.complete();
      await login;
    },
  );
  test(
    'stale save preserves input and blocks another write until review',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      c.setEditing(LayoutContent(title: 'Retained', zones: []));
      api.fail = const StoreApiException(
        'stale_version',
        'Changed',
        statusCode: 409,
      );
      expect(await c.saveDraft(), LayoutCommandOutcome.rejected);
      expect(c.editing!.title, 'Retained');
      expect(c.needsReview, true);
      expect(await c.publish(), LayoutCommandOutcome.busy);
    },
  );
  test(
    'invalid facings block save; removing the placement clears its issue',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      c.setInputIssue(resource, true);
      expect(await c.saveDraft(), LayoutCommandOutcome.rejected);
      expect(api.bodies, isEmpty);
      c.setEditing(LayoutContent(title: 'Valid', zones: []));
      expect(c.inputIssues, isEmpty);
    },
  );
  test(
    'assignment_changed print rejection requires authoritative reload',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      seed(c);
      api.getFailure = const StoreApiException(
        'assignment_changed',
        'Reload',
        statusCode: 409,
      );
      expect(await c.printView(resource), isNull);
      expect(c.error, contains('assignment_changed'));
    },
  );
  testWidgets(
    'fixture creation retains local workflow and client resource UUID',
    (tester) async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      api.reply = fixtureJson;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MerchandisingSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixture anlegen'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).first, 'Theke');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(api.bodies.single['name'], 'Theke');
      expect(merchandisingId(api.bodies.single['id']), isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'employee displays missing, zero, divergence and deactivation without edits',
    (tester) async {
      final auth = _Session(), api = _Api(role: 'employee');
      final (s, p, c) = await _setup(auth, api);
      seed(c);
      c.planogram = null;
      c.revision = null;
      c.editing = null;
      c.view = LayoutViewDto.fromJson({
        'fixture': fixtureJson,
        'assignment': {
          'id': resource,
          'fixtureId': resource,
          'revisionId': resource,
          'appliedVersion': 2,
        },
        'revision': {
          'id': resource,
          'planogramId': resource,
          'revisionNumber': 1,
          'status': 'published',
          'content': LayoutContent(
            title: 'Assigned',
            zones: [
              LayoutZone(
                id: company,
                label: 'Zone',
                placements: [
                  LayoutPlacement(id: resource, articleId: resource),
                  LayoutPlacement(id: location, articleId: location),
                ],
              ),
            ],
          ).toJson(),
        },
        'articles': [
          {
            'id': resource,
            'name': 'Zero',
            'sku': 'A',
            'unit': 'Stk',
            'isActive': false,
            'assortmentIsActive': false,
            'stock': {'quantity': '0', 'stockUnit': 'kg'},
          },
          {
            'id': location,
            'name': 'Missing',
            'sku': 'B',
            'unit': 'kg',
            'isActive': true,
            'assortmentIsActive': true,
            'stock': null,
          },
        ],
        'stockContextStatus': 'available',
        'queriedAt': '2026-10-04T12:00:00Z',
        'historical': false,
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MerchandisingSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Bestand 0 kg'), findsOneWidget);
      expect(find.textContaining('Kein Bestand erfasst'), findsOneWidget);
      expect(find.textContaining('Artikeleinheit abweichend'), findsOneWidget);
      expect(
        find.textContaining('Artikel oder Sortiment inaktiv'),
        findsOneWidget,
      );
      expect(find.text('Zugewiesenes Layout drucken'), findsOneWidget);
      expect(find.text('Entwurf speichern'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
      s.dispose();
    },
  );
  testWidgets(
    'authoritative reload resets unsaved fields even at unchanged version',
    (tester) async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      seed(c);
      final chosen = c.planogram!;
      api.reads['${c.pgRoot}/$resource'] = chosen.json;
      api.reads['${c.pgRoot}/$resource/revisions'] = {
        'items': [c.revision!.json],
        'nextCursor': null,
      };
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MerchandisingSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Layout-Titel');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Unconfirmed');
      await tester.pump();
      expect(c.editing!.title, 'Unconfirmed');
      await c.selectPlanogram(chosen);
      await tester.pump();
      expect(c.planogram!.version, chosen.version);
      expect(c.editing!.title, 'Layout');
      expect(find.text('Unconfirmed'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
      s.dispose();
    },
  );
  test(
    'synchronous session end cannot recreate pending identity before dispatch',
    () async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      seed(c);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
      });
      Future<void>? logout;
      void endSession() {
        if (c.busy && logout == null) {
          logout = s.signOut();
        }
      }

      c.addListener(endSession);
      expect(await c.publish(), LayoutCommandOutcome.fenced);
      expect(api.bodies, isEmpty);
      expect(c.pending, isNull);
      c.removeListener(endSession);
      await logout;
    },
  );
  testWidgets('employee empty state has no management controls', (
    tester,
  ) async {
    final auth = _Session(), api = _Api(role: 'employee');
    final (s, p, c) = await _setup(auth, api);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MerchandisingSection(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Noch keine Fixtures vorhanden.'), findsOneWidget);
    expect(find.text('Fixture anlegen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    p.dispose();
    s.dispose();
  });
  testWidgets(
    'draft editor exposes zones, accessible reorder and separate publish',
    (tester) async {
      final auth = _Session(), api = _Api();
      final (s, p, c) = await _setup(auth, api);
      seed(c);
      c.editing = LayoutContent(
        title: 'Layout',
        zones: [
          LayoutZone(id: layoutUuid(), label: 'Erste', placements: []),
          LayoutZone(id: layoutUuid(), label: 'Zweite', placements: []),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: MerchandisingSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Zone hinzufügen'), findsOneWidget);
      expect(find.text('Entwurf speichern'), findsOneWidget);
      expect(find.text('Veröffentlichen'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Zone nach unten').first);
      await tester.tap(find.byTooltip('Zone nach unten').first);
      await tester.pump();
      expect(c.editing!.zones.first.label, 'Zweite');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
      s.dispose();
    },
  );
}

class _Session implements StoreApi {
  int generation = 0;
  Completer<void>? gate;
  Completer<void> started = Completer<void>();
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
    if (gate != null) {
      if (!started.isCompleted) started.complete();
      await gate!.future;
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

/// Transport recorder only. Durable replay semantics are proved in PostgreSQL.
class _Api implements PlatformApi {
  _Api({this.role = 'admin'});
  final String role;
  final List<Map<String, dynamic>> bodies = [];
  Completer<Map<String, dynamic>>? hold;
  StoreApiException? fail, getFailure;
  Map<String, dynamic>? reply;
  final reads = <String, Map<String, dynamic>>{};
  @override
  Future<Map<String, dynamic>> post(
    String t,
    String route,
    Map<String, dynamic> body,
  ) async {
    bodies.add(body);
    if (hold != null) return hold!.future;
    if (fail != null) throw fail!;
    return reply ?? {};
  }

  @override
  Future<Map<String, dynamic>> get(
    String t,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': t.split(':').first,
        'companyId': company,
        'locationId': location,
        'role': role,
        'permissions': [
          if (role == 'admin') 'merchandising.layouts.manage',
          if (role == 'admin') 'merchandising.layouts.publish',
          'merchandising.layouts.read',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Test', 'version': 1},
        'locations': [
          {'id': location, 'name': 'Home', 'version': 1},
        ],
      };
    }
    if (getFailure != null) throw getFailure!;
    if (reads.containsKey(route)) return reads[route]!;
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }
}
