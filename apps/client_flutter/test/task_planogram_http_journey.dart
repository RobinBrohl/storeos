// Executed by the isolated real-server acceptance fixture.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/knowledge_controller.dart';
import 'package:storeos_client/src/application/task_template_controller.dart';
import 'package:storeos_client/src/application/shift_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'knowledge_http_journey.dart' show login;
import 'package:storeos_client/src/application/merchandising_controller.dart'
    show layoutUuid;

void main() {
  test(
    'real exact deployment and Knowledge authoring, historical read and completion',
    () async {
      final base = Uri.parse(Platform.environment['STOREOS_P47_JOURNEY_URL']!);
      if (base.host != '127.0.0.1') {
        throw StateError('Isolated loopback required.');
      }
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client),
          lost = _LostPublication(api);
      final admin = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          ),
          worker = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          );
      final p = PlatformController(admin, api),
          wp = PlatformController(worker, api);
      final knowledge = KnowledgeController(admin, p, api),
          templates = TaskTemplateController(admin, p, lost),
          shifts = ShiftController(admin, p, lost),
          work = ShiftController(worker, wp, api, self: true);
      addTearDown(() {
        knowledge.dispose();
        templates.dispose();
        shifts.dispose();
        work.dispose();
        p.dispose();
        wp.dispose();
        admin.dispose();
        worker.dispose();
        client.close();
      });
      await login(admin, p, 'test_admin');
      expect(await knowledge.create(), KnowledgeOutcome.confirmed);
      knowledge.setEditing(
        const WikiContent(
          title: 'Journey instruction v1',
          body: '<script>literal</script>\n**plain text**',
        ),
      );
      expect(await knowledge.save(), KnowledgeOutcome.confirmed);
      expect(await knowledge.publish(), KnowledgeOutcome.confirmed);
      final article = knowledge.detail!.article.id,
          revision = knowledge.confirmedPublication!.revision.id;
      await templates.create('Journey work', admin.user!.locationId);
      templates.addStep();
      templates.setInstruction(templates.steps.single.id, 'Confirm work');
      templates.addStep(numeric: true);
      final numeric = templates.steps.last.id;
      templates.setInstruction(numeric, 'Record number');
      templates.setNumberRule(numeric, 'unit', 'C');
      templates.setNumberRule(numeric, 'minimum', '1');
      templates.setNumberRule(numeric, 'maximum', '5');
      await templates.loadGuidance();
      templates.selectGuidance(templates.guidanceChoices!.single);
      await templates.loadPlanograms();
      expect(templates.planogramChoices, hasLength(1));
      final view = templates.planogramChoices!.single;
      templates.selectPlanogram(view);
      final pin = templates.planogramGuidance!;
      await templates.previewPlanogram();
      expect(
        templates.planogramSelectionPreview!.assignment!.id,
        pin.assignmentId,
      );
      await templates.previewGuidance();
      expect(templates.guidancePreview!.revisionId, revision);
      expect(templates.canPublish, false);
      await templates.save();
      expect(templates.error, isNull);
      expect(templates.canPublish, true);
      final templatePublicationVersion = templates.selected!.version;
      lost.lose = true;
      await templates.publish();
      expect(templates.revision!.isDraft, false);
      expect(templates.error, isNull);
      final tid = templates.selected!.id, trid = templates.revision!.id;
      await shifts.loadChoices();
      shifts.newDraft();
      shifts.chooseEmployee(Platform.environment['STOREOS_GUIDANCE_EMPLOYEE']!);
      final now = DateTime.now().toUtc();
      shifts.setTimes(
        start: now.toIso8601String(),
        end: now.add(const Duration(hours: 1)).toIso8601String(),
      );
      await shifts.loadRevisions(tid);
      shifts.addRevision(shifts.revisions.single);
      await shifts.reviewGuidance();
      expect(shifts.selectionGuidance[trid]!.revisionId, revision);
      expect(shifts.selectionPlanograms[trid]!.toJson(), pin.toJson());
      await shifts.save();
      expect(shifts.error, isNull);
      lost.lose = true;
      await shifts.publish();
      expect(shifts.error, isNull);
      final sid = shifts.selected!.id, task = shifts.tasks.single.id;
      await login(worker, wp, 'guided_worker');
      await work.open(sid);
      await work.openTask(task);
      await work.openInstruction();
      expect(work.taskKnowledge!.revisionId, revision);
      expect(work.taskKnowledge!.body, contains('<script>literal</script>'));
      work.closeInstruction();
      await work.openLayout();
      final frozen = work.taskPlanogram!.instruction.toJson();
      expect(work.taskPlanogram!.instruction.pin.toJson(), pin.toJson());
      work.closeLayout();
      expect(work.execution!.status, 'open');
      expect(await knowledge.newDraft(), KnowledgeOutcome.confirmed);
      knowledge.setEditing(
        const WikiContent(
          title: 'Journey instruction v2',
          body: 'New instructions',
        ),
      );
      expect(await knowledge.save(), KnowledgeOutcome.confirmed);
      expect(await knowledge.publish(), KnowledgeOutcome.confirmed);
      final replacement = knowledge.confirmedPublication!.revision.id;
      await admin.authorized((token) async {
        final pg = view.revision!.planogramId;
        final route = '/merchandising/planograms/$pg';
        final current = await api.get(token, route);
        final newRevision = layoutUuid();
        final draft = await api.post(token, '$route/revisions', {
          'id': newRevision,
          'expectedVersion': current['version'],
          'content': LayoutContent(
            title: 'Replacement layout R2',
            zones: [
              LayoutZone(
                id: layoutUuid(),
                label: 'New zone',
                placements: [
                  LayoutPlacement(
                    id: layoutUuid(),
                    articleId: view.articles.single['id'] as String,
                    facings: 5,
                  ),
                ],
              ),
            ],
          ).toJson(),
        });
        final published = await api
            .post(token, '$route/revisions/$newRevision/publish', {
              'operationId': layoutUuid(),
              'expectedVersion': draft['planogram']['version'],
            });
        final fixtureRoute =
            '/locations/${view.fixture.locationId}/merchandising/fixtures/${pin.fixtureId}';
        final fixture = await api.get(token, fixtureRoute);
        final assigned = await api.post(token, '$fixtureRoute/assignments', {
          'operationId': layoutUuid(),
          'expectedVersion': fixture['version'],
          'revisionId': newRevision,
        });
        final standalone = LayoutViewDto.fromJson(
          await api.get(token, '$fixtureRoute/layout'),
        );
        expect(standalone.revision!.id, newRevision);
        expect(standalone.assignment!.id, isNot(pin.assignmentId));
        await work.openLayout();
        expect(work.taskPlanogram!.instruction.toJson(), frozen);
        expect(work.taskPlanogram!.currentContext.reassigned, true);
        await api.post(token, '$fixtureRoute/retire', {
          'expectedVersion': assigned['appliedVersion'],
        });
        await api.post(token, '$route/retire', {
          'expectedVersion': published['appliedVersion'],
        });
      });
      await admin.authorized((token) async {
        final templateReplay = await api.post(
          token,
          '/task-templates/$tid/revisions/$trid/publish',
          {'expectedVersion': templatePublicationVersion},
        );
        expect(
          templateReplay['revision']['content']['planogramGuidance'],
          pin.toJson(),
        );
        final shiftReplay = await api.post(token, '/shifts/$sid/publish', {
          'expectedVersion': 1,
        });
        expect(shiftReplay['shift']['id'], sid);
        expect(shiftReplay['tasks'].single['id'], task);
      });
      await work.openLayout();
      expect(work.taskPlanogram!.instruction.toJson(), frozen);
      expect(work.taskPlanogram!.currentContext.fixtureRetired, true);
      expect(work.taskPlanogram!.currentContext.planogramRetired, true);
      work.closeLayout();
      expect(await knowledge.retire(), KnowledgeOutcome.confirmed);
      await work.openInstruction();
      expect(work.taskKnowledge!.revisionId, revision);
      expect(work.taskKnowledge!.articleRetired, true);
      expect(work.taskKnowledge!.superseded, true);
      await worker.authorized((token) async {
        try {
          await api.get(token, '/knowledge/articles/$article');
          fail('Retired standalone discovery allowed.');
        } on StoreApiException catch (e) {
          expect(e.statusCode, 404);
        }
        try {
          await api.get(
            token,
            '/employee-home/shifts/$sid/tasks/$task/knowledge',
            query: {'revisionId': replacement},
          );
          fail('Client-selected history allowed.');
        } on StoreApiException catch (e) {
          expect(e.statusCode, 400);
        }
      });
      await templates
          .publish(); // existing committed publication remains confirmed after retirement
      work.closeInstruction();
      await work.executeTask('start');
      await work.executeTask('confirm');
      work.setNumber('3');
      await work.executeTask('record-number');
      await work.executeTask('complete');
      expect(work.execution!.status, 'completed');
      await work.open(sid);
      await work.openTask(task);
      await work.openInstruction();
      expect(work.taskKnowledge!.revisionId, revision);
      await templates.newDraft();
      templates.clearGuidance();
      await templates.save();
      await templates.publish();
      expect(templates.error, contains('Platzierung ist für neue Arbeit'));
      expect(templates.revision!.isDraft, true);
      await shifts.open(sid);
      await shifts.openTask(task);
      await shifts.openInstruction();
      expect(shifts.taskKnowledge!.revisionId, revision);
      await shifts.openLayout();
      expect(shifts.taskPlanogram!.instruction.toJson(), frozen);
    },
  );
}

class _LostPublication implements PlatformApi {
  _LostPublication(this.delegate);
  final PlatformApi delegate;
  bool lose = false;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) => delegate.get(token, route, after: after, query: query);
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    final result = await delegate.post(token, route, body);
    if (lose && route.endsWith('/publish')) {
      lose = false;
      throw const StoreApiException(
        'network_unavailable',
        'Simulated committed response loss.',
      );
    }
    return result;
  }
}
