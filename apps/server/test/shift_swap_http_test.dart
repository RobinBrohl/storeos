import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_http_fixture.dart';

void main() {
  group('Stage B2a real authenticated HTTP', () {
    for (final count in [1, 10]) {
      test(
        'complete paired lifecycle with $count Tasks, scoped reads and exact lost-response replay',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f, tasks: count);
          expect(
            (await f.pool.runTx(
              (tx) => tx.execute('SELECT current_user'),
            )).single.first,
            f.runtimeUser,
          );
          final originalA = (await f.call('GET', '/shifts/${x.s.shiftA}')).body;
          final originalB = (await f.call('GET', '/shifts/${x.s.shiftB}')).body;
          final colleagues = await swapCall(
            f,
            'GET',
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues',
            token: x.a,
          );
          expect(
            ShiftSwapColleaguePageDto.fromJson(colleagues).toJson(),
            colleagues,
          );
          expect(colleagues['items'], [
            {'employeeId': x.s.b.employee, 'displayName': 'swap_fixture_b'},
          ]);
          final requested = await x.request();
          expect(requested['request']['status'], 'requested');
          for (final (token, direction) in [
            (x.a, 'outgoing'),
            (x.b, 'incoming'),
          ]) {
            final page = await swapCall(
              f,
              'GET',
              '$swapSelf?status=requested&direction=$direction',
              token: token,
            );
            expect(ShiftSwapPageDto.fromJson(page).toJson(), page);
            expect(page['items'], [requested['request']]);
          }
          final candidates = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/counterparts',
            token: x.b,
          );
          expect(
            ShiftSwapCounterpartPageDto.fromJson(candidates).toJson(),
            candidates,
          );
          expect((candidates['items'] as List).single['shiftId'], x.s.shiftB);
          final candidate = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/counterparts/${x.s.shiftB}',
            token: x.b,
          );
          expect(ShiftSwapLegDto.fromJson(candidate).toJson(), candidate);
          final offered = await x.offer(), confirmed = await x.confirm();
          expect(confirmed['request']['legs'], offered['request']['legs']);
          expect(
            (await f.call('GET', '/shifts/${x.s.shiftA}')).body,
            originalA,
          );
          expect(
            (await f.call('GET', '/shifts/${x.s.shiftB}')).body,
            originalB,
          );
          final managerList = await swapCall(
            f,
            'GET',
            '/locations/$merchandisingTestLocation/shift-swaps?status=confirmed',
          );
          expect(managerList['items'], [confirmed['request']]);
          final approved = await x.approve();
          expect(approved['request']['status'], 'approved');
          for (final receipt in [requested, offered, confirmed, approved]) {
            expectSwapReceipt(receipt);
          }
          for (final leg in approved['request']['legs'] as List) {
            final original = (await f.call(
              'GET',
              "/shifts/${leg['sourceShiftId']}",
            )).body;
            final replacement = (await f.call(
              'GET',
              "/shifts/${leg['replacementShiftId']}",
            )).body;
            expect(original['shift']['status'], 'cancelled');
            expect(
              (original['tasks'] as List).every(
                (t) => t['status'] == 'cancelled',
              ),
              true,
            );
            expect(replacement['shift']['status'], 'published');
            expect(
              replacement['shift']['employeeId'],
              leg['incomingEmployeeId'],
            );
            expect(leg['taskLinks'], hasLength(count));
            for (final link in leg['taskLinks'] as List) {
              final old = (original['tasks'] as List).singleWhere(
                (t) => t['id'] == link['sourceTaskId'],
              );
              final next = (replacement['tasks'] as List).singleWhere(
                (t) => t['id'] == link['replacementTaskId'],
              );
              final oldDetail = (await f.call(
                'GET',
                "/shifts/${leg['sourceShiftId']}/tasks/${old['id']}",
              )).body;
              final nextDetail = (await f.call(
                'GET',
                "/shifts/${leg['replacementShiftId']}/tasks/${next['id']}",
              )).body;
              expect(oldDetail['content'], isNotNull);
              expect(nextDetail['content'], oldDetail['content']);
              expect(next['templateId'], old['templateId']);
              expect(next['revisionId'], old['revisionId']);
              expect(next['position'], link['position']);
            }
          }
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
            )).single.first,
            0,
          );
          final firstHistory = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history',
            token: x.a,
          );
          expect(firstHistory['items'], [requested, offered]);
          final cursor = firstHistory['nextCursor'] as String;
          final second = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history?after=${Uri.encodeQueryComponent(cursor)}',
            token: x.a,
          );
          expect(second, {
            'items': [confirmed, approved],
            'nextCursor': null,
          });
          final managerHistory = await swapCall(
            f,
            'GET',
            '${swapManage(x.id)}/history',
          );
          expect(managerHistory['items'], firstHistory['items']);
          expect(
            await swapCall(
              f,
              'GET',
              '${swapManage(x.id)}/history?after=${Uri.encodeQueryComponent(managerHistory['nextCursor'] as String)}',
            ),
            second,
          );
          final detail = await swapCall(f, 'GET', swapManage(x.id));
          expect(ShiftSwapDetailDto.fromJson(detail).toJson(), detail);
          expect(detail['request'], approved['request']);
          expect(detail['availableActions'], isEmpty);
          final before = await x.s.hash();
          await f.restart();
          for (final (route, token, body, receipt, status) in [
            (swapSelf, x.a, x.requestBody, requested, 201),
            ('$swapSelf/${x.id}/offer', x.b, x.offerBody, offered, 200),
            ('$swapSelf/${x.id}/confirm', x.a, x.confirmBody, confirmed, 200),
            (
              '${swapManage(x.id)}/approve',
              f.adminToken!,
              x.approvalBody,
              approved,
              200,
            ),
          ]) {
            expect(
              await swapCall(
                f,
                'POST',
                route,
                token: token,
                body: body,
                expected: status,
              ),
              {...receipt, 'replayed': true},
            );
          }
          expect(await x.s.hash(), before);
        }),
      );
    }
    for (final (kind, version, source) in [
      ('decline', 1, false),
      ('decline', 2, true),
      ('withdraw', 1, true),
      ('withdraw', 2, true),
      ('withdraw', 3, true),
      ('withdraw', 2, false),
      ('withdraw', 3, false),
      ('reject', 1, false),
      ('reject', 2, false),
      ('reject', 3, false),
    ]) {
      test(
        '$kind v$version ${source ? 'source' : 'recipient/manager'} retains history, kind binding and claim-free replay',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f);
          await x.prepare(version);
          final route = kind == 'reject'
              ? '${swapManage(x.id)}/reject'
              : '$swapSelf/${x.id}/$kind';
          final token = kind == 'reject'
              ? f.adminToken!
              : source
              ? x.a
              : x.b;
          final body = {
            'operationId': newUuid(),
            'expectedVersion': version,
            if (kind != 'decline') 'reason': '  Explicit closure 😀  ',
          };
          final result = await swapCall(
            f,
            'POST',
            route,
            token: token,
            body: body,
          );
          final resolved = kind == 'reject'
              ? 'manager_reject'
              : kind == 'withdraw'
              ? source
                    ? 'source_withdraw'
                    : 'recipient_withdraw'
              : kind;
          expect(result['kind'], resolved);
          expect(result['acceptedVersion'], version + 1);
          expect(result['request']['legs'], hasLength(version == 1 ? 1 : 2));
          expectSwapReceipt(result);
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
            )).single.first,
            0,
          );
          // A new active request owns the released original; old retries cannot steal it.
          final nextBody = {
            ...x.requestBody,
            'requestId': newUuid(),
            'operationId': newUuid(),
          };
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            body: nextBody,
            expected: 201,
          );
          final before = await x.s.hash();
          expect(await swapCall(f, 'POST', route, token: token, body: body), {
            ...result,
            'replayed': true,
          });
          await swapCall(
            f,
            'POST',
            route,
            token: token,
            body: {
              ...body,
              if (kind != 'decline') 'reason': 'Changed payload',
              if (kind == 'decline') 'expectedVersion': version == 1 ? 2 : 1,
            },
            expected: kind == 'decline' ? 404 : 409,
            code: kind == 'decline' ? 'not_found' : 'operation_conflict',
          );
          expect(await x.s.hash(), before);
          final history = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/history',
            token: x.a,
          );
          for (final receipt in history['items'] as List) {
            expectSwapReceipt(Map<String, dynamic>.from(receipt as Map));
          }
        }),
      );
    }
    test(
      'both incoming employees perform ordinary exact work, then historical approval replays',
      () => withMerchandisingFixture((f) async {
        final now =
            (await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime;
        final start = now.add(const Duration(seconds: 10));
        final x = await httpSwapFixture(f, starts: start);
        await x.prepare(3);
        final approved = await x.approve();
        while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime)
            .isBefore(start)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        for (final leg in approved['request']['legs'] as List) {
          final token = leg['leg'] == 'a' ? x.b : x.a;
          final oldToken = leg['leg'] == 'a' ? x.a : x.b;
          final task = leg['taskLinks'][0]['replacementTaskId'];
          final root =
              "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task";
          await swapCall(
            f,
            'GET',
            root,
            token: oldToken,
            expected: 404,
            code: 'not_found',
          );
          await swapCall(
            f,
            'POST',
            '$root/start',
            token: token,
            body: {'operationId': newUuid(), 'expectedVersion': 1},
          );
          final detail = await swapCall(f, 'GET', root, token: token);
          final step = detail['content']['steps'][0]['id'];
          await swapCall(
            f,
            'POST',
            '$root/steps/$step/confirm',
            token: token,
            body: {'operationId': newUuid(), 'expectedVersion': 2},
          );
          await swapCall(
            f,
            'POST',
            '$root/complete',
            token: token,
            body: {'operationId': newUuid(), 'expectedVersion': 3},
          );
          expect(
            (await swapCall(f, 'GET', root, token: token))['status'],
            'completed',
          );
        }
        final before = await x.s.hash();
        expect(await x.approve(), {...approved, 'replayed': true});
        expect(await x.s.hash(), before);
      }),
      timeout: const Timeout(Duration(seconds: 40)),
    );
    test(
      'operation UUID binds request, exact command kind and counterpart version',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.request();
        final before = await x.s.hash();
        for (final patch in [
          {'requestId': newUuid()},
          {'expectedSourceVersion': 1},
          {'recipientEmployeeId': x.s.a.employee},
        ]) {
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.a,
            body: {...x.requestBody, ...patch},
            expected: 409,
            code: 'operation_conflict',
          );
        }
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/confirm',
          token: x.a,
          body: x.confirmBody,
          expected: 409,
          code: 'swap_conflict',
        );
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/offer',
          token: x.b,
          body: {...x.offerBody, 'expectedCounterpartVersion': 1},
          expected: 409,
          code: 'shift_conflict',
        );
        expect(await x.s.hash(), before);
        await x.offer();
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/confirm',
          token: x.a,
          body: {...x.confirmBody, 'operationId': x.offerBody['operationId']},
          expected: 409,
          code: 'operation_conflict',
        );
      }),
    );
  }, skip: swapHttpSkip);
}
