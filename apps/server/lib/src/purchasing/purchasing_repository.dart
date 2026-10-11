import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Reads/writes only Purchasing-owned tables and projections.
class PurchasingRepository {
  const PurchasingRepository(this.schema, this.company, this.location);
  final String schema, company, location;
  Future<Result> execute(TxSession tx, String sql, Map<String, Object?> p) =>
      tx.execute(
        Sql.named(sql),
        parameters: {
          for (final name in RegExp(
            r'@([A-Za-z][A-Za-z0-9_]*)',
          ).allMatches(sql).map((m) => m[1]!).toSet())
            name: {'company': company, 'location': location, ...p}[name],
        },
      );
  Future<Map<String, dynamic>?> find(
    TxSession tx,
    String id, {
    required bool supplier,
  }) async {
    final rows = await execute(
      tx,
      'SELECT $schema.purchasing_${supplier ? 'supplier' : 'order'}_json(company_id,id) FROM $schema.purchasing_${supplier ? 'suppliers' : 'orders'} WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid) ${supplier ? '' : 'AND location_id=CAST(@location AS uuid)'}',
      {'id': id},
    );
    return rows.isEmpty
        ? null
        : Map<String, dynamic>.from(rows.single.first as Map);
  }

  Future<Map<String, dynamic>?> receipt(TxSession tx, String operation) async {
    final r = await execute(
      tx,
      'SELECT * FROM $schema.purchasing_commands WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      {'operation': operation},
    );
    return r.isEmpty ? null : r.single.toColumnMap();
  }

