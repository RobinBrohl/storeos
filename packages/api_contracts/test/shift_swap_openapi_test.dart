import 'dart:convert';
import 'dart:io';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../tool/shift_swap_openapi.dart' show generateShiftSwapOpenApi;
import 'shift_swap_fixture.dart';

bool _swapPath(String p) =>
    p.contains('shift-swaps') || p.contains('swap-colleagues');
Map<String, dynamic> _copy(Map<String, dynamic> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

void main() {
  final raw = File('platform.openapi.json').readAsStringSync();
  final doc = jsonDecode(raw) as Map<String, dynamic>;
  final schemas = doc['components']['schemas'] as Map<String, dynamic>;
  final paths = doc['paths'] as Map<String, dynamic>;
  final yaml = File('openapi.yaml').readAsStringSync();
  final router = File(
    '../../apps/server/lib/src/http/shift_swap_routes.dart',
  ).readAsStringSync();
  final operations = <String, Map<String, dynamic>>{
    for (final path in paths.entries.where((e) => _swapPath(e.key)))
      for (final verb in (path.value as Map).entries)
        '${verb.key.toString().toUpperCase()} ${path.key}':
            Map<String, dynamic>.from(verb.value as Map),
  };

  test('sixteen operations independently match actual router registration', () {
    expect(operations.length, 16);
    expect(operations.keys.toSet(), registeredSwapOperations(router));
    final allIds = [
      for (final path in paths.values.whereType<Map>())
        for (final operation in path.values.whereType<Map>())
          if (operation['operationId'] is String) operation['operationId'],
    ];
    for (final operation in operations.values) {
      expect(
        allIds.where((id) => id == operation['operationId']),
        hasLength(1),
      );
      expect(operation['security'], [
        {'session': <String>[]},
      ]);
    }
  });

  test(
    'route reader detects a real registration rename and added command kind',
    () {
      expect(
        registeredSwapOperations(
          router.replaceAll('swap-colleagues', 'swap-peers'),
        ),
        isNot(operations.keys.toSet()),
      );
      expect(
        registeredSwapOperations(
          router.replaceFirst(
            "['offer', 'confirm', 'decline', 'withdraw']",
            "['offer', 'confirm', 'decline', 'withdraw', 'unexpected']",
          ),
        ),
        hasLength(17),
      );
    },
  );

  test(
    'canonical YAML contains exactly fifteen unique resolving swap path references',
    () {
      final keys = RegExp(
        r'^  (/[^\r\n]+):\r?$',
        multiLine: true,
      ).allMatches(yaml).map((m) => m[1]!).toList();
      expect(keys.toSet(), hasLength(keys.length));
      final added = keys.where(_swapPath).toSet();
      expect(added, paths.keys.where(_swapPath).toSet());
      expect(added, hasLength(15));
      for (final path in added) {
        final pointer = path.replaceAll('~', '~0').replaceAll('/', '~1');
        expect(
          yaml,
          contains(
            '  $path:\n    \$ref: "./platform.openapi.json#/paths/$pointer"',
          ),
        );
      }
      expect(yaml, contains('    ApiError:'));
      expect(yaml, contains('    session:'));
    },
  );

  test(
    'every new reference resolves and all public object schemas are closed',
    () {
      var references = 0;
      void walk(Object? node) {
        if (node is Map) {
          if (node[r'$ref'] case final String reference) {
            references++;
            if (reference.startsWith('#/')) {
              _resolve(doc, reference);
            } else {
              expect(reference, './openapi.yaml#/components/schemas/ApiError');
            }
          }
          if (node['type'] == 'object') {
            expect(node['additionalProperties'], false);
            expect(
              (node['required'] as List).toSet(),
              (node['properties'] as Map).keys.toSet(),
            );
          }
          for (final value in node.values) {
            walk(value);
          }
        } else if (node is List) {
          for (final value in node) {
            walk(value);
          }
        }
      }

      final newSchemas = schemas.entries
          .where((e) => e.key.startsWith('ShiftSwap'))
          .toList();
      expect(newSchemas, hasLength(22));
      for (final schema in newSchemas) {
        walk(schema.value);
      }
      for (final operation in operations.values) {
        // Error allOf clauses intentionally refer to the existing ApiError.
        for (final response in (operation['responses'] as Map).values) {
          _refs(response, (r) {
            references++;
            if (r.startsWith('#/')) {
              _resolve(doc, r);
            } else {
              expect(r, './openapi.yaml#/components/schemas/ApiError');
            }
          });
        }
      }
      expect(references, greaterThan(70));
    },
  );

  test(
    'bounded pages, required nullable properties and immutable pair bounds match DTOs',
    () {
      for (final name in [
        'ShiftSwapPage',
        'ShiftSwapColleaguePage',
        'ShiftSwapCounterpartPage',
        'ShiftSwapHistoryPage',
      ]) {
        final schema = schemas[name] as Map;
        expect(schema['required'], ['items', 'nextCursor']);
        expect(
          schema['properties']['items']['maxItems'],
          name == 'ShiftSwapHistoryPage' ? 2 : 50,
        );
        expect(
          schema['properties']['nextCursor']['anyOf'][0]['maxLength'],
          2048,
        );
        expect(schema['properties']['nextCursor']['anyOf'][1], {
          'type': 'null',
        });
      }
      expect(schemas['ShiftSwapEvidence']['properties']['legs']['maxItems'], 2);
      expect(schemas['ShiftSwapLeg']['properties']['tasks']['minItems'], 1);
      expect(schemas['ShiftSwapLeg']['properties']['tasks']['maxItems'], 10);
      expect(
        schemas['ShiftSwapLeg']['properties']['taskLinks']['maxItems'],
        10,
      );
      expect(
        schemas['ShiftSwapCommandResult']['x-storeos-max-utf8-bytes'],
        65536,
      );
      expect(
        schemas['ShiftSwapDetail']['properties']['availableActions']['maxItems'],
        3,
      );
      expect(
        schemas['ShiftSwapDetail']['properties']['availableActions']['uniqueItems'],
        true,
      );
    },
  );

  const commandNames = {
    'request': 'ShiftSwapRequest',
    'offer': 'ShiftSwapOffer',
    'confirm': 'ShiftSwapConfirm',
    'decline': 'ShiftSwapDecline',
    'source_withdraw': 'ShiftSwapWithdraw',
    'recipient_withdraw': 'ShiftSwapWithdraw',
    'manager_approve': 'ShiftSwapApprove',
    'manager_reject': 'ShiftSwapReject',
  };
  for (final entry in commandNames.entries) {
    test(
      '${entry.key} schema independently matches strict DTO fields and stage boundaries',
      () {
        final schema = schemas[entry.value] as Map<String, dynamic>;
        for (final version in [0, 1, 2, 3, 4, 2147483647, 2147483648]) {
          final command = swapCommand(entry.key, version);
          final dtoAccepted = _acceptsCommand(entry.key, command);
          // Shared withdrawal schema covers the union; recipient's narrower
          // current-authority stage is deliberately server-resolved.
          final expected = entry.key == 'recipient_withdraw'
              ? _acceptsCommand('source_withdraw', command)
              : dtoAccepted;
          expect(
            schemaAccepts(doc, schema, command),
            expected,
            reason: '${entry.key}/$version',
          );
        }
        final stage = switch (entry.key) {
          'confirm' => 2,
          'manager_approve' => 3,
          'recipient_withdraw' => 2,
          _ => 1,
        };
        final valid = swapCommand(entry.key, stage);
        expect(schema['additionalProperties'], false);
        expect((schema['required'] as List).toSet(), valid.keys.toSet());
        for (final field in valid.keys) {
          final missing = {...valid}..remove(field);
          expect(_acceptsCommand(entry.key, missing), false);
          expect(schemaAccepts(doc, schema, missing), false);
        }
        for (final field in [
          'actor',
          'accountId',
          'kind',
          'replacementShiftId',
          'snapshot',
          'requestedAt',
        ]) {
          final extra = {...valid, field: 'injected'};
          expect(_acceptsCommand(entry.key, extra), false);
          expect(schemaAccepts(doc, schema, extra), false);
        }
        final versionKey = entry.key == 'request'
            ? 'expectedSourceVersion'
            : 'expectedVersion';
        for (final value in [null, true, '$stage', stage.toDouble(), -1]) {
          final invalid = {...valid, versionKey: value};
          expect(_acceptsCommand(entry.key, invalid), false);
          expect(schemaAccepts(doc, schema, invalid), false);
        }
        for (final uuid in [
          'FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF',
          '00000000-0000-0000-0000-000000000000',
          'bad',
          ' ${swapId(99)}',
        ]) {
          final changed = {...valid, 'operationId': uuid};
          expect(
            schemaAccepts(doc, schema, changed),
            _acceptsCommand(entry.key, changed),
          );
        }
      },
    );
  }

  test(
    'reason normalization is scalar based after trimming, separate from raw UTF8 bytes',
    () {
      for (final (kind, name) in [
        ('source_withdraw', 'ShiftSwapWithdraw'),
        ('manager_reject', 'ShiftSwapReject'),
      ]) {
        for (final reason in [
          'changed',
          '😀' * 500,
          '😀' * 501,
          '${' ' * 800}x\n',
          '',
          ' \t\n',
          'a\nb',
          'a\u007fb',
          'a\u0085b',
          '\ud800',
          '\udc00',
          'x\ud800y',
        ]) {
          final value = {...swapCommand(kind, 1), 'reason': reason};
          expect(
            schemaAccepts(doc, schemas[name] as Map<String, dynamic>, value),
            _acceptsCommand(kind, value),
            reason: 'reason scalar/trim boundary',
          );
        }
        expect(
          schemas[name]['properties']['reason'],
          isNot(contains('maxLength')),
        );
        expect(
          schemas[name]['properties']['reason']['x-storeos-max-unicode-scalars'],
          500,
        );
      }
      for (final entry in operations.entries.where(
        (e) => e.key.startsWith('POST '),
      )) {
        expect(entry.value['requestBody']['x-storeos-max-utf8-bytes'], 8192);
      }
    },
  );

  for (final stage in [1, 2, 3]) {
    for (final state in [
      ['requested', 'offered', 'confirmed'][stage - 1],
      'withdrawn',
      'rejected',
      if (stage < 3) 'declined',
      if (stage == 3) 'approved',
    ]) {
      test(
        'response evidence $state from $stage validates emitted DTO and rejects structural drift',
        () {
          final value = swapEvidence(state: state, stage: stage, tasks: 10);
          final leg = (value['legs'] as List).first as Map<String, dynamic>;
          final work = (leg['tasks'] as List).first as Map<String, dynamic>;
          work['knowledgeGuidance'] = {
            'articleId': swapId(700),
            'revisionId': swapId(701),
          };
          work['planogramGuidance'] = {
            'fixtureId': swapId(702),
            'assignmentId': swapId(703),
            'revisionId': swapId(704),
          };
          final dto = ShiftSwapDto.fromJson(value).toJson();
          validateSchema(doc, schemas['ShiftSwapEvidence'], dto);
          for (final key in dto.keys) {
            expect(
              schemaAccepts(
                doc,
                schemas['ShiftSwapEvidence'],
                {...dto}..remove(key),
              ),
              false,
              reason: key,
            );
          }
          expect(
            schemaAccepts(doc, schemas['ShiftSwapEvidence'], {
              ...dto,
              'sourceAccountId': swapId(22),
            }),
            false,
          );
          for (final patch in [
            {'version': 9},
            {'legs': <Object?>[]},
            {'terminalKind': 'future_kind'},
          ]) {
            expect(
              schemaAccepts(doc, schemas['ShiftSwapEvidence'], {
                ...dto,
                ...patch,
              }),
              false,
            );
          }
          final tooMany = _copy(dto);
          ((tooMany['legs'] as List).first['tasks'] as List).add(work);
          expect(
            schemaAccepts(doc, schemas['ShiftSwapEvidence'], tooMany),
            false,
          );
          for (final field in work.keys) {
            final missingTask = _copy(dto);
            ((missingTask['legs'] as List).first['tasks'] as List).first.remove(
              field,
            );
            expect(
              schemaAccepts(doc, schemas['ShiftSwapEvidence'], missingTask),
              false,
              reason: 'Task $field',
            );
          }
          if (state == 'approved') {
            final missing = _copy(dto);
            ((missing['legs'] as List).first['taskLinks'] as List).removeLast();
            expect(
              schemaAccepts(doc, schemas['ShiftSwapEvidence'], missing),
              false,
            );
          }
          final operationKey = state == 'requested'
              ? 'requestOperationId'
              : state == 'offered'
              ? 'offerOperationId'
              : state == 'confirmed'
              ? 'confirmationOperationId'
              : 'terminalOperationId';
          final result = ShiftSwapCommandResult.fromJson({
            'operationId': dto[operationKey],
            'kind': switch (state) {
              'requested' => 'request',
              'offered' => 'offer',
              'confirmed' => 'confirm',
              _ => dto['terminalKind'],
            },
            'acceptedVersion': dto['version'],
            'statusCode': state == 'requested' ? 201 : 200,
            'request': dto,
            'replayed': false,
          }).toJson();
          validateSchema(doc, schemas['ShiftSwapCommandResult'], result);
          validateSchema(doc, schemas['ShiftSwapCommandResult'], {
            ...result,
            'replayed': true,
          });
          expect(
            schemaAccepts(doc, schemas['ShiftSwapCommandResult'], {
              ...result,
              'statusCode': 202,
            }),
            false,
          );
          expect(
            schemaAccepts(doc, schemas['ShiftSwapCommandResult'], {
              ...result,
              'acceptedVersion': 9,
            }),
            false,
          );
          expect(
            schemaAccepts(doc, schemas['ShiftSwapCommandResult'], {
              ...result,
              'acceptedVersion': (dto['version'] as int) == 1 ? 2 : 1,
            }),
            false,
          );
        },
      );
    }
  }

  test(
    'detail, discovery, counterpart and page shapes match real DTO serialization',
    () {
      final request = swapEvidence();
      final detail = ShiftSwapDetailDto.fromJson({
        'request': request,
        'participantRole': 'source',
        'actionable': true,
        'nonActionableReason': null,
        'availableActions': ['source_withdraw'],
      }).toJson();
      final page = ShiftSwapPageDto.fromJson({
        'items': [request],
        'nextCursor': null,
      }).toJson();
      final colleagues = ShiftSwapColleaguePageDto.fromJson({
        'items': [
          {'employeeId': swapId(44), 'displayName': 'B'},
        ],
        'nextCursor': null,
      }).toJson();
      final b =
          (swapEvidence(state: 'offered', stage: 2)['legs'] as List)[1]
              as Map<String, dynamic>;
      final candidate = ShiftSwapCounterpartPageDto.fromJson({
        'items': [
          {
            'shiftId': b['sourceShiftId'],
            'version': b['sourceVersion'],
            'startsAt': b['startsAt'],
            'endsAt': b['endsAt'],
          },
        ],
        'nextCursor': null,
      }).toJson();
      for (final pair in [
        (detail, 'ShiftSwapDetail'),
        (page, 'ShiftSwapPage'),
        (colleagues, 'ShiftSwapColleaguePage'),
        (candidate, 'ShiftSwapCounterpartPage'),
        (b, 'ShiftSwapCounterpartDetail'),
      ]) {
        validateSchema(doc, schemas[pair.$2], pair.$1);
        final fields = schemas[pair.$2]['required'] as List;
        expect(fields.toSet(), pair.$1.keys.toSet());
        for (final field in fields) {
          expect(
            schemaAccepts(doc, schemas[pair.$2], {...pair.$1}..remove(field)),
            false,
          );
        }
      }
      expect(
        schemaAccepts(doc, schemas['ShiftSwapDetail'], {
          ...detail,
          'availableActions': ['offer'],
        }),
        false,
      );
      expect(
        schemaAccepts(doc, schemas['ShiftSwapDetail'], {
          ...detail,
          'nonActionableReason': 'changed',
        }),
        false,
      );
      expect(
        schemaAccepts(doc, schemas['ShiftSwapPage'], {
          ...page,
          'nextCursor': '',
        }),
        false,
      );
      expect(
        schemaAccepts(doc, schemas['ShiftSwapPage'], {
          ...page,
          'nextCursor': 'x' * 2049,
        }),
        false,
      );
      for (final count in [1024, 1025]) {
        final unicodeCursor = {...page, 'nextCursor': '😀' * count};
        expect(
          schemaAccepts(doc, schemas['ShiftSwapPage'], unicodeCursor),
          count == 1024,
        );
        if (count == 1024) {
          ShiftSwapPageDto.fromJson(unicodeCursor);
        } else {
          expect(
            () => ShiftSwapPageDto.fromJson(unicodeCursor),
            throwsFormatException,
          );
        }
      }
      expect(
        schemaAccepts(doc, schemas['ShiftSwapCounterpartDetail'], {
          ...b,
          'leg': 'a',
        }),
        false,
      );
    },
  );

  test(
    'cross-field identity constraints are explicit and the strict DTO rejects forged references',
    () {
      final value = swapEvidence(state: 'approved', stage: 3);
      final invalid = _copy(value);
      (invalid['legs'] as List).first['incomingEmployeeId'] = swapId(999);
      expect(() => ShiftSwapDto.fromJson(invalid), throwsFormatException);
      expect(
        (schemas['ShiftSwapEvidence']['x-storeos-invariants'] as List).join(
          ' ',
        ),
        contains('leg a is source-to-recipient'),
      );
      expect(
        (schemas['ShiftSwapLeg']['x-storeos-invariants'] as List).join(' '),
        contains('Each link exactly matches'),
      );
      final receipt = {
        'operationId': swapId(999),
        'kind': 'manager_approve',
        'acceptedVersion': 4,
        'statusCode': 200,
        'request': value,
        'replayed': true,
      };
      expect(
        () => ShiftSwapCommandResult.fromJson(receipt),
        throwsFormatException,
      );
      expect(
        (schemas['ShiftSwapCommandResult']['x-storeos-invariants'] as List)
            .join(' '),
        contains('operationId equals'),
      );
    },
  );

  test(
    'public schemas contain no internal Account, link or authority version fields',
    () {
      const private = {
        'actor',
        'accountId',
        'accountVersion',
        'sourceAccountId',
        'recipientAccountId',
        'sourceLinkId',
        'recipientLinkId',
        'sourceAccountVersion',
        'recipientAccountVersion',
      };
      void inspect(Object? node) {
        if (node is Map) {
          if (node['properties'] case final Map properties) {
            expect(properties.keys.toSet().intersection(private), isEmpty);
          }
          for (final value in node.values) {
            inspect(value);
          }
        } else if (node is List) {
          for (final value in node) {
            inspect(value);
          }
        }
      }

      for (final entry in schemas.entries.where(
        (e) => e.key.startsWith('ShiftSwap'),
      )) {
        inspect(entry.value);
      }
      final withdraw =
          operations['POST /api/v1/platform/me/shift-swaps/{requestId}/withdraw']!;
      expect(
        withdraw['requestBody']['content']['application/json']['schema'][r'$ref'],
        endsWith('/ShiftSwapWithdraw'),
      );
      expect((schemas['ShiftSwapWithdraw']['properties'] as Map).keys.toSet(), {
        'operationId',
        'expectedVersion',
        'reason',
      });
      expect(
        operations.keys.any(
          (s) =>
              s.contains('source-withdraw') || s.contains('recipient-withdraw'),
        ),
        false,
      );
    },
  );

  test(
    'operation-specific error sets follow inspected Application call paths and HTTP controls',
    () {
      // Independently audited from colleagues/_candidateRequest/_fresh/_command
      // and HTTP parser/error tests, not imported from the generator's tables.
      const freshCodes = {
        'employee_unavailable',
        'guidance_unavailable',
        'planogram_guidance_unavailable',
        'shift_in_progress',
        'shift_not_swappable',
        'shift_not_transferable',
      };
      for (final entry in operations.entries) {
        final command = entry.key.startsWith('POST ');
        final path = entry.key.substring(entry.key.indexOf(' ') + 1);
        final action = path.split('/').last;
        final cursorRoute =
            action == 'swap-colleagues' ||
            action == 'shift-swaps' ||
            action == 'history' ||
            action == 'counterparts';
        final responses = entry.value['responses'] as Map;
        expect((responses['400']['x-error-codes'] as List).toSet(), {
          'invalid_request',
          if (command) 'invalid_json',
          if (!command && cursorRoute) 'invalid_cursor',
        });
        expect(responses['401']['x-error-codes'], ['unauthorized']);
        expect((responses['403']['x-error-codes'] as List).toSet(), {
          'forbidden',
          'origin_forbidden',
        });
        expect(responses['404']['x-error-codes'], ['not_found']);
        expect(responses['500']['x-error-codes'], ['internal_error']);
        expect(responses['503']['x-error-codes'], ['database_unavailable']);
        final fresh = command
            ? {'shift-swaps', 'offer', 'confirm', 'approve'}.contains(action)
            : action == 'swap-colleagues' || path.contains('/counterparts');
        expect(responses.containsKey('422'), fresh, reason: entry.key);
        if (fresh) {
          expect((responses['422']['x-error-codes'] as List).toSet(), {
            ...freshCodes,
            if (action == 'approve') 'invalid_selection',
          });
        }
        Set<String> conflicts = {};
        if (command) {
          conflicts = {
            'operation_conflict',
            if (action != 'shift-swaps') 'swap_conflict',
          };
          if ({'shift-swaps', 'offer', 'confirm', 'approve'}.contains(action)) {
            conflicts.add('shift_conflict');
          }
          if ({'offer', 'confirm', 'approve'}.contains(action)) {
            conflicts.add('shift_overlap');
          }
          if ({'shift-swaps', 'offer'}.contains(action)) {
            conflicts.add('swap_already_pending');
          }
        } else if (action == 'swap-colleagues') {
          conflicts = {'resource_limit'};
        } else if (action == 'counterparts') {
          conflicts = {'swap_conflict', 'shift_conflict'};
        } else if (path.contains('/counterparts/')) {
          conflicts = {
            'swap_conflict',
            'shift_conflict',
            'shift_overlap',
            'swap_already_pending',
          };
        }
        expect(
          responses.containsKey('409'),
          conflicts.isNotEmpty,
          reason: entry.key,
        );
        if (conflicts.isNotEmpty) {
          expect(
            (responses['409']['x-error-codes'] as List).toSet(),
            conflicts,
          );
        }
        expect(responses.containsKey('413'), command);
        expect(responses.containsKey('415'), command);
        if (command) {
          expect(responses['413']['x-error-codes'], ['body_too_large']);
          expect(responses['415']['x-error-codes'], ['unsupported_media_type']);
        }
        expect(
          responses.containsKey(
            command && action == 'shift-swaps' ? '201' : '200',
          ),
          true,
        );
        expect(
          responses.containsKey(
            command && action == 'shift-swaps' ? '200' : '201',
          ),
          false,
        );
        expect(responses.keys.toSet(), {
          command && action == 'shift-swaps' ? '201' : '200',
          '400',
          '401',
          '403',
          '404',
          if (conflicts.isNotEmpty) '409',
          if (command) ...['413', '415'],
          if (fresh) '422',
          '500',
          '503',
        });
      }
      final app = File(
        '../../apps/server/lib/src/application/shift_swap_application.dart',
      ).readAsStringSync();
      final task = File(
        '../../apps/server/lib/src/tasks/task_instance_service.dart',
      ).readAsStringSync();
      final errorControls = File(
        '../../apps/server/test/shift_swap_http_error_test.dart',
      ).readAsStringSync();
      expect(app, contains("{'request', 'offer'}.contains(commandKind)"));
      expect(app, contains("e.constraintName == 'swap_approval_future'"));
      expect(app, contains("if (!{409, 422}.contains(e.status)) rethrow"));
      expect(task, contains("'shift_not_transferable'"));
      expect(errorControls, contains("'private_integrity_fixture'"));
      expect(
        errorControls,
        contains("corrupt ? 'internal_error' : 'shift_not_swappable'"),
      );
      for (final entry in operations.values) {
        expect(entry['description'], contains('no pre-EOF 413 guarantee'));
        expect(
          entry['description'],
          contains('without a completed HTTP error response'),
        );
      }
    },
  );

  test(
    'all unrelated and P4.11 JSON/YAML definitions remain unchanged from Git baseline',
    () {
      final beforeJson = _git('platform.openapi.json');
      final beforeYaml = _git('openapi.yaml');
      final before = jsonDecode(beforeJson) as Map<String, dynamic>;
      final filtered = _copy(doc), original = _copy(before);
      for (final value in [filtered, original]) {
        (value['paths'] as Map).removeWhere((k, _) => _swapPath(k as String));
        (value['components']['schemas'] as Map).removeWhere(
          (k, _) => (k as String).startsWith('ShiftSwap'),
        );
      }
      expect(filtered, original);
      for (final pair in [
        (4, before['paths'] as Map),
        (6, before['components']['schemas'] as Map),
      ]) {
        final oldMembers = rawOpenApiMembers(beforeJson, pair.$1);
        final newMembers = rawOpenApiMembers(raw, pair.$1);
        expect(oldMembers.keys.toSet(), pair.$2.keys.toSet());
        for (final entry in oldMembers.entries) {
          if (_swapPath(entry.key) || entry.key.startsWith('ShiftSwap')) {
            continue;
          }
          expect(
            newMembers[entry.key],
            entry.value,
            reason: 'Raw member ${entry.key}',
          );
        }
      }
      String withoutSwapRefs(String value) => value.replaceAll(
        RegExp(
          r'^  /[^\r\n]*(?:shift-swaps|swap-colleagues)[^\r\n]*:\r?\n    \$ref:[^\r\n]*\r?\n',
          multiLine: true,
        ),
        '',
      );
      expect(withoutSwapRefs(yaml), withoutSwapRefs(beforeYaml));
    },
  );

  test(
    'generator is deterministic and two repeated runs create zero artifact diff',
    () {
      final first = generateShiftSwapOpenApi(raw, yaml);
      final second = generateShiftSwapOpenApi(first.$1, first.$2);
      expect(first, (raw, yaml));
      expect(second, first);
    },
  );

  test(
    'generator fails closed for duplicate keys, conflicting definitions and missing anchors',
    () {
      expect(() => generateShiftSwapOpenApi('[]', yaml), throwsFormatException);
      expect(
        () => generateShiftSwapOpenApi(
          '{"openapi":"3.1.0","components":"invalid"}',
          yaml,
        ),
        throwsFormatException,
      );
      final duplicate = raw.replaceFirst(
        '"paths": {',
        '"paths": {"duplicate":{},"duplicate":{},',
      );
      expect(
        () => generateShiftSwapOpenApi(duplicate, yaml),
        throwsFormatException,
      );
      final conflicting = _copy(doc);
      conflicting['components']['schemas']['ShiftSwapRequest']['additionalProperties'] =
          true;
      expect(
        () => generateShiftSwapOpenApi(jsonEncode(conflicting), yaml),
        throwsFormatException,
      );
      final missing = _copy(doc)..remove('paths');
      expect(
        () => generateShiftSwapOpenApi(jsonEncode(missing), yaml),
        throwsFormatException,
      );
      expect(
        () => generateShiftSwapOpenApi(
          raw,
          yaml.replaceFirst('paths:', 'renamed:'),
        ),
        throwsFormatException,
      );
      const pointer =
          '~1api~1v1~1platform~1employee-home~1shifts~1{shiftId}~1swap-colleagues';
      expect(
        () => generateShiftSwapOpenApi(
          raw,
          yaml.replaceFirst(
            './platform.openapi.json#/paths/$pointer',
            './wrong.json#/paths/$pointer',
          ),
        ),
        throwsFormatException,
      );
      final partial = _copy(doc);
      (partial['components']['schemas'] as Map).remove('ShiftSwapRequest');
      expect(
        () => generateShiftSwapOpenApi(jsonEncode(partial), yaml),
        throwsFormatException,
      );
      final quotedDuplicate = yaml.replaceFirst(
        'paths:\n',
        'paths:\n  "/api/v1/platform/me/shift-swaps":\n    \$ref: "unrelated.json"\n',
      );
      expect(
        () => generateShiftSwapOpenApi(raw, quotedDuplicate),
        throwsFormatException,
      );
    },
  );

  group('B2B-01 real CLI validation and no-write regressions', () {
    final originalJson = _git('platform.openapi.json');
    final originalYaml = _git('openapi.yaml');
    const path = '/api/v1/platform/me/shift-swaps';
    const historical = '/api/v1/platform/me/shift-transfers';
    const wrongRef =
        './platform.openapi.json#/paths/~1api~1v1~1platform~1organization';
    const correctRef =
        './platform.openapi.json#/paths/~1api~1v1~1platform~1me~1shift-swaps';
    String insert(String entry) => originalYaml.replaceFirst(
      'components:',
      '$entry'
          'components:',
    );
    String conflict(String declaration) =>
        insert('$declaration\n    \$ref: "$wrongRef"\n');
    final negatives = <String, (String, String)>{
      'original reviewer trailing comment': (
        conflict('  $path: # existing conflicting owned path'),
        path,
      ),
      'duplicate historical path with inline comment': (
        insert(
          '  $historical: # duplicate historical key\n    \$ref: "$wrongRef"\n',
        ),
        historical,
      ),
      'conflicting path with spaces and tabs around colon': (
        conflict('  $path \t: \t # conflicting definition'),
        path,
      ),
      'conflicting path with CRLF': (
        conflict('  $path: # CRLF conflict').replaceAll('\n', '\r\n'),
        path,
      ),
      'double-quoted conflicting path with comment': (
        conflict('  "$path": # quoted conflict'),
        path,
      ),
      'single-quoted conflicting path with comment': (
        conflict("  '$path': # quoted conflict"),
        path,
      ),
      'escaped quoted duplicate historical path': (
        insert(
          '  "/api/v1/platform/me/shift\\u002dtransfers": # decoded duplicate\n    \$ref: "$wrongRef"\n',
        ),
        r'shift\u002dtransfers',
      ),
      'two owned keys one with an inline comment': (
        insert(
          '  $path:\n    \$ref: "$correctRef"\n  $path: # duplicate\n    \$ref: "$wrongRef"\n',
        ),
        path,
      ),
      'partial correct managed reference': (
        insert(
          '  $path: # valid but incomplete set\n    \$ref: "$correctRef"\n',
        ),
        path,
      ),
      'malformed managed pointer fragment': (
        yaml.replaceFirst(correctRef, './platform.openapi.json#paths/wrong'),
        path,
      ),
      'managed reference to a different file': (
        yaml.replaceFirst(correctRef, './wrong.json#/paths/wrong'),
        path,
      ),
      'managed reference is not a string': (
        yaml.replaceFirst('"$correctRef"', '42'),
        path,
      ),
      'managed reference missing': (
        yaml.replaceFirst(
          '    \$ref: "$correctRef"',
          '    description: missing',
        ),
        path,
      ),
      'contradictory managed reference and operation': (
        yaml.replaceFirst(
          '    \$ref: "$correctRef"',
          '    \$ref: "$correctRef"\n    get: {}',
        ),
        path,
      ),
      'duplicate managed reference property': (
        yaml.replaceFirst(
          '    \$ref: "$correctRef"',
          '    \$ref: "$correctRef"\n    \$ref: "$wrongRef"',
        ),
        r'$ref',
      ),
      'duplicate components schemas mapping': (
        originalYaml.replaceFirst(
          'components:',
          'components:\n  schemas:\n    Broken: {type: string}',
        ),
        'schemas',
      ),
      'duplicate root paths mapping': (
        originalYaml.replaceFirst('paths:', 'paths: {}\npaths:'),
        'paths',
      ),
      'nested duplicate operation property': (
        insert(
          '  /unrelated:\n    get:\n      summary: first\n      summary: second\n',
        ),
        'summary',
      ),
      'unsupported merge key': (
        insert('  <<: {}\n'),
        'Unsupported canonical YAML key',
      ),
      'unsupported aliased path item': (
        insert('  /alias-a: &item {get: {}}\n  /alias-b: *item\n'),
        'alias',
      ),
      'unsupported intervening root mapping': (
        originalYaml.replaceFirst('components:', 'x-extra: {}\ncomponents:'),
        'layout',
      ),
      'multiple YAML documents': (
        '$originalYaml\n---\npaths: {}\n',
        'one document',
      ),
    };
    for (final entry in negatives.entries) {
      test(
        '${entry.key}: nonzero diagnostic and neither file written',
        () async {
          await _expectRejectedCli(
            originalJson,
            entry.value.$1,
            entry.value.$2,
          );
        },
      );
    }
    final conflictingPath = _copy(doc);
    conflictingPath['paths'][path]['post']['operationId'] = 'wrong';
    final conflictingSchema = _copy(doc);
    conflictingSchema['components']['schemas']['ShiftSwapRequest']['additionalProperties'] =
        true;
    final negativeJson = <String, (String, String)>{
      'conflicting generated JSON path': (jsonEncode(conflictingPath), path),
      'conflicting generated JSON schema': (
        jsonEncode(conflictingSchema),
        'ShiftSwapRequest',
      ),
      'duplicate JSON path key': (
        raw.replaceFirst('"paths": {', '"paths": {"$path":{},'),
        path,
      ),
    };
    for (final entry in negativeJson.entries) {
      test(
        '${entry.key}: nonzero diagnostic and neither file written',
        () async {
          await _expectRejectedCli(entry.value.$1, yaml, entry.value.$2);
        },
      );
    }

    test('canonical artifacts twice retain exact reviewed bytes', () async {
      await _expectValidCli(raw, yaml, expected: (raw, yaml));
    });
    test(
      'historical inputs reproduce the reviewed artifacts exactly',
      () async {
        await _expectValidCli(
          originalJson,
          originalYaml,
          expected: (raw, yaml),
        );
      },
    );
    test(
      'quoted managed keys and comments regenerate without rewriting',
      () async {
        final quoted = yaml.replaceAllMapped(
          RegExp(
            r'^  (/[^\r\n]*(?:shift-swaps|swap-colleagues)[^\r\n]*):$',
            multiLine: true,
          ),
          (m) => '  "${m[1]}": # retained valid definition',
        );
        await _expectValidCli(raw, quoted, expected: (raw, quoted));
      },
    );
    test('whitespace comments CRLF and four-space path indentation', () async {
      final indented = originalYaml
          .replaceFirst('paths:', 'paths: \t # root path comment')
          .replaceFirst('components:', 'components: # root component comment');
      final start = indented.indexOf('\n', indented.indexOf('paths:'));
      final end = indented.indexOf('components:');
      final adjusted =
          (indented.substring(0, start) +
                  indented
                      .substring(start, end)
                      .replaceAllMapped(
                        RegExp(r'^  ', multiLine: true),
                        (_) => '    ',
                      ) +
                  indented.substring(end))
              .replaceAll('\n', '\r\n');
      await _expectValidCli(originalJson, adjusted);
    });
    test(
      'hashes nested keys comments and similar distinct paths are not declarations',
      () async {
        const extra =
            '''  # /api/v1/platform/me/shift-swaps: only a comment
  /api/v1/platform/me/shift-swaps-archive:
    \$ref: "$wrongRef"
  /unrelated:
    get:
      description: "literal # is part of a quoted string"
      x-example:
        '/api/v1/platform/me/shift-swaps': "nested key # not a declaration"
''';
        await _expectValidCli(originalJson, insert(extra));
      },
    );
  });
}

Future<void> _expectRejectedCli(
  String json,
  String yaml,
  String diagnostic,
) async {
  final directory = Directory.systemTemp.createTempSync(
    'storeos-b2b01-reject-',
  );
  try {
    final files = [
      File('${directory.path}/platform.openapi.json')..writeAsStringSync(json),
      File('${directory.path}/openapi.yaml')..writeAsStringSync(yaml),
    ];
    final before = files.map((f) => f.readAsBytesSync()).toList();
    final result = await _generatorCli(directory);
    expect(result.exitCode, isNot(0));
    expect('${result.stdout}${result.stderr}', contains('FormatException'));
    expect('${result.stdout}${result.stderr}', contains(diagnostic));
    for (var i = 0; i < files.length; i++) {
      expect(
        files[i].readAsBytesSync(),
        orderedEquals(before[i]),
        reason: '${files[i].path} must not be partially written',
      );
    }
  } finally {
    directory.deleteSync(recursive: true);
  }
}

Future<void> _expectValidCli(
  String json,
  String yaml, {
  (String, String)? expected,
}) async {
  final directory = Directory.systemTemp.createTempSync('storeos-b2b01-valid-');
  try {
    final jsonFile = File('${directory.path}/platform.openapi.json')
      ..writeAsStringSync(json);
    final yamlFile = File('${directory.path}/openapi.yaml')
      ..writeAsStringSync(yaml);
    final first = await _generatorCli(directory);
    expect(first.exitCode, 0, reason: '${first.stdout}${first.stderr}');
    final firstBytes = (jsonFile.readAsBytesSync(), yamlFile.readAsBytesSync());
    if (expected != null) {
      expect(firstBytes.$1, orderedEquals(utf8.encode(expected.$1)));
      expect(firstBytes.$2, orderedEquals(utf8.encode(expected.$2)));
    }
    final document = jsonDecode(jsonFile.readAsStringSync()) as Map;
    final paths = document['paths'] as Map;
    const root = '/api/v1/platform/me/shift-swaps';
    const managed = '/api/v1/platform/locations/{locationId}/shift-swaps';
    const expectedPaths = {
      '/api/v1/platform/employee-home/shifts/{shiftId}/swap-colleagues',
      root,
      '$root/{requestId}',
      '$root/{requestId}/history',
      '$root/{requestId}/counterparts',
      '$root/{requestId}/counterparts/{shiftId}',
      '$root/{requestId}/offer',
      '$root/{requestId}/confirm',
      '$root/{requestId}/decline',
      '$root/{requestId}/withdraw',
      managed,
      '$managed/{requestId}',
      '$managed/{requestId}/history',
      '$managed/{requestId}/approve',
      '$managed/{requestId}/reject',
    };
    expect(
      expectedPaths.fold<int>(0, (n, p) => n + (paths[p] as Map).length),
      16,
    );
    expect(
      (document['components']['schemas'] as Map).keys.where(
        (k) => (k as String).startsWith('ShiftSwap'),
      ),
      hasLength(22),
    );
    final canonical = loadYaml(yamlFile.readAsStringSync()) as YamlMap;
    for (final path in expectedPaths) {
      final ref = (canonical['paths'] as YamlMap)[path][r'$ref'] as String;
      expect(ref.split('#').first, './platform.openapi.json');
      expect(
        _resolve(
          Map<String, dynamic>.from(document),
          '#${ref.split('#').last}',
        ),
        paths[path],
      );
    }
    // YAML's duplicate-detecting JSON-subset parser is independent of the
    // generator's raw JSON scanner and checks every mapping depth.
    expect(() => loadYaml(jsonFile.readAsStringSync()), returnsNormally);
    final second = await _generatorCli(directory);
    expect(second.exitCode, 0, reason: '${second.stdout}${second.stderr}');
    expect(jsonFile.readAsBytesSync(), orderedEquals(firstBytes.$1));
    expect(yamlFile.readAsBytesSync(), orderedEquals(firstBytes.$2));
  } finally {
    directory.deleteSync(recursive: true);
  }
}

Future<ProcessResult> _generatorCli(Directory directory) =>
    Process.run(Platform.resolvedExecutable, [
      '--packages=${File('.dart_tool/package_config.json').absolute.path}',
      File('tool/shift_swap_openapi.dart').absolute.path,
    ], workingDirectory: directory.path);

bool _acceptsCommand(String kind, Map<String, dynamic> value) {
  try {
    ShiftSwapCommandInput.fromJson(kind, value);
    return true;
  } on SwapInputException {
    return false;
  }
}

Object? _resolve(Map<String, dynamic> doc, String pointer) {
  Object? value = doc;
  for (final key in pointer.substring(2).split('/')) {
    if (value is! Map ||
        !value.containsKey(key.replaceAll('~1', '/').replaceAll('~0', '~'))) {
      throw FormatException('Unresolved reference $pointer.');
    }
    value = value[key.replaceAll('~1', '/').replaceAll('~0', '~')];
  }
  return value;
}

void _refs(Object? node, void Function(String) visit) {
  if (node is Map) {
    if (node[r'$ref'] case final String r) {
      visit(r);
    }
    for (final value in node.values) {
      _refs(value, visit);
    }
  } else if (node is List) {
    for (final value in node) {
      _refs(value, visit);
    }
  }
}

/// Independent structural JSON Schema evaluator for the keywords emitted here.
/// Relational constraints not expressible in standard JSON Schema are separately
/// documented/tested against real DTOs, rather than pretending the schema checks them.
bool schemaAccepts(Map<String, dynamic> doc, Object? schema, Object? value) {
  try {
    validateSchema(doc, schema, value);
    return true;
  } on FormatException {
    return false;
  }
}

void validateSchema(
  Map<String, dynamic> doc,
  Object? schema,
  Object? value, [
  String path = r'$',
]) {
  final s = schema as Map;
  Never invalid(String why) => throw FormatException('$path: $why');
  if (s[r'$ref'] case final String reference) {
    validateSchema(
      doc,
      reference.startsWith('#/')
          ? _resolve(doc, reference)
          : {
              'type': 'object',
              'required': ['code', 'message'],
              'properties': {
                'code': {'type': 'string'},
                'message': {'type': 'string'},
              },
            },
      value,
      path,
    );
  }
  if (s['type'] case final String type) {
    final valid = switch (type) {
      'object' => value is Map,
      'array' => value is List,
      'null' => value == null,
      'string' => value is String,
      'boolean' => value is bool,
      'integer' => value is int,
      'number' => value is num,
      _ => throw StateError('Unsupported schema type $type'),
    };
    if (!valid) invalid('type $type');
  }
  if (s.containsKey('const') && s['const'] != value) invalid('const');
  if (s['enum'] case final List allowed) {
    if (!allowed.contains(value)) invalid('enum');
  }
  if (s['allOf'] case final List rules) {
    for (final rule in rules) {
      validateSchema(doc, rule, value, path);
    }
  }
  if (s['anyOf'] case final List rules) {
    if (!rules.any((rule) => schemaAccepts(doc, rule, value))) invalid('anyOf');
  }
  if (s['not'] case final Map rule) {
    if (schemaAccepts(doc, rule, value)) invalid('not');
  }
  if (s['if'] case final Map condition) {
    final branch = schemaAccepts(doc, condition, value) ? s['then'] : s['else'];
    if (branch != null) validateSchema(doc, branch, value, path);
  }
  if (value is Map) {
    for (final key in (s['required'] as List? ?? [])) {
      if (!value.containsKey(key)) invalid('missing $key');
    }
    final properties = s['properties'] as Map? ?? {};
    for (final entry in value.entries) {
      if (properties.containsKey(entry.key)) {
        validateSchema(
          doc,
          properties[entry.key],
          entry.value,
          '$path.${entry.key}',
        );
      } else if (s['additionalProperties'] == false) {
        invalid('unknown ${entry.key}');
      }
    }
  }
  if (value is List) {
    if (s['minItems'] case final int min) {
      if (value.length < min) invalid('minItems');
    }
    if (s['maxItems'] case final int max) {
      if (value.length > max) invalid('maxItems');
    }
    if (s['uniqueItems'] == true &&
        value.map(jsonEncode).toSet().length != value.length) {
      invalid('uniqueItems');
    }
    final prefix = s['prefixItems'] as List? ?? [];
    for (var i = 0; i < value.length; i++) {
      // JSON Schema prefixItems and items govern separate array positions.
      if (i < prefix.length) {
        validateSchema(doc, prefix[i], value[i], '$path[$i]');
      }
      if (s.containsKey('items') && (prefix.isEmpty || i >= prefix.length)) {
        validateSchema(doc, s['items'], value[i], '$path[$i]');
      }
    }
  }
  if (value is num) {
    if (s['minimum'] case final num min) {
      if (value < min) invalid('minimum');
    }
    if (s['maximum'] case final num max) {
      if (value > max) invalid('maximum');
    }
  }
  if (value is String) {
    if (s['x-storeos-max-utf16-code-units'] case final int max) {
      if (value.length > max) invalid('UTF16 code units');
    }
    if (s['minLength'] case final int min) {
      if (value.runes.length < min) invalid('minLength');
    }
    if (s['maxLength'] case final int max) {
      if (value.runes.length > max) invalid('maxLength');
    }
    if (s['pattern'] case final String pattern) {
      if (!RegExp(pattern, unicode: true).hasMatch(value)) invalid('pattern');
    }
    if (s['x-storeos-max-unicode-scalars'] case final int max) {
      final normalized = s['x-storeos-trim'] == true ? value.trim() : value;
      if (s['x-storeos-already-trimmed'] == true && value != value.trim()) {
        invalid('untrimmed');
      }
      final units = normalized.codeUnits;
      for (var i = 0; i < units.length; i++) {
        if (units[i] >= 0xd800 && units[i] <= 0xdbff) {
          if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
            invalid('unpaired surrogate');
          }
        } else if (units[i] >= 0xdc00 && units[i] <= 0xdfff) {
          invalid('unpaired surrogate');
        }
      }
      if (normalized.runes.isEmpty ||
          normalized.runes.length > max ||
          normalized.runes.any((n) => n < 32 || n >= 127 && n <= 159)) {
        invalid('normalized reason');
      }
    }
    if (s['format'] == 'date-time') {
      try {
        shiftInstant(value);
      } on FormatException {
        invalid('date-time');
      }
    }
  }
  if (s['x-storeos-max-utf8-bytes'] case final int max) {
    if (utf8.encode(jsonEncode(value)).length > max) invalid('UTF8 bytes');
  }
}

