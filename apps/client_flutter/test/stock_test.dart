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
    'a lost adjust response is confirmed by the exact movement id',
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
      expect(f.controller.error, isNull);
      expect(f.controller.notice, contains('erneut geladen'));
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
    f.api.otherMutation = true;
    await f.controller.adjust(f.controller.items!.single, '12.5', 'Zugang');
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isTrue);
    expect(f.controller.error, contains('nicht bestätigt'));
    expect(f.controller.pendingAdjustment, isNotNull);
  });

  test('retrying reuses the exact same movementId', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.levels.add(_level());
    await f.controller.load();
    f.api.adjustThrows = true;
    f.api.adjustApplies = false;
    f.api.otherMutation = true;
    await f.controller.adjust(f.controller.items!.single, '12.5', 'Zugang');
    final firstId = f.api.lastAdjustBody!['movementId'];
    f.api.adjustThrows = false;
    f.api.otherMutation = false;
    await f.controller.retryPendingAdjustment();
    expect(f.api.postCount, 2);
    expect(f.api.lastAdjustBody!['movementId'], firstId);
    expect(f.controller.pendingAdjustment, isNull);
    expect(f.controller.notice, contains('korrigiert'));
  });

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
}

class _Fixture {
  _Fixture(this.session, this.platform, this.controller, this.api);
  final SessionController session;
  final PlatformController platform;
  final StockController controller;
  final _StockApi api;
  bool _disposed = false;

  static Future<_Fixture> create(String role) async {
    final api = _StockApi(role);
    final session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final controller = StockController(session, platform, api);
    await session.signIn(username: 'account', password: 'password');
    while (platform.isBusy) {
      await Future<void>.value();
    }
    return _Fixture(session, platform, controller, api);
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
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'token',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: const SessionUser(
      id: 'account',
      username: 'account',
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
  }) async =>
      const SystemStatusResponse(companyId: _company, locationId: _location);
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
  bool otherMutation = false;
  StoreApiException? failOpen;

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
        'userId': 'account',
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
    lastAdjustBody = body;
    final index = levels.indexWhere((item) => item.id == levelId);
    if (otherMutation) {
      levels[index] = _replace(levels[index], '99', levels[index].version + 1);
      movements[levelId] = [
        ...?movements[levelId],
        _movement(
          id: '88888888-8888-4888-8888-888888888888',
          kind: 'adjustment',
          delta: '92',
          balanceAfter: '99',
          balanceVersion: levels[index].version,
          note: 'Fremde Korrektur',
        ),
      ];
    } else if (adjustApplies) {
      levels[index] = _replace(
        levels[index],
        stockQuantityText(stockQuantity(body['quantity'])),
        levels[index].version + 1,
      );
      movements[levelId] = [
        ...?movements[levelId],
        _movement(
          id: body['movementId'] as String,
          kind: 'adjustment',
          delta: '5',
          balanceAfter: stockQuantityText(stockQuantity(body['quantity'])),
          balanceVersion: levels[index].version,
          note: body['note'] as String,
        ),
      ];
    }
    if (adjustThrows) {
      throw const StoreApiException('timeout', 'Unknown outcome');
    }
    return levels[index].toJson();
  }
}
