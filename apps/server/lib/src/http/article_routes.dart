import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../application/auth_service.dart';
import '../inventory/article_service.dart';
import 'api_support.dart';

class ArticleRoutes {
  ArticleRoutes(AuthService auth, ArticleService service) {
    const root = '/api/v1/platform/articles';
    router.get(
      root,
      (Request r) async => jsonResponse(
        200,
        await service.list(
          await auth.authenticate(bearerToken(r)),
          after: r.url.queryParameters['after'],
          q: r.url.queryParameters['q'],
          active: r.url.queryParameters['active'],
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
    router.post(
      '$root/<id>/edit',
      (Request r, String id) async => jsonResponse(
        200,
        await service.edit(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/deactivate',
      (Request r, String id) async => jsonResponse(
        200,
        await service.deactivate(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
    router.post(
      '$root/<id>/reactivate',
      (Request r, String id) async => jsonResponse(
        200,
        await service.reactivate(
          await auth.authenticate(bearerToken(r)),
          id,
          await readJson(r),
        ),
      ),
    );
  }
  final Router router = Router();
}
