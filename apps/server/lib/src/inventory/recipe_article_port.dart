import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

/// Inventory-owned Company-wide identity read. No Stock or mutation authority.
class RecipeArticlePort {
  const RecipeArticlePort(this.schema, this.companyId);
  final String schema, companyId;

  /// Current effective local availability for fresh Production use and warnings.
  Future<bool> effectivelyAvailable(
    TxSession tx,
    String location,
    String article,
  ) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.inventory_article_location_projection WHERE company_id=CAST(@company AS uuid) AND location_id=CAST(@location AS uuid) AND article_id=CAST(@article AS uuid) AND article_is_active AND assortment_is_active',
    ),
    parameters: {
      'company': companyId,
      'location': location,
      'article': article,
    },
  )).isNotEmpty;
  Future<List<RecipeArticleContext>> read(TxSession tx, Set<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text,sku,name,unit,is_active FROM $schema.inventory_recipe_article_projection '
        'WHERE company_id=CAST(@company AS uuid) AND id=ANY(CAST(@ids AS uuid[])) ORDER BY id',
      ),
      parameters: {'company': companyId, 'ids': ids.toList()},
    );
    return rows.map((r) {
      final j = r.toColumnMap();
      return RecipeArticleContext(
        RecipeArticleSnapshot(
          j['id'] as String,
          j['sku'] as String,
          j['name'] as String,
          j['unit'] as String,
        ),
        j['is_active'] as bool,
      );
    }).toList();
  }

  Future<List<RecipeArticleContext>> candidates(
    TxSession tx,
    String q,
    String? after,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text FROM $schema.inventory_recipe_article_projection WHERE company_id=CAST(@company AS uuid) '
        'AND is_active AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) '
        'AND (strpos(lower(name),lower(@q))>0 OR strpos(lower(sku),lower(@q))>0) ORDER BY id LIMIT 51',
      ),
      parameters: {'company': companyId, 'q': q, 'after': after},
    );
    return read(tx, rows.map((r) => r.first as String).toSet());
  }
}
