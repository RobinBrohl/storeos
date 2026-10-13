import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

Matcher refusal(String constraint) => throwsA(
  isA<ServerException>().having(
    (e) => e.constraintName,
    'constraint',
    constraint,
  ),
);

// Deliberately bypass the Dart DTO writer so malformed SQL reaches the database.
Future<void> rawReceipt(
  StageASwapFixture s,
  TxSession tx,
  String request,
  String actor,
  ShiftSwapCommandInput c,
  Map<String, dynamic> evidence,
) => tx
    .execute(
      Sql.named(
        '''INSERT INTO ${s.f.schema}.workforce_shift_swap_commands
    (company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,payload,result)
    VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@op AS uuid),CAST(@request AS uuid),CAST(@actor AS uuid),@kind,@expected,@accepted,@status,CAST(@payload AS jsonb),CAST(@result AS jsonb))''',
      ),
      parameters: {
        'company': merchandisingTestCompany,
        'location': merchandisingTestLocation,
        'op': c.operationId,
        'request': request,
        'actor': actor,
        'kind': c.kind,
        'expected': c.expectedVersion,
        'accepted': c.kind == 'request' ? 1 : c.expectedVersion + 1,
        'status': c.kind == 'request' ? 201 : 200,
        'payload': c.canonical,
        'result': jsonEncode({
          'operationId': c.operationId,
          'kind': c.kind,
          'acceptedVersion': evidence['version'],
          'statusCode': c.kind == 'request' ? 201 : 200,
          'request': evidence,
          'replayed': false,
        }),
      },
    )
    .then((_) {});

Future<String> confirmed(StageASwapFixture s) async {
  final id = await s.request();
  await s.offer(id);
  await s.transition(id, 'confirm', 2);
  return id;
}

