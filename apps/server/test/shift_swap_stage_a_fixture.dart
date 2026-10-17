import 'dart:async';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/identity/employee_links.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/tasks/task_instance_service.dart';
import 'package:storeos_server/src/workforce/workforce_service.dart';
import 'package:storeos_server/src/workforce/shift_swap_service.dart';
import 'package:storeos_server/src/workforce/shift_handoff_claim_service.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';

/// Restricted owner-port integrity fixtures. These are not swap HTTP acceptance.
class StageASwapFixture {
  StageASwapFixture(
    this.f,
    this.a,
    this.b,
    this.template,
    this.revision,
    this.shiftA,
    this.shiftB,
  ) : swaps = ShiftSwapService(f.database),
      claims = ShiftHandoffClaimService(f.database),
      workforce = WorkforceService(f.database),
      tasks = TaskInstanceService(f.database),
      links = EmployeeLinks(f.database);
  final MerchandisingFixture f;
  final BatchWorker a, b;
  final String template, revision, shiftA, shiftB;
  final ShiftSwapService swaps;
  final ShiftHandoffClaimService claims;
  final WorkforceService workforce;
  final TaskInstanceService tasks;
  final EmployeeLinks links;
  Future<T> tx<T>(Future<T> Function(TxSession, PlatformActor) work) => f
      .database
      .runAuthorized(f.adminPrincipal, 'workforce.shifts.manage', work);

