import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../platform/platform_database.dart';
import '../production/preparation_batch_service.dart';
import 'api_support.dart';

class PreparationBatchRoutes {
  PreparationBatchRoutes(AuthService auth, PreparationBatchService service) {
    void query(Request r, Set<String> allowed) {
      if (r.url.queryParametersAll.entries.any(
        (e) => !allowed.contains(e.key) || e.value.length != 1,
      )) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Unexpected or duplicate query fields.',
        );
      }
    }

    for (final self in [true, false]) {
      final root =
          '/api/v1/platform/production/${self ? 'self' : 'manage'}/locations/<locationId>/batches';
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
      router.get('$root/<batchId>', (
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
      router.get('$root/<batchId>/recipe', (
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
      final commands = self
          ? {'complete': 'complete', 'cancel': 'employee_cancel'}
          : {'cancel': 'manager_cancel', 'count-corrections': 'count_correct'};
      for (final c in commands.entries) {
        router.post('$root/<batchId>/${c.key}', (
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
            await service.command(p, location, id, c.value, body, self: self),
          );
        });
      }
      if (self) {
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
            await service.command(p, location, null, 'open', body),
          );
        });
      }
    }
  }
  final Router router = Router();
}
