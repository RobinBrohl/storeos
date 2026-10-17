import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

import 'merchandising_fixture.dart';
import 'shift_swap_http_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

void main() {
  test(
    'Step 9 four-actor Chrome, exact pair, dual Employee Home execution and explicit retry',
    () async {
      final portProbe = await ServerSocket.bind('127.0.0.1', 0),
          webPort = portProbe.port;
      await portProbe.close();
      await withMerchandisingFixture((f) async {
        expect(
          (await f.pool.runTx(
            (tx) => tx.execute('SELECT current_user'),
          )).single.first,
          f.runtimeUser,
        );
        final s = await stageAFixture(
          f,
          taskCount: 10,
          taskTitle:
              'ä😀 長 <script>globalThis.swapInjected=true</script> **literal**',
        );
        await f.account('swap_observer', role: 'viewer');
        for (final person in [s.a, s.b]) {
          final employee = (await f.call(
            'GET',
            '/employees/${person.employee}',
          )).body;
          await f.call(
            'POST',
            '/employees/${person.employee}/rename',
            body: {
              'expectedVersion': employee['version'],
              'displayName':
                  '${person.employee == s.a.employee ? 'A' : 'B'} ${'ä😀長 <script>literal</script> ' * 3}',
            },
          );
        }
        // Capture all consent bases after granting A manager capabilities.
        await f.call(
          'POST',
          '/users/${s.a.account}',
          body: {'expectedVersion': 1, 'role': 'admin', 'isActive': true},
        );
        final aToken = await f.login('swap_fixture_a');
        String? staleCounterpart;
        final extras = <String, String>{};
        for (final kind in ['decline', 'withdraw', 'reject', 'stale']) {
          final shift = newUuid(),
              id = newUuid(),
              start = DateTime.now().toUtc().add(
                Duration(days: 4 + extras.length),
              );
          await f.call(
            'POST',
            '/shifts',
            expected: 201,
            body: {
              'id': shift,
              'locationId': merchandisingTestLocation,
              'employeeId': s.a.employee,
              'startsAt': start.toIso8601String(),
              'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
              'selections': [
                {'templateId': s.template, 'revisionId': s.revision},
              ],
            },
          );
          await f.call(
            'POST',
            '/shifts/$shift/publish',
            body: {'expectedVersion': 1},
          );
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: aToken,
            expected: 201,
            body: {
              'operationId': newUuid(),
              'requestId': id,
              'sourceShiftId': shift,
              'expectedSourceVersion': 2,
              'recipientEmployeeId': s.b.employee,
            },
          );
          extras[kind] = id;
          if (kind == 'stale') {
            staleCounterpart = newUuid();
            await f.call(
              'POST',
              '/shifts',
              expected: 201,
              body: {
                'id': staleCounterpart,
                'locationId': merchandisingTestLocation,
                'employeeId': s.b.employee,
                'startsAt': start.toIso8601String(),
                'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
                'selections': [
                  {'templateId': s.template, 'revisionId': s.revision},
                ],
              },
            );
            await f.call(
              'POST',
              '/shifts/$staleCounterpart/publish',
              body: {'expectedVersion': 1},
            );
          }
        }
        final proxy = await HttpServer.bind('127.0.0.1', 0),
            client = HttpClient();
        final originalPort = f.server!.port;
        bool clockSet = false,
            dropped = false,
            retried = false,
            holdNext = false,
            staleAdvanced = false;
        String? approvalBody, requestId;
        String? approvalHash;
        Completer<void>? held, release;
        Object? proxyError;
        final stages = <String>[];
        final sub = proxy.listen((request) async {
          try {
            if (request.uri.path.startsWith('/__swap_probe/')) {
              switch (request.uri.path.split('/').last) {
                case 'arm':
                  holdNext = true;
                  held = Completer<void>();
                  release = Completer<void>();
                case 'held':
                  await held!.future;
                case 'release':
                  release!.complete();
              }
              request.response.headers.set(
                'access-control-allow-origin',
                'http://127.0.0.1:$webPort',
              );
              request.response.write('ok');
              await request.response.close();
              return;
            }
            final body = await request.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            if (!clockSet &&
                request.uri.path.endsWith('/auth/login') &&
                utf8.decode(body).contains('swap_fixture_a')) {
              final start = DateTime.now().toUtc().add(
                const Duration(seconds: 100),
              );
              for (final id in [s.shiftA, s.shiftB]) {
                await f.call(
                  'POST',
                  '/shifts/$id/amend',
                  body: {
                    'expectedVersion': 2,
                    'startsAt': start.toIso8601String(),
                    'endsAt': start
                        .add(const Duration(hours: 1))
                        .toIso8601String(),
                  },
                );
              }
              clockSet = true;
            }
            final swapCommand =
                request.method == 'POST' &&
                request.uri.path.contains('/shift-swaps');
            if (swapCommand &&
                !dropped &&
                !request.uri.path.endsWith('/approve')) {
              for (final id in [s.shiftA, s.shiftB]) {
                expect(
                  (await f.call('GET', '/shifts/$id')).body['shift']['status'],
                  'published',
                );
              }
            }
            final staleBarrier =
                !staleAdvanced &&
                request.method == 'POST' &&
                request.uri.path.endsWith('/${extras['stale']}/reject');
            if (staleBarrier) {
              await swapCall(
                f,
                'POST',
                '$swapSelf/${extras['stale']}/offer',
                token: s.b.token,
                body: {
                  'operationId': newUuid(),
                  'expectedVersion': 1,
                  'counterpartShiftId': staleCounterpart,
                  'expectedCounterpartVersion': 2,
                },
              );
              staleAdvanced = true;
            }
            if (request.uri.path.endsWith('/approve') && dropped) {
              expect(utf8.decode(body), approvalBody);
            }
            final outgoing = await client.openUrl(
              request.method,
              Uri.parse('http://127.0.0.1:$originalPort${request.uri}'),
            );
            request.headers.forEach((name, values) {
              if (!['host', 'content-length', 'connection'].contains(name)) {
                for (final value in values) {
                  outgoing.headers.add(name, value);
                }
              }
            });
            outgoing.contentLength = body.length;
            outgoing.add(body);
            final upstream = await outgoing.close();
            if (staleBarrier) expect(upstream.statusCode, 409);
            final bytes = await upstream.fold<List<int>>(
              [],
              (a, b) => a..addAll(b),
            );
            if (swapCommand && {200, 201}.contains(upstream.statusCode)) {
              final result = jsonDecode(utf8.decode(bytes)) as Map;
              stages.add(result['kind'] as String);
              if (result['kind'] == 'request') {
                requestId = result['request']['id'] as String;
              }
              if (result['kind'] == 'manager_approve') {
                if (!dropped) {
                  dropped = true;
                  approvalBody = utf8.decode(body);
                  approvalHash = await s.hash();
                  request.response.statusCode = 503;
                  request.response.headers.set(
                    'access-control-allow-origin',
                    'http://127.0.0.1:$webPort',
                  );
                  request.response.headers.contentType = ContentType.json;
                  request.response.write(
                    jsonEncode({
                      'code': 'service_unavailable',
                      'message': 'Injected completed response loss',
                    }),
                  );
                  await request.response.close();
                  return;
                }
                expect(result['replayed'], true);
                expect(await s.hash(), approvalHash);
                retried = true;
              }
            }
            if (holdNext &&
                request.method == 'GET' &&
                request.uri.path ==
                    '/api/v1/platform/me/shift-swaps/$requestId') {
              holdNext = false;
              held!.complete();
              await release!.future;
            }
            request.response.statusCode = upstream.statusCode;
            upstream.headers.forEach((name, values) {
              if (![
                'content-length',
                'connection',
                'transfer-encoding',
              ].contains(name)) {
                for (final value in values) {
                  request.response.headers.add(name, value);
                }
              }
            });
            request.response.add(bytes);
            await request.response.close();
          } catch (e) {
            proxyError = e;
            request.response.statusCode = 500;
            await request.response.close();
          }
        });
        final directory = await Directory.systemTemp.createTemp(
          'storeos_swap_step9_',
        );
        try {
          final defines = File('${directory.path}/defines.json');
          await defines.writeAsString(
            jsonEncode({
              'STOREOS_API_URL': 'http://127.0.0.1:${proxy.port}',
              'STOREOS_SWAP_BROWSER_URL': 'http://127.0.0.1:${proxy.port}',
              'STOREOS_KNOWLEDGE_PASSWORD': merchandisingTestPassword,
              'STOREOS_SWAP_SHIFT_A': s.shiftA,
              'STOREOS_SWAP_SHIFT_B': s.shiftB,
              'STOREOS_SWAP_EMPLOYEE_B': s.b.employee,
              'STOREOS_SWAP_EXTRAS': jsonEncode(extras),
            }),
          );
          final dart = Platform.environment['STOREOS_SWAP_PROBE_DART'];
          final snapshot =
              Platform.environment['STOREOS_SWAP_PROBE_FLUTTER_SNAPSHOT'];
          final result = await Process.run(
            dart ?? 'flutter',
            [
              ?snapshot,
              'drive',
              '--no-pub',
              '--driver=test_driver/integration_test.dart',
              '--target=integration_test/shift_swap_test.dart',
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
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
            runInShell: dart == null && Platform.isWindows,
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
          expect(proxyError, isNull);
          expect(dropped && retried, true);
          expect(stages.take(5), [
            'request',
            'offer',
            'confirm',
            'manager_approve',
            'manager_approve',
          ]);
          final approved = await swapCall(f, 'GET', swapManage(requestId!));
          for (final leg in approved['request']['legs'] as List) {
            expect(leg['taskLinks'], hasLength(10));
            final work = (await f.call(
              'GET',
              '/shifts/${leg['replacementShiftId']}',
            )).body;
            expect(work['shift']['employeeId'], leg['incomingEmployeeId']);
            expect((work['tasks'] as List).first['status'], 'completed');
            expect(
              (await f.call(
                'GET',
                '/shifts/${leg['sourceShiftId']}',
              )).body['shift']['status'],
              'cancelled',
            );
          }
          for (final kind in extras.keys) {
            final detail = await swapCall(f, 'GET', swapManage(extras[kind]!));
            expect(detail['request']['status'], switch (kind) {
              'decline' => 'declined',
              'withdraw' => 'withdrawn',
              _ => 'rejected',
            });
          }
        } finally {
          if (release != null && !release!.isCompleted) release!.complete();
          await sub.cancel();
          await proxy.close(force: true);
          client.close(force: true);
          await directory.delete(recursive: true);
        }
      }, allowedOrigins: {'http://127.0.0.1:$webPort'});
    },
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_SWAP_BROWSER'] == '1'
        ? false
        : 'Opt-in isolated PostgreSQL and Chrome required.',
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
