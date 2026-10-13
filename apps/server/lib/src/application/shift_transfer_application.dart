import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../tasks/task_instance_service.dart';
import '../workforce/workforce_service.dart';
import '../workforce/shift_transfer_service.dart';
import '../workforce/shift_handoff_claim_service.dart';

/// Authorized orchestration through public owner ports, in one Company transaction.
class ShiftTransferApplication {
  ShiftTransferApplication(this.database)
    : _transfers = ShiftTransferService(database),
      _workforce = WorkforceService(database),
      _tasks = TaskInstanceService(database),
      _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final ShiftTransferService _transfers;
  final WorkforceService _workforce;
  final TaskInstanceService _tasks;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;

  Future<T> _run<T>(
    SessionPrincipal p,
    String capability,
    Future<T> Function(TxSession, PlatformActor) work, {
    String? location,
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
        'transfer_already_pending',
        'Close the existing request first.',
      );
    } on TransferInputException catch (e) {
      throw PlatformFailure(400, e.code, e.message);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid transfer request.',
      );
    } on ShiftConflict {
      throw const PlatformFailure(
        409,
        'shift_conflict',
        'Source Shift changed.',
      );
    } on ShiftNotPublishable {
      throw const PlatformFailure(
        422,
        'shift_not_transferable',
        'Source Shift cannot be transferred.',
      );
    } on ServerException catch (e) {
      if (e.code == '23514' && e.constraintName == 'transfer_approval_future') {
        throw const PlatformFailure(
          422,
          'shift_not_transferable',
          'Transfer requires a future published Shift.',
        );
      }
      if (e.code == '23505' && e.constraintName == 'transfer_active_source') {
        throw const PlatformFailure(
          409,
          'transfer_already_pending',
          'Close the existing request first.',
        );
      }
      if (e.code == '23505' &&
          {
            'workforce_shift_transfer_requests_pkey',
            'workforce_shift_transfer_commands_pkey',
          }.contains(e.constraintName)) {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Transfer operation identity already exists.',
        );
      }
      if (e.code == '23P01' &&
          e.constraintName == 'shifts_published_no_overlap') {
        throw const PlatformFailure(
          409,
          'shift_overlap',
          'Recipient has overlapping published work.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Transfer database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Transfer database unavailable.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Transfer database unavailable.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Transfer database unavailable.',
      );
    } on StateError catch (e) {
      if (e.message == 'request() may not be called on a closed Pool.') {
        throw const PlatformFailure(
          503,
          'database_unavailable',
          'Transfer database unavailable.',
        );
      }
      throw const PlatformFailure(
        500,
        'internal_error',
        'Transfer evidence could not be verified.',
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
        link.locationId != actor.locationId) {
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
    final r = await _transfers.find(tx, shiftUuid(id));
    if (r == null ||
        (employee != null &&
            r['sourceEmployeeId'] != employee &&
            r['recipientEmployeeId'] != employee)) {
      throw const PlatformFailure(404, 'not_found', 'Transfer not found.');
    }
    return r;
  }

  Future<void> _eligible(
    TxSession tx,
    ShiftDto shift,
    String employee,
    String code,
  ) async {
    EmployeeDto person;
    try {
      person = await _people.get(tx, employee);
    } on PlatformFailure catch (e) {
      if (e.status != 404) rethrow;
      throw PlatformFailure(422, code, 'Employee assignment unavailable.');
    }
    if (!person.isActive ||
        person.companyId != database.companyId ||
        person.locationId != database.locationId ||
        person.assignedFrom.isAfter(shift.draft.startsAt) ||
        (person.assignedUntil != null &&
            person.assignedUntil!.isBefore(shift.draft.endsAt))) {
      throw PlatformFailure(
        422,
        code,
        'Employee assignment must cover the exact interval.',
      );
    }
  }

  Future<void> _future(TxSession tx, ShiftDto shift) async {
    if (shift.status != 'published' ||
        !shift.draft.startsAt.isAfter(await _now(tx))) {
      throw const PlatformFailure(
        422,
        'shift_not_transferable',
        'Transfer requires a future published Shift.',
      );
    }
  }

  Future<void> _bound(TxSession tx, Map<String, dynamic> r) async {
    for (final source in [true, false]) {
      final link = await _links.forEmployee(
        tx,
        r[source ? 'sourceEmployeeId' : 'recipientEmployeeId'] as String,
      );
      if (link == null ||
          link.id != r[source ? 'sourceLinkId' : 'recipientLinkId'] ||
          link.accountId != r[source ? 'proposedBy' : 'recipientAccountId'] ||
          await _links.transferAccountVersion(tx, link) !=
              r[source ? 'sourceAccountVersion' : 'recipientAccountVersion']) {
        throw PlatformFailure(
          422,
          source ? 'employee_unavailable' : 'recipient_unavailable',
          'Captured identity basis changed; close this request and propose again.',
        );
      }
    }
  }

  Future<ShiftDto> _fresh(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> r,
  ) async {
    final shift = await _workforce.get(tx, r['sourceShiftId'] as String);
    if (shift.version != r['sourceVersion'] ||
        shift.draft.employeeId != r['sourceEmployeeId'] ||
        shift.draft.startsAt != shiftInstant(r['startsAt']) ||
        shift.draft.endsAt != shiftInstant(r['endsAt'])) {
      throw const PlatformFailure(
        409,
        'shift_conflict',
        'Captured source Shift changed.',
      );
    }
    await _future(tx, shift);
    await _bound(tx, r);
    await _eligible(
      tx,
      shift,
      r['sourceEmployeeId'] as String,
      'employee_unavailable',
    );
    await _eligible(
      tx,
      shift,
      r['recipientEmployeeId'] as String,
      'recipient_unavailable',
    );
    await _tasks.validateTransfer(tx, shift, publisher: actor);
    if (await _workforce.overlapsTransfer(
      tx,
      shift,
      r['recipientEmployeeId'] as String,
    )) {
      throw const PlatformFailure(
        409,
        'shift_overlap',
        'Recipient has overlapping published work.',
      );
    }
    return shift;
  }

  Future<Map<String, dynamic>> _evidence(
    TxSession tx,
    Map<String, dynamic> r,
  ) async => {
    ...r,
    'sourceName': (await _people.get(
      tx,
      r['sourceEmployeeId'] as String,
    )).displayName,
    'recipientName': (await _people.get(
      tx,
      r['recipientEmployeeId'] as String,
    )).displayName,
    'tasks': await _tasks.transferSummary(tx, r['sourceShiftId'] as String),
    'taskLinks': await _tasks.transferLinks(
      tx,
      database.locationId,
      r['id'] as String,
    ),
  };
  Future<Map<String, dynamic>> _detail(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> r,
  ) async {
    String? blocked;
    if ({'proposed', 'accepted'}.contains(r['status'])) {
      try {
        await _fresh(tx, actor, r);
      } on PlatformFailure catch (e) {
        if (!{409, 422}.contains(e.status)) rethrow;
        blocked = e.code;
      }
    }
    return {
      ...await _evidence(tx, r),
      'actionable':
          {'proposed', 'accepted'}.contains(r['status']) && blocked == null,
      'nonActionableReason': blocked,
    };
  }

  Future<Map<String, dynamic>> detail(
    SessionPrincipal p,
    String id, {
    bool self = true,
    String? location,
  }) => _run(
    p,
    self ? 'workforce.transfers.self.read' : 'workforce.transfers.manage',
    (tx, actor) async {
      final employee = self ? (await _self(tx, actor)).employeeId : null;
      final r = await _get(tx, id, employee: employee);
      return {
        ...await _detail(tx, actor, r),
        'participantRole': employee == null
            ? 'manager'
            : employee == r['sourceEmployeeId']
            ? 'source'
            : 'recipient',
      };
    },
    location: location,
  );

  String _cursor(List<Object?> scope, String id) =>
      base64Url.encode(utf8.encode(jsonEncode([...scope, id])));
  String? _after(String? cursor, List<Object?> scope) {
    if (cursor == null) return null;
    try {
      if (cursor.length > 2048) throw const FormatException();
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (j is! List ||
          j.length != scope.length + 1 ||
          jsonEncode(j.take(scope.length).toList()) != jsonEncode(scope)) {
        throw const FormatException();
      }
      return shiftUuid(j.last);
    } catch (_) {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped transfer cursor.',
      );
    }
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal p, {
    bool self = true,
    String? location,
    String? direction,
    String? status,
    String? after,
  }) => _run(
    p,
    self ? 'workforce.transfers.self.read' : 'workforce.transfers.manage',
    (tx, actor) async {
      if ((status != null && !shiftTransferStates.contains(status)) ||
          (direction != null &&
              (!self || !{'incoming', 'outgoing'}.contains(direction)))) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Invalid transfer filters.',
        );
      }
      final employee = self ? (await _self(tx, actor)).employeeId : null;
      final scope = <Object?>[
        self ? 'self-transfers' : 'manager-transfers',
        database.companyId,
        database.locationId,
        employee,
        direction,
        status,
      ];
      final rows = await _transfers.page(
        tx,
        employee: employee,
        direction: direction,
        status: status,
        after: _after(after, scope),
      );
      final items = rows.take(50).toList();
      return {
        'items': [for (final r in items) await _evidence(tx, r)],
        'nextCursor': rows.length > 50
            ? _cursor(scope, items.last['id'] as String)
            : null,
      };
    },
    location: location,
  );

  Future<Map<String, dynamic>> recipients(
    SessionPrincipal p,
    String id, {
    String? after,
  }) => _run(p, 'workforce.transfers.self.request', (tx, actor) async {
    final source = await _self(tx, actor),
        shift = await _workforce.get(tx, shiftUuid(id));
    if (shift.draft.employeeId != source.employeeId ||
        shift.locationId != database.locationId) {
      throw const PlatformFailure(404, 'not_found', 'Shift not found.');
    }
    await _future(tx, shift);
    await _tasks.validateTransfer(tx, shift);
    final scope = <Object?>[
      'transfer-recipients',
      database.companyId,
      database.locationId,
      source.employeeId,
      shift.id,
      shift.version,
    ];
    final cursor = _after(after, scope), eligible = <Map<String, dynamic>>[];
    for (final person in await _people.list(tx)) {
      if (person.id == source.employeeId ||
          (cursor != null && person.id.compareTo(cursor) <= 0)) {
        continue;
      }
      try {
        await _eligible(tx, shift, person.id, 'recipient_unavailable');
      } on PlatformFailure catch (e) {
        if (e.status != 422) rethrow;
        continue;
      }
      final link = await _links.forEmployee(tx, person.id);
      if (link == null ||
          await _links.transferAccountVersion(tx, link) == null ||
          await _workforce.overlapsTransfer(tx, shift, person.id)) {
        continue;
      }
      eligible.add({
        'employeeId': person.id,
        'displayName': person.displayName,
      });
    }
    final items = eligible.take(50).toList();
    return {
      'items': items,
      'nextCursor': eligible.length > 50
          ? _cursor(scope, items.last['employeeId'] as String)
          : null,
      'shift': shift.toJson(),
      'sourceName': (await _people.get(tx, source.employeeId)).displayName,
      'tasks': await _tasks.transferSummary(tx, shift.id),
    };
  });

  Future<Map<String, dynamic>> command(
    SessionPrincipal p,
    String? id,
    String action,
    Map<String, dynamic> body, {
    bool self = true,
    String? location,
  }) => _run(
    p,
    self
        ? (action == 'propose'
              ? 'workforce.transfers.self.request'
              : 'workforce.transfers.self.read')
        : 'workforce.transfers.manage',
    (tx, actor) async {
      final link = self ? await _self(tx, actor) : null;
      Map<String, dynamic>? r;
      String kind = action;
      if (action != 'propose') {
        r = await _get(tx, id!, employee: link?.employeeId);
        if (self) {
          if (action == 'withdraw') {
            kind = r['sourceEmployeeId'] == link!.employeeId
                ? 'source_withdraw'
                : 'recipient_withdraw';
          }
          if (!{
            'accept',
            'decline',
            'source_withdraw',
            'recipient_withdraw',
          }.contains(kind)) {
            throw const PlatformFailure(
              403,
              'forbidden',
              'Unsupported participant action.',
            );
          }
          final source = kind == 'source_withdraw';
          _require(
            actor,
            source
                ? 'workforce.transfers.self.request'
                : 'workforce.transfers.self.respond',
          );
          if (!source &&
              (r['recipientEmployeeId'] != link!.employeeId ||
                  r['recipientLinkId'] != link.id ||
                  r['recipientAccountId'] != actor.id)) {
            throw const PlatformFailure(
              404,
              'not_found',
              'Transfer response unavailable.',
            );
          }
        } else {
          if (!{'manager_approve', 'manager_reject'}.contains(kind)) {
            throw const PlatformFailure(
              403,
              'forbidden',
              'Unsupported manager action.',
            );
          }
          if (kind == 'manager_approve') {
            _require(actor, 'workforce.shifts.manage');
            _require(actor, 'tasks.instances.read');
          }
        }
      } else if (!self) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Proposal requires current Employee.',
        );
      }
      final c = ShiftTransferCommandInput.fromJson(kind, body);
      final request = id == null
          ? c.payload['requestId'] as String
          : shiftUuid(id);
      ShiftDto? shift;
      if (kind == 'propose') {
        shift = await _workforce.get(tx, c.payload['sourceShiftId'] as String);
        if (shift.draft.employeeId != link!.employeeId ||
            shift.locationId != database.locationId) {
          throw const PlatformFailure(404, 'not_found', 'Shift not found.');
        }
        r = await _transfers.find(tx, request);
        if (r != null && r['sourceEmployeeId'] != link.employeeId) {
          throw const PlatformFailure(404, 'not_found', 'Transfer not found.');
        }
      }
      // Current capability, scope and participant resource checks precede receipt access.
      final receipt = await _transfers.receipt(tx, c.operationId);
      if (receipt != null) {
        final stored = ShiftTransferCommandInput.fromJson(
          receipt['kind'] as String,
          Map<String, dynamic>.from(receipt['payload'] as Map),
        );
        if (receipt['actor_id'] != actor.id ||
            receipt['request_id'] != request ||
            receipt['location_id'] != database.locationId ||
            receipt['kind'] != kind ||
            stored.canonical != c.canonical) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Operation identity is already bound.',
          );
        }
        return {
          ...Map<String, dynamic>.from(receipt['result'] as Map),
          'replayed': true,
        };
      }
      String? replacement;
      if (kind == 'propose') {
        if (r != null) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Request identity already exists.',
          );
        }
        if (shift!.version != c.expectedVersion) {
          throw const PlatformFailure(
            409,
            'shift_conflict',
            'Source Shift changed.',
          );
        }
        await _future(tx, shift);
        await _tasks.validateTransfer(tx, shift);
        await _eligible(tx, shift, link!.employeeId, 'employee_unavailable');
        final recipientId = c.payload['recipientEmployeeId'] as String;
        if (recipientId == link.employeeId) {
          throw const PlatformFailure(
            422,
            'recipient_unavailable',
            'Choose another eligible Employee.',
          );
        }
        await _eligible(tx, shift, recipientId, 'recipient_unavailable');
        final recipient = await _links.forEmployee(tx, recipientId),
            sourceVersion = await _links.transferAccountVersion(tx, link);
        final recipientVersion = recipient == null
            ? null
            : await _links.transferAccountVersion(tx, recipient);
        if (sourceVersion == null) {
          throw const PlatformFailure(
            422,
            'employee_unavailable',
            'Source identity unavailable.',
          );
        }
        if (recipient == null || recipientVersion == null) {
          throw const PlatformFailure(
            422,
            'recipient_unavailable',
            'Recipient identity unavailable.',
          );
        }
        if (await _workforce.overlapsTransfer(tx, shift, recipientId)) {
          throw const PlatformFailure(
            409,
            'shift_overlap',
            'Recipient has overlapping published work.',
          );
        }
        if (await _transfers.pending(tx, shift.id)) {
          throw const PlatformFailure(
            409,
            'transfer_already_pending',
            'Close the active request before proposing again.',
          );
        }
        await _future(tx, shift);
        await _transfers.propose(
          tx,
          shift,
          link,
          recipient,
          sourceVersion,
          recipientVersion,
          c,
        );
      } else {
        ShiftTransferRequest(
          r!,
        ).requireTransition(kind, c.expectedVersion, actor.id);
        if (kind == 'accept' || kind == 'manager_approve') {
          shift = await _fresh(tx, actor, r);
        }
        if (kind == 'manager_approve') {
          // Early rejection avoids effects; the deferred transfer invariant also
          // checks database time after all effects at the final approval boundary.
          await _future(tx, shift!);
          final now = await _now(tx), reason = 'Shift transfer $request';
          await _tasks.cancelForShift(
            tx,
            actor,
            shiftId: shift.id,
            locationId: shift.locationId,
            reason: reason,
            now: now,
          );
          await _workforce.cancel(
            tx,
            actor,
            shift.id,
            shift.version,
            reason,
            now,
          );
          replacement = newUuid();
          await _workforce.create(
            tx,
            actor,
            replacement,
            shift.locationId,
            ShiftDraftInput(
              employeeId: r['recipientEmployeeId'] as String,
              startsAt: shift.draft.startsAt,
              endsAt: shift.draft.endsAt,
              selections: shift.draft.selections,
            ),
          );
          await _workforce.checkPublication(tx, replacement, 1);
          await _tasks.createTransferReplacement(
            tx,
            actor,
            source: shift,
            requestId: request,
            replacementShiftId: replacement,
            recipient: r['recipientEmployeeId'] as String,
          );
          await _workforce.publish(tx, actor, replacement);
        }
        await _transfers.transition(
          tx,
          request,
          actor.id,
          c,
          replacement: replacement,
        );
      }
      final evidence = await _get(tx, request),
          result = {
            'request': await _evidence(tx, evidence),
            'replayed': false,
          };
      await _transfers.commitReceipt(tx, request, actor.id, c, result);
      await database.audit(
        tx,
        actor,
        'workforce.transfer.${kind == 'propose' ? 'proposed' : ShiftTransferRequest.target(kind)}',
        'shift_transfer',
        request,
        locationId: database.locationId,
        changes: {
          'requestId': request,
          'sourceShiftId': evidence['sourceShiftId'],
          'replacementShiftId': ?replacement,
          'sourceEmployeeId': evidence['sourceEmployeeId'],
          'recipientEmployeeId': evidence['recipientEmployeeId'],
          'operationId': c.operationId,
          'kind': kind,
          'expectedVersion': c.expectedVersion,
          'version': evidence['version'],
          'status': evidence['status'],
        },
      );
      return result;
    },
    location: location,
  );
}
