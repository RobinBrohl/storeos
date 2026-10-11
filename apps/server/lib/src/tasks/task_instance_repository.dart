import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class TaskInstanceRepository {
  TaskInstanceRepository(this.schema, this.companyId);
  final String schema, companyId;
  Future<bool> pristine(TxSession tx, String shift) async => (await tx.execute(
    Sql.named(
      '''SELECT 1 FROM $schema.task_instances t
      WHERE t.company_id=CAST(@company AS uuid) AND t.shift_id=CAST(@shift AS uuid)
      AND (t.status<>'open' OR t.version<>1 OR t.started_at IS NOT NULL OR t.started_by IS NOT NULL
        OR EXISTS(SELECT 1 FROM $schema.task_step_results r WHERE r.instance_id=t.id)
        OR EXISTS(SELECT 1 FROM $schema.task_numeric_attempts r WHERE r.instance_id=t.id)
        OR EXISTS(SELECT 1 FROM $schema.task_blockings r WHERE r.instance_id=t.id)
        OR EXISTS(SELECT 1 FROM $schema.task_execution_commands r WHERE r.instance_id=t.id)) LIMIT 1''',
    ),
    parameters: {'company': companyId, 'shift': shift},
  )).isEmpty;

  Future<void> linkTransfer(
    TxSession tx,
    String location,
    String request,
    TaskInstanceDto source,
    TaskInstanceDto replacement,
  ) async {
    await tx.execute(
      Sql.named(
        '''INSERT INTO $schema.task_transfer_links
      (company_id,location_id,request_id,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position)
      VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@request AS uuid),CAST(@sourceShift AS uuid),CAST(@replacementShift AS uuid),CAST(@source AS uuid),CAST(@replacement AS uuid),CAST(@template AS uuid),CAST(@revision AS uuid),@position)''',
      ),
      parameters: {
        'company': companyId,
        'location': location,
        'request': request,
        'sourceShift': source.shiftId,
        'replacementShift': replacement.shiftId,
        'source': source.id,
        'replacement': replacement.id,
        'template': source.templateId,
        'revision': source.revisionId,
        'position': source.position,
      },
    );
  }

  Future<List<Map<String, dynamic>>> transferLinks(
    TxSession tx,
    String location,
    String request,
  ) async => (await tx.execute(
    Sql.named(
      '''SELECT source_task_id::text AS "sourceTaskId",replacement_task_id::text AS "replacementTaskId",
      source_shift_id::text AS "sourceShiftId",replacement_shift_id::text AS "replacementShiftId",template_id::text AS "templateId",revision_id::text AS "revisionId",position
      FROM $schema.task_transfer_links WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND request_id=CAST(@request AS uuid) ORDER BY position''',
    ),
    parameters: {
      'company': companyId,
      'location': location,
      'request': request,
    },
  )).map((r) => r.toColumnMap()).toList();
  Future<void> insert(
    TxSession tx, {
    required String id,
    required String shiftId,
    required String employeeId,
    required String locationId,
    required ShiftTemplateSelection selection,
    required int position,
    required TaskTemplateContent content,
  }) async {
    await tx.execute(
      Sql.named(
        '''INSERT INTO $schema.task_instances(id,company_id,location_id,shift_id,employee_id,template_id,revision_id,position,content)
      VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@shift AS uuid),CAST(@employee AS uuid),CAST(@template AS uuid),CAST(@revision AS uuid),@position,@content)''',
      ),
      parameters: {
        'id': id,
        'company': companyId,
        'location': locationId,
        'shift': shiftId,
        'employee': employeeId,
        'template': selection.templateId,
        'revision': selection.revisionId,
        'position': position,
        'content': jsonEncode(content.toJson()),
      },
    );
  }

  Future<bool> cancelOpen(
    TxSession tx, {
    required String id,
    required String actorId,
    required DateTime now,
  }) async {
    final result = await tx.execute(
      Sql.named(
        '''UPDATE $schema.task_instances SET status='cancelled',version=version+1,cancelled_at=@now,cancelled_by=CAST(@actor AS uuid)
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND status='open' AND version=1''',
      ),
      parameters: {
        'id': id,
        'company': companyId,
        'actor': actorId,
        'now': now,
      },
    );
    return result.affectedRows == 1;
  }

  Future<List<TaskInstanceDto>> byIds(TxSession tx, List<String> ids) =>
      _query(tx, ids, instances: true);
  Future<List<TaskInstanceDto>> forShifts(
    TxSession tx,
    List<String> ids, {
    String? detailId,
  }) => _query(tx, ids, detailId: detailId);
  Future<List<TaskInstanceDto>> _query(
    TxSession tx,
    List<String> ids, {
    String? detailId,
    bool instances = false,
  }) async {
    if (ids.isEmpty) return [];
    final rows = await tx.execute(
      Sql.named(
        '''SELECT id::text,shift_id::text,employee_id::text,template_id::text,revision_id::text,title,position,status,version,jsonb_array_length(content::jsonb->'steps') AS total_steps,(SELECT count(*) FROM $schema.task_step_results r WHERE r.instance_id=t.id) AS confirmed_steps${detailId == null ? '' : ',content'}
      FROM $schema.task_instances t WHERE company_id=CAST(@company AS uuid) AND ${instances ? 'id' : 'shift_id'}=ANY(CAST(@ids AS uuid[]))
      AND (CAST(@detail AS uuid) IS NULL OR id=CAST(@detail AS uuid)) ORDER BY ${instances ? 't.id' : 'shift_id,position'}''',
      ),
      parameters: {'company': companyId, 'ids': ids, 'detail': detailId},
    );
    return rows.map((r) {
      final v = r.toColumnMap();
      return TaskInstanceDto(
        id: v['id'] as String,
        shiftId: v['shift_id'] as String,
        employeeId: v['employee_id'] as String,
        templateId: v['template_id'] as String,
        revisionId: v['revision_id'] as String,
        status: v['status'] as String,
        version: v['version'] as int,
        confirmedSteps: v['confirmed_steps'] as int,
        totalSteps: v['total_steps'] as int,
        title: v['title'] as String,
        position: v['position'] as int,
        content: detailId == null
            ? null
            : TaskTemplateContent.fromJson(
                jsonDecode(v['content'] as String) as Map<String, dynamic>,
              ),
      );
    }).toList();
  }
}
