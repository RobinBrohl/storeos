import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../application/auth_service.dart';
import '../infrastructure/auth_store.dart';
import '../organization/organization_repository.dart';
import 'platform_database.dart';
import 'platform_models.dart';
import 'plugin_repository.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Applies approval policy and coordinates plugin state, audit and token writes
/// in one transaction. SQL and row mapping live in the repository.
class PluginService {
  PluginService(this.database)
    : _repository = PluginRepository(database),
      _organization = OrganizationRepository(database);

  final PlatformDatabase database;
  final PluginRepository _repository;
  final OrganizationRepository _organization;
  final Random _random = Random.secure();

  Future<Map<String, dynamic>> list(SessionPrincipal principal) =>
      database.runAuthorized(principal, 'plugins.read', (tx, actor) async {
        final plugins = await _repository.list(tx, actor.companyId);
        if (plugins.length > 100) {
          throw const PlatformFailure(
            503,
            'plugin_limit',
            'Plugin registry exceeds the P1 listing limit.',
          );
        }
        return {'plugins': plugins.map((plugin) => plugin.toJson()).toList()};
      });

  Future<Map<String, dynamic>> register(
    SessionPrincipal principal,
    Map<String, dynamic> body,
  ) {
    if (body.length != 1 || body['manifest'] is! Map<String, dynamic>) {
      throw const PlatformFailure(400, 'invalid_manifest', 'Invalid manifest.');
    }
    late final PluginManifest manifest;
    try {
      manifest = PluginManifest.fromJson(
        body['manifest'] as Map<String, dynamic>,
      );
    } on FormatException {
      throw const PlatformFailure(400, 'invalid_manifest', 'Invalid manifest.');
    }
    return database.runAuthorized(principal, 'plugins.write', (
      tx,
      actor,
    ) async {
      if (await _repository.count(tx, actor.companyId) >= 100) {
        throw const PlatformFailure(
          409,
          'plugin_limit',
          'Plugin registry limit reached.',
        );
      }
      if (await _repository.exists(tx, manifest.id)) {
        throw const PlatformFailure(409, 'already_exists', 'Plugin exists.');
      }
      await _repository.insert(tx, actor.companyId, manifest);
      await database.audit(
        tx,
        actor,
        'plugin.registered',
        'plugin',
        manifest.id,
        locationId: actor.locationId,
        changes: {'name': manifest.name, 'version': manifest.version},
      );
      return (await _repository.load(
        tx,
        manifest.id,
        actor.companyId,
      ))!.toJson();
    });
  }

  Future<Map<String, dynamic>> approve(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> body,
  ) {
    final version = _expectedVersion(body);
    final locationId = body['locationId'];
    if (locationId is! String ||
        !_uuidPattern.hasMatch(locationId) ||
        body.keys.toSet().difference({
          'expectedVersion',
          'locationId',
          'permissions',
          'subscriptions',
        }).isNotEmpty) {
      throw const PlatformFailure(400, 'invalid_request', 'Invalid approval.');
    }
    return database.runAuthorized(principal, 'plugins.write', (
      tx,
      actor,
    ) async {
      final registration = await _requiredRegistration(tx, id, actor.companyId);
      if (registration.version != version) {
        throw const PlatformFailure(
          409,
          'version_conflict',
          'Version changed.',
        );
      }
      if (registration.status == 'approved') {
        throw const PlatformFailure(
          409,
          'invalid_state',
          'Disable before reapproval.',
        );
      }
      final manifest = PluginManifest.fromJson(registration.manifest);
      final permissions = _approvedList(
        body['permissions'],
        manifest.permissions.toSet(),
      );
      final subscriptions = _approvedList(
        body['subscriptions'],
        manifest.subscriptions.toSet(),
      );
      if (subscriptions.isNotEmpty && !permissions.contains('events.read')) {
        throw const PlatformFailure(
          400,
          'invalid_permissions',
          'Event subscription requires events.read.',
        );
      }
      if (await _organization.location(tx, locationId) == null) {
        throw const PlatformFailure(404, 'not_found', 'Location not found.');
      }
      await _repository.revokeTokens(tx, id);
      await _repository.revokePendingInbox(tx, id);
      await _repository.approve(
        tx,
        id: id,
        locationId: locationId,
        permissions: permissions,
        subscriptions: subscriptions,
      );
      final token = base64UrlEncode(
        List<int>.generate(32, (_) => _random.nextInt(256)),
      ).replaceAll('=', '');
      final expiresAt = DateTime.now().toUtc().add(const Duration(hours: 24));
      await _repository.issueToken(
        tx,
        id: id,
        tokenHash: digestToken(token),
        expiresAt: expiresAt,
      );
      await database.audit(
        tx,
        actor,
        'plugin.approved',
        'plugin',
        id,
        locationId: locationId.toLowerCase(),
        changes: {
          'status': 'approved',
          'locationId': locationId.toLowerCase(),
          'permissions': permissions,
          'subscriptions': subscriptions,
          'version': version + 1,
        },
      );
      return {
        'plugin': (await _repository.load(tx, id, actor.companyId))!.toJson(),
        'token': token,
        'expiresAt': expiresAt.toIso8601String(),
      };
    });
  }

