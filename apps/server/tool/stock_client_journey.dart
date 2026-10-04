import '../test/stock_integration_test.dart' show runStockClientJourney;
import 'package:test/test.dart';

void main() {
  test(
    'real Flutter Stock client / API / PostgreSQL journey',
    runStockClientJourney,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
