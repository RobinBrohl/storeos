/// Manual stock contracts: one stock level per company article and location
/// with an append-only movement ledger.
///
/// Quantities are exact scaled integer thousandths and travel only as decimal
/// strings (never JSON numbers). Manual targets and balances are non-negative;
/// movement deltas may be signed. `stockUnit` is the immutable unit-label
/// snapshot taken when the level was opened, so later Article edits can never
/// reinterpret historical stock. This package defines no receiving, waste,
/// count, sale, transfer, valuation, supplier or price behavior.
library;

import 'articles.dart';
import 'json_numbers.dart';

const int stockSearchMaxLength = 64;
const int stockNoteMaxLength = 500;

/// Largest exact scaled magnitude: 999999999999.999 as thousandths. The value
/// is below `2^53 - 1`, so shared Dart code may hold it as an integer on
/// Flutter Web; parsing and formatting still use integer arithmetic only.
const int stockMaxScaled = 999999999999999;

const Set<String> stockMovementKinds = {
  'opening',
  'adjustment',
  'count_correction',
};

final _targetQuantity = RegExp(r'^[0-9]{1,12}(\.[0-9]{1,3})?$');
final _signedQuantity = RegExp(r'^-?[0-9]{1,12}(\.[0-9]{1,3})?$');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _singleLineControls = RegExp(r'[\x00-\x1f\x7f]');

/// Parses a non-negative target or balance decimal string into thousandths.
int stockQuantity(Object? value) {
  if (value is! String || !_targetQuantity.hasMatch(value)) {
    throw const FormatException(
      'Menge: maximal 12 Vor- und 3 Nachkommastellen.',
    );
  }
  final scaled = _parseScaled(value);
  if (scaled > stockMaxScaled) {
    throw const FormatException('Menge außerhalb des Formats.');
  }
  return scaled;
}

/// Parses a signed movement delta decimal string into thousandths.
int stockDelta(Object? value) {
  if (value is! String || !_signedQuantity.hasMatch(value)) {
    throw const FormatException(
      'Delta: maximal 12 Vor- und 3 Nachkommastellen.',
    );
  }
  final scaled = _parseScaled(value.replaceFirst('-', ''));
  if (scaled > stockMaxScaled) {
    throw const FormatException('Delta außerhalb des Formats.');
  }
  return value.startsWith('-') ? -scaled : scaled;
}

int _parseScaled(String value) {
  final parts = value.split('.');
  final whole = int.parse(parts[0]);
  final fraction = parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0'));
  return whole * 1000 + fraction;
}

/// Canonical non-negative decimal text: no unnecessary leading zeros, no
/// trailing fractional zeros, no decimal point when the fraction is empty.
String stockQuantityText(int scaled) {
  if (scaled < 0 || scaled > stockMaxScaled) {
    throw const FormatException('Menge außerhalb des Formats.');
  }
  return _text(scaled);
}

/// Canonical signed decimal text; zero never carries a sign.
String stockDeltaText(int scaled) {
  if (scaled.abs() > stockMaxScaled) {
    throw const FormatException('Delta außerhalb des Formats.');
  }
  return scaled < 0 ? '-${_text(-scaled)}' : _text(scaled);
}

String _text(int scaled) {
  final fraction = (scaled % 1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${scaled ~/ 1000}${fraction.isEmpty ? '' : '.$fraction'}';
}

/// Canonical optional single-line note (open command): `null` stays `null`, a
/// non-null value must be trimmed, non-empty, at most 500 runes and free of
/// control characters and surrogates.
String? normalizeStockOpenNote(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Ungültige Notiz.');
  }
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > stockNoteMaxLength ||
      _singleLineControls.hasMatch(text) ||
      text.runes.any(_isSurrogate)) {
    throw const FormatException('Ungültige Notiz.');
  }
  return text;
}

/// Canonical required single-line correction reason (adjust command).
String normalizeStockAdjustNote(Object? value) {
  final text = normalizeStockOpenNote(value);
  if (text == null) {
    throw const FormatException('Begründung erforderlich.');
  }
  return text;
}

