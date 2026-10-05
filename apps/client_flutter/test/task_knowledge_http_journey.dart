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

void main() {
  test(
    'real guided authoring, pinning, historical read and normal completion',
    () async {
      final base = Uri.parse(
        Platform.environment['STOREOS_KNOWLEDGE_JOURNEY_URL']!,
      );
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
      await templates.previewGuidance();
      expect(templates.guidancePreview!.revisionId, revision);
      expect(templates.canPublish, false);
      await templates.save();
      expect(templates.error, isNull);
      expect(templates.canPublish, true);
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
      await shifts.open(sid);
      await shifts.openTask(task);
      await shifts.openInstruction();
      expect(shifts.taskKnowledge!.revisionId, revision);
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
