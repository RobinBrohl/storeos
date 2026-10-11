import 'package:postgres/postgres.dart';

/// Inventory owns catalog reads and effective local selection eligibility.
class PurchasingArticlePort {
  const PurchasingArticlePort(this.schema, this.company);
  final String schema, company;
  Future<Map<String, dynamic>?> read(
    TxSession tx,
    String location,
    String id,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT a.id::text,a.version,a.sku,a.name,a.unit,a.is_active,COALESCE(s.is_active,false) AS assorted FROM $schema.articles a LEFT JOIN $schema.article_location_assortment s ON s.company_id=a.company_id AND s.article_id=a.id AND s.location_id=CAST(@location AS uuid) WHERE a.company_id=CAST(@company AS uuid) AND a.id=CAST(@id AS uuid)',
      ),
      parameters: {'company': company, 'location': location, 'id': id},
    );
    return rows.isEmpty ? null : rows.single.toColumnMap();
  }

  Future<List<Map<String, dynamic>>> candidates(
    TxSession tx,
    String location,
    String q,
    String? after,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT a.id::text,a.version,a.sku,a.name,a.unit FROM $schema.articles a JOIN $schema.article_location_assortment s ON s.company_id=a.company_id AND s.article_id=a.id WHERE a.company_id=CAST(@company AS uuid) AND s.location_id=CAST(@location AS uuid) AND a.is_active AND s.is_active AND (CAST(@after AS uuid) IS NULL OR a.id>CAST(@after AS uuid)) AND (strpos(lower(a.name),lower(@q))>0 OR strpos(lower(a.sku),lower(@q))>0) ORDER BY a.id LIMIT 51',
      ),
      parameters: {
        'company': company,
        'location': location,
        'after': after,
        'q': q,
      },
    );
    return rows.map((r) => r.toColumnMap()).toList();
  }
}
