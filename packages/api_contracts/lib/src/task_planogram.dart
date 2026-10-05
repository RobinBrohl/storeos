import 'merchandising.dart';
import 'stock.dart' show stockQuantity;

/// Exact deployment occurrence; Company/Location come from the owning work.
class PlanogramGuidance {
  const PlanogramGuidance({
    required this.fixtureId,
    required this.assignmentId,
    required this.revisionId,
  });
  final String fixtureId, assignmentId, revisionId;
  factory PlanogramGuidance.fromJson(Map<String, dynamic> json) {
    _keys(json, {'fixtureId', 'assignmentId', 'revisionId'});
    return PlanogramGuidance(
      fixtureId: _id(json['fixtureId']),
      assignmentId: _id(json['assignmentId']),
      revisionId: _id(json['revisionId']),
    );
  }
  Map<String, dynamic> toJson() => {
    'fixtureId': fixtureId,
    'assignmentId': assignmentId,
    'revisionId': revisionId,
  };
  bool sameAs(PlanogramGuidance? other) =>
      other != null &&
      fixtureId == other.fixtureId &&
      assignmentId == other.assignmentId &&
      revisionId == other.revisionId;
}

/// Durable identities and immutable published structure, never live labels.
class RetainedLayoutInstruction {
  const RetainedLayoutInstruction({
    required this.pin,
    required this.planogramId,
    required this.revisionNumber,
    required this.content,
  });
  final PlanogramGuidance pin;
  final String planogramId;
  final int revisionNumber;
  final LayoutContent content;
  factory RetainedLayoutInstruction.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'fixtureId',
      'assignmentId',
      'revisionId',
      'planogramId',
      'revisionNumber',
      'content',
    });
    final number = jsonInteger(json['revisionNumber']);
    final content = LayoutContent.fromJson(_object(json['content']));
    if (number < 1 || !content.publishable) {
      throw const FormatException('Invalid retained layout.');
    }
    return RetainedLayoutInstruction(
      pin: PlanogramGuidance.fromJson({
        for (final k in ['fixtureId', 'assignmentId', 'revisionId']) k: json[k],
      }),
      planogramId: _id(json['planogramId']),
      revisionNumber: number,
      content: content,
    );
  }
  Map<String, dynamic> toJson() => {
    ...pin.toJson(),
    'planogramId': planogramId,
    'revisionNumber': revisionNumber,
    'content': content.toJson(),
  };
}

/// Explicitly current enrichment; absent Stock differs from unavailable or zero.
class RetainedLayoutContext {
  RetainedLayoutContext({
    required this.fixtureName,
    required this.fixtureKind,
    required this.fixtureRetired,
    required this.planogramRetired,
    required this.reassigned,
    required List<Map<String, dynamic>> articles,
    required this.stockContextStatus,
    required this.queriedAt,
  }) : articles = List.unmodifiable(
         articles.map((a) => Map<String, dynamic>.unmodifiable(a)),
       );
  final String fixtureName, fixtureKind;
  final bool fixtureRetired, planogramRetired, reassigned;
  final List<Map<String, dynamic>> articles;
  final StockContextStatus stockContextStatus;
  final DateTime queriedAt;
  factory RetainedLayoutContext.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'fixtureName',
      'fixtureKind',
      'fixtureRetired',
      'planogramRetired',
      'reassigned',
      'articles',
      'stockContextStatus',
      'queriedAt',
    });
    if (!fixtureKinds.contains(json['fixtureKind']) ||
        json['fixtureRetired'] is! bool ||
        json['planogramRetired'] is! bool ||
        json['reassigned'] is! bool ||
        json['articles'] is! List ||
        (json['articles'] as List).length > 100 ||
        json['queriedAt'] is! String) {
      throw const FormatException('Invalid current layout context.');
    }
    final time = DateTime.tryParse(json['queriedAt'] as String);
    if (time == null || !time.isUtc) {
      throw const FormatException('Invalid context time.');
    }
    return RetainedLayoutContext(
      fixtureName: merchandisingText(json['fixtureName']),
      fixtureKind: json['fixtureKind'] as String,
      fixtureRetired: json['fixtureRetired'] as bool,
      planogramRetired: json['planogramRetired'] as bool,
      reassigned: json['reassigned'] as bool,
      articles: (json['articles'] as List).map(_liveArticle).toList(),
      stockContextStatus: StockContextStatus.fromJson(
        json['stockContextStatus'],
      ),
      queriedAt: time,
    );
  }
  Map<String, dynamic> toJson() => {
    'fixtureName': fixtureName,
    'fixtureKind': fixtureKind,
    'fixtureRetired': fixtureRetired,
    'planogramRetired': planogramRetired,
    'reassigned': reassigned,
    'articles': articles,
    'stockContextStatus': stockContextStatus.name,
    'queriedAt': queriedAt.toUtc().toIso8601String(),
  };
}

class RetainedLayoutDto {
  const RetainedLayoutDto({
    required this.instruction,
    required this.currentContext,
  });
  final RetainedLayoutInstruction instruction;
  final RetainedLayoutContext currentContext;
  factory RetainedLayoutDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {'instruction', 'currentContext'});
    return RetainedLayoutDto(
      instruction: RetainedLayoutInstruction.fromJson(
        _object(json['instruction']),
      ),
      currentContext: RetainedLayoutContext.fromJson(
        _object(json['currentContext']),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'instruction': instruction.toJson(),
    'currentContext': currentContext.toJson(),
  };
}

String _id(Object? value) {
  final id = merchandisingId(value);
  if (id != value) throw const FormatException('Canonical UUID required.');
  return id;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Object required.');
  }
  return value;
}

void _keys(Map<String, dynamic> json, Set<String> expected) {
  if (json.length != expected.length ||
      !json.keys.toSet().containsAll(expected)) {
    throw const FormatException('Unexpected layout fields.');
  }
}

Map<String, dynamic> _liveArticle(Object? value) {
  final a = _object(value);
  _keys(a, {
    'id',
    'sku',
    'barcode',
    'name',
    'unit',
    'isActive',
    'assortmentIsActive',
    'stock',
  });
  _id(a['id']);
  merchandisingText(a['sku'], 64);
  merchandisingText(a['name']);
  merchandisingText(a['unit'], 32);
  if (a['barcode'] != null) merchandisingText(a['barcode'], 64);
  if (a['isActive'] is! bool ||
      (a['assortmentIsActive'] != null && a['assortmentIsActive'] is! bool)) {
    throw const FormatException('Invalid Article context.');
  }
  if (a['stock'] != null) {
    final stock = _object(a['stock']);
    _keys(stock, {'quantity', 'stockUnit'});
    stockQuantity(stock['quantity']);
    merchandisingText(stock['stockUnit'], 32);
  }
  return a;
}
