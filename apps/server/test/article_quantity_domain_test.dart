import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/inventory/article_quantity.dart';
import 'package:storeos_server/src/stock/stock_quantity.dart';
import 'package:test/test.dart';

void main() {
  test('kg/g and mL/L remain rational and dimension constrained', () {
    expect(exactStockTarget('1250', measurementRatio('g', 'kg')), 1250);
    expect(exactStockTarget('1.25', measurementRatio('kg', 'g')), 1250000);
    expect(exactStockTarget('750', measurementRatio('mL', 'L')), 750);
    expect(exactStockTarget('1.25', measurementRatio('L', 'mL')), 1250000);
    expect(() => measurementRatio('kg', 'L'), throwsFormatException);
    expect(() => measurementRatio('piece', 'g'), throwsFormatException);
  });
  test('direct cartons/pieces and bottles/volume use Article contents', () {
    final cartons = QuantityRatio.decimal('12');
    expect(exactStockTarget('2.5', cartons), 30000);
    expect(
      exactStockTarget('30', QuantityRatio(BigInt.one, BigInt.from(12))),
      2500,
    );
    expect(exactStockTarget('2', QuantityRatio.decimal('0.75')), 1500);
    expect(
      () => exactStockTarget('1', QuantityRatio(BigInt.one, BigInt.from(12))),
      throwsFormatException,
    );
  });
  test(
    'reject fractional precision and overflow without rounded intermediate ints',
    () {
      expect(exactStockTarget('0.000001', measurementRatio('kg', 'g')), 1);
      expect(
        () => exactStockTarget('0.000001', measurementRatio('g', 'kg')),
        throwsFormatException,
      );
      expect(
        exactStockTarget(
          '999999999999.999',
          QuantityRatio(BigInt.one, BigInt.one),
        ),
        stockMaxScaled,
      );
      expect(
        () => exactStockTarget(
          '999999999999.999999',
          QuantityRatio(BigInt.one, BigInt.one),
        ),
        throwsFormatException,
      );
      expect(
        () => exactStockTarget('999999999999', measurementRatio('kg', 'g')),
        throwsFormatException,
      );
      final huge = QuantityRatio.decimal('999999999999.999999');
      final reduced = huge / huge;
      expect(exactStockTarget('999999999999.999', reduced), stockMaxScaled);
      expect(reduced.numerator, BigInt.one);
      expect(reduced.denominator, BigInt.one);
    },
  );
}
