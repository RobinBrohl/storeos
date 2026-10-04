import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class MerchandisingArticleReference {
  const MerchandisingArticleReference(this.article, this.assortmentIsActive);
  final StockArticleDto article;
  final bool? assortmentIsActive;
  Map<String, dynamic> toJson() => {
    ...article.toJson(),
    'assortmentIsActive': assortmentIsActive,
  };
}

/// Inventory-owned bounded read contract; null membership differs from inactive.
class MerchandisingArticlePort {
  const MerchandisingArticlePort(this.schema, this.companyId);
  final String schema, companyId;
  Future<List<MerchandisingArticleReference>> read(
    TxSession tx,
    Set<String> ids,
    String? location,
  ) async {
    if (ids.isEmpty) return [];
    final rows = await tx.execute(
      Sql.named(
        'SELECT a.id::text, a.sku,a.barcode,a.name,a.unit,a.is_active,m.is_active AS membership FROM $schema.articles a LEFT JOIN $schema.article_location_assortment m ON m.article_id=a.id AND m.company_id=a.company_id AND m.location_id=CAST(@location AS uuid) WHERE a.company_id=CAST(@company AS uuid) AND a.id=ANY(CAST(@ids AS uuid[])) ORDER BY a.id',
      ),
      parameters: {
        'company': companyId,
        'ids': ids.toList(),
        'location': location,
      },
    );
    return rows.map((r) {
      final j = r.toColumnMap();
      return MerchandisingArticleReference(
        StockArticleDto(
          id: j['id'] as String,
          sku: j['sku'] as String,
          barcode: j['barcode'] as String?,
          name: j['name'] as String,
          unit: j['unit'] as String,
          isActive: j['is_active'] as bool,
        ),
        j['membership'] as bool?,
      );
    }).toList();
  }

  Future<Map<String, dynamic>> candidates(
    TxSession tx, {
    required String q,
    String? after,
    bool includeInactive = false,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT id::text FROM $schema.articles WHERE company_id=CAST(@company AS uuid) AND (@inactive OR is_active) AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) AND (name ILIKE @q OR sku ILIKE @q OR barcode ILIKE @q) ORDER BY id LIMIT 51',
      ),
      parameters: {
        'company': companyId,
        'inactive': includeInactive,
        'after': after,
        'q':
            '%${q.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_')}%',
      },
    );
    final ids = rows.take(50).map((r) => r.first as String).toSet();
    final articles = await read(tx, ids, null);
    return {
      'items': articles.map((a) => a.article.toJson()).toList(),
      'nextCursor': rows.length > 50 ? ids.last : null,
    };
  }
}
