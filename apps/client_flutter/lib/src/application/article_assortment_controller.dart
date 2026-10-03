import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

/// Location assortment controller. Membership state and the embedded article
/// state stay independent: the list defaults to active memberships, and
/// "Auch inaktive anzeigen" omits the active filter instead of asking for
/// inactive rows only.
class ArticleAssortmentController extends ChangeNotifier {
  ArticleAssortmentController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  List<ArticleAssortmentDto>? items;
  String? selectedLocationId, nextCursor, error, notice;
  String search = '';
  bool showInactive = false;
  bool busy = false, conflict = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  Completer<void>? _idle;

  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  bool get canManage => platform.allows('inventory.assortment.manage');
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

  ArticleAssortmentDto? associationFor(String articleId) {
    for (final item in items ?? <ArticleAssortmentDto>[]) {
      if (item.article.id == articleId) return item;
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
    showInactive = false;
    busy = false;
    conflict = false;
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

  String _route(String locationId) => '/locations/$locationId/assortment';

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
        if (failure.code == 'assortment_conflict' ||
            failure.code == 'lost_response') {
          conflict = true;
          error =
              'Das Sortiment wurde inzwischen geändert. Bitte den Serverstand neu laden.';
        } else if (failure.code == 'article_inactive') {
          error =
              'Der Artikel ist global inaktiv und kann nicht neu aktiviert werden. Erst den Artikel reaktivieren.';
        } else if (failure.code == 'already_exists') {
          error =
              'Der Artikel ist bereits im Sortiment. Bei einem inaktiven Eintrag zuerst "Auch inaktive anzeigen" aktivieren und dort reaktivieren.';
        } else {
          error = failure.message;
        }
      }
    } catch (_) {
      if (_current(epoch)) {
        error =
            'Das Sortiment konnte nicht bestätigt werden. Bitte erneut laden.';
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

  Map<String, String> _query({required bool? active}) => {
    if (search.trim().isNotEmpty) 'q': search.trim(),
    if (active != null) 'active': active ? 'true' : 'false',
  };

  Future<void> selectLocation(String locationId) {
    if (selectedLocationId == locationId) return Future<void>.value();
    selectedLocationId = locationId;
    items = null;
    nextCursor = null;
    error = notice = null;
    conflict = false;
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

  Future<void> setShowInactive(bool value) {
    showInactive = value;
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
      query: _query(active: showInactive ? null : true),
    );
    _appendPage(epoch, json);
  });

  Future<void> _reload(int epoch) async {
    _requireCurrent(epoch);
    final locationId = selectedLocationId;
    if (locationId == null) return;
    items = null;
    nextCursor = null;
    _notify();
    final json = await _get(
      epoch,
      _route(locationId),
      query: _query(active: showInactive ? null : true),
    );
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
        .map(
          (item) => ArticleAssortmentDto.fromJson(item as Map<String, dynamic>),
        )
        .toList();
    if (loaded.any((item) => item.locationId != locationId)) {
      throw const FormatException();
    }
    items = [
      ...replace ? <ArticleAssortmentDto>[] : items ?? <ArticleAssortmentDto>[],
      ...loaded,
    ];
    final cursor = json['nextCursor'];
    nextCursor = cursor is String && cursor.isNotEmpty ? cursor : null;
    _notify();
  }

  /// Searches the company article master for globally active articles that can
  /// be added. Inactive articles are deliberately not offered.
  Future<List<ArticleDto>> searchArticles(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || !_current(_epoch)) return const [];
    final json = await _get(
      _epoch,
      '/articles',
      query: {'q': trimmed, 'active': 'true'},
    );
    final raw = json['items'];
    if (raw is! List) throw const FormatException();
    return raw
        .map((item) => ArticleDto.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> enable(ArticleDto article) => _run((epoch) async {
    conflict = false;
    final locationId = selectedLocationId;
    if (locationId == null) return;
    final input = ArticleAssortmentCreateInput(
      id: _uuid(),
      articleId: article.id,
    );
    Object? failure;
    try {
      await _post(epoch, _route(locationId), input.toJson());
    } catch (error) {
      failure = error;
    }
    _requireCurrent(epoch);
    ArticleAssortmentDto? reconciled;
    try {
      reconciled = ArticleAssortmentDto.fromJson(
        await _get(epoch, '${_route(locationId)}/${input.id}'),
      );
    } catch (_) {
      // The create did not commit or is not readable; keep the original error.
    }
    if (reconciled != null &&
        reconciled.id == input.id &&
        reconciled.article.id == input.articleId &&
        reconciled.locationId == locationId) {
      await _reload(epoch);
      notice = 'Artikel ist im Sortiment und wurde erneut geladen.';
      return;
    }
    if (failure is StoreApiException && failure.code == 'already_exists') {
      showInactive = true;
    }
    if (failure != null) throw failure;
    await _reload(epoch);
    notice = 'Artikel ist im Sortiment.';
  });

  Future<void> deactivate(ArticleAssortmentDto item) =>
      _lifecycle(item, false, 'Sortimenteintrag deaktiviert.');
  Future<void> reactivate(ArticleAssortmentDto item) =>
      _lifecycle(item, true, 'Sortimenteintrag reaktiviert.');

  Future<void> _lifecycle(
    ArticleAssortmentDto item,
    bool target,
    String success,
  ) => _run((epoch) async {
    conflict = false;
    final locationId = selectedLocationId;
    if (locationId == null) return;
    final expected = item.version;
    final action = target ? 'reactivate' : 'deactivate';
    Object? failure;
    try {
      await _post(epoch, '${_route(locationId)}/${item.id}/$action', {
        'expectedVersion': expected,
      });
    } catch (error) {
      failure = error;
    }
    _requireCurrent(epoch);
    if (failure != null) {
      // Exact lost-response reconciliation: only the current target state at
      // exactly the expected version (no-op) or exactly one version later
      // (one successful mutation) confirms this command. A later version is
      // ambiguous and must never be attributed to this request.
      ArticleAssortmentDto? current;
      try {
        current = ArticleAssortmentDto.fromJson(
          await _get(epoch, '${_route(locationId)}/${item.id}'),
        );
      } catch (_) {
        // Keep the original failure.
      }
      if (current != null && current.isActive == target) {
        final confirmedNoop = current.version == expected;
        final confirmedMutation =
            expected <= maxIncrementableJsonSafeInteger &&
            current.version == expected + 1;
        if (confirmedNoop || confirmedMutation) {
          await _reload(epoch);
          notice = success;
          return;
        }
        if (current.version > expected) {
          conflict = true;
          error =
              'Das Sortiment wurde inzwischen anderweitig geändert. Bitte den Serverstand neu laden.';
          return;
        }
      }
      throw failure;
    }
    await _reload(epoch);
    notice = success;
  });

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
