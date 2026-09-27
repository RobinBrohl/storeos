import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/task_template_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/task_template_section.dart';

const company = '11111111-1111-4111-8111-111111111111';
const location = '22222222-2222-4222-8222-222222222222';
const account = '33333333-3333-4333-8333-333333333333';

void main() {
  test('failed overview refresh preserves a confirmed creation', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    f.api.failList = true;
    await f.c.create('Opening', location);
    expect(f.c.error, isNotNull);
    expect(f.c.notice, contains('gespeichert'));
    expect(f.c.confirmed, isTrue);
    expect(f.c.selected, isNotNull);
    expect(f.c.title, 'Opening');
    expect(f.api.records.length, 1);
    f.api.failList = false;
    await f.c.loadList();
    expect(f.c.error, isNull);
    expect(f.c.templates!.single.id, f.c.selected!.id);
    expect(f.api.records.length, 1);
  });

  test(
    'lost publication response cannot confirm different published content',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      final original = f.c.title;
      f.api.conflict = true;
      f.api.concurrentPublish = true;
      f.api.loseResponse = true;
      await f.c.publish();
      expect(f.c.notice, isNull);
      expect(f.c.conflict, isTrue);
      expect(f.c.title, original);
      expect(f.c.dirty, isTrue);
      expect(f.c.canNewDraft, isFalse);
      expect(f.c.error, isNotNull);
    },
  );
  test('creation refreshes the overview without another user action', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.c.loadList();
    expect(f.c.templates, isEmpty);
    await f.c.create('Opening', location);
    expect(f.c.templates, isNotNull);
    expect(f.c.templates!.single.id, f.c.selected!.id);
    expect(f.c.templates!.single.title, 'Opening');
  });

  for (final operation in ['create', 'save', 'publish', 'newDraft']) {
    test(
      'lost $operation response reconciles the same stable revision',
      () async {
        final f = await _Fixture.create();
        addTearDown(f.dispose);
        if (operation != 'create') await f.ready();
        if (operation == 'newDraft') await f.c.publish();
        f.api.loseResponse = true;
        await f.act(operation);
        expect(f.c.error, isNull);
        expect(f.c.confirmed, isTrue);
        expect(f.c.notice, isNotNull);
        expect(f.api.records.length, operation == 'newDraft' ? 2 : 1);
      },
    );
    test('late $operation does not continue in a new session', () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      if (operation != 'create') await f.ready();
      if (operation == 'newDraft') await f.c.publish();
      final pending = Completer<Map<String, dynamic>>();
      f.api.pending = pending;
      final action = f.act(operation);
      await f.session.signOut();
      await f.signIn();
      await f.c.loadList();
      final count = f.api.requests;
      pending.complete({});
      await action;
      expect(f.api.requests, count);
      expect(f.c.selected, isNull);
      expect(f.c.revision, isNull);
      expect(f.c.error, isNull);
    });
  }
  test(
    'conflicts preserve local input and require explicit server adoption',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.c.setTitle('Local edit');
      f.api.conflict = true;
      await f.c.save();
      expect(f.c.conflict, isTrue);
      expect(f.c.title, 'Local edit');
      expect(f.c.editable, isFalse);
      expect(f.c.notice, isNull);
      expect(f.c.error, contains('Serverstand'));
      f.c.useServerVersion();
      expect(f.c.title, 'Remote edit');
      expect(f.c.dirty, isFalse);
      expect(f.c.editable, isTrue);
    },
  );
  test('concurrent publication preserves unconfirmed local content', () async {
    final f = await _Fixture.create();
    addTearDown(f.dispose);
    await f.ready();
    f.c.setTitle('Local edit');
    f.api.conflict = true;
    f.api.concurrentPublish = true;
    await f.c.save();
    expect(f.c.revision!.isDraft, isFalse);
    expect(f.c.dirty, isTrue);
    expect(f.c.title, 'Local edit');
    expect(f.c.conflict, isTrue);
    expect(f.c.canNewDraft, isFalse);
    expect(f.c.canPublish, isFalse);
    f.c.useServerVersion();
    expect(f.c.dirty, isFalse);
    expect(f.c.title, 'Remote edit');
  });
  test(
    'failed reconciliation keeps local text but removes confirmation and write actions',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.c.setTitle('Local');
      f.api.failGet = true;
      await f.c.save();
      expect(f.c.confirmed, isFalse);
      expect(f.c.editable, isFalse);
      expect(f.c.title, 'Local');
      expect(f.c.error, isNotNull);
      expect(f.c.notice, isNull);
      f.api.failGet = false;
      await f.c.open(f.api.head!['id'] as String);
      expect(f.c.title, 'Local');
      expect(f.c.confirmed, isTrue);
    },
  );
  test(
    'viewer cannot request or create templates through controller entry points',
    () async {
      final f = await _Fixture.create(role: 'viewer');
      addTearDown(f.dispose);
      final count = f.api.requests;
      await f.c.loadList();
      await f.c.create('Denied', location);
      expect(f.api.requests, count);
      expect(f.c.templates, isNull);
    },
  );
  test(
    'list and history continuation use the returned cursors without loading content',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      f.api.paging = true;
      await f.c.loadList();
      expect(f.c.nextCursor, 'list-page');
      await f.c.loadList(more: true);
      expect(f.c.nextCursor, isNull);
      await f.c.open(f.c.selected!.id);
      expect(f.c.revisionCursor, 'revision-page');
      await f.c.moreHistory();
      expect(f.c.revisionCursor, isNull);
      expect(f.api.cursors, containsAll(['list-page', 'revision-page']));
    },
  );
  testWidgets(
    'editor persists steps, ordering, publication and immutable history',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TaskTemplateSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Noch keine Arbeitsvorlagen vorhanden.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('create-template')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('new-template-title')),
        'Opening',
      );
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.number, 1);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('publish-template')))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Schritt hinzufügen'));
      await tester.tap(find.text('Schritt hinzufügen'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Anleitungstext');
      await tester.enterText(field, 'Check door');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-dirty')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('save-template')));
      await tester.tap(find.byKey(const Key('save-template')));
      await tester.pumpAndSettle();
      expect(f.c.dirty, isFalse);
      await tester.ensureVisible(find.byKey(const Key('publish-template')));
      await tester.tap(find.byKey(const Key('publish-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.isDraft, isFalse);
      expect(find.byKey(const Key('save-template')), findsNothing);
      await tester.ensureVisible(
        find.text('Neue Revision aus letzter Freigabe'),
      );
      await tester.tap(find.text('Neue Revision aus letzter Freigabe'));
      await tester.pumpAndSettle();
      expect(f.c.revision!.number, 2);
      f.c.addStep();
      final second = f.c.steps.last.id;
      f.c.setInstruction(second, 'Check light');
      f.c.moveStep(second, -1);
      await f.c.save();
      expect(f.c.steps.first.instruction, 'Check light');
      await f.c.open(f.c.selected!.id, revisionId: f.api.records.keys.first);
      await tester.pumpAndSettle();
      expect(f.c.steps.single.instruction, 'Check door');
      expect(f.c.editable, isFalse);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
  testWidgets(
    'invalid text shows error and session expiry clears an open editor',
    (tester) async {
      final f = await _Fixture.create();
      addTearDown(f.dispose);
      await f.ready();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TaskTemplateSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      f.c.setTitle('');
      await f.c.save();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-error')), findsOneWidget);
      expect(f.c.dirty, isTrue);
      await f.session.signOut();
      await tester.pumpAndSettle();
      expect(f.c.steps, isEmpty);
      expect(find.text('Revisionshistorie'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}

class _Fixture {
  _Fixture(this.session, this.platform, this.c, this.api);
  final SessionController session;
  final PlatformController platform;
  final TaskTemplateController c;
  final _Api api;
  bool disposed = false;
  static Future<_Fixture> create({String role = 'admin'}) async {
    final api = _Api(role), session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final c = TaskTemplateController(session, platform, api);
    final f = _Fixture(session, platform, c, api);
    await f.signIn();
    return f;
  }

  Future<void> signIn() async {
    await session.signIn(username: 'test', password: 'test');
    while (platform.isBusy) {
      await Future<void>.value();
    }
  }

  Future<void> ready() async {
    await c.create('Opening', location);
    c.addStep();
    c.setInstruction(c.steps.single.id, 'Check');
    await c.save();
  }

  Future<void> act(String operation) => switch (operation) {
    'create' => c.create('Opening', location),
    'publish' => c.publish(),
    'newDraft' => c.newDraft(),
    _ => (() {
      c.setTitle('Changed');
      return c.save();
    })(),
  };
  void dispose() {
    if (disposed) return;
    disposed = true;
    c.dispose();
    platform.dispose();
    session.dispose();
  }
}

class _Session implements StoreApi {
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'token',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const SessionUser(
      id: account,
      username: 'test',
      companyId: company,
      locationId: location,
    ),
  );
  @override
  Future<void> logout(String token) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      const SystemStatusResponse(companyId: company, locationId: location);
}

class _Api implements PlatformApi {
  _Api(this.role);
  final String role;
  Map<String, dynamic>? head;
  final records = <String, Map<String, dynamic>>{};
  bool loseResponse = false, conflict = false, failGet = false, paging = false;
  bool concurrentPublish = false, failList = false;
  int requests = 0;
  final cursors = <String>[];
  Completer<Map<String, dynamic>>? pending;
  static const time = '2026-09-27T00:00:00Z';
  Map<String, dynamic> copy(Map<String, dynamic> value) =>
      jsonDecode(jsonEncode(value)) as Map<String, dynamic>;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    requests++;
    if (route == '/context') {
      return {
        'userId': account,
        'companyId': company,
        'locationId': location,
        'role': role,
        'permissions': [
          'context.read',
          'organization.read',
          if (role == 'admin') 'tasks.templates.manage',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Company', 'version': 1},
        'locations': [
          {'id': location, 'companyId': company, 'name': 'Home', 'version': 1},
        ],
      };
    }
    if (failGet) {
      throw const StoreApiException('network_unavailable', 'Nicht erreichbar.');
    }
    if (after != null) cursors.add(after);
    if (route == '/task-templates') {
      if (failList) {
        throw const StoreApiException(
          'network_unavailable',
          'Liste nicht erreichbar.',
        );
      }
      return {
        'items': head == null || after != null ? [] : [copy(head!)],
        'nextCursor': paging && after == null ? 'list-page' : null,
      };
    }
    if (head == null) {
      throw const StoreApiException('not_found', 'Missing', statusCode: 404);
    }
    if (route.endsWith('/revisions')) {
      return {
        'items': after != null
            ? []
            : records.values
                  .toList()
                  .reversed
                  .map((r) => copy(r)..remove('content'))
                  .toList(),
        'nextCursor': paging && after == null ? 'revision-page' : null,
      };
    }
    if (route == '/task-templates/${head!['id']}') return copy(head!);
    final revision = records[route.split('/').last];
    if (revision == null) {
      throw const StoreApiException('not_found', 'Missing', statusCode: 404);
    }
    return copy({'template': head, 'revision': revision});
  }

  Map<String, dynamic> makeRevision(String id, Map<String, dynamic> content) =>
      {
        'id': id,
        'templateId': head!['id'],
        'number': records.length + 1,
        'status': 'draft',
        'title': content['title'],
        'createdAt': time,
        'publishedAt': null,
        'publishedBy': null,
        'content': copy(content),
      };
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    requests++;
    if (pending case final pending?) return pending.future;
    String rid;
    if (route == '/task-templates') {
      rid = body['revisionId'] as String;
      head = {
        'id': body['id'],
        'companyId': company,
        'locationId': location,
        'version': 1,
        'title': body['content']['title'],
        'createdAt': time,
        'updatedAt': time,
        'draftId': rid,
        'publishedId': null,
      };
      records[rid] = makeRevision(rid, body['content'] as Map<String, dynamic>);
    } else if (route.endsWith('/revisions')) {
      rid = body['id'] as String;
      records[rid] = makeRevision(
        rid,
        records[head!['publishedId']]!['content'] as Map<String, dynamic>,
      );
      head!['draftId'] = rid;
      head!['version'] = (head!['version'] as int) + 1;
    } else {
      rid = route.split('/')[4];
      final revision = records[rid]!;
      if (conflict) {
        if (concurrentPublish) {
          revision['status'] = 'published';
          revision['publishedAt'] = time;
          revision['publishedBy'] = account;
          head!['publishedId'] = rid;
          head!['draftId'] = null;
        }
        revision['title'] = 'Remote edit';
        revision['content']['title'] = 'Remote edit';
        head!['version'] = (head!['version'] as int) + 1;
        if (loseResponse) {
          throw const StoreApiException('timeout', 'Antwort verloren.');
        }
        throw const StoreApiException(
          'template_conflict',
          'Conflict',
          statusCode: 409,
        );
      }
      if (route.endsWith('/edit')) {
        revision['content'] = copy(body['content'] as Map<String, dynamic>);
        revision['title'] = body['content']['title'];
        head!['title'] = revision['title'];
      } else {
        revision['status'] = 'published';
        revision['publishedAt'] = time;
        revision['publishedBy'] = account;
        head!['publishedId'] = rid;
        head!['draftId'] = null;
      }
      head!['version'] = (head!['version'] as int) + 1;
    }
    if (loseResponse) {
      throw const StoreApiException('timeout', 'Antwort verloren.');
    }
    return copy({'template': head, 'revision': records[rid]});
  }
}