/// Bounded reader for this real constructor's literal registrations and loops.
/// Unsupported registration syntax fails instead of silently hiding route drift.
Set<String> registeredSwapOperations(String source) {
  final loop = source.indexOf('for (final self in [true, false])');
  if (loop < 0) throw const FormatException('Unrecognized router scope loop.');
  final root = RegExp(
    r"final root\s*=\s*self\s*\?\s*'([^']+)'\s*:\s*'([^']+)';",
    dotAll: true,
  ).firstMatch(source)!;
  final branch = source.indexOf('if (self) {', root.end);
  final selfOpen = source.indexOf('{', branch),
      selfEnd = _blockEnd(source, selfOpen);
  final managerOpen = source.indexOf('{', source.indexOf('else', selfEnd));
  final managerEnd = _blockEnd(source, managerOpen);
  final result = <String>{};
  var readRegistrations = 0;
  void read(String region, String base) {
    final loopMatch = RegExp(
      r'for \(final kind in \[([^\]]+)\]\)',
      dotAll: true,
    ).firstMatch(region);
    final kinds = loopMatch == null
        ? <String>[]
        : RegExp(
            "'([^']+)'",
          ).allMatches(loopMatch[1]!).map((m) => m[1]!).toList();
    final calls = RegExp(
      r"router\.(get|post|put|patch|delete|head|options)\(\s*(root|'([^']+)')",
      dotAll: true,
    ).allMatches(region);
    for (final call in calls) {
      readRegistrations++;
      final template = call[2] == 'root'
          ? base
          : call[3]!.replaceAll(r'$root', base);
      for (final kind in template.contains(r'$kind') ? kinds : ['']) {
        final path = template
            .replaceAll(r'$kind', kind)
            .replaceAll('<location>', '{locationId}')
            .replaceAll('<shift>', '{shiftId}');
        result.add(
          '${call[1]!.toUpperCase()} ${path.replaceAll('<id>', path.endsWith('swap-colleagues') ? '{shiftId}' : '{requestId}')}',
        );
      }
    }
  }

  read(source.substring(0, loop), '');
  read(source.substring(selfOpen + 1, selfEnd - 1), root[1]!);
  read(source.substring(managerOpen + 1, managerEnd - 1), root[2]!);
  final actual = RegExp(r'router\.[a-z]+\(').allMatches(source).length;
  if (actual != readRegistrations ||
      result.any((s) => s.contains('<') || s.contains(r'$'))) {
    throw const FormatException('Unrecognized router registration.');
  }
  return result;
}

