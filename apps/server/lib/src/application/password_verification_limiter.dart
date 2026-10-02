/// Process-local bounded limiter for failed current-password verifications.
///
/// It is intentionally not transactional: a failure remains recorded even when
/// the surrounding database transaction rolls back, and it is only cleared by a
/// successful password change or by window expiry. Login and admin password
/// reset use separate paths and are unaffected.
class PasswordVerificationLimiter {
  PasswordVerificationLimiter({
    this.window = const Duration(minutes: 15),
    this.maxFailures = 5,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration window;
  final int maxFailures;
  final DateTime Function() _clock;
  final Map<String, _FailureWindow> _failures = {};

  /// Number of tracked accounts; exposed so tests can prove bounded storage.
  int get trackedAccountCount => _failures.length;

  bool allows(String accountId) {
    final now = _clock();
    _prune(now);
    return _count(accountId, now) < maxFailures;
  }

  void failure(String accountId) {
    final now = _clock();
    final current = _failures[accountId];
    if (current == null || now.difference(current.startedAt) >= window) {
      _failures[accountId] = _FailureWindow(now, 1);
    } else {
      current.count++;
    }
  }

  void success(String accountId) => _failures.remove(accountId);

  int _count(String accountId, DateTime now) {
    final current = _failures[accountId];
    if (current == null || now.difference(current.startedAt) >= window) {
      return 0;
    }
    return current.count;
  }

  void _prune(DateTime now) {
    if (_failures.length < 1000) return;
    _failures.removeWhere(
      (_, value) => now.difference(value.startedAt) >= window,
    );
  }
}

class _FailureWindow {
  _FailureWindow(this.startedAt, this.count);

  final DateTime startedAt;
  int count;
}
