import 'package:storeos_server/src/application/password_verification_limiter.dart';
import 'package:test/test.dart';

void main() {
  test('blocks after five failures within the window', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final limiter = PasswordVerificationLimiter(clock: () => now);
    expect(limiter.allows('account-a'), isTrue);
    for (var attempt = 0; attempt < 5; attempt++) {
      expect(limiter.allows('account-a'), isTrue);
      limiter.failure('account-a');
    }
    expect(limiter.allows('account-a'), isFalse);
    // A blocked check does not add another failure.
    expect(limiter.allows('account-a'), isFalse);
    limiter.failure('account-a');
    expect(limiter.allows('account-a'), isFalse);
  });

  test('the fixed window expires and allows the account again', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final limiter = PasswordVerificationLimiter(clock: () => now);
    for (var attempt = 0; attempt < 5; attempt++) {
      limiter.failure('account-a');
    }
    expect(limiter.allows('account-a'), isFalse);
    now = now.add(const Duration(minutes: 15));
    expect(limiter.allows('account-a'), isTrue);
  });

  test('success clears only the addressed account bucket', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final limiter = PasswordVerificationLimiter(clock: () => now);
    for (var attempt = 0; attempt < 5; attempt++) {
      limiter.failure('account-a');
      limiter.failure('account-b');
    }
    limiter.success('account-a');
    expect(limiter.allows('account-a'), isTrue);
    expect(limiter.allows('account-b'), isFalse);
  });

  test('failed attempts are tracked per account', () {
    final limiter = PasswordVerificationLimiter();
    limiter.failure('account-a');
    expect(limiter.allows('account-a'), isTrue);
    expect(limiter.allows('account-b'), isTrue);
    for (var attempt = 1; attempt < 5; attempt++) {
      limiter.failure('account-a');
    }
    expect(limiter.allows('account-a'), isFalse);
    expect(limiter.allows('account-b'), isTrue);
  });

  test('prunes expired keys once storage grew', () {
    var now = DateTime.utc(2026, 1, 1, 12);
    final limiter = PasswordVerificationLimiter(clock: () => now);
    for (var index = 0; index < 1200; index++) {
      limiter.failure('account-$index');
    }
    expect(limiter.trackedAccountCount, 1200);
    now = now.add(const Duration(minutes: 16));
    expect(limiter.allows('fresh-account'), isTrue);
    expect(limiter.trackedAccountCount, 0);
    limiter.failure('fresh-account');
    expect(limiter.trackedAccountCount, 1);
  });
}
