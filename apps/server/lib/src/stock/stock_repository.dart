import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'stock.dart';

/// Scope-bound movement record used for exact operation replay checks.
class StockMovementRecord {
  const StockMovementRecord({
    required this.id,
    required this.stockLevelId,
    required this.companyId,
    required this.locationId,
    required this.articleId,
    required this.kind,
    required this.deltaScaled,
    required this.balanceAfterScaled,
    required this.balanceVersion,
    required this.recordedBy,
    required this.note,
  });

  final String id, stockLevelId, companyId, locationId, articleId, kind;
  final int deltaScaled, balanceAfterScaled, balanceVersion;
  final String recordedBy;
  final String? note;
}

/// Stock persistence. Every statement is bound to the company and one location;
/// the released inventory projection view is the only inventory-owned object
/// this module reads directly.
class StockRepository {
  StockRepository(this.schema, this.companyId, this.locationId);

  final String schema, companyId, locationId;

  static const _levelColumns =
      'level.id::text AS id, level.location_id::text AS location_id, '
      'level.article_id::text AS article_id, level.stock_unit, '
      'level.quantity_scaled, level.version, level.created_at, '
      'level.updated_at, projection.sku, projection.barcode, '
      'projection.name, projection.unit, projection.article_is_active, '
      'projection.assortment_is_active';

  String get _levelSource =>
      'FROM $schema.stock_levels level '
      'JOIN $schema.inventory_article_location_projection projection '
      'ON projection.company_id=level.company_id '
      'AND projection.location_id=level.location_id '
      'AND projection.article_id=level.article_id ';

  Map<String, dynamic> get _scope => {
    'company': companyId,
    'location': locationId,
  };

