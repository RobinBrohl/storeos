import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/workforce/shift_handoff_claim_service.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

final _skip = merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';
void main() {
  test(
    'Stage A Identity owner port fences Account role ABA and replacement IDs',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f), id = await s.request();
      final link = (await s.tx(
        (tx, actor) => s.links.forEmployee(tx, s.a.employee),
      ))!;
      Future<bool> valid({String? account, String? linkage}) => s.tx(
        (tx, actor) => s.links.matchesSwapIdentityBasis(
          tx,
          employeeId: s.a.employee,
          accountId: account ?? s.a.account,
          linkId: linkage ?? link.id,
          accountVersion: 1,
        ),
      );
      expect(await valid(), true);
      expect(await valid(account: newUuid()), false);
      expect(await valid(linkage: newUuid()), false);
      await f.call(
        'POST',
        '/users/${s.a.account}',
        body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
      );
      expect(await valid(), false);
      await f.call(
        'POST',
        '/users/${s.a.account}',
        body: {'expectedVersion': 2, 'role': 'employee', 'isActive': true},
      );
      expect(await valid(), false);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$id'",
        )).single.first,
        1,
      );
      await s.transition(id, 'manager_reject', 1);
    }),
    skip: _skip,
  );
  test(
    'Stage A exact maximum 20 paired Tasks persists complete ordered lineage',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f, taskCount: 10), id = await s.request();
      await s.offer(id);
      await s.transition(id, 'confirm', 2);
      final result = (await s.approveIntegrityFixture(id))!;
      final legs = result.request.json['legs'] as List;
      expect(legs, hasLength(2));
      for (final leg in legs) {
        expect(leg['tasks'], hasLength(10));
        expect(leg['taskLinks'], hasLength(10));
        expect(
          (leg['taskLinks'] as List).map((x) => x['position']).toList(),
          List.generate(10, (i) => i),
        );
      }
      final rows = await f.owner.execute(
        "SELECT source_task_id,replacement_task_id FROM ${f.schema}.task_swap_links WHERE request_id='$id'",
      );
      expect(rows, hasLength(20));
      expect(rows.map((r) => r[0]).toSet(), hasLength(20));
      expect(rows.map((r) => r[1]).toSet(), hasLength(20));
    }),
    skip: _skip,
  );
  for (final defect in ['missing_link', 'snapshot_mismatch']) {
    test(
      'Stage A deferred Tasks $defect rejects complete-looking paired approval',
      () => withMerchandisingFixture((f) async {
        final s = await stageAFixture(f), id = await s.request();
        await s.offer(id);
        await s.transition(id, 'confirm', 2);
        final before = await s.hash();
        if (defect == 'missing_link') {
          await f.owner.execute(
            "CREATE FUNCTION ${f.schema}.p416_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.leg='b' THEN RETURN NULL; END IF; RETURN NEW; END \$\$",
          );
          await f.owner.execute(
            "CREATE TRIGGER p416_fault BEFORE INSERT ON ${f.schema}.task_swap_links FOR EACH ROW EXECUTE FUNCTION ${f.schema}.p416_fault()",
          );
        } else {
          await f.owner.execute(
            "CREATE FUNCTION ${f.schema}.p416_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN NEW.content:=jsonb_set(NEW.content::jsonb,'{title}','\"Altered frozen content\"'::jsonb)::text; RETURN NEW; END \$\$",
          );
          await f.owner.execute(
            "CREATE TRIGGER p416_fault BEFORE INSERT ON ${f.schema}.task_instances FOR EACH ROW EXECUTE FUNCTION ${f.schema}.p416_fault()",
          );
        }
        final operation = newUuid();
        await expectLater(
          s.approveIntegrityFixture(
            id,
            rawReceipt: true,
            rawTaskMaterialization: true,
            operation: operation,
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.constraintName,
              'constraint',
              'tasks_swap_approval_complete',
            ),
          ),
        );
        expect(await s.hash(), before);
        await f.owner.execute(
          'DROP TRIGGER p416_fault ON ${f.schema}.${defect == 'missing_link' ? 'task_swap_links' : 'task_instances'}',
        );
        await f.owner.execute('DROP FUNCTION ${f.schema}.p416_fault()');
        await s.approveIntegrityFixture(id, operation: operation);
      }),
      skip: _skip,
    );
  }
  test(
    'Stage A new scoped anchors reject cross-Company/Location and orphaned or extra claims',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          id = await s.request(),
          before = await s.hash();
      for (final scope in ['company_id', 'location_id']) {
        final company = scope == 'company_id'
                ? newUuid()
                : merchandisingTestCompany,
            location = scope == 'location_id'
                ? newUuid()
                : merchandisingTestLocation;
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              """INSERT INTO ${f.schema}.workforce_shift_swap_requests
        (company_id,id,location_id,source_employee_id,recipient_employee_id,source_account_id,recipient_account_id,source_link_id,recipient_link_id,source_account_version,recipient_account_version,request_operation_id)
        SELECT '$company','${newUuid()}','$location',source_employee_id,recipient_employee_id,source_account_id,recipient_account_id,source_link_id,recipient_link_id,1,1,'${newUuid()}'
        FROM ${f.schema}.workforce_shift_swap_requests WHERE id='$id'""",
            ),
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23503'),
          ),
        );
      }
      for (final owner in [id, newUuid()]) {
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              "INSERT INTO ${f.schema}.workforce_shift_handoff_claims(company_id,location_id,shift_id,swap_request_id,leg) VALUES('$merchandisingTestCompany','$merchandisingTestLocation','${s.shiftB}','$owner','b')",
            ),
          ),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'code', '23503'),
          ),
        );
      }
      expect(await s.hash(), before);
    }),
    skip: _skip,
  );
  test(
    'Stage A exact SQL receipt rejects injected or missing canonical fields',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          id = await s.request(),
          before = await s.hash();
      for (final payload in [
        "payload-'sourceShiftId'",
        "payload||'{\"actorId\":null}'::jsonb",
        "jsonb_set(payload,'{expectedSourceVersion}','null'::jsonb)",
      ]) {
        await expectLater(
          f.pool.runTx(
            (tx) => tx.execute(
              """INSERT INTO ${f.schema}.workforce_shift_swap_commands
        (company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,payload,result)
        SELECT company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,$payload,result
        FROM ${f.schema}.workforce_shift_swap_commands WHERE request_id='$id'""",
            ),
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.constraintName,
              'constraint',
              'swap_command_intent',
            ),
          ),
        );
      }
      expect(await s.hash(), before);
    }),
    skip: _skip,
  );
  test(
    'Stage A observed competing transfers share one source claim',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          recipient = await batchWorker(f, 'transfer_target');
      Future<String> propose() async {
        final result = await f.call(
          'POST',
          '/me/shift-transfers',
          token: s.a.token,
          expected: null,
          body: {
            'requestId': newUuid(),
            'operationId': newUuid(),
            'sourceShiftId': s.shiftA,
            'expectedSourceVersion': 2,
            'recipientEmployeeId': recipient.employee,
          },
        );
        return result.status == 201 ? 'created' : result.body['code'] as String;
      }

      expect(await observedWriters(f, propose, propose), [
        'created',
        'transfer_already_pending',
      ]);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );
  test(
    'Stage A occupied B transfer rejects offer, and legacy replay retains a later swap claim',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          recipient = await batchWorker(f, 'handoff_target'),
          id = await s.request();
      final body = {
        'requestId': newUuid(),
        'operationId': newUuid(),
        'sourceShiftId': s.shiftB,
        'expectedSourceVersion': 2,
        'recipientEmployeeId': recipient.employee,
      };
      final proposed = (await f.call(
        'POST',
        '/me/shift-transfers',
        token: s.b.token,
        body: body,
        expected: 201,
      )).body;
      final before = await s.hash();
      await expectLater(s.offer(id), throwsA(isA<ShiftHandoffConflict>()));
      expect(await s.hash(), before);
      await f.call(
        'POST',
        '/me/shift-transfers/${body['requestId']}/withdraw',
        token: s.b.token,
        body: {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'reason': 'Explicit closure',
        },
      );
      await s.offer(id);
      final claimed = await s.hash();
      expect(
        (await f.call(
          'POST',
          '/me/shift-transfers',
          token: s.b.token,
          body: body,
          expected: 201,
        )).body,
        {...proposed, 'replayed': true},
      );
      expect(await s.hash(), claimed);
    }),
    skip: _skip,
  );
  test(
    'Stage A exact requested/offered/confirmed/terminal claims and immutable replay',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          c = s.requestCommand(),
          id = await s.request(command: c);
      Future<int> claims() async =>
          (await f.owner.execute(
                "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$id'",
              )).single.first
              as int;
      expect(await claims(), 1);
      final offer = await s.offer(id);
      expect(await claims(), 2);
      await s.transition(id, 'confirm', 2);
      expect(await claims(), 2);
      await s.transition(id, 'recipient_withdraw', 3);
      expect(await claims(), 0);
      final history = await s.hash();
      final replay = await s.tx(
        (tx, actor) => s.swaps.replay(
          tx,
          id,
          s.b.account,
          ShiftSwapCommandInput.fromJson('offer', {
            'operationId': offer.json['operationId'],
            'expectedVersion': 1,
            'counterpartShiftId': s.shiftB,
            'expectedCounterpartVersion': 2,
          }),
        ),
      );
      expect(replay!.toJson(), {...offer.toJson(), 'replayed': true});
      expect(await s.hash(), history);
      final next = await s.request();
      expect(await claims(), 0);
      final occupied = await s.hash();
      await s.tx((tx, actor) => s.swaps.replay(tx, id, s.a.account, c));
      expect(await s.hash(), occupied);
      expect(next, isNot(id));
      await expectLater(
        s.tx((tx, actor) => s.swaps.replay(tx, id, s.b.account, c)),
        throwsA(
          isA<PlatformFailure>().having(
            (e) => e.code,
            'code',
            'operation_conflict',
          ),
        ),
      );
    }),
    skip: _skip,
  );

  for (final state in [1, 2, 3]) {
    for (final kind in [
      'manager_reject',
      'source_withdraw',
      if (state >= 2) 'recipient_withdraw',
      if (state < 3) 'decline',
    ]) {
      test(
        'Stage A stage $state $kind retains evidence and releases exact claims',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f), id = await s.request();
          if (state >= 2) await s.offer(id);
          if (state == 3) await s.transition(id, 'confirm', 2);
          final before = (await f.owner.execute(
            "SELECT work_references FROM ${f.schema}.workforce_shift_swap_legs WHERE request_id='$id' ORDER BY leg",
          )).map((r) => r.first).toList();
          await s.transition(id, kind, state);
          expect(
            (await f.owner.execute(
              "SELECT version FROM ${f.schema}.workforce_shift_swap_requests WHERE id='$id'",
            )).single.first,
            state + 1,
          );
          expect(
            (await f.owner.execute(
              "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
            )).single.first,
            0,
          );
          expect(
            (await f.owner.execute(
              "SELECT work_references FROM ${f.schema}.workforce_shift_swap_legs WHERE request_id='$id' ORDER BY leg",
            )).map((r) => r.first).toList(),
            before,
          );
        }),
        skip: _skip,
      );
    }
  }
  test(
    'Stage A missing claims, premature release, orphaned owners and evidence edits reject',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          id = await s.request(),
          before = await s.hash();
      for (final sql in [
        "DELETE FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$id'",
        "UPDATE ${f.schema}.workforce_shift_handoff_claims SET swap_request_id='${newUuid()}'",
        "UPDATE ${f.schema}.workforce_shift_swap_legs SET work_references='[]'::jsonb",
        "DELETE FROM ${f.schema}.workforce_shift_swap_commands",
        "UPDATE ${f.schema}.workforce_shift_swap_commands SET result='{}'::jsonb",
        "UPDATE ${f.schema}.workforce_shift_swap_requests SET source_account_version=2",
        "UPDATE ${f.schema}.workforce_shift_swap_requests SET status='offered',version=2,offered_by='${s.b.account}',offer_operation_id='${newUuid()}'",
      ]) {
        await expectLater(
          f.pool.runTx((tx) => tx.execute(sql)),
          throwsA(isA<ServerException>()),
        );
        expect(await s.hash(), before);
      }
      for (final patch in [
        "company_id='${newUuid()}'",
        "location_id='${newUuid()}'",
        "source_employee_id='${s.b.employee}'",
      ]) {
        await expectLater(
          f.owner.runTx(
            (tx) => tx.execute(
              "UPDATE ${f.schema}.workforce_shift_swap_legs SET $patch WHERE request_id='$id'",
            ),
          ),
          throwsA(isA<ServerException>()),
        );
      }
      // Terminal metadata and receipt alone cannot release the parent obligation.
      await expectLater(
        s.tx((tx, actor) async {
          final c = ShiftSwapCommandInput.fromJson('manager_reject', {
            'operationId': newUuid(),
            'expectedVersion': 1,
            'reason': 'Closure',
          });
          await s.swaps.transition(tx, id, actor.id, c);
          await s.receipt(tx, id, actor.id, c);
        }),
        throwsA(
          isA<ServerException>().having(
            (e) => e.constraintName,
            'constraint',
            'handoff_swap_complete',
          ),
        ),
      );
      expect(await s.hash(), before);
      // Capture without the claim must fail only at transaction completion.
      final c = s.requestCommand();
      await expectLater(
        s.tx((tx, actor) async {
          final a = (await s.links.forEmployee(tx, s.a.employee))!,
              b = (await s.links.forEmployee(tx, s.b.employee))!;
          await s.swaps.request(tx, c, a, b, 1, 1);
          final shift = await s.workforce.get(tx, s.shiftA);
          await s.swaps.captureLeg(
            tx,
            c.payload['requestId'] as String,
            'a',
            shift,
            s.b.employee,
            await s.tasks.captureSwapWork(tx, shift),
          );
          await s.receipt(tx, c.payload['requestId'] as String, s.a.account, c);
        }),
        throwsA(
          isA<ServerException>().having(
            (e) => e.constraintName,
            'constraint',
            'handoff_swap_complete',
          ),
        ),
      );
      expect(await s.hash(), before);
    }),
    skip: _skip,
  );

  test(
    'Stage A exact two-exclusion final roster, third overlap and adjacency',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f), id = await s.request();
      await s.offer(id);
      expect(
        await s.tx((tx, actor) => s.workforce.overlapsSwap(tx, id)),
        false,
      );
      final source = await s.tx((tx, actor) => s.workforce.get(tx, s.shiftA));
      final third = newUuid();
      await f.call(
        'POST',
        '/shifts',
        expected: 201,
        body: {
          'id': third,
          'locationId': merchandisingTestLocation,
          'employeeId': s.b.employee,
          'startsAt': source.draft.endsAt.toIso8601String(),
          'endsAt': source.draft.endsAt
              .add(const Duration(hours: 1))
              .toIso8601String(),
          'selections': [
            {'templateId': s.template, 'revisionId': s.revision},
          ],
        },
      );
      await f.call(
        'POST',
        '/shifts/$third/publish',
        body: {'expectedVersion': 1},
      );
      expect(
        await s.tx((tx, actor) => s.workforce.overlapsSwap(tx, id)),
        false,
      );
      // Close B's ordinary outgoing Shift; the handoff remains stale and claimed.
      await f.call(
        'POST',
        '/shifts/${s.shiftB}/cancel',
        body: {'expectedVersion': 2, 'reason': 'Ordinary closure'},
      );
      final other = newUuid();
      await f.call(
        'POST',
        '/shifts',
        expected: 201,
        body: {
          'id': other,
          'locationId': merchandisingTestLocation,
          'employeeId': s.b.employee,
          'startsAt': source.draft.startsAt.toIso8601String(),
          'endsAt': source.draft.endsAt.toIso8601String(),
          'selections': [
            {'templateId': s.template, 'revisionId': s.revision},
          ],
        },
      );
      await f.call(
        'POST',
        '/shifts/$other/publish',
        body: {'expectedVersion': 1},
      );
      expect(await s.tx((tx, actor) => s.workforce.overlapsSwap(tx, id)), true);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$id'",
        )).single.first,
        2,
      );
      await s.transition(id, 'manager_reject', 2);
    }),
    skip: _skip,
  );

  test(
    'Stage A deferred missing second replacement rolls all attempted effects back',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f), id = await s.request();
      await s.offer(id);
      await s.transition(id, 'confirm', 2);
      final before = await s.hash();
      await expectLater(
        s.approveIntegrityFixture(id, omitSecond: true),
        throwsA(anyOf(isA<FormatException>(), isA<ServerException>())),
      );
      expect(await s.hash(), before);
      // Direct malformed approval bypassing DTO validation reaches deferred SQL.
      await expectLater(
        s.tx((tx, actor) async {
          final op = newUuid();
          await tx.execute(
            "UPDATE ${f.schema}.workforce_shift_swap_requests SET status='approved',version=4,terminal_by='${actor.id}',terminal_at=clock_timestamp(),terminal_kind='manager_approve',terminal_operation_id='$op' WHERE id='$id'",
          );
          await s.claims.releaseSwap(tx, id);
          await tx.execute(
            'SET CONSTRAINTS ${f.schema}.handoff_swap_complete IMMEDIATE',
          );
        }),
        throwsA(isA<ServerException>()),
      );
      expect(await s.hash(), before);
      await s.approveIntegrityFixture(id);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.task_swap_links WHERE request_id='$id'",
        )).single.first,
        2,
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
        )).single.first,
        0,
      );
    }),
    skip: _skip,
  );

  for (final firstSwap in [true, false]) {
    test(
      'Stage A observed transfer versus swap A ${firstSwap ? 'swap' : 'transfer'} first',
      () => withMerchandisingFixture((f) async {
        final s = await stageAFixture(f),
            recipient = await batchWorker(f, 'transfer_only_recipient');
        final body = {
          'requestId': newUuid(),
          'operationId': newUuid(),
          'sourceShiftId': s.shiftA,
          'expectedSourceVersion': 2,
          'recipientEmployeeId': recipient.employee,
        };
        Future<String> transfer() async {
          final r = await f.call(
            'POST',
            '/me/shift-transfers',
            token: s.a.token,
            body: body,
            expected: null,
          );
          return r.status == 201 ? 'transfer' : r.body['code'] as String;
        }

        Future<String> swap() async {
          try {
            await s.request();
            return 'swap';
          } on ShiftHandoffConflict {
            return 'busy';
          }
        }

        final outcome = await observedWriters(
          f,
          firstSwap ? swap : transfer,
          firstSwap ? transfer : swap,
        );
        expect(
          outcome,
          firstSwap
              ? ['swap', 'transfer_already_pending']
              : ['transfer', 'busy'],
        );
        expect(
          (await f.owner.execute(
            "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
          )).single.first,
          1,
        );
      }),
      skip: _skip,
    );
  }
  test(
    'Stage A observed two competing swaps acquire one A and retain stale ownership',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f);
      Future<String> request() async {
        try {
          await s.request();
          return 'swap';
        } on ShiftHandoffConflict {
          return 'busy';
        }
      }

      expect(await observedWriters(f, request, request), ['swap', 'busy']);
      final id =
          (await f.owner.execute(
                "SELECT id FROM ${f.schema}.workforce_shift_swap_requests",
              )).single.first
              as String;
      await f.call(
        'POST',
        '/shifts/${s.shiftA}/cancel',
        body: {'expectedVersion': 2, 'reason': 'Stale source'},
      );
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims",
        )).single.first,
        1,
      );
      await s.transition(id, 'source_withdraw', 1);
    }),
    skip: _skip,
  );
  test(
    'Stage A reverse invitations cannot steal B; failed offers preserve both A claims',
    () => withMerchandisingFixture((f) async {
      final s = await stageAFixture(f),
          reverse = StageASwapFixture(
            f,
            s.b,
            s.a,
            s.template,
            s.revision,
            s.shiftB,
            s.shiftA,
          );
      final a = await s.request(),
          b = await reverse.request(),
          before = await s.hash();
      Future<String> offer(StageASwapFixture x, String id) async {
        try {
          await x.offer(id);
          return 'offered';
        } on ShiftHandoffConflict {
          return 'busy';
        }
      }

      expect(
        await observedWriters(f, () => offer(s, a), () => offer(reverse, b)),
        ['busy', 'busy'],
      );
      expect(await s.hash(), before);
      await reverse.transition(b, 'source_withdraw', 1);
      await s.offer(a);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$a'",
        )).single.first,
        2,
      );
    }),
    skip: _skip,
  );
}
