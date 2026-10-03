import 'task_templates.dart';

/// An explicit revision selection; list order is the planned task order.
class ShiftTemplateSelection {
  const ShiftTemplateSelection(this.templateId, this.revisionId);
  final String templateId, revisionId;
  factory ShiftTemplateSelection.fromJson(Map<String, dynamic> json) {
    if (json.length != 2) throw const FormatException('Ungültige Auswahl.');
    return ShiftTemplateSelection(
      shiftUuid(json['templateId']),
      shiftUuid(json['revisionId']),
    );
  }
  Map<String, dynamic> toJson() => {
    'templateId': templateId,
    'revisionId': revisionId,
  };
}

String shiftUuid(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
      ).hasMatch(value)) {
    throw const FormatException('Ungültige ID.');
  }
  return value.toLowerCase();
}

/// Reject implicit device time and DateTime.parse's calendar overflow normalization.
DateTime shiftInstant(Object? value) {
  if (value is! String) {
    throw const FormatException('Zeitpunkt mit UTC/Offset erforderlich.');
  }
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (m == null) {
    throw const FormatException('Zeitpunkt mit UTC/Offset erforderlich.');
  }
  final n = [for (var i = 1; i <= 6; i++) int.parse(m[i]!)];
  final date = DateTime.utc(n[0], n[1], n[2]);
  final zone = m[8]!;
  if (n[0] < 1 ||
      date.year != n[0] ||
      date.month != n[1] ||
      date.day != n[2] ||
      n[3] > 23 ||
      n[4] > 59 ||
      n[5] > 59 ||
      (zone != 'Z' &&
          (int.parse(zone.substring(1, 3)) > 23 ||
              int.parse(zone.substring(4)) > 59))) {
    throw const FormatException('Ungültiger Zeitpunkt.');
  }
  final instant = DateTime.parse(value).toUtc();
  if (instant.year < 1 || instant.year > 9999) {
    throw const FormatException(
      'Zeitpunkt außerhalb des unterstützten Bereichs.',
    );
  }
  return instant;
}

class ShiftDraftInput {
  ShiftDraftInput({
    required this.employeeId,
    required this.startsAt,
    required this.endsAt,
    required List<ShiftTemplateSelection> selections,
  }) : selections = List.unmodifiable(selections);
  final String employeeId;
  final DateTime startsAt, endsAt;
  final List<ShiftTemplateSelection> selections;
  factory ShiftDraftInput.fromJson(Map<String, dynamic> json) {
    final start = shiftInstant(json['startsAt']),
        end = shiftInstant(json['endsAt']);
    final raw = json['selections'];
    if (raw is! List || raw.length > 10 || !start.isBefore(end)) {
      throw const FormatException(
        'Beginn muss vor Ende liegen; maximal zehn Vorlagen.',
      );
    }
    final selections = raw.map((v) {
      if (v is! Map<String, dynamic>) {
        throw const FormatException('Ungültige Auswahl.');
      }
      return ShiftTemplateSelection.fromJson(v);
    }).toList();
    if (selections.map((s) => s.templateId).toSet().length !=
        selections.length) {
      throw const FormatException(
        'Jede Vorlage darf nur einmal gewählt werden.',
      );
    }
    return ShiftDraftInput(
      employeeId: shiftUuid(json['employeeId']),
      startsAt: start,
      endsAt: end,
      selections: selections,
    );
  }
  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'startsAt': startsAt.toIso8601String(),
    'endsAt': endsAt.toIso8601String(),
    'selections': selections.map((s) => s.toJson()).toList(),
  };
}

/// Exact request body for the bounded interval amendment of a published shift.
class ShiftAmendmentInput {
  ShiftAmendmentInput({
    required this.expectedVersion,
    required this.startsAt,
    required this.endsAt,
  });
  final int expectedVersion;
  final DateTime startsAt, endsAt;
  factory ShiftAmendmentInput.fromJson(Map<String, dynamic> json) {
    final version = json['expectedVersion'];
    if (version is! int || version < 1) {
      throw const FormatException('Invalid expected version.');
    }
    final start = shiftInstant(json['startsAt']),
        end = shiftInstant(json['endsAt']);
    if (!start.isBefore(end)) {
      throw const FormatException('Shift end must be after start.');
    }
    return ShiftAmendmentInput(
      expectedVersion: version,
      startsAt: start,
      endsAt: end,
    );
  }
  Map<String, dynamic> toJson() => {
    'expectedVersion': expectedVersion,
    'startsAt': startsAt.toUtc().toIso8601String(),
    'endsAt': endsAt.toUtc().toIso8601String(),
  };
}

