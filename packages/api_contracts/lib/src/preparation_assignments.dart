import 'dart:convert';
import 'preparation_batches.dart';
import 'recipes.dart';

/// Immutable canonical intent; authority and Batch inputs come from the server.
class PreparationAssignmentCommandInput {
  PreparationAssignmentCommandInput._(this.kind, this.payload);
  factory PreparationAssignmentCommandInput.fromJson(
    String kind,
    Map<String, dynamic> j,
  ) {
    final fields = switch (kind) {
      'create' => {
        'id',
        'operationId',
        'recipeId',
        'revisionId',
        'employeeId',
        'expectedEmployeeVersion',
        'plannedDeclaredBatchCount',
      },
      'withdraw' => {'operationId', 'expectedVersion', 'reason'},
      'start' => {'operationId', 'expectedVersion'},
      _ => throw const PreparationInputException(
        'invalid_request',
        'Unknown assignment command.',
      ),
    };
    if (j.length != fields.length || !fields.containsAll(j.keys)) {
      throw const PreparationInputException(
        'invalid_request',
        'Unexpected or missing fields.',
      );
    }
    final p = <String, dynamic>{'operationId': recipeId(j['operationId'])};
    if (kind == 'create') {
      for (final k in ['id', 'recipeId', 'revisionId', 'employeeId']) {
        p[k] = recipeId(j[k]);
      }
      final v = j['expectedEmployeeVersion'];
      if (v is! int || v < 1 || v > 9007199254740991) {
        throw const PreparationInputException(
          'invalid_request',
          'Expected current Employee version.',
        );
      }
      p['expectedEmployeeVersion'] = v;
      p['plannedDeclaredBatchCount'] = declaredBatchCount(
        j['plannedDeclaredBatchCount'],
      );
    } else {
      final v = j['expectedVersion'];
      if (v is! int || v < 1 || v > 2) {
        throw const PreparationInputException(
          'invalid_request',
          'Expected assignment version 1 or 2.',
        );
      }
      p['expectedVersion'] = v;
      if (kind == 'withdraw') {
        p['reason'] = preparationEvidenceText(j['reason']);
      }
    }
    return PreparationAssignmentCommandInput._(kind, Map.unmodifiable(p));
  }
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  String get canonical => jsonEncode(payload);
  Map<String, dynamic> toJson() => Map.of(payload);
}

class PreparationAssignmentDto {
  PreparationAssignmentDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j) {
    for (final key in [
      'id',
      'companyId',
      'locationId',
      'employeeId',
      'recipeId',
      'revisionId',
      'createdBy',
      'createOperationId',
    ]) {
      recipeId(j[key]);
    }
    declaredBatchCount(j['plannedDeclaredBatchCount']);
    if (!['assigned', 'started', 'withdrawn'].contains(j['status']) ||
        j['version'] != (j['status'] == 'assigned' ? 1 : 2)) {
      throw const FormatException('Invalid assignment lifecycle.');
    }
    for (final key in ['createdAt', 'startedAt', 'withdrawnAt']) {
      if ((key == 'createdAt' || j[key] != null) &&
          (j[key] is! String ||
              DateTime.tryParse(j[key] as String)?.isUtc != true)) {
        throw const FormatException('Invalid assignment timestamp.');
      }
    }
    if (j['status'] == 'started') {
      for (final key in [
        'batchId',
        'startedBy',
        'batchOperationId',
        'terminalOperationId',
      ]) {
        recipeId(j[key]);
      }
      if (j['startedAt'] == null ||
          j['withdrawnBy'] != null ||
          j['withdrawnAt'] != null ||
          j['withdrawalReason'] != null) {
        throw const FormatException('Invalid started evidence.');
      }
    } else if (j['status'] == 'withdrawn') {
      recipeId(j['withdrawnBy']);
      recipeId(j['terminalOperationId']);
      preparationEvidenceText(j['withdrawalReason']);
      if (j['withdrawnAt'] == null ||
          j['batchId'] != null ||
          j['startedBy'] != null ||
          j['startedAt'] != null ||
          j['batchOperationId'] != null) {
        throw const FormatException('Invalid withdrawn evidence.');
      }
    } else if ([
      'batchId',
      'startedBy',
      'startedAt',
      'batchOperationId',
      'terminalOperationId',
      'withdrawnBy',
      'withdrawnAt',
      'withdrawalReason',
    ].any((k) => j[k] != null)) {
      throw const FormatException('Invalid assigned evidence.');
    }
  }
  final Map<String, dynamic> json;
  String get id => json['id'] as String;
  String get status => json['status'] as String;
  int get version => json['version'] as int;
  String? get batchId => json['batchId'] as String?;
  int get planned => json['plannedDeclaredBatchCount'] as int;
  Map<String, dynamic> toJson() => Map.of(json);
}
