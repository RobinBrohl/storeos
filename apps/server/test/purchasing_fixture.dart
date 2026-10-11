import 'dart:async';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';

String get purchasingOrders =>
    '/purchasing/locations/$merchandisingTestLocation/orders';
Future<Map<String, dynamic>> supplier(
  MerchandisingFixture f, {
  String name = 'Supplier',
  String? reference,
}) async =>
    (await f.call(
          'POST',
          '/purchasing/suppliers',
          expected: 201,
          body: {
            'id': newUuid(),
            'operationId': newUuid(),
            'name': name,
            'orderingReference': reference,
          },
        )).body['supplier']
        as Map<String, dynamic>;
Future<Map<String, dynamic>> draft(
  MerchandisingFixture f,
  Map s, {
  String? reference,
}) async =>
    (await f.call(
          'POST',
          purchasingOrders,
          expected: 201,
          body: {
            'id': newUuid(),
            'operationId': newUuid(),
            'reference': reference ?? 'PO-${newUuid()}',
            'supplierId': s['id'],
            'expectedSupplierVersion': s['version'],
          },
        )).body['order']
        as Map<String, dynamic>;
Map<String, dynamic> draftSave(
  Map d,
  List<Map<String, dynamic>> lines, {
  bool reselectSupplier = false,
}) => {
  'operationId': newUuid(),
  'expectedVersion': d['version'],
  'reference': d['reference'],
  'supplierId': d['supplier']['id'],
  'expectedSupplierVersion': d['supplier']['version'],
  'reselectSupplier': reselectSupplier,
  'lines': lines,
};
Map<String, dynamic> purchasingLine(
  Map a, {
  String quantity = '2.5',
  String? id,
  bool reselect = true,
}) => {
  'id': id ?? newUuid(),
  'articleId': a['id'],
  'expectedArticleVersion': a['version'],
  'quantity': quantity,
  'reselectArticle': reselect,
};
Map<String, dynamic> retainedLine(Map l) => {
  'id': l['id'],
  'articleId': l['articleId'],
  'expectedArticleVersion': l['articleVersion'],
  'quantity': l['quantity'],
  'reselectArticle': false,
};
Future<Map<String, dynamic>> populated(
  MerchandisingFixture f, {
  Map<String, dynamic>? s,
}) async {
  final d = await draft(f, s ?? await supplier(f)),
      a = await f.stockArticle(sku: 'PO-${newUuid()}', unit: 'kg');
  return (await f.call(
        'PUT',
        '$purchasingOrders/${d['id']}',
        body: draftSave(d, [purchasingLine(a.toJson())]),
      )).body['order']
      as Map<String, dynamic>;
}

Future<List<Object?>> purchasingEvidence(MerchandisingFixture f) async => [
  for (final table in [
    'purchasing_suppliers',
    'purchasing_orders',
    'purchasing_order_lines',
    'purchasing_commands',
    'audit_entries',
  ])
    (await f.owner.execute(
      'SELECT md5(string_agg(to_jsonb(t)::text,\'\' ORDER BY to_jsonb(t)::text)) FROM "${f.schema}".$table t',
    )).single.first,
];
Future<void> purchasingUnchanged(
  MerchandisingFixture f,
  List<Object?> before,
) => expectLater(purchasingEvidence(f), completion(before));
Future<List<MerchandisingReply>> orderedPurchasing(
  MerchandisingFixture f,
  Future<MerchandisingReply> Function() first,
  Future<MerchandisingReply> Function() second,
) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holding = f.database.runAuthorized(
    f.adminPrincipal,
    'purchasing.orders.manage',
    (tx, a) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  Future<void> queued(int n) async {
    final watch = Stopwatch()..start();
    while (watch.elapsed < const Duration(seconds: 10)) {
      final rows = await f.owner.execute(
        Sql.named(
          'SELECT count(*) FROM pg_locks WHERE locktype=\'advisory\' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid',
        ),
        parameters: {
          'key': 'storeos_platform:${f.schema}:$merchandisingTestCompany',
        },
      );
      if ((rows.single.first as int) >= n) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Observed lock queue barrier timed out.');
  }

  try {
    final a = first();
    await queued(1);
    final b = second();
    await queued(2);
    release.complete();
    await holding;
    return [await a, await b];
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}
