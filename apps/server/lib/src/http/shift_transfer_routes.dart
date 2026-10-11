import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../application/shift_transfer_application.dart';
import '../platform/platform_database.dart';
import 'api_support.dart';

class ShiftTransferRoutes {
  ShiftTransferRoutes(AuthService auth, ShiftTransferApplication app) {
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

    router.get(
      '/api/v1/platform/employee-home/shifts/<id>/transfer-recipients',
      (Request r, String id) async {
        query(r, {'after'});
        return jsonResponse(
          200,
          await app.recipients(
            await auth.authenticate(bearerToken(r)),
            id,
            after: r.url.queryParameters['after'],
          ),
        );
      },
    );
    for (final self in [true, false]) {
      final root = self
          ? '/api/v1/platform/me/shift-transfers'
          : '/api/v1/platform/locations/<location>/shift-transfers';
      Future<Response> list(Request r, {String? location}) async {
        query(r, {'status', 'after', if (self) 'direction'});
        return jsonResponse(
          200,
          await app.list(
            await auth.authenticate(bearerToken(r)),
            self: self,
            location: location,
            status: r.url.queryParameters['status'],
            direction: r.url.queryParameters['direction'],
            after: r.url.queryParameters['after'],
          ),
        );
      }

      Future<Response> detail(Request r, String id, {String? location}) async {
        query(r, {});
        return jsonResponse(
          200,
          await app.detail(
            await auth.authenticate(bearerToken(r)),
            id,
            self: self,
            location: location,
          ),
        );
      }

      Future<Response> command(
        Request r,
        String? id,
        String kind, {
        String? location,
      }) async {
        query(r, {});
        final p = await auth.authenticate(bearerToken(r));
        final body = await readJson(r, limit: 8192, rejectDuplicateNames: true);
        return jsonResponse(
          kind == 'propose' ? 201 : 200,
          await app.command(p, id, kind, body, self: self, location: location),
        );
      }

      if (self) {
        router.get(root, (Request r) => list(r));
        router.get('$root/<id>', (Request r, String id) => detail(r, id));
        router.post(root, (Request r) => command(r, null, 'propose'));
        for (final kind in ['accept', 'decline', 'withdraw']) {
          router.post(
            '$root/<id>/$kind',
            (Request r, String id) => command(r, id, kind),
          );
        }
      } else {
        router.get(
          root,
          (Request r, String location) => list(r, location: location),
        );
        router.get(
          '$root/<id>',
          (Request r, String location, String id) =>
              detail(r, id, location: location),
        );
        for (final kind in ['approve', 'reject']) {
          router.post(
            '$root/<id>/$kind',
            (Request r, String location, String id) =>
                command(r, id, 'manager_$kind', location: location),
          );
        }
      }
    }
  }
  final Router router = Router();
}