bool _isSurrogate(int rune) => rune >= 0xd800 && rune <= 0xdfff;

/// Compact company-article projection embedded in a stock level.
class StockArticleDto {
  const StockArticleDto({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.unit,
    required this.isActive,
  });

  final String id, sku, name, unit;
  final String? barcode;
  final bool isActive;

  factory StockArticleDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'sku', 'barcode', 'name', 'unit', 'isActive'});
    final isActive = json['isActive'];
    if (isActive is! bool) {
      throw const FormatException('Ungültiger Artikelzustand.');
    }
    return StockArticleDto(
      id: _id(json, 'id'),
      sku: normalizeArticleSku(json['sku']),
      barcode: normalizeArticleBarcode(json['barcode']),
      name: normalizeArticleText(
        json['name'],
        field: 'name',
        maxLength: articleNameMaxLength,
      ),
      unit: normalizeArticleText(
        json['unit'],
        field: 'unit',
        maxLength: articleUnitMaxLength,
      ),
      isActive: isActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sku': sku,
    'barcode': barcode,
    'name': name,
    'unit': unit,
    'isActive': isActive,
  };
}

/// Persisted stock level: the transactionally maintained current projection.
class StockLevelDto {
  const StockLevelDto({
    required this.id,
    required this.locationId,
    required this.articleId,
    required this.stockUnit,
    required this.quantity,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.article,
    required this.assortmentIsActive,
  });

  final String id, locationId, articleId;

  /// Immutable unit-label snapshot taken at opening.
  final String stockUnit;

  /// Canonical decimal string of the current on-hand quantity.
  final String quantity;
  final int version;
  final DateTime createdAt, updatedAt;
  final StockArticleDto article;
  final bool assortmentIsActive;

  factory StockLevelDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'locationId',
      'articleId',
      'stockUnit',
      'quantity',
      'version',
      'createdAt',
      'updatedAt',
      'article',
      'assortmentIsActive',
    });
    final version = json['version'];
    final assortmentIsActive = json['assortmentIsActive'];
    final article = json['article'];
    if (version is! int ||
        version < 1 ||
        version > maxJsonSafeInteger ||
        assortmentIsActive is! bool ||
        article is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger Bestandszustand.');
    }
    return StockLevelDto(
      id: _id(json, 'id'),
      locationId: _id(json, 'locationId'),
      articleId: _id(json, 'articleId'),
      stockUnit: normalizeArticleText(
        json['stockUnit'],
        field: 'stockUnit',
        maxLength: articleUnitMaxLength,
      ),
      quantity: stockQuantityText(stockQuantity(json['quantity'])),
      version: version,
      createdAt: _time(json, 'createdAt'),
      updatedAt: _time(json, 'updatedAt'),
      article: StockArticleDto.fromJson(article),
      assortmentIsActive: assortmentIsActive,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'locationId': locationId,
    'articleId': articleId,
    'stockUnit': stockUnit,
    'quantity': quantity,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'article': article.toJson(),
    'assortmentIsActive': assortmentIsActive,
  };
}

/// One immutable movement row; history inherits the level's immutable unit.
class StockMovementDto {
  const StockMovementDto({
    required this.id,
    required this.kind,
    required this.delta,
    required this.balanceAfter,
    required this.balanceVersion,
    required this.recordedAt,
    required this.recordedBy,
    required this.note,
    this.countId,
    this.countLineId,
    this.countObservationId,
  });

  final String id, kind;

  /// Canonical signed decimal string.
  final String delta;

  /// Canonical non-negative decimal string.
  final String balanceAfter;
  final int balanceVersion;
  final DateTime recordedAt;
  final String recordedBy;
  final String? note;
  final String? countId, countLineId, countObservationId;

