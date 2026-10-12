import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'article_quantity.dart';
import 'article_quantity_repository.dart';

export 'article_quantity.dart' show QuantityRatio, ArticleQuantityUnit;

/// Narrow Inventory read port. The caller establishes authorized resource scope
/// and shares its transaction; no foreign repository/table access is released.
class ArticleQuantityPort {
  ArticleQuantityPort(String schema, String companyId)
    : _repository = ArticleQuantityRepository(schema, companyId);
  final ArticleQuantityRepository _repository;
  Future<ArticleQuantityProfileDto?> current(TxSession tx, String articleId) =>
      _repository.find(tx, articleId);
  ArticleQuantityUnit resolve(ArticleQuantityProfileDto profile, String unit) =>
      resolveQuantityUnit(profile, unit);
}
