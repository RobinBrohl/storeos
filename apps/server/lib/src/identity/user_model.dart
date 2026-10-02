class UserCredential {
  const UserCredential({required this.passwordHash, required this.version});

  final String passwordHash;
  final int version;
}

class UserRecord {
  const UserRecord({
    required this.id,
    required this.username,
    required this.companyId,
    required this.locationId,
    required this.role,
    required this.isActive,
    required this.version,
  });

  final String id;
  final String username;
  final String companyId;
  final String locationId;
  final String role;
  final bool isActive;
  final int version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'companyId': companyId,
    'locationId': locationId,
    'role': role,
    'isActive': isActive,
    'version': version,
  };
}
