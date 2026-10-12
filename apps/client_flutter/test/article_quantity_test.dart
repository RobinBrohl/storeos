import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/article_quantity_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/article_quantity_dialog.dart';

const actor = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222',
    article = '33333333-3333-4333-8333-333333333333',
    levelId = '44444444-4444-4444-8444-444444444444',
    profileId = '55555555-5555-4555-8555-555555555555',
    bindingId = '66666666-6666-4666-8666-666666666666',
    operation = '77777777-7777-4777-8777-777777777777';
final time = DateTime.utc(2026, 10, 12);
ArticleQuantityProfileDto profile() => ArticleQuantityProfileDto(
  id: profileId,
  articleId: article,
  baseUnit: 'kg',
  version: 1,
  status: 'active',
  packages: [],
  reason: 'Explicit anchor',
  recordedBy: actor,
  recordedAt: time,
);
StockQuantityBindingDto binding() => StockQuantityBindingDto(
  id: bindingId,
  levelId: levelId,
  profileId: profileId,
  profileVersion: 1,
  stockVersion: 1,
  unit: 'kg',
  label: 'kg',
  numerator: '1',
  denominator: '1',
  reason: 'Declared one Stock unit',
  recordedBy: actor,
  recordedAt: time,
);
StockLevelDto level() => StockLevelDto(
  id: levelId,
  locationId: location,
  articleId: article,
  stockUnit: 'legacy kg label',
  quantity: '2',
  version: 1,
  createdAt: time,
  updatedAt: time,
  article: const StockArticleDto(
    id: article,
    sku: 'SKU',
    barcode: null,
    name: 'Flour',
    unit: 'edited label',
    isActive: true,
  ),
  assortmentIsActive: true,
);
StockConversionPreviewDto preview() => const StockConversionPreviewDto(
  levelId: levelId,
  bindingId: bindingId,
  profileId: profileId,
  profileVersion: 1,
  stockVersion: 1,
  baseUnit: 'kg',
  stockUnit: 'legacy kg label',
  inputUnit: 'g',
  inputLabel: 'g',
  inputQuantity: '1250',
  numerator: '1',
  denominator: '1000',
  currentQuantity: '2',
  targetQuantity: '1.25',
  delta: '-0.75',
);

class Auth implements StoreApi {
  int token = 0;
  Completer<void>? statusGate;
  @override
  Future<SessionResponse> login(LoginRequest request) async => SessionResponse(
    token: 'token-${++token}',
    expiresAt: time.add(const Duration(days: 1)),
    user: const SessionUser(
      id: actor,
      username: 'admin',
      companyId: actor,
      locationId: location,
    ),
  );
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    await statusGate?.future;
    return const SystemStatusResponse(companyId: actor, locationId: location);
  }

  @override
  Future<void> logout(String token) async {}
  @override
  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String newPassword,
  }) async {}
}

class Api implements PlatformApi {
  bool drop = false, failRefresh = false;
  int? rejection;
  int posts = 0;
  Completer<void>? gate;
  Map<String, dynamic>? committed;
  final bodies = <String>[];
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (failRefresh) {
      throw const StoreApiException(
        'database_unavailable',
        'Unavailable',
        statusCode: 503,
      );
    }
    if (route.endsWith('/quantity')) {
      return {'profile': profile().toJson(), 'binding': binding().toJson()};
    }
    if (route.endsWith('/history') || route.endsWith('/evidence')) {
      return {'items': [], 'nextCursor': null};
    }
    return level().toJson();
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    posts++;
    if (route.endsWith('/preview')) return preview().toJson();
    bodies.add(jsonEncode(body));
    await gate?.future;
    if (rejection case final status?) {
      throw StoreApiException('forbidden', 'Access denied', statusCode: status);
    }
    committed ??= {
      'operationId': body['operationId'],
      'review': body['review'],
      'reason': body['reason'],
      'recordedBy': actor,
      'recordedAt': time.toIso8601String(),
      'movementId': body['operationId'],
      'balanceVersion': 2,
    };
    if (drop) throw const StoreApiException('network_error', 'Response lost');
    return committed!;
  }
}

class RemovedPackageApi extends Api {
  static const packageId = '88888888-8888-4888-8888-888888888888';
  bool bound = false;
  int previews = 0;
  StockQuantityBindingDto? confirmed;
  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (!route.endsWith('/quantity')) return level().toJson();
    return {
      'profile': {
        ...profile().toJson(),
        'version': bound ? 2 : 1,
        'packages': bound
            ? <Map<String, dynamic>>[]
            : [
                {'id': packageId, 'label': 'Bag', 'content': '25'},
              ],
      },
      'binding': confirmed?.toJson(),
    };
  }

  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (route.endsWith('/bind')) {
      confirmed = StockQuantityBindingDto.fromJson({
        ...binding().toJson(),
        'id': body['operationId'],
        'unit': body['unit'],
        'label': 'Bag',
        'numerator': '25',
        'reason': body['reason'],
      });
      bound = true;
      return confirmed!.toJson();
    }
    previews++;
    expect(body['inputUnit'], 'kg');
    expect(body['profileVersion'], 2);
    return {
      ...preview().toJson(),
      'bindingId': operation,
      'profileVersion': 2,
      'inputUnit': 'kg',
      'inputLabel': 'kg',
      'inputQuantity': body['inputQuantity'],
      'numerator': '1',
      'denominator': '25',
      'targetQuantity': '1',
      'delta': '-1',
    };
  }
}