  Future<Map<String, dynamic>> disable(
    SessionPrincipal principal,
    String id,
    Map<String, dynamic> body,
  ) {
    final version = _expectedVersion(body);
    if (body.length != 1) {
      throw const PlatformFailure(
        400,
        'invalid_request',
        'Invalid disable request.',
      );
    }
    return database.runAuthorized(principal, 'plugins.write', (
      tx,
      actor,
    ) async {
      final registration = await _requiredRegistration(tx, id, actor.companyId);
      if (registration.version != version) {
        throw const PlatformFailure(
          409,
          'version_conflict',
          'Version changed.',
        );
      }
      if (registration.status != 'approved') {
        throw const PlatformFailure(
          409,
          'invalid_state',
          'Plugin is not approved.',
        );
      }
      await _repository.revokeTokens(tx, id);
      await _repository.revokePendingInbox(tx, id);
      await _repository.disable(tx, id);
      await database.audit(
        tx,
        actor,
        'plugin.disabled',
        'plugin',
        id,
        locationId: registration.locationId,
        changes: {'status': 'disabled', 'version': version + 1},
      );
      return (await _repository.load(tx, id, actor.companyId))!.toJson();
    });
  }

  Future<Map<String, dynamic>> organization(String? token) =>
      database.pool.runTx((tx) async {
        final grant = await _authenticate(tx, token, 'organization.read');
        return _organization.pluginProjection(
          tx,
          companyId: grant.companyId,
          locationId: grant.locationId,
        );
      });

  Future<Map<String, dynamic>> events(String? token, {String? after}) {
    final cursor = _inboxCursor(after);
    return database.pool.runTx((tx) async {
      final grant = await _authenticate(tx, token, 'events.read');
      final rows = await _repository.inboxPage(tx, grant, afterId: cursor);
      final page = rows.take(50).toList();
      return {
        'items': page.map((event) => event.toJson()).toList(),
        'nextCursor': rows.length > 50 ? page.last.inboxId.toString() : null,
      };
    });
  }

  Future<void> acknowledge(String? token, String eventId) {
    if (!_uuidPattern.hasMatch(eventId)) {
      throw const PlatformFailure(400, 'invalid_id', 'Invalid event id.');
    }
    return database.pool.runTx((tx) async {
      final grant = await _authenticate(tx, token, 'events.read');
      final state = await _repository.lockDelivery(tx, grant.id, eventId);
      if (state == null ||
          state.status == 'revoked' ||
          state.companyId != grant.companyId ||
          (state.locationId != null && state.locationId != grant.locationId) ||
          state.recordedAt.isBefore(grant.approvedAt) ||
          !grant.subscriptions.contains(state.type)) {
        throw const PlatformFailure(404, 'not_found', 'Event not found.');
      }
      if (state.status == 'pending') {
        await _repository.acknowledge(tx, grant.id, eventId);
      }
    });
  }

  Future<PluginRegistration> _requiredRegistration(
    TxSession tx,
    String id,
    String companyId,
  ) async {
    final registration = await _repository.lock(tx, id, companyId);
    if (registration == null) {
      throw const PlatformFailure(404, 'not_found', 'Plugin not found.');
    }
    return registration;
  }

  Future<PluginGrant> _authenticate(
    TxSession tx,
    String? token,
    String permission,
  ) async {
    if (token == null || !_tokenPattern.hasMatch(token)) {
      throw const PlatformFailure(
        401,
        'unauthorized',
        'Plugin token required.',
      );
    }
    // The same company lock gates admin approval/disable in runAuthorized.
    // Read the token only after that lock to avoid stale approval races.
    await _repository.lockCompany(tx);
    final grant = await _repository.activeGrant(
      tx,
      tokenHash: digestToken(token),
      companyId: database.companyId,
    );
    if (grant == null) {
      throw const PlatformFailure(401, 'unauthorized', 'Plugin token invalid.');
    }
    if (!grant.permissions.contains(permission)) {
      throw const PlatformFailure(403, 'forbidden', 'Access denied.');
    }
    return grant;
  }
}

int _expectedVersion(Map<String, dynamic> body) {
  final value = body['expectedVersion'];
  if (value is! int || value <= 0) {
    throw const PlatformFailure(400, 'invalid_version', 'Invalid version.');
  }
  return value;
}

List<String> _approvedList(Object? input, Set<String> declared) {
  if (input is! List || input.length > declared.length) {
    throw const PlatformFailure(
      400,
      'invalid_permissions',
      'Invalid approval.',
    );
  }
  final values = <String>[];
  for (final item in input) {
    if (item is! String || !declared.contains(item) || values.contains(item)) {
      throw const PlatformFailure(
        400,
        'invalid_permissions',
        'Invalid approval.',
      );
    }
    values.add(item);
  }
  return values;
}

int? _inboxCursor(String? after) {
  if (after == null || after.isEmpty) return null;
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(after)) {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
  final value = int.tryParse(after);
  if (value == null) {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
  return value;
}
