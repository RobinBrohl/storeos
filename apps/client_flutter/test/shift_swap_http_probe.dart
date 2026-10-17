import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/shift_swap_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

// Explicitly launched by the isolated backend test, outside the default suite.
void main() {
  test(
    'real HTTP request/approval response loss and exact receipt replay',
    () async {
      final env = Platform.environment,
          base = Uri.parse(env['STOREOS_SWAP_PROBE_URL']!);
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client);
      final controllers = <ShiftSwapController>[];
      Future<ShiftSwapController> actor(
        String username, {
        bool self = true,
      }) async {
        final session = SessionController(
          HttpStoreApi(baseUri: base, client: client),
        );
        final platform = PlatformController(session, api);
        final c = ShiftSwapController(session, platform, api, self: self);
        controllers.add(c);
        final ready = Completer<void>();
        void changed() {
          if (!platform.isBusy &&
              platform.organization != null &&
              !ready.isCompleted) {
            ready.complete();
          }
        }

        platform.addListener(changed);
        await session.signIn(
          username: username,
          password: 'stock-test-only-password-strong',
        );
        changed();
        await ready.future.timeout(const Duration(seconds: 10));
        platform.removeListener(changed);
        return c;
      }

      addTearDown(() {
        for (final c in controllers) {
          c.dispose();
          c.platform.dispose();
          c.session.dispose();
        }
        client.close();
      });
      final a = await actor('swap_fixture_a'),
          b = await actor('swap_fixture_b');
      final manager = await actor('test_admin', self: false);
      final own = await a.session.authorized(
        (token) => api.get(
          token,
          '/employee-home/shifts/${env['STOREOS_SWAP_PROBE_SHIFT']}',
        ),
      );
      await a.chooseSource(
        ShiftDto.fromJson(own['shift'] as Map<String, dynamic>),
      );
      a.chooseColleague(env['STOREOS_SWAP_PROBE_RECIPIENT']);
      expect(await a.request(), SwapOutcome.uncertain);
      final intended = a.pending!;
      expect(await a.retry(), SwapOutcome.confirmed);
      expect(a.lastConfirmed!.json['statusCode'], 201);
      expect(a.lastConfirmed!.json['replayed'], true);
      final id = intended.requestId;
      await b.select(id);
      await b.loadCounterparts();
      await b.chooseCounterpart(env['STOREOS_SWAP_PROBE_COUNTERPART']!);
      expect(await b.act('offer'), SwapOutcome.confirmed);
      await a.select(id);
      expect(await a.act('confirm'), SwapOutcome.confirmed);
      await manager.select(id);
      expect(manager.can('manager_approve'), true);
      expect(await manager.act('approve'), SwapOutcome.uncertain);
      final approval = manager.pending!;
      expect(await manager.retry(), SwapOutcome.confirmed);
      expect(manager.lastConfirmed!.json['replayed'], true);
      expect(manager.lastConfirmed!.json['operationId'], approval.operationId);
      expect(manager.detail!.json['request']['status'], 'approved');
      expect(await manager.act('approve'), SwapOutcome.rejected);
      await manager.loadHistory(id);
      await manager.loadHistory(id, more: true);
      expect(manager.history, hasLength(4));
      final legs = manager.lastConfirmed!.request.json['legs'] as List;
      expect(legs.map((l) => l['replacementShiftId']).toSet(), hasLength(2));
      for (final leg in legs) {
        expect(leg['taskLinks'], hasLength(1));
        expect(leg['taskLinks'][0]['sourceTaskId'], leg['tasks'][0]['id']);
      }
    },
  );
}
