import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_application_fixture.dart';

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  for (final offer in [false, true]) {
    test(
      'F01 future ${offer ? 'offer' : 'request'} accepts and exactly replays',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        if (offer) await x.request();
        final accepted = offer ? await x.offer() : await x.request();
        final before = await x.s.hash();
        final replay = await x.app.command(
          offer ? x.b : x.a,
          offer ? x.id : null,
          offer ? 'offer' : 'request',
          (offer ? x.offered : x.requested).toJson(),
        );
        expect(replay.toJson(), {...accepted.toJson(), 'replayed': true});
        expect(await x.s.hash(), before);
      }),
      skip: skip,
    );
    for (final defect in [
      'clock',
      'owner',
      'identity',
      'scope',
      'version',
      'interval',
      'tasks',
      'references',
      'claim',
      'receipt',
    ]) {
      for (final expired in defect == 'clock' ? [true] : [false, true]) {
        test(
          'F01 ${offer ? 'offer' : 'request'} $defect expired=$expired',
          () => withMerchandisingFixture((f) async {
            final now =
                (await f.owner.execute('SELECT clock_timestamp()')).single.first
                    as DateTime;
            final start = now.add(
              expired ? const Duration(seconds: 12) : const Duration(days: 2),
            );
            // B alone crosses its start; the persisted A invitation remains future.
            final x = await b1Fixture(
              f,
              starts: offer ? start.add(const Duration(hours: 2)) : start,
            );
            var counterpart = x.s.shiftB;
            if (offer) {
              await f.call(
                'POST',
                '/shifts/${x.s.shiftB}/cancel',
                body: {
                  'expectedVersion': 2,
                  'reason': 'Isolated F01 counterpart fixture',
                },
              );
              final a = await x.s.tx(
                (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
              );
              counterpart = await b1Shift(
                f,
                x.s.b.employee,
                start,
                a.draft.selections,
              );
              await x.request();
            }
            final table = switch (defect) {
              'claim' => 'workforce_shift_handoff_claims',
              'receipt' => 'workforce_shift_swap_commands',
              _ => 'workforce_shift_swap_legs',
            };
            final mutation = switch (defect) {
              'owner' => 'NEW.source_employee_id := NEW.incoming_employee_id;',
              'identity' => "NEW.leg := 'c';",
              'scope' =>
                "NEW.source_shift_id := '${offer ? x.s.shiftA : x.s.shiftB}'; SELECT version,starts_at,ends_at INTO NEW.source_version,NEW.starts_at,NEW.ends_at FROM ${f.schema}.shifts WHERE id=NEW.source_shift_id; NEW.work_references := ${f.schema}.tasks_swap_references(NEW.company_id,NEW.source_shift_id,NEW.location_id);",
              'version' => 'NEW.source_version := NEW.source_version + 1;',
              'interval' => "NEW.ends_at := NEW.ends_at + interval '1 minute';",
              'tasks' =>
                "UPDATE ${f.schema}.task_instances SET version=version+1,status='in_progress',started_at=clock_timestamp(),started_by='${offer ? x.s.b.account : x.s.a.account}' WHERE shift_id=NEW.source_shift_id;",
              'references' =>
                "NEW.work_references := jsonb_set(NEW.work_references, '{0,title}', '\"Incorrect immutable title\"'::jsonb);",
              'claim' => 'NEW.leg := NULL;',
              'receipt' => 'NEW.expected_version := 0;',
              _ => '',
            };
            final key = '${f.schema}:f01_capture';
            await f.owner.execute(
              '''CREATE FUNCTION ${f.schema}.f01_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$
            BEGIN $mutation
              IF current_setting('storeos.f01_raw',true) IS DISTINCT FROM 'yes' THEN
                PERFORM pg_advisory_xact_lock(hashtext('$key'));
              END IF;
              RETURN NEW;
            END \$\$''',
            );
            await f.owner.execute(
              'CREATE TRIGGER a_f01_fault BEFORE INSERT ON ${f.schema}.$table FOR EACH ROW EXECUTE FUNCTION ${f.schema}.f01_fault()',
            );
            final before = await x.s.hash();
            ServerException? raw;
            if (defect != 'clock') {
              raw = await _rawFailure(x, offer, counterpart);
              expect(
                raw.code,
                defect == 'scope' ? (offer ? '23505' : '23503') : '23514',
              );
              expect(raw.constraintName, isNot('swap_leg_future'));
              expect(await x.s.hash(), before);
            }
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
            PlatformFailure? observed;
            final command = () async {
              try {
                if (offer) {
                  await x.offer(counterpart: counterpart);
                } else {
                  await x.request();
                }
              } on PlatformFailure catch (e) {
                observed = e;
              }
            }();
            try {
              await _waiter(f, key);
              if (expired) {
                while (((await f.owner.execute(
                          'SELECT clock_timestamp()',
                        )).single.first
                        as DateTime)
                    .isBefore(start)) {
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                }
              } else {
                expect(
                  ((await f.owner.execute(
                            'SELECT clock_timestamp()',
                          )).single.first
                          as DateTime)
                      .isBefore(start),
                  true,
                );
              }
            } finally {
              release.complete();
              await holder;
            }
            await command;
            expect(
              await x.s.hash(),
              before,
              reason: 'Complete durable rollback precedes response assertions',
            );
            expect(observed, isNotNull);
            expect(observed!.status, defect == 'clock' ? 422 : 500);
            expect(
              observed!.code,
              defect == 'clock' ? 'shift_not_swappable' : 'internal_error',
            );
            expect(
              observed!.message,
              defect == 'clock'
                  ? 'Swap requires future work at leg capture.'
                  : 'Swap database operation failed.',
            );
            if (table == 'workforce_shift_swap_legs' && expired) {
              final late = await _rawFailure(x, offer, counterpart);
              expect(
                late.code,
                defect == 'scope' ? (offer ? '23505' : '23503') : '23514',
              );
              expect(
                late.constraintName,
                defect == 'clock'
                    ? 'swap_leg_future'
                    : isNot('swap_leg_future'),
              );
              if (raw != null) expect(late.constraintName, raw.constraintName);
              raw = late;
              expect(await x.s.hash(), before);
            }
            print(
              'F01 ${offer ? 'offer' : 'request'} $defect expired=$expired: SQLSTATE=${raw!.code}, constraintName=${raw.constraintName}, Application=${observed!.status}/${observed!.code}, transaction=rolled_back',
            );
            await f.owner.execute(
              'DROP TRIGGER a_f01_fault ON ${f.schema}.$table',
            );
            if (!expired) {
              // The same body and UUID must succeed after removing an integrity fault.
              final c = offer ? x.offered : x.requested;
              final accepted = await x.app.command(
                offer ? x.b : x.a,
                offer ? x.id : null,
                offer ? 'offer' : 'request',
                c.toJson(),
              );
              expect(accepted.json['replayed'], false);
            } else if (defect == 'clock') {
              final operation = offer
                  ? x.offered.operationId
                  : x.requested.operationId;
              if (offer) {
                final closed = await x.app.command(x.b, x.id, 'decline', {
                  'operationId': operation,
                  'expectedVersion': 1,
                });
                expect(closed.request.json['status'], 'declined');
                expect(closed.json['replayed'], false);
              } else {
                final source = await x.s.tx(
                  (tx, actor) => x.s.workforce.get(tx, x.s.shiftA),
                );
                final fresh = await b1Shift(
                  f,
                  x.s.a.employee,
                  start.add(const Duration(days: 2)),
                  source.draft.selections,
                );
                final accepted = await x.app.command(x.a, null, 'request', {
                  ...x.requested.toJson(),
                  'requestId': newUuid(),
                  'sourceShiftId': fresh,
                });
                expect(accepted.json['operationId'], operation);
                expect(accepted.request.json['status'], 'requested');
                expect(accepted.json['replayed'], false);
              }
            }
          }),
          skip: skip,
          timeout: const Timeout(Duration(seconds: 40)),
        );
      }
    }
  }
  test(
    'F01 marker outside request/offer remains internal even at deferred completion',
    () => withMerchandisingFixture((f) async {
      final x = await b1Fixture(f);
      await x.request();
      await f.owner.execute(
        "CREATE FUNCTION ${f.schema}.f01_wrong_context() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN RAISE EXCEPTION 'Unrelated injected marker' USING ERRCODE='23514',CONSTRAINT='swap_leg_future'; END \$\$",
      );
      await f.owner.execute(
        'CREATE CONSTRAINT TRIGGER f01_wrong_context AFTER INSERT ON ${f.schema}.workforce_shift_swap_commands DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ${f.schema}.f01_wrong_context()',
      );
      final before = await x.s.hash();
      await expectLater(
        x.app.command(x.b, x.id, 'decline', {
          'operationId': newUuid(),
          'expectedVersion': 1,
        }),
        throwsA(
          isA<PlatformFailure>()
              .having((e) => e.status, 'status', 500)
              .having((e) => e.code, 'code', 'internal_error'),
        ),
      );
      expect(await x.s.hash(), before);
    }),
    skip: skip,
  );
}

