import 'dart:convert';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_http_fixture.dart';

void main() {
  group('Stage B2a strict HTTP parsing', () {
    test(
      'malformed JSON, nested decoded duplicate names, field injection and strict command types consume no operation',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f), before = await x.s.hash();
        for (final raw in [
          '',
          '{',
          '[]',
          'null',
          'true',
          '{"operationId":"x","operati\\u006fnId":"y"}',
          '{"extra":{"a":1,"\\u0061":2}}',
          '{"extra":[{"nested":{"key":1,"k\\u0065y":2}}]}',
        ]) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            raw: raw,
            expected: 400,
            code: 'invalid_json',
          );
        }
        for (final extra in [
          'actor',
          'accountId',
          'sourceEmployeeId',
          'owner',
          'replacementShiftId',
          'snapshot',
          'requestedAt',
          'kind',
          'role',
        ]) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            body: {...x.requestBody, extra: 'injected'},
            expected: 400,
            code: 'invalid_request',
          );
        }
        for (final patch in [
          {'operationId': null},
          {'operationId': 1},
          {'operationId': ' ${newUuid()} '},
          {'requestId': 'bad'},
          {'sourceShiftId': <String>[]},
          {'recipientEmployeeId': true},
          {'expectedSourceVersion': '2'},
          {'expectedSourceVersion': 2.0},
          {'expectedSourceVersion': 0},
          {'expectedSourceVersion': 2147483648},
        ]) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            body: {...x.requestBody, ...patch},
            expected: 400,
            code: 'invalid_request',
          );
        }
        expect(await x.s.hash(), before);
        final upper = {
          for (final e in x.requestBody.entries)
            e.key: e.value is String
                ? (e.value as String).toUpperCase()
                : e.value,
        };
        final accepted = await swapCall(
          f,
          'POST',
          swapSelf,
          token: x.a,
          body: upper,
          expected: 201,
        );
        expect(accepted['operationId'], x.requestBody['operationId']);
        expect(accepted['request']['id'], x.id);
        expect(await x.request(), {...accepted, 'replayed': true});
      }),
    );
    test(
      '8192 UTF-8 byte boundary, declared/chunked overflow and supported media type',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f), before = await x.s.hash();
        for (final media in [
          null,
          'text/plain',
          'application/problem+json',
          'application/jsonp',
        ]) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            body: x.requestBody,
            mediaType: media,
            expected: 415,
            code: 'unsupported_media_type',
          );
        }
        for (final chunked in [false, true]) {
          for (final raw in [' ' * 8193, '😀' * 2049]) {
            await swapCall(
              f,
              'POST',
              swapSelf,
              token: x.a,
              raw: raw,
              chunked: chunked,
              expected: 413,
              code: 'body_too_large',
            );
          }
        }
        expect(await x.s.hash(), before);
        final json = jsonEncode(x.requestBody);
        final exact = json + ' ' * (8192 - utf8.encode(json).length);
        expect(utf8.encode(exact), hasLength(8192));
        final accepted = await swapCall(
          f,
          'POST',
          swapSelf,
          token: x.a,
          raw: exact,
          mediaType: 'Application/JSON; charset=utf-8',
          expected: 201,
        );
        expect(await x.request(), {...accepted, 'replayed': true});
      }),
    );
    test(
      'every route rejects unknown and decoded duplicate query fields and malformed IDs',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.request();
        final before = await x.s.hash();
        final routes = [
          (
            'GET',
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues',
            x.a,
            <String, dynamic>{},
          ),
          ('GET', swapSelf, x.a, <String, dynamic>{}),
          ('POST', swapSelf, x.a, x.requestBody),
          ('GET', '$swapSelf/${x.id}', x.a, <String, dynamic>{}),
          ('GET', '$swapSelf/${x.id}/history', x.a, <String, dynamic>{}),
          ('GET', '$swapSelf/${x.id}/counterparts', x.b, <String, dynamic>{}),
          (
            'GET',
            '$swapSelf/${x.id}/counterparts/${x.s.shiftB}',
            x.b,
            <String, dynamic>{},
          ),
          for (final kind in ['offer', 'confirm', 'decline', 'withdraw'])
            ('POST', '$swapSelf/${x.id}/$kind', x.a, x.confirmBody),
          (
            'GET',
            '/locations/$merchandisingTestLocation/shift-swaps',
            f.adminToken!,
            <String, dynamic>{},
          ),
          ('GET', swapManage(x.id), f.adminToken!, <String, dynamic>{}),
          (
            'GET',
            '${swapManage(x.id)}/history',
            f.adminToken!,
            <String, dynamic>{},
          ),
          for (final kind in ['approve', 'reject'])
            (
              'POST',
              '${swapManage(x.id)}/$kind',
              f.adminToken!,
              x.approvalBody,
            ),
        ];
        for (final (method, route, token, body) in routes) {
          for (final query in [
            'injected=x',
            'after=x&after=y',
            'after=x&%61fter=y',
          ]) {
            await swapCall(
              f,
              method,
              '$route?$query',
              token: token,
              body: method == 'POST' ? body : null,
              expected: 400,
              code: 'invalid_request',
            );
          }
        }
        for (final query in [
          'status=UNKNOWN',
          'direction=both',
          'status=requested&status=offered',
          'after=',
          'after=bad',
          'after=${'a' * 2049}',
        ]) {
          await swapCall(
            f,
            'GET',
            '$swapSelf?$query',
            token: x.a,
            expected: 400,
          );
        }
        await swapCall(
          f,
          'GET',
          '/locations/$merchandisingTestLocation/shift-swaps?direction=incoming',
          expected: 400,
          code: 'invalid_request',
        );
        for (final route in [
          '$swapSelf/not-a-uuid',
          '$swapSelf/not-a-uuid/history',
          '$swapSelf/not-a-uuid/counterparts',
          '$swapSelf/${x.id}/counterparts/not-a-uuid',
          '/employee-home/shifts/not-a-uuid/swap-colleagues',
          '/locations/not-a-uuid/shift-swaps',
        ]) {
          await swapCall(
            f,
            'GET',
            route,
            token: route.contains('/counterparts') ? x.b : x.a,
            expected: route.startsWith('/locations/') ? 403 : 400,
          );
        }
        expect(await x.s.hash(), before);
      }),
    );
    test(
      'withdraw and reject reasons use approved Unicode bounds; clients cannot choose withdrawal kind',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.prepare(2);
        final before = await x.s.hash();
        for (final (route, token) in [
          ('$swapSelf/${x.id}/withdraw', x.a),
          ('${swapManage(x.id)}/reject', f.adminToken!),
        ]) {
          for (final reason in [
            null,
            42,
            '',
            '   ',
            '😀' * 501,
            'bad\u0000reason',
          ]) {
            await swapCall(
              f,
              'POST',
              route,
              token: token,
              body: {
                'operationId': newUuid(),
                'expectedVersion': 2,
                'reason': reason,
              },
              expected: 400,
              code: 'invalid_request',
            );
          }
          for (final field in ['role', 'kind', 'accountId']) {
            await swapCall(
              f,
              'POST',
              route,
              token: token,
              body: {
                'operationId': newUuid(),
                'expectedVersion': 2,
                'reason': 'Valid',
                field: 'recipient_withdraw',
              },
              expected: 400,
              code: 'invalid_request',
            );
          }
        }
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/confirm',
          token: x.a,
          body: {...x.confirmBody, 'reason': 'Unapproved field'},
          expected: 400,
          code: 'invalid_request',
        );
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/offer',
          token: x.b,
          body: {...x.offerBody, 'counterpartShiftId': false},
          expected: 400,
          code: 'invalid_request',
        );
        expect(await x.s.hash(), before);
        final accepted = await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/withdraw',
          token: x.b,
          body: {
            'operationId': newUuid(),
            'expectedVersion': 2,
            'reason': '  ${'😀' * 500}  ',
          },
        );
        expect(accepted['kind'], 'recipient_withdraw');
        expect(accepted['request']['terminalReason'], '😀' * 500);
      }),
    );
  }, skip: swapHttpSkip);
}
