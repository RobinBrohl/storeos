import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../config.dart';
import '../infrastructure/auth_store.dart';
import '../inventory/inventory_article_port.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'stock.dart';
import 'stock_repository.dart';

/// Public stock port. The movement ledger is authoritative business evidence;
/// the stock level is the transactionally maintained projection. All calls
/// participate in the caller's authorized company transaction.
class StockService {
  StockService(this.database)
    : _organization = OrganizationService(database),
      _articles = InventoryArticlePort(database.schema, database.companyId);

  final PlatformDatabase database;
  final OrganizationService _organization;
  final InventoryArticlePort _articles;

  StockRepository _repository(String locationId) =>
      StockRepository(database.schema, database.companyId, locationId);

  Future<T> _run<T>(
    SessionPrincipal principal,
    Future<T> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(
        principal,
        'stock.levels.manage',
        action,
      );
    } on StockStateConflict {
      throw const PlatformFailure(
        409,
        'stock_conflict',
        'Stock state changed.',
      );
    }
  }

  Future<StockLevelDto> _get(
    TxSession tx,
    StockRepository repository,
    String id,
  ) async {
    final level = await repository.find(tx, id);
    if (level == null) {
      throw const PlatformFailure(404, 'not_found', 'Stock level not found.');
    }
    return level;
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal principal,
    String locationId, {
    String? after,
    String? q,
  }) {
    final location = _location(locationId);
    final cursor = _cursor(after);
    final query = _search(q);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      final rows = await repository.page(tx, after: cursor, query: query);
      final items = rows.take(50).toList();
      return {
        'items': items.map((level) => level.toJson()).toList(),
        'nextCursor': rows.length > 50 ? items.last.id : null,
      };
    });
  }

  Future<Map<String, dynamic>> get(
    SessionPrincipal principal,
    String locationId,
    String levelId,
  ) {
    final location = _location(locationId);
    levelId = requireUuid({'levelId': levelId}, 'levelId');
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      return (await _get(tx, repository, levelId)).toJson();
    });
  }

  Future<Map<String, dynamic>> open(
    SessionPrincipal principal,
    String locationId,
    Map<String, dynamic> input,
  ) {
    final location = _location(locationId);
    final parsed = _openInput(input);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      final article = await _articles.findArticle(tx, parsed.articleId);
      if (article == null) {
        throw const PlatformFailure(404, 'not_found', 'Article not found.');
      }
      if (!article.isActive) {
        throw const PlatformFailure(
          409,
          'article_inactive',
          'Article is inactive.',
        );
      }
      final assortmentActive = await repository.assortmentActive(
        tx,
        parsed.articleId,
      );
      if (assortmentActive != true) {
        throw const PlatformFailure(
          409,
          'not_in_assortment',
          'Article has no active assortment membership at this location.',
        );
      }
      if (await repository.idExists(tx, parsed.id) ||
          await repository.pairExists(tx, parsed.articleId)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Stock level already exists.',
        );
      }
      final quantityScaled = stockQuantity(parsed.quantity);
      final movementId = newUuid();
      await _mapUnique(
        () => repository.insertLevel(
          tx,
          id: parsed.id,
          articleId: parsed.articleId,
          stockUnit: article.unit,
          quantityScaled: quantityScaled,
        ),
      );
      await repository.insertMovement(
        tx,
        id: movementId,
        stockLevelId: parsed.id,
        articleId: parsed.articleId,
        kind: 'opening',
        deltaScaled: quantityScaled,
        balanceAfterScaled: quantityScaled,
        balanceVersion: 1,
        recordedBy: actor.id,
        note: parsed.note,
      );
      final created = await _get(tx, repository, parsed.id);
      await database.audit(
        tx,
        actor,
        'stock.level.opened',
        'stock_level',
        created.id,
        locationId: location,
        changes: {
          'articleId': parsed.articleId,
          'movementId': movementId,
          'version': created.version,
        },
      );
      return created.toJson();
    });
  }

  Future<Map<String, dynamic>> adjust(
    SessionPrincipal principal,
    String locationId,
    String levelId,
    Map<String, dynamic> input,
  ) {
    final location = _location(locationId);
    levelId = requireUuid({'levelId': levelId}, 'levelId');
    final parsed = _adjustInput(input);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      // Operation identity is checked before any stale-version handling so an
      // exact retry after later writes still replays instead of conflicting.
      final existing = await repository.findMovement(tx, parsed.movementId);
      if (existing != null) {
        final exactReplay =
            existing.stockLevelId == levelId &&
            existing.companyId == database.companyId &&
            existing.locationId == location &&
            existing.recordedBy == actor.id &&
            existing.kind == 'adjustment' &&
            existing.balanceVersion == parsed.expectedVersion + 1 &&
            existing.balanceAfterScaled == stockQuantity(parsed.quantity) &&
            existing.note == parsed.note;
        if (!exactReplay) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Operation ID is already bound to another command.',
          );
        }
        return (await _get(tx, repository, levelId)).toJson();
      }
      final current = StockLevel(await _get(tx, repository, levelId));
      current.requireVersion(parsed.expectedVersion);
      final quantityScaled = stockQuantity(parsed.quantity);
      if (current.quantityScaled == quantityScaled) {
        return current.view.toJson();
      }
      final deltaScaled = quantityScaled - current.quantityScaled;
      await repository.updateQuantity(
        tx,
        id: levelId,
        expectedVersion: parsed.expectedVersion,
        quantityScaled: quantityScaled,
      );
      await repository.insertMovement(
        tx,
        id: parsed.movementId,
        stockLevelId: levelId,
        articleId: current.view.articleId,
        kind: 'adjustment',
        deltaScaled: deltaScaled,
        balanceAfterScaled: quantityScaled,
        balanceVersion: parsed.expectedVersion + 1,
        recordedBy: actor.id,
        note: parsed.note,
      );
      final updated = await _get(tx, repository, levelId);
      await database.audit(
        tx,
        actor,
        'stock.level.adjusted',
        'stock_level',
        updated.id,
        locationId: location,
        changes: {
          'articleId': updated.articleId,
          'movementId': parsed.movementId,
          'oldVersion': current.view.version,
          'version': updated.version,
          'changedFields': const ['quantity'],
        },
      );
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> listMovements(
    SessionPrincipal principal,
    String locationId,
    String levelId, {
    String? after,
  }) {
    final location = _location(locationId);
    levelId = requireUuid({'levelId': levelId}, 'levelId');
    final before = _movementCursor(after);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      await _get(tx, repository, levelId);
      final rows = await repository.movements(
        tx,
        stockLevelId: levelId,
        beforeVersion: before,
      );
      final items = rows.take(50).toList();
      return {
        'items': items.map((movement) => movement.toJson()).toList(),
        'nextCursor': rows.length > 50
            ? items.last.balanceVersion.toString()
            : null,
      };
    });
  }

  /// Maps only the stock level uniqueness indexes to the friendly conflict;
  /// every other integrity failure keeps its normal behavior.
  Future<void> _mapUnique(Future<void> Function() action) async {
    try {
      await action();
    } on ServerException catch (error) {
      if (error.code == '23505' &&
          const {
            'stock_levels_pkey',
            'stock_levels_scope_unique',
          }.contains(error.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Stock level already exists.',
        );
      }
      rethrow;
    }
  }

  String _location(String locationId) =>
      requireUuid({'locationId': locationId}, 'locationId');

  String? _cursor(String? after) {
    if (after == null) return null;
    if (!isUuid(after)) {
      throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
    }
    return after.toLowerCase();
  }

  int? _movementCursor(String? after) {
    if (after == null) return null;
    final value = int.tryParse(after);
    if (value == null || value < 1) {
      throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
    }
    return value;
  }

  String? _search(String? q) {
    if (q == null) return null;
    final query = q.trim();
    if (query.isEmpty ||
        query.runes.length > stockSearchMaxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query)) {
      throw const PlatformFailure(400, 'invalid_request', 'Invalid search.');
    }
    return query;
  }
}

StockOpenInput _openInput(Map<String, dynamic> input) {
  try {
    return StockOpenInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_stock', 'Invalid stock level.');
  }
}

StockAdjustInput _adjustInput(Map<String, dynamic> input) {
  try {
    return StockAdjustInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(
      400,
      'invalid_stock',
      'Invalid stock adjustment.',
    );
  }
}
