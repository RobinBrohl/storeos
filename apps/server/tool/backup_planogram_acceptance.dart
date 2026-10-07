// Bounded P4.7 probes for the isolated encrypted backup acceptance only.
import 'dart:convert';
import 'stock_count_acceptance.dart';
import 'recipe_acceptance.dart';
import 'preparation_acceptance.dart';
import 'package:storeos_server/src/stock/stock_count_service.dart';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/auth_service.dart';
import 'package:storeos_server/src/application/shift_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/merchandising/merchandising_service.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/tasks/task_template_service.dart';

Future<Map<String, dynamic>> verifyBackupPlanogramReads(
  Endpoint endpoint,
  String schema,
  Map<String, dynamic> evidence, {
  bool historicalOnly = false,
}) async {
  final pool = Pool<void>.withEndpoints(
    [endpoint],
    settings: const PoolSettings(
      sslMode: SslMode.disable,
      maxConnectionCount: 2,
    ),
  );
  final auth = await AuthService.create(
    store: PostgresAuthStore(pool, schemaName: schema),
    companyId: evidence['companyId'] as String,
    locationId: evidence['locationId'] as String,
    sessionTtl: const Duration(minutes: 1),
  );
  AuthService? alternateAuth;
  String? workerToken, adminToken, alternateToken, otherWorkerToken;
  try {
    final db = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: evidence['companyId'] as String,
      locationId: evidence['locationId'] as String,
    );
    final app = ShiftApplication(db), merchandising = MerchandisingService(db);
    final worker = await auth.login(
      LoginRequest(
        username: 'backup_accept_worker',
        password: evidence['workerRecoveryPassword'] as String,
      ),
      remoteKey: 'isolated-planogram-restore',
    );
    workerToken = worker.token;
    final principal = await auth.authenticate(worker.token);
    final admin = await auth.login(
      LoginRequest(
        username: 'backup_accept_admin',
        password: evidence['adminRecoveryPassword'] as String,
      ),
      remoteKey: 'isolated-planogram-current-restore',
    );
    adminToken = admin.token;
    final manager = await auth.authenticate(admin.token);
    final s = quotedSchema(schema);
    otherWorkerToken = (await auth.login(
      LoginRequest(
        username: 'backup_accept_other_worker',
        password: evidence['workerRecoveryPassword'] as String,
      ),
      remoteKey: 'isolated-count-other-employee-restore',
    )).token;
    final historical = await verifyHistoricalPreparation(
      db,
      manager,
      principal,
      await auth.authenticate(otherWorkerToken),
    );
    if (historicalOnly) return historical;
    await verifyRestoredStockCounts(
      db,
      manager,
      principal,
      evidence,
      otherWorker: await auth.authenticate(otherWorkerToken),
    );
    await verifyRestoredRecipes(db, manager, principal);
    await verifyRestoredPreparation(
      db,
      manager,
      principal,
      otherEmployee: await auth.authenticate(otherWorkerToken),
    );
    var auditBefore = (await pool.execute(
      'SELECT count(*) FROM $s.audit_entries',
    )).single.single;
    final tasksBefore = (await pool.execute(
      'SELECT count(*) FROM $s.task_instances',
    )).single.single;
    final retained = RetainedLayoutDto.fromJson(
      await app.planogram(
        principal,
        evidence['shiftId'] as String,
        evidence['completedTaskId'] as String,
      ),
    );
    final pin = retained.instruction.pin;
    if (pin.fixtureId != evidence['planogramFixtureId'] ||
        pin.assignmentId != evidence['planogramAssignmentId'] ||
        pin.revisionId != evidence['planogramRevisionId'] ||
        retained.instruction.revisionNumber != 1 ||
        retained.instruction.content.title != 'Brot Revision 1' ||
        !retained.currentContext.reassigned ||
        !retained.currentContext.fixtureRetired ||
        !retained.currentContext.planogramRetired) {
      throw StateError('Restored Task did not retain exact F/A1/R1.');
    }
    void live(List<Map<String, dynamic>> articles, StockContextStatus status) {
      final article = articles.single;
      if (status != StockContextStatus.available ||
          article['id'] != evidence['articleId'] ||
          article['name'] != 'Planogramm Brot München <>&' ||
          article['isActive'] != true ||
          article['assortmentIsActive'] != true ||
          article['unit'] != 'Stk' ||
          article['stock']?['quantity'] != '12.5' ||
          article['stock']?['stockUnit'] != 'Stk') {
        throw StateError('Restored current Article/Assortment/Stock differs.');
      }
    }

    if (retained.instruction.content.articleIds.single !=
        evidence['articleId']) {
      throw StateError('Retained placement Article identity differs.');
    }
    live(
      retained.currentContext.articles,
      retained.currentContext.stockContextStatus,
    );
    final current = LayoutViewDto.fromJson(
      await merchandising.layout(
        manager,
        evidence['locationId'] as String,
        pin.fixtureId,
      ),
    );
    if (current.fixture.id != pin.fixtureId ||
        current.assignment!.id != evidence['currentAssignmentId'] ||
        current.assignment!.id == pin.assignmentId ||
        current.revision!.id != evidence['currentRevisionId'] ||
        current.revision!.id == pin.revisionId ||
        current.revision!.revisionNumber != 2 ||
        current.revision!.content.title != 'Brot Revision 2') {
      throw StateError('Restored current deployment did not resolve F/A2/R2.');
    }
    live(current.articles, current.stockContextStatus);
    Future<void> denied(
      Future<Map<String, dynamic>> action,
      int status,
      String code,
    ) async {
      try {
        await action;
      } on PlatformFailure catch (error) {
        if (error.status == status && error.code == code) return;
        rethrow;
      }
      throw StateError(
        'Restored arbitrary historical Planogram access succeeded.',
      );
    }

    await denied(
      merchandising.printView(
        principal,
        evidence['locationId'] as String,
        pin.fixtureId,
        pin.assignmentId,
      ),
      409,
      'invalid_lifecycle',
    );
    await denied(
      merchandising.assignments(
        principal,
        evidence['locationId'] as String,
        pin.fixtureId,
      ),
      403,
      'forbidden',
    );
    await denied(
      merchandising.getRevision(
        principal,
        retained.instruction.planogramId,
        pin.revisionId,
      ),
      403,
      'forbidden',
    );
    await denied(
      app.planogram(
        principal,
        evidence['shiftId'] as String,
        evidence['otherTaskId'] as String,
      ),
      404,
      'not_found',
    );
    await denied(
      app.planogram(
        principal,
        evidence['otherShiftId'] as String,
        evidence['otherTaskId'] as String,
      ),
      404,
      'not_found',
    );
    // The other employee's context exists and is readable by the scoped manager.
    final other = RetainedLayoutDto.fromJson(
      await app.planogram(
        manager,
        evidence['otherShiftId'] as String,
        evidence['otherTaskId'] as String,
        self: false,
      ),
    );
    if (other.instruction.pin != pin &&
        jsonEncode(other.instruction.pin.toJson()) !=
            jsonEncode(pin.toJson())) {
      throw StateError('Other employee denial target lacks retained evidence.');
    }
    if ((await pool.execute(
          'SELECT count(*) FROM $s.audit_entries',
        )).single.single !=
        auditBefore) {
      throw StateError('Restored Planogram reads created audit evidence.');
    }
    // The same restored B evidence must be denied by a current A-scoped admin.
    final alternateDb = PlatformDatabase(
      pool,
      schemaName: schema,
      companyId: evidence['companyId'] as String,
      locationId: evidence['alternateLocationId'] as String,
    );
    alternateAuth = await AuthService.create(
      store: PostgresAuthStore(pool, schemaName: schema),
      companyId: alternateDb.companyId,
      locationId: alternateDb.locationId,
      sessionTtl: const Duration(minutes: 1),
    );
    alternateToken = (await alternateAuth.login(
      LoginRequest(
        username: 'backup_scope_admin_a',
        password: evidence['adminRecoveryPassword'] as String,
      ),
      remoteKey: 'isolated-planogram-scope-restore',
    )).token;
    final alternateManager = await alternateAuth.authenticate(alternateToken);
    auditBefore = (await pool.execute(
      'SELECT count(*) FROM $s.audit_entries',
    )).single.single;
    final alternateShifts = ShiftApplication(alternateDb);
    await denied(
      StockCountService(alternateDb).get(
        alternateManager,
        evidence['locationId'] as String,
        evidence['approvedCountId'] as String,
      ),
      403,
      'forbidden',
    );
    await denied(
      StockCountService(alternateDb).command(
        alternateManager,
        evidence['locationId'] as String,
        evidence['approvedCountId'] as String,
        'approve',
        jsonDecode(evidence['countApprovePayload'] as String)
            as Map<String, dynamic>,
      ),
      403,
      'forbidden',
    );
    final alternateTemplates = TaskTemplateService(alternateDb);
    await denied(
      alternateTemplates.planogram(
        alternateManager,
        evidence['completedTemplateId'] as String,
        evidence['completedTemplateRevisionId'] as String,
      ),
      403,
      'forbidden',
    );
    await denied(
      alternateShifts.planogram(
        alternateManager,
        evidence['shiftId'] as String,
        evidence['completedTaskId'] as String,
        self: false,
      ),
      403,
      'forbidden',
    );
    await denied(
      alternateTemplates.publish(
        alternateManager,
        evidence['completedTemplateId'] as String,
        evidence['completedTemplateRevisionId'] as String,
        {'expectedVersion': 1},
      ),
      403,
      'forbidden',
    );
    await denied(
      alternateShifts.publish(alternateManager, evidence['shiftId'] as String, {
        'expectedVersion': 1,
      }),
      403,
      'forbidden',
    );
    // Returning to B still resolves the original retired/reassigned instruction.
    final returned = RetainedLayoutDto.fromJson(
      await app.planogram(
        manager,
        evidence['shiftId'] as String,
        evidence['completedTaskId'] as String,
        self: false,
      ),
    );
    if (!returned.instruction.pin.sameAs(pin)) {
      throw StateError(
        'Restored retained pin changed after Location reconfiguration.',
      );
    }
    await TaskTemplateService(db).publish(
      manager,
      evidence['completedTemplateId'] as String,
      evidence['completedTemplateRevisionId'] as String,
      {'expectedVersion': 1},
    );
    await app.publish(manager, evidence['shiftId'] as String, {
      'expectedVersion': 1,
    });
    if ((await pool.execute(
          'SELECT count(*) FROM $s.audit_entries',
        )).single.single !=
        auditBefore) {
      throw StateError('Restored Planogram reads created audit evidence.');
    }
    if ((await pool.execute(
          'SELECT count(*) FROM $s.task_instances',
        )).single.single !=
        tasksBefore) {
      throw StateError('Restored scope checks/replay duplicated Tasks.');
    }
    return historical;
  } finally {
    if (otherWorkerToken != null) await auth.logout(otherWorkerToken);
    if (alternateToken != null) await alternateAuth!.logout(alternateToken);
    if (workerToken != null) await auth.logout(workerToken);
    if (adminToken != null) await auth.logout(adminToken);
    await pool.close();
  }
}

