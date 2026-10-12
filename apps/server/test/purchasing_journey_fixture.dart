import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';
import 'recipe_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'preparation_assignment_integration_test.dart' show manage, request;

const purchasingLegacyTables = [
  'stock_levels',
  'stock_movements',
  'stock_counts',
  'stock_count_lines',
  'stock_count_rounds',
  'stock_count_observations',
  'stock_count_commands',
  'production_recipes',
  'production_recipe_revisions',
  'production_recipe_ingredients',
  'production_preparation_batches',
  'production_preparation_batch_commands',
  'production_preparation_batch_count_corrections',
  'shifts',
  'shift_template_selections',
  'task_template_revisions',
  'task_instances',
  'workforce_shift_transfer_requests',
  'workforce_shift_transfer_commands',
  'task_transfer_links',
  'knowledge_articles',
  'knowledge_revisions',
  'event_outbox',
  'event_receipts',
];
Future<Map<String, Object?>> purchasingLegacyEvidence(
  MerchandisingFixture f, {
  bool includeAssignments = false,
}) async => {
  for (final table in [
    ...purchasingLegacyTables,
    if (includeAssignments) ...[
      'production_preparation_assignments',
      'production_preparation_assignment_commands',
    ],
  ])
    table: (await f.owner.execute(
      "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
    )).single.toList(),
};
Future<void> seedPurchasingLegacy(MerchandisingFixture f) async {
  await seedRecipeCountEvidence(f);
  final w = await batchWorker(f, 'purchasing_legacy_preparer'),
      r = await batchRecipe(f),
      opening = batchOpening(r);
  await f.call('POST', batchSelf, token: w.token, body: opening, expected: 201);
  await f.call(
    'POST',
    '$batchSelf/${opening['batchId']}/complete',
    token: w.token,
    body: batchComplete(),
  );
  await f.call(
    'POST',
    '$batchManage/${opening['batchId']}/count-corrections',
    body: batchCorrection(),
  );
  final g = await guidedScenario(f),
      recipient = await batchWorker(f, 'purchasing_legacy_recipient'),
      id = newUuid();
  final shift = newUuid(),
      start = DateTime.now().toUtc().add(const Duration(days: 2));
  await f.call(
    'POST',
    '/shifts',
    expected: 201,
    body: {
      'id': shift,
      'locationId': merchandisingTestLocation,
      'employeeId': g.employee,
      'startsAt': start.toIso8601String(),
      'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
      'selections': [
        {'templateId': g.template, 'revisionId': g.revision},
      ],
    },
  );
  await f.call('POST', '/shifts/$shift/publish', body: {'expectedVersion': 1});
  await f.call(
    'POST',
    '/me/shift-transfers',
    token: g.token,
    body: {
      'requestId': id,
      'operationId': newUuid(),
      'sourceShiftId': shift,
      'expectedSourceVersion': 2,
      'recipientEmployeeId': recipient.employee,
    },
    expected: 201,
  );
  await f.call(
    'POST',
    '/me/shift-transfers/$id/accept',
    token: recipient.token,
    body: {'operationId': newUuid(), 'expectedVersion': 1},
  );
  await f.call(
    'POST',
    '/locations/$merchandisingTestLocation/shift-transfers/$id/approve',
    body: {'operationId': newUuid(), 'expectedVersion': 2},
  );
}

