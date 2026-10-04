import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

/// One movement-history page.
class StockMovementPageResult {
  const StockMovementPageResult(this.items, this.nextCursor);

  final List<StockMovementDto> items;
  final String? nextCursor;
}

enum StockAdjustmentOutcome {
  confirmedMutation,
  confirmedNoOp,
  invalidInput,
  unconfirmed,
  conflict,
  rejected,
  ignored,
}

class StockAdjustmentResult {
  const StockAdjustmentResult(this.outcome, {this.refreshFailed = false});

  final StockAdjustmentOutcome outcome;
  final bool refreshFailed;
  bool get confirmed =>
      outcome == StockAdjustmentOutcome.confirmedMutation ||
      outcome == StockAdjustmentOutcome.confirmedNoOp;
}

/// Memory-only immutable identity, including the original authorization scope.
class PendingStockAdjustment {
  const PendingStockAdjustment({
    required this.epoch,
    required this.sessionIdentity,
    required this.actorId,
    required this.locationId,
    required this.levelId,
    required this.input,
  });

  final int epoch;
  final Object sessionIdentity;
  final String actorId, locationId, levelId;
  final StockAdjustInput input;
  String get movementId => input.movementId;
}

/// Manual stock controller. A real adjustment sends one newly generated
/// `movementId`; retrying the same ambiguous command reuses it. A lost
/// response remains unconfirmed until an exact retry receives a valid response.
class StockController extends ChangeNotifier {
  StockController(
    this.session,
    this.platform,
    this.api, {
    String Function()? movementIdFactory,
  }) : _newMovementId = movementIdFactory ?? _uuid {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }

  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final String Function() _newMovementId;

  List<StockLevelDto>? items;
  String? selectedLocationId, nextCursor, error, notice;
  String search = '';
  bool busy = false, conflict = false;
  bool adjustmentAbandoned = false;
  PendingStockAdjustment? _pendingAdjustment;
  PendingStockAdjustment? get pendingAdjustment => _pendingAdjustment;
  PendingStockAdjustment? _lastAdjustment;
  PendingStockAdjustment? get lastAdjustment => _lastAdjustment;
  StockAdjustmentResult? adjustmentResult;
  String? quantityError, noteError, refreshError;
  bool _disposed = false;
  int _epoch = 0;
  Object? _sessionIdentity;
  Completer<void>? _idle;

  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  bool get canManage => platform.allows('stock.levels.manage');
  bool get hasMore => nextCursor != null;
  List<LocationDto> get locations =>
      platform.organization?.locations
          .where((location) => location.name != null)
          .toList() ??
      [];
  String? get selectionUnavailableReason => platform.organization == null
      ? 'Standorte sind noch nicht bestätigt. Bitte die Organisation laden.'
      : locations.isEmpty
      ? 'Zuerst unter Organisation einen Standort einrichten.'
      : null;

  StockLevelDto? levelFor(String articleId) {
    for (final item in items ?? <StockLevelDto>[]) {
      if (item.articleId == articleId) return item;
    }
    return null;
  }

