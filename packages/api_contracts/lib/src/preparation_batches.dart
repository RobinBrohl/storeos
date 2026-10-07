import 'dart:convert';
import 'recipes.dart';

class PreparationInputException extends FormatException {
  const PreparationInputException(this.code, String message) : super(message);
  final String code;
}

Never _fail(String code, String message) =>
    throw PreparationInputException(code, message);

int declaredBatchCount(Object? value, {bool correction = false}) {
  if (value is! int || value < (correction ? 0 : 1) || value > 9999) {
    _fail(
      'invalid_count',
      'Expected whole declared Recipe batches within the supported range.',
    );
  }
  return value;
}

String preparationEvidenceText(Object? value) {
  if (value is! String) _fail('invalid_content', 'Expected plain text.');
  final text = value.trim();
  if (text.isEmpty ||
      text.runes.length > 500 ||
      text.contains(RegExp(r'[\x00-\x1f\x7f-\x9f]')) ||
      text.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
    _fail(
      'invalid_content',
      'Evidence text must contain 1–500 characters without control characters.',
    );
  }
  return text;
}

/// Canonical client intent. Server identities and frozen content are never input.
class PreparationCommandInput {
  PreparationCommandInput._(this.kind, this.payload);
  factory PreparationCommandInput.fromJson(
    String kind,
    Map<String, dynamic> j,
  ) {
    final fields = switch (kind) {
      'open' => {
        'batchId',
        'operationId',
        'recipeId',
        'revisionId',
        'plannedDeclaredBatchCount',
      },
      'complete' => {
        'operationId',
        'expectedVersion',
        'actualDeclaredBatchCount',
        'note',
      },
      'employee_cancel' ||
      'manager_cancel' => {'operationId', 'expectedVersion', 'reason'},
      'count_correct' => {
        'operationId',
        'expectedVersion',
        'expectedLatestCorrectionNumber',
        'replacementDeclaredBatchCount',
        'reason',
      },
      _ => throw const PreparationInputException(
        'invalid_request',
        'Unknown command.',
      ),
    };
    if (j.length != fields.length || !fields.containsAll(j.keys)) {
      _fail('invalid_request', 'Unexpected or missing fields.');
    }
    final p = <String, dynamic>{'operationId': recipeId(j['operationId'])};
    if (kind == 'open') {
      for (final k in ['batchId', 'recipeId', 'revisionId']) {
        p[k] = recipeId(j[k]);
      }
      p['plannedDeclaredBatchCount'] = j['plannedDeclaredBatchCount'] == null
          ? null
          : declaredBatchCount(j['plannedDeclaredBatchCount']);
    } else {
      final version = j['expectedVersion'];
      if (version is! int || version < 1 || version > 2) {
        _fail('invalid_request', 'Expected batch version 1 or 2.');
      }
      p['expectedVersion'] = version;
      if (kind == 'complete') {
        p['actualDeclaredBatchCount'] = declaredBatchCount(
          j['actualDeclaredBatchCount'],
        );
        p['note'] = j['note'] == null
            ? null
            : preparationEvidenceText(j['note']);
      } else {
        p['reason'] = preparationEvidenceText(j['reason']);
      }
      if (kind == 'count_correct') {
        final n = j['expectedLatestCorrectionNumber'];
        if (n is! int || n < 0 || n > 2147483646) {
          _fail('invalid_request', 'Invalid correction number.');
        }
        p['expectedLatestCorrectionNumber'] = n;
        p['replacementDeclaredBatchCount'] = declaredBatchCount(
          j['replacementDeclaredBatchCount'],
          correction: true,
        );
      }
    }
    return PreparationCommandInput._(kind, Map.unmodifiable(p));
  }
  final String kind;
  final Map<String, dynamic> payload;
  String get operationId => payload['operationId'] as String;
  Map<String, dynamic> toJson() => Map.of(payload);
  String get canonical => jsonEncode(payload);
}

class PreparationBatchDto {
  PreparationBatchDto.fromJson(Map<String, dynamic> j)
    : json = Map.unmodifiable(j) {
    for (final k in [
      'batchId',
      'companyId',
      'locationId',
      'recipeId',
      'revisionId',
      'employeeId',
      'openedBy',
    ]) {
      recipeId(j[k]);
    }
    if (!['open', 'completed', 'cancelled'].contains(j['status']) ||
        j['version'] != (j['status'] == 'open' ? 1 : 2)) {
      throw const FormatException('Invalid batch lifecycle.');
    }
    if (j['plannedDeclaredBatchCount'] != null) {
      declaredBatchCount(j['plannedDeclaredBatchCount']);
    }
    if (j['status'] == 'completed') {
      declaredBatchCount(j['actualDeclaredBatchCount']);
    }
    for (final k in ['openedAt', 'completedAt', 'cancelledAt']) {
      if (j[k] != null &&
          (j[k] is! String ||
              DateTime.tryParse(j[k] as String)?.isUtc != true)) {
        throw const FormatException('Invalid evidence timestamp.');
      }
    }
  }
  final Map<String, dynamic> json;
  String get id => json['batchId'] as String;
  String get status => json['status'] as String;
  int get version => json['version'] as int;
  int? get actual => json['actualDeclaredBatchCount'] as int?;
  int? get effective => json['effectiveDeclaredBatchCount'] as int?;
  int get latestCorrectionNumber => json['latestCorrectionNumber'] as int? ?? 0;
  Map<String, dynamic> toJson() => Map.of(json);
}
