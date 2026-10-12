import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/infrastructure/migration_runner.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/purchasing/purchasing_service.dart';
import 'knowledge_acceptance.dart';
import 'purchasing_acceptance.dart';

Future<void> applyPreDeliveryMigrations(
  Connection owner,
  String schema,
  String runtime,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'storeos_p414_prefix_',
  );
  try {
    for (final file in Directory('migrations').listSync().whereType<File>()) {
      if (file.uri.pathSegments.last.compareTo('0026_') < 0) {
        await file.copy('${directory.path}/${file.uri.pathSegments.last}');
      }
    }
    await MigrationRunner(
      connection: owner,
      migrationsDirectory: directory,
      schemaName: schema,
      runtimeDatabaseUser: runtime,
    ).apply();
  } finally {
    await directory.delete(recursive: true);
  }
}

Future<List<Map<String, dynamic>>> seedPurchasingDeliveries(
  KnowledgeAcceptanceRequest request,
  String location,
) async {
  final root = '/api/v1/platform/purchasing/locations/$location/orders',
      records = <Map<String, dynamic>>[];
  final existing =
      (await request('GET', '$root?status=issued', null, 200))['items'] as List;
  final active =
      (await request(
            'GET',
            '/api/v1/platform/purchasing/suppliers?status=active',
            null,
            200,
          ))['items']
          as List;
  final articles =
      (await request(
            'GET',
            '/api/v1/platform/purchasing/locations/$location/article-selections',
            null,
            200,
          ))['items']
          as List;
  Future<Map> order(String reference, String quantity) async {
    var o =
        (await request('POST', root, {
              'id': newUuid(),
              'operationId': newUuid(),
              'reference': reference,
              'supplierId': active.first['id'],
              'expectedSupplierVersion': active.first['version'],
            }, 201))['order']
            as Map;
    o =
        (await request('PUT', '$root/${o['id']}', {
              'operationId': newUuid(),
              'expectedVersion': o['version'],
              'reference': o['reference'],
              'supplierId': o['supplier']['id'],
              'expectedSupplierVersion': o['supplier']['version'],
              'reselectSupplier': false,
              'lines': [
                {
                  'id': newUuid(),
                  'articleId': articles.first['id'],
                  'expectedArticleVersion': articles.first['version'],
                  'quantity': quantity,
                  'reselectArticle': true,
                },
              ],
            }, 200))['order']
            as Map;
    return (await request('POST', '$root/${o['id']}/issue', {
          'operationId': newUuid(),
          'expectedVersion': o['version'],
        }, 200))['order']
        as Map;
  }

  Future<Map> command(
    Map o,
    String kind,
    int ledger, {
    Map? prior,
    String quantity = '1',
    String? reference,
  }) async {
    final body = <String, dynamic>{
      'operationId': newUuid(),
      'expectedOrderVersion': o['version'],
      'expectedLedgerVersion': ledger,
      'reason': kind == 'delivery_declare'
          ? 'Accepted declaration / overdelivery'
          : 'Reasoned evidence replacement',
      if (prior == null) ...{
        'deliveryId': newUuid(),
        'localReference': reference ?? 'Local-${newUuid()}',
      } else
        'expectedRevision': prior['revision'],
      if (kind != 'delivery_void')
        'lines': [
          {'orderLineId': o['lines'][0]['id'], 'quantity': quantity},
        ],
    };
    final result = await request(
      'POST',
      '$root/${o['id']}/deliveries${prior == null ? '' : '/${prior['deliveryId']}/${kind == 'delivery_void' ? 'void' : 'correct'}'}',
      body,
      prior == null ? 201 : 200,
    );
    records.add({
      'orderId': o['id'],
      'deliveryId': result['delivery']['deliveryId'],
      'kind': kind,
      'body': body,
      'result': result,
    });
    return result['delivery'] as Map;
  }

  final over = existing.single as Map;
  final a = await command(over, 'delivery_declare', 0, reference: 'Over-A'),
      b = await command(
        over,
        'delivery_declare',
        1,
        quantity: '2',
        reference: 'Over-B',
      );
  await command(over, 'delivery_correct', 2, prior: a, quantity: '0.5');
  final v = await command(over, 'delivery_void', 3, prior: b);
  await command(over, 'delivery_correct', 4, prior: v, quantity: '2.5');
  var closed = await order('P414 terminal evidence', '12');
  final c = await command(
    closed,
    'delivery_declare',
    0,
    quantity: '5',
    reference: 'Terminal-A',
  );
  await command(
    closed,
    'delivery_declare',
    1,
    quantity: '7',
    reference: 'Terminal-B',
  );
  closed =
      (await request('POST', '$root/${closed['id']}/close', {
            'operationId': newUuid(),
            'expectedVersion': closed['version'],
            'reason': 'Administrative close at twelve',
          }, 200))['order']
          as Map;
  await command(closed, 'delivery_correct', 2, prior: c, quantity: '4');
  final partial = await order('P414 partial evidence', '12');
  await command(
    partial,
    'delivery_declare',
    0,
    quantity: '5',
    reference: 'Partial-A',
  );
  return records;
}

