import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../stock/stock_service.dart';
import 'api_support.dart';

class StockRoutes {
  StockRoutes(AuthService auth, StockService service) {
    const root = '/api/v1/platform/locations/<locationId>/stock';
    router.get(
      root,
      (Request r, String locationId) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          locationId,
          after: r.url.queryParameters['after'],
          q: r.url.queryParameters['q'],
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
      '$root/<levelId>',
      (Request r, String locationId, String levelId) async => jsonResponse(
        200,
        await service.get(
          await auth.authenticate(bearerToken(r)),
          locationId,
          levelId,
        ),
      ),
    );
    router.post(
      '$root/<levelId>/adjust',
      (Request r, String locationId, String levelId) async => jsonResponse(
        200,
        await service.adjust(
          await auth.authenticate(bearerToken(r)),
          locationId,
          levelId,
          await readJson(r),
        ),
      ),
    );
    router.get(
      '$root/<levelId>/movements',
      (Request r, String locationId, String levelId) async => jsonResponse(
        200,
        await service.listMovements(
          await auth.authenticate(bearerToken(r)),
          locationId,
          levelId,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
  }
  final Router router = Router();
}
