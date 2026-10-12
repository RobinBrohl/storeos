import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_journey_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'preparation_assignment_integration_test.dart'
    show manage, self, request, start;
import 'task_planogram_fixture.dart';

Future<List<Object?>> catalog(MerchandisingFixture f) async => [
  for (final query in [
    "SELECT md5(string_agg(jsonb_build_array(c.oid,c.relname,c.relkind,c.relowner,c.relacl,c.relpersistence,c.reloptions,c.reltablespace,c.reltype,c.relchecks,c.relhasrules,c.relhastriggers,c.relrowsecurity,c.relforcerowsecurity)::text,'' ORDER BY c.oid)) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}'",
    "SELECT md5(string_agg(to_jsonb(c)::text,'' ORDER BY c.oid)) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace WHERE n.nspname='${f.schema}'",
    "SELECT md5(string_agg(to_jsonb(p)::text,'' ORDER BY p.oid)) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}'",
    "SELECT md5(string_agg(to_jsonb(a)::text,'' ORDER BY a.attrelid,a.attnum)) FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='${f.schema}'",
    "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY version)) FROM \"${f.schema}\".schema_migrations t",
    "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY id)) FROM \"${f.schema}\".audit_entries t",
  ])
    (await f.owner.execute(query)).single.first,
];
const priorTables = [
  ...purchasingLegacyTables,
  'purchasing_suppliers',
  'purchasing_orders',
  'purchasing_order_lines',
  'purchasing_commands',
  'merchandising_fixtures',
  'merchandising_planograms',
  'merchandising_planogram_revisions',
  'merchandising_planogram_assignments',
  'audit_entries',
];
Future<Map<String, Object?>> priorEvidence(MerchandisingFixture f) async => {
  for (final table in priorTables)
    table: (await f.owner.execute(
      "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
    )).single.toList(),
};
Future<List<Object?>> assignmentHash(MerchandisingFixture f) async => [
  for (final t in [
    'production_preparation_assignments',
    'production_preparation_assignment_commands',
  ])
    (await f.owner.execute(
      "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$t t",
    )).single.first,
];

