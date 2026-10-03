import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/article_assortment_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/assortment_section.dart';

const _company = '11111111-1111-4111-8111-111111111111';
const _location = '22222222-2222-4222-8222-222222222222';
const _second = '33333333-3333-4333-8333-333333333333';
const _mehl = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _milch = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _assoc = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';

ArticleDto _article({
  String id = _mehl,
  String sku = 'SKU-1',
  String? barcode = '000123',
  String name = 'Mehl',
  String unit = 'kg',
  bool active = true,
  int version = 1,
}) => ArticleDto(
  id: id,
  companyId: _company,
  sku: sku,
  barcode: barcode,
  name: name,
  description: null,
  unit: unit,
  isActive: active,
  version: version,
  createdAt: DateTime.utc(2030, 1, 1, 8),
  updatedAt: DateTime.utc(2030, 1, 1, 8),
);

ArticleAssortmentDto _association({
  String id = _assoc,
  String location = _location,
  ArticleDto? article,
  bool active = true,
  int version = 1,
}) {
  final source = article ?? _article();
  return ArticleAssortmentDto(
    id: id,
    locationId: location,
    isActive: active,
    version: version,
    createdAt: DateTime.utc(2030, 1, 1, 8),
    updatedAt: DateTime.utc(2030, 1, 1, 8),
    article: ArticleAssortmentArticleDto(
      id: source.id,
      sku: source.sku,
      barcode: source.barcode,
      name: source.name,
      unit: source.unit,
      isActive: source.isActive,
    ),
  );
}

