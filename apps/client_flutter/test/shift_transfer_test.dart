import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/shift_transfer_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/shift_transfer_section.dart';
import 'preparation_batch_test.dart' show BatchApi, BatchAuth;
import 'recipe_test.dart' show company, location, article, revision, line;

const transferLiteral = '<script>literal</script> **plain** 😀';
Map<String, dynamic> transferJson({
  String role = 'recipient',
  String state = 'proposed',
}) => {
  'id': line,
  'companyId': company,
  'locationId': location,
  'sourceShiftId': article,
  'sourceEmployeeId': company,
  'recipientEmployeeId': revision,
  'proposedBy': article,
  'sourceLinkId': company,
  'recipientLinkId': revision,
  'recipientAccountId': revision,
  'sourceVersion': 2,
  'sourceAccountVersion': 1,
  'recipientAccountVersion': 1,
  'proposalOperationId': article,
  'status': state,
  'version': state == 'proposed' ? 1 : 2,
  'startsAt': '2030-01-01T08:00:00Z',
  'endsAt': '2030-01-01T10:00:00Z',
  'proposedAt': '2029-01-01T08:00:00Z',
  'acceptedBy': state == 'accepted' ? revision : null,
  'acceptedAt': state == 'accepted' ? '2029-01-01T09:00:00Z' : null,
  'acceptanceOperationId': state == 'accepted' ? line : null,
  'terminalBy': null,
  'terminalAt': null,
  'terminalReason': null,
  'terminalKind': null,
  'terminalOperationId': null,
  'replacementShiftId': null,
  'sourceName': transferLiteral,
  'recipientName': 'Recipient',
  'tasks': [
    {
      'id': article,
      'title': transferLiteral,
      'templateId': article,
      'revisionId': revision,
      'position': 0,
      'knowledgeGuidance': null,
      'planogramGuidance': null,
    },
  ],
  'taskLinks': <Map<String, dynamic>>[],
  'participantRole': role,
  'actionable': true,
  'nonActionableReason': null,
};

class TransferApi extends BatchApi {
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': company,
        'companyId': company,
        'locationId': location,
        'role': 'admin',
        'permissions': [
          'workforce.transfers.self.read',
          'workforce.transfers.self.request',
          'workforce.transfers.self.respond',
          'workforce.transfers.manage',
          'workforce.shifts.manage',
          'tasks.instances.read',
        ],
      };
    }
    if (route == '/organization') return super.get(token, route);
    if (readHold != null) return readHold!.future;
    if (readFailure != null) throw readFailure!;
    return detailReply ?? transferJson();
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    routes.add(route);
    bodies.add(Map.of(body));
    if (postHold != null) return postHold!.future;
    if (failure != null) throw failure!;
    return reply ?? {'request': transferJson(), 'replayed': true};
  }
}

Future<(SessionController, ShiftTransferController)> transferSetup(
  TransferApi api, {
  bool self = true,
  String role = 'recipient',
  String state = 'proposed',
}) async {
  final session = SessionController(BatchAuth()),
      platform = PlatformController(session, api),
      controller = ShiftTransferController(session, platform, api, self: self);
  final ready = Completer<void>();
  void changed() {
    if (platform.organization != null &&
        !platform.isBusy &&
        !ready.isCompleted) {
      ready.complete();
    }
  }

  platform.addListener(changed);
  await session.signIn(username: 'employee', password: 'test');
  changed();
  await ready.future;
  platform.removeListener(changed);
  addTearDown(() {
    controller.dispose();
    platform.dispose();
    session.dispose();
  });
  controller.detail = ShiftTransferDto.fromJson(
    transferJson(role: role, state: state),
  );
  return (session, controller);
}

Future<TransferOutcome> invokeTransfer(ShiftTransferController c, String kind) {
  if (kind == 'propose') {
    c.source = ShiftDto(
      id: article,
      companyId: company,
      locationId: location,
      version: 2,
      status: 'published',
      draft: ShiftDraftInput(
        employeeId: company,
        startsAt: DateTime.utc(2030, 1, 1, 8),
        endsAt: DateTime.utc(2030, 1, 1, 10),
        selections: [ShiftTemplateSelection(article, revision)],
      ),
      createdAt: DateTime.utc(2029),
      updatedAt: DateTime.utc(2029),
    );
    c.recipient = {'employeeId': revision, 'displayName': 'Recipient'};
    return c.propose();
  }
  return c.act(
    kind.startsWith('manager_')
        ? kind.substring(8)
        : kind.endsWith('withdraw')
        ? 'withdraw'
        : kind,
    reason: kind.endsWith('withdraw') || kind == 'manager_reject'
        ? transferLiteral
        : null,
  );
}

