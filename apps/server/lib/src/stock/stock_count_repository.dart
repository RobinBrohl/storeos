import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'stock_count.dart';

/// All statements are bound to the configured Company and execution Location.
class StockCountRepository {
  StockCountRepository(this.schema, this.companyId, this.locationId);
  final String schema, companyId, locationId;
  Map<String, Object?> get scope => {
    'company': companyId,
    'location': locationId,
  };
  String get whereScope =>
      'company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid)';
  Future<List<Map<String, dynamic>>> query(
    TxSession tx,
    String sql, [
    Map<String, Object?> parameters = const {},
  ]) async => (await tx.execute(
    Sql.named(sql),
    parameters: {...scope, ...parameters},
  )).map((r) => r.toColumnMap()).toList();

  Future<StockCount?> find(TxSession tx, String id) async {
    final rows = await query(
      tx,
      'SELECT to_jsonb(c) AS evidence FROM $schema.stock_counts c WHERE $whereScope AND id=CAST(@id AS uuid)',
      {'id': id},
    );
    return rows.isEmpty ? null : StockCount(_json(rows.single['evidence']));
  }

  Future<List<StockCount>> page(
    TxSession tx, {
    String? after,
    String? employeeId,
  }) async => (await query(
    tx,
    'SELECT to_jsonb(c) AS evidence FROM $schema.stock_counts c WHERE $whereScope AND (CAST(@employee AS uuid) IS NULL OR employee_id=CAST(@employee AS uuid)) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) ORDER BY id LIMIT 51',
    {'after': after, 'employee': employeeId},
  )).map((r) => StockCount(_json(r['evidence']))).toList();

  Future<List<StockCountLine>> lines(TxSession tx, String countId) async =>
      (await query(
            tx,
            'SELECT to_jsonb(l) AS line,to_jsonb(r) AS round,to_jsonb(o) AS observation,to_jsonb(s) AS stock FROM $schema.stock_count_lines l JOIN $schema.stock_count_rounds r ON r.id=l.current_round_id LEFT JOIN $schema.stock_count_observations o ON o.round_id=r.id JOIN $schema.stock_levels s ON s.id=l.stock_level_id WHERE l.company_id=CAST(@company AS uuid) AND l.location_id=CAST(@location AS uuid) AND l.count_id=CAST(@count AS uuid) ORDER BY l.position LIMIT 100',
            {'count': countId},
          ))
          .map(
            (r) => StockCountLine(
              _json(r['line']),
              StockCountRound(_json(r['round'])),
              r['observation'] == null
                  ? null
                  : StockCountObservation(_json(r['observation'])),
              _json(r['stock']),
            ),
          )
          .toList();

  Future<List<Map<String, dynamic>>> rounds(
    TxSession tx,
    String countId,
    String lineId, {
    int? before,
  }) => query(
    tx,
    'SELECT to_jsonb(r) AS round,to_jsonb(o) AS observation,(r.id=l.current_round_id) AS current FROM $schema.stock_count_rounds r JOIN $schema.stock_count_lines l ON l.id=r.line_id LEFT JOIN $schema.stock_count_observations o ON o.round_id=r.id WHERE r.company_id=CAST(@company AS uuid) AND r.location_id=CAST(@location AS uuid) AND r.count_id=CAST(@count AS uuid) AND r.line_id=CAST(@line AS uuid) AND (CAST(@before AS bigint) IS NULL OR r.number<CAST(@before AS bigint)) ORDER BY r.number DESC LIMIT 51',
    {'count': countId, 'line': lineId, 'before': before},
  );

