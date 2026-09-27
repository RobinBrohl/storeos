import 'dart:convert';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:test/test.dart';

void main() {
  final json = {
    'id': 'employee',
    'companyId': 'company',
    'locationId': 'location',
    'displayName': 'Léa',
    'isActive': true,
    'version': 1,
    'createdAt': '2026-09-27T10:00:00.000Z',
    'updatedAt': '2026-09-27T10:00:00.000Z',
    'assignedFrom': '2026-09-27T10:00:00.000Z',
    'assignedUntil': null,
  };
  test('employee wire contract round trips with explicit UTC assignment', () {
    expect(
      EmployeeDto.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      ).toJson(),
      json,
    );
  });
  test('invalid activity intervals and unzoned timestamps fail closed', () {
    for (final change in [
      {'isActive': false},
      {'assignedUntil': '2026-09-27T11:00:00.000Z'},
      {'createdAt': '2026-09-27T10:00:00'},
      {'version': 0},
    ]) {
      expect(
        () => EmployeeDto.fromJson({...json, ...change}),
        throwsFormatException,
      );
    }
  });
  test('revoked link wire contract preserves identity and history', () {
    final link = EmployeeLinkDto(
      id: 'link',
      accountId: 'account',
      employeeId: 'employee',
      companyId: 'company',
      locationId: 'location',
      version: 2,
      linkedAt: DateTime.utc(2026),
      revokedAt: DateTime.utc(2026, 2),
    );
    expect(EmployeeLinkDto.fromJson(link.toJson()).toJson(), link.toJson());
  });
}
