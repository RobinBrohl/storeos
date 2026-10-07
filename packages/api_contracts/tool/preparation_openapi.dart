import 'dart:convert';
import 'dart:io';

/// Regenerate only the bounded P4.10 operations and schemas.
void main() {
  final file = File('platform.openapi.json');
  final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final schemas = (doc['components'] as Map)['schemas'] as Map;
  final uuid = {'type': 'string', 'format': 'uuid'};
  final instant = {'type': 'string', 'format': 'date-time'};
  final text = {
    'type': 'string',
    'minLength': 1,
    'maxLength': 500,
    'description':
        'Plain text, trimmed; no control characters. Render literally. Retained authoritative evidence; excluded from audit/log metadata.',
  };
  Map<String, dynamic> nullable(Map<String, dynamic> value) => {
    'anyOf': [
      value,
      {'type': 'null'},
    ],
  };
  Map<String, dynamic> count(int min) => {
    'type': 'integer',
    'minimum': min,
    'maximum': 9999,
    'description':
        'Whole declared Recipe batches; no yield, output-unit or Stock semantics. Fractional/floating/scientific/string JSON representations are rejected by the server.',
  };
  Map<String, dynamic> object(Map<String, dynamic> p) => {
    'type': 'object',
    'additionalProperties': false,
    'required': p.keys.toList(),
    'properties': p,
  };
  Map<String, dynamic> ref(String n) => {r'$ref': '#/components/schemas/$n'};
  schemas['PreparationOpenRequest'] = object({
    'batchId': uuid,
    'operationId': uuid,
    'recipeId': uuid,
    'revisionId': uuid,
    'plannedDeclaredBatchCount': nullable(count(1)),
  });
  schemas['PreparationCompleteRequest'] = object({
    'operationId': uuid,
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 2},
    'actualDeclaredBatchCount': count(1),
    'note': nullable(text),
  });
  schemas['PreparationCancelRequest'] = object({
    'operationId': uuid,
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 2},
    'reason': text,
  });
  schemas['PreparationCorrectRequest'] = object({
    'operationId': uuid,
    'expectedVersion': {'type': 'integer', 'minimum': 1, 'maximum': 2},
    'expectedLatestCorrectionNumber': {
      'type': 'integer',
      'minimum': 0,
      'maximum': 2147483646,
    },
    'replacementDeclaredBatchCount': count(0),
    'reason': text,
  });
  schemas['PreparationCorrection'] = object({
    'companyId': uuid,
    'locationId': uuid,
    'batchId': uuid,
    'correctionNumber': {'type': 'integer', 'minimum': 1},
    'previousEffectiveCount': count(0),
    'replacementDeclaredBatchCount': count(0),
    'correctedBy': uuid,
    'correctedAt': instant,
    'reason': text,
    'operationId': uuid,
  });
  final properties = <String, dynamic>{
    'batchId': uuid,
    'companyId': uuid,
    'locationId': uuid,
    'recipeId': uuid,
    'revisionId': uuid,
    'employeeId': uuid,
    'openedBy': uuid,
    'openedAt': instant,
    'plannedDeclaredBatchCount': nullable(count(1)),
    'status': {
      'type': 'string',
      'enum': ['open', 'completed', 'cancelled'],
    },
    'version': {
      'type': 'integer',
      'enum': [1, 2],
    },
    'openOperationId': uuid,
    'actualDeclaredBatchCount': nullable(count(1)),
    'completedBy': nullable(uuid),
    'completedAt': nullable(instant),
    'completionNote': nullable(text),
    'cancelledBy': nullable(uuid),
    'cancelledAt': nullable(instant),
    'cancellationReason': nullable(text),
    'terminalOperationId': nullable(uuid),
    'terminalKind': nullable({
      'type': 'string',
      'enum': ['complete', 'employee_cancel', 'manager_cancel'],
    }),
  };
  schemas['PreparationBatch'] = object(properties);
  schemas['PreparationBatchDetail'] = object({
    ...properties,
    'corrections': {'type': 'array', 'items': ref('PreparationCorrection')},
    'latestCorrectionNumber': {'type': 'integer', 'minimum': 0},
    'effectiveDeclaredBatchCount': nullable(count(0)),
  });
  schemas['PreparationBatchPage'] = object({
    'items': {
      'type': 'array',
      'maxItems': 50,
      'items': ref('PreparationBatchDetail'),
    },
    'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
  });
  schemas['PreparationCommandResult'] = object({
    'batch': ref('PreparationBatch'),
    'replayed': {'type': 'boolean'},
  });
  schemas['PreparationCorrectionResult'] = object({
    'correction': ref('PreparationCorrection'),
    'replayed': {'type': 'boolean'},
  });
  schemas['PreparationRecipeContext'] = object({
    'recipeId': uuid,
    'revisionId': uuid,
    'revisionNumber': {'type': 'integer', 'minimum': 1},
    'publishedAt': instant,
    'content': ref('RecipeContent'),
    'currentProduced': nullable(ref('RecipeArticleContext')),
    'currentIngredients': {
      'type': 'array',
      'maxItems': 50,
      'items': ref('RecipeArticleContext'),
    },
    'warnings': {
      'type': 'array',
      'maxItems': 104,
      'items': {'type': 'string'},
      'description':
          'Current context only. Frozen approved content remains authoritative. Retirement is not emergency withdrawal.',
    },
  });
  final paths = doc['paths'] as Map;
  final yaml = File('openapi.yaml');
  var index = yaml.readAsStringSync();
  final refs = StringBuffer();
  void operation(
    String path,
    String method,
    String id,
    String response, {
    String? input,
    bool list = false,
    bool self = false,
    bool opening = false,
    bool correction = false,
  }) {
    final errors = <String, List<String>>{
      '400': [
        'invalid_request',
        if (list) 'invalid_cursor',
        if (input != null) 'invalid_json',
        if (opening || input == 'PreparationCompleteRequest' || correction)
          'invalid_count',
        if (input != null && !opening) 'invalid_content',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      '404': ['not_found'],
      if (input != null)
        '409': [
          if (!opening) 'invalid_lifecycle',
          if (!opening) 'stale_version',
          'operation_conflict',
          if (correction) 'correction_conflict',
        ],
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      if (opening)
        '422': [
          'recipe_selection_unavailable',
          'article_unavailable',
          'not_in_assortment',
          'ingredient_unit_changed',
          'operator_unavailable',
        ],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final codes in errors.values) {
      codes.sort();
    }
    final parameters = [
      {'name': 'locationId', 'in': 'path', 'required': true, 'schema': uuid},
      if (path.contains('{batchId}'))
        {'name': 'batchId', 'in': 'path', 'required': true, 'schema': uuid},
      if (list) ...[
        {
          'name': 'after',
          'in': 'query',
          'required': false,
          'schema': {'type': 'string', 'maxLength': 2048},
          'description':
              'Keyset cursor binds Company, configured Location, self Employee identity and lifecycle filter.',
        },
        {
          'name': 'status',
          'in': 'query',
          'required': false,
          'schema': {
            'type': 'string',
            'enum': ['open', 'completed', 'cancelled'],
          },
        },
      ],
    ];
    final success = opening ? '201' : '200';
    final responses = <String, dynamic>{
      success: {
        'description': input != null
            ? 'Original committed evidence. Exact replay returns the original command result after current authorization; no duplicate effects.'
            : 'Authorized retained evidence.',
        'content': {
          'application/json': {'schema': ref(response)},
        },
      },
    };
    for (final e in errors.entries) {
      responses[e.key] = {
        'description': '${e.key}: ${e.value.join(', ')}.',
        'x-error-codes': e.value,
        'content': {
          'application/json': {
            'schema': {r'$ref': './openapi.yaml#/components/schemas/ApiError'},
          },
        },
      };
    }
    paths.putIfAbsent(path, () => <String, dynamic>{});
    (paths[path] as Map)[method] = {
      'operationId': id,
      'summary': id,
      'description':
          '${self ? 'Current eligible linked Employee, own resource' : 'Manager Location authority'}; configured Location equality precedes resource/receipt evidence. ${path.endsWith('/recipe') ? 'Batch access precedes exact persisted revision resolution; additionally requires production.recipes.read. No Recipe/revision overrides.' : ''} Unknown/duplicate query fields rejected. Evidence only; no Stock/Task effects.',
      'security': [
        {'session': <String>[]},
      ],
      'parameters': parameters,
      if (input != null)
        'requestBody': {
          'required': true,
          'description':
              'Strict duplicate-decoded-name JSON; maximum 16384 transport bytes. Server owns identity, timestamps and snapshots.',
          'content': {
            'application/json': {'schema': ref(input)},
          },
        },
      'responses': responses,
    };
  }

  for (final self in [true, false]) {
    final root =
            '/api/v1/platform/production/${self ? 'self' : 'manage'}/locations/{locationId}/batches',
        prefix = self ? 'Self' : 'Managed';
    operation(
      root,
      'get',
      'list${prefix}PreparationBatches',
      'PreparationBatchPage',
      list: true,
      self: self,
    );
    operation(
      '$root/{batchId}',
      'get',
      'read${prefix}PreparationBatch',
      'PreparationBatchDetail',
      self: self,
    );
    operation(
      '$root/{batchId}/recipe',
      'get',
      'read${prefix}PreparationRecipe',
      'PreparationRecipeContext',
      self: self,
    );
    operation(
      '$root/{batchId}/cancel',
      'post',
      'cancel${prefix}PreparationBatch',
      'PreparationCommandResult',
      input: 'PreparationCancelRequest',
      self: self,
    );
    if (self) {
      operation(
        root,
        'post',
        'openPreparationBatch',
        'PreparationCommandResult',
        input: 'PreparationOpenRequest',
        self: true,
        opening: true,
      );
      operation(
        '$root/{batchId}/complete',
        'post',
        'completePreparationBatch',
        'PreparationCommandResult',
        input: 'PreparationCompleteRequest',
        self: true,
      );
    } else {
      operation(
        '$root/{batchId}/count-corrections',
        'post',
        'correctPreparationBatchCount',
        'PreparationCorrectionResult',
        input: 'PreparationCorrectRequest',
        correction: true,
      );
    }
  }
  for (final path in paths.keys.where(
    (p) => p.toString().contains('/batches'),
  )) {
    final existing = '  $path:';
    if (!index.contains(existing)) {
      refs.writeln(
        '$existing\n    \$ref: \'./platform.openapi.json#/paths/${path.toString().replaceAll('~', '~0').replaceAll('/', '~1')}\'',
      );
    }
  }
  index = index.replaceFirst('paths:\n', 'paths:\n$refs');
  final baseline = Process.runSync('git', [
    'show',
    'HEAD:packages/api_contracts/platform.openapi.json',
  ], stdoutEncoding: null);
  if (baseline.exitCode != 0) throw StateError('Cannot read baseline OpenAPI.');
  String entries(Map<dynamic, dynamic> values, int indent) =>
      const JsonEncoder.withIndent('  ')
          .convert(values)
          .split('\n')
          .skip(1)
          .toList()
          .reversed
          .skip(1)
          .toList()
          .reversed
          .map((line) => '${' ' * indent}$line')
          .join('\n');
  final additions = {
    for (final e in paths.entries)
      if (e.key.toString().contains('/batches')) e.key: e.value,
  };
  final newSchemas = {
    for (final e in schemas.entries)
      if (e.key.toString().startsWith('Preparation')) e.key: e.value,
  };
  final original = utf8.decode(baseline.stdout as List<int>);
  file.writeAsStringSync(
    original
        .replaceFirst(
          '\n  },\n  "components": {',
          ',\n${entries(additions, 2)}\n  },\n  "components": {',
        )
        .replaceFirst(
          '\n    }\n  }\n}\n',
          ',\n${entries(newSchemas, 4)}\n    }\n  }\n}\n',
        ),
  );
  yaml.writeAsStringSync(index);
}