class ShiftDto {
  ShiftDto({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.version,
    required this.status,
    required this.draft,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.publicationVersion,
    this.cancelledAt,
    this.cancelledBy,
    this.cancellationReason,
    this.cancellationVersion,
    this.amendedAt,
    this.amendedBy,
    this.amendmentVersion,
  });
  final String id, companyId, locationId, status;
  final int version;
  final ShiftDraftInput draft;
  final DateTime createdAt, updatedAt;
  final DateTime? publishedAt;
  final int? publicationVersion;
  final DateTime? cancelledAt;
  final String? cancelledBy, cancellationReason;
  final int? cancellationVersion;
  final DateTime? amendedAt;
  final String? amendedBy;
  final int? amendmentVersion;
  factory ShiftDto.fromJson(Map<String, dynamic> j) {
    final status = j['status'] as String;
    final cancelledAt = j['cancelledAt'] == null
        ? null
        : shiftInstant(j['cancelledAt']);
    final cancelledBy = j['cancelledBy'] == null
        ? null
        : shiftUuid(j['cancelledBy']);
    final cancellationReason = j['cancellationReason'];
    final cancellationVersion = j['cancellationVersion'];
    final amendedAt = j['amendedAt'] == null
        ? null
        : shiftInstant(j['amendedAt']);
    final amendedBy = j['amendedBy'] == null ? null : shiftUuid(j['amendedBy']);
    final amendmentVersion = j['amendmentVersion'];
    final amendmentEvidence =
        amendedAt != null &&
        amendedBy != null &&
        amendmentVersion is int &&
        amendmentVersion >= 1;
    final noAmendmentEvidence =
        amendedAt == null && amendedBy == null && amendmentVersion == null;
    if (!{'draft', 'published', 'cancelled'}.contains(status) ||
        (status == 'cancelled'
            ? cancelledAt == null ||
                  cancelledBy == null ||
                  cancellationReason is! String ||
                  cancellationReason.isEmpty ||
                  cancellationReason.runes.length > 500 ||
                  cancellationVersion is! int ||
                  cancellationVersion < 1
            : cancelledAt != null ||
                  cancelledBy != null ||
                  cancellationReason != null ||
                  cancellationVersion != null) ||
        (!amendmentEvidence && !noAmendmentEvidence) ||
        (status == 'draft' && !noAmendmentEvidence)) {
      throw const FormatException('Ungültiger Schichtstatus.');
    }
    return ShiftDto(
      id: shiftUuid(j['id']),
      companyId: shiftUuid(j['companyId']),
      locationId: shiftUuid(j['locationId']),
      version: j['version'] as int,
      status: status,
      draft: ShiftDraftInput.fromJson(j),
      createdAt: shiftInstant(j['createdAt']),
      updatedAt: shiftInstant(j['updatedAt']),
      publishedAt: j['publishedAt'] == null
          ? null
          : shiftInstant(j['publishedAt']),
      publicationVersion: j['publicationVersion'] as int?,
      cancelledAt: cancelledAt,
      cancelledBy: cancelledBy,
      cancellationReason: cancellationReason as String?,
      cancellationVersion: cancellationVersion as int?,
      amendedAt: amendedAt,
      amendedBy: amendedBy,
      amendmentVersion: amendmentVersion as int?,
    );
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'locationId': locationId,
    'version': version,
    'status': status,
    ...draft.toJson(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'publishedAt': publishedAt?.toUtc().toIso8601String(),
    'publicationVersion': publicationVersion,
    if (cancelledAt != null)
      'cancelledAt': cancelledAt!.toUtc().toIso8601String(),
    if (cancelledBy != null) 'cancelledBy': cancelledBy,
    if (cancellationReason != null) 'cancellationReason': cancellationReason,
    if (cancellationVersion != null) 'cancellationVersion': cancellationVersion,
    if (amendedAt != null) 'amendedAt': amendedAt!.toUtc().toIso8601String(),
    if (amendedBy != null) 'amendedBy': amendedBy,
    if (amendmentVersion != null) 'amendmentVersion': amendmentVersion,
  };
}

class TaskInstanceDto {
  TaskInstanceDto({
    required this.id,
    required this.shiftId,
    required this.employeeId,
    required this.templateId,
    required this.revisionId,
    required this.title,
    required this.position,
    this.content,
    this.status = 'open',
    this.version = 1,
    this.confirmedSteps = 0,
    this.totalSteps = 0,
  });
  final String status;
  final int version, confirmedSteps, totalSteps;
  final String id, shiftId, employeeId, templateId, revisionId, title;
  final int position;
  final TaskTemplateContent? content;
  factory TaskInstanceDto.fromJson(Map<String, dynamic> j) => TaskInstanceDto(
    id: shiftUuid(j['id']),
    shiftId: shiftUuid(j['shiftId']),
    employeeId: shiftUuid(j['employeeId']),
    templateId: shiftUuid(j['templateId']),
    revisionId: shiftUuid(j['revisionId']),
    status: j['status'] as String,
    version: j['version'] as int,
    confirmedSteps: j['confirmedSteps'] as int? ?? 0,
    totalSteps: j['totalSteps'] as int? ?? 0,
    title: j['title'] as String,
    position: j['position'] as int,
    content: j['content'] == null
        ? null
        : TaskTemplateContent.fromJson(j['content'] as Map<String, dynamic>),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'shiftId': shiftId,
    'employeeId': employeeId,
    'templateId': templateId,
    'revisionId': revisionId,
    'title': title,
    'position': position,
    'status': status,
    'version': version,
    'confirmedSteps': confirmedSteps,
    'totalSteps': totalSteps,
    if (content != null) 'content': content!.toJson(),
  };
}
