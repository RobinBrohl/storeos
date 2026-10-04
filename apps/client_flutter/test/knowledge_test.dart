import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/knowledge_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/knowledge_section.dart';

const company = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222';
const article = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    revision = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const literal = '# markdown\n<script>alert(1)</script>\n<a href="x">**\n  ä 😀';
Map<String, dynamic> articleJson({
  int version = 1,
  String status = 'active',
  String? draft = revision,
  String? current,
}) => {
  'id': article,
  'companyId': company,
  'version': version,
  'status': status,
  'activeDraftRevisionId': draft,
  'currentPublishedRevisionId': current,
  'createdAt': '2030-01-01T08:00:00Z',
  'updatedAt': '2030-01-01T08:00:00Z',
  'createdBy': 'admin',
  'retiredAt': status == 'retired' ? '2030-01-02T08:00:00Z' : null,
  'retiredBy': status == 'retired' ? 'admin' : null,
};
Map<String, dynamic> revisionJson({String status = 'draft', int number = 1}) =>
    {
      'id': revision,
      'companyId': company,
      'articleId': article,
      'revisionNumber': number,
      'status': status,
      'content': {'title': 'Closing', 'body': literal},
      'createdAt': '2030-01-01T08:00:00Z',
      'createdBy': 'admin',
      'publishedAt': status == 'published' ? '2030-01-01T09:00:00Z' : null,
      'publishedBy': status == 'published' ? 'admin' : null,
      'publishOperationId': status == 'published' ? company : null,
      'publishExpectedVersion': status == 'published' ? 1 : null,
      'publicationVersion': status == 'published' ? 2 : null,
      'discardedAt': status == 'discarded' ? '2030-01-01T09:00:00Z' : null,
      'discardedBy': status == 'discarded' ? 'admin' : null,
    };
Map<String, dynamic> get employeeJson => {
  'articleId': article,
  'revisionId': revision,
  'title': 'Closing',
  'body': literal,
  'revisionNumber': 1,
  'publishedAt': '2030-01-01T09:00:00Z',
};
Map<String, dynamic> get detailJson => {
  'article': articleJson(),
  'draft': revisionJson(),
  'currentPublished': null,
};
Future<(SessionController, PlatformController, KnowledgeController)> _setup(
  _Auth auth,
  _Api api,
) async {
  final s = SessionController(auth),
      p = PlatformController(s, api),
      c = KnowledgeController(s, p, api);
  final ready = Completer<void>();
  void loaded() {
    if (p.organization != null && !p.isBusy && !ready.isCompleted) {
      ready.complete();
    }
  }

  p.addListener(loaded);
  await s.signIn(username: 'admin', password: 'test');
  loaded();
  await ready.future;
  p.removeListener(loaded);
  addTearDown(() {
    c.dispose();
    p.dispose();
    s.dispose();
  });
  c.detail = WikiDetailDto.fromJson(detailJson);
  c.editing = c.detail!.draft!.content;
  c.selectedRevision = c.detail!.draft;
  return (s, p, c);
}

