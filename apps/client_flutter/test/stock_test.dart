import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/application/stock_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/stock_section.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
const _second = '33333333-3333-4333-8333-333333333333';
const _mehl = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _milch = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _levelId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const _assoc = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

ArticleAssortmentDto _candidate({
  String id = _assoc,
  String articleId = _mehl,
  String name = 'Mehl',
  String unit = 'kg',
  bool articleActive = true,
}) => ArticleAssortmentDto(
  id: id,
  locationId: _location,
  isActive: true,
  version: 1,
  createdAt: DateTime.utc(2030, 1, 1, 8),
  updatedAt: DateTime.utc(2030, 1, 1, 8),
  article: ArticleAssortmentArticleDto(
    id: articleId,
    sku: 'SKU-1',
    barcode: null,
    name: name,
    unit: unit,
    isActive: articleActive,
  ),
);

StockLevelDto _level({
  String id = _levelId,
  String articleId = _mehl,
  String name = 'Mehl',
  String sku = 'SKU-1',
  String quantity = '7',
  String stockUnit = 'kg',
  String articleUnit = 'kg',
  bool articleActive = true,
  bool assortmentActive = true,
  int version = 1,
}) => StockLevelDto(
  id: id,
  locationId: _location,
  articleId: articleId,
  stockUnit: stockUnit,
  quantity: quantity,
  version: version,
  createdAt: DateTime.utc(2030, 1, 1, 8),
  updatedAt: DateTime.utc(2030, 1, 1, 8),
  article: StockArticleDto(
    id: articleId,
    sku: sku,
    barcode: null,
    name: name,
    unit: articleUnit,
    isActive: articleActive,
  ),
  assortmentIsActive: assortmentActive,
);

StockMovementDto _movement({
  String id = 'ffffffff-ffff-4fff-8fff-ffffffffffff',
  String kind = 'opening',
  String delta = '7',
  String balanceAfter = '7',
  int balanceVersion = 1,
  String? note,
}) => StockMovementDto(
  id: id,
  kind: kind,
  delta: delta,
  balanceAfter: balanceAfter,
  balanceVersion: balanceVersion,
  recordedAt: DateTime.utc(2030, 1, 1, 8),
  recordedBy: _company,
  note: note,
);

