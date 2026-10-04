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
  Object? _sessionIdentity;
  SystemStatusResponse? _status;
  DateTime? _checkedAt;
  String? _error;
  String? _notice;
  String? _noticeTitle;
  bool _noticePositive = false;
  Timer? _expiryTimer;
  bool _busy = false;
  bool _disposed = false;

  bool get isAuthenticated => _session != null;
  bool get isBusy => _busy;
  SessionUser? get user => _session?.user;

  /// Opaque identity changes even when the same account replaces its session.
  Object? get sessionIdentity => _sessionIdentity;
  SystemStatusResponse? get status => _status;
  DateTime? get checkedAt => _checkedAt;
  String? get error => _error;
  String? get notice => _notice;
  String? get noticeTitle => _noticeTitle;
  bool get noticePositive => _noticePositive;

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

  /// Clears transient error and notice state, e.g. before opening the
  /// password-change dialog.
  void clearMessages() {
    if (_disposed) return;
    _error = null;
    _notice = null;
    _noticeTitle = null;
    _noticePositive = false;
    _notify();
  }

  /// Changes the authenticated account's own password after verifying the
  /// current one. On success, and on an ambiguous transport outcome, the local
  /// session is cleared because the server revokes all sessions on commit.
  Future<bool> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (_busy) return false;
    final session = _session;
    if (_disposed || session == null || !session.expiresAt.isAfter(_now())) {
      if (!_disposed && session != null) _expireSession();
      return false;
    }
    final currentBytes = passwordUtf8ByteLength(currentPassword);
    if (currentBytes == 0 || currentBytes > passwordMaxUtf8Bytes) {
      _error = 'Aktuelles Passwort eingeben.';
      _notice = null;
      _notify();
      return false;
    }
    final newBytes = passwordUtf8ByteLength(newPassword);
    if (newBytes < passwordMinUtf8Bytes || newBytes > passwordMaxUtf8Bytes) {
      _error =
          'Das neue Passwort muss $passwordMinUtf8Bytes bis '
          '$passwordMaxUtf8Bytes UTF-8-Bytes lang sein.';
      _notice = null;
      _notify();
      return false;
    }
    if (newPassword == currentPassword) {
      _error = 'Das neue Passwort muss sich vom aktuellen unterscheiden.';
      _notice = null;
      _notify();
      return false;
    }
    _busy = true;
    _error = null;
    _notice = null;
    _noticeTitle = null;
    _noticePositive = false;
    _notify();
    try {
      await _api.changePassword(
        token: session.token,
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
      if (_disposed || !identical(_session, session)) return false;
      _clearSession();
      _noticeTitle = 'Passwort geändert';
      _noticePositive = true;
      _notice = 'Passwort geändert. Bitte mit dem neuen Passwort anmelden.';
      return true;
    } on StoreApiException catch (error) {
      if (_disposed || !identical(_session, session)) return false;
      if (error.statusCode == 401) {
        _clearSession();
        _noticeTitle = 'Passwortänderung';
        _noticePositive = false;
        _notice =
            'Die Sitzung ist nicht mehr gültig. Bitte mit dem neuen Passwort '
            'anmelden; falls die Änderung nicht gespeichert wurde, weiterhin '
            'mit dem bisherigen Passwort.';
        return false;
      }
      if (error.code == 'timeout' ||
          error.code == 'network_unavailable' ||
          error.code == 'stale_session') {
        _clearSession();
        _noticeTitle = 'Passwortänderung unklar';
        _noticePositive = false;
        _notice =
            'Die Verbindung wurde unterbrochen. Bitte mit dem neuen Passwort '
            'anmelden; falls die Änderung nicht gespeichert wurde, funktioniert '
            'weiterhin das bisherige Passwort.';
        return false;
      }
      _error = error.message;
      return false;
    } finally {
      if (!_disposed) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> signIn({
    required String username,
    required String password,
  }) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    _notice = null;
    _noticeTitle = null;
    _noticePositive = false;
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
      _sessionIdentity = Object();
      _scheduleExpiry(session);
      _notify();
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
    _noticeTitle = null;
    _noticePositive = false;
    _notify();
    try {
      await _api.logout(token);
    } catch (_) {
      if (!_disposed) {
        _noticeTitle = 'Abmeldung';
        _noticePositive = false;
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
    _sessionIdentity = null;
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
