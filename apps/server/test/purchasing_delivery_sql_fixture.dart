import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'purchasing_fixture.dart';

Future<void> insertSqlDeclaration(
  MerchandisingFixture f,
  Map<String, dynamic> order,
  Map<String, dynamic> body, {
  String? mutation,
}) => f.pool.runTx((tx) async {
  final table = '"${f.schema}"',
      payload = Map<String, dynamic>.from(body),
      delivery = body['deliveryId'],
      operation = body['operationId'],
      ledger = (body['expectedLedgerVersion'] as int) + 1;
  if (mutation == 'missing_key') payload.remove('reason');
  if (mutation == 'wrong_type') payload['expectedLedgerVersion'] = '0';
  if (mutation == 'payload_empty_object') payload.clear();
  if (mutation == 'payload_operation_null') payload['operationId'] = null;
  if (mutation == 'excess_total') {
    payload['lines'] = [
      {...(body['lines'] as List).single as Map, 'quantity': '1.000'},
    ];
  }
  final quantity = int.parse(
    (mutation == 'excess_total'
            ? '1.000'
            : body['lines'][0]['quantity'] as String)
        .replaceAll('.', ''),
  );
  await tx.execute(
    Sql.named(
      'INSERT INTO $table.purchasing_delivery_revisions(company_id,location_id,order_id,delivery_id,revision,ledger_version,kind,local_reference,reason,actor_id,operation_id) '
      "VALUES(@company,@location,@order,@delivery,1,@ledger,'delivery_declare',@reference,@reason,@actor,@operation)",
    ),
    parameters: {
      'company': merchandisingTestCompany,
      'location': mutation == 'foreign_location'
          ? newUuid()
          : merchandisingTestLocation,
      'order': order['id'],
      'delivery': delivery,
      'ledger': mutation == 'duplicate_sequence' ? ledger - 1 : ledger,
      'reference': body['localReference'],
      'reason': body['reason'],
      'actor': f.adminId,
      'operation': operation,
    },
  );
  if (mutation != 'missing_lines') {
    final quantitySql = mutation == 'bad_scale'
        ? "'0.5'::bigint"
        : mutation == 'nonpositive_quantity'
        ? '0'
        : '$quantity';
    await tx.execute(
      Sql.named(
        'INSERT INTO $table.purchasing_delivery_revision_lines(company_id,location_id,order_id,delivery_id,revision,order_line_id,quantity_scaled) '
        'VALUES(@company,@location,@order,@delivery,1,@line,$quantitySql)',
      ),
      parameters: {
        'company': merchandisingTestCompany,
        'location': merchandisingTestLocation,
        'order': order['id'],
        'delivery': delivery,
        'line': mutation == 'foreign_line'
            ? newUuid()
            : body['lines'][0]['orderLineId'],
      },
    );
  }
  final payloadSql = switch (mutation) {
    'payload_sql_null' => 'NULL',
    'payload_null' => "'null'::jsonb",
    _ => '@payload::jsonb',
  };
  final resultSql = mutation == 'result_null'
      ? "'null'::jsonb"
      : "jsonb_build_object('delivery',$table.purchasing_delivery_revision_json(@company,@order,@delivery,1),'summary',$table.purchasing_delivery_summary(@company,@order,@ledger),'replayed',false)";
  await tx.execute(
    Sql.named(
      'INSERT INTO $table.purchasing_delivery_commands(company_id,location_id,order_id,delivery_id,actor_id,operation_id,kind,expected_order_version,expected_ledger_version,revision,ledger_version,response_status,payload,result) '
      "VALUES(@company,@location,@order,@delivery,@actor,@operation,'delivery_declare',@version,@baseline,1,@ledger,201,$payloadSql,$resultSql)",
    ),
    parameters: {
      'company': merchandisingTestCompany,
      'location': merchandisingTestLocation,
      'order': order['id'],
      'delivery': delivery,
      'actor': f.adminId,
      'operation': operation,
      'version': order['version'],
      'baseline': body['expectedLedgerVersion'],
      'ledger': ledger,
      if (!{'payload_null', 'payload_sql_null'}.contains(mutation))
        'payload': jsonEncode(payload),
    },
  );
});

Future<void> verifySqlDeclaration(
  MerchandisingFixture f,
  Map<String, dynamic> order,
  Map<String, dynamic> body,
) async {
  final rows = await f.owner.execute(
    Sql.named(
      'SELECT '
      '(SELECT count(*) FROM "${f.schema}".purchasing_delivery_revisions WHERE delivery_id=@delivery),'
      '(SELECT count(*) FROM "${f.schema}".purchasing_delivery_revision_lines WHERE delivery_id=@delivery),'
      '(SELECT count(*) FROM "${f.schema}".purchasing_delivery_commands WHERE operation_id=@operation)',
    ),
    parameters: {
      'delivery': body['deliveryId'],
      'operation': body['operationId'],
    },
  );
  expect(rows.single, [1, 1, 1]);
  final replay = await f.call(
    'POST',
    '$purchasingOrders/${order['id']}/deliveries',
    body: body,
    expected: 201,
  );
  expect(replay.body['replayed'], true);
  expect(replay.body['delivery']['deliveryId'], body['deliveryId']);
  expect(replay.body['delivery']['lines'], body['lines']);
  expect(
    replay.body['summary']['ledgerVersion'],
    (body['expectedLedgerVersion'] as int) + 1,
  );
}
