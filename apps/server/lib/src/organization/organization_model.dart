class CompanyRecord {
  const CompanyRecord(this.id, this.name, this.version);

  final String id;
  final String? name;
  final int version;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'version': version};
}

class LocationRecord {
  const LocationRecord(this.id, this.companyId, this.name, this.version);

  final String id;
  final String companyId;
  final String? name;
  final int version;

  Map<String, dynamic> toJson() => {
    'id': id,
    'companyId': companyId,
    'name': name,
    'version': version,
  };
}
