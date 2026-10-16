import 'dart:convert';
import 'shifts.dart';

const shiftTransferStates = {
  'proposed',
  'accepted',
  'declined',
  'withdrawn',
  'rejected',
  'approved',
};
const shiftTransferKinds = {
  'propose',
  'accept',
  'decline',
  'source_withdraw',
  'recipient_withdraw',
  'manager_reject',
  'manager_approve',
};

class TransferInputException implements Exception {
  const TransferInputException(this.code, this.message);
  final String code, message;
}

String transferReason(Object? value) {
  if (value is! String) {
    throw const TransferInputException(
      'invalid_reason',
      'A reason is required.',
    );
  }
  final text = value.trim();
  // JSON may decode escaped lone UTF-16 surrogates, but they are not Unicode
  // scalar values and cannot be persisted as PostgreSQL JSON/text.
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (i + 1 < text.length) {
        final next = text.codeUnitAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          i++;
          continue;
        }
      }
      throw const TransferInputException(
        'invalid_reason',
        'Use 1 to 500 plain-text code points.',
      );
    }
    if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const TransferInputException(
        'invalid_reason',
        'Use 1 to 500 plain-text code points.',
      );
    }
  }
  if (text.isEmpty ||
      text.runes.length > 500 ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(text)) {
    throw const TransferInputException(
      'invalid_reason',
      'Use 1 to 500 plain-text code points.',
    );
  }
  return text;
}

class ShiftTransferCommandInput {
  ShiftTransferCommandInput._(this.kind, this.payload);
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  int get expectedVersion =>
      payload[kind == 'propose' ? 'expectedSourceVersion' : 'expectedVersion']
          as int;
  String get canonical => jsonEncode(payload);
  Map<String, dynamic> toJson() => Map.of(payload);
  factory ShiftTransferCommandInput.fromJson(
    String kind,
    Map<String, dynamic> j,
  ) {
    try {
      if (!shiftTransferKinds.contains(kind)) throw const FormatException();
      final propose = kind == 'propose';
      final reason = {
        'source_withdraw',
        'recipient_withdraw',
        'manager_reject',
      }.contains(kind);
      final keys = {
        'operationId',
        if (propose) ...{
          'requestId',
          'sourceShiftId',
          'expectedSourceVersion',
          'recipientEmployeeId',
        } else
          'expectedVersion',
        if (reason) 'reason',
      };
      if (j.length != keys.length || !keys.every(j.containsKey)) {
        throw const FormatException();
      }
      final version = j[propose ? 'expectedSourceVersion' : 'expectedVersion'];
      if (version is! int || version < 1 || version > 2147483647) {
        throw const FormatException();
      }
      return ShiftTransferCommandInput._(
        kind,
        Map.unmodifiable({
          'operationId': shiftUuid(j['operationId']),
          if (propose) ...{
            'requestId': shiftUuid(j['requestId']),
            'sourceShiftId': shiftUuid(j['sourceShiftId']),
            'expectedSourceVersion': version,
            'recipientEmployeeId': shiftUuid(j['recipientEmployeeId']),
          } else
            'expectedVersion': version,
          if (reason) 'reason': transferReason(j['reason']),
        }),
      );
    } on FormatException {
      throw const TransferInputException(
        'invalid_request',
        'Invalid transfer command fields.',
      );
    }
  }
}

