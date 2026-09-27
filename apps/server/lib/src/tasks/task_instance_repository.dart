import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class TaskInstanceRepository {
  TaskInstanceRepository(this.schema, this.companyId);
  final String schema, companyId;
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

  Future<List<TaskInstanceDto>> forShifts(
    TxSession tx,
    List<String> ids, {
    String? detailId,
  }) async {
    if (ids.isEmpty) return [];
    final rows = await tx.execute(
      Sql.named(
        '''SELECT id::text,shift_id::text,employee_id::text,template_id::text,revision_id::text,title,position${detailId == null ? '' : ',content'}
      FROM $schema.task_instances WHERE company_id=CAST(@company AS uuid) AND shift_id=ANY(CAST(@ids AS uuid[]))
      AND (CAST(@detail AS uuid) IS NULL OR id=CAST(@detail AS uuid)) ORDER BY shift_id,position''',
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
