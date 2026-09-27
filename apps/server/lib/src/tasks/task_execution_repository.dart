import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class TaskExecutionRepository {
  TaskExecutionRepository(this.schema, this.companyId);
  final String schema, companyId;
  Future<TaskExecutionDto?> get(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        '''SELECT id::text, status, version, started_at, started_by::text, completed_at, completed_by::text
      FROM $schema.task_instances WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid)''',
      ),
      parameters: {'company': companyId, 'id': id},
    );
    if (rows.isEmpty) return null;
    final r = rows.single.toColumnMap();
    final steps = await tx.execute(
      Sql.named(
        '''SELECT step_id::text, confirmed_at, confirmed_by::text FROM $schema.task_step_results
      WHERE company_id=CAST(@company AS uuid) AND instance_id=CAST(@id AS uuid) ORDER BY position''',
      ),
      parameters: {'company': companyId, 'id': id},
    );
    return TaskExecutionDto(
      instanceId: id,
      status: r['status'] as String,
      version: r['version'] as int,
      startedAt: r['started_at'] as DateTime?,
      startedBy: r['started_by'] as String?,
      completedAt: r['completed_at'] as DateTime?,
      completedBy: r['completed_by'] as String?,
      results: steps.map((row) {
        final s = row.toColumnMap();
        return TaskStepResultDto(
          s['step_id'] as String,
          s['confirmed_at'] as DateTime,
          s['confirmed_by'] as String,
        );
      }).toList(),
    );
  }

  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT company_id::text, actor_id::text, instance_id::text, input, result FROM $schema.task_execution_commands WHERE operation_id=CAST(@op AS uuid)',
      ),
      parameters: {'op': operation},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<void> remember(
    TxSession tx,
    String operation,
    String actor,
    String location,
    String id,
    String input,
    TaskExecutionDto result,
  ) => tx
      .execute(
        Sql.named(
          '''INSERT INTO $schema.task_execution_commands(operation_id,company_id,location_id,instance_id,actor_id,input,result)
      VALUES(CAST(@op AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@input,@result)''',
        ),
        parameters: {
          'op': operation,
          'company': companyId,
          'location': location,
          'id': id,
          'actor': actor,
          'input': input,
          'result': jsonEncode(result.toJson()),
        },
      )
      .then((_) {});
  Future<void> apply(
    TxSession tx,
    TaskExecutionDto current,
    String command,
    String? step,
    String actor,
    String location,
    DateTime now,
  ) async {
    if (command == 'confirm') {
      await tx.execute(
        Sql.named(
          '''INSERT INTO $schema.task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by)
        VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@step AS uuid),@position,@now,CAST(@actor AS uuid))''',
        ),
        parameters: {
          'id': current.instanceId,
          'company': companyId,
          'location': location,
          'step': step,
          'position': current.results.length,
          'now': now,
          'actor': actor,
        },
      );
    }
    final change = switch (command) {
      'start' =>
        ",status='in_progress',started_at=@now,started_by=CAST(@actor AS uuid)",
      'complete' =>
        ",status='completed',completed_at=@now,completed_by=CAST(@actor AS uuid)",
      _ => '',
    };
    final updated = await tx.execute(
      Sql.named(
        'UPDATE $schema.task_instances SET version=version+1$change WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version',
      ),
      parameters: {
        'id': current.instanceId,
        'company': companyId,
        'version': current.version,
        if (command != 'confirm') 'now': now,
        if (command != 'confirm') 'actor': actor,
      },
    );
    if (updated.affectedRows != 1) {
      throw StateError('Execution version changed inside transaction.');
    }
  }

  Future<List<String>> running(
    TxSession tx,
    String employee,
    String location,
    String? after,
  ) async => (await tx.execute(
    Sql.named(
      '''SELECT id::text FROM $schema.task_instances WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)
      AND employee_id=CAST(@employee AS uuid) AND status='in_progress' AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51''',
    ),
    parameters: {
      'company': companyId,
      'location': location,
      'employee': employee,
      'after': after,
    },
  )).map((r) => r.first as String).toList();
}
