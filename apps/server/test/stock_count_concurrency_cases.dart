part of 'stock_count_integration_test.dart';

Future<void> _queued(MerchandisingFixture f, int expected) async {
  final deadline = Stopwatch()..start();
  while (deadline.elapsed < const Duration(seconds: 10)) {
    final rows = await f.owner.execute(
      Sql.named(
        "SELECT count(*) FROM pg_locks WHERE locktype='advisory' AND NOT granted AND objid=(hashtext(@key)::bigint & 4294967295)::oid AND classid=((hashtext(@key)::bigint >> 32) & 4294967295)::oid",
      ),
      parameters: {
        'key': 'storeos_platform:${f.schema}:$merchandisingTestCompany',
      },
    );
    if (rows.single.first == expected) return;
  }
  fail('Expected $expected observably queued Company transactions.');
}

Future<List<MerchandisingReply>> _ordered(
  MerchandisingFixture f,
  Future<MerchandisingReply> Function() first,
  Future<MerchandisingReply> Function() second,
) async {
  final acquired = Completer<void>(), release = Completer<void>();
  final holding = f.database.runAuthorized(
    f.adminPrincipal,
    'stock.levels.manage',
    (tx, actor) async {
      acquired.complete();
      await release.future;
    },
  );
  await acquired.future;
  try {
    final a = first();
    await _queued(f, 1);
    final b = second();
    await _queued(f, 2);
    release.complete();
    await holding;
    return await Future.wait([a, b]);
  } finally {
    if (!release.isCompleted) release.complete();
    await holding;
  }
}

