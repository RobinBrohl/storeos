// Invoked only by the isolated PostgreSQL fixture, outside test discovery.
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/merchandising_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test(
    'real Flutter controllers / HTTP / PostgreSQL planogram journey',
    () async {
      final base = Uri.parse(
        Platform.environment['STOREOS_PLANOGRAM_JOURNEY_URL']!,
      );
      final expectedStockStatus = StockContextStatus.fromJson(
        Platform.environment['STOREOS_PLANOGRAM_JOURNEY_STOCK_STATUS'],
      );
      if (base.host != '127.0.0.1') {
        throw StateError('Isolated loopback API required.');
      }
      final client = http.Client();
      final transport = HttpPlatformApi(baseUri: base, client: client);
      final fault = _LostResponse(transport);
      final session = SessionController(
        HttpStoreApi(baseUri: base, client: client),
      );
      final platform = PlatformController(session, transport);
      final c = MerchandisingController(session, platform, fault);
      addTearDown(() {
        c.dispose();
        platform.dispose();
        session.dispose();
        client.close();
      });
      final ready = Completer<void>();
      void loaded() {
        if (platform.organization != null &&
            !platform.isBusy &&
            !ready.isCompleted) {
          ready.complete();
        }
      }

      platform.addListener(loaded);
      await session.signIn(
        username: 'test_admin',
        password: Platform.environment['STOREOS_PLANOGRAM_JOURNEY_PASSWORD']!,
      );
      loaded();
      await ready.future.timeout(const Duration(seconds: 10));
      platform.removeListener(loaded);
      await c.load();
      expect(
        await c.createFixture('Brot Theke', 'counter'),
        LayoutCommandOutcome.confirmed,
      );
      await c.openFixture(c.fixture!);
      expect(await c.createPlanogram(), LayoutCommandOutcome.confirmed);
      expect(await c.newDraft(), LayoutCommandOutcome.confirmed);
      final article =
          Platform.environment['STOREOS_PLANOGRAM_JOURNEY_ARTICLE']!;
      c.setEditing(
        LayoutContent(
          title: 'Brot München <>&',
          zones: [
            LayoutZone(
              id: layoutUuid(),
              label: 'Links',
              placements: [
                LayoutPlacement(
                  id: layoutUuid(),
                  articleId: article,
                  facings: 2,
                ),
              ],
            ),
          ],
        ),
      );
      expect(await c.saveDraft(), LayoutCommandOutcome.confirmed);
      expect(await c.publish(), LayoutCommandOutcome.confirmed);
      final first = c.revision!;
      final chosen = c.planogram!;
      await c.selectPlanogram(chosen);
      fault.lose = true;
      expect(await c.assign(first), LayoutCommandOutcome.uncertain);
      final pending = c.pending!;
      expect(await c.retryPending(), LayoutCommandOutcome.confirmed);
      expect(fault.bodies.last, pending.body);
      await c.openFixture(c.fixture!);
      expect(c.view!.revision!.id, first.id);
      expect(c.view!.stockContextStatus, expectedStockStatus);
      expect(
        c.view!.revision!.content.zones.single.placements.single.facings,
        2,
      );
      final oldAssignment = c.view!.assignment!.id;
      final print = await c.printView(oldAssignment);
      expect(print!.html, contains('A4 landscape'));
      expect(print.html, contains('&lt;&gt;&amp;'));
      expect(print.html, isNot(contains('Bestand')));
      await c.selectPlanogram(chosen);
      expect(await c.newDraft(), LayoutCommandOutcome.confirmed);
      c.setEditing(LayoutContent(title: 'Brot zwei', zones: c.editing!.zones));
      expect(await c.saveDraft(), LayoutCommandOutcome.confirmed);
      expect(await c.publish(), LayoutCommandOutcome.confirmed);
      final second = c.revision!;
      await c.openFixture(c.fixture!);
      expect(c.view!.revision!.id, first.id);
      expect(await c.assign(second), LayoutCommandOutcome.confirmed);
      await c.openFixture(c.fixture!);
      expect(c.view!.revision!.id, second.id);
      await c.loadHistory();
      expect(c.history, hasLength(2));
      expect(
        (await c.printView(oldAssignment))!.html,
        contains('Historische Zuweisung'),
      );
      final worker = SessionController(
        HttpStoreApi(baseUri: base, client: client),
      );
      final workerPlatform = PlatformController(worker, transport);
      final read = MerchandisingController(worker, workerPlatform, transport);
      addTearDown(() {
        read.dispose();
        workerPlatform.dispose();
        worker.dispose();
      });
      await worker.signIn(
        username: 'planogram_worker',
        password: Platform.environment['STOREOS_PLANOGRAM_JOURNEY_PASSWORD']!,
      );
      await read.load();
      await read.openFixture(read.fixtures.single);
      expect(read.view!.revision!.id, second.id);
      expect(read.view!.stockContextStatus, expectedStockStatus);
      expect(read.view!.revision!.content.title, 'Brot zwei');
      expect(
        read.view!.revision!.content.zones.single.placements.single.facings,
        2,
      );
      expect(
        (await read.printView(read.view!.assignment!.id))!.revisionId,
        second.id,
      );
    },
  );
}

class _LostResponse implements PlatformApi {
  _LostResponse(this.real);
  final PlatformApi real;
  bool lose = false;
  final List<Map<String, dynamic>> bodies = [];
  @override
  Future<Map<String, dynamic>> get(
    String t,
    String r, {
    String? after,
    Map<String, String>? query,
  }) => real.get(t, r, after: after, query: query);
  @override
  Future<Map<String, dynamic>> post(
    String t,
    String r,
    Map<String, dynamic> b,
  ) async {
    bodies.add(b);
    final result = await real.post(t, r, b);
    if (lose) {
      lose = false;
      throw const StoreApiException(
        'network_unavailable',
        'Committed response intentionally lost.',
      );
    }
    return result;
  }
}
