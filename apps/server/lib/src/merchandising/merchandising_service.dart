import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../infrastructure/auth_store.dart';
import '../inventory/merchandising_article_port.dart';
import '../stock/stock_context_port.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'merchandising_repository.dart';
import 'print_layout.dart';
import 'planogram_guidance_port.dart';
import '../http/json_logger.dart';

class MerchandisingService {
  MerchandisingService(this.database)
    : repository = MerchandisingRepository(database.schema, database.companyId),
      articles = MerchandisingArticlePort(database.schema, database.companyId),
      stock = StockContextPort(database.schema, database.companyId);
  final PlatformDatabase database;
  final MerchandisingRepository repository;
  final MerchandisingArticlePort articles;
  final StockContextPort stock;
  String get s => database.schema;
  Future<Map<String, dynamic>> _run(
    SessionPrincipal p,
    String permission,
    String? location,
    Future<Map<String, dynamic>> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(
        p,
        'merchandising.layouts.$permission',
        (tx, actor) async {
          if (actor.locationId != database.locationId ||
              (location != null && location != database.locationId)) {
            throw const PlatformFailure(
              403,
              'forbidden',
              'Local location required.',
            );
          }
          await OrganizationService(
            database,
          ).requireConfiguredLocation(tx, location ?? database.locationId);
          return action(tx, actor);
        },
      );
    } on ServerException catch (e) {
      const JsonLogger().event(
        'merchandising_database_error',
        level: 'error',
        fields: {'sqlState': e.code, 'constraint': e.constraintName},
      );
      if (e.code == '23505' &&
          const {
            'merchandising_fixtures_pkey',
            'merchandising_planograms_pkey',
            'merchandising_planogram_revisions_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Resource already exists; reload its original identity.',
        );
      }
      if (e.code == '23505' &&
          const {
            'merchandising_planogram_zones_pkey',
            'merchandising_planogram_placements_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'layout_identity_conflict',
          'Layout IDs already belong to another revision.',
        );
      }
      // Unexpected infrastructure/integrity failures remain 5xx in this module.
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Database unavailable.',
      );
    }
  }

  Future<Map<String, dynamic>> _get(
    TxSession tx,
    String table,
    String id,
  ) async =>
      await repository.find(tx, table, id) ??
      (throw const PlatformFailure(404, 'not_found', 'Resource not found.'));
  void _active(Map<String, dynamic> j) {
    if (j['status'] != 'active') {
      throw const PlatformFailure(
        409,
        'invalid_lifecycle',
        'Resource retired.',
      );
    }
  }

  void _version(Map<String, dynamic> j, int v) {
    if (j['version'] != v) {
      throw const PlatformFailure(
        409,
        'stale_version',
        'State changed; reload and review.',
      );
    }
  }

  Future<void> _bump(
    TxSession tx,
    String table,
    String id,
  ) => repository.execute(
    tx,
    'UPDATE ${repository.table(table)} SET version=version+1,updated_at=clock_timestamp() WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
    {'id': id},
  );
  Future<void> _audit(
    TxSession tx,
    PlatformActor a,
    String action,
    String type,
    String id, {
    String? location,
    Map<String, dynamic> changes = const {},
  }) => database.audit(
    tx,
    a,
    'merchandising.$action',
    type,
    id,
    locationId: location,
    changes: changes,
  );
  Future<Map<String, dynamic>> listFixtures(
    SessionPrincipal p,
    String location, {
    String? after,
  }) => _run(p, 'read', merchandisingId(location), (tx, a) async {
    final rows = await repository.query(
      tx,
      'fixtures',
      where:
          'AND location_id=CAST(@location AS uuid) AND (@manager OR status=\'active\') AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid))',
      parameters: {
        'location': location,
        'manager': a.role == 'admin',
        'after': after == null ? null : merchandisingId(after),
      },
    );
    return _page(rows.map((j) => _fixtureRead(j, a)).toList());
  });
  Future<Map<String, dynamic>> _fixture(
    TxSession tx,
    String location,
    String id,
  ) async {
    final f = await _get(tx, 'fixtures', id);
    if (f['locationId'] != location) {
      throw const PlatformFailure(404, 'not_found', 'Fixture not found.');
    }
    return f;
  }

  Map<String, dynamic> _fixtureRead(Map<String, dynamic> f, PlatformActor a) =>
      a.role == 'admin'
      ? f
      : {
          for (final k in [
            'id',
            'locationId',
            'name',
            'kind',
            'status',
            'version',
            'currentAssignmentId',
          ])
            k: f[k],
        };
  Future<Map<String, dynamic>> getFixture(
    SessionPrincipal p,
    String location,
    String id,
  ) => _run(p, 'read', merchandisingId(location), (tx, a) async {
    final f = await _fixture(tx, location, merchandisingId(id));
    if (a.role != 'admin') _active(f);
    return _fixtureRead(f, a);
  });
  Future<Map<String, dynamic>> createFixture(
    SessionPrincipal p,
    String location,
    Map<String, dynamic> input,
  ) {
    final c = FixtureInput.fromJson(input);
    return _run(p, 'manage', merchandisingId(location), (tx, a) async {
      if (await repository.find(tx, 'fixtures', c.id!) != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Fixture already exists.',
        );
      }
      await repository.execute(
        tx,
        'INSERT INTO $s.merchandising_fixtures(id,company_id,location_id,name,kind,created_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),@name,@kind,CAST(@actor AS uuid))',
        {
          'id': c.id,
          'location': location,
          'name': c.name,
          'kind': c.kind,
          'actor': a.id,
        },
      );
      await _audit(
        tx,
        a,
        'fixture.created',
        'fixture',
        c.id!,
        location: location,
        changes: {'version': 1},
      );
      return _get(tx, 'fixtures', c.id!);
    });
  }

  Future<Map<String, dynamic>> editFixture(
    SessionPrincipal p,
    String location,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = FixtureInput.fromJson(input, create: false);
    return _run(p, 'manage', merchandisingId(location), (tx, a) async {
      final f = await _fixture(tx, location, merchandisingId(id));
      _version(f, c.expectedVersion!);
      _active(f);
      if (f['name'] == c.name && f['kind'] == c.kind) return f;
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_fixtures SET name=@name,kind=@kind WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {'id': id, 'name': c.name, 'kind': c.kind},
      );
      await _bump(tx, 'fixtures', id);
      await _audit(
        tx,
        a,
        'fixture.edited',
        'fixture',
        id,
        location: location,
        changes: {
          'oldVersion': c.expectedVersion,
          'version': c.expectedVersion! + 1,
        },
      );
      return _get(tx, 'fixtures', id);
    });
  }

  Future<Map<String, dynamic>> retireFixture(
    SessionPrincipal p,
    String location,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = VersionCommand.fromJson(input);
    return _run(p, 'manage', merchandisingId(location), (tx, a) async {
      final f = await _fixture(tx, location, merchandisingId(id));
      _version(f, c.expectedVersion);
      _active(f);
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_fixtures SET status=\'retired\',retired_at=clock_timestamp(),retired_by=CAST(@actor AS uuid),version=version+1,updated_at=clock_timestamp() WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {'actor': a.id, 'id': id},
      );
      await _audit(
        tx,
        a,
        'fixture.retired',
        'fixture',
        id,
        location: location,
        changes: {'version': c.expectedVersion + 1, 'status': 'retired'},
      );
      return _get(tx, 'fixtures', id);
    });
  }

  Future<Map<String, dynamic>> listPlanograms(
    SessionPrincipal p, {
    String? after,
  }) => _run(
    p,
    'manage',
    null,
    (tx, a) async => _page(
      await repository.query(
        tx,
        'planograms',
        where: 'AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid))',
        parameters: {'after': after == null ? null : merchandisingId(after)},
      ),
    ),
  );
  Future<Map<String, dynamic>> getPlanogram(SessionPrincipal p, String id) =>
      _run(
        p,
        'manage',
        null,
        (tx, a) => _get(tx, 'planograms', merchandisingId(id)),
      );
  Future<Map<String, dynamic>> createPlanogram(
    SessionPrincipal p,
    Map<String, dynamic> input,
  ) {
    final c = PlanogramInput.fromJson(input);
    return _run(p, 'manage', c.authoringLocationId, (tx, a) async {
      if (c.originFixtureId != null) {
        _active(await _fixture(tx, c.authoringLocationId!, c.originFixtureId!));
      }
      if (await repository.find(tx, 'planograms', c.id) != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Planogram already exists.',
        );
      }
      await repository.execute(
        tx,
        'INSERT INTO $s.merchandising_planograms(id,company_id,authoring_location_id,origin_fixture_id,created_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@fixture AS uuid),CAST(@actor AS uuid))',
        {
          'id': c.id,
          'location': c.authoringLocationId,
          'fixture': c.originFixtureId,
          'actor': a.id,
        },
      );
      await _audit(
        tx,
        a,
        'planogram.created',
        'planogram',
        c.id,
        changes: {'version': 1},
      );
      return _get(tx, 'planograms', c.id);
    });
  }

  Future<Map<String, dynamic>> retirePlanogram(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = VersionCommand.fromJson(input);
    return _run(p, 'manage', null, (tx, a) async {
      final pg = await _get(tx, 'planograms', merchandisingId(id));
      _version(pg, c.expectedVersion);
      _active(pg);
      final drafts = await repository.query(
        tx,
        'planogram_revisions',
        where: 'AND planogram_id=CAST(@id AS uuid) AND status=\'draft\'',
        parameters: {'id': id},
      );
      for (final d in drafts) {
        await _discard(tx, a, d['id'] as String);
        await _audit(
          tx,
          a,
          'draft.discarded',
          'planogram_revision',
          d['id'] as String,
          changes: {'status': 'discarded', 'version': c.expectedVersion + 1},
        );
      }
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_planograms SET status=\'retired\',retired_at=clock_timestamp(),retired_by=CAST(@actor AS uuid),version=version+1,updated_at=clock_timestamp() WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {'actor': a.id, 'id': id},
      );
      await _audit(
        tx,
        a,
        'planogram.retired',
        'planogram',
        id,
        changes: {'version': c.expectedVersion + 1, 'status': 'retired'},
      );
      return _get(tx, 'planograms', id);
    });
  }

  Future<Map<String, dynamic>> _revision(
    TxSession tx,
    String pg,
    String id,
  ) async {
    final r = await _get(tx, 'planogram_revisions', id);
    if (r['planogramId'] != pg) {
      throw const PlatformFailure(404, 'not_found', 'Revision not found.');
    }
    final content = await repository.content(tx, r);
    final context = await articles.read(
      tx,
      content.articleIds,
      database.locationId,
    );
    return {
      ...r,
      'content': content.toJson(),
      'articles': context.map((a) => a.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> getRevision(
    SessionPrincipal p,
    String pg,
    String id,
  ) => _run(
    p,
    'manage',
    null,
    (tx, a) => _revision(tx, merchandisingId(pg), merchandisingId(id)),
  );
  Future<Map<String, dynamic>> listRevisions(
    SessionPrincipal p,
    String pg, {
    String? after,
  }) => _run(p, 'manage', null, (tx, a) async {
    await _get(tx, 'planograms', merchandisingId(pg));
    final rows = await repository.query(
      tx,
      'planogram_revisions',
      where:
          'AND planogram_id=CAST(@id AS uuid) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid))',
      parameters: {
        'id': pg,
        'after': after == null ? null : merchandisingId(after),
      },
    );
    final result = <Map<String, dynamic>>[];
    for (final r in rows) {
      result.add(await _revision(tx, pg, r['id'] as String));
    }
    return _page(result);
  });
  Future<void> _validateArticles(
    TxSession tx,
    LayoutContent c, {
    bool active = false,
    String? location,
  }) async {
    final refs = await articles.read(tx, c.articleIds, location);
    final unavailable = c.articleIds
        .where(
          (id) => !refs.any(
            (r) => r.article.id == id && (!active || r.article.isActive),
          ),
        )
        .toList();
    if (unavailable.isNotEmpty) {
      throw PlatformFailure(
        409,
        'article_unavailable',
        'Unavailable Articles: ${unavailable.join(', ')}',
      );
    }
    final missing = refs
        .where((r) => location != null && r.assortmentIsActive != true)
        .map((r) => r.article.id)
        .toList();
    if (missing.isNotEmpty) {
      throw PlatformFailure(
        409,
        'assortment_unavailable',
        'Assortment unavailable: ${missing.join(', ')}',
      );
    }
  }

  Future<Map<String, dynamic>> createDraft(
    SessionPrincipal p,
    String pg,
    Map<String, dynamic> input,
  ) {
    final c = DraftCommand.fromJson(input, create: true);
    return _run(p, 'manage', null, (tx, a) async {
      final plan = await _get(tx, 'planograms', merchandisingId(pg));
      if (await repository.find(tx, 'planogram_revisions', c.id!) != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Revision already exists.',
        );
      }
      _version(plan, c.expectedVersion);
      _active(plan);
      final rows = await repository.query(
        tx,
        'planogram_revisions',
        where: 'AND planogram_id=CAST(@id AS uuid)',
        parameters: {'id': pg},
        order: 'revision_number DESC',
        limit: 1,
      );
      final draft = await repository.query(
        tx,
        'planogram_revisions',
        where: 'AND planogram_id=CAST(@id AS uuid) AND status=\'draft\'',
        parameters: {'id': pg},
      );
      if (draft.isNotEmpty) {
        throw const PlatformFailure(
          409,
          'draft_exists',
          'One draft already exists.',
        );
      }
      await _validateArticles(tx, c.content);
      await repository.execute(
        tx,
        'INSERT INTO $s.merchandising_planogram_revisions(id,company_id,planogram_id,revision_number,title,created_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@pg AS uuid),@number,@title,CAST(@actor AS uuid))',
        {
          'id': c.id,
          'pg': pg,
          'number': rows.isEmpty
              ? 1
              : (rows.first['revisionNumber'] as int) + 1,
          'title': c.content.title,
          'actor': a.id,
        },
      );
      await repository.saveContent(tx, c.id!, c.content);
      await _bump(tx, 'planograms', pg);
      await _audit(
        tx,
        a,
        'draft.created',
        'planogram_revision',
        c.id!,
        changes: {'version': c.expectedVersion + 1},
      );
      return {
        'planogram': await _get(tx, 'planograms', pg),
        'revision': await _revision(tx, pg, c.id!),
      };
    });
  }

  Future<Map<String, dynamic>> editDraft(
    SessionPrincipal p,
    String pg,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = DraftCommand.fromJson(input);
    return _run(p, 'manage', null, (tx, a) async {
      final plan = await _get(tx, 'planograms', merchandisingId(pg));
      _version(plan, c.expectedVersion);
      _active(plan);
      final r = await _revision(tx, pg, merchandisingId(id));
      _draft(r);
      await _validateArticles(tx, c.content);
      if (jsonEncode(r['content']) == c.content.canonical) {
        return {'planogram': plan, 'revision': r};
      }
      await repository.saveContent(tx, id, c.content);
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_planogram_revisions SET title=@title WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {'id': id, 'title': c.content.title},
      );
      await _bump(tx, 'planograms', pg);
      await _audit(
        tx,
        a,
        'draft.saved',
        'planogram_revision',
        id,
        changes: {'version': c.expectedVersion + 1},
      );
      return {
        'planogram': await _get(tx, 'planograms', pg),
        'revision': await _revision(tx, pg, id),
      };
    });
  }

  void _draft(Map<String, dynamic> r) {
    if (r['status'] != 'draft') {
      throw const PlatformFailure(409, 'invalid_lifecycle', 'Draft required.');
    }
  }

  Future<void> _discard(
    TxSession tx,
    PlatformActor a,
    String id,
  ) => repository.execute(
    tx,
    'UPDATE $s.merchandising_planogram_revisions SET status=\'discarded\',discarded_at=clock_timestamp(),discarded_by=CAST(@actor AS uuid) WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
    {'id': id, 'actor': a.id},
  );
  Future<Map<String, dynamic>> discardDraft(
    SessionPrincipal p,
    String pg,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = VersionCommand.fromJson(input);
    return _run(p, 'manage', null, (tx, a) async {
      final plan = await _get(tx, 'planograms', merchandisingId(pg));
      _version(plan, c.expectedVersion);
      _active(plan);
      final r = await _revision(tx, pg, merchandisingId(id));
      _draft(r);
      await _discard(tx, a, id);
      await _bump(tx, 'planograms', pg);
      await _audit(
        tx,
        a,
        'draft.discarded',
        'planogram_revision',
        id,
        changes: {'version': c.expectedVersion + 1, 'status': 'discarded'},
      );
      return {
        'planogram': await _get(tx, 'planograms', pg),
        'revision': await _revision(tx, pg, id),
      };
    });
  }

  Future<Map<String, dynamic>> publish(
    SessionPrincipal p,
    String pg,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = PublishCommand.fromJson(input);
    pg = merchandisingId(pg);
    id = merchandisingId(id);
    return _run(p, 'publish', null, (tx, a) async {
      if ((await repository.operation(
        tx,
        'planogram_assignments',
        c.operationId,
      )).isNotEmpty) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Operation ID bound to an assignment.',
        );
      }
      final replay = await repository.operation(
        tx,
        'planogram_revisions',
        c.operationId,
      );
      if (replay.isNotEmpty) {
        final r = replay.single;
        if (r['companyId'] != database.companyId ||
            r['id'] != id ||
            r['planogramId'] != pg ||
            r['publishedBy'] != a.id ||
            r['publishExpectedVersion'] != c.expectedVersion) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Operation ID bound to another publish.',
          );
        }
        return {
          'revision': await _revision(tx, pg, id),
          'appliedVersion': r['publicationVersion'],
          'replayed': true,
        };
      }
      final plan = await _get(tx, 'planograms', pg);
      _version(plan, c.expectedVersion);
      _active(plan);
      final r = await _revision(tx, pg, id);
      _draft(r);
      final content = LayoutContent.fromJson(
        r['content'] as Map<String, dynamic>,
      );
      if (!content.publishable) {
        throw const PlatformFailure(
          409,
          'invalid_layout',
          'Every published zone requires placements.',
        );
      }
      await _validateArticles(tx, content, active: true);
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_planogram_revisions SET status=\'published\',published_at=clock_timestamp(),published_by=CAST(@actor AS uuid),publish_operation_id=CAST(@op AS uuid),publish_expected_version=CAST(@version AS bigint),publication_version=CAST(@version AS bigint)+1 WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {
          'id': id,
          'actor': a.id,
          'op': c.operationId,
          'version': c.expectedVersion,
        },
      );
      await _bump(tx, 'planograms', pg);
      await _audit(
        tx,
        a,
        'revision.published',
        'planogram_revision',
        id,
        changes: {
          'operationId': c.operationId,
          'version': c.expectedVersion + 1,
          'status': 'published',
        },
      );
      return {
        'revision': await _revision(tx, pg, id),
        'appliedVersion': c.expectedVersion + 1,
        'replayed': false,
      };
    });
  }

  Future<Map<String, dynamic>> candidates(
    SessionPrincipal p, {
    String q = '',
    String? after,
    bool includeInactive = false,
  }) {
    if (q.runes.length > 64 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(q)) {
      throw const FormatException('Invalid search.');
    }
    return _run(
      p,
      'manage',
      null,
      (tx, a) => articles.candidates(
        tx,
        q: q,
        after: after == null ? null : merchandisingId(after),
        includeInactive: includeInactive,
      ),
    );
  }

  Future<Map<String, dynamic>> assignments(
    SessionPrincipal p,
    String location,
    String id, {
    String? after,
  }) => _run(p, 'manage', merchandisingId(location), (tx, a) async {
    await _fixture(tx, location, merchandisingId(id));
    return _page(
      await repository.query(
        tx,
        'planogram_assignments',
        where:
            'AND fixture_id=CAST(@id AS uuid) AND location_id=CAST(@location AS uuid) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid))',
        parameters: {
          'id': id,
          'location': location,
          'after': after == null ? null : merchandisingId(after),
        },
      ),
    );
  });
  Future<Map<String, dynamic>> assign(
    SessionPrincipal p,
    String location,
    String id,
    Map<String, dynamic> input,
  ) {
    final c = AssignCommand.fromJson(input);
    id = merchandisingId(id);
    return _run(p, 'publish', merchandisingId(location), (tx, a) async {
      if ((await repository.operation(
        tx,
        'planogram_revisions',
        c.operationId,
      )).isNotEmpty) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Operation ID bound to a publication.',
        );
      }
      final replay = await repository.operation(
        tx,
        'planogram_assignments',
        c.operationId,
      );
      if (replay.isNotEmpty) {
        final r = replay.single;
        if (r['companyId'] != database.companyId ||
            r['fixtureId'] != id ||
            r['locationId'] != location ||
            r['revisionId'] != c.revisionId ||
            r['assignedBy'] != a.id ||
            r['expectedVersion'] != c.expectedVersion) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Operation ID bound to another assignment.',
          );
        }
        return {
          'assignment': r,
          'applied': true,
          'replayed': true,
          'appliedVersion': r['appliedVersion'],
        };
      }
      final f = await _fixture(tx, location, id);
      _version(f, c.expectedVersion);
      _active(f);
      final r = await _get(tx, 'planogram_revisions', c.revisionId);
      if (r['status'] != 'published') {
        throw const PlatformFailure(
          409,
          'invalid_lifecycle',
          'Published revision required.',
        );
      }
      _active(await _get(tx, 'planograms', r['planogramId'] as String));
      final content = await repository.content(tx, r);
      await _validateArticles(tx, content, active: true, location: location);
      if (f['currentAssignmentId'] != null) {
        final current = await _get(
          tx,
          'planogram_assignments',
          f['currentAssignmentId'] as String,
        );
        if (current['revisionId'] == c.revisionId) {
          return {
            'assignment': current,
            'applied': false,
            'replayed': false,
            'appliedVersion': f['version'],
          };
        }
      }
      final assignment = newUuid();
      await repository.execute(
        tx,
        'INSERT INTO $s.merchandising_planogram_assignments(id,company_id,location_id,fixture_id,revision_id,operation_id,expected_version,applied_version,assigned_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@fixture AS uuid),CAST(@revision AS uuid),CAST(@op AS uuid),CAST(@version AS bigint),CAST(@version AS bigint)+1,CAST(@actor AS uuid))',
        {
          'id': assignment,
          'location': location,
          'fixture': id,
          'revision': c.revisionId,
          'op': c.operationId,
          'version': c.expectedVersion,
          'actor': a.id,
        },
      );
      await repository.execute(
        tx,
        'UPDATE $s.merchandising_fixtures SET current_assignment_id=CAST(@assignment AS uuid),version=version+1,updated_at=clock_timestamp() WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
        {'assignment': assignment, 'id': id},
      );
      await _audit(
        tx,
        a,
        'assignment.created',
        'planogram_assignment',
        assignment,
        location: location,
        changes: {
          'fixtureId': id,
          'revisionId': c.revisionId,
          'operationId': c.operationId,
          'version': c.expectedVersion + 1,
        },
      );
      return {
        'assignment': await _get(tx, 'planogram_assignments', assignment),
        'applied': true,
        'replayed': false,
        'appliedVersion': c.expectedVersion + 1,
      };
    });
  }

  Future<Map<String, dynamic>> _view(
    TxSession tx,
    PlatformActor a,
    String location,
    String fixture, {
    String? assignment,
    bool print = false,
  }) async {
    final f = await _fixture(tx, location, fixture);
    if (a.role != 'admin') {
      if (f['status'] != 'active') {
        throw const PlatformFailure(
          409,
          'invalid_lifecycle',
          'Fixture retired.',
        );
      }
      if (assignment != null && assignment != f['currentAssignmentId']) {
        throw const PlatformFailure(
          409,
          'assignment_changed',
          'Assignment changed; reload.',
        );
      }
    }
    final chosen = assignment ?? f['currentAssignmentId'] as String?;
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    if (chosen == null) {
      return {
        'fixture': _fixtureRead(f, a),
        'assignment': null,
        'revision': null,
        'articles': <Map<String, dynamic>>[],
        'stockContextStatus': StockContextStatus.available.name,
        'queriedAt': now.toUtc().toIso8601String(),
        'historical': false,
      };
    }
    final asg = await _get(tx, 'planogram_assignments', chosen);
    if (asg['fixtureId'] != fixture || asg['locationId'] != location) {
      throw const PlatformFailure(404, 'not_found', 'Assignment not found.');
    }
    final r = await _get(
      tx,
      'planogram_revisions',
      asg['revisionId'] as String,
    );
    final content = await repository.content(tx, r);
    final refs = await articles.read(tx, content.articleIds, location);
    final stockBatch = print
        ? const StockContextBatch({})
        : await stock.read(tx, location, content.articleIds);
    final revision = {...r, 'content': content.toJson()};
    if (a.role != 'admin') {
      for (final k in [
        'createdBy',
        'publishedBy',
        'publishOperationId',
        'publishExpectedVersion',
        'publicationVersion',
        'discardedBy',
      ]) {
        revision.remove(k);
      }
    }
    return {
      'fixture': _fixtureRead(f, a),
      'assignment': a.role == 'admin'
          ? asg
          : {
              for (final k in [
                'id',
                'fixtureId',
                'revisionId',
                'appliedVersion',
                'assignedAt',
              ])
                k: asg[k],
            },
      'revision': revision,
      'articles': refs
          .map(
            (r) => {
              ...r.toJson(),
              if (!print) 'stock': stockBatch.levels[r.article.id]?.toJson(),
            },
          )
          .toList(),
      'stockContextStatus': stockBatch.status.name,
      'queriedAt': now.toUtc().toIso8601String(),
      'historical':
          chosen != f['currentAssignmentId'] || f['status'] == 'retired',
    };
  }

  Future<Map<String, dynamic>> layout(
    SessionPrincipal p,
    String location,
    String id,
  ) => _run(
    p,
    'read',
    merchandisingId(location),
    (tx, a) => _view(tx, a, location, merchandisingId(id)),
  );

  /// Current eligible deployment only; historical Task reads use their stored pin.
  Future<Map<String, dynamic>> guidanceSelection(
    SessionPrincipal p,
    String location,
    String id,
  ) => _run(p, 'read', merchandisingId(location), (tx, actor) async {
    if (!permissionsForRole(actor.role).contains('tasks.templates.manage')) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Template management access required.',
      );
    }
    final view = await _view(tx, actor, location, merchandisingId(id));
    final assignment = view['assignment'] as Map<String, dynamic>?;
    if (assignment == null) {
      throw const PlatformFailure(
        422,
        'planogram_selection_unavailable',
        'Select a current eligible Fixture deployment.',
      );
    }
    await PlanogramGuidancePort(database).validatePublication(
      tx,
      actor,
      location,
      PlanogramGuidance(
        fixtureId: id,
        assignmentId: assignment['id'] as String,
        revisionId: assignment['revisionId'] as String,
      ),
      selection: true,
    );
    return view;
  });
  Future<Map<String, dynamic>> printView(
    SessionPrincipal p,
    String location,
    String id,
    String assignment,
  ) => _run(p, 'read', merchandisingId(location), (tx, a) async {
    final view = await _view(
      tx,
      a,
      location,
      merchandisingId(id),
      assignment: merchandisingId(assignment),
      print: true,
    );
    return {
      'assignmentId': assignment,
      'revisionId': (view['revision'] as Map)['id'],
      'html': renderLayoutPrint(LayoutViewDto.fromJson(view)),
    };
  });
}

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
  'items': rows.take(50).toList(),
  'nextCursor': rows.length > 50 ? rows[49]['id'] : null,
};
