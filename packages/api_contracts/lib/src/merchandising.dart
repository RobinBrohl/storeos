import 'dart:convert';
import 'json_numbers.dart';

int jsonInteger(Object? value) {
  if (value is! int || value.abs() > maxJsonSafeInteger) {
    throw const FormatException('Integer required.');
  }
  return value;
}

const fixtureKinds = {'shelf', 'refrigerated_case', 'counter', 'display'};
const layoutMaxBytes = 12 * 1024;
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
String merchandisingId(Object? value) {
  if (value is! String || !_uuid.hasMatch(value.toLowerCase())) {
    throw const FormatException('Invalid UUID.');
  }
  return value.toLowerCase();
}

String merchandisingText(Object? value, [int max = 120]) {
  if (value is! String) throw const FormatException('Text required.');
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > max ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(text) ||
      text.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
    throw const FormatException('Invalid text.');
  }
  return text;
}

int merchandisingVersion(Object? value, {bool writable = true}) {
  final version = jsonInteger(value);
  if (version < 1 ||
      version > maxJsonSafeInteger ||
      (writable && version == maxJsonSafeInteger)) {
    throw const FormatException('Invalid version.');
  }
  return version;
}

void _keys(
  Map<String, dynamic> json,
  Set<String> required, [
  Set<String> optional = const {},
]) {
  if (!json.keys.toSet().containsAll(required) ||
      json.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('Unexpected fields.');
  }
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Object required.');
  }
  return value;
}

