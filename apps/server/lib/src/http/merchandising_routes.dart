import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import '../application/auth_service.dart';
import '../infrastructure/auth_store.dart';
import '../merchandising/merchandising_service.dart';
import 'api_support.dart';

class MerchandisingRoutes {
  MerchandisingRoutes(AuthService auth, MerchandisingService service) {
    const c = '/api/v1/platform/merchandising';
    const f = '/api/v1/platform/locations/<locationId>/merchandising/fixtures';
    Future<SessionPrincipal> actor(Request r) =>
        auth.authenticate(bearerToken(r));
    router.get(
      f,
      (Request r, String l) async => jsonResponse(
        200,
        await service.listFixtures(
          await actor(r),
          l,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      f,
      (Request r, String l) async => jsonResponse(
        201,
        await service.createFixture(await actor(r), l, await readJson(r)),
      ),
    );
    router.get(
      '$f/<fixtureId>',
      (Request r, String l, String id) async =>
          jsonResponse(200, await service.getFixture(await actor(r), l, id)),
    );
    router.post(
      '$f/<fixtureId>/edit',
      (Request r, String l, String id) async => jsonResponse(
        200,
        await service.editFixture(await actor(r), l, id, await readJson(r)),
      ),
    );
    router.post(
      '$f/<fixtureId>/retire',
      (Request r, String l, String id) async => jsonResponse(
        200,
        await service.retireFixture(await actor(r), l, id, await readJson(r)),
      ),
    );
    router.get(
      '$c/planograms',
      (Request r) async => jsonResponse(
        200,
        await service.listPlanograms(
          await actor(r),
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      '$c/planograms',
      (Request r) async => jsonResponse(
        201,
        await service.createPlanogram(await actor(r), await readJson(r)),
      ),
    );
    router.get(
      '$c/planograms/<planogramId>',
      (Request r, String pg) async =>
          jsonResponse(200, await service.getPlanogram(await actor(r), pg)),
    );
    router.post(
      '$c/planograms/<planogramId>/retire',
      (Request r, String pg) async => jsonResponse(
        200,
        await service.retirePlanogram(await actor(r), pg, await readJson(r)),
      ),
    );
    const revisions = '$c/planograms/<planogramId>/revisions';
    router.get(
      revisions,
      (Request r, String pg) async => jsonResponse(
        200,
        await service.listRevisions(
          await actor(r),
          pg,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      revisions,
      (Request r, String pg) async => jsonResponse(
        201,
        await service.createDraft(await actor(r), pg, await readJson(r)),
      ),
    );
    router.get(
      '$revisions/<revisionId>',
      (Request r, String pg, String id) async =>
          jsonResponse(200, await service.getRevision(await actor(r), pg, id)),
    );
    router.post(
      '$revisions/<revisionId>/edit',
      (Request r, String pg, String id) async => jsonResponse(
        200,
        await service.editDraft(await actor(r), pg, id, await readJson(r)),
      ),
    );
    router.post(
      '$revisions/<revisionId>/discard',
      (Request r, String pg, String id) async => jsonResponse(
        200,
        await service.discardDraft(await actor(r), pg, id, await readJson(r)),
      ),
    );
    router.post(
      '$revisions/<revisionId>/publish',
      (Request r, String pg, String id) async => jsonResponse(
        200,
        await service.publish(await actor(r), pg, id, await readJson(r)),
      ),
    );
    router.get(
      '$c/articles',
      (Request r) async => jsonResponse(
        200,
        await service.candidates(
          await actor(r),
          q: r.url.queryParameters['q'] ?? '',
          after: r.url.queryParameters['after'],
          includeInactive: r.url.queryParameters['includeInactive'] == 'true',
        ),
      ),
    );
    router.get(
      '$f/<fixtureId>/layout',
      (Request r, String l, String id) async =>
          jsonResponse(200, await service.layout(await actor(r), l, id)),
    );
    router.get(
      '$f/<fixtureId>/assignments',
      (Request r, String l, String id) async => jsonResponse(
        200,
        await service.assignments(
          await actor(r),
          l,
          id,
          after: r.url.queryParameters['after'],
        ),
      ),
    );
    router.post(
      '$f/<fixtureId>/assignments',
      (Request r, String l, String id) async => jsonResponse(
        200,
        await service.assign(await actor(r), l, id, await readJson(r)),
      ),
    );
    router.get(
      '$f/<fixtureId>/assignments/<assignmentId>/print-view',
      (Request r, String l, String id, String assignment) async => jsonResponse(
        200,
        await service.printView(await actor(r), l, id, assignment),
      ),
    );
  }
  final Router router = Router();
}
