import 'package:storeos_server/src/workforce/shift_transfer.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';

void main() {
  const allowed = {
    'proposed': {'accept', 'decline', 'source_withdraw', 'manager_reject'},
    'accepted': {
      'source_withdraw',
      'recipient_withdraw',
      'manager_reject',
      'manager_approve',
    },
  };
  for (final state in [
    'proposed',
    'accepted',
    'declined',
    'withdrawn',
    'rejected',
    'approved',
  ]) {
    for (final kind in [
      'accept',
      'decline',
      'source_withdraw',
      'recipient_withdraw',
      'manager_reject',
      'manager_approve',
    ]) {
      test('$state permits only its canonical $kind transition', () {
        final r = ShiftTransferRequest({
          'status': state,
          'version': 2,
          'proposedBy': 'source',
          'acceptedBy': 'recipient',
        });
        if (allowed[state]?.contains(kind) == true) {
          r.requireTransition(kind, 2, 'manager');
        } else {
          expect(
            () => r.requireTransition(kind, 2, 'manager'),
            throwsA(
              isA<PlatformFailure>().having(
                (e) => e.code,
                'code',
                'transfer_conflict',
              ),
            ),
          );
        }
        expect(
          () => r.requireTransition(kind, 1, 'manager'),
          throwsA(isA<PlatformFailure>()),
        );
      });
    }
  }
  for (final actor in ['source', 'recipient']) {
    test('independent approval excludes $actor Account', () {
      expect(
        () => ShiftTransferRequest({
          'status': 'accepted',
          'version': 2,
          'proposedBy': 'source',
          'acceptedBy': 'recipient',
        }).requireTransition('manager_approve', 2, actor),
        throwsA(isA<PlatformFailure>().having((e) => e.status, 'status', 403)),
      );
    });
  }
  test('fixed role grants are minimal', () {
    final all = {
      'workforce.transfers.self.read',
      'workforce.transfers.self.request',
      'workforce.transfers.self.respond',
      'workforce.transfers.manage',
    };
    expect(permissionsForRole('admin').toSet().intersection(all), all);
    expect(
      permissionsForRole('employee').toSet().intersection(all),
      all.difference({'workforce.transfers.manage'}),
    );
    for (final role in ['viewer', 'auditor', 'plugin']) {
      expect(permissionsForRole(role).toSet().intersection(all), isEmpty);
    }
  });
}
