// Opt-in real adapters/controllers, invoked by the isolated server fixture.
import 'dart:async';

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/stock_count_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test(
    'real Flutter / HTTP / PostgreSQL two-line stale/recount/mixed approval and lost response',
    () async {
      final env = Platform.environment;
      final base = Uri.parse(env['STOREOS_COUNT_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client();
      final api = HttpPlatformApi(baseUri: base, client: client);
      final faults = Faults(api);
      final manager = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          ),
          worker = SessionController(
            HttpStoreApi(baseUri: base, client: client),
          );
      final mp = PlatformController(manager, api),
          wp = PlatformController(worker, api);
      final m = StockCountController(manager, mp, faults),
          w = StockCountController(worker, wp, api, self: true);
      addTearDown(() {
        m.dispose();
        w.dispose();
        mp.dispose();
        wp.dispose();
        manager.dispose();
        worker.dispose();
        client.close();
      });
      await manager.signIn(
        username: 'test_admin',
        password: 'stock-test-only-password-strong',
      );
      await worker.signIn(
        username: 'p48_worker',
        password: 'stock-test-only-password-strong',
      );
      Future<void> ready(PlatformController p) async {
        final complete = Completer<void>();
        void changed() {
          if (!p.isBusy && p.organization != null && !complete.isCompleted) {
            complete.complete();
          }
        }

        p.addListener(changed);
        try {
          changed();
          await complete.future.timeout(const Duration(seconds: 10));
        } finally {
          p.removeListener(changed);
        }
      }

      await Future.wait([ready(mp), ready(wp)]);
      expect(
        await m.open(env['STOREOS_COUNT_EMPLOYEE']!, [
          env['STOREOS_COUNT_A']!,
          env['STOREOS_COUNT_B']!,
        ], 'Physical <script>literal</script>'),
        true,
      );
      final id = m.selectedId!;
      await w.select(id);
      expect(w.employeeDetail!.lines.map((l) => l.stockUnit), ['kg', 'Stk']);
      expect(await w.record(w.employeeDetail!.lines[0], '9', null), true);
      expect(await w.record(w.employeeDetail!.lines[1], '5', null), true);
      final stock =
          '/locations/${manager.user!.locationId}/stock/${env['STOREOS_COUNT_A']}';
      await manager.authorized(
        (token) => api.post(token, '$stock/adjust', {
          'movementId': '00000000-0000-4000-8000-000000000001',
          'expectedVersion': 1,
          'quantity': '12',
          'note': 'Normal correction during counting',
        }),
      );
      await m.select(id);
      expect(m.managerDetail!.lines[0]['stale'], true);
      expect(await m.approve(), false);
      expect(m.error, contains('Nachzählung'));
      expect(
        await m.recount([
          m.managerDetail!.lines[0]['id'] as String,
        ], 'Fresh physical count'),
        true,
      );
      await w.select(id);
      expect(w.employeeDetail!.lines[0].round.number, 2);
      expect(w.employeeDetail!.lines[0].round.observation, isNull);
      expect(await w.record(w.employeeDetail!.lines[0], '11', null), true);
      await m.select(id);
      faults.lose = true;
      expect(await m.approve(), false);
      final pending = m.pending!;
      final originalBody = pending.body;
      await manager.authorized(
        (token) => api.post(token, '$stock/adjust', {
          'movementId': '00000000-0000-4000-8000-000000000002',
          'expectedVersion': 3,
          'quantity': '13',
          'note': 'Later supported correction',
        }),
      );
      faults.lose = false;
      expect(await m.retry(), true);
      expect(faults.bodies.last, originalBody);
      expect(m.lastConfirmed!['lines'][0]['currentStock']['quantity'], '11');
      expect(m.managerDetail!.lines[0]['currentStock']['quantity'], '13');
      expect(m.managerDetail!.lines[1]['outcome']['movementId'], isNull);
      expect(m.managerDetail!.lines[1]['currentStock']['version'], 1);
      final history = (await w.history(
        id,
        w.employeeDetail!.lines[0].id,
      )).single;
      expect(history['items'], hasLength(2));
      final current = await manager.authorized(
        (token) => api.get(token, stock),
      );
      expect(current['quantity'], '13');
      expect(current['version'], 4);
    },
  );
}

class Faults implements PlatformApi {
  Faults(this.real);
  final PlatformApi real;
  bool lose = false;
  final bodies = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) => real.get(token, route, after: after, query: query);
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map.of(body));
    final result = await real.post(token, route, body);
    if (lose) {
      throw const StoreApiException('timeout', 'Committed response lost');
    }
    return result;
  }
}
