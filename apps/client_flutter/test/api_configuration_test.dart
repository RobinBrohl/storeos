import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/config/api_configuration.dart';

void main() {
  test('accepts local HTTP and remote HTTPS', () {
    expect(
      ApiConfiguration.parse('http://127.0.0.1:8080').baseUri.origin,
      'http://127.0.0.1:8080',
    );
    expect(
      ApiConfiguration.parse('https://store.example.org').baseUri.scheme,
      'https',
    );
  });

  test('rejects remote HTTP, credentials and non-root paths', () {
    expect(
      () => ApiConfiguration.parse('http://store.example.org'),
      throwsFormatException,
    );
    expect(
      () => ApiConfiguration.parse('https://user:secret@store.example.org'),
      throwsFormatException,
    );
    expect(
      () => ApiConfiguration.parse('https://store.example.org/admin'),
      throwsFormatException,
    );
  });
}
