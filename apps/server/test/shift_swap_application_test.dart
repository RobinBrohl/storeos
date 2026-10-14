import 'dart:convert';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';
import 'shift_swap_application_fixture.dart';

Matcher failure(int status, [String? code]) => isA<PlatformFailure>()
    .having((e) => e.status, 'status', status)
    .having((e) => e.code, 'code', code ?? anything);

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  group('Stage B1 restricted Application', () {
    test(
      'progression requires exact stage and request receipt UUID binds target/version/payload',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        final accepted = await x.request();
        final before = await x.s.hash();
        await expectLater(
          x.app.command(x.a, x.id, 'confirm', {
            'operationId': newUuid(),
            'expectedVersion': 2,
          }),
          throwsA(failure(409, 'swap_conflict')),
        );
        await expectLater(x.approve(), throwsA(failure(409, 'swap_conflict')));
        for (final patch in [
          {'requestId': newUuid()},
          {'expectedSourceVersion': 1},
          {'recipientEmployeeId': x.s.a.employee},
        ]) {
          await expectLater(
            x.app.command(x.a, null, 'request', {
              ...x.requested.toJson(),
              ...patch,
            }),
            throwsA(failure(409, 'operation_conflict')),
          );
        }
        expect(await x.s.hash(), before);
        final closed = await x.app.command(x.a, x.id, 'source_withdraw', {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'reason': 'Retain original evidence',
        });
        final original = x.requested;
        await x.request();
        final current = await x.s.hash();
        expect(
          (await x.app.command(
            x.a,
            null,
            'request',
            original.toJson(),
          )).toJson(),
          {...accepted.toJson(), 'replayed': true},
        );
        expect(await x.s.hash(), current);
        expect(
          closed.request.json['terminalReason'],
          'Retain original evidence',
        );
      }),
    );
    test(
      'observed two B offers to distinct invitations acquire one B; losing A invitation persists',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f), c = await batchWorker(f, 'third_inviter');
        final shift = await x.s.tx(
          (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
        );
        final cShift = await b1Shift(
          f,
          c.employee,
          shift.draft.startsAt,
          shift.draft.selections,
        );
        final principal = await f.auth.authenticate(c.token);
        await x.request();
        final second = {
          'requestId': newUuid(),
          'operationId': newUuid(),
          'sourceShiftId': cShift,
          'expectedSourceVersion': 2,
          'recipientEmployeeId': x.s.b.employee,
        };
        await x.app.command(principal, null, 'request', second);
        Future<String> offer(String request) async {
          try {
            await x.app.command(x.b, request, 'offer', {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'counterpartShiftId': x.s.shiftB,
              'expectedCounterpartVersion': 2,
            });
            return 'offered';
          } on PlatformFailure catch (e) {
            return e.code;
          }
        }

        expect(
          await observedWriters(
            f,
            () => offer(x.id),
            () => offer(second['requestId'] as String),
          ),
          ['offered', 'swap_already_pending'],
        );
        expect(
          (await x.app.detail(
            principal,
            second['requestId'] as String,
          )).json['request']['status'],
          'requested',
        );
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
          )).single.first,
          3,
        );
      }),
    );
    for (final count in [1, 10]) {
      test(
        'real equal-interval exchange, $count ordered Tasks per leg, exact historical replay',
        () => withMerchandisingFixture((f) async {
          final x = await b1Fixture(f, tasks: count);
          expect(
            (await f.pool.runTx(
              (tx) => tx.execute('SELECT current_user'),
            )).single.first,
            f.runtimeUser,
          );
          final request = await x.request();
          expect(request.json['statusCode'], 201);
          expect(
            (await x.app.colleagues(x.a, x.s.shiftA)).json['items'],
            contains(
              equals({
                'employeeId': x.s.b.employee,
                'displayName': 'swap_fixture_b',
              }),
            ),
          );
          expect(
            (await x.app.counterparts(x.b, x.id)).json['items'],
            hasLength(1),
          );
          expect(
            (await x.app.counterpart(x.b, x.id, x.s.shiftB)).json['tasks'],
            hasLength(count),
          );
          final offer = await x.offer(), confirmation = await x.confirm();
          expect(offer.request.json['version'], 2);
          expect(confirmation.request.json['version'], 3);
          final body = x.approval(), approved = await x.approve(body: body);
          expect(approved.request.json['status'], 'approved');
          expect(approved.request.json['version'], 4);
          for (final leg in approved.request.json['legs'] as List) {
            expect(leg['tasks'], hasLength(count));
            expect(leg['taskLinks'], hasLength(count));
            final replacement = await x.s.tx(
              (tx, actor) =>
                  x.s.workforce.get(tx, leg['replacementShiftId'] as String),
            );
            expect(replacement.status, 'published');
            expect(replacement.draft.employeeId, leg['incomingEmployeeId']);
            for (final link in leg['taskLinks'] as List) {
              final a = await x.s.tx(
                (tx, actor) => x.s.tasks.detail(
                  tx,
                  leg['sourceShiftId'] as String,
                  link['sourceTaskId'] as String,
                ),
              );
              final b = await x.s.tx(
                (tx, actor) => x.s.tasks.detail(
                  tx,
                  leg['replacementShiftId'] as String,
                  link['replacementTaskId'] as String,
                ),
              );
              expect(b.content!.toJson(), a.content!.toJson());
              expect(a.status, 'cancelled');
            }
          }
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
            )).single.first,
            0,
          );
          final before = await x.s.hash();
          for (final pair in [
            (x.a, x.requested, request),
            (x.b, x.offered, offer),
            (x.a, x.confirmed, confirmation),
          ]) {
            final replay = await x.app.command(
              pair.$1,
              pair.$2.kind == 'request' ? null : x.id,
              pair.$2.kind,
              pair.$2.toJson(),
            );
            expect(replay.toJson(), {...pair.$3.toJson(), 'replayed': true});
          }
          expect((await x.approve(body: body)).toJson(), {
            ...approved.toJson(),
            'replayed': true,
          });
          expect(await x.s.hash(), before);
          expect(await x.app.history(x.a, x.id), hasLength(4));
          expect(
            (await x.app.list(x.a, direction: 'outgoing')).json['items'],
            hasLength(1),
          );
          expect(
            (await x.app.list(x.b, direction: 'incoming')).json['items'],
            hasLength(1),
          );
          expect(
            (await x.app.detail(x.b, x.id)).json['availableActions'],
            isEmpty,
          );
          final audit = (await f.owner.execute(
            "SELECT changes FROM ${f.schema}.audit_entries WHERE action='workforce.swap.approved'",
          )).single.first;
          expect(jsonEncode(audit), isNot(contains('swap_fixture')));
          expect(jsonEncode(audit), isNot(contains('startsAt')));
        }),
      );
    }
    for (final path in [
      ('decline', 1, false),
      ('decline', 2, true),
      ('source_withdraw', 1, true),
      ('source_withdraw', 2, true),
      ('source_withdraw', 3, true),
      ('recipient_withdraw', 2, false),
      ('recipient_withdraw', 3, false),
      ('manager_reject', 1, false),
      ('manager_reject', 2, false),
      ('manager_reject', 3, false),
    ]) {
      test(
        '${path.$1} from version ${path.$2}, retained evidence and released replay',
        () => withMerchandisingFixture((f) async {
          final x = await b1Fixture(f);
          await x.prepare(path.$2);
          final manager = path.$1 == 'manager_reject',
              who = manager
                  ? f.adminPrincipal
                  : path.$3
                  ? x.a
                  : x.b;
          final body = {
            'operationId': newUuid(),
            'expectedVersion': path.$2,
            if (path.$1 != 'decline') 'reason': 'Explicit protected closure',
          };
          final accepted = await x.app.command(
            who,
            x.id,
            path.$1,
            body,
            self: !manager,
          );
          expect(accepted.request.json['version'], path.$2 + 1);
          expect(
            accepted.request.json['offerOperationId'],
            path.$2 >= 2 ? x.offered.operationId : null,
          );
          expect(
            accepted.request.json['confirmationOperationId'],
            path.$2 >= 3 ? x.confirmed.operationId : null,
          );
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
            )).single.first,
            0,
          );
          expect(
            (await x.s.tx(
              (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
            )).status,
            'published',
          );
          final before = await x.s.hash();
          expect(
            (await x.app.command(
              who,
              x.id,
              path.$1,
              body,
              self: !manager,
            )).toJson(),
            {...accepted.toJson(), 'replayed': true},
          );
          expect(await x.s.hash(), before);
        }),
      );
    }
    test(
      'current scope and participant checks precede replay; strict intents and UUID conflicts',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f),
            outsider = await batchWorker(f, 'unrelated');
        final other = await f.auth.authenticate(outsider.token);
        await x.prepare(3);
        final before = await x.s.hash();
        await expectLater(x.app.detail(other, x.id), throwsA(failure(404)));
        await expectLater(x.app.history(other, x.id), throwsA(failure(404)));
        await expectLater(x.app.counterparts(x.a, x.id), throwsA(failure(404)));
        await expectLater(
          x.app.command(other, x.id, 'confirm', x.confirmed.toJson()),
          throwsA(failure(404)),
        );
        await expectLater(
          x.app.command(x.a, x.id, 'confirm', {
            ...x.confirmed.toJson(),
            'snapshot': <String, dynamic>{},
          }),
          throwsA(failure(400)),
        );
        await expectLater(
          x.app.command(x.a, x.id, 'confirm', {
            ...x.confirmed.toJson(),
            'operationId': x.offered.operationId,
          }),
          throwsA(failure(409, 'operation_conflict')),
        );
        await expectLater(
          x.app.command(x.b, x.id, 'recipient_withdraw', {
            'operationId': x.offered.operationId,
            'expectedVersion': 3,
            'reason': 'changed intent',
          }),
          throwsA(failure(409, 'operation_conflict')),
        );
        await expectLater(
          x.app.command(x.a, x.id, 'source_withdraw', {
            'operationId': newUuid(),
            'expectedVersion': 2,
            'reason': 'stale version',
          }),
          throwsA(failure(409, 'swap_conflict')),
        );
        await expectLater(
          x.app.command(
            x.a,
            x.id,
            'manager_approve',
            x.approval(),
            self: false,
          ),
          throwsA(failure(403)),
        );
        await expectLater(
          x.app.detail(
            f.adminPrincipal,
            x.id,
            self: false,
            location: newUuid(),
          ),
          throwsA(failure(403)),
        );
        final foreign = SessionPrincipal(
          id: x.a.id,
          companyId: newUuid(),
          locationId: merchandisingTestLocation,
          username: x.a.username,
        );
        await expectLater(x.app.detail(foreign, x.id), throwsA(failure(403)));
        expect(await x.s.hash(), before);
        for (final role in ['viewer', 'auditor']) {
          final username = await f.account('denied_$role', role: role),
              p = await f.auth.authenticate(await f.login(username));
          await expectLater(
            x.app.detail(p, x.id, self: false),
            throwsA(failure(403)),
          );
          await expectLater(x.app.detail(p, x.id), throwsA(failure(403)));
        }
      }),
    );
    test(
      'B cannot select peer work; failed offer retains original invitation and consumes no UUID',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        await x.request();
        final before = await x.s.hash();
        final body = {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'counterpartShiftId': x.s.shiftA,
          'expectedCounterpartVersion': 2,
        };
        await expectLater(
          x.app.command(x.b, x.id, 'offer', body),
          throwsA(failure(404)),
        );
        expect(await x.s.hash(), before);
        await expectLater(
          x.app.command(x.b, x.id, 'offer', {
            ...body,
            'counterpartShiftId': x.s.shiftB,
            'expectedCounterpartVersion': 1,
          }),
          throwsA(failure(409, 'shift_conflict')),
        );
        expect(await x.s.hash(), before);
        await x.app.command(x.b, x.id, 'offer', {
          ...body,
          'counterpartShiftId': x.s.shiftB,
        });
        await expectLater(
          x.app.command(x.a, x.id, 'confirm', {
            'operationId': body['operationId'],
            'expectedVersion': 2,
          }),
          throwsA(failure(409, 'operation_conflict')),
        );
      }),
    );
    test(
      'independent manager Account enforced even for participant with admin rights',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        await f.call(
          'POST',
          '/users/${x.s.a.account}',
          body: {'expectedVersion': 1, 'role': 'admin', 'isActive': true},
        );
        final a = await f.auth.authenticate(await f.login('swap_fixture_a'));
        final y = B1SwapFixture(x.s, a, x.b);
        await y.prepare(3);
        final before = await x.s.hash();
        await expectLater(
          y.app.command(a, y.id, 'manager_approve', y.approval(), self: false),
          throwsA(failure(403)),
        );
        expect(
          (await y.app.detail(a, y.id, self: false)).json['availableActions'],
          ['manager_reject'],
        );
        expect(await x.s.hash(), before);
        await y.approve();
      }),
    );
    test(
      'stale amended leg changes actionability only; explicit source closure still works',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        await x.prepare(3);
        final s = await x.s.tx(
          (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
        );
        await f.call(
          'POST',
          '/shifts/${s.id}/amend',
          body: {
            'expectedVersion': 2,
            'startsAt': s.draft.startsAt
                .add(const Duration(minutes: 5))
                .toIso8601String(),
            'endsAt': s.draft.endsAt
                .add(const Duration(minutes: 5))
                .toIso8601String(),
          },
        );
        final before = await x.s.hash(), detail = await x.app.detail(x.a, x.id);
        expect(detail.json['actionable'], false);
        expect(detail.json['availableActions'], ['source_withdraw']);
        await expectLater(x.approve(), throwsA(failure(409, 'shift_conflict')));
        expect(await x.s.hash(), before);
        await x.app.command(x.a, x.id, 'source_withdraw', {
          'operationId': newUuid(),
          'expectedVersion': 3,
          'reason': 'Close stale work',
        });
      }),
    );
    test(
      'third Shift rejects final exchange although neither original schedule overlaps',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f),
            s = await x.s.tx((tx, actor) => x.s.workforce.get(tx, x.s.shiftA));
        // Move B's original away before capture, leaving B's A-time interval free.
        await f.call(
          'POST',
          '/shifts/${x.s.shiftB}/amend',
          body: {
            'expectedVersion': 2,
            'startsAt': s.draft.startsAt
                .add(const Duration(hours: 3))
                .toIso8601String(),
            'endsAt': s.draft.endsAt
                .add(const Duration(hours: 3))
                .toIso8601String(),
          },
        );
        await x.request();
        final offer = {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'counterpartShiftId': x.s.shiftB,
          'expectedCounterpartVersion': 3,
        };
        await x.app.command(x.b, x.id, 'offer', offer);
        await x.confirm();
        await b1Shift(f, x.s.b.employee, s.draft.startsAt, s.draft.selections);
        final before = await x.s.hash();
        await expectLater(x.approve(), throwsA(failure(409, 'shift_overlap')));
        expect(await x.s.hash(), before);
      }),
    );
    test(
      'intersecting departing intervals and half-open adjacent third Shift are valid',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f),
            s = await x.s.tx((tx, actor) => x.s.workforce.get(tx, x.s.shiftB));
        await f.call(
          'POST',
          '/shifts/${s.id}/amend',
          body: {
            'expectedVersion': 2,
            'startsAt': s.draft.startsAt
                .add(const Duration(minutes: 30))
                .toIso8601String(),
            'endsAt': s.draft.endsAt
                .add(const Duration(minutes: 30))
                .toIso8601String(),
          },
        );
        await b1Shift(
          f,
          x.s.a.employee,
          s.draft.endsAt.add(const Duration(minutes: 30)),
          s.draft.selections,
        );
        await x.request();
        await x.app.command(x.b, x.id, 'offer', {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'counterpartShiftId': s.id,
          'expectedCounterpartVersion': 3,
        });
        await x.confirm();
        await x.approve();
      }),
    );
    for (final firstSwap in [true, false]) {
      for (final legB in [true, false]) {
        test(
          'observed P4.11 versus swap ${legB ? 'offer B' : 'request A'} ${firstSwap ? 'swap' : 'transfer'} first',
          () => withMerchandisingFixture((f) async {
            final x = await b1Fixture(f),
                recipient = await batchWorker(f, 'one_way_recipient');
            if (legB) await x.request();
            Future<String> swap() async {
              try {
                if (legB) {
                  await x.offer();
                } else {
                  await x.request();
                }
                return 'swap';
              } on PlatformFailure catch (e) {
                return e.code;
              }
            }

            Future<String> transfer() async {
              final r = await f.call(
                'POST',
                '/me/shift-transfers',
                token: legB ? x.s.b.token : x.s.a.token,
                expected: null,
                body: {
                  'operationId': newUuid(),
                  'requestId': newUuid(),
                  'sourceShiftId': legB ? x.s.shiftB : x.s.shiftA,
                  'expectedSourceVersion': 2,
                  'recipientEmployeeId': recipient.employee,
                },
              );
              return r.status == 201 ? 'transfer' : r.body['code'] as String;
            }

            expect(
              await observedWriters(
                f,
                firstSwap ? swap : transfer,
                firstSwap ? transfer : swap,
              ),
              firstSwap
                  ? ['swap', 'transfer_already_pending']
                  : ['transfer', 'swap_already_pending'],
            );
            if (legB && !firstSwap) {
              expect(
                (await x.app.detail(x.a, x.id)).json['request']['status'],
                'requested',
              );
            }
          }),
        );
      }
    }
    test(
      'observed swap/swap race has one winner; opposite invitations retain their own A claims',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        Future<String> request() async {
          try {
            await x.app.command(
              x.a,
              null,
              'request',
              x.s.requestCommand().toJson(),
            );
            return 'winner';
          } on PlatformFailure catch (e) {
            return e.code;
          }
        }

        expect(await observedWriters(f, request, request), [
          'winner',
          'swap_already_pending',
        ]);
        // Close the winner and create both explicit opposite invitations.
        final rows = (await x.app.list(x.a)).json['items'] as List;
        await x.app
            .command(x.a, rows.single['id'] as String, 'source_withdraw', {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'reason': 'New explicit invitations',
            });
        await x.request();
        final opposite = {
          'operationId': newUuid(),
          'requestId': newUuid(),
          'sourceShiftId': x.s.shiftB,
          'expectedSourceVersion': 2,
          'recipientEmployeeId': x.s.a.employee,
        };
        await x.app.command(x.b, null, 'request', opposite);
        final before = await x.s.hash();
        await expectLater(
          x.offer(),
          throwsA(failure(409, 'swap_already_pending')),
        );
        expect(await x.s.hash(), before);
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
          )).single.first,
          2,
        );
      }),
    );
    test(
      'opaque cursors refuse endpoint/request/filter substitutions',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        await x.request();
        final wrong = base64Url.encode(
          utf8.encode(
            jsonEncode([
              'swaps',
              merchandisingTestCompany,
              merchandisingTestLocation,
              x.s.b.employee,
              null,
              null,
              newUuid(),
            ]),
          ),
        );
        await expectLater(
          x.app.list(x.a, after: wrong),
          throwsA(failure(400, 'invalid_cursor')),
        );
        await expectLater(
          x.app.counterparts(x.b, x.id, after: wrong),
          throwsA(failure(400, 'invalid_cursor')),
        );
        await expectLater(
          x.app.colleagues(x.a, x.s.shiftA, after: wrong),
          throwsA(failure(400, 'invalid_cursor')),
        );
      }),
    );
  }, skip: skip);
}
