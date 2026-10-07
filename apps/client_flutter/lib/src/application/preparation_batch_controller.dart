import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum PreparationOutcome { confirmed, rejected, uncertain, fenced, busy }

class PendingPreparationCommand {
  PendingPreparationCommand(
    this.identity,
    this.route,
    PreparationCommandInput input,
  ) : kind = input.kind,
      body = Map.unmodifiable(input.toJson());
  final Object identity;
  final String kind;
  final String route;
  final Map<String, dynamic> body;
}

class PreparationBatchController extends ChangeNotifier {
  PreparationBatchController(
    this.session,
    this.platform,
    this.api, {
    this.self = true,
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
  bool _disposed = false, busy = false;
  String? error, notice, refreshWarning, nextCursor, recipeCursor, status;
  List<PreparationBatchDto> items = [];
  List<PublishedRecipeDto> recipes = [];
  PublishedRecipeDto? selection;
  PreparationBatchDto? detail;
  Map<String, dynamic>? instruction, lastConfirmed;
  String? lastConfirmedKind, confirmedBatchId;
  int? confirmedOriginalCount;
  PendingPreparationCommand? pending;
  bool get canRead => platform.allows(
    self ? 'production.batches.self.read' : 'production.batches.manage',
  );
  bool get canExecute => platform.allows(
    self ? 'production.batches.self.execute' : 'production.batches.manage',
  );
  bool get canReadRecipe => platform.allows('production.recipes.read');
  bool get locked => busy || pending != null;
  String get root =>
      '/production/${self ? 'self' : 'manage'}/locations/${session.user!.locationId}/batches';
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
    error = null;
    notice = null;
    refreshWarning = null;
    nextCursor = null;
    recipeCursor = null;
    status = null;
    items = [];
    recipes = [];
    selection = null;
    detail = null;
    instruction = null;
    lastConfirmed = null;
    lastConfirmedKind = null;
    confirmedBatchId = null;
    confirmedOriginalCount = null;
    pending = null;
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
            : 'Could not load confirmed server evidence.';
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
    final rows = (page['items'] as List).map(
      (j) => PreparationBatchDto.fromJson(j as Map<String, dynamic>),
    );
    items = [if (more) ...items, ...rows];
    nextCursor = page['nextCursor'] as String?;
  });
  Future<void> filter(String? value) async {
    if (locked) return;
    status = value;
    nextCursor = null;
    items = [];
    await load();
  }

  Future<void> select(String id) => _read((identity) async {
    if (id != confirmedBatchId) _clearConfirmation();
    detail = null;
    instruction = null;
    selection = null;
    detail = PreparationBatchDto.fromJson(await _get(identity, '$root/$id'));
    refreshWarning = null;
  });
  void _clearConfirmation() {
    lastConfirmed = null;
    lastConfirmedKind = null;
    confirmedBatchId = null;
    confirmedOriginalCount = null;
    notice = null;
    refreshWarning = null;
  }

  Future<void> readInstruction() => _read((identity) async {
    if (detail == null || !canReadRecipe) return;
    instruction = await _get(identity, '$root/${detail!.id}/recipe');
  });
  Future<void> choices({bool more = false}) => _read((identity) async {
    if (!self || !canReadRecipe) return;
    final page = await _get(
      identity,
      '/production/recipes',
      query: {if (more && recipeCursor != null) 'after': recipeCursor!},
    );
    recipes = [
      if (more) ...recipes,
      ...(page['items'] as List).map(
        (j) => PublishedRecipeDto.fromJson(j as Map<String, dynamic>),
      ),
    ];
    recipeCursor = page['nextCursor'] as String?;
  });
  void choose(PublishedRecipeDto recipe) {
    if (locked) return;
    selection = recipe;
    _clearConfirmation();
    detail = null;
    instruction = null;
    _notify();
  }

  void closeDetail() {
    if (locked) return;
    selection = null;
    _clearConfirmation();
    detail = null;
    instruction = null;
    _notify();
  }

  Future<PreparationOutcome> open(int? planned) async {
    if (!self || selection == null || !canReadRecipe) {
      return PreparationOutcome.rejected;
    }
    return _submit('open', root, {
      'batchId': _newId(),
      'operationId': _newId(),
      'recipeId': selection!.recipe,
      'revisionId': selection!.revisionId,
      'plannedDeclaredBatchCount': planned,
    });
  }

