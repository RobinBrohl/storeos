import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_journey_fixture.dart';

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
void main() {
  test(
    'real populated 0023 to 0024, late catalog/grant rollback and encrypted fenced pre-0024 recovery',
    () async {
      await withMerchandisingFixture(
        (f) async {
          await seedPurchasingLegacy(f);
          final before = await purchasingLegacyEvidence(f),
              beforeCatalog = await catalog(f),
              temporary = await Directory.systemTemp.createTemp(
                'storeos_p412_recovery_',
              ),
              target =
                  'storeos_restore_p412_${newUuid().replaceAll('-', '').substring(0, 16)}';
          Connection? restored;
          bool targetCreated = false;
          try {
            final backup = await Process.run('pwsh', [
              '-NoProfile',
              '-File',
              '../../infra/backup/Backup-StoreOS.ps1',
              '-Database',
              'storeos_p412_test',
              '-BackupDirectory',
              temporary.path,
            ]);
            expect(
              backup.exitCode,
              0,
              reason: 'Encrypted pre-0024 backup failed.',
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
              '${migrations.path}/0024_bounded_purchase_orders.sql',
            ).writeAsString('\nSELECT 1/0;\n', mode: FileMode.append);
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
            expect(await purchasingLegacyEvidence(f), before);
            expect(
              (await f.owner.execute(
                "SELECT to_regclass('${f.schema}.purchasing_orders')",
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
                '0024_bounded_purchase_orders',
                '0025_planned_preparation_assignments',
              ],
            );
            expect(await purchasingLegacyEvidence(f), before);
            expect(
              await MigrationRunner(
                connection: f.owner,
                migrationsDirectory: Directory('migrations'),
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              isEmpty,
            );
            await populated(f);
            final source = await purchasingEvidence(f),
                legacyAfter = await purchasingLegacyEvidence(f);
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
              reason: 'Encrypted pre-0024 recovery failed.',
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
              '0023_one_way_shift_transfers',
            );
            expect(
              (await restored.execute(
                "SELECT to_regclass('storeos_platform.purchasing_orders')",
              )).single.first,
              isNull,
            );
            expect(
              (await restored.execute(
                "SELECT count(*) FROM pg_constraint WHERE conname='purchasing_account_company_anchor'",
              )).single.first,
              0,
            );
            for (final table in purchasingLegacyTables) {
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
            expect(await purchasingLegacyEvidence(f), legacyAfter);
          } finally {
            await restored?.close();
            if (targetCreated) {
              if (!RegExp(
                r'^storeos_restore_p412_[a-f0-9]{16}$',
              ).hasMatch(target)) {
                throw StateError('Invalid recovery cleanup target.');
              }
              await f.owner.execute('DROP DATABASE IF EXISTS "$target"');
            }
            await temporary.delete(recursive: true);
          }
        },
        legacyBefore: '0024_bounded_purchase_orders.sql',
        fixedSchema: 'storeos_platform',
      );
    },
    skip:
        Platform.environment['STOREOS_PURCHASING_MIGRATION_RECOVERY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Dedicated isolated P4.12 encrypted migration/recovery opt-in required.',
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
