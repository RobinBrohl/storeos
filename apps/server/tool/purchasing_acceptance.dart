import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/purchasing/purchasing_service.dart';
import 'knowledge_acceptance.dart';

Object? stablePurchasing(Object? v) {
  if (v is Map) {
    return {
      for (final k in v.keys.map((e) => e.toString()).toList()..sort())
        k: stablePurchasing(v[k]),
    };
  }
  if (v is List) return v.map(stablePurchasing).toList();
  return v;
}

Future<List<Map<String, dynamic>>> seedPurchasing(
  KnowledgeAcceptanceRequest request,
  String location,
) async {
  const root = '/api/v1/platform/purchasing';
  final orders = '$root/locations/$location/orders',
      records = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> command(
    String method,
    String route,
    String kind,
    Map<String, dynamic> body,
  ) async {
    final status = kind.endsWith('_create') ? 201 : 200,
        result = await request(method, route, body, status);
    records.add({
      'method': method,
      'route': route.substring('/api/v1/platform'.length),
      'kind': kind,
      'target':
          result[kind.startsWith('supplier_') ? 'supplier' : 'order']['id'],
      'body': body,
      'result': result,
    });
    return result;
  }

  final s =
      (await command('POST', '$root/suppliers', 'supplier_create', {
            'id': newUuid(),
            'operationId': newUuid(),
            'name': 'Purchasing historical Supplier 😀',
            'orderingReference': 'CUSTOMER',
          }))['supplier']
          as Map;
  await command('POST', '$root/suppliers', 'supplier_create', {
    'id': newUuid(),
    'operationId': newUuid(),
    'name': 'Active Purchasing Supplier',
    'orderingReference': null,
  });
  final selections = await request(
        'GET',
        '$root/locations/$location/article-selections',
        null,
        200,
      ),
      candidates = selections['items'] as List,
      a = candidates.cast<Map>().firstWhere(
        (a) => (a['sku'] as String).startsWith('RECIPE-PRODUCED-'),
        orElse: () => candidates.first as Map,
      );
  for (final state in [
    'empty_draft',
    'populated_draft',
    'issued',
    'closed',
    'issued_cancelled',
    'draft_cancelled',
  ]) {
    var d =
        (await command('POST', orders, 'order_create', {
              'id': newUuid(),
              'operationId': newUuid(),
              'reference': 'P412-$state',
              'supplierId': s['id'],
              'expectedSupplierVersion': 1,
            }))['order']
            as Map;
    if (state != 'empty_draft' && state != 'draft_cancelled') {
      d =
          (await command('PUT', '$orders/${d['id']}', 'order_save', {
                'operationId': newUuid(),
                'expectedVersion': 1,
                'reference': d['reference'],
                'supplierId': s['id'],
                'expectedSupplierVersion': 1,
                'reselectSupplier': false,
                'lines': [
                  {
                    'id': newUuid(),
                    'articleId': a['id'],
                    'expectedArticleVersion': a['version'],
                    'quantity': '2.5',
                    'reselectArticle': true,
                  },
                ],
              }))['order']
              as Map;
    }
    if (['issued', 'closed', 'issued_cancelled'].contains(state)) {
      d =
          (await command('POST', '$orders/${d['id']}/issue', 'order_issue', {
                'operationId': newUuid(),
                'expectedVersion': d['version'],
              }))['order']
              as Map;
    }
    if (state == 'closed' || state.endsWith('_cancelled')) {
      final action = state == 'closed' ? 'close' : 'cancel';
      await command('POST', '$orders/${d['id']}/$action', 'order_$action', {
        'operationId': newUuid(),
        'expectedVersion': d['version'],
        'reason': 'Administrative $state 😀',
      });
    }
  }
  await command('PUT', '$root/suppliers/${s['id']}', 'supplier_edit', {
    'operationId': newUuid(),
    'expectedVersion': 1,
    'name': 'Changed Purchasing Supplier',
    'orderingReference': 'LATER',
  });
  await command(
    'POST',
    '$root/suppliers/${s['id']}/retire',
    'supplier_retire',
    {'operationId': newUuid(), 'expectedVersion': 2},
  );
  final article = await request(
    'GET',
    '/api/v1/platform/articles/${a['id']}',
    null,
    200,
  );
  await request('POST', '/api/v1/platform/articles/${a['id']}/edit', {
    'expectedVersion': article['version'],
    'sku': article['sku'],
    'barcode': article['barcode'],
    'name': 'Later Purchasing catalog label',
    'description': article['description'],
    'unit': article['unit'],
  }, 200);
  return records;
}