  Future<PreparationOutcome> complete(int count, String? note) async {
    if (!self || detail == null) return PreparationOutcome.rejected;
    return _submit('complete', '$root/${detail!.id}/complete', {
      'operationId': _newId(),
      'expectedVersion': detail!.version,
      'actualDeclaredBatchCount': count,
      'note': note == null || note.trim().isEmpty ? null : note,
    });
  }

  Future<PreparationOutcome> cancel(String reason) async {
    if (detail == null) return PreparationOutcome.rejected;
    return _submit(
      self ? 'employee_cancel' : 'manager_cancel',
      '$root/${detail!.id}/cancel',
      {
        'operationId': _newId(),
        'expectedVersion': detail!.version,
        'reason': reason,
      },
    );
  }

  Future<PreparationOutcome> correct(int count, String reason) async {
    if (self || detail == null) return PreparationOutcome.rejected;
    return _submit('count_correct', '$root/${detail!.id}/count-corrections', {
      'operationId': _newId(),
      'expectedVersion': detail!.version,
      'expectedLatestCorrectionNumber': detail!.latestCorrectionNumber,
      'replacementDeclaredBatchCount': count,
      'reason': reason,
    });
  }

  Future<PreparationOutcome> _submit(
    String kind,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (locked || !canExecute || !_current(_identity)) {
      return PreparationOutcome.busy;
    }
    try {
      pending = PendingPreparationCommand(
        _identity!,
        route,
        PreparationCommandInput.fromJson(kind, body),
      );
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return PreparationOutcome.rejected;
    }
    return retry();
  }

  Future<PreparationOutcome> retry() async {
    final command = pending;
    if (command == null || busy) return PreparationOutcome.busy;
    final identity = command.identity;
    if (!_current(identity)) return PreparationOutcome.fenced;
    final selected = detail?.id;
    final originalCount = detail?.actual;
    busy = true;
    error = null;
    refreshWarning = null;
    _notify();
    try {
      final result = await session.authorized((token) {
        if (!_current(identity)) {
          throw const StoreApiException('stale_session', 'Session changed.');
        }
        return api.post(token, command.route, command.body);
      });
      if (!_current(identity)) return PreparationOutcome.fenced;
      lastConfirmed = Map.unmodifiable(result);
      lastConfirmedKind = command.kind;
      confirmedBatchId = result['batch'] != null
          ? PreparationBatchDto.fromJson(
              result['batch'] as Map<String, dynamic>,
            ).id
          : selected!;
      confirmedOriginalCount = originalCount;
      // Command receipts are immutable results, not current detail projections.
      detail = null;
      instruction = null;
      items = items.where((b) => b.id != confirmedBatchId).toList();
      pending = null;
      selection = null;
      notice = 'Command confirmed by the server.';
      _notify();
      try {
        final id = confirmedBatchId!;
        detail = PreparationBatchDto.fromJson(
          await _get(identity, '$root/$id'),
        );
      } catch (_) {
        if (_current(identity)) {
          refreshWarning =
              'Command confirmed. Current batch detail is unavailable; reload authoritative detail before further commands.';
        }
      }
      try {
        final page = await _get(identity, root, query: {'status': ?status});
        items = (page['items'] as List)
            .map((j) => PreparationBatchDto.fromJson(j as Map<String, dynamic>))
            .toList();
        nextCursor = page['nextCursor'] as String?;
      } catch (_) {
        if (_current(identity)) {
          refreshWarning ??=
              'Command confirmed. Current history could not be refreshed.';
        }
      }
      return _current(identity)
          ? PreparationOutcome.confirmed
          : PreparationOutcome.fenced;
    } on StoreApiException catch (e) {
      if (!_current(identity)) return PreparationOutcome.fenced;
      if ({400, 401, 403, 404, 409, 413, 415, 422}.contains(e.statusCode)) {
        pending = null;
        error = '${e.code}: ${e.message}';
        return PreparationOutcome.rejected;
      }
      error = 'Outcome unconfirmed. Retry the exact same command.';
      return PreparationOutcome.uncertain;
    } catch (_) {
      if (!_current(identity)) return PreparationOutcome.fenced;
      error = 'Outcome unconfirmed. Retry the exact same command.';
      return PreparationOutcome.uncertain;
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

String _uuid() {
  final r = Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