  Future<Map<String, dynamic>> evidenceJson(
    TxSession tx,
    String request,
  ) async {
    final r = (await swaps.find(tx, request))!;
    String? instant(Object? v) =>
        v == null ? null : (v as DateTime).toUtc().toIso8601String();
    final legs = await swaps.legs(tx, request);
    return {
      'id': request,
      'companyId': merchandisingTestCompany,
      'locationId': merchandisingTestLocation,
      'sourceEmployeeId': r['source_employee_id'],
      'recipientEmployeeId': r['recipient_employee_id'],
      'sourceName': 'Fixture A',
      'recipientName': 'Fixture B',
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
            'taskLinks': await tasks.swapLinks(tx, request, l['leg'] as String),
          },
      ],
    };
  }

  Future<ShiftSwapDto> evidence(TxSession tx, String request) async =>
      ShiftSwapDto.fromJson(await evidenceJson(tx, request));

  Future<ShiftSwapCommandResult> receipt(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c,
  ) async {
    final e = await evidence(tx, request);
    final result = ShiftSwapCommandResult.fromJson({
      'operationId': c.operationId,
      'kind': c.kind,
      'acceptedVersion': e.json['version'],
      'statusCode': c.kind == 'request' ? 201 : 200,
      'request': e.toJson(),
      'replayed': false,
    });
    await swaps.commitReceipt(tx, request, actor, c, result);
    return result;
  }

  ShiftSwapCommandInput requestCommand({String? source, String? request}) =>
      ShiftSwapCommandInput.fromJson('request', {
        'requestId': request ?? newUuid(),
        'operationId': newUuid(),
        'sourceShiftId': source ?? shiftA,
        'expectedSourceVersion': 2,
        'recipientEmployeeId': b.employee,
      });
  Future<String> request({
    String? source,
    ShiftSwapCommandInput? command,
  }) async {
    final c = command ?? requestCommand(source: source),
        request = c.payload['requestId'] as String;
    await tx((tx, actor) async {
      final sourceLink = (await links.forEmployee(tx, a.employee))!,
          recipientLink = (await links.forEmployee(tx, b.employee))!;
      await swaps.request(
        tx,
        c,
        sourceLink,
        recipientLink,
        (await links.transferAccountVersion(tx, sourceLink))!,
        (await links.transferAccountVersion(tx, recipientLink))!,
      );
      final shift = await workforce.get(
        tx,
        c.payload['sourceShiftId'] as String,
      );
      await swaps.captureLeg(
        tx,
        request,
        'a',
        shift,
        b.employee,
        await tasks.captureSwapWork(tx, shift),
      );
      await claims.claimSwapA(tx, request);
      await receipt(tx, request, a.account, c);
    });
    return request;
  }

  Future<ShiftSwapCommandResult> offer(String request, {String? counterpart}) =>
      tx((tx, actor) async {
        final shift = await workforce.get(tx, counterpart ?? shiftB),
            c = ShiftSwapCommandInput.fromJson('offer', {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'counterpartShiftId': shift.id,
              'expectedCounterpartVersion': shift.version,
            });
        await swaps.captureLeg(
          tx,
          request,
          'b',
          shift,
          a.employee,
          await tasks.captureSwapWork(tx, shift),
        );
        await claims.lockSwapOriginals(tx, request);
        await claims.claimSwapB(tx, request);
        await swaps.transition(tx, request, b.account, c);
        return receipt(tx, request, b.account, c);
      });
  Future<ShiftSwapCommandResult> transition(
    String request,
    String kind,
    int version, {
    String? actor,
  }) => tx((tx, manager) async {
    final c = ShiftSwapCommandInput.fromJson(kind, {
      'operationId': newUuid(),
      'expectedVersion': version,
      if ({
        'source_withdraw',
        'recipient_withdraw',
        'manager_reject',
      }.contains(kind))
        'reason': 'Integrity fixture closure',
    });
    final who =
        actor ??
        (kind == 'confirm' || kind == 'source_withdraw'
            ? a.account
            : kind == 'recipient_withdraw' || kind == 'decline' && version == 1
            ? b.account
            : kind == 'decline'
            ? a.account
            : manager.id);
    await swaps.transition(tx, request, who, c);
    if (!{'offer', 'confirm'}.contains(kind)) {
      await claims.releaseSwap(tx, request);
    }
    return receipt(tx, request, who, c);
  });
  Future<ShiftSwapCommandResult?> approveIntegrityFixture(
    String request, {
    bool omitSecond = false,
    String? operation,
    bool rawReceipt = false,
    bool rawTaskMaterialization = false,
  }) => tx((tx, actor) async {
    await claims.lockSwapOriginals(tx, request);
    final originals = [
      await workforce.get(tx, shiftA),
      await workforce.get(tx, shiftB),
    ];
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    for (final shift in originals) {
      await tasks.cancelForShift(
        tx,
        actor,
        shiftId: shift.id,
        locationId: shift.locationId,
        reason: 'Integrity swap fixture',
        now: now,
      );
      await workforce.cancel(
        tx,
        actor,
        shift.id,
        shift.version,
        'Integrity swap fixture',
        now,
      );
    }
    for (var i = 0; i < (omitSecond ? 1 : 2); i++) {
      final source = originals[i],
          incoming = i == 0 ? b.employee : a.employee,
          leg = i == 0 ? 'a' : 'b',
          replacement = newUuid();
      await swaps.replacement(tx, request, leg, replacement);
      await workforce.create(
        tx,
        actor,
        replacement,
        source.locationId,
        ShiftDraftInput(
          employeeId: incoming,
          startsAt: source.draft.startsAt,
          endsAt: source.draft.endsAt,
          selections: source.draft.selections,
        ),
      );
      if (rawTaskMaterialization) {
        await tasks.createForShift(
          tx,
          actor,
          shiftId: replacement,
          employeeId: incoming,
          locationId: source.locationId,
          selections: source.draft.selections,
        );
        // Explicit adversarial SQL fixture, not an application repository read.
        await tx.execute(
          '''INSERT INTO ${f.schema}.task_swap_links(company_id,location_id,request_id,leg,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position)
          SELECT s.company_id,s.location_id,'$request','$leg',s.shift_id,b.shift_id,s.id,b.id,s.template_id,s.revision_id,s.position
          FROM ${f.schema}.task_instances s JOIN ${f.schema}.task_instances b ON b.company_id=s.company_id AND b.position=s.position AND b.template_id=s.template_id AND b.revision_id=s.revision_id
          WHERE s.shift_id='${source.id}' AND b.shift_id='$replacement' ''',
        );
      } else {
        await tasks.createSwapReplacement(
          tx,
          actor,
          source: source,
          requestId: request,
          leg: leg,
          replacementShiftId: replacement,
          incoming: incoming,
        );
      }
      await workforce.publish(tx, actor, replacement);
    }
    final c = ShiftSwapCommandInput.fromJson('manager_approve', {
      'operationId': operation ?? newUuid(),
      'expectedVersion': 3,
    });
    await swaps.transition(tx, request, actor.id, c);
    await claims.releaseSwap(tx, request);
    if (rawReceipt) {
      final e = await evidenceJson(tx, request);
      await tx.execute(
        Sql.named(
          '''INSERT INTO ${f.schema}.workforce_shift_swap_commands(company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,payload,result)
        VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@operation AS uuid),CAST(@request AS uuid),CAST(@actor AS uuid),'manager_approve',3,4,200,CAST(@payload AS jsonb),CAST(@result AS jsonb))''',
        ),
        parameters: {
          'company': merchandisingTestCompany,
          'location': merchandisingTestLocation,
          'operation': c.operationId,
          'request': request,
          'actor': actor.id,
          'payload': c.canonical,
          'result': jsonEncode({
            'operationId': c.operationId,
            'kind': c.kind,
            'acceptedVersion': 4,
            'statusCode': 200,
            'request': e,
            'replayed': false,
          }),
        },
      );
      return null;
    }
    return receipt(tx, request, actor.id, c);
  });
  Future<String> hash() async => jsonEncode({
    for (final table in [
      'shifts',
      'shift_template_selections',
      'task_instances',
      'task_execution_commands',
      'task_step_results',
      'task_numeric_attempts',
      'task_blockings',
      'workforce_shift_swap_requests',
      'workforce_shift_swap_legs',
      'workforce_shift_swap_commands',
      'workforce_shift_handoff_claims',
      'task_swap_links',
      'workforce_shift_transfer_requests',
      'workforce_shift_transfer_commands',
      'task_transfer_links',
      'audit_entries',
    ])
      table: (await f.owner.execute(
        "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${f.schema}.$table t",
      )).single.toList(),
  });
}

