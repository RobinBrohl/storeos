import 'dart:convert';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_application_fixture.dart' show b1Shift;
import 'shift_swap_http_fixture.dart';

String _after(String cursor) => 'after=${Uri.encodeQueryComponent(cursor)}';
List<dynamic> _envelope(String cursor) =>
    jsonDecode(utf8.decode(base64Url.decode(cursor))) as List<dynamic>;
String _encode(List<dynamic> envelope) =>
    base64Url.encode(utf8.encode(jsonEncode(envelope)));

Future<void> _invalidCursor(
  HttpSwapFixture x,
  String route,
  String token,
  String cursor,
) async {
  final before = await x.s.hash();
  final response = await swapCall(
    x.f,
    'GET',
    '$route${route.contains('?') ? '&' : '?'}${_after(cursor)}',
    token: token,
    expected: 400,
    code: 'invalid_cursor',
  );
  expect(response.keys.toSet(), {'code', 'message'});
  expect(await x.s.hash(), before);
}

Future<void> _markerMatrix(
  HttpSwapFixture x,
  String route,
  String token,
  String cursor,
  List<Object?> markers,
) async {
  final envelope = _envelope(cursor);
  for (final marker in markers) {
    await _invalidCursor(
      x,
      route,
      token,
      _encode([...envelope.take(envelope.length - 1), marker]),
    );
  }
  final missing = [...envelope]..removeAt(1);
  final extra = [...envelope]..insert(1, 'extra');
  await _invalidCursor(x, route, token, _encode(missing));
  await _invalidCursor(x, route, token, _encode(extra));
  final basis = envelope.indexWhere(
    (value) => value is String && RegExp(r'^[a-f0-9]{64}$').hasMatch(value),
  );
  for (final index in {0, envelope.length - 2, if (basis >= 0) basis}) {
    final invalid = [...envelope];
    invalid[index] = 'incorrect-scope-or-basis';
    await _invalidCursor(x, route, token, _encode(invalid));
  }
}

Future<(HttpSwapFixture, Set<String>)> _issuedLists(
  MerchandisingFixture f,
) async {
  final x = await httpSwapFixture(f);
  final source = await x.s.tx((tx, actor) => x.s.workforce.get(tx, x.s.shiftA));
  final ids = <String>{};
  for (var i = 0; i < 51; i++) {
    final shift = i == 0
        ? x.s.shiftA
        : await b1Shift(
            f,
            x.s.a.employee,
            source.draft.startsAt.add(Duration(hours: i * 2)),
            source.draft.selections,
          );
    final body = {
      ...x.requestBody,
      'sourceShiftId': shift,
      if (i != 0) 'requestId': newUuid(),
      if (i != 0) 'operationId': newUuid(),
    };
    final accepted = await swapCall(
      f,
      'POST',
      swapSelf,
      token: x.a,
      expected: 201,
      body: body,
    );
    ids.add(accepted['request']['id'] as String);
  }
  return (x, ids);
}

Future<Map<String, dynamic>> _firstPage(
  HttpSwapFixture x,
  String route,
  String token,
) async {
  final first = await swapCall(x.f, 'GET', route, token: token);
  expect(first['items'], hasLength(50));
  expect(first['nextCursor'], isA<String>());
  return first;
}

Future<void> _traverse(
  HttpSwapFixture x,
  String route,
  String token,
  Set<String> expected,
) async {
  final seen = <String>{};
  String? cursor;
  do {
    final page = await swapCall(
      x.f,
      'GET',
      cursor == null
          ? route
          : '$route${route.contains('?') ? '&' : '?'}${_after(cursor)}',
      token: token,
    );
    expect((page['items'] as List).length, lessThanOrEqualTo(50));
    for (final item in page['items'] as List) {
      expect(seen.add(item['id'] as String), true);
    }
    cursor = page['nextCursor'] as String?;
  } while (cursor != null);
  expect(seen, expected);
}

Future<String> _replacement(
  HttpSwapFixture x,
  String employee,
  String name,
) async {
  final f = x.f;
  final link =
      (await f.call('GET', '/employees/$employee/account-link')).body['link']
          as Map<String, dynamic>;
  await f.call(
    'POST',
    "/employee-links/${link['id']}/revoke",
    body: {'expectedVersion': link['version']},
  );
  final account = newUuid();
  await f.call(
    'POST',
    '/users',
    expected: 201,
    body: {
      'id': account,
      'username': name,
      'password': merchandisingTestPassword,
      'locationId': merchandisingTestLocation,
      'role': 'employee',
    },
  );
  await f.call(
    'POST',
    '/employees/$employee/account-link',
    expected: 201,
    body: {
      'id': newUuid(),
      'accountId': account,
      'expectedEmployeeVersion': 1,
      'expectedAccountVersion': 1,
    },
  );
  return f.login(name);
}

