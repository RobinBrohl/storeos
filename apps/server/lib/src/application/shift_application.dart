import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';
import '../tasks/task_instance_service.dart';
import '../tasks/task_execution_service.dart';
import '../workforce/workforce_service.dart';

/// Coordinates public ports, authorization and one shared local transaction.
class ShiftApplication {
  ShiftApplication(this.database)
    : _workforce = WorkforceService(database),
      _tasks = TaskInstanceService(database),
      _execution = TaskExecutionService(database),
      _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final WorkforceService _workforce;
  final TaskInstanceService _tasks;
  final TaskExecutionService _execution;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;
  Future<Map<String, dynamic>> _run(
    SessionPrincipal p,
    String permission,
    Future<Map<String, dynamic>> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(p, permission, action);
    } on ShiftConflict {
      throw const PlatformFailure(
        409,
        'shift_conflict',
        'The shift changed or is already published.',
      );
    } on ShiftNotPublishable {
      throw const PlatformFailure(
        422,
        'shift_not_publishable',
        'Select tasks and a shift that has not ended.',
      );
    }
  }

  ShiftDraftInput _input(Map<String, dynamic> input) {
    try {
      return ShiftDraftInput.fromJson(input);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_shift',
        'Invalid shift interval or selections.',
      );
    }
  }

  Future<void> _eligible(
    TxSession tx,
    String location,
    ShiftDraftInput input,
  ) async {
    await _organization.requireConfiguredLocation(tx, location);
    final employee = await _people.get(tx, input.employeeId);
    if (!employee.isActive ||
        employee.locationId != location ||
        employee.assignedFrom.isAfter(input.startsAt) ||
        (employee.assignedUntil != null &&
            employee.assignedUntil!.isBefore(input.endsAt))) {
      throw const PlatformFailure(
        422,
        'employee_unavailable',
        'Employee assignment does not cover the shift.',
      );
    }
  }

  Future<String> _self(TxSession tx, PlatformActor actor) async {
    final link = await _links.forAccount(tx, actor.id);
    if (actor.locationId != database.locationId ||
        link == null ||
        link.companyId != actor.companyId ||
        link.locationId != actor.locationId) {
      throw const PlatformFailure(
        404,
        'employee_unavailable',
        'No active employee profile.',
      );
    }
    final person = await _people.get(tx, link.employeeId);
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    if (!person.isActive ||
        person.assignedFrom.isAfter(now) ||
        (person.assignedUntil != null &&
            !now.isBefore(person.assignedUntil!)) ||
        person.companyId != actor.companyId ||
        person.locationId != actor.locationId) {
      throw const PlatformFailure(
        404,
        'employee_unavailable',
        'No active employee profile.',
      );
    }
    return person.id;
  }

  void _require(PlatformActor actor, String permission) {
    if (!permissionsForRole(actor.role).contains(permission)) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
  }

  Future<Map<String, dynamic>> _detail(TxSession tx, ShiftDto shift) async => {
    'shift': shift.toJson(),
    'tasks': (await _tasks.forShifts(tx, [
      shift.id,
    ])).map((t) => t.toJson()).toList(),
  };
  Future<Map<String, dynamic>> create(
    SessionPrincipal p,
    Map<String, dynamic> input,
  ) {
    requireFields(
      input,
      required: {
        'id',
        'locationId',
        'employeeId',
        'startsAt',
        'endsAt',
        'selections',
      },
    );
    final id = requireUuid(input, 'id'),
        location = requireUuid(input, 'locationId'),
        draft = _input(input);
    return _run(p, 'workforce.shifts.manage', (tx, actor) async {
      final retry = await _workforce.creationRetry(
        tx,
        actor,
        id,
        location,
        draft,
      );
      if (retry != null) return _detail(tx, retry);
      await _eligible(tx, location, draft);
      await _tasks.validateSelections(tx, location, draft.selections);
      return _detail(
        tx,
        await _workforce.create(tx, actor, id, location, draft),
      );
    });
  }

  Future<Map<String, dynamic>> edit(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(
      input,
      required: {
        'expectedVersion',
        'employeeId',
        'startsAt',
        'endsAt',
        'selections',
      },
    );
    final version = requireVersion(input), draft = _input(input);
    return _run(p, 'workforce.shifts.manage', (tx, actor) async {
      final shift = await _workforce.get(tx, id);
      await _eligible(tx, shift.locationId, draft);
      await _tasks.validateSelections(tx, shift.locationId, draft.selections);
      return _detail(tx, await _workforce.edit(tx, actor, id, version, draft));
    });
  }

  Future<Map<String, dynamic>> publish(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(input, required: {'expectedVersion'});
    final version = requireVersion(input);
    return _run(p, 'workforce.shifts.manage', (tx, actor) async {
      _require(actor, 'tasks.instances.read');
      final shift = await _workforce.get(tx, id);
      if (await _workforce.checkPublication(tx, id, version)) {
        return _detail(tx, shift);
      }
      await _eligible(tx, shift.locationId, shift.draft);
      await _tasks.createForShift(
        tx,
        actor,
        shiftId: id,
        employeeId: shift.draft.employeeId,
        locationId: shift.locationId,
        selections: shift.draft.selections,
      );
      return _detail(tx, await _workforce.publish(tx, actor, id));
    });
  }

  Future<ShiftDto> _visible(
    TxSession tx,
    PlatformActor actor,
    String id,
    bool self,
  ) async {
    final employee = self ? await _self(tx, actor) : null;
    final shift = await _workforce.get(tx, id);
    if (self &&
        (shift.status != 'published' ||
            shift.draft.employeeId != employee ||
            shift.locationId != actor.locationId)) {
      throw const PlatformFailure(404, 'not_found', 'Shift not found.');
    }
    return shift;
  }

  Future<Map<String, dynamic>> get(
    SessionPrincipal p,
    String id, {
    bool self = false,
    String? taskId,
  }) {
    id = requireUuid({'id': id}, 'id');
    if (taskId != null) taskId = requireUuid({'id': taskId}, 'id');
    final detailId = taskId;
    return _run(
      p,
      self ? 'workforce.shifts.self.read' : 'workforce.shifts.manage',
      (tx, actor) async {
        _require(
          actor,
          self ? 'tasks.instances.self.read' : 'tasks.instances.read',
        );
        final shift = await _visible(tx, actor, id, self);
        return detailId == null
            ? await _detail(tx, shift)
            : (await _tasks.detail(tx, id, detailId)).toJson();
      },
    );
  }

  Future<Map<String, dynamic>> running(SessionPrincipal p, {String? after}) {
    if (after != null) after = requireUuid({'id': after}, 'id');
    final cursor = after;
    return _run(p, 'tasks.instances.self.read', (tx, actor) async {
      final employee = await _self(tx, actor);
      return _execution.running(tx, employee, actor.locationId, cursor);
    });
  }

  Future<Map<String, dynamic>> execution(
    SessionPrincipal p,
    String shiftId,
    String taskId, {
    bool self = true,
  }) {
    shiftId = requireUuid({'id': shiftId}, 'id');
    taskId = requireUuid({'id': taskId}, 'id');
    return _run(
      p,
      self ? 'tasks.instances.self.read' : 'tasks.instances.read',
      (tx, actor) async {
        await _visible(tx, actor, shiftId, self);
        await _tasks.detail(tx, shiftId, taskId);
        return (await _execution.get(tx, taskId)).toJson();
      },
    );
  }

  Future<Map<String, dynamic>> execute(
    SessionPrincipal p,
    String shiftId,
    String taskId,
    String command,
    Map<String, dynamic> input, {
    String? stepId,
  }) {
    shiftId = requireUuid({'id': shiftId}, 'id');
    taskId = requireUuid({'id': taskId}, 'id');
    if (stepId != null) stepId = requireUuid({'id': stepId}, 'id');
    requireFields(input, required: {'operationId', 'expectedVersion'});
    final operation = requireUuid(input, 'operationId'),
        version = requireVersion(input),
        step = stepId;
    return _run(p, 'tasks.instances.self.execute', (tx, actor) async {
      final shift = await _visible(tx, actor, shiftId, true);
      final task = await _tasks.detail(tx, shiftId, taskId);
      final now =
          (await tx.execute('SELECT clock_timestamp()')).single.first
              as DateTime;
      return (await _execution.execute(
        tx,
        actor,
        task,
        shift,
        command,
        operation,
        version,
        step,
        now,
      )).toJson();
    });
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal p, {
    bool self = false,
    String? after,
  }) {
    DateTime? time;
    String? id;
    if (after != null) {
      try {
        final parts =
            jsonDecode(
                  utf8.decode(base64Url.decode(base64Url.normalize(after))),
                )
                as List;
        if (parts.length != 2) throw const FormatException();
        time = shiftInstant(parts[0]);
        id = shiftUuid(parts[1]);
      } catch (_) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid shift cursor.',
        );
      }
    }
    return _run(
      p,
      self ? 'workforce.shifts.self.read' : 'workforce.shifts.manage',
      (tx, actor) async {
        _require(
          actor,
          self ? 'tasks.instances.self.read' : 'tasks.instances.read',
        );
        final employee = self ? await _self(tx, actor) : null;
        final rows = await _workforce.page(
          tx,
          employeeId: employee,
          locationId: self ? actor.locationId : null,
          afterTime: time,
          afterId: id,
        );
        final items = rows.take(50).toList();
        final tasks = await _tasks.forShifts(
          tx,
          items.map((s) => s.id).toList(),
        );
        return {
          'items': [
            for (final shift in items)
              {
                'shift': shift.toJson(),
                'tasks': tasks
                    .where((t) => t.shiftId == shift.id)
                    .map((t) => t.toJson())
                    .toList(),
              },
          ],
          'nextCursor': rows.length > 50
              ? base64Url.encode(
                  utf8.encode(
                    jsonEncode([
                      items.last.draft.startsAt.toIso8601String(),
                      items.last.id,
                    ]),
                  ),
                )
              : null,
        };
      },
    );
  }
}
