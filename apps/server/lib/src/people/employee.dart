/// Operational profile rules, independent of transport and persistence.
class Employee {
  const Employee({
    required this.id,
    required this.companyId,
    required this.locationId,
    required this.name,
    required this.isActive,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.assignedFrom,
    required this.assignedUntil,
  });

  final String id, companyId, locationId, name;
  final bool isActive;
  final int version;
  final DateTime createdAt, updatedAt, assignedFrom;
  final DateTime? assignedUntil;

  static String displayName(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name.length > 120 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const FormatException('Invalid employee display name.');
    }
    return name;
  }

  static void requireEditable(bool active) {
    if (!active) throw const InactiveEmployee();
  }
}

class InactiveEmployee implements Exception {
  const InactiveEmployee();
}