void main() {
  for (final kind in [
    'propose',
    'accept',
    'decline',
    'source_withdraw',
    'recipient_withdraw',
    'manager_reject',
    'manager_approve',
  ]) {
    test(
      '$kind immutable exact uncertain retry and successful failed-refresh separation',
      () async {
        final api = TransferApi();
        final (_, c) = await transferSetup(
          api,
          self: !kind.startsWith('manager_'),
          role: kind == 'source_withdraw' ? 'source' : 'recipient',
          state: kind == 'recipient_withdraw' || kind == 'manager_approve'
              ? 'accepted'
              : 'proposed',
        );
        api.failure = const StoreApiException(
          'database_unavailable',
          'Unconfirmed',
          statusCode: 503,
        );
        expect(await invokeTransfer(c, kind), TransferOutcome.uncertain);
        final p = c.pending!;
        expect(() => p.body['operationId'] = company, throwsUnsupportedError);
        expect(c.can('accept'), false);
        await c.load();
        api.failure = null;
        api.readFailure = const StoreApiException(
          'database_unavailable',
          'Refresh unavailable',
          statusCode: 503,
        );
        expect(await c.retry(), TransferOutcome.confirmed);
        expect(api.routes[0], api.routes[1]);
        expect(api.bodies[0], api.bodies[1]);
        expect(c.pending, isNull);
        expect(c.lastConfirmed, isNotNull);
        expect(c.detail, isNull);
        expect(c.refreshWarning, contains('Command confirmed'));
        expect(c.can('approve'), false);
      },
    );
    test(
      '$kind same-account session replacement fences delayed writes and all transient state',
      () async {
        final api = TransferApi();
        final (s, c) = await transferSetup(
          api,
          self: !kind.startsWith('manager_'),
          role: kind == 'source_withdraw' ? 'source' : 'recipient',
          state: kind == 'recipient_withdraw' || kind == 'manager_approve'
              ? 'accepted'
              : 'proposed',
        );
        api.postHold = Completer<Map<String, dynamic>>();
        final result = invokeTransfer(c, kind);
        expect(c.pending, isNotNull);
        final before = s.sessionIdentity;
        await s.signIn(username: 'employee', password: 'test');
        expect(identical(before, s.sessionIdentity), false);
        api.postHold!.complete({'request': transferJson(), 'replayed': false});
        expect(await result, TransferOutcome.fenced);
        expect(c.detail, isNull);
        expect(c.source, isNull);
        expect(c.recipient, isNull);
        expect(c.pending, isNull);
        expect(c.items, isEmpty);
        expect(c.lastConfirmed, isNull);
        expect(c.nextCursor, isNull);
        expect(c.direction, isNull);
      },
    );
  }
  test('delayed participant GET cannot populate replacement session', () async {
    final api = TransferApi();
    final (s, c) = await transferSetup(api);
    api.readHold = Completer<Map<String, dynamic>>();
    final loading = c.select(line);
    await s.signIn(username: 'employee', password: 'test');
    api.readHold!.complete(transferJson());
    await loading;
    expect(c.detail, isNull);
    expect(c.error, isNull);
  });
  test(
    'definitive stale conflict clears executable detail and does not retain operation',
    () async {
      final api = TransferApi();
      final (_, c) = await transferSetup(api);
      api.failure = const StoreApiException(
        'shift_conflict',
        'Changed',
        statusCode: 409,
      );
      expect(await c.act('accept'), TransferOutcome.rejected);
      expect(c.pending, isNull);
      expect(c.detail, isNull);
      expect(c.can('accept'), false);
    },
  );
  testWidgets(
    'literal transfer evidence, acceptance explanation and reason field clearing',
    (tester) async {
      final api = TransferApi();
      final (s, c) = await transferSetup(api, role: 'source');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ShiftTransferSection(controller: c)),
        ),
      );
      await tester.pump();
      expect(find.textContaining(transferLiteral), findsWidgets);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Private withdrawal text');
      await s.signIn(username: 'employee', password: 'test');
      await tester.pump();
      expect(find.text('Private withdrawal text'), findsNothing);
      await s.signOut();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
