import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../config.dart';
import '../infrastructure/auth_store.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'article_assortment.dart';
import 'article_assortment_repository.dart';
import 'article_repository.dart';

/// Public inventory port for location assortment. Membership state and article
/// state stay independent: a new or reactivated membership requires an active
/// company article, while article deactivation never mutates existing rows.
class ArticleAssortmentService {
  ArticleAssortmentService(this.database)
    : _organization = OrganizationService(database),
      _articles = ArticleRepository(database.schema, database.companyId);

  final PlatformDatabase database;
  final OrganizationService _organization;
  final ArticleRepository _articles;

  ArticleAssortmentRepository _repository(String locationId) =>
      ArticleAssortmentRepository(
        database.schema,
        database.companyId,
        locationId,
      );

  Future<T> _run<T>(
    SessionPrincipal principal,
    Future<T> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(
        principal,
        'inventory.assortment.manage',
        action,
      );
    } on ArticleAssortmentStateConflict {
      throw const PlatformFailure(
        409,
        'assortment_conflict',
        'Assortment state changed.',
      );
    }
  }

  Future<ArticleAssortmentDto> _get(
    TxSession tx,
    ArticleAssortmentRepository repository,
    String id,
  ) async {
    final association = await repository.find(tx, id);
    if (association == null) {
      throw const PlatformFailure(404, 'not_found', 'Assortment not found.');
    }
    return association;
  }

  /// Requires a company article that is currently globally active.
  Future<ArticleDto> _activeArticle(TxSession tx, String articleId) async {
    final article = await _articles.find(tx, articleId);
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
    return article;
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal principal,
    String locationId, {
    String? after,
    String? q,
    String? active,
  }) {
    final location = _location(locationId);
    final cursor = _cursor(after);
    final query = _search(q);
    final filter = _active(active);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      final rows = await repository.page(
        tx,
        after: cursor,
        query: query,
        active: filter,
      );
      final items = rows.take(50).toList();
      return {
        'items': items.map((item) => item.toJson()).toList(),
        'nextCursor': rows.length > 50 ? items.last.id : null,
      };
    });
  }

  Future<Map<String, dynamic>> get(
    SessionPrincipal principal,
    String locationId,
    String id,
  ) {
    final location = _location(locationId);
    id = requireUuid({'id': id}, 'id');
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      return (await _get(tx, repository, id)).toJson();
    });
  }

  Future<Map<String, dynamic>> create(
    SessionPrincipal principal,
    String locationId,
    Map<String, dynamic> input,
  ) {
    final location = _location(locationId);
    final parsed = _createInput(input);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      await _activeArticle(tx, parsed.articleId);
      if (await repository.idExists(tx, parsed.id) ||
          await repository.pairExists(tx, parsed.articleId)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Assortment already exists.',
        );
      }
      await _mapUnique(() => repository.insert(tx, parsed));
      final created = await _get(tx, repository, parsed.id);
      await _audit(tx, actor, location, created, 'created');
      return created.toJson();
    });
  }

  Future<Map<String, dynamic>> deactivate(
    SessionPrincipal principal,
    String locationId,
    String id,
    Map<String, dynamic> input,
  ) => _setActive(principal, locationId, id, input, false);

  Future<Map<String, dynamic>> reactivate(
    SessionPrincipal principal,
    String locationId,
    String id,
    Map<String, dynamic> input,
  ) => _setActive(principal, locationId, id, input, true);

  Future<Map<String, dynamic>> _setActive(
    SessionPrincipal principal,
    String locationId,
    String id,
    Map<String, dynamic> input,
    bool active,
  ) {
    final location = _location(locationId);
    id = requireUuid({'id': id}, 'id');
    final parsed = _lifecycleInput(input);
    final repository = _repository(location);
    return _run(principal, (tx, actor) async {
      await _organization.requireConfiguredLocation(tx, location);
      final current = ArticleAssortment(await _get(tx, repository, id));
      // A stale request is never a no-op: version validation happens before
      // the target-state check.
      current.requireVersion(parsed.expectedVersion);
      if (current.view.isActive == active) return current.view.toJson();
      if (active) {
        await _activeArticle(tx, current.view.article.id);
      }
      await _mapUnique(() => repository.setActive(tx, current, active));
      final updated = await _get(tx, repository, id);
      await _audit(
        tx,
        actor,
        location,
        updated,
        active ? 'reactivated' : 'deactivated',
      );
      return updated.toJson();
    });
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    String locationId,
    ArticleAssortmentDto association,
    String action,
  ) => database.audit(
    tx,
    actor,
    'inventory.assortment.$action',
    'assortment',
    association.id,
    locationId: locationId,
    changes: {
      'articleId': association.article.id,
      'isActive': association.isActive,
      'version': association.version,
    },
  );

  /// Maps only the assortment uniqueness indexes to the friendly conflict;
  /// every other integrity failure keeps its normal behavior.
  Future<void> _mapUnique(Future<void> Function() action) async {
    try {
      await action();
    } on ServerException catch (error) {
      if (error.code == '23505' &&
          const {
            'article_location_assortment_pkey',
            'article_location_assortment_pair_unique',
          }.contains(error.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Assortment already exists.',
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

  String? _search(String? q) {
    if (q == null) return null;
    final query = q.trim();
    if (query.isEmpty ||
        query.runes.length > articleAssortmentSearchMaxLength ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(query)) {
      throw const PlatformFailure(400, 'invalid_request', 'Invalid search.');
    }
    return query;
  }

  bool? _active(String? active) => switch (active) {
    null => null,
    'true' => true,
    'false' => false,
    _ => throw const PlatformFailure(
      400,
      'invalid_request',
      'Invalid active filter.',
    ),
  };
}

ArticleAssortmentCreateInput _createInput(Map<String, dynamic> input) {
  try {
    return ArticleAssortmentCreateInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(
      400,
      'invalid_assortment',
      'Invalid assortment.',
    );
  }
}

ArticleAssortmentLifecycleInput _lifecycleInput(Map<String, dynamic> input) {
  try {
    return ArticleAssortmentLifecycleInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(
      400,
      'invalid_assortment',
      'Invalid assortment.',
    );
  }
}
