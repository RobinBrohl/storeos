import 'package:postgres/postgres.dart';
import 'employee.dart';

class EmployeeRepository {
  EmployeeRepository(this.schema, this.companyId);
  final String schema, companyId;

  String get _columns =>
      'id::text, company_id::text, location_id::text, '
      'display_name, is_active, version, created_at, updated_at, assigned_from, assigned_until';

  Future<Employee?> find(TxSession tx, String id) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM $schema.employees '
        'WHERE id = CAST(@id AS uuid) AND company_id = CAST(@company AS uuid)',
      ),
      parameters: {'id': id, 'company': companyId},
    );
    return rows.isEmpty ? null : _employee(rows.single);
  }

  Future<List<Employee>> list(TxSession tx) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM $schema.employees '
        'WHERE company_id = CAST(@company AS uuid) ORDER BY id LIMIT 201',
      ),
      parameters: {'company': companyId},
    );
    return rows.map(_employee).toList();
  }

  Future<Employee> create(
    TxSession tx,
    String id,
    String locationId,
    String name,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO $schema.employees '
        '(id, company_id, location_id, display_name) VALUES '
        '(CAST(@id AS uuid), CAST(@company AS uuid), CAST(@location AS uuid), @name) '
        'RETURNING $_columns',
      ),
      parameters: {
        'id': id,
        'company': companyId,
        'location': locationId,
        'name': name,
      },
    );
    return _employee(rows.single);
  }

  Future<Employee?> update(
    TxSession tx,
    Employee employee, {
    String? name,
    bool deactivate = false,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'UPDATE $schema.employees SET '
        'display_name = @name, is_active = @active, version = version + 1, '
        'updated_at = clock_timestamp(), '
        'assigned_until = CASE WHEN @active THEN NULL ELSE clock_timestamp() END '
        'WHERE id = CAST(@id AS uuid) AND company_id = CAST(@company AS uuid) '
        'AND version = @version RETURNING $_columns',
      ),
      parameters: {
        'id': employee.id,
        'company': companyId,
        'name': name ?? employee.name,
        'active': !deactivate,
        'version': employee.version,
      },
    );
    return rows.isEmpty ? null : _employee(rows.single);
  }
}

Employee _employee(ResultRow row) {
  final data = row.toColumnMap();
  return Employee(
    id: data['id'] as String,
    companyId: data['company_id'] as String,
    locationId: data['location_id'] as String,
    name: data['display_name'] as String,
    isActive: data['is_active'] as bool,
    version: data['version'] as int,
    createdAt: data['created_at'] as DateTime,
    updatedAt: data['updated_at'] as DateTime,
    assignedFrom: data['assigned_from'] as DateTime,
    assignedUntil: data['assigned_until'] as DateTime?,
  );
}
