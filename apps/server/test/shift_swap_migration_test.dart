import 'dart:convert';
import 'dart:io';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import '../tool/shift_transfer_acceptance.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_legacy_fixture.dart';

void main() {
  test(
    'Stage A actual populated 0027 late rollback, exact active/stale backfill and historical replay',
    () => withMerchandisingFixture((f) async {
      final seed = await seedActual0027Transfers(f);
      final tables = (await f.owner.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname='${f.schema}' AND tablename<>'schema_migrations' ORDER BY tablename",
      )).map((r) => r[0] as String).toList();
      // Hash every original field. New nullable provenance is checked separately;
      // adding its keys to to_jsonb must not disguise changes to old evidence.
      String originalRow(String table) => table == 'shifts'
          ? "(to_jsonb(x)-ARRAY['swap_request_id','swap_leg'])"
          : 'to_jsonb(x)';
      Future<String> evidence() async => jsonEncode({
        for (final t in tables)
          t: (await f.owner.execute(
            "SELECT count(*),md5(string_agg(${originalRow(t)}::text,'' ORDER BY ${originalRow(t)}::text)) FROM ${f.schema}.$t x",
          )).single.toList(),
      });
      Future<String> catalog() async => jsonEncode({
        for (final e in {
          'relations':
              "SELECT c.relname,c.relkind::text,c.relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}' ORDER BY c.relname",
          'constraints':
              "SELECT c.conname,pg_get_constraintdef(c.oid) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='${f.schema}' ORDER BY c.conname,pg_get_constraintdef(c.oid)",
          'functions':
              "SELECT p.proname,pg_get_functiondef(p.oid),p.proacl::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' ORDER BY p.proname,pg_get_functiondef(p.oid)",
          'triggers':
              "SELECT c.relname,t.tgname,pg_get_triggerdef(t.oid) FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}' ORDER BY c.relname,t.tgname",
          'grants':
              "SELECT table_name,column_name,grantee,privilege_type FROM information_schema.column_privileges WHERE table_schema='${f.schema}' ORDER BY table_name,column_name,grantee,privilege_type",
          'versions':
              "SELECT version,checksum FROM ${f.schema}.schema_migrations ORDER BY version",
        }.entries)
          e.key: (await f.owner.execute(
            e.value,
          )).map((r) => r.toList()).toList(),
      });
      final before = await evidence(), beforeCatalog = await catalog();
      final states = (await f.owner.execute(
        "SELECT status,count(*) FROM ${f.schema}.workforce_shift_transfer_requests GROUP BY status ORDER BY status",
      )).map((r) => r.toList()).toList();
      expect(states, [
        ['accepted', 2],
        ['approved', 1],
        ['declined', 1],
        ['proposed', 2],
        ['rejected', 2],
        ['withdrawn', 3],
      ]);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.task_transfer_links",
        )).single.first,
        1,
      );
      final directory = await Directory.systemTemp.createTemp(
        'storeos_p416_late_rollback_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last,
              copy = await file.copy('${directory.path}/$name');
          if (name == '0028_bilateral_shift_swaps.sql') {
            await copy.writeAsString(
              '\nSELECT storeos_p416_deliberate_failure_after_backfill();\n',
              mode: FileMode.append,
            );
          }
        }
        await expectLater(
          MigrationRunner(
            connection: f.owner,
            migrationsDirectory: directory,
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          ).apply(),
          throwsA(isA<Exception>()),
        );
        expect(await evidence(), before);
        expect(await catalog(), beforeCatalog);
        expect(
          (await f.owner.execute(
            "SELECT to_regclass('${f.schema}.workforce_shift_handoff_claims')",
          )).single.first,
          null,
        );
      } finally {
        final tempRoot = Directory.systemTemp.resolveSymbolicLinksSync(),
            target = directory.resolveSymbolicLinksSync();
        if (!target.startsWith(
          '$tempRoot${Platform.pathSeparator}storeos_p416_late_rollback_',
        )) {
          throw StateError('Unexpected rollback fixture cleanup target.');
        }
        await directory.delete(recursive: true);
      }
      final runner = MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      );
      expect(await runner.apply(), ['0028_bilateral_shift_swaps']);
      expect(await evidence(), before);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM ${f.schema}.shifts WHERE swap_request_id IS NOT NULL OR swap_leg IS NOT NULL',
        )).single.first,
        0,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
        )).single.first,
        4,
      );
      expect(
        (await f.owner.execute(
          '''SELECT count(*) FROM ${f.schema}.workforce_shift_transfer_requests r
      LEFT JOIN ${f.schema}.workforce_shift_handoff_claims c ON c.company_id=r.company_id AND c.transfer_request_id=r.id AND c.location_id=r.location_id AND c.shift_id=r.source_shift_id
      WHERE (r.status IN ('proposed','accepted')) IS DISTINCT FROM (c.shift_id IS NOT NULL)''',
        )).single.first,
        0,
      );
      expect(
        (await f.owner.execute(
          '''SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims c JOIN ${f.schema}.workforce_shift_transfer_requests r ON r.company_id=c.company_id AND r.id=c.transfer_request_id
      JOIN ${f.schema}.shifts s ON s.company_id=r.company_id AND s.id=r.source_shift_id WHERE s.status='cancelled' OR s.version<>r.source_version''',
        )).single.first,
        2,
      );
      expect(await runner.apply(), isEmpty);
      expect(await evidence(), before);
      final source = await f.auth.authenticate(
            await f.login('legacy_transfer_a'),
          ),
          recipient = await f.auth.authenticate(
            await f.login('legacy_transfer_b'),
          );
      await verifyShiftTransfers(
        f.database,
        f.adminPrincipal,
        source,
        recipient,
        seed['records'] as List,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
        )).single.first,
        4,
      );
    }, legacyBefore: '0028_bilateral_shift_swaps'),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
