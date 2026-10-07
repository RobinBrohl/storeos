import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'recipe_fixture.dart';
import 'task_knowledge_fixture.dart';

void main() {
  test(
    'actual Chrome Recipe authoring, frozen units, restart/lost-response retry, employee read and retirement',
    () async {
      final socket = await ServerSocket.bind('127.0.0.1', 0),
          webPort = socket.port;
      await socket.close();
      await withMerchandisingFixture((f) async {
        final work = await guidedScenario(
          f,
          schema: 1,
          workerName: 'recipe_worker',
        );
        final p = await f.article(
          recipeArticleInput(
            'BROWSER-P',
            unit: 'tray',
            name: 'Produced <script>globalThis.recipeInjected=true</script>',
          ),
        );
        final i1 = await f.article(
          recipeArticleInput(
            'BROWSER-I1',
            name:
                'Flour <img src="x" onerror="globalThis.recipeInjected=true">',
          ),
        );
        final i2 = await f.article(
          recipeArticleInput(
            'BROWSER-I2',
            unit: 'kg',
            name: 'Water <a href="https://invalid.example/p49">literal</a>',
          ),
        );
        await f.openStock(
          (await f.stockArticle(sku: 'BROWSER-STOCK')).id,
          quantity: '12.250',
        );
        final before = await recipeEvidence(f, stock: true);
        final upstreamPort = f.server!.port,
            client = HttpClient(),
            proxy = await HttpServer.bind('127.0.0.1', 0);
        var publications = 0, dropped = false, restarted = false;
        String? originalBody;
        var exactRetries = 0;
        var draftCheckpoints = 0, unitRejections = 0, readChecks = 0;
        proxy.listen((request) async {
          try {
            final bytes = await request.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            final isRead =
                request.method == 'GET' &&
                request.uri.path.startsWith(
                  '/api/v1/platform/production/recipes',
                );
            final isPublication =
                request.method == 'POST' &&
                request.uri.path.endsWith('/publish');
            final evidenceBefore = isRead || isPublication
                ? await recipeEvidence(f)
                : null;
            if (request.method == 'POST' &&
                request.uri.path.endsWith('/publish')) {
              publications++;
              if (dropped) {
                expect(utf8.decode(bytes), originalBody);
                exactRetries++;
              }
            }
            final outgoing = await client.openUrl(
              request.method,
              Uri.parse('http://127.0.0.1:$upstreamPort${request.uri}'),
            );
            request.headers.forEach((name, values) {
              if (name != 'host' &&
                  name != 'content-length' &&
                  name != 'connection') {
                for (final value in values) {
                  outgoing.headers.add(name, value);
                }
              }
            });
            outgoing.add(bytes);
            final upstream = await outgoing.close();
            final responseBytes = await upstream.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            if (isRead) {
              expect(await recipeEvidence(f), evidenceBefore);
              readChecks++;
            }
            if (isPublication && upstream.statusCode == 422) {
              expect(
                jsonDecode(utf8.decode(responseBytes))['code'],
                'ingredient_unit_changed',
              );
              expect(await recipeEvidence(f), evidenceBefore);
              unitRejections++;
            }
            if (isPublication &&
                upstream.statusCode == 200 &&
                jsonDecode(utf8.decode(responseBytes))['replayed'] == true) {
              expect(await recipeEvidence(f), evidenceBefore);
            }
            if (request.method == 'POST' &&
                request.uri.path.endsWith('/edit') &&
                request.uri.path.contains('/production/manage/recipes/') &&
                upstream.statusCode == 200) {
              draftCheckpoints++;
              final number = draftCheckpoints == 1 ? 2 : 3;
              final revision = await f.owner.execute(
                'SELECT status,batch_description,preparation FROM "${f.schema}".production_recipe_revisions WHERE revision_number=$number',
              );
              expect(revision.single[0], 'draft');
              expect(
                revision.single[1],
                draftCheckpoints == 1
                    ? 'one 30 × 40 cm tray'
                    : 'one 30 × 40 cm tray <script>globalThis.recipeInjected=true</script>',
              );
              const preparation =
                  '<script>globalThis.recipeInjected=true</script>\n<a href="https://invalid.example/p49">literal</a>\n<img src="x" onerror="globalThis.recipeInjected=true">\n# plain ä 😀';
              expect(
                revision.single[2],
                draftCheckpoints == 1
                    ? preparation
                    : 'Replacement\n$preparation',
              );
              final lines = await f.owner.execute(
                'SELECT article_id::text,quantity_scaled,sku,name,unit,position FROM "${f.schema}".production_recipe_ingredients WHERE revision_id=(SELECT id FROM "${f.schema}".production_recipe_revisions WHERE revision_number=$number) ORDER BY position',
              );
              expect(lines.map((r) => r.toList()), [
                [i1.id, 1250, i1.sku, i1.name, 'kg', 1],
                [
                  i2.id,
                  draftCheckpoints == 1 ? 50 : 75,
                  i2.sku,
                  i2.name,
                  draftCheckpoints == 3 ? 'g' : 'kg',
                  2,
                ],
              ]);
            }
            if (request.method == 'POST' &&
                request.uri.path.endsWith('/publish') &&
                upstream.statusCode == 200 &&
                publications >= 3 &&
                !dropped) {
              originalBody = utf8.decode(bytes);
              dropped = true;
              await f.restart(port: upstreamPort);
              restarted = true;
              // Discard the committed response and simulate a gateway failure. A
              // status response prevents Chrome's automatic socket-level POST retry.
              request.response.statusCode = 503;
              upstream.headers.forEach((name, values) {
                if (name.startsWith('access-control-')) {
                  for (final value in values) {
                    request.response.headers.add(name, value);
                  }
                }
              });
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'code': 'publication_response_lost',
                  'message': 'Gateway lost the committed response.',
                }),
              );
              await request.response.close();
              return;
            }
            request.response.statusCode = upstream.statusCode;
            upstream.headers.forEach((name, values) {
              if (name != 'transfer-encoding' &&
                  name != 'content-length' &&
                  name != 'connection') {
                for (final value in values) {
                  request.response.headers.add(name, value);
                }
              }
            });
            request.response.add(responseBytes);
            await request.response.close();
          } catch (e, stack) {
            stderr.writeln('Recipe browser proxy failed: ${e.runtimeType}');
            Zone.current.handleUncaughtError(e, stack);
          }
        });
        final directory = await Directory.systemTemp.createTemp(
          'storeos_recipe_browser_',
        );
        try {
          final defines = File('${directory.path}/defines.json');
          await defines.writeAsString(
            jsonEncode({
              'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
              'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
              'STOREOS_RECIPE_PASSWORD': merchandisingTestPassword,
              'STOREOS_RECIPE_PRODUCED': p.id,
              'STOREOS_RECIPE_INGREDIENT': i2.id,
              'STOREOS_RECIPE_SHIFT': work.shift,
            }),
          );
          final result = await Process.run(
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
            [
              'drive',
              '--no-pub',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/recipe_test.dart',
              '-d',
              'web-server',
              '--web-hostname=127.0.0.1',
              '--web-port=$webPort',
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
          expect(dropped, isTrue);
          expect(restarted, isTrue);
          expect(exactRetries, 2);
          expect(draftCheckpoints, 3);
          expect(unitRejections, 1);
          expect(readChecks, greaterThan(0));
          expect(await recipeEvidence(f, stock: true), before);
          expect(
            (await f.owner.execute(
              'SELECT status,count(*) FROM "${f.schema}".production_recipe_revisions GROUP BY status',
            )).map((r) => r.toList()),
            unorderedEquals([
              ['published', 2],
              ['discarded', 2],
            ]),
          );
        } finally {
          await proxy.close(force: true);
          client.close(force: true);
          await directory.delete(recursive: true);
        }
      }, allowedOrigins: {'http://127.0.0.1:$webPort'});
    },
    skip:
        Platform.environment['STOREOS_RECIPE_BROWSER'] == '1' &&
            merchandisingDatabaseAvailable
        ? false
        : 'Opt-in ChromeDriver and isolated PostgreSQL required.',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
