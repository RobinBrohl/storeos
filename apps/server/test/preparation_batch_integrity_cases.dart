part of 'preparation_batch_integration_test.dart';

void registerBatchIntegrityCases() {
  for (final planned in [null, 1, 9999]) {
    test(
      'persist plan $planned and complete boundary 9999',
      () => withMerchandisingFixture((f) async {
        final w = await batchWorker(f, 'bounds'),
            r = await batchRecipe(f),
            open = batchOpening(r, planned: planned);
        final id = open['batchId'] as String;
        await f.call(
          'POST',
          batchSelf,
          token: w.token,
          body: open,
          expected: 201,
        );
        for (final count in [0, 10000, 1.5, '1']) {
          await f.call(
            'POST',
            '$batchSelf/$id/complete',
            token: w.token,
            body: {...batchComplete(), 'actualDeclaredBatchCount': count},
            expected: 400,
          );
        }
        await f.call(
          'POST',
          '$batchSelf/$id/complete',
          token: w.token,
          body: batchComplete(count: 9999),
        );
        for (final replacement in [0, 1, 9999]) {
          final detail = (await f.call('GET', '$batchManage/$id')).body;
          await f.call(
            'POST',
            '$batchManage/$id/count-corrections',
            body: batchCorrection(
              latest: detail['latestCorrectionNumber'] as int,
              replacement: replacement,
            ),
          );
        }
        final detail = (await f.call('GET', '$batchManage/$id')).body;
        expect(detail['plannedDeclaredBatchCount'], planned);
        expect(detail['actualDeclaredBatchCount'], 9999);
        expect(detail['effectiveDeclaredBatchCount'], 9999);
        for (final count in [-1, 10000, 1.5, '0']) {
          await f.call(
            'POST',
            '$batchManage/$id/count-corrections',
            body: {
              ...batchCorrection(latest: 3),
              'replacementDeclaredBatchCount': count,
            },
            expected: 400,
          );
        }
      }),
      skip: skip,
    );
  }
  test(
    'receipt conflict actor kind resource payload and immutable cancellation replay',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'receipts'),
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
      final before = await batchEvidence(f);
      for (final changed in [
        {...open, 'plannedDeclaredBatchCount': 4},
        {...open, 'revisionId': newUuid()},
        {...open, 'batchId': newUuid()},
      ]) {
        expect(
          (await f.call(
            'POST',
            batchSelf,
            token: w.token,
            body: changed,
            expected: 409,
          )).body['code'],
          'operation_conflict',
        );
      }
      expect(await batchEvidence(f), before);
      final cancelled = batchCancel();
      final original = (await f.call(
        'POST',
        '$batchSelf/$id/cancel',
        token: w.token,
        body: cancelled,
      )).body;
      await f.restart();
      final after = await batchEvidence(f);
      final replay = (await f.call(
        'POST',
        '$batchSelf/$id/cancel',
        token: w.token,
        body: cancelled,
      )).body;
      expect(replay['batch'], original['batch']);
      expect(replay['replayed'], true);
      expect(
        (await f.call(
          'POST',
          '$batchManage/$id/cancel',
          body: cancelled,
          expected: 409,
        )).body['code'],
        'operation_conflict',
      );
      expect(await batchEvidence(f), after);
      await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: w.token,
        body: batchComplete(),
        expected: 409,
      );
    }),
    skip: skip,
  );
  test(
    'runtime grants, terminal identity, published pin and append-only correction/receipt protection',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'integrity'),
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
      final schema = '"${f.schema}"';
      Future<void> denied(
        String sql, {
        String code = '42501',
        bool owner = false,
      }) async {
        try {
          if (owner) {
            await f.owner.execute(sql);
          } else {
            await f.pool.execute(sql);
          }
        } on ServerException catch (e) {
          expect(e.code, code);
          return;
        }
        fail('Illegal evidence write accepted.');
      }

      for (final table in [
        'production_preparation_batches',
        'production_preparation_batch_commands',
        'production_preparation_batch_count_corrections',
      ]) {
        await denied('DELETE FROM $schema.$table');
        await denied('TRUNCATE $schema.$table CASCADE');
      }
      await denied(
        "UPDATE $schema.production_preparation_batches SET employee_id='${newUuid()}' WHERE id='$id'",
      );
      await denied(
        "UPDATE $schema.production_preparation_batches SET planned_declared_batch_count=4 WHERE id='$id'",
        owner: true,
        code: '23514',
      );
      await f.call(
        'POST',
        '$batchSelf/$id/complete',
        token: w.token,
        body: batchComplete(),
      );
      await denied(
        "UPDATE $schema.production_preparation_batches SET actual_declared_batch_count=3 WHERE id='$id'",
        code: '23514',
      );
      await denied(
        "UPDATE $schema.production_preparation_batches SET status='open' WHERE id='$id'",
        code: '23514',
        owner: true,
      );
      await f.call(
        'POST',
        '$batchManage/$id/count-corrections',
        body: batchCorrection(),
      );
      for (final table in [
        'production_preparation_batch_commands',
        'production_preparation_batch_count_corrections',
      ]) {
        await denied("UPDATE $schema.$table SET location_id=location_id");
        await denied(
          "UPDATE $schema.$table SET location_id=location_id",
          owner: true,
          code: '23514',
        );
        await denied('DELETE FROM $schema.$table', owner: true, code: '23514');
      }
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='${f.schema}' AND p.proname LIKE 'preparation_%' AND p.prosecdef",
        )).single.first,
        0,
      );
    }),
    skip: skip,
  );
  test(
    'bounded keysets bind Employee Company Location endpoint and lifecycle before evidence',
    () => withMerchandisingFixture((f) async {
      final a = await batchWorker(f, 'page_a'),
          b = await batchWorker(f, 'page_b'),
          r = await batchRecipe(f);
      for (var n = 0; n < 51; n++) {
        await f.call(
          'POST',
          batchSelf,
          token: a.token,
          body: batchOpening(r),
          expected: 201,
        );
      }
      final page = (await f.call('GET', batchSelf, token: a.token)).body;
      expect((page['items'] as List).length, 50);
      final cursor = page['nextCursor'] as String;
      final managed = (await f.call('GET', batchManage)).body;
      expect((managed['items'] as List).length, 50);
      expect(
        (await f.call(
          'GET',
          '$batchManage?after=${managed['nextCursor']}',
        )).body['nextCursor'],
        null,
      );
      expect(
        (await f.call('GET', batchSelf, token: b.token)).body['items'],
        isEmpty,
      );
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(cursor))))
              as Map<String, dynamic>;
      for (final key in ['company', 'location', 'employee']) {
        final changed = base64Url
            .encode(utf8.encode(jsonEncode({...decoded, key: newUuid()})))
            .replaceAll('=', '');
        await f.call(
          'GET',
          '$batchSelf?after=$changed',
          token: a.token,
          expected: 400,
        );
      }
      final next = (await f.call(
        'GET',
        '$batchSelf?after=$cursor',
        token: a.token,
      )).body;
      expect((next['items'] as List).length, 1);
      expect(next['nextCursor'], isNull);
      for (final target in [
        '$batchSelf?after=$cursor&status=open',
        '$batchManage?after=$cursor',
      ]) {
        expect(
          (await f.call(
            'GET',
            target,
            token: target.startsWith(batchSelf) ? a.token : null,
            expected: 400,
          )).body['code'],
          'invalid_cursor',
        );
      }
      await f.call(
        'GET',
        '$batchSelf?after=$cursor',
        token: b.token,
        expected: 400,
      );
      for (final malformed in ['!', 'A', 'a' * 2049]) {
        await f.call(
          'GET',
          '$batchSelf?after=$malformed',
          token: a.token,
          expected: 400,
        );
      }
      await f.call(
        'GET',
        '$batchSelf?status=unknown',
        token: a.token,
        expected: 400,
      );
      await f.call(
        'GET',
        '$batchSelf?recipeId=${r.detail.recipe.id}',
        token: a.token,
        expected: 400,
      );
      await f.call(
        'GET',
        '$batchSelf?status=open&status=completed',
        token: a.token,
        expected: 400,
      );
    }),
    skip: skip,
  );
}
