import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/preparation_assignment_controller.dart';
import 'package:storeos_client/src/application/preparation_batch_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

void main() {
  test(
    'real assignment manager selection, retained R1 start/restart retry and linked actual/correction evidence',
    () async {
      final env = Platform.environment,
          base = Uri.parse(Platform.environment['STOREOS_ASSIGNMENT_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client),
          auth = HttpStoreApi(baseUri: base, client: client);
      final manager = SessionController(auth),
          worker = SessionController(auth),
          mp = PlatformController(manager, api),
          wp = PlatformController(worker, api);
      final m = PreparationAssignmentController(manager, mp, api),
          w = PreparationAssignmentController(worker, wp, api, self: true),
          mb = PreparationBatchController(manager, mp, api, self: false),
          wb = PreparationBatchController(worker, wp, api);
      addTearDown(() {
        m.dispose();
        w.dispose();
        mb.dispose();
        wb.dispose();
        mp.dispose();
        wp.dispose();
        manager.dispose();
        worker.dispose();
        client.close();
      });
      Future<void> ready(PlatformController p) async {
        final c = Completer<void>();
        void changed() {
          if (p.organization != null && !p.isBusy && !c.isCompleted) {
            c.complete();
          }
        }

        p.addListener(changed);
        changed();
        await c.future.timeout(const Duration(seconds: 10));
        p.removeListener(changed);
      }

      await manager.signIn(
        username: 'test_admin',
        password: 'stock-test-only-password-strong',
      );
      await ready(mp);
      await m.choices();
      m.choose(
        m.recipes.singleWhere(
          (r) => r.recipe == env['STOREOS_ASSIGNMENT_RECIPE'],
        ),
      );
      await m.assignees();
      m.chooseEmployee(
        m.employees.singleWhere(
          (e) => e['id'] == env['STOREOS_ASSIGNMENT_EMPLOYEE'],
        ),
      );
      expect(await m.create(3), AssignmentOutcome.confirmed);
      final id = m.confirmedId!;
      await worker.signIn(
        username: 'assignment_worker',
        password: 'stock-test-only-password-strong',
      );
      await ready(wp);
      await w.load();
      expect(w.items.single.id, id);
      await w.select(id);
      await w.readInstruction();
      expect(w.instruction!['revisionNumber'], 1);
      expect(w.instruction!['warnings'], contains('recipe_replaced'));
      expect(
        (w.instruction!['content'] as Map)['batchDescription'],
        'one 30 × 40 cm tray',
      );
      expect(await w.start(), AssignmentOutcome.uncertain);
      final pending = w.pending!;
      expect(await w.retry(), AssignmentOutcome.confirmed);
      expect(w.lastConfirmed!['replayed'], true);
      final batchId = w.detail!.batchId!;
      await wb.select(batchId);
      expect(
        await wb.complete(2, 'Actual literal <script> 😀'),
        PreparationOutcome.confirmed,
      );
      await mb.select(batchId);
      expect(mb.detail!.actual, 2);
      for (final count in [1, 0]) {
        expect(
          await mb.correct(count, 'Reviewed correction $count <script> 😀'),
          PreparationOutcome.confirmed,
        );
        expect(mb.detail!.effective, count);
        expect(mb.detail!.actual, 2);
      }
      await m.select(id);
      await m.readHistory();
      expect(m.detail!.status, 'started');
      expect(m.detail!.planned, 3);
      expect(
        (m.detail!.json['batch'] as Map)['effectiveDeclaredBatchCount'],
        0,
      );
      expect(pending.body.keys.toSet(), {'operationId', 'expectedVersion'});
    },
  );
}
