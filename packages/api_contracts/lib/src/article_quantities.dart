/// Explicit P4.15 transport contracts. Labels never identify measurement units.
library;

import 'json_numbers.dart';
import 'stock.dart';

const measurementUnits = {'g', 'kg', 'mL', 'L', 'piece'};
String quantityDimension(String unit) => switch (unit) {
  'g' || 'kg' => 'mass',
  'mL' || 'L' => 'volume',
  'piece' => 'count',
  _ => throw const FormatException('Unsupported measurement unit.'),
};

String quantityId(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Invalid quantity identity.');
  }
  return value.toLowerCase();
}

int quantityVersion(Object? value, {bool zero = false}) {
  if (value is! int ||
      value < (zero ? 0 : 1) ||
      value > maxIncrementableJsonSafeInteger) {
    throw const FormatException('Invalid quantity version.');
  }
  return value;
}

/// Canonical bounded decimal text, with no numeric JSON or exponent notation.
String quantityDecimal(Object? value, {bool positive = false}) {
  if (value is! String ||
      !RegExp(r'^[0-9]{1,12}(\.[0-9]{1,6})?$').hasMatch(value)) {
    throw const FormatException(
      'Use a decimal string with at most 12 integer and 6 fractional digits.',
    );
  }
  final parts = value.split('.');
  final whole = BigInt.parse(parts.first).toString();
  final fraction = parts.length == 1
      ? ''
      : parts.last.replaceFirst(RegExp(r'0+$'), '');
  final result = '$whole${fraction.isEmpty ? '' : '.$fraction'}';
  if (positive && result == '0') {
    throw const FormatException('Content must be positive.');
  }
  return result;
}

String quantityUnit(Object? value) {
  if (value is String && measurementUnits.contains(value)) return value;
  if (value is String && value.startsWith('pack:')) {
    return 'pack:${quantityId(value.substring(5))}';
  }
  throw const FormatException(
    'Select a measurement unit or explicit Article package.',
  );
}

void quantityKeys(Map<String, dynamic> json, Set<String> keys) {
  if (json.length != keys.length ||
      json.keys.any((key) => !keys.contains(key))) {
    throw const FormatException('Unsupported or missing quantity fields.');
  }
}

Map<String, dynamic> quantityObject(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected quantity object.');
  }
  return value;
}

String _text(Object? value, int limit) {
  if (value is! String) throw const FormatException('Expected text.');
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > limit ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) ||
      text.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
    throw const FormatException('Invalid quantity text.');
  }
  return text;
}

String quantityReason(Object? value) => _text(value, 500);

DateTime quantityInstant(Object? value) {
  final parsed = value is String ? DateTime.tryParse(value) : null;
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('Expected an exact UTC evidence timestamp.');
  }
  return parsed;
}