int _blockEnd(String source, int open) {
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    final c = source[i];
    if (c == '"' || c == "'") {
      final quote = c;
      while (++i < source.length) {
        if (source[i] == r'\') {
          i++;
        } else if (source[i] == quote) {
          break;
        }
      }
    } else if (c == '{') {
      depth++;
    } else if (c == '}' && --depth == 0) {
      return i + 1;
    }
  }
  throw const FormatException('Unclosed source block.');
}

String _git(String filename) {
  final result = Process.runSync('git', [
    'show',
    'HEAD:packages/api_contracts/$filename',
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    throw StateError('Cannot read existing API baseline.');
  }
  return result.stdout as String;
}

/// Independent raw-member comparison, including original key/value formatting.
Map<String, String> rawOpenApiMembers(String source, int indent) {
  final result = <String, String>{};
  final header = RegExp(
    indent == 4 ? r'^  "paths": \{' : r'^    "schemas": \{',
    multiLine: true,
  ).firstMatch(source);
  if (header == null) {
    throw const FormatException('Missing raw member comparison scope.');
  }
  final open = source.indexOf('{', header.start);
  source = source.substring(open + 1, _blockEnd(source, open) - 1);
  for (final match in RegExp(
    '^ {$indent}("[^"\\n]+"):',
    multiLine: true,
  ).allMatches(source)) {
    final key = jsonDecode(match[1]!) as String;
    final start = source.indexOf('{', match.end);
    result[key] = source.substring(match.start, _blockEnd(source, start));
  }
  return result;
}