void main() {
  test('capability gating blocks every assortment request', () async {
    final f = await _Fixture.create('viewer');
    addTearDown(f.dispose);
    expect(f.controller.canManage, isFalse);
    await f.controller.selectLocation(_location);
    expect(f.api.assortmentRequests, isEmpty);
    expect(f.api.postCount, 0);
    expect(f.controller.items, isNull);
  });

  test('selecting a location loads active memberships by default', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    expect(f.controller.locations, hasLength(2));
    f.api.associations.addAll([
      _association(),
      _association(
        id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        article: _article(id: _milch, sku: 'MILCH', name: 'Vollmilch'),
        active: false,
      ),
    ]);
    await f.controller.selectLocation(_location);
    expect(f.api.queries.last['active'], 'true');
    expect(f.api.queries.last['after'], isNull);
    expect(f.controller.items, hasLength(1));
    await f.controller.setShowInactive(true);
    expect(f.api.queries.last.containsKey('active'), isFalse);
    expect(f.controller.items, hasLength(2));
  });

  test('search is sent literally and switching locations reloads', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.associations.addAll([
      _association(),
      _association(
        id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        article: _article(id: _milch, sku: 'MILCH', name: 'Vollmilch'),
      ),
    ]);
    await f.controller.selectLocation(_location);
    await f.controller.setSearch('milch');
    expect(f.api.queries.last['q'], 'milch');
    expect(f.controller.items, hasLength(1));
    expect(f.controller.items!.single.article.name, 'Vollmilch');
    await f.controller.setSearch('');
    await f.controller.selectLocation(_second);
    expect(f.controller.items, isEmpty);
    expect(f.api.queries.last['q'], isNull);
  });

  test('enable posts a client UUID and reconciles a lost response', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.articles.add(_article());
    f.api.loseCreateResponse = true;
    await f.controller.enable(_article());
    expect(f.api.postCount, 1);
    expect(f.controller.error, isNull);
    expect(f.controller.notice, contains('erneut geladen'));
    expect(f.controller.items, hasLength(1));
    expect(f.api.lastCreateBody!['articleId'], _mehl);
    expect(f.api.lastCreateBody!['id'], isA<String>());
  });

  test('a duplicate association stays a deterministic error', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.failCreate = const StoreApiException(
      'already_exists',
      'Conflict',
      statusCode: 409,
    );
    await f.controller.enable(_article());
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isFalse);
    expect(f.controller.error, contains('bereits im Sortiment'));
    expect(f.controller.showInactive, isTrue);
  });

  test('a globally inactive article is refused without retry', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.failCreate = const StoreApiException(
      'article_inactive',
      'Conflict',
      statusCode: 409,
    );
    await f.controller.enable(_article(active: false));
    expect(f.api.postCount, 1);
    expect(f.controller.error, contains('global inaktiv'));
  });

  test(
    'deactivate and reactivate are version guarded and refresh the list',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      await f.controller.selectLocation(_location);
      await f.controller.setShowInactive(true);
      f.api.articles.add(_article());
      await f.controller.enable(_article());
      final created = f.controller.items!.single;
      await f.controller.deactivate(created);
      expect(f.api.lastLifecycle, ['deactivate', 1]);
      expect(f.controller.items!.single.isActive, isFalse);
      expect(f.controller.items!.single.version, 2);
      await f.controller.reactivate(f.controller.items!.single);
      expect(f.api.lastLifecycle, ['reactivate', 2]);
      expect(f.controller.items!.single.isActive, isTrue);
      expect(f.controller.items!.single.version, 3);
    },
  );

  test('a stale lifecycle conflict asks for an explicit reload', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.associations.add(_association());
    await f.controller.load();
    f.api.failLifecycle = const StoreApiException(
      'assortment_conflict',
      'Conflict',
      statusCode: 409,
    );
    await f.controller.deactivate(f.controller.items!.single);
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isTrue);
    expect(f.controller.error, contains('neu laden'));
    await f.controller.load();
    expect(f.controller.conflict, isFalse);
  });

  test('lost lifecycle response confirms an exact no-op', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.associations.add(_association());
    await f.controller.load();
    f.api.lifecycleThrows = true;
    f.api.lifecycleMutations = 0;
    await f.controller.reactivate(f.controller.items!.single);
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isFalse);
    expect(f.controller.notice, contains('reaktiviert'));
  });

  test('lost lifecycle response confirms exactly one mutation', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.associations.add(_association());
    await f.controller.setShowInactive(true);
    f.api.lifecycleThrows = true;
    f.api.lifecycleMutations = 1;
    await f.controller.deactivate(f.controller.items!.single);
    expect(f.api.postCount, 1);
    expect(f.controller.conflict, isFalse);
    expect(f.controller.notice, contains('deaktiviert'));
    expect(f.controller.items!.single.isActive, isFalse);
    expect(f.controller.items!.single.version, 2);
  });

  test(
    'an ambiguous later version is never attributed to the request',
    () async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      await f.controller.selectLocation(_location);
      f.api.associations.add(_association());
      await f.controller.load();
      f.api.lifecycleThrows = true;
      f.api.lifecycleMutations = 2;
      await f.controller.deactivate(f.controller.items!.single);
      expect(f.api.postCount, 1);
      expect(f.controller.conflict, isTrue);
      expect(f.controller.error, contains('neu laden'));
    },
  );

  test('duplicate submit is blocked while a command is busy', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    final pending = Completer<Map<String, dynamic>>();
    f.api.pendingWrite = pending;
    final first = f.controller.enable(_article());
    await f.controller.enable(_article(id: _milch, sku: 'MILCH'));
    expect(f.api.postCount, 1);
    pending.complete(_association().toJson());
    await first;
    expect(f.api.postCount, 1);
  });

  test('pagination appends the next page', () async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    await f.controller.selectLocation(_location);
    f.api.associations.addAll([
      _association(),
      _association(
        id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
        article: _article(id: _milch, sku: 'MILCH'),
      ),
      _association(
        id: 'ffffffff-ffff-4fff-8fff-ffffffffffff',
        article: _article(
          id: '99999999-9999-4999-8999-999999999999',
          sku: 'SALZ',
        ),
      ),
    ]);
    f.api.pageSize = 2;
    await f.controller.load();
    expect(f.controller.items, hasLength(2));
    expect(f.controller.hasMore, isTrue);
    await f.controller.loadMore();
    expect(f.controller.items, hasLength(3));
    expect(f.controller.hasMore, isFalse);
    expect(f.api.queries.last['after'], isNotNull);
  });

  testWidgets(
    'section defaults to active memberships and shows both on toggle',
    (tester) async {
      final f = await _Fixture.create('admin');
      addTearDown(f.dispose);
      f.api.associations.addAll([
        _association(article: _article()),
        _association(
          id: 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          article: _article(id: _milch, sku: 'MILCH', name: 'Vollmilch'),
          active: false,
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AssortmentSection(
              controller: f.controller,
              platform: f.platform,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mehl'), findsOneWidget);
      expect(find.text('Vollmilch'), findsNothing);
      await tester.tap(find.byKey(const Key('assortment-include-inactive')));
      await tester.pumpAndSettle();
      expect(find.text('Vollmilch'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey(
            'assortment-inactive-eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
          ),
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      f.dispose();
    },
  );

  testWidgets('an active membership with a global inactive article is marked', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.associations.add(_association(article: _article(active: false)));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssortmentSection(
            controller: f.controller,
            platform: f.platform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mehl'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('assortment-article-inactive-$_assoc')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('assortment-effective-$_assoc')),
      findsNothing,
    );
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('the add dialog searches active articles and enables one', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.articles.add(_article());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssortmentSection(
            controller: f.controller,
            platform: f.platform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-assortment')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('assortment-add-search')),
      'mehl',
    );
    await tester.tap(find.byKey(const Key('assortment-add-search-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('assortment-add-$_mehl')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('assortment-add-$_mehl')));
    await tester.pumpAndSettle();
    expect(f.api.lastCreateBody!['articleId'], _mehl);
    expect(find.text('Mehl'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });

  testWidgets('an already associated article cannot be added twice', (
    tester,
  ) async {
    final f = await _Fixture.create('admin');
    addTearDown(f.dispose);
    f.api.articles.add(_article());
    f.api.associations.add(_association());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssortmentSection(
            controller: f.controller,
            platform: f.platform,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create-assortment')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('assortment-add-search')),
      'mehl',
    );
    await tester.tap(find.byKey(const Key('assortment-add-search-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining('bereits im Sortiment'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('assortment-add-$_mehl')));
    await tester.pumpAndSettle();
    expect(f.api.lastCreateBody, isNull);
    await tester.pumpWidget(const SizedBox());
    f.dispose();
  });
}

class _Fixture {
  _Fixture(this.session, this.platform, this.controller, this.api);
  final SessionController session;
  final PlatformController platform;
  final ArticleAssortmentController controller;
  final _AssortmentApi api;
  bool _disposed = false;

  static Future<_Fixture> create(String role) async {
    final api = _AssortmentApi(role);
    final session = SessionController(_Session());
    final platform = PlatformController(session, api);
    final controller = ArticleAssortmentController(session, platform, api);
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

class _AssortmentApi implements PlatformApi {
  _AssortmentApi(this.role);
  final String role;
  final List<ArticleDto> articles = [];
  final List<ArticleAssortmentDto> associations = [];
  final List<Map<String, String>> queries = [];
  final List<String> assortmentRequests = [];
  Map<String, dynamic>? lastCreateBody;
  List<Object>? lastLifecycle;
  int postCount = 0;
  int pageSize = 50;
  bool loseCreateResponse = false;
  bool lifecycleThrows = false;
  int lifecycleMutations = 1;
  StoreApiException? failCreate, failLifecycle;
  Completer<Map<String, dynamic>>? pendingWrite;

  List<ArticleAssortmentDto> _page(
    String locationId,
    Map<String, String> query,
    String? after,
  ) {
    var matching = associations.where((item) {
      if (item.locationId != locationId) return false;
      final active = query['active'];
      if (active == 'true' && !item.isActive) return false;
      if (active == 'false' && item.isActive) return false;
      final q = query['q']?.toLowerCase();
      if (q != null &&
          !item.article.name.toLowerCase().contains(q) &&
          !item.article.sku.toLowerCase().contains(q)) {
        return false;
      }
      if (after != null && item.id.compareTo(after) <= 0) return false;
      return true;
    }).toList()..sort((a, b) => a.id.compareTo(b.id));
    return matching;
  }

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
          if (role == 'admin') 'inventory.assortment.manage',
          if (role == 'admin') 'inventory.articles.manage',
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
    if (route == '/articles') {
      final q = parameters['q']?.toLowerCase();
      final active = parameters['active'];
      final matching = articles.where((article) {
        if (active == 'true' && !article.isActive) return false;
        if (q != null &&
            !article.name.toLowerCase().contains(q) &&
            !article.sku.toLowerCase().contains(q)) {
          return false;
        }
        return true;
      }).toList()..sort((a, b) => a.id.compareTo(b.id));
      return {
        'items': matching.map((article) => article.toJson()).toList(),
        'nextCursor': null,
      };
    }
    if (route.startsWith('/locations/')) {
      assortmentRequests.add(route);
      queries.add({...parameters, 'after': ?after});
      final segments = route.split('/');
      if (segments.length == 5) {
        final id = segments.last;
        return associations.singleWhere((item) => item.id == id).toJson();
      }
      final matching = _page(segments[2], parameters, after);
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
    if (pendingWrite case final pending?) return pending.future;
    final segments = route.split('/');
    if (segments.length == 4) {
      lastCreateBody = body;
      if (failCreate case final failure?) throw failure;
      final article = articles.singleWhere(
        (item) => item.id == body['articleId'],
      );
      final created = _association(
        id: body['id'] as String,
        article: article,
        location: segments[2],
      );
      associations.add(created);
      if (loseCreateResponse) {
        throw const StoreApiException('timeout', 'Unknown outcome');
      }
      return created.toJson();
    }
    final id = segments[4];
    final index = associations.indexWhere((item) => item.id == id);
    final current = associations[index];
    if (failLifecycle case final failure?) throw failure;
    final activate = segments.last == 'reactivate';
    lastLifecycle = [
      activate ? 'reactivate' : 'deactivate',
      body['expectedVersion'],
    ];
    if (lifecycleMutations > 0) {
      var updated = current;
      for (var i = 0; i < lifecycleMutations; i++) {
        updated = ArticleAssortmentDto(
          id: updated.id,
          locationId: updated.locationId,
          isActive: activate,
          version: updated.version + 1,
          createdAt: updated.createdAt,
          updatedAt: DateTime.utc(2030, 1, 1, 9),
          article: updated.article,
        );
      }
      associations[index] = updated;
    }
    if (lifecycleThrows) {
      throw const StoreApiException('timeout', 'Unknown outcome');
    }
    return associations[index].toJson();
  }
}