// Every mutation probe runs in its own rollback-only owner transaction. Exact
// SQLSTATE/constraint assertions distinguish pin guards from incidental failures.
Future<void> verifyBackupPlanogramProtections(
  Connection owner,
  String schema,
  String runtime,
  Map<String, dynamic> evidence,
) async {
  final s = quotedSchema(schema);
  final task = (await owner.execute(
    Sql.named(
      'SELECT content,template_id::text,revision_id::text,planogram_fixture_id::text,planogram_assignment_id::text,planogram_revision_id::text FROM $s.task_instances WHERE id=CAST(@id AS uuid)',
    ),
    parameters: {'id': evidence['completedTaskId']},
  )).single;
  final content = jsonDecode(task[0] as String) as Map<String, dynamic>;
  final pin = content['planogramGuidance'] as Map<String, dynamic>;
  if (task[3] != evidence['planogramFixtureId'] ||
      task[4] != evidence['planogramAssignmentId'] ||
      task[5] != evidence['planogramRevisionId']) {
    throw StateError(
      'Restored generated Task identity differs from source content.',
    );
  }
  final stock = (await owner.execute(
    Sql.named(
      'SELECT a.id::text,a.is_active,x.is_active,l.quantity_scaled,l.stock_unit,m.kind,m.delta_scaled,m.balance_after_scaled,m.balance_version,m.recorded_by::text,m.recorded_at IS NOT NULL FROM $s.articles a JOIN $s.article_location_assortment x ON x.article_id=a.id AND x.company_id=a.company_id JOIN $s.stock_levels l ON l.article_id=a.id AND l.location_id=x.location_id JOIN $s.stock_movements m ON m.stock_level_id=l.id WHERE a.id=CAST(@article AS uuid) AND l.id=CAST(@level AS uuid)',
    ),
    parameters: {
      'article': evidence['articleId'],
      'level': evidence['stockLevelId'],
    },
  )).single;
  if (stock[0] != evidence['articleId'] ||
      stock[1] != true ||
      stock[2] != true ||
      stock[3] != 12500 ||
      stock[4] != 'Stk' ||
      stock[5] != 'opening' ||
      stock[6] != 12500 ||
      stock[7] != 12500 ||
      stock[8] != 1 ||
      stock[9] != evidence['adminAccountId'] ||
      stock[10] != true) {
    throw StateError('Restored attributable Stock opening evidence differs.');
  }
  Future<void> reject(
    String sql,
    Map<String, Object?> args,
    String code, {
    String? constraint,
    bool asRuntime = false,
  }) async {
    try {
      await owner.runTx((tx) async {
        if (asRuntime) {
          await tx.execute('SET LOCAL ROLE "${runtime.replaceAll('"', '""')}"');
        }
        await tx.execute(Sql.named(sql), parameters: args);
        throw const _ProbeAccepted();
      });
    } on ServerException catch (error) {
      if (error.code == code &&
          (constraint == null || error.constraintName == constraint)) {
        return;
      }
      throw StateError(
        'Restored Planogram rejection did not hit expected $code/$constraint.',
      );
    } on _ProbeAccepted {
      throw StateError(
        'Restored Planogram database protection accepted a mutation.',
      );
    }
  }

  final insert =
      'INSERT INTO $s.task_template_revisions(id,template_id,company_id,location_id,revision_number,content) VALUES(CAST(@id AS uuid),CAST(@template AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),2,@content)';
  final args = <String, Object?>{
    'id': newUuid(),
    'template': task[1],
    'company': evidence['companyId'],
    'location': evidence['locationId'],
  };
  final r2 = (await owner.execute(
    'SELECT id::text FROM $s.merchandising_planogram_revisions WHERE revision_number=2',
  )).single.first;
  for (final wrong in [
    {...pin, 'fixtureId': newUuid()},
    {...pin, 'revisionId': r2},
  ]) {
    await reject(
      insert,
      {
        ...args,
        'content': jsonEncode({...content, 'planogramGuidance': wrong}),
      },
      '23503',
      constraint: 'task_revision_planogram_fk',
    );
  }
  for (final scope in ['company', 'location']) {
    await reject(insert, {
      ...args,
      scope: newUuid(),
      'content': task[0],
    }, '23503');
  }
  await reject(
    'INSERT INTO $s.task_instances(id,company_id,location_id,shift_id,employee_id,template_id,revision_id,position,content) SELECT CAST(@new AS uuid),company_id,location_id,shift_id,employee_id,template_id,revision_id,9,@content FROM $s.task_instances WHERE id=CAST(@id AS uuid)',
    {
      'new': newUuid(),
      'id': evidence['completedTaskId'],
      'content': jsonEncode({...content, 'planogramGuidance': null}),
    },
    '23514',
    constraint: 'task_guidance_snapshot',
  );
  await reject(
    'UPDATE $s.task_instances SET content=@content,version=version+1 WHERE id=CAST(@id AS uuid)',
    {
      'id': evidence['otherTaskId'],
      'content': jsonEncode({...content, 'planogramGuidance': null}),
    },
    '23514',
  );
  await reject(
    'UPDATE $s.task_template_revisions SET content=@content WHERE id=CAST(@id AS uuid)',
    {
      'id': task[2],
      'content': jsonEncode({...content, 'planogramGuidance': null}),
    },
    '23514',
  );
  for (final table in ['task_instances', 'task_template_revisions']) {
    final id = table == 'task_instances'
        ? evidence['completedTaskId']
        : task[2];
    for (final column in ['fixture', 'assignment', 'revision']) {
      final generated = (await owner.execute(
        Sql.named(
          'SELECT planogram_${column}_id::text=content::jsonb #>> \'{planogramGuidance,${column}Id}\' FROM $s.$table WHERE id=CAST(@id AS uuid)',
        ),
        parameters: {'id': id},
      )).single.single;
      if (generated != true) {
        throw StateError('Restored generated column is not derived.');
      }
      await reject(
        'UPDATE $s.$table SET planogram_${column}_id=CAST(@value AS uuid) WHERE id=CAST(@id AS uuid)',
        {'value': newUuid(), 'id': id},
        '428C9',
      );
    }
  }
  // Preserve the runtime-role guard as well as owner-level retained immutability.
  await reject(
    'UPDATE $s.task_instances SET content=content WHERE id=CAST(@id AS uuid)',
    {'id': evidence['completedTaskId']},
    '42501',
    asRuntime: true,
  );
}

class _ProbeAccepted implements Exception {
  const _ProbeAccepted();
}
