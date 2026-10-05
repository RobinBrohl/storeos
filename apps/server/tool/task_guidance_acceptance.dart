import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/shift_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/knowledge/knowledge_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'knowledge_acceptance.dart';

const guidanceAcceptanceBody =
    'Retained guidance v1\n<script>literal</script>\n**plain**';
const _root = '/api/v1/platform/knowledge/manage/articles';
Future<KnowledgeGuidance> seedGuidanceInstruction(
  KnowledgeAcceptanceRequest request,
) async {
  final pin = KnowledgeGuidance(articleId: newUuid(), revisionId: newUuid());
  await request(
    'POST',
    _root,
    CreateWikiRequest(
      pin.articleId,
      pin.revisionId,
      const WikiContent(
        title: 'Retained guidance',
        body: guidanceAcceptanceBody,
      ),
    ).toJson(),
    201,
  );
  await request(
    'POST',
    '$_root/${pin.articleId}/revisions/${pin.revisionId}/publish',
    PublishWikiRequest(newUuid(), 1).toJson(),
    200,
  );
  return pin;
}

Future<void> replaceAndRetireGuidance(
  KnowledgeAcceptanceRequest request,
  KnowledgeGuidance pin,
) async {
  final replacement = newUuid();
  await request(
    'POST',
    '$_root/${pin.articleId}/revisions',
    NewWikiDraftRequest(replacement, 2).toJson(),
    201,
  );
  await request(
    'POST',
    '$_root/${pin.articleId}/revisions/$replacement/edit',
    SaveWikiRequest(
      3,
      const WikiContent(
        title: 'Replacement guidance v2',
        body: 'Never substitute this revision for assigned work.',
      ),
    ).toJson(),
    200,
  );
  await request(
    'POST',
    '$_root/${pin.articleId}/revisions/$replacement/publish',
    PublishWikiRequest(newUuid(), 4).toJson(),
    200,
  );
  await request(
    'POST',
    '$_root/${pin.articleId}/retire',
    WikiVersionRequest(5).toJson(),
    200,
  );
}

Future<void> verifyGuidanceEvidence(
  Connection owner,
  String schema,
  String runtime,
) async {
  final s = quotedSchema(schema), role = '"${runtime.replaceAll('"', '""')}"';
  final rows = await owner.execute(
    'SELECT t.content,t.status,t.knowledge_article_id::text,t.knowledge_revision_id::text,r.revision_number,a.status,a.current_published_revision_id::text,t.knowledge_revision_id=tr.knowledge_revision_id FROM $s.task_instances t JOIN $s.knowledge_revisions r ON r.id=t.knowledge_revision_id JOIN $s.knowledge_articles a ON a.id=t.knowledge_article_id JOIN $s.task_template_revisions tr ON tr.id=t.revision_id',
  );
  if (rows.length != 1) throw StateError('Expected one restored guided task.');
  final row = rows.single,
      content = TaskTemplateContent.fromJson(
        jsonDecode(row[0] as String) as Map<String, dynamic>,
      );
  if (content.schemaVersion != 3 ||
      row[1] != 'completed' ||
      row[4] != 1 ||
      row[5] != 'retired' ||
      row[6] == row[3] ||
      row[7] != true ||
      content.knowledgeGuidance!.articleId != row[2] ||
      content.knowledgeGuidance!.revisionId != row[3] ||
      jsonEncode(content.toJson()).contains(guidanceAcceptanceBody)) {
    throw StateError('Retained guidance evidence changed.');
  }
  final audit = await owner.execute(
    'SELECT changes FROM $s.audit_entries WHERE action=\'tasks.instance.completed\' AND entity_id=(SELECT id::text FROM $s.task_instances WHERE knowledge_revision_id IS NOT NULL)',
  );
  if (audit.length != 1 ||
      (audit.single.first as Map)['knowledgeRevisionId'] != row[3] ||
      jsonEncode(audit.single.first).contains(guidanceAcceptanceBody)) {
    throw StateError('Guided completion audit missing.');
  }
  for (final mutation in [
    'UPDATE $s.task_instances SET knowledge_revision_id=NULL WHERE knowledge_revision_id IS NOT NULL',
    'UPDATE $s.task_instances SET content=content WHERE knowledge_revision_id IS NOT NULL',
    'UPDATE $s.task_template_revisions SET content=content WHERE knowledge_revision_id IS NOT NULL',
  ]) {
    var denied = false;
    try {
      await owner.runTx((tx) async {
        await tx.execute('SET LOCAL ROLE $role');
        await tx.execute(mutation);
      });
    } on ServerException {
      denied = true;
    }
    if (!denied) throw StateError('Restored guidance protection failed.');
  }
}

/// The isolated restore remains fenced to the runtime role. A fresh authenticated
/// verification session uses an owner test pool; no original session is revived.
Future<void> verifyRestoredGuidanceRead(
  Endpoint endpoint,
  String schema,
  String company,
  String location,
  String username,
  String password,
) async {
  final pool = Pool<void>.withEndpoints(
    [endpoint],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 2,
    ),
  );
  try {
    final auth = await AuthService.create(
      store: PostgresAuthStore(pool, schemaName: schema),
      companyId: company,
      locationId: location,
      sessionTtl: const Duration(minutes: 1),
    );
    final session = await auth.login(
      LoginRequest(username: username, password: password),
      remoteKey: 'isolated-restore-verification',
    );
    try {
      final principal = await auth.authenticate(session.token),
          db = PlatformDatabase(
            pool,
            schemaName: schema,
            companyId: company,
            locationId: location,
          );
      final row = (await pool.execute(
        'SELECT id::text,shift_id::text,knowledge_article_id::text,knowledge_revision_id::text FROM ${quotedSchema(schema)}.task_instances WHERE knowledge_revision_id IS NOT NULL',
      )).single;
      final read = TaskKnowledgeDto.fromJson(
        await ShiftApplication(
          db,
        ).knowledge(principal, row[1] as String, row[0] as String),
      );
      if (read.revisionId != row[3] ||
          read.body != guidanceAcceptanceBody ||
          !read.superseded ||
          !read.articleRetired) {
        throw StateError('Restored contextual read did not retain v1.');
      }
      Future<void> denied(
        Future<Map<String, dynamic>> action,
        int status,
      ) async {
        try {
          await action;
        } on PlatformFailure catch (e) {
          if (e.status == status) return;
          rethrow;
        }
        throw StateError('Unexpected historical access.');
      }

      final knowledge = KnowledgeService(db);
      await denied(knowledge.readPublished(principal, row[2] as String), 404);
      await denied(
        knowledge.revision(principal, row[2] as String, row[3] as String),
        403,
      );
    } finally {
      await auth.logout(session.token);
    }
  } finally {
    await pool.close();
  }
}
