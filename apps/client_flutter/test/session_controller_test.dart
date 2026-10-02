import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  final now = DateTime.utc(2026, 9, 27, 12);

  test(
    'login loads a status only for the assigned company and location',
    () async {
      final api = FakeStoreApi(now);
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);

      await controller.signIn(username: ' robin ', password: 'secret');

      expect(api.lastUsername, 'robin');
      expect(controller.isAuthenticated, isTrue);
      expect(controller.status?.database, 'reachable');
      expect(controller.error, isNull);
    },
  );

  test(
    'status failure is visible and does not invent a healthy status',
    () async {
      final api = FakeStoreApi(now)
        ..statusError = const StoreApiException(
          'network_unavailable',
          'Der Standortserver ist nicht erreichbar.',
        );
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);

      await controller.signIn(username: 'robin', password: 'secret');

      expect(controller.isAuthenticated, isTrue);
      expect(controller.status, isNull);
      expect(controller.error, contains('nicht erreichbar'));
    },
  );

  test('unauthorized status clears the in-memory session', () async {
    final api = FakeStoreApi(now)
      ..statusError = const StoreApiException(
        'unauthorized',
        'Sitzung ungültig.',
        statusCode: 401,
      );
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);

    await controller.signIn(username: 'robin', password: 'secret');

    expect(controller.isAuthenticated, isFalse);
    expect(controller.status, isNull);
    expect(controller.error, contains('erneut anmelden'));
  });

  test('logout clears local session even if server logout fails', () async {
    final api = FakeStoreApi(now);
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);
    await controller.signIn(username: 'robin', password: 'secret');
    api.logoutError = const StoreApiException('network_unavailable', 'Offline');

    await controller.signOut();

    expect(api.loggedOutToken, 'test-token');
    expect(controller.isAuthenticated, isFalse);
    expect(controller.status, isNull);
    expect(
      controller.notice,
      contains('Serverabmeldung konnte nicht bestätigt'),
    );
  });

  test('late status response cannot restore an expired session', () async {
    var clock = now;
    final api = FakeStoreApi(now)
      ..pendingStatus = Completer<SystemStatusResponse>();
    final controller = SessionController(api, now: () => clock);
    addTearDown(controller.dispose);

    final signIn = controller.signIn(username: 'robin', password: 'secret');
    await Future<void>.delayed(Duration.zero);
    clock = now.add(const Duration(hours: 2));
    api.pendingStatus!.complete(api.response);
    await signIn;

    expect(controller.isAuthenticated, isFalse);
    expect(controller.status, isNull);
    expect(controller.error, contains('abgelaufen'));
  });

  test('late login response cannot write into a disposed controller', () async {
    final api = FakeStoreApi(now)..pendingLogin = Completer<SessionResponse>();
    final controller = SessionController(api, now: () => now);

    final signIn = controller.signIn(username: 'robin', password: 'secret');
    controller.dispose();
    api.pendingLogin!.complete(api.session);
    await signIn;

    expect(controller.isAuthenticated, isFalse);
    expect(api.statusCalls, 0);
  });

  test('unknown database state is not presented as healthy', () async {
    final api = FakeStoreApi(now)
      ..response = const SystemStatusResponse(
        companyId: 'company-1',
        locationId: 'location-1',
        database: 'unknown',
      );
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);

    await controller.signIn(username: 'robin', password: 'secret');

    expect(controller.isAuthenticated, isTrue);
    expect(controller.status, isNull);
    expect(controller.error, contains('keine erreichbare Datenbank'));
  });

  test(
    'password change clears the session and announces the new login',
    () async {
      final api = FakeStoreApi(now);
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);
      await controller.signIn(username: 'robin', password: 'secret');

      final changed = await controller.changePassword(
        currentPassword: 'old-password-123',
        newPassword: 'new-password-123',
      );

      expect(changed, isTrue);
      expect(api.lastToken, 'test-token');
      expect(api.lastCurrentPassword, 'old-password-123');
      expect(api.lastNewPassword, 'new-password-123');
      expect(controller.isAuthenticated, isFalse);
      expect(controller.noticeTitle, 'Passwort geändert');
      expect(controller.noticePositive, isTrue);
      expect(controller.notice, contains('neuen Passwort'));
    },
  );

  test(
    'wrong current password keeps the session and shows the static error',
    () async {
      final api = FakeStoreApi(now)
        ..changePasswordError = const StoreApiException(
          'invalid_current_password',
          'Das aktuelle Passwort ist nicht korrekt.',
          statusCode: 422,
        );
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);
      await controller.signIn(username: 'robin', password: 'secret');

      final changed = await controller.changePassword(
        currentPassword: 'old-password-123',
        newPassword: 'new-password-123',
      );

      expect(changed, isFalse);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.error, 'Das aktuelle Passwort ist nicht korrekt.');
    },
  );

  test(
    'rate limiting keeps the session and shows the throttling message',
    () async {
      final api = FakeStoreApi(now)
        ..changePasswordError = const StoreApiException(
          'rate_limited',
          'Zu viele Versuche. Bitte später erneut versuchen.',
          statusCode: 429,
        );
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);
      await controller.signIn(username: 'robin', password: 'secret');

      final changed = await controller.changePassword(
        currentPassword: 'old-password-123',
        newPassword: 'new-password-123',
      );

      expect(changed, isFalse);
      expect(controller.isAuthenticated, isTrue);
      expect(controller.error, contains('Zu viele Versuche'));
    },
  );

  test(
    'an ambiguous transport outcome clears the session with a warning',
    () async {
      final api = FakeStoreApi(now)
        ..changePasswordError = const StoreApiException(
          'timeout',
          'Der Standortserver antwortet nicht rechtzeitig.',
        );
      final controller = SessionController(api, now: () => now);
      addTearDown(controller.dispose);
      await controller.signIn(username: 'robin', password: 'secret');

      final changed = await controller.changePassword(
        currentPassword: 'old-password-123',
        newPassword: 'new-password-123',
      );

      expect(changed, isFalse);
      expect(controller.isAuthenticated, isFalse);
      expect(controller.noticeTitle, 'Passwortänderung unklar');
      expect(controller.noticePositive, isFalse);
      expect(controller.notice, contains('bisherige Passwort'));
    },
  );

  test('an unauthorized password change expires the local session', () async {
    final api = FakeStoreApi(now)
      ..changePasswordError = const StoreApiException(
        'unauthorized',
        'Authentication required.',
        statusCode: 401,
      );
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);
    await controller.signIn(username: 'robin', password: 'secret');

    await controller.changePassword(
      currentPassword: 'old-password-123',
      newPassword: 'new-password-123',
    );

    expect(controller.isAuthenticated, isFalse);
    expect(controller.noticeTitle, 'Passwortänderung');
    expect(controller.noticePositive, isFalse);
  });

  test('a second submit while busy is ignored', () async {
    final api = FakeStoreApi(now)..pendingChangePassword = Completer<void>();
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);
    await controller.signIn(username: 'robin', password: 'secret');

    final first = controller.changePassword(
      currentPassword: 'old-password-123',
      newPassword: 'new-password-123',
    );
    final second = await controller.changePassword(
      currentPassword: 'old-password-123',
      newPassword: 'new-password-123',
    );

    expect(second, isFalse);
    expect(api.changePasswordCalls, 1);
    api.pendingChangePassword!.complete();
    expect(await first, isTrue);
  });

  test('client validation counts UTF-8 bytes, not characters', () async {
    final api = FakeStoreApi(now);
    final controller = SessionController(api, now: () => now);
    addTearDown(controller.dispose);
    await controller.signIn(username: 'robin', password: 'secret');

    final tooShort = await controller.changePassword(
      currentPassword: 'old-password-123',
      newPassword: 'ä' * 5,
    );
    expect(tooShort, isFalse);
    expect(api.changePasswordCalls, 0);
    expect(controller.error, contains('UTF-8-Bytes'));

    final byteValid = await controller.changePassword(
      currentPassword: 'old-password-123',
      newPassword: 'ä' * 6,
    );
    expect(byteValid, isTrue);
    expect(api.changePasswordCalls, 1);
  });
}