void main() {
  test(
    'real populated 0024 to 0025, late catalog/grant rollback and encrypted fenced pre-0025 recovery',
    () async {
      await withMerchandisingFixture(
        (f) async {
          await seedPurchasingLegacy(f);
          await deployment(f);
          final order = await populated(f);
          final issued =
              (await f.call(
                    'POST',
                    '$purchasingOrders/${order['id']}/issue',
                    body: {
                      'operationId': newUuid(),
                      'expectedVersion': order['version'],
                    },
                  )).body['order']
                  as Map;
          await f.call(
            'POST',
            '$purchasingOrders/${order['id']}/close',
            body: {
              'operationId': newUuid(),
              'expectedVersion': issued['version'],
              'reason': 'Preserved pre-update close evidence',
            },
          );
          final before = await priorEvidence(f),
              beforeCatalog = await catalog(f),
              temporary = await Directory.systemTemp.createTemp(
                'storeos_p413_recovery_',
              ),
              target =
                  'storeos_restore_p413_${newUuid().replaceAll('-', '').substring(0, 16)}';
          Connection? restored;
          bool targetCreated = false;
          try {
            final backup = await Process.run('pwsh', [
              '-NoProfile',
              '-File',
              '../../infra/backup/Backup-StoreOS.ps1',
              '-Database',
              Uri.parse(
                Platform.environment['STOREOS_TEST_DATABASE']!,
              ).pathSegments.single,
              '-BackupDirectory',
              temporary.path,
            ]);
            expect(
              backup.exitCode,
              0,
              reason: 'Encrypted pre-0025 backup failed.',
            );
            final encrypted = temporary
                .listSync()
                .whereType<File>()
                .singleWhere((f) => f.path.endsWith('.sodb'));
            expect(encrypted.lengthSync(), greaterThan(0));
            final migrations = Directory('${temporary.path}/migrations')
              ..createSync();
            for (final file in Directory(
              'migrations',
            ).listSync().whereType<File>()) {
              await file.copy(
                '${migrations.path}/${file.uri.pathSegments.last}',
              );
            }
            await File(
              '${migrations.path}/0025_planned_preparation_assignments.sql',
            ).writeAsString(r'''
CREATE FUNCTION {{schema}}.p413_late_migration_fault() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Acceptance fault after grants and ledger insertion' USING ERRCODE='23514'; END $$;
CREATE CONSTRAINT TRIGGER p413_late_migration_fault AFTER INSERT ON {{schema}}.schema_migrations
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.p413_late_migration_fault();
''', mode: FileMode.append);
            await expectLater(
              MigrationRunner(
                connection: f.owner,
                migrationsDirectory: migrations,
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              throwsA(isA<ServerException>()),
            );
            expect(await catalog(f), beforeCatalog);
            expect(await priorEvidence(f), before);
            expect(
              (await f.owner.execute(
                "SELECT to_regclass('${f.schema}.production_preparation_assignments')",
              )).single.first,
              isNull,
            );
            expect(
              await MigrationRunner(
                connection: f.owner,
                migrationsDirectory: Directory('migrations'),
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              [
                '0025_planned_preparation_assignments',
                '0026_purchase_order_delivery_evidence',
                '0027_article_quantities',
              ],
            );
            expect(await priorEvidence(f), before);
            expect(
              await MigrationRunner(
                connection: f.owner,
                migrationsDirectory: Directory('migrations'),
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              isEmpty,
            );
            final worker = await batchWorker(f, 'upgrade_assignment_worker'),
                recipe = await existingBatchRecipe(f),
                c = request(recipe, worker);
            await f.call('POST', manage, body: c, expected: 201);
            final started = (await f.call(
              'POST',
              '$self/${c['id']}/start',
              token: worker.token,
              body: start(),
            )).body;
            expect(
              (started['assignment'] as Map)['batchId'],
              (started['batch'] as Map)['batchId'],
            );
            final assignmentsBefore = await assignmentHash(f);
            final source = await purchasingEvidence(f),
                legacyAfter = await priorEvidence(f);
            targetCreated = true;
            final recover = await Process.run('pwsh', [
              '-NoProfile',
              '-File',
              '../../infra/backup/Restore-StoreOS.ps1',
              '-BackupPath',
              encrypted.path,
              '-TargetDatabase',
              target,
            ]);
            expect(
              recover.exitCode,
              0,
              reason: 'Encrypted pre-0025 recovery failed.',
            );
            final uri = Uri.parse(
                  Platform.environment['STOREOS_TEST_DATABASE']!,
                ),
                user = uri.userInfo.split(':');
            restored = await Connection.open(
              Endpoint(
                host: uri.host,
                port: uri.port,
                database: target,
                username: Uri.decodeComponent(user[0]),
                password: Uri.decodeComponent(user[1]),
              ),
              settings: const ConnectionSettings(sslMode: SslMode.disable),
            );
            expect(
              (await restored.execute(
                'SELECT version FROM storeos_platform.schema_migrations ORDER BY version DESC LIMIT 1',
              )).single.first,
              '0024_bounded_purchase_orders',
            );
            expect(
              (await restored.execute(
                "SELECT to_regclass('storeos_platform.production_preparation_assignments')",
              )).single.first,
              isNull,
            );
            expect(
              (await restored.execute(
                "SELECT count(*) FROM pg_constraint WHERE conname='preparation_batch_assignment_anchor'",
              )).single.first,
              0,
            );
            for (final table in priorTables) {
              expect(
                (await restored.execute(
                  "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM storeos_platform.$table t",
                )).single.toList(),
                before[table],
              );
            }
            expect(
              (await restored.execute(
                "SELECT has_database_privilege('storeos',current_database(),'CONNECT')",
              )).single.first,
              false,
            );
            expect(
              (await restored.execute(
                'SELECT count(*) FROM storeos_platform.auth_sessions WHERE revoked_at IS NULL',
              )).single.first,
              0,
            );
            expect(await purchasingEvidence(f), source);
            expect(await priorEvidence(f), legacyAfter);
            expect(await assignmentHash(f), assignmentsBefore);
          } finally {
            await restored?.close();
            if (targetCreated) {
              if (!RegExp(
                r'^storeos_restore_p413_[a-f0-9]{16}$',
              ).hasMatch(target)) {
                throw StateError('Invalid recovery cleanup target.');
              }
              await f.owner.execute('DROP DATABASE IF EXISTS "$target"');
            }
            await temporary.delete(recursive: true);
          }
        },
        legacyBefore: '0025_planned_preparation_assignments.sql',
        fixedSchema: 'storeos_platform',
      );
    },
    skip:
        Platform.environment['STOREOS_PURCHASING_MIGRATION_RECOVERY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Dedicated isolated P4.13 encrypted migration/recovery opt-in required.',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
