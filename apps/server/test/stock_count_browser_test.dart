import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'task_knowledge_fixture.dart';

void main() {
  test(
    'real Chrome Stock count workflow and PostgreSQL zero/provenance oracle',
    () async {
      final socket = await ServerSocket.bind('127.0.0.1', 0);
      final port = socket.port;
      await socket.close();
      await withMerchandisingFixture((f) async {
        await prepareGuidedWorker(f);
        final a = await f.openStock(
              (await f.stockArticle(sku: 'CHROME-A', unit: 'kg')).id,
              quantity: '10',
            ),
            b = await f.openStock(
              (await f.stockArticle(sku: 'CHROME-B', unit: 'Stk')).id,
              quantity: '5',
            );
        final directory = await Directory.systemTemp.createTemp(
          'storeos_count_browser_',
        );
        try {
          final defines = File('${directory.path}/defines.json');
          await defines.writeAsString(
            jsonEncode({
              'STOREOS_API_URL': f.base,
              'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
              'STOREOS_COUNT_A': a.id,
              'STOREOS_COUNT_B': b.id,
            }),
          );
          final result = await Process.run(
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
            [
              'drive',
              '--no-pub',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/stock_count_test.dart',
              '-d',
              'web-server',
              '--web-hostname=127.0.0.1',
              '--web-port=$port',
              '--headless',
              '--no-web-resources-cdn',
              '--driver-port=${Platform.environment['STOREOS_KNOWLEDGE_DRIVER_PORT'] ?? '4444'}',
              '--dart-define-from-file=${defines.path}',
              if (Platform.environment['CHROME_EXECUTABLE'] case final chrome?)
                '--chrome-binary=$chrome',
            ],
            workingDirectory: '../client_flutter',
            runInShell: Platform.isWindows,
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
          expect((await f.level(a.id)).quantity, '11');
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
              'SELECT status FROM "${f.schema}".stock_counts ORDER BY status',
            )).map((r) => r.first),
            ['approved', 'cancelled'],
          );
        } finally {
          await directory.delete(recursive: true);
        }
      }, allowedOrigins: {'http://127.0.0.1:$port'});
    },
    skip:
        Platform.environment['STOREOS_COUNT_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in ChromeDriver and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
