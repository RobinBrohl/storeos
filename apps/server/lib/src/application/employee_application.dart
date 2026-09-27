import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import '../platform/platform_input.dart';

/// Coordinates public module ports within one authorized local transaction.
class EmployeeApplication {
  EmployeeApplication(this.database)
    : _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;

  Future<Map<String, dynamic>> list(SessionPrincipal principal) =>
      database.runAuthorized(
        principal,
        'people.manage',
        (tx, actor) async => {
          'employees': (await _people.list(
            tx,
          )).map((item) => item.toJson()).toList(),
        },
      );

  Future<Map<String, dynamic>> get(SessionPrincipal principal, String id) {
    id = requireUuid({'id': id}, 'id');
    return database.runAuthorized(
      principal,
      'people.manage',
      (tx, actor) async => (await _people.get(tx, id)).toJson(),
    );
  }

  Future<Map<String, dynamic>> me(SessionPrincipal principal) =>
      database.runAuthorized(principal, 'people.self.read', (tx, actor) async {
        final link = await _links.forAccount(tx, actor.id);
        if (link == null ||
            link.companyId != actor.companyId ||
            link.locationId != actor.locationId) {
          throw const PlatformFailure(
            404,
            'employee_unavailable',
            'No active employee profile.',
          );
        }
        final employee = await _people.get(tx, link.employeeId);
        if (!employee.isActive ||
            employee.companyId != actor.companyId ||
            employee.locationId != actor.locationId) {
          throw const PlatformFailure(
            404,
            'employee_unavailable',
            'No active employee profile.',
          );
        }
        return employee.toJson();
      });

  Future<Map<String, dynamic>> create(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) {
    requireFields(input, required: {'id', 'displayName', 'locationId'});
    final id = requireUuid(input, 'id');
    final location = requireUuid(input, 'locationId');
    final name = requireName(input, 'displayName');
    return database.runAuthorized(principal, 'people.manage', (
      tx,
      actor,
    ) async {
      await _organization.requireConfiguredLocation(tx, location);
      final employee = await _people.create(tx, id, location, name);
      await database.audit(
        tx,
        actor,
        'people.employee.created',
        'employee',
        id,
        locationId: location,
        changes: {'isActive': true, 'version': employee.version},
      );
      return employee.toJson();
    });
  }

  Future<Map<String, dynamic>> rename(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(input, required: {'displayName', 'expectedVersion'});
    final name = requireName(input, 'displayName');
    final version = requireVersion(input);
    return database.runAuthorized(principal, 'people.manage', (
      tx,
      actor,
    ) async {
      final current = await _people.get(tx, id);
      _people.checkEditable(current, version);
      final updated = await _people.rename(tx, current, name);
      if (updated.version != current.version) {
        await database.audit(
          tx,
          actor,
          'people.employee.renamed',
          'employee',
          id,
          locationId: current.locationId,
          changes: {
            'changedFields': ['displayName'],
            'version': updated.version,
          },
        );
      }
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> deactivate(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(input, required: {'expectedVersion'});
    final version = requireVersion(input);
    return database.runAuthorized(principal, 'people.manage', (
      tx,
      actor,
    ) async {
      final current = await _people.get(tx, id);
      _people.checkEditable(current, version);
      final updated = await _people.deactivate(tx, current);
      final link = await _links.forEmployee(tx, id);
      if (link != null) await _links.revoke(tx, actor, link.id, link.version);
      await database.audit(
        tx,
        actor,
        'people.employee.deactivated',
        'employee',
        id,
        locationId: current.locationId,
        changes: {'isActive': false, 'version': updated.version},
      );
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> accountLink(
    SessionPrincipal principal,
    String id,
  ) {
    id = requireUuid({'id': id}, 'id');
    return database.runAuthorized(principal, 'people.manage', (
      tx,
      actor,
    ) async {
      await _people.get(tx, id);
      return {'link': (await _links.forEmployee(tx, id))?.toJson()};
    });
  }

  Future<Map<String, dynamic>> link(
    SessionPrincipal principal,
    String employeeId,
    Map<String, dynamic> input,
  ) {
    employeeId = requireUuid({'id': employeeId}, 'id');
    requireFields(
      input,
      required: {
        'id',
        'accountId',
        'expectedEmployeeVersion',
        'expectedAccountVersion',
      },
    );
    final id = requireUuid(input, 'id');
    final accountId = requireUuid(input, 'accountId');
    final employeeVersion = requireVersion({
      'expectedVersion': input['expectedEmployeeVersion'],
    });
    final accountVersion = requireVersion({
      'expectedVersion': input['expectedAccountVersion'],
    });
    return database.runAuthorized(principal, 'people.manage', (
      tx,
      actor,
    ) async {
      final employee = await _people.get(tx, employeeId);
      _people.checkEditable(employee, employeeVersion);
      return (await _links.link(
        tx,
        actor,
        employee,
        id: id,
        accountId: accountId,
        expectedAccountVersion: accountVersion,
      )).toJson();
    });
  }

  Future<Map<String, dynamic>> unlink(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> input,
  ) {
    id = requireUuid({'id': id}, 'id');
    requireFields(input, required: {'expectedVersion'});
    final version = requireVersion(input);
    return database.runAuthorized(
      principal,
      'people.manage',
      (tx, actor) async =>
          (await _links.revoke(tx, actor, id, version)).toJson(),
    );
  }
}