void registerCountConcurrencyCases() {
  for (final sameOperation in [true, false]) {
    test(
      'queued observation ${sameOperation ? 'changed payload' : 'different operation'} preserves only the first accepted evidence',
      () => withMerchandisingFixture((f) async {
        final worker = await f.counter('observation_conflict_queue');
        final c = await f.openCount(worker.employee, [
          await f.openStock((await f.stockArticle(sku: 'OBS-CONFLICT')).id),
        ]);
        final line = _lines(c).single;
        final payload = {
          ..._command(1),
          'roundId': line['round']['id'],
          'quantity': '1',
          'note': null,
        };
        final route =
            '/me/stock-counts/${c['id']}/lines/${line['id']}/observations';
        final replies = await _ordered(
          f,
          () => f.call('POST', route, token: worker.token, body: payload),
          () => f.call(
            'POST',
            route,
            token: worker.token,
            expected: 409,
            body: {
              ...payload,
              'operationId': sameOperation ? payload['operationId'] : newUuid(),
              'quantity': sameOperation ? '2' : '1',
            },
          ),
        );
        expect(
          replies.last.body['code'],
          sameOperation ? 'operation_conflict' : 'count_conflict',
        );
        final current = _lines(await f.review(c['id'] as String)).single;
        expect(current['round']['observation']['quantity'], '1');
        expect(
          (await f.owner.execute(
            'SELECT count(*) FROM "${f.schema}".stock_count_observations',
          )).single.first,
          1,
        );
      }),
      skip: _skip,
    );
  }
  test(
    'queued recount before cancellation leaves the new round open and rejects the old expected version',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('recount_cancel_queue');
      var c = await f.openCount(worker.employee, [
        await f.openStock((await f.stockArticle(sku: 'RECOUNT-CANCEL')).id),
      ]);
      c = await f.observeCount(c, 0, worker.token, '1');
      final replies = await _ordered(
        f,
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          body: {
            ..._command(c['version'] as int),
            'lineIds': [_lines(c).single['id']],
            'reason': 'Fresh round first',
          },
        ),
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/cancel',
          expected: 409,
          body: {
            ..._command(c['version'] as int),
            'reason': 'Old cancellation version',
          },
        ),
      );
      expect(replies.last.body['code'], 'count_conflict');
      final current = await f.review(c['id'] as String);
      expect(current['status'], 'open');
      expect(_lines(current).single['round']['number'], 2);
      expect(_lines(current).single['round']['observation'], isNull);
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_count_observations',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );
  for (final approvalFirst in [true, false]) {
    test(
      'observable Company queue serializes approval ${approvalFirst ? 'before' : 'after'} manual Stock correction',
      () => withMerchandisingFixture((f) async {
        final worker = await f.counter('queue_worker');
        final level = await f.openStock(
          (await f.stockArticle(sku: 'QUEUE')).id,
          quantity: '5',
        );
        var c = await f.openCount(worker.employee, [level]);
        c = await f.observeCount(c, 0, worker.token, '4');
        Future<MerchandisingReply> approve() => f.call(
          'POST',
          '${_root(c['id'] as String)}/approve',
          body: _command(c['version'] as int),
          expected: null,
        );
        Future<MerchandisingReply> adjust() => f.call(
          'POST',
          '/locations/$_location/stock/${level.id}/adjust',
          body: {
            'movementId': newUuid(),
            'expectedVersion': 1,
            'quantity': '6',
            'note': 'Serialized ordinary correction',
          },
          expected: null,
        );
        final replies = await _ordered(
          f,
          approvalFirst ? approve : adjust,
          approvalFirst ? adjust : approve,
        );
        expect(replies.map((r) => r.status), [200, 409]);
        expect(
          replies.last.body['code'],
          approvalFirst ? 'stock_conflict' : 'count_stale',
        );
        expect((await f.level(level.id)).quantity, approvalFirst ? '4' : '6');
        await f.assertLedgerInvariant(level.id);
      }),
      skip: _skip,
    );
  }
  for (final recountFirst in [true, false]) {
    test(
      'observation/recount Company ordering ${recountFirst ? 'recount' : 'observation'} first retains exact round',
      () => withMerchandisingFixture((f) async {
        final worker = await f.counter('round_queue');
        final c = await f.openCount(worker.employee, [
          await f.openStock((await f.stockArticle(sku: 'ROUND-QUEUE')).id),
        ]);
        final line = _lines(c).single;
        Future<MerchandisingReply> recount() => f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          expected: null,
          body: {
            ..._command(1),
            'lineIds': [line['id']],
            'reason': 'Ordered recount',
          },
        );
        Future<MerchandisingReply> observe() => f.call(
          'POST',
          '/me/stock-counts/${c['id']}/lines/${line['id']}/observations',
          expected: null,
          token: worker.token,
          body: {
            ..._command(1),
            'roundId': line['round']['id'],
            'quantity': '1',
            'note': null,
          },
        );
        final replies = await _ordered(
          f,
          recountFirst ? recount : observe,
          recountFirst ? observe : recount,
        );
        expect(replies.map((r) => r.status), [200, 409]);
        final current = _lines(await f.review(c['id'] as String)).single;
        expect(current['round']['number'], recountFirst ? 2 : 1);
        expect(current['round']['observation'] == null, recountFirst);
      }),
      skip: _skip,
    );
  }
  test(
    'queued exact duplicate observation replays; different operations, two recounts and cancellation never duplicate evidence',
    () => withMerchandisingFixture((f) async {
      final worker = await f.counter('duplicate_queue');
      var c = await f.openCount(worker.employee, [
        await f.openStock((await f.stockArticle(sku: 'DUP-QUEUE')).id),
      ]);
      final line = _lines(c).single;
      final payload = {
        ..._command(1),
        'roundId': line['round']['id'],
        'quantity': '1',
        'note': null,
      };
      final route =
          '/me/stock-counts/${c['id']}/lines/${line['id']}/observations';
      final duplicate = await _ordered(
        f,
        () => f.call('POST', route, token: worker.token, body: payload),
        () => f.call('POST', route, token: worker.token, body: payload),
      );
      expect(duplicate.first.body, duplicate.last.body);
      c = await f.review(c['id'] as String);
      final recount = {
        ..._command(c['version'] as int),
        'lineIds': [line['id']],
        'reason': 'Concurrent checks',
      };
      final two = await _ordered(
        f,
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          body: recount,
        ),
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          expected: 409,
          body: {...recount, 'operationId': newUuid()},
        ),
      );
      expect(two.last.body['code'], 'count_conflict');
      c = await f.review(c['id'] as String);
      await _ordered(
        f,
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/cancel',
          body: {..._command(c['version'] as int), 'reason': 'Terminal cancel'},
        ),
        () => f.call(
          'POST',
          '${_root(c['id'] as String)}/recount',
          expected: 409,
          body: {
            ..._command(c['version'] as int),
            'lineIds': [line['id']],
            'reason': 'Too late',
          },
        ),
      );
      expect((await f.review(c['id'] as String))['status'], 'cancelled');
      expect(
        (await f.owner.execute(
          'SELECT count(*) FROM "${f.schema}".stock_count_observations',
        )).single.first,
        1,
      );
    }),
    skip: _skip,
  );
}
