import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'shift_transfer.dart';

/// Private Workforce persistence. Foreign modules are accessed through ports.
class ShiftTransferRepository {
  ShiftTransferRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Future<Result> _execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(
        Sql.named(sql),
        parameters: {'company': company, 'location': location, ...p},
      );
  Map<String, dynamic> _row(ResultRow row) => {
    for (final e in row.toColumnMap().entries)
      if (!{'proposal_kind', 'acceptance_kind'}.contains(e.key))
        e.key.replaceAllMapped(
          RegExp(r'_([a-z])'),
          (m) => m[1]!.toUpperCase(),
        ): e.value is DateTime
            ? (e.value as DateTime).toUtc().toIso8601String()
            : e.value,
  };
  String get _select =>
      'SELECT * FROM $schema.workforce_shift_transfer_requests WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)';
  Future<Map<String, dynamic>?> find(TxSession tx, String id) async {
    final rows = await _execute(tx, '$_select AND id=CAST(@id AS uuid)', {
      'id': id,
    });
    return rows.isEmpty ? null : _row(rows.single);
  }

  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    String? employee,
    String? direction,
    String? status,
    String? after,
  }) async => (await _execute(
    tx,
    '''$_select
      AND (CAST(@employee AS uuid) IS NULL OR
        ((CAST(@direction AS text) IS NULL OR @direction='outgoing') AND source_employee_id=CAST(@employee AS uuid)) OR
        ((CAST(@direction AS text) IS NULL OR @direction='incoming') AND recipient_employee_id=CAST(@employee AS uuid)))
      AND (CAST(@status AS text) IS NULL OR status=@status)
      AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51''',
    {
      'employee': employee,
      'direction': direction,
      'status': status,
      'after': after,
    },
  )).map(_row).toList();
  Future<void> propose(
    TxSession tx,
    ShiftDto shift,
    EmployeeLinkDto source,
    EmployeeLinkDto recipient,
    int sourceAccountVersion,
    int recipientAccountVersion,
    ShiftTransferCommandInput c,
  ) async {
    await _execute(
      tx,
      '''INSERT INTO $schema.workforce_shift_transfer_requests
      (company_id,location_id,id,source_shift_id,source_version,source_employee_id,recipient_employee_id,starts_at,ends_at,proposed_by,source_link_id,recipient_link_id,recipient_account_id,source_account_version,recipient_account_version,proposal_operation_id)
      VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@shift AS uuid),@version,CAST(@source AS uuid),CAST(@recipient AS uuid),@start,@end,CAST(@actor AS uuid),CAST(@sourceLink AS uuid),CAST(@recipientLink AS uuid),CAST(@recipientAccount AS uuid),@sourceAccountVersion,@recipientAccountVersion,CAST(@operation AS uuid))''',
      {
        'id': c.payload['requestId'],
        'shift': shift.id,
        'version': shift.version,
        'source': source.employeeId,
        'recipient': recipient.employeeId,
        'start': shift.draft.startsAt,
        'end': shift.draft.endsAt,
        'actor': source.accountId,
        'sourceLink': source.id,
        'recipientLink': recipient.id,
        'recipientAccount': recipient.accountId,
        'sourceAccountVersion': sourceAccountVersion,
        'recipientAccountVersion': recipientAccountVersion,
        'operation': c.operationId,
      },
    );
  }

  Future<void> transition(
    TxSession tx,
    String id,
    String actor,
    ShiftTransferCommandInput c, {
    String? replacement,
  }) async {
    final accept = c.kind == 'accept';
    await _execute(
      tx,
      '''UPDATE $schema.workforce_shift_transfer_requests SET status=@status,version=version+1,
      ${accept ? 'accepted_by=CAST(@actor AS uuid),accepted_at=clock_timestamp(),acceptance_operation_id=CAST(@operation AS uuid)' : 'terminal_by=CAST(@actor AS uuid),terminal_at=clock_timestamp(),terminal_operation_id=CAST(@operation AS uuid),terminal_kind=@kind,terminal_reason=@reason,replacement_shift_id=CAST(@replacement AS uuid)'}
      WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid) AND version=@version''',
      {
        'id': id,
        'actor': actor,
        'operation': c.operationId,
        'status': ShiftTransferRequest.target(c.kind),
        'version': c.expectedVersion,
        if (!accept) ...{
          'kind': c.kind,
          'reason': c.payload['reason'],
          'replacement': replacement,
        },
      },
    );
  }

  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT * FROM $schema.workforce_shift_transfer_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': company, 'operation': operation},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<void> commitReceipt(
    TxSession tx,
    String id,
    String actor,
    ShiftTransferCommandInput c,
    Map<String, dynamic> result,
  ) async {
    await _execute(
      tx,
      '''INSERT INTO $schema.workforce_shift_transfer_commands(company_id,operation_id,location_id,request_id,actor_id,kind,expected_version,payload,result)
      VALUES(CAST(@company AS uuid),CAST(@operation AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),CAST(@actor AS uuid),@kind,@version,CAST(@payload AS jsonb),CAST(@result AS jsonb))''',
      {
        'id': id,
        'actor': actor,
        'operation': c.operationId,
        'kind': c.kind,
        'version': c.expectedVersion,
        'payload': c.canonical,
        'result': jsonEncode(result),
      },
    );
  }
}
