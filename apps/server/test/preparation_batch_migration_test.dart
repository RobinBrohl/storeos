import 'dart:convert';
import 'dart:io';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'task_planogram_fixture.dart';
import '../tool/recipe_acceptance.dart';

void main() {
  test(
    'populated actual 0021 late 0022 rollback and exact legacy preservation before real batch smoke',
    () => withMerchandisingFixture((f) async {
      await seedRecipeCountEvidence(f);
      await seedRecipeCompositions(
        (method, route, body, status) async => (await f.call(
          method,
          route,
          body: body,
          expected: status,
          platform: false,
        )).body,
      );
      final r = await batchRecipe(f),
          w = await batchWorker(f, 'migration_worker');
      for (final schema in [1, 2, 3]) {
        await guidedScenario(
          f,
          schema: schema,
          workerName: 'migration_schema_$schema',
        );
      }
      await planogramTaskScenario(f);
      final tables = (await f.owner.execute(
        "SELECT tablename FROM pg_tables WHERE schemaname='${f.schema}' AND tablename<>'schema_migrations' ORDER BY tablename",
      )).map((r) => r[0] as String).toList();
      Future<String> evidence() async => jsonEncode({
        for (final table in tables)
          table: (await f.owner.execute(
            "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
          )).single.toList(),
      });
      Future<String> catalog() async => jsonEncode(
        (await f.owner.execute(
          "SELECT c.relname,c.relkind::text,c.relacl::text FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}' ORDER BY c.relname",
        )).map((r) => r.toList()).toList(),
      );
      final before = await evidence(), beforeCatalog = await catalog();
      final directory = await Directory.systemTemp.createTemp(
        'storeos_p410_failed_migration_',
      );
      try {
        for (final file in Directory(
          'migrations',
        ).listSync().whereType<File>()) {
          final name = file.uri.pathSegments.last;
          final copy = await file.copy('${directory.path}/$name');
          if (name == '0022_preparation_batches.sql') {
            await copy.writeAsString(
              '\nSELECT storeos_deliberate_late_migration_failure();\n',
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
            "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' AND p.proname LIKE 'preparation_%'",
          )).single.first,
          0,
        );
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM \"${f.schema}\".schema_migrations WHERE version='0022_preparation_batches'",
          )).single.first,
          0,
        );
      } finally {
        await directory.delete(recursive: true);
      }
      await MigrationRunner(
        connection: f.owner,
        migrationsDirectory: Directory('migrations'),
        schemaName: f.schema,
        runtimeDatabaseUser: f.runtimeUser,
      ).apply();
      expect(await evidence(), before);
      final counts = jsonDecode(before) as Map;
      for (final table in [
        'production_recipes',
        'production_recipe_revisions',
        'production_recipe_ingredients',
        'stock_levels',
        'stock_movements',
        'stock_counts',
        'stock_count_rounds',
        'stock_count_observations',
        'stock_count_commands',
        'task_template_revisions',
        'task_instances',
        'knowledge_revisions',
        'merchandising_planogram_revisions',
        'audit_entries',
      ]) {
        expect((counts[table] as List).first, greaterThan(0), reason: table);
      }
      final open = batchOpening(r), id = open['batchId'] as String;
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: open,
        expected: 201,
      );
      await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: w.token,
        body: batchComplete(),
      );
      await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        body: batchCorrection(replacement: 0),
      );
      expect(
        (await f.call(
          'GET',
          '$batchManage/$id',
        )).body['effectiveDeclaredBatchCount'],
        0,
      );
    }, legacyBefore: '0022_preparation_batches'),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
