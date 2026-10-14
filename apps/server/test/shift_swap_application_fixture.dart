import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/application/shift_swap_application.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

class B1SwapFixture {
  B1SwapFixture(this.s, this.a, this.b)
    : app = ShiftSwapApplication(s.f.database);
  final StageASwapFixture s;
  final SessionPrincipal a, b;
  final ShiftSwapApplication app;
  MerchandisingFixture get f => s.f;
  late ShiftSwapCommandInput requested, offered, confirmed;
  String get id => requested.payload['requestId'] as String;
  Future<ShiftSwapCommandResult> request() {
    requested = s.requestCommand();
    return app.command(a, null, 'request', requested.toJson());
  }

  Future<ShiftSwapCommandResult> offer({String? counterpart}) {
    offered = ShiftSwapCommandInput.fromJson('offer', {
      'operationId': newUuid(),
      'expectedVersion': 1,
      'counterpartShiftId': counterpart ?? s.shiftB,
      'expectedCounterpartVersion': 2,
    });
    return app.command(b, id, 'offer', offered.toJson());
  }

  Future<ShiftSwapCommandResult> confirm() {
    confirmed = ShiftSwapCommandInput.fromJson('confirm', {
      'operationId': newUuid(),
      'expectedVersion': 2,
    });
    return app.command(a, id, 'confirm', confirmed.toJson());
  }

  Future<void> prepare(int version) async {
    await request();
    if (version >= 2) await offer();
    if (version >= 3) await confirm();
  }

  Map<String, dynamic> approval({String? operation}) => {
    'operationId': operation ?? newUuid(),
    'expectedVersion': 3,
  };
  Future<ShiftSwapCommandResult> approve({Map<String, dynamic>? body}) =>
      app.command(
        f.adminPrincipal,
        id,
        'manager_approve',
        body ?? approval(),
        self: false,
      );
}

Future<B1SwapFixture> b1Fixture(
  MerchandisingFixture f, {
  int tasks = 1,
  DateTime? starts,
}) async {
  final s = await stageAFixture(f, taskCount: tasks, starts: starts);
  return B1SwapFixture(
    s,
    await f.auth.authenticate(s.a.token),
    await f.auth.authenticate(s.b.token),
  );
}

Future<String> b1Shift(
  MerchandisingFixture f,
  String employee,
  DateTime start,
  List<ShiftTemplateSelection> selections, {
  Duration length = const Duration(hours: 1),
}) async {
  final id = newUuid();
  await f.call(
    'POST',
    '/shifts',
    expected: 201,
    body: {
      'id': id,
      'locationId': merchandisingTestLocation,
      'employeeId': employee,
      'startsAt': start.toUtc().toIso8601String(),
      'endsAt': start.add(length).toUtc().toIso8601String(),
      'selections': [for (final s in selections) s.toJson()],
    },
  );
  await f.call('POST', '/shifts/$id/publish', body: {'expectedVersion': 1});
  return id;
}