class LayoutPlacement {
  const LayoutPlacement({
    required this.id,
    required this.articleId,
    this.facings,
  });
  final String id, articleId;
  final int? facings;
  factory LayoutPlacement.fromJson(Map<String, dynamic> j) {
    _keys(j, {'id', 'articleId'}, {'facings'});
    final facings = j['facings'] == null ? null : jsonInteger(j['facings']);
    if (facings != null && (facings < 1 || facings > maxJsonSafeInteger)) {
      throw const FormatException('Facings must be 1–999.');
    }
    return LayoutPlacement(
      id: merchandisingId(j['id']),
      articleId: merchandisingId(j['articleId']),
      facings: facings,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'articleId': articleId,
    'facings': facings,
  };
}

class LayoutZone {
  LayoutZone({
    required this.id,
    required this.label,
    required List<LayoutPlacement> placements,
  }) : placements = List.unmodifiable(placements);
  final String id, label;
  final List<LayoutPlacement> placements;
  factory LayoutZone.fromJson(Map<String, dynamic> j) {
    _keys(j, {'id', 'label', 'placements'});
    if (j['placements'] is! List || (j['placements'] as List).length > 100) {
      throw const FormatException('Invalid placements.');
    }
    return LayoutZone(
      id: merchandisingId(j['id']),
      label: merchandisingText(j['label'], 80),
      placements: (j['placements'] as List)
          .map((p) => LayoutPlacement.fromJson(_object(p)))
          .toList(),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'placements': placements.map((p) => p.toJson()).toList(),
  };
}

class LayoutContent {
  LayoutContent({required this.title, required List<LayoutZone> zones})
    : zones = List.unmodifiable(zones);
  final String title;
  final List<LayoutZone> zones;
  Set<String> get articleIds =>
      zones.expand((z) => z.placements).map((p) => p.articleId).toSet();
  factory LayoutContent.fromJson(Map<String, dynamic> j) {
    _keys(j, {'title', 'zones'});
    if (j['zones'] is! List || (j['zones'] as List).length > 10) {
      throw const FormatException('At most 10 zones.');
    }
    final result = LayoutContent(
      title: merchandisingText(j['title']),
      zones: (j['zones'] as List)
          .map((z) => LayoutZone.fromJson(_object(z)))
          .toList(),
    );
    final placements = result.zones.expand((z) => z.placements).toList();
    final ids = [
      ...result.zones.map((z) => z.id),
      ...placements.map((p) => p.id),
    ];
    if (placements.length > 100 ||
        ids.toSet().length != ids.length ||
        utf8.encode(result.canonical).length > layoutMaxBytes) {
      throw const FormatException(
        'Layout exceeds limits or has duplicate IDs.',
      );
    }
    return result;
  }
  String get canonical => jsonEncode(toJson());
  bool get publishable =>
      zones.isNotEmpty && zones.every((z) => z.placements.isNotEmpty);
  Map<String, dynamic> toJson() => {
    'title': title,
    'zones': zones.map((z) => z.toJson()).toList(),
  };
}

class FixtureInput {
  FixtureInput.fromJson(Map<String, dynamic> j, {bool create = true}) {
    _keys(j, {create ? 'id' : 'expectedVersion', 'name', 'kind'});
    id = create ? merchandisingId(j['id']) : null;
    expectedVersion = create
        ? null
        : merchandisingVersion(j['expectedVersion']);
    name = merchandisingText(j['name']);
    if (j['kind'] is! String) throw const FormatException('Invalid kind.');
    kind = j['kind'] as String;
    if (!fixtureKinds.contains(kind)) {
      throw const FormatException('Invalid fixture kind.');
    }
  }
  late final String? id;
  late final int? expectedVersion;
  late final String name, kind;
}

class PlanogramInput {
  PlanogramInput.fromJson(Map<String, dynamic> j) {
    _keys(j, {'id', 'authoringLocationId', 'originFixtureId'});
    id = merchandisingId(j['id']);
    authoringLocationId = j['authoringLocationId'] == null
        ? null
        : merchandisingId(j['authoringLocationId']);
    originFixtureId = j['originFixtureId'] == null
        ? null
        : merchandisingId(j['originFixtureId']);
    if (originFixtureId != null && authoringLocationId == null) {
      throw const FormatException('Origin requires location.');
    }
  }
  late final String id;
  late final String? authoringLocationId, originFixtureId;
}

class VersionCommand {
  VersionCommand.fromJson(Map<String, dynamic> j) {
    _keys(j, {'expectedVersion'});
    expectedVersion = merchandisingVersion(j['expectedVersion']);
  }
  late final int expectedVersion;
}

class DraftCommand {
  DraftCommand.fromJson(Map<String, dynamic> j, {bool create = false}) {
    _keys(j, {'expectedVersion', 'content', if (create) 'id'});
    id = create ? merchandisingId(j['id']) : null;
    expectedVersion = merchandisingVersion(j['expectedVersion']);
    content = LayoutContent.fromJson(_object(j['content']));
  }
  late final String? id;
  late final int expectedVersion;
  late final LayoutContent content;
}

class PublishCommand {
  PublishCommand.fromJson(Map<String, dynamic> j) {
    _keys(j, {'operationId', 'expectedVersion'});
    operationId = merchandisingId(j['operationId']);
    expectedVersion = merchandisingVersion(j['expectedVersion']);
  }
  late final String operationId;
  late final int expectedVersion;
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'expectedVersion': expectedVersion,
  };
}

class AssignCommand {
  AssignCommand.fromJson(Map<String, dynamic> j) {
    _keys(j, {'operationId', 'expectedVersion', 'revisionId'});
    operationId = merchandisingId(j['operationId']);
    revisionId = merchandisingId(j['revisionId']);
    expectedVersion = merchandisingVersion(j['expectedVersion']);
  }
  late final String operationId, revisionId;
  late final int expectedVersion;
  Map<String, dynamic> toJson() => {
    'operationId': operationId,
    'expectedVersion': expectedVersion,
    'revisionId': revisionId,
  };
}

/// Read envelopes retain server evidence while exposing typed resource identity.
class FixtureDto {
  FixtureDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j),
      id = merchandisingId(j['id']),
      locationId = merchandisingId(j['locationId']),
      name = merchandisingText(j['name']),
      kind = j['kind'] as String,
      status = j['status'] as String,
      version = merchandisingVersion(j['version'], writable: false),
      currentAssignmentId = j['currentAssignmentId'] as String?;
  final Map<String, dynamic> json;
  final String id, locationId, name, kind, status;
  final int version;
  final String? currentAssignmentId;
}

class PlanogramDto {
  PlanogramDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j),
      id = merchandisingId(j['id']),
      status = j['status'] as String,
      version = merchandisingVersion(j['version'], writable: false);
  final Map<String, dynamic> json;
  final String id, status;
  final int version;
}

