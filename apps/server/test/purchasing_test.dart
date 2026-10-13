import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'purchasing_cases.dart';
import 'purchasing_race_cases.dart';
import 'purchasing_safety_cases.dart';
import 'purchasing_uuid_replay_cases.dart';

void main() {
  if (Platform.environment['STOREOS_TEST_DATABASE'] != null) {
    purchasingUuidReplayCases();
  }
  if (Platform.environment['STOREOS_TEST_DATABASE'] != null) {
    purchasingSafetyCases();
  }
  if (Platform.environment['STOREOS_TEST_DATABASE'] != null) {
    purchasingCases();
  }
  if (Platform.environment['STOREOS_TEST_DATABASE'] != null) {
    purchasingRaceCases();
  }
  test(
    'P4.12 clean migration remains valid through current 0026',
    () async {
      final uri = Uri.parse(Platform.environment['STOREOS_TEST_DATABASE']!);
      final parts = uri.userInfo.split(':');
      final connection = await Connection.open(
        Endpoint(
          host: uri.host,
          port: uri.port,
          database: uri.pathSegments.single,
          username: Uri.decodeComponent(parts[0]),
          password: Uri.decodeComponent(parts[1]),
        ),
        settings: const ConnectionSettings(sslMode: SslMode.disable),
      );
      final schema = 'storeos_purchasing_${newUuid().replaceAll('-', '')}';
      try {
        final applied = await MigrationRunner(
          connection: connection,
          migrationsDirectory: Directory('migrations'),
          schemaName: schema,
          runtimeDatabaseUser: Platform.environment['STOREOS_DB_USER'],
        ).apply();
        expect(applied.last, '0028_bilateral_shift_swaps');
      } finally {
        await connection.execute('DROP SCHEMA IF EXISTS "$schema" CASCADE');
        await connection.close();
      }
    },
    skip: Platform.environment['STOREOS_TEST_DATABASE'] == null
        ? 'Explicit disposable PostgreSQL required'
        : false,
  );
  test(
    'P4.12 Supplier and empty draft persist through restricted runtime',
    () async {
      await withMerchandisingFixture((f) async {
        final s = newUuid();
        final supplierBody = <String, dynamic>{
          'id': s,
          'operationId': newUuid(),
          'name': 'Supplier 😀',
          'orderingReference': null,
        };
        final created = await f.call(
          'POST',
          '/purchasing/suppliers',
          expected: 201,
          body: supplierBody,
        );
        expect(created.body['supplier']['version'], 1);
        final order = newUuid();
        await f.call(
          'POST',
          '/purchasing/locations/$merchandisingTestLocation/orders',
          expected: 201,
          body: {
            'id': order,
            'operationId': newUuid(),
            'reference': 'PO-1',
            'supplierId': s,
            'expectedSupplierVersion': 1,
          },
        );
        final d = await f.call(
          'GET',
          '/purchasing/locations/$merchandisingTestLocation/orders/$order',
        );
        expect(d.body['lines'], isEmpty);
      });
    },
    skip: Platform.environment['STOREOS_TEST_DATABASE'] == null
        ? 'Explicit disposable PostgreSQL required'
        : false,
  );
}
