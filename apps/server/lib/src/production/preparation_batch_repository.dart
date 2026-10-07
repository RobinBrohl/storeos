import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Owns only Production tables. Every query binds Company and configured Location.
class PreparationBatchRepository {
  PreparationBatchRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Future<Result> execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(
        Sql.named(sql),
        parameters: {'company': company, 'location': location, ...p},
      );
  Map<String, dynamic> _json(Map<String, dynamic> row, {bool batch = false}) =>
      {
        for (final e in row.entries)
          if (![
            'revision_status',
            'open_kind',
            'terminal_actor',
            'command_kind',
          ].contains(e.key))
            (batch && e.key == 'id'
                ? 'batchId'
                : e.key.replaceAllMapped(
                    RegExp(r'_([a-z])'),
                    (m) => m[1]!.toUpperCase(),
                  )): e.value is DateTime
                ? (e.value as DateTime).toUtc().toIso8601String()
                : e.value,
      };
  Future<Map<String, dynamic>?> find(TxSession tx, String id) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.production_preparation_batches WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)',
      {'id': id},
    );
    return rows.isEmpty ? null : _json(rows.single.toColumnMap(), batch: true);
  }

  Future<List<Map<String, dynamic>>> corrections(
    TxSession tx,
    String id,
  ) async => (await execute(
    tx,
    'SELECT * FROM $schema.production_preparation_batch_count_corrections WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND batch_id=CAST(@id AS uuid) ORDER BY correction_number',
    {'id': id},
  )).map((r) => _json(r.toColumnMap())).toList();
  Future<Map<String, dynamic>> detail(
    TxSession tx,
    Map<String, dynamic> batch,
  ) async {
    final chain = await corrections(tx, batch['batchId'] as String);
    return {
      ...batch,
      'corrections': chain,
      'latestCorrectionNumber': chain.isEmpty
          ? 0
          : chain.last['correctionNumber'],
      'effectiveDeclaredBatchCount': chain.isEmpty
          ? batch['actualDeclaredBatchCount']
          : chain.last['replacementDeclaredBatchCount'],
    };
  }

  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    String? employee,
    String? status,
    String? after,
  }) async => (await execute(
    tx,
    'SELECT * FROM $schema.production_preparation_batches WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND (CAST(@employee AS uuid) IS NULL OR employee_id=CAST(@employee AS uuid)) AND (CAST(@status AS text) IS NULL OR status=@status) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51',
    {'employee': employee, 'status': status, 'after': after},
  )).map((r) => _json(r.toColumnMap(), batch: true)).toList();
  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT * FROM $schema.production_preparation_batch_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': company, 'operation': operation},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<void> accept(
    TxSession tx,
    String id,
    String actor,
    PreparationCommandInput input,
    Map<String, dynamic> result,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_preparation_batch_commands(company_id,operation_id,location_id,batch_id,actor_id,kind,payload,result) VALUES(CAST(@company AS uuid),CAST(@operation AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@kind,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      {
        'operation': input.operationId,
        'id': id,
        'actor': actor,
        'kind': input.kind,
        'payload': input.canonical,
        'result': jsonEncode(result),
      },
    );
  }

  Future<void> open(
    TxSession tx,
    String employee,
    String actor,
    PreparationCommandInput c,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.production_preparation_batches(id,company_id,location_id,recipe_id,revision_id,employee_id,opened_by,planned_declared_batch_count,open_operation_id) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@recipe AS uuid),CAST(@revision AS uuid),CAST(@employee AS uuid),CAST(@actor AS uuid),@planned,CAST(@operation AS uuid))',
      {
        'id': c.payload['batchId'],
        'recipe': c.payload['recipeId'],
        'revision': c.payload['revisionId'],
        'employee': employee,
        'actor': actor,
        'planned': c.payload['plannedDeclaredBatchCount'],
        'operation': c.operationId,
      },
    );
  }

  Future<void> terminal(
    TxSession tx,
    String id,
    String actor,
    PreparationCommandInput c,
  ) async {
    final complete = c.kind == 'complete';
    await execute(
      tx,
      'UPDATE $schema.production_preparation_batches SET status=@status,version=2,terminal_operation_id=CAST(@operation AS uuid),terminal_kind=@kind,${complete ? 'actual_declared_batch_count=@count,completed_by=CAST(@actor AS uuid),completed_at=clock_timestamp(),completion_note=@text' : 'cancelled_by=CAST(@actor AS uuid),cancelled_at=clock_timestamp(),cancellation_reason=@text'} WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)',
      {
        'id': id,
        'actor': actor,
        'operation': c.operationId,
        'kind': c.kind,
        'status': complete ? 'completed' : 'cancelled',
        if (complete) 'count': c.payload['actualDeclaredBatchCount'],
        'text': c.payload[complete ? 'note' : 'reason'],
      },
    );
  }

  Future<Map<String, dynamic>> correct(
    TxSession tx,
    PreparationBatchDto batch,
    String actor,
    PreparationCommandInput c,
  ) async {
    final rows = await execute(
      tx,
      'INSERT INTO $schema.production_preparation_batch_count_corrections(company_id,location_id,batch_id,correction_number,previous_effective_count,replacement_declared_batch_count,corrected_by,reason,operation_id) VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),@number,@previous,@replacement,CAST(@actor AS uuid),@reason,CAST(@operation AS uuid)) RETURNING *',
      {
        'id': batch.id,
        'number': batch.latestCorrectionNumber + 1,
        'previous': batch.effective,
        'replacement': c.payload['replacementDeclaredBatchCount'],
        'actor': actor,
        'reason': c.payload['reason'],
        'operation': c.operationId,
      },
    );
    return _json(rows.single.toColumnMap());
  }
}
