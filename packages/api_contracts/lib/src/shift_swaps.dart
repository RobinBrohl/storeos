import 'dart:convert';
import 'shifts.dart';
import 'shift_transfers.dart' show transferReason, TransferInputException;

const shiftSwapStates = {
  'requested',
  'offered',
  'confirmed',
  'declined',
  'withdrawn',
  'rejected',
  'approved',
};
const shiftSwapKinds = {
  'request',
  'offer',
  'confirm',
  'decline',
  'source_withdraw',
  'recipient_withdraw',
  'manager_reject',
  'manager_approve',
};

class SwapInputException implements Exception {
  const SwapInputException(this.message);
  final String message;
}

void _keys(Map<String, dynamic> j, Set<String> keys) {
  if (j.length != keys.length || !keys.every(j.containsKey)) {
    throw const FormatException('Invalid swap fields.');
  }
}

int _version(Object? v) {
  if (v is! int || v < 1 || v > 2147483647) {
    throw const FormatException('Invalid version.');
  }
  return v;
}

Map<String, dynamic> _object(Object? v) {
  if (v is! Map<String, dynamic>) {
    throw const FormatException('Object required.');
  }
  return v;
}

Object? _freeze(Object? v) {
  if (v is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      v.map((k, v) => MapEntry(k, _freeze(v))),
    );
  }
  if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
  return v;
}

/// Command intent never contains an actor, snapshot or replacement identity.
class ShiftSwapCommandInput {
  ShiftSwapCommandInput._(this.kind, this.payload);
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  int get expectedVersion =>
      payload[kind == 'request' ? 'expectedSourceVersion' : 'expectedVersion']
          as int;
  String get canonical => jsonEncode(payload);
  Map<String, dynamic> toJson() => Map.of(payload);

  factory ShiftSwapCommandInput.fromJson(String kind, Map<String, dynamic> j) {
    try {
      if (!shiftSwapKinds.contains(kind)) throw const FormatException();
      final request = kind == 'request', offer = kind == 'offer';
      final reason = {
        'source_withdraw',
        'recipient_withdraw',
        'manager_reject',
      }.contains(kind);
      _keys(j, {
        'operationId',
        if (request) ...{
          'requestId',
          'sourceShiftId',
          'expectedSourceVersion',
          'recipientEmployeeId',
        } else
          'expectedVersion',
        if (offer) ...{'counterpartShiftId', 'expectedCounterpartVersion'},
        if (reason) 'reason',
      });
      final version = _version(
        j[request ? 'expectedSourceVersion' : 'expectedVersion'],
      );
      if ((!request && version > 3) ||
          (offer && version != 1) ||
          (kind == 'confirm' && version != 2) ||
          (kind == 'manager_approve' && version != 3) ||
          (kind == 'decline' && version > 2) ||
          (kind == 'recipient_withdraw' && version < 2)) {
        throw const FormatException('Invalid command stage.');
      }
      final payload = {
        'operationId': shiftUuid(j['operationId']),
        if (request) ...{
          'requestId': shiftUuid(j['requestId']),
          'sourceShiftId': shiftUuid(j['sourceShiftId']),
          'expectedSourceVersion': version,
          'recipientEmployeeId': shiftUuid(j['recipientEmployeeId']),
        } else
          'expectedVersion': version,
        if (offer) ...{
          'counterpartShiftId': shiftUuid(j['counterpartShiftId']),
          'expectedCounterpartVersion': _version(
            j['expectedCounterpartVersion'],
          ),
        },
        if (reason) 'reason': transferReason(j['reason']),
      };
      if (utf8.encode(jsonEncode(payload)).length > 8192) {
        throw const FormatException();
      }
      return ShiftSwapCommandInput._(kind, Map.unmodifiable(payload));
    } on FormatException {
      throw const SwapInputException('Invalid swap command.');
    } on TransferInputException {
      throw const SwapInputException('Invalid swap reason.');
    }
  }
}

