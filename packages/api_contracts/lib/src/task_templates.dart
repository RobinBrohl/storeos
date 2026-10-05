import 'dart:convert';
import 'task_numbers.dart';
import 'task_planogram.dart';

/// Versioned instruction content, not execution results or a workflow engine.
class TaskTemplateContent {
  TaskTemplateContent({
    required this.title,
    required List<TemplateStep> steps,
    this.schemaVersion = 1,
    this.knowledgeGuidance,
    this.planogramGuidance,
  }) : steps = List.unmodifiable(steps);
  final int schemaVersion;
  final String title;
  final List<TemplateStep> steps;
  final KnowledgeGuidance? knowledgeGuidance;
  final PlanogramGuidance? planogramGuidance;
  factory TaskTemplateContent.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'schemaVersion',
      'title',
      'steps',
      if ({3, 4}.contains(json['schemaVersion'])) 'knowledgeGuidance',
      if (json['schemaVersion'] == 4) 'planogramGuidance',
    });
    if (json['schemaVersion'] is! int ||
        !{1, 2, 3, 4}.contains(json['schemaVersion']) ||
        json['steps'] is! List) {
      throw const FormatException('Ungültiges Inhaltsschema.');
    }
    final title = _text(json, 'title').trim();
    if (title.isEmpty ||
        title.runes.length > 120 ||
        _controls.hasMatch(title)) {
      throw const FormatException(
        'Der Titel benötigt 1 bis 120 Zeichen ohne Steuerzeichen.',
      );
    }
    final steps = (json['steps'] as List)
        .map((raw) => TemplateStep.fromJson(_object(raw)))
        .toList();
    if (steps.length > 20 ||
        steps.map((s) => s.id).toSet().length != steps.length) {
      throw const FormatException(
        'Maximal 20 Schritte mit eindeutigen IDs sind erlaubt.',
      );
    }
    if (json['schemaVersion'] == 1 &&
        steps.any((s) => s.type != 'confirmation')) {
      throw const FormatException('Zahlenschritte benötigen Schema 2.');
    }
    final value = TaskTemplateContent(
      title: title,
      steps: steps,
      schemaVersion: json['schemaVersion'] as int,
      knowledgeGuidance: json['knowledgeGuidance'] == null
          ? null
          : KnowledgeGuidance.fromJson(_object(json['knowledgeGuidance'])),
      planogramGuidance: json['planogramGuidance'] == null
          ? null
          : PlanogramGuidance.fromJson(_object(json['planogramGuidance'])),
    );
    if (utf8.encode(jsonEncode(value.toJson())).length > 8192) {
      throw const FormatException(
        'Der gesamte Vorlageninhalt darf 8 KiB nicht überschreiten.',
      );
    }
    return value;
  }
  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'title': title,
    'steps': steps.map((s) => s.toJson()).toList(),
    if ({3, 4}.contains(schemaVersion))
      'knowledgeGuidance': knowledgeGuidance?.toJson(),
    if (schemaVersion == 4) 'planogramGuidance': planogramGuidance?.toJson(),
  };
}

/// Exact approved Knowledge identity. Scope comes from the owning work context.
class KnowledgeGuidance {
  const KnowledgeGuidance({required this.articleId, required this.revisionId});
  final String articleId, revisionId;
  factory KnowledgeGuidance.fromJson(Map<String, dynamic> json) {
    _keys(json, {'articleId', 'revisionId'});
    return KnowledgeGuidance(
      articleId: _id(json, 'articleId'),
      revisionId: _id(json, 'revisionId'),
    );
  }
  Map<String, dynamic> toJson() => {
    'articleId': articleId,
    'revisionId': revisionId,
  };
  bool sameAs(KnowledgeGuidance? other) =>
      other != null &&
      articleId == other.articleId &&
      revisionId == other.revisionId;
}

/// Safe historical instruction resolved by the server from an authorized task.
class TaskKnowledgeDto {
  const TaskKnowledgeDto({
    required this.taskId,
    required this.articleId,
    required this.revisionId,
    required this.revisionNumber,
    required this.title,
    required this.body,
    required this.publishedAt,
    required this.superseded,
    required this.articleRetired,
  });
  final String taskId, articleId, revisionId, title, body;
  final int revisionNumber;
  final DateTime publishedAt;
  final bool superseded, articleRetired;
  factory TaskKnowledgeDto.fromJson(Map<String, dynamic> json) {
    _keys(json, {
      'taskId',
      'articleId',
      'revisionId',
      'revisionNumber',
      'title',
      'body',
      'publishedAt',
      'superseded',
      'articleRetired',
    });
    if (json['superseded'] is! bool || json['articleRetired'] is! bool) {
      throw const FormatException('Invalid instruction lifecycle.');
    }
    return TaskKnowledgeDto(
      taskId: _id(json, 'taskId'),
      articleId: _id(json, 'articleId'),
      revisionId: _id(json, 'revisionId'),
      revisionNumber: _positive(json, 'revisionNumber'),
      title: _text(json, 'title'),
      body: _text(json, 'body'),
      publishedAt: _time(json, 'publishedAt'),
      superseded: json['superseded'] as bool,
      articleRetired: json['articleRetired'] as bool,
    );
  }
  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'articleId': articleId,
    'revisionId': revisionId,
    'revisionNumber': revisionNumber,
    'title': title,
    'body': body,
    'publishedAt': publishedAt.toUtc().toIso8601String(),
    'superseded': superseded,
    'articleRetired': articleRetired,
  };
}

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
);
final _controls = RegExp(r'[\x00-\x1f\x7f]');
final _instructionControls = RegExp(r'[\x00-\x08\x0b-\x1f\x7f]');

