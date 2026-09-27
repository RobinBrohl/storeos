class LoginLimiter {
  LoginLimiter({
    this.window = const Duration(minutes: 15),
    this.maxUserFailures = 5,
    this.maxRemoteFailures = 30,
    this.maxConcurrent = 4,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration window;
  final int maxUserFailures;
  final int maxRemoteFailures;
  final int maxConcurrent;
  final DateTime Function() _clock;
  final Map<String, _FailureWindow> _users = {};
  final Map<String, _FailureWindow> _remotes = {};
  int _inFlight = 0;

  bool begin(String usernameKey, String remoteKey) {
    final now = _clock();
    _prune(now);
    if ((_users.length + _remotes.length >= 10000 &&
            !_users.containsKey(usernameKey) &&
            !_remotes.containsKey(remoteKey)) ||
        _inFlight >= maxConcurrent ||
        _failures(_users, usernameKey, now) >= maxUserFailures ||
        _failures(_remotes, remoteKey, now) >= maxRemoteFailures) {
      return false;
    }
    _inFlight++;
    return true;
  }

  void failure(String usernameKey, String remoteKey) {
    final now = _clock();
    _increment(_users, usernameKey, now);
    _increment(_remotes, remoteKey, now);
  }

  void success(String usernameKey) => _users.remove(usernameKey);

  void end() {
    if (_inFlight > 0) _inFlight--;
  }

  int _failures(Map<String, _FailureWindow> windows, String key, DateTime now) {
    final current = windows[key];
    if (current == null || now.difference(current.startedAt) >= window) {
      return 0;
    }
    return current.count;
  }

  void _increment(
    Map<String, _FailureWindow> windows,
    String key,
    DateTime now,
  ) {
    final current = windows[key];
    if (current == null || now.difference(current.startedAt) >= window) {
      windows[key] = _FailureWindow(now, 1);
    } else {
      current.count++;
    }
  }

  void _prune(DateTime now) {
    if (_users.length + _remotes.length < 1000) return;
    _users.removeWhere((_, value) => now.difference(value.startedAt) >= window);
    _remotes.removeWhere(
      (_, value) => now.difference(value.startedAt) >= window,
    );
  }
}

class _FailureWindow {
  _FailureWindow(this.startedAt, this.count);

  final DateTime startedAt;
  int count;
}
