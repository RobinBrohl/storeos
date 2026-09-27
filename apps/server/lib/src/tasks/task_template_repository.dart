import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'task_template.dart';

class TaskTemplateRepository {
  TaskTemplateRepository(this.schema, this.companyId);
  final String schema, companyId;
  String get _head =>
      'SELECT t.id::text, t.company_id::text, t.location_id::text, t.version, '
      't.created_at, t.updated_at, latest.title, '
      '(SELECT id::text FROM $schema.task_template_revisions WHERE template_id=t.id AND status=\'draft\') AS draft_id, '
      '(SELECT id::text FROM $schema.task_template_revisions WHERE template_id=t.id AND status=\'published\' ORDER BY revision_number DESC LIMIT 1) AS published_id '
      'FROM $schema.task_templates t JOIN LATERAL '
      '(SELECT title FROM $schema.task_template_revisions WHERE template_id=t.id ORDER BY revision_number DESC LIMIT 1) latest ON true ';
  String get _revisionColumns =>
      'id::text, template_id::text, revision_number, status, title, created_at, published_at, published_by::text';
  Map<String, dynamic> get _scope => {'company': companyId};

  /// Fetch pinned published revisions in one scoped query, never "latest".
  Future<Map<String, TemplateRevisionDto>> publishedSelections(
    TxSession tx,
    String locationId,
    List<String> revisionIds,
  ) async {
    if (revisionIds.isEmpty) return {};
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_revisionColumns, content FROM $schema.task_template_revisions '
        'WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) '
        "AND status='published' AND id=ANY(CAST(@ids AS uuid[]))",
      ),
      parameters: {..._scope, 'location': locationId, 'ids': revisionIds},
    );
    return {
      for (final row in rows)
        (row.toColumnMap()['id'] as String): _revision(row.toColumnMap()),
    };
  }

  Future<TaskTemplateDto?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        '$_head WHERE t.id=CAST(@id AS uuid) AND t.company_id=CAST(@company AS uuid)',
      ),
      parameters: {..._scope, 'id': id},
    );
    return rows.isEmpty ? null : _template(rows.single.toColumnMap());
  }

  Future<List<TaskTemplateDto>> page(
    TxSession tx,
    String? after,
  ) async => (await tx.execute(
    Sql.named(
      '$_head WHERE t.company_id=CAST(@company AS uuid) '
      'AND (CAST(@after AS uuid) IS NULL OR t.id>CAST(@after AS uuid)) ORDER BY t.id LIMIT 51',
    ),
    parameters: {..._scope, 'after': after},
  )).map((r) => _template(r.toColumnMap())).toList();
  Future<List<TemplateRevisionDto>> revisions(
    TxSession tx,
    String id,
    int? before,
  ) async => (await tx.execute(
    Sql.named(
      'SELECT $_revisionColumns FROM $schema.task_template_revisions '
      'WHERE template_id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) '
      'AND (CAST(@before AS integer) IS NULL OR revision_number<@before) ORDER BY revision_number DESC LIMIT 51',
    ),
    parameters: {..._scope, 'id': id, 'before': before},
  )).map((r) => _revision(r.toColumnMap())).toList();
  Future<TaskRevision?> revision(
    TxSession tx,
    String templateId,
    String id,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_revisionColumns, content, publication_version FROM $schema.task_template_revisions '
        'WHERE id=CAST(@id AS uuid) AND template_id=CAST(@template AS uuid) AND company_id=CAST(@company AS uuid)',
      ),
      parameters: {..._scope, 'template': templateId, 'id': id},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return TaskRevision(_revision(row), row['publication_version'] as int?);
  }

  Future<bool> revisionIdExists(
    TxSession tx,
    String id,
  ) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.task_template_revisions WHERE id=CAST(@id AS uuid)',
    ),
    parameters: {'id': id},
  )).isNotEmpty;
  Future<void> insert(TxSession tx, String id, String location) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.task_templates(id, company_id, location_id) '
        'VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid))',
      ),
      parameters: {..._scope, 'id': id, 'location': location},
    );
  }

  Future<void> addRevision(
    TxSession tx,
    String templateId,
    String locationId,
    String id,
    TaskTemplateContent content,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.task_template_revisions '
        '(id, template_id, company_id, location_id, revision_number, content) '
        'VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid), '
        '(SELECT COALESCE(MAX(revision_number),0)+1 FROM $schema.task_template_revisions WHERE template_id=CAST(@template AS uuid)),@content)',
      ),
      parameters: {
        ..._scope,
        'id': id,
        'template': templateId,
        'location': locationId,
        'content': jsonEncode(content.toJson()),
      },
    );
  }

  Future<void> touch(TxSession tx, TaskTemplateDto template) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.task_templates SET version=version+1, updated_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version',
      ),
      parameters: {..._scope, 'id': template.id, 'version': template.version},
    );
    if (result.affectedRows != 1) throw TemplateStateConflict();
  }

  Future<void> edit(
    TxSession tx,
    TaskRevision revision,
    TaskTemplateContent content,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.task_template_revisions SET content=@content '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND status=\'draft\'',
      ),
      parameters: {
        ..._scope,
        'id': revision.view.id,
        'content': jsonEncode(content.toJson()),
      },
    );
    if (result.affectedRows != 1) throw TemplateStateConflict();
  }

  Future<void> publish(
    TxSession tx,
    TaskRevision revision,
    String actorId,
    int version,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.task_template_revisions SET status=\'published\', '
        'published_at=clock_timestamp(), published_by=CAST(@actor AS uuid), publication_version=@version '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND status=\'draft\'',
      ),
      parameters: {
        ..._scope,
        'id': revision.view.id,
        'actor': actorId,
        'version': version,
      },
    );
    if (result.affectedRows != 1) throw TemplateStateConflict();
  }
}

TaskTemplateDto _template(Map<String, dynamic> r) => TaskTemplateDto(
  id: r['id'] as String,
  companyId: r['company_id'] as String,
  locationId: r['location_id'] as String,
  version: r['version'] as int,
  title: r['title'] as String,
  createdAt: r['created_at'] as DateTime,
  updatedAt: r['updated_at'] as DateTime,
  draftId: r['draft_id'] as String?,
  publishedId: r['published_id'] as String?,
);
TemplateRevisionDto _revision(Map<String, dynamic> r) => TemplateRevisionDto(
  id: r['id'] as String,
  templateId: r['template_id'] as String,
  number: r['revision_number'] as int,
  status: r['status'] as String,
  title: r['title'] as String,
  createdAt: r['created_at'] as DateTime,
  publishedAt: r['published_at'] as DateTime?,
  publishedBy: r['published_by'] as String?,
  content: r['content'] == null
      ? null
      : TaskTemplateContent.fromJson(
          jsonDecode(r['content'] as String) as Map<String, dynamic>,
        ),
);
