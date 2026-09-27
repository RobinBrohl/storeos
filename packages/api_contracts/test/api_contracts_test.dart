import 'dart:convert';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> wire(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  test('session survives the actual JSON wire representation', () {
    final session = SessionResponse(
      token: 'opaque-session-token',
      expiresAt: DateTime.utc(2026, 9, 27, 12),
      user: const SessionUser(
        id: 'account-1',
        username: 'operator',
        companyId: 'company-1',
        locationId: 'location-1',
      ),
    );
    final decoded = SessionResponse.fromJson(wire(session.toJson()));
    expect(decoded.toJson(), session.toJson());
    expect(decoded.expiresAt.isUtc, isTrue);
  });

  test('missing, mistyped and unzoned session fields are rejected', () {
    expect(
      () => LoginRequest.fromJson({'username': 'operator'}),
      throwsFormatException,
    );
    expect(
      () => HealthResponse.fromJson({'status': true}),
      throwsFormatException,
    );
    expect(
      () => SessionResponse.fromJson({
        'token': 'token',
        'expiresAt': '2026-09-27T12:00:00',
        'user': <String, dynamic>{},
      }),
      throwsFormatException,
    );
    expect(
      () => SystemStatusResponse.fromJson({'apiVersion': '1'}),
      throwsFormatException,
    );
  });

  test('additive response fields remain compatible', () {
    final response = SystemStatusResponse.fromJson({
      'service': 'storeos',
      'apiVersion': 1,
      'companyId': 'company-1',
      'locationId': 'location-1',
      'database': 'reachable',
      'futureOptionalField': 'ignored',
    });
    expect(response.locationId, 'location-1');
  });

  test('health and safe error contracts round trip', () {
    const health = HealthResponse(status: 'unavailable');
    const error = ApiError(code: 'unauthorized', message: 'Sign in required.');
    expect(
      HealthResponse.fromJson(wire(health.toJson())).status,
      'unavailable',
    );
    expect(ApiError.fromJson(wire(error.toJson())).toJson(), error.toJson());
  });
}
