part of 'preparation_assignment_integration_test.dart';

Future<List<Object?>> assignmentEvidence(MerchandisingFixture f) async => [
  ...await batchEvidence(f),
  for (final table in [
    'production_preparation_assignments',
    'production_preparation_assignment_commands',
  ])
    (await f.owner.execute(
      "SELECT md5(string_agg(to_jsonb(t)::text,'' ORDER BY to_jsonb(t)::text)) FROM \"${f.schema}\".$table t",
    )).single.first,
];
void registerAssignmentCases() {
  test(
    'replacement Account link follows Employee work but cannot replay prior actor evidence',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'original_link'),
          r = await batchRecipe(f),
          c = request(r, w),
          pending = request(r, w);
      await f.call('POST', manage, body: c, expected: 201);
      await f.call('POST', manage, body: pending, expected: 201);
      final original = start();
      await f.call(
        'POST',
        '$self/${c['id']}/start',
        token: w.token,
        body: original,
      );
      final link =
          (await f.call(
                'GET',
                '/employees/${w.employee}/account-link',
              )).body['link']
              as Map;
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': link['version']},
      );
      final account = newUuid();
      await f.call(
        'POST',
        '/users',
        expected: 201,
        body: {
          'id': account,
          'username': 'replacement_link',
          'password': merchandisingTestPassword,
          'role': 'employee',
          'locationId': merchandisingTestLocation,
        },
      );
      await f.call(
        'POST',
        '/employees/${w.employee}/account-link',
        expected: 201,
        body: {
          'id': newUuid(),
          'accountId': account,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
      );
      final replacement = await f.login('replacement_link');
      await f.call('GET', '$self/${c['id']}', token: replacement);
      await f.call('GET', '$self/${c['id']}/recipe', token: replacement);
      final before = await assignmentEvidence(f);
      await f.call(
        'POST',
        '$self/${c['id']}/start',
        token: replacement,
        body: original,
        expected: 409,
      );
      await f.call(
        'GET',
        '$self/${pending['id']}',
        token: w.token,
        expected: 401,
      );
      expect(await assignmentEvidence(f), before);
      final oldFresh = await f.login('original_link');
      await f.call(
        'GET',
        '$self/${pending['id']}',
        token: oldFresh,
        expected: 404,
      );
      final started = (await f.call(
        'POST',
        '$self/${pending['id']}/start',
        token: replacement,
        body: start(),
      )).body;
      expect(started['assignment']['employeeId'], w.employee);
      expect(started['batch']['openedBy'], account);
    }),
    skip: skip,
  );
  test(
    '50 item pages filter before pagination and bind every cursor scope',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'paged_worker'),
          other = await batchWorker(f, 'paged_other'),
          r = await batchRecipe(f);
      final foreign = request(r, other)
        ..['id'] = '00000000-0000-4000-8000-000000000001';
      await f.call('POST', manage, body: foreign, expected: 201);
      for (var n = 1; n <= 52; n++) {
        final c = request(r, w)
          ..['id'] = '10000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
        await f.call('POST', manage, body: c, expected: 201);
      }
      final p = (await f.call(
        'GET',
        '$self?status=assigned',
        token: w.token,
      )).body;
      expect(p['items'], hasLength(50));
      expect(
        (p['items'] as List).every(
          (dynamic a) => a['employeeId'] == w.employee,
        ),
        true,
      );
      final cursor = Uri.encodeQueryComponent(p['nextCursor'] as String);
      final last = (await f.call(
        'GET',
        '$self?status=assigned&after=$cursor',
        token: w.token,
      )).body;
      expect(last['items'], hasLength(2));
      expect(last['nextCursor'], null);
      for (final route in [
        '$self?after=$cursor',
        '$self?status=started&after=$cursor',
        '$manage?status=assigned&after=$cursor',
        '$manage/assignees?after=$cursor',
      ]) {
        await f.call(
          'GET',
          route,
          token: route.contains('/self/') ? w.token : null,
          expected: 400,
        );
      }
      await f.call(
        'GET',
        '$self?status=assigned&after=$cursor',
        token: other.token,
        expected: 400,
      );
    }),
    skip: skip,
  );
  test(
    'all assignment endpoints reject stale role, foreign Company and Location before evidence',
    () => withMerchandisingFixture((f) async {
      final w = await batchWorker(f, 'scope_worker'),
          r = await batchRecipe(f),
          c = request(r, w),
          id = c['id'] as String;
      await f.call('POST', manage, body: c, expected: 201);
      await f.account('assignment_viewer', role: 'viewer');
      final visitor = await f.login('assignment_viewer');
      final before = await assignmentEvidence(f);
      for (final root in [manage, self]) {
        for (final suffix in [
          '',
          if (root == manage) '/assignees',
          '/$id',
          '/$id/recipe',
          '/$id/history',
        ]) {
          await f.call('GET', '$root$suffix', token: visitor, expected: 403);
          await f.call(
            'GET',
            '${root.replaceFirst(merchandisingTestLocation, newUuid())}$suffix',
            token: root == manage ? null : w.token,
            expected: 403,
          );
        }
      }
      await f.call('POST', manage, token: visitor, body: c, expected: 403);
      await f.call(
        'POST',
        '$manage/$id/withdraw',
        token: visitor,
        body: {...start(), 'reason': 'Scope'},
        expected: 403,
      );
      await f.call(
        'POST',
        '$self/$id/start',
        token: visitor,
        body: start(),
        expected: 403,
      );
      final foreign = PreparationAssignmentService(
        PlatformDatabase(
          f.pool,
          schemaName: f.schema,
          companyId: newUuid(),
          locationId: merchandisingTestLocation,
        ),
      );
      for (final action in [
        () => foreign.list(f.adminPrincipal, merchandisingTestLocation),
        () => foreign.detail(f.adminPrincipal, merchandisingTestLocation, id),
        () => foreign.recipe(f.adminPrincipal, merchandisingTestLocation, id),
        () => foreign.history(f.adminPrincipal, merchandisingTestLocation, id),
        () => foreign.assignees(f.adminPrincipal, merchandisingTestLocation),
        () => foreign.command(
          f.adminPrincipal,
          merchandisingTestLocation,
          null,
          'create',
          c,
        ),
      ]) {
        await expectLater(
          action(),
          throwsA(
            isA<PlatformFailure>().having((e) => e.status, 'status', 403),
          ),
        );
      }
      expect(await assignmentEvidence(f), before);
      // A valid old session must not override the current Account role.
      await f.call(
        'POST',
        '/users/${w.account}',
        body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
      );
      await f.call(
        'POST',
        '$self/$id/start',
        token: w.token,
        body: start(),
        expected: 401,
      );
      await f.restart(companyId: newUuid());
      for (final root in [manage, self]) {
        for (final suffix in [
          '',
          if (root == manage) '/assignees',
          '/$id',
          '/$id/recipe',
          '/$id/history',
        ]) {
          await f.call('GET', '$root$suffix', expected: 401);
        }
      }
      await f.call('POST', manage, body: c, expected: 401);
      await f.call(
        'POST',
        '$manage/$id/withdraw',
        body: {...start(), 'reason': 'Foreign Company'},
        expected: 401,
      );
      await f.call('POST', '$self/$id/start', body: start(), expected: 401);
    }),
    skip: skip,
  );
  for (final first in [true, false]) {
    test(
      'start withdraw observed lock order startFirst=$first',
      () => withMerchandisingFixture((f) async {
        final r = await batchRecipe(f),
            w = await batchWorker(f, 'race_worker'),
            c = request(r, w),
            id = c['id'];
        await f.call('POST', manage, body: c, expected: 201);
        final s = start(),
            withdraw = {...start(), 'reason': 'Manager withdrawal'};
        Future<MerchandisingReply> starting() => f.call(
          'POST',
          '$self/$id/start',
          token: w.token,
          body: s,
          expected: first ? 200 : 409,
        );
        Future<MerchandisingReply> withdrawing() => f.call(
          'POST',
          '$manage/$id/withdraw',
          body: withdraw,
          expected: first ? 409 : 200,
        );
        await orderedBatchCommands(
          f,
          first ? starting : withdrawing,
          first ? withdrawing : starting,
        );
        final d = (await f.call('GET', '$manage/$id')).body;
        expect(d['status'], first ? 'started' : 'withdrawn');
        expect(d['batchId'] != null, first);
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".production_preparation_batches',
          )).single.first,
          first ? 1 : 0,
        );
        if (!first) {
          final before = await assignmentEvidence(f);
          expect(
            (await f.call(
              'POST',
              '$manage/$id/withdraw',
              body: withdraw,
            )).body['replayed'],
            true,
          );
          expect(await assignmentEvidence(f), before);
        }
      }),
      skip: skip,
    );
  }
  test(
    'simultaneous identical start returns one original Batch and two original audits',
    () => withMerchandisingFixture((f) async {
      final r = await batchRecipe(f),
          w = await batchWorker(f, 'identical'),
          c = request(r, w),
          id = c['id'];
      await f.call('POST', manage, body: c, expected: 201);
      final s = start();
      final results = await orderedBatchCommands(
        f,
        () => f.call('POST', '$self/$id/start', token: w.token, body: s),
        () => f.call('POST', '$self/$id/start', token: w.token, body: s),
      );
      expect(results[0].body['batch'], results[1].body['batch']);
      expect(results[1].body['replayed'], true);
      expect(
        (await f.owner.execute(
          "SELECT count(*) FROM \"${f.schema}\".audit_entries WHERE action IN ('production.batch.opened','production.preparation_assignment.started')",
        )).single.first,
        2,
      );
    }),
    skip: skip,
  );
  for (final mutation in [
    'publish',
    'retire',
    'produced_deactivate',
    'assortment_deactivate',
    'ingredient_deactivate',
    'ingredient_unit',
    'employee_deactivate',
    'employee_unlink',
    'account_role',
    'session_revoke',
  ]) {
    for (final changeFirst in [true, false]) {
      test(
        'assignment current eligibility $mutation changeFirst=$changeFirst',
        () => withMerchandisingFixture((f) async {
          final w = await batchWorker(f, 'eligibility'),
              r = await batchRecipe(f),
              c = request(r, w),
              id = c['id'];
          await f.call('POST', manage, body: c, expected: 201);
          String route;
          Map<String, dynamic> payload;
          if (mutation == 'publish') {
            r.detail = (await replacementRecipe(f, r.detail)).detail;
            route =
                '$recipeRoot/${r.detail.recipe.id}/revisions/${r.detail.draft!.id}/publish';
            payload = PublishRecipeRequest(
              newUuid(),
              r.detail.recipe.version,
            ).toJson();
          } else if (mutation == 'retire') {
            route = '$recipeRoot/${r.detail.recipe.id}/retire';
            payload = RecipeVersionRequest(r.detail.recipe.version).toJson();
          } else if (mutation == 'assortment_deactivate') {
            final member =
                ((await f.call(
                              'GET',
                              '/locations/$merchandisingTestLocation/assortment',
                            )).body['items']
                            as List)
                        .single
                    as Map;
            route =
                '/locations/$merchandisingTestLocation/assortment/${member['id']}/deactivate';
            payload = {'expectedVersion': member['version']};
          } else if (mutation == 'employee_unlink') {
            final link =
                (await f.call(
                      'GET',
                      '/employees/${w.employee}/account-link',
                    )).body['link']
                    as Map;
            route = '/employee-links/${link['id']}/revoke';
            payload = {'expectedVersion': link['version']};
          } else if (mutation == 'employee_deactivate') {
            route = '/employees/${w.employee}/deactivate';
            payload = {'expectedVersion': 1};
          } else if (mutation == 'account_role') {
            route = '/users/${w.account}';
            payload = {
              'expectedVersion': 1,
              'role': 'viewer',
              'isActive': true,
            };
          } else if (mutation == 'session_revoke') {
            route = '/users/${w.account}/password';
            payload = {
              'expectedVersion': 1,
              'password': merchandisingTestPassword,
            };
          } else if (mutation == 'ingredient_unit') {
            route = '/articles/${r.ingredient.id}/edit';
            payload = {
              'expectedVersion': r.ingredient.version,
              'sku': r.ingredient.sku,
              'barcode': r.ingredient.barcode,
              'name': r.ingredient.name,
              'description': r.ingredient.description,
              'unit': 'g',
            };
          } else {
            final article = mutation == 'produced_deactivate'
                ? r.produced
                : r.ingredient;
            route = '/articles/${article.id}/deactivate';
            payload = {'expectedVersion': article.version};
          }
          final identity =
              mutation.startsWith('employee_') ||
              mutation.startsWith('account_') ||
              mutation == 'session_revoke';
          Future<MerchandisingReply> change() =>
              f.call('POST', route, body: payload);
          Future<MerchandisingReply> starting() => f.call(
            'POST',
            '$self/$id/start',
            token: w.token,
            body: start(),
            expected: changeFirst && mutation != 'publish'
                ? (identity ? 401 : 422)
                : 200,
          );
          final results = await orderedBatchCommands(
            f,
            changeFirst ? change : starting,
            changeFirst ? starting : change,
          );
          if (!changeFirst || mutation == 'publish') {
            final b = results[changeFirst ? 1 : 0].body['batch'] as Map;
            expect(b['revisionId'], c['revisionId']);
            expect(
              (await f.call('GET', '$manage/$id/recipe')).body['revisionId'],
              c['revisionId'],
            );
          } else {
            expect(
              (await f.call('GET', '$manage/$id')).body['status'],
              'assigned',
            );
            expect(
              (await f.owner.execute(
                'SELECT count(*) FROM "${f.schema}".production_preparation_batches',
              )).single.first,
              0,
            );
          }
        }),
        skip: skip,
      );
    }
  }
  for (final fault in [
    'link_time',
    'opening_payload',
    'start_receipt_batch',
    'create_insert',
    'batch_insert',
    'batch_receipt',
    'batch_audit',
    'assignment_transition',
    'assignment_receipt',
    'assignment_audit',
    'deferred',
  ]) {
    test(
      'rollback all evidence at $fault; same external UUID remains reusable',
      () => withMerchandisingFixture((f) async {
        final r = await batchRecipe(f),
            w = await batchWorker(f, 'fault'),
            c = request(r, w),
            id = c['id'];
        if (fault != 'create_insert') {
          await f.call('POST', manage, body: c, expected: 201);
        }
        final before = await assignmentEvidence(f), schema = '"${f.schema}"';
        final table = switch (fault) {
          'create_insert' ||
          'assignment_transition' ||
          'link_time' ||
          'deferred' => 'production_preparation_assignments',
          'batch_insert' => 'production_preparation_batches',
          'batch_receipt' ||
          'opening_payload' => 'production_preparation_batch_commands',
          'assignment_receipt' ||
          'start_receipt_batch' => 'production_preparation_assignment_commands',
          _ => 'audit_entries',
        };
        final transition = fault == 'assignment_transition';
        final when = fault == 'batch_audit'
            ? "WHEN(NEW.action='production.batch.opened')"
            : fault == 'assignment_audit'
            ? "WHEN(NEW.action='production.preparation_assignment.started')"
            : '';
        await f.owner.execute(
          "CREATE FUNCTION $schema.assignment_test_fault() RETURNS trigger LANGUAGE plpgsql AS \$\$ BEGIN ${switch (fault) {
            'link_time' => "NEW.started_at=NEW.started_at+interval '1 second'; RETURN NEW;",
            'opening_payload' => "NEW.payload=jsonb_set(NEW.payload,'{plannedDeclaredBatchCount}','4'); RETURN NEW;",
            'start_receipt_batch' => "NEW.result=jsonb_set(NEW.result,'{batch,recipeId}',to_jsonb('${newUuid()}'::text)); RETURN NEW;",
            _ => "RAISE EXCEPTION 'Injected assignment failure' USING ERRCODE='23514';",
          }} END \$\$; CREATE ${fault == 'deferred' ? 'CONSTRAINT ' : ''}TRIGGER assignment_test_fault ${['link_time', 'opening_payload', 'start_receipt_batch'].contains(fault) ? 'BEFORE' : 'AFTER'} ${transition || fault == 'deferred' || fault == 'link_time' ? 'UPDATE' : 'INSERT'} ON $schema.$table ${fault == 'deferred' ? 'DEFERRABLE INITIALLY DEFERRED ' : ''}FOR EACH ROW $when EXECUTE FUNCTION $schema.assignment_test_fault()",
          queryMode: QueryMode.simple,
        );
        final s = start();
        await f.call(
          'POST',
          fault == 'create_insert' ? manage : '$self/$id/start',
          token: fault == 'create_insert' ? null : w.token,
          body: fault == 'create_insert' ? c : s,
          expected: 500,
        );
        expect(await assignmentEvidence(f), before);
        await f.owner.execute(
          'DROP TRIGGER assignment_test_fault ON $schema.$table',
        );
        await f.call(
          'POST',
          fault == 'create_insert' ? manage : '$self/$id/start',
          token: fault == 'create_insert' ? null : w.token,
          body: fault == 'create_insert' ? c : s,
          expected: fault == 'create_insert' ? 201 : 200,
        );
      }),
      skip: skip,
    );
  }
  test(
    'strict transport count version scope and receipt conflicts preserve evidence',
    () => withMerchandisingFixture((f) async {
      final r = await batchRecipe(f),
          w = await batchWorker(f, 'strict'),
          c = request(r, w);
      for (final value in [0, 10000, '3', 3.0, null]) {
        await f.call(
          'POST',
          manage,
          body: {...c, 'plannedDeclaredBatchCount': value},
          expected: 400,
        );
      }
      await f.call(
        'POST',
        manage,
        body: {...c, 'expectedEmployeeVersion': 2},
        expected: 409,
      );
      await f.call(
        'POST',
        manage,
        body: {...c, 'employeeId': newUuid()},
        expected: 422,
      );
      for (final field in [
        'companyId',
        'actorId',
        'batchId',
        'locationId',
        'startedAt',
      ]) {
        await f.call(
          'POST',
          manage,
          body: {...c, field: newUuid()},
          expected: 400,
        );
      }
      await f.call(
        'POST',
        manage,
        raw: '{"id":"${c['id']}","\\u0069d":"${c['id']}"}',
        expected: 400,
      );
      final nested = await f.call(
        'POST',
        manage,
        raw: '{"x":{"name":1,"\\u006eame":2}}',
        expected: 400,
      );
      expect(nested.body['code'], 'invalid_json');
      await f.call(
        'POST',
        manage,
        raw: '{"x":"${'x' * 16384}"}',
        expected: 413,
      );
      await f.call(
        'POST',
        manage,
        body: c,
        jsonContentType: false,
        expected: 415,
      );
      await f.call('POST', manage, body: c, expected: 201);
      final before = await assignmentEvidence(f);
      for (final changed in [
        {...c, 'plannedDeclaredBatchCount': 4},
        {...c, 'id': newUuid()},
        {...c, 'employeeId': newUuid()},
      ]) {
        await f.call('POST', manage, body: changed, expected: 409);
      }
      await f.call('POST', manage, body: c, token: w.token, expected: 403);
      final foreign = manage.replaceFirst(merchandisingTestLocation, newUuid());
      await f.call('GET', foreign, expected: 403);
      for (final query in [
        'unknown=1',
        'status=assigned&status=started',
        'after=%%%',
      ]) {
        await f.call('GET', '$manage?$query', expected: 400);
      }
      expect(await assignmentEvidence(f), before);
      await f.call(
        'POST',
        '$self/${c['id']}/start',
        token: w.token,
        body: {...start(), 'batchId': newUuid()},
        expected: 400,
      );
    }),
    skip: skip,
  );
  test(
    'restricted runtime cannot edit selection receipts delete or fabricate terminal evidence',
    () => withMerchandisingFixture((f) async {
      final r = await batchRecipe(f),
          w = await batchWorker(f, 'grants'),
          c = request(r, w),
          id = c['id'];
      await f.call('POST', manage, body: c, expected: 201);
      for (final sql in [
        'UPDATE "${f.schema}".production_preparation_assignments SET employee_id=employee_id',
        'UPDATE "${f.schema}".production_preparation_assignments SET recipe_id=recipe_id',
        'UPDATE "${f.schema}".production_preparation_assignments SET planned_declared_batch_count=4',
        'UPDATE "${f.schema}".production_preparation_assignment_commands SET result=result',
        'DELETE FROM "${f.schema}".production_preparation_assignments',
        'DELETE FROM "${f.schema}".production_preparation_assignment_commands',
        'TRUNCATE "${f.schema}".production_preparation_assignments',
        "UPDATE \"${f.schema}\".production_preparation_assignments SET status='started',version=2",
      ]) {
        await expectLater(
          f.pool.runTx((tx) => tx.execute(sql)),
          throwsA(isA<ServerException>()),
        );
      }
      final withdrawal = {...start(), 'reason': 'Retain forever'};
      await f.call('POST', '$manage/$id/withdraw', body: withdrawal);
      await expectLater(
        f.pool.runTx(
          (tx) => tx.execute(
            'UPDATE "${f.schema}".production_preparation_assignments SET status=\'assigned\',version=1',
          ),
        ),
        throwsA(isA<ServerException>()),
      );
      for (final payload in [
        "'{}'::jsonb",
        "'{\"operationId\":null,\"expectedVersion\":1}'::jsonb",
        "'{\"operationId\":\"${newUuid()}\",\"expectedVersion\":null}'::jsonb",
      ]) {
        expect(
          (await f.owner.execute(
            "SELECT \"${f.schema}\".preparation_assignment_command_shape('start',$payload,'{\"assignment\":{},\"batch\":{},\"replayed\":false}'::jsonb)",
          )).single.first,
          false,
        );
      }
    }),
    skip: skip,
  );
}
