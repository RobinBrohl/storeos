import 'package:postgres/postgres.dart';

import '../platform/platform_database.dart';
import 'organization_model.dart';

class OrganizationRepository {
  OrganizationRepository(this.database);

  final PlatformDatabase database;

  /// Narrow read projection for an already authorized, location-scoped plugin.
  Future<Map<String, dynamic>> pluginProjection(
    TxSession tx, {
    required String companyId,
    required String locationId,
  }) async {
    if (companyId != database.companyId) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
    final visibleCompany = await company(tx);
    final visibleLocation = await location(tx, locationId);
    if (visibleCompany == null || visibleLocation == null) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
    return {
      'company': visibleCompany.toJson(),
      'locations': [visibleLocation.toJson()],
    };
  }

  Future<CompanyRecord?> company(TxSession tx) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, name, version FROM ${database.schema}.companies '
        'WHERE id = CAST(@companyId AS uuid)',
      ),
      parameters: {'companyId': database.companyId},
    );
    return result.isEmpty ? null : _companyFromRow(result.single);
  }

  Future<LocationRecord?> location(TxSession tx, String locationId) async {
    final result = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, company_id::text AS company_id, name, version '
        'FROM ${database.schema}.locations '
        'WHERE id = CAST(@locationId AS uuid) '
        'AND company_id = CAST(@companyId AS uuid)',
      ),
      parameters: {'locationId': locationId, 'companyId': database.companyId},
    );
    return result.isEmpty ? null : _locationFromRow(result.single);
  }

  Future<List<LocationRecord>> locations(
    TxSession tx, {
    String? onlyLocationId,
  }) async {
    final locationFilter = onlyLocationId == null
        ? ''
        : 'AND id = CAST(@onlyLocationId AS uuid) ';
    final parameters = <String, dynamic>{'companyId': database.companyId};
    if (onlyLocationId != null) parameters['onlyLocationId'] = onlyLocationId;
    final result = await tx.execute(
      Sql.named(
        'SELECT id::text AS id, company_id::text AS company_id, name, version '
        'FROM ${database.schema}.locations '
        'WHERE company_id = CAST(@companyId AS uuid) '
        '$locationFilter'
        'ORDER BY id LIMIT 201',
      ),
      parameters: parameters,
    );
    return result.map(_locationFromRow).toList();
  }

  Future<CompanyRecord> setCompanyName(
    TxSession tx,
    String name,
    int expectedVersion,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.companies '
        'SET name = @name, version = version + 1, updated_at = now() '
        'WHERE id = CAST(@companyId AS uuid) AND version = @expectedVersion '
        'RETURNING id::text AS id, name, version',
      ),
      parameters: {
        'name': name,
        'companyId': database.companyId,
        'expectedVersion': expectedVersion,
      },
    );
    if (result.isEmpty) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    return _companyFromRow(result.single);
  }

  Future<LocationRecord> setLocationName(
    TxSession tx,
    String locationId,
    String name,
    int expectedVersion,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'UPDATE ${database.schema}.locations '
        'SET name = @name, version = version + 1, updated_at = now() '
        'WHERE id = CAST(@locationId AS uuid) '
        'AND company_id = CAST(@companyId AS uuid) '
        'AND version = @expectedVersion '
        'RETURNING id::text AS id, company_id::text AS company_id, name, version',
      ),
      parameters: {
        'locationId': locationId,
        'companyId': database.companyId,
        'name': name,
        'expectedVersion': expectedVersion,
      },
    );
    if (result.isEmpty) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    return _locationFromRow(result.single);
  }

  Future<LocationRecord> createLocation(
    TxSession tx,
    String locationId,
    String name,
  ) async {
    final result = await tx.execute(
      Sql.named(
        'INSERT INTO ${database.schema}.locations (id, company_id, name) '
        'VALUES (CAST(@locationId AS uuid), CAST(@companyId AS uuid), @name) '
        'RETURNING id::text AS id, company_id::text AS company_id, name, version',
      ),
      parameters: {
        'locationId': locationId,
        'companyId': database.companyId,
        'name': name,
      },
    );
    return _locationFromRow(result.single);
  }
}

CompanyRecord _companyFromRow(ResultRow row) {
  final values = row.toColumnMap();
  return CompanyRecord(
    values['id']! as String,
    values['name'] as String?,
    values['version']! as int,
  );
}

LocationRecord _locationFromRow(ResultRow row) {
  final values = row.toColumnMap();
  return LocationRecord(
    values['id']! as String,
    values['company_id']! as String,
    values['name'] as String?,
    values['version']! as int,
  );
}
