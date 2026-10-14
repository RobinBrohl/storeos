import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';
import 'shift_swap_application_fixture.dart';
import 'shift_swap_application_test.dart' show failure;
import 'task_planogram_fixture.dart';
import 'task_knowledge_fixture.dart';

Future<(B1SwapFixture, PlanogramTaskScenario)> guidedSwap(
  MerchandisingFixture f, {
  int count = 1,
}) async {
  final g = await planogramTaskScenario(
    f,
    publishShift: false,
    knowledge: true,
  );
  final a = await f.auth.authenticate(g.token),
      b = await batchWorker(f, 'guided_b');
  final selections = <ShiftTemplateSelection>[
    ShiftTemplateSelection(g.templateId, g.templateRevisionId),
  ];
  for (var i = 1; i < count; i++) {
    final template = newUuid(), revision = newUuid();
    await f.call(
      'POST',
      '/task-templates',
      expected: 201,
      body: {
        'id': template,
        'revisionId': revision,
        'locationId': merchandisingTestLocation,
        'content': {
          'schemaVersion': 4,
          'title': 'Ordered guided work $i',
          'steps': [
            {
              'id': newUuid(),
              'type': 'confirmation',
              'instruction': 'Frozen instruction',
            },
          ],
          'knowledgeGuidance': {
            'articleId': g.knowledge!.article.id,
            'revisionId': g.knowledge!.revision.id,
          },
          'planogramGuidance': g.deployment.pin.toJson(),
        },
      },
    );
    await f.call(
      'POST',
      '/task-templates/$template/revisions/$revision/publish',
      body: {'expectedVersion': 1},
    );
    selections.add(ShiftTemplateSelection(template, revision));
  }
  final start = DateTime.now().toUtc().add(const Duration(days: 2));
  final s = StageASwapFixture(
    f,
    BatchWorker(a.id, g.employeeId, g.token),
    b,
    g.templateId,
    g.templateRevisionId,
    await b1Shift(f, g.employeeId, start, selections),
    await b1Shift(f, b.employee, start, selections.reversed.toList()),
  );
  return (B1SwapFixture(s, a, await f.auth.authenticate(b.token)), g);
}

void main() {
  final skip = merchandisingDatabaseAvailable
      ? false
      : 'Explicit isolated PostgreSQL required.';
  group('Stage B1 exact guidance', () {
    for (final blocked in ['knowledge', 'planogram']) {
      for (final version in [1, 2, 3]) {
        test(
          '$blocked invalidation rejects ${version == 1
              ? 'offer'
              : version == 2
              ? 'confirmation'
              : 'approval'} with unchanged evidence',
          () => withMerchandisingFixture((f) async {
            final (x, g) = await guidedSwap(f);
            await x.prepare(version);
            if (blocked == 'knowledge') {
              await f.call(
                'POST',
                '$knowledgeRoot/${g.knowledge!.article.id}/retire',
                body: {'expectedVersion': 2},
              );
            } else {
              await replaceDeployment(f, g.deployment);
            }
            final before = await x.s.hash();
            await expectLater(
              version == 1
                  ? x.offer()
                  : version == 2
                  ? x.confirm()
                  : x.approve(),
              throwsA(
                failure(
                  422,
                  blocked == 'knowledge'
                      ? 'guidance_unavailable'
                      : 'planogram_guidance_unavailable',
                ),
              ),
            );
            expect(await x.s.hash(), before);
            final detail = await x.app.detail(x.a, x.id);
            expect(detail.json['actionable'], false);
            expect(detail.json['request']['version'], version);
            await x.app.command(f.adminPrincipal, x.id, 'manager_reject', {
              'operationId': newUuid(),
              'expectedVersion': version,
              'reason': 'Unavailable exact pin',
            }, self: false);
          }),
        );
      }
    }
    test(
      'ten ordered exact pins per leg survive newer Knowledge publication and real paired materialization',
      () => withMerchandisingFixture((f) async {
        final (x, g) = await guidedSwap(f, count: 10);
        await x.prepare(3);
        final newest = await replaceInstruction(f, g.knowledge!.article.id);
        expect(newest.id, isNot(g.knowledge!.revision.id));
        final approved = await x.approve();
        expect(jsonEncode(approved.toJson()), isNot(contains(instructionBody)));
        for (final leg in approved.request.json['legs'] as List) {
          expect(leg['tasks'], hasLength(10));
          expect(leg['taskLinks'], hasLength(10));
          for (var i = 0; i < 10; i++) {
            final work = leg['tasks'][i], link = leg['taskLinks'][i];
            expect(work['position'], i);
            expect(
              work['knowledgeGuidance']['revisionId'],
              g.knowledge!.revision.id,
            );
            expect(work['planogramGuidance'], g.deployment.pin.toJson());
            final original = await x.s.tx(
              (tx, actor) => x.s.tasks.detail(
                tx,
                leg['sourceShiftId'] as String,
                link['sourceTaskId'] as String,
              ),
            );
            final replacement = await x.s.tx(
              (tx, actor) => x.s.tasks.detail(
                tx,
                leg['replacementShiftId'] as String,
                link['replacementTaskId'] as String,
              ),
            );
            expect(replacement.content!.toJson(), original.content!.toJson());
          }
        }
      }),
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }, skip: skip);
}