  void _sessionChanged() {
    if (identical(_sessionIdentity, session.sessionIdentity)) return;
    final discardedPending = _pendingAdjustment != null;
    _sessionIdentity = session.sessionIdentity;
    _epoch++;
    items = null;
    selectedLocationId = null;
    nextCursor = null;
    error = notice = null;
    if (discardedPending && session.isAuthenticated) {
      notice =
          'Sitzung geändert. Die lokale Wiederholungsverfolgung wurde beendet. '
          'Eine Serverkorrektur wurde dadurch weder abgebrochen noch '
          'rückgängig gemacht. Bitte Serverstand neu laden.';
    }
    search = '';
    busy = false;
    conflict = false;
    adjustmentAbandoned = false;
    _pendingAdjustment = null;
    _lastAdjustment = null;
    adjustmentResult = null;
    quantityError = noteError = refreshError = null;
    _idle = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int epoch) =>
      !_disposed &&
      epoch == _epoch &&
      session.isAuthenticated &&
      identical(_sessionIdentity, session.sessionIdentity);
  void _requireCurrent(int epoch) {
    if (!_current(epoch)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
  }

  String _route(String locationId) => '/locations/$locationId/stock';

  Future<Map<String, dynamic>> _get(
    int epoch,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    _requireCurrent(epoch);
    final response = await session.authorized(
      (token) => api.get(token, route, after: after, query: query),
    );
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

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (busy || !_current(_epoch) || !canManage || selectedLocationId == null) {
      return;
    }
    final epoch = _epoch;
    final idle = Completer<void>();
    _idle = idle;
    busy = true;
    error = notice = null;
    _notify();
    try {
      _requireCurrent(epoch);
      await action(epoch);
    } on StoreApiException catch (failure) {
      if (_current(epoch)) {
        _mapFailure(failure);
      }
    } catch (_) {
      if (_current(epoch)) {
        error =
            'Der Bestand konnte nicht bestätigt werden. Bitte erneut laden.';
      }
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
      if (identical(_idle, idle)) _idle = null;
      idle.complete();
    }
  }

  void _mapFailure(StoreApiException failure) {
    if (failure.code == 'stock_conflict' ||
        failure.code == 'operation_conflict' ||
        failure.code == 'lost_response') {
      conflict = true;
      error =
          'Der Bestand wurde inzwischen geändert. Bitte den Serverstand neu laden.';
    } else if (failure.code == 'not_in_assortment') {
      error =
          'Der Artikel hat am Standort keine aktive Sortimentsfreigabe und kann keinen neuen Bestand erhalten.';
    } else if (failure.code == 'article_inactive') {
      error =
          'Der Artikel ist global inaktiv und kann keinen neuen Bestand erhalten.';
    } else if (failure.code == 'already_exists') {
      error =
          'Für den Artikel wird an diesem Standort bereits Bestand geführt.';
    } else {
      error = failure.message;
    }
  }

  Future<void> selectLocation(String locationId) {
    if (selectedLocationId == locationId) return Future<void>.value();
    if (busy || pendingAdjustment != null) {
      return Future<void>.value();
    }
    selectedLocationId = locationId;
    items = null;
    nextCursor = null;
    error = notice = null;
    conflict = false;
    adjustmentAbandoned = false;
    return load();
  }

  Future<void> load() => _run((epoch) async {
    await _reload(epoch);
    _requireCurrent(epoch);
    refreshError = null;
  });

  Future<void> setSearch(String value) {
    search = value;
    return load();
  }

  Future<void> loadMore() => _run((epoch) async {
    final cursor = nextCursor;
    final locationId = selectedLocationId;
    if (cursor == null || locationId == null) return;
    final json = await _get(
      epoch,
      _route(locationId),
      after: cursor,
      query: _query(),
    );
    _appendPage(epoch, json);
  });

  Map<String, String> _query() => {
    if (search.trim().isNotEmpty) 'q': search.trim(),
  };

  Future<void> _reload(int epoch) async {
    _requireCurrent(epoch);
    final locationId = selectedLocationId;
    if (locationId == null) return;
    final json = await _get(epoch, _route(locationId), query: _query());
    _appendPage(epoch, json, replace: true);
  }

  void _appendPage(
    int epoch,
    Map<String, dynamic> json, {
    bool replace = false,
  }) {
    _requireCurrent(epoch);
    final locationId = selectedLocationId;
    final rawItems = json['items'];
    if (rawItems is! List || locationId == null) throw const FormatException();
    final loaded = rawItems
        .map((item) => StockLevelDto.fromJson(item as Map<String, dynamic>))
        .toList();
    if (loaded.any((item) => item.locationId != locationId)) {
      throw const FormatException();
    }
    items = [
      ...replace ? <StockLevelDto>[] : items ?? <StockLevelDto>[],
      ...loaded,
    ];
    final cursor = json['nextCursor'];
    nextCursor = cursor is String && cursor.isNotEmpty ? cursor : null;
    _notify();
  }

  /// Active assortment candidates for the open dialog. Globally inactive
  /// articles are excluded deterministically; articles that already carry a
  /// level are returned but must be shown disabled.
  Future<List<ArticleAssortmentDto>> searchOpenCandidates(String query) async {
    final epoch = _epoch;
    final trimmed = query.trim();
    if (trimmed.isEmpty || !_current(_epoch) || selectedLocationId == null) {
      return const [];
    }
    final json = await _get(
      epoch,
      '/locations/$selectedLocationId/assortment',
      query: {'q': trimmed, 'active': 'true'},
    );
    _requireCurrent(epoch);
    final raw = json['items'];
    if (raw is! List) throw const FormatException();
    return raw
        .map(
          (item) => ArticleAssortmentDto.fromJson(item as Map<String, dynamic>),
        )
        .where((item) => item.article.isActive)
        .toList();
  }

  /// Opens the first recorded quantity for an article. The client UUID is the
  /// reconciliation key; the immutable aggregate id proves which open created
  /// the level even if it was adjusted afterwards.
  Future<void> openStock(ArticleAssortmentDto article) => _run((epoch) async {
    conflict = false;
    final locationId = selectedLocationId;
    if (locationId == null) return;
    final input = StockOpenInput(
      id: _uuid(),
      articleId: article.article.id,
      quantity: '0',
      note: null,
    ).toJson();
    Object? failure;
    try {
      await _post(epoch, _route(locationId), input);
    } catch (error) {
      failure = error;
    }
    _requireCurrent(epoch);
    StockLevelDto? reconciled;
    try {
      reconciled = StockLevelDto.fromJson(
        await _get(epoch, '${_route(locationId)}/${input['id']}'),
      );
    } catch (_) {
      // The open did not commit or is not readable; keep the original error.
    }
    if (reconciled != null &&
        reconciled.id == input['id'] &&
        reconciled.articleId == input['articleId'] &&
        reconciled.locationId == locationId) {
      await _reload(epoch);
      _requireCurrent(epoch);
      notice = 'Bestand wurde angelegt und erneut geladen.';
      return;
    }
    if (failure != null) throw failure;
    await _reload(epoch);
    _requireCurrent(epoch);
    notice = 'Bestand angelegt.';
  });

  bool get adjustmentDecisionRequired => conflict || adjustmentAbandoned;
  bool get adjustmentBlocked =>
      busy || pendingAdjustment != null || adjustmentDecisionRequired;

  /// Acquires the guard synchronously, before validation or UUID creation.
  Future<StockAdjustmentResult> adjust(
    StockLevelDto level,
    String quantity,
    String note,
  ) => _submitAdjustment(level: level, quantity: quantity, note: note);

  Future<StockAdjustmentResult> retryPendingAdjustment() => _submitAdjustment();

  /// Discards local tracking only; it neither cancels nor reverses a write.
  void abandonPendingAdjustment() {
    if (busy || pendingAdjustment == null) return;
    _pendingAdjustment = null;
    adjustmentResult = null;
    error = null;
    notice =
        'Lokale Nachverfolgung beendet. Eine Serverkorrektur wird dadurch '
        'nicht abgebrochen oder rückgängig gemacht. Ob sie gespeichert wurde, '
        'ist weiterhin unklar. Bitte Serverstand laden.';
    conflict = false;
    adjustmentAbandoned = true;
    _notify();
  }

  /// An explicit reload starts a new decision after conflict or abandonment.
  Future<void> prepareNewAdjustment() async {
    if (busy || pendingAdjustment != null) return;
    await _run((epoch) async {
      await _reload(epoch);
      _requireCurrent(epoch);
      conflict = false;
      adjustmentAbandoned = false;
      adjustmentResult = null;
      error = refreshError = null;
    });
  }

  Future<StockAdjustmentResult> _submitAdjustment({
    StockLevelDto? level,
    String? quantity,
    String? note,
  }) async {
    const ignored = StockAdjustmentResult(StockAdjustmentOutcome.ignored);
    if (busy || !_current(_epoch) || !canManage || selectedLocationId == null) {
      return ignored;
    }
    final retry = level == null;
    if ((!retry && (pendingAdjustment != null || adjustmentDecisionRequired)) ||
        (retry && pendingAdjustment == null)) {
      return ignored;
    }
    final epoch = _epoch;
    final idle = Completer<void>();
    _idle = idle;
    busy = true;
    try {
      if (!retry) {
        error = notice = refreshError = null;
        quantityError = noteError = null;
        String? canonical, normalized;
        try {
          canonical = stockQuantityText(stockQuantity(quantity!.trim()));
        } on FormatException {
          quantityError =
              'Menge: maximal 12 Vor- und 3 Nachkommastellen, nicht negativ.';
        }
        try {
          normalized = normalizeStockAdjustNote(note);
        } on FormatException {
          noteError =
              'Eine Begründung ist erforderlich: maximal 500 Zeichen, '
              'eine Zeile, keine Steuerzeichen.';
        }
        if (quantityError != null || noteError != null) {
          error = quantityError ?? noteError;
          return adjustmentResult = const StockAdjustmentResult(
            StockAdjustmentOutcome.invalidInput,
          );
        }
        if (level.locationId != selectedLocationId ||
            level.version < 1 ||
            level.version > maxIncrementableJsonSafeInteger) {
          error =
              'Der Bestand passt nicht zum aktuellen Standort oder zur '
              'unterstützten Version. Bitte Serverstand laden.';
          return adjustmentResult = const StockAdjustmentResult(
            StockAdjustmentOutcome.rejected,
          );
        }
        _pendingAdjustment = PendingStockAdjustment(
          epoch: epoch,
          sessionIdentity: _sessionIdentity!,
          actorId: session.user!.id,
          locationId: level.locationId,
          levelId: level.id,
          input: StockAdjustInput(
            movementId: _newMovementId(),
            expectedVersion: level.version,
            quantity: canonical!,
            note: normalized!,
          ),
        );
        _lastAdjustment = pendingAdjustment;
      }
      final pending = pendingAdjustment!;
      if (pending.epoch != epoch ||
          !identical(pending.sessionIdentity, session.sessionIdentity) ||
          pending.actorId != session.user?.id ||
          pending.locationId != selectedLocationId) {
        return ignored;
      }
      error = notice = refreshError = null;
      adjustmentResult = null;
      _notify();
      StockLevelDto confirmed;
      try {
        confirmed = StockLevelDto.fromJson(
          await _post(
            epoch,
            '${_route(pending.locationId)}/${pending.levelId}/adjust',
            pending.input.toJson(),
          ),
        );
        _requireCurrent(epoch);
        if (confirmed.id != pending.levelId ||
            confirmed.locationId != pending.locationId ||
            confirmed.version < pending.input.expectedVersion ||
            (confirmed.version == pending.input.expectedVersion &&
                confirmed.quantity != pending.input.quantity)) {
          throw const FormatException('Unexpected adjustment response.');
        }
      } catch (failure) {
        if (!_current(epoch)) return ignored;
        if (failure is StoreApiException &&
            (failure.code == 'stock_conflict' ||
                failure.code == 'operation_conflict')) {
          _pendingAdjustment = null;
          conflict = true;
          error =
              '${failure.code}: Korrektur abgelehnt '
              '(Operation ${pending.movementId}). Serverstand laden und '
              'bewusst neu entscheiden.';
          return adjustmentResult = const StockAdjustmentResult(
            StockAdjustmentOutcome.conflict,
          );
        }
        if (failure is StoreApiException &&
            const {
              400,
              401,
              403,
              404,
              405,
              409,
              413,
              415,
              422,
            }.contains(failure.statusCode)) {
          _pendingAdjustment = null;
          error = failure.message;
          return adjustmentResult = const StockAdjustmentResult(
            StockAdjustmentOutcome.rejected,
          );
        }
        error =
            'Die eigene Korrektur ist nicht bestätigt. Genau diese '
            'Operation unverändert erneut senden.';
        return adjustmentResult = const StockAdjustmentResult(
          StockAdjustmentOutcome.unconfirmed,
        );
      }
      _pendingAdjustment = null;
      final outcome = confirmed.version == pending.input.expectedVersion
          ? StockAdjustmentOutcome.confirmedNoOp
          : StockAdjustmentOutcome.confirmedMutation;
      adjustmentResult = StockAdjustmentResult(outcome);
      notice = outcome == StockAdjustmentOutcome.confirmedNoOp
          ? 'Menge bereits unverändert. Keine Bestandsbewegung aufgezeichnet.'
          : 'Bestandkorrektur bestätigt.';
      items = [
        for (final item in items ?? <StockLevelDto>[])
          if (item.id == confirmed.id) confirmed else item,
      ];
      try {
        await _reload(epoch);
        _requireCurrent(epoch);
      } catch (_) {
        if (!_current(epoch)) return ignored;
        refreshError =
            'Korrektur bestätigt; die Bestandsliste konnte nicht '
            'aktualisiert werden. Bitte erneut laden.';
        adjustmentResult = StockAdjustmentResult(outcome, refreshFailed: true);
      }
      return adjustmentResult!;
    } finally {
      if (_current(epoch)) {
        busy = false;
        _notify();
      }
      if (identical(_idle, idle)) _idle = null;
      idle.complete();
    }
  }

  /// Loads one movement-history page ordered by descending balanceVersion.
  Future<StockMovementPageResult> loadMovements(
    StockLevelDto level, {
    String? after,
  }) async {
    final epoch = _epoch;
    final locationId = selectedLocationId;
    if (locationId == null || !_current(epoch)) {
      return const StockMovementPageResult([], null);
    }
    final json = await _get(
      epoch,
      '${_route(locationId)}/${level.id}/movements',
      after: after,
    );
    _requireCurrent(epoch);
    final raw = json['items'];
    if (raw is! List) throw const FormatException();
    final cursor = json['nextCursor'];
    return StockMovementPageResult(
      raw
          .map(
            (item) => StockMovementDto.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      cursor is String && cursor.isNotEmpty ? cursor : null,
    );
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
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
