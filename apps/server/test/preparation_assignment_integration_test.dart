import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'package:postgres/postgres.dart';
import 'package:storeos_server/src/production/preparation_assignment_service.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';
part 'preparation_assignment_cases.dart';

final skip = merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';
String get manage =>
    '/production/manage/locations/$merchandisingTestLocation/preparation-assignments';
String get self =>
    '/production/self/locations/$merchandisingTestLocation/preparation-assignments';
Map<String, dynamic> request(BatchRecipe r, BatchWorker w) => {
  'id': newUuid(),
  'operationId': newUuid(),
  'recipeId': r.detail.recipe.id,
  'revisionId': r.detail.currentPublished!.id,
  'employeeId': w.employee,
  'expectedEmployeeVersion': 1,
  'plannedDeclaredBatchCount': 3,
};
Map<String, dynamic> start() => {
  'operationId': newUuid(),
  'expectedVersion': 1,
};
void main() {
  registerAssignmentCases();
  test(
    'assignment R1 survives R2, starts once, restart replay, completion and zero correction',
    () => withMerchandisingFixture((f) async {
      final r = await batchRecipe(f),
          w = await batchWorker(f, 'assigned_worker'),
          other = await batchWorker(f, 'other_worker');
      final c = request(r, w), id = c['id'] as String;
      final created = (await f.call(
        'POST',
        manage,
        body: c,
        expected: 201,
      )).body;
      expect((created['assignment'] as Map)['status'], 'assigned');
      expect(
        (await f.call('GET', '$manage/assignees')).body['items'],
        hasLength(2),
      );
      for (final e
          in (await f.call('GET', '$manage/assignees')).body['items'] as List) {
        expect((e as Map).keys.toSet(), {'id', 'displayName', 'version'});
      }
      final r1 = r.detail.currentPublished!.id;
      r.detail = (await replacementRecipe(f, r.detail)).detail;
      r.detail = (await saveRecipe(
        f,
        r.detail,
        r.detail.draft!.content.editable.ingredients,
        preparation: 'New R2 instructions',
      )).detail;
      await publishRecipe(f, r.detail);
      r.detail = await recipeDetail(f, r.detail.recipe.id);
      for (final suffix in ['', '/recipe', '/history']) {
        await f.call(
          'GET',
          '$self/$id$suffix',
          token: other.token,
          expected: 404,
        );
      }
      await f.call(
        'POST',
        '$self/$id/start',
        token: other.token,
        body: start(),
        expected: 404,
      );
      expect(
        (await f.call(
          'GET',
          '$self/$id/recipe',
          token: w.token,
        )).body['revisionId'],
        r1,
      );
      final s = start();
      final outcomes = await orderedBatchCommands(
        f,
        () => f.call('POST', '$self/$id/start', token: w.token, body: s),
        () => f.call(
          'POST',
          '$self/$id/start',
          token: w.token,
          body: start(),
          expected: 409,
        ),
      );
      final accepted = outcomes.first.body,
          b = accepted['batch'] as Map,
          bid = b['batchId'] as String;
      expect(b['revisionId'], r1);
      expect(b['plannedDeclaredBatchCount'], 3);
      await f.restart();
      final before = await batchEvidence(f);
      final replay = (await f.call(
        'POST',
        '$self/$id/start',
        token: w.token,
        body: s,
      )).body;
      expect(replay['batch'], b);
      expect(replay['replayed'], true);
      expect(await batchEvidence(f), before);
      await f.call(
        'POST',
        '$batchSelf/$bid/complete',
        token: w.token,
        body: batchComplete(),
      );
      await f.call(
        'POST',
        '$batchManage/$bid/count-corrections',
        body: batchCorrection(),
      );
      await f.call(
        'POST',
        '$batchManage/$bid/count-corrections',
        body: batchCorrection(latest: 1, replacement: 0),
      );
      final detail = (await f.call('GET', '$manage/$id')).body;
      expect((detail['batch'] as Map)['actualDeclaredBatchCount'], 2);
      expect((detail['batch'] as Map)['effectiveDeclaredBatchCount'], 0);
      expect(detail['status'], 'started');
      final pending = request(r, w), pendingId = pending['id'];
      await f.call('POST', manage, body: pending, expected: 201);
      await f.call(
        'POST',
        '$recipeRoot/${r.detail.recipe.id}/retire',
        body: RecipeVersionRequest(r.detail.recipe.version).toJson(),
      );
      await f.call(
        'POST',
        '$self/$pendingId/start',
        token: w.token,
        body: start(),
        expected: 422,
      );
      expect(
        (await f.call(
          'GET',
          '$self/$id/recipe',
          token: w.token,
        )).body['revisionId'],
        r1,
      );
      expect(
        (await f.call(
          'POST',
          '$self/$id/start',
          token: w.token,
          body: s,
        )).body['batch'],
        b,
      );
      expect(
        (await f.call(
          'POST',
          manage,
          body: c,
          expected: 201,
        )).body['assignment'],
        created['assignment'],
      );
      await f.call(
        'POST',
        '$manage/$id/withdraw',
        body: {...start(), 'reason': 'too late'},
        expected: 409,
      );
      expect(
        (await f.call(
          'POST',
          '$manage/$id/withdraw',
          body: {
            ...start(),
            'expectedVersion': 2,
            'reason': 'Cannot change terminal assignment',
          },
          expected: 409,
        )).body['code'],
        'assignment_state_conflict',
      );
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: {...batchOpening(r), 'revisionId': r1},
        expected: 422,
      );
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".production_preparation_batches',
        )).single.first,
        1,
      );
      for (final row in await f.owner.execute(
        "SELECT changes FROM \"${f.schema}\".audit_entries WHERE action LIKE 'production.preparation_assignment.%'",
      )) {
        expect(
          (row.single as Map).keys.toSet().difference({
            'assignmentId',
            'employeeId',
            'recipeId',
            'revisionId',
            'locationId',
            'operationId',
            'version',
            'status',
            'batchId',
          }),
          isEmpty,
        );
      }
    }),
    skip: skip,
  );
}
