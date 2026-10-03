/// Company-wide article/product-master contracts. This is master data only:
/// no stock, supplier, purchasing or price behavior is defined here.
library;

import 'json_numbers.dart';

const int articleSkuMaxLength = 64;
const int articleBarcodeMaxLength = 64;
const int articleNameMaxLength = 120;
const int articleUnitMaxLength = 32;
const int articleDescriptionMaxLength = 2000;
const int articleSearchMaxLength = 64;

/// Deterministic ASCII-only case fold for the company SKU uniqueness key.
///
/// Uppercase `A`-`Z` become lowercase; every other code unit is preserved.
/// This matches the database expression
/// `translate(sku, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz')`
/// exactly, so application and database agree without locale- or
/// collation-dependent case mapping. Non-ASCII letters compare exactly as
/// entered.
String articleSkuKey(String sku) {
  final buffer = StringBuffer();
  for (final unit in sku.codeUnits) {
    buffer.writeCharCode(unit >= 0x41 && unit <= 0x5a ? unit + 0x20 : unit);
  }
  return buffer.toString();
}

/// Canonical SKU: trimmed, non-empty, bounded, no control characters.
String normalizeArticleSku(Object? value) {
  final text = _requiredText(
    value,
    field: 'sku',
    maxLength: articleSkuMaxLength,
    controls: _singleLineControls,
  );
  return text;
}

/// Canonical required single-line text (name, unit).
String normalizeArticleText(
  Object? value, {
  required String field,
  required int maxLength,
}) => _requiredText(
  value,
  field: field,
  maxLength: maxLength,
  controls: _singleLineControls,
);

/// Canonical optional opaque text (barcode): blank becomes null.
String? normalizeArticleBarcode(Object? value) => _optionalText(
  value,
  field: 'barcode',
  maxLength: articleBarcodeMaxLength,
  controls: _singleLineControls,
);

/// Canonical optional description: blank becomes null, CRLF becomes LF.
String? normalizeArticleDescription(Object? value) => _optionalText(
  value,
  field: 'description',
  maxLength: articleDescriptionMaxLength,
  controls: _descriptionControls,
  normalizeNewlines: true,
);

String _requiredText(
  Object? value, {
  required String field,
  required int maxLength,
  required RegExp controls,
}) {
  if (value is! String) {
    throw FormatException('Ungültiges Feld: $field');
  }
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > maxLength ||
      controls.hasMatch(text) ||
      text.runes.any(_isSurrogate)) {
    throw FormatException('Ungültiges Feld: $field');
  }
  return text;
}

String? _optionalText(
  Object? value, {
  required String field,
  required int maxLength,
  required RegExp controls,
  bool normalizeNewlines = false,
}) {
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Ungültiges Feld: $field');
  }
  final text = (normalizeNewlines ? value.replaceAll('\r\n', '\n') : value)
      .trim();
  if (text.isEmpty) return null;
  if (text.runes.length > maxLength ||
      controls.hasMatch(text) ||
      text.runes.any(_isSurrogate)) {
    throw FormatException('Ungültiges Feld: $field');
  }
  return text;
}

bool _isSurrogate(int rune) => rune >= 0xd800 && rune <= 0xdfff;

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _singleLineControls = RegExp(r'[\x00-\x1f\x7f]');
final _descriptionControls = RegExp(r'[\x00-\x08\x0b-\x1f\x7f]');

/// Persisted article projection. `barcode` and `description` are optional.
class ArticleDto {
  const ArticleDto({
    required this.id,
    required this.companyId,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.description,
    required this.unit,
    required this.isActive,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id, companyId, sku, name, unit;
  final String? barcode, description;
  final bool isActive;
  final int version;
  final DateTime createdAt, updatedAt;

  factory ArticleDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'companyId',
      'sku',
      'barcode',
      'name',
      'description',
      'unit',
      'isActive',
      'version',
      'createdAt',
      'updatedAt',
    });
    final isActive = json['isActive'];
    final version = json['version'];
    if (isActive is! bool ||
        version is! int ||
        version < 1 ||
        version > maxJsonSafeInteger) {
      throw const FormatException('Ungültiger Artikelzustand.');
    }
    return ArticleDto(
      id: _id(json, 'id'),
      companyId: _id(json, 'companyId'),
      sku: normalizeArticleSku(json['sku']),
      barcode: normalizeArticleBarcode(json['barcode']),
      name: normalizeArticleText(
        json['name'],
        field: 'name',
        maxLength: articleNameMaxLength,
      ),
      description: normalizeArticleDescription(json['description']),
      unit: normalizeArticleText(
        json['unit'],
        field: 'unit',
        maxLength: articleUnitMaxLength,
      ),
      isActive: isActive,
      version: version,
      createdAt: _time(json, 'createdAt'),
      updatedAt: _time(json, 'updatedAt'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'sku': sku,
    'barcode': barcode,
    'name': name,
    'description': description,
    'unit': unit,
    'isActive': isActive,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Create input. All six keys are required; `barcode` and `description` may be
/// `null` but must be present. Empty optional strings are canonicalized to
/// `null`.
class ArticleCreateInput {
  const ArticleCreateInput({
    required this.id,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.description,
    required this.unit,
  });

  final String id, sku, name, unit;
  final String? barcode, description;

  factory ArticleCreateInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'sku', 'barcode', 'name', 'description', 'unit'});
    return ArticleCreateInput(
      id: _id(json, 'id'),
      sku: normalizeArticleSku(json['sku']),
      barcode: normalizeArticleBarcode(json['barcode']),
      name: normalizeArticleText(
        json['name'],
        field: 'name',
        maxLength: articleNameMaxLength,
      ),
      description: normalizeArticleDescription(json['description']),
      unit: normalizeArticleText(
        json['unit'],
        field: 'unit',
        maxLength: articleUnitMaxLength,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'sku': sku,
    'barcode': barcode,
    'name': name,
    'description': description,
    'unit': unit,
  };
}

/// Full replacement of the mutable article attributes.
class ArticleEditInput {
  const ArticleEditInput({
    required this.expectedVersion,
    required this.sku,
    required this.barcode,
    required this.name,
    required this.description,
    required this.unit,
  });

  final int expectedVersion;
  final String sku, name, unit;
  final String? barcode, description;

  factory ArticleEditInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'expectedVersion',
      'sku',
      'barcode',
      'name',
      'description',
      'unit',
    });
    return ArticleEditInput(
      expectedVersion: _version(json),
      sku: normalizeArticleSku(json['sku']),
      barcode: normalizeArticleBarcode(json['barcode']),
      name: normalizeArticleText(
        json['name'],
        field: 'name',
        maxLength: articleNameMaxLength,
      ),
      description: normalizeArticleDescription(json['description']),
      unit: normalizeArticleText(
        json['unit'],
        field: 'unit',
        maxLength: articleUnitMaxLength,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'expectedVersion': expectedVersion,
    'sku': sku,
    'barcode': barcode,
    'name': name,
    'description': description,
    'unit': unit,
  };
}

/// Deactivate/reactivate input.
class ArticleLifecycleInput {
  const ArticleLifecycleInput({required this.expectedVersion});

  final int expectedVersion;

  factory ArticleLifecycleInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'expectedVersion'});
    return ArticleLifecycleInput(expectedVersion: _version(json));
  }

  Map<String, dynamic> toJson() => {'expectedVersion': expectedVersion};
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
