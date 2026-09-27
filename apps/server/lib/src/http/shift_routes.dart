import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../application/shift_application.dart';
import 'api_support.dart';

class ShiftRoutes {
  ShiftRoutes(AuthService auth, ShiftApplication app) {
    const root = '/api/v1/platform/shifts';
    router.post(
      root,
      (Request r) async => jsonResponse(
        201,
        await app.create(
          await auth.authenticate(bearerToken(r)),
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/edit',
      (Request r, String id) async => jsonResponse(
        200,
        await app.edit(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/publish',
      (Request r, String id) async => jsonResponse(
        200,
        await app.publish(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
    for (final self in [false, true]) {
      final path = self ? '/api/v1/platform/employee-home/shifts' : root;
      router.get(
        path,
        (Request r) async => jsonResponse(
          200,
          await app.list(
            await auth.authenticate(bearerToken(r)),
            self: self,
            after: r.url.queryParameters['after'],
          ),
        ),
      );
      router.get(
        '$path/<id>',
        (Request r, String id) async => jsonResponse(
          200,
          await app.get(
            await auth.authenticate(bearerToken(r)),
            id,
            self: self,
          ),
        ),
      );
      router.get(
        '$path/<id>/tasks/<task>',
        (Request r, String id, String task) async => jsonResponse(
          200,
          await app.get(
            await auth.authenticate(bearerToken(r)),
            id,
            self: self,
            taskId: task,
          ),
        ),
      );
    }
  }
  final Router router = Router();
}
