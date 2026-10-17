import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'merchandising_fixture.dart';
import 'shift_swap_http_fixture.dart';

void main() {
  test(
    'Step 8 Flutter controllers through real HTTP and restricted PostgreSQL replay',
    () => withMerchandisingFixture((f) async {
      final x = await httpSwapFixture(f);
      expect(
        (await f.pool.runTx(
          (tx) => tx.execute('SELECT current_user'),
        )).single.first,
        f.runtimeUser,
      );
      final upstreamPort = f.server!.port;
      final gateway = await HttpServer.bind('127.0.0.1', 0),
          client = HttpClient();
      final originals = <String, String>{}, conserved = <String, String>{};
      final replayed = <String>{};
      Object? gatewayFailure;
      final subscription = gateway.listen((request) async {
        try {
          // Both request and response entities complete before injecting loss.
          final body = await request.fold<List<int>>(
            [],
            (a, b) => a..addAll(b),
          );
          final text = utf8.decode(body);
          final command =
              request.method == 'POST' &&
              (request.uri.path.endsWith('/me/shift-swaps') ||
                  request.uri.path.endsWith('/approve'));
          final route = request.uri.path;
          if (command && originals.containsKey(route)) {
            expect(text, originals[route]);
          }
          final outgoing = await client.openUrl(
            request.method,
            Uri.parse('http://127.0.0.1:$upstreamPort${request.uri}'),
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
          final bytes = await upstream.fold<List<int>>(
            [],
            (a, b) => a..addAll(b),
          );
          if (command && {200, 201}.contains(upstream.statusCode)) {
            final result = jsonDecode(utf8.decode(bytes)) as Map;
            if (!originals.containsKey(route)) {
              originals[route] = text;
              conserved[route] = await x.s.hash();
              // Recreate production ServerApp/auth/router/native listener on the
              // same database and port. This is not an OS-process restart.
              await f.restart(port: upstreamPort);
              request.response.statusCode = 503;
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
            expect(await x.s.hash(), conserved[route]);
            replayed.add(route);
          }
          request.response.statusCode = upstream.statusCode;
          request.response.headers.contentType = ContentType.json;
          request.response.add(bytes);
          await request.response.close();
        } catch (e) {
          gatewayFailure = e;
          request.response.statusCode = 500;
          await request.response.close();
        }
      });
      try {
        final executable =
            Platform.environment['STOREOS_FLUTTER_EXECUTABLE'] ?? 'flutter';
        final dart = Platform.environment['STOREOS_SWAP_PROBE_DART'];
        final snapshot =
            Platform.environment['STOREOS_SWAP_PROBE_FLUTTER_SNAPSHOT'];
        final process = await Process.run(
          dart ?? executable,
          [
            ?snapshot,
            'test',
            '--no-pub',
            'test/shift_swap_http_probe.dart',
            '--reporter',
            'expanded',
          ],
          workingDirectory: '../client_flutter',
          runInShell: dart == null && Platform.isWindows,
          environment: {
            'STOREOS_SWAP_PROBE_URL': 'http://127.0.0.1:${gateway.port}',
            'STOREOS_SWAP_PROBE_SHIFT': x.s.shiftA,
            'STOREOS_SWAP_PROBE_COUNTERPART': x.s.shiftB,
            'STOREOS_SWAP_PROBE_RECIPIENT': x.s.b.employee,
          },
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
        expect(gatewayFailure, isNull);
        expect(process.exitCode, 0);
        expect(originals, hasLength(2));
        expect(replayed, hasLength(2));
        final page = await swapCall(
          f,
          'GET',
          '/locations/$merchandisingTestLocation/shift-swaps',
        );
        expect(page['items'].single['status'], 'approved');
        for (final shift in [x.s.shiftA, x.s.shiftB]) {
          expect(
            (await f.call('GET', '/shifts/$shift')).body['shift']['status'],
            'cancelled',
          );
        }
      } finally {
        await subscription.cancel();
        await gateway.close(force: true);
        client.close(force: true);
      }
    }),
    skip:
        merchandisingDatabaseAvailable &&
            Platform.environment['STOREOS_SWAP_FLUTTER_PROBE'] == '1'
        ? false
        : 'Opt-in isolated PostgreSQL and Flutter SDK required.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
