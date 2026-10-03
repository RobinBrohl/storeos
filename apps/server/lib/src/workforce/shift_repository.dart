import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'shift.dart';

class ShiftRepository {
  ShiftRepository(this.schema, this.companyId);
  final String schema, companyId;
  Map<String, dynamic> get _scope => {'company': companyId};
  String get _select =>
      '''SELECT s.id::text, s.company_id::text, s.location_id::text, s.employee_id::text,
    s.starts_at, s.ends_at, s.status, s.version, s.created_at, s.updated_at, s.published_at, s.publication_version,
    s.created_by::text, s.creation_input, s.cancelled_at, s.cancelled_by::text, s.cancellation_reason, s.cancellation_version,
    s.amended_at, s.amended_by::text, s.amendment_version,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('templateId',template_id::text,'revisionId',revision_id::text) ORDER BY position)
      FROM $schema.shift_template_selections WHERE shift_id=s.id),'[]'::jsonb) AS selections
    FROM $schema.shifts s WHERE s.company_id=CAST(@company AS uuid)''';
  Shift _row(Map<String, dynamic> r) => Shift(
    ShiftDto(
      id: r['id'] as String,
      companyId: r['company_id'] as String,
      locationId: r['location_id'] as String,
      version: r['version'] as int,
      status: r['status'] as String,
      draft: ShiftDraftInput(
        employeeId: r['employee_id'] as String,
        startsAt: (r['starts_at'] as DateTime).toUtc(),
        endsAt: (r['ends_at'] as DateTime).toUtc(),
        selections: (r['selections'] as List)
            .map(
              (v) => ShiftTemplateSelection.fromJson(
                Map<String, dynamic>.from(v as Map),
              ),
            )
            .toList(),
      ),
      createdAt: r['created_at'] as DateTime,
      updatedAt: r['updated_at'] as DateTime,
      publishedAt: r['published_at'] as DateTime?,
      publicationVersion: r['publication_version'] as int?,
      cancelledAt: r['cancelled_at'] as DateTime?,
      cancelledBy: r['cancelled_by'] as String?,
      cancellationReason: r['cancellation_reason'] as String?,
      cancellationVersion: r['cancellation_version'] as int?,
      amendedAt: r['amended_at'] as DateTime?,
      amendedBy: r['amended_by'] as String?,
      amendmentVersion: r['amendment_version'] as int?,
    ),
    r['creation_input'] as String,
    r['created_by'] as String,
  );
  Future<Shift?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named('$_select AND s.id=CAST(@id AS uuid)'),
      parameters: {..._scope, 'id': id},
    );
    return rows.isEmpty ? null : _row(rows.single.toColumnMap());
  }

  Future<List<Shift>> page(
    TxSession tx, {
    String? employeeId,
    String? locationId,
    DateTime? afterTime,
    String? afterId,
  }) async => (await tx.execute(
    Sql.named('''$_select
      AND (CAST(@employee AS uuid) IS NULL OR (s.employee_id=CAST(@employee AS uuid) AND s.location_id=CAST(@location AS uuid) AND s.status='published' AND s.ends_at>clock_timestamp()))
      AND (CAST(@afterTime AS timestamptz) IS NULL OR (s.starts_at,s.id)>(CAST(@afterTime AS timestamptz),CAST(@afterId AS uuid)))
      ORDER BY s.starts_at,s.id LIMIT 51'''),
    parameters: {
      ..._scope,
      'employee': employeeId,
      'location': locationId,
      'afterTime': afterTime,
      'afterId': afterId,
    },
  )).map((r) => _row(r.toColumnMap())).toList();
  Future<void> insert(
    TxSession tx,
    String id,
    String locationId,
    String actorId,
    ShiftDraftInput input,
  ) async {
    await tx.execute(
      Sql.named(
        '''INSERT INTO $schema.shifts(id,company_id,location_id,employee_id,starts_at,ends_at,created_by,creation_input)
      VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@employee AS uuid),@start,@end,CAST(@actor AS uuid),@input)''',
      ),
      parameters: {
        ..._scope,
        'id': id,
        'location': locationId,
        'employee': input.employeeId,
        'start': input.startsAt,
        'end': input.endsAt,
        'actor': actorId,
        'input': jsonEncode(input.toJson()),
      },
    );
    await selections(tx, id, locationId, input.selections);
  }

  Future<void> selections(
    TxSession tx,
    String id,
    String locationId,
    List<ShiftTemplateSelection> items,
  ) async {
    await tx.execute(
      Sql.named(
        'DELETE FROM $schema.shift_template_selections WHERE shift_id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      ),
      parameters: {..._scope, 'id': id},
    );
    for (var i = 0; i < items.length; i++) {
      await tx.execute(
        Sql.named(
          '''INSERT INTO $schema.shift_template_selections(shift_id,company_id,location_id,template_id,revision_id,position)
        VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@template AS uuid),CAST(@revision AS uuid),@position)''',
        ),
        parameters: {
          ..._scope,
          'id': id,
          'location': locationId,
          'template': items[i].templateId,
          'revision': items[i].revisionId,
          'position': i,
        },
      );
    }
  }

  Future<void> edit(TxSession tx, Shift current, ShiftDraftInput input) async {
    final changed = await tx.execute(
      Sql.named(
        '''UPDATE $schema.shifts SET employee_id=CAST(@employee AS uuid),starts_at=@start,ends_at=@end,version=version+1,updated_at=clock_timestamp()
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version AND status='draft' ''',
      ),
      parameters: {
        ..._scope,
        'id': current.view.id,
        'version': current.view.version,
        'employee': input.employeeId,
        'start': input.startsAt,
        'end': input.endsAt,
      },
    );
    if (changed.affectedRows != 1) throw ShiftConflict();
    await selections(
      tx,
      current.view.id,
      current.view.locationId,
      input.selections,
    );
  }

  Future<bool> overlapsWindow(
    TxSession tx,
    String id,
    String employeeId,
    DateTime startsAt,
    DateTime endsAt,
  ) async => (await tx.execute(
    Sql.named('''SELECT 1 FROM $schema.shifts
    WHERE company_id=CAST(@company AS uuid) AND employee_id=CAST(@employee AS uuid) AND id<>CAST(@id AS uuid)
    AND status='published' AND starts_at<@end AND ends_at>@start LIMIT 1'''),
    parameters: {
      ..._scope,
      'id': id,
      'employee': employeeId,
      'start': startsAt,
      'end': endsAt,
    },
  )).isNotEmpty;

  Future<bool> overlaps(TxSession tx, Shift current) => overlapsWindow(
    tx,
    current.view.id,
    current.view.draft.employeeId,
    current.view.draft.startsAt,
    current.view.draft.endsAt,
  );
  Future<void> publish(TxSession tx, Shift current, String actorId) async {
    final result = await tx.execute(
      Sql.named(
        '''UPDATE $schema.shifts SET status='published',version=version+1,updated_at=clock_timestamp(),published_at=clock_timestamp(),published_by=CAST(@actor AS uuid),publication_version=@version
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version AND status='draft' ''',
      ),
      parameters: {
        ..._scope,
        'id': current.view.id,
        'actor': actorId,
        'version': current.view.version,
      },
    );
    if (result.affectedRows != 1) throw ShiftConflict();
  }

  Future<void> amend(
    TxSession tx,
    Shift current,
    String actorId,
    DateTime startsAt,
    DateTime endsAt,
    DateTime now,
  ) async {
    final result = await tx.execute(
      Sql.named(
        '''UPDATE $schema.shifts SET starts_at=@start,ends_at=@end,version=version+1,updated_at=clock_timestamp(),
      amended_at=@now,amended_by=CAST(@actor AS uuid),amendment_version=@version
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version AND status='published' ''',
      ),
      parameters: {
        ..._scope,
        'id': current.view.id,
        'actor': actorId,
        'start': startsAt,
        'end': endsAt,
        'version': current.view.version,
        'now': now,
      },
    );
    if (result.affectedRows != 1) throw ShiftConflict();
  }

  Future<void> cancel(
    TxSession tx,
    Shift current,
    String actorId,
    String reason,
    DateTime now,
  ) async {
    final result = await tx.execute(
      Sql.named(
        '''UPDATE $schema.shifts SET status='cancelled',version=version+1,updated_at=clock_timestamp(),
      cancelled_at=@now,cancelled_by=CAST(@actor AS uuid),cancellation_reason=@reason,cancellation_version=@version
      WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) AND version=@version AND status='published' ''',
      ),
      parameters: {
        ..._scope,
        'id': current.view.id,
        'actor': actorId,
        'reason': reason,
        'version': current.view.version,
        'now': now,
      },
    );
    if (result.affectedRows != 1) throw ShiftConflict();
  }
}
