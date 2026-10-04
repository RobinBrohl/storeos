import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../platform/platform_database.dart';
import '../http/json_logger.dart';
import 'knowledge_repository.dart';
import 'wiki_article.dart';

class KnowledgeService {
  KnowledgeService(this.database)
    : repository = KnowledgeRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final KnowledgeRepository repository;

  Future<Map<String, dynamic>> _run(
    SessionPrincipal p,
    String capability,
    Future<Map<String, dynamic>> Function(TxSession, PlatformActor) work,
  ) async {
    try {
      return await database.runAuthorized(
        p,
        'knowledge.articles.$capability',
        work,
      );
    } on ServerException catch (e) {
      const JsonLogger().event(
        'knowledge_database_error',
        level: 'error',
        fields: {'sqlState': e.code, 'constraint': e.constraintName},
      );
      if (e.code == '23505' &&
          const {
            'knowledge_articles_pkey',
            'knowledge_revisions_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Identity exists; reload and review.',
        );
      }
      if (e.code == '23505' && e.constraintName == 'knowledge_one_draft') {
        throw const PlatformFailure(
          409,
          'draft_exists',
          'Article already has a draft.',
        );
      }
      if (e.code == '23505' &&
          e.constraintName == 'knowledge_publication_operation_unique') {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Publication identity conflicts.',
        );
      }
      if (e.code == '23505' &&
          e.constraintName == 'knowledge_revision_number_unique') {
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
          'Knowledge database unavailable.',
        );
      }
      throw const PlatformFailure(
        500,
        'internal_error',
        'Knowledge integrity failure.',
      );
    }
  }

  Future<WikiArticleDto> _article(TxSession tx, String id) async =>
      await repository.article(tx, knowledgeId(id)) ??
      (throw const PlatformFailure(404, 'not_found', 'Article not found.'));
  Future<WikiRevisionDto> _revision(
    TxSession tx,
    String article,
    String revision,
  ) async =>
      await repository.revision(
        tx,
        knowledgeId(article),
        knowledgeId(revision),
      ) ??
      (throw const PlatformFailure(404, 'not_found', 'Revision not found.'));
  Future<Map<String, dynamic>> _detail(
    TxSession tx,
    WikiArticleDto a,
  ) async => {
    'article': a.toJson(),
    'draft': a.activeDraftRevisionId == null
        ? null
        : (await _revision(tx, a.id, a.activeDraftRevisionId!)).toJson(),
    'currentPublished': a.currentPublishedRevisionId == null
        ? null
        : (await _revision(tx, a.id, a.currentPublishedRevisionId!)).toJson(),
  };
  Future<Map<String, dynamic>> _result(
    TxSession tx,
    String a,
    String r,
  ) async => {
    'article': (await _article(tx, a)).toJson(),
    'revision': (await _revision(tx, a, r)).toJson(),
  };
  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    String action,
    WikiArticleDto a, {
    WikiRevisionDto? revision,
    List<String> fields = const [],
    String? operation,
  }) => database.audit(
    tx,
    actor,
    'knowledge.$action',
    'wiki_article',
    a.id,
    changes: {
      'articleId': a.id,
      if (revision != null) 'revisionId': revision.id,
      if (revision != null) 'revisionNumber': revision.revisionNumber,
      'expectedVersion': a.version,
      'appliedVersion': a.version + 1,
      'fromStatus': a.status,
      'toStatus': action == 'article.retired' ? 'retired' : a.status,
      if (revision != null) 'fromRevisionStatus': revision.status,
      if (revision != null)
        'toRevisionStatus': switch (action) {
          'revision.published' => 'published',
          'draft.discarded' || 'article.retired' => 'discarded',
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
    WikiContent(title: q, body: '').validate();
    final rows = await repository.published(tx, q: q, after: _cursor(after));
    return {
      'items': rows.take(50).map((r) => r.toJson()).toList(),
      'nextCursor': rows.length > 50 ? rows[49].articleId : null,
    };
  });
  Future<Map<String, dynamic>> readPublished(SessionPrincipal p, String id) =>
      _run(p, 'read', (tx, actor) async {
        final rows = await repository.published(tx, id: knowledgeId(id));
        if (rows.isEmpty) {
          throw const PlatformFailure(
            404,
            'not_found',
            'Published instruction not found.',
          );
        }
        return rows.single.toJson();
      });
  Future<Map<String, dynamic>> listManaged(
    SessionPrincipal p, {
    String? after,
  }) => _run(p, 'manage', (tx, actor) async {
    final rows = await repository.articles(tx, _cursor(after));
    return {
      'items': [for (final a in rows.take(50)) await _detail(tx, a)],
      'nextCursor': rows.length > 50 ? rows[49].id : null,
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
    int? before;
    if (after != null) {
      before = int.tryParse(after);
      if (!RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(after) ||
          before == null ||
          before > 2147483647) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid history cursor.',
        );
      }
    }
    final rows = await repository.history(tx, a.id, before);
    return {
      'items': rows.take(50).map((r) => r.toJson()).toList(),
      'nextCursor': rows.length > 50
          ? rows[49].revisionNumber.toString()
          : null,
    };
  });
  Future<Map<String, dynamic>> revision(
    SessionPrincipal p,
    String id,
    String revisionId,
  ) => _run(p, 'manage', (tx, actor) async {
    await _article(tx, id);
    return (await _revision(tx, id, revisionId)).toJson();
  });

  Future<Map<String, dynamic>> create(
    SessionPrincipal p,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = CreateWikiRequest.fromJson(input);
    await repository.createArticle(tx, c.id, actor.id);
    await repository.createDraft(tx, c.id, c.revisionId, actor.id, c.content);
    await repository.pointDraft(tx, c.id, c.revisionId, bump: false);
    final a = await _article(tx, c.id),
        r = await _revision(tx, c.id, c.revisionId);
    await database.audit(
      tx,
      actor,
      'knowledge.article.created',
      'wiki_article',
      a.id,
      changes: {
        'articleId': a.id,
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
    final c = NewWikiDraftRequest.fromJson(input), a = await _article(tx, id);
    final aggregate = WikiArticle(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireNoDraft();
    final previous = a.currentPublishedRevisionId == null
        ? null
        : await _revision(tx, a.id, a.currentPublishedRevisionId!);
    await repository.createDraft(
      tx,
      a.id,
      c.id,
      actor.id,
      previous?.content ?? const WikiContent(title: '', body: ''),
    );
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
    final c = SaveWikiRequest.fromJson(input),
        a = await _article(tx, id),
        r = await _revision(tx, id, revisionId);
    final aggregate = WikiArticle(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireDraft(r);
    if (r.content.sameAs(c.content)) return _result(tx, a.id, r.id);
    await repository.save(tx, a.id, r.id, c.content);
    await _audit(
      tx,
      actor,
      'draft.saved',
      a,
      revision: r,
      fields: [
        if (r.content.title != c.content.title) 'title',
        if (r.content.body != c.content.body) 'body',
      ],
    );
    return _result(tx, a.id, r.id);
  });
  Future<Map<String, dynamic>> discard(
    SessionPrincipal p,
    String id,
    String revisionId,
    Map<String, dynamic> input,
  ) => _run(p, 'manage', (tx, actor) async {
    final c = WikiVersionRequest.fromJson(input),
        a = await _article(tx, id),
        r = await _revision(tx, id, revisionId);
    final aggregate = WikiArticle(a)..requireActiveVersion(c.expectedVersion);
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
    final c = PublishWikiRequest.fromJson(input);
    id = knowledgeId(id);
    revisionId = knowledgeId(revisionId);
    // Resource scope and fresh authorization precede replay; lifecycle/version do not.
    final a = await _article(tx, id);
    final committed = await repository.publication(tx, c.operationId);
    if (committed != null) {
      if (committed.articleId != id ||
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
    final aggregate = WikiArticle(a)..requireActiveVersion(c.expectedVersion);
    aggregate.requireDraft(r);
    WikiArticle.requirePublication(r.content);
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
    final c = WikiVersionRequest.fromJson(input), a = await _article(tx, id);
    WikiArticle(a).requireActiveVersion(c.expectedVersion);
    final r = a.activeDraftRevisionId == null
        ? null
        : await _revision(tx, a.id, a.activeDraftRevisionId!);
    if (r != null) await repository.discard(tx, a.id, r.id, actor.id);
    await repository.retire(tx, a.id, actor.id);
    await _audit(tx, actor, 'article.retired', a, revision: r);
    return _detail(tx, await _article(tx, a.id));
  });
}

String? _cursor(String? value) {
  if (value == null) return null;
  try {
    return knowledgeId(value);
  } on FormatException {
    throw const PlatformFailure(
      400,
      'invalid_cursor',
      'Invalid Knowledge cursor.',
    );
  }
}
