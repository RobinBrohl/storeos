import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/http/api_support.dart';
import 'package:storeos_server/src/http/guarded_http_server.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

// Only completed requests go over loopback here. Expiration and incomplete
// lifecycle tests use finite in-process streams in upload_lifecycle_test.dart.
void main() {
  for (final limit in [8192, 16384, 65536, 262144]) {
    test(
      'completed JSON boundary and overflow at $limit via production ingress',
      () async {
        final server = await GuardedHttpServer.bind(
          (request) async {
            try {
              final body = await readJson(
                request,
                limit: limit,
                rejectDuplicateNames: true,
              );
              return jsonResponse(200, {
                'length': (body['text'] as String).length,
              });
            } on PlatformFailure catch (error) {
              return jsonResponse(error.status, {'code': error.code});
            }
          },
          '127.0.0.1',
          0,
        );
        final client = HttpClient();
        addTearDown(() async {
          client.close(force: true);
          await server.close();
        });
        Future<(int, Map<String, dynamic>)> send(
          int size, {
          bool chunked = false,
        }) async {
          final payload = utf8.encode(jsonEncode({'text': 'x' * (size - 11)}));
          expect(payload.length, size);
          final request = await client.post('127.0.0.1', server.port, '/');
          request.headers.contentType = ContentType.json;
          if (!chunked) request.contentLength = payload.length;
          request.add(payload);
          final response = await request.close();
          return (
            response.statusCode,
            jsonDecode(await utf8.decoder.bind(response).join())
                as Map<String, dynamic>,
          );
        }

        expect((await send(limit)).$1, 200);
        for (final chunked in [false, true]) {
          final overflow = await send(limit + 1, chunked: chunked);
          expect(overflow.$1, 413);
          expect(overflow.$2, {'code': 'body_too_large'});
        }
        expect((await send(limit)).$1, 200);
      },
    );
  }

  test(
    'completed invalid JSON, duplicate names and media errors retain codes',
    () async {
      final server = await GuardedHttpServer.bind(
        (request) async {
          try {
            await readJson(request, rejectDuplicateNames: true);
            return Response.ok('ok');
          } on PlatformFailure catch (error) {
            return jsonResponse(error.status, {'code': error.code});
          }
        },
        '127.0.0.1',
        0,
      );
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close();
      });
      for (final (body, type, expected) in [
        ('{', 'application/json', 400),
        ('{"a":1,"a":2}', 'application/json', 400),
        ('{}', 'text/plain', 415),
      ]) {
        final request = await client.post('127.0.0.1', server.port, '/');
        request.headers.set(HttpHeaders.contentTypeHeader, type);
        request.write(body);
        final response = await request.close();
        expect(response.statusCode, expected);
        await response.drain<void>();
      }
    },
  );

  test(
    'shutdown owns listener and sockets while completed business work finishes',
    () async {
      final entered = Completer<void>();
      final finish = Completer<void>();
      var committed = false;
      final server = await GuardedHttpServer.bind(
        (request) async {
          await readJson(request);
          entered.complete();
          await finish.future;
          committed = true;
          return Response.ok('ok');
        },
        '127.0.0.1',
        0,
      );
      final port = server.port;
      final client = HttpClient();
      final request = await client.post('127.0.0.1', port, '/');
      request.headers.contentType = ContentType.json;
      request.write('{}');
      final response = request.close().then<void>(
        (r) => r.drain<void>(),
        onError: (Object _) {},
      );
      await entered.future;
      expect(server.activeRequests, 1);
      expect(server.incompleteBodies, 0);
      final stopping = server.close();
      expect(server.activeConnections, 0);
      expect(server.activeRequests, 1);
      finish.complete();
      await stopping;
      await server.close();
      await response;
      expect(committed, true);
      expect(server.activeRequests, 0);
      final rebound = await ServerSocket.bind('127.0.0.1', port);
      await rebound.close();
      client.close(force: true);
    },
  );
}
