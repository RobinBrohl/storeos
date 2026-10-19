import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import '../tool/shift_swap_recovery_acceptance.dart';
import '../tool/shift_transfer_acceptance.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

void main() {
  test(
    'recovery inventory, SHA-256, scoped HTTP replay and corruption refusal',
    () => withMerchandisingFixture((f) async {
      final pair = await stageAFixture(f);
      Future<Map<String, dynamic>> call(
        String? token,
        String method,
        String route,
        Map<String, dynamic>? body,
        int status,
      ) async => (await f.call(
        method,
        route.replaceFirst('/api/v1/platform', ''),
        token: token,
        body: body,
        expected: status,
      )).body;
      final records = await seedRecoverySwaps(
        (m, r, b, s) => call(null, m, r, b, s),
        (m, r, b, s) => call(pair.a.token, m, r, b, s),
        (m, r, b, s) => call(pair.b.token, m, r, b, s),
        merchandisingTestLocation,
        pair.a.employee,
        pair.b.employee,
        pair.template,
        pair.revision,
      );
      expect(records, hasLength(23));
      final evidence = await verifyRecoverySwaps(f.owner, f.schema);
      for (final state in (evidence['tables'] as Map).values) {
        expect(state['sha256'], matches(r'^[a-f0-9]{64}$'));
      }
      await verifyTransferHandoffClaims(f.owner, f.schema, expectedActive: 0);
      final conserved = await recoveryProjection(f.owner, f.schema, {
        ...swapRecoveryTables,
        'workforce_shift_handoff_claims': 'company_id,shift_id',
        'shifts': 'id',
        'task_instances': 'id',
        'audit_entries': 'id',
      });
      await verifyRecoverySwapReplay(
        (m, r, b, s) => call(null, m, r, b, s),
        (m, r, b, s) => call(pair.a.token, m, r, b, s),
        (m, r, b, s) => call(pair.b.token, m, r, b, s),
        records,
        merchandisingTestLocation,
      );
      expect(
        await recoveryProjection(f.owner, f.schema, {
          ...swapRecoveryTables,
          'workforce_shift_handoff_claims': 'company_id,shift_id',
          'shifts': 'id',
          'task_instances': 'id',
          'audit_entries': 'id',
        }),
        conserved,
      );
      // Owner-only corruption probes on a disposable test schema. Each mutation
      // rolls back; no privileged mutation is used to construct functional state.
      for (final sql in [
        'DELETE FROM ${f.schema}.workforce_shift_swap_commands WHERE operation_id=(SELECT operation_id FROM ${f.schema}.workforce_shift_swap_commands LIMIT 1)',
        'DELETE FROM ${f.schema}.workforce_shift_handoff_claims WHERE shift_id=(SELECT shift_id FROM ${f.schema}.workforce_shift_handoff_claims LIMIT 1)',
        "UPDATE ${f.schema}.workforce_shift_handoff_claims SET leg=CASE leg WHEN 'a' THEN 'b' ELSE 'a' END",
        "DELETE FROM ${f.schema}.task_swap_links WHERE leg='a'",
        "DELETE FROM ${f.schema}.workforce_shift_swap_legs WHERE leg='b' AND request_id=(SELECT id FROM ${f.schema}.workforce_shift_swap_requests WHERE status='approved')",
      ]) {
        await f.owner.execute('BEGIN');
        try {
          await f.owner.execute('SET LOCAL session_replication_role=replica');
          await f.owner.execute(sql);
          await expectLater(
            verifyRecoverySwaps(f.owner, f.schema),
            throwsStateError,
          );
        } finally {
          await f.owner.execute('ROLLBACK');
        }
        expect(
          jsonEncode(await verifyRecoverySwaps(f.owner, f.schema)),
          jsonEncode(evidence),
        );
      }
      await expectLater(
        f.pool.execute(
          "UPDATE ${f.schema}.workforce_shift_handoff_claims SET leg='b'",
        ),
        throwsA(
          isA<ServerException>().having((e) => e.code, 'SQLSTATE', '42501'),
        ),
      );
      await expectLater(
        f.pool.execute(
          'INSERT INTO ${f.schema}.workforce_shift_handoff_claims SELECT * FROM ${f.schema}.workforce_shift_handoff_claims LIMIT 1',
        ),
        throwsA(isA<PgException>()),
      );
      expect(await verifyRecoverySwaps(f.owner, f.schema), evidence);
    }),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
}
