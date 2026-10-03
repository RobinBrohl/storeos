import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'article.dart';

/// Company-wide article persistence. Every statement is company scoped; the
/// article table has no location ownership column.
class ArticleRepository {
  ArticleRepository(this.schema, this.companyId);

  final String schema, companyId;

  static const _columns =
      'id::text, company_id::text, sku, barcode, name, description, unit, '
      'is_active, version, created_at, updated_at';

  Map<String, dynamic> get _scope => {'company': companyId};

  Future<ArticleDto?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM $schema.articles '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
      ),
      parameters: {..._scope, 'id': id},
    );
    return rows.isEmpty ? null : _article(rows.single.toColumnMap());
  }

  Future<List<ArticleDto>> page(
    TxSession tx, {
    String? after,
    String? query,
    bool? active,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT $_columns FROM $schema.articles '
      'WHERE company_id=CAST(@company AS uuid) '
      'AND (CAST(@after AS uuid) IS NULL OR id>CAST(@after AS uuid)) '
      'AND (CAST(@active AS boolean) IS NULL '
      'OR is_active=CAST(@active AS boolean)) '
      "AND (CAST(@q AS text) IS NULL "
      "OR name ILIKE @pattern ESCAPE '\\' "
      "OR sku ILIKE @pattern ESCAPE '\\') "
      'ORDER BY id LIMIT 51',
    ),
    parameters: {
      ..._scope,
      'after': after,
      'q': query,
      'pattern': query == null ? null : _likePattern(query),
      'active': active,
    },
  )).map((row) => _article(row.toColumnMap())).toList();

  Future<bool> idExists(TxSession tx, String id) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.articles '
      'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid)',
    ),
    parameters: {..._scope, 'id': id},
  )).isNotEmpty;

  Future<bool> skuKeyExists(
    TxSession tx,
    String skuKey, {
    String? excludeId,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.articles '
      'WHERE company_id=CAST(@company AS uuid) AND sku_key=@skuKey '
      'AND (CAST(@exclude AS uuid) IS NULL OR id<>CAST(@exclude AS uuid))',
    ),
    parameters: {..._scope, 'skuKey': skuKey, 'exclude': excludeId},
  )).isNotEmpty;

  Future<bool> barcodeExists(
    TxSession tx,
    String barcode, {
    String? excludeId,
  }) async => (await tx.execute(
    Sql.named(
      'SELECT 1 FROM $schema.articles '
      'WHERE company_id=CAST(@company AS uuid) AND barcode=@barcode '
      'AND (CAST(@exclude AS uuid) IS NULL OR id<>CAST(@exclude AS uuid))',
    ),
    parameters: {..._scope, 'barcode': barcode, 'exclude': excludeId},
  )).isNotEmpty;

  Future<void> insert(TxSession tx, ArticleCreateInput input) async {
    await tx.execute(
      Sql.named(
        'INSERT INTO $schema.articles '
        '(id, company_id, sku, barcode, name, description, unit) '
        'VALUES(CAST(@id AS uuid), CAST(@company AS uuid), @sku, @barcode, '
        '@name, @description, @unit)',
      ),
      parameters: {
        ..._scope,
        'id': input.id,
        'sku': input.sku,
        'barcode': input.barcode,
        'name': input.name,
        'description': input.description,
        'unit': input.unit,
      },
    );
  }

  Future<void> edit(
    TxSession tx,
    Article article,
    ArticleEditInput input,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.articles SET sku=@sku, barcode=@barcode, name=@name, '
        'description=@description, unit=@unit, version=version+1, '
        'updated_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) '
        'AND version=@version',
      ),
      parameters: {
        ..._scope,
        'id': article.view.id,
        'version': article.view.version,
        'sku': input.sku,
        'barcode': input.barcode,
        'name': input.name,
        'description': input.description,
        'unit': input.unit,
      },
    );
    if (result.affectedRows != 1) throw ArticleStateConflict();
  }

  Future<void> setActive(TxSession tx, Article article, bool active) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE $schema.articles SET is_active=@active, version=version+1, '
        'updated_at=clock_timestamp() '
        'WHERE id=CAST(@id AS uuid) AND company_id=CAST(@company AS uuid) '
        'AND version=@version',
      ),
      parameters: {
        ..._scope,
        'id': article.view.id,
        'version': article.view.version,
        'active': active,
      },
    );
    if (result.affectedRows != 1) throw ArticleStateConflict();
  }
}

String _likePattern(String query) {
  final escaped = query
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
  return '%$escaped%';
}

ArticleDto _article(Map<String, dynamic> row) => ArticleDto(
  id: row['id'] as String,
  companyId: row['company_id'] as String,
  sku: row['sku'] as String,
  barcode: row['barcode'] as String?,
  name: row['name'] as String,
  description: row['description'] as String?,
  unit: row['unit'] as String,
  isActive: row['is_active'] as bool,
  version: row['version'] as int,
  createdAt: row['created_at'] as DateTime,
  updatedAt: row['updated_at'] as DateTime,
);
