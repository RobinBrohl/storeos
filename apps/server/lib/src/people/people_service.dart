import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../platform/platform_database.dart';
import 'employee.dart';
import 'employee_repository.dart';

/// Public people port. Call with the coordinator's authorized transaction.
/// Only transport projections leave this module, never repositories or rows.
class PeopleService {
  PeopleService(PlatformDatabase database)
    : _repository = EmployeeRepository(database.schema, database.companyId);
  final EmployeeRepository _repository;

  Future<EmployeeDto> get(TxSession tx, String id) async {
    final result = await _repository.find(tx, id);
    if (result == null) {
      throw const PlatformFailure(404, 'not_found', 'Employee not found.');
    }
    return _view(result);
  }

  Future<List<EmployeeDto>> list(TxSession tx) async {
    final items = await _repository.list(tx);
    if (items.length > 200) {
      throw const PlatformFailure(
        409,
        'resource_limit',
        'Employee limit exceeded.',
      );
    }
    return items.map(_view).toList();
  }

  Future<EmployeeDto> create(
    TxSession tx,
    String id,
    String locationId,
    String name,
  ) async {
    if (await _repository.find(tx, id) != null) {
      throw const PlatformFailure(
        409,
        'already_exists',
        'Employee already exists.',
      );
    }
    if ((await list(tx)).length >= 200) {
      throw const PlatformFailure(
        409,
        'resource_limit',
        'Employee limit reached.',
      );
    }
    return _view(
      await _repository.create(tx, id, locationId, Employee.displayName(name)),
    );
  }

  void checkEditable(EmployeeDto employee, int expectedVersion) {
    if (employee.version != expectedVersion) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    try {
      Employee.requireEditable(employee.isActive);
    } on InactiveEmployee {
      throw const PlatformFailure(
        409,
        'inactive_employee',
        'Employee is inactive.',
      );
    }
  }

  Future<EmployeeDto> rename(
    TxSession tx,
    EmployeeDto employee,
    String name,
  ) async {
    final normalized = Employee.displayName(name);
    if (normalized == employee.displayName) return employee;
    return _updated(
      await _repository.update(tx, _model(employee), name: normalized),
    );
  }

  Future<EmployeeDto> deactivate(TxSession tx, EmployeeDto employee) async =>
      _updated(
        await _repository.update(tx, _model(employee), deactivate: true),
      );

  EmployeeDto _updated(Employee? result) {
    if (result == null) {
      throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
    }
    return _view(result);
  }
}

EmployeeDto _view(Employee value) => EmployeeDto(
  id: value.id,
  companyId: value.companyId,
  locationId: value.locationId,
  displayName: value.name,
  isActive: value.isActive,
  version: value.version,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
  assignedFrom: value.assignedFrom,
  assignedUntil: value.assignedUntil,
);
Employee _model(EmployeeDto value) => Employee(
  id: value.id,
  companyId: value.companyId,
  locationId: value.locationId,
  name: value.displayName,
  isActive: value.isActive,
  version: value.version,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
  assignedFrom: value.assignedFrom,
  assignedUntil: value.assignedUntil,
);
