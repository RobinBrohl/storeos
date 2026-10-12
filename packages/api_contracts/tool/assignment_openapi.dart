import 'dart:convert';
import 'dart:io';

/// Add only the bounded P4.13 contracts to the immutable HEAD representation.
void main() {
  final baseline = Process.runSync('git', [
    'show',
    'HEAD:packages/api_contracts/platform.openapi.json',
  ], stdoutEncoding: null);
  if (baseline.exitCode != 0) throw StateError('Cannot read baseline OpenAPI.');
  final original = utf8.decode(baseline.stdout as List<int>);
  final uuid = {'type': 'string', 'format': 'uuid'},
      instant = {'type': 'string', 'format': 'date-time'};
  Map<String, dynamic> nullable(Map<String, dynamic> j) => {
    'anyOf': [
      j,
      {'type': 'null'},
    ],
  };
  Map<String, dynamic> object(Map<String, dynamic> j) => {
    'type': 'object',
    'additionalProperties': false,
    'required': j.keys.toList(),
    'properties': j,
  };
  Map<String, dynamic> ref(String name) => {
    r'$ref': '#/components/schemas/$name',
  };
  final count = {
    'type': 'integer',
    'minimum': 1,
    'maximum': 9999,
    'description':
        'Whole repetitions of one declared Recipe batch; no output units, yield or Stock effect.',
  };
  final version = {'type': 'integer', 'minimum': 1, 'maximum': 2};
  final text = {
    'type': 'string',
    'minLength': 1,
    'maxLength': 500,
    'description':
        'Trimmed literal text; control characters and malformed Unicode rejected.',
  };
  final properties = <String, dynamic>{
    for (final k in [
      'id',
      'companyId',
      'locationId',
      'employeeId',
      'recipeId',
      'revisionId',
      'createdBy',
      'createOperationId',
    ])
      k: uuid,
    'plannedDeclaredBatchCount': count,
    'createdAt': instant,
    'status': {
      'type': 'string',
      'enum': ['assigned', 'started', 'withdrawn'],
    },
    'version': version,
    for (final k in [
      'batchId',
      'batchOperationId',
      'startedBy',
      'withdrawnBy',
      'terminalOperationId',
    ])
      k: nullable(uuid),
    'startedAt': nullable(instant),
    'withdrawnAt': nullable(instant),
    'withdrawalReason': nullable(text),
  };
  final schemas = <String, dynamic>{
    'PreparationAssignment': object(properties),
    'PreparationAssignmentDetail': object({
      ...properties,
      'batch': nullable(ref('PreparationBatchDetail')),
    }),
    'PreparationAssignmentHistory': object({
      'assignment': ref('PreparationAssignment'),
      'batch': nullable(ref('PreparationBatchDetail')),
    }),
    'PreparationAssignmentPage': object({
      'items': {
        'type': 'array',
        'maxItems': 50,
        'items': ref('PreparationAssignment'),
      },
      'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
    }),
    'PreparationAssignee': object({
      'id': uuid,
      'displayName': {'type': 'string'},
      'version': {'type': 'integer', 'minimum': 1, 'maximum': 9007199254740991},
    }),
    'PreparationAssigneePage': object({
      'items': {
        'type': 'array',
        'maxItems': 50,
        'items': ref('PreparationAssignee'),
      },
      'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
    }),
    'PreparationAssignmentCreateRequest': object({
      'id': uuid,
      'operationId': uuid,
      'recipeId': uuid,
      'revisionId': uuid,
      'employeeId': uuid,
      'expectedEmployeeVersion': {
        'type': 'integer',
        'minimum': 1,
        'maximum': 9007199254740991,
      },
      'plannedDeclaredBatchCount': count,
    }),
    'PreparationAssignmentStartRequest': object({
      'operationId': uuid,
      'expectedVersion': version,
    }),
    'PreparationAssignmentWithdrawRequest': object({
      'operationId': uuid,
      'expectedVersion': version,
      'reason': text,
    }),
    'PreparationAssignmentCommandResult': object({
      'assignment': ref('PreparationAssignment'),
      'replayed': {'type': 'boolean'},
    }),
    'PreparationAssignmentStartResult': object({
      'assignment': ref('PreparationAssignment'),
      'batch': ref('PreparationBatch'),
      'replayed': {'type': 'boolean'},
    }),
  };
  final paths = <String, dynamic>{};
  void op(
    String path,
    String method,
    String name,
    String output, {
    String? input,
    bool page = false,
    bool assignees = false,
  }) {
    final create = input == 'PreparationAssignmentCreateRequest',
        start = input == 'PreparationAssignmentStartRequest',
        withdraw = input == 'PreparationAssignmentWithdrawRequest';
    final errors = <String, List<String>>{
      '400': [
        'invalid_request',
        if (page) 'invalid_cursor',
        if (input != null) 'invalid_json',
        if (create) 'invalid_count',
        if (withdraw) 'invalid_content',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      if (input != null)
        '409': [
          if (create) 'already_exists',
          'operation_conflict',
          'version_conflict',
          if (!create) 'assignment_state_conflict',
        ],
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      if (create || start)
        '422': [
          if (create) 'assignee_unavailable',
          create ? 'recipe_selection_unavailable' : 'recipe_unavailable',
          'article_unavailable',
          'not_in_assortment',
          'ingredient_unit_changed',
        ],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final codes in errors.values) {
      codes.sort();
    }
    final response = <String, dynamic>{
      create ? '201' : '200': {
        'description': input == null
            ? 'Authorized evidence.'
            : 'Original accepted evidence; current detail is fetched separately. Exact authorized replay creates no effects.',
        'content': {
          'application/json': {'schema': ref(output)},
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
    };
    (paths.putIfAbsent(path, () => <String, dynamic>{}) as Map)[method] = {
      'operationId': name,
      'summary': name,
      'security': [
        {'session': <String>[]},
      ],
      'description':
          'Current session, Company and configured Location equality precede scoped evidence/receipt disclosure. Self access derives the currently eligible linked Employee. Recipe read authority required. Unknown/duplicate query fields rejected. Assignment lifecycle stays started while Batch evolves. No Stock, Task, scheduling or event effects.',
      'parameters': [
        {'name': 'locationId', 'in': 'path', 'required': true, 'schema': uuid},
        if (path.contains('{assignmentId}'))
          {
            'name': 'assignmentId',
            'in': 'path',
            'required': true,
            'schema': uuid,
          },
        if (page)
          {
            'name': 'after',
            'in': 'query',
            'schema': {'type': 'string', 'maxLength': 2048},
            'description':
                'Keyset position binds endpoint, Company, configured Location, self/manager, Employee and filters.',
          },
        if (page && !assignees)
          {
            'name': 'status',
            'in': 'query',
            'schema': {
              'type': 'string',
              'enum': ['assigned', 'started', 'withdrawn'],
            },
          },
      ],
      if (input != null)
        'requestBody': {
          'required': true,
          'description':
              'Strict decoded duplicate-name JSON, 16384 byte streamed limit; no actor, scope, Batch IDs, timestamps or start overrides.',
          'content': {
            'application/json': {'schema': ref(input)},
          },
        },
      'responses': response,
    };
  }

  for (final self in [false, true]) {
    final root =
            '/api/v1/platform/production/${self ? 'self' : 'manage'}/locations/{locationId}/preparation-assignments',
        prefix = self ? 'Self' : 'Managed';
    op(
      root,
      'get',
      'list${prefix}PreparationAssignments',
      'PreparationAssignmentPage',
      page: true,
    );
    if (!self) {
      op(
        root,
        'post',
        'createPreparationAssignment',
        'PreparationAssignmentCommandResult',
        input: 'PreparationAssignmentCreateRequest',
      );
      op(
        '$root/assignees',
        'get',
        'listPreparationAssignees',
        'PreparationAssigneePage',
        page: true,
        assignees: true,
      );
    }
    op(
      '$root/{assignmentId}',
      'get',
      'read${prefix}PreparationAssignment',
      'PreparationAssignmentDetail',
    );
    op(
      '$root/{assignmentId}/recipe',
      'get',
      'read${prefix}AssignmentRecipe',
      'PreparationRecipeContext',
    );
    op(
      '$root/{assignmentId}/history',
      'get',
      'read${prefix}AssignmentHistory',
      'PreparationAssignmentHistory',
    );
    op(
      '$root/{assignmentId}/${self ? 'start' : 'withdraw'}',
      'post',
      self ? 'startPreparationAssignment' : 'withdrawPreparationAssignment',
      self
          ? 'PreparationAssignmentStartResult'
          : 'PreparationAssignmentCommandResult',
      input: self
          ? 'PreparationAssignmentStartRequest'
          : 'PreparationAssignmentWithdrawRequest',
    );
  }
  String entries(Map<String, dynamic> j, int indent) =>
      const JsonEncoder.withIndent('  ')
          .convert(j)
          .split('\n')
          .skip(1)
          .toList()
          .reversed
          .skip(1)
          .toList()
          .reversed
          .map((l) => '${' ' * indent}$l')
          .join('\n');
  final baselineJson = jsonDecode(original) as Map;
  final baselinePaths = baselineJson['paths'] as Map;
  final alreadyIncluded = paths.keys.any(baselinePaths.containsKey);
  if (alreadyIncluded) {
    for (final pair in [
      (paths, baselinePaths),
      (schemas, baselineJson['components']['schemas'] as Map),
    ]) {
      for (final entry in pair.$1.entries) {
        if (jsonEncode(pair.$2[entry.key]) != jsonEncode(entry.value)) {
          throw StateError(
            'Existing assignment contract differs: ${entry.key}',
          );
        }
      }
    }
  }
  if (!alreadyIncluded) {
    File('platform.openapi.json').writeAsStringSync(
      original
          .replaceFirst(
            '\n  },\n  "components": {',
            ',\n${entries(paths, 2)}\n  },\n  "components": {',
          )
          .replaceFirst(
            '\n    }\n  }\n}\n',
            ',\n${entries(schemas, 4)}\n    }\n  }\n}\n',
          ),
    );
  }
  final yaml = File('openapi.yaml');
  var index = yaml.readAsStringSync();
  for (final path in paths.keys) {
    if (!index.contains('  $path:')) {
      index = index.replaceFirst(
        'paths:\n',
        'paths:\n  $path:\n    \$ref: \'./platform.openapi.json#/paths/${path.replaceAll('~', '~0').replaceAll('/', '~1')}\'\n',
      );
    }
  }
  for (final name in schemas.keys) {
    if (!index.contains('    $name:')) {
      index = index.replaceFirst(
        '  schemas:\n',
        '  schemas:\n    $name:\n      \$ref: \'./platform.openapi.json#/components/schemas/$name\'\n',
      );
    }
  }
  yaml.writeAsStringSync(index);
}
