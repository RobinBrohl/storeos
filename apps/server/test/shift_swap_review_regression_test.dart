import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';
import '../../../packages/api_contracts/test/shift_swap_fixture.dart';
import 'article_quantity_fixture.dart';

// The seven independent review probes, retaining the counterexample SQL.
// Only the three reproduced defects now require refusal instead of acceptance.
void main() {
  group(
    'Independent Stage A review regressions',
    () {
      test(
        'Probe: incomplete second replacement reaches deferred SQL and restores all hashes',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f), id = await s.request();
          await s.offer(id);
          await s.transition(id, 'confirm', 2);
          final before = await s.hash();
          await expectLater(
            s.approveIntegrityFixture(id, omitSecond: true, rawReceipt: true),
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
      );

      test(
        'Probe: populated 0027 P4.15 rows survive 0028 and exact replay',
        () => withMerchandisingFixture((f) async {
          final a = await f.stockArticle(sku: 'P416-REVIEW-P415');
          final l = await f.openStock(a.id, quantity: '1');
          final p = await configureQuantity(
            f,
            a.id,
            'kg',
            packages: [
              {'id': newUuid(), 'label': 'Probe sack', 'content': '5'},
            ],
          );
          await bindQuantity(f, l, p, 'kg');
          final review = await previewQuantity(f, l, p, 'g', '1250');
          final command = correctionCommand(review);
          final result = (await f.call(
            'POST',
            '${quantityStockRoot(l)}/correct',
            body: command,
          )).body;
          final tables = [
            'inventory_quantity_profiles',
            'inventory_quantity_revisions',
            'inventory_quantity_commands',
            'stock_quantity_bindings',
            'stock_quantity_corrections',
            'stock_levels',
            'stock_movements',
            'audit_entries',
          ];
          Future<String> hash() async => jsonEncode({
            for (final t in tables)
              t: (await f.owner.execute(
                "SELECT count(*),md5(string_agg(to_jsonb(x)::text,'' ORDER BY to_jsonb(x)::text)) FROM ${f.schema}.$t x",
              )).single.toList(),
          });
          final before = await hash();
          for (final t in tables.take(5)) {
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM ${f.schema}.$t',
              )).single.first,
              greaterThan(0),
            );
          }
          final runner = MigrationRunner(
            connection: f.owner,
            migrationsDirectory: Directory('migrations'),
            schemaName: f.schema,
            runtimeDatabaseUser: f.runtimeUser,
          );
          expect(await runner.apply(), ['0028_bilateral_shift_swaps']);
          expect(await hash(), before);
          expect(await runner.apply(), isEmpty);
          expect(
            (await f.call(
              'POST',
              '${quantityStockRoot(l)}/correct',
              body: command,
            )).body,
            result,
          );
          expect(await hash(), before);
        }, legacyBefore: '0028_bilateral_shift_swaps'),
      );

      test('F03: withdrawal receipt kind mismatch is rejected by DTO', () {
        final j = swapEvidence(state: 'withdrawn', stage: 2);
        j['terminalKind'] = 'recipient_withdraw';
        expect(
          () => ShiftSwapCommandResult.fromJson({
            'operationId': j['terminalOperationId'],
            'kind': 'source_withdraw',
            'acceptedVersion': j['version'],
            'statusCode': 200,
            'request': j,
            'replayed': false,
          }),
          throwsFormatException,
        );
      });

      test(
        'F02: restricted SQL refuses the original unreadable receipt',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f), c = s.requestCommand();
          final id = c.payload['requestId'] as String;
          final before = await s.hash();
          await expectLater(
            s.tx((tx, actor) async {
              expect(
                (await tx.execute('SELECT current_user')).single.first,
                f.runtimeUser,
              );
              final a = (await s.links.forEmployee(tx, s.a.employee))!;
              final b = (await s.links.forEmployee(tx, s.b.employee))!;
              await s.swaps.request(tx, c, a, b, 1, 1);
              final shift = await s.workforce.get(tx, s.shiftA);
              await s.swaps.captureLeg(
                tx,
                id,
                'a',
                shift,
                s.b.employee,
                await s.tasks.captureSwapWork(tx, shift),
              );
              await s.claims.claimSwapA(tx, id);
              final e = await s.evidenceJson(tx, id);
              e['requestedAt'] = (e['requestedAt'] as String).replaceFirst(
                'T',
                ' ',
              );
              final result = {
                'operationId': c.operationId,
                'kind': 'request',
                'acceptedVersion': 1,
                'statusCode': 201,
                'request': e,
                'replayed': false,
              };
              await tx.execute(
                Sql.named(
                  '''INSERT INTO ${f.schema}.workforce_shift_swap_commands
        (company_id,location_id,operation_id,request_id,actor_id,kind,expected_version,accepted_version,status_code,payload,result)
        VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@op AS uuid),CAST(@request AS uuid),CAST(@actor AS uuid),'request',2,1,201,CAST(@payload AS jsonb),CAST(@result AS jsonb))''',
                ),
                parameters: {
                  'company': merchandisingTestCompany,
                  'location': merchandisingTestLocation,
                  'op': c.operationId,
                  'request': id,
                  'actor': s.a.account,
                  'payload': c.canonical,
                  'result': jsonEncode(result),
                },
              );
            }),
            throwsA(
              isA<ServerException>().having(
                (e) => e.constraintName,
                'constraint',
                'swap_command_result',
              ),
            ),
          );
          expect(await s.hash(), before);
          expect(
            await s.tx((tx, actor) => s.swaps.replay(tx, id, s.a.account, c)),
            isNull,
          );
          await s.request(command: c);
          expect(
            (await s.tx(
              (tx, actor) => s.swaps.replay(tx, id, s.a.account, c),
            ))!.json['replayed'],
            true,
          );
        }),
      );

      test(
        'F01: original pre-existing overlapping third Shift substitution refuses',
        () => withMerchandisingFixture((f) async {
          final s = await stageAFixture(f);
          final a = await s.tx((tx, actor) => s.workforce.get(tx, s.shiftA));
          final startB = a.draft.startsAt.add(const Duration(hours: 2));
          await f.call(
            'POST',
            '/shifts/${s.shiftB}/amend',
            body: {
              'expectedVersion': 2,
              'startsAt': startB.toIso8601String(),
              'endsAt': startB.add(const Duration(hours: 1)).toIso8601String(),
            },
          );
          Future<String> third(String employee, DateTime start) async {
            final id = newUuid();
            await f.call(
              'POST',
              '/shifts',
              expected: 201,
              body: {
                'id': id,
                'employeeId': employee,
                'locationId': merchandisingTestLocation,
                'startsAt': start.toIso8601String(),
                'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
                'selections': [
                  {'templateId': s.template, 'revisionId': s.revision},
                ],
              },
            );
            await f.call(
              'POST',
              '/shifts/$id/publish',
              body: {'expectedVersion': 1},
            );
            return id;
          }

          final replacementA = await third(s.b.employee, a.draft.startsAt);
          final replacementB = await third(s.a.employee, startB);
          final id = await s.request();
          await s.offer(id);
          await s.transition(id, 'confirm', 2);
          expect(
            await s.tx((tx, actor) => s.workforce.overlapsSwap(tx, id)),
            true,
          );
          final beforeCounts = (await f.owner.execute('''SELECT
      (SELECT count(*) FROM ${f.schema}.shifts),
      (SELECT count(*) FROM ${f.schema}.task_instances)''')).single.toList();
          final before = await s.hash();
          await expectLater(
            s.tx((tx, actor) async {
              expect(
                (await tx.execute('SELECT current_user')).single.first,
                f.runtimeUser,
              );
              final originals = [
                await s.workforce.get(tx, s.shiftA),
                await s.workforce.get(tx, s.shiftB),
              ];
              final now =
                  (await tx.execute('SELECT clock_timestamp()')).single.first
                      as DateTime;
              for (final source in originals) {
                await s.tasks.cancelForShift(
                  tx,
                  actor,
                  shiftId: source.id,
                  locationId: source.locationId,
                  reason: 'Adversarial integrity probe',
                  now: now,
                );
                await s.workforce.cancel(
                  tx,
                  actor,
                  source.id,
                  source.version,
                  'Adversarial integrity probe',
                  now,
                );
              }
              for (var i = 0; i < 2; i++) {
                final leg = i == 0 ? 'a' : 'b',
                    replacement = i == 0 ? replacementA : replacementB;
                await s.swaps.replacement(tx, id, leg, replacement);
                await tx.execute(
                  '''INSERT INTO ${f.schema}.task_swap_links
          (company_id,location_id,request_id,leg,source_shift_id,replacement_shift_id,source_task_id,replacement_task_id,template_id,revision_id,position)
          SELECT x.company_id,x.location_id,'$id','$leg',x.shift_id,y.shift_id,x.id,y.id,x.template_id,x.revision_id,x.position
          FROM ${f.schema}.task_instances x JOIN ${f.schema}.task_instances y
          ON y.company_id=x.company_id AND y.template_id=x.template_id AND y.revision_id=x.revision_id AND y.position=x.position
          WHERE x.shift_id='${originals[i].id}' AND y.shift_id='$replacement' ''',
                );
              }
              final c = ShiftSwapCommandInput.fromJson('manager_approve', {
                'operationId': newUuid(),
                'expectedVersion': 3,
              });
              await s.swaps.transition(tx, id, actor.id, c);
              await s.claims.releaseSwap(tx, id);
              await s.receipt(tx, id, actor.id, c);
            }),
            throwsA(
              isA<ServerException>().having(
                (e) => e.constraintName,
                'constraint',
                'swap_replacement_creation',
              ),
            ),
          );
          expect(await s.hash(), before);
          expect(
            (await f.owner.execute(
              "SELECT status FROM ${f.schema}.workforce_shift_swap_requests WHERE id='$id'",
            )).single.first,
            'confirmed',
          );
          expect(
            (await f.owner.execute('''SELECT
      (SELECT count(*) FROM ${f.schema}.shifts),
      (SELECT count(*) FROM ${f.schema}.task_instances)''')).single.toList(),
            beforeCounts,
          );
        }),
      );

      for (final offerFirst in [true, false]) {
        test(
          'Probe: transfer versus B offer both orders: offerFirst=$offerFirst',
          () => withMerchandisingFixture((f) async {
            final s = await stageAFixture(f),
                target = await batchWorker(f, 'probe_target');
            final id = await s.request();
            Future<String> transfer() async {
              final r = await f.call(
                'POST',
                '/me/shift-transfers',
                token: s.b.token,
                expected: null,
                body: {
                  'requestId': newUuid(),
                  'operationId': newUuid(),
                  'sourceShiftId': s.shiftB,
                  'expectedSourceVersion': 2,
                  'recipientEmployeeId': target.employee,
                },
              );
              return r.status == 201 ? 'transfer' : r.body['code'] as String;
            }

            Future<String> offer() async {
              try {
                await s.offer(id);
                return 'offered';
              } on Exception catch (e) {
                if (e.runtimeType.toString() == 'ShiftHandoffConflict') {
                  return 'busy';
                }
                rethrow;
              }
            }

            expect(
              await observedWriters(
                f,
                offerFirst ? offer : transfer,
                offerFirst ? transfer : offer,
              ),
              offerFirst
                  ? ['offered', 'transfer_already_pending']
                  : ['transfer', 'busy'],
            );
            final row = await s.tx((tx, actor) => s.swaps.find(tx, id));
            expect(row!['status'], offerFirst ? 'offered' : 'requested');
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM ${f.schema}.workforce_shift_handoff_claims',
              )).single.first,
              2,
            );
          }),
        );
      }
    },
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
}