Future<ServerException> _rawFailure(
  B1SwapFixture x,
  bool offer,
  String counterpart,
) async {
  try {
    await x.s.tx((tx, actor) async {
      expect(
        (await tx.execute('SELECT current_user')).single.first,
        x.f.runtimeUser,
      );
      await tx.execute("SELECT set_config('storeos.f01_raw','yes',true)");
      final c = offer
          ? ShiftSwapCommandInput.fromJson('offer', {
              'operationId': newUuid(),
              'expectedVersion': 1,
              'counterpartShiftId': counterpart,
              'expectedCounterpartVersion': 2,
            })
          : x.s.requestCommand();
      final id = offer ? x.id : c.payload['requestId'] as String;
      if (!offer) {
        final a = (await x.s.links.forEmployee(tx, x.s.a.employee))!;
        final b = (await x.s.links.forEmployee(tx, x.s.b.employee))!;
        await x.s.swaps.request(
          tx,
          c,
          a,
          b,
          (await x.s.links.swapAccountVersion(tx, a))!,
          (await x.s.links.swapAccountVersion(tx, b))!,
        );
      }
      final s = await x.s.workforce.get(tx, offer ? counterpart : x.s.shiftA);
      await x.s.swaps.captureLeg(
        tx,
        id,
        offer ? 'b' : 'a',
        s,
        offer ? x.s.a.employee : x.s.b.employee,
        await x.s.tasks.captureSwapWork(tx, s),
      );
      if (offer) {
        await x.s.claims.claimSwapB(tx, id);
        await x.s.swaps.transition(tx, id, x.s.b.account, c);
      } else {
        await x.s.claims.claimSwapA(tx, id);
      }
      await x.s.receipt(tx, id, offer ? x.s.b.account : x.s.a.account, c);
    });
  } on ServerException catch (e) {
    return e;
  }
  throw StateError('Expected real PostgreSQL refusal.');
}

Future<void> _waiter(MerchandisingFixture f, String key) async {
  final timer = Stopwatch()..start();
  while (timer.elapsed < const Duration(seconds: 8)) {
    final r = await f.owner.execute(
      Sql.named(
        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
      ),
      parameters: {'key': key},
    );
    if (r.single.first == 1) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Expected observed persistence waiter.');
}