class TemplateStep {
  const TemplateStep({
    required this.id,
    required this.instruction,
    this.type = 'confirmation',
    this.unit,
    this.minimum,
    this.maximum,
  });
  final String type;
  final String? unit, minimum, maximum;
  final String id, instruction;
  factory TemplateStep.fromJson(Map<String, dynamic> json) {
    final numeric = json['type'] == 'number';
    _keys(json, {
      'id',
      'type',
      'instruction',
      if (numeric) ...{'unit', 'minimum', 'maximum'},
    });
    final id = _text(json, 'id').toLowerCase();
    final instruction = _text(
      json,
      'instruction',
    ).replaceAll('\r\n', '\n').trim();
    if (!_uuid.hasMatch(id) ||
        !{'confirmation', 'number'}.contains(json['type']) ||
        instruction.isEmpty ||
        instruction.runes.length > 1000 ||
        _instructionControls.hasMatch(instruction)) {
      throw const FormatException(
        'Ein Schritt benötigt eine gültige ID und 1 bis 1.000 Zeichen Anleitungstext.',
      );
    }
    if (!numeric) return TemplateStep(id: id, instruction: instruction);
    final unit = _text(json, 'unit').trim();
    final low = taskNumber(json['minimum']), high = taskNumber(json['maximum']);
    if (unit.isEmpty ||
        unit.runes.length > 32 ||
        _controls.hasMatch(unit) ||
        low > high) {
      throw const FormatException(
        'Einheit (1–32 Zeichen) und gültige inklusive Grenzen erforderlich.',
      );
    }
    return TemplateStep(
      id: id,
      instruction: instruction,
      type: 'number',
      unit: unit,
      minimum: taskNumberText(low),
      maximum: taskNumberText(high),
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    if (type == 'number') ...{
      'unit': unit,
      'minimum': minimum,
      'maximum': maximum,
    },
    'instruction': instruction,
  };
}

class TaskTemplateDto {
  const TaskTemplateDto({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.version,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.draftId,
    required this.publishedId,
  });
  final String id, companyId, locationId, title;
  final int version;
  final DateTime createdAt, updatedAt;
  final String? draftId, publishedId;
  factory TaskTemplateDto.fromJson(Map<String, dynamic> json) =>
      TaskTemplateDto(
        id: _id(json, 'id'),
        companyId: _id(json, 'companyId'),
        locationId: _id(json, 'locationId'),
        version: _positive(json, 'version'),
        title: _text(json, 'title'),
        createdAt: _time(json, 'createdAt'),
        updatedAt: _time(json, 'updatedAt'),
        draftId: json['draftId'] == null ? null : _id(json, 'draftId'),
        publishedId: json['publishedId'] == null
            ? null
            : _id(json, 'publishedId'),
      );
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'locationId': locationId,
    'version': version,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'draftId': draftId,
    'publishedId': publishedId,
  };
}

class TemplateRevisionDto {
  const TemplateRevisionDto({
    required this.id,
    required this.templateId,
    required this.number,
    required this.status,
    required this.title,
    required this.createdAt,
    required this.publishedAt,
    required this.publishedBy,
    this.content,
  });
  final String id, templateId, status, title;
  final int number;
  final DateTime createdAt;
  final DateTime? publishedAt;
  final String? publishedBy;
  final TaskTemplateContent? content;
  bool get isDraft => status == 'draft';
  factory TemplateRevisionDto.fromJson(Map<String, dynamic> json) {
    final status = _text(json, 'status');
    final time = json['publishedAt'] == null
        ? null
        : _time(json, 'publishedAt');
    final by = json['publishedBy'] == null ? null : _id(json, 'publishedBy');
    if (!{'draft', 'published'}.contains(status) ||
        (status == 'draft'
            ? time != null || by != null
            : time == null || by == null)) {
      throw const FormatException('Ungültiger Revisionszustand.');
    }
    final content = json['content'] == null
        ? null
        : TaskTemplateContent.fromJson(_object(json['content']));
    final title = _text(json, 'title');
    if (content != null &&
        (content.title != title ||
            (status == 'published' && content.steps.isEmpty))) {
      throw const FormatException('Inkonsistenter Revisionsinhalt.');
    }
    return TemplateRevisionDto(
      id: _id(json, 'id'),
      templateId: _id(json, 'templateId'),
      number: _positive(json, 'number'),
      status: status,
      title: title,
      createdAt: _time(json, 'createdAt'),
      publishedAt: time,
      publishedBy: by,
      content: content,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'templateId': templateId,
    'number': number,
    'status': status,
    'title': title,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'publishedBy': publishedBy,
    if (content != null) 'content': content!.toJson(),
  };
}

void _keys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      !value.keys.toSet().containsAll(expected)) {
    throw const FormatException('Ungültige Inhaltsfelder.');
  }
}

Map<String, dynamic> _object(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Objekt erwartet.');
  }
  return raw;
}

String _text(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String ||
      value.isEmpty ||
      value.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff)) {
    throw FormatException('Ungültiges Feld: $key');
  }
  return value;
}

String _id(Map<String, dynamic> json, String key) {
  final value = _text(json, key);
  if (!_uuid.hasMatch(value)) throw FormatException('Ungültige ID: $key');
  return value;
}

int _positive(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int || value < 1) {
    throw FormatException('Ungültige Version: $key');
  }
  return value;
}

DateTime _time(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(_text(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('Ungültige UTC-Zeit: $key');
  }
  return value;
}
