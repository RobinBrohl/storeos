import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../inventory/merchandising_article_port.dart';
import '../stock/stock_context_port.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import 'merchandising_repository.dart';

/// Merchandising-owned deployment boundary. Callers authorize stored work first.
class PlanogramGuidancePort {
  PlanogramGuidancePort(this.database)
    : _repository = MerchandisingRepository(
        database.schema,
        database.companyId,
      ),
      _articles = MerchandisingArticlePort(database.schema, database.companyId),
      _stock = StockContextPort(database.schema, database.companyId);
  final PlatformDatabase database;
  final MerchandisingRepository _repository;
  final MerchandisingArticlePort _articles;
  final StockContextPort _stock;

  void requireRead(PlatformActor actor) {
    if (actor.companyId != database.companyId ||
        actor.locationId != database.locationId ||
        !permissionsForRole(
          actor.role,
        ).contains('merchandising.layouts.read')) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Local merchandising read access required.',
      );
    }
  }

  /// Current work scope applies even when retained lifecycle evidence is valid.
  Future<void> requireWorkLocation(
    TxSession tx,
    PlatformActor actor,
    String locationId,
  ) async {
    requireRead(actor);
    if (requireUuid({'id': locationId}, 'id') != database.locationId) {
      throw const PlatformFailure(403, 'forbidden', 'Local location required.');
    }
    await OrganizationService(
      database,
    ).requireConfiguredLocation(tx, locationId);
  }

  Future<void> validatePublication(
    TxSession tx,
    PlatformActor actor,
    String locationId,
    PlanogramGuidance pin, {
    bool selection = false,
  }) async {
    await requireWorkLocation(tx, actor, locationId);
    final fixture = await _repository.find(tx, 'fixtures', pin.fixtureId);
    final assignment = await _repository.find(
      tx,
      'planogram_assignments',
      pin.assignmentId,
    );
    final revision = await _repository.find(
      tx,
      'planogram_revisions',
      pin.revisionId,
    );
    final planogram = revision == null
        ? null
        : await _repository.find(
            tx,
            'planograms',
            revision['planogramId'] as String,
          );
    bool eligible =
        fixture != null &&
        fixture['locationId'] == locationId &&
        fixture['status'] == 'active' &&
        fixture['currentAssignmentId'] == pin.assignmentId &&
        assignment != null &&
        assignment['locationId'] == locationId &&
        assignment['fixtureId'] == pin.fixtureId &&
        assignment['revisionId'] == pin.revisionId &&
        revision != null &&
        revision['status'] == 'published' &&
        planogram != null &&
        planogram['status'] == 'active';
    if (eligible) {
      final content = await _repository.content(tx, revision);
      final refs = await _articles.read(tx, content.articleIds, locationId);
      eligible =
          content.publishable &&
          refs.length == content.articleIds.length &&
          refs.every((r) => r.article.isActive && r.assortmentIsActive == true);
    }
    if (!eligible) {
      throw PlatformFailure(
        422,
        selection
            ? 'planogram_selection_unavailable'
            : 'planogram_guidance_unavailable',
        selection
            ? 'Select a current eligible Fixture deployment.'
            : 'Retained deployment is unavailable for new work; explicitly reselect the layout.',
      );
    }
  }

  Future<RetainedLayoutDto> readStoredPin(
    TxSession tx,
    PlatformActor actor,
    String locationId,
    PlanogramGuidance pin,
  ) async {
    await requireWorkLocation(tx, actor, locationId);
    final fixture = await _repository.find(tx, 'fixtures', pin.fixtureId);
    final assignment = await _repository.find(
      tx,
      'planogram_assignments',
      pin.assignmentId,
    );
    final revision = await _repository.find(
      tx,
      'planogram_revisions',
      pin.revisionId,
    );
    final planogram = revision == null
        ? null
        : await _repository.find(
            tx,
            'planograms',
            revision['planogramId'] as String,
          );
    if (fixture == null ||
        fixture['locationId'] != locationId ||
        assignment == null ||
        assignment['locationId'] != locationId ||
        assignment['fixtureId'] != pin.fixtureId ||
        assignment['revisionId'] != pin.revisionId ||
        revision == null ||
        revision['status'] != 'published' ||
        planogram == null) {
      throw const PlatformFailure(
        500,
        'internal_error',
        'Retained deployment integrity failure.',
      );
    }
    final content = await _repository.content(tx, revision);
    final refs = await _articles.read(tx, content.articleIds, locationId);
    if (!content.publishable || refs.length != content.articleIds.length) {
      throw const PlatformFailure(
        500,
        'internal_error',
        'Retained layout integrity failure.',
      );
    }
    final batch = await _stock.read(tx, locationId, content.articleIds);
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    return RetainedLayoutDto(
      instruction: RetainedLayoutInstruction(
        pin: pin,
        planogramId: revision['planogramId'] as String,
        revisionNumber: revision['revisionNumber'] as int,
        content: content,
      ),
      currentContext: RetainedLayoutContext(
        fixtureName: fixture['name'] as String,
        fixtureKind: fixture['kind'] as String,
        fixtureRetired: fixture['status'] == 'retired',
        planogramRetired: planogram['status'] == 'retired',
        reassigned: fixture['currentAssignmentId'] != pin.assignmentId,
        articles: refs
            .map(
              (r) => {
                ...r.toJson(),
                'stock': batch.levels[r.article.id]?.toJson(),
              },
            )
            .toList(),
        stockContextStatus: batch.status,
        queriedAt: now,
      ),
    );
  }
}