/// Only deliberately disclosed work; internal Account/link bases are excluded.
class ShiftSwapLegDto {
  ShiftSwapLegDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'leg',
      'sourceShiftId',
      'sourceVersion',
      'sourceEmployeeId',
      'incomingEmployeeId',
      'startsAt',
      'endsAt',
      'tasks',
      'taskLinks',
      'replacementShiftId',
    });
    if (!{'a', 'b'}.contains(j['leg'])) throw const FormatException();
    for (final k in [
      'sourceShiftId',
      'sourceEmployeeId',
      'incomingEmployeeId',
    ]) {
      if (shiftUuid(j[k]) != j[k]) {
        throw const FormatException('Noncanonical identity.');
      }
    }
    if (j['sourceEmployeeId'] == j['incomingEmployeeId']) {
      throw const FormatException();
    }
    _version(j['sourceVersion']);
    if (!shiftInstant(j['endsAt']).isAfter(shiftInstant(j['startsAt']))) {
      throw const FormatException();
    }
    if (j['replacementShiftId'] != null &&
        (shiftUuid(j['replacementShiftId']) != j['replacementShiftId'] ||
            j['replacementShiftId'] == j['sourceShiftId'])) {
      throw const FormatException();
    }
    final tasks = j['tasks'];
    if (tasks is! List || tasks.isEmpty || tasks.length > 10) {
      throw const FormatException();
    }
    final ids = <String>{};
    for (var i = 0; i < tasks.length; i++) {
      final t = tasks[i];
      if (t is! Map<String, dynamic>) throw const FormatException();
      _keys(t, {
        'id',
        'templateId',
        'revisionId',
        'position',
        'title',
        'knowledgeGuidance',
        'planogramGuidance',
      });
      for (final k in ['id', 'templateId', 'revisionId']) {
        if (shiftUuid(t[k]) != t[k]) throw const FormatException();
      }
      if (!ids.add(t['id'] as String) ||
          t['position'] is! int ||
          t['position'] != i ||
          t['title'] is! String ||
          (t['title'] as String).isEmpty ||
          (t['title'] as String).runes.length > 120) {
        throw const FormatException();
      }
      for (final k in ['knowledgeGuidance', 'planogramGuidance']) {
        final pin = t[k];
        if (pin == null) continue;
        if (pin is! Map<String, dynamic>) throw const FormatException();
        final fields = k == 'knowledgeGuidance'
            ? {'articleId', 'revisionId'}
            : {'fixtureId', 'assignmentId', 'revisionId'};
        _keys(pin, fields);
        for (final field in fields) {
          if (shiftUuid(pin[field]) != pin[field]) {
            throw const FormatException();
          }
        }
      }
    }
    final links = j['taskLinks'];
    if (links is! List ||
        links.length != (j['replacementShiftId'] == null ? 0 : tasks.length)) {
      throw const FormatException('Incomplete paired lineage.');
    }
    final replacements = <String>{};
    for (var i = 0; i < links.length; i++) {
      final l = _object(links[i]), t = _object(tasks[i]);
      _keys(l, {
        'sourceTaskId',
        'replacementTaskId',
        'sourceShiftId',
        'replacementShiftId',
        'templateId',
        'revisionId',
        'position',
      });
      if (l['sourceTaskId'] != t['id'] ||
          l['templateId'] != t['templateId'] ||
          l['revisionId'] != t['revisionId'] ||
          l['position'] is! int ||
          l['position'] != i ||
          l['sourceShiftId'] != j['sourceShiftId'] ||
          l['replacementShiftId'] != j['replacementShiftId'] ||
          shiftUuid(l['replacementTaskId']) != l['replacementTaskId'] ||
          !replacements.add(l['replacementTaskId'] as String) ||
          ids.contains(l['replacementTaskId'])) {
        throw const FormatException('Invalid paired lineage.');
      }
    }
    json = _freeze(j) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