class RevisionDto {
  RevisionDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j),
      id = merchandisingId(j['id']),
      planogramId = merchandisingId(j['planogramId']),
      status = j['status'] as String,
      revisionNumber = jsonInteger(j['revisionNumber']),
      content = LayoutContent.fromJson(_object(j['content'])),
      articles = List.unmodifiable(
        (j['articles'] as List? ?? []).cast<Map<String, dynamic>>(),
      );
  final Map<String, dynamic> json;
  final String id, planogramId, status;
  final int revisionNumber;
  final LayoutContent content;
  final List<Map<String, dynamic>> articles;
}

class AssignmentDto {
  AssignmentDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j),
      id = merchandisingId(j['id']),
      fixtureId = merchandisingId(j['fixtureId']),
      revisionId = merchandisingId(j['revisionId']),
      appliedVersion = merchandisingVersion(
        j['appliedVersion'],
        writable: false,
      );
  final Map<String, dynamic> json;
  final String id, fixtureId, revisionId;
  final int appliedVersion;
}

class MerchandisingPage<T> {
  MerchandisingPage.fromJson(
    Map<String, dynamic> j,
    T Function(Map<String, dynamic>) decode,
  ) : items = List.unmodifiable(
        (j['items'] as List).map((i) => decode(_object(i))),
      ),
      nextCursor = j['nextCursor'] as String?;
  final List<T> items;
  final String? nextCursor;
}

enum StockContextStatus {
  available,
  unavailable;

  static StockContextStatus fromJson(Object? value) => switch (value) {
    'available' => available,
    'unavailable' => unavailable,
    _ => throw const FormatException('Invalid stock context status.'),
  };
}

class LayoutViewDto {
  LayoutViewDto.fromJson(Map<String, dynamic> j)
    : fixture = FixtureDto.fromJson(_object(j['fixture'])),
      assignment = j['assignment'] == null
          ? null
          : AssignmentDto.fromJson(_object(j['assignment'])),
      revision = j['revision'] == null
          ? null
          : RevisionDto.fromJson(_object(j['revision'])),
      articles = List.unmodifiable(
        (j['articles'] as List).cast<Map<String, dynamic>>(),
      ),
      stockContextStatus = StockContextStatus.fromJson(j['stockContextStatus']),
      queriedAt = DateTime.parse(j['queriedAt'] as String),
      historical = j['historical'] as bool? ?? false;
  final FixtureDto fixture;
  final AssignmentDto? assignment;
  final RevisionDto? revision;
  final List<Map<String, dynamic>> articles;
  final StockContextStatus stockContextStatus;
  final DateTime queriedAt;
  final bool historical;
  Map<String, dynamic> toJson() => {
    'fixture': fixture.json,
    'assignment': assignment?.json,
    'revision': revision?.json,
    'articles': articles,
    'stockContextStatus': stockContextStatus.name,
    'queriedAt': queriedAt.toUtc().toIso8601String(),
    'historical': historical,
  };
}

class PrintViewDto {
  PrintViewDto.fromJson(Map<String, dynamic> j)
    : assignmentId = merchandisingId(j['assignmentId']),
      revisionId = merchandisingId(j['revisionId']),
      html = j['html'] as String;
  final String assignmentId, revisionId, html;
}

class LayoutDraftResultDto {
  LayoutDraftResultDto.fromJson(Map<String, dynamic> j)
    : planogram = PlanogramDto.fromJson(_object(j['planogram'])),
      revision = RevisionDto.fromJson(_object(j['revision']));
  final PlanogramDto planogram;
  final RevisionDto revision;
}

class LayoutPublishResultDto {
  LayoutPublishResultDto.fromJson(Map<String, dynamic> j)
    : revision = RevisionDto.fromJson(_object(j['revision'])),
      appliedVersion = merchandisingVersion(
        j['appliedVersion'],
        writable: false,
      ),
      replayed = j['replayed'] as bool;
  final RevisionDto revision;
  final int appliedVersion;
  final bool replayed;
}

class LayoutAssignResultDto {
  LayoutAssignResultDto.fromJson(Map<String, dynamic> j)
    : assignment = AssignmentDto.fromJson(_object(j['assignment'])),
      appliedVersion = merchandisingVersion(
        j['appliedVersion'],
        writable: false,
      ),
      applied = j['applied'] as bool,
      replayed = j['replayed'] as bool;
  final AssignmentDto assignment;
  final int appliedVersion;
  final bool applied, replayed;
}
