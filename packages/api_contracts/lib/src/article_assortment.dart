/// Location assortment contracts: one durable membership row saying that a
/// company location is configured to carry a company article.
///
/// Membership state (`isActive` on the association) is independent from the
/// embedded article's `isActive`. Effective operational availability is the
/// conjunction of both; this package deliberately stores only the raw states.
/// No stock, quantity, valuation, supplier, purchasing or price behavior is
/// defined here.
library;

import 'articles.dart';
import 'json_numbers.dart';

const int articleAssortmentSearchMaxLength = 64;

/// Compact company-article projection embedded in an assortment row.
class ArticleAssortmentArticleDto {
  const ArticleAssortmentArticleDto({
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

  factory ArticleAssortmentArticleDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'sku', 'barcode', 'name', 'unit', 'isActive'});
    final isActive = json['isActive'];
    if (isActive is! bool) {
      throw const FormatException('Ungültiger Artikelzustand.');
    }
    return ArticleAssortmentArticleDto(
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

/// Persisted location-assortment membership with the embedded article summary.
class ArticleAssortmentDto {
  const ArticleAssortmentDto({
    required this.id,
    required this.locationId,
    required this.isActive,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.article,
  });

  final String id, locationId;
  final bool isActive;
  final int version;
  final DateTime createdAt, updatedAt;
  final ArticleAssortmentArticleDto article;

  factory ArticleAssortmentDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'id',
      'locationId',
      'isActive',
      'version',
      'createdAt',
      'updatedAt',
      'article',
    });
    final isActive = json['isActive'];
    final version = json['version'];
    final article = json['article'];
    if (isActive is! bool ||
        version is! int ||
        version < 1 ||
        version > maxJsonSafeInteger ||
        article is! Map<String, dynamic>) {
      throw const FormatException('Ungültiger Sortimentszustand.');
    }
    return ArticleAssortmentDto(
      id: _id(json, 'id'),
      locationId: _id(json, 'locationId'),
      isActive: isActive,
      version: version,
      createdAt: _time(json, 'createdAt'),
      updatedAt: _time(json, 'updatedAt'),
      article: ArticleAssortmentArticleDto.fromJson(article),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'locationId': locationId,
    'isActive': isActive,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'article': article.toJson(),
  };
}

/// Enable input. Both keys are required; the server derives the company from
/// the revalidated session and the location from the route.
class ArticleAssortmentCreateInput {
  const ArticleAssortmentCreateInput({
    required this.id,
    required this.articleId,
  });

  final String id, articleId;

  factory ArticleAssortmentCreateInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'id', 'articleId'});
    return ArticleAssortmentCreateInput(
      id: _id(json, 'id'),
      articleId: _id(json, 'articleId'),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'articleId': articleId};
}

/// Deactivate/reactivate input.
class ArticleAssortmentLifecycleInput {
  const ArticleAssortmentLifecycleInput({required this.expectedVersion});

  final int expectedVersion;

  factory ArticleAssortmentLifecycleInput.fromJson(Map<String, dynamic> json) {
    _keys(json, {'expectedVersion'});
    return ArticleAssortmentLifecycleInput(expectedVersion: _version(json));
  }

  Map<String, dynamic> toJson() => {'expectedVersion': expectedVersion};
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException('Ungültige Felder.');
  }
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);

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
