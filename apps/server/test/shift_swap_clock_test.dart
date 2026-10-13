import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  test(
    'Stage A deferred Tasks barrier crosses original start and rolls paired approval back',
    () => withMerchandisingFixture((f) async {
      final now =
              (await f.owner.execute('SELECT clock_timestamp()')).single.first
                  as DateTime,
          start = now.add(const Duration(seconds: 8));
      final s = await stageAFixture(f, starts: start), id = await s.request();
      await s.offer(id);
      await s.transition(id, 'confirm', 2);
      final before = await s.hash(), key = '${f.schema}:swap_clock_barrier';
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
      final attempted = s.approveIntegrityFixture(id);
      final rejected = expectLater(
        attempted,
        throwsA(
          isA<ServerException>().having(
            (e) => e.constraintName,
            'constraint',
            'swap_approval_future',
          ),
        ),
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
            fail('Deferred Tasks validation must reach the observed barrier.');
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
      expect(await s.hash(), before);
    }),
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );
  test(
    'Stage A approved integrity fixture permits later ordinary execution and retained replay',
    () => withMerchandisingFixture((f) async {
      final now =
              (await f.owner.execute('SELECT clock_timestamp()')).single.first
                  as DateTime,
          start = now.add(const Duration(seconds: 8));
      final s = await stageAFixture(f, starts: start), id = await s.request();
      await s.offer(id);
      await s.transition(id, 'confirm', 2);
      final result = (await s.approveIntegrityFixture(id))!,
          leg = (result.request.json['legs'] as List).first as Map;
      while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
              as DateTime)
          .isBefore(start)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final task = (leg['taskLinks'] as List).first as Map;
      await f.call(
        'POST',
        '/employee-home/shifts/${leg['replacementShiftId']}/tasks/${task['replacementTaskId']}/start',
        token: s.b.token,
        body: {'operationId': newUuid(), 'expectedVersion': 1},
      );
      final before = await s.hash();
      final replay = await s.tx(
        (tx, actor) => s.swaps.replay(
          tx,
          id,
          actor.id,
          ShiftSwapCommandInput.fromJson('manager_approve', {
            'operationId': result.json['operationId'],
            'expectedVersion': 3,
          }),
        ),
      );
      expect(replay!.toJson(), {...result.toJson(), 'replayed': true});
      expect(await s.hash(), before);
    }),
    skip: skip,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
