import 'dart:convert';
import '../inventory/recipe_article_port.dart';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../platform/platform_database.dart';
import '../http/json_logger.dart';
import 'recipe_repository.dart';
import 'recipe.dart';

class RecipeService {
  RecipeService(this.database)
    : repository = RecipeRepository(database.schema, database.companyId),
      articles = RecipeArticlePort(database.schema, database.companyId);
  final PlatformDatabase database;
  final RecipeRepository repository;
  final RecipeArticlePort articles;

  Future<Map<String, dynamic>> _run(
    SessionPrincipal p,
    String capability,
    Future<Map<String, dynamic>> Function(TxSession, PlatformActor) work,
  ) async {
    try {
      return await database.runAuthorized(
        p,
        'production.recipes.$capability',
        work,
      );
    } on RecipeInputException catch (e) {
      throw PlatformFailure(
        e.code == 'recipe_not_publishable' ? 422 : 400,
        e.code,
        e.message,
      );
    } on ServerException catch (e) {
      const JsonLogger().event(
        'recipe_database_error',
        level: 'error',
        fields: {'sqlState': e.code, 'constraint': e.constraintName},
      );
      if (e.code == '23505' &&
          const {
            'production_recipes_pkey',
            'recipe_produced_unique',
            'production_recipe_revisions_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Identity exists; reload and review.',
        );
      }
      if (e.code == '23505' && e.constraintName == 'recipe_one_draft') {
        throw const PlatformFailure(
          409,
          'draft_exists',
          'Recipe already has a draft.',
        );
      }
      if (e.code == '23505' &&
          e.constraintName == 'recipe_publication_operation_unique') {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Publication identity conflicts.',
        );
      }
      if (e.code == '23505' &&
          e.constraintName == 'recipe_revision_number_unique') {
        throw const PlatformFailure(
          409,
          'revision_conflict',
          'Revision allocation changed.',
        );
      }
      // Contain the global broad constraint mapping: defects remain server errors.
      if (e.code?.startsWith('08') == true ||
          const {
            '42501',
            '55P03',
            '57014',
            '57P01',
            '53300',
          }.contains(e.code)) {
        throw const PlatformFailure(
          503,
          'database_unavailable',
          'Recipe database unavailable.',
        );
      }
      throw const PlatformFailure(
        500,
        'internal_error',
        'Recipe integrity failure.',
      );
    }
  }

  Future<RecipeDto> _article(TxSession tx, String id) async =>
      await repository.article(tx, recipeId(id)) ??
      (throw const PlatformFailure(404, 'not_found', 'Recipe not found.'));
  Future<RecipeRevisionDto> _revision(
    TxSession tx,
    String article,
    String revision,
  ) async =>
      await repository.revision(tx, recipeId(article), recipeId(revision)) ??
      (throw const PlatformFailure(404, 'not_found', 'Revision not found.'));
  Future<Map<String, dynamic>> _detail(TxSession tx, RecipeDto a) async {
    final draft = a.activeDraftRevisionId == null
        ? null
        : await _revision(tx, a.id, a.activeDraftRevisionId!);
    final published = a.currentPublishedRevisionId == null
        ? null
        : await _revision(tx, a.id, a.currentPublishedRevisionId!);
    final context = await articles.read(tx, {
      a.producedArticleId,
      ...?draft?.content.ingredients.map((i) => i.article.id),
      ...?published?.content.ingredients.map((i) => i.article.id),
    });
    return {
      'recipe': a.toJson(),
      'draft': draft?.toJson(),
      'currentPublished': published?.toJson(),
      'currentProduced': context
          .singleWhere((i) => i.article.id == a.producedArticleId)
          .toJson(),
      'currentIngredients': context
          .where((i) => i.article.id != a.producedArticleId)
          .map((i) => i.toJson())
          .toList(),
    };
  }

  Future<Map<String, dynamic>> _result(
    TxSession tx,
    String a,
    String r,
  ) async => {
    'detail': await _detail(tx, await _article(tx, a)),
    'revision': (await _revision(tx, a, r)).toJson(),
  };
  Future<Map<String, dynamic>> _published(TxSession tx, RecipeDto a) async {
    final r = await _revision(tx, a.id, a.currentPublishedRevisionId!);
    final context = await articles.read(tx, {
      a.producedArticleId,
      ...r.content.ingredients.map((i) => i.article.id),
    });
    return {
      'recipeId': a.id,
      'revisionId': r.id,
      'revisionNumber': r.revisionNumber,
      'publishedAt': r.publishedAt,
      'content': r.content.toJson(),
      'currentProduced': context
          .singleWhere((i) => i.article.id == a.producedArticleId)
          .toJson(),
      'currentIngredients': context
          .where((i) => i.article.id != a.producedArticleId)
          .map((i) => i.toJson())
          .toList(),
    };
  }

  Future<RecipeArticleContext> _activeArticle(TxSession tx, String id) async {
    final found = await articles.read(tx, {id});
    if (found.isEmpty || !found.single.isActive) {
      throw const PlatformFailure(
        422,
        'article_unavailable',
        'Active Company Article required.',
      );
    }
    return found.single;
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    String action,
    RecipeDto a, {
    RecipeRevisionDto? revision,
    List<String> fields = const [],
    String? operation,
  }) => database.audit(
    tx,
    actor,
    'production.recipe.$action',
    'recipe',
    a.id,
    changes: {
      'recipeId': a.id,
      'producedArticleId': a.producedArticleId,
      if (revision != null) 'revisionId': revision.id,
      if (revision != null) 'revisionNumber': revision.revisionNumber,
      'expectedVersion': a.version,
      'appliedVersion': a.version + 1,
      'fromStatus': a.status,
      'toStatus': action == 'retired' ? 'retired' : a.status,
      if (revision != null) 'fromRevisionStatus': revision.status,
      if (revision != null)
        'toRevisionStatus': switch (action) {
          'revision.published' => 'published',
          'draft.discarded' || 'retired' => 'discarded',
          _ => revision.status,
        },
      if (fields.isNotEmpty) 'changedFields': fields,
      'operationId': ?operation,
    },
  );

  Future<Map<String, dynamic>> listPublished(
    SessionPrincipal p, {
    String q = '',
    String? after,
  }) => _run(p, 'read', (tx, actor) async {
    _query(q);
    final rows = await repository.visible(
      tx,
      q: q,
      after: _cursor(after, 'published', q),
    );
    return {
      'items': [for (final a in rows.take(50)) await _published(tx, a)],
      'nextCursor': rows.length > 50
          ? _encode('published', q, rows[49].id)
          : null,
    };
  });
  Future<Map<String, dynamic>> readPublished(SessionPrincipal p, String id) =>
      _run(p, 'read', (tx, actor) async {
        final rows = await repository.visible(tx, id: recipeId(id));
        if (rows.isEmpty) {
          throw const PlatformFailure(
            404,
            'not_found',
            'Approved Recipe unavailable.',
          );
        }
        return _published(tx, rows.single);
      });
  Future<Map<String, dynamic>> candidates(
    SessionPrincipal p, {
    String q = '',
    String? after,
    String? id,
  }) => _run(p, 'manage', (tx, actor) async {
    _query(q);
    if (id != null) {
      recipeId(id);
      if (after != null || q.isNotEmpty) {
        throw const PlatformFailure(
          400,
          'invalid_input',
          'Exact Article selection cannot use search or cursor.',
        );
      }
      final selected = await articles.read(tx, {id});
      return {
        'items': selected
            .where((i) => i.isActive)
            .map((i) => i.toJson())
            .toList(),
        'nextCursor': null,
      };
    }
    final rows = await articles.candidates(
      tx,
      q,
      _cursor(after, 'candidates', q),
    );
    return {
      'items': rows.take(50).map((i) => i.toJson()).toList(),
      'nextCursor': rows.length > 50
          ? _encode('candidates', q, rows[49].article.id)
          : null,
    };
  });
  Future<Map<String, dynamic>> listManaged(
    SessionPrincipal p, {
    String? after,
  }) => _run(p, 'manage', (tx, actor) async {
    final rows = await repository.articles(tx, _cursor(after, 'managed', ''));
    return {
      'items': [for (final a in rows.take(50)) await _detail(tx, a)],
      'nextCursor': rows.length > 50
          ? _encode('managed', '', rows[49].id)
          : null,
    };
  });
  Future<Map<String, dynamic>> detail(SessionPrincipal p, String id) => _run(
    p,
    'manage',
    (tx, actor) async => _detail(tx, await _article(tx, id)),
  );
  Future<Map<String, dynamic>> history(
    SessionPrincipal p,
    String id, {
    String? after,
  }) => _run(p, 'manage', (tx, actor) async {
    final a = await _article(tx, id);
    final raw = _cursor(after, 'history:${a.id}', '', history: true);
    final before = raw == null ? null : int.parse(raw);
    final rows = await repository.history(tx, a.id, before);
    return {
      'items': rows.take(50).map((r) => r.toJson()).toList(),
      'nextCursor': rows.length > 50
          ? _encode('history:${a.id}', '', rows[49].revisionNumber.toString())
          : null,
    };
  });
  Future<Map<String, dynamic>> revision(
    SessionPrincipal p,
    String id,
    String revisionId,
  ) => _run(p, 'manage', (tx, actor) async {
    await _article(tx, id);
    final r = await _revision(tx, id, revisionId);
    final context = await articles.read(tx, {
      r.content.produced.id,
      ...r.content.ingredients.map((i) => i.article.id),
    });
    return {
      'revision': r.toJson(),
      'currentProduced': context
          .singleWhere((i) => i.article.id == r.content.produced.id)
          .toJson(),
      'currentIngredients': context
          .where((i) => i.article.id != r.content.produced.id)
          .map((i) => i.toJson())
          .toList(),
    };
  });

  Future<Map<String, dynamic>> create(
    SessionPrincipal p,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = CreateRecipeRequest.fromJson(input);
    final produced = await _activeArticle(tx, c.producedArticleId);
    await repository.createArticle(tx, c.id, c.producedArticleId, actor.id);
    await repository.createDraft(
      tx,
      c.id,
      c.revisionId,
      actor.id,
      RecipeContent(
        produced: produced.article,
        batchDescription: '',
        preparation: '',
        ingredients: [],
      ),
    );
    await repository.pointDraft(tx, c.id, c.revisionId, bump: false);
    final a = await _article(tx, c.id),
        r = await _revision(tx, c.id, c.revisionId);
    await database.audit(
      tx,
      actor,
      'production.recipe.created',
      'recipe',
      a.id,
      changes: {
        'recipeId': a.id,
        'producedArticleId': a.producedArticleId,
        'revisionId': r.id,
        'revisionNumber': 1,
        'appliedVersion': 1,
        'status': 'active',
      },
    );
    return _result(tx, c.id, c.revisionId);
  });
  Future<Map<String, dynamic>> newDraft(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = NewRecipeDraftRequest.fromJson(input), a = await _article(tx, id);
    final aggregate = Recipe(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireNoDraft();
    final content = a.currentPublishedRevisionId == null
        ? RecipeContent(
            produced: (await _activeArticle(tx, a.producedArticleId)).article,
            batchDescription: '',
            preparation: '',
            ingredients: [],
          )
        : (await _revision(tx, a.id, a.currentPublishedRevisionId!)).content;
    await repository.createDraft(tx, a.id, c.id, actor.id, content);
    await repository.pointDraft(tx, a.id, c.id);
    await _audit(
      tx,
      actor,
      'draft.created',
      a,
      revision: await _revision(tx, a.id, c.id),
    );
    return _result(tx, a.id, c.id);
  });
  Future<Map<String, dynamic>> save(
    SessionPrincipal p,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = SaveRecipeRequest.fromJson(input),
        a = await _article(tx, id),
        r = await _revision(tx, id, revisionId);
    final aggregate = Recipe(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireDraft(r);
    c.content.validate(producedArticleId: a.producedArticleId);
    final old = {for (final i in r.content.ingredients) i.id: i};
    final lines = <RecipeIngredientDto>[];
    for (final i in c.content.ingredients) {
      final retained = old[i.id];
      RecipeArticleSnapshot snapshot;
      if (!i.reselect && retained != null) {
        if (retained.article.id != i.articleId) {
          throw const PlatformFailure(
            400,
            'invalid_request',
            'Changed reference requires explicit reselection.',
          );
        }
        snapshot = retained.article;
      } else {
        if (!i.reselect) {
          throw const PlatformFailure(
            400,
            'invalid_request',
            'New reference requires explicit selection.',
          );
        }
        snapshot = (await _activeArticle(tx, i.articleId)).article;
      }
      lines.add(
        RecipeIngredientDto(
          i.id,
          lines.length + 1,
          snapshot,
          recipeQuantityText(recipeQuantity(i.quantity)),
        ),
      );
    }
    final content = RecipeContent(
      produced: r.content.produced,
      batchDescription: c.content.batchDescription,
      preparation: c.content.preparation,
      ingredients: lines,
    )..validate();
    await repository.save(tx, a.id, r.id, content);
    await _audit(
      tx,
      actor,
      'draft.saved',
      a,
      revision: r,
      fields: ['batchDescription', 'preparation', 'ingredients'],
    );
    return _result(tx, a.id, r.id);
  });
  Future<Map<String, dynamic>> discard(
    SessionPrincipal p,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = RecipeVersionRequest.fromJson(input),
        a = await _article(tx, id),
        r = await _revision(tx, id, revisionId);
    final aggregate = Recipe(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireDraft(r);
    await repository.discard(tx, a.id, r.id, actor.id);
    await repository.pointDraft(tx, a.id, null);
    await _audit(tx, actor, 'draft.discarded', a, revision: r);
    return _result(tx, a.id, r.id);
  });
  Future<Map<String, dynamic>> publish(
    SessionPrincipal p,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _run(p, 'publish', (tx, actor) async {
    final c = PublishRecipeRequest.fromJson(input);
    id = recipeId(id);
    revisionId = recipeId(revisionId);
    // Resource scope and fresh authorization precede replay; lifecycle/version do not.
    final a = await _article(tx, id);
    final committed = await repository.publication(tx, c.operationId);
    if (committed != null) {
      if (committed.recipe != id ||
          committed.id != revisionId ||
          committed.publishedBy != actor.id ||
          committed.publishExpectedVersion != c.expectedVersion) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Publication identity conflicts.',
        );
      }
      return {'revision': committed.toJson(), 'replayed': true};
    }
    final r = await _revision(tx, id, revisionId);
    final aggregate = Recipe(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireDraft(r);
    Recipe.requirePublication(r.content);
    await _activeArticle(tx, a.producedArticleId);
    for (final i in r.content.ingredients) {
      final current = await _activeArticle(tx, i.article.id);
      if (current.article.unit != i.article.unit) {
        throw const PlatformFailure(
          422,
          'ingredient_unit_changed',
          'Reselect the ingredient and review quantity; no unit conversion is performed.',
        );
      }
    }
    await repository.publish(tx, a.id, r.id, actor.id, c);
    await _audit(
      tx,
      actor,
      'revision.published',
      a,
      revision: r,
      operation: c.operationId,
    );
    return {
      'revision': (await _revision(tx, a.id, r.id)).toJson(),
      'replayed': false,
    };
  });
  Future<Map<String, dynamic>> retire(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> input,
  ) => _run(p, 'publish', (tx, actor) async {
    final c = RecipeVersionRequest.fromJson(input), a = await _article(tx, id);
    Recipe(a).requireActiveVersion(c.expectedVersion);
    final r = a.activeDraftRevisionId == null
        ? null
        : await _revision(tx, a.id, a.activeDraftRevisionId!);
    if (r != null) await repository.discard(tx, a.id, r.id, actor.id);
    await repository.retire(tx, a.id, actor.id);
    await _audit(tx, actor, 'retired', a, revision: r);
    return _detail(tx, await _article(tx, a.id));
  });
  void _query(String q) {
    RecipeDraftContent(
      batchDescription: q,
      preparation: '',
      ingredients: [],
    ).validate();
  }

  String _encode(String scope, String q, String value) => base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'company': database.companyId,
            'scope': scope,
            'q': q,
            'value': value,
          }),
        ),
      )
      .replaceAll('=', '');
  String? _cursor(
    String? value,
    String scope,
    String q, {
    bool history = false,
  }) {
    if (value == null) return null;
    try {
      if (value.length > 2048 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
        throw const FormatException();
      }
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(value))),
      );
      if (j is! Map ||
          j.length != 4 ||
          j['company'] != database.companyId ||
          j['scope'] != scope ||
          j['q'] != q ||
          j['value'] is! String) {
        throw const FormatException();
      }
      final v = j['value'] as String;
      if (history) {
        final n = int.tryParse(v);
        if (!RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(v) ||
            n == null ||
            n > 2147483647) {
          throw const FormatException();
        }
        return v;
      }
      return recipeId(v);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped Recipe cursor.',
      );
    }
  }
}
