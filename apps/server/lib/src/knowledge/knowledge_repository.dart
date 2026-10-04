import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Knowledge SQL only; authenticated Company ownership is always included.
class KnowledgeRepository {
  const KnowledgeRepository(this.schema, this.companyId);
  final String schema, companyId;

  Future<Result> execute(
    TxSession tx,
    String sql,
    Map<String, Object?> parameters,
  ) => tx.execute(
    Sql.named(sql),
    parameters: {'company': companyId, ...parameters},
  );

  Future<WikiArticleDto?> article(TxSession tx, String id) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.knowledge_articles WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid)',
      {'id': id},
    );
    return rows.isEmpty
        ? null
        : WikiArticleDto.fromJson(_json(rows.single.toColumnMap()));
  }

  Future<WikiRevisionDto?> revision(
    TxSession tx,
    String article,
    String id,
  ) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.knowledge_revisions WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND id=CAST(@id AS uuid)',
      {'article': article, 'id': id},
    );
    return rows.isEmpty ? null : _revision(rows.single.toColumnMap());
  }

  Future<WikiRevisionDto?> publication(TxSession tx, String operation) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.knowledge_revisions WHERE company_id=CAST(@company AS uuid) AND publish_operation_id=CAST(@operation AS uuid)',
      {'operation': operation},
    );
    return rows.isEmpty ? null : _revision(rows.single.toColumnMap());
  }

  Future<List<WikiArticleDto>> articles(
    TxSession tx,
    String? after,
  ) async => (await execute(
    tx,
    'SELECT * FROM $schema.knowledge_articles WHERE company_id=CAST(@company AS uuid) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51',
    {'after': after},
  )).map((r) => WikiArticleDto.fromJson(_json(r.toColumnMap()))).toList();
  Future<List<WikiRevisionDto>> history(
    TxSession tx,
    String article,
    int? before,
  ) async => (await execute(
    tx,
    'SELECT * FROM $schema.knowledge_revisions WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND (CAST(@before AS integer) IS NULL OR revision_number<@before) ORDER BY revision_number DESC LIMIT 51',
    {'article': article, 'before': before},
  )).map((r) => _revision(r.toColumnMap())).toList();

  Future<List<PublishedWikiDto>> published(
    TxSession tx, {
    String? id,
    String? after,
    String q = '',
  }) async =>
      (await execute(
            tx,
            'SELECT a.id::text AS "articleId",r.id::text AS "revisionId",r.title,r.body,r.revision_number AS "revisionNumber",r.published_at AS "publishedAt" '
            'FROM $schema.knowledge_articles a JOIN $schema.knowledge_revisions r '
            'ON r.id=a.current_published_revision_id AND r.article_id=a.id AND r.company_id=a.company_id AND r.status=\'published\' '
            'WHERE a.company_id=CAST(@company AS uuid) AND a.status=\'active\' '
            'AND (CAST(@id AS uuid) IS NULL OR a.id=CAST(@id AS uuid)) '
            'AND (CAST(@after AS uuid) IS NULL OR a.id>CAST(@after AS uuid)) '
            'AND strpos(lower(r.title),lower(@q))>0 ORDER BY a.id LIMIT 51',
            {'id': id, 'after': after, 'q': q},
          ))
          .map(
            (r) => PublishedWikiDto.fromJson({
              ...r.toColumnMap(),
              'publishedAt': (r.toColumnMap()['publishedAt'] as DateTime)
                  .toUtc()
                  .toIso8601String(),
            }),
          )
          .toList();

  Future<void> createArticle(TxSession tx, String id, String actor) async {
    await execute(
      tx,
      'INSERT INTO $schema.knowledge_articles(id,company_id,created_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@actor AS uuid))',
      {'id': id, 'actor': actor},
    );
  }

  Future<void> createDraft(
    TxSession tx,
    String article,
    String id,
    String actor,
    WikiContent content,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.knowledge_revisions(id,company_id,article_id,revision_number,title,body,created_by) '
      'SELECT CAST(@id AS uuid),CAST(@company AS uuid),CAST(@article AS uuid),COALESCE(max(revision_number),0)+1,@title,@body,CAST(@actor AS uuid) '
      'FROM $schema.knowledge_revisions WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid)',
      {'id': id, 'article': article, 'actor': actor, ...content.toJson()},
    );
  }

  Future<void> pointDraft(
    TxSession tx,
    String article,
    String? revision, {
    bool bump = true,
  }) async {
    await execute(
      tx,
      'UPDATE $schema.knowledge_articles SET active_draft_revision_id=CAST(@revision AS uuid),version=version+${bump ? 1 : 0},updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@article AS uuid)',
      {'article': article, 'revision': revision},
    );
  }

  Future<void> save(
    TxSession tx,
    String article,
    String revision,
    WikiContent content,
  ) async {
    await execute(
      tx,
      'UPDATE $schema.knowledge_revisions SET title=@title,body=@body WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND id=CAST(@revision AS uuid)',
      {'article': article, 'revision': revision, ...content.toJson()},
    );
    await pointDraft(tx, article, revision);
  }

  Future<void> discard(
    TxSession tx,
    String article,
    String revision,
    String actor,
  ) async {
    await execute(
      tx,
      'UPDATE $schema.knowledge_revisions SET status=\'discarded\',discarded_at=clock_timestamp(),discarded_by=CAST(@actor AS uuid) WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND id=CAST(@revision AS uuid)',
      {'article': article, 'revision': revision, 'actor': actor},
    );
  }

  Future<void> publish(
    TxSession tx,
    String article,
    String revision,
    String actor,
    PublishWikiRequest command,
  ) async {
    await execute(
      tx,
      'UPDATE $schema.knowledge_revisions SET status=\'published\',published_at=clock_timestamp(),published_by=CAST(@actor AS uuid),publish_operation_id=CAST(@operationId AS uuid),publish_expected_version=CAST(@expectedVersion AS bigint),publication_version=CAST(@expectedVersion AS bigint)+1 WHERE company_id=CAST(@company AS uuid) AND article_id=CAST(@article AS uuid) AND id=CAST(@revision AS uuid)',
      {
        'article': article,
        'revision': revision,
        'actor': actor,
        ...command.toJson(),
      },
    );
    await execute(
      tx,
      'UPDATE $schema.knowledge_articles SET current_published_revision_id=CAST(@revision AS uuid),active_draft_revision_id=NULL,version=version+1,updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@article AS uuid)',
      {'article': article, 'revision': revision},
    );
  }

  Future<void> retire(TxSession tx, String article, String actor) async {
    await execute(
      tx,
      'UPDATE $schema.knowledge_articles SET status=\'retired\',active_draft_revision_id=NULL,retired_at=clock_timestamp(),retired_by=CAST(@actor AS uuid),version=version+1,updated_at=clock_timestamp() WHERE company_id=CAST(@company AS uuid) AND id=CAST(@article AS uuid)',
      {'article': article, 'actor': actor},
    );
  }
}

WikiRevisionDto _revision(Map<String, dynamic> row) {
  final j = _json(row);
  j['content'] = {'title': j.remove('title'), 'body': j.remove('body')};
  return WikiRevisionDto.fromJson(j);
}

Map<String, dynamic> _json(Map<String, dynamic> row) => {
  for (final e in row.entries)
    if (e.key != 'current_published_state' && e.key != 'active_draft_state')
      e.key.replaceAllMapped(
        RegExp(r'_([a-z])'),
        (m) => m[1]!.toUpperCase(),
      ): e.value is DateTime
          ? (e.value as DateTime).toUtc().toIso8601String()
          : e.value,
};
