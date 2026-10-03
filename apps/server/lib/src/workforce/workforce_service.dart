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
    await _mapOverlapConstraint(
      () => _repository.publish(tx, current, actor.id),
    );
    final result = await get(tx, id);
    await _audit(tx, actor, result, 'published');
    return result;
  }

  /// Maps only the published-shift exclusion constraint to the friendly
  /// overlap conflict; every other exclusion or integrity failure is rethrown.
  Future<void> _mapOverlapConstraint(Future<void> Function() action) async {
    try {
      await action();
    } on ServerException catch (error) {
      if (error.code == '23P01' &&
          error.constraintName == 'shifts_published_no_overlap') {
        throw const PlatformFailure(
          409,
          'shift_overlap',
          'A published shift overlaps this interval.',
        );
      }
      rethrow;
    }
  }

  Future<void> checkAmendOverlap(
    TxSession tx,
    ShiftDto current,
    DateTime startsAt,
    DateTime endsAt,
  ) async {
    if (await _repository.overlapsWindow(
      tx,
      current.id,
      current.draft.employeeId,
      startsAt,
      endsAt,
    )) {
      throw const PlatformFailure(
        409,
        'shift_overlap',
        'A published shift overlaps this interval.',
      );
    }
  }

  Future<ShiftDto> amend(
    TxSession tx,
    PlatformActor actor,
    String id,
    int expectedVersion,
    DateTime startsAt,
    DateTime endsAt,
    Future<DateTime> Function() preWriteCheck,
  ) async {
    final current = await _get(tx, id);
    if (current.repeatsAmendment(expectedVersion, actor.id, startsAt, endsAt)) {
      return current.view;
    }
    current.requireAmendable(expectedVersion);
    if (current.matchesAmendment(startsAt, endsAt)) return current.view;
    final now = await preWriteCheck();
    await _mapOverlapConstraint(
      () => _repository.amend(tx, current, actor.id, startsAt, endsAt, now),
    );
    final result = await get(tx, id);
    await _audit(tx, actor, result, 'amended', before: current.view);
    return result;
  }

  Future<ShiftDto> cancel(
    TxSession tx,
    PlatformActor actor,
    String id,
    int expectedVersion,
    String reason,
    DateTime now,
  ) async {
    final current = await _get(tx, id);
    if (current.view.status == 'cancelled') {
      if (current.view.cancellationVersion == expectedVersion &&
          current.view.cancelledBy == actor.id &&
          current.view.cancellationReason == reason) {
        return current.view;
      }
      throw ShiftConflict();
    }
    current.requireCancellable(expectedVersion);
    await _repository.cancel(tx, current, actor.id, reason, now);
    final result = await get(tx, id);
    await _audit(
      tx,
      actor,
      result,
      'cancelled',
      before: current.view,
      reason: reason,
    );
    return result;
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    ShiftDto shift,
    String action, {
    ShiftDto? before,
    String? reason,
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
      if (action == 'cancelled' && before != null) 'oldStatus': before.status,
      if (action == 'cancelled' && before != null) 'oldVersion': before.version,
      if (action == 'amended' && before != null)
        'oldStartsAt': before.draft.startsAt.toIso8601String(),
      if (action == 'amended' && before != null)
        'oldEndsAt': before.draft.endsAt.toIso8601String(),
      'reason': ?reason,
      'cancellationVersion': ?shift.cancellationVersion,
      'amendmentVersion': ?shift.amendmentVersion,
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
