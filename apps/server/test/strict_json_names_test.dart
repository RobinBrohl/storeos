import 'dart:convert';
import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/http/api_support.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

Future<Map<String, dynamic>> read(String source, {bool strict = true}) =>
    readJson(
      Request(
        'POST',
        Uri.parse('http://localhost/'),
        headers: {'content-type': 'application/json'},
        body: source,
      ),
      rejectDuplicateNames: strict,
    );
Matcher code(String expected) =>
    throwsA(isA<PlatformFailure>().having((e) => e.code, 'code', expected));

void main() {
  test(
    'decoded names including escaped quotes, slashes and Unicode collide',
    () async {
      for (final source in [
        r'{"x":1,"\u0078":2}',
        r'{"a\"b":1,"a\u0022b":2}',
        r'{"a\\b":1,"a\u005cb":2}',
        r'{"😀":1,"\ud83d\ude00":2}',
        r'{"nested":[{"q":1,"q":2}]}',
        r'{"":1,"":2}',
      ]) {
        await expectLater(read(source), code('invalid_json'));
      }
    },
  );
  test(
    'objects have independent names and repeated values are valid',
    () async {
      for (final source in [
        r'{"x":"x","y":"x","nested":{"x":1}}',
        r'{"items":[{"x":1},{"x":2}]}',
        r'{"escaped":"\"},[","a\\b":1,"a/b":2}',
        r'{"a":[],"b":{},"c":[[{}]],"d":null,"e":true}',
      ]) {
        expect(await read(source), jsonDecode(source));
      }
    },
  );
  test(
    'canonical grammar and malformed UTF-8 still fail as invalid_json',
    () async {
      for (final source in [
        '{',
        '[]',
        r'{"x":"\q"}',
        r'{"x":"unterminated}',
        r'{"x":1,}',
        r'{"x":01}',
        r'{"x":[1}',
        r'{"x":NaN}',
      ]) {
        await expectLater(read(source), code('invalid_json'));
      }
      await expectLater(
        readJson(
          Request(
            'POST',
            Uri.parse('http://localhost/'),
            headers: {'content-type': 'application/json'},
            body: [0xff],
          ),
          rejectDuplicateNames: true,
        ),
        code('invalid_json'),
      );
    },
  );
  test('duplicate enforcement is opt-in for unrelated APIs', () async {
    expect(await read(r'{"x":1,"x":2}', strict: false), {'x': 2});
  });
  test('streamed byte limit rejects before decoding', () async {
    await expectLater(
      readJson(
        Request(
          'POST',
          Uri.parse('http://localhost/'),
          headers: {'content-type': 'application/json'},
          body: Stream.fromIterable([
            utf8.encode('{"x":'),
            utf8.encode('"large"}'),
          ]),
        ),
        limit: 8,
        rejectDuplicateNames: true,
      ),
      code('body_too_large'),
    );
  });
  test('deep nesting uses iterative scope tracking', () async {
    final source = '{"x":${'[' * 4000}{"x":1}${']' * 4000}}';
    expect((await read(source)).containsKey('x'), true);
  });
}
