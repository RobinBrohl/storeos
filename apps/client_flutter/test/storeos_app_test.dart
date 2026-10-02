import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/app/storeos_app.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  final baseUri = Uri.parse('http://127.0.0.1:8080');

  Future<void> fillAndLogin(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('username-field')), 'robin');
    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.ensureVisible(find.byKey(const Key('login-button')));
    await tester.tap(find.byKey(const Key('login-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows real status after login and lets user log out', (
    tester,
  ) async {
    final api = StubStoreApi();
    await tester.pumpWidget(StoreOsApp(api: api, baseUri: baseUri));

    await fillAndLogin(tester);
    expect(find.text('Standortserver erreichbar'), findsOneWidget);
    expect(find.text('company-1'), findsOneWidget);
    expect(api.statusCalls, 1);

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-button')), findsOneWidget);
    expect(find.text('Standortserver erreichbar'), findsNothing);
    expect(api.logoutCalls, 1);
  });

  testWidgets('failed refresh removes old healthy status and explains outage', (
    tester,
  ) async {
    final api = StubStoreApi();
    await tester.pumpWidget(StoreOsApp(api: api, baseUri: baseUri));
    await fillAndLogin(tester);

    api.statusError = const StoreApiException(
      'network_unavailable',
      'Der Standortserver ist nicht erreichbar.',
    );
    await tester.tap(find.byKey(const Key('refresh-button')));
    await tester.pumpAndSettle();

    expect(find.text('Standortserver erreichbar'), findsNothing);
    expect(find.text('Status nicht abrufbar'), findsOneWidget);
    expect(
      find.text('Der Standortserver ist nicht erreichbar.'),
      findsOneWidget,
    );
  });

  testWidgets('login error is shown without entering status screen', (
    tester,
  ) async {
    final api = StubStoreApi()
      ..loginError = const StoreApiException(
        'invalid_credentials',
        'Anmeldung fehlgeschlagen.',
        statusCode: 401,
      );
    await tester.pumpWidget(StoreOsApp(api: api, baseUri: baseUri));

    await fillAndLogin(tester);

    expect(find.text('Anmeldung nicht möglich'), findsOneWidget);
    expect(find.text('Anmeldung fehlgeschlagen.'), findsOneWidget);
    expect(find.text('Standort-Systemstatus'), findsNothing);
  });

  testWidgets('failed server logout still removes the local session', (
    tester,
  ) async {
    final api = StubStoreApi()
      ..logoutError = const StoreApiException(
        'network_unavailable',
        'Der Standortserver ist nicht erreichbar.',
      );
    await tester.pumpWidget(StoreOsApp(api: api, baseUri: baseUri));
    await fillAndLogin(tester);

    await tester.tap(find.byKey(const Key('logout-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('login-button')), findsOneWidget);
    expect(find.text('Abmeldung'), findsOneWidget);
    expect(
      find.textContaining('Serverabmeldung konnte nicht bestätigt'),
      findsOneWidget,
    );
  });
}

class StubStoreApi implements StoreApi {
  StoreApiException? loginError;
  StoreApiException? statusError;
  StoreApiException? logoutError;
  int statusCalls = 0;
  int logoutCalls = 0;

  @override
  Future<SessionResponse> login(LoginRequest request) async {
    if (loginError case final error?) throw error;
    return SessionResponse(
      token: 'test-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      user: const SessionUser(
        id: 'user-1',
        username: 'robin',
        companyId: 'company-1',
        locationId: 'location-1',
      ),
    );
  }

  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    statusCalls++;
    if (statusError case final error?) throw error;
    return const SystemStatusResponse(
      companyId: 'company-1',
      locationId: 'location-1',
    );
  }

  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> logout(String token) async {
    logoutCalls++;
    if (logoutError case final error?) throw error;
  }
}
