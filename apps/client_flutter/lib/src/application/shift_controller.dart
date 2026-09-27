import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

class ShiftController extends ChangeNotifier {
  ShiftController(this.session, this.platform, this.api, {this.self = false}) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  List<Map<String, dynamic>>? items;
  List<EmployeeDto> employees = [];
  List<TaskTemplateDto> templates = [];
  List<TemplateRevisionDto> revisions = [];
  String? cursor,
      templateCursor,
      revisionCursor,
      revisionTemplateId,
      error,
      notice;
  ShiftDto? selected;
  List<TaskInstanceDto> tasks = [];
  TaskInstanceDto? task;
  String? employeeId, locationId;
  String startsAt = '', endsAt = '';
  List<ShiftTemplateSelection> selections = [];
  bool busy = false, editingNew = false, conflict = false, unconfirmed = false;
  int generation = 0, _epoch = 0;
  bool _disposed = false;
  String? _user, _newId, _pendingRoute;
  Map<String, dynamic>? _pendingBody;
  String? get reloadId => selected?.id ?? _pendingBody?['id'] as String?;
  String get root => self ? '/employee-home/shifts' : '/shifts';
  bool get allowed => platform.allows(
    self ? 'workforce.shifts.self.read' : 'workforce.shifts.manage',
  );
  List<EmployeeDto> get selectableEmployees => employees
      .where((e) => e.isActive && (editingNew || e.locationId == locationId))
      .toList();
  List<TaskTemplateDto> get selectableTemplates => templates
      .where((t) => t.locationId == locationId && t.publishedId != null)
      .toList();
  String? get selectedEmployeeOption =>
      selectableEmployees.any((e) => e.id == employeeId) ? employeeId : null;
  bool get editable =>
      !self &&
      !busy &&
      !conflict &&
      !unconfirmed &&
      (editingNew || selected?.status == 'draft');
  Map<String, dynamic> get input => {
    'employeeId': employeeId,
    'startsAt': startsAt,
    'endsAt': endsAt,
    'selections': selections.map((s) => s.toJson()).toList(),
  };
  bool get dirty {
    if (editingNew) return true;
    if (selected == null) return false;
    try {
      return jsonEncode(ShiftDraftInput.fromJson(input).toJson()) !=
          jsonEncode(selected!.draft.toJson());
    } catch (_) {
      return true;
    }
  }

  bool get canPublish =>
      editable && !editingNew && !dirty && selections.isNotEmpty;
  bool canAddRevision(TemplateRevisionDto revision) =>
      editable &&
      !revision.isDraft &&
      selections.length < 10 &&
      !selections.any((s) => s.templateId == revision.templateId) &&
      selectableTemplates.any((t) => t.id == revision.templateId) &&
      revisions.any(
        (r) => r.id == revision.id && r.templateId == revision.templateId,
      );

  void _clearRevisionChoices() {
    revisions = [];
    revisionCursor = revisionTemplateId = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (_user == session.user?.id) return;
    _user = session.user?.id;
    _epoch++;
    items = null;
    cursor = null;
    employees = [];
    templates = [];
    revisions = [];
    templateCursor = revisionCursor = revisionTemplateId = null;
    selected = null;
    tasks = [];
    task = null;
    employeeId = locationId = null;
    startsAt = endsAt = '';
    selections = [];
    busy = editingNew = conflict = unconfirmed = false;
    _newId = _pendingRoute = null;
    _pendingBody = null;
    error = notice = null;
    generation++;
    _notify();
  }

