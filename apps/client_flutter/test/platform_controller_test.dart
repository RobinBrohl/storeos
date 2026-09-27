import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/platform_models.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  Future<void> settled() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test(
    'admin context loads organization and version conflict reloads',
    () async {
      final session = SessionController(_SessionApi());
      final api = _PlatformApi(role: 'admin');
      final controller = PlatformController(session, api);
      await session.signIn(username: 'robin', password: 'secret');
      await settled();

      expect(controller.context?.role, 'admin');
      expect(controller.organization?.company.name, 'Demo');
      api.conflictOnce = true;
      expect(await controller.renameCompany('Neu'), false);
      expect(controller.organization?.company.version, 2);
      expect(controller.error, contains('inzwischen geändert'));

      expect(await controller.renameCompany('Neu'), true);
      expect(api.posts.last.$2['expectedVersion'], 2);
      expect(controller.organization?.company.name, 'Neu');
      controller.dispose();
      session.dispose();
    },
  );

  test('ambiguous create reloads and reuses client UUID on retry', () async {
    final session = SessionController(_SessionApi());
    final api = _PlatformApi(role: 'admin');
    final controller = PlatformController(session, api);
    await session.signIn(username: 'robin', password: 'secret');
    await settled();

    api.failLocationOnce = true;
    expect(await controller.createLocation('Nord'), false);
    final firstId = api.posts.last.$2['id'];
    expect(controller.organization?.locations.length, 1);
    expect(await controller.createLocation('Nord'), true);
    expect(api.posts.last.$2['id'], firstId);
    expect(controller.organization?.locations.length, 2);
    controller.dispose();
    session.dispose();
  });

  test('viewer cannot load users or use admin mutations', () async {
    final session = SessionController(_SessionApi());
    final api = _PlatformApi(role: 'viewer');
    final controller = PlatformController(session, api);
    await session.signIn(username: 'robin', password: 'secret');
    await settled();

    expect(controller.allows('organization.read'), true);
    expect(controller.allows('identity.read'), false);
    await controller.loadUsers();
    expect(controller.users, isNull);
    expect(api.getRoutes, isNot(contains('/users')));
    expect(await controller.renameCompany('Verboten'), false);
    expect(api.posts, isEmpty);
    controller.dispose();
    session.dispose();
  });

  test(
    'lost location response is confirmed by reload and completes the form',
    () async {
      final session = SessionController(_SessionApi());
      final api = _PlatformApi(role: 'admin')
        ..loseCreatedLocationResponse = true;
      final controller = PlatformController(session, api);
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      await session.signIn(username: 'robin', password: 'secret');
      await settled();

      expect(await controller.createLocation('Nord'), isTrue);
      expect(controller.organization?.locations, hasLength(2));
      expect(api.posts, hasLength(1));
      expect(controller.error, isNull);
      expect(controller.notice, contains('vorhanden'));
    },
  );

  test(
    'lost user response is confirmed by reload and completes the form',
    () async {
      final session = SessionController(_SessionApi());
      final api = _PlatformApi(role: 'admin')..loseCreatedUserResponse = true;
      final controller = PlatformController(session, api);
      addTearDown(controller.dispose);
      addTearDown(session.dispose);
      await session.signIn(username: 'robin', password: 'secret');
      await settled();

      expect(
        await controller.createUser(
          username: 'new.user',
          password: 'test-only-password',
          locationId: 'location-1',
          role: 'viewer',
        ),
        isTrue,
      );
      expect(controller.users, hasLength(1));
      expect(api.posts, hasLength(1));
      expect(controller.error, isNull);
    },
  );

  test('late user response after logout cannot restore data', () async {
    final session = SessionController(_SessionApi());
    final api = _PlatformApi(role: 'admin');
    final controller = PlatformController(session, api);
    await session.signIn(username: 'robin', password: 'secret');
    await settled();

    final delayedUsers = Completer<Map<String, dynamic>>();
    api.delayedUsers = delayedUsers;
    final load = controller.loadUsers();
    await settled();
    await session.signOut();
    delayedUsers.complete({'users': []});
    await load;
    expect(controller.users, isNull);
    expect(controller.context, isNull);
    controller.dispose();
    session.dispose();
  });

  test(
    'plugin manifest is strict and approval token is returned once',
    () async {
      final session = SessionController(_SessionApi());
      final api = _PlatformApi(role: 'admin');
      final controller = PlatformController(session, api);
      await session.signIn(username: 'robin', password: 'secret');
      await settled();

      expect(
        () => parseManifest('{"id":"x","name":"Bad"}'),
        throwsFormatException,
      );
      await controller.loadPlugins();
      final plugin = controller.plugins!.single;
      final approval = await controller.approvePlugin(
        plugin,
        locationId: 'location-1',
        permissions: const ['organization.read'],
        subscriptions: const [],
      );
      expect(approval?.token, 'one-time-token');
      expect(controller.plugins!.single.status, 'approved');
      expect(controller.plugins!.single.tokenExpiresAt, isNotNull);
      expect(controller.notice, contains('Zugangstoken'));
      controller.dispose();
      session.dispose();
    },
  );
}