void main() {
  test('capability gating blocks every stock request', () async {
    final f = await _Fixture.create('viewer');
    addTearDown(f.dispose);
    expect(f.controller.canManage, isFalse);
    await f.controller.selectLocation(_location);
    expect(f.api.stockRequests, isEmpty);
    expect(f.api.postCount, 0);
    expect(f.controller.items, isNull);
  });

  test('selecting a location loads levels and search is literal', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.addAll([
      _level(),
      _level(
        id: '99999999-9999-4999-8999-999999999999',
        articleId: _milch,
        name: 'Vollmilch',
        sku: 'MILCH-1',
      ),
    ]);
    await f.controller.selectLocation(_location);
    expect(f.api.queries.last['q'], isNull);
    expect(f.controller.items, hasLength(2));
    await f.controller.setSearch('MILCH-1');
    expect(f.api.queries.last['q'], 'MILCH-1');
    expect(f.controller.items, hasLength(1));
    expect(f.controller.items!.single.articleId, _milch);
    await f.controller.selectLocation(_second);
    expect(f.controller.items, isEmpty);
  });

  test('open posts a client UUID and reconciles a lost response', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.candidates.add(_candidate());
    f.api.loseOpenResponse = true;
    await f.controller.openStock(_candidate());
    expect(f.api.postCount, 1);
    expect(f.api.lastOpenBody!['articleId'], _mehl);
    expect(f.api.lastOpenBody!['id'], isA<String>());
    expect(f.api.lastOpenBody!['quantity'], '0');
    expect(f.api.lastOpenBody!['note'], isNull);
    expect(f.controller.error, isNull);
    expect(f.controller.notice, contains('erneut geladen'));
    expect(f.controller.items, hasLength(1));
  });

  test('open conflicts are explainable', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    for (final entry in {
      'article_inactive': 'global inaktiv',
      'not_in_assortment': 'Sortimentsfreigabe',
      'already_exists': 'bereits Bestand',
    }.entries) {
      f.api.failOpen = StoreApiException(
        entry.key,
        'conflict',
        statusCode: 409,
      );
      await f.controller.openStock(_candidate());
      expect(f.controller.error, contains(entry.value));
    }
  });

  test('open picker excludes globally inactive articles', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.candidates.addAll([
      _candidate(articleId: _mehl, name: 'Milchpulver'),
      _candidate(
        id: '99999999-9999-4999-8999-999999999999',
        articleId: _milch,
        name: 'Vollmilch',
        articleActive: false,
      ),
    ]);
    final results = await f.controller.searchOpenCandidates('milch');
    expect(results, hasLength(1));
    expect(results.single.article.name, 'Milchpulver');
  });

  test('adjust sends the operation identity, target and reason', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.levels.add(_level());
    await f.controller.load();
    final level = f.controller.items!.single;
    await f.controller.adjust(level, ' 12.500 ', '  Zugang  ');
    expect(f.api.lastAdjustBody!['expectedVersion'], 1);
    expect(f.api.lastAdjustBody!['quantity'], '12.5');
    expect(f.api.lastAdjustBody!['note'], 'Zugang');
    expect(f.api.lastAdjustBody!['movementId'], isA<String>());
    expect(f.controller.error, isNull);
    expect(f.controller.items!.single.quantity, '12.5');
    expect(f.controller.items!.single.version, 2);
    expect(f.controller.pendingAdjustment, isNull);
  });

  test('invalid adjustments never reach the server', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.levels.add(_level());
    await f.controller.load();
    final level = f.controller.items!.single;
    await f.controller.adjust(level, '-1', 'Grund');
    expect(f.api.postCount, 0);
    expect(f.controller.error, contains('nicht negativ'));
    await f.controller.adjust(level, '1', '   ');
    expect(f.api.postCount, 0);
    expect(f.controller.error, contains('Begründung'));
    await f.controller.adjust(level, '1.0001', 'Grund');
    expect(f.api.postCount, 0);
  });

  test(
    'a lost committed response remains uncertain until direct exact replay',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      await f.controller.selectLocation(_location);
      f.api.levels.add(_level());
      await f.controller.load();
      f.api.adjustThrows = true;
      f.api.adjustApplies = true;
      await f.controller.adjust(f.controller.items!.single, '12.5', 'Zugang');
      expect(f.api.postCount, 1);
      expect(
        f.controller.adjustmentResult!.outcome,
        StockAdjustmentOutcome.unconfirmed,
      );
      final original = f.controller.pendingAdjustment!;
      f.api.adjustThrows = false;
      final result = await f.controller.retryPendingAdjustment();
      expect(result.outcome, StockAdjustmentOutcome.confirmedMutation);
      expect(f.api.lastAdjustBody, original.input.toJson());
      expect(f.api.adjustedAuditCount, 1);
      expect(f.api.movements[_levelId], hasLength(1));
      expect(f.controller.pendingAdjustment, isNull);
      expect(f.controller.items!.single.quantity, '12.5');
    },
  );

  test('another actor\'s later command is never attributed', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.levels.add(_level());
    await f.controller.load();
    f.api.adjustThrows = true;
    f.api.adjustApplies = false;
    await f.controller.adjust(f.controller.items!.single, '12.5', 'Zugang');
    expect(f.api.postCount, 1);
    expect(f.controller.error, contains('nicht bestätigt'));
    f.api.adjustThrows = false;
    f.api.adjustApplies = true;
    await f.api
        .post('other:1', '/locations/$_location/stock/$_levelId/adjust', {
          'movementId': '88888888-8888-4888-8888-888888888888',
          'expectedVersion': 1,
          'quantity': '12.5',
          'note': 'Other actor',
        });
    await f.controller.load();
    expect(f.controller.items!.single.quantity, '12.5');
    expect(
      f.controller.adjustmentResult!.outcome,
      StockAdjustmentOutcome.unconfirmed,
    );
    expect(f.controller.pendingAdjustment, isNotNull);
  });

  test(
    'unused stale retry conflicts and requires an explicit new decision',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      await f.controller.selectLocation(_location);
      f.api.levels.add(_level());
      await f.controller.load();
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      await f.controller.adjust(f.controller.items!.single, '12.5', 'Zugang');
      final firstId = f.api.lastAdjustBody!['movementId'];
      f.api.adjustThrows = false;
      f.api.adjustApplies = true;
      await f.api
          .post('other:1', '/locations/$_location/stock/$_levelId/adjust', {
            'movementId': '88888888-8888-4888-8888-888888888888',
            'expectedVersion': 1,
            'quantity': '12.5',
            'note': 'Other actor',
          });
      final result = await f.controller.retryPendingAdjustment();
      expect(f.api.postCount, 3);
      expect(f.api.lastAdjustBody!['movementId'], firstId);
      expect(f.controller.pendingAdjustment, isNull);
      expect(result.outcome, StockAdjustmentOutcome.conflict);
      expect(f.controller.conflict, isTrue);
      expect(f.api.adjustedAuditCount, 1);
      expect(f.api.movements[_levelId]!.where((m) => m.id == firstId), isEmpty);
      await f.controller.adjust(f.api.levels.single, '15', 'new');
      expect(f.api.postCount, 3);
      await f.controller.prepareNewAdjustment();
      await f.controller.adjust(f.controller.items!.single, '15', 'new');
      expect(f.api.postCount, 4);
      expect(f.api.lastAdjustBody!['movementId'], isNot(firstId));
      expect(f.api.lastAdjustBody!['expectedVersion'], 2);
    },
  );

  test(
    'duplicate pending submission cannot allocate or replace identity',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      final gate = f.api.adjustmentGate = Completer<void>();
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      final first = f.controller.adjust(
        f.api.levels.single,
        ' 12.500 ',
        ' Zugang ',
      );
      final original = f.controller.pendingAdjustment;
      final result = await f.controller.adjust(
        f.api.levels.single,
        '99',
        'replacement',
      );
      expect(result.outcome, StockAdjustmentOutcome.ignored);
      expect(f.controller.pendingAdjustment, same(original));
      expect(f.movementIds, 1);
      expect(f.api.postCount, 1);
      gate.complete();
      expect((await first).outcome, StockAdjustmentOutcome.unconfirmed);
      expect(f.controller.pendingAdjustment, same(original));
      expect(original!.input.toJson(), f.api.adjustmentBodies.single);
      expect(original.input.expectedVersion, 1);
      expect(original.input.quantity, '12.5');
      expect(original.input.note, 'Zugang');
      f.api.adjustThrows = false;
      f.api.adjustApplies = true;
      expect((await f.controller.retryPendingAdjustment()).confirmed, isTrue);
      expect(f.api.adjustmentBodies.last, f.api.adjustmentBodies.first);
      expect(f.movementIds, 1);
    },
  );

  test('validation includes note bounds and creates no identity', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    for (final input in [
      ('-1', 'reason'),
      ('1.0001', 'reason'),
      ('1000000000000', 'reason'),
      ('1', ''),
      ('1', 'x' * 501),
      ('1', 'line\nbreak'),
      ('1', '\uD800'),
    ]) {
      expect(
        (await f.controller.adjust(_level(), input.$1, input.$2)).outcome,
        StockAdjustmentOutcome.invalidInput,
      );
      expect(f.controller.pendingAdjustment, isNull);
    }
    expect(f.movementIds, 0);
    expect(f.api.postCount, 0);
  });

  test(
    'committed replay returns later current level without extra effects',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      f.api.adjustThrows = true;
      await f.controller.adjust(f.api.levels.single, '12.5', 'first');
      final original = f.controller.pendingAdjustment!;
      f.api.adjustThrows = false;
      await f.api
          .post('other:1', '/locations/$_location/stock/$_levelId/adjust', {
            'movementId': '77777777-7777-4777-8777-777777777777',
            'expectedVersion': 2,
            'quantity': '20',
            'note': 'later',
          });
      final before = f.api.adjustedAuditCount;
      expect(
        (await f.controller.retryPendingAdjustment()).outcome,
        StockAdjustmentOutcome.confirmedMutation,
      );
      expect(f.api.lastAdjustBody, original.input.toJson());
      expect(f.controller.items!.single.quantity, '20');
      expect(f.controller.items!.single.version, 3);
      expect(f.api.adjustedAuditCount, before);
      expect(f.api.movements[_levelId], hasLength(2));
    },
  );

  test(
    'partial history and matching quantity never resolve uncertainty',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      f.api.adjustThrows = true;
      await f.controller.adjust(f.api.levels.single, '12.5', 'first');
      final original = f.controller.pendingAdjustment!;
      f.api.adjustThrows = false;
      await f.api
          .post('other:1', '/locations/$_location/stock/$_levelId/adjust', {
            'movementId': '77777777-7777-4777-8777-777777777777',
            'expectedVersion': 2,
            'quantity': '20',
            'note': 'later',
          });
      f.api.pageSize = 1;
      final page = await f.controller.loadMovements(f.api.levels.single);
      expect(page.items.any((m) => m.id == original.movementId), isFalse);
      expect(page.nextCursor, isNotNull);
      await f.controller.load();
      expect(f.controller.pendingAdjustment, same(original));
      expect(
        f.controller.adjustmentResult!.outcome,
        StockAdjustmentOutcome.unconfirmed,
      );
      expect((await f.controller.retryPendingAdjustment()).confirmed, isTrue);
    },
  );

  test(
    'confirmed write plus refresh failure never offers correction retry',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      f.api.failStockList = true;
      final result = await f.controller.adjust(
        f.api.levels.single,
        '12.5',
        'reason',
      );
      expect(result.outcome, StockAdjustmentOutcome.confirmedMutation);
      expect(result.refreshFailed, isTrue);
      expect(f.controller.pendingAdjustment, isNull);
      expect(f.controller.refreshError, isNotNull);
      expect(f.controller.items!.single.version, 2);
      await f.controller.retryPendingAdjustment();
      expect(f.api.postCount, 1);
      f.api.failStockList = false;
      await f.controller.load();
      expect(f.controller.refreshError, isNull);
      expect(f.controller.adjustmentResult!.confirmed, isTrue);
    },
  );

  test(
    'no-op consumes no movement/audit/id and next correction is fresh',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      final result = await f.controller.adjust(
        f.api.levels.single,
        '7.000',
        'reason',
      );
      final unused = f.api.lastAdjustBody!['movementId'];
      expect(result.outcome, StockAdjustmentOutcome.confirmedNoOp);
      expect(f.controller.pendingAdjustment, isNull);
      expect(f.api.movements, isEmpty);
      expect(f.api.committed, isEmpty);
      expect(f.api.adjustedAuditCount, 0);
      expect(f.api.levels.single.version, 1);
      expect(f.controller.notice, contains('Keine Bestandsbewegung'));
      await f.controller.adjust(f.api.levels.single, '9', 'new');
      expect(f.api.lastAdjustBody!['movementId'], isNot(unused));
      expect(f.api.adjustedAuditCount, 1);
    },
  );

  test('operation conflict is definitive and never auto-resends', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.add(_level());
    await f.controller.selectLocation(_location);
    f.api.adjustThrows = true;
    f.api.adjustApplies = false;
    await f.controller.adjust(f.api.levels.single, '9', 'reason');
    final original = f.controller.pendingAdjustment!;
    f.api.adjustThrows = false;
    f.api.adjustApplies = true;
    await f.api.post(
      'other:1',
      '/locations/$_location/stock/$_levelId/adjust',
      {...original.input.toJson(), 'quantity': '8'},
    );
    final result = await f.controller.retryPendingAdjustment();
    expect(result.outcome, StockAdjustmentOutcome.conflict);
    expect(f.controller.pendingAdjustment, isNull);
    expect(f.controller.error, contains(original.movementId));
    final count = f.api.postCount;
    await f.controller.retryPendingAdjustment();
    await f.controller.adjust(f.api.levels.single, '10', 'replacement');
    expect(f.api.postCount, count);
  });

  test(
    'fake rejects changed payload, actor, level and location identity',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      await f.controller.adjust(f.api.levels.single, '9', 'reason');
      final body = f.api.lastAdjustBody!;
      final route = '/locations/$_location/stock/$_levelId/adjust';
      for (final change in [
        (token: 'account:2', route: route, body: {...body, 'quantity': '10'}),
        (token: 'account:2', route: route, body: {...body, 'note': 'changed'}),
        (
          token: 'account:2',
          route: route,
          body: {...body, 'expectedVersion': 2},
        ),
        (token: 'other:1', route: route, body: body),
        (
          token: 'account:2',
          route: '/locations/$_second/stock/$_levelId/adjust',
          body: body,
        ),
        (
          token: 'account:2',
          route: '/locations/$_location/stock/$_assoc/adjust',
          body: body,
        ),
      ]) {
        await expectLater(
          f.api.post(change.token, change.route, change.body),
          throwsA(
            isA<StoreApiException>().having(
              (e) => e.code,
              'code',
              'operation_conflict',
            ),
          ),
        );
      }
      expect(f.api.adjustedAuditCount, 1);
    },
  );

  test(
    'pending command blocks location change until explicit local abandonment',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.levels.add(_level());
      await f.controller.selectLocation(_location);
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      await f.controller.adjust(f.api.levels.single, '9', 'reason');
      final original = f.controller.pendingAdjustment;
      await f.controller.selectLocation(_second);
      expect(f.controller.selectedLocationId, _location);
      expect(f.controller.pendingAdjustment, same(original));
      f.api.failStockList = true;
      await f.controller.load();
      expect(f.controller.pendingAdjustment, same(original));
      expect(
        f.controller.adjustmentResult!.outcome,
        StockAdjustmentOutcome.unconfirmed,
      );
      f.api.failStockList = false;
      f.controller.abandonPendingAdjustment();
      expect(f.controller.notice, contains('nicht abgebrochen'));
      await f.controller.selectLocation(_second);
      expect(f.controller.selectedLocationId, _second);
      await f.controller.retryPendingAdjustment();
      expect(f.api.postCount, 1);
    },
  );

  for (final replacement in ['account', 'other']) {
    test(
      'held replacement status ($replacement) cannot send an old pending command',
      () async {
        final sessionApi = _Session();
        final f = await _Fixture.create('admin', sessionApi: sessionApi);
        addTearDown(f.dispose);
        f.api.levels.add(_level());
        await f.controller.selectLocation(_location);
        f.api.adjustThrows = true;
        f.api.adjustApplies = false;
        await f.controller.adjust(f.api.levels.single, '9', 'private reason');
        final originalIdentity = f.session.sessionIdentity;
        final statusGate = sessionApi.statusGate = Completer<void>();
        final statusStarted = sessionApi.statusStarted = Completer<void>();
        var signInFinished = false;
        final replacementSignIn = f.session
            .signIn(username: replacement, password: 'password')
            .whenComplete(() => signInFinished = true);
        await statusStarted.future;
        try {
          expect(signInFinished, isFalse);
          expect(f.session.sessionIdentity, isNot(same(originalIdentity)));
          final requestCount = f.api.postCount;
          expect(
            (await f.controller.retryPendingAdjustment()).outcome,
            StockAdjustmentOutcome.ignored,
          );
          expect(f.api.postCount, requestCount);
          expect(f.api.adjustmentTokens, ['account:1']);
          expect(f.controller.pendingAdjustment, isNull);
          expect(f.controller.lastAdjustment, isNull);
          expect(f.controller.selectedLocationId, isNull);
          expect(f.controller.items, isNull);
          expect(f.controller.adjustmentResult, isNull);
          expect(f.controller.notice, contains('Sitzung geändert'));
          expect(f.controller.notice, contains('weder abgebrochen'));
          expect(f.controller.notice, isNot(contains('private reason')));
          expect(
            (await f.controller.adjust(_level(), '10', 'new')).outcome,
            StockAdjustmentOutcome.ignored,
          );
          expect(f.movementIds, 1);
          expect(f.api.postCount, requestCount);
        } finally {
          statusGate.complete();
          await replacementSignIn;
        }
      },
    );

    for (final oldFails in [false, true]) {
      test(
        'old adjustment ${oldFails ? 'failure' : 'result'} is ignored during held replacement status ($replacement)',
        () async {
          final sessionApi = _Session();
          final f = await _Fixture.create('admin', sessionApi: sessionApi);
          addTearDown(f.dispose);
          f.api.levels.add(_level());
          await f.controller.selectLocation(_location);
          final requestGate = f.api.adjustmentGate = Completer<void>();
          f.api.adjustThrows = oldFails;
          f.api.adjustApplies = !oldFails;
          final oldRequest = f.controller.adjust(
            f.api.levels.single,
            '9',
            'private reason',
          );
          final statusGate = sessionApi.statusGate = Completer<void>();
          final statusStarted = sessionApi.statusStarted = Completer<void>();
          final replacementSignIn = f.session.signIn(
            username: replacement,
            password: 'password',
          );
          await statusStarted.future;
          final replacementNotice = f.controller.notice;
          var notifications = 0;
          void changed() => notifications++;
          f.controller.addListener(changed);
          try {
            requestGate.complete();
            expect((await oldRequest).outcome, StockAdjustmentOutcome.ignored);
            expect(notifications, 0);
            expect(f.controller.notice, replacementNotice);
            expect(f.controller.error, isNull);
            expect(f.controller.refreshError, isNull);
            expect(f.controller.pendingAdjustment, isNull);
            expect(f.controller.lastAdjustment, isNull);
            expect(f.controller.adjustmentResult, isNull);
            expect(f.controller.items, isNull);
            expect(f.controller.selectedLocationId, isNull);
            expect(f.controller.busy, isFalse);
            expect(f.api.adjustmentTokens, ['account:1']);
          } finally {
            f.controller.removeListener(changed);
            if (!requestGate.isCompleted) requestGate.complete();
            statusGate.complete();
            await oldRequest;
            await replacementSignIn;
          }
        },
      );
    }

    test(
      'replacement session ($replacement) fences pending and stale responses',
      () async {
        final f = await _Fixture.create('admin');
        addTearDown(f.dispose);
        f.api.levels.add(_level());
        await f.controller.selectLocation(_location);
        final gate = f.api.adjustmentGate = Completer<void>();
        final first = f.controller.adjust(f.api.levels.single, '9', 'reason');
        await f.session.signIn(username: replacement, password: 'password');
        while (f.platform.isBusy) {
          await Future<void>.value();
        }
        expect(f.controller.pendingAdjustment, isNull);
        await f.controller.selectLocation(_second);
        gate.complete();
        expect((await first).outcome, StockAdjustmentOutcome.ignored);
        expect(f.controller.items, isEmpty);
        expect(f.controller.selectedLocationId, _second);
        expect(f.controller.notice, isNull);
        expect(f.controller.adjustmentResult, isNull);
        await f.controller.retryPendingAdjustment();
        expect(f.api.postCount, 1);
      },
    );
  }

  test('pagination appends the next page', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.addAll([
      _level(),
      _level(id: '99999999-9999-4999-8999-999999999999', articleId: _milch),
      _level(
        id: '88888888-8888-4888-8888-888888888888',
        articleId: '77777777-7777-4777-8777-777777777777',
      ),
    ]);
    f.api.pageSize = 2;
    await f.controller.selectLocation(_location);
    expect(f.controller.items, hasLength(2));
    expect(f.controller.hasMore, isTrue);
    await f.controller.loadMore();
    expect(f.controller.items, hasLength(3));
    expect(f.controller.hasMore, isFalse);
    expect(f.api.queries.last['after'], isNotNull);
  });

  test('movement history is paged by balance version', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.levels.add(_level(quantity: '2', version: 2));
    await f.controller.load();
    f.api.movements[_levelId] = [
      _movement(
        id: '99999999-9999-4999-8999-999999999999',
        kind: 'adjustment',
        delta: '-5',
        balanceAfter: '2',
        balanceVersion: 2,
        note: 'Korrektur',
      ),
      _movement(),
    ];
    final page = await f.controller.loadMovements(f.controller.items!.single);
    expect(page.items, hasLength(2));
    expect(page.items.first.balanceVersion, 2);
    expect(page.items.first.kind, 'adjustment');
    expect(page.nextCursor, isNull);
  });

  for (final status in [413, 415]) {
    test(
      '$status definitively rejects adjustment without pending retry',
      () async {
        final f = await _Fixture.create('admin');
        addTearDown(f.dispose);
        f.api.levels.add(_level());
        await f.controller.selectLocation(_location);
        f.api.failAdjust = StoreApiException(
          status == 413 ? 'body_too_large' : 'unsupported_media_type',
          'Request rejected before StockService',
          statusCode: status,
        );
        final result = await f.controller.adjust(_level(), '9', 'reason');
        expect(result.outcome, StockAdjustmentOutcome.rejected);
        expect(f.controller.pendingAdjustment, isNull);
        expect(f.controller.conflict, isFalse);
        expect(f.controller.adjustmentBlocked, isFalse);
        expect(f.api.adjustedAuditCount, 0);
        expect(f.api.movements, isEmpty);
        expect(
          (await f.controller.retryPendingAdjustment()).outcome,
          StockAdjustmentOutcome.ignored,
        );
        expect(f.api.postCount, 1);
        await f.controller.selectLocation(_second);
        expect(f.controller.selectedLocationId, _second);
      },
    );
  }

  testWidgets('section shows quantity, unit and degradation indicators', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.add(
      _level(articleActive: false, assortmentActive: true, stockUnit: 'kg'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockSection(controller: f.controller, platform: f.platform),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('7 kg · SKU-1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stock-article-inactive-$_levelId')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('stock-effective-$_levelId')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('section marks a diverged live article unit', (tester) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.add(_level(stockUnit: 'kg', articleUnit: 'Stk'));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockSection(controller: f.controller, platform: f.platform),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Artikeleinheit heute: Stk'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('adjust dialog sends target and required reason', (tester) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.add(_level());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockSection(controller: f.controller, platform: f.platform),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stock-adjust-$_levelId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('stock-adjust-quantity')),
      '12.5',
    );
    await tester.enterText(
      find.byKey(const Key('stock-adjust-note')),
      'Zugang',
    );
    await tester.tap(find.byKey(const Key('stock-adjust-submit')));
    await tester.pumpAndSettle();
    expect(f.api.lastAdjustBody!['quantity'], '12.5');
    expect(f.api.lastAdjustBody!['note'], 'Zugang');
    expect(find.text('12.5 kg · SKU-1'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('history dialog lists movements in the frozen unit', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.levels.add(_level());
    f.api.movements[_levelId] = [_movement(note: 'Anfang')];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StockSection(controller: f.controller, platform: f.platform),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('stock-history-$_levelId')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anfangsbestand'), findsOneWidget);
    expect(find.textContaining('Stand danach: 7 kg'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('invalid dialog input stays visible and creates no command', (
    tester,
  ) async {
    final f = await _pumpAdjustment(tester);
    addTearDown(f.dispose);
    await _enterAdjustment(tester, '-1', 'entered reason');
    await tester.tap(find.byKey(const Key('stock-adjust-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(_field(tester, 'stock-adjust-quantity').controller!.text, '-1');
    expect(
      _field(tester, 'stock-adjust-note').controller!.text,
      'entered reason',
    );
    expect(
      _field(tester, 'stock-adjust-quantity').decoration!.errorText,
      isNotNull,
    );
    expect(f.movementIds, 0);
    expect(f.api.postCount, 0);
    await _enterAdjustment(tester, '8', '');
    await tester.tap(find.byKey(const Key('stock-adjust-submit')));
    await tester.pumpAndSettle();
    expect(
      _field(tester, 'stock-adjust-note').decoration!.errorText,
      isNotNull,
    );
    expect(f.movementIds, 0);
    await _disposeWidget(tester, f);
  });

  for (final replacement in ['account', 'other']) {
    for (final dialog in ['adjust', 'history', 'open']) {
      testWidgets(
        '$dialog dialog hides old context during held replacement ($replacement)',
        (tester) async {
          final sessionApi = _Session();
          final f = await _Fixture.create('admin', sessionApi: sessionApi);
          addTearDown(f.dispose);
          f.api.levels.add(_level());
          f.api.movements[_levelId] = [_movement(note: 'private history')];
          f.api.candidates.add(_candidate(articleId: _milch));
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StockSection(
                  controller: f.controller,
                  platform: f.platform,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            dialog == 'open'
                ? find.byKey(const Key('create-stock'))
                : find.byKey(ValueKey('stock-$dialog-$_levelId')),
          );
          await tester.pumpAndSettle();
          if (dialog == 'adjust') {
            f.api.adjustThrows = true;
            f.api.adjustApplies = false;
            await _enterAdjustment(tester, '9', 'private reason');
            await tester.tap(find.byKey(const Key('stock-adjust-submit')));
            await tester.pumpAndSettle();
          } else if (dialog == 'open') {
            await tester.enterText(
              find.byKey(const Key('stock-open-search')),
              'Mehl',
            );
            await tester.tap(find.byKey(const Key('stock-open-search-button')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('stock-open-$_milch')),
              findsOneWidget,
            );
          } else {
            expect(find.textContaining('private history'), findsOneWidget);
          }
          final statusGate = sessionApi.statusGate = Completer<void>();
          final statusStarted = sessionApi.statusStarted = Completer<void>();
          final replacementSignIn = f.session.signIn(
            username: replacement,
            password: 'password',
          );
          await statusStarted.future;
          try {
            await tester.pump();
            expect(
              find.byKey(const Key('stock-context-changed')),
              findsOneWidget,
            );
            expect(find.byKey(const Key('stock-adjust-note')), findsNothing);
            expect(find.byKey(const Key('stock-open-search')), findsNothing);
            expect(
              find.byKey(const ValueKey('stock-open-$_milch')),
              findsNothing,
            );
            expect(find.textContaining('private history'), findsNothing);
            expect(find.textContaining('private reason'), findsNothing);
            expect(f.controller.pendingAdjustment, isNull);
            expect(f.controller.lastAdjustment, isNull);
          } finally {
            statusGate.complete();
            await replacementSignIn;
          }
          await _disposeWidget(tester, f);
        },
      );
    }
  }

  testWidgets(
    'dialog disables duplicate send and retains uncertainty after closing',
    (tester) async {
      final f = await _pumpAdjustment(tester);
      addTearDown(f.dispose);
      final gate = f.api.adjustmentGate = Completer<void>();
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      await _enterAdjustment(tester, '12.5', 'reason');
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('stock-adjust-submit')),
      );
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('stock-adjust-submit')))
            .onPressed,
        isNull,
      );
      expect(f.api.postCount, 1);
      expect(f.movementIds, 1);
      final original = f.controller.pendingAdjustment;
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_field(tester, 'stock-adjust-quantity').enabled, isFalse);
      expect(_field(tester, 'stock-adjust-note').controller!.text, 'reason');
      await tester.tap(find.byKey(const Key('stock-adjust-close')));
      await tester.pumpAndSettle();
      expect(f.controller.pendingAdjustment, same(original));
      expect(find.byKey(const Key('stock-retry-adjustment')), findsOneWidget);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byKey(const Key('stock-location')),
            )
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StockSection(controller: f.controller, platform: f.platform),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(f.controller.pendingAdjustment, same(original));
      expect(find.byKey(const Key('stock-retry-adjustment')), findsOneWidget);
      await _disposeWidget(tester, f);
    },
  );

  for (final failure in [
    const StoreApiException('stock_conflict', 'conflict', statusCode: 409),
    const StoreApiException('operation_conflict', 'conflict', statusCode: 409),
    const StoreApiException('forbidden', 'denied', statusCode: 403),
    const StoreApiException('body_too_large', 'rejected', statusCode: 413),
    const StoreApiException(
      'unsupported_media_type',
      'rejected',
      statusCode: 415,
    ),
    const StoreApiException('http_408', 'gateway timeout', statusCode: 408),
    const StoreApiException('server_error', 'server failure', statusCode: 500),
  ]) {
    testWidgets('${failure.code} keeps dialog input and never auto-resends', (
      tester,
    ) async {
      final f = await _pumpAdjustment(tester);
      addTearDown(f.dispose);
      f.api.failAdjust = failure;
      await _enterAdjustment(tester, '12.5', 'entered reason');
      await tester.tap(find.byKey(const Key('stock-adjust-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(_field(tester, 'stock-adjust-quantity').controller!.text, '12.5');
      expect(
        _field(tester, 'stock-adjust-note').controller!.text,
        'entered reason',
      );
      expect(find.byKey(const Key('stock-adjust-error')), findsOneWidget);
      expect(f.api.postCount, 1);
      if (failure.statusCode == 413 || failure.statusCode == 415) {
        expect(
          f.controller.adjustmentResult!.outcome,
          StockAdjustmentOutcome.rejected,
        );
        expect(f.controller.pendingAdjustment, isNull);
        expect(f.controller.adjustmentBlocked, isFalse);
        expect(_field(tester, 'stock-adjust-quantity').enabled, isTrue);
        expect(find.byKey(const Key('stock-retry-adjustment')), findsNothing);
        await tester.tap(find.byKey(const Key('stock-adjust-close')));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const Key('stock-location')),
              )
              .onChanged,
          isNotNull,
        );
      }
      if (failure.statusCode == 408 || failure.statusCode == 500) {
        expect(
          f.controller.adjustmentResult!.outcome,
          StockAdjustmentOutcome.unconfirmed,
        );
        expect(f.controller.pendingAdjustment, isNotNull);
      }
      if (failure.statusCode == 409) {
        expect(f.controller.pendingAdjustment, isNull);
        expect(_field(tester, 'stock-adjust-quantity').enabled, isFalse);
        f.api.failAdjust = null;
        await tester.tap(find.byKey(const Key('stock-adjust-new-decision')));
        await tester.pumpAndSettle();
        expect(_field(tester, 'stock-adjust-quantity').enabled, isTrue);
        expect(f.api.postCount, 1);
        await tester.tap(find.byKey(const Key('stock-adjust-submit')));
        await tester.pumpAndSettle();
        expect(f.api.postCount, 2);
        expect(find.byType(AlertDialog), findsNothing);
      }
      await _disposeWidget(tester, f);
    });
  }

  testWidgets(
    'confirmed refresh failure stays open for acknowledgement without retry',
    (tester) async {
      final f = await _pumpAdjustment(tester);
      addTearDown(f.dispose);
      f.api.failStockList = true;
      await _enterAdjustment(tester, '12.5', 'reason');
      await tester.tap(find.byKey(const Key('stock-adjust-submit')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.byKey(const Key('stock-adjust-refresh-error')),
        findsOneWidget,
      );
      expect(f.controller.adjustmentResult!.confirmed, isTrue);
      expect(f.controller.pendingAdjustment, isNull);
      expect(find.byKey(const Key('stock-retry-adjustment')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('stock-adjust-submit')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('stock-adjust-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('stock-refresh-error')), findsOneWidget);
      expect(f.api.postCount, 1);
      await _disposeWidget(tester, f);
    },
  );

  testWidgets('confirmed no-op closes and communicates no recorded movement', (
    tester,
  ) async {
    final f = await _pumpAdjustment(tester);
    addTearDown(f.dispose);
    await _enterAdjustment(tester, '7', 'same quantity');
    await tester.tap(find.byKey(const Key('stock-adjust-submit')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Keine Bestandsbewegung'), findsOneWidget);
    expect(f.api.movements, isEmpty);
    expect(f.api.adjustedAuditCount, 0);
    await _disposeWidget(tester, f);
  });

  testWidgets(
    'abandoning requires explicit acknowledgement of local-only effect',
    (tester) async {
      final f = await _pumpAdjustment(tester);
      addTearDown(f.dispose);
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      await _enterAdjustment(tester, '9', 'reason');
      await tester.tap(find.byKey(const Key('stock-adjust-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-adjust-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-abandon-adjustment')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Dies bricht keine Serveranfrage'),
        findsOneWidget,
      );
      expect(f.controller.pendingAdjustment, isNotNull);
      await tester.tap(find.byKey(const Key('stock-confirm-abandon')));
      await tester.pumpAndSettle();
      expect(f.controller.pendingAdjustment, isNull);
      expect(f.api.postCount, 1);
      expect(f.controller.conflict, isFalse);
      expect(f.controller.notice, contains('weiterhin unklar'));
      expect(find.textContaining('Korrektur abgelehnt'), findsNothing);
      expect(
        find.textContaining('Ob die Korrektur gespeichert wurde'),
        findsOneWidget,
      );
      expect(f.controller.adjustmentBlocked, isTrue);
      expect(find.byKey(const Key('stock-retry-adjustment')), findsNothing);
      final sent = f.api.postCount;
      await f.controller.adjust(f.api.levels.single, '10', 'new');
      expect(f.api.postCount, sent);
      f.api.adjustThrows = false;
      f.api.adjustApplies = true;
      await tester.tap(find.byKey(const Key('stock-reload')));
      await tester.pumpAndSettle();
      expect(f.controller.adjustmentBlocked, isFalse);
      await _disposeWidget(tester, f);
    },
  );

  testWidgets(
    'old abandonment confirmation cannot discard replacement pending command',
    (tester) async {
      final f = await _pumpAdjustment(tester);
      addTearDown(f.dispose);
      f.api.adjustThrows = true;
      f.api.adjustApplies = false;
      await _enterAdjustment(tester, '9', 'old reason');
      await tester.tap(find.byKey(const Key('stock-adjust-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-adjust-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock-abandon-adjustment')));
      await tester.pumpAndSettle();
      await f.session.signIn(username: 'account', password: 'password');
      await f.controller.selectLocation(_location);
      await f.controller.adjust(
        f.api.levels.single,
        '10',
        'replacement reason',
      );
      final replacementPending = f.controller.pendingAdjustment;
      expect(replacementPending, isNotNull);
      await tester.tap(find.byKey(const Key('stock-confirm-abandon')));
      await tester.pumpAndSettle();
      expect(f.controller.pendingAdjustment, same(replacementPending));
      expect(f.controller.adjustmentAbandoned, isFalse);
      expect(f.api.adjustmentTokens, ['account:1', 'account:2']);
      await _disposeWidget(tester, f);
    },
  );
}

TextField _field(WidgetTester tester, String key) =>
    tester.widget<TextField>(find.byKey(Key(key)));

Future<void> _disposeWidget(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox());
  fixture.dispose();
}

Future<void> _enterAdjustment(
  WidgetTester tester,
  String quantity,
  String note,
) async {
  await tester.enterText(
    find.byKey(const Key('stock-adjust-quantity')),
    quantity,
  );
  await tester.enterText(find.byKey(const Key('stock-adjust-note')), note);
}

Future<_Fixture> _pumpAdjustment(WidgetTester tester) async {
  final f = await _Fixture.create('admin');
  f.api.levels.add(_level());
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StockSection(controller: f.controller, platform: f.platform),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('stock-adjust-$_levelId')));
  await tester.pumpAndSettle();
  return f;
}

class _Fixture {
  _Fixture(this.session, this.platform, this.controller, this.api);
  final SessionController session;
  final PlatformController platform;
  final StockController controller;
  final _StockApi api;
  bool _disposed = false;
  int movementIds = 0;

  static Future<_Fixture> create(String role, {_Session? sessionApi}) async {
    final api = _StockApi(role);
    final session = SessionController(sessionApi ?? _Session());
    final platform = PlatformController(session, api);
    late _Fixture fixture;
    final controller = StockController(
      session,
      platform,
      api,
      movementIdFactory: () =>
          '00000000-0000-4000-8000-'
          '${(++fixture.movementIds).toString().padLeft(12, '0')}',
    );
    fixture = _Fixture(session, platform, controller, api);
    await session.signIn(username: 'account', password: 'password');
    while (platform.isBusy) {
      await Future<void>.value();
    }
    return fixture;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    platform.dispose();
    session.dispose();
  }
}

class _Session implements StoreApi {
  int generation = 0;
  Completer<void>? statusGate, statusStarted;
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: '${request.username}:${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: request.username,
      username: request.username,
      companyId: _company,
      locationId: _location,
    ),
  );
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
  @override
  Future<void> logout(String token) async {}
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    if (statusStarted case final started? when !started.isCompleted) {
      started.complete();
    }
    await statusGate?.future;
    return const SystemStatusResponse(
      companyId: _company,
      locationId: _location,
    );
  }
}

class _StockApi implements PlatformApi {
  _StockApi(this.role);
  final String role;
  final List<ArticleAssortmentDto> candidates = [];
  final List<StockLevelDto> levels = [];
  final Map<String, List<StockMovementDto>> movements = {};
  final List<Map<String, String>> queries = [];
  final List<String> stockRequests = [];
  Map<String, dynamic>? lastOpenBody;
  Map<String, dynamic>? lastAdjustBody;
  int postCount = 0;
  int pageSize = 50;
  bool loseOpenResponse = false;
  bool adjustThrows = false;
  bool adjustApplies = true;
  StoreApiException? failOpen;
  StoreApiException? failAdjust;
  Completer<void>? adjustmentGate;
  bool failStockList = false;
  int adjustedAuditCount = 0;
  final List<Map<String, dynamic>> adjustmentBodies = [];
  final List<String> adjustmentTokens = [];
  final Map<String, ({String actor, String route, Map<String, dynamic> body})>
  committed = {};

  StockLevelDto _replace(StockLevelDto level, String quantity, int version) =>
      StockLevelDto(
        id: level.id,
        locationId: level.locationId,
        articleId: level.articleId,
        stockUnit: level.stockUnit,
        quantity: quantity,
        version: version,
        createdAt: level.createdAt,
        updatedAt: DateTime.utc(2030, 1, 1, 9),
        article: level.article,
        assortmentIsActive: level.assortmentIsActive,
      );

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    final parameters = query ?? const <String, String>{};
    if (route == '/context') {
      return {
        'userId': token.split(':').first,
        'companyId': _company,
        'locationId': _location,
        'role': role,
        'permissions': [
          'context.read',
          'organization.read',
          if (role == 'admin') 'stock.levels.manage',
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': _company, 'name': 'Test company', 'version': 2},
        'locations': [
          {
            'id': _location,
            'companyId': _company,
            'name': 'Home',
            'version': 2,
          },
          {
            'id': _second,
            'companyId': _company,
            'name': 'Second',
            'version': 1,
          },
        ],
      };
    }
    if (route.endsWith('/assortment')) {
      final q = parameters['q']?.toLowerCase();
      final matching = candidates.where((candidate) {
        if (q == null) return true;
        return candidate.article.name.toLowerCase().contains(q) ||
            candidate.article.sku.toLowerCase().contains(q);
      }).toList();
      return {
        'items': matching.map((candidate) => candidate.toJson()).toList(),
        'nextCursor': null,
      };
    }
    if (route.endsWith('/movements')) {
      final levelId = route.split('/')[4];
      final all = [...?movements[levelId]]
        ..sort((a, b) => b.balanceVersion.compareTo(a.balanceVersion));
      final start = after == null
          ? 0
          : all.indexWhere((item) => item.balanceVersion.toString() == after) +
                1;
      final page = all.skip(start).take(pageSize).toList();
      return {
        'items': page.map((item) => item.toJson()).toList(),
        'nextCursor': all.length > start + page.length
            ? page.last.balanceVersion.toString()
            : null,
      };
    }
    if (route.startsWith('/locations/')) {
      if (failStockList && route.endsWith('/stock')) {
        throw const StoreApiException(
          'network_unavailable',
          'List unavailable',
        );
      }
      stockRequests.add(route);
      queries.add({...parameters, 'after': ?after});
      final segments = route.split('/');
      if (segments.length == 5) {
        return levels.singleWhere((item) => item.id == segments.last).toJson();
      }
      final locationId = segments[2];
      final q = parameters['q']?.toLowerCase();
      var matching = levels.where((item) {
        if (item.locationId != locationId) return false;
        if (q != null &&
            !item.article.name.toLowerCase().contains(q) &&
            !item.article.sku.toLowerCase().contains(q)) {
          return false;
        }
        if (after != null && item.id.compareTo(after) <= 0) return false;
        return true;
      }).toList()..sort((a, b) => a.id.compareTo(b.id));
      final page = matching.take(pageSize).toList();
      return {
        'items': page.map((item) => item.toJson()).toList(),
        'nextCursor': matching.length > page.length ? page.last.id : null,
      };
    }
    throw const FormatException('Unexpected route.');
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    postCount++;
    final segments = route.split('/');
    if (segments.length == 4) {
      lastOpenBody = body;
      if (failOpen case final failure?) throw failure;
      final candidate = candidates.firstWhere(
        (item) => item.article.id == body['articleId'],
      );
      final created = StockLevelDto(
        id: body['id'] as String,
        locationId: segments[2],
        articleId: candidate.article.id,
        stockUnit: candidate.article.unit,
        quantity: stockQuantityText(stockQuantity(body['quantity'])),
        version: 1,
        createdAt: DateTime.utc(2030, 1, 1, 8),
        updatedAt: DateTime.utc(2030, 1, 1, 8),
        article: StockArticleDto(
          id: candidate.article.id,
          sku: candidate.article.sku,
          barcode: candidate.article.barcode,
          name: candidate.article.name,
          unit: candidate.article.unit,
          isActive: candidate.article.isActive,
        ),
        assortmentIsActive: true,
      );
      levels.add(created);
      movements[created.id] = [
        _movement(
          id: '99999999-9999-4999-8999-999999999999',
          delta: created.quantity,
          balanceAfter: created.quantity,
        ),
      ];
      if (loseOpenResponse) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      return created.toJson();
    }
    final levelId = segments[4];
    lastAdjustBody = Map.of(body);
    adjustmentBodies.add(Map.of(body));
    adjustmentTokens.add(token);
    await adjustmentGate?.future;
    if (failAdjust case final failure?) throw failure;
    final index = levels.indexWhere((item) => item.id == levelId);
    if (adjustThrows && !adjustApplies) {
      throw const StoreApiException('timeout', 'Unknown outcome');
    }
    final input = StockAdjustInput.fromJson(body);
    final existing = committed[input.movementId];
    if (existing != null) {
      if (existing.actor != token.split(':').first ||
          existing.route != route ||
          !mapEquals(existing.body, input.toJson())) {
        throw const StoreApiException(
          'operation_conflict',
          'Identity conflict',
          statusCode: 409,
        );
      }
      return levels[index].toJson();
    }
    if (levels[index].locationId != segments[2]) {
      throw const StoreApiException(
        'not_found',
        'Wrong location',
        statusCode: 404,
      );
    }
    if (levels[index].version != input.expectedVersion) {
      throw const StoreApiException(
        'stock_conflict',
        'Stale version',
        statusCode: 409,
      );
    }
    if (levels[index].quantity == input.quantity) return levels[index].toJson();
    final before = levels[index];
    levels[index] = _replace(before, input.quantity, before.version + 1);
    movements[levelId] = [
      ...?movements[levelId],
      _movement(
        id: body['movementId'] as String,
        kind: 'adjustment',
        delta: stockDeltaText(
          stockQuantity(input.quantity) - stockQuantity(before.quantity),
        ),
        balanceAfter: stockQuantityText(stockQuantity(body['quantity'])),
        balanceVersion: levels[index].version,
        note: body['note'] as String,
      ),
    ];
    committed[input.movementId] = (
      actor: token.split(':').first,
      route: route,
      body: input.toJson(),
    );
    adjustedAuditCount++;
    if (adjustThrows) {
      throw const StoreApiException('timeout', 'Unknown outcome');
    }
    return levels[index].toJson();
  }
}