class ShiftSwapDto {
  ShiftSwapDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'id',
      'companyId',
      'locationId',
      'sourceEmployeeId',
      'recipientEmployeeId',
      'sourceName',
      'recipientName',
      'status',
      'version',
      'requestedAt',
      'requestOperationId',
      'offeredAt',
      'offerOperationId',
      'confirmedAt',
      'confirmationOperationId',
      'terminalAt',
      'terminalOperationId',
      'terminalKind',
      'terminalReason',
      'legs',
    });
    for (final k in [
      'id',
      'companyId',
      'locationId',
      'sourceEmployeeId',
      'recipientEmployeeId',
      'requestOperationId',
    ]) {
      if (shiftUuid(j[k]) != j[k]) throw const FormatException();
    }
    for (final k in ['sourceName', 'recipientName']) {
      if (j[k] is! String ||
          (j[k] as String).isEmpty ||
          (j[k] as String).runes.length > 120) {
        throw const FormatException();
      }
    }
    final state = j['status'], version = _version(j['version']);
    if (!shiftSwapStates.contains(state) ||
        j['sourceEmployeeId'] == j['recipientEmployeeId']) {
      throw const FormatException();
    }
    final offered = j['offeredAt'] != null,
        confirmed = j['confirmedAt'] != null;
    final terminal = !{'requested', 'offered', 'confirmed'}.contains(state);
    var last = shiftInstant(j['requestedAt']);
    for (final pair in [
      ('offeredAt', 'offerOperationId'),
      ('confirmedAt', 'confirmationOperationId'),
      ('terminalAt', 'terminalOperationId'),
    ]) {
      if ((j[pair.$1] == null) != (j[pair.$2] == null)) {
        throw const FormatException();
      }
      if (j[pair.$1] != null) {
        final at = shiftInstant(j[pair.$1]);
        if (at.isBefore(last) || shiftUuid(j[pair.$2]) != j[pair.$2]) {
          throw const FormatException();
        }
        last = at;
      }
    }
    if ((confirmed && !offered) ||
        (state == 'requested' && (offered || version != 1)) ||
        (state == 'offered' && (!offered || confirmed || version != 2)) ||
        (state == 'confirmed' && (!confirmed || version != 3)) ||
        terminal != (j['terminalAt'] != null) ||
        terminal != (j['terminalKind'] != null) ||
        (terminal &&
            version !=
                (confirmed
                    ? 4
                    : offered
                    ? 3
                    : 2)) ||
        (state == 'declined' &&
            (confirmed || j['terminalKind'] != 'decline')) ||
        (state == 'withdrawn' &&
            !{
              'source_withdraw',
              'recipient_withdraw',
            }.contains(j['terminalKind'])) ||
        (j['terminalKind'] == 'recipient_withdraw' && !offered) ||
        (state == 'rejected' && j['terminalKind'] != 'manager_reject') ||
        (state == 'approved' &&
            (!confirmed || j['terminalKind'] != 'manager_approve'))) {
      throw const FormatException();
    }
    final reason = {'withdrawn', 'rejected'}.contains(state);
    if (reason != (j['terminalReason'] != null)) throw const FormatException();
    if (reason) {
      try {
        if (transferReason(j['terminalReason']) != j['terminalReason']) {
          throw const FormatException();
        }
      } on TransferInputException {
        throw const FormatException('Invalid retained reason.');
      }
    }
    final legs = j['legs'];
    if (legs is! List || legs.length != (offered ? 2 : 1)) {
      throw const FormatException();
    }
    final originals = <String>{},
        replacements = <String>{},
        tasks = <String>{},
        replacementTasks = <String>{};
    for (var i = 0; i < legs.length; i++) {
      final l = ShiftSwapLegDto.fromJson(_object(legs[i])).json;
      if (l['leg'] != (i == 0 ? 'a' : 'b') ||
          l['sourceEmployeeId'] !=
              j[i == 0 ? 'sourceEmployeeId' : 'recipientEmployeeId'] ||
          l['incomingEmployeeId'] !=
              j[i == 0 ? 'recipientEmployeeId' : 'sourceEmployeeId'] ||
          !originals.add(l['sourceShiftId'] as String) ||
          (state == 'approved') != (l['replacementShiftId'] != null) ||
          (l['replacementShiftId'] != null &&
              !replacements.add(l['replacementShiftId'] as String))) {
        throw const FormatException();
      }
      for (final t in l['tasks'] as List) {
        if (!tasks.add(t['id'] as String)) throw const FormatException();
      }
      for (final link in l['taskLinks'] as List) {
        if (!replacementTasks.add(link['replacementTaskId'] as String)) {
          throw const FormatException();
        }
      }
    }
    if (originals.intersection(replacements).isNotEmpty ||
        tasks.intersection(replacementTasks).isNotEmpty) {
      throw const FormatException();
    }
    json = _freeze(j) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

/// Original accepted evidence stays distinct from current actionability.
class ShiftSwapCommandResult {
  ShiftSwapCommandResult.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'operationId',
      'kind',
      'acceptedVersion',
      'statusCode',
      'request',
      'replayed',
    });
    if (shiftUuid(j['operationId']) != j['operationId'] ||
        !shiftSwapKinds.contains(j['kind']) ||
        j['replayed'] is! bool) {
      throw const FormatException();
    }
    request = ShiftSwapDto.fromJson(_object(j['request']));
    final expectedState = switch (j['kind']) {
      'request' => 'requested',
      'offer' => 'offered',
      'confirm' => 'confirmed',
      'decline' => 'declined',
      'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
      'manager_reject' => 'rejected',
      _ => 'approved',
    };
    final operationKey = switch (j['kind']) {
      'request' => 'requestOperationId',
      'offer' => 'offerOperationId',
      'confirm' => 'confirmationOperationId',
      _ => 'terminalOperationId',
    };
    if (j['statusCode'] is! int ||
        j['statusCode'] != (j['kind'] == 'request' ? 201 : 200) ||
        j['acceptedVersion'] is! int ||
        j['acceptedVersion'] != request.json['version'] ||
        request.json['status'] != expectedState ||
        (operationKey == 'terminalOperationId' &&
            request.json['terminalKind'] != j['kind']) ||
        request.json[operationKey] != j['operationId']) {
      throw const FormatException();
    }
    json = _freeze(j) as Map<String, dynamic>;
    if (utf8.encode(jsonEncode(json)).length > 65536) {
      throw const FormatException();
    }
  }
  late final ShiftSwapDto request;
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

