import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_application_fixture.dart';
import 'shift_swap_application_test.dart' show failure;

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  group('Stage B1 rollback and identity', () {
    for (final fault in [
      'second_cancel',
      'second_replacement',
      'partial_tasks',
      'missing_link',
      'receipt',
      'audit',
      'deferred',
    ]) {
      test(
        '$fault refuses entire approval, retains confirmed pair/claims, UUID remains reusable',
        () => withMerchandisingFixture((f) async {
          final x = await b1Fixture(f, tasks: 3);
          await x.prepare(3);
          final before = await x.s.hash(), body = x.approval();
          final table = switch (fault) {
            'second_cancel' || 'second_replacement' => 'shifts',
            'partial_tasks' => 'task_instances',
            'missing_link' => 'task_swap_links',
            'receipt' => 'workforce_shift_swap_commands',
            _ => 'audit_entries',
          };
          final condition = switch (fault) {
            'second_cancel' =>
              "NEW.id='${x.s.shiftB}' AND NEW.status='cancelled'",
            'second_replacement' =>
              "NEW.employee_id='${x.s.a.employee}' AND NEW.status='draft'",
            'partial_tasks' =>
              "NEW.employee_id='${x.s.a.employee}' AND NEW.position=1",
            'missing_link' => "NEW.leg='b' AND NEW.position=1",
            'receipt' => "NEW.kind='manager_approve'",
            _ => "NEW.action='workforce.swap.approved'",
          };
          final response = {'partial_tasks', 'missing_link'}.contains(fault)
              ? 'RETURN NULL;'
              : "RAISE EXCEPTION 'Injected B1 refusal' USING ERRCODE='23514';";
          await f.owner.execute(
            'CREATE FUNCTION ${f.schema}.b1_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF $condition THEN $response END IF; RETURN NEW; END \$\$',
          );
          if (fault == 'deferred') {
            await f.owner.execute(
              'CREATE CONSTRAINT TRIGGER b1_fault AFTER INSERT ON ${f.schema}.$table DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION ${f.schema}.b1_fault()',
            );
          } else {
            await f.owner.execute(
              'CREATE TRIGGER b1_fault BEFORE ${fault == 'second_cancel' ? 'UPDATE' : 'INSERT'} ON ${f.schema}.$table FOR EACH ROW EXECUTE FUNCTION ${f.schema}.b1_fault()',
            );
          }
          await expectLater(
            x.approve(body: body),
            throwsA(failure(500, 'internal_error')),
          );
          expect(await x.s.hash(), before);
          expect(
            (await x.app.detail(x.a, x.id)).json['request']['status'],
            'confirmed',
          );
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
            )).single.first,
            2,
          );
          await f.owner.execute('DROP TRIGGER b1_fault ON ${f.schema}.$table');
          expect(
            (await x.approve(body: body)).request.json['status'],
            'approved',
          );
        }),
      );
    }
    test(
      'missing owned B claim fails closed before schedule effects',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        await x.prepare(3);
        // Isolated corruption fixture: production grants cannot disable guards.
        await f.owner.execute(
          'ALTER TABLE ${f.schema}.workforce_shift_handoff_claims DISABLE TRIGGER USER',
        );
        await f.owner.execute(
          "DELETE FROM ${f.schema}.workforce_shift_handoff_claims WHERE leg='b'",
        );
        await f.owner.execute(
          'ALTER TABLE ${f.schema}.workforce_shift_handoff_claims ENABLE TRIGGER USER',
        );
        final before = await x.s.hash();
        await expectLater(x.approve(), throwsA(failure(500, 'internal_error')));
        expect(await x.s.hash(), before);
      }),
    );
    for (final source in [true, false]) {
      test(
        '${source ? 'A' : 'B'} Account/link replacement cannot inherit consent or replay; explicit closure remains',
        () => withMerchandisingFixture((f) async {
          final x = await b1Fixture(f);
          await x.prepare(3);
          final employee = source ? x.s.a.employee : x.s.b.employee;
          final old = source ? x.a : x.b;
          final link =
              (await f.call(
                    'GET',
                    '/employees/$employee/account-link',
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
            '/employees/$employee/account-link',
            expected: 201,
            body: {
              'id': newUuid(),
              'accountId': account,
              'expectedEmployeeVersion': 1,
              'expectedAccountVersion': 1,
            },
          );
          final current = await f.auth.authenticate(
            await f.login('replacement'),
          );
          final before = await x.s.hash();
          await expectLater(x.app.detail(old, x.id), throwsA(failure(401)));
          expect((await x.app.detail(current, x.id)).json['actionable'], false);
          expect(await x.app.history(current, x.id), hasLength(3));
          await expectLater(
            x.app.command(
              current,
              x.id,
              source ? 'confirm' : 'offer',
              source ? x.confirmed.toJson() : x.offered.toJson(),
            ),
            throwsA(failure(404)),
          );
          await expectLater(
            x.approve(),
            throwsA(failure(422, 'employee_unavailable')),
          );
          expect(await x.s.hash(), before);
          if (source) {
            await x.app.command(current, x.id, 'source_withdraw', {
              'operationId': newUuid(),
              'expectedVersion': 3,
              'reason': 'Close stale identity',
            });
          } else {
            await expectLater(
              x.app.command(current, x.id, 'recipient_withdraw', {
                'operationId': newUuid(),
                'expectedVersion': 3,
                'reason': 'Cannot inherit B',
              }),
              throwsA(failure(404)),
            );
            await x.app.command(f.adminPrincipal, x.id, 'manager_reject', {
              'operationId': newUuid(),
              'expectedVersion': 3,
              'reason': 'Manager closes stale identity',
            }, self: false);
          }
        }),
      );
    }
    test(
      'Account role ABA invalidates progression, current authorization precedes historical replay',
      () => withMerchandisingFixture((f) async {
        final x = await b1Fixture(f);
        final requested = await x.request();
        await f.call(
          'POST',
          '/users/${x.s.a.account}',
          body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
        );
        final viewer = await f.auth.authenticate(
          await f.login('swap_fixture_a'),
        );
        await expectLater(
          x.app.command(viewer, null, 'request', x.requested.toJson()),
          throwsA(failure(403)),
        );
        await f.call(
          'POST',
          '/users/${x.s.a.account}',
          body: {'expectedVersion': 2, 'role': 'employee', 'isActive': true},
        );
        final current = await f.auth.authenticate(
          await f.login('swap_fixture_a'),
        );
        final before = await x.s.hash();
        await expectLater(
          x.offer(),
          throwsA(failure(422, 'employee_unavailable')),
        );
        expect(await x.s.hash(), before);
        expect(
          (await x.app.command(
            current,
            null,
            'request',
            x.requested.toJson(),
          )).toJson(),
          {...requested.toJson(), 'replayed': true},
        );
        expect(await x.s.hash(), before);
        await x.app.command(current, x.id, 'source_withdraw', {
          'operationId': newUuid(),
          'expectedVersion': 1,
          'reason': 'Close stale Account version',
        });
      }),
    );
    test(
      'ordinary source execution invalidates approval while claims and stale closure persist',
      () => withMerchandisingFixture((f) async {
        final now =
            (await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime;
        final x = await b1Fixture(
          f,
          starts: now.add(const Duration(seconds: 5)),
        );
        await x.prepare(3);
        final leg = (await x.app.detail(x.a, x.id)).json['request']['legs'][0];
        while (((await f.owner.execute('SELECT clock_timestamp()')).single.first
                as DateTime)
            .isBefore(now.add(const Duration(seconds: 5)))) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        await f.call(
          'POST',
          "/employee-home/shifts/${leg['sourceShiftId']}/tasks/${leg['tasks'][0]['id']}/start",
          token: x.s.a.token,
          body: {'operationId': newUuid(), 'expectedVersion': 1},
        );
        final before = await x.s.hash();
        await expectLater(
          x.approve(),
          throwsA(failure(422, 'shift_not_swappable')),
        );
        expect(await x.s.hash(), before);
        await x.app.command(f.adminPrincipal, x.id, 'manager_reject', {
          'operationId': newUuid(),
          'expectedVersion': 3,
          'reason': 'Work has begun',
        }, self: false);
      }),
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }, skip: skip);
}
