import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/preparation_batch_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

void main() {
  test(
    'real declarations, historical instruction, exact retry and effective-zero evidence',
    () async {
      final env = Platform.environment,
          base = Uri.parse(Platform.environment['STOREOS_PREPARATION_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client);
      final worker = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          ),
          manager = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          );
      final wp = PlatformController(worker, api),
          mp = PlatformController(manager, api),
          w = PreparationBatchController(worker, wp, api),
          m = PreparationBatchController(manager, mp, api, self: false);
      addTearDown(() {
        w.dispose();
        m.dispose();
        wp.dispose();
        mp.dispose();
        worker.dispose();
        manager.dispose();
        client.close();
      });
      Future<void> ready(PlatformController p) async {
        final wait = Completer<void>();
        void changed() {
          if (p.organization != null && !p.isBusy && !wait.isCompleted) {
            wait.complete();
          }
        }

        p.addListener(changed);
        changed();
        await wait.future.timeout(const Duration(seconds: 10));
        p.removeListener(changed);
      }

      await worker.signIn(
        username: 'batch_worker',
        password: 'stock-test-only-password-strong',
      );
      await ready(wp);
      await manager.signIn(
        username: 'test_admin',
        password: 'stock-test-only-password-strong',
      );
      await ready(mp);
      await w.choices();
      w.choose(
        w.recipes.singleWhere(
          (r) => r.recipe == env['STOREOS_PREPARATION_RECIPE'],
        ),
      );
      expect(w.selection!.content.batchDescription, 'one 30 × 40 cm tray');
      expect(w.selection!.content.ingredients.single.quantity, '1.250');
      expect(await w.open(3), PreparationOutcome.confirmed);
      final id = w.detail!.id;
      await w.select(id);
      await w.readInstruction();
      expect(w.instruction!['revisionNumber'], 1);
      expect(w.instruction!['warnings'], contains('recipe_retired'));
      expect(
        await w.complete(2, 'Literal completion <script> 😀'),
        PreparationOutcome.uncertain,
      );
      final pending = w.pending!;
      expect(await w.retry(), PreparationOutcome.confirmed);
      expect(w.lastConfirmed!['replayed'], true);
      await m.select(id);
      expect(m.detail!.actual, 2);
      expect(m.detail!.json['plannedDeclaredBatchCount'], 3);
      expect(
        await m.correct(1, 'Manager reviewed count <script> 😀'),
        PreparationOutcome.confirmed,
      );
      expect(m.detail!.effective, 1);
      final replay = await worker.authorized(
        (token) => api.post(token, pending.route, pending.body),
      );
      expect((replay['batch'] as Map)['actualDeclaredBatchCount'], 2);
      await w.select(id);
      expect(w.detail!.effective, 1);
      await m.select(env['STOREOS_PREPARATION_ZERO']!);
      expect(m.detail!.actual, 1);
      expect(
        await m.correct(0, 'Reported completion in error <script> 😀'),
        PreparationOutcome.confirmed,
      );
      expect(m.detail!.status, 'completed');
      expect(m.detail!.actual, 1);
      expect(m.detail!.effective, 0);
    },
  );
}
