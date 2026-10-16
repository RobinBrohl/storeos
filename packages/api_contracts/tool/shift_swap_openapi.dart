import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

/// P4.16 only. Existing JSON members and canonical YAML bytes are retained.
void main() {
  final jsonFile = File('platform.openapi.json');
  final yamlFile = File('openapi.yaml');
  final json = jsonFile.readAsStringSync(), yaml = yamlFile.readAsStringSync();
  // Validate both artifacts before writing either one.
  final generated = generateShiftSwapOpenApi(json, yaml);
  if (generated.$1 != json) jsonFile.writeAsStringSync(generated.$1);
  if (generated.$2 != yaml) yamlFile.writeAsStringSync(generated.$2);
}

(String, String) generateShiftSwapOpenApi(String json, String yaml) {
  final decoded = jsonDecode(json);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Expected an OpenAPI document object.');
  }
  final doc = decoded, componentMap = doc['components'];
  final security = componentMap is Map ? componentMap['securitySchemes'] : null;
  final session = security is Map ? security['session'] : null;
  if (doc['openapi'] != '3.1.0' ||
      session is! Map ||
      session['scheme'] != 'bearer') {
    throw const FormatException(
      'Expected OpenAPI 3.1 and bearer session scheme.',
    );
  }
  final (paths, schemas) = _definitions();
  final raw = _RawJson(json);
  final pathObject = raw.memberObject(raw.root, 'paths');
  final components = raw.memberObject(raw.root, 'components');
  final schemaObject = raw.memberObject(components, 'schemas');
  for (final entry in [
    (pathObject, paths, _managedSwapPath),
    (schemaObject, schemas, (String s) => s.startsWith('ShiftSwap')),
  ]) {
    final owned = entry.$1.members.keys.where(entry.$3).toSet();
    if (owned.isNotEmpty &&
        (owned.length != entry.$2.length ||
            !owned.containsAll(entry.$2.keys))) {
      throw const FormatException('Partial or unexpected P4.16 definitions.');
    }
    for (final key in owned) {
      final member = entry.$1.members[key]!;
      if (jsonEncode(jsonDecode(json.substring(member.$1, member.$2))) !=
          jsonEncode(entry.$2[key])) {
        throw FormatException('Conflicting P4.16 definition: $key.');
      }
    }
  }
  final replacements = <(int, String)>[];
  for (final pair in [(pathObject, paths, 4), (schemaObject, schemas, 6)]) {
    if (pair.$2.keys.every(pair.$1.members.containsKey)) continue;
    if (pair.$1.members.isEmpty) {
      throw const FormatException(
        'Expected nonempty historical OpenAPI anchors.',
      );
    }
    final additions = (pair.$2.keys.toList()..sort())
        .map(
          (key) =>
              '${' ' * pair.$3}${jsonEncode(key)}: ${_render(pair.$2[key], pair.$3)}',
        )
        .join(',\n');
    replacements.add((pair.$1.start + 1, '\n$additions,'));
  }
  var result = json;
  for (final change in replacements..sort((a, b) => b.$1.compareTo(a.$1))) {
    result = result.replaceRange(change.$1, change.$1, change.$2);
  }
  final canonical = _canonicalReferences(yaml, paths.keys.toList()..sort());
  // Reject invalid proposed output before main can write either artifact.
  _RawJson(result);
  return (result, canonical);
}

// Compact small schema clauses keep bounded additions readable without changing
// any historical member's formatting or inviting large repeated-line diff moves.
String _render(Object? value, int indent) {
  final flat = jsonEncode(value), padding = ' ' * indent;
  if (flat.length <= 160 || value is! Map && value is! List) return flat;
  if (value is Map) {
    return '{\n${value.entries.map((e) => '$padding  ${jsonEncode(e.key)}: ${_render(e.value, indent + 2)}').join(',\n')}\n$padding}';
  }
  return '[\n${(value as List).map((e) => '$padding  ${_render(e, indent + 2)}').join(',\n')}\n$padding]';
}

