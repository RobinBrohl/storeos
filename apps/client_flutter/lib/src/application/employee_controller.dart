import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

class EmployeeController extends ChangeNotifier {
  EmployeeController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  List<EmployeeDto>? employees;
  EmployeeDto? mine, selected;
  EmployeeLinkDto? link;
  List<PlatformUserDto> accounts = [];
  bool busy = false;
  String? error, notice;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  Timer? _poll;
  Completer<void>? _idle;

  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  String? _pendingId, _pendingName, _pendingLocation;
  String? _pendingLinkId, _pendingLinkEmployee, _pendingLinkAccount;

  bool get canManage => platform.allows('people.manage');
  List<LocationDto> get configuredLocations =>
      platform.organization?.locations
          .where((location) => location.name != null)
          .toList() ??
      [];
  String? get creationUnavailableReason => platform.organization == null
      ? 'Standorte sind noch nicht bestätigt. Bitte die Organisation laden.'
      : configuredLocations.isEmpty
      ? 'Zuerst unter Organisation einen Standort einrichten.'
      : null;
  List<PlatformUserDto> get linkCandidates => accounts
      .where(
        (account) =>
            account.isActive &&
            account.companyId == selected?.companyId &&
            account.locationId == selected?.locationId,
      )
      .toList();

  void _sessionChanged() {
    if (_userId == session.user?.id) return;
    _userId = session.user?.id;
    _epoch++;
    employees = null;
    mine = null;
    selected = null;
    link = null;
    accounts = [];
    error = null;
    notice = null;
    busy = false;
    _idle = null;
    _pendingId = _pendingLinkId = null;
    stopSelfRefresh();
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) =>
      !_disposed && epoch == _epoch && session.isAuthenticated;
  void _requireCurrent(int epoch) {
    if (!_current(epoch)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
  }

  Future<Map<String, dynamic>> _get(int epoch, String route) async {
    _requireCurrent(epoch);
    final response = await session.authorized((token) => api.get(token, route));
    _requireCurrent(epoch);
    return response;
  }

  Future<Map<String, dynamic>> _post(
    int epoch,
    String route,
    Map<String, dynamic> body,
  ) async {
    _requireCurrent(epoch);
    final response = await session.authorized(
      (token) => api.post(token, route, body),
    );
    _requireCurrent(epoch);
    return response;
  }

  Future<void> _run(
    String permission,
    Future<void> Function(int epoch) action,
  ) async {
    if (busy || !_current(_epoch) || !platform.allows(permission)) {
      return;
    }
    final epoch = _epoch;
    final idle = Completer<void>();
    _idle = idle;
    busy = true;
    error = notice = null;
    _notify();
    try {
      await action(epoch);
    } catch (failure) {
      if (_current(epoch)) error = _message(failure);
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
      if (identical(_idle, idle)) _idle = null;
      idle.complete();
    }
  }

  Future<void> loadEmployees() => _run('people.manage', (epoch) async {
    _clearManagement();
    await _reloadEmployees(epoch);
  });

  Future<void> _reloadEmployees(int epoch) async {
    _requireCurrent(epoch);
    employees = null;
    _notify();
    final json = await _get(epoch, '/employees');
    final items = json['employees'];
    if (items is! List) throw const FormatException();
    final loaded = items
        .map((item) => EmployeeDto.fromJson(item as Map<String, dynamic>))
        .toList();
    if (loaded.any((item) => item.companyId != session.user?.companyId)) {
      throw const FormatException();
    }
    employees = loaded;
  }

  Future<void> select(EmployeeDto employee) =>
      _run('people.manage', (epoch) => _reloadSelected(epoch, employee.id));

  Future<void> _reloadSelected(int epoch, String id) async {
    _requireCurrent(epoch);
    selected = null;
    link = null;
    accounts = [];
    _notify();
    final employee = EmployeeDto.fromJson(await _get(epoch, '/employees/$id'));
    final rawLink = (await _get(epoch, '/employees/$id/account-link'))['link'];
    final users = UsersResponse.fromJson(await _get(epoch, '/users')).users;
    if (employee.companyId != session.user?.companyId) {
      throw const FormatException();
    }
    final loadedLink = rawLink == null
        ? null
        : EmployeeLinkDto.fromJson(rawLink as Map<String, dynamic>);
    if (loadedLink != null &&
        (loadedLink.employeeId != id ||
            loadedLink.companyId != employee.companyId ||
            loadedLink.locationId != employee.locationId ||
            loadedLink.revokedAt != null)) {
      throw const FormatException();
    }
    selected = employee;
    link = loadedLink;
    accounts = users;
  }

  Future<void> loadSelf() => _run('people.self.read', (epoch) async {
    mine = null;
    _notify();
    final profile = EmployeeDto.fromJson(await _get(epoch, '/employees/me'));
    if (!profile.isActive ||
        profile.companyId != session.user?.companyId ||
        profile.locationId != session.user?.locationId) {
      throw const FormatException();
    }
    mine = profile;
  });

  void startSelfRefresh() {
    _poll ??= Timer.periodic(const Duration(seconds: 30), (_) => loadSelf());
    loadSelf();
  }

  void stopSelfRefresh() {
    _poll?.cancel();
    _poll = null;
  }

  Future<void> create(String name, String locationId) =>
      _run('people.manage', (epoch) async {
        final normalized = name.trim();
        final id = _pendingName == normalized && _pendingLocation == locationId
            ? _pendingId ?? _uuid()
            : _uuid();
        _pendingId = id;
        _pendingName = normalized;
        _pendingLocation = locationId;
        _clearManagement();
        Object? failure;
        try {
          await _post(epoch, '/employees', {
            'id': id,
            'displayName': normalized,
            'locationId': locationId,
          });
        } catch (e) {
          failure = e;
        }
        _requireCurrent(epoch);
        await _reloadEmployees(epoch);
        if (employees!.any((employee) => employee.id == id)) {
          _pendingId = null;
          notice = 'Mitarbeiterprofil gespeichert und erneut geladen.';
        } else if (failure != null) {
          throw failure;
        }
      });

  Future<void> rename(EmployeeDto employee, String name) => _mutate(
    employee,
    '/employees/${employee.id}/rename',
    {'displayName': name.trim(), 'expectedVersion': employee.version},
  );
  Future<void> deactivate(EmployeeDto employee) => _mutate(
    employee,
    '/employees/${employee.id}/deactivate',
    {'expectedVersion': employee.version},
  );
  Future<void> unlink(EmployeeDto employee, EmployeeLinkDto link) => _mutate(
    employee,
    '/employee-links/${link.id}/revoke',
    {'expectedVersion': link.version},
  );

  Future<void> _mutate(
    EmployeeDto employee,
    String route,
    Map<String, dynamic> body,
  ) => _run('people.manage', (epoch) async {
    Object? failure;
    try {
      await _post(epoch, route, body);
    } catch (e) {
      failure = e;
    }
    // Remove stale details before reconciling an unknown commit outcome.
    _requireCurrent(epoch);
    _clearManagement();
    await _reloadEmployees(epoch);
    await _reloadSelected(epoch, employee.id);
    if (failure != null) throw failure;
    notice = 'Änderung gespeichert und erneut geladen.';
  });

  Future<void> linkAccount(
    EmployeeDto employee,
    PlatformUserDto account,
  ) => _run('people.manage', (epoch) async {
    final id =
        _pendingLinkEmployee == employee.id && _pendingLinkAccount == account.id
        ? _pendingLinkId ?? _uuid()
        : _uuid();
    _pendingLinkId = id;
    _pendingLinkEmployee = employee.id;
    _pendingLinkAccount = account.id;
    Object? failure;
    try {
      await _post(epoch, '/employees/${employee.id}/account-link', {
        'id': id,
        'accountId': account.id,
        'expectedEmployeeVersion': employee.version,
        'expectedAccountVersion': account.version,
      });
    } catch (e) {
      failure = e;
    }
    _requireCurrent(epoch);
    await _reloadSelected(epoch, employee.id);
    if (link?.id == id) {
      _pendingLinkId = null;
      notice =
          'Account verknüpft. Bestehende Sitzungen wurden beendet; Rollen bleiben unverändert.';
    } else if (failure != null) {
      throw failure;
    }
  });

  void _clearManagement() {
    employees = null;
    selected = null;
    link = null;
    accounts = [];
    _notify();
  }

  String _message(Object failure) => switch (failure) {
    StoreApiException(code: 'already_linked') =>
      'Der Account oder das Mitarbeiterprofil ist bereits verknüpft. Bitte die bestehende Zuordnung prüfen.',
    StoreApiException(code: 'resource_limit') =>
      'Die unterstützte Anzahl an Datensätzen ist erreicht.',
    StoreApiException(code: 'inactive_employee' || 'inactive_identity') =>
      'Das Profil oder der Account ist deaktiviert. Die Aktion ist nicht möglich.',
    StoreApiException(statusCode: 404) =>
      'Kein zugängliches Mitarbeiterprofil beziehungsweise keine passende Zuordnung vorhanden.',
    StoreApiException(:final message) => message,
    _ =>
      'Die Mitarbeiterdaten konnten nicht bestätigt werden. Bitte erneut laden.',
  };

  @override
  void dispose() {
    _disposed = true;
    stopSelfRefresh();
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
