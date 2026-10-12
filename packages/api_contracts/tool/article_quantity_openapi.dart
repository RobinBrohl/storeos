import 'dart:convert';
import 'dart:io';

void addArticleQuantityOpenApi(Map<String, dynamic> doc) {
  final schemas = doc['components']['schemas'] as Map,
      paths = doc['paths'] as Map;
  Map<String, dynamic> ref(String name) => {
    r'$ref': name == 'ApiError'
        ? './openapi.yaml#/components/schemas/ApiError'
        : '#/components/schemas/$name',
  };
  Map<String, dynamic> obj(Map<String, dynamic> fields) => {
    'type': 'object',
    'additionalProperties': false,
    'required': fields.keys.toList(),
    'properties': fields,
  };
  Map<String, dynamic> nullable(Map<String, dynamic> schema) => {
    'anyOf': [
      schema,
      {'type': 'null'},
    ],
  };
  final id = {'type': 'string', 'format': 'uuid'},
      version = {'type': 'integer', 'minimum': 1, 'maximum': 9007199254740990},
      reason = {'type': 'string', 'minLength': 1, 'maxLength': 500},
      label = {'type': 'string', 'minLength': 1, 'maxLength': 32},
      instant = {'type': 'string', 'format': 'date-time'};
  final measurement = {
        'type': 'string',
        'enum': ['g', 'kg', 'mL', 'L', 'piece'],
      },
      unit = {
        'type': 'string',
        'pattern':
            r'^(g|kg|mL|L|piece|pack:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
      },
      decimal = {'type': 'string', 'pattern': r'^[0-9]{1,12}(\.[0-9]{1,6})?$'},
      stock = {'type': 'string', 'pattern': r'^[0-9]{1,12}(\.[0-9]{1,3})?$'},
      delta = {'type': 'string', 'pattern': r'^-?[0-9]{1,12}(\.[0-9]{1,3})?$'},
      ratio = {'type': 'string', 'pattern': r'^[1-9][0-9]{0,39}$'};
  schemas['ArticleQuantityPackage'] = obj({
    'id': id,
    'label': label,
    'content': {
      ...decimal,
      'description':
          'Positive exact content directly in the Article anchor base unit. No nested packages.',
    },
  });
  final packages = {
    'type': 'array',
    'maxItems': 16,
    'items': ref('ArticleQuantityPackage'),
  };
  schemas['ArticleQuantityProfile'] = obj({
    'id': id,
    'articleId': id,
    'baseUnit': measurement,
    'version': version,
    'status': {
      'type': 'string',
      'enum': ['active', 'suspended'],
    },
    'packages': packages,
    'reason': reason,
    'recordedBy': id,
    'recordedAt': instant,
  });
  schemas['ArticleQuantityConfigure'] = obj({
    'operationId': id,
    'profileId': id,
    'baseUnit': measurement,
    'packages': packages,
    'reason': reason,
  });
  schemas['ArticleQuantityReplace'] = obj({
    'operationId': id,
    'expectedVersion': version,
    'packages': packages,
    'reason': reason,
  });
  schemas['ArticleQuantitySuspend'] = obj({
    'operationId': id,
    'expectedVersion': version,
    'reason': reason,
  });
  schemas['StockQuantityBind'] = obj({
    'operationId': id,
    'profileId': id,
    'profileVersion': version,
    'stockVersion': version,
    'unit': unit,
    'reason': reason,
  });
  schemas['StockQuantityBinding'] = obj({
    'id': id,
    'levelId': id,
    'profileId': id,
    'profileVersion': version,
    'stockVersion': version,
    'unit': unit,
    'label': label,
    'numerator': ratio,
    'denominator': ratio,
    'reason': reason,
    'recordedBy': id,
    'recordedAt': instant,
  });
  schemas['StockQuantityPreviewInput'] = obj({
    'profileVersion': version,
    'stockVersion': version,
    'inputUnit': unit,
    'inputQuantity': decimal,
  });
  schemas['StockQuantityPreview'] = obj({
    'levelId': id,
    'bindingId': id,
    'profileId': id,
    'profileVersion': version,
    'stockVersion': version,
    'baseUnit': measurement,
    'stockUnit': label,
    'inputUnit': unit,
    'inputLabel': label,
    'inputQuantity': decimal,
    'numerator': ratio,
    'denominator': ratio,
    'currentQuantity': stock,
    'targetQuantity': stock,
    'delta': delta,
  });
  schemas['StockQuantityCorrect'] = obj({
    'operationId': id,
    'review': ref('StockQuantityPreview'),
    'reason': reason,
  });
  schemas['StockQuantityEvidence'] = obj({
    'operationId': id,
    'review': ref('StockQuantityPreview'),
    'reason': reason,
    'recordedBy': id,
    'recordedAt': instant,
    'movementId': nullable(id),
    'balanceVersion': {...version, 'maximum': 9007199254740991},
  });
  schemas['ArticleQuantityContext'] = obj({
    'profile': nullable(ref('ArticleQuantityProfile')),
  });
  schemas['StockQuantityContext'] = obj({
    'profile': nullable(ref('ArticleQuantityProfile')),
    'binding': nullable(ref('StockQuantityBinding')),
  });
  Map<String, dynamic> page(String name) => obj({
    'items': {'type': 'array', 'maxItems': 50, 'items': ref(name)},
    'nextCursor': nullable({'type': 'string'}),
  });
  schemas['ArticleQuantityHistory'] = page('ArticleQuantityProfile');
  schemas['StockQuantityHistory'] = page('StockQuantityEvidence');
  Map<String, dynamic> operation(
    String name,
    String output,
    String description, {
    String? input,
    List<Map<String, dynamic>> query = const [],
  }) => {
    'operationId': name,
    'description': description,
    'security': [
      {'session': <String>[]},
    ],
    if (query.isNotEmpty) 'parameters': query,
    if (input != null)
      'requestBody': {
        'required': true,
        'content': {
          'application/json': {'schema': ref(input)},
        },
      },
    'responses': {
      '200': {
        'description':
            'Original committed result, or read-only current/preview evidence.',
        'content': {
          'application/json': {'schema': ref(output)},
        },
      },
      for (final status in [
        '400',
        '401',
        '403',
        '404',
        '409',
        '413',
        '415',
        '422',
        '503',
      ])
        status: {
          'description':
              'Explicit rejection or unconfirmed availability failure.',
          'content': {
            'application/json': {'schema': ref('ApiError')},
          },
        },
    },
  };
  Map<String, dynamic> parameter(String name) => {
    'name': name,
    'in': 'path',
    'required': true,
    'schema': id,
  };
  const article = '/api/v1/platform/articles/{articleId}/quantity',
      level =
          '/api/v1/platform/locations/{locationId}/stock/{levelId}/quantity';
  paths[article] = {
    'parameters': [parameter('articleId')],
    'get': operation(
      'articleQuantityGet',
      'ArticleQuantityContext',
      'Admin inventory.articles.manage; explicit profile or null. Retained revision reads are scoped.',
      query: [
        {'name': 'version', 'in': 'query', 'schema': version},
      ],
    ),
  };
  paths['$article/history'] = {
    'parameters': [parameter('articleId')],
    'get': operation(
      'articleQuantityHistory',
      'ArticleQuantityHistory',
      'Newest first, at most 50 immutable profile revisions.',
      query: [
        {'name': 'before', 'in': 'query', 'schema': version},
      ],
    ),
  };
  for (final pair in [
    ('configure', 'ArticleQuantityConfigure'),
    ('replace', 'ArticleQuantityReplace'),
    ('suspend', 'ArticleQuantitySuspend'),
  ]) {
    paths['$article/${pair.$1}'] = {
      'parameters': [parameter('articleId')],
      'post': operation(
        'articleQuantity${pair.$1}',
        'ArticleQuantityProfile',
        'Admin inventory.articles.manage; immutable anchor/full revision or terminal suspension. Atomic audit and actor/payload-bound exact replay.',
        input: pair.$2,
      ),
    };
  }
  paths[level] = {
    'parameters': [parameter('locationId'), parameter('levelId')],
    'get': operation(
      'stockQuantityContext',
      'StockQuantityContext',
      'Admin stock.levels.manage with actor/route configured execution Location equality. Explicit prospective binding or null.',
    ),
  };
  paths['$level/evidence'] = {
    'parameters': [parameter('locationId'), parameter('levelId')],
    'get': operation(
      'stockQuantityEvidence',
      'StockQuantityHistory',
      'Scoped original conversion evidence, including zero delta receipts. UUID keyset order.',
      query: [
        {'name': 'after', 'in': 'query', 'schema': id},
      ],
    ),
  };
  for (final pair in [
    ('bind', 'StockQuantityBind', 'StockQuantityBinding'),
    ('preview', 'StockQuantityPreviewInput', 'StockQuantityPreview'),
    ('correct', 'StockQuantityCorrect', 'StockQuantityEvidence'),
  ]) {
    paths['$level/${pair.$1}'] = {
      'parameters': [parameter('locationId'), parameter('levelId')],
      'post': operation(
        'stockQuantity${pair.$1}',
        pair.$3,
        'Admin stock.levels.manage; configured execution Location equality before resource/replay lookup. Preview is read-only. Correction recomputes the complete reviewed absolute target under exact Stock/profile versions. No rounding, inferred labels, cross dimensions or unbound conversions. Committed exact replay precedes fresh lifecycle checks.',
        input: pair.$2,
      ),
    };
  }
}

