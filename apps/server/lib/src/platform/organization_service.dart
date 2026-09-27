import '../infrastructure/auth_store.dart';
import '../organization/organization_repository.dart';
import 'platform_database.dart';
import 'platform_input.dart';

class OrganizationService {
  OrganizationService(this.database)
    : repository = OrganizationRepository(database);

  final PlatformDatabase database;
  final OrganizationRepository repository;

  Future<Map<String, dynamic>> read(SessionPrincipal principal) =>
      database.runAuthorized(principal, 'organization.read', (tx, actor) async {
        final company = await repository.company(tx);
        if (company == null) {
          throw const PlatformFailure(
            503,
            'platform_not_initialized',
            'Organization is unavailable.',
          );
        }
        final locations = await repository.locations(
          tx,
          onlyLocationId: actor.role == 'viewer' ? actor.locationId : null,
        );
        if (locations.length > 200) {
          throw const PlatformFailure(
            409,
            'resource_limit',
            'Too many locations for this API.',
          );
        }
        return {
          'company': company.toJson(),
          'locations': locations.map((location) => location.toJson()).toList(),
        };
      });

  Future<Map<String, dynamic>> setup(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) async {
    requireFields(input, required: {'companyName', 'locationName'});
    final companyName = requireName(input, 'companyName');
    final locationName = requireName(input, 'locationName');
    return database.runAuthorized(principal, 'organization.write', (
      tx,
      actor,
    ) async {
      final currentCompany = await repository.company(tx);
      final currentLocation = await repository.location(
        tx,
        database.locationId,
      );
      if (currentCompany == null || currentLocation == null) {
        throw const PlatformFailure(
          503,
          'platform_not_initialized',
          'Organization is unavailable.',
        );
      }
      if (currentCompany.name != null || currentLocation.name != null) {
        throw const PlatformFailure(
          409,
          'already_configured',
          'Organization is already configured.',
        );
      }
      final company = await repository.setCompanyName(
        tx,
        companyName,
        currentCompany.version,
      );
      final location = await repository.setLocationName(
        tx,
        database.locationId,
        locationName,
        currentLocation.version,
      );
      await database.audit(
        tx,
        actor,
        'organization.company.setup',
        'company',
        company.id,
        changes: {'name': companyName, 'version': company.version},
      );
      await database.audit(
        tx,
        actor,
        'organization.location.setup',
        'location',
        location.id,
        locationId: location.id,
        changes: {'name': locationName, 'version': location.version},
      );
      final correlationId = newUuid();
      await database.publishOrganizationEvent(
        tx,
        actor,
        'organization.company.setup',
        'company',
        company.id,
        company.version,
        company.toJson(),
        correlationId: correlationId,
      );
      await database.publishOrganizationEvent(
        tx,
        actor,
        'organization.location.updated',
        'location',
        location.id,
        location.version,
        location.toJson(),
        locationId: location.id,
        correlationId: correlationId,
      );
      return {
        'company': company.toJson(),
        'locations': [location.toJson()],
      };
    });
  }

  Future<Map<String, dynamic>> renameCompany(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) async {
    requireFields(input, required: {'name', 'expectedVersion'});
    final name = requireName(input, 'name');
    final expectedVersion = requireVersion(input);
    return database.runAuthorized(principal, 'organization.write', (
      tx,
      actor,
    ) async {
      final current = await repository.company(tx);
      if (current == null) {
        throw const PlatformFailure(
          503,
          'platform_not_initialized',
          'Organization is unavailable.',
        );
      }
      _checkVersion(current.version, expectedVersion);
      if (current.name == null) {
        throw const PlatformFailure(
          409,
          'setup_required',
          'Set up the organization first.',
        );
      }
      if (current.name == name) return current.toJson();
      final updated = await repository.setCompanyName(
        tx,
        name,
        expectedVersion,
      );
      await database.audit(
        tx,
        actor,
        'organization.company.updated',
        'company',
        updated.id,
        changes: {
          'oldName': current.name,
          'newName': updated.name,
          'version': updated.version,
        },
      );
      await database.publishOrganizationEvent(
        tx,
        actor,
        'organization.company.updated',
        'company',
        updated.id,
        updated.version,
        updated.toJson(),
      );
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> createLocation(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) async {
    requireFields(input, required: {'id', 'name'});
    final id = requireUuid(input, 'id');
    final name = requireName(input, 'name');
    return database.runAuthorized(principal, 'organization.write', (
      tx,
      actor,
    ) async {
      final company = await repository.company(tx);
      if (company?.name == null) {
        throw const PlatformFailure(
          409,
          'setup_required',
          'Set up the organization first.',
        );
      }
      if (await repository.location(tx, id) != null) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Location already exists.',
        );
      }
      final locations = await repository.locations(tx);
      if (locations.length >= 200) {
        throw const PlatformFailure(
          409,
          'resource_limit',
          'Location limit reached.',
        );
      }
      final created = await repository.createLocation(tx, id, name);
      await database.audit(
        tx,
        actor,
        'organization.location.created',
        'location',
        created.id,
        locationId: created.id,
        changes: {'name': created.name, 'version': created.version},
      );
      await database.publishOrganizationEvent(
        tx,
        actor,
        'organization.location.created',
        'location',
        created.id,
        created.version,
        created.toJson(),
        locationId: created.id,
      );
      return created.toJson();
    });
  }

  Future<Map<String, dynamic>> renameLocation(
    SessionPrincipal principal,
    String locationId,
    Map<String, dynamic> input,
  ) async {
    final id = requireUuid({'id': locationId}, 'id');
    requireFields(input, required: {'name', 'expectedVersion'});
    final name = requireName(input, 'name');
    final expectedVersion = requireVersion(input);
    return database.runAuthorized(principal, 'organization.write', (
      tx,
      actor,
    ) async {
      final current = await repository.location(tx, id);
      if (current == null) {
        throw const PlatformFailure(404, 'not_found', 'Location not found.');
      }
      _checkVersion(current.version, expectedVersion);
      final company = await repository.company(tx);
      if (company?.name == null || current.name == null) {
        throw const PlatformFailure(
          409,
          'setup_required',
          'Set up the organization first.',
        );
      }
      if (current.name == name) return current.toJson();
      final updated = await repository.setLocationName(
        tx,
        id,
        name,
        expectedVersion,
      );
      await database.audit(
        tx,
        actor,
        'organization.location.updated',
        'location',
        updated.id,
        locationId: updated.id,
        changes: {
          'oldName': current.name,
          'newName': updated.name,
          'version': updated.version,
        },
      );
      await database.publishOrganizationEvent(
        tx,
        actor,
        'organization.location.updated',
        'location',
        updated.id,
        updated.version,
        updated.toJson(),
        locationId: updated.id,
      );
      return updated.toJson();
    });
  }
}

void _checkVersion(int actual, int expected) {
  if (actual != expected) {
    throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
  }
}
