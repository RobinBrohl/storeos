import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../platform/platform_database.dart';
import '../purchasing/purchasing_service.dart';
import 'api_support.dart';

class PurchasingRoutes {
  PurchasingRoutes(AuthService auth, PurchasingService service) {
    void query(Request r, Set<String> fields) {
      if (r.url.queryParametersAll.entries.any(
        (e) => !fields.contains(e.key) || e.value.length != 1,
      )) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Unexpected or duplicate query parameters.',
        );
      }
    }

    const root = '/api/v1/platform/purchasing';
    final supplier = '$root/suppliers',
        orders = '$root/locations/<locationId>/orders';
    router.get(supplier, (Request r) async {
      query(r, {'status', 'q', 'after'});
      return jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          null,
          supplier: true,
          status: r.url.queryParameters['status'],
          q: r.url.queryParameters['q'],
          after: r.url.queryParameters['after'],
        ),
      );
    });
    router.get('$supplier/<id>', (Request r, String id) async {
      query(r, {});
      return jsonResponse(
        200,
        await service.detail(
          await auth.authenticate(bearerToken(r)),
          null,
          id,
          supplier: true,
        ),
      );
    });
    router.get('$supplier/<id>/history', (Request r, String id) async {
      query(r, {'after'});
      return jsonResponse(
        200,
        await service.history(
          await auth.authenticate(bearerToken(r)),
          null,
          id,
          supplier: true,
          after: r.url.queryParameters['after'],
        ),
      );
    });
    Future<Response> supplierWrite(Request r, String? id, String kind) async {
      query(r, {});
      final p = await auth.authenticate(bearerToken(r));
      return jsonResponse(
        kind == 'supplier_create' ? 201 : 200,
        await service.command(
          p,
          null,
          id,
          kind,
          await readJson(r, limit: 16384, rejectDuplicateNames: true),
        ),
      );
    }

    router.post(
      supplier,
      (Request r) => supplierWrite(r, null, 'supplier_create'),
    );
    router.put(
      '$supplier/<id>',
      (Request r, String id) => supplierWrite(r, id, 'supplier_edit'),
    );
    router.post(
      '$supplier/<id>/retire',
      (Request r, String id) => supplierWrite(r, id, 'supplier_retire'),
    );
    router.get('$root/locations/<locationId>/article-selections', (
      Request r,
      String location,
    ) async {
      query(r, {'q', 'after'});
      return jsonResponse(
        200,
        await service.articleSelections(
          await auth.authenticate(bearerToken(r)),
          location,
          q: r.url.queryParameters['q'],
          after: r.url.queryParameters['after'],
        ),
      );
    });
    router.get(orders, (Request r, String location) async {
      query(r, {'status', 'supplierId', 'q', 'after'});
      return jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          location,
          supplier: false,
          status: r.url.queryParameters['status'],
          supplierId: r.url.queryParameters['supplierId'],
          q: r.url.queryParameters['q'],
          after: r.url.queryParameters['after'],
        ),
      );
    });
    router.get('$orders/<id>', (Request r, String location, String id) async {
      query(r, {});
      return jsonResponse(
        200,
        await service.detail(
          await auth.authenticate(bearerToken(r)),
          location,
          id,
          supplier: false,
        ),
      );
    });
    router.get('$orders/<id>/history', (
      Request r,
      String location,
      String id,
    ) async {
      query(r, {'after'});
      return jsonResponse(
        200,
        await service.history(
          await auth.authenticate(bearerToken(r)),
          location,
          id,
          supplier: false,
          after: r.url.queryParameters['after'],
        ),
      );
    });
    Future<Response> orderWrite(
      Request r,
      String location,
      String? id,
      String kind,
    ) async {
      query(r, {});
      final p = await auth.authenticate(bearerToken(r));
      return jsonResponse(
        kind == 'order_create' ? 201 : 200,
        await service.command(
          p,
          location,
          id,
          kind,
          await readJson(
            r,
            limit: kind == 'order_save' ? 262144 : 16384,
            rejectDuplicateNames: true,
          ),
        ),
      );
    }

    router.post(
      orders,
      (Request r, String location) =>
          orderWrite(r, location, null, 'order_create'),
    );
    router.put(
      '$orders/<id>',
      (Request r, String location, String id) =>
          orderWrite(r, location, id, 'order_save'),
    );
    for (final action in ['issue', 'cancel', 'close']) {
      router.post(
        '$orders/<id>/$action',
        (Request r, String location, String id) =>
            orderWrite(r, location, id, 'order_$action'),
      );
    }
  }
  final Router router = Router();
}
