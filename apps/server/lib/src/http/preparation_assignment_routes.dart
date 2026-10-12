import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../platform/platform_database.dart';
import '../production/preparation_assignment_service.dart';
import 'api_support.dart';

class PreparationAssignmentRoutes {
  PreparationAssignmentRoutes(
    AuthService auth,
    PreparationAssignmentService service,
  ) {
    void query(Request r, Set<String> fields) {
      if (r.url.queryParametersAll.entries.any(
        (e) => !fields.contains(e.key) || e.value.length != 1,
      )) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Unexpected or duplicate query fields.',
        );
      }
    }

    for (final self in [false, true]) {
      final root =
          '/api/v1/platform/production/${self ? 'self' : 'manage'}/locations/<locationId>/preparation-assignments';
      router.get(root, (Request r, String location) async {
        query(r, {'status', 'after'});
        return jsonResponse(
          200,
          await service.list(
            await auth.authenticate(bearerToken(r)),
            location,
            self: self,
            status: r.url.queryParameters['status'],
            after: r.url.queryParameters['after'],
          ),
        );
      });
      if (!self) {
        router.get('$root/assignees', (Request r, String location) async {
          query(r, {'after'});
          return jsonResponse(
            200,
            await service.assignees(
              await auth.authenticate(bearerToken(r)),
              location,
              after: r.url.queryParameters['after'],
            ),
          );
        });
        router.post(root, (Request r, String location) async {
          query(r, {});
          final p = await auth.authenticate(bearerToken(r));
          final body = await readJson(
            r,
            limit: 16384,
            rejectDuplicateNames: true,
          );
          return jsonResponse(
            201,
            await service.command(p, location, null, 'create', body),
          );
        });
      }
      router.get('$root/<assignmentId>', (
        Request r,
        String location,
        String id,
      ) async {
        query(r, {});
        return jsonResponse(
          200,
          await service.detail(
            await auth.authenticate(bearerToken(r)),
            location,
            id,
            self: self,
          ),
        );
      });
      router.get('$root/<assignmentId>/recipe', (
        Request r,
        String location,
        String id,
      ) async {
        query(r, {});
        return jsonResponse(
          200,
          await service.recipe(
            await auth.authenticate(bearerToken(r)),
            location,
            id,
            self: self,
          ),
        );
      });
      router.get('$root/<assignmentId>/history', (
        Request r,
        String location,
        String id,
      ) async {
        query(r, {});
        return jsonResponse(
          200,
          await service.history(
            await auth.authenticate(bearerToken(r)),
            location,
            id,
            self: self,
          ),
        );
      });
      final kind = self ? 'start' : 'withdraw';
      router.post('$root/<assignmentId>/$kind', (
        Request r,
        String location,
        String id,
      ) async {
        query(r, {});
        final p = await auth.authenticate(bearerToken(r));
        final body = await readJson(
          r,
          limit: 16384,
          rejectDuplicateNames: true,
        );
        return jsonResponse(
          200,
          await service.command(p, location, id, kind, body, self: self),
        );
      });
    }
  }
  final Router router = Router();
}
