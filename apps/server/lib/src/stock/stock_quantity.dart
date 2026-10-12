import 'package:storeos_api_contracts/api_contracts.dart';
import '../inventory/article_quantity_port.dart';

/// The Stock storage scale remains unchanged; intermediate arithmetic is BigInt.
int exactStockTarget(String input, QuantityRatio ratio) {
  final converted = QuantityRatio.decimal(input) * ratio;
  final numerator = converted.numerator * BigInt.from(1000);
  if (numerator.remainder(converted.denominator) != BigInt.zero) {
    throw const FormatException(
      'Target cannot be represented in exact Stock thousandths.',
    );
  }
  final scaled = numerator ~/ converted.denominator;
  if (scaled > BigInt.from(stockMaxScaled)) {
    throw const FormatException('Stock target overflow.');
  }
  return scaled.toInt();
}
