import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';

import 'store_api.dart';

class HttpStoreApi implements StoreApi {
  HttpStoreApi({
    required Uri baseUri,
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
  }) : this._(baseUri, client, timeout);

  HttpStoreApi._(this._baseUri, this._client, this.timeout);

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<SessionResponse> login(LoginRequest request) async {
    final response = await _send(
      () => _client.post(
        _baseUri.resolve('/api/v1/auth/login'),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      ),
    );
    _requireStatus(response, 200);
    return _decode(() => SessionResponse.fromJson(_object(response.body)));
  }

  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    final safeLocationId = Uri.encodeComponent(locationId);
    final response = await _send(
      () => _client.get(
        _baseUri.resolve('/api/v1/locations/$safeLocationId/system/status'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    _requireStatus(response, 200);
    return _decode(() => SystemStatusResponse.fromJson(_object(response.body)));
  }

  @override
  Future<void> logout(String token) async {
    final response = await _send(
      () => _client.post(
        _baseUri.resolve('/api/v1/auth/logout'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    _requireStatus(response, 204);
  }

  Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      throw const StoreApiException(
        'timeout',
        'Der Standortserver antwortet nicht rechtzeitig.',
      );
    } on http.ClientException {
      throw const StoreApiException(
        'network_unavailable',
        'Der Standortserver ist nicht erreichbar.',
      );
    }
  }

  void _requireStatus(http.Response response, int expected) {
    if (response.statusCode == expected) return;

    try {
      final apiError = ApiError.fromJson(_object(response.body));
      throw StoreApiException(
        apiError.code,
        _messageFor(apiError.code, response.statusCode),
        statusCode: response.statusCode,
      );
    } on StoreApiException {
      rethrow;
    } on FormatException {
      throw StoreApiException(
        'http_${response.statusCode}',
        'Der Standortserver hat einen Fehler gemeldet (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    } on TypeError {
      throw StoreApiException(
        'http_${response.statusCode}',
        'Der Standortserver hat einen Fehler gemeldet (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  String _messageFor(String code, int statusCode) => switch (code) {
    'invalid_credentials' => 'Anmeldung fehlgeschlagen. Zugangsdaten prüfen.',
    'invalid_token' || 'unauthorized' =>
      'Die Sitzung ist nicht mehr gültig. Bitte erneut anmelden.',
    'forbidden' => 'Für diesen Standort fehlt die Berechtigung.',
    'database_unavailable' ||
    'service_unavailable' => 'Der Standortserver ist derzeit nicht bereit.',
    _ => 'Der Standortserver hat einen Fehler gemeldet ($statusCode).',
  };

  T _decode<T>(T Function() parse) {
    try {
      return parse();
    } on FormatException {
      throw const StoreApiException(
        'invalid_response',
        'Die Serverantwort hat ein ungültiges Format.',
      );
    } on TypeError {
      throw const StoreApiException(
        'invalid_response',
        'Die Serverantwort hat ein ungültiges Format.',
      );
    }
  }

  Map<String, dynamic> _object(String body) {
    final value = jsonDecode(body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('JSON-Objekt erwartet.');
    }
    return value;
  }
}
