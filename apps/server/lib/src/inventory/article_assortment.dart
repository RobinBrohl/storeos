import 'package:storeos_api_contracts/api_contracts.dart';

class ArticleAssortmentStateConflict implements Exception {}

/// State rules stay independent of HTTP, Flutter and SQL. Membership state and
/// the embedded article state are deliberately separate.
class ArticleAssortment {
  const ArticleAssortment(this.view);

  final ArticleAssortmentDto view;

  void requireVersion(int expectedVersion) {
    if (view.version != expectedVersion) {
      throw ArticleAssortmentStateConflict();
    }
  }
}