  factory StockMovementDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'kind',
      'delta',
      'balanceAfter',
      'balanceVersion',
      'recordedAt',
      'recordedBy',
      'note',
      if (json['kind'] == 'count_correction') 'countId',
      if (json['kind'] == 'count_correction') 'countLineId',
      if (json['kind'] == 'count_correction') 'countObservationId',
    });
    final kind = json['kind'];
    final balanceVersion = json['balanceVersion'];
    if (kind is! String ||
        !stockMovementKinds.contains(kind) ||
        balanceVersion is! int ||
        balanceVersion < 1 ||
        balanceVersion > maxJsonSafeInteger) {
      throw const FormatException('Ungültige Bestandsbewegung.');
    }
    if (kind == 'count_correction' && stockDelta(json['delta']) == 0) {
      throw const FormatException('Invalid zero count correction.');
    }
    return StockMovementDto(
      id: _id(json, 'id'),
      kind: kind,
      delta: stockDeltaText(stockDelta(json['delta'])),
      balanceAfter: stockQuantityText(stockQuantity(json['balanceAfter'])),
      balanceVersion: balanceVersion,
      recordedAt: _time(json, 'recordedAt'),
      recordedBy: _id(json, 'recordedBy'),
      note: normalizeStockOpenNote(json['note']),
      countId: kind == 'count_correction' ? _id(json, 'countId') : null,
      countLineId: kind == 'count_correction' ? _id(json, 'countLineId') : null,
      countObservationId: kind == 'count_correction'
          ? _id(json, 'countObservationId')
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'delta': delta,
    'balanceAfter': balanceAfter,
    'balanceVersion': balanceVersion,
    'recordedAt': recordedAt.toUtc().toIso8601String(),
    'recordedBy': recordedBy,
    'note': note,
    if (kind == 'count_correction') 'countId': countId,
    if (kind == 'count_correction') 'countLineId': countLineId,
    if (kind == 'count_correction') 'countObservationId': countObservationId,
  };
}

/// Open input. All four keys are required; `note` may be `null`.
class StockOpenInput {
  const StockOpenInput({
    required this.id,
    required this.articleId,
    required this.quantity,
    required this.note,
  });

  final String id, articleId, quantity;
  final String? note;

  factory StockOpenInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'articleId', 'quantity', 'note'});
    return StockOpenInput(
      id: _id(json, 'id'),
      articleId: _id(json, 'articleId'),
      quantity: stockQuantityText(stockQuantity(json['quantity'])),
      note: normalizeStockOpenNote(json['note']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'quantity': quantity,
    'note': note,
  };
}

/// Absolute manual adjustment input. `movementId` is the operation identity;
/// `note` is the required correction reason.
class StockAdjustInput {
  const StockAdjustInput({
    required this.movementId,
    required this.expectedVersion,
    required this.quantity,
    required this.note,
  });

  final String movementId;
  final int expectedVersion;
  final String quantity;
  final String note;

  factory StockAdjustInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'movementId', 'expectedVersion', 'quantity', 'note'});
    return StockAdjustInput(
      movementId: _id(json, 'movementId'),
      expectedVersion: _version(json),
      quantity: stockQuantityText(stockQuantity(json['quantity'])),
      note: normalizeStockAdjustNote(json['note']),
    );
  }

  Map<String, dynamic> toJson() => {
    'movementId': movementId,
    'expectedVersion': expectedVersion,
    'quantity': quantity,
    'note': note,
  };
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException('Ungültige Felder.');
  }
}

String _id(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || !_uuid.hasMatch(value)) {
    throw FormatException('Ungültige ID: $key');
  }
  return value.toLowerCase();
}

/// A mutating command increments the persisted version by one, so the accepted
/// `expectedVersion` must stay incrementable and JSON-safe for Flutter Web.
int _version(Map<String, dynamic> json) {
  final value = json['expectedVersion'];
  if (value is! int || value < 1 || value > maxIncrementableJsonSafeInteger) {
    throw const FormatException('Ungültige Version.');
  }
  return value;
}

DateTime _time(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Ungültige UTC-Zeit: $key');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw FormatException('Ungültige UTC-Zeit: $key');
  }
  return parsed;
}
