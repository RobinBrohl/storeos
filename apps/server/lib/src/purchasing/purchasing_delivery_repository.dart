import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'purchasing_repository.dart';

/// All operations participate in the caller's authorized Company transaction.
class PurchasingDeliveryRepository extends PurchasingRepository {
  const PurchasingDeliveryRepository(
    super.schema,
    super.company,
    super.location,
  );
  Future<bool> installed(TxSession tx) async => (await execute(
    tx,
    "SELECT 1 FROM $schema.schema_migrations WHERE version='0026_purchase_order_delivery_evidence'",
    {},
  )).isNotEmpty;

  Future<void> lock(TxSession tx, String order) async {
    await execute(
      tx,
      'SELECT id FROM $schema.purchasing_orders WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@order AS uuid) FOR UPDATE',
      {'order': order},
    );
  }

  Future<Map<String, dynamic>?> commandReceipt(
    TxSession tx,
    String operation,
  ) async {
    final rows = await execute(
      tx,
      'SELECT * FROM $schema.purchasing_delivery_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      {'operation': operation},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<Map<String, dynamic>> summary(TxSession tx, String order) async {
    final rows = await execute(
      tx,
      'SELECT $schema.purchasing_delivery_summary(CAST(@company AS uuid),CAST(@order AS uuid),COALESCE(max(ledger_version),0)) FROM $schema.purchasing_delivery_revisions WHERE company_id=CAST(@company AS uuid) AND order_id=CAST(@order AS uuid)',
      {'order': order},
    );
    return Map<String, dynamic>.from(rows.single.first as Map);
  }

  Future<Map<String, dynamic>?> delivery(
    TxSession tx,
    String order,
    String delivery,
  ) async {
    final rows = await execute(
      tx,
      'SELECT $schema.purchasing_delivery_revision_json(company_id,order_id,delivery_id,revision) FROM $schema.purchasing_delivery_revisions WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND order_id=CAST(@order AS uuid) AND delivery_id=CAST(@delivery AS uuid) ORDER BY revision DESC LIMIT 1',
      {'order': order, 'delivery': delivery},
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(rows.single.first as Map);
  }

  Future<Map<String, dynamic>?> terminal(TxSession tx, String order) async {
    final rows = await execute(
      tx,
      "SELECT jsonb_build_object('operationId',operation_id,'orderVersion',order_version,'actorId',actor_id,'terminalAt',$schema.purchasing_time(terminal_at),'status',CASE WHEN kind='order_close' THEN 'closed' ELSE 'cancelled' END,'summary',summary) FROM $schema.purchasing_delivery_terminal_snapshots WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND order_id=CAST(@order AS uuid)",
      {'order': order},
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(rows.single.first as Map);
  }

  Future<void> append(
    TxSession tx,
    String order,
    String delivery,
    String actor,
    int revision,
    int ledger,
    String reference,
    PurchasingDeliveryInput c,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.purchasing_delivery_revisions(company_id,location_id,order_id,delivery_id,revision,ledger_version,kind,local_reference,reason,actor_id,operation_id) VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@order AS uuid),CAST(@delivery AS uuid),@revision,@ledger,@kind,@reference,@reason,CAST(@actor AS uuid),CAST(@operation AS uuid))',
      {
        'order': order,
        'delivery': delivery,
        'actor': actor,
        'revision': revision,
        'ledger': ledger,
        'kind': c.kind,
        'reference': reference,
        'reason': c.payload['reason'],
        'operation': c.operationId,
      },
    );
    for (final l in c.payload['lines'] as List? ?? []) {
      await execute(
        tx,
        'INSERT INTO $schema.purchasing_delivery_revision_lines(company_id,location_id,order_id,delivery_id,revision,order_line_id,quantity_scaled) VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@order AS uuid),CAST(@delivery AS uuid),@revision,CAST(@line AS uuid),@quantity)',
        {
          'order': order,
          'delivery': delivery,
          'revision': revision,
          'line': l['orderLineId'],
          'quantity': purchasingDeliveryScaled(l['quantity'] as String).toInt(),
        },
      );
    }
  }

  Future<void> acceptDelivery(
    TxSession tx,
    String order,
    String delivery,
    String actor,
    int revision,
    int ledger,
    PurchasingDeliveryInput c,
    Map<String, dynamic> result,
  ) async {
    await execute(
      tx,
      'INSERT INTO $schema.purchasing_delivery_commands(company_id,location_id,order_id,delivery_id,actor_id,operation_id,kind,expected_order_version,expected_ledger_version,expected_revision,revision,ledger_version,response_status,payload,result) VALUES(CAST(@company AS uuid),CAST(@location AS uuid),CAST(@order AS uuid),CAST(@delivery AS uuid),CAST(@actor AS uuid),CAST(@operation AS uuid),@kind,@ov,@lv,@ev,@revision,@ledger,@status,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      {
        'order': order,
        'delivery': delivery,
        'actor': actor,
        'operation': c.operationId,
        'kind': c.kind,
        'ov': c.payload['expectedOrderVersion'],
        'lv': c.payload['expectedLedgerVersion'],
        'ev': c.payload['expectedRevision'],
        'revision': revision,
        'ledger': ledger,
        'status': c.kind == 'delivery_declare' ? 201 : 200,
        'payload': c.canonical,
        'result': jsonEncode(result),
      },
    );
  }

  Future<void> captureTerminal(TxSession tx, String order) async {
    await execute(
      tx,
      'INSERT INTO $schema.purchasing_delivery_terminal_snapshots(company_id,location_id,order_id,operation_id,order_version,actor_id,kind,terminal_at,ledger_version,summary) SELECT company_id,location_id,id,terminal_operation_id,version,terminal_by,last_kind,terminal_at,COALESCE((SELECT max(ledger_version) FROM $schema.purchasing_delivery_revisions r WHERE r.company_id=o.company_id AND r.order_id=o.id),0),$schema.purchasing_delivery_summary(company_id,id,COALESCE((SELECT max(ledger_version) FROM $schema.purchasing_delivery_revisions r WHERE r.company_id=o.company_id AND r.order_id=o.id),0)) FROM $schema.purchasing_orders o WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@order AS uuid)',
      {'order': order},
    );
  }

  Future<List<Map<String, dynamic>>> deliveries(
    TxSession tx,
    String order, {
    String? delivery,
    int? afterRevision,
    String? after,
  }) async {
    final rows = await execute(
      tx,
      delivery == null
          ? 'SELECT $schema.purchasing_delivery_revision_json(company_id,order_id,delivery_id,revision) FROM (SELECT DISTINCT ON (delivery_id) * FROM $schema.purchasing_delivery_revisions WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND order_id=CAST(@order AS uuid) AND (CAST(@after AS uuid) IS NULL OR delivery_id>CAST(@after AS uuid)) ORDER BY delivery_id,revision DESC) r ORDER BY delivery_id LIMIT 51'
          : 'SELECT $schema.purchasing_delivery_revision_json(company_id,order_id,delivery_id,revision) FROM $schema.purchasing_delivery_revisions WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND order_id=CAST(@order AS uuid) AND delivery_id=CAST(@delivery AS uuid) AND (CAST(@afterRevision AS bigint) IS NULL OR revision>CAST(@afterRevision AS bigint)) ORDER BY revision LIMIT 51',
      {
        'order': order,
        'delivery': delivery,
        'after': after,
        'afterRevision': afterRevision,
      },
    );
    return rows.map((r) => Map<String, dynamic>.from(r.first as Map)).toList();
  }
}