void main() {
  final file = File('platform.openapi.json'),
      original = file.readAsStringSync(),
      doc = jsonDecode(original) as Map<String, dynamic>;
  final oldPaths = (doc['paths'] as Map).keys.toSet(),
      oldSchemas = (doc['components']['schemas'] as Map).keys.toSet();
  addArticleQuantityOpenApi(doc);
  final paths = Map.fromEntries(
        (doc['paths'] as Map).entries.where((e) => !oldPaths.contains(e.key)),
      ),
      schemas = Map.fromEntries(
        (doc['components']['schemas'] as Map).entries.where(
          (e) => !oldSchemas.contains(e.key),
        ),
      );
  if (paths.isEmpty) return;
  String entries(Map value, int spaces) {
    final encoded = const JsonEncoder.withIndent('  ').convert(value);
    return encoded
        .substring(2, encoded.length - 2)
        .split('\n')
        .map((line) => '${' ' * (spaces - 2)}$line')
        .join('\n');
  }

  var result = original.replaceFirst(
    '\n  },\n  "components":',
    ',\n${entries(paths, 4)}\n  },\n  "components":',
  );
  final end = result.lastIndexOf('\n    }\n  }\n}');
  if (end < 0) throw StateError('Unexpected OpenAPI formatting.');
  result = result.replaceRange(end, end, ',\n${entries(schemas, 6)}');
  file.writeAsStringSync(result);
  final yaml = File('openapi.yaml');
  var index = yaml.readAsStringSync();
  for (final path in paths.keys) {
    if (index.contains('\n  $path:\n')) continue;
    index = index.replaceFirst(
      'components:\n',
      '  $path:\n    \$ref: "./platform.openapi.json#/paths/${path.toString().replaceAll('~', '~0').replaceAll('/', '~1')}"\ncomponents:\n',
    );
  }
  yaml.writeAsStringSync(index);
}
