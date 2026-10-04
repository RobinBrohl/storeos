import 'package:postgres/postgres.dart';

/// Minimal article reference for the stock module's open gate. Foreign modules
/// use public ports instead of inventory tables or repositories.
class StockArticleReference {
  const StockArticleReference({
    required this.id,
    required this.unit,
    required this.isActive,
  });

  final String id, unit;
  final bool isActive;
}

/// Public inventory read port for stock. Stock reads the released
/// `inventory_article_location_projection` view directly for list/search,
/// membership state and the embedded article summary; this port exists only to
/// distinguish an unknown article (404) from a known article without membership
/// (409 not_in_assortment) and to snapshot the normalized unit at opening.
class InventoryArticlePort {
  InventoryArticlePort(this.schema, this.companyId);

  final String schema, companyId;

  Future<StockArticleReference?> findArticle(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, unit, is_active FROM $schema.articles '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      ),
      parameters: {'company': companyId, 'id': id},
    );
    if (rows.isEmpty) return null;
    final row = rows.single.toColumnMap();
    return StockArticleReference(
      id: row['id'] as String,
      unit: row['unit'] as String,
      isActive: row['is_active'] as bool,
    );
  }
}
