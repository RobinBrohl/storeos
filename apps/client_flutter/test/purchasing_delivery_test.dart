import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_client/src/application/purchasing_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/purchasing_delivery_dialog.dart';
import 'purchasing_test.dart'
    show Auth, Api, setup, ready, document, order, line, supplier;

class DeliveryApi extends Api {
  int ledger = 0, revision = 0;
  String orderStatus = 'issued';
  int orderVersion = 3;
  final registerQueries = <Map<String, String>>[];
  Map<String, dynamic>? delivery;
  Map<String, dynamic> get summary => {
    'orderId': order,
    'ledgerVersion': ledger,
    'declarationCount': revision == 0 ? 0 : 1,
    'lines': [
      {
        'orderLineId': line,
        'orderedQuantity': '2.500',
        'effectiveDelivered': revision == 0 ? '0.000' : '1.000',
        'recordedRemainder': revision == 0 ? '2.500' : '1.500',
        'overdelivery': '0.000',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route.endsWith('/$order')) {
      if (readHold != null) return readHold!.future;
      if (refreshFail) {
        throw const StoreApiException(
          'database_unavailable',
          'Unavailable',
          statusCode: 503,
        );
      }
      return {...document, 'status': orderStatus, 'version': orderVersion};
    }
    if (route.endsWith('/delivery-register')) {
      registerQueries.add(Map.of(query!));
      return {
        'items': query['status'] == orderStatus
            ? [
                {'id': order, 'status': orderStatus, 'summary': summary},
              ]
            : <Map<String, dynamic>>[],
        'nextCursor': 'register-page-${registerQueries.length}',
      };
    }
    if (route.endsWith('/delivery-summary')) {
      return {
        'summary': summary,
        'terminalSnapshot': null,
        'trackingAtClosure': 'not_terminal',
      };
    }
    if (route.endsWith('/deliveries')) {
      return {
        'items': [?delivery],
        'nextCursor': null,
      };
    }
    if (route.contains('/deliveries/')) return delivery!;
    return super.get(token, route, after: after, query: query);
  }

  @override
  Future<Map<String, dynamic>> write(
    String route,
    Map<String, dynamic> body,
  ) async {
    if (!route.contains('/deliveries')) {
      final result = await super.write(route, body);
      if (route.endsWith('/close')) {
        orderStatus = 'closed';
        orderVersion++;
        return {
          ...result,
          'order': {
            ...document,
            'status': orderStatus,
            'version': orderVersion,
          },
        };
      }
      return result;
    }
    routes.add(route);
    bodies.add(body);
    if (hold != null) return hold!.future;
    if (failure != null) throw failure!;
    ledger++;
    revision++;
    delivery = {
      'deliveryId': body['deliveryId'] ?? delivery!['deliveryId'],
      'orderId': order,
      'revision': revision,
      'ledgerVersion': ledger,
      'localReference': body['localReference'] ?? delivery!['localReference'],
      'lines': body['lines'] ?? [],
    };
    return {'delivery': delivery, 'summary': summary, 'replayed': false};
  }
}

void main() {
  for (final action in ['declare', 'close']) {
    test(
      'confirmed $action invalidates loaded register and cursor but preserves filters',
      () async {
        final api = DeliveryApi();
        final (_, _, c) = await setup(Auth(), api);
        c.status = 'issued';
        c.supplierFilter = supplier;
        c.setDeliveryQuery('Literal');
        await c.loadDeliveryRegister();
        expect(c.deliveryRegisterItems.single['summary']['ledgerVersion'], 0);
        expect(c.deliveryRegisterCursor, isNotNull);
        final outcome = action == 'declare'
            ? await c.deliveryCommand(
                'declare',
                reference: 'Local',
                lines: [
                  {'orderLineId': line, 'quantity': '1'},
                ],
              )
            : await c.lifecycle('close', reason: 'Administrative close');
        expect(outcome, PurchasingOutcome.confirmed);
        expect(c.deliveryRegisterItems, isEmpty);
        expect(c.deliveryRegisterCursor, isNull);
        expect(c.status, 'issued');
        expect(c.supplierFilter, supplier);
        expect(c.deliveryQuery, 'Literal');
        await c.loadDeliveryRegister(more: true);
        expect(api.registerQueries.last, {
          'status': 'issued',
          'supplierId': supplier,
          'q': 'Literal',
        });
        if (action == 'declare') {
          expect(c.deliveryRegisterItems.single['summary']['ledgerVersion'], 1);
        } else {
          expect(c.deliveryRegisterItems, isEmpty);
        }
      },
    );
  }
  for (final user in ['admin', 'other']) {
    testWidgets(
      'mounted delivery dialog immediately clears frozen labels and text on $user replacement',
      (t) async {
        final api = DeliveryApi();
        final (s, p, c) = await setup(Auth(), api);
        await t.pumpWidget(
          MaterialApp(
            home: PurchasingDeliveryDialog(controller: c, action: 'declare'),
          ),
        );
        await t.enterText(
          find.byKey(const Key('delivery-reference')),
          'Private local reference',
        );
        await t.enterText(
          find.byKey(const Key('delivery-reason')),
          'Private operator reason',
        );
        await s.signIn(username: user, password: 'test');
        await ready(p);
        await t.pumpAndSettle();
        expect(
          t
              .widget<TextField>(find.byKey(const Key('delivery-reference')))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          t
              .widget<TextField>(find.byKey(const Key('delivery-reason')))
              .controller!
              .text,
          isEmpty,
        );
        expect(find.textContaining('ordered 2.500'), findsNothing);
        expect(
          t
              .widget<TextButton>(find.byKey(const Key('delivery-confirm')))
              .onPressed,
          isNull,
        );
        expect(t.takeException(), null);
        await s.signOut();
        await t.pumpAndSettle();
        await t.pumpWidget(const SizedBox());
      },
    );
  }
  test(
    'delivery intent deeply frozen and guarded; uncertain retry retains exact body and route',
    () async {
      final api = DeliveryApi();
      final (_, _, c) = await setup(Auth(), api);
      final lines = [
        {'orderLineId': line, 'quantity': '1'},
      ];
      api.failure = const StoreApiException(
        'database_unavailable',
        'Lost response',
        statusCode: 503,
      );
      expect(
        await c.deliveryCommand('declare', reference: 'Local', lines: lines),
        PurchasingOutcome.uncertain,
      );
      final first = api.bodies.single, route = api.routes.single;
      lines[0]['quantity'] = '2';
      expect(first['lines'][0]['quantity'], '1.000');
      expect(
        await c.deliveryCommand('declare', reference: 'Changed', lines: lines),
        PurchasingOutcome.busy,
      );
      api.failure = const StoreApiException(
        'forbidden',
        'Revoked',
        statusCode: 403,
      );
      expect(await c.retry(), PurchasingOutcome.uncertain);
      expect(c.pending, isNotNull);
      api.failure = null;
      expect(await c.retry(), PurchasingOutcome.confirmed);
      expect(api.bodies.every((body) => identical(body, first)), true);
      expect(api.routes.every((v) => v == route), true);
      expect(c.lastConfirmed!['delivery']['revision'], 1);
      expect(c.pending, isNull);
    },
  );
  test(
    'confirmed declaration survives failed current refresh and clears actionable state',
    () async {
      final api = DeliveryApi();
      final (_, _, c) = await setup(Auth(), api);
      c.status = 'issued';
      await c.loadDeliveryRegister();
      expect(c.deliveryRegisterItems, isNotEmpty);
      api.refreshFail = true;
      expect(
        await c.deliveryCommand(
          'declare',
          reference: 'Local',
          lines: [
            {'orderLineId': line, 'quantity': '1'},
          ],
        ),
        PurchasingOutcome.confirmed,
      );
      expect(c.lastConfirmed, isNotNull);
      expect(c.detail, isNull);
      expect(c.deliverySummary, isNull);
      expect(c.refreshWarning, isNotNull);
      expect(c.pending, isNull);
      expect(c.deliveryRegisterItems, isEmpty);
      expect(c.deliveryRegisterCursor, isNull);
    },
  );
  for (final username in ['admin', 'other']) {
    test(
      '$username opaque session replacement fences held delivery write and all resident fields',
      () async {
        final api = DeliveryApi();
        final (s, p, c) = await setup(Auth(), api);
        api.hold = Completer<Map<String, dynamic>>();
        final write = c.deliveryCommand(
          'declare',
          reference: 'Secret',
          lines: [
            {'orderLineId': line, 'quantity': '1'},
          ],
        );
        await Future<void>.delayed(Duration.zero);
        c.deliveryRegisterItems = [
          {'id': order},
        ];
        c.deliveryRegisterCursor = 'old-page';
        c.deliveryQuery = 'Secret';
        await s.signIn(username: username, password: 'test');
        await ready(p);
        expect(c.pending, isNull);
        expect(c.detail, isNull);
        expect(c.deliveryDetail, isNull);
        expect(c.deliveryQuery, isEmpty);
        expect(c.deliveryRegisterItems, isEmpty);
        expect(c.deliveryRegisterCursor, isNull);
        c.status = 'issued';
        c.setDeliveryQuery('Replacement');
        await c.loadDeliveryRegister();
        final replacementRows = c.deliveryRegisterItems,
            replacementCursor = c.deliveryRegisterCursor;
        api.hold!.complete({
          'delivery': {'orderId': order, 'deliveryId': order},
          'summary': {},
          'replayed': false,
        });
        expect(await write, PurchasingOutcome.fenced);
        expect(c.lastConfirmed, isNull);
        expect(c.deliveryRegisterItems, same(replacementRows));
        expect(c.deliveryRegisterCursor, replacementCursor);
        expect(c.deliveryQuery, 'Replacement');
      },
    );
  }
  test(
    'definitive validation rejection retains selected authoritative detail',
    () async {
      final api = DeliveryApi();
      final (_, _, c) = await setup(Auth(), api);
      expect(
        await c.deliveryCommand(
          'declare',
          reference: 'Local',
          lines: [
            {'orderLineId': line, 'quantity': '0'},
          ],
        ),
        PurchasingOutcome.rejected,
      );
      expect(c.detail, isNotNull);
      expect(c.pending, isNull);
      expect(api.bodies, isEmpty);
    },
  );
}
