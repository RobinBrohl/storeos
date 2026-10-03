import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../config.dart';
import '../infrastructure/auth_store.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'article.dart';
import 'article_repository.dart';

/// Public inventory port for the company-wide article master. All calls
/// participate in the caller's authorized transaction.
class ArticleService {
  ArticleService(this.database)
    : _repository = ArticleRepository(database.schema, database.companyId);

  final PlatformDatabase database;
  final ArticleRepository _repository;

  Future<T> _run<T>(
    SessionPrincipal principal,
    Future<T> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(
        principal,
        'inventory.articles.manage',
        action,
      );
    } on ArticleStateConflict {
      throw const PlatformFailure(
        409,
        'article_conflict',
        'Article state changed.',
      );
    }
  }

  Future<ArticleDto> _get(TxSession tx, String id) async {
    final article = await _repository.find(tx, id);
    if (article == null) {
      throw const PlatformFailure(404, 'not_found', 'Article not found.');
    }
    return article;
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal principal, {
    String? after,
    String? q,
    String? active,
  }) {
    final cursor = after == null ? null : _cursor(after);
    final query = _search(q);
    final filter = _active(active);
    return _run(principal, (tx, actor) async {
      final rows = await _repository.page(
        tx,
        after: cursor,
        query: query,
        active: filter,
      );
      final items = rows.take(50).toList();
      return {
        'items': items.map((article) => article.toJson()).toList(),
        'nextCursor': rows.length > 50 ? items.last.id : null,
      };
    });
  }

  Future<Map<String, dynamic>> get(SessionPrincipal principal, String id) {
    id = requireUuid({'id': id}, 'id');
    return _run(principal, (tx, actor) async => (await _get(tx, id)).toJson());
  }

  Future<Map<String, dynamic>> create(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) {
    final parsed = _createInput(input);
    return _run(principal, (tx, actor) async {
      if (await _repository.idExists(tx, parsed.id) ||
          await _repository.skuKeyExists(tx, articleSkuKey(parsed.sku)) ||
          (parsed.barcode != null &&
              await _repository.barcodeExists(tx, parsed.barcode!))) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Article already exists.',
        );
      }
      await _mapUnique(() => _repository.insert(tx, parsed));
      final created = await _get(tx, parsed.id);
      await _audit(tx, actor, created, 'created');
      return created.toJson();
    });
  }

  Future<Map<String, dynamic>> edit(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    final parsed = _editInput(input);
    return _run(principal, (tx, actor) async {
      final current = Article(await _get(tx, id));
      current.requireVersion(parsed.expectedVersion);
      if (current.matches(parsed)) return current.view.toJson();
      if (await _repository.skuKeyExists(
            tx,
            articleSkuKey(parsed.sku),
            excludeId: current.view.id,
          ) ||
          (parsed.barcode != null &&
              await _repository.barcodeExists(
                tx,
                parsed.barcode!,
                excludeId: current.view.id,
              ))) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Article already exists.',
        );
      }
      final fields = current.changedFields(parsed);
      await _mapUnique(() => _repository.edit(tx, current, parsed));
      final updated = await _get(tx, id);
      await _audit(tx, actor, updated, 'updated', fields: fields);
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> deactivate(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) => _setActive(principal, id, input, false);

  Future<Map<String, dynamic>> reactivate(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) => _setActive(principal, id, input, true);

  Future<Map<String, dynamic>> _setActive(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
    bool active,
  ) {
    id = requireUuid({'id': id}, 'id');
    final parsed = _lifecycleInput(input);
    return _run(principal, (tx, actor) async {
      final current = Article(await _get(tx, id));
      current.requireVersion(parsed.expectedVersion);
      if (current.view.isActive == active) return current.view.toJson();
      await _mapUnique(() => _repository.setActive(tx, current, active));
      final updated = await _get(tx, id);
      await _audit(tx, actor, updated, active ? 'reactivated' : 'deactivated');
      return updated.toJson();
    });
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    ArticleDto article,
    String action, {
    List<String> fields = const [],
  }) => database.audit(
    tx,
    actor,
    'inventory.article.$action',
    'article',
    article.id,
    locationId: actor.locationId,
    changes: {
      'name': article.name,
      'sku': article.sku,
      if (article.barcode != null) 'barcode': article.barcode,
      'unit': article.unit,
      'isActive': article.isActive,
      'version': article.version,
      if (fields.isNotEmpty) 'changedFields': fields,
    },
  );

  /// Maps only the article uniqueness indexes to the friendly conflict;
  /// every other integrity failure keeps its normal behavior.
  Future<void> _mapUnique(Future<void> Function() action) async {
    try {
      await action();
    } on ServerException catch (error) {
      if (error.code == '23505' &&
          const {
            'articles_pkey',
            'articles_company_sku_key',
            'articles_company_barcode',
          }.contains(error.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Article already exists.',
        );
      }
      rethrow;
    }
  }

  String? _cursor(String after) {
    if (!isUuid(after)) {
      throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
    }
    return after.toLowerCase();
  }

  String? _search(String? q) {
    if (q == null) return null;
    final query = q.trim();
    if (query.isEmpty ||
        query.runes.length > articleSearchMaxLength ||
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

ArticleCreateInput _createInput(Map<String, dynamic> input) {
  try {
    return ArticleCreateInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_article', 'Invalid article.');
  }
}

ArticleEditInput _editInput(Map<String, dynamic> input) {
  try {
    return ArticleEditInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_article', 'Invalid article.');
  }
}

ArticleLifecycleInput _lifecycleInput(Map<String, dynamic> input) {
  try {
    return ArticleLifecycleInput.fromJson(input);
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_article', 'Invalid article.');
  }
}
