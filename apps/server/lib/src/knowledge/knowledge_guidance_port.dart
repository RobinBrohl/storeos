import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'knowledge_repository.dart';

/// Knowledge-owned boundary. Callers establish task visibility before exact read.
/// This port never queries Tasks or resolves a pin through the current pointer.
class KnowledgeGuidancePort {
  KnowledgeGuidancePort(this.database)
    : _repository = KnowledgeRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final KnowledgeRepository _repository;

  void requireRead(PlatformActor actor) {
    if (actor.companyId != database.companyId ||
        !permissionsForRole(actor.role).contains('knowledge.articles.read')) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Knowledge read access required.',
      );
    }
  }

  Future<void> validatePublication(
    TxSession tx,
    PlatformActor actor,
    KnowledgeGuidance pin, {
    bool selection = false,
  }) async {
    requireRead(actor);
    final article = await _repository.article(tx, pin.articleId);
    final revision = await _repository.revision(
      tx,
      pin.articleId,
      pin.revisionId,
    );
    if (article == null ||
        article.status != 'active' ||
        revision == null ||
        revision.status != 'published' ||
        (selection && article.currentPublishedRevisionId != pin.revisionId)) {
      throw PlatformFailure(
        422,
        selection ? 'guidance_selection_unavailable' : 'guidance_unavailable',
        selection
            ? 'Selected instruction is unavailable for draft authoring; select a current approved revision.'
            : 'Assigned instruction is unavailable for new work; remove or replace it.',
      );
    }
  }

  Future<TaskKnowledgeDto> readTaskPin(
    TxSession tx,
    PlatformActor actor,
    String taskId,
    KnowledgeGuidance storedPin,
  ) async {
    requireRead(actor);
    final article = await _repository.article(tx, storedPin.articleId);
    final revision = await _repository.revision(
      tx,
      storedPin.articleId,
      storedPin.revisionId,
    );
    if (article == null ||
        revision == null ||
        revision.status != 'published' ||
        revision.publishedAt == null) {
      throw const PlatformFailure(
        500,
        'internal_error',
        'Assigned instruction integrity failure.',
      );
    }
    return TaskKnowledgeDto(
      taskId: taskId,
      articleId: storedPin.articleId,
      revisionId: storedPin.revisionId,
      revisionNumber: revision.revisionNumber,
      title: revision.content.title,
      body: revision.content.body,
      publishedAt: DateTime.parse(revision.publishedAt!),
      superseded: article.currentPublishedRevisionId != storedPin.revisionId,
      articleRetired: article.status == 'retired',
    );
  }
}