  Future<StockCountCommand?> replay(
    TxSession tx,
    String operationId,
    String countId,
    String actor,
    String kind,
    Map<String, dynamic> payload,
  ) async {
    final rows = await query(
      tx,
      'SELECT to_jsonb(c) AS evidence, (count_id=CAST(@count AS uuid) AND actor_id=CAST(@actor AS uuid) AND kind=@kind AND payload=CAST(@payload AS jsonb) AND location_id=CAST(@location AS uuid)) AS exact FROM $schema.stock_count_commands c WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      {
        'operation': operationId,
        'count': countId,
        'actor': actor,
        'kind': kind,
        'payload': jsonEncode(payload),
      },
    );
    if (rows.isEmpty) return null;
    if (rows.single['exact'] != true) throw const CountOperationConflict();
    return StockCountCommand(_json(rows.single['evidence']));
  }

  Future<void> receipt(
    TxSession tx,
    String id,
    String operationId,
    String actor,
    String kind,
    Map<String, dynamic> payload,
    Map<String, dynamic> result,
  ) async {
    await query(
      tx,
      'INSERT INTO $schema.stock_count_commands (operation_id,count_id,company_id,location_id,actor_id,kind,payload,result) VALUES (CAST(@operation AS uuid),CAST(@count AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@actor AS uuid),@kind,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      {
        'operation': operationId,
        'count': id,
        'actor': actor,
        'kind': kind,
        'payload': jsonEncode(payload),
        'result': jsonEncode(result),
      },
    );
  }

  Future<void> open(
    TxSession tx,
    Map<String, dynamic> input,
    String actor,
  ) async {
    await query(
      tx,
      'INSERT INTO $schema.stock_counts (id,company_id,location_id,employee_id,created_by,purpose,preceding_count_id) VALUES (CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@employee AS uuid),CAST(@actor AS uuid),@purpose,CAST(@preceding AS uuid))',
      {
        'id': input['id'],
        'employee': input['employeeId'],
        'actor': actor,
        'purpose': input['purpose'],
        'preceding': input['precedingCountId'],
      },
    );
  }

  Future<void> insertLine(
    TxSession tx,
    String countId,
    String lineId,
    int position,
    StockLevelDto level,
  ) async {
    await query(
      tx,
      'INSERT INTO $schema.stock_count_lines (id,count_id,company_id,location_id,stock_level_id,article_id,position,stock_unit,sku,article_name,barcode) VALUES (CAST(@id AS uuid),CAST(@count AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@level AS uuid),CAST(@article AS uuid),@position,@unit,@sku,@name,@barcode)',
      {
        'id': lineId,
        'count': countId,
        'level': level.id,
        'article': level.articleId,
        'position': position,
        'unit': level.stockUnit,
        'sku': level.article.sku,
        'name': level.article.name,
        'barcode': level.article.barcode,
      },
    );
  }

  Future<void> appendRound(
    TxSession tx,
    String countId,
    String lineId,
    String roundId,
    int number,
    StockLevelDto level,
    String actor,
    String operationId,
    String? reason,
  ) async {
    await query(
      tx,
      'INSERT INTO $schema.stock_count_rounds (id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit,number,baseline_scaled,baseline_version,requested_by,provenance,operation_id,reason) VALUES (CAST(@id AS uuid),CAST(@line AS uuid),CAST(@count AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@level AS uuid),CAST(@article AS uuid),@unit,@number,@quantity,@version,CAST(@actor AS uuid),@provenance,CAST(@operation AS uuid),@reason)',
      {
        'id': roundId,
        'line': lineId,
        'count': countId,
        'level': level.id,
        'article': level.articleId,
        'unit': level.stockUnit,
        'number': number,
        'quantity': stockQuantity(level.quantity),
        'version': level.version,
        'actor': actor,
        'provenance': number == 1 ? 'open' : 'recount',
        'operation': operationId,
        'reason': reason,
      },
    );
    await query(
      tx,
      'UPDATE $schema.stock_count_lines SET current_round_id=CAST(@round AS uuid) WHERE $whereScope AND id=CAST(@line AS uuid) AND count_id=CAST(@count AS uuid)',
      {'round': roundId, 'line': lineId, 'count': countId},
    );
  }

  Future<void> observe(
    TxSession tx,
    StockCount count,
    StockCountLine line,
    Map<String, dynamic> input,
    String actor,
    String observationId,
  ) async {
    await query(
      tx,
      'INSERT INTO $schema.stock_count_observations (id,round_id,line_id,count_id,company_id,location_id,stock_level_id,article_id,stock_unit,employee_id,recorded_by,observed_scaled,note,operation_id) VALUES (CAST(@id AS uuid),CAST(@round AS uuid),CAST(@line AS uuid),CAST(@count AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@level AS uuid),CAST(@article AS uuid),@unit,CAST(@employee AS uuid),CAST(@actor AS uuid),@quantity,@note,CAST(@operation AS uuid))',
      {
        'id': observationId,
        'round': line.round.id,
        'line': line.id,
        'count': count.id,
        'level': line.identity['stock_level_id'],
        'article': line.identity['article_id'],
        'unit': line.identity['stock_unit'],
        'employee': count.employeeId,
        'actor': actor,
        'quantity': stockQuantity(input['quantity']),
        'note': input['note'],
        'operation': input['operationId'],
      },
    );
  }

  Future<void> advance(
    TxSession tx,
    StockCount count, {
    String status = 'open',
    String? actor,
    String? reason,
  }) async {
    await query(
      tx,
      "UPDATE $schema.stock_counts SET version=version+1,status=@status,approved_at=CASE WHEN @status='approved' THEN clock_timestamp() ELSE NULL END,approved_by=CASE WHEN @status='approved' THEN CAST(@actor AS uuid) ELSE NULL END,cancelled_at=CASE WHEN @status='cancelled' THEN clock_timestamp() ELSE NULL END,cancelled_by=CASE WHEN @status='cancelled' THEN CAST(@actor AS uuid) ELSE NULL END,cancellation_reason=@reason WHERE $whereScope AND id=CAST(@count AS uuid) AND version=@version AND status='open'",
      {
        'count': count.id,
        'version': count.version,
        'status': status,
        'actor': actor,
        'reason': reason,
      },
    );
  }

  Future<void> outcome(
    TxSession tx,
    StockCountLine line,
    String? movementId,
  ) async {
    await query(
      tx,
      'UPDATE $schema.stock_count_lines SET approved_observation_id=CAST(@observation AS uuid),discrepancy_scaled=@discrepancy,checked_stock_version=@version,movement_id=CAST(@movement AS uuid) WHERE $whereScope AND id=CAST(@line AS uuid)',
      {
        'line': line.id,
        'observation': line.observation!.id,
        'discrepancy': line.discrepancy,
        'version': line.round.version,
        'movement': movementId,
      },
    );
  }
}

Map<String, dynamic> countJson(Object? value) => _json(value);
Map<String, dynamic> _json(Object? value) => value is String
    ? (jsonDecode(value) as Map).cast<String, dynamic>()
    : (value as Map).cast<String, dynamic>();

class CountOperationConflict implements Exception {
  const CountOperationConflict();
}
