import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../inventory/article_assortment_service.dart';
import 'api_support.dart';

class ArticleAssortmentRoutes {
  ArticleAssortmentRoutes(AuthService auth, ArticleAssortmentService service) {
    const root = '/api/v1/platform/locations/<locationId>/assortment';
    router.get(
      root,
      (Request r, String locationId) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          locationId,
          after: r.url.queryParameters['after'],
          q: r.url.queryParameters['q'],
          active: r.url.queryParameters['active'],
        ),
      ),
    );
    router.post(
      root,
      (Request r, String locationId) async => jsonResponse(
        201,
        await service.create(
          await auth.authenticate(bearerToken(r)),
          locationId,
          await readJson(r),
        ),
      ),
    );
    router.get(
      '$root/<id>',
      (Request r, String locationId, String id) async => jsonResponse(
        200,
        await service.get(
          await auth.authenticate(bearerToken(r)),
          locationId,
          id,
        ),
      ),
    );
    router.post(
      '$root/<id>/deactivate',
      (Request r, String locationId, String id) async => jsonResponse(
        200,
        await service.deactivate(
          await auth.authenticate(bearerToken(r)),
          locationId,
          id,
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/reactivate',
      (Request r, String locationId, String id) async => jsonResponse(
        200,
        await service.reactivate(
          await auth.authenticate(bearerToken(r)),
          locationId,
          id,
          await readJson(r),
        ),
      ),
    );
  }
  final Router router = Router();
}
