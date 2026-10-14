import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../platform/platform_database.dart';
import 'shift_swap.dart';

/// Private Workforce evidence. No foreign repositories or tables are read.
class ShiftSwapRepository {
  ShiftSwapRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Future<Result> _execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(
        Sql.named(sql),
        parameters: {'company': company, 'location': location, ...p},
      );

  Future<Map<String, dynamic>?> find(TxSession tx, String request) async {
    final rows = await _execute(
      tx,
      '''SELECT * FROM $schema.workforce_shift_swap_requests
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@request AS uuid)''',
      {'request': request},
    );
    return rows.isEmpty ? null : Map.unmodifiable(rows.single.toColumnMap());
  }

  Future<List<Map<String, dynamic>>> legs(
    TxSession tx,
    String request,
  ) async => (await _execute(
    tx,
    '''SELECT * FROM $schema.workforce_shift_swap_legs WHERE company_id=CAST(@company AS uuid)
        AND location_id=CAST(@location AS uuid) AND request_id=CAST(@request AS uuid) ORDER BY leg''',
    {'request': request},
  )).map((r) => Map<String, dynamic>.unmodifiable(r.toColumnMap())).toList();

  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    String? employee,
    String? direction,
    String? status,
    String? after,
  }) async => (await _execute(
    tx,
    '''SELECT * FROM $schema.workforce_shift_swap_requests
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)
      AND (CAST(@employee AS uuid) IS NULL OR
        (CAST(@direction AS text) IS NULL AND (source_employee_id=CAST(@employee AS uuid) OR recipient_employee_id=CAST(@employee AS uuid))) OR
        (@direction='outgoing' AND source_employee_id=CAST(@employee AS uuid)) OR
        (@direction='incoming' AND recipient_employee_id=CAST(@employee AS uuid)))
      AND (CAST(@status AS text) IS NULL OR status=@status)
      AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51''',
    {
      'employee': employee,
      'direction': direction,
      'status': status,
      'after': after,
    },
  )).map((r) => Map<String, dynamic>.unmodifiable(r.toColumnMap())).toList();

  /// Original accepted results, never the private receipt actor/payload columns.
  Future<List<ShiftSwapCommandResult>> history(
    TxSession tx,
    String request,
  ) async =>
      (await _execute(
            tx,
            '''SELECT result FROM $schema.workforce_shift_swap_commands
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)
        AND request_id=CAST(@request AS uuid) ORDER BY accepted_version''',
            {'request': request},
          ))
          .map(
            (r) => ShiftSwapCommandResult.fromJson(
              r.first as Map<String, dynamic>,
            ),
          )
          .toList();

  Future<void> request(
    TxSession tx,
    ShiftSwapCommandInput c,
    EmployeeLinkDto source,
    EmployeeLinkDto recipient,
    int sourceVersion,
    int recipientVersion,
  ) async {
    if (c.kind != 'request') throw StateError('Request command required.');
    await _execute(
      tx,
      '''INSERT INTO $schema.workforce_shift_swap_requests
      (company_id,location_id,id,source_employee_id,recipient_employee_id,source_account_id,recipient_account_id,
       source_link_id,recipient_link_id,source_account_version,recipient_account_version,request_operation_id)
      VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@request AS uuid),CAST(@source AS uuid),CAST(@recipient AS uuid),CAST(@sourceAccount AS uuid),CAST(@recipientAccount AS uuid),CAST(@sourceLink AS uuid),CAST(@recipientLink AS uuid),@sourceVersion,@recipientVersion,CAST(@operation AS uuid))''',
      {
        'request': c.payload['requestId'],
        'source': source.employeeId,
        'recipient': recipient.employeeId,
        'sourceAccount': source.accountId,
        'recipientAccount': recipient.accountId,
        'sourceLink': source.id,
        'recipientLink': recipient.id,
        'sourceVersion': sourceVersion,
        'recipientVersion': recipientVersion,
        'operation': c.operationId,
      },
    );
  }

  Future<void> captureLeg(
    TxSession tx,
    String request,
    String leg,
    ShiftDto shift,
    String incoming,
    List<Map<String, dynamic>> references,
  ) async {
    await _execute(
      tx,
      '''INSERT INTO $schema.workforce_shift_swap_legs
      (company_id,location_id,request_id,leg,source_shift_id,source_version,source_employee_id,incoming_employee_id,starts_at,ends_at,work_references)
      VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@request AS uuid),@leg,CAST(@shift AS uuid),@version,CAST(@source AS uuid),CAST(@incoming AS uuid),@start,@end,CAST(@refs AS jsonb))''',
      {
        'request': request,
        'leg': leg,
        'shift': shift.id,
        'version': shift.version,
        'source': shift.draft.employeeId,
        'incoming': incoming,
        'start': shift.draft.startsAt,
        'end': shift.draft.endsAt,
        'refs': jsonEncode(references),
      },
    );
  }

  Future<void> transition(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c, {
    bool currentSourceAuthorized = false,
  }) async {
    final row = await find(tx, request);
    if (row == null) {
      throw const PlatformFailure(404, 'not_found', 'Swap not found.');
    }
    final target = ShiftSwapRequest(
      status: row['status'] as String,
      version: row['version'] as int,
      sourceAccount: row['source_account_id'] as String,
      recipientAccount: row['recipient_account_id'] as String,
    ).transition(c, actor, currentSourceAuthorized: currentSourceAuthorized);
    final evidence = switch (c.kind) {
      'offer' =>
        'offered_by=CAST(@actor AS uuid),offered_at=clock_timestamp(),offer_operation_id=CAST(@operation AS uuid)',
      'confirm' =>
        'confirmed_by=CAST(@actor AS uuid),confirmed_at=clock_timestamp(),confirmation_operation_id=CAST(@operation AS uuid)',
      _ =>
        'terminal_by=CAST(@actor AS uuid),terminal_at=clock_timestamp(),terminal_operation_id=CAST(@operation AS uuid),terminal_kind=@kind,terminal_reason=@reason',
    };
    final rows = await _execute(
      tx,
      '''UPDATE $schema.workforce_shift_swap_requests SET status=@status,version=version+1,$evidence
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@request AS uuid) AND version=@version''',
      {
        'request': request,
        'actor': actor,
        'operation': c.operationId,
        'status': target,
        'version': c.expectedVersion,
        if (!{'offer', 'confirm'}.contains(c.kind)) ...{
          'kind': c.kind,
          'reason': c.payload['reason'],
        },
      },
    );
    if (rows.affectedRows != 1) {
      throw const PlatformFailure(409, 'swap_conflict', 'Swap changed.');
    }
  }

  Future<void> replacement(
    TxSession tx,
    String request,
    String leg,
    String replacement,
  ) async {
    final rows = await _execute(
      tx,
      '''UPDATE $schema.workforce_shift_swap_legs SET replacement_shift_id=CAST(@replacement AS uuid)
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND request_id=CAST(@request AS uuid) AND leg=@leg AND replacement_shift_id IS NULL''',
      {'request': request, 'leg': leg, 'replacement': replacement},
    );
    if (rows.affectedRows != 1) {
      throw StateError('One-time leg replacement required.');
    }
  }

  Future<ShiftSwapCommandResult?> replay(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        '''SELECT * FROM $schema.workforce_shift_swap_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)''',
      ),
      parameters: {'company': company, 'operation': c.operationId},
    );
    if (rows.isEmpty) return null;
    final r = rows.single.toColumnMap();
    if (r['request_id'] != request ||
        r['location_id'] != location ||
        r['actor_id'] != actor ||
        r['kind'] != c.kind ||
        r['expected_version'] != c.expectedVersion ||
        ShiftSwapCommandInput.fromJson(
              c.kind,
              r['payload'] as Map<String, dynamic>,
            ).canonical !=
            c.canonical) {
      throw const PlatformFailure(
        409,
        'operation_conflict',
        'Swap operation identity already exists.',
      );
    }
    return ShiftSwapCommandResult.fromJson({
      ...r['result'] as Map<String, dynamic>,
      'replayed': true,
    });
  }

  Future<void> commitReceipt(
    TxSession tx,
    String request,
    String actor,
    ShiftSwapCommandInput c,
    ShiftSwapCommandResult result,
  ) async {
    if (result.json['operationId'] != c.operationId ||
        result.json['kind'] != c.kind ||
        result.json['replayed'] != false) {
      throw StateError('Exact fresh receipt required.');
    }
    await _execute(
      tx,
      '''INSERT INTO $schema.workforce_shift_swap_commands(company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,payload,result)
      VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@operation AS uuid),CAST(@request AS uuid),CAST(@actor AS uuid),@kind,@expected,@accepted,@status,CAST(@payload AS jsonb),CAST(@result AS jsonb))''',
      {
        'request': request,
        'actor': actor,
        'operation': c.operationId,
        'kind': c.kind,
        'expected': c.expectedVersion,
        'accepted': result.json['acceptedVersion'],
        'status': result.json['statusCode'],
        'payload': c.canonical,
        'result': jsonEncode(result.toJson()),
      },
    );
  }
}
