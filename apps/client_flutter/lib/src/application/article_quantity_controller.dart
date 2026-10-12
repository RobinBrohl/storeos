import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'session_controller.dart';

String newQuantityId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final text = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${text.substring(0, 8)}-${text.substring(8, 12)}-${text.substring(12, 16)}-${text.substring(16, 20)}-${text.substring(20)}';
}

/// One dialog/resource context. Pending commands cannot be edited or discarded
/// by another request; session/Location replacement clears the local context.
class ArticleQuantityController extends ChangeNotifier {
  ArticleQuantityController(
    this.session,
    this.api, {
    required this.articleId,
    this.levelId,
    this.locationId,
    this.locationCurrent,
    String Function()? idFactory,
  }) : _newId = idFactory ?? newQuantityId,
       _identity = session.sessionIdentity {
    session.addListener(_sessionChanged);
  }
  final SessionController session;
  final PlatformApi api;
  final String articleId;
  final String? levelId, locationId;
  final bool Function()? locationCurrent;
  final String Function() _newId;
  final Object? _identity;
  bool _disposed = false;
  bool busy = false, decisionRequired = false;
  String? error, notice, refreshError;
  ArticleQuantityProfileDto? profile;
  StockQuantityBindingDto? binding;
  StockLevelDto? level;
  StockConversionPreviewDto? review;
  Map<String, dynamic>? pending, result;
  String? pendingKind;
  bool _pendingUncertain = false;
  List<ArticleQuantityProfileDto> revisions = [];
  List<Map<String, dynamic>> evidence = [];
  String? historyCursor, evidenceCursor;
  bool get live =>
      !_disposed &&
      session.isAuthenticated &&
      identical(_identity, session.sessionIdentity) &&
      (locationCurrent?.call() ?? true);
  bool get stock => levelId != null;
  String get route => stock
      ? '/locations/$locationId/stock/$levelId/quantity'
      : '/articles/$articleId/quantity';
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (live) return;
    profile = null;
    binding = null;
    level = null;
    review = null;
    pending = null;
    pendingKind = null;
    _pendingUncertain = false;
    result = null;
    revisions = [];
    evidence = [];
    historyCursor = evidenceCursor = null;
    busy = false;
    decisionRequired = false;
    error = refreshError = notice = null;
    _notify();
  }

  void invalidateLocation() => _sessionChanged();
  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    if (!live) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    final value = await session.authorized(
      (token) => api.get(token, path, query: query),
    );
    if (!live) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    return value;
  }

  Future<void> _reload() async {
    final value = await _get(route);
    quantityKeys(value, stock ? {'profile', 'binding'} : {'profile'});
    final parsedProfile = value['profile'] == null
        ? null
        : ArticleQuantityProfileDto.fromJson(quantityObject(value['profile']));
    if (parsedProfile != null && parsedProfile.articleId != articleId) {
      throw const FormatException('Unexpected Article quantity scope.');
    }
    StockQuantityBindingDto? parsedBinding;
    StockLevelDto? parsedLevel;
    if (stock) {
      parsedBinding = value['binding'] == null
          ? null
          : StockQuantityBindingDto.fromJson(quantityObject(value['binding']));
      parsedLevel = StockLevelDto.fromJson(
        await _get('/locations/$locationId/stock/$levelId'),
      );
      if (parsedLevel.id != levelId ||
          parsedLevel.locationId != locationId ||
          parsedLevel.articleId != articleId ||
          (parsedBinding != null &&
              (parsedBinding.levelId != levelId ||
                  parsedBinding.profileId != parsedProfile?.id))) {
        throw const FormatException('Unexpected Stock quantity scope.');
      }
    }
    profile = parsedProfile;
    binding = parsedBinding;
    level = parsedLevel;
  }

  Future<void> load() async {
    if (!live || busy || pending != null) return;
    busy = true;
    error = refreshError = notice = null;
    review = null;
    result = null;
    profile = null;
    binding = null;
    level = null;
    revisions = [];
    evidence = [];
    historyCursor = evidenceCursor = null;
    _notify();
    try {
      await _reload();
      if (live) decisionRequired = false;
    } catch (e) {
      if (live) {
        error = e is StoreApiException
            ? e.message
            : 'Der Serverstand konnte nicht geladen werden.';
      }
    } finally {
      if (live) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> preview(String unit, String quantity) async {
    if (!live ||
        busy ||
        pending != null ||
        decisionRequired ||
        result != null ||
        level == null ||
        profile == null) {
      return;
    }
    late Map<String, dynamic> body;
    try {
      body = stockQuantityCommand('preview', {
        'profileVersion': profile!.version,
        'stockVersion': level!.version,
        'inputUnit': unit,
        'inputQuantity': quantity.trim().replaceAll(',', '.'),
      });
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return;
    }
    busy = true;
    error = notice = null;
    review = null;
    _notify();
    try {
      final value = await session.authorized(
        (token) => api.post(token, '$route/preview', body),
      );
      if (!live) return;
      final parsed = StockConversionPreviewDto.fromJson(value);
      if (parsed.levelId != levelId ||
          parsed.profileVersion != profile!.version ||
          parsed.stockVersion != level!.version ||
          parsed.inputUnit != body['inputUnit'] ||
          parsed.inputQuantity != body['inputQuantity'] ||
          parsed.bindingId != binding?.id) {
        throw const FormatException('Unexpected conversion preview.');
      }
      review = parsed;
    } catch (e) {
      if (live) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : 'Die Umrechnung konnte nicht bestätigt werden.';
        review = null;
      }
    } finally {
      if (live) {
        busy = false;
        _notify();
      }
    }
  }

  void editReview() {
    if (live && !busy && pending == null && result == null) {
      review = null;
      error = null;
      _notify();
    }
  }

  Future<void> command(String kind, Map<String, dynamic> input) async {
    if (!live ||
        busy ||
        pending != null ||
        decisionRequired ||
        result != null) {
      return;
    }
    try {
      pending = stock
          ? stockQuantityCommand(kind, {'operationId': _newId(), ...input})
          : articleQuantityCommand(kind, {'operationId': _newId(), ...input});
      pendingKind = kind;
      _pendingUncertain = false;
    } on FormatException catch (e) {
      error = e.message;
      _notify();
      return;
    }
    await retry();
  }

  Future<void> correct(String reason) async {
    if (review == null) return;
    await command('correct', {'review': review!.toJson(), 'reason': reason});
  }

  Future<void> retry() async {
    if (!live || busy || pending == null || pendingKind == null) return;
    final body = pending!;
    final kind = pendingKind!;
    busy = true;
    error = notice = refreshError = null;
    _notify();
    try {
      final value = await session.authorized(
        (token) => api.post(token, '$route/$kind', body),
      );
      if (!live) return;
      if (kind == 'correct') {
        stockQuantityEvidence(value);
        quantityKeys(value, {
          'operationId',
          'review',
          'reason',
          'recordedBy',
          'recordedAt',
          'movementId',
          'balanceVersion',
        });
        final parsed = StockConversionPreviewDto.fromJson(
          quantityObject(value['review']),
        );
        if (value['operationId'] != body['operationId'] ||
            value['reason'] != body['reason'] ||
            value['recordedBy'] != session.user?.id ||
            jsonEncode(parsed.toJson()) != jsonEncode(body['review']) ||
            value['balanceVersion'] !=
                parsed.stockVersion + (parsed.delta == '0' ? 0 : 1) ||
            value['movementId'] !=
                (parsed.delta == '0' ? null : body['operationId'])) {
          throw const FormatException('Unexpected correction receipt.');
        }
      } else if (kind == 'bind') {
        final parsed = StockQuantityBindingDto.fromJson(value);
        if (parsed.id != body['operationId'] ||
            parsed.levelId != levelId ||
            parsed.profileId != body['profileId'] ||
            parsed.profileVersion != body['profileVersion'] ||
            parsed.stockVersion != body['stockVersion'] ||
            parsed.unit != body['unit'] ||
            parsed.reason != body['reason'] ||
            parsed.recordedBy != session.user?.id) {
          throw const FormatException('Unexpected binding receipt.');
        }
      } else {
        final parsed = ArticleQuantityProfileDto.fromJson(value);
        if (parsed.articleId != articleId ||
            parsed.recordedBy != session.user?.id ||
            parsed.reason != body['reason'] ||
            parsed.version !=
                (kind == 'configure'
                    ? 1
                    : (body['expectedVersion'] as int) + 1) ||
            parsed.id !=
                (kind == 'configure' ? body['profileId'] : profile?.id) ||
            parsed.status != (kind == 'suspend' ? 'suspended' : 'active') ||
            (kind != 'suspend' &&
                jsonEncode(parsed.packages.map((p) => p.toJson()).toList()) !=
                    jsonEncode(body['packages']))) {
          throw const FormatException('Unexpected profile receipt.');
        }
      }
      result = kind == 'correct'
          ? stockQuantityEvidence(value)
          : Map.unmodifiable(value);
      pending = null;
      pendingKind = null;
      _pendingUncertain = false;
      review = null;
      notice = 'Gespeichert und bestätigt. Operation ${body['operationId']}.';
      try {
        await _reload();
      } catch (_) {
        if (live) {
          refreshError =
              'Gespeichert. Der aktuelle Serverstand konnte noch nicht geladen werden.';
        }
      }
    } catch (e) {
      if (!live) return;
      if (e is StoreApiException &&
          {
            400,
            401,
            403,
            404,
            405,
            409,
            413,
            415,
            422,
          }.contains(e.statusCode)) {
        // A rejection settles only this attempt. An earlier lost response may
        // already have committed; retain its exact command until confirmed or
        // the genuine session/Location context is replaced.
        if (_pendingUncertain) {
          error =
              '${e.code}: ${e.message} Das frühere Ergebnis bleibt '
              'unbestätigt. Nach wiederhergestelltem Zugriff nur dieselbe '
              'Operation unverändert erneut senden.';
          return;
        }
        pending = null;
        pendingKind = null;
        review = null;
        decisionRequired = true;
        error =
            '${e.code}: ${e.message} Serverstand laden und neu entscheiden.';
      } else {
        _pendingUncertain = true;
        error =
            'Ergebnis unbestätigt. Nur dieselbe Operation unverändert erneut senden.';
      }
    } finally {
      if (live) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> history({bool more = false}) async {
    if (!live || busy || pending != null) return;
    busy = true;
    error = null;
    _notify();
    try {
      final value = await _get(
        '$route/${stock ? 'evidence' : 'history'}',
        query: more
            ? {
                stock ? 'after' : 'before': (stock
                    ? evidenceCursor
                    : historyCursor)!,
              }
            : null,
      );
      final items = value['items'] as List;
      if (stock) {
        evidence = [
          if (more) ...evidence,
          ...items.map((v) => stockQuantityEvidence(quantityObject(v))),
        ];
        evidenceCursor = value['nextCursor'] as String?;
      } else {
        revisions = [
          if (more) ...revisions,
          ...items.map(
            (v) => ArticleQuantityProfileDto.fromJson(quantityObject(v)),
          ),
        ];
        historyCursor = value['nextCursor'] as String?;
      }
    } catch (_) {
      if (live) error = 'Nachweise konnten nicht geladen werden.';
    } finally {
      if (live) {
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
