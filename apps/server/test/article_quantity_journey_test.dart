import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'article_quantity_fixture.dart';
import 'merchandising_fixture.dart';

Future<void> quantityJourney({required bool browser}) async {
  final socket = await ServerSocket.bind('127.0.0.1', 0), webPort = socket.port;
  await socket.close();
  await withMerchandisingFixture((f) async {
    final articles = <ArticleDto>[], levels = <StockLevelDto>[];
    for (final kind in [
      'mass',
      'volume',
      'carton',
      'bottle',
      'package-removal',
    ]) {
      final a = await f.stockArticle(
        sku: 'P415-$kind',
        name: 'Quantity $kind',
        unit: 'legacy $kind',
      );
      articles.add(a);
      levels.add(await f.openStock(a.id, quantity: '1'));
    }
    final otherLocation = await f.createLocation('Retry scope');
    final upstreamPort = f.server!.port,
        client = HttpClient(),
        proxy = await HttpServer.bind('127.0.0.1', 0);
    bool dropped = false,
        rejected = false,
        stockChanged = false,
        packageChanged = false,
        bindingPackageRemoved = false;
    String? frozen;
    int retries = 0;
    proxy.listen((incoming) async {
      try {
        final bytes = await incoming.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        final path = incoming.uri.path,
            correct =
                incoming.method == 'POST' && path.endsWith('/quantity/correct'),
            preview =
                incoming.method == 'POST' && path.endsWith('/quantity/preview');
        if (correct && path.contains(levels[0].id) && dropped) {
          expect(utf8.decode(bytes), frozen);
          retries++;
        }
        final outgoing = await client.openUrl(
          incoming.method,
          Uri.parse('http://127.0.0.1:$upstreamPort${incoming.uri}'),
        );
        incoming.headers.forEach((name, values) {
          if (!['host', 'content-length', 'connection'].contains(name)) {
            for (final value in values) {
              outgoing.headers.add(name, value);
            }
          }
        });
        outgoing.add(bytes);
        final response = await outgoing.close(),
            data = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        if (preview) {
          stdout.writeln(
            'P415_PREVIEW ${utf8.decode(bytes)} -> ${utf8.decode(data)}',
          );
        }
        if (browser &&
            preview &&
            response.statusCode == 200 &&
            path.contains(levels[1].id) &&
            !stockChanged) {
          stockChanged = true;
          await f.adjustStock(
            levels[1],
            movementId: newUuid(),
            quantity: '2',
            note: 'Competing manual target after preview',
          );
        }
        if (browser &&
            preview &&
            response.statusCode == 200 &&
            path.contains(levels[2].id) &&
            !packageChanged) {
          packageChanged = true;
          final context = (await f.call(
            'GET',
            quantityStockRoot(levels[2]),
          )).body;
          final p = ArticleQuantityProfileDto.fromJson(
            quantityObject(context['profile']),
          );
          await f.call(
            'POST',
            '/articles/${articles[2].id}/quantity/replace',
            body: {
              'operationId': newUuid(),
              'expectedVersion': p.version,
              'packages': p.packages
                  .map((p) => {...p.toJson(), 'content': '24'})
                  .toList(),
              'reason': 'Packaging changed after review',
            },
          );
        }
        if (browser &&
            incoming.method == 'POST' &&
            path.endsWith('/quantity/bind') &&
            path.contains(levels[4].id) &&
            response.statusCode == 200 &&
            !bindingPackageRemoved) {
          bindingPackageRemoved = true;
          final bound = StockQuantityBindingDto.fromJson(
            quantityObject(jsonDecode(utf8.decode(data))),
          );
          expect(bound.unit, startsWith('pack:'));
          expect(bound.numerator, '12');
          await f.call(
            'POST',
            '/articles/${articles[4].id}/quantity/replace',
            body: {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'packages': <Map<String, dynamic>>[],
              'reason': 'Concurrent package removal after binding',
            },
          );
        }
        if (correct && path.contains(levels[0].id) && dropped && !rejected) {
          expect(response.statusCode, 403);
          rejected = true;
          // Restore execution scope through server configuration; the same
          // session remains valid, and authorization runs on every attempt.
          await f.restart(port: upstreamPort);
        }
        if (correct &&
            path.contains(levels[0].id) &&
            response.statusCode == 200 &&
            !dropped) {
          dropped = true;
          frozen = utf8.decode(bytes);
          await f.restart(port: upstreamPort, locationId: otherLocation);
          incoming.response.statusCode = 503;
          incoming.response.headers.contentType = ContentType.json;
          incoming.response.headers.set(
            'access-control-allow-origin',
            'http://127.0.0.1:$webPort',
          );
          incoming.response.write(
            jsonEncode({
              'code': 'database_unavailable',
              'message': 'Deliberately lost committed response',
            }),
          );
          await incoming.response.close();
          return;
        }
        incoming.response.statusCode = response.statusCode;
        response.headers.forEach((name, values) {
          if (![
            'content-length',
            'transfer-encoding',
            'connection',
          ].contains(name)) {
            for (final value in values) {
              incoming.response.headers.add(name, value);
            }
          }
        });
        incoming.response.add(data);
        await incoming.response.close();
      } catch (_) {
        incoming.response.statusCode = 500;
        await incoming.response.close();
      }
    });
    final temp = await Directory.systemTemp.createTemp(
      'storeos_quantity_journey_',
    );
    try {
      final definitions = {
        'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_QUANTITY_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
        'STOREOS_QUANTITY_LOCATION': merchandisingTestLocation,
        'STOREOS_QUANTITY_ARTICLE': articles[0].id,
        'STOREOS_QUANTITY_LEVEL': levels[0].id,
        'STOREOS_QUANTITY_ARTICLES': articles.map((a) => a.id).join(','),
        'STOREOS_QUANTITY_LEVELS': levels.map((l) => l.id).join(','),
      };
      final defines = File('${temp.path}/defines.json');
      await defines.writeAsString(jsonEncode(definitions));
      final process = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        browser
            ? [
                'drive',
                '--no-pub',
                '--driver=test_driver/integration_test.dart',
                '--target=integration_test/article_quantity_test.dart',
                '-d',
                'web-server',
                '--web-hostname=127.0.0.1',
                '--web-port=$webPort',
                '--headless',
                '--no-web-resources-cdn',
                '--driver-port=${Platform.environment['STOREOS_KNOWLEDGE_DRIVER_PORT'] ?? '4444'}',
                '--dart-define-from-file=${defines.path}',
                if (Platform.environment['CHROME_EXECUTABLE']
                    case final chrome?)
                  '--chrome-binary=$chrome',
              ]
            : [
                'test',
                '--no-pub',
                'test/article_quantity_http_journey.dart',
                '--reporter',
                'expanded',
              ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: definitions,
      );
      stdout.write(
        process.stdout.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      stderr.write(
        process.stderr.toString().replaceAll(
          merchandisingTestPassword,
          '[REDACTED]',
        ),
      );
      expect(process.exitCode, 0);
      expect(dropped, true);
      expect(rejected, true);
      expect(retries, 2);
      expect((await f.level(levels[0].id)).quantity, '1.25');
      await f.assertLedgerInvariant(levels[0].id);
      expect(
        (await f.call(
          'GET',
          '${quantityStockRoot(levels[0])}/evidence',
        )).body['items'],
        hasLength(1),
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_movements WHERE stock_level_id=\'${levels[0].id}\' AND kind=\'adjustment\'',
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".audit_entries WHERE entity_id=\'${levels[0].id}\' AND action=\'stock.quantity.corrected\'',
        )).single.first,
        1,
      );
      if (browser) {
        expect(stockChanged && packageChanged, true);
        for (var i = 1; i < 4; i++) {
          expect(
            (await f.level(levels[i].id)).quantity,
            ['0.75', '48', '1.5'][i - 1],
          );
          await f.assertLedgerInvariant(levels[i].id);
        }
        expect(bindingPackageRemoved, true);
        expect((await f.level(levels[4].id)).quantity, '2');
        await f.assertLedgerInvariant(levels[4].id);
        final context = (await f.call(
          'GET',
          quantityStockRoot(levels[4]),
        )).body;
        expect(context['binding']['profileVersion'], 1);
        expect(context['binding']['numerator'], '12');
        expect(context['profile']['version'], 2);
        expect(context['profile']['packages'], isEmpty);
      }
    } finally {
      await proxy.close(force: true);
      client.close(force: true);
      await temp.delete(recursive: true);
    }
  }, allowedOrigins: {'http://127.0.0.1:$webPort'});
}

void main() {
  test(
    'real Flutter controller quantity journey',
    () => quantityJourney(browser: false),
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_QUANTITY_CLIENT_JOURNEY'] == '1'
        ? false
        : 'Opt-in isolated HTTP/Flutter journey.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
  test(
    'actual Chrome quantity journeys',
    () => quantityJourney(browser: true),
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_QUANTITY_BROWSER'] == '1'
        ? false
        : 'Opt-in isolated Chrome journey.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