class ArticlePackageDto {
  const ArticlePackageDto({
    required this.id,
    required this.label,
    required this.content,
  });
  final String id, label, content;
  factory ArticlePackageDto.fromJson(Map<String, dynamic> json) {
    quantityKeys(json, {'id', 'label', 'content'});
    return ArticlePackageDto(
      id: quantityId(json['id']),
      label: _text(json['label'], 32),
      content: quantityDecimal(json['content'], positive: true),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'content': content,
  };
}

List<ArticlePackageDto> quantityPackages(Object? value) {
  if (value is! List || value.length > 16) {
    throw const FormatException('At most sixteen direct packages.');
  }
  final packages =
      value.map((v) => ArticlePackageDto.fromJson(quantityObject(v))).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
  if (packages.map((p) => p.id).toSet().length != packages.length ||
      packages.map((p) => p.label).toSet().length != packages.length) {
    throw const FormatException('Duplicate package identity or label.');
  }
  return List.unmodifiable(packages);
}

class ArticleQuantityProfileDto {
  ArticleQuantityProfileDto({
    required this.id,
    required this.articleId,
    required this.baseUnit,
    required this.version,
    required this.status,
    required List<ArticlePackageDto> packages,
    required this.reason,
    required this.recordedBy,
    required this.recordedAt,
  }) : packages = List.unmodifiable(packages);
  final String id, articleId, baseUnit, status, reason, recordedBy;
  final int version;
  final DateTime recordedAt;
  final List<ArticlePackageDto> packages;
  String get dimension => quantityDimension(baseUnit);
  factory ArticleQuantityProfileDto.fromJson(Map<String, dynamic> json) {
    quantityKeys(json, {
      'id',
      'articleId',
      'baseUnit',
      'version',
      'status',
      'packages',
      'reason',
      'recordedBy',
      'recordedAt',
    });
    final unit = quantityUnit(json['baseUnit']);
    quantityDimension(unit);
    if (!{'active', 'suspended'}.contains(json['status'])) {
      throw const FormatException('Invalid profile state.');
    }
    return ArticleQuantityProfileDto(
      id: quantityId(json['id']),
      articleId: quantityId(json['articleId']),
      baseUnit: unit,
      version: quantityVersion(json['version']),
      status: json['status'] as String,
      packages: quantityPackages(json['packages']),
      reason: quantityReason(json['reason']),
      recordedBy: quantityId(json['recordedBy']),
      recordedAt: quantityInstant(json['recordedAt']),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'baseUnit': baseUnit,
    'version': version,
    'status': status,
    'packages': packages.map((p) => p.toJson()).toList(),
    'reason': reason,
    'recordedBy': recordedBy,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

class StockQuantityBindingDto {
  const StockQuantityBindingDto({
    required this.id,
    required this.levelId,
    required this.profileId,
    required this.profileVersion,
    required this.stockVersion,
    required this.unit,
    required this.label,
    required this.numerator,
    required this.denominator,
    required this.reason,
    required this.recordedBy,
    required this.recordedAt,
  });
  final String id,
      levelId,
      profileId,
      unit,
      label,
      numerator,
      denominator,
      reason,
      recordedBy;
  final int profileVersion, stockVersion;
  final DateTime recordedAt;
  factory StockQuantityBindingDto.fromJson(Map<String, dynamic> json) {
    quantityKeys(json, {
      'id',
      'levelId',
      'profileId',
      'profileVersion',
      'stockVersion',
      'unit',
      'label',
      'numerator',
      'denominator',
      'reason',
      'recordedBy',
      'recordedAt',
    });
    return StockQuantityBindingDto(
      id: quantityId(json['id']),
      levelId: quantityId(json['levelId']),
      profileId: quantityId(json['profileId']),
      profileVersion: quantityVersion(json['profileVersion']),
      stockVersion: quantityVersion(json['stockVersion']),
      unit: quantityUnit(json['unit']),
      label: _text(json['label'], 32),
      numerator: quantityRatioInteger(json['numerator']),
      denominator: quantityRatioInteger(json['denominator']),
      reason: quantityReason(json['reason']),
      recordedBy: quantityId(json['recordedBy']),
      recordedAt: quantityInstant(json['recordedAt']),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'levelId': levelId,
    'profileId': profileId,
    'profileVersion': profileVersion,
    'stockVersion': stockVersion,
    'unit': unit,
    'label': label,
    'numerator': numerator,
    'denominator': denominator,
    'reason': reason,
    'recordedBy': recordedBy,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
  };
}

String quantityRatioInteger(Object? value) {
  if (value is! String || !RegExp(r'^[1-9][0-9]{0,39}$').hasMatch(value)) {
    throw const FormatException('Invalid exact ratio.');
  }
  return value;
}

/// Immutable review evidence. Every field is revalidated by the server on submit.
class StockConversionPreviewDto {
  const StockConversionPreviewDto({
    required this.levelId,
    required this.bindingId,
    required this.profileId,
    required this.profileVersion,
    required this.stockVersion,
    required this.baseUnit,
    required this.stockUnit,
    required this.inputUnit,
    required this.inputLabel,
    required this.inputQuantity,
    required this.numerator,
    required this.denominator,
    required this.currentQuantity,
    required this.targetQuantity,
    required this.delta,
  });
  final String levelId,
      bindingId,
      profileId,
      baseUnit,
      stockUnit,
      inputUnit,
      inputLabel,
      inputQuantity,
      numerator,
      denominator,
      currentQuantity,
      targetQuantity,
      delta;
  final int profileVersion, stockVersion;
  factory StockConversionPreviewDto.fromJson(Map<String, dynamic> json) {
    quantityKeys(json, {
      'levelId',
      'bindingId',
      'profileId',
      'profileVersion',
      'stockVersion',
      'baseUnit',
      'stockUnit',
      'inputUnit',
      'inputLabel',
      'inputQuantity',
      'numerator',
      'denominator',
      'currentQuantity',
      'targetQuantity',
      'delta',
    });
    final base = quantityUnit(json['baseUnit']);
    quantityDimension(base);
    return StockConversionPreviewDto(
      levelId: quantityId(json['levelId']),
      bindingId: quantityId(json['bindingId']),
      profileId: quantityId(json['profileId']),
      profileVersion: quantityVersion(json['profileVersion']),
      stockVersion: quantityVersion(json['stockVersion']),
      baseUnit: base,
      stockUnit: _text(json['stockUnit'], 32),
      inputUnit: quantityUnit(json['inputUnit']),
      inputLabel: _text(json['inputLabel'], 32),
      inputQuantity: quantityDecimal(json['inputQuantity']),
      numerator: quantityRatioInteger(json['numerator']),
      denominator: quantityRatioInteger(json['denominator']),
      currentQuantity: stockQuantityText(
        stockQuantity(json['currentQuantity']),
      ),
      targetQuantity: stockQuantityText(stockQuantity(json['targetQuantity'])),
      delta: stockDeltaText(stockDelta(json['delta'])),
    );
  }
  Map<String, dynamic> toJson() => {
    'levelId': levelId,
    'bindingId': bindingId,
    'profileId': profileId,
    'profileVersion': profileVersion,
    'stockVersion': stockVersion,
    'baseUnit': baseUnit,
    'stockUnit': stockUnit,
    'inputUnit': inputUnit,
    'inputLabel': inputLabel,
    'inputQuantity': inputQuantity,
    'numerator': numerator,
    'denominator': denominator,
    'currentQuantity': currentQuantity,
    'targetQuantity': targetQuantity,
    'delta': delta,
  };
}

/// Strict, deeply immutable original conversion evidence for reads and replay.
Map<String, dynamic> stockQuantityEvidence(Map<String, dynamic> json) {
  quantityKeys(json, {
    'operationId',
    'review',
    'reason',
    'recordedBy',
    'recordedAt',
    'movementId',
    'balanceVersion',
  });
  final operation = quantityId(json['operationId']);
  final review = StockConversionPreviewDto.fromJson(
    quantityObject(json['review']),
  );
  final movement = json['movementId'] == null
      ? null
      : quantityId(json['movementId']);
  final version = json['balanceVersion'];
  if (version is! int ||
      version < 1 ||
      version > maxJsonSafeInteger ||
      version != review.stockVersion + (review.delta == '0' ? 0 : 1) ||
      movement != (review.delta == '0' ? null : operation)) {
    throw const FormatException('Invalid conversion receipt outcome.');
  }
  return Map.unmodifiable({
    'operationId': operation,
    'review': Map<String, dynamic>.unmodifiable(review.toJson()),
    'reason': quantityReason(json['reason']),
    'recordedBy': quantityId(json['recordedBy']),
    'recordedAt': quantityInstant(json['recordedAt']).toIso8601String(),
    'movementId': movement,
    'balanceVersion': version,
  });
}

/// Canonical command fields, also used to freeze exact client retries.
Map<String, dynamic> articleQuantityCommand(
  String kind,
  Map<String, dynamic> json,
) {
  final fields = switch (kind) {
    'configure' => {
      'operationId',
      'profileId',
      'baseUnit',
      'packages',
      'reason',
    },
    'replace' => {'operationId', 'expectedVersion', 'packages', 'reason'},
    'suspend' => {'operationId', 'expectedVersion', 'reason'},
    _ => throw const FormatException('Unknown quantity command.'),
  };
  quantityKeys(json, fields);
  final result = <String, dynamic>{
    'operationId': quantityId(json['operationId']),
  };
  if (kind == 'configure') {
    result['profileId'] = quantityId(json['profileId']);
    final unit = quantityUnit(json['baseUnit']);
    quantityDimension(unit);
    result['baseUnit'] = unit;
  } else {
    result['expectedVersion'] = quantityVersion(json['expectedVersion']);
  }
  if (kind != 'suspend') {
    result['packages'] = List<Map<String, dynamic>>.unmodifiable(
      quantityPackages(
        json['packages'],
      ).map((p) => Map<String, dynamic>.unmodifiable(p.toJson())),
    );
  }
  result['reason'] = quantityReason(json['reason']);
  return Map.unmodifiable(result);
}

Map<String, dynamic> stockQuantityCommand(
  String kind,
  Map<String, dynamic> json,
) {
  final fields = switch (kind) {
    'bind' => {
      'operationId',
      'profileId',
      'profileVersion',
      'stockVersion',
      'unit',
      'reason',
    },
    'preview' => {
      'profileVersion',
      'stockVersion',
      'inputUnit',
      'inputQuantity',
    },
    'correct' => {'operationId', 'review', 'reason'},
    _ => throw const FormatException('Unknown Stock quantity command.'),
  };
  quantityKeys(json, fields);
  final result = <String, dynamic>{};
  if (kind != 'preview') {
    result['operationId'] = quantityId(json['operationId']);
  }
  if (kind == 'correct') {
    result['review'] = Map<String, dynamic>.unmodifiable(
      StockConversionPreviewDto.fromJson(
        quantityObject(json['review']),
      ).toJson(),
    );
  } else {
    if (kind == 'bind') result['profileId'] = quantityId(json['profileId']);
    result['profileVersion'] = quantityVersion(json['profileVersion']);
    result['stockVersion'] = quantityVersion(json['stockVersion']);
    if (kind == 'bind') result['unit'] = quantityUnit(json['unit']);
    if (kind == 'preview') {
      result['inputUnit'] = quantityUnit(json['inputUnit']);
      result['inputQuantity'] = quantityDecimal(json['inputQuantity']);
    }
  }
  if (kind != 'preview') result['reason'] = quantityReason(json['reason']);
  return Map.unmodifiable(result);
}
