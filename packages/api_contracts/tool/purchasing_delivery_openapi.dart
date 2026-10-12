import 'dart:convert';
import 'dart:io';

void addPurchasingDeliveryOpenApi(Map<String, dynamic> doc) {
  final schemas = doc['components']['schemas'] as Map,
      paths = doc['paths'] as Map;
  Map<String, dynamic> ref(String name) => {
    r'$ref': '#/components/schemas/$name',
  };
  Map<String, dynamic> obj(Map<String, dynamic> properties) => {
    'type': 'object',
    'additionalProperties': false,
    'required': properties.keys.toList(),
    'properties': properties,
  };
  Map<String, dynamic> nullable(Map value) => {
    'anyOf': [
      value,
      {'type': 'null'},
    ],
  };
  final uuid = {'type': 'string', 'format': 'uuid'},
      version = {'type': 'integer', 'minimum': 1, 'maximum': 9007199254740991},
      ledger = {'type': 'integer', 'minimum': 0, 'maximum': 9007199254740991},
      instant = {'type': 'string', 'format': 'date-time'};
  final reason = {'type': 'string', 'minLength': 1, 'maxLength': 500},
      reference = {'type': 'string', 'minLength': 1, 'maxLength': 64};
  final quantity = {
    'type': 'string',
    'pattern': r'^[0-9]{1,12}(\.[0-9]{1,3})?$',
    'description':
        'Positive exact thousandths, through 999999999999.999; JSON numbers and unit overrides forbidden.',
  };
  final outputQuantity = {
    'type': 'string',
    'pattern': r'^[0-9]{1,12}\.[0-9]{3}$',
  };
  final lines = {
    'type': 'array',
    'minItems': 1,
    'maxItems': 50,
    'items': obj({'orderLineId': uuid, 'quantity': quantity}),
  };
  final expected = {
    'operationId': uuid,
    'expectedOrderVersion': version,
    'expectedLedgerVersion': ledger,
  };
  schemas['PurchasingDeliveryDeclare'] = obj({
    ...expected,
    'deliveryId': uuid,
    'localReference': reference,
    'reason': nullable(reason),
    'lines': lines,
  });
  schemas['PurchasingDeliveryCorrect'] = obj({
    ...expected,
    'expectedRevision': version,
    'reason': reason,
    'lines': lines,
  });
  schemas['PurchasingDeliveryVoid'] = obj({
    ...expected,
    'expectedRevision': version,
    'reason': reason,
  });
  schemas['PurchasingDeliveryRevision'] = obj({
    'deliveryId': uuid,
    'orderId': uuid,
    'locationId': uuid,
    'revision': version,
    'ledgerVersion': version,
    'kind': {
      'type': 'string',
      'enum': ['delivery_declare', 'delivery_correct', 'delivery_void'],
    },
    'localReference': reference,
    'reason': nullable(reason),
    'actorId': uuid,
    'recordedAt': instant,
    'operationId': uuid,
    'lines': {...lines, 'minItems': 0},
  });
  schemas['PurchasingDeliverySummary'] = obj({
    'orderId': uuid,
    'ledgerVersion': ledger,
    'declarationCount': ledger,
    'lines': {
      'type': 'array',
      'maxItems': 50,
      'items': obj({
        'orderLineId': uuid,
        'orderedQuantity': outputQuantity,
        'effectiveDelivered': outputQuantity,
        'recordedRemainder': outputQuantity,
        'overdelivery': outputQuantity,
      }),
    },
  });
  schemas['PurchasingDeliveryTerminal'] = obj({
    'operationId': uuid,
    'orderVersion': version,
    'actorId': uuid,
    'terminalAt': instant,
    'status': {
      'type': 'string',
      'enum': ['closed', 'cancelled'],
    },
    'summary': ref('PurchasingDeliverySummary'),
  });
  schemas['PurchasingDeliverySummaryDetail'] = obj({
    'summary': ref('PurchasingDeliverySummary'),
    'terminalSnapshot': nullable(ref('PurchasingDeliveryTerminal')),
    'trackingAtClosure': {
      'type': 'string',
      'enum': ['available', 'unavailable', 'not_terminal', 'not_issued'],
    },
  });
  schemas['PurchasingDeliveryResult'] = obj({
    'delivery': ref('PurchasingDeliveryRevision'),
    'summary': ref('PurchasingDeliverySummary'),
    'replayed': {'type': 'boolean'},
  });
  schemas['PurchasingDeliveryRegisterEntry'] = obj({
    'id': uuid,
    'reference': reference,
    'supplierId': uuid,
    'supplierName': {'type': 'string', 'maxLength': 200},
    'status': {
      'type': 'string',
      'enum': ['issued', 'closed', 'cancelled'],
    },
    'orderVersion': version,
    'ledgerVersion': ledger,
    'declarationCount': ledger,
    'hasRecordedRemainder': {'type': 'boolean'},
    'hasOverdelivery': {'type': 'boolean'},
    'hasTerminalSnapshot': {'type': 'boolean'},
  });
  for (final pair in {
    'Page': 'Revision',
    'RegisterPage': 'RegisterEntry',
  }.entries) {
    schemas['PurchasingDelivery${pair.key}'] = obj({
      'items': {
        'type': 'array',
        'maxItems': 50,
        'items': ref('PurchasingDelivery${pair.value}'),
      },
      'nextCursor': nullable({'type': 'string', 'maxLength': 2048}),
    });
  }
  void operation(
    String path,
    String name,
    String response, {
    String? input,
    bool cursor = false,
    bool missing = true,
    List<String> filters = const [],
    List<String> conflicts = const [],
    List<String> selections = const [],
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
      if (selections.isNotEmpty) '422': selections,
      if (input != null) '413': ['body_too_large'],
      if (input != null) '415': ['unsupported_media_type'],
      '500': ['internal_error'],
      '503': ['database_unavailable'],
    };
    for (final v in errors.values) {
      v.sort();
    }
    paths.putIfAbsent(path, () => <String, dynamic>{});
    (paths[path] as Map)[input == null ? 'get' : 'post'] = {
      'operationId': 'purchasingDelivery$name',
      'summary': 'Purchasing delivery $name',
      'description':
          'Current session, purchasing.orders.manage and configured Company/Location/Order/Delivery scope precede receipt lookup. Recorded delivery evidence does not mutate or establish Stock. Exact authorized replay returns original revision and summary at acceptance. Full replacement corrections and voids preserve history, including after termination. Administrative close captures a separate immutable boundary. No unlike-unit Order total. Local reference is operator chosen; no physical shipment deduplication. Unknown/duplicate decoded JSON and query members are rejected.',
      'security': [
        {'session': <String>[]},
      ],
      'parameters': [
        for (final n in ['locationId', 'orderId', 'deliveryId'])
          if (path.contains('{$n}'))
            {'name': n, 'in': 'path', 'required': true, 'schema': uuid},
        if (cursor)
          {
            'name': 'after',
            'in': 'query',
            'required': false,
            'schema': {'type': 'string', 'maxLength': 2048},
            'description':
                'Canonical Company/Location/endpoint/resource/filter bound keyset; not authority.',
          },
        for (final n in filters)
          {
            'name': n,
            'in': 'query',
            'required': false,
            'schema': n == 'supplierId'
                ? uuid
                : n == 'status'
                ? {
                    'type': 'string',
                    'enum': ['issued', 'closed', 'cancelled'],
                  }
                : {'type': 'string', 'maxLength': 200},
          },
      ],
      if (input != null)
        'requestBody': {
          'required': true,
          'description':
              'Streamed UTF-8 bound 16384 bytes; bounded canonical receipt payload/result 32768/65536 SQL bytes. Server derives actors, snapshots, units, sequences and totals. Reason is required if effective overdelivery increases.',
          'content': {
            'application/json': {'schema': ref('PurchasingDelivery$input')},
          },
        },
      'responses': {
        name == 'Declare' ? '201' : '200': {
          'description': input == null
              ? 'Authorized current evidence.'
              : 'Original accepted evidence; replay creates no effects.',
          'content': {
            'application/json': {'schema': ref('PurchasingDelivery$response')},
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

  const root = '/api/v1/platform/purchasing/locations/{locationId}',
      order = '$root/orders/{orderId}',
      deliveries = '$order/deliveries';
  operation(
    '$root/delivery-register',
    'Register',
    'RegisterPage',
    missing: false,
    cursor: true,
    filters: ['status', 'supplierId', 'q'],
  );
  operation('$order/delivery-summary', 'Summary', 'SummaryDetail');
  operation(deliveries, 'List', 'Page', cursor: true);
  operation('$deliveries/{deliveryId}', 'Detail', 'Revision');
  operation(
    '$deliveries/{deliveryId}/history',
    'History',
    'Page',
    cursor: true,
  );
  const common = [
    'version_conflict',
    'ledger_version_conflict',
    'operation_conflict',
    'version_limit',
    'quantity_limit',
  ];
  operation(
    deliveries,
    'Declare',
    'Result',
    input: 'Declare',
    conflicts: [
      ...common,
      'already_exists',
      'reference_conflict',
      'order_state_conflict',
    ],
    selections: ['invalid_order_line', 'overdelivery_reason_required'],
  );
  operation(
    '$deliveries/{deliveryId}/correct',
    'Correct',
    'Result',
    input: 'Correct',
    conflicts: [...common, 'revision_conflict', 'no_change'],
    selections: ['invalid_order_line'],
  );
  operation(
    '$deliveries/{deliveryId}/void',
    'Void',
    'Result',
    input: 'Void',
    conflicts: [...common, 'revision_conflict', 'no_change'],
  );
}

void main() {
  final file = File('platform.openapi.json'),
      original = file.readAsStringSync(),
      doc = jsonDecode(original) as Map<String, dynamic>;
  final oldPaths = (doc['paths'] as Map).keys.toSet(),
      oldSchemas = (doc['components']['schemas'] as Map).keys.toSet();
  addPurchasingDeliveryOpenApi(doc);
  String entries(Map values, int indent) => values.entries
      .map(
        (e) =>
            '${' ' * indent}${jsonEncode(e.key)}: ${const JsonEncoder.withIndent('  ').convert(e.value).split('\n').join('\n${' ' * indent}')}',
      )
      .join(',\n');
  final newPaths = Map.fromEntries(
    (doc['paths'] as Map).entries.where((e) => !oldPaths.contains(e.key)),
  );
  final newSchemas = Map.fromEntries(
    (doc['components']['schemas'] as Map).entries.where(
      (e) => !oldSchemas.contains(e.key),
    ),
  );
  if (newPaths.isEmpty) {
    throw StateError(
      'Delivery OpenAPI already generated; verify idempotent contract via tests.',
    );
  }
  var result = original.replaceFirst(
    '\n  },\n  "components":',
    ',\n${entries(newPaths, 4)}\n  },\n  "components":',
  );
  final end = result.lastIndexOf('\n    }\n  }\n}');
  if (end < 0) throw StateError('Unexpected OpenAPI formatting.');
  result = result.replaceRange(end, end, ',\n${entries(newSchemas, 6)}');
  file.writeAsStringSync(result);
  final yaml = File('openapi.yaml');
  var index = yaml.readAsStringSync();
  for (final path in newPaths.keys) {
    index = index.replaceFirst(
      'components:\n',
      '  $path:\n    \$ref: "./platform.openapi.json#/paths/${path.toString().replaceAll('~', '~0').replaceAll('/', '~1')}"\ncomponents:\n',
    );
  }
  yaml.writeAsStringSync(index);
}
