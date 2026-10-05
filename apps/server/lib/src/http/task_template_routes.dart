import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../tasks/task_template_service.dart';
import 'api_support.dart';
import '../platform/platform_database.dart';

class TaskTemplateRoutes {
  TaskTemplateRoutes(AuthService auth, TaskTemplateService service) {
    const root = '/api/v1/platform/task-templates';
    router.get(
      root,
      (Request r) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      root,
      (Request r) async => jsonResponse(
        201,
        await service.create(
          await auth.authenticate(bearerToken(r)),
          await readJson(r),
        ),
      ),
    );
    router.get(
      '$root/<id>',
      (Request r, String id) async => jsonResponse(
        200,
        await service.get(await auth.authenticate(bearerToken(r)), id),
      ),
    );
    router.get(
      '$root/<id>/revisions',
      (Request r, String id) async => jsonResponse(
        200,
        await service.revisions(
          await auth.authenticate(bearerToken(r)),
          id,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      '$root/<id>/revisions',
      (Request r, String id) async => jsonResponse(
        201,
        await service.newDraft(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
    router.get(
      '$root/<id>/revisions/<revision>',
      (Request r, String id, String revision) async => jsonResponse(
        200,
        await service.revision(
          await auth.authenticate(bearerToken(r)),
          id,
          revision,
        ),
      ),
    );
    router.get('$root/<id>/revisions/<revision>/planogram', (
      Request r,
      String id,
      String revision,
    ) async {
      if (r.url.hasQuery) {
        throw const PlatformFailure(
          400,
          'invalid_query',
          'Template layout reads accept no query parameters.',
        );
      }
      return jsonResponse(
        200,
        await service.planogram(
          await auth.authenticate(bearerToken(r)),
          id,
          revision,
        ),
      );
    });
    router.post(
      '$root/<id>/revisions/<revision>/edit',
      (Request r, String id, String revision) async => jsonResponse(
        200,
        await service.edit(
          await auth.authenticate(bearerToken(r)),
          id,
          revision,
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/revisions/<revision>/publish',
      (Request r, String id, String revision) async => jsonResponse(
        200,
        await service.publish(
          await auth.authenticate(bearerToken(r)),
          id,
          revision,
          await readJson(r),
        ),
      ),
    );
  }
  final Router router = Router();
}
