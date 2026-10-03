import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/article_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/article_section.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
const _mehl = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _milch = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _old = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

ArticleDto _article({
  String id = _mehl,
  String sku = 'SKU-1',
  String? barcode = '000123',
  String name = 'Mehl',
  String? description,
  String unit = 'kg',
  bool active = true,
  int version = 1,
}) => ArticleDto(
  id: id,
  companyId: _company,
  sku: sku,
  barcode: barcode,
  name: name,
  description: description,
  unit: unit,
  isActive: active,
  version: version,
  createdAt: DateTime.utc(2030, 1, 1, 8),
  updatedAt: DateTime.utc(2030, 1, 1, 8),
);

void main() {
  test(
    'capability gating prevents any article request for non-admin',
    () async {
      final f = await _Fixture.create('viewer');
      addTearDown(f.dispose);
      expect(f.controller.canManage, isFalse);
      await f.controller.load();
      expect(f.api.getRequests, isEmpty);
      expect(f.controller.articles, isNull);
    },
  );

  test(
    'default list is active-only; include-inactive omits the filter',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.articles.addAll([
        _article(),
        _article(id: _old, sku: 'OLD', active: false),
      ]);
      await f.controller.load();
      expect(f.api.queries.last['active'], 'true');
      expect(f.controller.articles, hasLength(1));
      await f.controller.setShowInactive(true);
      expect(f.api.queries.last.containsKey('active'), isFalse);
      expect(f.controller.articles, hasLength(2));
      expect(
        f.controller.articles!.map((article) => article.isActive).toSet(),
        {true, false},
      );
    },
  );

  test('search is sent as a literal query parameter', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.articles.addAll([
      _article(),
      _article(id: _milch, sku: 'MILCH', name: 'Vollmilch'),
    ]);
    await f.controller.setSearch('milch');
    expect(f.api.queries.last['q'], 'milch');
    expect(f.controller.articles, hasLength(1));
    expect(f.controller.articles!.single.name, 'Vollmilch');
  });

  test(
    'create reconciles a lost response by client id without replay',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.loseCreateResponse = true;
      await f.controller.create(
        const ArticleCreateInput(
          id: '00000000-0000-4000-8000-000000000000',
          sku: 'NEU-1',
          barcode: null,
          name: 'Neu',
          description: null,
          unit: 'Stk',
        ),
      );
      expect(f.api.postCount, 1);
      expect(f.controller.error, isNull);
      expect(f.controller.notice, contains('gespeichert'));
      expect(f.controller.articles!.single.sku, 'NEU-1');
      expect(f.controller.articles!.single.barcode, isNull);
    },
  );

  test('duplicate SKU from another id stays a deterministic error', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.articles.add(_article());
    f.api.failCreate = const StoreApiException(
      'already_exists',
      'Conflict',
      statusCode: 409,
    );
    await f.controller.create(
      const ArticleCreateInput(
        id: '00000000-0000-4000-8000-000000000000',
        sku: 'SKU-1',
        barcode: null,
        name: 'Neu',
        description: null,
        unit: 'Stk',
      ),
    );
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isFalse);
    expect(f.controller.error, contains('vergeben'));
  });

  test(
    'stale edit sets an explicit reload state and never auto-resends',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.articles.add(_article());
      await f.controller.load();
      f.api.failPost = const StoreApiException(
        'article_conflict',
        'Conflict',
        statusCode: 409,
      );
      await f.controller.edit(
        f.controller.articles!.single,
        const ArticleEditInput(
          expectedVersion: 1,
          sku: 'SKU-1',
          barcode: null,
          name: 'Geändert',
          description: null,
          unit: 'kg',
        ),
      );
      expect(f.api.postCount, 1);
      expect(f.controller.conflict, isTrue);
      expect(f.controller.error, contains('neu laden'));
      await f.controller.load();
      expect(f.controller.conflict, isFalse);
    },
  );

  test(
    'deactivate and reactivate are version guarded and refresh the list',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.articles.add(_article());
      await f.controller.load();
      await f.controller.setShowInactive(true);
      await f.controller.deactivate(f.controller.articles!.single);
      expect(f.api.lastLifecycle, ['deactivate', 1]);
      expect(f.controller.articles!.single.isActive, isFalse);
      expect(f.controller.articles!.single.version, 2);
      await f.controller.reactivate(f.controller.articles!.single);
      expect(f.api.lastLifecycle, ['reactivate', 2]);
      expect(f.controller.articles!.single.isActive, isTrue);
      expect(f.controller.articles!.single.version, 3);
    },
  );

  test('duplicate submit is blocked while a command is busy', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    final pending = Completer<Map<String, dynamic>>();
    f.api.pendingWrite = pending;
    final input = const ArticleCreateInput(
      id: '00000000-0000-4000-8000-000000000000',
      sku: 'NEU-1',
      barcode: null,
      name: 'Neu',
      description: null,
      unit: 'Stk',
    );
    final first = f.controller.create(input);
    await f.controller.create(input);
    expect(f.api.postCount, 1);
    pending.complete(_article(sku: 'NEU-1').toJson());
    await first;
    expect(f.api.postCount, 1);
  });

  test('pagination appends the next page', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.articles.addAll([
      _article(),
      _article(id: _milch, sku: 'MILCH', name: 'Vollmilch'),
      _article(id: _old, sku: 'OLD', name: 'Alt'),
    ]);
    f.api.pageSize = 2;
    await f.controller.load();
    expect(f.controller.articles, hasLength(2));
    expect(f.controller.hasMore, isTrue);
    await f.controller.loadMore();
    expect(f.controller.articles, hasLength(3));
    expect(f.controller.hasMore, isFalse);
    expect(f.api.queries.last['after'], isNotNull);
  });

  testWidgets(
    'article section defaults to active only and shows both on toggle',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.articles.addAll([
        _article(),
        _article(id: _old, sku: 'OLD', name: 'Altartikel', active: false),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ArticleSection(controller: f.controller)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mehl'), findsOneWidget);
      expect(find.text('Altartikel'), findsNothing);
      await tester.tap(find.byKey(const Key('article-include-inactive')));
      await tester.pumpAndSettle();
      expect(find.text('Altartikel'), findsOneWidget);
      expect(find.text('OLD · kg · 000123 · inaktiv'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('create dialog canonicalizes blank optional fields to null', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ArticleSection(controller: f.controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-article')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('article-sku-input')), 'NEU-1');
    await tester.enterText(find.byKey(const Key('article-name-input')), 'Neu');
    await tester.enterText(find.byKey(const Key('article-unit-input')), 'Stk');
    await tester.enterText(
      find.byKey(const Key('article-barcode-input')),
      '   ',
    );
    await tester.enterText(
      find.byKey(const Key('article-description-input')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('article-submit')));
    await tester.pumpAndSettle();
    expect(f.api.lastCreateBody, isNotNull);
    expect(f.api.lastCreateBody!['barcode'], isNull);
    expect(f.api.lastCreateBody!['description'], isNull);
    expect(f.api.lastCreateBody!['sku'], 'NEU-1');
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('invalid create input is rejected locally without a request', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ArticleSection(controller: f.controller)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-article')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('article-sku-input')), '   ');
    await tester.enterText(find.byKey(const Key('article-name-input')), 'Neu');
    await tester.enterText(find.byKey(const Key('article-unit-input')), 'Stk');
    await tester.tap(find.byKey(const Key('article-submit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('article-form-error')), findsOneWidget);
    expect(f.api.postCount, 0);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
}

class _Fixture {
  _Fixture(this.session, this.platform, this.controller, this.api);
  final SessionController session;
  final PlatformController platform;
  final ArticleController controller;
  final _ArticleApi api;
  bool _disposed = false;
  static Future<_Fixture> create(String role) async {
    final api = _ArticleApi(role);
    final session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final controller = ArticleController(session, platform, api);
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

class _ArticleApi implements PlatformApi {
  _ArticleApi(this.role);
  final String role;
  final List<ArticleDto> articles = [];
  final List<Map<String, String>> queries = [];
  final List<String> getRequests = [];
  Map<String, dynamic>? lastCreateBody;
  List<Object>? lastLifecycle;
  int postCount = 0;
  int pageSize = 50;
  bool loseCreateResponse = false;
  StoreApiException? failCreate, failPost;
  Completer<Map<String, dynamic>>? pendingWrite;

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': 'account',
        'companyId': _company,
        'locationId': _location,
        'role': role,
        'permissions': [
          'context.read',
          'organization.read',
          if (role == 'admin') 'inventory.articles.manage',
        ],
      };
    }
    if (route == '/articles') {
      getRequests.add(route);
      queries.add({...?query, 'after': ?after});
      var matching = articles.where((article) {
        final active = query?['active'];
        if (active == 'true' && !article.isActive) return false;
        if (active == 'false' && article.isActive) return false;
        final q = query?['q']?.toLowerCase();
        if (q != null &&
            !article.name.toLowerCase().contains(q) &&
            !article.sku.toLowerCase().contains(q)) {
          return false;
        }
        if (after != null && article.id.compareTo(after) <= 0) return false;
        return true;
      }).toList()..sort((a, b) => a.id.compareTo(b.id));
      final page = matching.take(pageSize).toList();
      return {
        'items': page.map((article) => article.toJson()).toList(),
        'nextCursor': matching.length > page.length ? page.last.id : null,
      };
    }
    final id = route.split('/').last;
    return articles.singleWhere((article) => article.id == id).toJson();
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    postCount++;
    if (pendingWrite case final pending?) return pending.future;
    if (route == '/articles') {
      lastCreateBody = body;
      if (failCreate case final failure?) throw failure;
      final article = ArticleDto(
        id: body['id'] as String,
        companyId: _company,
        sku: body['sku'] as String,
        barcode: body['barcode'] as String?,
        name: body['name'] as String,
        description: body['description'] as String?,
        unit: body['unit'] as String,
        isActive: true,
        version: 1,
        createdAt: DateTime.utc(2030, 1, 1, 8),
        updatedAt: DateTime.utc(2030, 1, 1, 8),
      );
      articles.add(article);
      if (loseCreateResponse) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      return article.toJson();
    }
    if (failPost case final failure?) throw failure;
    final segments = route.split('/');
    final id = segments[2];
    final index = articles.indexWhere((article) => article.id == id);
    final current = articles[index];
    if (route.endsWith('/edit')) {
      final updated = ArticleDto(
        id: current.id,
        companyId: current.companyId,
        sku: body['sku'] as String,
        barcode: body['barcode'] as String?,
        name: body['name'] as String,
        description: body['description'] as String?,
        unit: body['unit'] as String,
        isActive: current.isActive,
        version: current.version + 1,
        createdAt: current.createdAt,
        updatedAt: DateTime.utc(2030, 1, 1, 9),
      );
      articles[index] = updated;
      return updated.toJson();
    }
    final activate = route.endsWith('/reactivate');
    lastLifecycle = [
      activate ? 'reactivate' : 'deactivate',
      body['expectedVersion'],
    ];
    final updated = ArticleDto(
      id: current.id,
      companyId: current.companyId,
      sku: current.sku,
      barcode: current.barcode,
      name: current.name,
      description: current.description,
      unit: current.unit,
      isActive: activate,
      version: current.version + 1,
      createdAt: current.createdAt,
      updatedAt: DateTime.utc(2030, 1, 1, 9),
    );
    articles[index] = updated;
    return updated.toJson();
  }
}
