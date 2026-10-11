import 'dart:convert';
import 'recipes.dart' show recipeQuantity, recipeQuantityText;

const purchasingMaxVersion = 9007199254740991;
const purchasingDocumentBytes = 98304;

class PurchasingInputException extends FormatException {
  const PurchasingInputException(super.message);
}

Never purchasingInvalid(String message) =>
    throw PurchasingInputException(message);

String purchasingId(Object? v) {
  if (v is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
      ).hasMatch(v)) {
    purchasingInvalid('Expected UUID.');
  }
  return v.toLowerCase();
}

int purchasingVersion(Object? v) {
  if (v is! int || v < 1 || v > purchasingMaxVersion) {
    purchasingInvalid('Expected Web-safe positive version.');
  }
  return v;
}

String purchasingText(Object? v, int max) {
  if (v is! String) purchasingInvalid('Expected single-line text.');
  final s = v.trim();
  if (s.isEmpty ||
      s.runes.length > max ||
      s.contains(RegExp(r'[\x00-\x1f\x7f-\x9f]')) ||
      s.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
    purchasingInvalid('Text exceeds bounds or contains invalid characters.');
  }
  return s;
}

String purchasingQuantity(Object? v) {
  try {
    return recipeQuantityText(recipeQuantity(v));
  } on FormatException {
    purchasingInvalid(
      'Expected positive exact decimal string, 0.001 through 999999999999.999.',
    );
  }
}

String purchasingReferenceKey(String s) =>
    s.replaceAllMapped(RegExp('[A-Z]'), (m) => m[0]!.toLowerCase());

dynamic purchasingFreeze(dynamic v) => switch (v) {
  Map m => Map<String, dynamic>.unmodifiable({
    for (final e in m.entries) e.key as String: purchasingFreeze(e.value),
  }),
  List l => List<dynamic>.unmodifiable(l.map(purchasingFreeze)),
  _ => v,
};

void _fields(Map<String, dynamic> j, Set<String> keys) {
  if (j.length != keys.length || !keys.containsAll(j.keys)) {
    purchasingInvalid('Unexpected or missing fields.');
  }
}

/// All eight intents share one durable Company/operation namespace.
class PurchasingCommandInput {
  PurchasingCommandInput._(this.kind, Map<String, dynamic> p)
    : payload = purchasingFreeze(p) as Map<String, dynamic>;
  factory PurchasingCommandInput.fromJson(String kind, Map<String, dynamic> j) {
    final fields = switch (kind) {
      'supplier_create' => {'id', 'operationId', 'name', 'orderingReference'},
      'supplier_edit' => {
        'operationId',
        'expectedVersion',
        'name',
        'orderingReference',
      },
      'supplier_retire' || 'order_issue' => {'operationId', 'expectedVersion'},
      'order_create' => {
        'id',
        'operationId',
        'reference',
        'supplierId',
        'expectedSupplierVersion',
      },
      'order_save' => {
        'operationId',
        'expectedVersion',
        'reference',
        'supplierId',
        'expectedSupplierVersion',
        'reselectSupplier',
        'lines',
      },
      'order_cancel' ||
      'order_close' => {'operationId', 'expectedVersion', 'reason'},
      _ => purchasingInvalid('Unknown Purchasing command.'),
    };
    _fields(j, fields);
    final p = <String, dynamic>{'operationId': purchasingId(j['operationId'])};
    if (fields.contains('id')) p['id'] = purchasingId(j['id']);
    if (fields.contains('expectedVersion')) {
      p['expectedVersion'] = purchasingVersion(j['expectedVersion']);
    }
    if (fields.contains('name')) {
      p['name'] = purchasingText(j['name'], 200);
      p['orderingReference'] = j['orderingReference'] == null
          ? null
          : purchasingText(j['orderingReference'], 64);
    }
    if (fields.contains('reference')) {
      p['reference'] = purchasingText(j['reference'], 64);
      p['supplierId'] = purchasingId(j['supplierId']);
      p['expectedSupplierVersion'] = purchasingVersion(
        j['expectedSupplierVersion'],
      );
    }
    if (kind == 'order_save') {
      if (j['reselectSupplier'] is! bool) {
        purchasingInvalid('Expected explicit Supplier reselection flag.');
      }
      p['reselectSupplier'] = j['reselectSupplier'];
      if (j['lines'] is! List || (j['lines'] as List).length > 50) {
        purchasingInvalid('Expected 0–50 lines.');
      }
      final ids = <String>{}, articles = <String>{};
      p['lines'] = [
        for (final raw in j['lines'] as List)
          (() {
            if (raw is! Map<String, dynamic>) {
              purchasingInvalid('Expected line object.');
            }
            _fields(raw, {
              'id',
              'articleId',
              'expectedArticleVersion',
              'quantity',
              'reselectArticle',
            });
            final id = purchasingId(raw['id']),
                article = purchasingId(raw['articleId']);
            if (!ids.add(id) || !articles.add(article)) {
              purchasingInvalid('Duplicate line or Article identity.');
            }
            if (raw['reselectArticle'] is! bool) {
              purchasingInvalid('Expected explicit Article reselection flag.');
            }
            return <String, dynamic>{
              'id': id,
              'articleId': article,
              'expectedArticleVersion': purchasingVersion(
                raw['expectedArticleVersion'],
              ),
              'quantity': purchasingQuantity(raw['quantity']),
              'reselectArticle': raw['reselectArticle'],
            };
          })(),
      ];
    }
    if (fields.contains('reason')) {
      p['reason'] = purchasingText(j['reason'], 500);
    }
    if (utf8.encode(jsonEncode(p)).length > 262144) {
      purchasingInvalid('Command exceeds receipt bounds.');
    }
    return PurchasingCommandInput._(kind, p);
  }
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  String get canonical => jsonEncode(payload);
  Map<String, dynamic> toJson() => Map.of(payload);
}

/// Identical decoded UTF-8 sum in migration 0024; framing and timestamps excluded.
int purchasingDocumentSize(Map<String, dynamic> order) {
  final supplier = order['supplier'] as Map;
  final values = <Object?>[
    order['id'],
    order['companyId'],
    order['locationId'],
    order['reference'],
    supplier['id'],
    supplier['version'],
    supplier['name'],
    supplier['orderingReference'],
  ];
  for (final l in order['lines'] as List) {
    values.addAll([
      l['id'],
      l['position'],
      l['articleId'],
      l['articleVersion'],
      l['sku'],
      l['name'],
      l['unit'],
      l['quantity'],
    ]);
  }
  return values.fold(0, (n, v) => n + utf8.encode(v?.toString() ?? '').length);
}

String purchasingOrderText(Map<String, dynamic> order) {
  final s = order['supplier'] as Map;
  return [
    'Order ${order['reference']}',
    'Supplier: ${s['name']}',
    if (s['orderingReference'] != null)
      'Ordering reference: ${s['orderingReference']}',
    'Location: ${order['locationId']}',
    'Status: ${order['status']}',
    'Issue records internal approval. Closure is administrative; neither records transmission or receipt.',
    for (final l in order['lines'] as List)
      '${l['position']}. ${l['sku']} — ${l['name']}: ${l['quantity']} ${l['unit']}',
  ].join('\n');
}
