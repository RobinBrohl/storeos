import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../stock/stock_count_service.dart';
import 'api_support.dart';

class StockCountRoutes {
  StockCountRoutes(AuthService auth, StockCountService service) {
    const root = '/api/v1/platform/locations/<locationId>/stock-counts';
    const self = '/api/v1/platform/me/stock-counts';
    router.get(
      '$root/assignees',
      (Request r, String locationId) async => jsonResponse(
        200,
        await service.assignees(
          await auth.authenticate(bearerToken(r)),
          locationId,
        ),
      ),
    );
    router.get(
      root,
      (Request r, String locationId) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          locationId,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      root,
      (Request r, String locationId) async => jsonResponse(
        201,
        await service.open(
          await auth.authenticate(bearerToken(r)),
          locationId,
          await readJson(r),
        ),
      ),
    );
    router.get(
      '$root/<countId>',
      (Request r, String locationId, String countId) async => jsonResponse(
        200,
        await service.get(
          await auth.authenticate(bearerToken(r)),
          locationId,
          countId,
        ),
      ),
    );
    router.get(
      '$root/<countId>/lines/<lineId>/rounds',
      (Request r, String locationId, String countId, String lineId) async =>
          jsonResponse(
            200,
            await service.history(
              await auth.authenticate(bearerToken(r)),
              locationId,
              countId,
              lineId,
              after: r.url.queryParameters['after'],
            ),
          ),
    );
    for (final kind in ['recount', 'approve', 'cancel']) {
      router.post(
        '$root/<countId>/$kind',
        (Request r, String locationId, String countId) async => jsonResponse(
          200,
          await service.command(
            await auth.authenticate(bearerToken(r)),
            locationId,
            countId,
            kind,
            await readJson(r),
          ),
        ),
      );
    }
    router.get(
      self,
      (Request r) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          service.database.locationId,
          self: true,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.get(
      '$self/<countId>',
      (Request r, String countId) async => jsonResponse(
        200,
        await service.get(
          await auth.authenticate(bearerToken(r)),
          service.database.locationId,
          countId,
          self: true,
        ),
      ),
    );
    router.get(
      '$self/<countId>/lines/<lineId>/rounds',
      (Request r, String countId, String lineId) async => jsonResponse(
        200,
        await service.history(
          await auth.authenticate(bearerToken(r)),
          service.database.locationId,
          countId,
          lineId,
          self: true,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      '$self/<countId>/lines/<lineId>/observations',
      (Request r, String countId, String lineId) async => jsonResponse(
        200,
        await service.observe(
          await auth.authenticate(bearerToken(r)),
          countId,
          lineId,
          await readJson(r),
        ),
      ),
    );
  }
  final router = Router();
}
