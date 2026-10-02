import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_section.dart';

const company = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222',
    account = '33333333-3333-4333-8333-333333333333',
    employee = '44444444-4444-4444-8444-444444444444',
    template = '55555555-5555-4555-8555-555555555555',
    revision = '66666666-6666-4666-8666-666666666666',
    taskId = '77777777-7777-4777-8777-777777777777';
void main() {
  test(
    'refreshing choices clears obsolete revisions and safely rejects a stale selection',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      final stale = f.c.revisions.single;
      f.c.removeSelection(template);
      f.api.hideTemplates = true;
      await f.c.loadChoices();
      expect(() => f.c.addRevision(stale), returnsNormally);
      expect(f.c.revisions, isEmpty);
      expect(f.c.selections, isEmpty);
    },
  );
  test('new draft clears revision choices from the previous editor', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    f.c.newDraft();
    expect(f.c.revisions, isEmpty);
    expect(f.c.revisionTemplateId, isNull);
  });
  for (final operation in ['edit', 'publish']) {
    test(
      'unreceived $operation is retryable when the server still has the original draft',
      () async {
        final f = await Fixture.create();
        addTearDown(f.dispose);
        await f.prepare();
        await f.c.save();
        if (operation == 'edit') f.c.setTimes(end: '2030-01-01T19:00:00Z');
        f.api.failBeforeWrite = true;
        await (operation == 'publish' ? f.c.publish() : f.c.save());
        expect(f.c.conflict, isFalse);
        expect(f.c.unconfirmed, isTrue);
        expect(f.c.notice, isNull);
        expect(f.c.error, isNotNull);
        f.api.failBeforeWrite = false;
        await f.c.retry();
        expect(f.c.error, isNull);
        expect(f.c.unconfirmed, isFalse);
        expect(f.api.records, hasLength(1));
        expect(f.c.selected!.version, 2);
      },
    );
  }
  test(
    'lost unchanged save confirms the original version without a false conflict',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      await f.c.save();
      f.api.lose = true;
      await f.c.save();
      expect(f.c.error, isNull);
      expect(f.c.conflict, isFalse);
      expect(f.c.selected!.version, 1);
      expect(f.c.unconfirmed, isFalse);
    },
  );
  for (final operation in ['create', 'edit', 'publish']) {
    test('lost $operation response confirms only matching state', () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      if (operation != 'create') await f.c.save();
      if (operation == 'edit') f.c.setTimes(end: '2030-01-01T19:00:00Z');
      f.api.lose = true;
      await (operation == 'publish' ? f.c.publish() : f.c.save());
      expect(f.c.error, isNull);
      expect(f.c.unconfirmed, isFalse);
      expect(f.c.notice, isNotNull);
      expect(f.api.records, hasLength(1));
    });
    test('late $operation cannot populate a replaced session', () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      if (operation != 'create') await f.c.save();
      if (operation == 'edit') f.c.setTimes(end: '2030-01-01T19:00:00Z');
      f.api.pending = Completer<Map<String, dynamic>>();
      final future = operation == 'publish' ? f.c.publish() : f.c.save();
      await f.session.signOut();
      await f.signIn();
      f.api.pending!.complete({});
      await future;
      expect(f.c.selected, isNull);
      expect(f.c.employeeId, isNull);
      expect(f.c.selections, isEmpty);
      expect(f.c.error, isNull);
    });
  }
  test(
    'unconfirmed creation retains stable ID and prevents input changes',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      f.api.lose = true;
      f.api.failGet = true;
      await f.c.save();
      expect(f.c.unconfirmed, isTrue);
      expect(f.c.editable, isFalse);
      final id = f.api.records.keys.single, start = f.c.startsAt;
      f.c.setTimes(start: '2031-01-01T00:00:00Z');
      expect(f.c.startsAt, start);
      f.api.failGet = false;
      f.api.lose = false;
      await f.c.retry();
      expect(f.c.selected!.id, id);
      expect(f.api.records, hasLength(1));
      expect(f.c.unconfirmed, isFalse);
    },
  );
  test(
    'concurrent content publication is a conflict, never false success',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      await f.c.save();
      f.api.changeOnPublish = true;
      f.api.lose = true;
      await f.c.publish();
      expect(f.c.conflict, isTrue);
      expect(f.c.notice, isNull);
      expect(f.c.endsAt, '2030-01-01T18:00:00.000Z');
      expect(f.c.canPublish, isFalse);
      f.api.lose = false;
      await f.c.open(f.c.selected!.id);
      expect(f.c.conflict, isFalse);
      expect(f.c.selected!.status, 'published');
    },
  );
  test('explicit conflict never resends local input', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    await f.c.save();
    f.c.setTimes(end: '2030-01-01T19:00:00Z');
    f.api.conflict = true;
    await f.c.save();
    final requests = f.api.posts;
    await f.c.retry();
    expect(f.c.conflict, isTrue);
    expect(f.api.posts, requests);
    expect(f.c.endsAt, '2030-01-01T19:00:00Z');
  });
  test('overview failure does not revoke confirmed creation', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    f.api.failList = true;
    await f.c.save();
    expect(f.c.error, isNotNull);
    expect(f.c.notice, isNotNull);
    expect(f.c.selected, isNotNull);
    expect(f.c.unconfirmed, isFalse);
    f.api.failList = false;
    await f.c.load();
    expect(f.c.items, hasLength(1));
  });
  test(
    'selection order, pagination and invalid times stay in controller',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      f.c.addRevision(f.c.revisions.single);
      expect(f.c.selections, hasLength(1));
      f.c.setTimes(start: 'invalid');
      await f.c.save();
      expect(f.c.error, isNotNull);
      expect(f.api.posts, 0);
      f.api.page = true;
      await f.c.load();
      await f.c.load(more: true);
      expect(f.api.cursors, contains('next'));
    },
  );
  test(
    'employee home has no active profile state and no management actions',
    () async {
      final f = await Fixture.create(self: true);
      addTearDown(f.dispose);
      f.api.noProfile = true;
      await f.c.load();
      expect(f.c.error, contains('Mitarbeiterprofil'));
      expect(f.c.editable, isFalse);
      f.c.newDraft();
      expect(f.c.editingNew, isFalse);
    },
  );
  testWidgets('UTC editor persists errors and shows publication limitation', (
    tester,
  ) async {
    final f = await Fixture.create();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.c)),
      ),
    );
    await tester.pumpAndSettle();
    await f.prepare();
    await f.c.save();
    await tester.pumpAndSettle();
    expect(find.textContaining('Alle Zeiten in UTC'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('publish-shift')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Nach Veröffentlichung sind Änderung'),
      findsOneWidget,
    );
    final publish = tester.widget<FilledButton>(
      find.byKey(const Key('publish-shift')),
    );
    expect(publish.onPressed, isNotNull);
    await f.session.signOut();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('publish-shift')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
  testWidgets('own home shows readable snapshots without execution controls', (
    tester,
  ) async {
    final f = await Fixture.create();
    await f.prepare();
    await f.c.save();
    await f.c.publish();
    final home = ShiftController(f.session, f.platform, f.api, self: true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: home)),
      ),
    );
    await tester.pumpAndSettle();
    await home.open(f.c.selected!.id);
    await home.openTask(taskId);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('1. Check equipment'), 250);
    await tester.pumpAndSettle();
    expect(find.text('1. Check equipment'), findsOneWidget);
    expect(find.byKey(const Key('save-shift')), findsNothing);
    expect(find.text('Abschließen'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    home.dispose();
    f.dispose();
  });
  test('published shift cancellation is confirmed and read-only', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    await f.c.save();
    await f.c.publish();
    expect(f.c.canCancelShift, isTrue);
    await f.c.cancelShift('Wrong employee');
    expect(f.c.error, isNull);
    expect(f.c.selected!.status, 'cancelled');
    expect(f.c.selected!.version, 3);
    expect(f.c.selected!.cancellationVersion, 2);
    expect(f.c.selected!.cancellationReason, 'Wrong employee');
    expect(f.c.selected!.cancelledBy, account);
    expect(f.c.tasks.single.status, 'cancelled');
    expect(f.c.tasks.single.version, 2);
    expect(f.c.canCancelShift, isFalse);
  });
  test('cancellation is not offered once a task left open', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    await f.c.save();
    await f.c.publish();
    final id = f.c.selected!.id;
    ((f.api.records[id]!['tasks'] as List).first as Map)['status'] =
        'in_progress';
    await f.c.open(id);
    expect(f.c.canCancelShift, isFalse);
  });
  test(
    'lost cancellation response confirms only exact cancellation evidence',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      await f.c.save();
      await f.c.publish();
      f.api.lose = true;
      await f.c.cancelShift('Duplicate publication');
      expect(f.c.error, isNull);
      expect(f.c.conflict, isFalse);
      expect(f.c.unconfirmed, isFalse);
      expect(f.c.notice, isNotNull);
      expect(f.c.selected!.status, 'cancelled');
      expect(f.c.selected!.cancellationReason, 'Duplicate publication');
    },
  );
  test('a mismatching cancellation is never treated as success', () async {
    final f = await Fixture.create();
    addTearDown(f.dispose);
    await f.prepare();
    await f.c.save();
    await f.c.publish();
    f.api.cancelTamper = true;
    f.api.lose = true;
    await f.c.cancelShift('Duplicate publication');
    expect(f.c.conflict, isTrue);
    expect(f.c.notice, isNull);
    expect(f.c.selected!.status, 'published');
  });
  test(
    'server refusal keeps the shift published and shows the reason',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      await f.c.save();
      await f.c.publish();
      f.api.cancelRefused = true;
      await f.c.cancelShift('Too late');
      expect(f.c.error, contains('begonnen'));
      expect(f.c.selected!.status, 'published');
      expect(f.c.canCancelShift, isTrue);
      expect(f.c.unconfirmed, isFalse);
    },
  );
  test(
    'cancellation reason is required and bounded before any request',
    () async {
      final f = await Fixture.create();
      addTearDown(f.dispose);
      await f.prepare();
      await f.c.save();
      await f.c.publish();
      final requests = f.api.posts;
      await f.c.cancelShift('   ');
      expect(f.c.error, isNotNull);
      expect(f.api.posts, requests);
      await f.c.cancelShift('x' * 501);
      expect(f.c.error, isNotNull);
      expect(f.api.posts, requests);
    },
  );
  testWidgets('published shift offers cancellation and renders it read-only', (
    tester,
  ) async {
    final f = await Fixture.create();
    await f.prepare();
    await f.c.save();
    await f.c.publish();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ShiftSection(controller: f.c)),
      ),
    );
    await tester.pumpAndSettle();
    await f.c.open(f.c.selected!.id);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('cancel-shift')), 300);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('cancel-shift')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(const Key('cancel-shift')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-cancel-shift')));
    await tester.pumpAndSettle();
    expect(find.text('Begründung erforderlich.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('cancel-shift-reason')),
      'Wrong employee',
    );
    await tester.tap(find.byKey(const Key('confirm-cancel-shift')));
    await tester.pumpAndSettle();
    expect(f.c.selected!.status, 'cancelled');
    expect(find.byKey(const Key('cancel-shift')), findsNothing);
    expect(find.byKey(const Key('publish-shift')), findsNothing);
    expect(find.byKey(const Key('shift-cancellation')), findsOneWidget);
    expect(find.textContaining('Grund: Wrong employee'), findsOneWidget);
    expect(find.byKey(const Key('shift-error')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
  testWidgets(
    'cancellation dialog counts Unicode code points, not UTF-16 units',
    (tester) async {
      final f = await Fixture.create();
      await f.prepare();
      await f.c.save();
      await f.c.publish();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftSection(controller: f.c)),
        ),
      );
      await tester.pumpAndSettle();
      await f.c.open(f.c.selected!.id);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const Key('cancel-shift')),
        300,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cancel-shift')));
      await tester.pumpAndSettle();
      final reason = '😀' * 300;
      expect(reason.runes.length, 300);
      expect(reason.length, greaterThan(500));
      await tester.enterText(
        find.byKey(const Key('cancel-shift-reason')),
        reason,
      );
      await tester.tap(find.byKey(const Key('confirm-cancel-shift')));
      await tester.pumpAndSettle();
      expect(find.text('Maximal 500 Zeichen.'), findsNothing);
      expect(f.c.selected!.status, 'cancelled');
      expect(f.c.selected!.cancellationReason, reason);
      expect(find.byKey(const Key('shift-cancellation')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}

class Fixture {
  Fixture(this.session, this.platform, this.c, this.api);
  final SessionController session;
  final PlatformController platform;
  final ShiftController c;
  final Api api;
  static Future<Fixture> create({bool self = false}) async {
    final api = Api(),
        session = SessionController(Session()),
        platform = PlatformController(session, api),
        c = ShiftController(session, platform, api, self: self);
    final f = Fixture(session, platform, c, api);
    await f.signIn();
    return f;
  }

  Future<void> signIn() async {
    await session.signIn(username: 'test', password: 'test');
    while (platform.isBusy) {
      await Future<void>.value();
    }
  }

  Future<void> prepare() async {
    await c.loadChoices();
    c.newDraft();
    c.chooseEmployee(employee);
    c.setTimes(start: '2030-01-01T08:00:00Z', end: '2030-01-01T18:00:00Z');
    await c.loadRevisions(template);
    c.addRevision(c.revisions.single);
  }

  void dispose() {
    c.dispose();
    platform.dispose();
    session.dispose();
  }
}

class Session implements StoreApi {
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
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> logout(String token) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      const SystemStatusResponse(companyId: company, locationId: location);
}

class Api implements PlatformApi {
  bool hideTemplates = false, failBeforeWrite = false;
  final records = <String, Map<String, dynamic>>{};
  bool lose = false,
      failGet = false,
      failList = false,
      conflict = false,
      changeOnPublish = false,
      noProfile = false,
      page = false,
      cancelRefused = false,
      cancelTamper = false;
  int posts = 0;
  final cursors = <String>[];
  Completer<Map<String, dynamic>>? pending;
  static const time = '2026-09-27T00:00:00Z';
  Map<String, dynamic> copy(Map<String, dynamic> v) =>
      jsonDecode(jsonEncode(v)) as Map<String, dynamic>;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    if (route == '/context') {
      return {
        'userId': account,
        'companyId': company,
        'locationId': location,
        'role': 'admin',
        'permissions': [
          'context.read',
          'organization.read',
          'workforce.shifts.manage',
          'workforce.shifts.self.read',
          'tasks.instances.read',
          'tasks.instances.self.read',
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
      throw const StoreApiException('network_unavailable', 'Offline');
    }
    if (noProfile) {
      throw const StoreApiException(
        'employee_unavailable',
        'No profile',
        statusCode: 404,
      );
    }
    if (route.endsWith('/blockings') || route.endsWith('/blocked-tasks')) {
      return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
    }
    if (route == '/employee-home/running-tasks') {
      return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
    }
    if (route.endsWith('/execution')) {
      return {
        'instanceId': taskId,
        'status': 'open',
        'version': 1,
        'results': <Map<String, dynamic>>[],
        'startedAt': null,
        'startedBy': null,
        'completedAt': null,
        'completedBy': null,
      };
    }
    if (after != null) cursors.add(after);
    if (route == '/employees') {
      return {
        'employees': [
          {
            'id': employee,
            'companyId': company,
            'locationId': location,
            'displayName': 'Worker',
            'isActive': true,
            'version': 1,
            'createdAt': time,
            'updatedAt': time,
            'assignedFrom': time,
            'assignedUntil': null,
          },
        ],
      };
    }
    if (route == '/task-templates') {
      if (hideTemplates) {
        return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
      }
      return {
        'items': [
          {
            'id': template,
            'companyId': company,
            'locationId': location,
            'title': 'Opening',
            'version': 2,
            'createdAt': time,
            'updatedAt': time,
            'draftId': null,
            'publishedId': revision,
          },
        ],
        'nextCursor': null,
      };
    }
    if (route.endsWith('/revisions')) {
      return {
        'items': [
          {
            'id': revision,
            'templateId': template,
            'number': 1,
            'status': 'published',
            'title': 'Opening',
            'createdAt': time,
            'publishedAt': time,
            'publishedBy': account,
          },
        ],
        'nextCursor': null,
      };
    }
    if (route.endsWith('/shifts')) {
      if (failList) {
        throw const StoreApiException('network_unavailable', 'List failed');
      }
      return {
        'items': after == null ? records.values.map(copy).toList() : [],
        'nextCursor': page && after == null ? 'next' : null,
      };
    }
    if (route.contains('/tasks/')) {
      return {
        ...records.values.single['tasks'][0] as Map<String, dynamic>,
        'content': {
          'schemaVersion': 1,
          'title': 'Opening',
          'steps': [
            {
              'id': taskId,
              'type': 'confirmation',
              'instruction': 'Check equipment',
            },
          ],
        },
      };
    }
    final result = records[route.split('/').last];
    if (result == null) {
      throw const StoreApiException('not_found', 'Missing', statusCode: 404);
    }
    return copy(result);
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    posts++;
    if (failBeforeWrite) {
      throw const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
    }
    if (pending != null) return pending!.future;
    if (conflict) {
      throw const StoreApiException(
        'shift_conflict',
        'Conflict',
        statusCode: 409,
      );
    }
    final id = (body['id'] ?? route.split('/')[2]) as String;
    if (route == '/shifts') {
      records.putIfAbsent(
        id,
        () => {
          'shift': {
            ...body,
            'companyId': company,
            'version': 1,
            'status': 'draft',
            'createdAt': time,
            'updatedAt': time,
            'publishedAt': null,
            'publicationVersion': null,
          },
          'tasks': <Map<String, dynamic>>[],
        },
      );
    } else {
      final shift = records[id]!['shift'] as Map<String, dynamic>;
      if (route.endsWith('/cancel')) {
        if (cancelRefused) {
          throw const StoreApiException(
            'shift_in_progress',
            'Task started',
            statusCode: 422,
          );
        }
        shift['status'] = 'cancelled';
        shift['cancelledAt'] = time;
        shift['cancelledBy'] = account;
        shift['cancellationReason'] = body['reason'];
        shift['cancellationVersion'] = cancelTamper
            ? 99
            : body['expectedVersion'];
        shift['version'] = (shift['version'] as int) + 1;
        for (final task in records[id]!['tasks'] as List) {
          (task as Map<String, dynamic>)['status'] = 'cancelled';
          task['version'] = 2;
        }
      } else if (route.endsWith('/publish')) {
        shift['status'] = 'published';
        shift['publishedAt'] = time;
        shift['publicationVersion'] = body['expectedVersion'];
        shift['version'] = (shift['version'] as int) + 1;
        if (changeOnPublish) {
          shift['endsAt'] = '2030-01-01T20:00:00Z';
          shift['publicationVersion'] = 99;
        }
        records[id]!['tasks'] = [
          {
            'id': taskId,
            'shiftId': id,
            'employeeId': employee,
            'templateId': template,
            'revisionId': revision,
            'title': 'Opening',
            'position': 0,
            'status': 'open',
            'version': 1,
            'totalSteps': 1,
            'confirmedSteps': 0,
          },
        ];
      } else {
        final changed =
            jsonEncode(ShiftDraftInput.fromJson(shift).toJson()) !=
            jsonEncode(ShiftDraftInput.fromJson(body).toJson());
        shift.addAll(body);
        if (changed) shift['version'] = (shift['version'] as int) + 1;
      }
    }
    if (lose) {
      throw const StoreApiException('network_unavailable', 'Lost response');
    }
    return copy(records[id]!);
  }
}