/// Transfer evidence contains no execution results or instruction bodies.
class ShiftTransferDto {
  ShiftTransferDto.fromJson(Map<String, dynamic> j)
    : json = _freeze(j) as Map<String, dynamic> {
    const evidenceKeys = {
      'id',
      'companyId',
      'locationId',
      'sourceShiftId',
      'sourceVersion',
      'sourceEmployeeId',
      'recipientEmployeeId',
      'startsAt',
      'endsAt',
      'proposedBy',
      'proposedAt',
      'sourceLinkId',
      'recipientLinkId',
      'recipientAccountId',
      'sourceAccountVersion',
      'recipientAccountVersion',
      'proposalOperationId',
      'status',
      'version',
      'acceptedBy',
      'acceptedAt',
      'acceptanceOperationId',
      'terminalBy',
      'terminalAt',
      'terminalReason',
      'terminalOperationId',
      'terminalKind',
      'replacementShiftId',
      'sourceName',
      'recipientName',
      'tasks',
      'taskLinks',
    };
    const detailKeys = {'actionable', 'nonActionableReason', 'participantRole'};
    if (!evidenceKeys.every(j.containsKey) ||
        j.keys.any(
          (k) => !evidenceKeys.contains(k) && !detailKeys.contains(k),
        ) ||
        (detailKeys.any(j.containsKey) &&
            (!detailKeys.every(j.containsKey) ||
                j['actionable'] is! bool ||
                !{
                  'source',
                  'recipient',
                  'manager',
                }.contains(j['participantRole']) ||
                (j['nonActionableReason'] != null &&
                    j['nonActionableReason'] is! String)))) {
      throw const FormatException('Invalid transfer projection.');
    }
    for (final key in [
      'id',
      'companyId',
      'locationId',
      'sourceShiftId',
      'sourceEmployeeId',
      'recipientEmployeeId',
      'proposedBy',
      'sourceLinkId',
      'recipientLinkId',
      'recipientAccountId',
      'proposalOperationId',
    ]) {
      shiftUuid(j[key]);
    }
    if (!shiftTransferStates.contains(j['status']) ||
        j['version'] is! int ||
        (j['version'] as int) < 1 ||
        (j['version'] as int) > 3 ||
        j['sourceVersion'] is! int ||
        (j['sourceVersion'] as int) < 1 ||
        (j['sourceVersion'] as int) > 2147483647 ||
        j['sourceEmployeeId'] == j['recipientEmployeeId']) {
      throw const FormatException('Invalid transfer evidence.');
    }
    for (final key in ['sourceAccountVersion', 'recipientAccountVersion']) {
      if (j[key] is! int ||
          (j[key] as int) < 1 ||
          (j[key] as int) > 2147483647) {
        throw const FormatException('Invalid identity basis.');
      }
    }
    final start = shiftInstant(j['startsAt']), end = shiftInstant(j['endsAt']);
    if (!end.isAfter(start)) throw const FormatException('Invalid interval.');
    shiftInstant(j['proposedAt']);
    if (j['acceptedAt'] != null) {
      shiftInstant(j['acceptedAt']);
      shiftUuid(j['acceptedBy']);
    }
    if (j['terminalAt'] != null) {
      shiftInstant(j['terminalAt']);
      shiftUuid(j['terminalBy']);
    }
    if (j['replacementShiftId'] != null) shiftUuid(j['replacementShiftId']);
    for (final key in ['sourceName', 'recipientName']) {
      if (j[key] is! String ||
          (j[key] as String).runes.isEmpty ||
          (j[key] as String).runes.length > 120) {
        throw const FormatException('Invalid colleague display evidence.');
      }
    }
    for (final key in ['tasks', 'taskLinks']) {
      if (j[key] != null && (j[key] is! List || (j[key] as List).length > 10)) {
        throw const FormatException('Invalid bounded work evidence.');
      }
    }
    final accepted = j['acceptedAt'] != null,
        terminal = !{'proposed', 'accepted'}.contains(j['status']);
    if (accepted != (j['acceptedBy'] != null) ||
        accepted != (j['acceptanceOperationId'] != null) ||
        (accepted && j['acceptedBy'] != j['recipientAccountId']) ||
        (j['status'] == 'proposed' && (accepted || j['version'] != 1)) ||
        (j['status'] == 'accepted' && (!accepted || j['version'] != 2)) ||
        terminal != (j['terminalAt'] != null) ||
        terminal != (j['terminalBy'] != null) ||
        terminal != (j['terminalOperationId'] != null) ||
        terminal != (j['terminalKind'] != null) ||
        (terminal && j['version'] != (accepted ? 3 : 2)) ||
        (j['status'] == 'declined' &&
            (accepted ||
                j['terminalKind'] != 'decline' ||
                j['terminalBy'] != j['recipientAccountId'])) ||
        (j['status'] == 'withdrawn' &&
            !{
              'source_withdraw',
              'recipient_withdraw',
            }.contains(j['terminalKind'])) ||
        (j['terminalKind'] == 'recipient_withdraw' &&
            (!accepted || j['terminalBy'] != j['acceptedBy'])) ||
        (j['status'] == 'rejected' && j['terminalKind'] != 'manager_reject') ||
        (j['status'] == 'approved' &&
            (!accepted ||
                j['replacementShiftId'] == null ||
                j['replacementShiftId'] == j['sourceShiftId'] ||
                j['terminalKind'] != 'manager_approve' ||
                j['terminalBy'] == j['proposedBy'] ||
                j['terminalBy'] == j['acceptedBy'])) ||
        (j['status'] != 'approved' && j['replacementShiftId'] != null)) {
      throw const FormatException('Inconsistent transfer lifecycle evidence.');
    }
    final proposedAt = shiftInstant(j['proposedAt']);
    if ((accepted && shiftInstant(j['acceptedAt']).isBefore(proposedAt)) ||
        (terminal &&
            shiftInstant(j['terminalAt']).isBefore(
              accepted ? shiftInstant(j['acceptedAt']) : proposedAt,
            ))) {
      throw const FormatException('Invalid evidence chronology.');
    }
    for (final key in ['acceptanceOperationId', 'terminalOperationId']) {
      if (j[key] != null) shiftUuid(j[key]);
    }
    if ({'withdrawn', 'rejected'}.contains(j['status'])) {
      if (transferReason(j['terminalReason']) != j['terminalReason']) {
        throw const FormatException('Invalid terminal reason.');
      }
    } else if (j['terminalReason'] != null) {
      throw const FormatException('Unexpected terminal reason.');
    }
    final tasks = j['tasks'], links = j['taskLinks'];
    if (tasks is! List ||
        tasks.isEmpty ||
        tasks.length > 10 ||
        links is! List ||
        (j['status'] == 'approved'
            ? links.length != tasks.length
            : links.isNotEmpty)) {
      throw const FormatException('Incomplete transfer work evidence.');
    }
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks[i];
      if (task is! Map ||
          task['position'] != i ||
          task['title'] is! String ||
          (task['title'] as String).isEmpty ||
          (task['title'] as String).runes.length > 120) {
        throw const FormatException('Invalid task summary.');
      }
      for (final key in ['id', 'templateId', 'revisionId']) {
        shiftUuid(task[key]);
      }
      if (task.keys.any(
        (k) => !{
          'id',
          'templateId',
          'revisionId',
          'position',
          'title',
          'knowledgeGuidance',
          'planogramGuidance',
        }.contains(k),
      )) {
        throw const FormatException('Unsafe task projection.');
      }
      for (final key in ['knowledgeGuidance', 'planogramGuidance']) {
        final pin = task[key];
        if (pin != null) {
          final fields = key == 'knowledgeGuidance'
              ? {'articleId', 'revisionId'}
              : {'fixtureId', 'assignmentId', 'revisionId'};
          if (pin is! Map ||
              pin.keys.toSet().difference(fields).isNotEmpty ||
              pin.length != fields.length) {
            throw const FormatException('Invalid exact pin.');
          }
          for (final field in fields) {
            shiftUuid(pin[field]);
          }
        }
      }
    }
    if (tasks.map((t) => t['id']).toSet().length != tasks.length ||
        tasks.map((t) => t['templateId']).toSet().length != tasks.length) {
      throw const FormatException('Repeated source work identity.');
    }
    for (var i = 0; i < links.length; i++) {
      final link = links[i];
      if (link is! Map ||
          link.length != 7 ||
          link.keys.any(
            (k) => !{
              'sourceTaskId',
              'replacementTaskId',
              'sourceShiftId',
              'replacementShiftId',
              'templateId',
              'revisionId',
              'position',
            }.contains(k),
          ) ||
          link['position'] != i ||
          link['sourceTaskId'] != tasks[i]['id'] ||
          link['sourceShiftId'] != j['sourceShiftId'] ||
          link['replacementShiftId'] != j['replacementShiftId'] ||
          link['templateId'] != tasks[i]['templateId'] ||
          link['revisionId'] != tasks[i]['revisionId']) {
        throw const FormatException('Invalid exact task lineage.');
      }
      shiftUuid(link['replacementTaskId']);
    }
    if (links.map((l) => l['replacementTaskId']).toSet().length !=
            links.length ||
        links.any((l) => tasks.any((t) => t['id'] == l['replacementTaskId']))) {
      throw const FormatException('Repeated replacement work identity.');
    }
  }
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get status => json['status'] as String;
  int get version => json['version'] as int;
  Map<String, dynamic> toJson() => Map.of(json);
}

Object? _freeze(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.unmodifiable({
      for (final e in value.entries) e.key as String: _freeze(e.value),
    });
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
