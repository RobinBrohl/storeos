import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class PasswordHasher {
  PasswordHasher({
    this.memoryKiB = 19456,
    this.iterations = 2,
    this.parallelism = 1,
    this.hashLength = 32,
    Random? random,
  }) : _random = random ?? Random.secure();

  final int memoryKiB;
  final int iterations;
  final int parallelism;
  final int hashLength;
  final Random _random;

  Future<String> hash(String password) async {
    final salt = List<int>.generate(16, (_) => _random.nextInt(256));
    final algorithm = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    final secret = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final result = await secret.extractBytes();
    final parameters = 'm=$memoryKiB,t=$iterations,p=$parallelism';
    return <String>[
      '',
      'argon2id',
      'v=19',
      parameters,
      _encode(salt),
      _encode(result),
    ].join(r'$');
  }

  Future<bool> verify(String password, String encoded) async {
    try {
      final fields = encoded.split(r'$');
      if (fields.length != 6 ||
          fields[0].isNotEmpty ||
          fields[1] != 'argon2id' ||
          fields[2] != 'v=19') {
        return false;
      }
      final match = RegExp(r'^m=(\d+),t=(\d+),p=(\d+)$').firstMatch(fields[3]);
      if (match == null) return false;
      final memory = int.parse(match[1]!);
      final rounds = int.parse(match[2]!);
      final lanes = int.parse(match[3]!);
      final salt = _decode(fields[4]);
      final expected = _decode(fields[5]);
      if (memory < 64 ||
          memory > 262144 ||
          rounds < 1 ||
          rounds > 10 ||
          lanes < 1 ||
          lanes > 8 ||
          salt.length < 16 ||
          salt.length > 64 ||
          expected.length < 16 ||
          expected.length > 64) {
        return false;
      }
      final algorithm = Argon2id(
        memory: memory,
        iterations: rounds,
        parallelism: lanes,
        hashLength: expected.length,
      );
      final actual = await (await algorithm.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      )).extractBytes();
      return _constantTimeEqual(actual, expected);
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  String _encode(List<int> bytes) => base64Encode(bytes).replaceAll('=', '');

  List<int> _decode(String value) {
    // Accept hashes issued before canonical PHC encoding as well.
    final standard = value.replaceAll('-', '+').replaceAll('_', '/');
    final padded = standard.padRight((standard.length + 3) ~/ 4 * 4, '=');
    return base64.decode(padded);
  }

  bool _constantTimeEqual(List<int> actual, List<int> expected) {
    if (actual.length != expected.length) return false;
    var diff = 0;
    for (var i = 0; i < actual.length; i++) {
      diff |= actual[i] ^ expected[i];
    }
    return diff == 0;
  }
}