  Future<StockLevelDto?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_levelColumns $_levelSource '
        'WHERE level.id=CAST(@id AS uuid) '
        'AND level.company_id=CAST(@company AS uuid) '
        'AND level.location_id=CAST(@location AS uuid)',
      ),
      parameters: {..._scope, 'id': id},
    );
    return rows.isEmpty ? null : _level(rows.single.toColumnMap());
  }

  Future<List<StockLevelDto>> page(
    TxSession tx, {
    String? after,
    String? query,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT $_levelColumns $_levelSource '
      'WHERE level.company_id=CAST(@company AS uuid) '
      'AND level.location_id=CAST(@location AS uuid) '
      'AND (CAST(@after AS uuid) IS NULL OR level.id>CAST(@after AS uuid)) '
      "AND (CAST(@q AS text) IS NULL "
      "OR projection.name ILIKE @pattern ESCAPE '\\' "
      "OR projection.sku ILIKE @pattern ESCAPE '\\') "
      'ORDER BY level.id LIMIT 51',
    ),
    parameters: {
      ..._scope,
      'after': after,
      'q': query,
      'pattern': query == null ? null : _likePattern(query),
    },
  )).map((row) => _level(row.toColumnMap())).toList();

  Future<bool> idExists(TxSession tx, String id) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.stock_levels '
      'WHERE id=CAST(@id AS uuid) '
      'AND company_id=CAST(@company AS uuid) '
      'AND location_id=CAST(@location AS uuid)',
    ),
    parameters: {..._scope, 'id': id},
  )).isNotEmpty;

  Future<bool> pairExists(TxSession tx, String articleId) async =>
      (await tx.execute(
        Sql.named(
          'SELECT 1 FROM $schema.stock_levels '
          'WHERE company_id=CAST(@company AS uuid) '
          'AND location_id=CAST(@location AS uuid) '
          'AND article_id=CAST(@article AS uuid)',
        ),
        parameters: {..._scope, 'article': articleId},
      )).isNotEmpty;

  /// Assortment membership state from the released projection view: `null`
  /// when no membership row exists, otherwise its live active flag.
  Future<bool?> assortmentActive(TxSession tx, String articleId) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT assortment_is_active '
        'FROM $schema.inventory_article_location_projection '
        'WHERE company_id=CAST(@company AS uuid) '
        'AND location_id=CAST(@location AS uuid) '
        'AND article_id=CAST(@article AS uuid)',
      ),
      parameters: {..._scope, 'article': articleId},
    );
    return rows.isEmpty
        ? null
        : rows.single.toColumnMap()['assortment_is_active'] as bool;
  }

  Future<void> insertLevel(
    TxSession tx, {
    required String id,
    required String articleId,
    required String stockUnit,
    required int quantityScaled,
  }) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.stock_levels '
        '(id, company_id, location_id, article_id, stock_unit, '
        'quantity_scaled) '
        'VALUES(CAST(@id AS uuid), CAST(@company AS uuid), '
        'CAST(@location AS uuid), CAST(@article AS uuid), @stockUnit, '
        '@quantity)',
      ),
      parameters: {
        ..._scope,
        'id': id,
        'article': articleId,
        'stockUnit': stockUnit,
        'quantity': quantityScaled,
      },
    );
  }

  Future<void> updateQuantity(
    TxSession tx, {
    required String id,
    required int expectedVersion,
    required int quantityScaled,
  }) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.stock_levels '
        'SET quantity_scaled=@quantity, version=version+1, '
        'updated_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid) '
        'AND company_id=CAST(@company AS uuid) '
        'AND location_id=CAST(@location AS uuid) '
        'AND version=@version',
      ),
      parameters: {
        ..._scope,
        'id': id,
        'version': expectedVersion,
        'quantity': quantityScaled,
      },
    );
    if (result.affectedRows != 1) throw StockStateConflict();
  }

  Future<void> insertMovement(
    TxSession tx, {
    required String id,
    required String stockLevelId,
    required String articleId,
    required String kind,
    required int deltaScaled,
    required int balanceAfterScaled,
    required int balanceVersion,
    required String recordedBy,
    required String? note,
  }) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.stock_movements '
        '(id, stock_level_id, company_id, location_id, article_id, kind, '
        'delta_scaled, balance_after_scaled, balance_version, recorded_by, '
        'note) '
        'VALUES(CAST(@id AS uuid), CAST(@level AS uuid), '
        'CAST(@company AS uuid), CAST(@location AS uuid), '
        'CAST(@article AS uuid), @kind, @delta, @balance, @version, '
        'CAST(@actor AS uuid), @note)',
      ),
      parameters: {
        ..._scope,
        'id': id,
        'level': stockLevelId,
        'article': articleId,
        'kind': kind,
        'delta': deltaScaled,
        'balance': balanceAfterScaled,
        'version': balanceVersion,
        'actor': recordedBy,
        'note': note,
      },
    );
  }

  /// Company-scoped lookup by movement id; the replay check compares the full
  /// level/location/actor/payload identity afterwards.
  Future<StockMovementRecord?> findMovement(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, stock_level_id::text AS stock_level_id, '
        'company_id::text AS company_id, location_id::text AS location_id, '
        'article_id::text AS article_id, kind, delta_scaled, '
        'balance_after_scaled, balance_version, recorded_by::text AS '
        'recorded_by, note FROM $schema.stock_movements '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      ),
      parameters: {'company': companyId, 'id': id},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return StockMovementRecord(
      id: row['id'] as String,
      stockLevelId: row['stock_level_id'] as String,
      companyId: row['company_id'] as String,
      locationId: row['location_id'] as String,
      articleId: row['article_id'] as String,
      kind: row['kind'] as String,
      deltaScaled: row['delta_scaled'] as int,
      balanceAfterScaled: row['balance_after_scaled'] as int,
      balanceVersion: row['balance_version'] as int,
      recordedBy: row['recorded_by'] as String,
      note: row['note'] as String?,
    );
  }

  Future<List<StockMovementDto>> movements(
    TxSession tx, {
    required String stockLevelId,
    int? beforeVersion,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT id::text AS id, kind, delta_scaled, balance_after_scaled, '
      'balance_version, recorded_at, recorded_by::text AS recorded_by, note '
      'FROM $schema.stock_movements '
      'WHERE company_id=CAST(@company AS uuid) '
      'AND location_id=CAST(@location AS uuid) '
      'AND stock_level_id=CAST(@level AS uuid) '
      'AND (CAST(@before AS bigint) IS NULL '
      'OR balance_version<CAST(@before AS bigint)) '
      'ORDER BY balance_version DESC LIMIT 51',
    ),
    parameters: {..._scope, 'level': stockLevelId, 'before': beforeVersion},
  )).map((row) => _movement(row.toColumnMap())).toList();
}

String _likePattern(String query) {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

StockLevelDto _level(Map<String, dynamic> row) => StockLevelDto(
  id: row['id'] as String,
  locationId: row['location_id'] as String,
  articleId: row['article_id'] as String,
  stockUnit: row['stock_unit'] as String,
  quantity: stockQuantityText(row['quantity_scaled'] as int),
  version: row['version'] as int,
  createdAt: row['created_at'] as DateTime,
  updatedAt: row['updated_at'] as DateTime,
  article: StockArticleDto(
    id: row['article_id'] as String,
    sku: row['sku'] as String,
    barcode: row['barcode'] as String?,
    name: row['name'] as String,
    unit: row['unit'] as String,
    isActive: row['article_is_active'] as bool,
  ),
  assortmentIsActive: row['assortment_is_active'] as bool,
);

StockMovementDto _movement(Map<String, dynamic> row) => StockMovementDto(
  id: row['id'] as String,
  kind: row['kind'] as String,
  delta: stockDeltaText(row['delta_scaled'] as int),
  balanceAfter: stockQuantityText(row['balance_after_scaled'] as int),
  balanceVersion: row['balance_version'] as int,
  recordedAt: row['recorded_at'] as DateTime,
  recordedBy: row['recorded_by'] as String,
  note: row['note'] as String?,
);
