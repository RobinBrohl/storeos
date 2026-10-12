import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'preparation_assignment_integration_test.dart'
    show manage, self, request, start, assignmentEvidence;
import 'recipe_fixture.dart';
import 'purchasing_fixture.dart';
import 'purchasing_journey_fixture.dart';
import 'task_planogram_fixture.dart';

Future<void> assignmentJourney({required bool browser}) async {
  final socket = await ServerSocket.bind('127.0.0.1', 0), webPort = socket.port;
  await socket.close();
  await withMerchandisingFixture((f) async {
    await seedPurchasingLegacy(f);
    await populated(f);
    await deployment(f);
    final worker = await batchWorker(f, 'assignment_worker'),
        other = await batchWorker(f, 'assignment_other'),
        r = await existingBatchRecipe(f);
    Future<List<Object?>> protected() async => [
      for (final table in [
        ...purchasingLegacyTables.where((t) => !t.startsWith('production_')),
        'purchasing_suppliers',
        'purchasing_orders',
        'purchasing_order_lines',
        'purchasing_commands',
        'merchandising_fixtures',
        'merchandising_planograms',
        'merchandising_planogram_revisions',
        'merchandising_planogram_assignments',
      ])
        (await f.owner.execute(
          "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
        )).single.toList(),
    ];
    final protectedBefore = await protected(),
        upstreamPort = f.server!.port,
        client = HttpClient(),
        proxy = await HttpServer.bind('127.0.0.1', 0);
    var created = false,
        dropped = false,
        restarted = false,
        replays = 0,
        competing = false;
    String? id, originalBody, batchId;
    Map? original;
    proxy.listen((incoming) async {
      try {
        final bytes = await incoming.fold<List<int>>(
          [],
          (a, b) => a..addAll(b),
        );
        final starting =
            incoming.method == 'POST' &&
            incoming.uri.path.endsWith('/start') &&
            incoming.uri.path.contains('/preparation-assignments/');
        final creating =
            incoming.method == 'POST' &&
            incoming.uri.path.endsWith('/preparation-assignments');
        final before = starting && dropped ? await assignmentEvidence(f) : null;
        if (starting && dropped) expect(utf8.decode(bytes), originalBody);
        late HttpClientResponse upstream;
        late List<int> data;
        Future<MerchandisingReply> forward() async {
          final outgoing = await client.openUrl(
            incoming.method,
            Uri.parse('http://127.0.0.1:$upstreamPort${incoming.uri}'),
          );
          incoming.headers.forEach((n, vs) {
            if (!['host', 'content-length', 'connection'].contains(n)) {
              for (final v in vs) {
                outgoing.headers.add(n, v);
              }
            }
          });
          outgoing.add(bytes);
          upstream = await outgoing.close();
          data = await upstream.fold<List<int>>([], (a, b) => a..addAll(b));
          return MerchandisingReply(
            upstream.statusCode,
            data.isEmpty
                ? {}
                : jsonDecode(utf8.decode(data)) as Map<String, dynamic>,
            null,
          );
        }

        if (starting && !dropped) {
          final outcomes = await orderedBatchCommands(
            f,
            forward,
            () => f.call(
              'POST',
              '$self/$id/start',
              token: worker.token,
              body: start(),
              expected: 409,
            ),
          );
          expect(outcomes.map((o) => o.status), [200, 409]);
          competing = true;
        } else {
          await forward();
        }
        if (creating && upstream.statusCode == 201 && !created) {
          created = true;
          id =
              (jsonDecode(utf8.decode(data))['assignment'] as Map)['id']
                  as String;
          r.detail = (await replacementRecipe(f, r.detail)).detail;
          r.detail = (await saveRecipe(
            f,
            r.detail,
            r.detail.draft!.content.editable.ingredients,
            preparation: 'Visibly different replacement R2',
            batch: 'different R2 declaration',
          )).detail;
          await publishRecipe(f, r.detail);
          r.detail = await recipeDetail(f, r.detail.recipe.id);
          for (final suffix in ['', '/recipe', '/history']) {
            await f.call(
              'GET',
              '$self/$id$suffix',
              token: other.token,
              expected: 404,
            );
          }
          await f.call(
            'POST',
            '$self/$id/start',
            token: other.token,
            body: start(),
            expected: 404,
          );
          await f.call(
            'GET',
            self.replaceAll(merchandisingTestLocation, newUuid()),
            token: worker.token,
            expected: 403,
          );
        }
        if (starting && upstream.statusCode == 200) {
          final result = jsonDecode(utf8.decode(data)) as Map;
          if (dropped) {
            replays++;
            expect(result['assignment'], original!['assignment']);
            expect(result['batch'], original!['batch']);
            expect(await assignmentEvidence(f), before);
          } else {
            original = result;
            originalBody = utf8.decode(bytes);
            batchId = (result['batch'] as Map)['batchId'] as String;
            dropped = true;
            await f.restart(port: upstreamPort);
            restarted = true;
            incoming.response.statusCode = 503;
            upstream.headers.forEach((n, vs) {
              if (n.startsWith('access-control-')) {
                for (final v in vs) {
                  incoming.response.headers.add(n, v);
                }
              }
            });
            incoming.response.headers.contentType = ContentType.json;
            incoming.response.write(
              jsonEncode({
                'code': 'database_unavailable',
                'message':
                    'Committed start response intentionally lost by acceptance gateway.',
              }),
            );
            await incoming.response.close();
            return;
          }
        }
        incoming.response.statusCode = upstream.statusCode;
        upstream.headers.forEach((n, vs) {
          if (![
            'transfer-encoding',
            'content-length',
            'connection',
          ].contains(n)) {
            for (final v in vs) {
              incoming.response.headers.add(n, v);
            }
          }
        });
        incoming.response.add(data);
        await incoming.response.close();
      } catch (e, stack) {
        stderr.writeln(
          'Assignment acceptance gateway failed: ${e.runtimeType}',
        );
        Zone.current.handleUncaughtError(e, stack);
      }
    });
    final temp = await Directory.systemTemp.createTemp(
      'storeos_assignment_journey_',
    );
    try {
      final definitions = {
        'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
        'STOREOS_ASSIGNMENT_URL': 'http://127.0.0.1:${proxy.port}',
        'STOREOS_ASSIGNMENT_RECIPE': r.detail.recipe.id,
        'STOREOS_ASSIGNMENT_EMPLOYEE': worker.employee,
      };
      final defines = File('${temp.path}/defines.json');
      await defines.writeAsString(jsonEncode(definitions));
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        browser
            ? [
                'drive',
                '--no-pub',
                '--driver=test_driver/integration_test.dart',
                '--target=integration_test/preparation_assignment_test.dart',
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
                'test/preparation_assignment_http_journey.dart',
                '--reporter',
                'expanded',
              ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: definitions,
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
      expect(created && dropped && restarted && competing, true);
      expect(replays, 1);
      final pending = request(r, worker), pendingId = pending['id'];
      await f.call('POST', manage, body: pending, expected: 201);
      await f.call(
        'POST',
        '$recipeRoot/${r.detail.recipe.id}/retire',
        body: RecipeVersionRequest(r.detail.recipe.version).toJson(),
      );
      final before = await assignmentEvidence(f);
      await f.call(
        'POST',
        '$self/$pendingId/start',
        token: worker.token,
        body: start(),
        expected: 422,
      );
      final replay = (await f.call(
        'POST',
        '$self/$id/start',
        token: worker.token,
        raw: originalBody,
      )).body;
      expect(replay['replayed'], true);
      expect(replay['assignment'], original!['assignment']);
      expect(replay['batch'], original!['batch']);
      expect(await assignmentEvidence(f), before);
      final d = (await f.call('GET', '$manage/$id')).body,
          b = d['batch'] as Map;
      expect(d['status'], 'started');
      expect(d['revisionId'], original!['assignment']['revisionId']);
      expect(b['batchId'], batchId);
      expect(b['actualDeclaredBatchCount'], 2);
      expect(b['effectiveDeclaredBatchCount'], 0);
      expect(b['corrections'], hasLength(2));
      final context = (await f.call(
        'GET',
        '$self/$id/recipe',
        token: worker.token,
      )).body;
      expect(context['revisionNumber'], 1);
      expect(context['warnings'], contains('recipe_retired'));
      expect(await protected(), protectedBefore);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries WHERE entity_id='$id' AND action LIKE 'production.preparation_assignment.%'",
        )).single.first,
        2,
      );
    } finally {
      await proxy.close(force: true);
      client.close(force: true);
      await temp.delete(recursive: true);
    }
  }, allowedOrigins: {'http://127.0.0.1:$webPort'});
}
