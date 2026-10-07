import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';

Future<void> preparationJourney({required bool browser}) async {
  final socket = await ServerSocket.bind('127.0.0.1', 0), webPort = socket.port;
  await socket.close();
  await withMerchandisingFixture((f) async {
    final worker = await batchWorker(f, 'batch_worker'),
        r = await batchRecipe(f);
    await seedRecipeCountEvidence(f);
    final zero = batchOpening(r, planned: 1),
        zeroId = zero['batchId'] as String;
    await f.call(
      'POST',
      batchSelf,
      token: worker.token,
      body: zero,
      expected: 201,
    );
    await f.call(
      'POST',
      '$batchSelf/$zeroId/complete',
      token: worker.token,
      body: batchComplete(count: 1),
    );
    final stockBefore = await recipeEvidence(f, stock: true);
    final upstreamPort = f.server!.port,
        client = HttpClient(),
        proxy = await HttpServer.bind('127.0.0.1', 0);
    var opened = false, dropped = false, restarted = false, replays = 0;
    String? originalBody, mainBatch;
    proxy.listen((request) async {
      try {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b));
        final complete =
            request.method == 'POST' &&
            request.uri.path.endsWith('/complete') &&
            request.uri.path.contains('/production/self/');
        final opening =
            request.method == 'POST' && request.uri.path.endsWith('/batches');
        final before = complete && dropped ? await batchEvidence(f) : null;
        if (complete && dropped) {
          expect(utf8.decode(bytes), originalBody);
        }
        final outgoing = await client.openUrl(
          request.method,
          Uri.parse('http://127.0.0.1:$upstreamPort${request.uri}'),
        );
        request.headers.forEach((name, values) {
          if (!['host', 'content-length', 'connection'].contains(name)) {
            for (final v in values) {
              outgoing.headers.add(name, v);
            }
          }
        });
        outgoing.add(bytes);
        final upstream = await outgoing.close();
        final response = await upstream.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        if (opening && upstream.statusCode == 201 && !opened) {
          opened = true;
          final result = jsonDecode(utf8.decode(response)) as Map;
          mainBatch = (result['batch'] as Map)['batchId'] as String;
          final row = (await f.owner.execute(
            "SELECT company_id::text,location_id::text,employee_id::text,opened_by::text,revision_id::text,planned_declared_batch_count,opened_at FROM \"${f.schema}\".production_preparation_batches WHERE id='$mainBatch'",
          )).single;
          expect(row.take(6).toList(), [
            merchandisingTestCompany,
            merchandisingTestLocation,
            worker.employee,
            worker.account,
            r.detail.currentPublished!.id,
            3,
          ]);
          expect(row[6], isA<DateTime>());
          var d = (await replacementRecipe(f, r.detail)).detail;
          d = (await saveRecipe(
            f,
            d,
            d.draft!.content.ingredients
                .map(
                  (i) => RecipeIngredientInput(i.id, i.article.id, i.quantity),
                )
                .toList(),
            preparation: 'Visibly different replacement preparation R2',
          )).detail;
          await publishRecipe(f, d);
          d = await recipeDetail(f, d.recipe.id);
          await f.call(
            'POST',
            '$recipeRoot/${d.recipe.id}/retire',
            body: RecipeVersionRequest(d.recipe.version).toJson(),
          );
          await f.call(
            'POST',
            batchSelf,
            token: worker.token,
            body: batchOpening(r),
            expected: 422,
          );
        }
        if (complete && upstream.statusCode == 200) {
          final result = jsonDecode(utf8.decode(response)) as Map;
          expect((result['batch'] as Map)['actualDeclaredBatchCount'], 2);
          if (dropped) {
            replays++;
            expect(await batchEvidence(f), before);
          } else {
            originalBody = utf8.decode(bytes);
            dropped = true;
            await f.restart(port: upstreamPort);
            restarted = true;
            request.response.statusCode = 503;
            upstream.headers.forEach((name, values) {
              if (name.startsWith('access-control-')) {
                for (final v in values) {
                  request.response.headers.add(name, v);
                }
              }
            });
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'code': 'database_unavailable',
                'message':
                    'Committed response intentionally lost by acceptance gateway.',
              }),
            );
            await request.response.close();
            return;
          }
        }
        request.response.statusCode = upstream.statusCode;
        upstream.headers.forEach((name, values) {
          if (![
            'transfer-encoding',
            'content-length',
            'connection',
          ].contains(name)) {
            for (final v in values) {
              request.response.headers.add(name, v);
            }
          }
        });
        request.response.add(response);
        await request.response.close();
      } catch (e, stack) {
        stderr.writeln('Preparation journey gateway failed: ${e.runtimeType}');
        Zone.current.handleUncaughtError(e, stack);
      }
    });
    final directory = await Directory.systemTemp.createTemp(
      'storeos_preparation_journey_',
    );
    try {
      final defines = File('${directory.path}/defines.json');
      final data = {
        'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
        'STOREOS_PREPARATION_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_PREPARATION_RECIPE': r.detail.recipe.id,
        'STOREOS_PREPARATION_ZERO': zeroId,
      };
      await defines.writeAsString(jsonEncode(data));
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        browser
            ? [
                'drive',
                '--no-pub',
                '--driver=test_driver/integration_test.dart',
                '--target=integration_test/preparation_batch_test.dart',
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
                'test/preparation_batch_http_journey.dart',
                '--reporter',
                'expanded',
              ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: data,
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
      expect(opened, true);
      expect(dropped, true);
      expect(restarted, true);
      expect(replays, 2);
      expect(await recipeEvidence(f, stock: true), stockBefore);
      final detail = (await f.call('GET', '$batchManage/$mainBatch')).body;
      expect(detail['plannedDeclaredBatchCount'], 3);
      expect(detail['actualDeclaredBatchCount'], 2);
      expect(detail['effectiveDeclaredBatchCount'], 1);
      expect(detail['version'], 2);
      final z = (await f.call('GET', '$batchManage/$zeroId')).body;
      expect(z['status'], 'completed');
      expect(z['actualDeclaredBatchCount'], 1);
      expect(z['effectiveDeclaredBatchCount'], 0);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".production_preparation_batch_commands',
        )).single.first,
        6,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries WHERE action LIKE 'production.batch.%'",
        )).single.first,
        6,
      );
    } finally {
      await proxy.close(force: true);
      client.close(force: true);
      await directory.delete(recursive: true);
    }
  }, allowedOrigins: {'http://127.0.0.1:$webPort'});
}
