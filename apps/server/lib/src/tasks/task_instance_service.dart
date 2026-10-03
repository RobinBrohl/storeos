import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'task_template_repository.dart';
import 'task_instance_repository.dart';

/// Tasks owns selection validation and snapshots; no workforce table access.
class TaskInstanceService {
  TaskInstanceService(this.database)
    : _templates = TaskTemplateRepository(database.schema, database.companyId),
      _instances = TaskInstanceRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final TaskTemplateRepository _templates;
  final TaskInstanceRepository _instances;
  Future<List<TaskTemplateContent>> validateSelections(
    TxSession tx,
    String location,
    List<ShiftTemplateSelection> selections,
  ) async {
    final revisions = await _templates.publishedSelections(
      tx,
      location,
      selections.map((s) => s.revisionId).toList(),
    );
    final contents = <TaskTemplateContent>[];
    for (final selection in selections) {
      final revision = revisions[selection.revisionId];
      if (revision == null || revision.templateId != selection.templateId) {
        throw const PlatformFailure(
          422,
          'invalid_selection',
          'Select published revisions from this location.',
        );
      }
      contents.add(revision.content!);
    }
    return contents;
  }

  Future<void> createForShift(
    TxSession tx,
    PlatformActor actor, {
    required String shiftId,
    required String employeeId,
    required String locationId,
    required List<ShiftTemplateSelection> selections,
  }) async {
    final contents = await validateSelections(tx, locationId, selections);
    for (var i = 0; i < selections.length; i++) {
      final id = newUuid();
      await _instances.insert(
        tx,
        id: id,
        shiftId: shiftId,
        employeeId: employeeId,
        locationId: locationId,
        selection: selections[i],
        position: i,
        content: contents[i],
      );
      await database.audit(
        tx,
        actor,
        'tasks.instance.created',
        'task_instance',
        id,
        locationId: locationId,
        changes: {
          'shiftId': shiftId,
          'employeeId': employeeId,
          'revisionId': selections[i].revisionId,
          'version': 1,
          'status': 'open',
        },
      );
    }
  }

  /// Read-only pre-execution gate: every instance must still be pristine open.
  Future<void> requireAllOpen(TxSession tx, {required String shiftId}) async {
    final tasks = await _instances.forShifts(tx, [shiftId]);
    for (final task in tasks) {
      if (task.status != 'open' || task.version != 1) {
        throw PlatformFailure(
          422,
          'shift_in_progress',
          'Task ${task.id} is no longer open; the shift cannot be amended.',
        );
      }
    }
  }

  Future<void> cancelForShift(
    TxSession tx,
    PlatformActor actor, {
    required String shiftId,
    required String locationId,
    required String reason,
    required DateTime now,
  }) async {
    final tasks = await _instances.forShifts(tx, [shiftId]);
    for (final task in tasks) {
      if (task.status != 'open' || task.version != 1) {
        throw PlatformFailure(
          422,
          'shift_in_progress',
          'Task ${task.id} is no longer open; the shift cannot be cancelled.',
        );
      }
    }
    for (final task in tasks) {
      if (!await _instances.cancelOpen(
        tx,
        id: task.id,
        actorId: actor.id,
        now: now,
      )) {
        throw const PlatformFailure(
          409,
          'shift_conflict',
          'The shift changed. Reload before continuing.',
        );
      }
      await database.audit(
        tx,
        actor,
        'tasks.instance.cancelled',
        'task_instance',
        task.id,
        locationId: locationId,
        changes: {
          'oldStatus': 'open',
          'status': 'cancelled',
          'oldVersion': 1,
          'version': 2,
          'origin': 'shift_cancellation',
          'shiftId': shiftId,
          'reason': reason,
        },
      );
    }
  }

  Future<List<TaskInstanceDto>> forShifts(TxSession tx, List<String> ids) =>
      _instances.forShifts(tx, ids);
  Future<TaskInstanceDto> detail(
    TxSession tx,
    String shiftId,
    String id,
  ) async {
    final rows = await _instances.forShifts(tx, [shiftId], detailId: id);
    if (rows.isEmpty) {
      throw const PlatformFailure(404, 'not_found', 'Task not found.');
    }
    return rows.single;
  }
}
