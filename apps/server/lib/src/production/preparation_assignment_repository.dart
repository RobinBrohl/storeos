import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Production-owned requests and receipts; every query binds Company/Location.
class PreparationAssignmentRepository {
  PreparationAssignmentRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Future<Result> execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(
        Sql.named(sql),
        parameters: {'company': company, 'location': location, ...p},
      );
  Map<String, dynamic> json(Map<String, dynamic> row) => {
    for (final e in row.entries)
      if (![
        'revision_status',
        'create_kind',
        'batch_kind',
        'terminal_actor',
        'terminal_kind',
      ].contains(e.key))
        e.key.replaceAllMapped(RegExp(r'_([a-z])'), (m) => m[1]!.toUpperCase()):
            e.value is DateTime ? _instant(e.value as DateTime) : e.value,
  };
  String _instant(DateTime value) {
    final s = value.toUtc().toIso8601String();
    return s.length == 24 ? s.replaceFirst('Z', '000Z') : s;
  }

  Future<Map<String, dynamic>?> find(
    TxSession tx,
    String id, {
    bool lock = false,
  }) async {
    final r = await execute(
      tx,
      'SELECT * FROM $schema.production_preparation_assignments WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid) ${lock ? 'FOR UPDATE' : ''}',
      {'id': id},
    );
    return r.isEmpty ? null : json(r.single.toColumnMap());
  }

  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    String? employee,
    String? status,
    String? after,
  }) async => (await execute(
    tx,
    'SELECT * FROM $schema.production_preparation_assignments WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND (CAST(@employee AS uuid) IS NULL OR employee_id=CAST(@employee AS uuid)) AND (CAST(@status AS text) IS NULL OR status=@status) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51',
    {'employee': employee, 'status': status, 'after': after},
  )).map((r) => json(r.toColumnMap())).toList();
  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final r = await tx.execute(
      Sql.named(
        'SELECT * FROM $schema.production_preparation_assignment_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': company, 'operation': operation},
    );
    return r.isEmpty ? null : r.single.toColumnMap();
  }

  Future<void> create(
    TxSession tx,
    String actor,
    PreparationAssignmentCommandInput c,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_preparation_assignments(id,company_id,location_id,employee_id,recipe_id,revision_id,planned_declared_batch_count,created_by,create_operation_id) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@employee AS uuid),CAST(@recipe AS uuid),CAST(@revision AS uuid),@count,CAST(@actor AS uuid),CAST(@operation AS uuid))',
      {
        'id': c.payload['id'],
        'employee': c.payload['employeeId'],
        'recipe': c.payload['recipeId'],
        'revision': c.payload['revisionId'],
        'count': c.payload['plannedDeclaredBatchCount'],
        'actor': actor,
        'operation': c.operationId,
      },
    );
  }

  Future<void> withdraw(
    TxSession tx,
    String id,
    String actor,
    PreparationAssignmentCommandInput c,
  ) async {
    await execute(
      tx,
      "UPDATE $schema.production_preparation_assignments SET status='withdrawn',version=2,withdrawn_by=CAST(@actor AS uuid),withdrawn_at=clock_timestamp(),withdrawal_reason=@reason,terminal_operation_id=CAST(@operation AS uuid) WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)",
      {
        'id': id,
        'actor': actor,
        'reason': c.payload['reason'],
        'operation': c.operationId,
      },
    );
  }

  Future<void> start(
    TxSession tx,
    String id,
    Map<String, dynamic> batch,
    PreparationAssignmentCommandInput c,
  ) async {
    await execute(
      tx,
      "UPDATE $schema.production_preparation_assignments SET status='started',version=2,batch_id=CAST(@batch AS uuid),batch_operation_id=CAST(@opening AS uuid),started_by=CAST(@actor AS uuid),started_at=CAST(@at AS timestamptz),terminal_operation_id=CAST(@operation AS uuid) WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)",
      {
        'id': id,
        'batch': batch['batchId'],
        'opening': batch['openOperationId'],
        'actor': batch['openedBy'],
        'at': batch['openedAt'],
        'operation': c.operationId,
      },
    );
  }

  Future<void> accept(
    TxSession tx,
    String id,
    String actor,
    PreparationAssignmentCommandInput c,
    Map<String, dynamic> result,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_preparation_assignment_commands(company_id,operation_id,location_id,assignment_id,actor_id,kind,payload,result) VALUES(CAST(@company AS uuid),CAST(@operation AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@kind,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      {
        'operation': c.operationId,
        'id': id,
        'actor': actor,
        'kind': c.kind,
        'payload': c.canonical,
        'result': jsonEncode(result),
      },
    );
  }
}
