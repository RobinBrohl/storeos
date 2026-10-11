import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'task_template_repository.dart';
import 'task_instance_repository.dart';
import '../knowledge/knowledge_guidance_port.dart';
import '../merchandising/planogram_guidance_port.dart';

/// Tasks owns selection validation and snapshots; no workforce table access.
class TaskInstanceService {
  TaskInstanceService(this.database)
    : _templates = TaskTemplateRepository(database.schema, database.companyId),
      _instances = TaskInstanceRepository(database.schema, database.companyId),
      _knowledge = KnowledgeGuidancePort(database),
      _planogram = PlanogramGuidancePort(database);
  final PlatformDatabase database;
  final TaskTemplateRepository _templates;
  final TaskInstanceRepository _instances;
  final KnowledgeGuidancePort _knowledge;
  final PlanogramGuidancePort _planogram;

  /// Bounded transfer projection deliberately omits all execution evidence.
  Future<List<Map<String, dynamic>>> transferSummary(
    TxSession tx,
    String shift,
  ) async {
    final items = await _instances.forShifts(tx, [shift]);
    return [
      for (final t in items)
        {
          'id': t.id,
          'title': t.title,
          'templateId': t.templateId,
          'revisionId': t.revisionId,
          'position': t.position,
          'knowledgeGuidance': (await detail(
            tx,
            shift,
            t.id,
          )).content!.knowledgeGuidance?.toJson(),
          'planogramGuidance': (await detail(
            tx,
            shift,
            t.id,
          )).content!.planogramGuidance?.toJson(),
        },
    ];
  }

  Future<void> validateTransfer(
    TxSession tx,
    ShiftDto shift, {
    PlatformActor? publisher,
  }) async {
    await requireAllOpen(tx, shiftId: shift.id);
    final items = await _instances.forShifts(tx, [shift.id]);
    if (items.isEmpty ||
        items.length != shift.draft.selections.length ||
        items.length > 10 ||
        !await _instances.pristine(tx, shift.id)) {
      throw const PlatformFailure(
        422,
        'shift_in_progress',
        'The complete Task set must remain pristine.',
      );
    }
    for (var i = 0; i < items.length; i++) {
      final item = items[i], selection = shift.draft.selections[i];
      if (item.position != i ||
          item.templateId != selection.templateId ||
          item.revisionId != selection.revisionId) {
        throw const PlatformFailure(
          422,
          'shift_not_transferable',
          'Source work identity is inconsistent.',
        );
      }
      if (publisher != null) {
        final content = (await detail(tx, shift.id, item.id)).content!;
        if (content.knowledgeGuidance case final pin?) {
          await _knowledge.validatePublication(tx, publisher, pin);
        }
        if (content.planogramGuidance case final pin?) {
          await _planogram.validatePublication(
            tx,
            publisher,
            shift.locationId,
            pin,
          );
        }
      }
    }
  }

  Future<void> createTransferReplacement(
    TxSession tx,
    PlatformActor actor, {
    required ShiftDto source,
    required String requestId,
    required String replacementShiftId,
    required String recipient,
  }) async {
    await createForShift(
      tx,
      actor,
      shiftId: replacementShiftId,
      employeeId: recipient,
      locationId: source.locationId,
      selections: source.draft.selections,
    );
    final originals = await _instances.forShifts(tx, [source.id]);
    final replacements = await _instances.forShifts(tx, [replacementShiftId]);
    if (originals.length != replacements.length || originals.isEmpty) {
      throw StateError('Incomplete transfer work');
    }
    for (var i = 0; i < originals.length; i++) {
      final a = await detail(tx, source.id, originals[i].id),
          b = await detail(tx, replacementShiftId, replacements[i].id);
      if (a.templateId != b.templateId ||
          a.revisionId != b.revisionId ||
          a.position != b.position ||
          jsonEncode(a.content!.toJson()) != jsonEncode(b.content!.toJson())) {
        throw StateError('Transfer snapshots differ');
      }
      await _instances.linkTransfer(tx, source.locationId, requestId, a, b);
    }
  }

  Future<List<Map<String, dynamic>>> transferLinks(
    TxSession tx,
    String location,
    String request,
  ) => _instances.transferLinks(tx, location, request);
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
    // Validate the complete selection before materialization, within the same
    // authorized Company transaction that serializes guidance/deployment writers.
    for (final content in contents) {
      if (content.knowledgeGuidance case final pin?) {
        await _knowledge.validatePublication(tx, actor, pin);
      }
      if (content.planogramGuidance case final pin?) {
        await _planogram.validatePublication(tx, actor, locationId, pin);
      }
    }
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
          if (contents[i].knowledgeGuidance case final pin?) ...{
            'knowledgeArticleId': pin.articleId,
            'knowledgeRevisionId': pin.revisionId,
          },
          if (contents[i].planogramGuidance case final pin?) ...{
            'fixtureId': pin.fixtureId,
            'planogramAssignmentId': pin.assignmentId,
            'planogramRevisionId': pin.revisionId,
          },
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
