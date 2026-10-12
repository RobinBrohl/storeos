import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum AssignmentOutcome { confirmed, rejected, uncertain, fenced, busy }

class PendingAssignmentCommand {
  PendingAssignmentCommand(
    this.identity,
    this.route,
    PreparationAssignmentCommandInput c,
  ) : kind = c.kind,
      body = Map.unmodifiable(c.toJson());
  final Object identity;
  final String route, kind;
  final Map<String, dynamic> body;
}

class PreparationAssignmentController extends ChangeNotifier {
  PreparationAssignmentController(
    this.session,
    this.platform,
    this.api, {
    this.self = false,
    String Function()? idFactory,
  }) : _newId = idFactory ?? _uuid {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  final String Function() _newId;
  Object? _identity;
  Object? get sessionIdentity => _identity;
  bool _disposed = false, busy = false, _uncertain = false;
  bool get locked => busy || pending != null;
  bool get canRead =>
      platform.allows(
        self
            ? 'production.assignments.self.read'
            : 'production.assignments.manage',
      ) &&
      platform.allows('production.recipes.read');
  bool get canExecute =>
      canRead &&
      (!self ||
          (platform.allows('production.assignments.self.start') &&
              platform.allows('production.batches.self.execute')));
  String get root =>
      '/production/${self ? 'self' : 'manage'}/locations/${session.user!.locationId}/preparation-assignments';
  List<PreparationAssignmentDto> items = [];
  List<PublishedRecipeDto> recipes = [];
  List<Map<String, dynamic>> employees = [];
  PublishedRecipeDto? selection;
  Map<String, dynamic>? employeeSelection, instruction, history, lastConfirmed;
  PreparationAssignmentDto? detail;
  PendingAssignmentCommand? pending;
  String? error,
      notice,
      refreshWarning,
      status,
      nextCursor,
      recipeCursor,
      employeeCursor,
      confirmedId;

  bool _current(Object? identity) =>
      !_disposed &&
      identity != null &&
      identical(identity, _identity) &&
      identical(identity, session.sessionIdentity) &&
      session.isAuthenticated;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    busy = false;
    _uncertain = false;
    items = [];
    recipes = [];
    employees = [];
    selection = null;
    employeeSelection = null;
    detail = null;
    instruction = null;
    history = null;
    lastConfirmed = null;
    pending = null;
    error = null;
    notice = null;
    refreshWarning = null;
    status = null;
    nextCursor = null;
    recipeCursor = null;
    employeeCursor = null;
    confirmedId = null;
    _notify();
  }

