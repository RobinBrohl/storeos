import '../infrastructure/auth_store.dart';
import 'audit_repository.dart';
import 'platform_database.dart';

class AuditService {
  AuditService(this.database) : _repository = AuditRepository(database.schema);

  final PlatformDatabase database;
  final AuditRepository _repository;

  Future<Map<String, dynamic>> list(
    SessionPrincipal principal, {
    String? after,
  }) {
    final cursor = _auditCursor(after);
    return database.runAuthorized(principal, 'audit.read', (tx, actor) async {
      final rows = await _repository.page(
        tx,
        companyId: actor.companyId,
        beforeId: cursor,
      );
      final page = rows.take(50).toList();
      await database.audit(
        tx,
        actor,
        'audit.read',
        'audit',
        'collection',
        locationId: actor.locationId,
      );
      return {
        'items': page.map((entry) => entry.toJson()).toList(),
        'nextCursor': rows.length > 50 ? page.last.id.toString() : null,
      };
    });
  }
}

int? _auditCursor(String? after) {
  if (after == null || after.isEmpty) return null;
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(after)) {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
  final parsed = int.tryParse(after);
  if (parsed == null) {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
  return parsed;
}