void main() {
  test(
    'search and bounded pagination retain query and append safe projections',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.reads[KnowledgeController.publicRoot] = {
        'items': [employeeJson],
        'nextCursor': article,
      };
      await c.search('%_\\');
      expect(c.query, '%_\\');
      expect(c.published, hasLength(1));
      api.reads[KnowledgeController.publicRoot] = {
        'items': [employeeJson],
        'nextCursor': null,
      };
      await c.search(c.query, more: true);
      expect(c.published, hasLength(2));
      expect(api.queries.last, {'q': '%_\\', 'after': article});
      await c.openInstruction(article);
      expect(c.instruction!.body, literal);
    },
  );
  test(
    'incomplete or invalid editing is retained and never dispatched',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      c.setEditing(WikiContent(title: 'T', body: 'x' * 8192));
      expect(await c.save(), KnowledgeOutcome.rejected);
      expect(api.bodies, isEmpty);
      expect(c.editing!.body.length, 8192);
      c.setEditing(const WikiContent(title: '', body: ''));
      expect(await c.save(), KnowledgeOutcome.confirmed);
    },
  );
  test(
    'publish cannot include unsaved editing; preview remains exact saved text',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      c.setEditing(const WikiContent(title: 'Changed', body: 'Changed'));
      expect(await c.publish(), KnowledgeOutcome.rejected);
      expect(api.bodies, isEmpty);
      expect(c.detail!.draft!.content.body, literal);
    },
  );
  for (final code in [400, 409, 413, 415]) {
    test(
      'definitive HTTP $code retains input and permits only safe reconciliation',
      () async {
        final api = _Api();
        final (_, _, c) = await _setup(_Auth(), api);
        c.setEditing(const WikiContent(title: 'Changed', body: 'Retain me'));
        api.failure = StoreApiException(
          code == 409 ? 'stale_version' : 'invalid_request',
          'Rejected',
          statusCode: code,
        );
        expect(await c.save(), KnowledgeOutcome.rejected);
        expect(c.editing!.body, 'Retain me');
        expect(c.pending, isNull);
        expect(c.needsReview, code == 409);
        if (code == 409) {
          api.failure = null;
          await c.reloadForReview();
          expect(c.editing!.body, 'Retain me');
          expect(await c.save(), KnowledgeOutcome.busy);
          c.acceptReviewedState();
          expect(c.editing!.body, literal);
        }
      },
    );
  }
  test(
    'lost publication retains immutable identity and duplicate submit is guarded',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.hold = Completer<Map<String, dynamic>>();
      final first = c.publish();
      final retained = c.pending!;
      expect(await c.publish(), KnowledgeOutcome.busy);
      expect(api.bodies, hasLength(1));
      expect(
        () => retained.body['expectedVersion'] = 9,
        throwsUnsupportedError,
      );
      api.hold!.completeError(const StoreApiException('timeout', 'Lost'));
      expect(await first, KnowledgeOutcome.uncertain);
      expect(identical(c.pending, retained), true);
      api.hold = null;
      api.failure = const StoreApiException(
        'http_408',
        'Gateway timeout',
        statusCode: 408,
      );
      expect(await c.retryPublication(), KnowledgeOutcome.uncertain);
      expect(identical(c.pending, retained), true);
      expect(api.bodies.last, retained.body);
      api.failure = null;
      api.reply = {
        'revision': revisionJson(status: 'published'),
        'replayed': true,
      };
      expect(await c.retryPublication(), KnowledgeOutcome.confirmed);
      expect(api.bodies.last, retained.body);
      expect(c.pending, isNull);
      expect(c.confirmedPublication!.replayed, true);
    },
  );
  test(
    'confirmed publication plus failed refresh remains confirmed with no write retry',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.reply = {
        'revision': revisionJson(status: 'published'),
        'replayed': false,
      };
      api.readFailure = const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
      expect(await c.publish(), KnowledgeOutcome.confirmed);
      expect(c.pending, isNull);
      expect(c.confirmedPublication, isNotNull);
      expect(c.refreshWarning, isNotNull);
      expect(await c.retryPublication(), KnowledgeOutcome.fenced);
      expect(api.bodies, hasLength(1));
    },
  );
  test(
    'ambiguous save requires reload and explicit review, never automatic rebase',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      c.setEditing(const WikiContent(title: 'Changed', body: 'Retain me'));
      api.failure = const StoreApiException('timeout', 'Lost');
      expect(await c.save(), KnowledgeOutcome.uncertain);
      expect(await c.save(), KnowledgeOutcome.busy);
      expect(c.pending!.kind, KnowledgeCommandKind.save);
      api.failure = null;
      await c.reloadForReview();
      expect(c.needsReview, true);
      expect(c.editing!.body, 'Retain me');
      c.acceptReviewedState();
      expect(c.needsReview, false);
      expect(c.editing!.body, literal);
    },
  );
  test(
    'creation keeps stable identities until authoritative reconciliation',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.failure = const StoreApiException('timeout', 'Lost');
      expect(await c.create(), KnowledgeOutcome.uncertain);
      final pending = c.pending!;
      expect(await c.create(), KnowledgeOutcome.busy);
      api.failure = null;
      api.reads['${KnowledgeController.manageRoot}/${pending.articleId}'] = {
        ...detailJson,
        'article': {...articleJson(), 'id': pending.articleId},
      };
      await c.reloadForReview();
      expect(c.pending, isNull);
      expect(c.reviewedReload, true);
      expect(c.detail!.article.id, pending.articleId);
    },
  );
  for (final actor in ['admin', 'other']) {
    test(
      'opaque replacement $actor with held status prevents old dispatch/results',
      () async {
        final auth = _Auth(), api = _Api();
        final (s, _, c) = await _setup(auth, api);
        api.hold = Completer<Map<String, dynamic>>();
        final result = c.publish();
        final old = c.pending!;
        auth.statusGate = Completer<void>();
        final login = s.signIn(username: actor, password: 'test');
        await auth.statusStarted.future;
        expect(c.pending, isNull);
        expect(c.detail, isNull);
        expect(await c.retryPublication(), KnowledgeOutcome.fenced);
        api.hold!.complete({
          'revision': revisionJson(status: 'published'),
          'replayed': false,
        });
        expect(await result, KnowledgeOutcome.fenced);
        expect(c.confirmedPublication, isNull);
        expect(api.bodies, hasLength(1));
        expect(identical(old.identity, s.sessionIdentity), false);
        auth.statusGate!.complete();
        await login;
      },
    );
  }
  test(
    'session replacement during notification cannot dispatch old command under new token',
    () async {
      final auth = _Auth(), api = _Api();
      final (s, _, c) = await _setup(auth, api);
      bool replaced = false;
      Future<void>? login;
      void replace() {
        if (c.busy && !replaced) {
          replaced = true;
          s.invalidateSession();
          login = s.signIn(username: 'other', password: 'test');
        }
      }

      c.addListener(replace);
      expect(await c.publish(), KnowledgeOutcome.fenced);
      await login;
      c.removeListener(replace);
      expect(api.bodies, isEmpty);
    },
  );
  testWidgets(
    'employee empty/loading/error, search and literal instruction with refresh',
    (tester) async {
      final api = _Api(role: 'employee');
      final result = await tester.runAsync(() => _setup(_Auth(), api));
      final (_, _, c) = result!;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Keine freigegebenen Anleitungen gefunden.'),
        findsOneWidget,
      );
      expect(find.text('Verwalten'), findsNothing);
      c.instruction = PublishedWikiDto.fromJson(employeeJson);
      c.notifyListeners();
      await tester.pump();
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      expect(find.text('Anleitung aktualisieren'), findsOneWidget);
      api.readFailure = const StoreApiException(
        'network_unavailable',
        'Unavailable',
      );
      await c.search('x');
      await tester.pump();
      expect(find.byKey(const Key('knowledge-error')), findsOneWidget);
    },
  );
  testWidgets(
    'manager editing, retained invalid input, saved preview and history statuses',
    (tester) async {
      final api = _Api();
      final result = await tester.runAsync(() => _setup(_Auth(), api));
      final (_, _, c) = result!;
      c.managing = true;
      c.history = [
        WikiRevisionDto.fromJson(revisionJson()),
        WikiRevisionDto.fromJson(revisionJson(status: 'discarded', number: 2)),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: KnowledgeSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('knowledge-title')),
        'Unsaved',
      );
      await tester.pump();
      expect(c.editing!.title, 'Unsaved');
      expect(c.detail!.draft!.content.title, 'Closing');
      final publish = tester.widget<FilledButton>(
        find.byKey(const Key('knowledge-publish')),
      );
      expect(publish.onPressed, isNull);
      final scrollable = find
          .descendant(
            of: find.byKey(const Key('knowledge-list')),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.widgetWithText(SelectableText, literal),
        300,
        scrollable: scrollable,
      );
      expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('DISCARDED · Revision 2'),
        400,
        scrollable: scrollable,
      );
      expect(find.text('DISCARDED · Revision 2'), findsOneWidget);
    },
  );
}

