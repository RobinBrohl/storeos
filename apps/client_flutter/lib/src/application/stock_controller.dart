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

/// Manual stock controller. A real adjustment sends one newly generated
/// `movementId`; retrying the same ambiguous command reuses it. A lost
/// response is only confirmed when the movement with that exact id exists, so
/// another actor's same-quantity adjustment is never attributed.
class StockController extends ChangeNotifier {
  StockController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }

  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;

  List<StockLevelDto>? items;
  String? selectedLocationId, nextCursor, error, notice;
  String search = '';
  bool busy = false, conflict = false;
  Map<String, dynamic>? pendingAdjustment;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
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
    if (_userId == session.user?.id) return;
    _userId = session.user?.id;
    _epoch++;
    items = null;
    selectedLocationId = null;
    nextCursor = null;
    error = notice = null;
    search = '';
    busy = false;
    conflict = false;
    pendingAdjustment = null;
    _idle = null;
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
    selectedLocationId = locationId;
    items = null;
    nextCursor = null;
    error = notice = null;
    conflict = false;
    pendingAdjustment = null;
    return load();
  }

  Future<void> load() => _run((epoch) async {
    conflict = false;
    await _reload(epoch);
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
    items = null;
    nextCursor = null;
    _notify();
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
    final trimmed = query.trim();
    if (trimmed.isEmpty || !_current(_epoch) || selectedLocationId == null) {
      return const [];
    }
    final json = await _get(
      _epoch,
      '/locations/$selectedLocationId/assortment',
      query: {'q': trimmed, 'active': 'true'},
    );
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
      notice = 'Bestand wurde angelegt und erneut geladen.';
      return;
    }
    if (failure != null) throw failure;
    await _reload(epoch);
    notice = 'Bestand angelegt.';
  });

  /// Applies an absolute manual correction with a fresh operation id.
  Future<void> adjust(StockLevelDto level, String quantity, String note) {
    final trimmed = note.trim();
    late final String canonical;
    try {
      canonical = stockQuantityText(stockQuantity(quantity.trim()));
    } on FormatException {
      error = 'Menge: maximal 12 Vor- und 3 Nachkommastellen, nicht negativ.';
      _notify();
      return Future<void>.value();
    }
    if (trimmed.isEmpty) {
      error = 'Eine Begründung ist erforderlich.';
      _notify();
      return Future<void>.value();
    }
    pendingAdjustment = {
      'movementId': _uuid(),
      'levelId': level.id,
      'expectedVersion': level.version,
      'quantity': canonical,
      'note': trimmed,
    };
    return _applyPendingAdjustment();
  }

  /// Retries the exact ambiguous command with the same movementId.
  Future<void> retryPendingAdjustment() => _applyPendingAdjustment();

  Future<void> _applyPendingAdjustment() => _run((epoch) async {
    conflict = false;
    final locationId = selectedLocationId;
    final pending = pendingAdjustment;
    if (locationId == null || pending == null) return;
    Object? failure;
    try {
      await _post(epoch, '${_route(locationId)}/${pending['levelId']}/adjust', {
        'movementId': pending['movementId'],
        'expectedVersion': pending['expectedVersion'],
        'quantity': pending['quantity'],
        'note': pending['note'],
      });
    } catch (error) {
      failure = error;
    }
    _requireCurrent(epoch);
    if (failure != null) {
      await _reconcileAdjustment(epoch, locationId, pending, failure);
      return;
    }
    pendingAdjustment = null;
    await _reload(epoch);
    notice = 'Bestand korrigiert.';
  });

  Future<void> _reconcileAdjustment(
    int epoch,
    String locationId,
    Map<String, dynamic> pending,
    Object failure,
  ) async {
    StockLevelDto? current;
    try {
      current = StockLevelDto.fromJson(
        await _get(epoch, '${_route(locationId)}/${pending['levelId']}'),
      );
    } catch (_) {
      // Keep the original failure.
    }
    if (current != null &&
        await _movementExists(
          epoch,
          locationId,
          pending['levelId'] as String,
          pending['movementId'] as String,
        )) {
      pendingAdjustment = null;
      await _reload(epoch);
      notice = 'Bestand korrigiert und erneut geladen.';
      return;
    }
    if (current != null && current.version == pending['expectedVersion']) {
      // Not applied (or a server-side no-op): the command may be retried.
      throw failure;
    }
    if (current != null &&
        current.version > (pending['expectedVersion'] as int)) {
      conflict = true;
      error =
          'Der Bestand wurde inzwischen anderweitig geändert. Bitte den Serverstand neu laden; die eigene Korrektur ist nicht bestätigt.';
      return;
    }
    throw failure;
  }

  Future<bool> _movementExists(
    int epoch,
    String locationId,
    String levelId,
    String movementId,
  ) async {
    try {
      final json = await _get(
        epoch,
        '${_route(locationId)}/$levelId/movements',
      );
      final raw = json['items'];
      if (raw is! List) return false;
      return raw.any(
        (item) => (item as Map<String, dynamic>)['id'] == movementId,
      );
    } catch (_) {
      return false;
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
