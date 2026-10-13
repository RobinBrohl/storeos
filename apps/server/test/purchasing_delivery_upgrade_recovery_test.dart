import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_journey_fixture.dart';
import 'purchasing_delivery_test.dart'
    show issued, declareBody, deliveryEvidence;
import 'preparation_batch_fixture.dart';
import 'preparation_assignment_integration_test.dart' show manage, request;
import 'preparation_assignment_upgrade_recovery_test.dart'
    show catalog, priorTables;

void main() {
  test(
    'populated 0025 to 0026: deferred post-grant rollback, encrypted fenced pre-0026 recovery and unchanged source',
    () async {
      await withMerchandisingFixture(
        (f) async {
          await seedPurchasingLegacy(f);
          final recipe = await existingBatchRecipe(f),
              worker = await batchWorker(f, 'p414_upgrade_worker');
          await f.call(
            'POST',
            manage,
            body: request(recipe, worker),
            expected: 201,
          );
          final legacy = await issued(f),
              root = '$purchasingOrders/${legacy['id']}';
          await f.call(
            'POST',
            '$root/close',
            body: {
              'operationId': newUuid(),
              'expectedVersion': legacy['version'],
              'reason': 'Legacy closed before tracking',
            },
          );
          final tables = [
            ...priorTables,
            'production_preparation_assignments',
            'production_preparation_assignment_commands',
          ];
          // Compare every pre-upgrade field; assert new NULL anchors separately.
          String originalRow(String table) => table == 'shifts'
              ? "(to_jsonb(t)-ARRAY['swap_request_id','swap_leg'])"
              : 'to_jsonb(t)';
          Future<Map<String, Object?>> evidence(
            Connection connection,
          ) async => {
            for (final t in tables)
              t: (await connection.execute(
                "SELECT count(*),md5(string_agg(${originalRow(t)}::text,'' ORDER BY ${originalRow(t)}::text)) FROM storeos_platform.$t t",
              )).single.toList(),
          };
          final before = await evidence(f.owner),
              schemaBefore = await catalog(f),
              temporary = await Directory.systemTemp.createTemp(
                'storeos_p414_recovery_',
              ),
              target =
                  'storeos_restore_p414_${newUuid().replaceAll('-', '').substring(0, 16)}';
          Connection? restored;
          bool targetCreated = false;
          try {
            final uri = Uri.parse(
              Platform.environment['STOREOS_TEST_DATABASE']!,
            );
            final backup = await Process.run('pwsh', [
              '-NoProfile',
              '-File',
              '../../infra/backup/Backup-StoreOS.ps1',
              '-Database',
              uri.pathSegments.single,
              '-BackupDirectory',
              temporary.path,
            ]);
            expect(
              backup.exitCode,
              0,
              reason: 'Encrypted pre-0026 backup failed.',
            );
            final encrypted = temporary
                .listSync()
                .whereType<File>()
                .singleWhere((f) => f.path.endsWith('.sodb'));
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
              '${migrations.path}/0026_purchase_order_delivery_evidence.sql',
            ).writeAsString(r'''
CREATE FUNCTION {{schema}}.p414_late_migration_fault() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Late migration acceptance fault' USING ERRCODE='23514'; END $$;
CREATE CONSTRAINT TRIGGER p414_late_migration_fault AFTER INSERT ON {{schema}}.schema_migrations
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.p414_late_migration_fault();
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
            expect(await catalog(f), schemaBefore);
            expect(await evidence(f.owner), before);
            expect(
              await MigrationRunner(
                connection: f.owner,
                migrationsDirectory: Directory('migrations'),
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              [
                '0026_purchase_order_delivery_evidence',
                '0027_article_quantities',
                '0028_bilateral_shift_swaps',
              ],
            );
            expect(await evidence(f.owner), before);
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM ${f.schema}.shifts WHERE swap_request_id IS NOT NULL OR swap_leg IS NOT NULL',
              )).single.first,
              0,
            );
            expect(
              await MigrationRunner(
                connection: f.owner,
                migrationsDirectory: Directory('migrations'),
                schemaName: f.schema,
                runtimeDatabaseUser: f.runtimeUser,
              ).apply(),
              isEmpty,
            );
            expect(
              (await f.call(
                'GET',
                '$root/delivery-summary',
              )).body['trackingAtClosure'],
              'unavailable',
            );
            final o = await issued(f);
            await f.call(
              'POST',
              '$purchasingOrders/${o['id']}/deliveries',
              body: declareBody(o),
              expected: 201,
            );
            final source = await deliveryEvidence(f),
                sourcePrior = await evidence(f.owner);
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
              reason: 'Encrypted pre-0026 recovery failed.',
            );
            final user = uri.userInfo.split(':');
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
              '0025_planned_preparation_assignments',
            );
            expect(
              (await restored.execute(
                "SELECT to_regclass('storeos_platform.purchasing_delivery_revisions')",
              )).single.first,
              null,
            );
            expect(await evidence(restored), before);
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
            expect(await deliveryEvidence(f), source);
            expect(await evidence(f.owner), sourcePrior);
          } finally {
            await restored?.close();
            if (targetCreated) {
              if (!RegExp(
                r'^storeos_restore_p414_[a-f0-9]{16}$',
              ).hasMatch(target)) {
                throw StateError('Invalid recovery cleanup target.');
              }
              await f.owner.execute('DROP DATABASE IF EXISTS "$target"');
            }
            await temporary.delete(recursive: true);
          }
        },
        legacyBefore: '0026_purchase_order_delivery_evidence.sql',
        fixedSchema: 'storeos_platform',
      );
    },
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_PURCHASING_MIGRATION_RECOVERY'] == '1'
        ? false
        : 'Explicit isolated encrypted-recovery opt-in required.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
