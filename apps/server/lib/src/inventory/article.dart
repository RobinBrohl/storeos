import 'package:storeos_api_contracts/api_contracts.dart';

class ArticleStateConflict implements Exception {}

/// State rules stay independent of HTTP, Flutter and SQL.
class Article {
  const Article(this.view);

  final ArticleDto view;

  bool matches(ArticleEditInput input) =>
      view.sku == input.sku &&
      view.barcode == input.barcode &&
      view.name == input.name &&
      view.description == input.description &&
      view.unit == input.unit;

  void requireVersion(int expectedVersion) {
    if (view.version != expectedVersion) throw ArticleStateConflict();
  }

  /// Normalized mutable attributes that differ from the stored row.
  List<String> changedFields(ArticleEditInput input) => [
    if (view.sku != input.sku) 'sku',
    if (view.barcode != input.barcode) 'barcode',
    if (view.name != input.name) 'name',
    if (view.description != input.description) 'description',
    if (view.unit != input.unit) 'unit',
  ];
}
