import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../infrastructure/auth_store.dart';
import '../knowledge/knowledge_service.dart';
import 'api_support.dart';

class KnowledgeRoutes {
  KnowledgeRoutes(AuthService auth, KnowledgeService service) {
    const public = '/api/v1/platform/knowledge/articles';
    const manage = '/api/v1/platform/knowledge/manage/articles';
    const revisions = '$manage/<articleId>/revisions';
    Future<SessionPrincipal> actor(Request r) =>
        auth.authenticate(bearerToken(r));
    // 8 KiB canonical content can use six bytes per escaped JSON code point.
    Future<Map<String, dynamic>> body(Request r) => readJson(r, limit: 65536);
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
      '$public/<articleId>',
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
      '$manage/<articleId>',
      (Request r, String a) async =>
          jsonResponse(200, await service.detail(await actor(r), a)),
    );
    router.post(
      '$manage/<articleId>/retire',
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
