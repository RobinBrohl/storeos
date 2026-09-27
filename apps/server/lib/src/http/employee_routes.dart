import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../application/employee_application.dart';
import 'api_support.dart';

class EmployeeRoutes {
  EmployeeRoutes(this.auth, this.application) {
    const root = '/api/v1/platform';
    router.get(
      '$root/employees',
      (Request request) async => jsonResponse(
        200,
        await application.list(await auth.authenticate(bearerToken(request))),
      ),
    );
    router.get(
      '$root/employees/me',
      (Request request) async => jsonResponse(
        200,
        await application.me(await auth.authenticate(bearerToken(request))),
      ),
    );
    router.get(
      '$root/employees/<id>',
      (Request request, String id) async => jsonResponse(
        200,
        await application.get(
          await auth.authenticate(bearerToken(request)),
          id,
        ),
      ),
    );
    router.post(
      '$root/employees',
      (Request request) async => jsonResponse(
        201,
        await application.create(
          await auth.authenticate(bearerToken(request)),
          await readJson(request),
        ),
      ),
    );
    router.post(
      '$root/employees/<id>/rename',
      (Request request, String id) async => jsonResponse(
        200,
        await application.rename(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      ),
    );
    router.post(
      '$root/employees/<id>/deactivate',
      (Request request, String id) async => jsonResponse(
        200,
        await application.deactivate(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      ),
    );
    router.get(
      '$root/employees/<id>/account-link',
      (Request request, String id) async => jsonResponse(
        200,
        await application.accountLink(
          await auth.authenticate(bearerToken(request)),
          id,
        ),
      ),
    );
    router.post(
      '$root/employees/<id>/account-link',
      (Request request, String id) async => jsonResponse(
        201,
        await application.link(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      ),
    );
    router.post(
      '$root/employee-links/<id>/revoke',
      (Request request, String id) async => jsonResponse(
        200,
        await application.unlink(
          await auth.authenticate(bearerToken(request)),
          id,
          await readJson(request),
        ),
      ),
    );
  }
  final AuthService auth;
  final EmployeeApplication application;
  final Router router = Router();
}
