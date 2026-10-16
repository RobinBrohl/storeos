import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../application/shift_swap_application.dart';
import '../platform/platform_database.dart';
import 'api_support.dart';

/// Authenticated transport only; participant intent is resolved by Application.
class ShiftSwapRoutes {
  ShiftSwapRoutes(AuthService auth, ShiftSwapApplication app) {
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
      final after = r.url.queryParameters['after'];
      if (after != null && after.length > 2048) {
        throw const PlatformFailure(
          400,
          'invalid_cursor',
          'Invalid swap cursor.',
        );
      }
    }

    router.get('/api/v1/platform/employee-home/shifts/<id>/swap-colleagues', (
      Request r,
      String id,
    ) async {
      final p = await auth.authenticate(bearerToken(r));
      query(r, {'after'});
      return jsonResponse(
        200,
        (await app.colleagues(
          p,
          id,
          after: r.url.queryParameters['after'],
        )).toJson(),
      );
    });
    for (final self in [true, false]) {
      final root = self
          ? '/api/v1/platform/me/shift-swaps'
          : '/api/v1/platform/locations/<location>/shift-swaps';
      Future<Response> list(Request r, {String? location}) async {
        final p = await auth.authenticate(bearerToken(r));
        query(r, {'status', 'after', if (self) 'direction'});
        return jsonResponse(
          200,
          (await app.list(
            p,
            self: self,
            location: location,
            status: r.url.queryParameters['status'],
            direction: r.url.queryParameters['direction'],
            after: r.url.queryParameters['after'],
          )).toJson(),
        );
      }

      Future<Response> detail(Request r, String id, {String? location}) async {
        final p = await auth.authenticate(bearerToken(r));
        query(r, {});
        return jsonResponse(
          200,
          (await app.detail(p, id, self: self, location: location)).toJson(),
        );
      }

      Future<Response> history(Request r, String id, {String? location}) async {
        final p = await auth.authenticate(bearerToken(r));
        query(r, {'after'});
        return jsonResponse(
          200,
          await app.historyPage(
            p,
            id,
            self: self,
            location: location,
            after: r.url.queryParameters['after'],
          ),
        );
      }

      Future<Response> command(
        Request r,
        String? id,
        String kind, {
        String? location,
      }) async {
        final p = await auth.authenticate(bearerToken(r));
        query(r, {});
        final body = await readJson(r, limit: 8192, rejectDuplicateNames: true);
        final result = kind == 'withdraw'
            ? await app.withdraw(p, id!, body)
            : await app.command(
                p,
                id,
                kind,
                body,
                self: self,
                location: location,
              );
        return jsonResponse(result.json['statusCode'] as int, result.toJson());
      }

      if (self) {
        router.get(root, (Request r) => list(r));
        router.post(root, (Request r) => command(r, null, 'request'));
        router.get('$root/<id>', (Request r, String id) => detail(r, id));
        router.get(
          '$root/<id>/history',
          (Request r, String id) => history(r, id),
        );
        router.get('$root/<id>/counterparts', (Request r, String id) async {
          final p = await auth.authenticate(bearerToken(r));
          query(r, {'after'});
          return jsonResponse(
            200,
            (await app.counterparts(
              p,
              id,
              after: r.url.queryParameters['after'],
            )).toJson(),
          );
        });
        router.get('$root/<id>/counterparts/<shift>', (
          Request r,
          String id,
          String shift,
        ) async {
          final p = await auth.authenticate(bearerToken(r));
          query(r, {});
          return jsonResponse(
            200,
            (await app.counterpart(p, id, shift)).toJson(),
          );
        });
        for (final kind in ['offer', 'confirm', 'decline', 'withdraw']) {
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
        router.get(
          '$root/<id>/history',
          (Request r, String location, String id) =>
              history(r, id, location: location),
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
