import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test('valid plugin IDs with repeated dots remain addressable', () async {
    final requests = <http.Request>[];
    final api = HttpPlatformApi(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      }),
    );
    await api.post('session-secret', '/plugins/test..reader/disable', {
      'expectedVersion': 1,
    });
    expect(
      requests.single.url.path,
      '/api/v1/platform/plugins/test..reader/disable',
    );
    for (final route in [
      '/../auth/login',
      '/%2e%2e/auth/login',
      '/plugins#fragment',
      '/plugins?query=1',
    ]) {
      await expectLater(api.get('session-secret', route), throwsArgumentError);
    }
    expect(requests, hasLength(1));
  });
  test('platform routes carry bearer token, cursor and JSON body', () async {
    final requests = <http.Request>[];
    final api = HttpPlatformApi(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'items': [], 'nextCursor': null}),
          200,
        );
      }),
    );

    await api.get('session-secret', '/audit', after: 'a+b/==');
    await api.post('session-secret', '/company', {
      'name': 'Neuer Name',
      'expectedVersion': 3,
    });

    expect(requests[0].url.path, '/api/v1/platform/audit');
    expect(requests[0].url.queryParameters['after'], 'a+b/==');
    expect(requests[0].headers['Authorization'], 'Bearer session-secret');
    expect(requests[1].method, 'POST');
    expect(jsonDecode(requests[1].body), {
      'name': 'Neuer Name',
      'expectedVersion': 3,
    });
    expect(requests[1].headers['Content-Type'], contains('application/json'));
  });

  test('HTTP 409 explains reload without exposing server message', () async {
    final api = HttpPlatformApi(
      baseUri: Uri.parse('http://127.0.0.1:8080'),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'code': 'version_conflict',
            'message': 'internal detail',
          }),
          409,
        ),
      ),
    );

    await expectLater(
      api.post('session-secret', '/company', {
        'name': 'Neu',
        'expectedVersion': 1,
      }),
      throwsA(
        isA<StoreApiException>()
            .having((error) => error.statusCode, 'statusCode', 409)
            .having(
              (error) => error.message,
              'message',
              contains('neu geladen'),
            ),
      ),
    );
  });
}