Future<void> verifyPurchasingDeliveries(
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
      'purchasing_delivery_revisions',
      'purchasing_delivery_revision_lines',
      'purchasing_delivery_commands',
      'purchasing_delivery_terminal_snapshots',
      'purchasing_orders',
      'purchasing_commands',
      'audit_entries',
    ])
      table: (await db.pool.execute(
        "SELECT count(*),md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM ${db.schema}.$table t",
      )).single.toList(),
  });
  final before = await hash();
  Future<void> denied(Future<Object?> call) async {
    try {
      await call;
      throw StateError('Delivery authorization denial missing.');
    } on PlatformFailure catch (e) {
      if (e.status != 403) rethrow;
    }
  }

  for (final raw in records) {
    final r = raw as Map;
    final replay = await service.deliveryCommand(
      manager,
      db.locationId,
      r['orderId'] as String,
      r['kind'] == 'delivery_declare' ? null : r['deliveryId'] as String,
      r['kind'] as String,
      Map<String, dynamic>.from(r['body'] as Map),
    );
    if (jsonEncode(stablePurchasing(replay)) !=
        jsonEncode(
          stablePurchasing({...r['result'] as Map, 'replayed': true}),
        )) {
      throw StateError('Original delivery receipt changed.');
    }
    await service.deliveryDetail(
      manager,
      db.locationId,
      r['orderId'] as String,
      r['deliveryId'] as String,
    );
    await denied(
      service.deliverySummary(worker, db.locationId, r['orderId'] as String),
    );
    if (otherLocation != null) {
      await denied(
        service.deliverySummary(manager, otherLocation, r['orderId'] as String),
      );
    }
    if (otherManager != null) {
      await denied(
        service.deliverySummary(
          otherManager,
          db.locationId,
          r['orderId'] as String,
        ),
      );
    }
  }
  final closed =
      records.firstWhere(
            (r) =>
                (r as Map)['result']['summary']['lines'][0]['orderedQuantity'] ==
                '12.000',
          )
          as Map;
  final summary = await service.deliverySummary(
    manager,
    db.locationId,
    closed['orderId'] as String,
  );
  if (summary['summary']['lines'][0]['effectiveDelivered'] != '11.000' ||
      summary['terminalSnapshot']['summary']['lines'][0]['effectiveDelivered'] !=
          '12.000') {
    throw StateError('Delivery closure/current comparison changed.');
  }
  if (await hash() != before) {
    throw StateError('Delivery verification mutated evidence.');
  }
}

Future<void> verifyDeliveryGrants(
  Connection owner,
  String schema,
  String runtime,
) async {
  for (final table in [
    'purchasing_delivery_revisions',
    'purchasing_delivery_revision_lines',
    'purchasing_delivery_commands',
    'purchasing_delivery_terminal_snapshots',
  ]) {
    final row = (await owner.execute(
      Sql.named(
        "SELECT has_table_privilege(@role,@table,'SELECT'),has_table_privilege(@role,@table,'INSERT'),has_table_privilege(@role,@table,'UPDATE'),has_table_privilege(@role,@table,'DELETE'),has_table_privilege(@role,@table,'TRUNCATE')",
      ),
      parameters: {'role': runtime, 'table': '"$schema".$table'},
    )).single;
    if (jsonEncode(row.toList()) != '[true,true,false,false,false]') {
      throw StateError('Delivery runtime grants changed.');
    }
  }
}
