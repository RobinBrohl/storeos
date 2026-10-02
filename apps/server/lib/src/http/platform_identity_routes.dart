import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../platform/identity_service.dart';
import '../platform/organization_service.dart';
import 'api_support.dart';

/// Thin HTTP adapter for P1 organization and user administration.
class PlatformIdentityRoutes {
  PlatformIdentityRoutes({
    required this.auth,
    required this.organization,
    required this.identity,
  }) {
    router.get('/api/v1/platform/context', _context);
    router.get('/api/v1/platform/organization', _organization);
    router.post('/api/v1/platform/organization/setup', _setup);
    router.post('/api/v1/platform/company', _renameCompany);
    router.post('/api/v1/platform/locations', _createLocation);
    router.post('/api/v1/platform/locations/<id>', _renameLocation);
    router.get('/api/v1/platform/users', _users);
    router.post('/api/v1/platform/users', _createUser);
    router.post('/api/v1/platform/users/<id>', _updateUser);
    router.post('/api/v1/platform/users/<id>/password', _setPassword);
    router.post('/api/v1/platform/profile/password', _changeOwnPassword);
  }

  final AuthService auth;
  final OrganizationService organization;
  final IdentityService identity;
  final Router router = Router();

  Future<Response> _context(Request request) async => jsonResponse(
    200,
    await identity.context(await auth.authenticate(bearerToken(request))),
  );

  Future<Response> _organization(Request request) async => jsonResponse(
    200,
    await organization.read(await auth.authenticate(bearerToken(request))),
  );

  Future<Response> _setup(Request request) async => jsonResponse(
    200,
    await organization.setup(
      await auth.authenticate(bearerToken(request)),
      await readJson(request),
    ),
  );

  Future<Response> _renameCompany(Request request) async => jsonResponse(
    200,
    await organization.renameCompany(
      await auth.authenticate(bearerToken(request)),
      await readJson(request),
    ),
  );

  Future<Response> _createLocation(Request request) async => jsonResponse(
    201,
    await organization.createLocation(
      await auth.authenticate(bearerToken(request)),
      await readJson(request),
    ),
  );

  Future<Response> _renameLocation(Request request, String id) async =>
      jsonResponse(
        200,
        await organization.renameLocation(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      );

  Future<Response> _users(Request request) async => jsonResponse(
    200,
    await identity.listUsers(await auth.authenticate(bearerToken(request))),
  );

  Future<Response> _createUser(Request request) async => jsonResponse(
    201,
    await identity.createUser(
      await auth.authenticate(bearerToken(request)),
      await readJson(request),
    ),
  );

  Future<Response> _updateUser(Request request, String id) async =>
      jsonResponse(
        200,
        await identity.updateUser(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      );

  Future<Response> _setPassword(Request request, String id) async =>
      jsonResponse(
        200,
        await identity.setPassword(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      );

  Future<Response> _changeOwnPassword(Request request) async {
    await identity.changeOwnPassword(
      await auth.authenticate(bearerToken(request)),
      await readJson(request),
    );
    return Response(204);
  }
}
