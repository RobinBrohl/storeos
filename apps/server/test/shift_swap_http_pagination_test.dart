import 'dart:convert';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_application_fixture.dart' show b1Shift;
import 'shift_swap_http_fixture.dart';

String cursorQuery(String cursor) =>
    '?after=${Uri.encodeQueryComponent(cursor)}';
String cursorEnvelope(List<dynamic> envelope) =>
    base64Url.encode(utf8.encode(jsonEncode(envelope)));

void main() {
  group('Stage B2a real HTTP pagination', () {
    test(
      'history advances immutable receipt order and rejects reader/request/endpoint/marker substitution',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.prepare(3);
        await x.approve();
        final first = await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}/history',
          token: x.a,
        );
        final cursor = first['nextCursor'] as String;
        final raw =
            jsonDecode(utf8.decode(base64Url.decode(cursor))) as List<dynamic>;
        final private = await x.s.tx(
          (tx, actor) => x.s.links.forEmployee(tx, x.s.a.employee),
        );
        expect(jsonEncode(raw), isNot(contains(x.s.a.account)));
        expect(jsonEncode(raw), isNot(contains(private!.id)));
        expect(raw[5], matches(RegExp(r'^[a-f0-9]{64}$')));
        for (final endpoint in [
          '$swapSelf/${x.id}/history',
          '${swapManage(x.id)}/history',
        ]) {
          await swapCall(
            f,
            'GET',
            '$endpoint${cursorQuery(cursor)}',
            token: endpoint.startsWith('/me/') ? x.b : f.adminToken!,
            expected: 400,
            code: 'invalid_cursor',
          );
        }
        for (final marker in [
          null,
          1,
          <Object?>[],
          [2],
          ['2', raw.last[1]],
          [5, newUuid()],
          [2, newUuid()],
          [2, raw.last[1], 'extra'],
        ]) {
          final invalid = [...raw.take(raw.length - 1), marker];
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history${cursorQuery(cursorEnvelope(invalid))}',
            token: x.a,
            expected: 400,
            code: 'invalid_cursor',
          );
        }
        for (var i = 0; i < raw.length - 1; i++) {
          final invalid = [...raw];
          invalid[i] = 'wrong-scope';
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history${cursorQuery(cursorEnvelope(invalid))}',
            token: x.a,
            expected: 400,
            code: 'invalid_cursor',
          );
        }
        await swapCall(
          f,
          'GET',
          '$swapSelf${cursorQuery(cursor)}',
          token: x.a,
          expected: 400,
          code: 'invalid_cursor',
        );
        await swapCall(
          f,
          'GET',
          '$swapSelf/${newUuid()}/history${cursorQuery(cursor)}',
          token: x.a,
          expected: 404,
          code: 'not_found',
        );
        final second = await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}/history${cursorQuery(cursor)}',
          token: x.a,
        );
        expect((second['items'] as List).map((r) => r['acceptedVersion']), [
          3,
          4,
        ]);
        expect(second['nextCursor'], null);
        // A valid exact last-receipt marker returns an empty, bounded page.
        final endMarker = [4, second['items'][1]['operationId']];
        final atEnd = cursorEnvelope([...raw.take(raw.length - 1), endMarker]);
        expect(
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history${cursorQuery(atEnd)}',
            token: x.a,
          ),
          {'items': <Object?>[], 'nextCursor': null},
        );
        final c = await batchWorker(f, 'foreign_history');
        await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}/history?after=bad',
          token: c.token,
          expected: 404,
          code: 'not_found',
        );
        // A link replacement changes reader basis and invalidates previously scoped cursors.
        final bLink =
            (await f.call(
                  'GET',
                  '/employees/${x.s.b.employee}/account-link',
                )).body['link']
                as Map<String, dynamic>;
        final bHistory = await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}/history',
          token: x.b,
        );
        await f.call(
          'POST',
          "/employee-links/${bLink['id']}/revoke",
          body: {'expectedVersion': bLink['version']},
        );
        await f.call(
          'POST',
          '/employees/${x.s.b.employee}/account-link',
          expected: 201,
          body: {
            'id': newUuid(),
            'accountId': x.s.b.account,
            'expectedEmployeeVersion': 1,
            'expectedAccountVersion': 1,
          },
        );
        final relinked = await f.login('swap_fixture_b');
        await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}/history${cursorQuery(bHistory['nextCursor'] as String)}',
          token: relinked,
          expected: 400,
          code: 'invalid_cursor',
        );
      }),
    );
    test(
      '52 colleagues, 51 own candidates and 51 addressed requests traverse bounded pages without identity leakage',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        for (var i = 0; i < 51; i++) {
          await batchWorker(f, 'http_page_peer_$i');
        }
        final colleagueRoot =
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues';
        final colleagues = await swapCall(f, 'GET', colleagueRoot, token: x.a);
        expect(colleagues['items'], hasLength(50));
        final colleagueCursor = colleagues['nextCursor'] as String;
        final finalColleagues = await swapCall(
          f,
          'GET',
          '$colleagueRoot${cursorQuery(colleagueCursor)}',
          token: x.a,
        );
        expect(finalColleagues['items'], hasLength(2));
        final identities = [
          ...colleagues['items'] as List,
          ...finalColleagues['items'] as List,
        ];
        expect(identities.map((r) => r['employeeId']).toSet(), hasLength(52));
        for (final item in identities) {
          expect(item.keys.toSet(), {'employeeId', 'displayName'});
        }
        expect(finalColleagues['nextCursor'], null);
        await f.call(
          'POST',
          '/shifts/${x.s.shiftB}/cancel',
          body: {'expectedVersion': 2, 'reason': 'Own candidate fixture'},
        );
        await x.request();
        final source = await x.s.tx(
          (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
        );
        final shifts = <String>[];
        for (var i = 0; i < 51; i++) {
          shifts.add(
            await b1Shift(
              f,
              x.s.b.employee,
              source.draft.startsAt.add(Duration(days: 1, hours: i * 2)),
              source.draft.selections,
            ),
          );
        }
        final counterpartRoot = '$swapSelf/${x.id}/counterparts';
        final candidates = await swapCall(
          f,
          'GET',
          counterpartRoot,
          token: x.b,
        );
        final candidateCursor = candidates['nextCursor'] as String;
        expect(candidates['items'], hasLength(50));
        final last = await swapCall(
          f,
          'GET',
          '$counterpartRoot${cursorQuery(candidateCursor)}',
          token: x.b,
        );
        expect(last['items'], hasLength(1));
        final allCandidates = [
          ...candidates['items'] as List,
          ...last['items'] as List,
        ];
        expect(allCandidates.map((r) => r['shiftId']).toSet(), shifts.toSet());
        expect(last['nextCursor'], null);
        for (final candidate in allCandidates) {
          expect(candidate.keys.toSet(), {
            'shiftId',
            'version',
            'startsAt',
            'endsAt',
          });
        }
        await swapCall(
          f,
          'GET',
          '$counterpartRoot${cursorQuery(colleagueCursor)}',
          token: x.b,
          expected: 400,
          code: 'invalid_cursor',
        );
        await swapCall(
          f,
          'GET',
          '$counterpartRoot${cursorQuery(candidateCursor)}',
          token: x.a,
          expected: 404,
          code: 'not_found',
        );
        final markers =
            jsonDecode(utf8.decode(base64Url.decode(candidateCursor)))
                as List<dynamic>;
        markers[markers.length - 1] = <String>[];
        await swapCall(
          f,
          'GET',
          '$counterpartRoot${cursorQuery(cursorEnvelope(markers))}',
          token: x.b,
          expected: 400,
          code: 'invalid_cursor',
        );
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/withdraw',
          token: x.a,
          body: {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'Release fixture A',
          },
        );
        for (final shift in shifts) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.b,
            expected: 201,
            body: {
              'operationId': newUuid(),
              'requestId': newUuid(),
              'sourceShiftId': shift,
              'expectedSourceVersion': 2,
              'recipientEmployeeId': x.s.a.employee,
            },
          );
        }
        final root = '$swapSelf?direction=incoming&status=requested';
        final requests = await swapCall(f, 'GET', root, token: x.a);
        expect(requests['items'], hasLength(50));
        final requestCursor = requests['nextCursor'] as String;
        final finalRequests = await swapCall(
          f,
          'GET',
          '$root&after=${Uri.encodeQueryComponent(requestCursor)}',
          token: x.a,
        );
        expect(finalRequests['items'], hasLength(1));
        expect(
          [
            ...requests['items'] as List,
            ...finalRequests['items'] as List,
          ].map((r) => r['id']).toSet(),
          hasLength(51),
        );
        expect(finalRequests['nextCursor'], null);
        for (final route in [
          '$swapSelf?direction=outgoing&status=requested',
          '$swapSelf?direction=incoming&status=offered',
          '/locations/$merchandisingTestLocation/shift-swaps?status=requested',
        ]) {
          await swapCall(
            f,
            'GET',
            '$route&after=${Uri.encodeQueryComponent(requestCursor)}',
            token: route.startsWith('/me/') ? x.a : f.adminToken!,
            expected: 400,
            code: 'invalid_cursor',
          );
        }
        await swapCall(
          f,
          'GET',
          '$root&after=${Uri.encodeQueryComponent(requestCursor)}',
          token: x.b,
          expected: 400,
          code: 'invalid_cursor',
        );
        for (final cursor in [
          colleagueCursor,
          candidateCursor,
          requestCursor,
        ]) {
          final decoded = utf8.decode(base64Url.decode(cursor));
          expect(decoded, isNot(contains(x.s.a.account)));
          expect(decoded, isNot(contains(x.s.b.account)));
          expect(cursor.length, lessThanOrEqualTo(2048));
        }
      }),
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }, skip: swapHttpSkip);
}
