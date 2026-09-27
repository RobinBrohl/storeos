import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test('uses the configured routes and bearer token', () async {
    final session = SessionResponse(
      token: 'sensitive-token',
      expiresAt: DateTime.utc(2026, 9, 27, 18),
      user: const SessionUser(
        id: 'user-1',
        username: 'robin',
        companyId: 'company-1',
        locationId: 'location-1',
      ),
    );
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/login') {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {
          'username': 'robin',
          'password': 'secret',
        });
        return http.Response(jsonEncode(session.toJson()), 200);
      }
      if (request.url.path == '/api/v1/locations/location-1/system/status') {
        expect(request.method, 'GET');
        expect(request.headers['Authorization'], 'Bearer sensitive-token');
        return http.Response(
          jsonEncode(
            const SystemStatusResponse(
              companyId: 'company-1',
              locationId: 'location-1',
            ).toJson(),
          ),
          200,
        );
      }
      expect(request.url.path, '/api/v1/auth/logout');
      expect(request.headers['Authorization'], 'Bearer sensitive-token');
      return http.Response('', 204);
    });
    final api = HttpStoreApi(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      client: client,
    );

    final loggedIn = await api.login(
      const LoginRequest(username: 'robin', password: 'secret'),
    );
    final status = await api.systemStatus(
      token: loggedIn.token,
      locationId: loggedIn.user.locationId,
    );
    await api.logout(loggedIn.token);

    expect(status.database, 'reachable');
  });

  test('surfaces structured HTTP errors', () async {
    final api = HttpStoreApi(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode(
            const ApiError(
              code: 'invalid_credentials',
              message: 'Anmeldung fehlgeschlagen.',
            ).toJson(),
          ),
          401,
        ),
      ),
    );

    await expectLater(
      api.login(const LoginRequest(username: 'robin', password: 'wrong')),
      throwsA(
        isA<StoreApiException>()
            .having((error) => error.code, 'code', 'invalid_credentials')
            .having(
              (error) => error.message,
              'message',
              'Anmeldung fehlgeschlagen. Zugangsdaten prüfen.',
            )
            .having((error) => error.statusCode, 'statusCode', 401),
      ),
    );
  });
}
