import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/app/storeos_app.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  Future<void> login(WidgetTester tester, {bool settle = true}) async {
    await tester.enterText(find.byKey(const Key('username-field')), 'robin');
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.ensureVisible(find.byKey(const Key('login-button')));
    await tester.tap(find.byKey(const Key('login-button')));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  void desktop(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('admin can set names and create a user through real views', (
    tester,
  ) async {
    desktop(tester);
    final platform = _UiPlatformApi(role: 'admin');
    await tester.pumpWidget(
      StoreOsApp(
        api: _UiSessionApi(),
        platformApi: platform,
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
    );
    await login(tester);
    await tester.tap(find.text('Organisation').first);
    await tester.pumpAndSettle();
    expect(find.text('Einrichtung offen'), findsOneWidget);

    await tester.tap(find.byKey(const Key('organization-setup')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Unternehmensname'),
      'Store GmbH',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Name des ersten Standorts'),
      'Mitte',
    );
    await tester.tap(find.text('Speichern').last);
    await tester.pumpAndSettle();
    expect(platform.posts.last.$1, '/organization/setup');
    expect(find.text('Store GmbH'), findsOneWidget);

    await tester.tap(find.text('Benutzer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-user')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Benutzername'),
      'anna',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Startpasswort'),
      'long-secret',
    );
    await tester.tap(find.text('Anlegen').last);
    await tester.pumpAndSettle();
    expect(platform.posts.last.$1, '/users');
    expect(platform.posts.last.$2['role'], 'viewer');
    expect(find.text('anna'), findsOneWidget);
  });

  testWidgets('viewer sees only status and own organization context', (
    tester,
  ) async {
    desktop(tester);
    final platform = _UiPlatformApi(role: 'viewer');
    await tester.pumpWidget(
      StoreOsApp(
        api: _UiSessionApi(),
        platformApi: platform,
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
    );
    await login(tester);
    expect(find.text('Benutzer'), findsNothing);
    expect(find.text('Audit'), findsNothing);
    expect(find.text('Plugins'), findsNothing);
    await tester.tap(find.text('Organisation').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('organization-setup')), findsNothing);
    expect(find.byKey(const Key('create-location')), findsNothing);
    expect(find.text('Nicht eingerichtet'), findsNothing);
  });

  testWidgets(
    'single-section loading state remains usable until context arrives',
    (tester) async {
      desktop(tester);
      final platform = _UiPlatformApi(role: 'admin');
      final contextReply = Completer<Map<String, dynamic>>();
      platform.delayedContext = contextReply;
      await tester.pumpWidget(
        StoreOsApp(
          api: _UiSessionApi(),
          platformApi: platform,
          baseUri: Uri.parse('http://127.0.0.1:8080'),
        ),
      );
      await login(tester, settle: false);
      expect(find.text('Standort-Systemstatus'), findsOneWidget);
      contextReply.complete(platform.contextJson);
      await tester.pumpAndSettle();
      expect(find.text('Organisation'), findsOneWidget);
    },
  );

  testWidgets('mobile plugin token disappears when session expires', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final platform = _UiPlatformApi(role: 'admin');
    await tester.pumpWidget(
      StoreOsApp(
        api: _UiSessionApi(sessionLength: const Duration(seconds: 20)),
        platformApi: platform,
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
    );
    await login(tester);
    await tester.tap(find.byKey(const Key('open-navigation')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plugins').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('approve-sample.plugin')));
    await tester.tap(find.byKey(const Key('approve-sample.plugin')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckboxListTile, 'organization.read'),
    );
    await tester.tap(find.text('Freigeben und Token erzeugen'));
    await tester.pumpAndSettle();
    expect(find.text('Token verborgen'), findsOneWidget);
    expect(find.text('secret-plugin-token'), findsNothing);
    await tester.tap(find.text('Anzeigen'));
    await tester.pump();
    expect(find.byKey(const Key('plugin-token')), findsOneWidget);

    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-button')), findsOneWidget);
    expect(find.byKey(const Key('plugin-token')), findsNothing);
  });

  testWidgets('password change returns to login with a success notice', (
    tester,
  ) async {
    desktop(tester);
    final platform = _UiPlatformApi(role: 'viewer');
    final api = _UiSessionApi();
    await tester.pumpWidget(
      StoreOsApp(
        api: api,
        platformApi: platform,
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
    );
    await login(tester);
    await tester.tap(find.byKey(const Key('change-password-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'old-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'different-password-123',
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('change-password-error')), findsOneWidget);
    expect(api.changePasswordCalls, 0);

    // Six two-byte characters are below 12 code points but exactly 12 UTF-8
    // bytes and therefore pass the byte-based policy.
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'ä' * 6,
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'ä' * 6,
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(api.changePasswordCalls, 1);
    expect(api.lastCurrentPassword, 'old-password-123');
    expect(api.lastNewPassword, 'ä' * 6);
    expect(find.byKey(const Key('login-button')), findsOneWidget);
    expect(find.text('Passwort geändert'), findsOneWidget);
    expect(find.textContaining('neuen Passwort'), findsOneWidget);
  });

  testWidgets('wrong current password keeps the dialog open with an error', (
    tester,
  ) async {
    desktop(tester);
    final platform = _UiPlatformApi(role: 'viewer');
    final api = _UiSessionApi()
      ..changePasswordError = const StoreApiException(
        'invalid_current_password',
        'Das aktuelle Passwort ist nicht korrekt.',
        statusCode: 422,
      );
    await tester.pumpWidget(
      StoreOsApp(
        api: api,
        platformApi: platform,
        baseUri: Uri.parse('http://127.0.0.1:8080'),
      ),
    );
    await login(tester);
    await tester.tap(find.byKey(const Key('change-password-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('current-password-field')),
      'wrong-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('new-password-field')),
      'new-password-123',
    );
    await tester.enterText(
      find.byKey(const Key('confirm-password-field')),
      'new-password-123',
    );
    await tester.tap(find.byKey(const Key('change-password-submit')));
    await tester.pumpAndSettle();

    expect(api.changePasswordCalls, 1);
    expect(
      find.text('Das aktuelle Passwort ist nicht korrekt.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('change-password-submit')), findsOneWidget);
    expect(find.byKey(const Key('login-button')), findsNothing);
  });
}

class _UiSessionApi implements StoreApi {
  _UiSessionApi({this.sessionLength = const Duration(hours: 1)});

  final Duration sessionLength;

  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'session-token',
    expiresAt: DateTime.now().toUtc().add(sessionLength),
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

  StoreApiException? changePasswordError;
  int changePasswordCalls = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    if (changePasswordError case final error?) throw error;
  }

  @override
  Future<void> logout(String token) async {}
}

class _UiPlatformApi implements PlatformApi {
  _UiPlatformApi({required this.role});
  final String role;
  final posts = <(String, Map<String, dynamic>)>[];
  Completer<Map<String, dynamic>>? delayedContext;
  String? companyName;
  String? locationName;
  final users = <Map<String, dynamic>>[];
  bool pluginApproved = false;

  Map<String, dynamic> get contextJson => {
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
            'identity.self.password',
            'audit.read',
            'events.read',
            'events.write',
            'plugins.read',
            'plugins.write',
          ]
        : ['organization.read', 'identity.self.password'],
  };

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
  }) async {
    switch (route) {
      case '/context':
        if (delayedContext case final pending?) return pending.future;
        return contextJson;
      case '/organization':
        return {
          'company': {'id': 'company-1', 'name': companyName, 'version': 1},
          'locations': [
            {
              'id': 'location-1',
              'companyId': 'company-1',
              'name': locationName,
              'version': 1,
            },
          ],
        };
      case '/users':
        return {'users': users};
      case '/audit':
      case '/events':
        return {'items': [], 'nextCursor': null};
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
              'status': pluginApproved ? 'approved' : 'registered',
              'version': pluginApproved ? 2 : 1,
              'locationId': pluginApproved ? 'location-1' : null,
              'permissions': pluginApproved
                  ? ['organization.read']
                  : <String>[],
              'subscriptions': <String>[],
              'tokenExpiresAt': pluginApproved ? '2030-01-01T00:00:00Z' : null,
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
    posts.add((route, body));
    switch (route) {
      case '/organization/setup':
        companyName = body['companyName'] as String;
        locationName = body['locationName'] as String;
        return get(token, '/organization');
      case '/users':
        final user = {
          'id': body['id'],
          'username': body['username'],
          'companyId': 'company-1',
          'locationId': body['locationId'],
          'role': body['role'],
          'isActive': true,
          'version': 1,
        };
        users.add(user);
        return user;
      case '/plugins/sample.plugin/approve':
        pluginApproved = true;
        final plugins = await get(token, '/plugins');
        return {
          'plugin': (plugins['plugins'] as List).first,
          'token': 'secret-plugin-token',
          'expiresAt': '2030-01-01T00:00:00Z',
        };
      default:
        throw StateError('Unexpected POST $route');
    }
  }
}