class ShiftSwapDetailDto {
  ShiftSwapDetailDto.fromJson(Map<String, dynamic> j) {
    _keys(j, {
      'request',
      'participantRole',
      'actionable',
      'nonActionableReason',
      'availableActions',
    });
    final request = ShiftSwapDto.fromJson(_object(j['request']));
    final role = j['participantRole'],
        actions = j['availableActions'],
        reason = j['nonActionableReason'];
    if (!{'source', 'recipient', 'manager'}.contains(role) ||
        j['actionable'] is! bool ||
        (reason != null &&
            (reason is! String ||
                !RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(reason))) ||
        (j['actionable'] == true && reason != null) ||
        actions is! List ||
        actions.length > 3 ||
        actions.toSet().length != actions.length) {
      throw const FormatException();
    }
    final status = request.json['status'];
    final allowed = switch ((role, status)) {
      ('source', 'requested') => {'source_withdraw'},
      ('source', 'offered') => {'confirm', 'decline', 'source_withdraw'},
      ('source', 'confirmed') => {'source_withdraw'},
      ('recipient', 'requested') => {'offer', 'decline'},
      ('recipient', 'offered' || 'confirmed') => {'recipient_withdraw'},
      ('manager', 'requested' || 'offered') => {'manager_reject'},
      ('manager', 'confirmed') => {'manager_reject', 'manager_approve'},
      _ => <String>{},
    };
    if (actions.any((a) => !allowed.contains(a)) ||
        (!{'requested', 'offered', 'confirmed'}.contains(status) &&
            j['actionable'] == true)) {
      throw const FormatException();
    }
    json = _freeze({...j, 'request': request.toJson()}) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

void _page(Map<String, dynamic> j) {
  _keys(j, {'items', 'nextCursor'});
  if (j['items'] is! List ||
      (j['items'] as List).length > 50 ||
      (j['nextCursor'] != null &&
          (j['nextCursor'] is! String ||
              (j['nextCursor'] as String).isEmpty ||
              (j['nextCursor'] as String).length > 2048))) {
    throw const FormatException();
  }
}

class ShiftSwapPageDto {
  ShiftSwapPageDto.fromJson(Map<String, dynamic> j) {
    _page(j);
    final ids = <String>{};
    for (final item in j['items'] as List) {
      final dto = ShiftSwapDto.fromJson(_object(item));
      if (!ids.add(dto.json['id'] as String)) throw const FormatException();
    }
    json = _freeze(j) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

/// Discovery deliberately exposes identities without any colleague roster facts.
class ShiftSwapColleaguePageDto {
  ShiftSwapColleaguePageDto.fromJson(Map<String, dynamic> j) {
    _page(j);
    final ids = <String>{};
    for (final item in j['items'] as List) {
      final row = _object(item);
      _keys(row, {'employeeId', 'displayName'});
      if (shiftUuid(row['employeeId']) != row['employeeId'] ||
          !ids.add(row['employeeId'] as String) ||
          row['displayName'] is! String ||
          (row['displayName'] as String).isEmpty ||
          (row['displayName'] as String).runes.length > 120) {
        throw const FormatException();
      }
    }
    json = _freeze(j) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}

/// Candidate metadata is scoped to B's own work by the future authorized caller.
class ShiftSwapCounterpartPageDto {
  ShiftSwapCounterpartPageDto.fromJson(Map<String, dynamic> j) {
    _page(j);
    final ids = <String>{};
    for (final item in j['items'] as List) {
      final row = _object(item);
      _keys(row, {'shiftId', 'version', 'startsAt', 'endsAt'});
      if (shiftUuid(row['shiftId']) != row['shiftId'] ||
          !ids.add(row['shiftId'] as String) ||
          !shiftInstant(row['endsAt']).isAfter(shiftInstant(row['startsAt']))) {
        throw const FormatException();
      }
      _version(row['version']);
    }
    json = _freeze(j) as Map<String, dynamic>;
  }
  late final Map<String, dynamic> json;
  Map<String, dynamic> toJson() => Map.of(json);
}