class FakeStoreApi implements StoreApi {
  FakeStoreApi(DateTime now)
    : session = SessionResponse(
        token: 'test-token',
        expiresAt: now.add(const Duration(hours: 1)),
        user: const SessionUser(
          id: 'user-1',
          username: 'robin',
          companyId: 'company-1',
          locationId: 'location-1',
        ),
      ),
      response = const SystemStatusResponse(
        companyId: 'company-1',
        locationId: 'location-1',
      );

  final SessionResponse session;
  SystemStatusResponse response;
  Completer<SessionResponse>? pendingLogin;
  Completer<SystemStatusResponse>? pendingStatus;
  StoreApiException? statusError;
  StoreApiException? logoutError;
  StoreApiException? changePasswordError;
  Completer<void>? pendingChangePassword;
  String? lastUsername;
  String? loggedOutToken;
  String? lastToken;
  String? lastCurrentPassword;
  String? lastNewPassword;
  int statusCalls = 0;
  int changePasswordCalls = 0;

  @override
  Future<SessionResponse> login(LoginRequest request) async {
    lastUsername = request.username;
    return pendingLogin?.future ?? session;
  }

  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    statusCalls++;
    if (statusError case final error?) throw error;
    return pendingStatus?.future ?? response;
  }

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    lastToken = token;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
    if (changePasswordError case final error?) throw error;
    await pendingChangePassword?.future;
  }

  @override
  Future<void> logout(String token) async {
    loggedOutToken = token;
    if (logoutError case final error?) throw error;
  }
}
