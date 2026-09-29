import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'task_execution.dart';
import 'task_execution_repository.dart';
import 'task_instance_repository.dart';

/// Public Tasks port; authorization and shift context come from the coordinator.
class TaskExecutionService {
  TaskExecutionService(this.database)
    : _repository = TaskExecutionRepository(
        database.schema,
        database.companyId,
      ),
      _instances = TaskInstanceRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final TaskExecutionRepository _repository;
  final TaskInstanceRepository _instances;
  Future<TaskExecutionDto> get(TxSession tx, String id) async =>
      await _repository.get(tx, id) ??
      (throw const PlatformFailure(404, 'not_found', 'Task not found.'));
  Future<Map<String, dynamic>> running(
    TxSession tx,
    String employee,
    String location,
    String? after,
  ) async {
    final ids = await _repository.running(tx, employee, location, after);
    final page = ids.take(50).toList();
    return {
      'items': (await _instances.byIds(
        tx,
        page,
      )).map((t) => t.toJson()).toList(),
      'nextCursor': ids.length > 50 ? page.last : null,
    };
  }

  Future<Map<String, dynamic>> exceptions(
    TxSession tx,
    String? employee,
    String location,
    String? after,
    String status,
  ) async {
    final ids = await _repository.exceptions(
          tx,
          employee,
          location,
          after,
          status,
        ),
        page = <String>[];
    page.addAll(ids.take(50));
    return {
      'items': (await _instances.byIds(
        tx,
        page,
      )).map((v) => v.toJson()).toList(),
      'nextCursor': ids.length > 50 ? page.last : null,
    };
  }

  Future<Map<String, dynamic>> history(
    TxSession tx,
    String instance,
    int? before,
  ) async {
    final rows = await _repository.history(tx, instance, before),
        page = rows.take(50).toList();
    return {
      'items': page.map((v) => v.toJson()).toList(),
      'nextCursor': rows.length > 50
          ? page.last.reportedVersion.toString()
          : null,
    };
  }

  Future<Map<String, dynamic>> numbers(
    TxSession tx,
    String instance,
    int? before,
  ) async {
    final rows = await _repository.numbers(tx, instance, before),
        page = rows.take(50).toList();
    return {
      'items': page.map((v) => v.toJson()).toList(),
      'nextCursor': rows.length > 50
          ? page.last.acceptedVersion.toString()
          : null,
    };
  }

  Future<TaskExecutionDto> execute(
    TxSession tx,
    PlatformActor actor,
    TaskInstanceDto task,
    ShiftDto shift,
    String command,
    String operation,
    int expectedVersion,
    String? stepId,
    DateTime now, {
    String? reason,
    String? value,
    Future<void> Function()? checkResume,
  }) async {
    final input = jsonEncode({
      'command': command,
      'expectedVersion': expectedVersion,
      'stepId': stepId,
      'reason': ?reason,
      'value': ?value,
    });
    final receipt = await _repository.receipt(tx, operation);
    if (receipt != null) {
      if (receipt['company_id'] != actor.companyId ||
          receipt['actor_id'] != actor.id ||
          receipt['instance_id'] != task.id ||
          receipt['input'] != input) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Operation ID is already bound to another command.',
        );
      }
      return TaskExecutionDto.fromJson(
        jsonDecode(receipt['result'] as String) as Map<String, dynamic>,
      );
    }
    final current = await get(tx, task.id);
    try {
      TaskExecution(current, task.content!).validate(
        command,
        expectedVersion,
        stepId,
        now,
        shift.draft.startsAt,
        shift.draft.endsAt,
      );
    } on ExecutionConflict {
      throw const PlatformFailure(
        409,
        'execution_conflict',
        'Execution state changed. Reload before continuing.',
      );
    } on InvalidExecution {
      throw const PlatformFailure(
        422,
        'invalid_execution',
        'Confirm every step in order before completing.',
      );
    } on OutsideShift {
      throw const PlatformFailure(
        422,
        'outside_shift',
        'Start is only allowed during the published shift.',
      );
    }
    String? attemptId;
    bool? inRange;
    if (command == 'record-number') {
      final step = task.content!.steps[current.results.length];
      inRange = TaskExecution(
        current,
        task.content!,
      ).acceptsNumber(step, taskNumber(value));
      attemptId = newUuid();
      await _repository.recordNumber(
        tx,
        TaskNumericAttemptDto(
          id: attemptId,
          instanceId: task.id,
          stepId: step.id,
          value: value!,
          inRange: inRange,
          recordedAt: now,
          recordedBy: actor.id,
          acceptedVersion: current.version + 1,
        ),
        shift.locationId,
      );
      command = inRange ? 'confirm' : 'block';
      if (!inRange) reason = 'Zahlenwert außerhalb der erlaubten Grenzen.';
      await database.audit(
        tx,
        actor,
        'tasks.step.number_recorded',
        'task_instance',
        task.id,
        locationId: shift.locationId,
        changes: {
          'operationId': operation,
          'attemptId': attemptId,
          'stepId': step.id,
          'revisionId': task.revisionId,
          'version': current.version + 1,
          'inRange': inRange,
        },
      );
    }
    String? blockingId;
    if (command == 'block') {
      blockingId = newUuid();
      stepId = current.results.length < task.content!.steps.length
          ? task.content!.steps[current.results.length].id
          : null;
      await _repository.block(
        tx,
        current,
        blockingId,
        stepId,
        reason!,
        actor.id,
        shift.locationId,
        now,
        numericAttemptId: attemptId,
      );
    } else if (command == 'resume' || command == 'cancel') {
      if (command == 'resume') await checkResume!();
      blockingId = current.activeBlockingId;
      await _repository.resolve(
        tx,
        current,
        reason!,
        actor.id,
        now,
        command == 'cancel' ? 'cancelled' : 'resumed',
      );
    }
    await _repository.apply(
      tx,
      current,
      command,
      stepId,
      actor.id,
      shift.locationId,
      now,
      numericAttemptId: attemptId,
    );
    final result = await get(tx, task.id);
    final action = switch (command) {
      'start' => 'tasks.instance.started',
      'confirm' => 'tasks.step.confirmed',
      'block' => 'tasks.instance.blocked',
      'resume' => 'tasks.instance.resumed',
      'cancel' => 'tasks.instance.cancelled',
      _ => 'tasks.instance.completed',
    };
    await database.audit(
      tx,
      actor,
      action,
      'task_instance',
      task.id,
      locationId: shift.locationId,
      changes: {
        'operationId': operation,
        'oldVersion': current.version,
        'version': result.version,
        'oldStatus': current.status,
        'status': result.status,
        'stepId': ?stepId,
        'blockingId': ?blockingId,
        'attemptId': ?attemptId,
        'inRange': ?inRange,
      },
    );
    await _repository.remember(
      tx,
      operation,
      actor.id,
      shift.locationId,
      task.id,
      input,
      result,
    );
    return result;
  }
}