Future<StageASwapFixture> stageAFixture(
  MerchandisingFixture f, {
  DateTime? starts,
  int taskCount = 1,
  String workerPrefix = 'swap_fixture',
  String taskTitle = 'Frozen fixture work',
}) async {
  final a = await batchWorker(f, '${workerPrefix}_a'),
      b = await batchWorker(f, '${workerPrefix}_b');
  final template = newUuid(), revision = newUuid();
  final selections = <Map<String, dynamic>>[];
  for (var i = 0; i < taskCount; i++) {
    final t = i == 0 ? template : newUuid(), r = i == 0 ? revision : newUuid();
    selections.add({'templateId': t, 'revisionId': r});
    await f.call(
      'POST',
      '/task-templates',
      expected: 201,
      body: {
        'id': t,
        'revisionId': r,
        'locationId': merchandisingTestLocation,
        'content': {
          'schemaVersion': 1,
          'title': taskTitle,
          'steps': [
            {
              'id': newUuid(),
              'type': 'confirmation',
              'instruction': 'Exact work',
            },
          ],
        },
      },
    );
    await f.call(
      'POST',
      '/task-templates/$t/revisions/$r/publish',
      body: {'expectedVersion': 1},
    );
  }
  final start = starts ?? DateTime.now().toUtc().add(const Duration(days: 2));
  Future<String> shift(String employee) async {
    final id = newUuid();
    await f.call(
      'POST',
      '/shifts',
      expected: 201,
      body: {
        'id': id,
        'locationId': merchandisingTestLocation,
        'employeeId': employee,
        'startsAt': start.toIso8601String(),
        'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
        'selections': selections,
      },
    );
    await f.call('POST', '/shifts/$id/publish', body: {'expectedVersion': 1});
    return id;
  }

  return StageASwapFixture(
    f,
    a,
    b,
    template,
    revision,
    await shift(a.employee),
    await shift(b.employee),
  );
}

Future<List<T>> observedWriters<T>(
  MerchandisingFixture f,
  Future<T> Function() first,
  Future<T> Function() second,
) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holder = f.database.runAuthorized(
    f.adminPrincipal,
    'workforce.shifts.manage',
    (tx, actor) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  Future<void> queued(int n) async {
    final timer = Stopwatch()..start();
    while (timer.elapsed < const Duration(seconds: 15)) {
      final rows = await f.owner.execute(
        Sql.named(
          "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
        ),
        parameters: {
          'key': 'storeos_platform:${f.schema}:$merchandisingTestCompany',
        },
      );
      if (rows.single.first == n) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('Expected $n observed queued Company writers.');
  }

  try {
    final a = first();
    await queued(1);
    final b = second();
    await queued(2);
    release.complete();
    await holder;
    return await Future.wait([a, b]);
  } finally {
    if (!release.isCompleted) release.complete();
    await holder;
  }
}
