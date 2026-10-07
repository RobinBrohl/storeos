import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = '11111111-1111-4111-8111-111111111111';
void main() {
  for (final correction in [false, true]) {
    for (final n in [if (correction) 0, 1, 9999]) {
      test(
        'whole count $n correction $correction',
        () => expect(declaredBatchCount(n, correction: correction), n),
      );
    }
    for (final value in [
      -1,
      if (!correction) 0,
      10000,
      1.5,
      1.0,
      '1',
      '1.0',
      null,
      true,
    ]) {
      test(
        'reject count $value ${value.runtimeType} correction $correction',
        () => expect(
          () => declaredBatchCount(value, correction: correction),
          throwsFormatException,
        ),
      );
    }
  }
  final open = {
    'batchId': id,
    'operationId': id,
    'recipeId': id,
    'revisionId': id,
    'plannedDeclaredBatchCount': null,
  };
  test('nullable plan and canonical stable identity', () {
    final c = PreparationCommandInput.fromJson('open', open);
    expect(c.toJson(), open);
    expect(
      c.canonical,
      PreparationCommandInput.fromJson(
        'open',
        jsonDecode(jsonEncode(open)) as Map<String, dynamic>,
      ).canonical,
    );
  });
  for (final extra in [
    'companyId',
    'employeeId',
    'openedBy',
    'openedAt',
    'content',
    'status',
    'version',
  ]) {
    test(
      'opening rejects authority $extra',
      () => expect(
        () => PreparationCommandInput.fromJson('open', {...open, extra: id}),
        throwsFormatException,
      ),
    );
  }
  for (final kind in [
    'complete',
    'employee_cancel',
    'manager_cancel',
    'count_correct',
  ]) {
    test('$kind canonical bounded evidence', () {
      final c = PreparationCommandInput.fromJson(kind, {
        'operationId': id,
        'expectedVersion': kind == 'count_correct' ? 2 : 1,
        if (kind == 'complete') ...{
          'actualDeclaredBatchCount': 2,
          'note': '  literal <script> 😀  ',
        } else
          'reason': '  literal <script> 😀  ',
        if (kind == 'count_correct') ...{
          'expectedLatestCorrectionNumber': 0,
          'replacementDeclaredBatchCount': 0,
        },
      });
      expect(
        c.payload[kind == 'complete' ? 'note' : 'reason'],
        'literal <script> 😀',
      );
    });
  }
  for (final value in ['', 'x' * 501, 'x\n', 'x\u0000', 'x\ud800']) {
    test(
      'reject invalid evidence ${value.length}',
      () => expect(
        () => preparationEvidenceText(value == 'x\n' ? 'x\ny' : value),
        throwsFormatException,
      ),
    );
  }
  test(
    '500 Unicode code points accepted',
    () => expect(preparationEvidenceText('😀' * 500).runes.length, 500),
  );
}
