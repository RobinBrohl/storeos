import 'dart:convert';
import 'dart:io';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const _path = '/api/v1/platform/profile/password';

void main() {
  group('ChangePasswordRequest', () {
    test('round-trips exactly currentPassword and newPassword', () {
      const request = ChangePasswordRequest(
        currentPassword: 'current-password-value',
        newPassword: 'replacement-password-value',
      );
      final json = request.toJson();
      expect(json.keys.toSet(), {'currentPassword', 'newPassword'});
      final parsed = ChangePasswordRequest.fromJson(json);
      expect(parsed.currentPassword, request.currentPassword);
      expect(parsed.newPassword, request.newPassword);
    });

    test('rejects unknown, missing and non-string fields', () {
      expect(
        () => ChangePasswordRequest.fromJson({
          'currentPassword': 'a',
          'newPassword': 'b',
          'userId': 'not allowed',
        }),
        throwsFormatException,
      );
      expect(
        () => ChangePasswordRequest.fromJson({'currentPassword': 'a'}),
        throwsFormatException,
      );
      expect(
        () => ChangePasswordRequest.fromJson({
          'currentPassword': 'a',
          'newPassword': 2,
        }),
        throwsFormatException,
      );
      expect(
        () => ChangePasswordRequest.fromJson(const {}),
        throwsFormatException,
      );
    });
  });

  group('UTF-8 byte policy', () {
    test('ASCII boundary is 12 bytes', () {
      expect(newPasswordProblem('a' * 11), isNotNull);
      expect(newPasswordProblem('a' * 12), isNull);
      expect(newPasswordProblem('a' * passwordMaxUtf8Bytes), isNull);
      expect(newPasswordProblem('a' * (passwordMaxUtf8Bytes + 1)), isNotNull);
    });

    test('multibyte values are measured in UTF-8 bytes, not code points', () {
      // Six two-byte characters: 6 code points but 12 UTF-8 bytes.
      expect('ä' * 6, hasLength(6));
      expect(passwordUtf8ByteLength('ä' * 6), 12);
      expect(newPasswordProblem('ä' * 6), isNull);

      // Five two-byte characters: 10 UTF-8 bytes, below the minimum.
      expect(passwordUtf8ByteLength('ä' * 5), 10);
      expect(newPasswordProblem('ä' * 5), isNotNull);

      // 512 two-byte characters are exactly the maximum; one more byte fails.
      expect(passwordUtf8ByteLength('ä' * 512), passwordMaxUtf8Bytes);
      expect(newPasswordProblem('ä' * 512), isNull);
      expect(passwordUtf8ByteLength('${'ä' * 512}a'), 1025);
      expect(newPasswordProblem('${'ä' * 512}a'), isNotNull);

      // Three-byte characters: 4 code points is only 12 bytes.
      expect(passwordUtf8ByteLength('€' * 4), 12);
      expect(newPasswordProblem('€' * 4), isNull);
    });

    test('current password is non-empty and bounded in UTF-8 bytes', () {
      expect(currentPasswordProblem(''), isNotNull);
      expect(currentPasswordProblem('x'), isNull);
      expect(currentPasswordProblem('ä' * 512), isNull);
      expect(currentPasswordProblem('ä' * 512 + 'a'), isNotNull);
    });

    test('new password must differ from the current password', () {
      const request = ChangePasswordRequest(
        currentPassword: 'same-password-value',
        newPassword: 'same-password-value',
      );
      expect(changePasswordProblem(request), isNotNull);
      expect(
        changePasswordProblem(
          const ChangePasswordRequest(
            currentPassword: 'current-password-value',
            newPassword: 'different-password-value',
          ),
        ),
        isNull,
      );
    });
  });

  group('OpenAPI containment', () {
    late Map<String, dynamic> document;
    late String yaml;

    setUpAll(() {
      document =
          jsonDecode(File('platform.openapi.json').readAsStringSync())
              as Map<String, dynamic>;
      yaml = File('openapi.yaml').readAsStringSync();
    });

    test('documents the self-service password route in both files', () {
      final path = (document['paths'] as Map)[_path] as Map;
      final operation = path['post'] as Map;
      expect(operation['operationId'], 'changeOwnPassword');
      expect(operation['security'], [
        {'session': <String>[]},
      ]);
      expect((operation['requestBody'] as Map)['required'], isTrue);
      expect(
        yaml,
        contains(
          "'./platform.openapi.json#/paths/"
          '~1api~1v1~1platform~1profile~1password\'',
        ),
      );
    });

    test('request schema requires exactly the two documented fields', () {
      final schemas =
          ((document['components'] as Map)['schemas']) as Map<String, dynamic>;
      final schema = schemas['ChangePassword'] as Map<String, dynamic>;
      expect(schema['additionalProperties'], isFalse);
      expect(
        schema['required'],
        containsAll(['currentPassword', 'newPassword']),
      );
      expect(schema['required'], hasLength(2));
      final properties = schema['properties'] as Map<String, dynamic>;
      expect(properties.keys.toSet(), {'currentPassword', 'newPassword'});
      for (final property in properties.values) {
        expect((property as Map)['writeOnly'], isTrue);
        expect(property['type'], 'string');
        expect(property['format'], 'password');
      }
    });

    test(
      'byte limits match shared constants and are not minLength/maxLength',
      () {
        final schemas =
            ((document['components'] as Map)['schemas'])
                as Map<String, dynamic>;
        final schema = schemas['ChangePassword'] as Map<String, dynamic>;
        final properties = schema['properties'] as Map<String, dynamic>;
        final current = properties['currentPassword'] as Map<String, dynamic>;
        final next = properties['newPassword'] as Map<String, dynamic>;

        expect(current['x-storeos-min-utf8-bytes'], 1);
        expect(current['x-storeos-max-utf8-bytes'], passwordMaxUtf8Bytes);
        expect(next['x-storeos-min-utf8-bytes'], passwordMinUtf8Bytes);
        expect(next['x-storeos-max-utf8-bytes'], passwordMaxUtf8Bytes);
        expect(current.containsKey('minLength'), isFalse);
        expect(current.containsKey('maxLength'), isFalse);
        expect(next.containsKey('minLength'), isFalse);
        expect(next.containsKey('maxLength'), isFalse);
        expect(current['description'], contains('UTF-8 bytes'));
        expect(next['description'], contains('UTF-8 bytes'));
        expect(next['description'], contains('$passwordMinUtf8Bytes'));
        expect(next['description'], contains('$passwordMaxUtf8Bytes'));
      },
    );

    test('204 has no content and the explicit error set is complete', () {
      final operation =
          ((document['paths'] as Map)[_path] as Map)['post'] as Map;
      final responses = operation['responses'] as Map<String, dynamic>;
      expect(responses.keys.toSet(), {
        '204',
        '400',
        '401',
        '403',
        '413',
        '415',
        '422',
        '429',
        '503',
        'default',
      });
      final success = responses['204'] as Map<String, dynamic>;
      expect(success.containsKey('content'), isFalse);
      expect(success['description'], contains('revoked'));
      expect(
        (responses['422'] as Map)['description'],
        contains('invalid_current_password'),
      );
      expect(
        (responses['429'] as Map)['description'],
        contains('rate_limited'),
      );
      expect(
        (responses['401'] as Map)['description'],
        contains('unauthorized'),
      );
      expect(
        (responses['403'] as Map)['description'],
        contains('identity.self.password'),
      );
    });
  });
}
