import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class TaskExecutionRepository {
  TaskExecutionRepository(this.schema, this.companyId);
  final String schema, companyId;
  Future<TaskExecutionDto?> get(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        '''SELECT t.id::text, t.status, t.version, t.started_at, t.started_by::text, t.completed_at, t.completed_by::text,
      c.id::text AS cancelled_blocking_id, c.resolved_at AS cancelled_at, c.resolved_by::text AS cancelled_by,
      (SELECT b.id::text FROM $schema.task_blockings b WHERE b.instance_id=t.id AND b.resolved_at IS NULL) AS blocking_id
      FROM $schema.task_instances t LEFT JOIN $schema.task_blockings c ON c.instance_id=t.id AND c.resolution_kind='cancelled'
      WHERE t.company_id=CAST(@company AS uuid) AND t.id=CAST(@id AS uuid)''',
      ),
      parameters: {'company': companyId, 'id': id},
    );
    if (rows.isEmpty) return null;
    final r = rows.single.toColumnMap();
    final steps = await tx.execute(
      Sql.named(
        '''SELECT step_id::text, confirmed_at, confirmed_by::text, accepted_version FROM $schema.task_step_results
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
      activeBlockingId: r['blocking_id'] as String?,
      cancelledBlockingId: r['cancelled_blocking_id'] as String?,
      cancelledAt: r['cancelled_at'] as DateTime?,
      cancelledBy: r['cancelled_by'] as String?,
      results: steps.map((row) {
        final s = row.toColumnMap();
        return TaskStepResultDto(
          s['step_id'] as String,
          s['confirmed_at'] as DateTime,
          s['confirmed_by'] as String,
          acceptedVersion: s['accepted_version'] as int,
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
          '''INSERT INTO $schema.task_step_results(instance_id,company_id,location_id,step_id,position,confirmed_at,confirmed_by,accepted_version)
        VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@step AS uuid),@position,@now,CAST(@actor AS uuid),@accepted)''',
        ),
        parameters: {
          'id': current.instanceId,
          'company': companyId,
          'location': location,
          'step': step,
          'position': current.results.length,
          'accepted': current.version + 1,
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
      'block' => ",status='blocked'",
      'resume' => ",status='in_progress'",
      'cancel' => ",status='cancelled'",
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
        if (command == 'start' || command == 'complete') 'now': now,
        if (command == 'start' || command == 'complete') 'actor': actor,
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
  Future<void> block(
    TxSession tx,
    TaskExecutionDto current,
    String id,
    String? step,
    String reason,
    String actor,
    String location,
    DateTime now,
  ) async {
    await tx.execute(
      Sql.named('''INSERT INTO $schema.task_blockings
      (id,instance_id,company_id,location_id,step_id,reason,reported_at,reported_by,reported_version)
      VALUES(CAST(@id AS uuid),CAST(@instance AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),
      CAST(@step AS uuid),@reason,@now,CAST(@actor AS uuid),@version)'''),
      parameters: {
        'id': id,
        'instance': current.instanceId,
        'company': companyId,
        'location': location,
        'step': step,
        'reason': reason,
        'now': now,
        'actor': actor,
        'version': current.version + 1,
      },
    );
  }

  Future<void> resolve(
    TxSession tx,
    TaskExecutionDto current,
    String reason,
    String actor,
    DateTime now,
    String kind,
  ) async {
    final changed = await tx.execute(
      Sql.named(
        '''UPDATE $schema.task_blockings SET resolution=@reason,resolution_kind=@kind,
      resolved_at=@now,resolved_by=CAST(@actor AS uuid),resolved_version=@version
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND instance_id=CAST(@instance AS uuid) AND resolved_at IS NULL''',
      ),
      parameters: {
        'reason': reason,
        'kind': kind,
        'now': now,
        'actor': actor,
        'version': current.version + 1,
        'id': current.activeBlockingId,
        'company': companyId,
        'instance': current.instanceId,
      },
    );
    if (changed.affectedRows != 1) {
      throw StateError('Blocking changed inside transaction.');
    }
  }

  Future<List<String>> exceptions(
    TxSession tx,
    String? employee,
    String location,
    String? after,
    String status,
  ) async => (await tx.execute(
    Sql.named(
      '''SELECT id::text FROM $schema.task_instances
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND status=@status
      AND (CAST(@employee AS uuid) IS NULL OR employee_id=CAST(@employee AS uuid))
      AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51''',
    ),
    parameters: {
      'company': companyId,
      'location': location,
      'employee': employee,
      'after': after,
      'status': status,
    },
  )).map((r) => r.first as String).toList();
  Future<List<TaskBlockingDto>> history(
    TxSession tx,
    String instance,
    int? before,
  ) async =>
      (await tx.execute(
        Sql.named(
          '''SELECT id::text,instance_id::text,step_id::text,reason,reported_at,reported_by::text,
      reported_version,resolution_kind,resolution,resolved_at,resolved_by::text,resolved_version FROM $schema.task_blockings
      WHERE company_id=CAST(@company AS uuid) AND instance_id=CAST(@instance AS uuid)
      AND (CAST(@before AS bigint) IS NULL OR reported_version<@before) ORDER BY reported_version DESC LIMIT 51''',
        ),
        parameters: {
          'company': companyId,
          'instance': instance,
          'before': before,
        },
      )).map((row) {
        final r = row.toColumnMap();
        return TaskBlockingDto(
          id: r['id'] as String,
          instanceId: r['instance_id'] as String,
          stepId: r['step_id'] as String?,
          reason: r['reason'] as String,
          reportedAt: r['reported_at'] as DateTime,
          reportedBy: r['reported_by'] as String,
          reportedVersion: r['reported_version'] as int,
          resolution: r['resolution'] as String?,
          resolutionKind: r['resolution_kind'] as String?,
          resolvedAt: r['resolved_at'] as DateTime?,
          resolvedBy: r['resolved_by'] as String?,
          resolvedVersion: r['resolved_version'] as int?,
        );
      }).toList();
}
