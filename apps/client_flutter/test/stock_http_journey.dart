// Invoked by the isolated server Stock integration fixture, not test discovery.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/stock_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';

void main() {
  test('real controller / HTTP / PostgreSQL correction journey', () async {
    final base = Uri.parse(Platform.environment['STOREOS_STOCK_JOURNEY_URL']!);
    if (base.host != '127.0.0.1') {
      throw StateError('Loopback fixture required.');
    }
    final client = http.Client();
    final transport = HttpPlatformApi(baseUri: base, client: client);
    final faults = _ResponseFaults(transport);
    final session = SessionController(
      HttpStoreApi(baseUri: base, client: client),
    );
    final platform = PlatformController(session, transport);
    final stock = StockController(session, platform, faults);
    addTearDown(() {
      stock.dispose();
      platform.dispose();
      session.dispose();
      client.close();
    });
    final initial = Completer<void>();
    void loaded() {
      if (!platform.isBusy &&
          platform.organization != null &&
          !initial.isCompleted) {
        initial.complete();
      }
    }

    platform.addListener(loaded);
    await session.signIn(
      username: 'test_admin',
      password: 'stock-test-only-password-strong',
    );
    expect(session.isAuthenticated, isTrue);
    loaded();
    await initial.future.timeout(const Duration(seconds: 10));
    platform.removeListener(loaded);
    expect(stock.canManage, isTrue);
    final location = Platform.environment['STOREOS_STOCK_JOURNEY_LOCATION']!;
    await stock.selectLocation(location);
    expect(stock.items, hasLength(1));
    final levelId = stock.items!.single.id;
    final route = '/locations/$location/stock/$levelId/adjust';
    int externalId = 100;
    Future<void> advance(int version, String quantity) => session.authorized((
      token,
    ) async {
      await transport.post(token, route, {
        'movementId':
            '00000000-0000-4000-8000-${(++externalId).toString().padLeft(12, '0')}',
        'expectedVersion': version,
        'quantity': quantity,
        'note': 'Later command',
      });
    });

    faults.loseCommittedResponse = true;
    final uncertain = await stock.adjust(
      stock.items!.single,
      '12.500',
      ' first ',
    );
    expect(uncertain.outcome, StockAdjustmentOutcome.unconfirmed);
    final committed = stock.pendingAdjustment!;
    await advance(2, '20');
    faults.loseCommittedResponse = false;
    expect(
      (await stock.retryPendingAdjustment()).outcome,
      StockAdjustmentOutcome.confirmedMutation,
    );
    expect(faults.bodies.last, committed.input.toJson());
    expect(stock.items!.single.version, 3);
    expect(stock.items!.single.quantity, '20');

    faults.dropBeforeSend = true;
    expect(
      (await stock.adjust(stock.items!.single, '21', 'not sent')).outcome,
      StockAdjustmentOutcome.unconfirmed,
    );
    final unused = stock.pendingAdjustment!;
    await advance(3, '21');
    await stock.load();
    expect(stock.pendingAdjustment, same(unused));
    faults.dropBeforeSend = false;
    expect(
      (await stock.retryPendingAdjustment()).outcome,
      StockAdjustmentOutcome.conflict,
    );
    expect(faults.bodies.last, unused.input.toJson());
    expect(stock.pendingAdjustment, isNull);
    expect(stock.error, contains('stock_conflict'));
    await stock.prepareNewAdjustment();
    expect(
      (await stock.adjust(
        stock.items!.single,
        '21',
        'already matches',
      )).outcome,
      StockAdjustmentOutcome.confirmedNoOp,
    );
    faults.failList = true;
    final confirmed = await stock.adjust(stock.items!.single, '22', 'last');
    expect(confirmed.outcome, StockAdjustmentOutcome.confirmedMutation);
    expect(confirmed.refreshFailed, isTrue);
    expect(stock.pendingAdjustment, isNull);
    final sent = faults.bodies.length;
    await stock.retryPendingAdjustment();
    expect(faults.bodies, hasLength(sent));
    faults.failList = false;
    await stock.load();
    expect(stock.items!.single.quantity, '22');
    expect(stock.items!.single.version, 5);
  });
}

class _ResponseFaults implements PlatformApi {
  _ResponseFaults(this.real);
  final PlatformApi real;
  bool loseCommittedResponse = false, dropBeforeSend = false, failList = false;
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) {
    if (failList && route.endsWith('/stock')) {
      throw const StoreApiException(
        'network_unavailable',
        'List response lost',
      );
    }
    return real.get(token, route, after: after, query: query);
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    bodies.add(Map.of(body));
    if (dropBeforeSend) throw const StoreApiException('timeout', 'Not sent');
    final result = await real.post(token, route, body);
    if (loseCommittedResponse) {
      throw const StoreApiException('timeout', 'Committed response lost');
    }
    return result;
  }
}
