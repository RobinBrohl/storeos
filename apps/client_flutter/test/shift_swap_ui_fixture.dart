import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import 'shift_swap_fixture.dart';
import 'shift_swap_test.dart' as fixture;

class SwapUiHarness extends fixture.SwapHarness {
  SwapUiHarness({super.role, super.state, super.stage, super.self});
  bool showList = true, sourceChanged = false;
  Completer<http.Response>? workHold;
  WidgetTester? tester;
  final receipts = <Map<String, dynamic>>[];

  @override
  Future<void> login() async {
    if (tester == null) {
      await super.login();
    } else {
      await tester!.runAsync(super.login);
    }
  }

  List<Map<String, dynamic>> get historyRows => [
    for (var v = 1; v <= (evidence['version'] as int); v++)
      {
        'operationId': v == 1
            ? evidence['requestOperationId']
            : v == 2 && evidence['offeredAt'] != null
            ? evidence['offerOperationId']
            : v == 3 && evidence['confirmedAt'] != null
            ? evidence['confirmationOperationId']
            : evidence['terminalOperationId'],
        'kind': v == 1
            ? 'request'
            : v == 2 && evidence['offeredAt'] != null
            ? 'offer'
            : v == 3 && evidence['confirmedAt'] != null
            ? 'confirm'
            : evidence['terminalKind'],
        'acceptedVersion': v,
        'statusCode': v == 1 ? 201 : 200,
        'request': v == evidence['version']
            ? evidence
            : {
                ...swapEvidence(
                  state: v == 1
                      ? 'requested'
                      : v == 2
                      ? 'offered'
                      : 'confirmed',
                  stage: v,
                ),
                'id': evidence['id'],
              },
        'replayed': false,
      },
  ];

  ShiftDto get ownShift => ShiftDto(
    id: swapId(20),
    companyId: swapId(2),
    locationId: swapId(3),
    version: sourceChanged ? 3 : 2,
    status: 'published',
    draft: ShiftDraftInput(
      employeeId: swapId(4),
      startsAt: DateTime.utc(2030, 1, 1, 10),
      endsAt: DateTime.utc(2030, 1, 1, 11),
      selections: [ShiftTemplateSelection(swapId(500), swapId(600))],
    ),
    createdAt: DateTime.utc(2029),
    updatedAt: DateTime.utc(2029),
  );
  Map<String, dynamic> get ownTask => {
    'id': swapId(120),
    'shiftId': swapId(20),
    'employeeId': swapId(4),
    'templateId': swapId(500),
    'revisionId': swapId(600),
    'position': 0,
    'status': 'open',
    'version': 1,
    'title': 'Exact work 0',
    'content': {'schemaVersion': 1, 'title': 'Exact work 0', 'steps': []},
  };
  @override
  Future<http.Response> handle(http.Request r) async {
    final route = r.url.path.substring('/api/v1/platform'.length);
    if (r.method == 'GET' &&
        route == '$root/$id' &&
        readHold == null &&
        readError == null &&
        read == null) {
      requests.add(r);
      return http.Response(
        jsonEncode(detail()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    if (r.method == 'GET' &&
        route.startsWith('/employee-home/shifts/') &&
        !route.endsWith('/swap-colleagues')) {
      requests.add(r);
      if (workHold != null) return workHold!.future;
      if (readError != null) throw readError!;
      return fixture.response(
        route.contains('/tasks/')
            ? ownTask
            : {
                'shift': ownShift.toJson(),
                'tasks': [ownTask],
              },
      );
    }
    if (r.method == 'GET' &&
        (route == root || route.endsWith('/history')) &&
        readHold == null &&
        readError == null &&
        read == null) {
      requests.add(r);
      return fixture.response({
        'items': route == root
            ? [if (showList) evidence]
            : historyRows
                  .skip(r.url.queryParameters['after'] == null ? 0 : 2)
                  .take(2)
                  .toList(),
        'nextCursor':
            route.endsWith('/history') &&
                historyRows.length > 2 &&
                r.url.queryParameters['after'] == null
            ? 'history-page-2'
            : null,
      });
    }
    final result = await super.handle(r);
    return http.Response.bytes(
      result.bodyBytes,
      result.statusCode,
      headers: {
        ...result.headers,
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  @override
  Map<String, dynamic> accept(String route, Map<String, dynamic> body) {
    final result = super.accept(route, body);
    receipts.add(result);
    return result;
  }
}