class _Auth implements StoreApi {
  int generation = 0;
  Completer<void>? statusGate;
  Completer<void> statusStarted = Completer<void>();
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
    if (statusGate != null) {
      if (!statusStarted.isCompleted) statusStarted.complete();
      await statusGate!.future;
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

/// Transport recorder: server replay/lifecycle semantics are tested in PostgreSQL.
class _Api implements PlatformApi {
  _Api({this.role = 'admin'});
  final String role;
  final bodies = <Map<String, dynamic>>[], queries = <Map<String, String>?>[];
  final reads = <String, Map<String, dynamic>>{};
  Completer<Map<String, dynamic>>? hold;
  StoreApiException? failure, readFailure;
  Map<String, dynamic>? reply;
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    bodies.add(body);
    if (hold != null) return hold!.future;
    if (failure != null) throw failure!;
    return reply ??
        {'article': articleJson(version: 2), 'revision': revisionJson()};
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
        'companyId': company,
        'locationId': location,
        'role': role,
        'permissions': [
          'knowledge.articles.read',
          if (role == 'admin') ...[
            'knowledge.articles.manage',
            'knowledge.articles.publish',
          ],
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
    queries.add(query);
    if (readFailure != null) throw readFailure!;
    if (reads.containsKey(route)) return reads[route]!;
    if (route == '${KnowledgeController.manageRoot}/$article') {
      return detailJson;
    }
    if (route == '${KnowledgeController.publicRoot}/$article') {
      return employeeJson;
    }
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }
}
