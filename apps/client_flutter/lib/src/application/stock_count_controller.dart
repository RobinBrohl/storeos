import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

/// Immutable, memory-only identity for an uncertain submitted count command.
class PendingCountCommand {
  PendingCountCommand(
    this.sessionIdentity,
    this.epoch,
    this.route,
    Map<String, dynamic> body,
  ) : body = _freeze(jsonDecode(jsonEncode(body))) as Map<String, dynamic>;
  final Object sessionIdentity;
  final int epoch;
  final String route;
  final Map<String, dynamic> body;
}

class StockCountController extends ChangeNotifier {
  StockCountController(
    this.session,
    this.platform,
    this.api, {
    this.self = false,
    String Function()? operationIdFactory,
  }) : _newId = operationIdFactory ?? _uuid {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  final String Function() _newId;
  Object? _identity;
  int _epoch = 0;
  bool _disposed = false;
  bool busy = false;
  String? error, refreshError, notice, nextCursor, stockCursor;
  List<Map<String, dynamic>>? items, assignees;
  List<StockLevelDto>? stockChoices;
  ManagerCountDto? managerDetail;
  EmployeeCountDto? employeeDetail;
  PendingCountCommand? pending;
  Map<String, dynamic>? lastConfirmed;
  bool get canRead =>
      platform.allows(
        self ? 'stock.counts.self.read' : 'stock.counts.manage',
      ) &&
      (self || platform.allows('stock.levels.manage'));
  bool get canApprove =>
      !self &&
      platform.allows('stock.counts.approve') &&
      platform.allows('stock.levels.manage');
  String get root => self
      ? '/me/stock-counts'
      : '/locations/${session.user!.locationId}/stock-counts';
  String? get selectedId => self ? employeeDetail?.id : managerDetail?.id;
  int? get selectedVersion =>
      self ? employeeDetail?.version : managerDetail?.version;

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    final uncertain = pending != null;
    _identity = session.sessionIdentity;
    _epoch++;
    busy = false;
    items = null;
    assignees = null;
    stockChoices = null;
    managerDetail = null;
    employeeDetail = null;
    pending = null;
    lastConfirmed = null;
    nextCursor = null;
    stockCursor = null;
    error = null;
    refreshError = null;
    notice = uncertain
        ? 'Sitzung geändert. Lokale Wiederholungsverfolgung beendet. Bitte Serverstand laden; eine Änderung wurde dadurch nicht rückgängig gemacht.'
        : null;
    _notify();
  }

