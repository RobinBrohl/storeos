import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';

typedef KnowledgeAcceptanceRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      String route,
      Map<String, dynamic>? body,
      int status,
    );

/// Real authorized writes seed all retained states; no direct business SQL.
Future<void> seedApprovedKnowledge(KnowledgeAcceptanceRequest request) async {
  const root = '/api/v1/platform/knowledge/manage/articles';
  for (var i = 0; i < 2; i++) {
    final id = newUuid(), revision = newUuid(), operation = newUuid();
    await request(
      'POST',
      root,
      CreateWikiRequest(
        id,
        revision,
        WikiContent(
          title: 'Knowledge $i',
          body: '# literal\n<script>plain</script>\n  ä 😀',
        ),
      ).toJson(),
      201,
    );
    await request(
      'POST',
      '$root/$id/revisions/$revision/publish',
      PublishWikiRequest(operation, 1).toJson(),
      200,
    );
    final replacement = newUuid();
    await request(
      'POST',
      '$root/$id/revisions',
      NewWikiDraftRequest(replacement, 2).toJson(),
      201,
    );
    if (i == 0) {
      await request(
        'POST',
        '$root/$id/revisions/$replacement/edit',
        SaveWikiRequest(
          3,
          const WikiContent(
            title: 'Current Knowledge',
            body: 'Current instructions',
          ),
        ).toJson(),
        200,
      );
      await request(
        'POST',
        '$root/$id/revisions/$replacement/publish',
        PublishWikiRequest(newUuid(), 4).toJson(),
        200,
      );
      final discarded = newUuid();
      await request(
        'POST',
        '$root/$id/revisions',
        NewWikiDraftRequest(discarded, 5).toJson(),
        201,
      );
      await request(
        'POST',
        '$root/$id/revisions/$discarded/discard',
        WikiVersionRequest(6).toJson(),
        200,
      );
      await request(
        'POST',
        '$root/$id/revisions',
        NewWikiDraftRequest(newUuid(), 7).toJson(),
        201,
      );
    } else {
      await request(
        'POST',
        '$root/$id/retire',
        WikiVersionRequest(3).toJson(),
        200,
      );
    }
    final replay = WikiPublicationDto.fromJson(
      await request(
        'POST',
        '$root/$id/revisions/$revision/publish',
        PublishWikiRequest(operation, 1).toJson(),
        200,
      ),
    );
    if (!replay.replayed || replay.revision.id != revision) {
      throw StateError('Knowledge late replay failed.');
    }
  }
}

/// Runs against source or restored isolated database through the runtime role.
Future<void> verifyKnowledgeEvidence(
  Connection owner,
  String schema,
  String runtime,
) async {
  final s = '"${schema.replaceAll('"', '""')}"',
      role = '"${runtime.replaceAll('"', '""')}"';
  final states = await owner.execute(
    'SELECT status,count(*) FROM $s.knowledge_revisions GROUP BY status ORDER BY status',
  );
  final counts = {for (final row in states) row[0] as String: row[1] as int};
  if (counts['published'] != 3 ||
      counts['discarded'] != 2 ||
      counts['draft'] != 1) {
    throw StateError('Knowledge evidence states incomplete.');
  }
  final pointers = await owner.execute(
    'SELECT count(*) FROM $s.knowledge_articles a LEFT JOIN $s.knowledge_revisions p ON p.id=a.current_published_revision_id AND p.article_id=a.id AND p.company_id=a.company_id AND p.status=\'published\' LEFT JOIN $s.knowledge_revisions d ON d.id=a.active_draft_revision_id AND d.article_id=a.id AND d.company_id=a.company_id AND d.status=\'draft\' WHERE (a.current_published_revision_id IS NOT NULL AND p.id IS NULL) OR (a.active_draft_revision_id IS NOT NULL AND d.id IS NULL) OR (a.status=\'retired\' AND a.active_draft_revision_id IS NOT NULL)',
  );
  if (pointers.single.first != 0) {
    throw StateError('Knowledge pointers invalid.');
  }
  final evidence = await owner.execute(
    'SELECT count(*) FROM $s.knowledge_revisions WHERE status=\'published\' AND publish_operation_id IS NOT NULL AND publication_version=publish_expected_version+1',
  );
  if (evidence.single.first != 3) {
    throw StateError('Knowledge publication evidence missing.');
  }
  final audit = await owner.execute(
    'SELECT count(*) FROM $s.audit_entries WHERE action LIKE \'knowledge.%\'',
  );
  if ((audit.single.first as int) < 10) {
    throw StateError('Knowledge audit missing.');
  }
  Future<void> reject(String sql, String code) async {
    var refused = false;
    try {
      await owner.runTx((tx) async {
        await tx.execute('SET LOCAL ROLE $role');
        await tx.execute(sql);
      });
    } on ServerException catch (e) {
      if (e.code != code) rethrow;
      refused = true;
    }
    if (!refused) throw StateError('Knowledge runtime protection failed.');
  }

  for (final state in ['published', 'discarded']) {
    await reject(
      'UPDATE $s.knowledge_revisions SET body=\'changed\' WHERE id=(SELECT id FROM $s.knowledge_revisions WHERE status=\'$state\' LIMIT 1)',
      '23514',
    );
  }
  for (final table in ['knowledge_articles', 'knowledge_revisions']) {
    await reject('DELETE FROM $s.$table', '42501');
    await reject('TRUNCATE $s.$table CASCADE', '42501');
  }
}
