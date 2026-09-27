import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../platform/platform_database.dart';
import 'employee_link_repository.dart';
import 'identity_repository.dart';

/// Public identity port; receives a current people projection from the coordinator.
class EmployeeLinks {
  EmployeeLinks(this._database)
    : _links = EmployeeLinkRepository(_database.schema, _database.companyId),
      _accounts = IdentityRepository(_database);
  final PlatformDatabase _database;
  final EmployeeLinkRepository _links;
  final IdentityRepository _accounts;

  Future<EmployeeLinkDto?> forEmployee(TxSession tx, String employeeId) =>
      _links.find(tx, employeeId: employeeId);
  Future<EmployeeLinkDto?> forAccount(TxSession tx, String accountId) =>
      _links.find(tx, accountId: accountId);

  Future<EmployeeLinkDto> link(
    TxSession tx,
    PlatformActor actor,
    EmployeeDto employee, {
    required String id,
    required String accountId,
    required int expectedAccountVersion,
  }) async {
    final account = await _accounts.user(tx, accountId);
    if (account == null ||
        account.companyId != employee.companyId ||
        account.locationId != employee.locationId) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Account not available at this location.',
      );
    }
    if (!employee.isActive || !account.isActive) {
      throw const PlatformFailure(
        409,
        'inactive_identity',
        'Profile and account must be active.',
      );
    }
    if (account.version != expectedAccountVersion) {
      throw const PlatformFailure(
        409,
        'version_conflict',
        'Account version changed.',
      );
    }
    if (await _links.find(tx, id: id) != null ||
        await forEmployee(tx, employee.id) != null ||
        await forAccount(tx, accountId) != null) {
      throw const PlatformFailure(
        409,
        'already_linked',
        'Account or employee is already linked.',
      );
    }
    final created = await _links.create(tx, id, accountId, employee);
    await _accounts.revokeSessions(tx, accountId);
    await _audit(tx, actor, created, 'identity.employee.linked');
    return created;
  }

  Future<EmployeeLinkDto> revoke(
    TxSession tx,
    PlatformActor actor,
    String id,
    int expectedVersion,
  ) async {
    final current = await _links.find(tx, id: id);
    if (current == null) {
      throw const PlatformFailure(404, 'not_found', 'Link not found.');
    }
    if (current.version != expectedVersion || current.revokedAt != null) {
      throw const PlatformFailure(
        409,
        'version_conflict',
        'Link version changed.',
      );
    }
    final updated = await _links.revoke(tx, current);
    if (updated == null) {
      throw const PlatformFailure(
        409,
        'version_conflict',
        'Link version changed.',
      );
    }
    await _accounts.revokeSessions(tx, current.accountId);
    await _audit(tx, actor, updated, 'identity.employee.unlinked');
    return updated;
  }

  Future<void> _audit(
    TxSession tx,
    PlatformActor actor,
    EmployeeLinkDto link,
    String action,
  ) => _database.audit(
    tx,
    actor,
    action,
    'employee_link',
    link.id,
    locationId: link.locationId,
    changes: {
      'accountId': link.accountId,
      'employeeId': link.employeeId,
      'status': link.revokedAt == null ? 'linked' : 'revoked',
      'version': link.version,
    },
  );
}
