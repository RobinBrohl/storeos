import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';
import 'task_planogram_fixture.dart';
import 'task_knowledge_fixture.dart' show knowledgeRoot;

void main() {
  for (final browser in [false, true]) {
    test(
      'P4.11 real ${browser ? 'Chrome UI' : 'Flutter controllers'} approval, exact restart retry and recipient ordinary Guided Work',
      () => _transferJourney(browser),
      skip:
          merchandisingDatabaseAvailable &&
              Platform.environment[browser
                      ? 'STOREOS_TRANSFER_BROWSER'
                      : 'STOREOS_TRANSFER_CLIENT_JOURNEY'] ==
                  '1'
          ? false
          : 'Opt-in Flutter with isolated PostgreSQL required.',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

Future<void> _transferJourney(bool browser) async {
  final probe = await ServerSocket.bind('127.0.0.1', 0), webPort = probe.port;
  await probe.close();
  await withMerchandisingFixture((f) async {
    final s = await planogramTaskScenario(
          f,
          publishShift: false,
          knowledge: true,
        ),
        r = await batchWorker(f, 'transfer_recipient');
    final recipe = await batchRecipe(f), opening = batchOpening(recipe);
    await f.call(
      'POST',
      batchSelf,
      token: r.token,
      body: opening,
      expected: 201,
    );
    await seedRecipeCountEvidence(f);
    Future<List<Object?>> unrelatedEvidence() async => [
      ...await recipeEvidence(f, stock: true),
      for (final table in [
        'production_recipes',
        'production_recipe_revisions',
        'production_recipe_ingredients',
        'production_preparation_batches',
        'production_preparation_batch_commands',
        'production_preparation_batch_count_corrections',
      ])
        (await f.owner.execute(
          "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
        )).single.toList(),
    ];
    final untouched = await unrelatedEvidence();
    final shift = newUuid(),
        start = DateTime.now().toUtc().add(const Duration(days: 1));
    await f.call(
      'POST',
      '/shifts',
      body: {
        'id': shift,
        'locationId': merchandisingTestLocation,
        'employeeId': s.employeeId,
        'startsAt': start.toIso8601String(),
        'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
        'selections': [
          {'templateId': s.templateId, 'revisionId': s.templateRevisionId},
        ],
      },
      expected: 201,
    );
    await f.call(
      'POST',
      '/shifts/$shift/publish',
      body: {'expectedVersion': 1},
    );
    final extra = <String, Map<String, dynamic>>{};
    if (browser) {
      for (final kind in [
        'decline',
        'source_withdraw',
        'recipient_withdraw',
        'reject',
        'overlap',
        'stale',
        'guidance',
      ]) {
        final sourceShift = newUuid(),
            requestId = newUuid(),
            begins = start.add(Duration(days: 2, hours: extra.length * 3)),
            ends = begins.add(const Duration(hours: 1));
        await f.call(
          'POST',
          '/shifts',
          body: {
            'id': sourceShift,
            'locationId': merchandisingTestLocation,
            'employeeId': s.employeeId,
            'startsAt': begins.toIso8601String(),
            'endsAt': ends.toIso8601String(),
            'selections': [
              {'templateId': s.templateId, 'revisionId': s.templateRevisionId},
            ],
          },
          expected: 201,
        );
        await f.call(
          'POST',
          '/shifts/$sourceShift/publish',
          body: {'expectedVersion': 1},
        );
        await f.call(
          'POST',
          '/me/shift-transfers',
          token: s.token,
          body: {
            'operationId': newUuid(),
            'requestId': requestId,
            'sourceShiftId': sourceShift,
            'expectedSourceVersion': 2,
            'recipientEmployeeId': r.employee,
          },
          expected: 201,
        );
        if (kind != 'decline') {
          await f.call(
            'POST',
            '/me/shift-transfers/$requestId/accept',
            token: r.token,
            body: {'operationId': newUuid(), 'expectedVersion': 1},
          );
        }
        extra[kind] = {
          'requestId': requestId,
          'shiftId': sourceShift,
          'startsAt': begins.toIso8601String(),
          'endsAt': ends.toIso8601String(),
        };
      }
    }
    final upstreamPort = f.server!.port,
        client = HttpClient(),
        proxy = await HttpServer.bind('127.0.0.1', 0);
    bool clockSet = false, dropped = false, restarted = false;
    int replays = 0;
    String? approvedId, replacement, approvalBody;
    List<Object?>? beforeReplay;
    Future<List<Object?>> conserved() async => [
      for (final table in [
        'shifts',
        'task_instances',
        'task_transfer_links',
        'workforce_shift_transfer_requests',
        'workforce_shift_transfer_commands',
        'audit_entries',
      ])
        (await f.owner.execute(
          "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
        )).single.toList(),
    ];
    proxy.listen((request) async {
      try {
        final bytes = await request.fold<List<int>>([], (a, b) => a..addAll(b)),
            text = utf8.decode(bytes);
        if (!clockSet &&
            request.uri.path.endsWith('/auth/login') &&
            text.contains('guided_worker')) {
          // Set a real imminent interval through the supported amendment command
          // after browser compilation; no clock/write test API is introduced.
          final now =
              (await f.owner.execute('SELECT clock_timestamp()')).single.first
                  as DateTime;
          // Allow the three browser identities to complete the success journey.
          // Boundary crossing is forced separately by the observed audit barrier.
          final begins = now.add(Duration(seconds: browser ? 60 : 20));
          await f.call(
            'POST',
            '/shifts/$shift/amend',
            body: {
              'expectedVersion': 2,
              'startsAt': begins.toIso8601String(),
              'endsAt': begins.add(const Duration(hours: 1)).toIso8601String(),
            },
          );
          clockSet = true;
        }
        final approval =
            request.method == 'POST' && request.uri.path.endsWith('/approve');
        final decisiveApproval =
            approval &&
            (approvedId == null || request.uri.path.contains(approvedId!));
        if (decisiveApproval && dropped) {
          expect(text, approvalBody);
          beforeReplay = await conserved();
        }
        if (approval && !decisiveApproval) {
          final entry = extra.entries.singleWhere(
            (e) => request.uri.path.contains(e.value['requestId'] as String),
          );
          final e = entry.value;
          if (entry.key == 'overlap') {
            final overlapping = newUuid();
            await f.call(
              'POST',
              '/shifts',
              body: {
                'id': overlapping,
                'locationId': merchandisingTestLocation,
                'employeeId': r.employee,
                'startsAt': e['startsAt'],
                'endsAt': e['endsAt'],
                'selections': [
                  {
                    'templateId': s.templateId,
                    'revisionId': s.templateRevisionId,
                  },
                ],
              },
              expected: 201,
            );
            await f.call(
              'POST',
              '/shifts/$overlapping/publish',
              body: {'expectedVersion': 1},
            );
          } else if (entry.key == 'stale') {
            final begins = DateTime.parse(
              e['startsAt'] as String,
            ).add(const Duration(minutes: 1));
            await f.call(
              'POST',
              '/shifts/${e['shiftId']}/amend',
              body: {
                'expectedVersion': 2,
                'startsAt': begins.toIso8601String(),
                'endsAt': e['endsAt'],
              },
            );
          } else if (entry.key == 'guidance') {
            await f.call(
              'POST',
              '$knowledgeRoot/${s.knowledge!.article.id}/retire',
              body: {'expectedVersion': 2},
            );
          }
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
        outgoing.contentLength = bytes.length;
        outgoing.add(bytes);
        final upstream = await outgoing.close(),
            response = await upstream.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
        if (decisiveApproval && upstream.statusCode == 200) {
          final result = jsonDecode(utf8.decode(response)) as Map;
          if (!dropped) {
            final finalNow =
                (await f.owner.execute('SELECT clock_timestamp()')).single.first
                    as DateTime;
            expect(
              finalNow.isBefore(
                DateTime.parse(result['request']['startsAt'] as String),
              ),
              isTrue,
              reason:
                  'Success journey must commit approval before source start.',
            );
            approvalBody = text;
            approvedId = result['request']['id'] as String;
            replacement = result['request']['replacementShiftId'] as String;
            dropped = true;
            await f.restart(port: upstreamPort);
            restarted = true;
            request.response.statusCode = 503;
            request.response.headers.contentType = ContentType.json;
            final origin = request.headers.value('origin');
            if (origin != null && f.allowedOrigins.contains(origin)) {
              request.response.headers.set(
                'access-control-allow-origin',
                origin,
              );
            }
            request.response.write(
              jsonEncode({
                'error': {
                  'code': 'database_unavailable',
                  'message': 'Injected committed response loss',
                },
              }),
            );
            await request.response.close();
            return;
          }
          expect(result['replayed'], true);
          expect(await conserved(), beforeReplay);
          replays++;
        }
        request.response.statusCode = upstream.statusCode;
        upstream.headers.forEach((name, values) {
          if (![
            'content-length',
            'connection',
            'transfer-encoding',
          ].contains(name)) {
            for (final v in values) {
              request.response.headers.add(name, v);
            }
          }
        });
        request.response.add(response);
        await request.response.close();
      } catch (e, stack) {
        stderr.writeln('Transfer gateway failed: ${e.runtimeType}');
        Zone.current.handleUncaughtError(e, stack);
      }
    });
    final directory = await Directory.systemTemp.createTemp(
      'storeos_transfer_journey_',
    );
    try {
      final defines = File('${directory.path}/defines.json'),
          data = {
            'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
            'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
            'STOREOS_TRANSFER_URL': 'http://127.0.0.1:${proxy.port}',
            'STOREOS_TRANSFER_SHIFT': shift,
            'STOREOS_TRANSFER_RECIPIENT': r.employee,
            'STOREOS_TRANSFER_EXTRAS': jsonEncode(extra),
          };
      await defines.writeAsString(jsonEncode(data));
      final result = await Process.run(
        Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter',
        browser
            ? [
                'drive',
                '--no-pub',
                '--driver=test_driver/integration_test.dart',
                '--target=integration_test/shift_transfer_test.dart',
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
                'test/shift_transfer_http_journey.dart',
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
      expect(dropped, true);
      expect(restarted, true);
      expect(replays, 1);
      final a = (await f.call('GET', '/shifts/$shift')).body,
          z = (await f.call('GET', '/shifts/$replacement')).body;
      expect(a['shift']['status'], 'cancelled');
      expect(a['shift']['employeeId'], s.employeeId);
      expect(z['shift']['employeeId'], r.employee);
      expect(z['shift']['startsAt'], a['shift']['startsAt']);
      expect(z['shift']['selections'], a['shift']['selections']);
      expect((z['tasks'] as List).single['status'], 'completed');
      final history = (await f.call(
        'GET',
        '/me/shift-transfers/$approvedId',
        token: s.token,
      )).body;
      expect(jsonEncode(history), isNot(contains('"results"')));
      expect(jsonEncode(history), isNot(contains('"value"')));
      expect(await unrelatedEvidence(), untouched);
      for (final entry in extra.entries) {
        final detail = (await f.call(
          'GET',
          '/locations/$merchandisingTestLocation/shift-transfers/${entry.value['requestId']}',
        )).body;
        expect(detail['status'], switch (entry.key) {
          'decline' => 'declined',
          'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
          'reject' => 'rejected',
          _ => 'accepted',
        });
        expect(
          (await f.call(
            'GET',
            '/shifts/${entry.value['shiftId']}',
          )).body['shift']['status'],
          'published',
        );
        expect(detail['replacementShiftId'], isNull);
      }
      for (final table in [
        'production_preparation_batches',
        'production_preparation_batch_commands',
      ]) {
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".$table',
          )).single.first,
          1,
        );
      }
    } finally {
      await proxy.close(force: true);
      client.close(force: true);
      await directory.delete(recursive: true);
    }
  }, allowedOrigins: {'http://127.0.0.1:$webPort'});
}