Future<void> cancelOriginals(
  StageASwapFixture s,
  TxSession tx,
  PlatformActor actor,
) async {
  final now =
      (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
  for (final id in [s.shiftA, s.shiftB]) {
    final source = await s.workforce.get(tx, id);
    await s.tasks.cancelForShift(
      tx,
      actor,
      shiftId: id,
      locationId: source.locationId,
      reason: 'Adversarial creation proof',
      now: now,
    );
    await s.workforce.cancel(
      tx,
      actor,
      id,
      source.version,
      'Adversarial creation proof',
      now,
    );
  }
}

Future<void> newReplacement(
  StageASwapFixture s,
  TxSession tx,
  PlatformActor actor,
  String request,
  String leg,
  String replacement, {
  bool bindFirst = true,
  String? location,
  String? employee,
}) async {
  final source = await s.workforce.get(tx, leg == 'a' ? s.shiftA : s.shiftB);
  if (bindFirst) await s.swaps.replacement(tx, request, leg, replacement);
  await s.workforce.create(
    tx,
    actor,
    replacement,
    location ?? source.locationId,
    ShiftDraftInput(
      employeeId: employee ?? (leg == 'a' ? s.b.employee : s.a.employee),
      startsAt: source.draft.startsAt,
      endsAt: source.draft.endsAt,
      selections: source.draft.selections,
    ),
  );
  if (!bindFirst) await s.swaps.replacement(tx, request, leg, replacement);
  await s.tasks.createSwapReplacement(
    tx,
    actor,
    source: source,
    requestId: request,
    leg: leg,
    replacementShiftId: replacement,
    incoming: leg == 'a' ? s.b.employee : s.a.employee,
  );
  await s.workforce.publish(tx, actor, replacement);
}

Future<void> decision(
  StageASwapFixture s,
  TxSession tx,
  PlatformActor actor,
  String id, {
  bool release = true,
}) async {
  final c = ShiftSwapCommandInput.fromJson('manager_approve', {
    'operationId': newUuid(),
    'expectedVersion': 3,
  });
  await s.swaps.transition(tx, id, actor.id, c);
  if (release) await s.claims.releaseSwap(tx, id);
  await rawReceipt(s, tx, id, actor.id, c, await s.evidenceJson(tx, id));
}

void main() {
  group(
    'Stage A remediation restricted SQL',
    () {
      test(
        'one fresh replacement plus matching existing work rolls back every effect',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f);
          final sourceA = await s.tx(
            (tx, actor) => s.workforce.get(tx, s.shiftA),
          );
          final startB = sourceA.draft.startsAt.add(const Duration(hours: 2));
          await f.call(
            'POST',
            '/shifts/${s.shiftB}/amend',
            body: {
              'expectedVersion': 2,
              'startsAt': startB.toIso8601String(),
              'endsAt': startB.add(const Duration(hours: 1)).toIso8601String(),
            },
          );
          final existing = newUuid();
          await f.call(
            'POST',
            '/shifts',
            expected: 201,
            body: {
              'id': existing,
              'locationId': merchandisingTestLocation,
              'employeeId': s.a.employee,
              'startsAt': startB.toIso8601String(),
              'endsAt': startB.add(const Duration(hours: 1)).toIso8601String(),
              'selections': [
                {'templateId': s.template, 'revisionId': s.revision},
              ],
            },
          );
          await f.call(
            'POST',
            '/shifts/$existing/publish',
            body: {'expectedVersion': 1},
          );
          final id = await confirmed(s), before = await s.hash();
          await expectLater(
            s.tx((tx, actor) async {
              expect(
                (await tx.execute('SELECT current_user')).single.first,
                f.runtimeUser,
              );
              await cancelOriginals(s, tx, actor);
              await newReplacement(s, tx, actor, id, 'a', newUuid());
              await s.swaps.replacement(tx, id, 'b', existing);
              await decision(s, tx, actor, id);
            }),
            refusal('swap_replacement_creation'),
          );
          expect(await s.hash(), before);
        }),
      );

      for (final defect in [
        'create_before_binding',
        'duplicate_pointer',
        'swapped_pointer',
        'missing_tasks',
        'crosslinked_tasks',
        'missing_claim_release',
        'foreign_location',
        'foreign_company',
      ]) {
        test(
          '$defect cannot commit an exchange; whole evidence hash restored',
          () => withMerchandisingFixture((f) async {
            final s = await stageAFixture(f),
                id = await confirmed(s),
                before = await s.hash();
            final a = newUuid(), b = newUuid();
            final constraint = switch (defect) {
              'create_before_binding' => 'swap_replacement_creation',
              'duplicate_pointer' => 'swap_replacement_creation',
              'swapped_pointer' || 'foreign_location' => 'swap_shift_creation',
              'missing_tasks' => 'tasks_swap_approval_complete',
              'crosslinked_tasks' =>
                'task_swap_links_company_id_replacement_task_id_key',
              'missing_claim_release' => 'handoff_swap_complete',
              _ => null,
            };
            await expectLater(
              s.tx((tx, actor) async {
                expect(
                  (await tx.execute('SELECT current_user')).single.first,
                  f.runtimeUser,
                );
                await cancelOriginals(s, tx, actor);
                if (defect == 'swapped_pointer') {
                  await s.swaps.replacement(tx, id, 'a', a);
                  await s.swaps.replacement(tx, id, 'b', b);
                  final source = await s.workforce.get(tx, s.shiftA);
                  await s.workforce.create(
                    tx,
                    actor,
                    b,
                    source.locationId,
                    ShiftDraftInput(
                      employeeId: s.b.employee,
                      startsAt: source.draft.startsAt,
                      endsAt: source.draft.endsAt,
                      selections: source.draft.selections,
                    ),
                  );
                } else if (defect == 'missing_tasks') {
                  await newReplacement(s, tx, actor, id, 'a', a);
                  await s.swaps.replacement(tx, id, 'b', b);
                  final source = await s.workforce.get(tx, s.shiftB);
                  await s.workforce.create(
                    tx,
                    actor,
                    b,
                    source.locationId,
                    ShiftDraftInput(
                      employeeId: s.a.employee,
                      startsAt: source.draft.startsAt,
                      endsAt: source.draft.endsAt,
                      selections: source.draft.selections,
                    ),
                  );
                  await s.workforce.publish(tx, actor, b);
                } else if (defect == 'foreign_company') {
                  await newReplacement(s, tx, actor, id, 'a', a);
                  await tx.execute('''INSERT INTO ${f.schema}.task_swap_links
              (company_id,location_id,request_id,leg,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position)
              SELECT '${newUuid()}',location_id,request_id,leg,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position
              FROM ${f.schema}.task_swap_links WHERE request_id='$id' ''');
                } else {
                  await newReplacement(
                    s,
                    tx,
                    actor,
                    id,
                    'a',
                    a,
                    bindFirst: defect != 'create_before_binding',
                    location: defect == 'foreign_location' ? newUuid() : null,
                  );
                  if (defect == 'duplicate_pointer') {
                    await s.swaps.replacement(tx, id, 'b', a);
                  }
                  if (defect == 'crosslinked_tasks') {
                    await tx.execute(
                      '''INSERT INTO ${f.schema}.task_swap_links
                (company_id,location_id,request_id,leg,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position)
                SELECT x.company_id,x.location_id,x.request_id,'b','${s.shiftB}',x.replacement_shift_id,t.id,x.replacement_task_id,x.template_id,x.revision_id,x.position
                FROM ${f.schema}.task_swap_links x JOIN ${f.schema}.task_instances t ON t.shift_id='${s.shiftB}' AND t.position=x.position WHERE x.request_id='$id' ''',
                    );
                  }
                  await newReplacement(s, tx, actor, id, 'b', b);
                }
                await decision(
                  s,
                  tx,
                  actor,
                  id,
                  release: defect != 'missing_claim_release',
                );
                if (defect == 'missing_claim_release') {
                  await tx.execute(
                    "DELETE FROM ${f.schema}.workforce_shift_handoff_claims WHERE swap_request_id='$id' AND leg='a'",
                  );
                }
              }),
              constraint == null
                  ? throwsA(
                      isA<ServerException>().having(
                        (e) => e.code,
                        'code',
                        '23514',
                      ),
                    )
                  : refusal(constraint),
            );
            expect(await s.hash(), before);
          }),
        );
      }

      test(
        'allocated draft cannot be committed before approval or forged on insertion',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f),
              id = await confirmed(s),
              before = await s.hash();
          await expectLater(
            s.tx((tx, actor) async {
              final replacement = newUuid(),
                  source = await s.workforce.get(tx, s.shiftA);
              await s.swaps.replacement(tx, id, 'a', replacement);
              await s.workforce.create(
                tx,
                actor,
                replacement,
                source.locationId,
                ShiftDraftInput(
                  employeeId: s.b.employee,
                  startsAt: source.draft.startsAt,
                  endsAt: source.draft.endsAt,
                  selections: source.draft.selections,
                ),
              );
            }),
            refusal('handoff_swap_complete'),
          );
          expect(await s.hash(), before);
          await expectLater(
            s.tx(
              (tx, actor) => tx.execute('''INSERT INTO ${f.schema}.shifts
        (id,company_id,location_id,employee_id,starts_at,ends_at,created_by,creation_input,swap_request_id,swap_leg)
        SELECT '${newUuid()}',company_id,location_id,employee_id,starts_at,ends_at,created_by,creation_input,'$id','a'
        FROM ${f.schema}.shifts WHERE id='${s.shiftA}' '''),
            ),
            refusal('swap_shift_creation'),
          );
          expect(await s.hash(), before);
        }),
      );

      test(
        'approved origin is exact, immutable and cannot be reused by another request',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f), id = await confirmed(s);
          final result = (await s.approveIntegrityFixture(id))!;
          final replacements = (result.request.json['legs'] as List)
              .map((l) => l['replacementShiftId'] as String)
              .toList();
          final origins = (await f.owner.execute(
            "SELECT swap_request_id::text,swap_leg FROM ${f.schema}.shifts WHERE swap_request_id='$id' ORDER BY swap_leg",
          )).map((r) => r.toList()).toList();
          expect(origins, [
            [id, 'a'],
            [id, 'b'],
          ]);
          expect(
            (await s.tx(
              (tx, actor) => tx.execute(
                "SELECT has_column_privilege(current_user,'${f.schema}.shifts','swap_request_id','UPDATE'),has_column_privilege(current_user,'${f.schema}.shifts','swap_leg','UPDATE')",
              ),
            )).single.toList(),
            [false, false],
          );
          final later = await stageAFixture(f, workerPrefix: 'later_swap'),
              other = await confirmed(later),
              before = await later.hash();
          await expectLater(
            later.tx((tx, actor) async {
              await cancelOriginals(later, tx, actor);
              await later.swaps.replacement(tx, other, 'a', replacements.first);
            }),
            throwsA(isA<ServerException>()),
          );
          expect(await later.hash(), before);
          await expectLater(
            s.tx(
              (tx, actor) => tx.execute(
                "UPDATE ${f.schema}.shifts SET swap_request_id=NULL WHERE id='${replacements.first}'",
              ),
            ),
            throwsA(
              isA<ServerException>().having((e) => e.code, 'code', '42501'),
            ),
          );
          expect(await later.hash(), before);
        }),
      );

      for (final path in [
        'requestedAt',
        'offeredAt',
        'confirmedAt',
        'terminalAt',
        'a.startsAt',
        'a.endsAt',
        'b.startsAt',
        'b.endsAt',
      ]) {
        test(
          'receipt $path malformed encodings refuse atomically; offsets replay exactly',
          () => withMerchandisingFixture((f) async {
            final s = await stageAFixture(f),
                id = await confirmed(s),
                before = await s.hash();
            Map<String, dynamic> holder(Map<String, dynamic> e) =>
                !path.contains('.')
                ? e
                : (e['legs'] as List)[path.startsWith('a') ? 0 : 1]
                      as Map<String, dynamic>;
            final key = path.split('.').last;
            for (final encoding in [
              'space',
              'no_zone',
              'lower_z',
              'seven_digits',
              'numeric',
              'null',
              'missing',
              'invalid_calendar',
              'leap_second',
              'bad_offset',
              'extra_key',
            ]) {
              final c = ShiftSwapCommandInput.fromJson('source_withdraw', {
                'operationId': newUuid(),
                'expectedVersion': 3,
                'reason': 'Receipt proof',
              });
              await expectLater(
                s.tx((tx, actor) async {
                  expect(
                    (await tx.execute('SELECT current_user')).single.first,
                    f.runtimeUser,
                  );
                  await s.swaps.transition(tx, id, s.a.account, c);
                  await s.claims.releaseSwap(tx, id);
                  final e = await s.evidenceJson(tx, id),
                      h = holder(e),
                      value = h[key] as String;
                  if (encoding == 'missing') {
                    h.remove(key);
                  } else if (encoding == 'extra_key') {
                    e['accountId'] = s.a.account;
                  } else {
                    h[key] = switch (encoding) {
                      'space' => value.replaceFirst('T', ' '),
                      'no_zone' => value.substring(0, value.length - 1),
                      'lower_z' => value.replaceFirst('Z', 'z'),
                      'seven_digits' => '${value.substring(0, 19)}.1234567Z',
                      'numeric' => 123,
                      'null' => null,
                      'invalid_calendar' => '2030-02-30T12:00:00Z',
                      'leap_second' => '2030-01-01T12:00:60Z',
                      _ => '2030-01-01T12:00:00+24:00',
                    };
                  }
                  expect(() => ShiftSwapDto.fromJson(e), throwsFormatException);
                  await rawReceipt(s, tx, id, s.a.account, c, e);
                }),
                refusal('swap_command_result'),
              );
              expect(await s.hash(), before);
              expect(
                await s.tx(
                  (tx, actor) => s.swaps.replay(tx, id, s.a.account, c),
                ),
                isNull,
              );
            }
            final c = ShiftSwapCommandInput.fromJson('source_withdraw', {
              'operationId': newUuid(),
              'expectedVersion': 3,
              'reason': 'Receipt proof',
            });
            late Map<String, dynamic> retained;
            await s.tx((tx, actor) async {
              await s.swaps.transition(tx, id, s.a.account, c);
              await s.claims.releaseSwap(tx, id);
              final e = await s.evidenceJson(tx, id), h = holder(e);
              final instant = shiftInstant(h[key]);
              // A legal +23:59 offset is accepted by Dart, beyond PG's input cast.
              h[key] =
                  '${instant.add(const Duration(hours: 23, minutes: 59)).toIso8601String().replaceFirst('Z', '')}+23:59';
              retained = {
                'operationId': c.operationId,
                'kind': c.kind,
                'acceptedVersion': 4,
                'statusCode': 200,
                'request': e,
                'replayed': false,
              };
              expect(
                ShiftSwapCommandResult.fromJson(retained).toJson(),
                retained,
              );
              await rawReceipt(s, tx, id, s.a.account, c, e);
            });
            final committed = await s.hash();
            final replay = (await s.tx(
              (tx, actor) => s.swaps.replay(tx, id, s.a.account, c),
            ))!;
            expect(replay.toJson(), {...retained, 'replayed': true});
            expect(await s.hash(), committed);
          }),
        );
      }

      test(
        'integer JSON tokens and retained Unicode reasons remain strictly readable',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f),
              id = await confirmed(s),
              before = await s.hash();
          for (final field in ['version', 'sourceVersion', 'position']) {
            final c = ShiftSwapCommandInput.fromJson('source_withdraw', {
              'operationId': newUuid(),
              'expectedVersion': 3,
              'reason': 'Exact result',
            });
            await expectLater(
              s.tx((tx, actor) async {
                await s.swaps.transition(tx, id, s.a.account, c);
                await s.claims.releaseSwap(tx, id);
                final e = await s.evidenceJson(tx, id),
                    leg = (e['legs'] as List).first as Map<String, dynamic>;
                final holder = field == 'version'
                    ? e
                    : field == 'sourceVersion'
                    ? leg
                    : (leg['tasks'] as List).first as Map<String, dynamic>;
                holder[field] = (holder[field] as int).toDouble();
                expect(() => ShiftSwapDto.fromJson(e), throwsFormatException);
                await rawReceipt(s, tx, id, s.a.account, c, e);
              }),
              refusal('swap_command_result'),
            );
            expect(await s.hash(), before);
          }
          for (final reason in [
            '\u00a0Untrimmed',
            'Untrimmed\u2007',
            'Control\u0085inside',
          ]) {
            await expectLater(
              s.tx(
                (tx, actor) => tx.execute(
                  Sql.named(
                    '''UPDATE ${f.schema}.workforce_shift_swap_requests SET
          status='withdrawn',version=4,terminal_by=source_account_id,terminal_kind='source_withdraw',terminal_reason=@reason,
          terminal_at=clock_timestamp(),terminal_operation_id=CAST(@op AS uuid) WHERE id=CAST(@id AS uuid)''',
                  ),
                  parameters: {'reason': reason, 'op': newUuid(), 'id': id},
                ),
              ),
              throwsA(
                isA<ServerException>().having((e) => e.code, 'code', '23514'),
              ),
            );
            expect(await s.hash(), before);
          }
        }),
      );

      test(
        'timestamp grammar, Gregorian boundaries and explicit nulls agree with Dart',
        () => withMerchandisingFixture((f) async {
          for (final value in <Object?>[
            '0001-01-01T00:00:00Z',
            '9999-12-31T23:59:59.999999Z',
            '2028-02-29T12:34:56.1Z',
            '2030-01-01T12:00:00+03:30',
            '2030-01-01T12:00:00-07:00',
            '2030-01-01T12:00:00-23:59',
            '2030-01-01T12:00:00+00:00',
            '2030-01-01T12:00:00-00:00',
            '0000-01-01T00:00:00Z',
            '0001-01-01T00:00:00+00:01',
            '9999-12-31T23:59:59-00:01',
            '2029-02-29T12:00:00Z',
            '2030-01-01T24:00:00Z',
            '2030-01-01T12:60:00Z',
            '2030-01-01T12:00:60Z',
            '2030-01-01T12:00:00+23:60',
            '2030-01-01 12:00:00Z',
            '2030-01-01T12:00:00.1234567Z',
            'infinity',
            123,
            true,
            {},
            [],
            null,
          ]) {
            DateTime? parsed;
            try {
              parsed = shiftInstant(value);
            } on FormatException {
              /* Expected invalid corpus cases. */
            }
            final expected = parsed ?? DateTime.utc(2030);
            final accepted = (await f.pool.runTx(
              (tx) => tx.execute(
                Sql.named(
                  'SELECT ${f.schema}.swap_receipt_instant(CAST(@value AS jsonb),@expected)',
                ),
                parameters: {'value': jsonEncode(value), 'expected': expected},
              ),
            )).single.first;
            expect(accepted, parsed != null, reason: 'Timestamp $value');
          }
          expect(
            (await f.pool.runTx(
              (tx) => tx.execute(
                "SELECT ${f.schema}.swap_receipt_instant('null'::jsonb,NULL),${f.schema}.swap_receipt_instant(NULL,NULL),${f.schema}.swap_receipt_instant('123'::jsonb,NULL)",
              ),
            )).single.toList(),
            [true, false, false],
          );
        }),
      );
    },
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
}