Future<void> verifyPurchasing(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal worker,
  List records, {
  String? otherLocation,
  SessionPrincipal? otherManager,
}) async {
  final service = PurchasingService(db);
  Future<String> hash() async => jsonEncode({
    for (final table in [
      'purchasing_suppliers',
      'purchasing_orders',
      'purchasing_order_lines',
      'purchasing_commands',
      'audit_entries',
    ])
      table: (await db.pool.execute(
        "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
      )).single.toList(),
  });
  final before = await hash();
  final historical = await db.pool.execute(
    'SELECT count(*) FROM ${db.schema}.purchasing_order_lines l JOIN ${db.schema}.articles a ON a.id=l.article_id AND a.company_id=l.company_id WHERE l.article_version<a.version AND l.name<>a.name',
  );
  if (historical.single.first != 4) {
    throw StateError(
      'Purchasing Article snapshots must predate changed catalog labels.',
    );
  }
  final kinds = <String>{}, states = <String>{};
  Future<void> denied(Future<Object?> call) async {
    try {
      await call;
      throw StateError('Purchasing authorization denial missing.');
    } on PlatformFailure catch (e) {
      if (e.status != 403) rethrow;
    }
  }

  for (final raw in records) {
    final r = raw as Map,
        kind = r['kind'] as String,
        supplier = kind.startsWith('supplier_'),
        body = Map<String, dynamic>.from(r['body'] as Map),
        target = r['target'] as String;
    kinds.add(kind);
    final replay = await service.command(
      manager,
      supplier ? null : db.locationId,
      kind.endsWith('_create') ? null : target,
      kind,
      body,
    );
    if (jsonEncode(stablePurchasing(replay)) !=
        jsonEncode(
          stablePurchasing({...r['result'] as Map, 'replayed': true}),
        )) {
      throw StateError('Purchasing original receipt changed after restore.');
    }
    final current = await service.detail(
      manager,
      supplier ? null : db.locationId,
      target,
      supplier: supplier,
    );
    if (!supplier) states.add(current['status'] as String);
    await denied(
      service.detail(
        worker,
        supplier ? null : db.locationId,
        target,
        supplier: supplier,
      ),
    );
    await denied(
      service.command(
        worker,
        supplier ? null : db.locationId,
        kind.endsWith('_create') ? null : target,
        kind,
        body,
      ),
    );
    if (!supplier && otherLocation != null) {
      await denied(
        service.detail(manager, otherLocation, target, supplier: false),
      );
    }
    if (!supplier && otherManager != null) {
      await denied(
        service.detail(otherManager, db.locationId, target, supplier: false),
      );
    }
  }
  if (kinds.length != 8 || states.length != 4 || await hash() != before) {
    throw StateError('Purchasing lifecycle/replay conservation failed.');
  }
}

Future<void> verifyPurchasingGrants(
  Connection owner,
  String schema,
  String runtime,
) async {
  for (final table in [
    'purchasing_suppliers',
    'purchasing_orders',
    'purchasing_order_lines',
    'purchasing_commands',
  ]) {
    for (final privilege in [
      'TRUNCATE',
      if (table != 'purchasing_order_lines') 'DELETE',
      if (table == 'purchasing_commands' || table == 'purchasing_order_lines')
        'UPDATE',
    ]) {
      final r = await owner.execute(
        Sql.named('SELECT has_table_privilege(@role,@table,@privilege)'),
        parameters: {
          'role': runtime,
          'table': '"$schema".$table',
          'privilege': privilege,
        },
      );
      if (r.single.first != false) {
        throw StateError('Purchasing runtime privilege too broad.');
      }
    }
  }
  try {
    await owner.runTx((tx) async {
      await tx.execute('SET LOCAL ROLE "$runtime"');
      await tx.execute('UPDATE "$schema".purchasing_commands SET kind=kind');
    });
    throw StateError('Purchasing receipt mutation permitted.');
  } on ServerException catch (e) {
    if (e.code != '42501') rethrow;
  }
}
