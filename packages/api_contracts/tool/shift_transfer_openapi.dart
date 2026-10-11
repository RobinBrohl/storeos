import 'dart:convert';
import 'dart:io';

/// Regenerates only P4.11 routes and their concrete bounded schemas.
void main() {
  final file = File('platform.openapi.json'),
      original = file.readAsStringSync(),
      doc = jsonDecode(original) as Map<String, dynamic>;
  final schemas = (doc['components'] as Map)['schemas'] as Map,
      paths = doc['paths'] as Map;
  final uuid = {'type': 'string', 'format': 'uuid'},
      instant = {'type': 'string', 'format': 'date-time'},
      version = {'type': 'integer', 'minimum': 1, 'maximum': 2147483647};
  Map<String, dynamic> ref(String name) => {
    r'$ref': '#/components/schemas/$name',
  };
  Map<String, dynamic> nullable(Map<String, dynamic> value) => {
    'anyOf': [
      value,
      {'type': 'null'},
    ],
  };
  Map<String, dynamic> object(
    Map<String, dynamic> properties, {
    Set<String>? required,
  }) => {
    'type': 'object',
    'additionalProperties': false,
    'required': (required ?? properties.keys.toSet()).toList(),
    'properties': properties,
  };
  final reason = {
    'type': 'string',
    'minLength': 1,
    'maxLength': 500,
    'description':
        'Trimmed plain text, bounded by Unicode code points, excluding C0/C1 controls. Required for withdrawal and manager rejection; excluded from audit/logs. Decline collects no reason.',
  };
  schemas['ShiftTransferPropose'] = object({
    'operationId': uuid,
    'requestId': uuid,
    'sourceShiftId': uuid,
    'expectedSourceVersion': version,
    'recipientEmployeeId': uuid,
  });
  schemas['ShiftTransferRespond'] = object({
    'operationId': uuid,
    'expectedVersion': version,
  });
  schemas['ShiftTransferClose'] = object({
    'operationId': uuid,
    'expectedVersion': version,
    'reason': reason,
  });
  schemas['ShiftTransferKnowledgePin'] = object({
    'articleId': uuid,
    'revisionId': uuid,
  });
  schemas['ShiftTransferPlanogramPin'] = object({
    'fixtureId': uuid,
    'assignmentId': uuid,
    'revisionId': uuid,
  });
  schemas['ShiftTransferTaskSummary'] = object({
    'id': uuid,
    'title': {'type': 'string', 'maxLength': 120},
    'templateId': uuid,
    'revisionId': uuid,
    'position': {'type': 'integer', 'minimum': 0, 'maximum': 9},
    'knowledgeGuidance': nullable(ref('ShiftTransferKnowledgePin')),
    'planogramGuidance': nullable(ref('ShiftTransferPlanogramPin')),
  });
  schemas['TaskTransferLink'] = object({
    for (final k in [
      'sourceTaskId',
      'replacementTaskId',
      'sourceShiftId',
      'replacementShiftId',
      'templateId',
      'revisionId',
    ])
      k: uuid,
    'position': {'type': 'integer', 'minimum': 0, 'maximum': 9},
  });
  final evidence = <String, dynamic>{
    for (final k in [
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
    ])
      k: uuid,
    for (final k in [
      'sourceVersion',
      'sourceAccountVersion',
      'recipientAccountVersion',
      'version',
    ])
      k: version,
    for (final k in ['startsAt', 'endsAt', 'proposedAt']) k: instant,
    'status': {
      'type': 'string',
      'enum': [
        'proposed',
        'accepted',
        'declined',
        'withdrawn',
        'rejected',
        'approved',
      ],
    },
    for (final k in [
      'acceptedBy',
      'acceptanceOperationId',
      'terminalBy',
      'terminalOperationId',
      'replacementShiftId',
    ])
      k: nullable(uuid),
    for (final k in ['acceptedAt', 'terminalAt']) k: nullable(instant),
    'terminalReason': nullable(reason),
    'terminalKind': nullable({
      'type': 'string',
      'enum': [
        'decline',
        'source_withdraw',
        'recipient_withdraw',
        'manager_reject',
        'manager_approve',
      ],
    }),
    'sourceName': {'type': 'string', 'maxLength': 120},
    'recipientName': {'type': 'string', 'maxLength': 120},
    'tasks': {
      'type': 'array',
      'minItems': 1,
      'maxItems': 10,
      'items': ref('ShiftTransferTaskSummary'),
    },
    'taskLinks': {
      'type': 'array',
      'maxItems': 10,
      'items': ref('TaskTransferLink'),
    },
  };
  schemas['ShiftTransferEvidence'] = object(evidence);
  schemas['ShiftTransferDetail'] = object({
    ...evidence,
    'actionable': {'type': 'boolean'},
    'nonActionableReason': nullable({'type': 'string'}),
    'participantRole': {
      'type': 'string',
      'enum': ['source', 'recipient', 'manager'],
    },
  });
  schemas['ShiftTransferOutcome'] = object({
    'request': ref('ShiftTransferEvidence'),
    'replayed': {'type': 'boolean'},
  });
  schemas['ShiftTransferPage'] = object({
    'items': {
      'type': 'array',
      'maxItems': 50,
      'items': ref('ShiftTransferEvidence'),
    },
    'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
  });
  schemas['ShiftTransferRecipientPage'] = object({
    'items': {
      'type': 'array',
      'maxItems': 50,
      'items': object({
        'employeeId': uuid,
        'displayName': {'type': 'string', 'maxLength': 120},
      }),
    },
    'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
    'shift': ref('Shift'),
    'sourceName': {'type': 'string', 'maxLength': 120},
    'tasks': {
      'type': 'array',
      'maxItems': 10,
      'items': ref('ShiftTransferTaskSummary'),
    },
  });
  void operation(
    String path,
    String method,
    String id,
    String response, {
    String? input,
    bool list = false,
    bool picker = false,
    bool self = true,
    String? kind,
  }) {
    final fresh = {'propose', 'accept', 'approve'}.contains(kind) || picker;
    final errors = <String, List<String>>{
      '400': [
        'invalid_request',
        if (list || picker) 'invalid_cursor',
        if (input != null) 'invalid_json',
        if (input == 'ShiftTransferClose') 'invalid_reason',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      if (input != null || picker)
        '409': [
          if (input != null) 'operation_conflict',
          if (input != null && kind != 'propose') 'transfer_conflict',
          if (fresh && !picker) 'shift_conflict',
          if (kind == 'propose') 'transfer_already_pending',
          if (fresh && !picker) 'shift_overlap',
          if (picker) 'resource_limit',
        ],
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      if (fresh)
        '422': [
          'shift_not_transferable',
          'shift_in_progress',
          if (!picker) 'employee_unavailable',
          if (!picker) 'recipient_unavailable',
          if (kind == 'accept' || kind == 'approve') 'guidance_unavailable',
          if (kind == 'accept' || kind == 'approve')
            'planogram_guidance_unavailable',
        ],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final codes in errors.values) {
      codes.sort();
    }
    final params = <Map<String, dynamic>>[
      for (final name in ['locationId', 'requestId', 'shiftId'])
        if (path.contains('{$name}'))
          {'name': name, 'in': 'path', 'required': true, 'schema': uuid},
      if (list || picker)
        {
          'name': 'after',
          'in': 'query',
          'schema': {'type': 'string', 'maxLength': 2048},
          'description':
              'Keyset cursor binds endpoint, Company, configured Location, current Employee and filters; picker also binds source Shift/version.',
        },
      if (list)
        {
          'name': 'status',
          'in': 'query',
          'schema': {
            'type': 'string',
            'enum': [
              'proposed',
              'accepted',
              'declined',
              'withdrawn',
              'rejected',
              'approved',
            ],
          },
        },
      if (list && self)
        {
          'name': 'direction',
          'in': 'query',
          'schema': {
            'type': 'string',
            'enum': ['incoming', 'outgoing'],
          },
        },
    ];
    paths.putIfAbsent(path, () => <String, dynamic>{});
    (paths[path] as Map)[method] = {
      'operationId': id,
      'summary': id,
      'security': [
        {'session': <String>[]},
      ],
      'description':
          'Current Company/capability/configured Location and participant or manager resource scope precede receipt lookup. Exact replay returns original evidence before fresh state checks. No execution results in transfer evidence. Approval requires independent manager and atomically cancels and republishes exact work. No automatic expiry or notifications.',
      'parameters': params,
      if (input != null)
        'requestBody': {
          'required': true,
          'description':
              'Strict duplicate-decoded-name JSON; at most 8192 bytes. Unknown fields refused. Identity, interval, snapshots, timestamps and replacement IDs are server-derived.',
          'content': {
            'application/json': {'schema': ref(input)},
          },
        },
      'responses': {
        kind == 'propose' ? '201' : '200': {
          'description': input == null
              ? 'Authorized current evidence.'
              : 'Original committed command evidence; current detail is loaded separately.',
          'content': {
            'application/json': {'schema': ref(response)},
          },
        },
        for (final e in errors.entries)
          e.key: {
            'description': '${e.key}: ${e.value.join(', ')}.',
            'x-error-codes': e.value,
            'content': {
              'application/json': {
                'schema': {
                  r'$ref': './openapi.yaml#/components/schemas/ApiError',
                },
              },
            },
          },
      },
    };
  }

  operation(
    '/api/v1/platform/employee-home/shifts/{shiftId}/transfer-recipients',
    'get',
    'listShiftTransferRecipients',
    'ShiftTransferRecipientPage',
    picker: true,
  );
  for (final self in [true, false]) {
    final root = self
            ? '/api/v1/platform/me/shift-transfers'
            : '/api/v1/platform/locations/{locationId}/shift-transfers',
        prefix = self ? 'Self' : 'Managed';
    operation(
      root,
      'get',
      'list${prefix}ShiftTransfers',
      'ShiftTransferPage',
      list: true,
      self: self,
    );
    operation(
      '$root/{requestId}',
      'get',
      'read${prefix}ShiftTransfer',
      'ShiftTransferDetail',
      self: self,
    );
    if (self) {
      operation(
        root,
        'post',
        'proposeShiftTransfer',
        'ShiftTransferOutcome',
        input: 'ShiftTransferPropose',
        kind: 'propose',
      );
    }
    for (final kind
        in self ? ['accept', 'decline', 'withdraw'] : ['approve', 'reject']) {
      operation(
        '$root/{requestId}/$kind',
        'post',
        '$kind${prefix}ShiftTransfer',
        'ShiftTransferOutcome',
        input: {'withdraw', 'reject'}.contains(kind)
            ? 'ShiftTransferClose'
            : 'ShiftTransferRespond',
        self: self,
        kind: kind,
      );
    }
  }
  final transferPaths = Map<String, dynamic>.fromEntries(
    paths.entries
        .where(
          (e) =>
              e.key.toString().contains('shift-transfers') ||
              e.key.toString().contains('transfer-recipients'),
        )
        .map((e) => MapEntry(e.key as String, e.value)),
  );
  final transferSchemas = Map<String, dynamic>.fromEntries(
    schemas.entries
        .where(
          (e) =>
              e.key.toString().startsWith('ShiftTransfer') ||
              e.key == 'TaskTransferLink',
        )
        .map((e) => MapEntry(e.key as String, e.value)),
  );
  file.writeAsStringSync(
    _members(
      _members(original, '"paths": {', transferPaths),
      '"schemas": {',
      transferSchemas,
    ),
  );
  final yaml = File('openapi.yaml'), existing = yaml.readAsStringSync();
  final marker = '# P4.11 transfer operations';
  final prefix = existing.contains(marker)
      ? existing.substring(0, existing.indexOf(marker))
      : existing;
  final references = StringBuffer('');
  for (final path in paths.keys.where(
    (p) =>
        (p as String).contains('shift-transfers') ||
        p.contains('transfer-recipients'),
  )) {
    references.writeln(
      '  $path:\n    \$ref: "./platform.openapi.json#/paths/${path.replaceAll('~', '~0').replaceAll('/', '~1')}"',
    );
  }
  // Path references belong to the canonical paths mapping, before components.
  final clean = prefix.replaceAll(
    RegExp(
      r'  /api/v1/platform/[^\n]*(?:shift-transfers|transfer-recipients)[^\n]*:\r?\n    \$ref:[^\n]*\r?\n',
    ),
    '',
  );
  yaml.writeAsStringSync(
    clean
        .replaceFirst('paths:\n', 'paths:\n${references.toString()}')
        .replaceFirst('paths:\r\n', 'paths:\r\n${references.toString()}'),
  );
}

// Preserve existing hand-authored schema formatting and every unrelated member.
String _members(String raw, String header, Map<String, dynamic> updates) {
  final open = raw.indexOf('{', raw.indexOf(header));
  int endObject(int start) {
    var depth = 0, quoted = false, escaped = false;
    for (var i = start; i < raw.length; i++) {
      final c = raw[i];
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (c == '\\') {
          escaped = true;
        } else if (c == '"') {
          quoted = false;
        }
        continue;
      }
      if (c == '"') {
        quoted = true;
      } else if (c == '{') {
        depth++;
      } else if (c == '}' && --depth == 0) {
        return i + 1;
      }
    }
    throw const FormatException('Unclosed OpenAPI object.');
  }

  final close = endObject(open) - 1, kept = <String>[];
  var cursor = open + 1, lastEnd = cursor, indent = 0;
  while (cursor < close) {
    final start = cursor;
    while (cursor < close && raw[cursor].trim().isEmpty) {
      cursor++;
    }
    if (cursor == close) break;
    final keyStart = cursor;
    if (indent == 0) indent = keyStart - raw.lastIndexOf('\n', keyStart) - 1;
    cursor++;
    var escaped = false;
    while (cursor < close) {
      final c = raw[cursor++];
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        break;
      }
    }
    final key = jsonDecode(raw.substring(keyStart, cursor)) as String;
    while (raw[cursor] != '{') {
      cursor++;
    }
    cursor = endObject(cursor);
    lastEnd = cursor;
    if (!updates.containsKey(key)) kept.add(raw.substring(start, cursor));
    while (cursor < close && raw[cursor].trim().isEmpty) {
      cursor++;
    }
    if (cursor < close && raw[cursor] == ',') cursor++;
  }
  for (final entry in updates.entries) {
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert({entry.key: entry.value});
    kept.add(
      encoded
          .substring(1, encoded.length - 1)
          .trimRight()
          .replaceAll('\n', '\n${' ' * (indent - 2)}'),
    );
  }
  return '${raw.substring(0, open + 1)}${kept.join(',')}${raw.substring(lastEnd, close)}${raw.substring(close)}';
}
