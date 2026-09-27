export 'shift.dart' show ShiftConflict, ShiftNotPublishable;
import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'shift.dart';
import 'shift_repository.dart';

/// Public workforce port. All calls participate in the coordinator's transaction.
class WorkforceService {
  WorkforceService(this.database)
    : _repository = ShiftRepository(database.schema, database.companyId);
  final PlatformDatabase database;
  final ShiftRepository _repository;
  Future<Shift> _get(TxSession tx, String id) async {
    final shift = await _repository.find(tx, id);
    if (shift == null) {
      throw const PlatformFailure(404, 'not_found', 'Shift not found.');
    }
    return shift;
  }

  Future<ShiftDto> get(TxSession tx, String id) async =>
      (await _get(tx, id)).view;
  Future<List<ShiftDto>> page(
    TxSession tx, {
    String? employeeId,
    String? locationId,
    DateTime? afterTime,
    String? afterId,
  }) async => (await _repository.page(
    tx,
    employeeId: employeeId,
    locationId: locationId,
    afterTime: afterTime,
    afterId: afterId,
  )).map((s) => s.view).toList();
  Future<ShiftDto?> creationRetry(
    TxSession tx,
    PlatformActor actor,
    String id,
    String location,
    ShiftDraftInput input,
  ) async {
    final old = await _repository.find(tx, id);
    if (old == null) return null;
    if (old.createdBy != actor.id ||
        old.view.locationId != location ||
        old.creationInput != jsonEncode(input.toJson())) {
      throw ShiftConflict();
    }
    return old.view;
  }

  Future<ShiftDto> create(
    TxSession tx,
    PlatformActor actor,
    String id,
    String location,
    ShiftDraftInput input,
  ) async {
    await _repository.insert(tx, id, location, actor.id, input);
    final result = await get(tx, id);
    await _audit(tx, actor, result, 'created');
    return result;
  }

  Future<ShiftDto> edit(
    TxSession tx,
    PlatformActor actor,
    String id,
    int version,
    ShiftDraftInput input,
  ) async {
    final current = await _get(tx, id);
    current.requireEditable(version);
    if (current.matches(input)) return current.view;
    await _repository.edit(tx, current, input);
    final result = await get(tx, id);
    await _audit(tx, actor, result, 'draft_updated', before: current.view);
    return result;
  }

  Future<bool> checkPublication(TxSession tx, String id, int version) async {
    final current = await _get(tx, id);
    if (current.repeatsPublication(version)) return true;
    current.requireEditable(version);
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    current.requirePublishable(now);
    if (await _repository.overlaps(tx, current)) {
      throw const PlatformFailure(
        409,
        'shift_overlap',
        'A published shift overlaps this interval.',
      );
    }
    return false;
  }

  Future<ShiftDto> publish(TxSession tx, PlatformActor actor, String id) async {
    final current = await _get(tx, id);
    await _repository.publish(tx, current, actor.id);
    final result = await get(tx, id);
    await _audit(tx, actor, result, 'published');
    return result;
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    ShiftDto shift,
    String action, {
    ShiftDto? before,
  }) => database.audit(
    tx,
    actor,
    'workforce.shift.$action',
    'shift',
    shift.id,
    locationId: shift.locationId,
    changes: {
      'employeeId': shift.draft.employeeId,
      'startsAt': shift.draft.startsAt.toIso8601String(),
      'endsAt': shift.draft.endsAt.toIso8601String(),
      'revisionIds': shift.draft.selections.map((s) => s.revisionId).toList(),
      'version': shift.version,
      'status': shift.status,
      if (before != null)
        'changedFields': [
          if (before.draft.employeeId != shift.draft.employeeId) 'employeeId',
          if (before.draft.startsAt != shift.draft.startsAt) 'startsAt',
          if (before.draft.endsAt != shift.draft.endsAt) 'endsAt',
          if (jsonEncode(before.draft.toJson()['selections']) !=
              jsonEncode(shift.draft.toJson()['selections']))
            'selections',
        ],
    },
  );
}
