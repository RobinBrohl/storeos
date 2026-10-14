import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_application_fixture.dart';
import 'shift_swap_application_test.dart' show failure;

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'Stage B1 final deferred Tasks barrier crosses original start and rolls entire Application approval back',
    () => withMerchandisingFixture((f) async {
      final now =
              (await f.owner.execute('SELECT clock_timestamp()')).single.first
                  as DateTime,
          start = now.add(const Duration(seconds: 10));
      final x = await b1Fixture(f, starts: start);
      await x.prepare(3);
      final before = await x.s.hash(), key = '${f.schema}:b1_clock_barrier';
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
      final rejected = expectLater(
        x.approve(),
        throwsA(failure(422, 'shift_not_swappable')),
      );
      try {
        final timer = Stopwatch()..start();
        while (true) {
          final rows = await f.owner.execute(
            Sql.named(
              "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
            ),
            parameters: {'key': key},
          );
          if (rows.single.first == 1) break;
          if (timer.elapsed > const Duration(seconds: 10)) {
            fail('Application approval must reach observed deferred barrier.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime)
            .isBefore(start)) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      } finally {
        release.complete();
        await holder;
      }
      await rejected;
      expect(await x.s.hash(), before);
    }),
    skip: skip,
    timeout: const Timeout(Duration(seconds: 35)),
  );
  test(
    'Stage B1 approved incoming work executes normally after start; retained receipt replays without fresh guard',
    () => withMerchandisingFixture((f) async {
      final now =
              (await f.owner.execute('SELECT clock_timestamp()')).single.first
                  as DateTime,
          start = now.add(const Duration(seconds: 8));
      final x = await b1Fixture(f, starts: start);
      await x.prepare(3);
      final body = x.approval(), result = await x.approve(body: body);
      while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
              as DateTime)
          .isBefore(start)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      for (final leg in result.request.json['legs'] as List) {
        final token = leg['leg'] == 'a' ? x.s.b.token : x.s.a.token;
        final oldToken = leg['leg'] == 'a' ? x.s.a.token : x.s.b.token;
        final task = leg['taskLinks'][0]['replacementTaskId'];
        await f.call(
          'GET',
          "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task",
          token: oldToken,
          expected: 404,
        );
        await f.call(
          'POST',
          "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task/start",
          token: token,
          body: {'operationId': newUuid(), 'expectedVersion': 1},
        );
        final detail = (await f.call(
          'GET',
          "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task",
          token: token,
        )).body;
        final step = detail['content']['steps'][0]['id'];
        await f.call(
          'POST',
          "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task/steps/$step/confirm",
          token: token,
          body: {'operationId': newUuid(), 'expectedVersion': 2},
        );
        await f.call(
          'POST',
          "/employee-home/shifts/${leg['replacementShiftId']}/tasks/$task/complete",
          token: token,
          body: {'operationId': newUuid(), 'expectedVersion': 3},
        );
      }
      final before = await x.s.hash();
      expect((await x.approve(body: body)).toJson(), {
        ...result.toJson(),
        'replayed': true,
      });
      expect(await x.s.hash(), before);
    }),
    skip: skip,
    timeout: const Timeout(Duration(seconds: 35)),
  );
}