  Future<void> accept(
    TxSession tx,
    String id,
    String actor,
    PurchasingCommandInput c,
    Map<String, dynamic> result,
  ) async {
    final supplier = c.kind.startsWith('supplier_');
    await execute(
      tx,
      'INSERT INTO $schema.purchasing_commands(company_id,operation_id,supplier_id,order_id,location_id,actor_id,kind,expected_version,applied_version,response_status,payload,result) VALUES(CAST(@company AS uuid),CAST(@operation AS uuid),CAST(@supplier AS uuid),CAST(@order AS uuid),CAST(@scope AS uuid),CAST(@actor AS uuid),@kind,@expected,@version,@status,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      {
        'operation': c.operationId,
        'supplier': supplier ? id : null,
        'order': supplier ? null : id,
        'scope': supplier ? null : location,
        'actor': actor,
        'kind': c.kind,
        'expected': c.payload['expectedVersion'],
        'version': (result[supplier ? 'supplier' : 'order'] as Map)['version'],
        'status': c.kind.endsWith('_create') ? 201 : 200,
        'payload': c.canonical,
        'result': jsonEncode(result),
      },
    );
  }

  Future<void> supplierCommand(
    TxSession tx,
    String id,
    String actor,
    PurchasingCommandInput c,
  ) async {
    final p = {
      'id': id,
      'actor': actor,
      'operation': c.operationId,
      'kind': c.kind,
      ...c.payload,
    };
    if (c.kind == 'supplier_create') {
      await execute(
        tx,
        'INSERT INTO $schema.purchasing_suppliers(company_id,id,name,ordering_reference,created_by,changed_by,last_operation_id,last_kind) VALUES(CAST(@company AS uuid),CAST(@id AS uuid),@name,@orderingReference,CAST(@actor AS uuid),CAST(@actor AS uuid),CAST(@operation AS uuid),@kind)',
        p,
      );
    } else {
      await execute(
        tx,
        'UPDATE $schema.purchasing_suppliers SET version=version+1,changed_by=CAST(@actor AS uuid),changed_at=statement_timestamp(),last_operation_id=CAST(@operation AS uuid),last_kind=@kind,${c.kind == 'supplier_edit' ? 'name=@name,ordering_reference=@orderingReference' : "status='retired',retired_by=CAST(@actor AS uuid),retired_at=statement_timestamp()"} WHERE company_id=CAST(@company AS uuid) AND id=CAST(@id AS uuid)',
        p,
      );
    }
  }

  Future<void> orderCommand(
    TxSession tx,
    String id,
    String actor,
    PurchasingCommandInput c, {
    Map<String, dynamic>? document,
  }) async {
    final p = <String, Object?>{
      'id': id,
      'actor': actor,
      'operation': c.operationId,
      'kind': c.kind,
      ...c.payload,
    };
    if (document != null) {
      final s = document['supplier'] as Map;
      p.addAll({
        'reference': document['reference'],
        'supplier': s['id'],
        'sv': s['version'],
        'sn': s['name'],
        'sr': s['orderingReference'],
      });
    }
    if (c.kind == 'order_create') {
      await execute(
        tx,
        'INSERT INTO $schema.purchasing_orders(company_id,id,location_id,reference,supplier_id,supplier_version,supplier_name,supplier_reference,created_by,changed_by,last_operation_id,last_kind) VALUES(CAST(@company AS uuid),CAST(@id AS uuid),CAST(@location AS uuid),@reference,CAST(@supplier AS uuid),@sv,@sn,@sr,CAST(@actor AS uuid),CAST(@actor AS uuid),CAST(@operation AS uuid),@kind)',
        p,
      );
    } else if (c.kind == 'order_save') {
      // Delete under the parent draft lock before advancing the aggregate.
      await execute(
        tx,
        'DELETE FROM $schema.purchasing_order_lines WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND order_id=CAST(@id AS uuid)',
        p,
      );
      for (final l in document!['lines'] as List) {
        await execute(
          tx,
          'INSERT INTO $schema.purchasing_order_lines(company_id,order_id,location_id,id,position,article_id,article_version,sku,name,unit,quantity_scaled) VALUES(CAST(@company AS uuid),CAST(@order AS uuid),CAST(@location AS uuid),CAST(@id AS uuid),@position,CAST(@articleId AS uuid),@articleVersion,@sku,@name,@unit,@scaled)',
          {
            'order': id,
            ...Map<String, Object?>.from(l as Map),
            'scaled': int.parse((l['quantity'] as String).replaceAll('.', '')),
          },
        );
      }
      await execute(
        tx,
        'UPDATE $schema.purchasing_orders SET version=version+1,changed_by=CAST(@actor AS uuid),changed_at=statement_timestamp(),last_operation_id=CAST(@operation AS uuid),last_kind=@kind,reference=@reference,supplier_id=CAST(@supplier AS uuid),supplier_version=@sv,supplier_name=@sn,supplier_reference=@sr WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)',
        p,
      );
    } else {
      final issue = c.kind == 'order_issue';
      await execute(
        tx,
        "UPDATE $schema.purchasing_orders SET version=version+1,changed_by=CAST(@actor AS uuid),changed_at=statement_timestamp(),last_operation_id=CAST(@operation AS uuid),last_kind=@kind,status=@state,${issue ? 'issued_by=CAST(@actor AS uuid),issued_at=statement_timestamp(),issue_operation_id=CAST(@operation AS uuid)' : 'terminal_by=CAST(@actor AS uuid),terminal_at=statement_timestamp(),terminal_reason=@reason,terminal_operation_id=CAST(@operation AS uuid)'} WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND id=CAST(@id AS uuid)",
        {
          ...p,
          'state': issue
              ? 'issued'
              : c.kind == 'order_close'
              ? 'closed'
              : 'cancelled',
        },
      );
    }
  }

  Future<List<Map<String, dynamic>>> page(
    TxSession tx, {
    required bool supplier,
    String? status,
    String? supplierId,
    String q = '',
    String? after,
  }) async {
    final r = await execute(
      tx,
      "SELECT $schema.purchasing_${supplier ? 'supplier' : 'order'}_json(company_id,id) FROM $schema.purchasing_${supplier ? 'suppliers' : 'orders'} WHERE company_id=CAST(@company AS uuid) ${supplier ? '' : 'AND location_id=CAST(@location AS uuid) AND (CAST(@supplier AS uuid) IS NULL OR supplier_id=CAST(@supplier AS uuid))'} AND (CAST(@status AS text) IS NULL OR status=@status) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) AND strpos(lower(${supplier ? 'name' : 'reference'}),lower(@q))>0 ORDER BY id LIMIT 51",
      {'supplier': supplierId, 'status': status, 'after': after, 'q': q},
    );
    return r.map((r) => Map<String, dynamic>.from(r.first as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> history(
    TxSession tx,
    String id, {
    required bool supplier,
    int? after,
  }) async {
    final rows = await execute(
      tx,
      'SELECT operation_id::text,kind,actor_id::text,applied_version,response_status,$schema.purchasing_time(accepted_at) AS accepted_at,result FROM $schema.purchasing_commands WHERE company_id=CAST(@company AS uuid) AND ${supplier ? 'supplier_id' : 'order_id'}=CAST(@id AS uuid) ${supplier ? '' : 'AND location_id=CAST(@location AS uuid)'} AND (CAST(@after AS bigint) IS NULL OR applied_version>CAST(@after AS bigint)) ORDER BY applied_version LIMIT 51',
      {'id': id, 'after': after},
    );
    return rows.map((r) {
      final j = r.toColumnMap();
      return <String, dynamic>{
        'operationId': j['operation_id'],
        'kind': j['kind'],
        'actorId': j['actor_id'],
        'appliedVersion': j['applied_version'],
        'responseStatus': j['response_status'],
        'acceptedAt': j['accepted_at'],
        'result': j['result'],
      };
    }).toList();
  }
}