Future<void> purchasingJourney({required bool browser}) async {
  final socket = await ServerSocket.bind('127.0.0.1', 0), webPort = socket.port;
  await socket.close();
  await withMerchandisingFixture((f) async {
    await seedPurchasingLegacy(f);
    final assignmentRecipe = await existingBatchRecipe(f),
        assignmentWorker = await batchWorker(f, 'p414_assignment_worker');
    await f.call(
      'POST',
      manage,
      body: request(assignmentRecipe, assignmentWorker),
      expected: 201,
    );
    final other = await f.createLocation('Other purchasing Location');
    await f.call(
      'POST',
      '/users',
      expected: 201,
      body: {
        'id': newUuid(),
        'username': 'purchasing_other_admin',
        'password': merchandisingTestPassword,
        'locationId': other,
        'role': 'admin',
      },
    );
    final otherToken = await f.login('purchasing_other_admin');
    if (browser) {
      await f.account('p414_replacement_admin', role: 'admin');
    }
    final a = await f.stockArticle(
          sku: 'P412-A',
          name:
              'Literal <script>globalThis.purchasingInjected=true</script> 😀',
          unit: 'kg',
        ),
        b = await f.stockArticle(
          sku: 'P412-B',
          name: 'Second Article',
          unit: 'piece',
        );
    final legacy = await purchasingLegacyEvidence(f, includeAssignments: true);
    final largeArticles = <String>[];
    if (browser) {
      for (var i = 0; i < 50; i++) {
        largeArticles.add(
          (await f.stockArticle(
            sku: 'P414-LARGE-$i',
            name: 'Literal <script> Article $i',
            unit: i.isEven ? 'kg' : 'piece',
          )).id,
        );
      }
    }
    expect((legacy['stock_count_commands'] as List).first, greaterThan(0));
    expect((legacy['task_transfer_links'] as List).first, greaterThan(0));
    expect(
      (legacy['production_preparation_batch_count_corrections'] as List).first,
      greaterThan(0),
    );
    final upstreamPort = f.server!.port,
        client = HttpClient(),
        proxy = await HttpServer.bind('127.0.0.1', 0);
    var changed = false, stale = false, dropped = false, replays = 0;
    bool deliveryDropped = false;
    String? deliveryBody;
    String? gateMode;
    Completer<void>? gate;
    bool held = false;
    String? issueBody, orderId;
    Map? frozen;
    proxy.listen((request) async {
      try {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b)),
            issue =
                request.method == 'POST' &&
                request.uri.path.endsWith('/issue') &&
                (orderId == null ||
                    request.uri.path.contains('/orders/$orderId/'));
        if (request.uri.path == '/api/v1/platform/p414-test-gate') {
          request.response.headers.set(
            'access-control-allow-origin',
            'http://127.0.0.1:$webPort',
          );
          request.response.headers.set(
            'access-control-allow-headers',
            'authorization,content-type',
          );
          request.response.headers.set(
            'access-control-allow-methods',
            'POST,OPTIONS',
          );
          if (request.method == 'OPTIONS') {
            request.response.statusCode = 204;
            await request.response.close();
            return;
          }
          final token = request.headers
              .value('authorization')
              ?.replaceFirst('Bearer ', '');
          final principal = await f.auth.authenticate(token);
          await f.database.runAuthorized(
            principal,
            'purchasing.orders.manage',
            (tx, a) async {},
          );
          final action = jsonDecode(utf8.decode(bytes))['action'];
          if (action == 'release') {
            if (gate != null && !gate!.isCompleted) gate!.complete();
            gateMode = null;
          } else if (action != 'status') {
            gateMode = action as String;
            gate = Completer<void>();
            held = false;
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'held': held}));
          await request.response.close();
          return;
        }
        if (gateMode == 'fail_refresh' &&
            request.method == 'GET' &&
            RegExp(
              r'/purchasing/locations/[^/]+/orders/[^/]+$',
            ).hasMatch(request.uri.path)) {
          gateMode = null;
          request.response.statusCode = 503;
          request.response.headers.set(
            'access-control-allow-origin',
            'http://127.0.0.1:$webPort',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'code': 'database_unavailable',
              'message': 'Injected current-detail refresh failure.',
            }),
          );
          await request.response.close();
          return;
        }
        final before = issue ? await purchasingEvidence(f) : null;
        if (issue && dropped) expect(utf8.decode(bytes), issueBody);
        final outgoing = await client.openUrl(
          request.method,
          Uri.parse('http://127.0.0.1:$upstreamPort${request.uri}'),
        );
        request.headers.forEach((n, vs) {
          if (!['host', 'content-length', 'connection'].contains(n)) {
            for (final v in vs) {
              outgoing.headers.add(n, v);
            }
          }
        });
        outgoing.add(bytes);
        final response = await outgoing.close(),
            data = await response.fold<List<int>>([], (a, b) => a..addAll(b));
        if (gateMode == 'hold_read' &&
                request.method == 'GET' &&
                request.uri.path.endsWith('/delivery-summary') ||
            gateMode == 'hold_write' &&
                request.method == 'POST' &&
                request.uri.path.endsWith('/deliveries')) {
          held = true;
          await gate!.future;
        }
        if (request.method == 'POST' &&
            request.uri.path.endsWith('/deliveries') &&
            response.statusCode == 201 &&
            !deliveryDropped) {
          deliveryDropped = true;
          deliveryBody = utf8.decode(bytes);
          await f.restart(port: upstreamPort);
          request.response.statusCode = 503;
          response.headers.forEach((n, vs) {
            if (n.startsWith('access-control-')) {
              for (final v in vs) {
                request.response.headers.add(n, v);
              }
            }
          });
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'code': 'database_unavailable',
              'message':
                  'Committed delivery response lost by acceptance gateway.',
            }),
          );
          await request.response.close();
          return;
        }
        if (request.method == 'POST' &&
            request.uri.path.endsWith('/deliveries') &&
            response.statusCode == 201 &&
            jsonDecode(utf8.decode(data))['replayed'] == true) {
          expect(utf8.decode(bytes), deliveryBody);
        }
        if (request.method == 'PUT' &&
            request.uri.path.contains('/purchasing/') &&
            request.uri.path.contains('/orders/') &&
            response.statusCode == 200 &&
            !changed) {
          final d = jsonDecode(utf8.decode(data))['order'] as Map;
          expect(
            (d['lines'] as List).map((dynamic l) => l['quantity']).toList(),
            ['2.500', '12.000'],
          );
          await editRecipeArticle(f, a, unit: 'bag');
          changed = true;
        }
        if (issue && response.statusCode == 409) {
          expect(jsonDecode(utf8.decode(data))['code'], 'article_unit_changed');
          await purchasingUnchanged(f, before!);
          stale = true;
        }
        if (issue && response.statusCode == 200) {
          final result = jsonDecode(utf8.decode(data)) as Map;
          expect(result['order']['lines'][0]['unit'], 'bag');
          if (dropped) {
            replays++;
            await purchasingUnchanged(f, before!);
            expect(result['order'], frozen);
          } else {
            expect(stale, true);
            issueBody = utf8.decode(bytes);
            frozen = result['order'] as Map;
            orderId = frozen!['id'] as String;
            dropped = true;
            final current = (await f.call('GET', '/articles/${a.id}')).body;
            await f.call(
              'POST',
              '/articles/${a.id}/edit',
              body: {
                'expectedVersion': current['version'],
                'sku': current['sku'],
                'barcode': null,
                'name': 'Later Article label',
                'description': null,
                'unit': 'bag',
              },
            );
            await f.restart(port: upstreamPort);
            request.response.statusCode = 503;
            response.headers.forEach((n, vs) {
              if (n.startsWith('access-control-')) {
                for (final v in vs) {
                  request.response.headers.add(n, v);
                }
              }
            });
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'code': 'database_unavailable',
                'message': 'Committed response lost by acceptance gateway.',
              }),
            );
            await request.response.close();
            return;
          }
        }
        request.response.statusCode = response.statusCode;
        response.headers.forEach((n, vs) {
          if (![
            'transfer-encoding',
            'content-length',
            'connection',
          ].contains(n)) {
            for (final v in vs) {
              request.response.headers.add(n, v);
            }
          }
        });
        request.response.add(data);
        await request.response.close();
      } catch (e, stack) {
        stderr.writeln('Purchasing journey gateway failed: ${e.runtimeType}');
        Zone.current.handleUncaughtError(e, stack);
      }
    });
    final directory = await Directory.systemTemp.createTemp(
      'storeos_purchasing_journey_',
    );
    try {
      final defines = File('${directory.path}/defines.json'),
          data = {
            'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
            'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
            'STOREOS_PURCHASING_URL': 'http://127.0.0.1:${proxy.port}',
            'STOREOS_PURCHASING_A': a.id,
            'STOREOS_PURCHASING_B': b.id,
            'STOREOS_PURCHASING_LARGE': largeArticles.join(','),
          };
      await defines.writeAsString(jsonEncode(data));
      final process = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        browser
            ? [
                'drive',
                '--no-pub',
                '--driver=test_driver/purchasing.dart',
                '--target=integration_test/purchasing_test.dart',
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
                'test/purchasing_http_journey.dart',
                '--reporter',
                'expanded',
              ],
        workingDirectory: '../client_flutter',
        runInShell: Platform.isWindows,
        environment: data,
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
      expect(stale, true);
      expect(dropped, true);
      expect(replays, 2);
      expect(deliveryDropped, true);
      final current = (await f.call('GET', '$purchasingOrders/$orderId')).body;
      expect(current['status'], 'closed');
      expect(current['lines'], frozen!['lines']);
      expect(current['supplier'], frozen!['supplier']);
      expect(current['version'], 5);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".purchasing_commands WHERE kind='order_issue' AND order_id='$orderId'",
        )).single.first,
        1,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries WHERE action='purchasing.order.issued' AND entity_id='$orderId'",
        )).single.first,
        1,
      );
      await f.call(
        'GET',
        '$purchasingOrders/$orderId',
        token: await f.login('recipe_counter'),
        expected: 403,
      );
      await f.call(
        'GET',
        '$purchasingOrders/$orderId',
        token: otherToken,
        expected: 403,
      );
      expect(
        await purchasingLegacyEvidence(f, includeAssignments: true),
        legacy,
      );
    } finally {
      if (gate != null && !gate!.isCompleted) gate!.complete();
      await proxy.close(force: true);
      client.close(force: true);
      await directory.delete(recursive: true);
    }
  }, allowedOrigins: {'http://127.0.0.1:$webPort'});
}
