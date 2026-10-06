part of 'stock_count_integration_test.dart';

void registerCountIntegrityCases() {
  test(
    'count HTTP boundary sanitizes PostgreSQL privilege failure as operational unavailability',
    () => withMerchandisingFixture((f) async {
      await f.owner.execute(
        'REVOKE SELECT ON "${f.schema}".stock_counts FROM "${f.runtimeUser}"',
      );
      try {
        final reply = await f.call(
          'GET',
          '/locations/$_location/stock-counts',
          expected: 503,
        );
        expect(reply.body['code'], 'database_unavailable');
        expect(reply.body['message'], 'Count database operation failed.');
        expect(reply.body.toString(), isNot(contains(f.schema)));
        expect(reply.body.toString(), isNot(contains('permission denied')));
      } finally {
        await f.owner.execute(
          'GRANT SELECT ON "${f.schema}".stock_counts TO "${f.runtimeUser}"',
        );
      }
    }),
    skip: _skip,
  );
  test(
    'third stale line and one self-recorded current line reject the entire three-line approval',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('three_worker');
      final levels = <StockLevelDto>[];
      for (var i = 0; i < 3; i++) {
        levels.add(
          await f.openStock(
            (await f.stockArticle(sku: 'THREE-$i')).id,
            quantity: '5',
          ),
        );
      }
      var c = await f.openCount(worker.employee, levels);
      for (var i = 0; i < 3; i++) {
        c = await f.observeCount(c, i, worker.token, '4');
      }
      await f.adjustStock(
        levels[2],
        movementId: newUuid(),
        quantity: '6',
        note: 'Third line stale',
      );
      final before = await f.countState(c['id'] as String);
      await f.call(
        'POST',
        '${_root(c['id'] as String)}/approve',
        body: _command(c['version'] as int),
        expected: 409,
      );
      expect(await f.countState(c['id'] as String), before);
      for (var i = 0; i < 2; i++) {
        expect((await f.level(levels[i].id)).toJson(), levels[i].toJson());
      }
      final recorder = await f.counter('three_self', role: 'admin');
      final link = (await f.call(
        'GET',
        '/employees/${worker.employee}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': 1},
      );
      final ownLink = (await f.call(
        'GET',
        '/employees/${recorder.employee}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${ownLink['id']}/revoke',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'POST',
        '/employees/${worker.employee}/account-link',
        expected: 201,
        body: {
          'id': newUuid(),
          'accountId': recorder.account,
          'expectedEmployeeVersion': 1,
          'expectedAccountVersion': 1,
        },
      );
      c = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/recount',
        body: {
          ..._command(c['version'] as int),
          'lineIds': [_lines(c)[2]['id']],
          'reason': 'Fresh third line',
        },
      )).body;
      final fresh = await f.login('three_self');
      c = await f.observeCount(c, 2, fresh, '5');
      final selfBefore = await f.countState(c['id'] as String);
      expect(
        (await f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          token: fresh,
          body: _command(c['version'] as int),
          expected: 422,
        )).body['code'],
        'self_approval_forbidden',
      );
      expect(await f.countState(c['id'] as String), selfBefore);
    }),
    skip: _skip,
  );
  test(
    'approved plugin, foreign Company, expired session and changed current role cannot disclose/replay count evidence',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('auth_worker');
      final level = await f.openStock((await f.stockArticle(sku: 'AUTH')).id);
      final manager = await f.counter('replay_manager', role: 'admin');
      final payload = {
        'operationId': newUuid(),
        'id': newUuid(),
        'employeeId': worker.employee,
        'stockLevelIds': [level.id],
        'purpose': 'Scoped replay',
        'precedingCountId': null,
      };
      await f.call(
        'POST',
        '/locations/$_location/stock-counts',
        token: manager.token,
        body: payload,
        expected: 201,
      );
      final foreign = SessionPrincipal(
        id: f.adminId,
        username: 'test_admin',
        companyId: newUuid(),
        locationId: _location,
        tokenHash: f.adminPrincipal.tokenHash,
      );
      await expectLater(
        StockCountService(
          f.database,
        ).get(foreign, _location, payload['id'] as String),
        throwsA(
          isA<PlatformFailure>().having((e) => e.status, 'Company denied', 403),
        ),
      );
      const pluginId = 'stock.counts-denied';
      await f.call(
        'POST',
        '/plugins',
        expected: 201,
        body: {
          'manifest': {
            'id': pluginId,
            'name': 'Denied Count Plugin',
            'version': '1.0.0',
            'vendor': 'Acceptance',
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
      final plugin =
          (await f.call(
                'POST',
                '/plugins/$pluginId/approve',
                body: {
                  'expectedVersion': 1,
                  'locationId': _location,
                  'permissions': ['organization.read'],
                  'subscriptions': <String>[],
                },
              )).body['token']
              as String;
      await f.call(
        'GET',
        '/locations/$_location/stock-counts',
        token: plugin,
        expected: 401,
      );
      await f.call('GET', '/me/stock-counts', token: plugin, expected: 401);
      await f.auth.logout(worker.token);
      await f.call(
        'GET',
        '/me/stock-counts',
        token: worker.token,
        expected: 401,
      );
      await f.call(
        'POST',
        '/users/${manager.account}',
        body: {'expectedVersion': 1, 'role': 'viewer', 'isActive': true},
      );
      final fresh = await f.login('replay_manager');
      await f.call(
        'POST',
        '/locations/$_location/stock-counts',
        token: fresh,
        body: payload,
        expected: 403,
      );
      await f.call(
        'GET',
        _root(payload['id'] as String),
        token: fresh,
        expected: 403,
      );
    }),
    skip: _skip,
  );
  test(
    'runtime grants and database guards retain immutable observations, rounds, identities and terminal evidence',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('integrity_worker');
      final level = await f.openStock(
        (await f.stockArticle(sku: 'INTEGRITY')).id,
        quantity: '5',
      );
      var c = await f.openCount(worker.employee, [level]);
      c = await f.observeCount(c, 0, worker.token, '4');
      final line = _lines(c).single;
      final id = c['id'];
      final round = line['round']['id'];
      final observation = line['round']['observation']['id'];
      for (final table in [
        'stock_counts',
        'stock_count_lines',
        'stock_count_rounds',
        'stock_count_observations',
        'stock_count_commands',
      ]) {
        await expectLater(
          f.pool.execute('DELETE FROM "${f.schema}".$table'),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'permission', '42501'),
          ),
        );
      }
      for (final sql in [
        "UPDATE \"${f.schema}\".stock_counts SET purpose='tamper' WHERE id='$id'",
        "UPDATE \"${f.schema}\".stock_count_lines SET sku='tamper' WHERE id='${line['id']}'",
        "UPDATE \"${f.schema}\".stock_count_rounds SET baseline_scaled=0 WHERE id='$round'",
        "UPDATE \"${f.schema}\".stock_count_observations SET observed_scaled=0 WHERE id='$observation'",
        "UPDATE \"${f.schema}\".stock_count_commands SET result='{}'::jsonb",
      ]) {
        await expectLater(
          f.pool.execute(sql),
          throwsA(
            isA<ServerException>().having((e) => e.code, 'permission', '42501'),
          ),
        );
        await expectLater(
          f.owner.execute(sql),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'immutability',
              '23514',
            ),
          ),
        );
      }
      final approved = (await f.call(
        'POST',
        '${_root(id as String)}/approve',
        body: _command(c['version'] as int),
      )).body;
      final movement = _lines(approved).single['outcome']['movementId'];
      for (final sql in [
        "UPDATE \"${f.schema}\".stock_counts SET version=version+1 WHERE id='$id'",
        "UPDATE \"${f.schema}\".stock_count_lines SET checked_stock_version=6 WHERE id='${line['id']}'",
        "UPDATE \"${f.schema}\".stock_movements SET count_id=NULL WHERE id='$movement'",
      ]) {
        await expectLater(
          f.owner.execute(sql),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'terminal immutability',
              '23514',
            ),
          ),
        );
      }
      final cancelled = await f.openCount(worker.employee, [
        await f.level(level.id),
      ]);
      await f.call(
        'POST',
        '${_root(cancelled['id'] as String)}/cancel',
        body: {..._command(1), 'reason': 'Terminal'},
      );
      await expectLater(
        f.owner.execute(
          "UPDATE \"${f.schema}\".stock_counts SET version=version+1 WHERE id='${cancelled['id']}'",
        ),
        throwsA(
          isA<ServerException>().having(
            (e) => e.code,
            'cancelled immutable',
            '23514',
          ),
        ),
      );
    }),
    skip: _skip,
  );

  test(
    'provenance rejects missing, duplicate, unrelated and legacy count identities; zero evidence cannot drift',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('provenance_worker');
      final a = await f.openStock(
        (await f.stockArticle(sku: 'PROV-A')).id,
        quantity: '5',
      );
      final b = await f.openStock(
        (await f.stockArticle(sku: 'PROV-B')).id,
        quantity: '5',
      );
      var c = await f.openCount(worker.employee, [a, b]);
      c = await f.observeCount(c, 0, worker.token, '4');
      c = await f.observeCount(c, 1, worker.token, '5');
      final approved = (await f.call(
        'POST',
        '${_root(c['id'] as String)}/approve',
        body: _command(c['version'] as int),
      )).body;
      final nonzero = _lines(approved).first;
      final zero = _lines(approved).last;
      for (final mode in ['missing', 'legacy', 'duplicate', 'unrelated']) {
        final movementId = newUuid();
        final kind = mode == 'legacy' ? 'adjustment' : 'count_correction';
        final count = mode == 'missing' ? 'NULL' : "'${approved['id']}'::uuid";
        final line = mode == 'unrelated' ? zero : nonzero;
        final sql =
            "INSERT INTO \"${f.schema}\".stock_movements (id,stock_level_id,company_id,location_id,article_id,kind,delta_scaled,balance_after_scaled,balance_version,recorded_by,count_id,count_line_id,count_observation_id) SELECT '$movementId'::uuid,stock_level_id,company_id,location_id,article_id,'$kind',-1000,4000,99,recorded_by,$count,'${line['id']}'::uuid,'${line['round']['observation']['id']}'::uuid FROM \"${f.schema}\".stock_movements WHERE id='${nonzero['outcome']['movementId']}'";
        await expectLater(
          f.pool.execute(sql),
          throwsA(
            isA<ServerException>().having(
              (e) => {'23503', '23505', '23514'}.contains(e.code),
              'constraint rejected',
              isTrue,
            ),
          ),
        );
      }
      await expectLater(
        f.owner.execute(
          "UPDATE \"${f.schema}\".stock_count_lines SET movement_id='${nonzero['outcome']['movementId']}' WHERE id='${zero['id']}'",
        ),
        throwsA(isA<ServerException>()),
      );
      final fresh = await f.openCount(worker.employee, [await f.level(a.id)]);
      final sourceLine = _lines(fresh).single;
      for (final position in [0, 101, 1]) {
        await expectLater(
          f.pool.execute(
            "INSERT INTO \"${f.schema}\".stock_count_lines (id,count_id,company_id,location_id,stock_level_id,article_id,position,stock_unit,sku,article_name,barcode) SELECT '${newUuid()}'::uuid,count_id,company_id,location_id,stock_level_id,article_id,$position,stock_unit,sku,article_name,barcode FROM \"${f.schema}\".stock_count_lines WHERE id='${sourceLine['id']}'",
          ),
          throwsA(isA<ServerException>()),
        );
      }
      expect((await f.countState(approved['id'] as String))['movements'], 1);
    }),
    skip: _skip,
  );

  test(
    'deactivation and unlinking block new observations/recounts while retaining historical manager evidence',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('eligibility_worker');
      var c = await f.openCount(worker.employee, [
        await f.openStock((await f.stockArticle(sku: 'ELIG')).id),
      ]);
      c = await f.observeCount(c, 0, worker.token, '1');
      final id = c['id'] as String;
      await f.call(
        'POST',
        '/employees/${worker.employee}/deactivate',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'GET',
        '/me/stock-counts/$id',
        token: worker.token,
        expected: 401,
      );
      final fresh = await f.login('eligibility_worker');
      await f.call('GET', '/me/stock-counts/$id', token: fresh, expected: 404);
      expect(
        (await f.call(
          'POST',
          '${_root(id)}/recount',
          body: {
            ..._command(c['version'] as int),
            'lineIds': [_lines(c).single['id']],
            'reason': 'Unavailable assignee',
          },
          expected: 422,
        )).body['code'],
        'assignee_unavailable',
      );
      expect(
        _lines(await f.review(id)).single['round']['observation']['quantity'],
        '1',
      );
      final accepted = (await f.call(
        'POST',
        '${_root(id)}/approve',
        body: _command(c['version'] as int),
      )).body;
      expect(accepted['status'], 'approved');
      final second = await f.counter('unlink_worker');
      c = await f.openCount(second.employee, [
        await f.openStock((await f.stockArticle(sku: 'UNLINK')).id),
      ]);
      final link = (await f.call(
        'GET',
        '/employees/${second.employee}/account-link',
      )).body['link'];
      await f.call(
        'POST',
        '/employee-links/${link['id']}/revoke',
        body: {'expectedVersion': 1},
      );
      await f.call(
        'GET',
        '/me/stock-counts/${c['id']}',
        token: await f.login('unlink_worker'),
        expected: 404,
      );
    }),
    skip: _skip,
  );

  test(
    'incomplete/version errors, bounded transport and scoped pagination are explicit',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('errors_worker');
      final level = await f.openStock((await f.stockArticle(sku: 'ERRORS')).id);
      final c = await f.openCount(worker.employee, [level]);
      final id = c['id'] as String;
      expect(
        (await f.call(
          'POST',
          '${_root(id)}/approve',
          body: _command(1),
          expected: 422,
        )).body['code'],
        'count_incomplete',
      );
      expect(
        (await f.call(
          'POST',
          '${_root(id)}/cancel',
          body: {..._command(2), 'reason': 'Mismatch'},
          expected: 409,
        )).body['code'],
        'count_conflict',
      );
      await f.call('POST', '${_root(id)}/approve', raw: '{', expected: 400);
      await f.call(
        'POST',
        '${_root(id)}/approve',
        raw: '{}',
        jsonContentType: false,
        expected: 415,
      );
      await f.call(
        'POST',
        '${_root(id)}/approve',
        raw: 'x' * 16385,
        expected: 413,
      );
      await f.call(
        'GET',
        '${_root(id)}/lines/${_lines(c).single['id']}/rounds?after=invalid',
        expected: 400,
      );
      for (var i = 0; i < 50; i++) {
        await f.openCount(worker.employee, [level]);
      }
      final first = (await f.call(
        'GET',
        '/locations/$_location/stock-counts',
      )).body;
      expect(first['items'], hasLength(50));
      final next = (await f.call(
        'GET',
        '/locations/$_location/stock-counts?after=${first['nextCursor']}',
      )).body;
      expect(next['items'], hasLength(1));
      expect(next['nextCursor'], isNull);
      final ids = [
        ...first['items'] as List,
        ...next['items'] as List,
      ].map((row) => row['id'] as String).toList();
      expect(ids.toSet(), hasLength(51));
      expect(ids, orderedEquals([...ids]..sort()));
      await f.call(
        'GET',
        '/me/stock-counts?after=${first['nextCursor']}',
        token: worker.token,
        expected: 400,
      );
      _blind(
        (await f.call('GET', '/me/stock-counts', token: worker.token)).body,
      );
      var current = c;
      for (var i = 0; i < 50; i++) {
        current = (await f.call(
          'POST',
          '${_root(id)}/recount',
          body: {
            ..._command(current['version'] as int),
            'lineIds': [_lines(c).single['id']],
            'reason': 'History page',
          },
        )).body;
      }
      final history = (await f.call(
        'GET',
        '${_root(id)}/lines/${_lines(c).single['id']}/rounds',
      )).body;
      expect(history['items'], hasLength(50));
      final last = (await f.call(
        'GET',
        '${_root(id)}/lines/${_lines(c).single['id']}/rounds?after=${history['nextCursor']}',
      )).body;
      expect(last['items'], hasLength(1));
      expect(
        [
          ...history['items'] as List,
          ...last['items'] as List,
        ].map((row) => row['number']),
        orderedEquals(List.generate(51, (i) => 51 - i)),
      );
      final ownHistory = (await f.call(
        'GET',
        '/me/stock-counts/$id/lines/${_lines(c).single['id']}/rounds',
        token: worker.token,
      )).body;
      final ownLast = (await f.call(
        'GET',
        '/me/stock-counts/$id/lines/${_lines(c).single['id']}/rounds?after=${ownHistory['nextCursor']}',
        token: worker.token,
      )).body;
      _blind(ownHistory);
      _blind(ownLast);
      expect(
        [
          ...ownHistory['items'] as List,
          ...ownLast['items'] as List,
        ].map((row) => row['number']),
        orderedEquals(List.generate(51, (i) => 51 - i)),
      );
      await f.call(
        'GET',
        '/me/stock-counts/$id/lines/${_lines(c).single['id']}/rounds?after=${history['nextCursor']}',
        token: worker.token,
        expected: 400,
      );
      await f.call(
        'GET',
        '${_root(next['items'][0]['id'] as String)}/lines/${_lines(c).single['id']}/rounds?after=${history['nextCursor']}',
        expected: 400,
      );
    }),
    skip: _skip,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
