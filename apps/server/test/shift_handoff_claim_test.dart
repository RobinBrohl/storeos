import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

void main() {
  test(
    'Stage A 0028 application and restricted evidence/claim grants',
    () => withMerchandisingFixture((f) async {
      try {
        await MigrationRunner(
          connection: f.owner,
          migrationsDirectory: Directory('migrations'),
          schemaName: f.schema,
          runtimeDatabaseUser: f.runtimeUser,
        ).apply();
      } on ServerException catch (e) {
        fail(
          'Migration SQL position ${e.position}, internal position ${e.internalPosition}, internal query ${e.internalQuery}: ${e.message}',
        );
      }
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.schema_migrations",
        )).single.first,
        28,
      );
      await f.pool.runTx((tx) async {
        final rows = await tx.execute(
          '''SELECT
        has_table_privilege(current_user,'${f.schema}.workforce_shift_handoff_claims','SELECT,INSERT,DELETE'),
        has_table_privilege(current_user,'${f.schema}.workforce_shift_handoff_claims','UPDATE'),
        has_table_privilege(current_user,'${f.schema}.workforce_shift_handoff_claims','TRUNCATE'),
        has_column_privilege(current_user,'${f.schema}.workforce_shift_swap_requests','status','UPDATE'),
        has_column_privilege(current_user,'${f.schema}.workforce_shift_swap_requests','source_account_id','UPDATE')''',
        );
        expect(rows.single.toList(), [true, false, false, true, false]);
      });
      for (final table in [
        'workforce_shift_swap_requests',
        'workforce_shift_swap_legs',
        'workforce_shift_swap_commands',
        'task_swap_links',
      ]) {
        expect(
          (await f.owner.execute(
            "SELECT has_table_privilege('${f.runtimeUser}','${f.schema}.$table','DELETE,TRUNCATE')",
          )).single.first,
          false,
        );
      }
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' AND p.prosecdef",
        )).single.first,
        0,
      );
    }, legacyBefore: '0028_bilateral_shift_swaps'),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
  test(
    'Stage A SQL NULL and malformed typed ownership rejects under runtime',
    () => withMerchandisingFixture((f) async {
      for (final tuple in [
        'NULL,NULL,NULL',
        "NULL,'33333333-3333-4333-8333-333333333333',NULL",
        "NULL,'33333333-3333-4333-8333-333333333333','x'",
        "'33333333-3333-4333-8333-333333333333','33333333-3333-4333-8333-333333333333','a'",
      ]) {
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              '''INSERT INTO ${f.schema}.workforce_shift_handoff_claims(company_id,location_id,shift_id,transfer_request_id,swap_request_id,leg)
        VALUES('$merchandisingTestCompany','$merchandisingTestLocation','44444444-4444-4444-8444-444444444444',$tuple)''',
            ),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.constraintName,
              'constraint',
              'handoff_owner_shape',
            ),
          ),
        );
      }
    }),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
}
