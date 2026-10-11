import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

String uuid(int n) =>
    '40000000-0000-4000-8000-${n.toRadixString(16).padLeft(12, '0')}';
Map<String, dynamic> evidence(String state) {
  final accepted = {'accepted', 'approved'}.contains(state),
      terminal = !{'proposed', 'accepted'}.contains(state);
  return {
    for (final pair in {
      'id': 1,
      'companyId': 2,
      'locationId': 3,
      'sourceShiftId': 4,
      'sourceEmployeeId': 5,
      'recipientEmployeeId': 6,
      'proposedBy': 7,
      'sourceLinkId': 8,
      'recipientLinkId': 9,
      'recipientAccountId': 10,
      'proposalOperationId': 11,
    }.entries)
      pair.key: uuid(pair.value),
    'sourceVersion': 2,
    'sourceAccountVersion': 1,
    'recipientAccountVersion': 1,
    'status': state,
    'version': terminal ? (accepted ? 3 : 2) : (accepted ? 2 : 1),
    'startsAt': '2030-01-01T08:00:00Z',
    'endsAt': '2030-01-01T09:00:00Z',
    'proposedAt': '2029-01-01T08:00:00Z',
    'acceptedBy': accepted ? uuid(10) : null,
    'acceptedAt': accepted ? '2029-01-01T09:00:00Z' : null,
    'acceptanceOperationId': accepted ? uuid(12) : null,
    'terminalBy': terminal ? uuid(state == 'declined' ? 10 : 13) : null,
    'terminalAt': terminal ? '2029-01-01T10:00:00Z' : null,
    'terminalOperationId': terminal ? uuid(14) : null,
    'terminalReason': {'withdrawn', 'rejected'}.contains(state)
        ? 'Coverage changed'
        : null,
    'terminalKind': switch (state) {
      'declined' => 'decline',
      'withdrawn' => 'source_withdraw',
      'rejected' => 'manager_reject',
      'approved' => 'manager_approve',
      _ => null,
    },
    'replacementShiftId': state == 'approved' ? uuid(15) : null,
    'sourceName': 'Source <literal>',
    'recipientName': 'Recipient',
    'tasks': [
      {
        'id': uuid(16),
        'title': 'Exact task',
        'templateId': uuid(17),
        'revisionId': uuid(18),
        'position': 0,
        'knowledgeGuidance': {'articleId': uuid(19), 'revisionId': uuid(20)},
        'planogramGuidance': {
          'fixtureId': uuid(21),
          'assignmentId': uuid(22),
          'revisionId': uuid(23),
        },
      },
    ],
    'taskLinks': state == 'approved'
        ? [
            {
              'sourceTaskId': uuid(16),
              'replacementTaskId': uuid(24),
              'sourceShiftId': uuid(4),
              'replacementShiftId': uuid(15),
              'templateId': uuid(17),
              'revisionId': uuid(18),
              'position': 0,
            },
          ]
        : <Map<String, dynamic>>[],
  };
}

void main() {
  for (final state in shiftTransferStates) {
    test('$state evidence validates retained lifecycle and exact pins', () {
      final j = evidence(state), dto = ShiftTransferDto.fromJson(j);
      expect(dto.toJson(), j);
      expect(dto.status, state);
    });
  }
  test(
    'response evidence is deeply immutable and independent of input aliases',
    () {
      final j = evidence('approved'), dto = ShiftTransferDto.fromJson(j);
      j['tasks'][0]['title'] = 'Overwritten';
      expect(dto.json['tasks'][0]['title'], 'Exact task');
      expect(
        () =>
            dto.json['tasks'][0]['knowledgeGuidance']['revisionId'] = uuid(99),
        throwsUnsupportedError,
      );
      expect(() => dto.json['taskLinks'].clear(), throwsUnsupportedError);
    },
  );
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'unsafe projection': (j) => j['results'] = <Object?>[],
    'partial consent': (j) => j['acceptedAt'] = null,
    'wrong acceptance actor': (j) => j['acceptedBy'] = uuid(7),
    'dependent approver': (j) => j['terminalBy'] = uuid(10),
    'reused Shift identity': (j) =>
        j['replacementShiftId'] = j['sourceShiftId'],
    'incomplete lineage': (j) => j['taskLinks'] = <Object?>[],
    'wrong template pin': (j) => j['taskLinks'][0]['revisionId'] = uuid(99),
    'reused Task identity': (j) =>
        j['taskLinks'][0]['replacementTaskId'] = uuid(16),
    'unsafe task body': (j) => j['tasks'][0]['content'] = 'private',
    'unsafe task result': (j) => j['tasks'][0]['results'] = <Object?>[],
    'invalid guidance UUID': (j) =>
        j['tasks'][0]['knowledgeGuidance']['revisionId'] = 'bad',
    'unexpected pin field': (j) =>
        j['tasks'][0]['planogramGuidance']['latest'] = 'unexpected',
    'unsafe link evidence': (j) => j['taskLinks'][0]['value'] = 3,
    'reversed chronology': (j) => j['terminalAt'] = '2028-01-01T08:00:00Z',
    'unbounded source version': (j) => j['sourceVersion'] = 2147483648,
    'incomplete action projection': (j) => j['actionable'] = true,
  };
  for (final entry in mutations.entries) {
    test('reject ${entry.key}', () {
      final j = evidence('approved');
      entry.value(j);
      expect(() => ShiftTransferDto.fromJson(j), throwsFormatException);
    });
  }
}