(Map<String, dynamic>, Map<String, dynamic>) _definitions() {
  Map<String, dynamic> ref(String name) => {
    r'$ref': '#/components/schemas/$name',
  };
  Map<String, dynamic> nullable(Map<String, dynamic> value) => {
    'anyOf': [
      value,
      {'type': 'null'},
    ],
  };
  Map<String, dynamic> obj(Map<String, dynamic> fields) => {
    'type': 'object',
    'additionalProperties': false,
    'required': fields.keys.toList(),
    'properties': fields,
  };
  Map<String, dynamic> array(
    Map<String, dynamic> item,
    int max, {
    int min = 0,
  }) => {'type': 'array', 'minItems': min, 'maxItems': max, 'items': item};
  Map<String, dynamic> isValue(String name, Object? value) => {
    'properties': {
      name: {'const': value},
    },
  };
  Map<String, dynamic> nonnull(String name) => {
    'properties': {
      name: {
        'not': {'type': 'null'},
      },
    },
  };
  Map<String, dynamic> when(
    Map<String, dynamic> condition,
    Map<String, dynamic> then, [
    Map<String, dynamic>? otherwise,
  ]) => {'if': condition, 'then': then, 'else': ?otherwise};
  final id = {
    'type': 'string',
    'minLength': 36,
    'maxLength': 36,
    'pattern':
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    'description':
        'Hexadecimal UUID shape; no UUID version/variant restriction. Input is case-insensitive and normalized to lowercase.',
  };
  final canonicalId = {
    ...id,
    'pattern': (id['pattern'] as String).replaceAll('a-fA-F', 'a-f'),
    'description': 'Canonical lowercase hexadecimal UUID shape.',
  };
  final version = {'type': 'integer', 'minimum': 1, 'maximum': 2147483647};
  final instant = {
    'type': 'string',
    'format': 'date-time',
    'pattern':
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$',
    'description':
        'Valid explicit UTC/offset calendar instant, years 0001–9999, at most six fractional digits. Server output is UTC; calendar overflow and leap seconds are rejected.',
  };
  final label = {'type': 'string', 'minLength': 1, 'maxLength': 120};
  final reasonInput = {
    'type': 'string',
    'minLength': 1,
    'x-storeos-trim': true,
    'x-storeos-min-unicode-scalars': 1,
    'x-storeos-max-unicode-scalars': 500,
    'x-storeos-reject-unpaired-surrogates': true,
    'x-storeos-forbidden-controls-after-trim': 'U+0000–001F and U+007F–009F',
    'description':
        'Trim using Dart String.trim, then require 1–500 Unicode scalar values, excluding C0/C1 controls and unpaired UTF-16 surrogates. Raw surrounding whitespace is accepted. The 8192 UTF-8 byte body limit is separate; raw maxLength=500 would incorrectly reject accepted inputs. Plain text; excluded from audit/logs.',
  };
  final retainedReason = {
    ...reasonInput,
    'maxLength': 500,
    'x-storeos-trim': false,
    'x-storeos-already-trimmed': true,
    'description':
        'Retained normalized reason: already trimmed, 1–500 Unicode scalar values, no C0/C1 controls or unpaired surrogates.',
  };
  final schemas = <String, dynamic>{};
  void command(String name, Map<String, dynamic> fields) {
    schemas[name] = obj({'operationId': id, ...fields});
  }

  command('ShiftSwapRequest', {
    'requestId': id,
    'sourceShiftId': id,
    'expectedSourceVersion': version,
    'recipientEmployeeId': id,
  });
  command('ShiftSwapOffer', {
    'expectedVersion': {'type': 'integer', 'const': 1},
    'counterpartShiftId': id,
    'expectedCounterpartVersion': version,
  });
  command('ShiftSwapConfirm', {
    'expectedVersion': {'type': 'integer', 'const': 2},
  });
  command('ShiftSwapDecline', {
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 2},
  });
  command('ShiftSwapWithdraw', {
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 3},
    'reason': reasonInput,
  });
  schemas['ShiftSwapWithdraw']['description'] =
      'One public withdrawal intent. The server derives source/recipient authority from current eligible ownership inside the authorized transaction. Recipient withdrawal requires stage 2 or 3; source withdrawal permits 1–3. No client-controlled actor or kind.';
  command('ShiftSwapApprove', {
    'expectedVersion': {'type': 'integer', 'const': 3},
  });
  command('ShiftSwapReject', {
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 3},
    'reason': reasonInput,
  });
  schemas['ShiftSwapKnowledgePin'] = obj({
    'articleId': canonicalId,
    'revisionId': canonicalId,
  });
  schemas['ShiftSwapPlanogramPin'] = obj({
    'fixtureId': canonicalId,
    'assignmentId': canonicalId,
    'revisionId': canonicalId,
  });
  schemas['ShiftSwapTaskSummary'] = obj({
    'id': canonicalId,
    'templateId': canonicalId,
    'revisionId': canonicalId,
    'position': {'type': 'integer', 'minimum': 0, 'maximum': 9},
    'title': label,
    'knowledgeGuidance': nullable(ref('ShiftSwapKnowledgePin')),
    'planogramGuidance': nullable(ref('ShiftSwapPlanogramPin')),
  });
  schemas['ShiftSwapTaskLink'] = obj({
    for (final k in [
      'sourceTaskId',
      'replacementTaskId',
      'sourceShiftId',
      'replacementShiftId',
      'templateId',
      'revisionId',
    ])
      k: canonicalId,
    'position': {'type': 'integer', 'minimum': 0, 'maximum': 9},
  });
  schemas['ShiftSwapLeg'] = {
    ...obj({
      'leg': {
        'type': 'string',
        'enum': ['a', 'b'],
      },
      'sourceShiftId': canonicalId,
      'sourceVersion': version,
      'sourceEmployeeId': canonicalId,
      'incomingEmployeeId': canonicalId,
      'startsAt': instant,
      'endsAt': instant,
      'tasks': array(ref('ShiftSwapTaskSummary'), 10, min: 1),
      'taskLinks': array(ref('ShiftSwapTaskLink'), 10),
      'replacementShiftId': nullable(canonicalId),
    }),
    'allOf': [
      when(
        isValue('replacementShiftId', null),
        {
          'properties': {
            'taskLinks': {'maxItems': 0},
          },
        },
        {
          'properties': {
            'taskLinks': {'minItems': 1},
          },
        },
      ),
    ],
    'x-storeos-invariants': [
      'endsAt is strictly after startsAt; sourceEmployeeId differs from incomingEmployeeId.',
      'Task IDs are unique, positions equal their zero-based array index, and retained references are immutable.',
      'A replacement differs from its original Shift. When replaced, taskLinks has exactly tasks.length entries in the same order.',
      'Each link exactly matches its Task id/templateId/revisionId/position and enclosing sourceShiftId/replacementShiftId.',
      'Replacement Task IDs are unique and disjoint from all original Task IDs.',
    ],
  };
  final legProperties =
      schemas['ShiftSwapLeg']['properties'] as Map<String, dynamic>;
  for (final name in ['tasks', 'taskLinks']) {
    (legProperties[name] as Map)['prefixItems'] = [
      for (var i = 0; i < 10; i++)
        {
          'allOf': [
            ref(name == 'tasks' ? 'ShiftSwapTaskSummary' : 'ShiftSwapTaskLink'),
            isValue('position', i),
          ],
        },
    ];
  }
  (schemas['ShiftSwapLeg']['allOf'] as List).addAll(<Map<String, dynamic>>[
    for (var count = 1; count <= 10; count++)
      when(
        {
          'allOf': [
            nonnull('replacementShiftId'),
            {
              'properties': {
                'tasks': {'minItems': count, 'maxItems': count},
              },
            },
          ],
        },
        {
          'properties': {
            'taskLinks': {'minItems': count, 'maxItems': count},
          },
        },
      ),
  ]);
  schemas['ShiftSwapCounterpartDetail'] = {
    ...schemas['ShiftSwapLeg'] as Map<String, dynamic>,
    'properties': {
      ...legProperties,
      'leg': {'type': 'string', 'const': 'b'},
      'replacementShiftId': {'type': 'null'},
      'taskLinks': array(ref('ShiftSwapTaskLink'), 0),
    },
    'description':
        'Selected own B candidate before offer: exact original Task summary, no replacement or lineage yet.',
  };
  final states = [
    'requested',
    'offered',
    'confirmed',
    'declined',
    'withdrawn',
    'rejected',
    'approved',
  ];
  final kinds = [
    'request',
    'offer',
    'confirm',
    'decline',
    'source_withdraw',
    'recipient_withdraw',
    'manager_reject',
    'manager_approve',
  ];
  final terminalKinds = kinds.skip(3).toList();
  final legs = {
    ...array(ref('ShiftSwapLeg'), 2, min: 1),
    'prefixItems': [
      for (final leg in ['a', 'b'])
        {
          'allOf': [ref('ShiftSwapLeg'), isValue('leg', leg)],
        },
    ],
  };
  final evidenceRules = <Map<String, dynamic>>[
    for (final pair in [
      ('offeredAt', 'offerOperationId'),
      ('confirmedAt', 'confirmationOperationId'),
      ('terminalAt', 'terminalOperationId'),
    ])
      when(isValue(pair.$1, null), isValue(pair.$2, null), {
        'properties': {pair.$2: canonicalId},
      }),
    when(nonnull('confirmedAt'), {
      'properties': {'offeredAt': instant},
    }),
    when(
      isValue('offeredAt', null),
      {
        'properties': {
          'legs': {'maxItems': 1},
        },
      },
      {
        'properties': {
          'legs': {'minItems': 2},
        },
      },
    ),
    for (final (state, v) in [
      ('requested', 1),
      ('offered', 2),
      ('confirmed', 3),
    ])
      when(isValue('status', state), {
        'properties': {
          'version': {'const': v},
          'offeredAt': v >= 2 ? instant : {'type': 'null'},
          'confirmedAt': v >= 3 ? instant : {'type': 'null'},
          'terminalAt': {'type': 'null'},
          'terminalKind': {'type': 'null'},
        },
      }),
    when(
      {
        'properties': {
          'status': {'enum': states.skip(3).toList()},
        },
      },
      {
        'properties': {
          'terminalAt': instant,
          'terminalKind': {'enum': terminalKinds},
        },
        'allOf': [
          when(
            nonnull('confirmedAt'),
            isValue('version', 4),
            when(
              nonnull('offeredAt'),
              isValue('version', 3),
              isValue('version', 2),
            ),
          ),
        ],
      },
    ),
    when(
      {
        'properties': {
          'status': {
            'enum': ['withdrawn', 'rejected'],
          },
        },
      },
      {
        'properties': {'terminalReason': retainedReason},
      },
      isValue('terminalReason', null),
    ),
    when(isValue('status', 'declined'), {
      'properties': {
        'confirmedAt': {'type': 'null'},
        'terminalKind': {'const': 'decline'},
      },
    }),
    when(isValue('status', 'withdrawn'), {
      'properties': {
        'terminalKind': {
          'enum': ['source_withdraw', 'recipient_withdraw'],
        },
      },
    }),
    when(isValue('terminalKind', 'recipient_withdraw'), {
      'properties': {'offeredAt': instant},
    }),
    when(
      isValue('status', 'rejected'),
      isValue('terminalKind', 'manager_reject'),
    ),
    when(
      isValue('status', 'approved'),
      {
        'properties': {
          'confirmedAt': instant,
          'terminalKind': {'const': 'manager_approve'},
          'legs': {
            'items': {
              'properties': {
                'replacementShiftId': canonicalId,
                'taskLinks': {'minItems': 1},
              },
            },
          },
        },
      },
      {
        'properties': {
          'legs': {'items': isValue('replacementShiftId', null)},
        },
      },
    ),
  ];
  schemas['ShiftSwapEvidence'] = {
    ...obj({
      for (final k in [
        'id',
        'companyId',
        'locationId',
        'sourceEmployeeId',
        'recipientEmployeeId',
      ])
        k: canonicalId,
      'sourceName': label,
      'recipientName': label,
      'status': {'type': 'string', 'enum': states},
      'version': {'type': 'integer', 'minimum': 1, 'maximum': 4},
      'requestedAt': instant,
      'requestOperationId': canonicalId,
      for (final k in ['offeredAt', 'confirmedAt', 'terminalAt'])
        k: nullable(instant),
      for (final k in [
        'offerOperationId',
        'confirmationOperationId',
        'terminalOperationId',
      ])
        k: nullable(canonicalId),
      'terminalKind': nullable({'type': 'string', 'enum': terminalKinds}),
      'terminalReason': nullable(retainedReason),
      'legs': legs,
    }),
    'allOf': evidenceRules,
    'description':
        'Immutable disclosed evidence, including original accepted snapshots; it is not current actionability. Every property is required, with explicit nulls where applicable. At most two legs, ten original Tasks per leg and twenty paired Task links overall.',
    'x-storeos-invariants': [
      'Source and recipient Employee identities differ; ordered leg a is source-to-recipient and leg b is recipient-to-source.',
      'Original Shift IDs, replacement Shift IDs, original Task IDs and replacement Task IDs are unique across both legs; original and replacement sets are disjoint.',
      'Requested/offered/confirmed/terminal instants are chronological. Each non-null instant has its matching operation ID.',
      'Exact cross-field and cross-array reference identity is validated by ShiftSwapDto and ShiftSwapLegDto; JSON Schema cannot compare arbitrary instance values.',
    ],
  };
  schemas['ShiftSwapCommandResult'] = {
    ...obj({
      'operationId': canonicalId,
      'kind': {'type': 'string', 'enum': kinds},
      'acceptedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 4},
      'statusCode': {
        'type': 'integer',
        'enum': [200, 201],
      },
      'request': ref('ShiftSwapEvidence'),
      'replayed': {'type': 'boolean'},
    }),
    'x-storeos-max-utf8-bytes': 65536,
    'x-storeos-invariants': [
      'acceptedVersion equals request.version. operationId equals the matching request/offer/confirmation/terminal operation ID.',
      'Original accepted evidence/status is returned on exact replay after current authorization; current actionability requires a separate detail read.',
    ],
    'allOf': [
      for (final kind in kinds)
        when(isValue('kind', kind), {
          'properties': {
            'statusCode': {'const': kind == 'request' ? 201 : 200},
            'request': {
              'properties': {
                'status': {
                  'const': switch (kind) {
                    'request' => 'requested',
                    'offer' => 'offered',
                    'confirm' => 'confirmed',
                    'decline' => 'declined',
                    'source_withdraw' || 'recipient_withdraw' => 'withdrawn',
                    'manager_reject' => 'rejected',
                    _ => 'approved',
                  },
                },
                if (terminalKinds.contains(kind))
                  'terminalKind': {'const': kind},
              },
            },
          },
        }),
    ],
  };
  (schemas['ShiftSwapCommandResult']['allOf'] as List).addAll(
    <Map<String, dynamic>>[
      for (var v = 1; v <= 4; v++)
        when({
          'properties': {'request': isValue('version', v)},
        }, isValue('acceptedVersion', v)),
    ],
  );
  final detailRules = <Map<String, dynamic>>[
    when(isValue('actionable', true), isValue('nonActionableReason', null)),
    when({
      'properties': {
        'request': {
          'properties': {
            'status': {'enum': states.skip(3).toList()},
          },
        },
      },
    }, isValue('actionable', false)),
  ];
  for (final role in ['source', 'recipient', 'manager']) {
    for (final state in states) {
      final allowed = switch ((role, state)) {
        ('source', 'requested' || 'confirmed') => ['source_withdraw'],
        ('source', 'offered') => ['confirm', 'decline', 'source_withdraw'],
        ('recipient', 'requested') => ['offer', 'decline'],
        ('recipient', 'offered' || 'confirmed') => ['recipient_withdraw'],
        ('manager', 'requested' || 'offered') => ['manager_reject'],
        ('manager', 'confirmed') => ['manager_reject', 'manager_approve'],
        _ => <String>[],
      };
      detailRules.add(
        when(
          {
            'properties': {
              'participantRole': {'const': role},
              'request': isValue('status', state),
            },
          },
          {
            'properties': {
              'availableActions': allowed.isEmpty
                  ? {'maxItems': 0}
                  : {
                      'items': {'enum': allowed},
                    },
            },
          },
        ),
      );
    }
  }
  schemas['ShiftSwapDetail'] = {
    ...obj({
      'request': ref('ShiftSwapEvidence'),
      'participantRole': {
        'type': 'string',
        'enum': ['source', 'recipient', 'manager'],
      },
      'actionable': {'type': 'boolean'},
      'nonActionableReason': nullable({
        'type': 'string',
        'pattern': r'^[a-z][a-z0-9_]{0,63}$',
        'maxLength': 64,
      }),
      'availableActions': {
        ...array({'type': 'string', 'enum': kinds.skip(1).toList()}, 3),
        'uniqueItems': true,
      },
    }),
    'allOf': detailRules,
    'description':
        'Current scoped action hints alongside immutable evidence. Actions never confer permission; fresh server authorization and state validation are required.',
  };
  final cursor = nullable({
    'type': 'string',
    'minLength': 1,
    'maxLength': 2048,
    'x-storeos-max-utf16-code-units': 2048,
  });
  void page(
    String name,
    Map<String, dynamic> item,
    int max,
    String description,
  ) {
    schemas[name] = {
      ...obj({
        'items': {...array(item, max), 'uniqueItems': true},
        'nextCursor': cursor,
      }),
      'description': description,
    };
  }

  page(
    'ShiftSwapPage',
    ref('ShiftSwapEvidence'),
    50,
    'At most fifty distinct request IDs, keyset ordered; required nextCursor is null at end.',
  );
  schemas['ShiftSwapColleague'] = obj({
    'employeeId': canonicalId,
    'displayName': label,
  });
  page(
    'ShiftSwapColleaguePage',
    ref('ShiftSwapColleague'),
    50,
    'At most fifty distinct eligible Employee identities, never a colleague roster.',
  );
  schemas['ShiftSwapCounterpartCandidate'] = obj({
    'shiftId': canonicalId,
    'version': version,
    'startsAt': instant,
    'endsAt': instant,
  });
  schemas['ShiftSwapCounterpartCandidate']['x-storeos-invariants'] = [
    'endsAt is strictly after startsAt.',
  ];
  page(
    'ShiftSwapCounterpartPage',
    ref('ShiftSwapCounterpartCandidate'),
    50,
    'At most fifty distinct eligible own Shift IDs for captured recipient B, ordered by startsAt/id.',
  );
  page(
    'ShiftSwapHistoryPage',
    ref('ShiftSwapCommandResult'),
    2,
    'Two immutable original receipts per page, ordered by acceptedVersion; at most four receipts over the lifecycle. Original statusCode/kind/version/replayed metadata is retained.',
  );

  final paths = <String, dynamic>{};
  void operation(
    String path,
    String method,
    String operationId,
    String response,
    String authorization, {
    String? input,
    String? kind,
    bool paginated = false,
    bool list = false,
    bool self = true,
    List<String> conflicts = const [],
    bool fresh = false,
  }) {
    final errors = <String, List<String>>{
      '400': [
        'invalid_request',
        if (paginated) 'invalid_cursor',
        if (input != null) 'invalid_json',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      if (conflicts.isNotEmpty) '409': conflicts,
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      if (fresh)
        '422': [
          'employee_unavailable',
          'guidance_unavailable',
          'planogram_guidance_unavailable',
          'shift_in_progress',
          'shift_not_swappable',
          'shift_not_transferable',
          if (kind == 'manager_approve') 'invalid_selection',
        ],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final codes in errors.values) {
      codes.sort();
    }
    final parameters = <Map<String, dynamic>>[
      for (final name in ['locationId', 'requestId', 'shiftId'])
        if (path.contains('{$name}'))
          {'name': name, 'in': 'path', 'required': true, 'schema': id},
      if (paginated)
        {
          'name': 'after',
          'in': 'query',
          'schema': {
            'type': 'string',
            'minLength': 1,
            'maxLength': 2048,
            'x-storeos-max-utf16-code-units': 2048,
          },
          'description':
              'Opaque scoped keyset cursor; possession grants no authority. Binds Company, configured Location, endpoint, current reader/participant/request and applicable filters/identity basis. Not a general roster cursor. Empty/invalid/stale or cross-scope cursors return invalid_cursor.',
        },
      if (list)
        {
          'name': 'status',
          'in': 'query',
          'schema': {'type': 'string', 'enum': states},
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
    final successSchema = {
      ...ref(response),
      if (kind != null)
        'properties': {
          'kind': {
            'enum': kind == 'withdraw'
                ? ['source_withdraw', 'recipient_withdraw']
                : [kind],
          },
        },
    };
    final entry = {
      'operationId': operationId,
      'summary': operationId,
      'security': [
        {'session': <String>[]},
      ],
      'description':
          '$authorization Current authenticated Company/configured execution Location and resource scope are checked on the server, independently of OpenAPI/UI controls. Current authorization precedes receipt replay. Unknown or duplicate query keys are rejected. Original accepted receipt evidence is separate from current actionability. Native upload expiry may destroy the connection without a completed HTTP error response; no pre-EOF 413 guarantee is made.',
      'parameters': parameters,
      if (input != null)
        'requestBody': {
          'required': true,
          'x-storeos-max-utf8-bytes': 8192,
          'description':
              'Complete strict JSON object, at most 8192 UTF-8 bytes, duplicate decoded property names and unknown fields rejected. No client actor/Account, replacement IDs, snapshots or server timestamps. JSON consumption reaches genuine native EOF before Application mutation; aborted/cancelled/expired input is not completion. Reason normalization limits are separate from wire bytes.',
          'content': {
            'application/json': {'schema': ref(input)},
          },
        },
      'responses': {
        kind == 'request' ? '201' : '200': {
          'description': input == null
              ? 'Authorized scoped evidence.'
              : 'Original accepted command evidence and status; exact replay adds replayed=true after current authorization.',
          'content': {
            'application/json': {'schema': successSchema},
          },
        },
        for (final error in errors.entries)
          error.key: {
            'description': '${error.key}: ${error.value.join(', ')}.',
            'x-error-codes': error.value,
            'content': {
              'application/json': {
                'schema': {
                  'allOf': [
                    {r'$ref': './openapi.yaml#/components/schemas/ApiError'},
                    {
                      'properties': {
                        'code': {'enum': error.value},
                      },
                    },
                  ],
                },
              },
            },
          },
      },
    };
    (paths.putIfAbsent(path, () => <String, dynamic>{}) as Map)[method] = entry;
  }

  const participantRead =
      'Requires workforce.swaps.self.read and a current eligible Account–Employee link. Only current source/recipient participants can read this request; IDs and cursors confer no access.';
  const requestAuth =
      'Requires workforce.swaps.self.read plus workforce.swaps.self.request, current eligible source linkage and an own future pristine source Shift. Discovery discloses eligible colleague ID/name only; it grants no colleague roster access.';
  const recipientAuth =
      'Requires workforce.swaps.self.read plus workforce.swaps.self.respond, the captured recipient Account/link and request-specific invitation. Counterparts expose only B’s own eligible work; A cannot inspect arbitrary peer Shifts.';
  const managerAuth =
      'Requires workforce.swaps.manage in the configured Company/Location. A request ID is not authority.';
  const root = '/api/v1/platform/me/shift-swaps';
  const managed = '/api/v1/platform/locations/{locationId}/shift-swaps';
  operation(
    '/api/v1/platform/employee-home/shifts/{shiftId}/swap-colleagues',
    'get',
    'listShiftSwapColleagues',
    'ShiftSwapColleaguePage',
    requestAuth,
    paginated: true,
    fresh: true,
    conflicts: ['resource_limit'],
  );
  for (final self in [true, false]) {
    final base = self ? root : managed, prefix = self ? 'Self' : 'Managed';
    operation(
      base,
      'get',
      'list${prefix}ShiftSwaps',
      'ShiftSwapPage',
      self ? participantRead : managerAuth,
      paginated: true,
      list: true,
      self: self,
    );
    operation(
      '$base/{requestId}',
      'get',
      'read${prefix}ShiftSwap',
      'ShiftSwapDetail',
      self ? participantRead : managerAuth,
    );
    operation(
      '$base/{requestId}/history',
      'get',
      'list${prefix}ShiftSwapHistory',
      'ShiftSwapHistoryPage',
      self ? participantRead : managerAuth,
      paginated: true,
    );
  }
  operation(
    root,
    'post',
    'requestShiftSwap',
    'ShiftSwapCommandResult',
    requestAuth,
    input: 'ShiftSwapRequest',
    kind: 'request',
    fresh: true,
    conflicts: ['operation_conflict', 'shift_conflict', 'swap_already_pending'],
  );
  operation(
    '$root/{requestId}/counterparts',
    'get',
    'listShiftSwapCounterparts',
    'ShiftSwapCounterpartPage',
    recipientAuth,
    paginated: true,
    fresh: true,
    conflicts: ['shift_conflict', 'swap_conflict'],
  );
  operation(
    '$root/{requestId}/counterparts/{shiftId}',
    'get',
    'readShiftSwapCounterpart',
    'ShiftSwapCounterpartDetail',
    recipientAuth,
    fresh: true,
    conflicts: [
      'shift_conflict',
      'shift_overlap',
      'swap_already_pending',
      'swap_conflict',
    ],
  );
  for (final (action, input, authority) in [
    ('offer', 'ShiftSwapOffer', recipientAuth),
    (
      'confirm',
      'ShiftSwapConfirm',
      'Requires workforce.swaps.self.read and workforce.swaps.self.respond plus the captured source Account/link. Confirmation binds the exact stored offer pair, not a new client-supplied pair.',
    ),
    (
      'decline',
      'ShiftSwapDecline',
      'Requires workforce.swaps.self.read and workforce.swaps.self.respond. Captured B declines requested/1; captured A declines offered/2. Decline accepts no reason.',
    ),
    (
      'withdraw',
      'ShiftSwapWithdraw',
      'Requires workforce.swaps.self.read. Current eligible source ownership plus workforce.swaps.self.request may withdraw stages 1–3, including a replacement source Account; captured B plus workforce.swaps.self.respond may withdraw stages 2–3. Server derives intent before parsing/replay; no client actor/kind selector.',
    ),
  ]) {
    operation(
      '$root/{requestId}/$action',
      'post',
      '${action}SelfShiftSwap',
      'ShiftSwapCommandResult',
      authority,
      input: input,
      kind: action,
      fresh: {'offer', 'confirm'}.contains(action),
      conflicts: [
        'operation_conflict',
        'swap_conflict',
        if ({'offer', 'confirm'}.contains(action)) ...[
          'shift_conflict',
          'shift_overlap',
        ],
        if (action == 'offer') 'swap_already_pending',
      ],
    );
  }
  operation(
    '$managed/{requestId}/approve',
    'post',
    'approveManagedShiftSwap',
    'ShiftSwapCommandResult',
    '$managerAuth Additionally requires workforce.shifts.manage and tasks.instances.read, current guidance read permissions when pinned, and an approver Account independent of both consenting Accounts. Both exact consents, original work, identity bases, final roster and database-time boundary are revalidated. Both cancellations/replacements, complete ordered lineage, receipt/audit and claim release commit atomically.',
    input: 'ShiftSwapApprove',
    kind: 'manager_approve',
    fresh: true,
    conflicts: [
      'operation_conflict',
      'shift_conflict',
      'shift_overlap',
      'swap_conflict',
    ],
  );
  operation(
    '$managed/{requestId}/reject',
    'post',
    'rejectManagedShiftSwap',
    'ShiftSwapCommandResult',
    '$managerAuth Explicit reason-bearing closure of stages 1–3; stale work can be rejected without fresh approval eligibility.',
    input: 'ShiftSwapReject',
    kind: 'manager_reject',
    conflicts: ['operation_conflict', 'swap_conflict'],
  );
  void integerTokens(Object? node) {
    if (node is Map) {
      if (node['type'] == 'integer') node['x-storeos-integer-token'] = true;
      for (final value in node.values.toList()) {
        integerTokens(value);
      }
    } else if (node is List) {
      for (final value in node) {
        integerTokens(value);
      }
    }
  }

  integerTokens(schemas);
  return (paths, schemas);
}

String _canonicalReferences(String yaml, List<String> paths) {
  final input = _canonicalYaml(yaml);
  final owned = _swapReferences(input.$1, paths);
  if (owned.isNotEmpty) return yaml;
  final newline = yaml.contains('\r\n') ? '\r\n' : '\n';
  final indent = ' ' * input.$3;
  final entries = paths
      .map(
        (p) =>
            '$indent$p:$newline$indent  \$ref: "${_pathReference(p)}"$newline',
      )
      .join();
  final result = yaml.replaceRange(input.$2, input.$2, entries);
  if (_swapReferences(_canonicalYaml(result).$1, paths).length !=
      paths.length) {
    throw const FormatException('Incomplete generated canonical P4.16 paths.');
  }
  return result;
}

bool _managedSwapPath(String path) => RegExp(
  r'^/api/v1/platform/(?:me/shift-swaps|locations/[^/]+/shift-swaps|employee-home/shifts/[^/]+/swap-colleagues)(?:/|$)',
).hasMatch(path);

String _pathReference(String path) =>
    './platform.openapi.json#/paths/${path.replaceAll('~', '~0').replaceAll('/', '~1')}';

Set<String> _swapReferences(YamlMap mapping, List<String> expected) {
  final owned = mapping.keys.cast<String>().where(_managedSwapPath).toSet();
  for (final path in owned) {
    final definition = mapping[path];
    if (!expected.contains(path) ||
        definition is! YamlMap ||
        definition.length != 1 ||
        definition[r'$ref'] != _pathReference(path)) {
      throw FormatException('Conflicting canonical P4.16 reference: $path.');
    }
  }
  if (owned.isNotEmpty && owned.length != expected.length) {
    throw FormatException(
      'Partial canonical P4.16 paths at ${owned.first}; missing ${expected.firstWhere((p) => !owned.contains(p))}.',
    );
  }
  return owned;
}

/// Parse without recovery: the pinned loader rejects duplicate keys at every
/// depth. Node spans locate the insertion without serializing historical YAML.
(YamlMap, int, int) _canonicalYaml(String source) {
  late final YamlNode document;
  try {
    document = loadYamlNode(source);
  } on YamlException catch (error) {
    throw FormatException('Invalid canonical YAML: $error');
  }
  final visited = Set<YamlNode>.identity();
  void validate(YamlNode node) {
    if (!visited.add(node)) {
      throw const FormatException('Unsupported canonical YAML alias.');
    }
    if (node is YamlMap) {
      for (final entry in node.nodes.entries) {
        final key = entry.key as YamlNode;
        if (key.value is! String || key.value == '<<') {
          throw FormatException(
            'Unsupported canonical YAML key: ${key.value}.',
          );
        }
        validate(key);
        validate(entry.value);
      }
    } else if (node is YamlList) {
      node.nodes.forEach(validate);
    }
  }

  validate(document);
  if (document is! YamlMap || document.style != CollectionStyle.BLOCK) {
    throw const FormatException('Expected canonical YAML root block mapping.');
  }
  final paths = document.nodes['paths'];
  final components = document.nodes['components'];
  if (document['openapi'] != '3.1.0' ||
      paths is! YamlMap ||
      paths.isEmpty ||
      paths.style != CollectionStyle.BLOCK ||
      components is! YamlMap ||
      components.style != CollectionStyle.BLOCK ||
      components.nodes['schemas'] is! YamlMap) {
    throw const FormatException(
      'Expected OpenAPI 3.1 canonical YAML paths/components/schemas mappings.',
    );
  }
  final keys = document.nodes.keys.cast<YamlNode>().toList();
  final pathIndex = keys.indexWhere((k) => k.value == 'paths');
  final componentIndex = keys.indexWhere((k) => k.value == 'components');
  if (componentIndex != pathIndex + 1 ||
      keys[pathIndex].span.start.column != 0 ||
      keys[componentIndex].span.start.column != 0 ||
      paths.keys.any((p) => p is! String || !p.startsWith('/'))) {
    throw const FormatException(
      'Unsupported canonical YAML layout: paths must immediately precede components and contain path keys.',
    );
  }
  return (
    paths,
    keys[componentIndex].span.start.offset,
    paths.nodes.keys.cast<YamlNode>().first.span.start.column,
  );
}

class _RawObject {
  _RawObject(this.start);
  final int start;
  final members = <String, (int, int)>{};
}

/// Indexes JSON object/value spans, rejecting duplicate keys at every depth.
/// Only mapping boundaries receive bytes; existing members are not encoded.
class _RawJson {
  _RawJson(this.raw) {
    _space();
    root = _object();
    _space();
    if (at != raw.length) {
      throw const FormatException('Unexpected JSON suffix.');
    }
  }
  final String raw;
  int at = 0;
  late final _RawObject root;
  final objects = <int, _RawObject>{};
  void _space() {
    while (at < raw.length && raw[at].trim().isEmpty) {
      at++;
    }
  }

  String _string() {
    final start = at++;
    while (at < raw.length) {
      if (raw[at] == r'\') {
        at += 2;
        continue;
      }
      if (raw[at++] == '"') {
        return jsonDecode(raw.substring(start, at)) as String;
      }
    }
    throw const FormatException('Unclosed JSON string.');
  }

  void _value() {
    _space();
    if (raw[at] == '{') {
      _object();
    } else if (raw[at] == '[') {
      at++;
      _space();
      while (raw[at] != ']') {
        _value();
        _space();
        if (raw[at] != ',') break;
        at++;
        _space();
      }
      at++;
    } else if (raw[at] == '"') {
      _string();
    } else {
      while (at < raw.length && !',}] \t\r\n'.contains(raw[at])) {
        at++;
      }
    }
  }

  _RawObject _object() {
    if (raw[at] != '{') throw const FormatException('Expected OpenAPI object.');
    final start = at++;
    final result = objects[start] = _RawObject(start);
    _space();
    while (raw[at] != '}') {
      final key = _string();
      _space();
      if (raw[at++] != ':') {
        throw const FormatException('Expected JSON member.');
      }
      _space();
      final start = at;
      _value();
      if (result.members.containsKey(key)) {
        throw FormatException('Duplicate JSON key: $key.');
      }
      result.members[key] = (start, at);
      _space();
      if (raw[at] != ',') break;
      at++;
      _space();
    }
    if (raw[at++] != '}') throw const FormatException('Expected object close.');
    return result;
  }

  _RawObject memberObject(_RawObject parent, String key) {
    final member = parent.members[key];
    final value = member == null ? null : objects[member.$1];
    if (value == null) throw FormatException('Missing object anchor: $key.');
    return value;
  }
}
