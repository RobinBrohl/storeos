import 'dart:io';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

void main() {
  test(
    'real count client/API/database journey and independent ledger oracle',
    () => withMerchandisingFixture((f) async {
      final account = newUuid(), employee = newUuid();
      await f.call(
        'POST',
        '/users',
        expected: 201,
        body: {
          'id': account,
          'username': 'p48_worker',
          'password': merchandisingTestPassword,
          'locationId': merchandisingTestLocation,
          'role': 'employee',
        },
      );
      await f.call(
        'POST',
        '/employees',
        expected: 201,
        body: {
          'id': employee,
          'displayName': 'Physical counter',
          'locationId': merchandisingTestLocation,
        },
      );
      await f.call(
        'POST',
        '/employees/$employee/account-link',
        expected: 201,
        body: {
          'id': newUuid(),
          'accountId': account,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
      );
      final a = await f.openStock(
        (await f.stockArticle(sku: 'CLIENT-A', unit: 'kg')).id,
        quantity: '10',
      );
      final b = await f.openStock(
        (await f.stockArticle(sku: 'CLIENT-B', unit: 'Stk')).id,
        quantity: '5',
      );
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        [
          'test',
          '--no-pub',
          'test/stock_count_http_journey.dart',
          '--reporter',
          'expanded',
        ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: {
          'STOREOS_COUNT_URL': f.base,
          'STOREOS_COUNT_EMPLOYEE': employee,
          'STOREOS_COUNT_A': a.id,
          'STOREOS_COUNT_B': b.id,
        },
      );
      stdout.write(
        result.stdout.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      stderr.write(
        result.stderr.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      expect(result.exitCode, 0);
      expect((await f.level(a.id)).quantity, '13');
      expect((await f.level(b.id)).toJson(), b.toJson());
      await f.assertLedgerInvariant(a.id);
      await f.assertLedgerInvariant(b.id);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements WHERE kind=\'count_correction\'',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_count_rounds',
        )).single.first,
        3,
      );
      await f.restart();
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_count_commands WHERE kind=\'approve\'',
        )).single.first,
        1,
      );
    }),
    skip:
        Platform.environment['STOREOS_COUNT_CLIENT_JOURNEY'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in real Flutter and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
