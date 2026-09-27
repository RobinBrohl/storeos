import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_models.dart';
import 'session_controller.dart';

class PlatformController extends ChangeNotifier {
  PlatformController(this._session, this._api) {
    _session.addListener(_onSessionChanged);
    _onSessionChanged();
  }

  final SessionController _session;
  final PlatformApi _api;
  String? _boundUserId;
  int _epoch = 0;
  bool _disposed = false;
  bool _busy = false;
  String? _error;
  String? _notice;
  String? _pendingLocationId;
  String? _pendingLocationName;
  String? _pendingUserId;
  String? _pendingUsername;

  PlatformContext? context;
  OrganizationSnapshot? organization;
  List<PlatformUser>? users;
  List<Map<String, dynamic>>? audit;
  String? auditNextCursor;
  List<Map<String, dynamic>>? events;
  String? eventsNextCursor;
  List<PluginRecord>? plugins;

  bool get isBusy => _busy;
  String? get error => _error;
  String? get notice => _notice;
  bool allows(String permission) => context?.allows(permission) ?? false;

  void _onSessionChanged() {
    final userId = _session.user?.id;
    if (userId == _boundUserId) return;
    _boundUserId = userId;
    _epoch++;
    context = null;
    organization = null;
    users = null;
    audit = null;
    auditNextCursor = null;
    events = null;
    eventsNextCursor = null;
    plugins = null;
    _busy = false;
    _error = null;
    _notice = null;
    _pendingLocationId = null;
    _pendingLocationName = null;
    _pendingUserId = null;
    _pendingUsername = null;
    _notify();
    if (userId != null) _loadInitial();
  }

  bool _current(int epoch) =>
      !_disposed && _epoch == epoch && _session.isAuthenticated;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T> _authorized<T>(Future<T> Function(String) request) =>
      _session.authorized(request);

