import 'dart:convert';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import '../tool/backup_restore_fixture.dart' show applyBackupMigrations;
import '../tool/shift_transfer_acceptance.dart';
import 'merchandising_fixture.dart';
import 'shift_swap_stage_a_fixture.dart';

void main() {
  test(
    'backup schema ordering restores restricted HTTP proposal, claim and replay',
    () => withMerchandisingFixture((f) async {
      final fixture = await stageAFixture(f);
      await f.call(
        'POST',
        '/shifts/${fixture.shiftB}/cancel',
        body: {
          'expectedVersion': 2,
          'reason': 'Recipient is free for transfer',
        },
      );
      final proposal = {
        'requestId': newUuid(),
        'operationId': newUuid(),
        'sourceShiftId': fixture.shiftA,
        'expectedSourceVersion': 2,
        'recipientEmployeeId': fixture.b.employee,
      };
      // Preserve the original valid proposal's failure at the old backup prefix.
      await f.call(
        'POST',
        '/me/shift-transfers',
        token: fixture.a.token,
        body: proposal,
        expected: 500,
      );
      for (final table in [
        'workforce_shift_transfer_requests',
        'workforce_shift_transfer_commands',
      ]) {
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM ${f.schema}.$table',
          )).single.first,
          0,
        );
      }
      await f.server!.close(force: true);
      f.server = null;
      expect(await applyBackupMigrations(f.owner, f.schema, f.runtimeUser), [
        '0026_purchase_order_delivery_evidence',
        '0027_article_quantities',
        '0028_bilateral_shift_swaps',
        '0029_swap_leg_future_error',
      ]);
      expect(
        await applyBackupMigrations(f.owner, f.schema, f.runtimeUser),
        isEmpty,
      );
      await f.restart();
      final result = (await f.call(
        'POST',
        '/me/shift-transfers',
        token: fixture.a.token,
        body: proposal,
        expected: 201,
      )).body;
      final before = await verifyTransferHandoffClaims(
        f.owner,
        f.schema,
        expectedActive: 1,
      );
      final replay = (await f.call(
        'POST',
        '/me/shift-transfers',
        token: fixture.a.token,
        body: proposal,
        expected: 201,
      )).body;
      expect(replay, {...result, 'replayed': true});
      expect(
        jsonEncode(
          await verifyTransferHandoffClaims(
            f.owner,
            f.schema,
            expectedActive: 1,
          ),
        ),
        jsonEncode(before),
      );
      await f.call(
        'POST',
        '/me/shift-transfers/${proposal['requestId']}/decline',
        token: fixture.b.token,
        body: {'operationId': newUuid(), 'expectedVersion': 1},
      );
      await verifyTransferHandoffClaims(f.owner, f.schema, expectedActive: 0);
    }, legacyBefore: '0026_purchase_order_delivery_evidence'),
    skip: merchandisingDatabaseAvailable
        ? false
        : 'Explicit isolated PostgreSQL required.',
  );
}
