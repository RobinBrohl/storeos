String swapId(int n) =>
    '11111111-1111-4111-8111-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> swapEvidence({
  String state = 'requested',
  int stage = 1,
  int tasks = 1,
}) {
  final offered = stage >= 2,
      confirmed = stage >= 3,
      approved = state == 'approved';
  final terminal = !{'requested', 'offered', 'confirmed'}.contains(state);
  Map<String, dynamic> leg(String which, int offset) {
    final work = [
      for (var i = 0; i < tasks; i++)
        {
          'id': swapId(offset + 100 + i),
          'templateId': swapId(500 + i),
          'revisionId': swapId(600 + i),
          'position': i,
          'title': 'Exact work $i',
          'knowledgeGuidance': null,
          'planogramGuidance': null,
        },
    ];
    return {
      'leg': which,
      'sourceShiftId': swapId(offset),
      'sourceVersion': 2,
      'sourceEmployeeId': swapId(which == 'a' ? 4 : 5),
      'incomingEmployeeId': swapId(which == 'a' ? 5 : 4),
      'startsAt': '2030-01-01T10:00:00Z',
      'endsAt': '2030-01-01T11:00:00Z',
      'tasks': work,
      'replacementShiftId': approved ? swapId(offset + 10) : null,
      'taskLinks': [
        if (approved)
          for (var i = 0; i < tasks; i++)
            {
              'sourceTaskId': work[i]['id'],
              'replacementTaskId': swapId(offset + 200 + i),
              'sourceShiftId': swapId(offset),
              'replacementShiftId': swapId(offset + 10),
              'templateId': work[i]['templateId'],
              'revisionId': work[i]['revisionId'],
              'position': i,
            },
      ],
    };
  }

  return {
    'id': swapId(1),
    'companyId': swapId(2),
    'locationId': swapId(3),
    'sourceEmployeeId': swapId(4),
    'recipientEmployeeId': swapId(5),
    'sourceName': 'A',
    'recipientName': 'B',
    'status': state,
    'version': terminal ? stage + 1 : stage,
    'requestedAt': '2029-01-01T10:00:00Z',
    'requestOperationId': swapId(6),
    'offeredAt': offered ? '2029-01-01T11:00:00Z' : null,
    'offerOperationId': offered ? swapId(7) : null,
    'confirmedAt': confirmed ? '2029-01-01T12:00:00Z' : null,
    'confirmationOperationId': confirmed ? swapId(8) : null,
    'terminalAt': terminal ? '2029-01-01T13:00:00Z' : null,
    'terminalOperationId': terminal ? swapId(9) : null,
    'terminalKind': terminal
        ? switch (state) {
            'declined' => 'decline',
            'withdrawn' => 'source_withdraw',
            'rejected' => 'manager_reject',
            _ => 'manager_approve',
          }
        : null,
    'terminalReason': {'withdrawn', 'rejected'}.contains(state)
        ? 'Coverage changed'
        : null,
    'legs': [leg('a', 20), if (offered) leg('b', 40)],
  };
}

Map<String, dynamic> swapCommand(String kind, int version) => {
  'operationId': swapId(900),
  if (kind == 'request') ...{
    'requestId': swapId(1),
    'sourceShiftId': swapId(20),
    'expectedSourceVersion': version,
    'recipientEmployeeId': swapId(5),
  } else
    'expectedVersion': version,
  if (kind == 'offer') ...{
    'counterpartShiftId': swapId(40),
    'expectedCounterpartVersion': 2,
  },
  if ({
    'source_withdraw',
    'recipient_withdraw',
    'manager_reject',
  }.contains(kind))
    'reason': 'Coverage changed',
};