  bool _current(int e) => !_disposed && e == _epoch && session.isAuthenticated;
  Future<Map<String, dynamic>> _get(int e, String path, {String? after}) async {
    final result = await session.authorized(
      (token) => api.get(token, path, after: after),
    );
    if (!_current(e)) {
      throw const StoreApiException('stale_session', 'Sitzung beendet.');
    }
    return result;
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (busy || !allowed || !_current(_epoch)) return;
    final e = _epoch;
    busy = true;
    error = notice = null;
    _notify();
    try {
      await action(e);
    } catch (f) {
      if (_current(e)) error = _message(f);
    } finally {
      if (_current(e)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _run((e) async {
    if (more && cursor == null) return;
    if (!more) {
      items = null;
      cursor = null;
      _notify();
    }
    final raw = await _get(e, root, after: more ? cursor : null);
    final loaded = (raw['items'] as List).cast<Map<String, dynamic>>();
    for (final item in loaded) {
      _check(ShiftDto.fromJson(item['shift'] as Map<String, dynamic>));
    }
    items = [if (more) ...?items, ...loaded];
    cursor = raw['nextCursor'] as String?;
  });
  void _check(ShiftDto shift) {
    if (shift.companyId != session.user?.companyId) {
      throw const FormatException();
    }
  }

  void _accept(Map<String, dynamic> raw) {
    final shift = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
    _check(shift);
    selected = shift;
    tasks = (raw['tasks'] as List)
        .map((v) => TaskInstanceDto.fromJson(v as Map<String, dynamic>))
        .toList();
    employeeId = shift.draft.employeeId;
    locationId = shift.locationId;
    startsAt = shift.draft.startsAt.toIso8601String();
    endsAt = shift.draft.endsAt.toIso8601String();
    selections = [...shift.draft.selections];
    task = null;
    _clearRevisionChoices();
    editingNew = conflict = unconfirmed = false;
    _pendingRoute = null;
    _pendingBody = null;
    generation++;
    if (items != null) {
      items = [
        for (final item in items!)
          if ((item['shift'] as Map)['id'] == shift.id) raw else item,
      ];
    }
  }

  Future<void> open(String id) => _run((e) async {
    final raw = await _get(e, '$root/$id');
    _accept(raw);
  });
  Future<void> openTask(String id) => _run((e) async {
    task = null;
    final raw = await _get(e, '$root/${selected!.id}/tasks/$id');
    task = TaskInstanceDto.fromJson(raw);
  });
  Future<void> loadChoices({bool more = false}) => _run((e) async {
    if (self) return;
    if (!more) {
      _clearRevisionChoices();
      employees = ((await _get(e, '/employees'))['employees'] as List)
          .map((v) => EmployeeDto.fromJson(v as Map<String, dynamic>))
          .toList();
      templates = [];
      templateCursor = null;
    }
    if (more && templateCursor == null) return;
    final raw = await _get(
      e,
      '/task-templates',
      after: more ? templateCursor : null,
    );
    templates = [
      ...templates,
      ...(raw['items'] as List).map(
        (v) => TaskTemplateDto.fromJson(v as Map<String, dynamic>),
      ),
    ];
    templateCursor = raw['nextCursor'] as String?;
  });
  Future<void> loadRevisions(String id, {bool more = false}) => _run((e) async {
    if (!more) {
      revisions = [];
      revisionCursor = null;
      revisionTemplateId = id;
    }
    if (more && revisionCursor == null) return;
    final raw = await _get(
      e,
      '/task-templates/$id/revisions',
      after: more ? revisionCursor : null,
    );
    revisions = [
      ...revisions,
      ...(raw['items'] as List)
          .map((v) => TemplateRevisionDto.fromJson(v as Map<String, dynamic>))
          .where((v) => !v.isDraft),
    ];
    revisionCursor = raw['nextCursor'] as String?;
  });
  void newDraft() {
    if (self || busy || unconfirmed) return;
    selected = null;
    tasks = [];
    task = null;
    employeeId = locationId = null;
    startsAt = endsAt = '';
    selections = [];
    _clearRevisionChoices();
    editingNew = true;
    conflict = false;
    _newId = _uuid();
    error = notice = null;
    generation++;
    _notify();
  }

  void chooseEmployee(String id) {
    if (!editable) return;
    final candidates = selectableEmployees.where((e) => e.id == id);
    if (candidates.isEmpty) return;
    final e = candidates.single;
    employeeId = id;
    if (editingNew && locationId != e.locationId) {
      locationId = e.locationId;
      selections = [];
      _clearRevisionChoices();
    }
    _notify();
  }

  void setTimes({String? start, String? end}) {
    if (!editable) return;
    startsAt = start ?? startsAt;
    endsAt = end ?? endsAt;
    _notify();
  }

  void addRevision(TemplateRevisionDto revision) {
    if (!canAddRevision(revision)) return;
    selections = [
      ...selections,
      ShiftTemplateSelection(revision.templateId, revision.id),
    ];
    _notify();
  }

  void removeSelection(String id) {
    if (!editable) return;
    selections = selections.where((s) => s.templateId != id).toList();
    _notify();
  }

  void moveSelection(int index, int delta) {
    if (!editable) return;
    final next = index + delta;
    if (next < 0 || next >= selections.length) return;
    final copy = [...selections], value = copy.removeAt(index);
    copy.insert(next, value);
    selections = copy;
    _notify();
  }

  Future<void> save() {
    if (!editable) return Future.value();
    return _run((e) async {
      final draft = ShiftDraftInput.fromJson(input);
      if (locationId == null) {
        throw const FormatException('Mitarbeiter auswählen.');
      }
      _pendingRoute = editingNew ? '/shifts' : '/shifts/${selected!.id}/edit';
      _pendingBody = {
        ...draft.toJson(),
        if (editingNew) 'id': _newId,
        if (editingNew) 'locationId': locationId,
        if (!editingNew) 'expectedVersion': selected!.version,
      };
      await _send(e);
    });
  }

  Future<void> publish() {
    if (!canPublish) return Future.value();
    return _run((e) async {
      _pendingRoute = '/shifts/${selected!.id}/publish';
      _pendingBody = {'expectedVersion': selected!.version};
      await _send(e);
    });
  }

  Future<void> retry() => _run((e) async {
    if (_pendingRoute != null && !conflict) await _send(e);
  });
  Future<void> _send(int e) async {
    final route = _pendingRoute!, body = _pendingBody!, prior = selected;
    unconfirmed = true;
    _notify();
    try {
      final raw = await session.authorized(
        (token) => api.post(token, route, body),
      );
      if (!_current(e)) return;
      final actual = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
      final intended = route.endsWith('/publish')
          ? prior!.draft
          : ShiftDraftInput.fromJson(body);
      if (jsonEncode(actual.draft.toJson()) != jsonEncode(intended.toJson())) {
        throw const StoreApiException(
          'shift_conflict',
          'Abweichender Serverstand. Bitte ausdrücklich neu laden.',
          statusCode: 409,
        );
      }
      _accept(raw);
      _newId = null;
      notice = 'Gespeichert und vom Server bestätigt.';
    } catch (f) {
      if (!_current(e)) return;
      if (f is StoreApiException && f.statusCode == 409) {
        conflict = true;
        throw const StoreApiException(
          'shift_conflict',
          'Der Serverstand wurde geändert. Eingaben bleiben erhalten; bitte den Serverstand ausdrücklich neu laden.',
        );
      }
      if (f is StoreApiException &&
          f.statusCode != null &&
          f.statusCode! < 500) {
        unconfirmed = false;
        _pendingRoute = null;
        _pendingBody = null;
        rethrow;
      }
      final id = body['id'] ?? prior?.id;
      try {
        final raw = await _get(e, '/shifts/$id');
        final actual = ShiftDto.fromJson(raw['shift'] as Map<String, dynamic>);
        final intended = route.endsWith('/publish')
            ? prior!.draft
            : ShiftDraftInput.fromJson(body);
        final matches =
            jsonEncode(actual.draft.toJson()) == jsonEncode(intended.toJson());
        final versionMatches = route.endsWith('/publish')
            ? actual.status == 'published' &&
                  actual.publicationVersion == body['expectedVersion']
            : actual.status == 'draft' &&
                  actual.version ==
                      (body.containsKey('expectedVersion')
                          ? (body['expectedVersion'] as int) +
                                (prior != null &&
                                        jsonEncode(prior.draft.toJson()) ==
                                            jsonEncode(intended.toJson())
                                    ? 0
                                    : 1)
                          : 1);
        if (matches && versionMatches) {
          _accept(raw);
          _newId = null;
          notice = 'Serverstand nach Antwortverlust bestätigt.';
        } else if (prior != null &&
            actual.status == 'draft' &&
            actual.version == prior.version &&
            jsonEncode(actual.draft.toJson()) ==
                jsonEncode(prior.draft.toJson())) {
          // A failed/unreceived request is not a competing edit. Keep exactly
          // the original command pending; only an explicit retry may resend it.
          throw const StoreApiException(
            'unconfirmed',
            'Serverstand unverändert; der Vorgang ist noch nicht bestätigt.',
          );
        } else {
          conflict = true;
          throw const StoreApiException(
            'shift_conflict',
            'Abweichender Serverstand. Eingaben wurden nicht erneut gesendet. Bitte neu laden.',
          );
        }
      } catch (check) {
        if (conflict) rethrow;
        throw const StoreApiException(
          'unconfirmed',
          'Ergebnis nicht bestätigt. Eingaben bleiben gesperrt; denselben Vorgang erneut prüfen oder senden.',
        );
      }
    }
    // Failure of this query must not revoke the confirmed write.
    final raw = await _get(e, root);
    items = (raw['items'] as List).cast<Map<String, dynamic>>();
    cursor = raw['nextCursor'] as String?;
  }

  String _message(Object f) => switch (f) {
    FormatException(:final message) when message.isNotEmpty => message,
    StoreApiException(code: 'employee_unavailable') =>
      'Kein aktives Mitarbeiterprofil oder keine gültige Standortzuordnung verfügbar.',
    StoreApiException(code: 'shift_overlap') =>
      'Die Schicht überschneidet sich mit einer veröffentlichten Schicht.',
    StoreApiException(code: 'shift_not_publishable') =>
      'Mindestens eine Aufgabe und eine noch nicht beendete Schicht sind erforderlich.',
    StoreApiException(code: 'invalid_selection') =>
      'Nur veröffentlichte Vorlagenrevisionen dieses Standorts sind erlaubt.',
    StoreApiException(:final message) => message,
    _ => 'Anfrage fehlgeschlagen. Bitte erneut laden.',
  };
  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
