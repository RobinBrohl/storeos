import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../tasks/task_instance_service.dart';
import '../workforce/workforce_service.dart';
import '../workforce/shift_swap_service.dart';
import '../workforce/shift_handoff_claim_service.dart';

/// Every command uses one authorized Company transaction and public owner ports.
class ShiftSwapApplication {
  ShiftSwapApplication(this.database)
    : _swaps = ShiftSwapService(database),
      _claims = ShiftHandoffClaimService(database),
      _workforce = WorkforceService(database),
      _tasks = TaskInstanceService(database),
      _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final ShiftSwapService _swaps;
  final ShiftHandoffClaimService _claims;
  final WorkforceService _workforce;
  final TaskInstanceService _tasks;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;
  static const _active = {'requested', 'offered', 'confirmed'};

  Future<T> _run<T>(
    SessionPrincipal p,
    String capability,
    Future<T> Function(TxSession, PlatformActor) work, {
    String? location,
    String? commandKind,
  }) async {
    try {
      return await database.runAuthorized(p, capability, (tx, actor) async {
        if (actor.locationId != database.locationId ||
            (location != null && shiftUuid(location) != database.locationId)) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Configured execution Location required.',
          );
        }
        await _organization.requireConfiguredLocation(tx, database.locationId);
        return work(tx, actor);
      });
    } on ShiftHandoffConflict {
      throw const PlatformFailure(
        409,
        'swap_already_pending',
        'Close the existing handoff request first.',
      );
    } on SwapInputException catch (e) {
      throw PlatformFailure(400, 'invalid_request', e.message);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid swap request.',
      );
    } on ShiftConflict {
      throw const PlatformFailure(
        409,
        'shift_conflict',
        'Captured Shift changed.',
      );
    } on ShiftNotPublishable {
      throw const PlatformFailure(
        422,
        'shift_not_swappable',
        'Swap requires pristine future work.',
      );
    } on ServerException catch (e) {
      if (e.code == '23514' &&
          e.constraintName == 'swap_leg_future' &&
          {'request', 'offer'}.contains(commandKind)) {
        throw const PlatformFailure(
          422,
          'shift_not_swappable',
          'Swap requires future work at leg capture.',
        );
      }
      if (e.code == '23514' && e.constraintName == 'swap_approval_future') {
        throw const PlatformFailure(
          422,
          'shift_not_swappable',
          'Swap requires future originals at final validation.',
        );
      }
      if (e.code == '23505' &&
          {
            'workforce_shift_swap_requests_pkey',
            'workforce_shift_swap_commands_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Swap operation identity already exists.',
        );
      }
      if (e.code == '23P01' &&
          e.constraintName == 'shifts_published_no_overlap') {
        throw const PlatformFailure(
          409,
          'shift_overlap',
          'Final roster has overlapping published work.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Swap database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Swap database unavailable.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Swap database unavailable.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Swap database unavailable.',
      );
    } on StateError catch (e) {
      final unavailable =
          e.message == 'request() may not be called on a closed Pool.';
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Swap evidence could not be verified.',
      );
    }
  }

  void _require(PlatformActor actor, String capability) {
    if (!permissionsForRole(actor.role).contains(capability)) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
  }

  Future<DateTime> _now(TxSession tx) async =>
      (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;

  Future<EmployeeLinkDto> _self(TxSession tx, PlatformActor actor) async {
    final link = await _links.forAccount(tx, actor.id);
    if (link == null ||
        link.companyId != actor.companyId ||
        link.locationId != actor.locationId ||
        await _links.swapAccountVersion(tx, link) == null) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Current Employee unavailable.',
      );
    }
    final person = await _people.get(tx, link.employeeId), now = await _now(tx);
    if (!person.isActive ||
        person.locationId != actor.locationId ||
        person.assignedFrom.isAfter(now) ||
        (person.assignedUntil != null &&
            !now.isBefore(person.assignedUntil!))) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Current Employee unavailable.',
      );
    }
    return link;
  }

  Future<Map<String, dynamic>> _get(
    TxSession tx,
    String id, {
    String? employee,
  }) async {
    final r = await _swaps.find(tx, shiftUuid(id));
    if (r == null ||
        (employee != null &&
            r['source_employee_id'] != employee &&
            r['recipient_employee_id'] != employee)) {
      throw const PlatformFailure(404, 'not_found', 'Swap not found.');
    }
    return r;
  }

  Future<ShiftDto> _own(TxSession tx, String id, String employee) async {
    final s = await _workforce.get(tx, id);
    if (s.companyId != database.companyId ||
        s.locationId != database.locationId ||
        s.draft.employeeId != employee) {
      throw const PlatformFailure(404, 'not_found', 'Shift not found.');
    }
    return s;
  }

  Future<void> _eligible(TxSession tx, ShiftDto shift, String employee) async {
    EmployeeDto person;
    try {
      person = await _people.get(tx, employee);
    } on PlatformFailure catch (e) {
      if (e.status != 404) rethrow;
      throw const PlatformFailure(
        422,
        'employee_unavailable',
        'Employee assignment unavailable.',
      );
    }
    if (!person.isActive ||
        person.companyId != database.companyId ||
        person.locationId != database.locationId ||
        person.assignedFrom.isAfter(shift.draft.startsAt) ||
        (person.assignedUntil != null &&
            person.assignedUntil!.isBefore(shift.draft.endsAt))) {
      throw const PlatformFailure(
        422,
        'employee_unavailable',
        'Employee assignment must cover the exact interval.',
      );
    }
  }

  Future<void> _future(TxSession tx, ShiftDto shift) async {
    if (shift.status != 'published' ||
        !shift.draft.startsAt.isAfter(await _now(tx))) {
      throw const PlatformFailure(
        422,
        'shift_not_swappable',
        'Swap requires a future published Shift.',
      );
    }
  }

  Future<void> _bound(TxSession tx, Map<String, dynamic> r) async {
    for (final prefix in ['source', 'recipient']) {
      if (!await _links.matchesSwapIdentityBasis(
        tx,
        employeeId: r['${prefix}_employee_id'] as String,
        accountId: r['${prefix}_account_id'] as String,
        linkId: r['${prefix}_link_id'] as String,
        accountVersion: r['${prefix}_account_version'] as int,
      )) {
        throw const PlatformFailure(
          422,
          'employee_unavailable',
          'Captured identity basis changed; close this request.',
        );
      }
    }
  }

  Future<void> _ownedClaims(
    TxSession tx,
    Map<String, dynamic> r,
    int count,
  ) async {
    if (!await _claims.ownsSwap(tx, r['id'] as String, count)) {
      throw StateError('Exact owned swap claims required.');
    }
  }

  List<Map<String, dynamic>> _refs(Map<String, dynamic> l) =>
      (l['work_references'] as List)
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList();

  Future<ShiftDto> _freshLeg(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> l,
  ) async {
    final s = await _workforce.get(tx, l['source_shift_id'] as String);
    if (s.companyId != database.companyId ||
        s.locationId != database.locationId ||
        s.version != l['source_version'] ||
        s.draft.employeeId != l['source_employee_id'] ||
        s.draft.startsAt != l['starts_at'] ||
        s.draft.endsAt != l['ends_at']) {
      throw const PlatformFailure(
        409,
        'shift_conflict',
        'Captured Shift identity changed.',
      );
    }
    await _future(tx, s);
    await _eligible(tx, s, l['source_employee_id'] as String);
    await _eligible(tx, s, l['incoming_employee_id'] as String);
    await _tasks.validateSwapWork(
      tx,
      s,
      _refs(l),
      incoming: l['incoming_employee_id'] as String,
      publisher: actor,
    );
    return s;
  }

  Future<List<ShiftDto>> _fresh(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> r,
  ) async {
    final legs = await _swaps.legs(tx, r['id'] as String);
    final count = r['status'] == 'requested' ? 1 : 2;
    if (legs.length != count) throw StateError('Exact stored legs required.');
    await _ownedClaims(tx, r, count);
    await _bound(tx, r);
    final originals = [for (final l in legs) await _freshLeg(tx, actor, l)];
    if (count == 2 && await _workforce.overlapsSwap(tx, r['id'] as String)) {
      throw const PlatformFailure(
        409,
        'shift_overlap',
        'Final roster has overlapping published work.',
      );
    }
    return originals;
  }

  bool _captured(Map<String, dynamic> r, EmployeeLinkDto link, String prefix) =>
      r['${prefix}_employee_id'] == link.employeeId &&
      r['${prefix}_account_id'] == link.accountId &&
      r['${prefix}_link_id'] == link.id;

  /// Role derives from command intent, including historical decline stage, so
  /// receipt authorization never depends on today's terminal lifecycle.
  void _authorizeCommand(
    PlatformActor actor,
    EmployeeLinkDto? link,
    Map<String, dynamic>? r,
    ShiftSwapCommandInput c,
    bool self,
  ) {
    if (!self) {
      if (!{'manager_approve', 'manager_reject'}.contains(c.kind)) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Manager command required.',
        );
      }
      if (c.kind == 'manager_approve') {
        _require(actor, 'workforce.shifts.manage');
        _require(actor, 'tasks.instances.read');
        if ({
          r!['source_account_id'],
          r['recipient_account_id'],
        }.contains(actor.id)) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Independent manager required.',
          );
        }
      }
      return;
    }
    _require(actor, 'workforce.swaps.self.read');
    _require(
      actor,
      c.kind == 'request' || c.kind == 'source_withdraw'
          ? 'workforce.swaps.self.request'
          : 'workforce.swaps.self.respond',
    );
    if (c.kind == 'request') return;
    final source =
        c.kind == 'confirm' ||
        c.kind == 'source_withdraw' ||
        (c.kind == 'decline' && c.expectedVersion == 2);
    final allowed = {
      'offer',
      'confirm',
      'decline',
      'source_withdraw',
      'recipient_withdraw',
    }.contains(c.kind);
    if (!allowed ||
        (c.kind == 'source_withdraw'
            ? r!['source_employee_id'] != link!.employeeId
            : !_captured(r!, link!, source ? 'source' : 'recipient'))) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Swap response unavailable.',
      );
    }
  }

  Future<ShiftSwapDto> _evidence(TxSession tx, Map<String, dynamic> r) async {
    String? instant(Object? v) =>
        v == null ? null : (v as DateTime).toUtc().toIso8601String();
    final request = r['id'] as String, legs = await _swaps.legs(tx, request);
    final json = <String, dynamic>{
      'id': request,
      'companyId': r['company_id'],
      'locationId': r['location_id'],
      'sourceEmployeeId': r['source_employee_id'],
      'recipientEmployeeId': r['recipient_employee_id'],
      'sourceName': (await _people.get(
        tx,
        r['source_employee_id'] as String,
      )).displayName,
      'recipientName': (await _people.get(
        tx,
        r['recipient_employee_id'] as String,
      )).displayName,
      'status': r['status'],
      'version': r['version'],
      'requestedAt': instant(r['requested_at']),
      'requestOperationId': r['request_operation_id'],
      'offeredAt': instant(r['offered_at']),
      'offerOperationId': r['offer_operation_id'],
      'confirmedAt': instant(r['confirmed_at']),
      'confirmationOperationId': r['confirmation_operation_id'],
      'terminalAt': instant(r['terminal_at']),
      'terminalOperationId': r['terminal_operation_id'],
      'terminalKind': r['terminal_kind'],
      'terminalReason': r['terminal_reason'],
      'legs': [
        for (final l in legs)
          {
            'leg': l['leg'],
            'sourceShiftId': l['source_shift_id'],
            'sourceVersion': l['source_version'],
            'sourceEmployeeId': l['source_employee_id'],
            'incomingEmployeeId': l['incoming_employee_id'],
            'startsAt': instant(l['starts_at']),
            'endsAt': instant(l['ends_at']),
            'tasks': l['work_references'],
            'replacementShiftId': l['replacement_shift_id'],
            'taskLinks': await _tasks.swapLinks(
              tx,
              request,
              l['leg'] as String,
            ),
          },
      ],
    };
    try {
      return ShiftSwapDto.fromJson(json);
    } on FormatException {
      throw StateError('Invalid persisted swap evidence.');
    }
  }

  Future<ShiftSwapCommandResult> command(
    SessionPrincipal p,
    String? id,
    String kind,
    Map<String, dynamic> body, {
    bool self = true,
    String? location,
  }) => _run(
    p,
    self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage',
    (tx, actor) => _command(tx, actor, id, kind, body, self: self),
    location: location,
    commandKind: kind,
  );

  /// Resolve the shared HTTP withdrawal intent from authorized stored ownership,
  /// before parsing/replay, inside the same transaction as the exact command.
  Future<ShiftSwapCommandResult> withdraw(
    SessionPrincipal p,
    String id,
    Map<String, dynamic> body,
  ) => _run(p, 'workforce.swaps.self.read', (tx, actor) async {
    final link = await _self(tx, actor);
    final r = await _get(tx, id, employee: link.employeeId);
    final source = r['source_employee_id'] == link.employeeId;
    if (!source && !_captured(r, link, 'recipient')) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Swap response unavailable.',
      );
    }
    return _command(
      tx,
      actor,
      id,
      source ? 'source_withdraw' : 'recipient_withdraw',
      body,
      self: true,
      link: link,
    );
  });

  Future<ShiftSwapCommandResult> _command(
    TxSession tx,
    PlatformActor actor,
    String? id,
    String kind,
    Map<String, dynamic> body, {
    required bool self,
    EmployeeLinkDto? link,
  }) async {
    final c = ShiftSwapCommandInput.fromJson(kind, body);
    if ((kind == 'request') != (id == null) || (kind == 'request' && !self)) {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid swap command target.',
      );
    }
    final request = kind == 'request'
        ? c.payload['requestId'] as String
        : shiftUuid(id);
    link ??= self ? await _self(tx, actor) : null;
    Map<String, dynamic>? r;
    ShiftDto? source;
    if (kind == 'request') {
      source = await _own(
        tx,
        c.payload['sourceShiftId'] as String,
        link!.employeeId,
      );
      r = await _swaps.find(tx, request);
      if (r != null && r['source_employee_id'] != link.employeeId) {
        throw const PlatformFailure(404, 'not_found', 'Swap not found.');
      }
    } else {
      r = await _get(tx, request, employee: link?.employeeId);
    }
    _authorizeCommand(actor, link, r, c, self);
    // Scope of a selected own counterpart also precedes receipt disclosure.
    final counterpart = kind == 'offer'
        ? await _own(
            tx,
            c.payload['counterpartShiftId'] as String,
            link!.employeeId,
          )
        : null;
    final replay = await _swaps.replay(tx, request, actor.id, c);
    if (replay != null) return replay;

    if (kind == 'request') {
      if (r != null) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Request identity already exists.',
        );
      }
      if (source!.version != c.expectedVersion) {
        throw const PlatformFailure(
          409,
          'shift_conflict',
          'Source Shift changed.',
        );
      }
      await _future(tx, source);
      await _eligible(tx, source, link!.employeeId);
      final recipientId = c.payload['recipientEmployeeId'] as String;
      if (recipientId == link.employeeId) {
        throw const PlatformFailure(
          422,
          'employee_unavailable',
          'Choose another eligible Employee.',
        );
      }
      await _eligible(tx, source, recipientId);
      final recipient = await _links.forEmployee(tx, recipientId);
      final sourceVersion = await _links.swapAccountVersion(tx, link),
          recipientVersion = recipient == null
              ? null
              : await _links.swapAccountVersion(tx, recipient);
      if (recipient == null ||
          sourceVersion == null ||
          recipientVersion == null) {
        throw const PlatformFailure(
          422,
          'employee_unavailable',
          'Participant identity unavailable.',
        );
      }
      await _tasks.validateTransfer(tx, source, publisher: actor);
      final refs = await _tasks.captureSwapWork(tx, source);
      await _swaps.request(
        tx,
        c,
        link,
        recipient,
        sourceVersion,
        recipientVersion,
      );
      await _swaps.captureLeg(tx, request, 'a', source, recipientId, refs);
      await _claims.claimSwapA(tx, request);
    } else {
      ShiftSwapRequest(
        status: r!['status'] as String,
        version: r['version'] as int,
        sourceAccount: r['source_account_id'] as String,
        recipientAccount: r['recipient_account_id'] as String,
      ).transition(
        c,
        actor.id,
        currentSourceAuthorized: kind == 'source_withdraw',
      );
      if (kind == 'offer') {
        await _fresh(tx, actor, r);
        if (counterpart!.version != c.payload['expectedCounterpartVersion']) {
          throw const PlatformFailure(
            409,
            'shift_conflict',
            'Counterpart Shift changed.',
          );
        }
        await _validateCandidate(tx, actor, r, counterpart);
        await _swaps.captureLeg(
          tx,
          request,
          'b',
          counterpart,
          r['source_employee_id'] as String,
          await _tasks.captureSwapWork(tx, counterpart),
        );
        await _claims.claimSwapB(tx, request);
        if (await _workforce.overlapsSwap(tx, request)) {
          throw const PlatformFailure(
            409,
            'shift_overlap',
            'Final roster has overlapping published work.',
          );
        }
      } else if (kind == 'confirm' || kind == 'manager_approve') {
        final originals = await _fresh(tx, actor, r);
        if (kind == 'manager_approve') {
          await _approve(tx, actor, request, originals);
        }
      }
      await _swaps.transition(
        tx,
        request,
        actor.id,
        c,
        currentSourceAuthorized: kind == 'source_withdraw',
      );
      if (!{'offer', 'confirm'}.contains(kind)) {
        await _claims.releaseSwap(tx, request);
      }
    }
    final evidence = await _evidence(tx, await _get(tx, request));
    final result = ShiftSwapCommandResult.fromJson({
      'operationId': c.operationId,
      'kind': kind,
      'acceptedVersion': evidence.json['version'],
      'statusCode': kind == 'request' ? 201 : 200,
      'request': evidence.toJson(),
      'replayed': false,
    });
    await _swaps.commitReceipt(tx, request, actor.id, c, result);
    await database.audit(
      tx,
      actor,
      'workforce.swap.${evidence.json['status']}',
      'shift_swap',
      request,
      locationId: database.locationId,
      changes: {
        'requestId': request,
        'operationId': c.operationId,
        'kind': kind,
        'expectedVersion': c.expectedVersion,
        'version': evidence.json['version'],
        'status': evidence.json['status'],
        'sourceEmployeeId': evidence.json['sourceEmployeeId'],
        'recipientEmployeeId': evidence.json['recipientEmployeeId'],
        'sourceShiftIds': [
          for (final l in evidence.json['legs'] as List)
            l['sourceShiftId'] as String,
        ],
        if (kind == 'manager_approve')
          'replacementShiftIds': [
            for (final l in evidence.json['legs'] as List)
              l['replacementShiftId'] as String,
          ],
      },
    );
    return result;
  }

  Future<void> _approve(
    TxSession tx,
    PlatformActor actor,
    String request,
    List<ShiftDto> originals,
  ) async {
    await _claims.lockSwapOriginals(tx, request);
    for (final s in originals) {
      await _future(tx, s);
    }
    final now = await _now(tx), reason = 'Shift swap $request';
    // Both departures precede either publication, preserving immediate exclusion.
    for (final s in originals) {
      await _tasks.cancelForShift(
        tx,
        actor,
        shiftId: s.id,
        locationId: s.locationId,
        reason: reason,
        now: now,
      );
      await _workforce.cancel(tx, actor, s.id, s.version, reason, now);
    }
    final replacements = [newUuid(), newUuid()];
    for (var i = 0; i < 2; i++) {
      await _swaps.replacement(
        tx,
        request,
        i == 0 ? 'a' : 'b',
        replacements[i],
      );
    }
    for (var i = 0; i < 2; i++) {
      final s = originals[i],
          incoming = originals[1 - i].draft.employeeId,
          leg = i == 0 ? 'a' : 'b';
      await _workforce.create(
        tx,
        actor,
        replacements[i],
        s.locationId,
        ShiftDraftInput(
          employeeId: incoming,
          startsAt: s.draft.startsAt,
          endsAt: s.draft.endsAt,
          selections: s.draft.selections,
        ),
      );
      await _workforce.checkPublication(tx, replacements[i], 1);
      await _tasks.createSwapReplacement(
        tx,
        actor,
        source: s,
        requestId: request,
        leg: leg,
        replacementShiftId: replacements[i],
        incoming: incoming,
      );
      await _workforce.publish(tx, actor, replacements[i]);
    }
    // Initially deferred database guards validate the complete transaction last.
  }

  Future<void> _validateCandidate(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> r,
    ShiftDto candidate,
  ) async {
    await _future(tx, candidate);
    await _eligible(tx, candidate, r['recipient_employee_id'] as String);
    await _eligible(tx, candidate, r['source_employee_id'] as String);
    await _tasks.validateTransfer(tx, candidate, publisher: actor);
    if (await _claims.occupied(tx, candidate.id)) {
      throw const ShiftHandoffConflict();
    }
    if (await _workforce.overlapsSwapCandidate(
      tx,
      r['id'] as String,
      candidate.id,
    )) {
      throw const PlatformFailure(
        409,
        'shift_overlap',
        'Final roster has overlapping published work.',
      );
    }
  }

  Future<ShiftSwapDetailDto> detail(
    SessionPrincipal p,
    String id, {
    bool self = true,
    String? location,
  }) => _run(p, self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage', (
    tx,
    actor,
  ) async {
    final link = self ? await _self(tx, actor) : null;
    final r = await _get(tx, id, employee: link?.employeeId);
    final role = link == null
        ? 'manager'
        : r['source_employee_id'] == link.employeeId
        ? 'source'
        : 'recipient';
    String? blocked;
    final active = _active.contains(r['status']);
    if (active) {
      try {
        await _fresh(tx, actor, r);
      } on PlatformFailure catch (e) {
        if (!{409, 422}.contains(e.status)) rethrow;
        blocked = e.code;
      }
    }
    final actions = <String>[];
    if (active) {
      if (role == 'manager') {
        actions.add('manager_reject');
        if (blocked == null &&
            r['status'] == 'confirmed' &&
            !{
              r['source_account_id'],
              r['recipient_account_id'],
            }.contains(actor.id) &&
            [
              'workforce.shifts.manage',
              'tasks.instances.read',
            ].every(permissionsForRole(actor.role).contains)) {
          actions.add('manager_approve');
        }
      } else if (role == 'source') {
        actions.add('source_withdraw');
        if (_captured(r, link!, 'source') && r['status'] == 'offered') {
          if (blocked == null) actions.add('confirm');
          actions.add('decline');
        }
      } else if (_captured(r, link!, 'recipient')) {
        if (r['status'] == 'requested') {
          if (blocked == null) actions.add('offer');
          actions.add('decline');
        } else {
          actions.add('recipient_withdraw');
        }
      }
    }
    return ShiftSwapDetailDto.fromJson({
      'request': (await _evidence(tx, r)).toJson(),
      'participantRole': role,
      'actionable': active && blocked == null,
      'nonActionableReason': blocked,
      'availableActions': actions,
    });
  }, location: location);

  String _cursor(List<Object?> scope, Object? marker) =>
      base64Url.encode(utf8.encode(jsonEncode([...scope, marker])));
  // Base64 cursors are readable. Keep captured Identity facts out of their
  // projection while retaining exact authorization-basis binding.
  String _cursorBasis(List<Object?> basis) =>
      sha256.convert(utf8.encode(jsonEncode(basis))).toString();
  Object? _after(String? cursor, List<Object?> scope) {
    if (cursor == null) return null;
    try {
      if (cursor.length > 2048) throw const FormatException();
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (j is! List ||
          j.length != scope.length + 1 ||
          j.last == null ||
          jsonEncode(j.take(scope.length).toList()) != jsonEncode(scope)) {
        throw const FormatException();
      }
      return j.last;
    } catch (_) {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped swap cursor.',
      );
    }
  }

  String _cursorUuid(Object? value) {
    try {
      final id = shiftUuid(value);
      if (id != value) throw const FormatException();
      return id;
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid swap cursor marker.',
      );
    }
  }

  DateTime _cursorInstant(Object? value) {
    try {
      return shiftInstant(value);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid swap cursor marker.',
      );
    }
  }

  Future<ShiftSwapPageDto> list(
    SessionPrincipal p, {
    bool self = true,
    String? location,
    String? direction,
    String? status,
    String? after,
  }) => _run(p, self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage', (
    tx,
    actor,
  ) async {
    if ((status != null && !shiftSwapStates.contains(status)) ||
        (direction != null &&
            (!self || !{'incoming', 'outgoing'}.contains(direction)))) {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid swap filters.',
      );
    }
    final link = self ? await _self(tx, actor) : null;
    final employee = link?.employeeId;
    final accountVersion = await _links.currentReaderAccountVersion(tx, actor);
    final scope = <Object?>[
      'swaps',
      database.companyId,
      database.locationId,
      employee,
      direction,
      status,
      self ? 'self' : 'manager',
      _cursorBasis([actor.id, accountVersion, link?.id, link?.version]),
    ];
    final marker = _after(after, scope);
    final rows = await _swaps.page(
      tx,
      employee: employee,
      direction: direction,
      status: status,
      after: marker == null ? null : _cursorUuid(marker),
    );
    final items = rows.take(50).toList();
    return ShiftSwapPageDto.fromJson({
      'items': [for (final r in items) (await _evidence(tx, r)).toJson()],
      'nextCursor': rows.length > 50 ? _cursor(scope, items.last['id']) : null,
    });
  }, location: location);

  /// At most four immutable receipts, preserving the original internal contract.
  Future<List<ShiftSwapCommandResult>> history(
    SessionPrincipal p,
    String id, {
    bool self = true,
    String? location,
  }) => _run(p, self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage', (
    tx,
    actor,
  ) async {
    final employee = self ? (await _self(tx, actor)).employeeId : null;
    final r = await _get(tx, id, employee: employee);
    return List.unmodifiable(await _swaps.history(tx, r['id'] as String));
  }, location: location);

  /// Two immutable receipts per transport page, ordered by accepted version.
  /// The cursor names an existing receipt and is bound to current reader scope.
  Future<Map<String, dynamic>> historyPage(
    SessionPrincipal p,
    String id, {
    bool self = true,
    String? location,
    String? after,
  }) => _run(p, self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage', (
    tx,
    actor,
  ) async {
    final link = self ? await _self(tx, actor) : null;
    final r = await _get(tx, id, employee: link?.employeeId);
    final scope = <Object?>[
      'swap-history',
      database.companyId,
      database.locationId,
      r['id'],
      self ? 'self' : 'manager',
      _cursorBasis([
        actor.id,
        link?.id,
        r['source_account_id'],
        r['source_link_id'],
        r['source_account_version'],
        r['recipient_account_id'],
        r['recipient_link_id'],
        r['recipient_account_version'],
      ]),
    ];
    final receipts = await _swaps.history(tx, r['id'] as String);
    final marker = _after(after, scope);
    var start = 0;
    if (after != null) {
      if (marker is! List ||
          marker.length != 2 ||
          marker[0] is! int ||
          (marker[0] as int) < 1 ||
          (marker[0] as int) > 4 ||
          marker[1] is! String) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid history cursor.',
        );
      }
      final operation = _cursorUuid(marker[1]);
      final index = receipts.indexWhere(
        (receipt) =>
            receipt.json['acceptedVersion'] == marker[0] &&
            receipt.json['operationId'] == operation,
      );
      if (index < 0) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid history cursor.',
        );
      }
      start = index + 1;
    }
    final items = receipts.skip(start).take(2).toList();
    return {
      'items': [for (final receipt in items) receipt.toJson()],
      'nextCursor': receipts.length > start + items.length
          ? _cursor(scope, [
              items.last.json['acceptedVersion'],
              items.last.json['operationId'],
            ])
          : null,
    };
  }, location: location);

  Future<ShiftSwapColleaguePageDto> colleagues(
    SessionPrincipal p,
    String sourceId, {
    String? after,
  }) => _run(p, 'workforce.swaps.self.request', (tx, actor) async {
    _require(actor, 'workforce.swaps.self.read');
    final link = await _self(tx, actor);
    final s = await _own(tx, shiftUuid(sourceId), link.employeeId);
    await _future(tx, s);
    await _eligible(tx, s, link.employeeId);
    await _tasks.validateTransfer(tx, s, publisher: actor);
    final scope = <Object?>[
      'swap-colleagues',
      database.companyId,
      database.locationId,
      _cursorBasis([link.accountId, link.id]),
      s.id,
      s.version,
    ];
    final raw = _after(after, scope),
        marker = raw == null ? null : _cursorUuid(raw);
    final eligible = <Map<String, dynamic>>[];
    for (final person in await _people.list(tx)) {
      if (person.id == link.employeeId ||
          (marker != null && person.id.compareTo(marker) <= 0)) {
        continue;
      }
      try {
        await _eligible(tx, s, person.id);
      } on PlatformFailure catch (e) {
        if (e.status != 422) rethrow;
        continue;
      }
      final target = await _links.forEmployee(tx, person.id);
      if (target == null ||
          await _links.swapAccountVersion(tx, target) == null) {
        continue;
      }
      eligible.add({
        'employeeId': person.id,
        'displayName': person.displayName,
      });
    }
    eligible.sort(
      (a, b) =>
          (a['employeeId'] as String).compareTo(b['employeeId'] as String),
    );
    final items = eligible.take(50).toList();
    return ShiftSwapColleaguePageDto.fromJson({
      'items': items,
      'nextCursor': eligible.length > 50
          ? _cursor(scope, items.last['employeeId'])
          : null,
    });
  });

  Future<Map<String, dynamic>> _candidateRequest(
    TxSession tx,
    PlatformActor actor,
    String id,
  ) async {
    final link = await _self(tx, actor);
    final r = await _get(tx, id, employee: link.employeeId);
    if (!_captured(r, link, 'recipient')) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Counterparts unavailable.',
      );
    }
    if (r['status'] != 'requested') {
      throw const PlatformFailure(
        409,
        'swap_conflict',
        'Counterparts require the original invitation.',
      );
    }
    await _fresh(tx, actor, r);
    return r;
  }

  Future<ShiftSwapLegDto> counterpart(
    SessionPrincipal p,
    String id,
    String shiftId,
  ) => _run(p, 'workforce.swaps.self.respond', (tx, actor) async {
    _require(actor, 'workforce.swaps.self.read');
    final r = await _candidateRequest(tx, actor, id);
    final s = await _own(
      tx,
      shiftUuid(shiftId),
      r['recipient_employee_id'] as String,
    );
    await _validateCandidate(tx, actor, r, s);
    return ShiftSwapLegDto.fromJson({
      'leg': 'b',
      'sourceShiftId': s.id,
      'sourceVersion': s.version,
      'sourceEmployeeId': s.draft.employeeId,
      'incomingEmployeeId': r['source_employee_id'],
      'startsAt': s.draft.startsAt.toUtc().toIso8601String(),
      'endsAt': s.draft.endsAt.toUtc().toIso8601String(),
      'tasks': await _tasks.captureSwapWork(tx, s),
      'taskLinks': <Object?>[],
      'replacementShiftId': null,
    });
  });
  Future<ShiftSwapCounterpartPageDto> counterparts(
    SessionPrincipal p,
    String id, {
    String? after,
  }) => _run(p, 'workforce.swaps.self.respond', (tx, actor) async {
    _require(actor, 'workforce.swaps.self.read');
    final r = await _candidateRequest(tx, actor, id);
    final scope = <Object?>[
      'swap-counterparts',
      database.companyId,
      database.locationId,
      r['id'],
      r['version'],
      _cursorBasis([
        r['recipient_account_id'],
        r['recipient_link_id'],
        r['recipient_account_version'],
      ]),
    ];
    final raw = _after(after, scope);
    DateTime? time;
    String? marker;
    if (raw != null) {
      if (raw is! List || raw.length != 2) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid counterpart cursor.',
        );
      }
      time = _cursorInstant(raw[0]);
      marker = _cursorUuid(raw[1]);
    }
    // Scan bounded owner pages until 51 eligible rows, retaining the last
    // eligible time/ID so filtered pages never hide later own candidates.
    final eligible = <Map<String, dynamic>>[];
    while (eligible.length < 51) {
      final rows = await _workforce.page(
        tx,
        employeeId: r['recipient_employee_id'] as String,
        locationId: database.locationId,
        afterTime: time,
        afterId: marker,
      );
      for (final s in rows) {
        time = s.draft.startsAt;
        marker = s.id;
        try {
          await _validateCandidate(tx, actor, r, s);
        } on ShiftHandoffConflict {
          continue;
        } on PlatformFailure catch (e) {
          if (!{409, 422}.contains(e.status)) rethrow;
          continue;
        }
        eligible.add({
          'shiftId': s.id,
          'version': s.version,
          'startsAt': s.draft.startsAt.toUtc().toIso8601String(),
          'endsAt': s.draft.endsAt.toUtc().toIso8601String(),
        });
        if (eligible.length == 51) break;
      }
      if (rows.length < 51) break;
    }
    final items = eligible.take(50).toList();
    return ShiftSwapCounterpartPageDto.fromJson({
      'items': items,
      'nextCursor': eligible.length > 50
          ? _cursor(scope, [items.last['startsAt'], items.last['shiftId']])
          : null,
    });
  });
}