  Future<Map<String, dynamic>> _get(
    Object identity,
    String route, {
    Map<String, String>? query,
  }) async {
    if (!_current(identity)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    final result = await session.authorized((token) {
      if (!_current(identity)) {
        throw const StoreApiException('stale_session', 'Session changed.');
      }
      return api.get(token, route, query: query);
    });
    if (!_current(identity)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    return result;
  }

  Future<void> _read(Future<void> Function(Object) work) async {
    if (locked || !canRead || !_current(_identity)) return;
    final identity = _identity!;
    busy = true;
    error = null;
    _notify();
    try {
      await work(identity);
    } catch (e) {
      if (_current(identity)) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : 'Could not load server evidence.';
      }
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _read((identity) async {
    final page = await _get(
      identity,
      root,
      query: {
        'status': ?status,
        if (more && nextCursor != null) 'after': nextCursor!,
      },
    );
    items = [
      if (more) ...items,
      ...(page['items'] as List).map(
        (j) => PreparationAssignmentDto.fromJson(
          Map<String, dynamic>.from(j as Map),
        ),
      ),
    ];
    nextCursor = page['nextCursor'] as String?;
  });
  Future<void> filter(String? value) async {
    if (locked) return;
    status = value;
    items = [];
    nextCursor = null;
    await load();
  }

  Future<void> select(String id) => _read((identity) async {
    detail = null;
    instruction = null;
    history = null;
    selection = null;
    employeeSelection = null;
    if (id != confirmedId) {
      lastConfirmed = null;
      confirmedId = null;
      notice = null;
    }
    detail = PreparationAssignmentDto.fromJson(
      await _get(identity, '$root/$id'),
    );
    refreshWarning = null;
  });
  Future<void> readInstruction() => _read((identity) async {
    if (detail != null) {
      instruction = await _get(identity, '$root/${detail!.id}/recipe');
    }
  });
  Future<void> readHistory() => _read((identity) async {
    if (detail != null) {
      history = await _get(identity, '$root/${detail!.id}/history');
    }
  });
  Future<void> choices({bool more = false}) => _read((identity) async {
    if (self) return;
    final page = await _get(
      identity,
      '/production/recipes',
      query: {if (more && recipeCursor != null) 'after': recipeCursor!},
    );
    recipes = [
      if (more) ...recipes,
      ...(page['items'] as List).map(
        (j) => PublishedRecipeDto.fromJson(Map<String, dynamic>.from(j as Map)),
      ),
    ];
    recipeCursor = page['nextCursor'] as String?;
  });
  Future<void> assignees({bool more = false}) => _read((identity) async {
    if (self) return;
    final page = await _get(
      identity,
      '$root/assignees',
      query: {if (more && employeeCursor != null) 'after': employeeCursor!},
    );
    employees = [
      if (more) ...employees,
      ...(page['items'] as List).map(
        (j) => Map<String, dynamic>.unmodifiable(j as Map),
      ),
    ];
    employeeCursor = page['nextCursor'] as String?;
  });
  void choose(PublishedRecipeDto recipe) {
    if (locked) return;
    selection = recipe;
    detail = null;
    instruction = null;
    history = null;
    _notify();
  }

  void chooseEmployee(Map<String, dynamic> employee) {
    if (locked) return;
    employeeSelection = Map.unmodifiable(employee);
    _notify();
  }

  Future<AssignmentOutcome> create(int count) async {
    if (self || selection == null || employeeSelection == null) {
      return AssignmentOutcome.rejected;
    }
    return _submit('create', root, {
      'id': _newId(),
      'operationId': _newId(),
      'recipeId': selection!.recipe,
      'revisionId': selection!.revisionId,
      'employeeId': employeeSelection!['id'],
      'expectedEmployeeVersion': employeeSelection!['version'],
      'plannedDeclaredBatchCount': count,
    });
  }

  Future<AssignmentOutcome> start() async {
    if (!self || detail == null) return AssignmentOutcome.rejected;
    return _submit('start', '$root/${detail!.id}/start', {
      'operationId': _newId(),
      'expectedVersion': detail!.version,
    });
  }

  Future<AssignmentOutcome> withdraw(String reason) async {
    if (self || detail == null) return AssignmentOutcome.rejected;
    return _submit('withdraw', '$root/${detail!.id}/withdraw', {
      'operationId': _newId(),
      'expectedVersion': detail!.version,
      'reason': reason,
    });
  }

  Future<AssignmentOutcome> _submit(
    String kind,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (locked || !canExecute || !_current(_identity)) {
      return AssignmentOutcome.busy;
    }
    try {
      pending = PendingAssignmentCommand(
        _identity!,
        route,
        PreparationAssignmentCommandInput.fromJson(kind, body),
      );
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return AssignmentOutcome.rejected;
    }
    _uncertain = false;
    return retry();
  }

  Future<AssignmentOutcome> retry() async {
    final c = pending;
    if (c == null || busy) return AssignmentOutcome.busy;
    final identity = c.identity;
    if (!_current(identity)) return AssignmentOutcome.fenced;
    busy = true;
    error = null;
    refreshWarning = null;
    _notify();
    try {
      final result = await session.authorized((token) {
        if (!_current(identity)) {
          throw const StoreApiException('stale_session', 'Session changed.');
        }
        return api.post(token, c.route, c.body);
      });
      if (!_current(identity)) return AssignmentOutcome.fenced;
      lastConfirmed = _freeze(result) as Map<String, dynamic>;
      confirmedId = (result['assignment'] as Map)['id'] as String;
      pending = null;
      _uncertain = false;
      detail = null;
      instruction = null;
      history = null;
      selection = null;
      employeeSelection = null;
      items = items.where((a) => a.id != confirmedId).toList();
      notice = 'Command confirmed by the server.';
      _notify();
      try {
        detail = PreparationAssignmentDto.fromJson(
          await _get(identity, '$root/$confirmedId'),
        );
      } catch (_) {
        if (_current(identity)) {
          refreshWarning =
              'Command confirmed. Reload authoritative assignment detail before further commands.';
        }
      }
      return _current(identity)
          ? AssignmentOutcome.confirmed
          : AssignmentOutcome.fenced;
    } on StoreApiException catch (e) {
      if (!_current(identity)) return AssignmentOutcome.fenced;
      if (!_uncertain &&
          {400, 401, 403, 404, 409, 413, 415, 422}.contains(e.statusCode)) {
        pending = null;
        error = '${e.code}: ${e.message}';
        return AssignmentOutcome.rejected;
      }
      _uncertain = true;
      error =
          'Outcome unconfirmed. Only exact retry is allowed. A later denial does not establish rollback.';
      return AssignmentOutcome.uncertain;
    } catch (_) {
      if (!_current(identity)) return AssignmentOutcome.fenced;
      _uncertain = true;
      error = 'Outcome unconfirmed. Retry the exact command.';
      return AssignmentOutcome.uncertain;
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

Object? _freeze(Object? v) => v is Map
    ? Map<String, dynamic>.unmodifiable(
        v.map((k, v) => MapEntry(k as String, _freeze(v))),
      )
    : v is List
    ? List.unmodifiable(v.map(_freeze))
    : v;
String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
