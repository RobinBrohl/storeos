import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';

import 'platform_api.dart';
import 'store_api.dart';

class HttpPlatformApi implements PlatformApi {
  HttpPlatformApi({
    required Uri baseUri,
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
  }) : this._(baseUri, client, timeout);

  HttpPlatformApi._(this._baseUri, this._client, this.timeout);

  final Uri _baseUri;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) => _request(
    () => _client.get(
      _uri(route, after: after, query: query),
      headers: {'Authorization': 'Bearer $token'},
    ),
  );

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) => _request(
    () => _client.post(
      _uri(route),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    ),
  );

  Uri _uri(String route, {String? after, Map<String, String>? query}) {
    // P1 routes contain UUIDs or manifest IDs, never URI control characters.
    // Repeated dots inside a manifest ID are valid; traversal segments are not.
    if (!RegExp(r'^/[A-Za-z0-9._/-]+$').hasMatch(route) ||
        route.split('/').any((part) => part == '.' || part == '..')) {
      throw ArgumentError.value(route, 'route', 'Ungültiger API-Pfad');
    }
    final uri = _baseUri.resolve('/api/v1/platform$route');
    final parameters = <String, String>{...?query, 'after': ?after};
    return parameters.isEmpty ? uri : uri.replace(queryParameters: parameters);
  }

  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send,
  ) async {
    late final http.Response response;
    try {
      response = await send().timeout(timeout);
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String code = 'http_${response.statusCode}';
      try {
        code = ApiError.fromJson(_object(response.body)).code;
      } catch (_) {
        // The status code still determines the safe user-facing message.
      }
      throw StoreApiException(code, switch (response.statusCode) {
        401 => 'Die Sitzung ist nicht mehr gültig. Bitte erneut anmelden.',
        403 => 'Für diese Aktion fehlt die Berechtigung.',
        409 =>
          'Der Datensatz wurde inzwischen geändert. Die Ansicht wird neu geladen.',
        400 || 422 => 'Die Eingaben wurden vom Server abgelehnt.',
        _ =>
          'Der Standortserver hat einen Fehler gemeldet (${response.statusCode}).',
      }, statusCode: response.statusCode);
    }
    if (response.body.trim().isEmpty) return const {};
    try {
      return _object(response.body);
    } on FormatException {
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
