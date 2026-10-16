import 'dart:convert';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/platform/plugin_service.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_http_fixture.dart';

void main() {
  group('Stage B2a authenticated privacy', () {
    test(
      'guessed foreign resources, unrelated employee, peer counterpart and manager routes reveal no evidence',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f),
            c = await batchWorker(f, 'unrelated');
        await x.prepare(1);
        final before = await x.s.hash();
        for (final id in [x.id, newUuid()]) {
          for (final suffix in [
            '',
            '/history',
            '/counterparts',
            '/counterparts/${x.s.shiftB}',
          ]) {
            final denied = await swapCall(
              f,
              'GET',
              '$swapSelf/$id$suffix',
              token: c.token,
              expected: 404,
              code: 'not_found',
            );
            expect(jsonEncode(denied), isNot(contains(x.id)));
          }
          for (final kind in ['offer', 'confirm', 'decline', 'withdraw']) {
            await swapCall(
              f,
              'POST',
              '$swapSelf/$id/$kind',
              token: c.token,
              body: kind == 'offer'
                  ? x.offerBody
                  : {
                      'operationId': newUuid(),
                      'expectedVersion': 2,
                      if (kind == 'withdraw') 'reason': 'Guessed',
                    },
              expected: 404,
              code: 'not_found',
            );
          }
          for (final suffix in ['', '/history']) {
            await swapCall(
              f,
              'GET',
              '${swapManage(id)}$suffix',
              token: x.a,
              expected: 403,
              code: 'forbidden',
            );
          }
          for (final kind in ['approve', 'reject']) {
            await swapCall(
              f,
              'POST',
              '${swapManage(id)}/$kind',
              token: x.a,
              body: x.approvalBody,
              expected: 403,
              code: 'forbidden',
            );
          }
        }
        for (final token in [x.a, c.token]) {
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/counterparts',
            token: token,
            expected: 404,
            code: 'not_found',
          );
        }
        for (final shift in [x.s.shiftA, newUuid()]) {
          await swapCall(
            f,
            'GET',
            '/employee-home/shifts/$shift/swap-colleagues',
            token: x.b,
            expected: 404,
            code: 'not_found',
          );
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}/counterparts/$shift',
            token: x.b,
            expected: 404,
            code: 'not_found',
          );
          await swapCall(
            f,
            'POST',
            '$swapSelf/${x.id}/offer',
            token: x.b,
            body: {...x.offerBody, 'counterpartShiftId': shift},
            expected: 404,
            code: 'not_found',
          );
          await swapCall(
            f,
            'POST',
            swapSelf,
            token: x.b,
            body: {
              ...x.requestBody,
              'requestId': newUuid(),
              'operationId': newUuid(),
              'sourceShiftId': shift,
            },
            expected: 404,
            code: 'not_found',
          );
        }
        expect(
          (await swapCall(f, 'GET', swapSelf, token: c.token))['items'],
          isEmpty,
        );
        expect(
          (await swapCall(
            f,
            'GET',
            '$swapSelf?direction=incoming',
            token: x.b,
          ))['items'],
          hasLength(1),
        );
        expect(await x.s.hash(), before);
        final unknownEmployee = newUuid();
        await swapCall(
          f,
          'POST',
          swapSelf,
          token: x.a,
          body: {
            ...x.requestBody,
            'requestId': newUuid(),
            'operationId': newUuid(),
            'recipientEmployeeId': unknownEmployee,
          },
          expected: 422,
          code: 'employee_unavailable',
        );
        expect(await x.s.hash(), before);
      }),
    );
    test(
      'absent, malformed, expired, revoked and plugin credentials are refused before command parsing',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.request();
        final plugins = PluginService(f.database);
        final registration = await plugins.register(f.adminPrincipal, {
          'manifest': {
            'id': 'swap-denied',
            'name': 'Denied',
            'version': '1.0.0',
            'vendor': 'StoreOS tests',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        });
        final grant = await plugins.approve(f.adminPrincipal, 'swap-denied', {
          'expectedVersion': registration['version'],
          'locationId': merchandisingTestLocation,
          'permissions': ['organization.read'],
          'subscriptions': <String>[],
        });
        final plugin = grant['token'] as String;
        await plugins.organization(plugin);
        await f.call(
          'POST',
          '/api/v1/auth/logout',
          platform: false,
          token: x.b,
          expected: 204,
        );
        // Owner-controlled session clock fixture; business commands still use HTTP.
        await f.owner.execute(
          "UPDATE ${f.schema}.auth_sessions SET created_at=clock_timestamp()-interval '2 seconds', expires_at=clock_timestamp()-interval '1 second' WHERE account_id='${x.s.a.account}'",
        );
        final before = await x.s.hash();
        for (final token in ['', 'malformed', 'a' * 43, x.a, x.b, plugin]) {
          for (final route in [
            swapSelf,
            '$swapSelf/${x.id}',
            '$swapSelf/${x.id}/history',
            '$swapSelf/${x.id}/counterparts',
            swapManage(x.id),
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues',
          ]) {
            await swapCall(
              f,
              'GET',
              route,
              token: token,
              expected: 401,
              code: 'unauthorized',
            );
          }
          for (final route in [
            swapSelf,
            '$swapSelf/${x.id}/offer',
            '$swapSelf/${x.id}/withdraw',
            '${swapManage(x.id)}/approve',
          ]) {
            await swapCall(
              f,
              'POST',
              route,
              token: token,
              raw: '{',
              expected: 401,
              code: 'unauthorized',
            );
          }
        }
        expect(await x.s.hash(), before);
      }),
    );
    test(
      'Viewer and Auditor lack every swap route capability',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.request();
        for (final role in ['viewer', 'auditor']) {
          await f.account('swap_$role', role: role);
          final token = await f.login('swap_$role');
          for (final route in [
            swapSelf,
            '$swapSelf/${x.id}',
            '$swapSelf/${x.id}/history',
            '$swapSelf/${x.id}/counterparts',
            '$swapSelf/${x.id}/counterparts/${x.s.shiftB}',
            '/locations/$merchandisingTestLocation/shift-swaps',
            swapManage(x.id),
            '${swapManage(x.id)}/history',
            '/employee-home/shifts/${x.s.shiftA}/swap-colleagues',
          ]) {
            await swapCall(
              f,
              'GET',
              route,
              token: token,
              expected: 403,
              code: 'forbidden',
            );
          }
          for (final route in [
            swapSelf,
            '$swapSelf/${x.id}/offer',
            '$swapSelf/${x.id}/confirm',
            '$swapSelf/${x.id}/decline',
            '$swapSelf/${x.id}/withdraw',
            '${swapManage(x.id)}/approve',
            '${swapManage(x.id)}/reject',
          ]) {
            await swapCall(
              f,
              'POST',
              route,
              token: token,
              body: route == swapSelf ? x.requestBody : x.offerBody,
              expected: 403,
              code: 'forbidden',
            );
          }
        }
      }),
    );
    for (final source in [true, false]) {
      test(
        '${source ? 'source' : 'recipient'} replaced Account/link cannot inherit consent or old receipts; current source closure remains',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f);
          await x.prepare(3);
          final worker = source ? x.s.a : x.s.b;
          final link =
              (await f.call(
                    'GET',
                    '/employees/${worker.employee}/account-link',
                  )).body['link']
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
              'username': 'replacement',
              'password': merchandisingTestPassword,
              'locationId': merchandisingTestLocation,
              'role': 'employee',
            },
          );
          await f.call(
            'POST',
            '/employees/${worker.employee}/account-link',
            expected: 201,
            body: {
              'id': newUuid(),
              'accountId': account,
              'expectedEmployeeVersion': 1,
              'expectedAccountVersion': 1,
            },
          );
          final token = await f.login('replacement');
          final before = await x.s.hash();
          if (source) {
            await swapCall(
              f,
              'POST',
              swapSelf,
              token: token,
              body: x.requestBody,
              expected: 409,
              code: 'operation_conflict',
            );
          }
          await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}',
            token: worker.token,
            expected: 401,
            code: 'unauthorized',
          );
          await swapCall(
            f,
            'POST',
            '$swapSelf/${x.id}/${source ? 'confirm' : 'offer'}',
            token: token,
            body: source ? x.confirmBody : x.offerBody,
            expected: 404,
            code: 'not_found',
          );
          await swapCall(
            f,
            'POST',
            '${swapManage(x.id)}/approve',
            body: x.approvalBody,
            expected: 422,
            code: 'employee_unavailable',
          );
          expect(await x.s.hash(), before);
          final close = {
            'operationId': newUuid(),
            'expectedVersion': 3,
            'reason': 'Close changed identity',
          };
          if (source) {
            final accepted = await swapCall(
              f,
              'POST',
              '$swapSelf/${x.id}/withdraw',
              token: token,
              body: close,
            );
            expect(accepted['kind'], 'source_withdraw');
            expect(
              await swapCall(
                f,
                'POST',
                '$swapSelf/${x.id}/withdraw',
                token: token,
                body: close,
              ),
              {...accepted, 'replayed': true},
            );
          } else {
            await swapCall(
              f,
              'POST',
              '$swapSelf/${x.id}/withdraw',
              token: token,
              body: close,
              expected: 404,
              code: 'not_found',
            );
            expect(await x.s.hash(), before);
            await swapCall(
              f,
              'POST',
              '${swapManage(x.id)}/reject',
              body: close,
            );
          }
        }),
      );
    }
    test(
      'Account version ABA blocks progression; participant admin cannot approve own consent',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await f.call(
          'POST',
          '/users/${x.s.a.account}',
          body: {'expectedVersion': 1, 'role': 'admin', 'isActive': true},
        );
        final a = await f.login('swap_fixture_a');
        await swapCall(
          f,
          'POST',
          swapSelf,
          token: a,
          body: x.requestBody,
          expected: 201,
        );
        await x.offer();
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/confirm',
          token: a,
          body: x.confirmBody,
        );
        final before = await x.s.hash();
        await swapCall(
          f,
          'POST',
          '${swapManage(x.id)}/approve',
          token: a,
          body: x.approvalBody,
          expected: 403,
          code: 'forbidden',
        );
        expect(await x.s.hash(), before);
        await f.call(
          'POST',
          '/users/${x.s.b.account}',
          body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
        );
        await f.call(
          'POST',
          '/users/${x.s.b.account}',
          body: {'expectedVersion': 2, 'role': 'employee', 'isActive': true},
        );
        final changed = await x.s.hash();
        await swapCall(
          f,
          'POST',
          '${swapManage(x.id)}/approve',
          body: x.approvalBody,
          expected: 422,
          code: 'employee_unavailable',
        );
        expect(await x.s.hash(), changed);
        final detail = await swapCall(f, 'GET', '$swapSelf/${x.id}', token: a);
        expect(detail['nonActionableReason'], 'employee_unavailable');
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/withdraw',
          token: a,
          body: {
            'operationId': newUuid(),
            'expectedVersion': 3,
            'reason': 'Close stale captured version',
          },
        );
      }),
    );
    test(
      'configured Location and Company fence real foreign resources and sessions',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.prepare(3);
        final otherLocation = await f.createLocation(
          'Other registered location',
        );
        for (final suffix in ['', '/history', '/approve']) {
          await swapCall(
            f,
            suffix == '/approve' ? 'POST' : 'GET',
            '/locations/$otherLocation/shift-swaps/${x.id}$suffix',
            body: suffix == '/approve' ? x.approvalBody : null,
            expected: 403,
            code: 'forbidden',
          );
        }
        final oldAdmin = f.adminToken!;
        await f.call(
          'POST',
          '/users',
          expected: 201,
          body: {
            'id': newUuid(),
            'username': 'other_manager',
            'password': merchandisingTestPassword,
            'locationId': otherLocation,
            'role': 'admin',
          },
        );
        final otherManager = await f.login('other_manager');
        await f.restart(locationId: otherLocation);
        await swapCall(
          f,
          'GET',
          '$swapSelf/${x.id}',
          token: x.a,
          expected: 403,
          code: 'forbidden',
        );
        for (final suffix in ['', '/history?after=bad', '/approve']) {
          await swapCall(
            f,
            suffix == '/approve' ? 'POST' : 'GET',
            '/locations/$otherLocation/shift-swaps/${x.id}$suffix',
            token: otherManager,
            body: suffix == '/approve' ? x.approvalBody : null,
            expected: 404,
            code: 'not_found',
          );
        }
        await swapCall(
          f,
          'GET',
          '/locations/$otherLocation/shift-swaps/${x.id}',
          token: oldAdmin,
          expected: 403,
          code: 'forbidden',
        );
        await f.restart();
        // Each installation has one Company. Use a second genuinely populated
        // isolated installation, preserving that enforced singleton contract.
        final company = newUuid();
        await withMerchandisingFixture((foreign) async {
          final y = await httpSwapFixture(foreign);
          await y.request();
          for (final (target, other, credential) in [
            (f, y, x.a),
            (foreign, x, y.a),
          ]) {
            await swapCall(
              target,
              'GET',
              '$swapSelf/${other.id}',
              token: credential,
              expected: 404,
              code: 'not_found',
            );
            await swapCall(
              target,
              'GET',
              '$swapSelf/${other.id}/history?after=bad',
              token: credential,
              expected: 404,
              code: 'not_found',
            );
            await swapCall(
              target,
              'GET',
              swapManage(other.id),
              expected: 404,
              code: 'not_found',
            );
            await swapCall(
              target,
              'GET',
              '/shifts/${other.s.shiftA}',
              expected: 404,
              code: 'not_found',
            );
            await swapCall(
              target,
              'GET',
              '/employees/${other.s.a.employee}',
              expected: 404,
              code: 'not_found',
            );
            await swapCall(
              target,
              'GET',
              '$swapSelf/${other.id}',
              token: other.a,
              expected: 401,
              code: 'unauthorized',
            );
          }
          await f.restart(companyId: company);
          await swapCall(
            f,
            'GET',
            swapManage(x.id),
            token: oldAdmin,
            expected: 401,
            code: 'unauthorized',
          );
          await f.restart();
        }, homeCompanyId: company);
      }),
    );
  }, skip: swapHttpSkip);
}
