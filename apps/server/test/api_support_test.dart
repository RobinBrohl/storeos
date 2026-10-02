import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/http/api_support.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

void main() {
  test('readJson rejects an oversized body with 413 semantics', () {
    final request = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/platform/profile/password'),
      headers: {'content-type': 'application/json'},
      body: 'x' * 20000,
    );
    expect(
      readJson(request),
      throwsA(
        isA<PlatformFailure>()
            .having((error) => error.status, 'status', 413)
            .having((error) => error.code, 'code', 'body_too_large'),
      ),
    );
  });

  test('readJson rejects missing and unsupported content types', () {
    final noType = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/platform/profile/password'),
      body: '{}',
    );
    expect(
      readJson(noType),
      throwsA(
        isA<PlatformFailure>()
            .having((error) => error.status, 'status', 415)
            .having((error) => error.code, 'code', 'unsupported_media_type'),
      ),
    );
    final textType = Request(
      'POST',
      Uri.parse('http://localhost/api/v1/platform/profile/password'),
      headers: {'content-type': 'text/plain'},
      body: '{}',
    );
    expect(
      readJson(textType),
      throwsA(
        isA<PlatformFailure>().having(
          (error) => error.code,
          'code',
          'unsupported_media_type',
        ),
      ),
    );
  });

  test('readJson maps malformed and non-object JSON to invalid_json', () {
    Future<void> rejects(String body) {
      final request = Request(
        'POST',
        Uri.parse('http://localhost/api/v1/platform/profile/password'),
        headers: {'content-type': 'application/json'},
        body: body,
      );
      return expectLater(
        readJson(request),
        throwsA(
          isA<PlatformFailure>().having(
            (error) => error.code,
            'code',
            'invalid_json',
          ),
        ),
      );
    }

    return Future.wait([rejects('not json'), rejects('[]')]);
  });
}
