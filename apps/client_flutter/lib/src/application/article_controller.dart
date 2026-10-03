import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

/// Company-wide article master controller. The list defaults to active
/// articles only; "Auch inaktive anzeigen" omits the active filter so both
/// states are shown.
class ArticleController extends ChangeNotifier {
  ArticleController(this.session, this.platform, this.api) {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  List<ArticleDto>? articles;
  String? nextCursor, error, notice;
  String search = '';
  bool showInactive = false;
  bool busy = false, conflict = false;
  bool _disposed = false;
  int _epoch = 0;
  String? _userId;
  Completer<void>? _idle;

  Future<void> get whenIdle => _idle?.future ?? Future<void>.value();
  bool get canManage => platform.allows('inventory.articles.manage');
  bool get hasMore => nextCursor != null;

  void _sessionChanged() {
    if (_userId == session.user?.id) return;
    _userId = session.user?.id;
    _epoch++;
    articles = null;
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
    if (busy || !_current(_epoch) || !canManage) return;
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
        if (failure.code == 'article_conflict') {
          conflict = true;
          error =
              'Der Artikel wurde inzwischen geändert. Bitte den Serverstand neu laden.';
        } else if (failure.code == 'already_exists') {
          error = 'SKU oder Barcode ist bereits vergeben.';
        } else {
          error = failure.message;
        }
      }
    } catch (_) {
      if (_current(epoch)) {
        error =
            'Die Artikel konnten nicht bestätigt werden. Bitte erneut laden.';
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
    if (cursor == null) return;
    final json = await _get(
      epoch,
      '/articles',
      after: cursor,
      query: _query(active: showInactive ? null : true),
    );
    _appendPage(epoch, json);
  });

  Future<void> _reload(int epoch) async {
    _requireCurrent(epoch);
    articles = null;
    nextCursor = null;
    _notify();
    final json = await _get(
      epoch,
      '/articles',
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
    final rawItems = json['items'];
    if (rawItems is! List) throw const FormatException();
    final loaded = rawItems
        .map((item) => ArticleDto.fromJson(item as Map<String, dynamic>))
        .toList();
    if (loaded.any((item) => item.companyId != session.user?.companyId)) {
      throw const FormatException();
    }
    articles = [
      ...replace ? <ArticleDto>[] : articles ?? <ArticleDto>[],
      ...loaded,
    ];
    final cursor = json['nextCursor'];
    nextCursor = cursor is String && cursor.isNotEmpty ? cursor : null;
    _notify();
  }

  Future<void> create(ArticleCreateInput draft) => _run((epoch) async {
    conflict = false;
    final input = ArticleCreateInput(
      id: _uuid(),
      sku: draft.sku,
      barcode: draft.barcode,
      name: draft.name,
      description: draft.description,
      unit: draft.unit,
    );
    Object? failure;
    try {
      await _post(epoch, '/articles', input.toJson());
    } catch (error) {
      failure = error;
    }
    _requireCurrent(epoch);
    ArticleDto? reconciled;
    try {
      reconciled = ArticleDto.fromJson(
        await _get(epoch, '/articles/${input.id}'),
      );
    } catch (_) {
      // The create did not commit or is not readable; keep the original error.
    }
    if (reconciled != null &&
        reconciled.sku == input.sku &&
        reconciled.name == input.name &&
        reconciled.unit == input.unit) {
      await _reload(epoch);
      notice = 'Artikel gespeichert und erneut geladen.';
      return;
    }
    if (failure != null) throw failure;
    await _reload(epoch);
    notice = 'Artikel gespeichert.';
  });

  Future<void> edit(ArticleDto article, ArticleEditInput draft) =>
      _run((epoch) async {
        conflict = false;
        await _post(epoch, '/articles/${article.id}/edit', {
          ...draft.toJson(),
          'expectedVersion': article.version,
        });
        await _reload(epoch);
        notice = 'Artikel gespeichert und erneut geladen.';
      });

  Future<void> deactivate(ArticleDto article) =>
      _lifecycle(article, 'deactivate', 'Artikel deaktiviert.');
  Future<void> reactivate(ArticleDto article) =>
      _lifecycle(article, 'reactivate', 'Artikel reaktiviert.');

  Future<void> _lifecycle(ArticleDto article, String action, String success) =>
      _run((epoch) async {
        conflict = false;
        await _post(epoch, '/articles/${article.id}/$action', {
          'expectedVersion': article.version,
        });
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