class _SessionApi implements StoreApi {
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'session-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    user: const SessionUser(
      id: 'user-1',
      username: 'robin',
      companyId: 'company-1',
      locationId: 'location-1',
    ),
  );

  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async => const SystemStatusResponse(
    companyId: 'company-1',
    locationId: 'location-1',
  );

  @override
  Future<void> logout(String token) async {}
}

class _PlatformApi implements PlatformApi {
  _PlatformApi({required this.role});
  final String role;
  final getRoutes = <String>[];
  final posts = <(String, Map<String, dynamic>)>[];
  bool conflictOnce = false;
  bool failLocationOnce = false;
  bool loseCreatedLocationResponse = false;
  bool loseCreatedUserResponse = false;
  final users = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? delayedUsers;

  Map<String, dynamic> company = {
    'id': 'company-1',
    'name': 'Demo',
    'version': 1,
  };
  List<Map<String, dynamic>> locations = [
    {
      'id': 'location-1',
      'companyId': 'company-1',
      'name': 'Mitte',
      'version': 1,
    },
  ];
  bool approved = false;

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    expect(token, 'session-token');
    getRoutes.add(route);
    switch (route) {
      case '/context':
        return {
          'userId': 'user-1',
          'companyId': 'company-1',
          'locationId': 'location-1',
          'role': role,
          'permissions': role == 'admin'
              ? [
                  'organization.read',
                  'organization.write',
                  'identity.read',
                  'identity.write',
                  'audit.read',
                  'events.read',
                  'events.write',
                  'plugins.read',
                  'plugins.write',
                ]
              : ['organization.read'],
        };
      case '/organization':
        return {'company': company, 'locations': locations};
      case '/users':
        if (delayedUsers case final pending?) return pending.future;
        return {'users': users};
      case '/plugins':
        return {
          'plugins': [
            {
              'id': 'sample.plugin',
              'manifest': {
                'id': 'sample.plugin',
                'name': 'Sample',
                'version': '1.0.0',
                'vendor': 'Example',
                'coreApiVersion': 1,
                'capabilities': ['organization.read'],
                'permissions': ['organization.read'],
                'subscriptions': <String>[],
                'configurationSchema': {
                  'type': 'object',
                  'properties': <String, dynamic>{},
                  'additionalProperties': false,
                },
              },
              'status': approved ? 'approved' : 'registered',
              'version': approved ? 2 : 1,
              'locationId': approved ? 'location-1' : null,
              'permissions': approved ? ['organization.read'] : <String>[],
              'subscriptions': <String>[],
              'tokenExpiresAt': approved ? '2030-01-01T00:00:00Z' : null,
            },
          ],
        };
      default:
        throw StateError('Unexpected GET $route');
    }
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    expect(token, 'session-token');
    posts.add((route, body));
    if (route == '/company') {
      if (conflictOnce) {
        conflictOnce = false;
        company = {...company, 'version': 2};
        throw const StoreApiException(
          'version_conflict',
          'Der Datensatz wurde inzwischen geändert. Die Ansicht wird neu geladen.',
          statusCode: 409,
        );
      }
      company = {
        ...company,
        'name': body['name'],
        'version': (company['version'] as int) + 1,
      };
      return company;
    }
    if (route == '/locations') {
      if (failLocationOnce) {
        failLocationOnce = false;
        throw const StoreApiException('timeout', 'Zeitüberschreitung.');
      }
      locations = [
        ...locations,
        {
          'id': body['id'],
          'companyId': 'company-1',
          'name': body['name'],
          'version': 1,
        },
      ];
      if (loseCreatedLocationResponse) {
        throw const StoreApiException('timeout', 'Zeitüberschreitung.');
      }
      return locations.last;
    }
    if (route == '/plugins/sample.plugin/approve') {
      approved = true;
      return {
        'plugin': (await get(token, '/plugins'))['plugins']![0],
        'token': 'one-time-token',
        'expiresAt': '2030-01-01T00:00:00Z',
      };
    }
    if (route == '/users') {
      users.add({
        'id': body['id'],
        'username': body['username'],
        'companyId': 'company-1',
        'locationId': body['locationId'],
        'role': body['role'],
        'isActive': true,
        'version': 1,
      });
      if (loseCreatedUserResponse) {
        throw const StoreApiException('timeout', 'Zeitüberschreitung.');
      }
      return users.last;
    }
    throw StateError('Unexpected POST $route');
  }
}
