// Executed by the isolated server fixture, outside ordinary test discovery.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/knowledge_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

Future<void> login(
  SessionController session,
  PlatformController platform,
  String username,
) async {
  final ready = Completer<void>();
  void loaded() {
    if (platform.organization != null &&
        !platform.isBusy &&
        !ready.isCompleted) {
      ready.complete();
    }
  }

  platform.addListener(loaded);
  try {
    await session.signIn(
      username: username,
      password: Platform.environment['STOREOS_KNOWLEDGE_JOURNEY_PASSWORD']!,
    );
    loaded();
    await ready.future.timeout(const Duration(seconds: 10));
  } finally {
    platform.removeListener(loaded);
  }
}

void main() {
  test(
    'real Knowledge author, employee, replacement, lost/late replay, history and retirement',
    () async {
      final base = Uri.parse(
        Platform.environment['STOREOS_KNOWLEDGE_JOURNEY_URL']!,
      );
      if (base.host != '127.0.0.1') {
        throw StateError('Isolated loopback API required.');
      }
      final client = http.Client(),
          transport = HttpPlatformApi(baseUri: base, client: client);
      final fault = _LostResponse(transport);
      final admin = SessionController(
        HttpStoreApi(baseUri: base, client: client),
      );
      final adminPlatform = PlatformController(admin, transport);
      final manager = KnowledgeController(admin, adminPlatform, fault);
      final worker = SessionController(
        HttpStoreApi(baseUri: base, client: client),
      );
      final workerPlatform = PlatformController(worker, transport);
      final employee = KnowledgeController(worker, workerPlatform, transport);
      addTearDown(() {
        manager.dispose();
        employee.dispose();
        adminPlatform.dispose();
        workerPlatform.dispose();
        admin.dispose();
        worker.dispose();
        client.close();
      });
      await login(admin, adminPlatform, 'test_admin');
      await login(worker, workerPlatform, 'knowledge_worker');
      expect(await manager.create(), KnowledgeOutcome.confirmed);
      final id = manager.detail!.article.id;
      const body =
          '# markdown\n<script>literal</script>\n<a href="x">**\n  ä 😀';
      manager.setEditing(
        const WikiContent(title: 'Closing instructions', body: body),
      );
      expect(await manager.publish(), KnowledgeOutcome.rejected);
      expect(await manager.save(), KnowledgeOutcome.confirmed);
      expect(manager.detail!.draft!.content.body, body);
      fault.lose = true;
      expect(await manager.publish(), KnowledgeOutcome.uncertain);
      final firstCommand = manager.pending!;
      expect(await manager.retryPublication(), KnowledgeOutcome.confirmed);
      expect(manager.confirmedPublication!.replayed, true);
      final first = manager.confirmedPublication!.revision;
      await employee.search('CLOSING');
      expect(employee.published, hasLength(1));
      await employee.openInstruction(id);
      expect(employee.instruction!.revisionId, first.id);
      expect(employee.instruction!.body, body);
      expect(await manager.newDraft(), KnowledgeOutcome.confirmed);
      await employee.refreshInstruction();
      expect(employee.instruction!.revisionId, first.id);
      manager.setEditing(
        const WikiContent(
          title: 'Closing replacement',
          body: 'Replacement text',
        ),
      );
      expect(await manager.save(), KnowledgeOutcome.confirmed);
      expect(await manager.publish(), KnowledgeOutcome.confirmed);
      final second = manager.confirmedPublication!.revision;
      await employee.refreshInstruction();
      expect(employee.instruction!.revisionId, second.id);
      expect(
        manager.history.where((r) => r.id == first.id).single.content.body,
        body,
      );
      final version = manager.detail!.article.version;
      final late = WikiPublicationDto.fromJson(
        await admin.authorized(
          (token) =>
              transport.post(token, firstCommand.route, firstCommand.body),
        ),
      );
      expect(late.revision.id, first.id);
      expect(late.replayed, true);
      await manager.openManaged(id);
      expect(manager.detail!.article.version, version);
      await employee.refreshInstruction();
      expect(employee.instruction!.revisionId, second.id);
      expect(await manager.retire(), KnowledgeOutcome.confirmed);
      await employee.search('Closing');
      expect(employee.published, isEmpty);
      await employee.openInstruction(id);
      expect(employee.instruction, isNull);
      expect(employee.error, contains('not_found'));
      expect(manager.detail!.article.status, 'retired');
      expect(manager.history, hasLength(2));
      final retiredVersion = manager.detail!.article.version;
      final retiredReplay = WikiPublicationDto.fromJson(
        await admin.authorized(
          (token) =>
              transport.post(token, firstCommand.route, firstCommand.body),
        ),
      );
      expect(retiredReplay.revision.id, first.id);
      await manager.openManaged(id);
      expect(manager.detail!.article.version, retiredVersion);
    },
  );
}

class _LostResponse implements PlatformApi {
  _LostResponse(this.delegate);
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
        'Injected committed response loss.',
      );
    }
    return result;
  }
}
