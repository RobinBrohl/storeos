import 'dart:convert';
import 'package:test/test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'task_planogram_fixture.dart';
import 'task_knowledge_fixture.dart';
import 'recipe_fixture.dart' show orderedRecipeCommands;
import 'merchandising_integration_test.dart' as m;

Future<String> transferGuidanceEvidence(
  MerchandisingFixture f,
) async => jsonEncode({
  for (final table in [
    'shifts',
    'shift_template_selections',
    'task_instances',
    'task_transfer_links',
    'workforce_shift_transfer_requests',
    'workforce_shift_transfer_commands',
    'audit_entries',
  ])
    table: (await f.owner.execute(
      "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t${table == 'audit_entries' ? " WHERE action='workforce.transfer.approved'" : ''}",
    )).single.toList(),
});

void main() {
  for (final blocked in [null, 'newer_knowledge', 'knowledge', 'planogram']) {
    test(
      'P4.11 exact schema-4 pins ${blocked ?? 'replacement'}',
      () => withMerchandisingFixture((f) async {
        final s = await planogramTaskScenario(
              f,
              publishShift: false,
              knowledge: true,
            ),
            r = await batchWorker(f, 'transfer_guided_recipient');
        final shift = newUuid(),
            id = newUuid(),
            start = DateTime.now().toUtc().add(const Duration(days: 1));
        await f.call(
          'POST',
          '/shifts',
          body: {
            'id': shift,
            'locationId': merchandisingTestLocation,
            'employeeId': s.employeeId,
            'startsAt': start.toIso8601String(),
            'endsAt': start.add(const Duration(hours: 1)).toIso8601String(),
            'selections': [
              {'templateId': s.templateId, 'revisionId': s.templateRevisionId},
            ],
          },
          expected: 201,
        );
        await f.call(
          'POST',
          '/shifts/$shift/publish',
          body: {'expectedVersion': 1},
        );
        await f.call(
          'POST',
          '/me/shift-transfers',
          token: s.token,
          body: {
            'operationId': newUuid(),
            'requestId': id,
            'sourceShiftId': shift,
            'expectedSourceVersion': 2,
            'recipientEmployeeId': r.employee,
          },
          expected: 201,
        );
        await f.call(
          'POST',
          '/me/shift-transfers/$id/accept',
          token: r.token,
          body: {'operationId': newUuid(), 'expectedVersion': 1},
        );
        if (blocked == 'knowledge') {
          await f.call(
            'POST',
            '$knowledgeRoot/${s.knowledge!.article.id}/retire',
            body: {'expectedVersion': 2},
          );
        }
        if (blocked == 'newer_knowledge') {
          final latest = await replaceInstruction(f, s.knowledge!.article.id);
          expect(latest.id, isNot(s.knowledge!.revision.id));
        }
        if (blocked == 'planogram') await replaceDeployment(f, s.deployment);
        final approve = await f.call(
          'POST',
          '/locations/$merchandisingTestLocation/shift-transfers/$id/approve',
          body: {'operationId': newUuid(), 'expectedVersion': 2},
          expected: {'knowledge', 'planogram'}.contains(blocked) ? 422 : 200,
        );
        if ({'knowledge', 'planogram'}.contains(blocked)) {
          expect(
            approve.body['code'],
            blocked == 'knowledge'
                ? 'guidance_unavailable'
                : 'planogram_guidance_unavailable',
          );
          expect(
            (await f.call('GET', '/shifts/$shift')).body['shift']['status'],
            'published',
          );
        } else {
          final b = approve.body['request']['replacementShiftId'];
          final originals =
              (await f.call('GET', '/shifts/$shift')).body['tasks'] as List;
          final replacements =
              (await f.call('GET', '/shifts/$b')).body['tasks'] as List;
          final a = (await f.call(
            'GET',
            '/shifts/$shift/tasks/${originals.single['id']}',
          )).body;
          final z = (await f.call(
            'GET',
            '/shifts/$b/tasks/${replacements.single['id']}',
          )).body;
          expect(z['content'], a['content']);
          expect(
            z['content']['knowledgeGuidance']['revisionId'],
            s.knowledge!.revision.id,
          );
          expect(z['content']['planogramGuidance'], s.deployment.pin.toJson());
          expect(jsonEncode(approve.body), isNot(contains(instructionBody)));
        }
      }),
      skip: merchandisingDatabaseAvailable
          ? false
          : 'Explicit isolated PostgreSQL required.',
    );
  }
  for (final kind in [
    'knowledge_publication',
    'knowledge_retirement',
    'planogram_unavailable',
    'planogram_revision',
    'planogram_reassignment',
  ]) {
    for (final changeFirst in [true, false]) {
      test(
        'P4.11 observed $kind change ${changeFirst ? 'before' : 'after'} approval',
        () => withMerchandisingFixture((f) async {
          final s = await planogramTaskScenario(
                f,
                publishShift: false,
                knowledge: true,
              ),
              r = await batchWorker(f, 'guidance_race_recipient'),
              shift = newUuid(),
              id = newUuid(),
              starts = DateTime.now().toUtc().add(const Duration(days: 1));
          await f.call(
            'POST',
            '/shifts',
            body: {
              'id': shift,
              'locationId': merchandisingTestLocation,
              'employeeId': s.employeeId,
              'startsAt': starts.toIso8601String(),
              'endsAt': starts.add(const Duration(hours: 1)).toIso8601String(),
              'selections': [
                {
                  'templateId': s.templateId,
                  'revisionId': s.templateRevisionId,
                },
              ],
            },
            expected: 201,
          );
          await f.call(
            'POST',
            '/shifts/$shift/publish',
            body: {'expectedVersion': 1},
          );
          await f.call(
            'POST',
            '/me/shift-transfers',
            token: s.token,
            body: {
              'operationId': newUuid(),
              'requestId': id,
              'sourceShiftId': shift,
              'expectedSourceVersion': 2,
              'recipientEmployeeId': r.employee,
            },
            expected: 201,
          );
          await f.call(
            'POST',
            '/me/shift-transfers/$id/accept',
            token: r.token,
            body: {'operationId': newUuid(), 'expectedVersion': 1},
          );
          late String route;
          Map<String, dynamic> body = {'expectedVersion': 2};
          String? newerRevision;
          if (kind == 'knowledge_publication') {
            final draft = WikiRevisionResultDto.fromJson(
              (await f.call(
                'POST',
                '$knowledgeRoot/${s.knowledge!.article.id}/revisions',
                body: NewWikiDraftRequest(newUuid(), 2).toJson(),
                expected: 201,
              )).body,
            );
            final edited = WikiRevisionResultDto.fromJson(
              (await f.call(
                'POST',
                '$knowledgeRoot/${s.knowledge!.article.id}/revisions/${draft.revision.id}/edit',
                body: SaveWikiRequest(
                  draft.article.version,
                  const WikiContent(
                    title: 'New race revision',
                    body: 'Retained v1 must remain exact.',
                  ),
                ).toJson(),
              )).body,
            );
            newerRevision = edited.revision.id;
            route =
                '$knowledgeRoot/${s.knowledge!.article.id}/revisions/$newerRevision/publish';
            body = PublishWikiRequest(
              newUuid(),
              edited.article.version,
            ).toJson();
          } else if (kind == 'knowledge_retirement') {
            route = '$knowledgeRoot/${s.knowledge!.article.id}/retire';
          } else if (kind == 'planogram_unavailable') {
            route = '${m.froot}/${s.deployment.fixtureId}/retire';
          } else if (kind == 'planogram_revision') {
            final current = (await f.call(
              'GET',
              '${m.proot}/${s.deployment.planogramId}',
            )).body;
            final draft = await m.draft(
              f,
              s.deployment.planogramId,
              current['version'] as int,
              m.content(s.deployment.articleId, title: 'New race layout'),
            );
            newerRevision = draft['revision']['id'] as String;
            route =
                '${m.proot}/${s.deployment.planogramId}/revisions/$newerRevision/publish';
            body = {
              'operationId': newUuid(),
              'expectedVersion': draft['planogram']['version'],
            };
          } else {
            newerRevision = (await replaceDeployment(
              f,
              s.deployment,
              assign: false,
            )).revisionId;
            route = '${m.froot}/${s.deployment.fixtureId}/assignments';
            body = {
              'operationId': newUuid(),
              'expectedVersion': 2,
              'revisionId': newerRevision,
            };
          }
          final command = {'operationId': newUuid(), 'expectedVersion': 2};
          final before = await transferGuidanceEvidence(f);
          Future<MerchandisingReply> change() =>
              f.call('POST', route, body: body, expected: null);
          Future<MerchandisingReply> approval() => f.call(
            'POST',
            '/locations/$merchandisingTestLocation/shift-transfers/$id/approve',
            body: command,
            expected: null,
          );
          final result = await orderedRecipeCommands(
            f,
            changeFirst ? change : approval,
            changeFirst ? approval : change,
          );
          final rejects =
              changeFirst &&
              {
                'knowledge_retirement',
                'planogram_unavailable',
                'planogram_reassignment',
              }.contains(kind);
          final mutation = result[changeFirst ? 0 : 1],
              approved = result[changeFirst ? 1 : 0];
          expect(mutation.status, 200, reason: jsonEncode(mutation.body));
          expect(
            approved.status,
            rejects ? 422 : 200,
            reason: jsonEncode(approved.body),
          );
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".task_transfer_links',
            )).single.first,
            rejects ? 0 : 1,
          );
          if (rejects) {
            expect(
              approved.body['code'],
              kind == 'knowledge_retirement'
                  ? 'guidance_unavailable'
                  : 'planogram_guidance_unavailable',
            );
            expect(await transferGuidanceEvidence(f), before);
            expect(
              (await f.call('GET', '/shifts/$shift')).body['shift']['status'],
              'published',
            );
            expect(
              (await f.call(
                'GET',
                '/locations/$merchandisingTestLocation/shift-transfers/$id',
              )).body['status'],
              'accepted',
            );
          } else {
            final replacement = approved.body['request']['replacementShiftId'];
            final sourceTasks =
                (await f.call('GET', '/shifts/$shift')).body['tasks'] as List;
            final targetTasks =
                (await f.call('GET', '/shifts/$replacement')).body['tasks']
                    as List;
            expect(targetTasks, hasLength(1));
            final original = (await f.call(
              'GET',
              '/shifts/$shift/tasks/${sourceTasks.single['id']}',
            )).body;
            final target = (await f.call(
              'GET',
              '/shifts/$replacement/tasks/${targetTasks.single['id']}',
            )).body;
            expect(target['content'], original['content']);
            expect(
              target['content']['knowledgeGuidance']['revisionId'],
              s.knowledge!.revision.id,
            );
            expect(
              target['content']['planogramGuidance'],
              s.deployment.pin.toJson(),
            );
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM "${f.schema}".task_transfer_links l JOIN "${f.schema}".task_instances a ON a.id=l.source_task_id JOIN "${f.schema}".task_instances b ON b.id=l.replacement_task_id WHERE l.request_id=\'$id\' AND a.shift_id=\'$shift\' AND b.shift_id=\'$replacement\' AND a.status=\'cancelled\' AND b.status=\'open\' AND b.version=1 AND a.content::jsonb=b.content::jsonb AND a.template_id=b.template_id AND a.revision_id=b.revision_id AND a.position=b.position',
              )).single.first,
              1,
            );
            for (final query in [
              'SELECT count(*) FROM "${f.schema}".workforce_shift_transfer_requests WHERE status=\'approved\' AND id=\'$id\'',
              'SELECT count(*) FROM "${f.schema}".workforce_shift_transfer_commands WHERE kind=\'manager_approve\' AND request_id=\'$id\'',
              'SELECT count(*) FROM "${f.schema}".audit_entries WHERE action=\'workforce.transfer.approved\' AND entity_id=\'$id\'',
              'SELECT count(*) FROM "${f.schema}".shifts WHERE id=\'$replacement\' AND status=\'published\'',
            ]) {
              expect((await f.owner.execute(query)).single.first, 1);
            }
            final after = await transferGuidanceEvidence(f);
            expect((await approval()).body, {
              ...approved.body,
              'replayed': true,
            });
            expect(await transferGuidanceEvidence(f), after);
          }
          if (kind == 'knowledge_publication') {
            expect(
              (await f.call(
                'GET',
                '$knowledgeRoot/${s.knowledge!.article.id}',
              )).body['article']['currentPublishedRevisionId'],
              newerRevision,
            );
          }
          if (kind == 'planogram_revision') {
            expect(
              (await f.call(
                'GET',
                '${m.proot}/${s.deployment.planogramId}/revisions/$newerRevision',
              )).body['status'],
              'published',
            );
            expect(
              (await f.call(
                'GET',
                '${m.froot}/${s.deployment.fixtureId}',
              )).body['currentAssignmentId'],
              s.deployment.pin.assignmentId,
            );
          }
        }),
        skip: merchandisingDatabaseAvailable
            ? false
            : 'Explicit isolated PostgreSQL required.',
      );
    }
  }
}
