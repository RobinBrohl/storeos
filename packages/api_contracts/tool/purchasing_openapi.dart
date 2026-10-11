import 'dart:convert';
import 'dart:io';

/// Endpoint-local contract inventory. Existing operations are preserved.
void addPurchasingOpenApi(Map<String, dynamic> doc) {
  final paths = doc['paths'] as Map,
      schemas = (doc['components'] as Map)['schemas'] as Map;
  final uuid = {'type': 'string', 'format': 'uuid'},
      version = {'type': 'integer', 'minimum': 1, 'maximum': 9007199254740991};
  Map<String, dynamic> text(int max) => {
    'type': 'string',
    'minLength': 1,
    'maxLength': max,
    'description':
        'Trimmed literal single-line Unicode text; no controls or unpaired surrogates.',
  };
  Map<String, dynamic> nullable(Map value) => {
    'anyOf': [
      value,
      {'type': 'null'},
    ],
  };
  Map<String, dynamic> object(Map<String, dynamic> p) => {
    'type': 'object',
    'additionalProperties': false,
    'required': p.keys.toList(),
    'properties': p,
  };
  Map<String, dynamic> ref(String s) => {r'$ref': '#/components/schemas/$s'};
  final quantity = {
    'type': 'string',
    'pattern': r'^[0-9]{1,12}(\.[0-9]{1,3})?$',
    'description':
        'Positive exact thousandths, 0.001–999999999999.999. JSON numbers, rounding and unit conversion are forbidden. Output has exactly three fractional digits.',
  };
  final supplierSnapshot = object({
    'id': uuid,
    'version': version,
    'name': text(200),
    'orderingReference': nullable(text(64)),
  });
  final line = object({
    'id': uuid,
    'position': {'type': 'integer', 'minimum': 1, 'maximum': 50},
    'articleId': uuid,
    'articleVersion': version,
    'sku': text(64),
    'name': text(120),
    'unit': text(32),
    'quantity': quantity,
  });
  final instant = {'type': 'string', 'format': 'date-time'};
  final attribution = {
    'createdBy': uuid,
    'createdAt': instant,
    'changedBy': uuid,
    'changedAt': instant,
  };
  schemas['PurchasingSupplier'] = object({
    'id': uuid,
    'companyId': uuid,
    'name': text(200),
    'orderingReference': nullable(text(64)),
    'status': {
      'type': 'string',
      'enum': ['active', 'retired'],
    },
    'version': version,
    ...attribution,
    'retiredBy': nullable(uuid),
    'retiredAt': nullable(instant),
  });
  schemas['PurchasingOrder'] = object({
    'id': uuid,
    'companyId': uuid,
    'locationId': uuid,
    'reference': text(64),
    'supplier': supplierSnapshot,
    'lines': {'type': 'array', 'maxItems': 50, 'items': line},
    'status': {
      'type': 'string',
      'enum': ['draft', 'issued', 'closed', 'cancelled'],
    },
    'version': version,
    ...attribution,
    'issuedBy': nullable(uuid),
    'issuedAt': nullable(instant),
    'terminalBy': nullable(uuid),
    'terminalAt': nullable(instant),
    'reason': nullable(text(500)),
  });
  for (final entity in ['Supplier', 'Order']) {
    schemas['Purchasing${entity}Result'] = object({
      entity.toLowerCase(): ref('Purchasing$entity'),
      'replayed': {'type': 'boolean'},
    });
    schemas['Purchasing${entity}Page'] = object({
      'items': {
        'type': 'array',
        'maxItems': 50,
        'items': ref('Purchasing$entity'),
      },
      'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
    });
  }
  schemas['PurchasingArticle'] = object({
    'id': uuid,
    'version': version,
    'sku': text(64),
    'name': text(120),
    'unit': text(32),
  });
  schemas['PurchasingArticlePage'] = object({
    'items': {
      'type': 'array',
      'maxItems': 50,
      'items': ref('PurchasingArticle'),
    },
    'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
  });
  schemas['PurchasingHistoryEntry'] = object({
    'operationId': uuid,
    'kind': {
      'type': 'string',
      'enum': [
        'supplier_create',
        'supplier_edit',
        'supplier_retire',
        'order_create',
        'order_save',
        'order_issue',
        'order_cancel',
        'order_close',
      ],
    },
    'actorId': uuid,
    'appliedVersion': version,
    'responseStatus': {
      'type': 'integer',
      'enum': [200, 201],
    },
    'acceptedAt': instant,
    'result': {
      'oneOf': [ref('PurchasingSupplierResult'), ref('PurchasingOrderResult')],
    },
  });
  schemas['PurchasingHistoryPage'] = object({
    'items': {
      'type': 'array',
      'maxItems': 50,
      'items': ref('PurchasingHistoryEntry'),
    },
    'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
  });
  final op = {'operationId': uuid},
      expected = {...op, 'expectedVersion': version},
      supplierFields = {
        'name': text(200),
        'orderingReference': nullable(text(64)),
      },
      selection = {
        'reference': text(64),
        'supplierId': uuid,
        'expectedSupplierVersion': version,
      };
  schemas['PurchasingSupplierCreate'] = object({
    'id': uuid,
    ...op,
    ...supplierFields,
  });
  schemas['PurchasingSupplierEdit'] = object({...expected, ...supplierFields});
  schemas['PurchasingVersionCommand'] = object(expected);
  schemas['PurchasingOrderCreate'] = object({'id': uuid, ...op, ...selection});
  schemas['PurchasingOrderSave'] = object({
    ...expected,
    ...selection,
    'reselectSupplier': {'type': 'boolean'},
    'lines': {
      'type': 'array',
      'maxItems': 50,
      'items': object({
        'id': uuid,
        'articleId': uuid,
        'expectedArticleVersion': version,
        'quantity': quantity,
        'reselectArticle': {'type': 'boolean'},
      }),
    },
  });
  schemas['PurchasingTerminalCommand'] = object({
    ...expected,
    'reason': text(500),
  });
  void operation(
    String path,
    String method,
    String id,
    String response, {
    String? input,
    List<String> conflicts = const [],
    List<String> selections = const [],
    List<String> filters = const [],
    bool cursor = false,
    bool missing = false,
  }) {
    final errors = <String, List<String>>{
      '400': [
        'invalid_request',
        if (input != null) 'invalid_json',
        if (cursor) 'invalid_cursor',
      ],
      '401': ['unauthorized'],
      '403': ['forbidden', 'origin_forbidden'],
      if (missing) '404': ['not_found'],
      if (conflicts.isNotEmpty) '409': conflicts,
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      if (selections.isNotEmpty) '422': selections,
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final e in errors.values) {
      e.sort();
    }
    final parameters = [
      for (final name in ['locationId', 'supplierId', 'orderId'])
        if (path.contains('{$name}'))
          {'name': name, 'in': 'path', 'required': true, 'schema': uuid},
      if (cursor)
        {
          'name': 'after',
          'in': 'query',
          'required': false,
          'schema': {'type': 'string', 'maxLength': 2048},
          'description':
              'Keyset binds endpoint, Company, configured Location/resource and exact filters. It grants no authority.',
        },
      for (final name in filters)
        {
          'name': name,
          'in': 'query',
          'required': false,
          'schema': name == 'supplierId'
              ? uuid
              : {'type': 'string', 'maxLength': name == 'q' ? 200 : 64},
        },
    ];
    paths.putIfAbsent(path, () => <String, dynamic>{});
    (paths[path] as Map)[method] = {
      'operationId': id,
      'summary': id,
      'description':
          'Admin capability and current Company/resource scope precede receipt disclosure. Orders additionally require route = configured = current Account Location. Issue is internal approval; closure is administrative. Neither transmits or receives goods. Duplicate/unknown query fields and decoded JSON member names are rejected. No Stock, Tasks or events.',
      'security': [
        {'session': <String>[]},
      ],
      'parameters': parameters,
      if (input != null)
        'requestBody': {
          'required': true,
          'description':
              'Strict fields; transport byte maximum ${input == 'PurchasingOrderSave' ? 262144 : 16384}. Server captures snapshots/actors/timestamps. Draft document 98304 decoded UTF-8 bytes. Receipt payload/result 262144/524288 bytes.',
          'content': {
            'application/json': {'schema': ref(input)},
          },
        },
      'responses': {
        id.endsWith('Create') ? '201' : '200': {
          'description':
              'Original accepted evidence for writes; current detail is a separate GET. Exact replay appends no effects.',
          'content': {
            'application/json': {'schema': ref(response)},
          },
        },
        for (final e in errors.entries)
          e.key: {
            'description': e.value.join(', '),
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

  const root = '/api/v1/platform/purchasing';
  final s = '$root/suppliers', o = '$root/locations/{locationId}/orders';
  operation(
    s,
    'get',
    'purchasingSupplierList',
    'PurchasingSupplierPage',
    cursor: true,
    filters: ['status', 'q'],
  );
  operation(
    s,
    'post',
    'purchasingSupplierCreate',
    'PurchasingSupplierResult',
    input: 'PurchasingSupplierCreate',
    conflicts: ['already_exists', 'operation_conflict'],
  );
  operation(
    '$s/{supplierId}',
    'get',
    'purchasingSupplierDetail',
    'PurchasingSupplier',
    missing: true,
  );
  operation(
    '$s/{supplierId}',
    'put',
    'purchasingSupplierEdit',
    'PurchasingSupplierResult',
    input: 'PurchasingSupplierEdit',
    missing: true,
    conflicts: [
      'version_conflict',
      'version_limit',
      'supplier_state_conflict',
      'no_change',
      'operation_conflict',
    ],
  );
  operation(
    '$s/{supplierId}/retire',
    'post',
    'purchasingSupplierRetire',
    'PurchasingSupplierResult',
    input: 'PurchasingVersionCommand',
    missing: true,
    conflicts: [
      'version_conflict',
      'version_limit',
      'supplier_state_conflict',
      'operation_conflict',
    ],
  );
  operation(
    '$s/{supplierId}/history',
    'get',
    'purchasingSupplierHistory',
    'PurchasingHistoryPage',
    cursor: true,
    missing: true,
  );
  operation(
    '$root/locations/{locationId}/article-selections',
    'get',
    'purchasingArticleSelections',
    'PurchasingArticlePage',
    cursor: true,
    missing: true,
    filters: ['q'],
  );
  operation(
    o,
    'get',
    'purchasingOrderList',
    'PurchasingOrderPage',
    cursor: true,
    missing: true,
    filters: ['status', 'supplierId', 'q'],
  );
  operation(
    o,
    'post',
    'purchasingOrderCreate',
    'PurchasingOrderResult',
    input: 'PurchasingOrderCreate',
    missing: true,
    conflicts: [
      'already_exists',
      'operation_conflict',
      'order_reference_conflict',
      'supplier_changed',
    ],
    selections: ['supplier_selection_unavailable'],
  );
  operation(
    '$o/{orderId}',
    'get',
    'purchasingOrderDetail',
    'PurchasingOrder',
    missing: true,
  );
  operation(
    '$o/{orderId}',
    'put',
    'purchasingOrderSave',
    'PurchasingOrderResult',
    input: 'PurchasingOrderSave',
    missing: true,
    conflicts: [
      'version_conflict',
      'version_limit',
      'operation_conflict',
      'order_state_conflict',
      'order_reference_conflict',
      'no_change',
      'supplier_changed',
      'article_reference_changed',
    ],
    selections: [
      'supplier_selection_unavailable',
      'article_selection_unavailable',
      'not_in_assortment',
    ],
  );
  operation(
    '$o/{orderId}/issue',
    'post',
    'purchasingOrderIssue',
    'PurchasingOrderResult',
    input: 'PurchasingVersionCommand',
    missing: true,
    conflicts: [
      'version_conflict',
      'version_limit',
      'operation_conflict',
      'order_state_conflict',
      'supplier_changed',
      'article_reference_changed',
      'article_unit_changed',
    ],
    selections: [
      'supplier_selection_unavailable',
      'article_selection_unavailable',
      'not_in_assortment',
      'order_not_issuable',
    ],
  );
  for (final action in ['cancel', 'close']) {
    operation(
      '$o/{orderId}/$action',
      'post',
      'purchasingOrder$action',
      'PurchasingOrderResult',
      input: 'PurchasingTerminalCommand',
      missing: true,
      conflicts: [
        'version_conflict',
        'version_limit',
        'operation_conflict',
        'order_state_conflict',
      ],
    );
  }
  operation(
    '$o/{orderId}/history',
    'get',
    'purchasingOrderHistory',
    'PurchasingHistoryPage',
    missing: true,
    cursor: true,
  );
}

void main() {
  final f = File('platform.openapi.json'),
      doc = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
  addPurchasingOpenApi(doc);
  // Preserve the reviewed formatting of every pre-existing operation/schema.
  final baseline = Process.runSync('git', [
    'show',
    'HEAD:packages/api_contracts/platform.openapi.json',
  ], stdoutEncoding: null);
  if (baseline.exitCode != 0) {
    throw StateError('Cannot read reviewed OpenAPI baseline.');
  }
  var original = utf8.decode(baseline.stdout as List<int>);
  String entries(Map values, int indent) => values.entries
      .map(
        (e) =>
            '${' ' * indent}${jsonEncode(e.key)}: ${const JsonEncoder.withIndent('  ').convert(e.value).split('\n').join('\n${' ' * indent}')}',
      )
      .join(',\n');
  final newPaths = Map.fromEntries(
    pathsOf(
      doc,
    ).entries.where((e) => e.key.toString().contains('/purchasing/')),
  );
  final newSchemas = Map.fromEntries(
    ((doc['components'] as Map)['schemas'] as Map).entries.where(
      (e) => e.key.toString().startsWith('Purchasing'),
    ),
  );
  original = original.replaceFirst(
    '\n  },\n  "components":',
    ',\n${entries(newPaths, 4)}\n  },\n  "components":',
  );
  final end = original.lastIndexOf('\n    }\n  }\n}');
  if (end < 0 || !original.contains('purchasingSupplierCreate')) {
    throw StateError('Unexpected OpenAPI layout.');
  }
  original = original.replaceRange(end, end, ',\n${entries(newSchemas, 6)}');
  f.writeAsStringSync(original);
  final yaml = File('openapi.yaml');
  var index = yaml.readAsStringSync();
  for (final e in (doc['paths'] as Map).entries.where(
    (e) => e.key.toString().contains('/purchasing/'),
  )) {
    if (index.contains('  ${e.key}:')) continue;
    final block =
        '  ${e.key}:\n    \$ref: "./platform.openapi.json#/paths/${e.key.toString().replaceAll('~', '~0').replaceAll('/', '~1')}"\n';
    index = index.replaceFirst(
      'components:\n',
      '$block'
          'components:\n',
    );
  }
  yaml.writeAsStringSync(index);
}

Map pathsOf(Map doc) => doc['paths'] as Map;
