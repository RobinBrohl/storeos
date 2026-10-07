import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:test/test.dart';
import 'merchandising_fixture.dart';
import 'preparation_batch_fixture.dart';
import 'recipe_fixture.dart';
part 'preparation_batch_integrity_cases.dart';
part 'preparation_batch_concurrency_cases.dart';

final skip = merchandisingDatabaseAvailable
    ? false
    : 'Explicit isolated PostgreSQL required.';
void main() {
  registerBatchIntegrityCases();
  registerBatchOpeningRaces();
  test(
    'eleven routes deny plugin tokens before preparation evidence',
    () => withMerchandisingFixture((f) async {
      const pluginId = 'preparation.denied-plugin';
      await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': pluginId,
            'name': 'Preparation denied plugin',
            'version': '1.0.0',
            'vendor': 'StoreOS Acceptance',
            'coreApiVersion': 1,
            'capabilities': ['organization.read'],
            'permissions': ['organization.read'],
            'subscriptions': <String>[],
            'configurationSchema': {
              'type': 'object',
              'properties': <String, dynamic>{},
              'additionalProperties': false,
            },
          },
        },
      );
      final token =
          (await f.call(
                'POST',
                '/plugins/$pluginId/approve',
                body: {
                  'expectedVersion': 1,
                  'locationId': merchandisingTestLocation,
                  'permissions': ['organization.read'],
                  'subscriptions': <String>[],
                },
              )).body['token']
              as String;
      await f.call(
        'GET',
        '/api/plugin/v1/organization',
        platform: false,
        token: token,
      );
      final w = await batchWorker(f, 'plugin_worker'),
          r = await batchRecipe(f),
          opening = batchOpening(r),
          id = opening['batchId'] as String;
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: opening,
        expected: 201,
      );
      final before = await batchEvidence(f);
      for (final root in [batchSelf, batchManage]) {
        for (final suffix in ['', '/$id', '/$id/recipe']) {
          await f.call('GET', '$root$suffix', token: token, expected: 401);
        }
        await f.call(
          'POST',
          '$root/$id/cancel',
          token: token,
          body: batchCancel(),
          expected: 401,
        );
      }
      await f.call(
        'POST',
        batchSelf,
        token: token,
        body: opening,
        expected: 401,
      );
      await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: token,
        body: batchComplete(),
        expected: 401,
      );
      await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        token: token,
        body: batchCorrection(),
        expected: 401,
      );
      expect(await batchEvidence(f), before);
    }),
    skip: skip,
  );
  test(
    'exact pin survives replacement retirement; original replay and correction zero, no Stock/Count effects',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'batch_worker'), r = await batchRecipe(f);
      await seedRecipeCountEvidence(f);
      final stock = await recipeEvidence(f, stock: true);
      final open = batchOpening(r), id = open['batchId'] as String;
      final opened =
          (await f.call(
                'POST',
                batchSelf,
                token: w.token,
                body: open,
                expected: 201,
              )).body['batch']
              as Map;
      expect(opened['employeeId'], w.employee);
      expect(opened['openedBy'], w.account);
      expect(opened['version'], 1);
      expect(opened['plannedDeclaredBatchCount'], 3);
      r.detail = (await replacementRecipe(f, r.detail)).detail;
      r.detail = (await saveRecipe(
        f,
        r.detail,
        r.detail.draft!.content.editable.ingredients,
        preparation: 'Replacement instruction',
      )).detail;
      await publishRecipe(f, r.detail);
      r.detail = await recipeDetail(f, r.detail.recipe.id);
      await f.call(
        'POST',
        '$recipeRoot/${r.detail.recipe.id}/retire',
        body: RecipeVersionRequest(r.detail.recipe.version).toJson(),
      );
      final context = (await f.call(
        'GET',
        '$batchSelf/$id/recipe',
        token: w.token,
      )).body;
      expect(context['revisionId'], open['revisionId']);
      expect((context['content'] as Map)['preparation'], contains('Mix'));
      expect(context['warnings'], contains('recipe_retired'));
      final before = await batchEvidence(f);
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: batchOpening(r),
        expected: 422,
      );
      expect(await batchEvidence(f), before);
      final replay = (await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: open,
        expected: 201,
      )).body;
      expect(replay['batch'], opened);
      expect(replay['replayed'], true);
      final complete = batchComplete();
      final original = (await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: w.token,
        body: complete,
      )).body['batch'];
      await f.restart();
      await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        body: batchCorrection(),
      );
      final correction = batchCorrection(latest: 1, replacement: 0);
      final corrected = (await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        body: correction,
      )).body['correction'];
      expect((corrected as Map)['previousEffectiveCount'], 1);
      expect(corrected['correctionNumber'], 2);
      final stable = await batchEvidence(f);
      expect(
        (await f.call(
          'POST',
          '$batchSelf/$id/complete',
          token: w.token,
          body: complete,
        )).body['batch'],
        original,
      );
      expect(
        (await f.call(
          'POST',
          '$batchManage/$id/count-corrections',
          body: correction,
        )).body['correction'],
        corrected,
      );
      expect(await batchEvidence(f), stable);
      final detail = (await f.call('GET', '$batchManage/$id')).body;
      expect(detail['actualDeclaredBatchCount'], 2);
      expect(detail['effectiveDeclaredBatchCount'], 0);
      expect(detail['version'], 2);
      expect((detail['corrections'] as List).length, 2);
      expect(detail['status'], 'completed');
      expect(await recipeEvidence(f, stock: true), stock);
      final audits = await f.owner.execute(
        'SELECT changes FROM "${f.schema}".audit_entries WHERE action LIKE \'production.batch.%\'',
      );
      expect(audits.length, 4);
      for (final row in audits) {
        expect(jsonEncode(row.first), isNot(contains('<script>')));
      }
    }),
    skip: skip,
  );
  test(
    'self isolation, current linkage, wrong configured Location, roles and no proxy completion',
    () => withMerchandisingFixture((f) async {
      final a = await batchWorker(f, 'employee_a'),
          b = await batchWorker(f, 'employee_b'),
          r = await batchRecipe(f),
          open = batchOpening(r);
      final id = open['batchId'] as String;
      await f.call(
        'POST',
        batchSelf,
        token: a.token,
        body: open,
        expected: 201,
      );
      for (final suffix in ['', '/recipe']) {
        await f.call(
          'GET',
          '$batchSelf/$id$suffix',
          token: b.token,
          expected: 404,
        );
      }
      for (final entry in {
        'complete': batchComplete(),
        'cancel': batchCancel(),
      }.entries) {
        await f.call(
          'POST',
          '$batchSelf/$id/${entry.key}',
          token: b.token,
          body: entry.value,
          expected: 404,
        );
      }
      await f.call(
        'POST',
        batchSelf,
        token: b.token,
        body: open,
        expected: 404,
      );
      expect(
        (await f.call('GET', batchSelf, token: b.token)).body['items'],
        isEmpty,
      );
      await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        token: a.token,
        body: batchCorrection(),
        expected: 403,
      );
      final proxy = await f.client.postUrl(
        Uri.parse('${f.base}/api/v1/platform$batchManage/$id/complete'),
      );
      proxy.headers.set('authorization', 'Bearer ${f.adminToken}');
      final proxyReply = await proxy.close();
      expect(proxyReply.statusCode, 404);
      await proxyReply.drain<void>();
      final location = await f.createLocation('Other');
      for (final root in [batchSelf, batchManage]) {
        await f.call(
          'GET',
          root.replaceAll(merchandisingTestLocation, location),
          token: root == batchSelf ? a.token : null,
          expected: 403,
        );
      }
      await f.call(
        'POST',
        batchSelf.replaceAll(merchandisingTestLocation, location),
        token: a.token,
        body: open,
        expected: 403,
      );
      for (final role in ['viewer', 'auditor']) {
        await f.account(role, role: role);
        await f.call(
          'GET',
          batchManage,
          token: await f.login(role),
          expected: 403,
        );
      }
      await f.call(
        'POST',
        '/employees/${a.employee}/deactivate',
        body: {'expectedVersion': 1},
      );
      await f.call('GET', '$batchSelf/$id', token: a.token, expected: 401);
      await f.call('POST', '$batchManage/$id/cancel', body: batchCancel());
      expect(
        (await f.call('GET', '$batchManage/$id')).body['employeeId'],
        a.employee,
      );
    }),
    skip: skip,
  );
  for (final kind in [
    'open',
    'complete',
    'employee_cancel',
    'manager_cancel',
    'count_correct',
  ]) {
    test(
      'audit rollback $kind, failed operation remains reusable',
      () => withMerchandisingFixture((f) async {
        final w = await batchWorker(f, 'atomic'),
            r = await batchRecipe(f),
            open = batchOpening(r);
        final id = open['batchId'] as String;
        if (kind != 'open') {
          await f.call(
            'POST',
            batchSelf,
            token: w.token,
            body: open,
            expected: 201,
          );
        }
        if (kind == 'count_correct') {
          await f.call(
            'POST',
            '$batchSelf/$id/complete',
            token: w.token,
            body: batchComplete(),
          );
        }
        final before = await batchEvidence(f);
        await f.owner.execute(
          'CREATE FUNCTION "${f.schema}".batch_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN IF NEW.action LIKE \'production.batch.%\' THEN RAISE EXCEPTION \'Injected audit failure\'; END IF; RETURN NEW; END \$\$; CREATE TRIGGER batch_fault BEFORE INSERT ON "${f.schema}".audit_entries FOR EACH ROW EXECUTE FUNCTION "${f.schema}".batch_fault()',
          queryMode: QueryMode.simple,
        );
        final route = kind == 'open'
            ? batchSelf
            : '${kind == 'manager_cancel' || kind == 'count_correct' ? batchManage : batchSelf}/$id/${kind == 'count_correct'
                  ? 'count-corrections'
                  : kind == 'complete'
                  ? 'complete'
                  : 'cancel'}';
        final body = kind == 'open'
            ? open
            : kind == 'complete'
            ? batchComplete()
            : kind == 'count_correct'
            ? batchCorrection()
            : batchCancel();
        final token = kind == 'manager_cancel' || kind == 'count_correct'
            ? null
            : w.token;
        final failed = await f.call(
          'POST',
          route,
          body: body,
          token: token,
          expected: 500,
        );
        expect(failed.body['code'], 'internal_error');
        expect(await batchEvidence(f), before);
        await f.owner.execute(
          'DROP TRIGGER batch_fault ON "${f.schema}".audit_entries',
        );
        await f.call(
          'POST',
          route,
          body: body,
          token: token,
          expected: kind == 'open' ? 201 : 200,
        );
      }),
      skip: skip,
    );
  }
  test(
    'strict decoded duplicates, unknown fields, integer lexical transport and text/body limits',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'strict'),
          r = await batchRecipe(f),
          open = batchOpening(r);
      final before = await batchEvidence(f);
      for (final name in ['operationId', r'operation\u0049d']) {
        await f.call(
          'POST',
          batchSelf,
          token: w.token,
          raw:
              '${jsonEncode(open).substring(0, jsonEncode(open).length - 1)},"$name":"${newUuid()}"}',
          expected: 400,
        );
      }
      for (final n in ['1.0', '1e0', '1.5', '"1"', '0', '10000', '-1']) {
        final raw = jsonEncode({...open, 'plannedDeclaredBatchCount': null})
            .replaceAll(
              '"plannedDeclaredBatchCount":null',
              '"plannedDeclaredBatchCount":$n',
            );
        expect(
          (await f.call(
            'POST',
            batchSelf,
            token: w.token,
            raw: raw,
            expected: 400,
          )).body['code'],
          'invalid_count',
        );
      }
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: {...open, 'employeeId': w.employee},
        expected: 400,
      );
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        raw: ' ' * 16385,
        expected: 413,
      );
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: open,
        jsonContentType: false,
        expected: 415,
      );
      expect(await batchEvidence(f), before);
    }),
    skip: skip,
  );
  for (final first in ['complete', 'employee_cancel', 'manager_cancel']) {
    for (final second in ['complete', 'employee_cancel', 'manager_cancel']) {
      if (first == second) continue;
      test(
        'serialized terminal race $first then $second',
        () => withMerchandisingFixture((f) async {
          final w = await batchWorker(f, 'race'),
              r = await batchRecipe(f),
              open = batchOpening(r);
          final id = open['batchId'] as String;
          await f.call(
            'POST',
            batchSelf,
            token: w.token,
            body: open,
            expected: 201,
          );
          Future<MerchandisingReply> act(String kind, int status) => f.call(
            'POST',
            '${kind == 'manager_cancel' ? batchManage : batchSelf}/$id/${kind == 'complete' ? 'complete' : 'cancel'}',
            token: kind == 'manager_cancel' ? null : w.token,
            body: kind == 'complete' ? batchComplete() : batchCancel(),
            expected: status,
          );
          final result = await orderedBatchCommands(
            f,
            () => act(first, 200),
            () => act(second, 409),
          );
          expect(result.last.body['code'], 'invalid_lifecycle');
          expect(
            (await f.owner.execute(
              'SELECT count(*) FROM "${f.schema}".production_preparation_batch_commands',
            )).single.first,
            2,
          );
        }),
        skip: skip,
      );
    }
  }
  test(
    'serialized competing corrections and completion retry retain exact originals',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'correct_race'),
          r = await batchRecipe(f),
          open = batchOpening(r);
      final id = open['batchId'] as String;
      await f.call(
        'POST',
        batchSelf,
        token: w.token,
        body: open,
        expected: 201,
      );
      final complete = batchComplete();
      await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: w.token,
        body: complete,
      );
      final results = await orderedBatchCommands(
        f,
        () => f.call(
          'POST',
          '$batchManage/$id/count-corrections',
          body: batchCorrection(),
        ),
        () => f.call(
          'POST',
          '$batchManage/$id/count-corrections',
          body: batchCorrection(replacement: 0),
          expected: 409,
        ),
      );
      expect(results.last.body['code'], 'correction_conflict');
      expect(
        ((await f.call(
              'POST',
              '$batchSelf/$id/complete',
              token: w.token,
              body: complete,
            )).body['batch']
            as Map)['actualDeclaredBatchCount'],
        2,
      );
    }),
    skip: skip,
  );
}
