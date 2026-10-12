import 'dart:convert';
import 'purchasing.dart';

const purchasingDeliveryMaxQuantity = 999999999999999;

int purchasingLedgerVersion(Object? value) {
  if (value is! int || value < 0 || value > purchasingMaxVersion) {
    purchasingInvalid('Expected Web-safe nonnegative ledger version.');
  }
  return value;
}

/// Complete, canonical, deeply immutable delivery command intent.
class PurchasingDeliveryInput {
  PurchasingDeliveryInput._(this.kind, Map<String, dynamic> value)
    : payload = purchasingFreeze(value) as Map<String, dynamic>;

  factory PurchasingDeliveryInput.fromJson(
    String kind,
    Map<String, dynamic> j,
  ) {
    final keys = <String>{
      'operationId',
      'expectedOrderVersion',
      'expectedLedgerVersion',
      'reason',
      if (kind == 'delivery_declare') ...{'deliveryId', 'localReference'},
      if (kind != 'delivery_declare') 'expectedRevision',
      if (kind != 'delivery_void') 'lines',
    };
    if (!{
          'delivery_declare',
          'delivery_correct',
          'delivery_void',
        }.contains(kind) ||
        j.length != keys.length ||
        !keys.containsAll(j.keys)) {
      purchasingInvalid('Unexpected or missing delivery command fields.');
    }
    final p = <String, dynamic>{
      'operationId': purchasingId(j['operationId']),
      'expectedOrderVersion': purchasingVersion(j['expectedOrderVersion']),
      'expectedLedgerVersion': purchasingLedgerVersion(
        j['expectedLedgerVersion'],
      ),
      if (kind == 'delivery_declare') ...{
        'deliveryId': purchasingId(j['deliveryId']),
        'localReference': purchasingText(j['localReference'], 64),
      } else
        'expectedRevision': purchasingVersion(j['expectedRevision']),
      'reason': kind == 'delivery_declare' && j['reason'] == null
          ? null
          : purchasingText(j['reason'], 500),
    };
    if (kind != 'delivery_void') {
      final raw = j['lines'];
      if (raw is! List || raw.isEmpty || raw.length > 50) {
        purchasingInvalid('Expected 1–50 delivery lines.');
      }
      final ids = <String>{};
      final lines = <Map<String, dynamic>>[];
      for (final l in raw) {
        if (l is! Map<String, dynamic> ||
            l.length != 2 ||
            !l.containsKey('orderLineId') ||
            !l.containsKey('quantity')) {
          purchasingInvalid('Expected exact Order-line identity and quantity.');
        }
        final id = purchasingId(l['orderLineId']);
        if (!ids.add(id)) purchasingInvalid('Duplicate Order-line identity.');
        lines.add({
          'orderLineId': id,
          'quantity': purchasingQuantity(l['quantity']),
        });
      }
      lines.sort(
        (a, b) =>
            (a['orderLineId'] as String).compareTo(b['orderLineId'] as String),
      );
      p['lines'] = lines;
    }
    if (utf8.encode(jsonEncode(p)).length > 16384) {
      purchasingInvalid('Delivery command exceeds receipt bounds.');
    }
    return PurchasingDeliveryInput._(kind, p);
  }
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  String get canonical => jsonEncode(payload);
}

BigInt purchasingDeliveryScaled(String quantity) =>
    BigInt.parse(purchasingQuantity(quantity).replaceAll('.', ''));

String purchasingDeliveryQuantityText(BigInt scaled) {
  if (scaled < BigInt.zero ||
      scaled > BigInt.from(purchasingDeliveryMaxQuantity)) {
    purchasingInvalid('Quantity aggregate exceeds supported bounds.');
  }
  return '${scaled ~/ BigInt.from(1000)}.${(scaled % BigInt.from(1000)).toString().padLeft(3, '0')}';
}
