import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:storeos_client/src/application/purchasing_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/http_platform_api.dart';
import 'package:storeos_client/src/data/http_store_api.dart';

void main() {
  test(
    'complete real Purchasing flow with two exact quantities, stale rejection, frozen replay and closure',
    () async {
      final env = Platform.environment,
          base = Uri.parse(env['STOREOS_PURCHASING_URL']!);
      expect(base.host, '127.0.0.1');
      final client = http.Client(),
          api = HttpPlatformApi(baseUri: base, client: client),
          s = SessionController(HttpStoreApi(baseUri: base, client: client)),
          p = PlatformController(s, api),
          c = PurchasingController(s, p, api);
      addTearDown(() {
        c.dispose();
        p.dispose();
        s.dispose();
        client.close();
      });
      final ready = Completer<void>();
      void changed() {
        if (p.organization != null && !p.isBusy && !ready.isCompleted) {
          ready.complete();
        }
      }

      p.addListener(changed);
      await s.signIn(
        username: 'test_admin',
        password: env['STOREOS_KNOWLEDGE_PASSWORD']!,
      );
      changed();
      await ready.future.timeout(const Duration(seconds: 10));
      p.removeListener(changed);
      expect(
        await c.supplierCreate(
          'Literal <a href="https://invalid.example/p412">Supplier 😀',
          'CUSTOMER',
        ),
        PurchasingOutcome.confirmed,
      );
      final supplier = c.supplierDetail!;
      c.newDraft();
      c.chooseSupplier(supplier);
      c.reference = 'P412 controller';
      expect(await c.create(), PurchasingOutcome.confirmed);
      await c.articleChoices();
      c.addArticle(
        c.articles.firstWhere((a) => a['id'] == env['STOREOS_PURCHASING_A']),
      );
      c.addArticle(
        c.articles.firstWhere((a) => a['id'] == env['STOREOS_PURCHASING_B']),
      );
      c.quantity(c.lines[0]['id'] as String, '2.5');
      c.quantity(c.lines[1]['id'] as String, '12');
      expect(await c.save(), PurchasingOutcome.confirmed);
      expect(c.detail!['lines'].map((l) => l['quantity']).toList(), [
        '2.500',
        '12.000',
      ]);
      c.reviewSaved();
      expect(await c.lifecycle('issue'), PurchasingOutcome.rejected);
      expect(c.error, contains('article_unit_changed'));
      expect(c.detail!['status'], 'draft');
      await c.articleChoices();
      c.reselectArticle(
        c.lines[0]['id'] as String,
        c.articles.firstWhere((a) => a['id'] == env['STOREOS_PURCHASING_A']),
      );
      expect(await c.save(), PurchasingOutcome.confirmed);
      c.reviewSaved();
      expect(await c.lifecycle('issue'), PurchasingOutcome.uncertain);
      final pending = c.pending!;
      expect(await c.retry(), PurchasingOutcome.confirmed);
      expect(c.lastConfirmed!['replayed'], true);
      final frozen = c.detail!;
      await c.selectSupplier(supplier['id'] as String);
      expect(
        await c.supplierEdit('Later supplier', 'LATER'),
        PurchasingOutcome.confirmed,
      );
      expect(await c.supplierRetire(), PurchasingOutcome.confirmed);
      expect(c.supplierDetail!['status'], 'retired');
      expect(c.detail!['supplier'], frozen['supplier']);
      final deliveryLine = c.detail!['lines'][1]['id'] as String;
      Future<PurchasingOutcome> declare(
        String reference,
        String quantity, {
        String? reason,
      }) => c.deliveryCommand(
        'declare',
        reference: reference,
        reason: reason,
        lines: [
          {'orderLineId': deliveryLine, 'quantity': quantity},
        ],
      );
      expect(
        await declare('Delivery A <script>', '5'),
        PurchasingOutcome.uncertain,
      );
      final deliveryPending = c.pending!;
      expect(await c.retry(), PurchasingOutcome.confirmed);
      final deliveryA = c.deliveryDetail!['deliveryId'] as String;
      expect(await declare('Delivery B', '7'), PurchasingOutcome.confirmed);
      expect(
        await declare('Delivery extra', '1', reason: 'Accepted excess'),
        PurchasingOutcome.confirmed,
      );
      expect(
        await c.deliveryCommand('void', reason: 'Mistaken duplicate'),
        PurchasingOutcome.confirmed,
      );
      await c.selectDelivery(deliveryA);
      expect(
        await c.deliveryCommand(
          'correct',
          reason: 'Correct to four',
          lines: [
            {'orderLineId': deliveryLine, 'quantity': '4'},
          ],
        ),
        PurchasingOutcome.confirmed,
      );
      expect(
        await c.deliveryCommand(
          'correct',
          reason: 'Restore measured five',
          lines: [
            {'orderLineId': deliveryLine, 'quantity': '5'},
          ],
        ),
        PurchasingOutcome.confirmed,
      );
      expect(
        await c.lifecycle(
          'close',
          reason: 'Administrative completion <script> 😀',
        ),
        PurchasingOutcome.confirmed,
      );
      await c.readHistory();
      expect(c.history.map((h) => h['kind']), [
        'order_create',
        'order_save',
        'order_save',
        'order_issue',
        'order_close',
      ]);
      final result = await s.authorized(
        (token) => api.post(token, pending.route, pending.body),
      );
      expect(result['order'], frozen);
      expect(result['replayed'], true);
      await c.select(frozen['id'] as String);
      expect(c.detail!['status'], 'closed');
      await c.selectDelivery(deliveryA);
      expect(
        await c.deliveryCommand(
          'correct',
          reason: 'After closure correction',
          lines: [
            {'orderLineId': deliveryLine, 'quantity': '4'},
          ],
        ),
        PurchasingOutcome.confirmed,
      );
      expect(
        c.deliverySummary!['summary']['lines'][1]['effectiveDelivered'],
        '11.000',
      );
      expect(
        c.deliverySummary!['terminalSnapshot']['summary']['lines'][1]['effectiveDelivered'],
        '12.000',
      );
      final deliveryReplay = await s.authorized(
        (token) => api.post(token, deliveryPending.route, deliveryPending.body),
      );
      expect(deliveryReplay['delivery']['lines'][0]['quantity'], '5.000');
      expect(
        deliveryReplay['summary']['lines'][1]['effectiveDelivered'],
        '5.000',
      );
      expect(deliveryReplay['replayed'], true);
      await s.signOut();
    },
  );
}