void main() {
  group('Stage B2a F01-F03 remediation through actual HTTP', () {
    test(
      'F01 captured recipient withdrawal rejects malformed scalars before receipt and preserves offered consent',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.prepare(2);
        final route = '$swapSelf/${x.id}/withdraw',
            before = await x.s.hash(),
            op = newUuid();
        for (final escaped in [
          r'\ud800',
          r'\udfff',
          r'\udc00\ud800',
          r'\ud800A',
        ]) {
          final error = await swapCall(
            f,
            'POST',
            route,
            token: x.b,
            raw:
                '{"operationId":"$op","expectedVersion":2,"reason":"$escaped"}',
            expected: 400,
            code: 'invalid_request',
          );
          expect(error['message'], 'Invalid swap reason.');
          expect(await x.s.hash(), before);
        }
        final accepted = await swapCall(
          f,
          'POST',
          route,
          token: x.b,
          body: {
            'operationId': op,
            'expectedVersion': 2,
            'reason': 'Valid 😀 closure',
          },
        );
        expect(accepted['kind'], 'recipient_withdraw');
        expect(
          accepted['request']['offerOperationId'],
          x.offerBody['operationId'],
        );
        expect(accepted['replayed'], false);
      }),
    );
    for (final manager in [false, true]) {
      test(
        'F01 ${manager ? 'manager reject' : 'source withdraw'} rejects escaped malformed scalars without receipt/audit and reuses UUID with 500 valid mixed scalars',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f);
          await x.request();
          final route = manager
              ? '${swapManage(x.id)}/reject'
              : '$swapSelf/${x.id}/withdraw';
          final token = manager ? f.adminToken! : x.a;
          final before = await x.s.hash(), reuse = newUuid();
          for (final reason in [
            r'\ud800',
            r'\udbff',
            r'\udc00',
            r'\udfff',
            r'\udc00\ud800',
            r'\ud800\ud800',
            r'\udfff\udfff',
            r'\ud800A',
            r'A\udc00',
            r'\ud800\u0061\udc00',
            r'x\u0000y',
            r'x\u001fy',
            r'x\u0085y',
            r'x\u009fy',
            r'\ud83d\ude00' * 501,
          ]) {
            final error = await swapCall(
              f,
              'POST',
              route,
              token: token,
              raw:
                  '{"operationId":"$reuse","expectedVersion":1,"reason":"$reason"}',
              expected: 400,
              code: 'invalid_request',
            );
            expect(error, {
              'code': 'invalid_request',
              'message': 'Invalid swap reason.',
            });
            expect(await x.s.hash(), before);
          }
          expect(
            (await f.owner.execute(
              "SELECT count(*) FROM ${f.schema}.workforce_shift_swap_commands WHERE operation_id='$reuse'",
            )).single.first,
            0,
          );
          expect(
            (await f.owner.execute(
              "SELECT count(*) FROM ${f.schema}.audit_entries WHERE changes->>'operationId'='$reuse'",
            )).single.first,
            0,
          );
          final good = await swapCall(
            f,
            'POST',
            route,
            token: token,
            raw:
                '{"operationId":"$reuse","expectedVersion":1,"reason":"  ${r'A\ud83d\ude00' * 250}  "}',
          );
          expect(good['replayed'], false);
          expect(good['request']['terminalReason'], 'A😀' * 250);
          expect(good['kind'], manager ? 'manager_reject' : 'source_withdraw');
          expect(
            await swapCall(
              f,
              'POST',
              route,
              token: token,
              body: {
                'operationId': reuse,
                'expectedVersion': 1,
                'reason': 'A😀' * 250,
              },
            ),
            {...good, 'replayed': true},
          );
        }),
      );
      for (final escaped in [
        r'\ud800\udc00',
        r'\udbff\udfff',
        r'BMP \ud83d\ude00 \u00e4',
      ]) {
        test(
          'F01 ${manager ? 'reject' : 'withdraw'} accepts valid escaped reason $escaped',
          () => withMerchandisingFixture((f) async {
            final x = await httpSwapFixture(f);
            await x.request();
            final reason = jsonDecode('"$escaped"') as String;
            final accepted = await swapCall(
              f,
              'POST',
              manager
                  ? '${swapManage(x.id)}/reject'
                  : '$swapSelf/${x.id}/withdraw',
              token: manager ? f.adminToken! : x.a,
              raw:
                  '{"operationId":"${newUuid()}","expectedVersion":1,"reason":"$escaped"}',
            );
            expect(accepted['request']['terminalReason'], reason);
          }),
        );
      }
      test(
        'F01 P4.11 ${manager ? 'rejection' : 'withdrawal'} preserves valid Unicode and classifies malformed scalar as invalid_reason',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f);
          await f.call(
            'POST',
            '/shifts/${x.s.shiftB}/cancel',
            body: {
              'expectedVersion': 2,
              'reason': 'Free transfer recipient interval',
            },
          );
          final id = newUuid();
          await swapCall(
            f,
            'POST',
            '/me/shift-transfers',
            token: x.a,
            expected: 201,
            body: {...x.requestBody, 'requestId': id, 'operationId': newUuid()},
          );
          final route = manager
              ? '/locations/$merchandisingTestLocation/shift-transfers/$id/reject'
              : '/me/shift-transfers/$id/withdraw';
          final token = manager ? f.adminToken! : x.a,
              before = await x.s.hash(),
              op = newUuid();
          for (final escaped in [
            r'\ud800',
            r'\udfff',
            r'\udc00\ud800',
            r'\ud800A',
          ]) {
            final error = await swapCall(
              f,
              'POST',
              route,
              token: token,
              raw:
                  '{"operationId":"$op","expectedVersion":1,"reason":"$escaped"}',
              expected: 400,
              code: 'invalid_reason',
            );
            expect(error['message'], 'Use 1 to 500 plain-text code points.');
            expect(await x.s.hash(), before);
          }
          final accepted = await swapCall(
            f,
            'POST',
            route,
            token: token,
            raw:
                '{"operationId":"$op","expectedVersion":1,"reason":"  ${r'A\ud83d\ude00' * 250}  "}',
          );
          expect(accepted['request']['terminalReason'], 'A😀' * 250);
          expect(accepted['replayed'], false);
        }),
      );
    }
    test(
      'F02 genuine source, recipient and manager lists fence reader/link/version changes and traverse every authorized row',
      () => withMerchandisingFixture((f) async {
        final (x, ids) = await _issuedLists(f);
        final sourceRoot = '$swapSelf?direction=outgoing&status=requested';
        final recipientRoot = '$swapSelf?direction=incoming&status=requested';
        final managerRoot =
            '/locations/$merchandisingTestLocation/shift-swaps?status=requested';
        final aPage = await _firstPage(x, sourceRoot, x.a),
            bPage = await _firstPage(x, recipientRoot, x.b),
            mPage = await _firstPage(x, managerRoot, f.adminToken!);
        final ac = aPage['nextCursor'] as String,
            bc = bPage['nextCursor'] as String,
            mc = mPage['nextCursor'] as String;
        for (final (root, token) in [
          (sourceRoot, x.a),
          (recipientRoot, x.b),
          (managerRoot, f.adminToken!),
        ]) {
          await _traverse(x, root, token, ids);
        }
        final links = [
          for (final worker in [x.s.a, x.s.b])
            (await f.call(
              'GET',
              '/employees/${worker.employee}/account-link',
            )).body['link']['id'],
        ];
        for (final cursor in [ac, bc, mc]) {
          final envelope = _envelope(cursor);
          expect(envelope, hasLength(9));
          expect(envelope[7], matches(RegExp(r'^[a-f0-9]{64}$')));
          expect(envelope.whereType<int>(), isEmpty);
          for (final private in [
            x.s.a.account,
            x.s.b.account,
            f.adminId,
            ...links,
          ]) {
            expect(jsonEncode(envelope), isNot(contains(private as String)));
          }
        }
        final unrelated = await batchWorker(f, 'unrelated_cursor_reader');
        await _invalidCursor(x, sourceRoot, unrelated.token, ac);
        await _invalidCursor(x, sourceRoot, x.b, ac);
        await _invalidCursor(x, managerRoot, f.adminToken!, ac);
        for (final (route, token, cursor) in [
          (sourceRoot, x.a, ac),
          (recipientRoot, x.b, bc),
          (managerRoot, f.adminToken!, mc),
        ]) {
          for (final index in [0, 1, 2, 6, 7]) {
            final envelope = _envelope(cursor);
            envelope[index] = index == 7 ? '0' * 64 : newUuid();
            await _invalidCursor(x, route, token, _encode(envelope));
          }
        }
        await _invalidCursor(
          x,
          '$swapSelf?direction=incoming&status=requested',
          x.a,
          ac,
        );
        await _invalidCursor(
          x,
          '$swapSelf?direction=outgoing&status=offered',
          x.a,
          ac,
        );
        await f.account('second_cursor_manager', role: 'admin');
        final secondManager = await f.login('second_cursor_manager');
        await _invalidCursor(x, managerRoot, secondManager, mc);
        final secondPage = await _firstPage(x, managerRoot, secondManager);
        await _traverse(x, managerRoot, secondManager, ids);
        final aReplacement = await _replacement(
          x,
          x.s.a.employee,
          'new_source_reader',
        );
        await _invalidCursor(x, sourceRoot, aReplacement, ac);
        await _traverse(x, sourceRoot, aReplacement, ids);
        final bReplacement = await _replacement(
          x,
          x.s.b.employee,
          'new_recipient_reader',
        );
        await _invalidCursor(x, recipientRoot, bReplacement, bc);
        await _traverse(x, recipientRoot, bReplacement, ids);
        final aNew = await _firstPage(x, sourceRoot, aReplacement);
        final aLink =
            (await f.call(
                  'GET',
                  '/employees/${x.s.a.employee}/account-link',
                )).body['link']
                as Map<String, dynamic>;
        await f.call(
          'POST',
          "/employee-links/${aLink['id']}/revoke",
          body: {'expectedVersion': aLink['version']},
        );
        await f.call(
          'POST',
          '/employees/${x.s.a.employee}/account-link',
          expected: 201,
          body: {
            'id': newUuid(),
            'accountId': aLink['accountId'],
            'expectedEmployeeVersion': 1,
            'expectedAccountVersion': 1,
          },
        );
        final relinked = await f.login('new_source_reader');
        await _invalidCursor(
          x,
          sourceRoot,
          relinked,
          aNew['nextCursor'] as String,
        );
        final currentA = await _firstPage(x, sourceRoot, relinked);
        for (final (username, account, oldRole, root, cursor) in [
          (
            'new_source_reader',
            aLink['accountId'] as String,
            'employee',
            sourceRoot,
            currentA['nextCursor'] as String,
          ),
          (
            'second_cursor_manager',
            (await f.auth.authenticate(secondManager)).id,
            'admin',
            managerRoot,
            secondPage['nextCursor'] as String,
          ),
        ]) {
          await f.call(
            'POST',
            '/users/$account',
            body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
          );
          await f.call(
            'POST',
            '/users/$account',
            body: {'expectedVersion': 2, 'role': oldRole, 'isActive': true},
          );
          final token = await f.login(username);
          await _invalidCursor(x, root, token, cursor);
          await _traverse(x, root, token, ids);
        }
        // The same current Account can be authorized for both endpoint families.
        await f.call(
          'POST',
          "/users/${aLink['accountId']}",
          body: {'expectedVersion': 3, 'role': 'admin', 'isActive': true},
        );
        final bothFamilies = await f.login('new_source_reader');
        final selfAdminPage = await _firstPage(x, sourceRoot, bothFamilies);
        final managerAdminPage = await _firstPage(x, managerRoot, bothFamilies);
        await _invalidCursor(
          x,
          managerRoot,
          bothFamilies,
          selfAdminPage['nextCursor'] as String,
        );
        await _invalidCursor(
          x,
          sourceRoot,
          bothFamilies,
          managerAdminPage['nextCursor'] as String,
        );
        await _traverse(x, sourceRoot, bothFamilies, ids);
        await _traverse(x, managerRoot, bothFamilies, ids);
        final otherLocation = await f.createLocation('Other cursor location');
        await f.call(
          'POST',
          '/users',
          expected: 201,
          body: {
            'id': newUuid(),
            'username': 'other_location_manager',
            'password': merchandisingTestPassword,
            'locationId': otherLocation,
            'role': 'admin',
          },
        );
        final locationManager = await f.login('other_location_manager');
        await f.restart(locationId: otherLocation);
        await _invalidCursor(
          x,
          '/locations/$otherLocation/shift-swaps?status=requested',
          locationManager,
          mc,
        );
        await f.restart();
        await withMerchandisingFixture((other) async {
          final foreign = await httpSwapFixture(other);
          await _invalidCursor(foreign, managerRoot, other.adminToken!, mc);
        }, homeCompanyId: newUuid());
      }),
      timeout: const Timeout(Duration(minutes: 3)),
    );
    test(
      'F03 genuine participant and manager list envelopes classify every malformed typed UUID marker as invalid_cursor',
      () => withMerchandisingFixture((f) async {
        final (x, _) = await _issuedLists(f);
        for (final (route, token) in [
          ('$swapSelf?direction=outgoing', x.a),
          ('/locations/$merchandisingTestLocation/shift-swaps', f.adminToken!),
        ]) {
          final page = await _firstPage(x, route, token);
          await _markerMatrix(x, route, token, page['nextCursor'] as String, [
            1,
            true,
            <Object?>[],
            <String, Object?>{},
            'bad',
            ' AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA ',
            'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
            null,
          ]);
        }
        await swapCall(
          f,
          'GET',
          '$swapSelf/not-a-uuid',
          token: x.a,
          expected: 400,
          code: 'invalid_request',
        );
        await swapCall(
          f,
          'GET',
          '$swapSelf?status=bad',
          token: x.a,
          expected: 400,
          code: 'invalid_request',
        );
        await swapCall(
          f,
          'GET',
          '$swapSelf?direction=bad',
          token: x.a,
          expected: 400,
          code: 'invalid_request',
        );
      }),
      timeout: const Timeout(Duration(minutes: 3)),
    );
    test(
      'F03 issued colleague, counterpart and history cursor markers fail locally without protected reads or writes',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        for (var i = 0; i < 51; i++) {
          await batchWorker(f, 'cursor_peer_$i');
        }
        final colleagues =
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues';
        final colleaguePage = await _firstPage(x, colleagues, x.a);
        await _markerMatrix(
          x,
          colleagues,
          x.a,
          colleaguePage['nextCursor'] as String,
          [
            1,
            true,
            <Object?>[],
            'bad',
            'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA',
            null,
          ],
        );
        await f.call(
          'POST',
          '/shifts/${x.s.shiftB}/cancel',
          body: {
            'expectedVersion': 2,
            'reason': 'Generate genuine owned cursor page',
          },
        );
        await x.request();
        final original = await x.s.tx(
          (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
        );
        final shifts = <String>[];
        for (var i = 0; i < 51; i++) {
          shifts.add(
            await b1Shift(
              f,
              x.s.b.employee,
              original.draft.startsAt.add(Duration(days: 1, hours: i * 2)),
              original.draft.selections,
            ),
          );
        }
        final root = '$swapSelf/${x.id}/counterparts';
        final candidates = await _firstPage(x, root, x.b);
        final cursor = candidates['nextCursor'] as String,
            marker = _envelope(cursor).last as List;
        await _markerMatrix(x, root, x.b, cursor, [
          null,
          1,
          true,
          'bad',
          <Object?>[],
          [marker[0]],
          [marker[0], marker[1], 'extra'],
          [1, marker[1]],
          [true, marker[1]],
          ['bad', marker[1]],
          ['2026-02-30T12:00:00Z', marker[1]],
          ['2026-10-14T12:00:00', marker[1]],
          [marker[0], false],
          [marker[0], 'bad'],
          [marker[0], 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'],
        ]);
        await swapCall(
          f,
          'GET',
          '$root?${_after(cursor)}',
          token: x.a,
          expected: 404,
          code: 'not_found',
        );
        await swapCall(
          f,
          'GET',
          '$root/not-a-uuid',
          token: x.b,
          expected: 400,
          code: 'invalid_request',
        );
        final continuation = await swapCall(
          f,
          'GET',
          '$root?${_after(cursor)}',
          token: x.b,
        );
        expect(continuation['items'], hasLength(1));
        x.offerBody['counterpartShiftId'] = shifts.first;
        await x.offer();
        await x.confirm();
        await x.approve();
        for (final (route, token) in [
          ('$swapSelf/${x.id}/history', x.a),
          ('${swapManage(x.id)}/history', f.adminToken!),
        ]) {
          final first = await swapCall(f, 'GET', route, token: token),
              historyCursor = first['nextCursor'] as String;
          final historyMarker = _envelope(historyCursor).last as List;
          await _markerMatrix(x, route, token, historyCursor, [
            null,
            1,
            true,
            <Object?>[],
            [1],
            [historyMarker[0], historyMarker[1], 'extra'],
            ['2', historyMarker[1]],
            [historyMarker[0], false],
            [historyMarker[0], 'bad'],
            [historyMarker[0], 'AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA'],
          ]);
          final last = await swapCall(
            f,
            'GET',
            '$route?${_after(historyCursor)}',
            token: token,
          );
          expect((last['items'] as List).map((r) => r['acceptedVersion']), [
            3,
            4,
          ]);
        }
      }),
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, skip: swapHttpSkip);
}
