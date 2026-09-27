import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/employee_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/employee_section.dart';
import 'package:storeos_client/src/ui/platform_home_screen.dart';

void main() {
  test(
    'link conflict explains the occupied assignment rather than a version change',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.employees.add(_profile());
      await f.controller.select(_profile());
      final reply = Completer<Map<String, dynamic>>();
      f.api.pendingWrite = reply;
      final pending = f.controller.linkAccount(
        _profile(),
        f.controller.linkCandidates.single,
      );
      reply.completeError(
        const StoreApiException(
          'already_linked',
          'Version changed',
          statusCode: 409,
        ),
      );
      await pending;
      expect(f.controller.error, contains('bereits verknüpft'));
      expect(f.controller.notice, isNull);
      expect(f.controller.link, isNull);
    },
  );

  for (final operation in ['create', 'rename', 'link']) {
    test(
      'late $operation stops before reconciliation in a new session',
      () async {
        final f = await _Fixture.create('admin');
        addTearDown(f.dispose);
        f.api.employees.add(_profile());
        await f.controller.select(_profile());
        final account = f.controller.linkCandidates.single;
        final reply = Completer<Map<String, dynamic>>();
        f.api.pendingWrite = reply;
        final pending = switch (operation) {
          'create' => f.controller.create('Created', 'location'),
          'rename' => f.controller.rename(_profile(), 'Changed'),
          _ => f.controller.linkAccount(_profile(), account),
        };
        await f.session.signOut();
        await f.session.signIn(username: 'account', password: 'password');
        while (f.platform.isBusy) {
          await Future<void>.value();
        }
        await f.controller.loadEmployees();
        final requests = f.api.employeeRequests;
        final current = f.controller.employees;
        reply.complete(_profile().toJson());
        await pending;
        expect(f.api.employeeRequests, requests);
        expect(f.controller.employees, same(current));
        expect(f.controller.selected, isNull);
        expect(f.controller.error, isNull);
        expect(f.controller.notice, isNull);
      },
    );
  }

  test(
    'failed create reconciliation removes old list and selected details',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.employees.add(_profile());
      await f.controller.loadEmployees();
      await f.controller.select(_profile());
      f.api.failList = true;
      await f.controller.create('Created', 'location');
      expect(f.controller.employees, isNull);
      expect(f.controller.selected, isNull);
      expect(f.controller.accounts, isEmpty);
      expect(f.controller.error, isNotNull);
      expect(f.controller.notice, isNull);
    },
  );

  testWidgets(
    'opening management during a pending self read still loads its list',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      final reply = Completer<Map<String, dynamic>>();
      f.api.pendingSelf = reply;
      final pending = f.controller.loadSelf();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployeeSection(controller: f.controller, self: false),
          ),
        ),
      );
      await tester.pump();
      reply.complete(_profile().toJson());
      await pending;
      await tester.pumpAndSettle();
      expect(
        find.text('Noch keine Mitarbeiterprofile vorhanden.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'unconfigured locations explain why profile creation is disabled',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.configured = false;
      await f.platform.loadOrganization();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployeeSection(controller: f.controller, self: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('create-employee')),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Standort einrichten'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  test(
    'self profile is cleared on denied refresh and cannot be restored after logout',
    () async {
      final f = await _Fixture.create('employee');
      addTearDown(f.dispose);
      await f.controller.loadSelf();
      expect(f.controller.mine?.displayName, 'Employee');
      f.api.denySelf = true;
      await f.controller.loadSelf();
      expect(f.controller.mine, isNull);
      expect(f.controller.error, isNotNull);
      f.api.denySelf = false;
      f.api.pendingSelf = Completer<Map<String, dynamic>>();
      final pending = f.controller.loadSelf();
      await f.session.signOut();
      f.api.pendingSelf!.complete(_profile().toJson());
      await pending;
      expect(f.controller.mine, isNull);
      expect(f.controller.selected, isNull);
    },
  );

  test(
    'lost employee create response is reconciled through its stable ID',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.loseCreateResponse = true;
      await f.controller.create('Created', 'location');
      expect(f.controller.employees, hasLength(1));
      expect(f.controller.error, isNull);
      expect(f.controller.notice, contains('gespeichert'));
      expect(f.api.createIds, hasLength(1));
    },
  );

  test(
    'unconfirmed employee create retains ID for retry and does not claim success',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.rejectCreate = true;
      await f.controller.create('Created', 'location');
      expect(f.controller.error, isNotNull);
      expect(f.controller.notice, isNull);
      f.api.rejectCreate = false;
      await f.controller.create('Created', 'location');
      expect(f.api.createIds.toSet(), hasLength(1));
      expect(f.controller.employees, hasLength(1));
    },
  );

  test(
    'link candidates are limited by activity and location; response loss reloads actual link',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.employees.add(_profile());
      await f.controller.select(_profile());
      expect(f.controller.linkCandidates.map((u) => u.id), ['account']);
      f.api.loseLinkResponse = true;
      await f.controller.linkAccount(
        _profile(),
        f.controller.linkCandidates.single,
      );
      expect(f.controller.link?.accountId, 'account');
      expect(f.controller.error, isNull);
      expect(f.controller.notice, contains('verknüpft'));
    },
  );

  test(
    'viewer cannot request employee data even through controller entry points',
    () async {
      final f = await _Fixture.create('viewer');
      addTearDown(f.dispose);
      await f.controller.loadEmployees();
      await f.controller.loadSelf();
      await f.controller.create('No', 'location');
      expect(f.api.employeeRequests, 0);
    },
  );

  testWidgets(
    'narrow admin navigation keeps all sections and employee management reachable',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      tester.view.physicalSize = const Size(303, 918);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: PlatformHomeScreen(
            session: f.session,
            platform: f.platform,
            employees: f.controller,
            baseUri: Uri.parse('http://127.0.0.1:8080'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsNothing);
      await tester.tap(find.byKey(const Key('open-navigation')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ListTile, 'Mitarbeiter'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Mein Profil'), findsOneWidget);
      await tester.tap(find.widgetWithText(ListTile, 'Mitarbeiter'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('create-employee')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'employee self view renders actual profile and removes it after failed periodic refresh',
    (tester) async {
      final f = await _Fixture.create('employee');
      addTearDown(f.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployeeSection(controller: f.controller, self: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Employee'), findsOneWidget);
      expect(find.byKey(const Key('create-employee')), findsNothing);
      f.api.denySelf = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Employee'), findsNothing);
      expect(find.byKey(const Key('employee-error')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets(
    'admin creates, links and deactivates a profile using the employee views',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      tester.view.physicalSize = const Size(1100, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmployeeSection(controller: f.controller, self: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-employee')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('employee-name-input')),
        'Created',
      );
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('Created'), findsOneWidget);
      await tester.tap(find.text('Created'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Account verknüpfen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('account (employee)'));
      await tester.pumpAndSettle();
      expect(find.text('Verknüpfung entziehen'), findsOneWidget);
      await tester.tap(find.text('Deaktivieren'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();
      expect(find.text('Profil deaktiviert'), findsOneWidget);
      expect(find.text('Account verknüpfen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );
}

EmployeeDto _profile({
  String id = 'employee',
  String name = 'Employee',
  bool active = true,
  int version = 1,
}) => EmployeeDto(
  id: id,
  companyId: 'company',
  locationId: 'location',
  displayName: name,
  isActive: active,
  version: version,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  assignedFrom: DateTime.utc(2026),
  assignedUntil: active ? null : DateTime.utc(2026, 2),
);

class _Fixture {
  _Fixture(this.session, this.platform, this.controller, this.api);
  final SessionController session;
  final PlatformController platform;
  final EmployeeController controller;
  final _Api api;
  bool _disposed = false;
  static Future<_Fixture> create(String role) async {
    final api = _Api(role);
    final session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final controller = EmployeeController(session, platform, api);
    await session.signIn(username: 'account', password: 'password');
    while (platform.isBusy) {
      await Future<void>.value();
    }
    return _Fixture(session, platform, controller, api);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
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
      id: 'account',
      username: 'account',
      companyId: 'company',
      locationId: 'location',
    ),
  );
  @override
  Future<void> logout(String token) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async =>
      const SystemStatusResponse(companyId: 'company', locationId: 'location');
}

class _Api implements PlatformApi {
  _Api(this.role);
  final String role;
  final List<EmployeeDto> employees = [];
  final List<String> createIds = [];
  EmployeeLinkDto? link;
  bool denySelf = false,
      loseCreateResponse = false,
      rejectCreate = false,
      loseLinkResponse = false;
  int employeeRequests = 0;
  bool failList = false, configured = true;
  Completer<Map<String, dynamic>>? pendingWrite;
  Completer<Map<String, dynamic>>? pendingSelf;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    if (route == '/context') {
      return {
        'userId': 'account',
        'companyId': 'company',
        'locationId': 'location',
        'role': role,
        'permissions': [
          'context.read',
          'organization.read',
          if (role == 'admin') ...[
            'people.manage',
            'identity.read',
            'audit.read',
            'events.read',
            'plugins.read',
          ],
          if (role == 'admin' || role == 'employee') 'people.self.read',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {
          'id': 'company',
          'name': configured ? 'Company' : null,
          'version': 1,
        },
        'locations': [
          {
            'id': 'location',
            'companyId': 'company',
            'name': configured ? 'Home' : null,
            'version': 1,
          },
        ],
      };
    }
    if (route == '/users') {
      return {
        'users': [
          for (final id in ['account', 'foreign', 'inactive'])
            {
              'id': id,
              'username': id,
              'companyId': 'company',
              'locationId': id == 'foreign' ? 'elsewhere' : 'location',
              'role': 'employee',
              'isActive': id != 'inactive',
              'version': 1,
            },
        ],
      };
    }
    employeeRequests++;
    if (route == '/employees/me') {
      if (denySelf) {
        throw const StoreApiException(
          'employee_unavailable',
          'Denied',
          statusCode: 404,
        );
      }
      return pendingSelf?.future ?? _profile().toJson();
    }
    if (route == '/employees') {
      if (failList) {
        throw const StoreApiException('network_unavailable', 'Offline');
      }
      return {'employees': employees.map((e) => e.toJson()).toList()};
    }
    if (route.endsWith('/account-link')) return {'link': link?.toJson()};
    return employees.singleWhere((e) => route.endsWith(e.id)).toJson();
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    employeeRequests++;
    if (pendingWrite case final pending?) return pending.future;
    if (route == '/employees') {
      createIds.add(body['id'] as String);
      if (rejectCreate) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      final employee = _profile(
        id: body['id'] as String,
        name: body['displayName'] as String,
      );
      employees.add(employee);
      if (loseCreateResponse) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      return employee.toJson();
    }
    if (route.endsWith('/account-link')) {
      link = EmployeeLinkDto(
        id: body['id'] as String,
        accountId: body['accountId'] as String,
        employeeId: employees.single.id,
        companyId: 'company',
        locationId: 'location',
        version: 1,
        linkedAt: DateTime.utc(2026),
        revokedAt: null,
      );
      if (loseLinkResponse) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      return link!.toJson();
    }
    if (route.endsWith('/deactivate')) {
      employees[0] = _profile(
        id: employees[0].id,
        name: employees[0].displayName,
        active: false,
        version: 2,
      );
      link = null;
      return employees[0].toJson();
    }
    throw StateError('Unexpected route $route');
  }
}
