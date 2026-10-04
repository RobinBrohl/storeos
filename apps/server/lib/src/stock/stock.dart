import 'package:storeos_api_contracts/api_contracts.dart';

class StockStateConflict implements Exception {}

/// State rules stay independent of HTTP, Flutter and SQL.
class StockLevel {
  const StockLevel(this.view);

  final StockLevelDto view;

  /// Exact scaled thousandths parsed from the canonical wire quantity.
  int get quantityScaled => stockQuantity(view.quantity);

  void requireVersion(int expectedVersion) {
    if (view.version != expectedVersion) throw StockStateConflict();
  }
}
