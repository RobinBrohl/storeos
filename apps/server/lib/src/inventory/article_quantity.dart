import 'package:storeos_api_contracts/api_contracts.dart';

/// Exact dimension arithmetic for the bounded Inventory measurement contract.
class QuantityRatio {
  factory QuantityRatio(BigInt numerator, BigInt denominator) {
    if (numerator < BigInt.zero || denominator <= BigInt.zero) {
      throw const FormatException('Invalid rational quantity.');
    }
    final divisor = numerator.gcd(denominator);
    return QuantityRatio._(numerator ~/ divisor, denominator ~/ divisor);
  }
  const QuantityRatio._(this.numerator, this.denominator);
  factory QuantityRatio.decimal(String text) {
    final parts = quantityDecimal(text).split('.');
    final scale = parts.length == 1 ? 0 : parts.last.length;
    return QuantityRatio(
      BigInt.parse(parts.join()),
      BigInt.from(10).pow(scale),
    );
  }
  final BigInt numerator, denominator;
  QuantityRatio operator *(QuantityRatio other) => QuantityRatio(
    numerator * other.numerator,
    denominator * other.denominator,
  );
  QuantityRatio operator /(QuantityRatio other) => QuantityRatio(
    numerator * other.denominator,
    denominator * other.numerator,
  );
}

QuantityRatio measurementRatio(String unit, String baseUnit) {
  if (quantityDimension(unit) != quantityDimension(baseUnit)) {
    throw const FormatException('Incompatible quantity dimensions.');
  }
  BigInt scale(String value) =>
      BigInt.from(value == 'kg' || value == 'L' ? 1000 : 1);
  return QuantityRatio(scale(unit), scale(baseUnit));
}

class ArticleQuantityUnit {
  const ArticleQuantityUnit(this.unit, this.label, this.ratio);
  final String unit, label;
  final QuantityRatio ratio;
}

ArticleQuantityUnit resolveQuantityUnit(
  ArticleQuantityProfileDto profile,
  String unit,
) {
  if (measurementUnits.contains(unit)) {
    return ArticleQuantityUnit(
      unit,
      unit,
      measurementRatio(unit, profile.baseUnit),
    );
  }
  final matches = profile.packages.where((p) => 'pack:${p.id}' == unit);
  if (matches.length != 1) {
    throw const FormatException('Package is unavailable in this revision.');
  }
  final package = matches.single;
  return ArticleQuantityUnit(
    unit,
    package.label,
    QuantityRatio.decimal(package.content),
  );
}