Future<SessionController> signed(Auth auth) async {
  final session = SessionController(auth);
  await session.signIn(username: 'admin', password: 'fixture');
  return session;
}

void main() {
  for (final status in [400, 403, 409, 422]) {
    test(
      'lost committed response survives rejected retry $status and exact replay',
      () async {
        final api = Api(), session = await signed(Auth());
        final c = ArticleQuantityController(
          session,
          api,
          articleId: article,
          levelId: levelId,
          locationId: location,
          idFactory: () => operation,
        );
        addTearDown(() {
          c.dispose();
          session.dispose();
        });
        await c.load();
        await c.preview('g', '1250');
        api.drop = true;
        await c.correct('Reviewed reason');
        final frozen = c.pending, identity = session.sessionIdentity;
        final receipt = api.committed;
        api.drop = false;
        api.rejection = status;
        await c.retry();
        expect(c.pending, same(frozen));
        expect(c.pendingKind, 'correct');
        expect(c.decisionRequired, false);
        expect(c.result, isNull);
        expect(c.error, contains('unbestätigt'));
        expect(session.sessionIdentity, same(identity));
        await c.load();
        await c.correct('Changed reason');
        expect(c.pending, same(frozen));
        api.rejection = null;
        await c.retry();
        expect(c.result, receipt);
        expect(c.pending, isNull);
        expect(api.bodies, hasLength(3));
        expect(api.bodies, everyElement(api.bodies.first));
      },
    );
  }
  test(
    'first-attempt rejection requires new decision; uncertain rejection still fences replacement',
    () async {
      final auth = Auth(), api = Api(), session = await signed(auth);
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        idFactory: () => operation,
      );
      addTearDown(() {
        c.dispose();
        session.dispose();
      });
      await c.load();
      await c.preview('g', '1250');
      api.rejection = 403;
      await c.correct('Reviewed reason');
      expect(c.pending, isNull);
      expect(c.decisionRequired, true);
      expect(api.committed, isNull);
      api.rejection = null;
      await c.load();
      await c.preview('g', '1250');
      api.drop = true;
      await c.correct('Reviewed reason');
      api.rejection = 403;
      await c.retry();
      expect(c.pending, isNotNull);
      await session.signIn(username: 'admin', password: 'fixture');
      expect(c.live, false);
      expect(c.pending, isNull);
      expect(c.review, isNull);
      expect(c.binding, isNull);
      final posts = api.posts;
      await c.retry();
      expect(api.posts, posts);
    },
  );
  testWidgets(
    'package removed after confirmed binding requires explicit reselection and fresh review',
    (tester) async {
      final api = RemovedPackageApi(), session = await signed(Auth());
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        idFactory: () => operation,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleQuantityDialog(controller: c, name: 'Flour'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quantity-input-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bag (25 kg)').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quantity-reason')),
        'Declared bag',
      );
      await tester.ensureVisible(find.byKey(const Key('quantity-bind')));
      await tester.tap(find.byKey(const Key('quantity-bind')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(c.result, api.confirmed!.toJson());
      expect(c.binding!.toJson(), api.confirmed!.toJson());
      expect(c.binding!.profileVersion, 1);
      expect(c.profile!.version, 2);
      expect(c.profile!.packages, isEmpty);
      expect(
        find.byKey(const Key('quantity-unit-reselection')),
        findsOneWidget,
      );
      final dropdown = find.byKey(const Key('quantity-input-unit'));
      expect(tester.state<FormFieldState<String>>(dropdown).value, isNull);
      await tester.ensureVisible(find.byKey(const Key('quantity-reload')));
      await tester.tap(find.byKey(const Key('quantity-reload')));
      await tester.pumpAndSettle();
      expect(tester.state<FormFieldState<String>>(dropdown).value, isNull);
      await tester.enterText(
        find.byKey(const Key('quantity-input-value')),
        '25',
      );
      await tester.enterText(
        find.byKey(const Key('quantity-reason')),
        'Fresh target',
      );
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('quantity-preview')))
            .onPressed,
        isNull,
      );
      expect(api.previews, 0);
      await tester.ensureVisible(dropdown);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('quantity-preview')));
      await tester.tap(find.byKey(const Key('quantity-preview')));
      await tester.pumpAndSettle();
      expect(api.previews, 1);
      expect(c.review!.profileVersion, 2);
      expect(c.review!.inputUnit, 'kg');
      expect(c.review!.targetQuantity, '1');
      expect(c.binding!.toJson(), api.confirmed!.toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      session.dispose();
    },
  );
  test(
    'uncertain command freezes reason, review and UUID; duplicate send and edited retry blocked',
    () async {
      final auth = Auth(), api = Api(), session = await signed(auth);
      var ids = 0;
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        idFactory: () {
          ids++;
          return operation;
        },
      );
      addTearDown(() {
        c.dispose();
        session.dispose();
      });
      await c.load();
      await c.preview('g', '1250');
      api.drop = true;
      api.gate = Completer<void>();
      final sending = c.correct('Reviewed reason');
      await Future<void>.delayed(Duration.zero);
      await c.correct('Another reason');
      expect(ids, 1);
      expect(api.posts, 2);
      api.gate!.complete();
      await sending;
      expect(c.pending, isNotNull);
      expect(c.result, isNull);
      expect(() => c.pending!['reason'] = 'mutated', throwsUnsupportedError);
      expect(
        () => quantityObject(c.pending!['review'])['targetQuantity'] = '3',
        throwsUnsupportedError,
      );
      await c.load();
      expect(c.pending, isNotNull);
      await c.command('correct', {
        'review': preview().toJson(),
        'reason': 'Changed',
      });
      expect(ids, 1);
      api.drop = false;
      await c.retry();
      expect(c.pending, isNull);
      expect(c.result!['operationId'], operation);
      expect(api.bodies[0], api.bodies[1]);
      expect(ids, 1);
    },
  );
  test('confirmed write and failed refresh stays confirmed', () async {
    final auth = Auth(), api = Api(), session = await signed(auth);
    final c = ArticleQuantityController(
      session,
      api,
      articleId: article,
      levelId: levelId,
      locationId: location,
      idFactory: () => operation,
    );
    addTearDown(() {
      c.dispose();
      session.dispose();
    });
    await c.load();
    await c.preview('g', '1250');
    api.failRefresh = true;
    await c.correct('Physical target');
    expect(c.result, isNotNull);
    expect(c.pending, isNull);
    expect(c.refreshError, isNotNull);
    await c.retry();
    expect(api.posts, 2);
  });
  test(
    'same-account held session replacement fences pending request and clears reads immediately',
    () async {
      final auth = Auth(), api = Api(), session = await signed(auth);
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        idFactory: () => operation,
      );
      addTearDown(() {
        c.dispose();
        session.dispose();
      });
      await c.load();
      await c.preview('g', '1250');
      api.gate = Completer<void>();
      final sending = c.correct('private reason');
      await Future<void>.delayed(Duration.zero);
      auth.statusGate = Completer<void>();
      final replacement = session.signIn(
        username: 'admin',
        password: 'fixture',
      );
      await Future<void>.delayed(Duration.zero);
      expect(c.live, false);
      expect(c.pending, isNull);
      expect(c.profile, isNull);
      expect(c.binding, isNull);
      expect(c.level, isNull);
      expect(c.review, isNull);
      api.gate!.complete();
      await sending;
      expect(c.result, isNull);
      auth.statusGate!.complete();
      await replacement;
      await c.retry();
      expect(api.posts, 2);
    },
  );
  test(
    'Location replacement fences a held preview and invalid inputs create no operation',
    () async {
      final auth = Auth(), api = Api(), session = await signed(auth);
      bool current = true;
      var ids = 0;
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        locationCurrent: () => current,
        idFactory: () {
          ids++;
          return operation;
        },
      );
      addTearDown(() {
        c.dispose();
        session.dispose();
      });
      await c.load();
      await c.preview('g', '1e3');
      expect(api.posts, 0);
      await c.command('correct', {'review': preview().toJson(), 'reason': ''});
      expect(ids, 1);
      expect(c.pending, isNull);
      expect(api.posts, 0);
      current = false;
      c.invalidateLocation();
      expect(c.live, false);
      expect(c.level, isNull);
      await c.preview('g', '1250');
      expect(api.posts, 0);
    },
  );
  testWidgets(
    'review visibly shows exact target, delta and pinned versions; fields lock before submit',
    (tester) async {
      final auth = Auth(), api = Api(), session = await signed(auth);
      final c = ArticleQuantityController(
        session,
        api,
        articleId: article,
        levelId: levelId,
        locationId: location,
        idFactory: () => operation,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ArticleQuantityDialog(controller: c, name: 'Flour'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('quantity-input-unit')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('quantity-input-value')),
        '1250',
      );
      await tester.enterText(
        find.byKey(const Key('quantity-reason')),
        'Physical target',
      );
      await tester.ensureVisible(find.byKey(const Key('quantity-preview')));
      await tester.tap(find.byKey(const Key('quantity-preview')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('quantity-review')), findsOneWidget);
      expect(find.textContaining('1250 g → 1.25'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quantity-input-value')))
            .enabled,
        false,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quantity-reason')))
            .enabled,
        false,
      );
      await tester.ensureVisible(find.byKey(const Key('quantity-correct')));
      await tester.tap(find.byKey(const Key('quantity-correct')));
      await tester.pumpAndSettle();
      expect(c.result, isNotNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      session.dispose();
    },
  );
}
