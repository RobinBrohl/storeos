import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/store_api.dart';

class SessionController extends ChangeNotifier {
  SessionController(this._api, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final StoreApi _api;
  final DateTime Function() _now;

  SessionResponse? _session;
  SystemStatusResponse? _status;
  DateTime? _checkedAt;
  String? _error;
  String? _notice;
  Timer? _expiryTimer;
  bool _busy = false;
  bool _disposed = false;

  bool get isAuthenticated => _session != null;
  bool get isBusy => _busy;
  SessionUser? get user => _session?.user;
  SystemStatusResponse? get status => _status;
  DateTime? get checkedAt => _checkedAt;
  String? get error => _error;
  String? get notice => _notice;

  /// Grants a short-lived token only to an application-layer request callback.
  /// A result from an expired or replaced session is never returned to callers.
  Future<T> authorized<T>(Future<T> Function(String token) request) async {
    final session = _session;
    if (_disposed || session == null || !session.expiresAt.isAfter(_now())) {
      if (!_disposed && session != null) _expireSession();
      throw const StoreApiException(
        'invalid_session',
        'Die Sitzung ist nicht mehr gültig. Bitte erneut anmelden.',
        statusCode: 401,
      );
    }
    try {
      final result = await request(session.token);
      if (_disposed || !identical(_session, session)) {
        throw const StoreApiException(
          'stale_session',
          'Die Sitzung wurde inzwischen beendet.',
        );
      }
      if (!session.expiresAt.isAfter(_now())) {
        _expireSession();
        throw const StoreApiException(
          'invalid_session',
          'Die Sitzung ist abgelaufen. Bitte erneut anmelden.',
          statusCode: 401,
        );
      }
      return result;
    } on StoreApiException catch (error) {
      if (!_disposed &&
          identical(_session, session) &&
          error.statusCode == 401) {
        _expireSession();
      }
      rethrow;
    }
  }

  void invalidateSession() {
    if (_session != null && !_disposed) _expireSession();
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();

    try {
      final session = await _api.login(
        LoginRequest(username: username.trim(), password: password),
      );
      if (_disposed) return;
      if (!session.expiresAt.isAfter(_now())) {
        throw const StoreApiException(
          'expired_session',
          'Der Server hat eine bereits abgelaufene Sitzung geliefert.',
        );
      }
      _session = session;
      _scheduleExpiry(session);
      await _loadStatus();
    } on StoreApiException catch (error) {
      if (!_disposed) _error = error.message;
    } catch (_) {
      if (!_disposed) {
        _error = 'Die Anmeldung konnte nicht abgeschlossen werden.';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> refreshStatus() async {
    if (_busy || _session == null) return;
    if (!_session!.expiresAt.isAfter(_now())) {
      _expireSession();
      return;
    }
    _busy = true;
    _status = null;
    _checkedAt = null;
    _error = null;
    _notify();
    try {
      await _loadStatus();
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> signOut() async {
    if (_busy || _session == null) return;
    final token = _session!.token;
    _busy = true;
    _clearSession();
    _error = null;
    _notice = null;
    _notify();
    try {
      await _api.logout(token);
    } catch (_) {
      if (!_disposed) {
        _notice =
            'Lokale Sitzung beendet. Die Serverabmeldung konnte nicht bestätigt werden.';
      }
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> _loadStatus() async {
    final session = _session;
    if (session == null) return;
    try {
      final result = await _api.systemStatus(
        token: session.token,
        locationId: session.user.locationId,
      );
      if (_disposed || !identical(_session, session)) return;
      if (!session.expiresAt.isAfter(_now())) {
        _expireSession();
        return;
      }
      if (result.companyId != session.user.companyId ||
          result.locationId != session.user.locationId ||
          result.service != 'storeos' ||
          result.apiVersion != 1) {
        throw const StoreApiException(
          'unexpected_status',
          'Die Serverantwort passt nicht zur angemeldeten Sitzung.',
        );
      }
      if (result.database != 'reachable') {
        throw const StoreApiException(
          'database_unavailable',
          'Der Standortserver meldet keine erreichbare Datenbank.',
        );
      }
      _status = result;
      _checkedAt = _now();
      _error = null;
    } on StoreApiException catch (error) {
      if (_disposed || !identical(_session, session)) return;
      _status = null;
      _checkedAt = null;
      if (error.statusCode == 401) {
        _clearSession();
        _error = 'Die Sitzung ist nicht mehr gültig. Bitte erneut anmelden.';
      } else {
        _error = error.message;
      }
    } catch (_) {
      if (_disposed || !identical(_session, session)) return;
      _status = null;
      _checkedAt = null;
      _error = 'Der Systemstatus konnte nicht gelesen werden.';
    }
  }

  void _scheduleExpiry(SessionResponse session) {
    _expiryTimer?.cancel();
    final duration = session.expiresAt.difference(_now());
    _expiryTimer = Timer(duration, _expireSession);
  }

  void _expireSession() {
    if (_disposed) return;
    _clearSession();
    _error = 'Die Sitzung ist abgelaufen. Bitte erneut anmelden.';
    _notify();
  }

  void _clearSession() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _session = null;
    _status = null;
    _checkedAt = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clearSession();
    super.dispose();
  }
}