  bool _current(int epoch) =>
      !_disposed &&
      epoch == _epoch &&
      session.isAuthenticated &&
      identical(_identity, session.sessionIdentity);
  void _check(int epoch) {
    if (!_current(epoch)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<Map<String, dynamic>> _get(
    int epoch,
    String route, {
    String? after,
  }) async {
    _check(epoch);
    final result = await session.authorized(
      (token) => api.get(token, route, after: after),
    );
    _check(epoch);
    return result;
  }

  Future<void> _run(Future<void> Function(int) action) async {
    if (busy || !_current(_epoch) || !canRead) return;
    final epoch = _epoch;
    busy = true;
    error = null;
    _notify();
    try {
      await action(epoch);
    } on StoreApiException catch (e) {
      if (_current(epoch)) error = e.message;
    } catch (_) {
      if (_current(epoch)) error = 'Serverstand konnte nicht bestätigt werden.';
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _run((epoch) async {
    final page = await _get(epoch, root, after: more ? nextCursor : null);
    final rows = (page['items'] as List).cast<Map<String, dynamic>>();
    items = [if (more) ...?items, ...rows];
    nextCursor = page['nextCursor'] as String?;
  });
  Future<void> select(String id) => _run((epoch) async {
    _setDetail(await _get(epoch, '$root/$id'));
  });
  void closeDetail() {
    if (busy) return;
    managerDetail = null;
    employeeDetail = null;
    _notify();
  }

  void _setDetail(Map<String, dynamic> result) {
    if (self) {
      employeeDetail = EmployeeCountDto.fromJson(result);
    } else {
      managerDetail = ManagerCountDto.fromJson(result);
    }
  }

  Future<void> choices({bool more = false}) => _run((epoch) async {
    if (self) return;
    final location = session.user!.locationId;
    final stock = await _get(
      epoch,
      '/locations/$location/stock',
      after: more ? stockCursor : null,
    );
    final levels = (stock['items'] as List)
        .map((v) => StockLevelDto.fromJson(v as Map<String, dynamic>))
        .toList();
    stockChoices = [if (more) ...?stockChoices, ...levels];
    stockCursor = stock['nextCursor'] as String?;
    if (!more) {
      assignees = (await _get(
        epoch,
        '$root/assignees',
      ))['items'].cast<Map<String, dynamic>>();
    }
  });
  Future<List<Map<String, dynamic>>> history(
    String count,
    String line, {
    String? after,
  }) async {
    final epoch = _epoch;
    final result = await _get(
      epoch,
      '$root/$count/lines/$line/rounds',
      after: after,
    );
    if (self) {
      for (final row in result['items'] as List) {
        EmployeeCountRoundDto.fromJson(row as Map<String, dynamic>);
      }
    }
    return [
      {'items': result['items'], 'nextCursor': result['nextCursor']},
    ];
  }

  Future<bool> open(
    String employee,
    List<String> levels,
    String purpose, {
    String? preceding,
  }) async {
    if (self) return false;
    return _submit('open', root, {
      'operationId': _newId(),
      'id': _newId(),
      'employeeId': employee,
      'stockLevelIds': levels,
      'purpose': purpose,
      'precedingCountId': preceding,
    });
  }

  Future<bool> record(
    EmployeeCountLineDto line,
    String quantity,
    String? note,
  ) async {
    if (!self || employeeDetail == null) return false;
    return _submit(
      'observation',
      '$root/${employeeDetail!.id}/lines/${line.id}/observations',
      {
        'operationId': _newId(),
        'expectedVersion': employeeDetail!.version,
        'roundId': line.round.id,
        'quantity': quantity.trim().replaceAll(',', '.'),
        'note': note?.trim().isEmpty == true ? null : note,
      },
    );
  }

  Future<bool> recount(List<String> lines, String reason) async {
    if (self || managerDetail == null) return false;
    return _submit('recount', '$root/${managerDetail!.id}/recount', {
      'operationId': _newId(),
      'expectedVersion': managerDetail!.version,
      'lineIds': lines,
      'reason': reason,
    });
  }

  Future<bool> approve() async {
    if (!canApprove || managerDetail == null) return false;
    return _submit('approve', '$root/${managerDetail!.id}/approve', {
      'operationId': _newId(),
      'expectedVersion': managerDetail!.version,
    });
  }

  Future<bool> cancel(String reason) async {
    if (self || managerDetail == null) return false;
    return _submit('cancel', '$root/${managerDetail!.id}/cancel', {
      'operationId': _newId(),
      'expectedVersion': managerDetail!.version,
      'reason': reason,
    });
  }

  Future<bool> _submit(
    String kind,
    String route,
    Map<String, dynamic> input,
  ) async {
    if (busy || pending != null || !_current(_epoch) || !canRead) return false;
    try {
      final command = StockCountCommandInput.fromJson(kind, input);
      pending = PendingCountCommand(
        _identity!,
        _epoch,
        route,
        command.toJson(),
      );
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return false;
    }
    return retry();
  }

  Future<bool> retry() async {
    final command = pending;
    if (command == null ||
        busy ||
        !_current(command.epoch) ||
        !identical(command.sessionIdentity, _identity)) {
      return false;
    }
    busy = true;
    error = null;
    refreshError = null;
    _notify();
    final epoch = command.epoch;
    try {
      _check(epoch);
      final result = await session.authorized(
        (token) => api.post(token, command.route, command.body),
      );
      _check(epoch);
      _setDetail(result);
      lastConfirmed = result;
      pending = null;
      notice = 'Änderung vom Server bestätigt.';
      _notify();
      try {
        final id = selectedId!;
        _setDetail(await _get(epoch, '$root/$id'));
        final page = await _get(epoch, root);
        items = (page['items'] as List).cast<Map<String, dynamic>>();
        nextCursor = page['nextCursor'] as String?;
      } catch (_) {
        if (_current(epoch)) {
          refreshError =
              'Änderung bestätigt. Aktueller Serverstand konnte nicht neu geladen werden.';
        }
      }
      return _current(epoch);
    } on StoreApiException catch (e) {
      if (_current(epoch)) {
        final definitive = {
          400,
          401,
          403,
          404,
          409,
          413,
          415,
          422,
        }.contains(e.statusCode);
        if (definitive) {
          pending = null;
          error = switch (e.code) {
            'count_stale' =>
              'Bestand geändert. Neu laden und Nachzählung anfordern.',
            'count_incomplete' =>
              'Für jede aktuelle Runde ist eine Beobachtung erforderlich.',
            'self_approval_forbidden' =>
              'Ein anderes Konto muss die selbst erfasste Beobachtung freigeben.',
            'assignee_unavailable' =>
              'Zählende Person nicht verfügbar. Abbrechen und eine Folgezählung eröffnen.',
            'round_conflict' =>
              'Eine neue Runde wurde angefordert. Neu laden und erneut physisch zählen.',
            'observation_exists' =>
              'Beobachtung bereits angenommen. Für einen neuen Wert ist eine Nachzählung erforderlich.',
            'operation_conflict' =>
              'Auftragskennung bereits anders verwendet. Serverstand laden und prüfen.',
            'count_conflict' =>
              'Zählung inzwischen geändert. Serverstand laden und erneut prüfen.',
            _ => e.message,
          };
        } else {
          error =
              'Ergebnis unbestätigt. Nur denselben Auftrag exakt wiederholen.';
        }
      }
      return false;
    } catch (_) {
      if (_current(epoch)) {
        error =
            'Ergebnis unbestätigt. Nur denselben Auftrag exakt wiederholen.';
      }
      return false;
    } finally {
      if (_current(epoch)) {
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

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

Object? _freeze(Object? value) => value is Map<String, dynamic>
    ? Map<String, dynamic>.unmodifiable(
        value.map((key, value) => MapEntry(key, _freeze(value))),
      )
    : value is List
    ? List.unmodifiable(value.map(_freeze))
    : value;
