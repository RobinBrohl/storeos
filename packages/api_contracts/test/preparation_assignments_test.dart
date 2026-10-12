import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

const id = '11111111-1111-4111-8111-111111111111';
Map<String, dynamic> create() => {
  'id': id,
  'operationId': id,
  'recipeId': id,
  'revisionId': id,
  'employeeId': id,
  'expectedEmployeeVersion': 1,
  'plannedDeclaredBatchCount': 3,
};
void main() {
  test('exact immutable canonical create intent', () {
    final input = create();
    final c = PreparationAssignmentCommandInput.fromJson('create', input);
    input['plannedDeclaredBatchCount'] = 9;
    expect(c.payload['plannedDeclaredBatchCount'], 3);
    expect(() => c.payload['employeeId'] = id, throwsUnsupportedError);
    expect(
      PreparationAssignmentCommandInput.fromJson(
        'create',
        c.toJson(),
      ).canonical,
      c.canonical,
    );
  });
  for (final count in [null, 0, 10000, 1.0, '3', true]) {
    test(
      'reject count $count (${count.runtimeType})',
      () => expect(
        () => PreparationAssignmentCommandInput.fromJson(
          'create',
          create()..['plannedDeclaredBatchCount'] = count,
        ),
        throwsFormatException,
      ),
    );
  }
  for (final field in [
    'companyId',
    'locationId',
    'actorId',
    'batchId',
    'batchOperationId',
    'startedAt',
    'snapshot',
  ]) {
    test(
      'reject forged $field',
      () => expect(
        () => PreparationAssignmentCommandInput.fromJson(
          'create',
          create()..[field] = id,
        ),
        throwsFormatException,
      ),
    );
  }
  for (final v in [0, 3, 1.0, '1', null]) {
    test(
      'reject version $v (${v.runtimeType})',
      () => expect(
        () => PreparationAssignmentCommandInput.fromJson('start', {
          'operationId': id,
          'expectedVersion': v,
        }),
        throwsFormatException,
      ),
    );
  }
  test('start rejects overriding count and employee', () {
    for (final field in [
      'plannedDeclaredBatchCount',
      'employeeId',
      'batchId',
      'recipeId',
    ]) {
      expect(
        () => PreparationAssignmentCommandInput.fromJson('start', {
          'operationId': id,
          'expectedVersion': 1,
          field: id,
        }),
        throwsFormatException,
      );
    }
  });
  test('reason Unicode bounds and controls', () {
    for (final reason in ['', 'x' * 501, '\u0000', '\ud800', 'line\nline']) {
      expect(
        () => PreparationAssignmentCommandInput.fromJson('withdraw', {
          'operationId': id,
          'expectedVersion': 1,
          'reason': reason,
        }),
        throwsFormatException,
      );
    }
    expect(
      PreparationAssignmentCommandInput.fromJson('withdraw', {
        'operationId': id,
        'expectedVersion': 1,
        'reason': ' 😀 reason ',
      }).payload['reason'],
      '😀 reason',
    );
  });
}
