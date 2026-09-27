import '../application/password_hasher.dart';
import '../identity/identity_repository.dart';
import '../infrastructure/auth_store.dart';
import '../organization/organization_repository.dart';
import 'platform_database.dart';
import 'platform_input.dart';

class IdentityService {
  IdentityService(this.database, this.passwordHasher)
    : repository = IdentityRepository(database),
      organization = OrganizationRepository(database);

  final PlatformDatabase database;
  final PasswordHasher passwordHasher;
  final IdentityRepository repository;
  final OrganizationRepository organization;

  Future<Map<String, dynamic>> context(SessionPrincipal principal) =>
      database.runAuthorized(
        principal,
        'context.read',
        (tx, actor) async => {
          'userId': actor.id,
          'companyId': actor.companyId,
          'locationId': actor.locationId,
          'role': actor.role,
          'permissions': permissionsForRole(actor.role),
        },
      );

  Future<Map<String, dynamic>> listUsers(SessionPrincipal principal) =>
      database.runAuthorized(principal, 'identity.read', (tx, actor) async {
        final users = await repository.users(tx);
        if (users.length > 200) {
          throw const PlatformFailure(
            409,
            'resource_limit',
            'Too many users for this API.',
          );
        }
        return {'users': users.map((user) => user.toJson()).toList()};
      });

  Future<Map<String, dynamic>> createUser(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) async {
    requireFields(
      input,
      required: {'id', 'username', 'password', 'locationId', 'role'},
    );
    final id = requireUuid(input, 'id');
    final username = requireUsername(input);
    final password = requirePassword(input);
    final locationId = requireUuid(input, 'locationId');
    final role = requireRole(input);
    return database.runAuthorized(principal, 'identity.write', (
      tx,
      actor,
    ) async {
      final location = await organization.location(tx, locationId);
      if (location?.name == null) {
        throw const PlatformFailure(404, 'not_found', 'Location not found.');
      }
      if (await repository.user(tx, id) != null ||
          await repository.usernameExists(tx, username.toLowerCase())) {
        throw const PlatformFailure(
          409,
          'already_exists',
          'User already exists.',
        );
      }
      final users = await repository.users(tx);
      if (users.length >= 200) {
        throw const PlatformFailure(
          409,
          'resource_limit',
          'User limit reached.',
        );
      }
      final hash = await passwordHasher.hash(password);
      final created = await repository.createUser(
        tx,
        id: id,
        username: username,
        usernameKey: username.toLowerCase(),
        passwordHash: hash,
        locationId: locationId,
        role: role,
      );
      await database.audit(
        tx,
        actor,
        'identity.user.created',
        'user',
        id,
        locationId: locationId,
        changes: {
          'username': username,
          'role': role,
          'isActive': true,
          'locationId': locationId,
          'version': created.version,
        },
      );
      return created.toJson();
    });
  }

  Future<Map<String, dynamic>> updateUser(
    SessionPrincipal principal,
    String userId,
    Map<String, dynamic> input,
  ) async {
    final id = requireUuid({'id': userId}, 'id');
    requireFields(input, required: {'role', 'isActive', 'expectedVersion'});
    final role = requireRole(input);
    final isActive = requireActive(input);
    final expectedVersion = requireVersion(input);
    return database.runAuthorized(principal, 'identity.write', (
      tx,
      actor,
    ) async {
      final current = await repository.user(tx, id);
      if (current == null) {
        throw const PlatformFailure(404, 'not_found', 'User not found.');
      }
      _checkVersion(current.version, expectedVersion);
      if (current.role == role && current.isActive == isActive) {
        return current.toJson();
      }
      if (current.isActive &&
          current.role == 'admin' &&
          (!isActive || role != 'admin') &&
          await repository.activeAdminCount(tx) <= 1) {
        throw const PlatformFailure(
          409,
          'last_admin',
          'The last active admin cannot be removed.',
        );
      }
      final updated = await repository.setRoleAndActive(
        tx,
        userId: id,
        role: role,
        isActive: isActive,
        expectedVersion: expectedVersion,
      );
      await repository.revokeSessions(tx, id);
      await database.audit(
        tx,
        actor,
        'identity.user.updated',
        'user',
        id,
        locationId: current.locationId,
        changes: {
          'oldRole': current.role,
          'role': role,
          'oldIsActive': current.isActive,
          'isActive': isActive,
          'version': updated.version,
        },
      );
      return updated.toJson();
    });
  }

  Future<Map<String, dynamic>> setPassword(
    SessionPrincipal principal,
    String userId,
    Map<String, dynamic> input,
  ) async {
    final id = requireUuid({'id': userId}, 'id');
    requireFields(input, required: {'password', 'expectedVersion'});
    final password = requirePassword(input);
    final expectedVersion = requireVersion(input);
    return database.runAuthorized(principal, 'identity.write', (
      tx,
      actor,
    ) async {
      final current = await repository.user(tx, id);
      if (current == null) {
        throw const PlatformFailure(404, 'not_found', 'User not found.');
      }
      _checkVersion(current.version, expectedVersion);
      final hash = await passwordHasher.hash(password);
      final updated = await repository.setPassword(
        tx,
        userId: id,
        passwordHash: hash,
        expectedVersion: expectedVersion,
      );
      await repository.revokeSessions(tx, id);
      await database.audit(
        tx,
        actor,
        'identity.user.password_reset',
        'user',
        id,
        locationId: current.locationId,
        changes: {'version': updated.version},
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
