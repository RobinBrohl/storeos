import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/password_hasher.dart';
import '../application/password_verification_limiter.dart';
import '../identity/identity_repository.dart';
import '../infrastructure/auth_store.dart';
import '../organization/organization_repository.dart';
import 'platform_database.dart';
import 'platform_input.dart';

class IdentityService {
  IdentityService(
    this.database,
    this.passwordHasher, {
    PasswordVerificationLimiter? limiter,
  }) : repository = IdentityRepository(database),
       organization = OrganizationRepository(database),
       limiter = limiter ?? PasswordVerificationLimiter();

  final PlatformDatabase database;
  final PasswordHasher passwordHasher;
  final PasswordVerificationLimiter limiter;
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

  /// Changes the authenticated actor's own password after verifying the
  /// current one. The target is always the session account; no request field
  /// can select another account. Password update, all-session revocation and
  /// audit commit in one company-locked transaction.
  Future<void> changeOwnPassword(
    SessionPrincipal principal,
    Map<String, dynamic> input,
  ) async {
    late final ChangePasswordRequest request;
    try {
      request = ChangePasswordRequest.fromJson(input);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid request fields.',
      );
    }
    final problem = changePasswordProblem(request);
    if (problem != null) {
      throw PlatformFailure(400, 'invalid_request', problem);
    }
    await database.runAuthorized(principal, 'identity.self.password', (
      tx,
      actor,
    ) async {
      final credential = await repository.credential(tx, actor.id);
      if (credential == null) {
        throw const PlatformFailure(401, 'unauthorized', 'Session is invalid.');
      }
      if (!limiter.allows(actor.id)) {
        throw const PlatformFailure(429, 'rate_limited', 'Try again later.');
      }
      final valid = await passwordHasher.verify(
        request.currentPassword,
        credential.passwordHash,
      );
      if (!valid) {
        // The limiter is intentionally not transactional; this failure
        // remains recorded even though the transaction below rolls back.
        limiter.failure(actor.id);
        throw const PlatformFailure(
          422,
          'invalid_current_password',
          'Current password is incorrect.',
        );
      }
      final hash = await passwordHasher.hash(request.newPassword);
      final updated = await repository.setPassword(
        tx,
        userId: actor.id,
        passwordHash: hash,
        expectedVersion: credential.version,
      );
      await repository.revokeSessions(tx, actor.id);
      await database.audit(
        tx,
        actor,
        'identity.user.password_changed',
        'user',
        actor.id,
        locationId: actor.locationId,
        changes: {'version': updated.version},
      );
    });
    limiter.success(principal.id);
  }
}

void _checkVersion(int actual, int expected) {
  if (actual != expected) {
    throw const PlatformFailure(409, 'version_conflict', 'Version conflict.');
  }
}
