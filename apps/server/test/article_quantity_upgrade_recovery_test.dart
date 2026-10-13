import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'article_quantity_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_journey_fixture.dart';
import 'purchasing_delivery_test.dart' show issued, declareBody;
import 'preparation_assignment_upgrade_recovery_test.dart' show catalog;

const quantityTables = [
  'inventory_quantity_profiles',
  'inventory_quantity_revisions',
  'inventory_quantity_commands',
  'stock_quantity_bindings',
  'stock_quantity_corrections',
];
Future<Map<String, Object?>> dataHash(
  Connection connection,
  String schema,
  List<String> tables, {
  bool beforeSwapMigration = false,
}) async => {
  for (final table in tables)
    table: (await connection.execute(
      "SELECT count(*),md5(string_agg(${beforeSwapMigration && table == 'shifts' ? "(to_jsonb(t)-ARRAY['swap_request_id','swap_leg'])" : 'to_jsonb(t)'}::text,'' ORDER BY ${beforeSwapMigration && table == 'shifts' ? "(to_jsonb(t)-ARRAY['swap_request_id','swap_leg'])" : 'to_jsonb(t)'}::text)) FROM \"$schema\".$table t",
    )).single.toList(),
};
void main() {
  test(
    'populated 0026 preservation, post-grant deferred rollback and encrypted 0027 fenced restore with exact replay',
    () => withMerchandisingFixture(
      (f) async {
        await seedPurchasingLegacy(f);
        final order = await issued(f);
        await f.call(
          'POST',
          '$purchasingOrders/${order['id']}/deliveries',
          body: declareBody(order),
          expected: 201,
        );
        final a = await f.stockArticle(sku: 'P415-UPGRADE', unit: 'opaque kg');
        final l = await f.openStock(a.id, quantity: '2');
        final tables = (await f.owner.execute(
          "SELECT tablename FROM pg_tables WHERE schemaname='${f.schema}' AND tablename NOT IN ('auth_sessions','schema_migrations') ORDER BY tablename",
        )).map((r) => r.first as String).toList();
        final prior = await dataHash(
              f.owner,
              f.schema,
              tables,
              beforeSwapMigration: true,
            ),
            priorCatalog = await catalog(f);
        final temp = await Directory.systemTemp.createTemp(
          'storeos_p415_recovery_',
        );
        final target =
            'storeos_restore_p415_${newUuid().replaceAll('-', '').substring(0, 16)}';
        Connection? restored;
        Pool<void>? restoredPool;
        MerchandisingFixture? restoredFixture;
        bool targetCreated = false;
        try {
          final migrationCopy = Directory('${temp.path}/migrations')
            ..createSync();
          for (final file in Directory(
            'migrations',
          ).listSync().whereType<File>()) {
            await file.copy(
              '${migrationCopy.path}/${file.uri.pathSegments.last}',
            );
          }
          await File(
            '${migrationCopy.path}/0027_article_quantities.sql',
          ).writeAsString(r'''
CREATE FUNCTION {{schema}}.p415_late_fault() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Intentional post-grant deferred migration fault' USING ERRCODE='23514'; END $$;
CREATE CONSTRAINT TRIGGER p415_late_fault AFTER INSERT ON {{schema}}.schema_migrations
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION {{schema}}.p415_late_fault();
''', mode: FileMode.append);
          await expectLater(
            MigrationRunner(
              connection: f.owner,
              migrationsDirectory: migrationCopy,
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            throwsA(isA<PgException>()),
          );
          expect(await catalog(f), priorCatalog);
          expect(
            await dataHash(
              f.owner,
              f.schema,
              tables,
              beforeSwapMigration: true,
            ),
            prior,
          );
          for (final table in quantityTables) {
            expect(
              (await f.owner.execute(
                "SELECT to_regclass('${f.schema}.$table')",
              )).single.first,
              isNull,
            );
          }
          expect(
            await MigrationRunner(
              connection: f.owner,
              migrationsDirectory: Directory('migrations'),
              schemaName: f.schema,
              runtimeDatabaseUser: f.runtimeUser,
            ).apply(),
            ['0027_article_quantities', '0028_bilateral_shift_swaps'],
          );
          expect(
            await dataHash(
              f.owner,
              f.schema,
              tables,
              beforeSwapMigration: true,
            ),
            prior,
          );
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
          final p = await configureQuantity(
            f,
            a.id,
            'kg',
            packages: [
              {'id': newUuid(), 'label': 'Bag', 'content': '25'},
            ],
          );
          final bind = bindingCommand(l, p, 'kg');
          await f.call('POST', '${quantityStockRoot(l)}/bind', body: bind);
          final cmd = correctionCommand(
            await previewQuantity(f, l, p, 'g', '1250'),
          );
          final original = (await f.call(
            'POST',
            '${quantityStockRoot(l)}/correct',
            body: cmd,
          )).body;
          final latest = await f.level(l.id);
          final zero = correctionCommand(
            await previewQuantity(f, latest, p, 'kg', '1.25'),
          );
          final zeroResult = (await f.call(
            'POST',
            '${quantityStockRoot(l)}/correct',
            body: zero,
          )).body;
          await f.call(
            'POST',
            '/articles/${a.id}/quantity/suspend',
            body: {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'reason': 'Suspended before encrypted backup',
            },
          );
          final sourceHash = await dataHash(f.owner, f.schema, [
            ...tables,
            ...quantityTables,
          ]);
          final uri = Uri.parse(Platform.environment['STOREOS_TEST_DATABASE']!);
          final backup = await Process.run('pwsh', [
            '-NoProfile',
            '-File',
            '../../infra/backup/Backup-StoreOS.ps1',
            '-Database',
            uri.pathSegments.single,
            '-BackupDirectory',
            temp.path,
          ]);
          expect(backup.exitCode, 0, reason: 'Encrypted P4.15 backup failed.');
          final encrypted = temp.listSync().whereType<File>().singleWhere(
            (file) => file.path.endsWith('.sodb'),
          );
          targetCreated = true;
          final restore = await Process.run('pwsh', [
            '-NoProfile',
            '-File',
            '../../infra/backup/Restore-StoreOS.ps1',
            '-BackupPath',
            encrypted.path,
            '-TargetDatabase',
            target,
          ]);
          expect(
            restore.exitCode,
            0,
            reason: 'Encrypted P4.15 restore failed.',
          );
          final credentials = uri.userInfo.split(':');
          restored = await Connection.open(
            Endpoint(
              host: uri.host,
              port: uri.port,
              database: target,
              username: Uri.decodeComponent(credentials[0]),
              password: Uri.decodeComponent(credentials[1]),
            ),
            settings: const ConnectionSettings(sslMode: SslMode.disable),
          );
          expect(
            await dataHash(restored, f.schema, [...tables, ...quantityTables]),
            sourceHash,
          );
          expect(
            (await restored.execute(
              "SELECT has_database_privilege('storeos',current_database(),'CONNECT')",
            )).single.first,
            false,
          );
          expect(
            (await restored.execute(
              'SELECT count(*) FROM "${f.schema}".auth_sessions WHERE revoked_at IS NULL',
            )).single.first,
            0,
          );
          // Test-only activation of the isolated restore, after proving the fence.
          // No normally operating service/database is redirected to this target.
          await f.owner.execute(
            'GRANT CONNECT ON DATABASE "$target" TO "${f.runtimeUser}"',
          );
          restoredPool = Pool<void>.withEndpoints([
            Endpoint(
              host: uri.host,
              port: uri.port,
              database: target,
              username: f.runtimeUser,
              password: File(
                Platform.environment['STOREOS_DB_PASSWORD_FILE']!,
              ).readAsStringSync().trim(),
            ),
          ], settings: const PoolSettings(sslMode: SslMode.disable));
          restoredFixture = MerchandisingFixture(
            restored,
            restoredPool,
            f.schema,
            f.runtimeUser,
          );
          await restoredFixture.restart();
          restoredFixture.adminToken = await restoredFixture.login(
            'test_admin',
          );
          final restoredAfterLogin = await dataHash(restored, f.schema, [
            ...tables,
            ...quantityTables,
          ]);
          expect(
            (restoredAfterLogin['audit_entries'] as List).first,
            ((sourceHash['audit_entries'] as List).first as int) + 1,
          );
          expect(
            (await restoredFixture.call(
              'POST',
              '${quantityStockRoot(l)}/correct',
              body: cmd,
            )).body,
            original,
          );
          expect(
            (await restoredFixture.call(
              'POST',
              '${quantityStockRoot(l)}/correct',
              body: zero,
            )).body,
            zeroResult,
          );
          expect(
            (await restoredFixture.call(
              'GET',
              quantityStockRoot(l),
            )).body['profile']['status'],
            'suspended',
          );
          await restoredFixture.call(
            'GET',
            '/locations/${newUuid()}/stock/${l.id}/quantity/evidence',
            expected: 403,
          );
          expect(
            await dataHash(restored, f.schema, [...tables, ...quantityTables]),
            restoredAfterLogin,
          );
          expect(
            await dataHash(f.owner, f.schema, [...tables, ...quantityTables]),
            sourceHash,
          );
          await f.assertLedgerInvariant(l.id);
        } finally {
          restoredFixture?.client.close(force: true);
          await restoredFixture?.server?.close(force: true);
          await restoredPool?.close();
          await restored?.close();
          if (targetCreated) {
            if (!RegExp(
              r'^storeos_restore_p415_[a-f0-9]{16}$',
            ).hasMatch(target)) {
              throw StateError('Invalid isolated cleanup target.');
            }
            await f.owner.execute('DROP DATABASE IF EXISTS "$target"');
          }
          await temp.delete(recursive: true);
        }
      },
      legacyBefore: '0027_article_quantities.sql',
      fixedSchema: 'storeos_platform',
    ),
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_PURCHASING_MIGRATION_RECOVERY'] == '1'
        ? false
        : 'Explicit isolated encrypted migration/recovery opt-in required.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
