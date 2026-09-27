import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

class EmployeeLinkRepository {
  EmployeeLinkRepository(this.schema, this.companyId);
  final String schema, companyId;
  String get _columns =>
      'id::text, account_id::text, employee_id::text, '
      'company_id::text, location_id::text, version, linked_at, revoked_at';

  Future<EmployeeLinkDto?> find(
    TxSession tx, {
    String? id,
    String? employeeId,
    String? accountId,
  }) async {
    final rows = await tx.execute(
      Sql.named(
        'SELECT $_columns FROM $schema.account_employee_links '
        'WHERE company_id = CAST(@company AS uuid) AND '
        '${id != null
            ? 'id = CAST(@target AS uuid)'
            : employeeId != null
            ? 'employee_id = CAST(@target AS uuid) AND revoked_at IS NULL'
            : 'account_id = CAST(@target AS uuid) AND revoked_at IS NULL'}',
      ),
      parameters: {
        'company': companyId,
        'target': id ?? employeeId ?? accountId,
      },
    );
    return rows.isEmpty ? null : _link(rows.single);
  }

  Future<EmployeeLinkDto> create(
    TxSession tx,
    String id,
    String accountId,
    EmployeeDto employee,
  ) async {
    final rows = await tx.execute(
      Sql.named(
        'INSERT INTO $schema.account_employee_links '
        '(id, account_id, employee_id, company_id, location_id) VALUES '
        '(CAST(@id AS uuid), CAST(@account AS uuid), CAST(@employee AS uuid), '
        'CAST(@company AS uuid), CAST(@location AS uuid)) RETURNING $_columns',
      ),
      parameters: {
        'id': id,
        'account': accountId,
        'employee': employee.id,
        'company': companyId,
        'location': employee.locationId,
      },
    );
    return _link(rows.single);
  }

  Future<EmployeeLinkDto?> revoke(TxSession tx, EmployeeLinkDto link) async {
    final rows = await tx.execute(
      Sql.named(
        'UPDATE $schema.account_employee_links '
        'SET revoked_at = clock_timestamp(), version = version + 1 '
        'WHERE id = CAST(@id AS uuid) AND company_id = CAST(@company AS uuid) '
        'AND version = @version AND revoked_at IS NULL RETURNING $_columns',
      ),
      parameters: {
        'id': link.id,
        'company': companyId,
        'version': link.version,
      },
    );
    return rows.isEmpty ? null : _link(rows.single);
  }
}

EmployeeLinkDto _link(ResultRow row) {
  final data = row.toColumnMap();
  return EmployeeLinkDto(
    id: data['id'] as String,
    accountId: data['account_id'] as String,
    employeeId: data['employee_id'] as String,
    companyId: data['company_id'] as String,
    locationId: data['location_id'] as String,
    version: data['version'] as int,
    linkedAt: data['linked_at'] as DateTime,
    revokedAt: data['revoked_at'] as DateTime?,
  );
}
