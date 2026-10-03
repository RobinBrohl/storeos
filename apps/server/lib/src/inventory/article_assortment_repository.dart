import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'article_assortment.dart';

/// Location-scoped assortment persistence. Every statement is bound to the
/// company and one location; the association is the only inventory table with a
/// location column.
class ArticleAssortmentRepository {
  ArticleAssortmentRepository(this.schema, this.companyId, this.locationId);

  final String schema, companyId, locationId;

  static const _columns =
      'a.id::text AS id, a.location_id::text AS location_id, a.is_active, '
      'a.version, a.created_at, a.updated_at, ar.id::text AS article_id, '
      'ar.sku, ar.barcode, ar.name, ar.unit, '
      'ar.is_active AS article_is_active';

  Map<String, dynamic> get _scope => {
    'company': companyId,
    'location': locationId,
  };

  Future<ArticleAssortmentDto?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM $schema.article_location_assortment a '
        'JOIN $schema.articles ar '
        'ON ar.id=a.article_id AND ar.company_id=a.company_id '
        'WHERE a.id=CAST(@id AS uuid) '
        'AND a.company_id=CAST(@company AS uuid) '
        'AND a.location_id=CAST(@location AS uuid)',
      ),
      parameters: {..._scope, 'id': id},
    );
    return rows.isEmpty ? null : _assortment(rows.single.toColumnMap());
  }

  Future<List<ArticleAssortmentDto>> page(
    TxSession tx, {
    String? after,
    String? query,
    bool? active,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT $_columns FROM $schema.article_location_assortment a '
      'JOIN $schema.articles ar '
      'ON ar.id=a.article_id AND ar.company_id=a.company_id '
      'WHERE a.company_id=CAST(@company AS uuid) '
      'AND a.location_id=CAST(@location AS uuid) '
      'AND (CAST(@after AS uuid) IS NULL OR a.id>CAST(@after AS uuid)) '
      'AND (CAST(@active AS boolean) IS NULL '
      'OR a.is_active=CAST(@active AS boolean)) '
      "AND (CAST(@q AS text) IS NULL "
      "OR ar.name ILIKE @pattern ESCAPE '\\' "
      "OR ar.sku ILIKE @pattern ESCAPE '\\') "
      'ORDER BY a.id LIMIT 51',
    ),
    parameters: {
      ..._scope,
      'after': after,
      'q': query,
      'pattern': query == null ? null : _likePattern(query),
      'active': active,
    },
  )).map((row) => _assortment(row.toColumnMap())).toList();

  Future<bool> idExists(TxSession tx, String id) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.article_location_assortment '
      'WHERE id=CAST(@id AS uuid) '
      'AND company_id=CAST(@company AS uuid) '
      'AND location_id=CAST(@location AS uuid)',
    ),
    parameters: {..._scope, 'id': id},
  )).isNotEmpty;

  Future<bool> pairExists(TxSession tx, String articleId) async =>
      (await tx.execute(
        Sql.named(
          'SELECT 1 FROM $schema.article_location_assortment '
          'WHERE company_id=CAST(@company AS uuid) '
          'AND location_id=CAST(@location AS uuid) '
          'AND article_id=CAST(@article AS uuid)',
        ),
        parameters: {..._scope, 'article': articleId},
      )).isNotEmpty;

  Future<void> insert(TxSession tx, ArticleAssortmentCreateInput input) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.article_location_assortment '
        '(id, company_id, article_id, location_id) '
        'VALUES(CAST(@id AS uuid), CAST(@company AS uuid), '
        'CAST(@article AS uuid), CAST(@location AS uuid))',
      ),
      parameters: {..._scope, 'id': input.id, 'article': input.articleId},
    );
  }

  Future<void> setActive(
    TxSession tx,
    ArticleAssortment current,
    bool active,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.article_location_assortment '
        'SET is_active=@active, version=version+1, '
        'updated_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid) '
        'AND company_id=CAST(@company AS uuid) '
        'AND location_id=CAST(@location AS uuid) '
        'AND version=@version',
      ),
      parameters: {
        ..._scope,
        'id': current.view.id,
        'version': current.view.version,
        'active': active,
      },
    );
    if (result.affectedRows != 1) throw ArticleAssortmentStateConflict();
  }
}

String _likePattern(String query) {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

ArticleAssortmentDto _assortment(Map<String, dynamic> row) =>
    ArticleAssortmentDto(
      id: row['id'] as String,
      locationId: row['location_id'] as String,
      isActive: row['is_active'] as bool,
      version: row['version'] as int,
      createdAt: row['created_at'] as DateTime,
      updatedAt: row['updated_at'] as DateTime,
      article: ArticleAssortmentArticleDto(
        id: row['article_id'] as String,
        sku: row['sku'] as String,
        barcode: row['barcode'] as String?,
        name: row['name'] as String,
        unit: row['unit'] as String,
        isActive: row['article_is_active'] as bool,
      ),
    );
