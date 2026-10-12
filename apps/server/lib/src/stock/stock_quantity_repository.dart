import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Stock-owned binding and conversion persistence. No Inventory tables are read.
class StockQuantityRepository {
  const StockQuantityRepository(this.schema, this.companyId, this.locationId);
  final String schema, companyId, locationId;
  Map<String, dynamic> get scope => {
    'company': companyId,
    'location': locationId,
  };
  Future<StockQuantityBindingDto?> binding(TxSession tx, String level) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text,stock_level_id::text,profile_id::text,profile_version,stock_version,unit,label,numerator,denominator,reason,recorded_by::text,recorded_at FROM $schema.stock_quantity_bindings WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND stock_level_id=CAST(@level AS uuid)',
      ),
      parameters: {...scope, 'level': level},
    );
    if (rows.isEmpty) return null;
    final r = rows.single.toColumnMap();
    return StockQuantityBindingDto(
      id: r['id'] as String,
      levelId: r['stock_level_id'] as String,
      profileId: r['profile_id'] as String,
      profileVersion: r['profile_version'] as int,
      stockVersion: r['stock_version'] as int,
      unit: r['unit'] as String,
      label: r['label'] as String,
      numerator: r['numerator'] as String,
      denominator: r['denominator'] as String,
      reason: r['reason'] as String,
      recordedBy: r['recorded_by'] as String,
      recordedAt: r['recorded_at'] as DateTime,
    );
  }

  Future<Map<String, dynamic>?> operation(
    TxSession tx,
    String operation,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT stock_level_id::text,location_id::text,recorded_by::text,payload,result FROM $schema.stock_quantity_corrections WHERE company_id=CAST(@company AS uuid) AND operation_id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': companyId, 'operation': operation},
    );
    if (rows.isNotEmpty) {
      return {'kind': 'correct', ...rows.single.toColumnMap()};
    }
    final bindings = await tx.execute(
      Sql.named(
        'SELECT stock_level_id::text,location_id::text,recorded_by::text FROM $schema.stock_quantity_bindings WHERE company_id=CAST(@company AS uuid) AND id=CAST(@operation AS uuid)',
      ),
      parameters: {'company': companyId, 'operation': operation},
    );
    return bindings.isEmpty
        ? null
        : {'kind': 'bind', ...bindings.single.toColumnMap()};
  }

  Future<void> insertBinding(
    TxSession tx,
    StockLevelDto level,
    String actor,
    Map<String, dynamic> command,
    String label,
    String numerator,
    String denominator,
  ) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.stock_quantity_bindings(id,company_id,location_id,article_id,stock_level_id,profile_id,profile_version,stock_version,unit,label,numerator,denominator,reason,recorded_by) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@article AS uuid),CAST(@level AS uuid),CAST(@profile AS uuid),@profileVersion,@stockVersion,@unit,@label,@numerator,@denominator,@reason,CAST(@actor AS uuid))',
      ),
      parameters: {
        ...scope,
        'id': command['operationId'],
        'article': level.articleId,
        'level': level.id,
        'profile': command['profileId'],
        'profileVersion': command['profileVersion'],
        'stockVersion': command['stockVersion'],
        'unit': command['unit'],
        'label': label,
        'numerator': numerator,
        'denominator': denominator,
        'reason': command['reason'],
        'actor': actor,
      },
    );
  }

  Future<Map<String, dynamic>> insertCorrection(
    TxSession tx,
    StockLevelDto level,
    String actor,
    Map<String, dynamic> command,
    StockConversionPreviewDto review,
    String? movement,
  ) async {
    // The database timestamp is part of immutable evidence and the original result.
    final time =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    final result = <String, dynamic>{
      'operationId': command['operationId'],
      'review': review.toJson(),
      'reason': command['reason'],
      'recordedBy': actor,
      'recordedAt': time.toUtc().toIso8601String(),
      'movementId': movement,
      'balanceVersion': level.version + (movement == null ? 0 : 1),
    };
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.stock_quantity_corrections(operation_id,company_id,location_id,article_id,stock_level_id,binding_id,profile_id,profile_version,expected_version,input_quantity,numerator,denominator,before_scaled,target_scaled,delta_scaled,movement_id,reason,recorded_by,recorded_at,payload,result) VALUES(CAST(@id AS uuid),CAST(@company AS uuid),CAST(@location AS uuid),CAST(@article AS uuid),CAST(@level AS uuid),CAST(@binding AS uuid),CAST(@profile AS uuid),@profileVersion,@version,@input,@numerator,@denominator,@before,@target,@delta,CAST(@movement AS uuid),@reason,CAST(@actor AS uuid),@time,CAST(@payload AS jsonb),CAST(@result AS jsonb))',
      ),
      parameters: {
        ...scope,
        'id': command['operationId'],
        'article': level.articleId,
        'level': level.id,
        'binding': review.bindingId,
        'profile': review.profileId,
        'profileVersion': review.profileVersion,
        'version': review.stockVersion,
        'input': review.inputQuantity,
        'numerator': review.numerator,
        'denominator': review.denominator,
        'before': stockQuantity(review.currentQuantity),
        'target': stockQuantity(review.targetQuantity),
        'delta': stockDelta(review.delta),
        'movement': movement,
        'reason': command['reason'],
        'actor': actor,
        'time': time,
        'payload': jsonEncode(command),
        'result': jsonEncode(result),
      },
    );
    return result;
  }

  Future<List<Map<String, dynamic>>> evidence(
    TxSession tx,
    String level, {
    String? after,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT result FROM $schema.stock_quantity_corrections WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND stock_level_id=CAST(@level AS uuid) AND (CAST(@after AS uuid) IS NULL OR operation_id>CAST(@after AS uuid)) ORDER BY operation_id LIMIT 51',
    ),
    parameters: {...scope, 'level': level, 'after': after},
  )).map((r) => quantityObject(r.first)).toList();
}