  Future<void> _loadInitial() async {
    if (_busy || !_session.isAuthenticated) return;
    final epoch = _epoch;
    _busy = true;
    _error = null;
    _notify();
    try {
      final rawContext = await _authorized(
        (token) => _api.get(token, '/context'),
      );
      if (!_current(epoch)) return;
      final loadedContext = PlatformContext.fromJson(rawContext);
      final user = _session.user!;
      if (loadedContext.userId != user.id ||
          loadedContext.companyId != user.companyId ||
          loadedContext.locationId != user.locationId ||
          !{'admin', 'auditor', 'viewer'}.contains(loadedContext.role)) {
        _session.invalidateSession();
        return;
      }
      context = loadedContext;
      final rawOrganization = await _authorized(
        (token) => _api.get(token, '/organization'),
      );
      if (!_current(epoch)) return;
      final loadedOrganization = _parseOrganization(rawOrganization);
      organization = loadedOrganization;
    } catch (error) {
      if (_current(epoch)) _error = _message(error);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
      }
    }
  }

  Future<void> retryInitial() => _loadInitial();

  Future<void> loadOrganization() => _load('organization.read', () async {
    organization = _parseOrganization(
      await _authorized((token) => _api.get(token, '/organization')),
    );
  });

  Future<void> loadUsers() => _load('identity.read', () async {
    final json = await _authorized((token) => _api.get(token, '/users'));
    users = objectsOf(
      json['users'],
      'users',
    ).map(PlatformUser.fromJson).toList(growable: false);
  });

  Future<void> loadAudit({bool more = false}) => _load('audit.read', () async {
    if (more && auditNextCursor == null) return;
    final page = CursorPage.fromJson(
      await _authorized(
        (token) =>
            _api.get(token, '/audit', after: more ? auditNextCursor : null),
      ),
    );
    audit = more ? [...?audit, ...page.items] : page.items;
    auditNextCursor = page.nextCursor;
  });

  Future<void> loadEvents({bool more = false}) => _load(
    'events.read',
    () async {
      if (more && eventsNextCursor == null) return;
      final page = CursorPage.fromJson(
        await _authorized(
          (token) =>
              _api.get(token, '/events', after: more ? eventsNextCursor : null),
        ),
      );
      events = more ? [...?events, ...page.items] : page.items;
      eventsNextCursor = page.nextCursor;
    },
  );

  Future<void> loadPlugins() => _load('plugins.read', () async {
    final json = await _authorized((token) => _api.get(token, '/plugins'));
    plugins = objectsOf(
      json['plugins'],
      'plugins',
    ).map(PluginRecord.fromJson).toList(growable: false);
  });

  Future<void> _load(String permission, Future<void> Function() task) async {
    if (!_can(permission) || _busy) return;
    final epoch = _epoch;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    try {
      await task();
    } catch (error) {
      if (_current(epoch)) _error = _message(error);
    } finally {
      if (_current(epoch)) {
        _busy = false;
        _notify();
      }
    }
  }

  bool _can(String permission) {
    if (_session.isAuthenticated && allows(permission)) return true;
    if (_session.isAuthenticated && context != null) {
      _error = 'Für diese Aktion fehlt die Berechtigung.';
      _notify();
    }
    return false;
  }

  Future<bool> _write(
    String permission,
    String route,
    Map<String, dynamic> body,
    Future<void> Function() reload,
    String success,
  ) async {
    if (!_can(permission) || _busy) return false;
    final epoch = _epoch;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    bool committed = false;
    String? failure;
    try {
      await _authorized((token) => _api.post(token, route, body));
      committed = true;
    } catch (error) {
      failure = _message(error);
    }
    if (!_current(epoch)) return false;
    try {
      await reload();
    } catch (error) {
      if (_current(epoch)) {
        _error = committed
            ? 'Die Änderung wurde angenommen, aber der aktuelle Stand konnte nicht geladen werden: ${_message(error)}'
            : '$failure Der aktuelle Stand konnte nicht geladen werden: ${_message(error)}';
      }
    } finally {
      if (_current(epoch)) {
        if (_error == null) {
          if (committed) {
            _notice = success;
          } else {
            _error = '$failure Der aktuelle Stand wurde neu geladen.';
          }
        }
        _busy = false;
        _notify();
      }
    }
    return committed && _current(epoch) && _error == null;
  }

  Future<void> _reloadOrganization() async {
    organization = _parseOrganization(
      await _authorized((token) => _api.get(token, '/organization')),
    );
  }

  OrganizationSnapshot _parseOrganization(Map<String, dynamic> json) {
    final snapshot = OrganizationSnapshot.fromJson(json);
    final platformContext = context;
    if (platformContext == null ||
        snapshot.company.id != platformContext.companyId ||
        snapshot.locations.isEmpty ||
        !snapshot.locations.any(
          (location) => location.id == platformContext.locationId,
        ) ||
        snapshot.locations.any(
          (location) => location.companyId != platformContext.companyId,
        )) {
      throw const FormatException(
        'Die Organisation passt nicht zur angemeldeten Sitzung.',
      );
    }
    if (platformContext.role == 'viewer') {
      return OrganizationSnapshot(
        company: snapshot.company,
        locations: snapshot.locations
            .where((location) => location.id == platformContext.locationId)
            .toList(growable: false),
      );
    }
    return snapshot;
  }

  Future<void> _reloadUsers() async {
    final json = await _authorized((token) => _api.get(token, '/users'));
    users = objectsOf(
      json['users'],
      'users',
    ).map(PlatformUser.fromJson).toList(growable: false);
  }

  Future<void> _reloadPlugins() async {
    final json = await _authorized((token) => _api.get(token, '/plugins'));
    plugins = objectsOf(
      json['plugins'],
      'plugins',
    ).map(PluginRecord.fromJson).toList(growable: false);
  }

  Future<bool> setup(String companyName, String locationName) {
    if (companyName.trim().isEmpty || locationName.trim().isEmpty) {
      return _invalid('Beide Namen müssen ausgefüllt sein.');
    }
    return _write(
      'organization.write',
      '/organization/setup',
      {'companyName': companyName.trim(), 'locationName': locationName.trim()},
      _reloadOrganization,
      'Unternehmen und erster Standort wurden eingerichtet.',
    );
  }

  Future<bool> renameCompany(String name) {
    final company = organization?.company;
    if (company == null || name.trim().isEmpty) {
      return _invalid('Einen gültigen Unternehmensnamen eingeben.');
    }
    return _write(
      'organization.write',
      '/company',
      {'name': name.trim(), 'expectedVersion': company.version},
      _reloadOrganization,
      'Unternehmensname aktualisiert.',
    );
  }

  Future<bool> createLocation(String name) async {
    if (name.trim().isEmpty) return _invalid('Standortname eingeben.');
    final epoch = _epoch;
    final normalizedName = name.trim();
    final id = _pendingLocationName == normalizedName
        ? _pendingLocationId ?? _uuid()
        : _uuid();
    _pendingLocationId = id;
    _pendingLocationName = normalizedName;
    final success = await _write(
      'organization.write',
      '/locations',
      {'id': id, 'name': normalizedName},
      _reloadOrganization,
      'Standort angelegt.',
    );
    if (!_current(epoch)) return false;
    if (success ||
        (organization?.locations.any((location) => location.id == id) ??
            false)) {
      _pendingLocationId = null;
      _pendingLocationName = null;
      if (!success && _session.isAuthenticated) {
        _error = null;
        _notice = 'Der Standort ist nach erneutem Laden vorhanden.';
        _notify();
      }
      return true;
    }
    return false;
  }

  Future<bool> renameLocation(LocationRecord location, String name) {
    if (name.trim().isEmpty) return _invalid('Standortname eingeben.');
    return _write(
      'organization.write',
      '/locations/${Uri.encodeComponent(location.id)}',
      {'name': name.trim(), 'expectedVersion': location.version},
      _reloadOrganization,
      'Standortname aktualisiert.',
    );
  }

  Future<bool> createUser({
    required String username,
    required String password,
    required String locationId,
    required String role,
  }) async {
    final epoch = _epoch;
    if (username.trim().isEmpty ||
        password.isEmpty ||
        !{'admin', 'auditor', 'viewer'}.contains(role) ||
        !(organization?.locations.any(
              (location) => location.id == locationId,
            ) ??
            false)) {
      return _invalid('Benutzername, Passwort, Standort und Rolle prüfen.');
    }
    final normalizedUsername = username.trim();
    final id = _pendingUsername == normalizedUsername
        ? _pendingUserId ?? _uuid()
        : _uuid();
    _pendingUserId = id;
    _pendingUsername = normalizedUsername;
    final success = await _write(
      'identity.write',
      '/users',
      {
        'id': id,
        'username': normalizedUsername,
        'password': password,
        'locationId': locationId,
        'role': role,
      },
      _reloadUsers,
      'Benutzer angelegt.',
    );
    if (!_current(epoch)) return false;
    if (success || (users?.any((user) => user.id == id) ?? false)) {
      _pendingUserId = null;
      _pendingUsername = null;
      if (!success && _session.isAuthenticated) {
        _error = null;
        _notice = 'Der Benutzer ist nach erneutem Laden vorhanden.';
        _notify();
      }
      return true;
    }
    return false;
  }

  Future<bool> updateUser(PlatformUser user, String role, bool isActive) {
    if (!{'admin', 'auditor', 'viewer'}.contains(role)) {
      return _invalid('Ungültige Rolle.');
    }
    return _write(
      'identity.write',
      '/users/${Uri.encodeComponent(user.id)}',
      {'role': role, 'isActive': isActive, 'expectedVersion': user.version},
      _reloadUsers,
      'Benutzer aktualisiert.',
    );
  }

  Future<bool> resetPassword(PlatformUser user, String password) {
    if (password.isEmpty) return _invalid('Ein neues Passwort eingeben.');
    return _write(
      'identity.write',
      '/users/${Uri.encodeComponent(user.id)}/password',
      {'password': password, 'expectedVersion': user.version},
      _reloadUsers,
      'Passwort ersetzt; bestehende Sitzungen des Benutzers wurden widerrufen.',
    );
  }

  Future<bool> registerPlugin(String manifestSource) async {
    late final Map<String, dynamic> manifest;
    try {
      manifest = parseManifest(manifestSource);
    } catch (error) {
      return _invalid(_message(error));
    }
    return _write(
      'plugins.write',
      '/plugins',
      {'manifest': manifest},
      _reloadPlugins,
      'Plugin-Manifest registriert. Es ist noch nicht freigegeben.',
    );
  }

  Future<PluginApproval?> approvePlugin(
    PluginRecord plugin, {
    required String locationId,
    required List<String> permissions,
    required List<String> subscriptions,
  }) async {
    if (!_can('plugins.write') || _busy) return null;
    if (!(organization?.locations.any(
              (location) => location.id == locationId,
            ) ??
            false) ||
        permissions
            .toSet()
            .difference(plugin.requestedPermissions.toSet())
            .isNotEmpty ||
        subscriptions
            .toSet()
            .difference(plugin.requestedSubscriptions.toSet())
            .isNotEmpty ||
        (subscriptions.isNotEmpty && !permissions.contains('events.read'))) {
      await _invalid('Standort und freizugebende Rechte prüfen.');
      return null;
    }
    final epoch = _epoch;
    _busy = true;
    _error = null;
    _notice = null;
    _notify();
    PluginApproval? approval;
    try {
      final json = await _authorized(
        (token) => _api
            .post(token, '/plugins/${Uri.encodeComponent(plugin.id)}/approve', {
              'expectedVersion': plugin.version,
              'locationId': locationId,
              'permissions': permissions,
              'subscriptions': subscriptions,
            }),
      );
      approval = PluginApproval.fromJson(json);
    } catch (error) {
      if (_current(epoch)) _error = _message(error);
    }
    if (!_current(epoch)) return null;
    try {
      await _reloadPlugins();
    } catch (error) {
      if (_current(epoch)) {
        _error =
            '${_error ?? 'Freigabeantwort erhalten.'} Aktueller Plugin-Stand nicht abrufbar: ${_message(error)}';
      }
    } finally {
      if (_current(epoch)) {
        if (approval != null && _error == null) {
          _notice = 'Plugin freigegeben. Zugangstoken jetzt sicher übernehmen.';
        }
        _busy = false;
        _notify();
      }
    }
    return _current(epoch) ? approval : null;
  }

  Future<bool> disablePlugin(PluginRecord plugin) => _write(
    'plugins.write',
    '/plugins/${Uri.encodeComponent(plugin.id)}/disable',
    {'expectedVersion': plugin.version},
    _reloadPlugins,
    'Plugin deaktiviert; Zugangstoken widerrufen.',
  );

  Future<bool> replayEvent(Map<String, dynamic> event) {
    if (context?.role != 'admin' || event['status'] != 'dead_letter') {
      return _invalid(
        'Nur Administratoren können fehlgeschlagene Ereignisse erneut einreihen.',
      );
    }
    final eventId = event['eventId'];
    if (eventId is! String || eventId.isEmpty) {
      return _invalid('Das Ereignis hat keine gültige ID.');
    }
    return _write(
      'events.write',
      '/events/${Uri.encodeComponent(eventId)}/replay',
      const {},
      () async {
        final page = CursorPage.fromJson(
          await _authorized((token) => _api.get(token, '/events')),
        );
        events = page.items;
        eventsNextCursor = page.nextCursor;
      },
      'Ereignis zur erneuten Zustellung eingereiht.',
    );
  }

  Future<bool> _invalid(String message) async {
    _error = message;
    _notice = null;
    _notify();
    return false;
  }

  String _message(Object error) => switch (error) {
    StoreApiException(:final message) => message,
    FormatException(:final message) => message,
    _ => 'Die Anfrage konnte nicht abgeschlossen werden.',
  };

  String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }
}
