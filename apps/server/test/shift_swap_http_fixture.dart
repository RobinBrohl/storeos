import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

const swapSelf = '/me/shift-swaps';
String swapManage(String id) =>
    '/locations/$merchandisingTestLocation/shift-swaps/$id';

/// Real network HTTP through ServerApp, authentication, router and restricted SQL.
Future<Map<String, dynamic>> swapCall(
  MerchandisingFixture f,
  String method,
  String route, {
  String? token,
  Map<String, dynamic>? body,
  String? raw,
  String? mediaType = 'application/json',
  bool chunked = false,
  int expected = 200,
  String? code,
}) async {
  final request = await f.client.openUrl(
    method,
    Uri.parse('${f.base}/api/v1/platform$route'),
  );
  final credential = token ?? f.adminToken;
  if (credential != null && credential.isNotEmpty) {
    request.headers.set('authorization', 'Bearer $credential');
  }
  if (mediaType != null) request.headers.set('content-type', mediaType);
  if (body != null || raw != null) {
    final bytes = utf8.encode(raw ?? jsonEncode(body));
    if (!chunked) request.contentLength = bytes.length;
    request.add(bytes);
  }
  final response = await request.close();
  final text = await utf8.decodeStream(response);
  expect(response.statusCode, expected, reason: '$method $route: $text');
  expect(response.headers.contentType?.mimeType, 'application/json');
  expect(response.headers.contentType?.charset, 'utf-8');
  expect(response.headers.value('cache-control'), 'no-store');
  expect(response.headers.value('x-content-type-options'), 'nosniff');
  expect(
    response.headers.value('x-request-id'),
    matches(RegExp(r'^[a-f0-9-]{36}$')),
  );
  final json = jsonDecode(text) as Map<String, dynamic>;
  if (expected >= 400) {
    expect(json.keys.toSet(), {'code', 'message'});
    if (code != null) expect(json['code'], code);
    for (final private in [
      'SELECT ',
      'INSERT ',
      f.schema,
      'ServerException',
      'stackTrace',
      'account_id',
      'link_id',
    ]) {
      expect(text, isNot(contains(private)));
    }
  }
  return json;
}

class HttpSwapFixture {
  HttpSwapFixture(this.s)
    : requestBody = s.requestCommand().toJson(),
      offerBody = {
        'operationId': newUuid(),
        'expectedVersion': 1,
        'counterpartShiftId': s.shiftB,
        'expectedCounterpartVersion': 2,
      },
      confirmBody = {'operationId': newUuid(), 'expectedVersion': 2},
      approvalBody = {'operationId': newUuid(), 'expectedVersion': 3};
  final StageASwapFixture s;
  MerchandisingFixture get f => s.f;
  final Map<String, dynamic> requestBody, offerBody, confirmBody, approvalBody;
  String get id => requestBody['requestId'] as String;
  String get a => s.a.token;
  String get b => s.b.token;
  Future<Map<String, dynamic>> request() =>
      swapCall(f, 'POST', swapSelf, token: a, body: requestBody, expected: 201);
  Future<Map<String, dynamic>> offer() =>
      swapCall(f, 'POST', '$swapSelf/$id/offer', token: b, body: offerBody);
  Future<Map<String, dynamic>> confirm() =>
      swapCall(f, 'POST', '$swapSelf/$id/confirm', token: a, body: confirmBody);
  Future<Map<String, dynamic>> approve() =>
      swapCall(f, 'POST', '${swapManage(id)}/approve', body: approvalBody);
  Future<void> prepare(int version) async {
    await request();
    if (version >= 2) await offer();
    if (version >= 3) await confirm();
  }
}

Future<HttpSwapFixture> httpSwapFixture(
  MerchandisingFixture f, {
  DateTime? starts,
  int tasks = 1,
}) async =>
    HttpSwapFixture(await stageAFixture(f, starts: starts, taskCount: tasks));

void expectSwapReceipt(Map<String, dynamic> result) {
  expect(ShiftSwapCommandResult.fromJson(result).toJson(), result);
  final encoded = jsonEncode(result);
  for (final private in [
    'accountId',
    'accountVersion',
    'linkId',
    'source_account',
    'recipient_account',
  ]) {
    expect(encoded, isNot(contains(private)));
  }
}

Object get swapHttpSkip => merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';
