import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_application_fixture.dart' show b1Shift;
import 'shift_swap_application_guidance_test.dart' show guidedSwap;
import 'shift_swap_http_fixture.dart';
import 'task_knowledge_fixture.dart' show knowledgeRoot;
import 'task_planogram_fixture.dart' show replaceDeployment;

Future<void> _waiter(MerchandisingFixture f, String key) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < const Duration(seconds: 10)) {
    final result = await f.owner.execute(
      Sql.named(
        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
      ),
      parameters: {'key': key},
    );
    if (result.single.first == 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('HTTP command must reach observed PostgreSQL barrier.');
}

Future<void> _crossBoundary(
  MerchandisingFixture f,
  String key,
  DateTime start,
  Future<void> Function() command,
) async {
  final held = Completer<void>(), release = Completer<void>();
  final holder = f.pool.runTx((tx) async {
    await tx.execute(
      Sql.named('SELECT pg_advisory_xact_lock(hashtext(@key))'),
      parameters: {'key': key},
    );
    held.complete();
    await release.future;
  });
  await held.future;
  final response = command();
  try {
    await _waiter(f, key);
    while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
            as DateTime)
        .isBefore(start)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  } finally {
    release.complete();
    await holder;
  }
  await response;
}

void main() {
  group('Stage B2a real HTTP error mapping', () {
    for (final (state, constraint, expected) in [
      ('23503', 'private_scope_fixture', 500),
      ('23505', 'private_unique_fixture', 500),
      ('23514', 'private_integrity_fixture', 500),
      (
        '23514',
        'swap_leg_future',
        500,
      ), // F01 is never a manager error mapping.
      ('23514', 'swap_leg_future_suffix', 500),
      ('42P01', 'private_missing_relation_fixture', 500),
      ('08006', 'private_connection_fixture', 503),
      ('42501', 'private_privilege_fixture', 503),
      ('55P03', 'private_lock_fixture', 503),
      ('57014', 'private_timeout_fixture', 503),
      ('57P01', 'private_shutdown_fixture', 503),
      ('53300', 'private_capacity_fixture', 503),
    ]) {
      test(
        '$state/$constraint returns $expected after attempted approval effects and preserves exact reusable UUID',
        () => withMerchandisingFixture((f) async {
          final x = await httpSwapFixture(f);
          await x.prepare(3);
          final before = await x.s.hash();
          await f.owner.execute(
            '''CREATE FUNCTION ${f.schema}.http_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$
            BEGIN IF NEW.kind='manager_approve' THEN
              RAISE EXCEPTION 'Private SQL fixture detail' USING ERRCODE='$state', CONSTRAINT='$constraint';
            END IF; RETURN NEW; END \$\$''',
          );
          await f.owner.execute(
            'CREATE TRIGGER http_fault BEFORE INSERT ON ${f.schema}.workforce_shift_swap_commands FOR EACH ROW EXECUTE FUNCTION ${f.schema}.http_fault()',
          );
          final error = await swapCall(
            f,
            'POST',
            '${swapManage(x.id)}/approve',
            body: x.approvalBody,
            expected: expected,
            code: expected == 503 ? 'database_unavailable' : 'internal_error',
          );
          expect(error['message'], 'Swap database operation failed.');
          expect(await x.s.hash(), before);
          expect(
            (await swapCall(f, 'GET', swapManage(x.id)))['request']['status'],
            'confirmed',
          );
          await f.owner.execute(
            'DROP TRIGGER http_fault ON ${f.schema}.workforce_shift_swap_commands',
          );
          expect((await x.approve())['request']['status'], 'approved');
        }),
      );
    }
    for (final offer in [false, true]) {
      for (final corrupt in [false, true]) {
        test(
          'real late ${offer ? 'offer' : 'request'} capture ${corrupt ? 'integrity defect remains 500' : 'exact F01 maps 422'} with full rollback',
          () => withMerchandisingFixture((f) async {
            final now =
                (await f.owner.execute('SELECT clock_timestamp()')).single.first
                    as DateTime;
            final start = now.add(const Duration(seconds: 12));
            final x = await httpSwapFixture(
              f,
              starts: offer ? start.add(const Duration(hours: 2)) : start,
            );
            if (offer) {
              await f.call(
                'POST',
                '/shifts/${x.s.shiftB}/cancel',
                body: {
                  'expectedVersion': 2,
                  'reason': 'Separate late B fixture',
                },
              );
              final a = await x.s.tx(
                (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
              );
              x.offerBody['counterpartShiftId'] = await b1Shift(
                f,
                x.s.b.employee,
                start,
                a.draft.selections,
              );
              await x.request();
            }
            final key = '${f.schema}:http_capture';
            await f.owner.execute(
              '''CREATE FUNCTION ${f.schema}.http_capture() RETURNS trigger LANGUAGE plpgsql AS \$\$
              BEGIN IF NEW.leg='${offer ? 'b' : 'a'}' THEN
                ${corrupt ? 'NEW.source_version := NEW.source_version+1;' : ''}
                PERFORM pg_advisory_xact_lock(hashtext('$key'));
              END IF; RETURN NEW; END \$\$''',
            );
            await f.owner.execute(
              'CREATE TRIGGER a_http_capture BEFORE INSERT ON ${f.schema}.workforce_shift_swap_legs FOR EACH ROW EXECUTE FUNCTION ${f.schema}.http_capture()',
            );
            final before = await x.s.hash();
            await _crossBoundary(f, key, start, () async {
              final error = await swapCall(
                f,
                'POST',
                offer ? '$swapSelf/${x.id}/offer' : swapSelf,
                token: offer ? x.b : x.a,
                body: offer ? x.offerBody : x.requestBody,
                expected: corrupt ? 500 : 422,
                code: corrupt ? 'internal_error' : 'shift_not_swappable',
              );
              if (!corrupt) {
                expect(
                  error['message'],
                  'Swap requires future work at leg capture.',
                );
              }
            });
            expect(await x.s.hash(), before);
          }),
          timeout: const Timeout(Duration(seconds: 40)),
        );
      }
    }
    test(
      'approval crosses actual deferred Tasks boundary and HTTP 422 rolls back both replacements, receipts, claims and audit',
      () => withMerchandisingFixture((f) async {
        final now =
            (await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime;
        final start = now.add(const Duration(seconds: 12));
        final x = await httpSwapFixture(f, starts: start);
        await x.prepare(3);
        final key = '${f.schema}:http_deferred';
        final definition =
            (await f.owner.execute(
                  "SELECT pg_get_functiondef('${f.schema}.tasks_swap_approval_complete(uuid,uuid)'::regprocedure)",
                )).single.first
                as String;
        await f.owner.execute(
          definition.replaceFirst(
            'BEGIN',
            "BEGIN PERFORM pg_advisory_xact_lock(hashtext('$key'));",
          ),
        );
        final before = await x.s.hash();
        await _crossBoundary(f, key, start, () async {
          await swapCall(
            f,
            'POST',
            '${swapManage(x.id)}/approve',
            body: x.approvalBody,
            expected: 422,
            code: 'shift_not_swappable',
          );
        });
        expect(await x.s.hash(), before);
      }),
      timeout: const Timeout(Duration(seconds: 40)),
    );
    for (final pin in ['knowledge', 'planogram']) {
      test(
        '$pin invalidation returns actual guidance eligibility HTTP 422 with stale detail and explicit rejection',
        () => withMerchandisingFixture((f) async {
          final (internal, g) = await guidedSwap(f);
          final x = HttpSwapFixture(internal.s);
          await x.prepare(3);
          if (pin == 'knowledge') {
            await f.call(
              'POST',
              '$knowledgeRoot/${g.knowledge!.article.id}/retire',
              body: {'expectedVersion': 2},
            );
          } else {
            await replaceDeployment(f, g.deployment);
          }
          final before = await x.s.hash();
          final code = pin == 'knowledge'
              ? 'guidance_unavailable'
              : 'planogram_guidance_unavailable';
          await swapCall(
            f,
            'POST',
            '${swapManage(x.id)}/approve',
            body: x.approvalBody,
            expected: 422,
            code: code,
          );
          expect(await x.s.hash(), before);
          final detail = await swapCall(
            f,
            'GET',
            '$swapSelf/${x.id}',
            token: x.a,
          );
          expect(detail['nonActionableReason'], code);
          expect(detail['availableActions'], ['source_withdraw']);
          await swapCall(
            f,
            'POST',
            '${swapManage(x.id)}/reject',
            body: {
              'operationId': newUuid(),
              'expectedVersion': 3,
              'reason': 'Unavailable pin',
            },
          );
        }),
      );
    }
    test(
      'shared claim conflict, stale Shift version and final third-Shift overlap return bounded HTTP 409',
      () => withMerchandisingFixture((f) async {
        final x = await httpSwapFixture(f);
        await x.request();
        final before = await x.s.hash();
        await swapCall(
          f,
          'POST',
          swapSelf,
          token: x.a,
          body: {
            ...x.requestBody,
            'requestId': newUuid(),
            'operationId': newUuid(),
          },
          expected: 409,
          code: 'swap_already_pending',
        );
        expect(await x.s.hash(), before);
        final source = await x.s.tx(
          (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
        );
        await f.call(
          'POST',
          '/shifts/${x.s.shiftB}/amend',
          body: {
            'expectedVersion': 2,
            'startsAt': source.draft.startsAt
                .add(const Duration(hours: 3))
                .toIso8601String(),
            'endsAt': source.draft.endsAt
                .add(const Duration(hours: 3))
                .toIso8601String(),
          },
        );
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/offer',
          token: x.b,
          body: x.offerBody,
          expected: 409,
          code: 'shift_conflict',
        );
        x.offerBody['expectedCounterpartVersion'] = 3;
        await x.offer();
        await x.confirm();
        await b1Shift(
          f,
          x.s.b.employee,
          source.draft.startsAt,
          source.draft.selections,
        );
        final overlapBefore = await x.s.hash();
        await swapCall(
          f,
          'POST',
          '${swapManage(x.id)}/approve',
          body: x.approvalBody,
          expected: 409,
          code: 'shift_overlap',
        );
        expect(await x.s.hash(), overlapBefore);
        await swapCall(
          f,
          'POST',
          '$swapSelf/${x.id}/withdraw',
          token: x.a,
          body: {
            'operationId': newUuid(),
            'expectedVersion': 3,
            'reason': 'Close overlapping final roster',
          },
        );
      }),
    );
  }, skip: swapHttpSkip);
}
