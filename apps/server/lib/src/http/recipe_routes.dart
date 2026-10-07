import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../infrastructure/auth_store.dart';
import '../production/recipe_service.dart';
import 'api_support.dart';

class RecipeRoutes {
  RecipeRoutes(AuthService auth, RecipeService service) {
    const public = '/api/v1/platform/production/recipes';
    const manage = '/api/v1/platform/production/manage/recipes';
    const revisions = '$manage/<recipeId>/revisions';
    Future<SessionPrincipal> actor(Request r) =>
        auth.authenticate(bearerToken(r));
    // Independent transport bound; canonical decoded composition is at most 32 KiB.
    Future<Map<String, dynamic>> body(Request r) =>
        readJson(r, limit: 262144, rejectDuplicateNames: true);
    router.get(
      '/api/v1/platform/production/manage/article-candidates',
      (Request r) async => jsonResponse(
        200,
        await service.candidates(
          await actor(r),
          q: r.url.queryParameters['q'] ?? '',
          after: r.url.queryParameters['after'],
          id: r.url.queryParameters['id'],
        ),
      ),
    );
    router.get(
      public,
      (Request r) async => jsonResponse(
        200,
        await service.listPublished(
          await actor(r),
          q: r.url.queryParameters['q'] ?? '',
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.get(
      '$public/<recipeId>',
      (Request r, String a) async =>
          jsonResponse(200, await service.readPublished(await actor(r), a)),
    );
    router.get(
      manage,
      (Request r) async => jsonResponse(
        200,
        await service.listManaged(
          await actor(r),
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      manage,
      (Request r) async => jsonResponse(
        201,
        await service.create(await actor(r), await body(r)),
      ),
    );
    router.get(
      '$manage/<recipeId>',
      (Request r, String a) async =>
          jsonResponse(200, await service.detail(await actor(r), a)),
    );
    router.post(
      '$manage/<recipeId>/retire',
      (Request r, String a) async => jsonResponse(
        200,
        await service.retire(await actor(r), a, await body(r)),
      ),
    );
    router.get(
      revisions,
      (Request r, String a) async => jsonResponse(
        200,
        await service.history(
          await actor(r),
          a,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      revisions,
      (Request r, String a) async => jsonResponse(
        201,
        await service.newDraft(await actor(r), a, await body(r)),
      ),
    );
    router.get(
      '$revisions/<revisionId>',
      (Request r, String a, String v) async =>
          jsonResponse(200, await service.revision(await actor(r), a, v)),
    );
    router.post(
      '$revisions/<revisionId>/edit',
      (Request r, String a, String v) async => jsonResponse(
        200,
        await service.save(await actor(r), a, v, await body(r)),
      ),
    );
    router.post(
      '$revisions/<revisionId>/discard',
      (Request r, String a, String v) async => jsonResponse(
        200,
        await service.discard(await actor(r), a, v, await body(r)),
      ),
    );
    router.post(
      '$revisions/<revisionId>/publish',
      (Request r, String a, String v) async => jsonResponse(
        200,
        await service.publish(await actor(r), a, v, await body(r)),
      ),
    );
  }
  final Router router = Router();
}
