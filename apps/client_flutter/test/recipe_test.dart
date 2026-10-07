import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_client/src/application/recipe_controller.dart';
import 'package:storeos_client/src/application/platform_controller.dart';
import 'package:storeos_client/src/application/session_controller.dart';
import 'package:storeos_client/src/data/platform_api.dart';
import 'package:storeos_client/src/data/store_api.dart';
import 'package:storeos_client/src/ui/recipe_section.dart';

const company = '11111111-1111-4111-8111-111111111111',
    location = '22222222-2222-4222-8222-222222222222',
    article = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    revision = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    produced = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    ingredient = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
    line = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
const literal = '<script>alert(1)</script>\n<a href="x">** ä 😀';
Map<String, dynamic> snapshotJson(String id) => {
  'id': id,
  'sku': id == produced ? 'P' : 'I',
  'name': id == produced ? 'Produced' : 'Ingredient',
  'unit': id == produced ? 'tray' : 'kg',
};
Map<String, dynamic> contextJson(String id) => {
  'article': snapshotJson(id),
  'isActive': true,
};
Map<String, dynamic> get contentJson => {
  'produced': snapshotJson(produced),
  'batchDescription': 'One tray',
  'preparation': literal,
  'ingredients': [
    {
      'id': line,
      'position': 1,
      'article': snapshotJson(ingredient),
      'quantity': '1.250',
    },
  ],
};
Map<String, dynamic> articleJson({int version = 2}) => {
  'id': article,
  'companyId': company,
  'producedArticleId': produced,
  'status': 'active',
  'version': version,
  'currentPublishedRevisionId': null,
  'activeDraftRevisionId': revision,
  'createdAt': '2030-01-01T08:00:00Z',
  'updatedAt': '2030-01-01T08:00:00Z',
  'createdBy': company,
  'retiredAt': null,
  'retiredBy': null,
};
Map<String, dynamic> revisionJson({String status = 'draft'}) => {
  'id': revision,
  'companyId': company,
  'recipeId': article,
  'revisionNumber': 1,
  'status': status,
  'content': contentJson,
  'createdAt': '2030-01-01T08:00:00Z',
  'createdBy': company,
  'publishedAt': status == 'published' ? '2030-01-01T09:00:00Z' : null,
  'publishedBy': status == 'published' ? company : null,
  'publishOperationId': status == 'published' ? line : null,
  'publishExpectedVersion': status == 'published' ? 2 : null,
  'publicationVersion': status == 'published' ? 3 : null,
  'discardedAt': null,
  'discardedBy': null,
};
Map<String, dynamic> get detailJson => {
  'recipe': articleJson(),
  'draft': revisionJson(),
  'currentPublished': null,
  'currentProduced': contextJson(produced),
  'currentIngredients': [contextJson(ingredient)],
};
Map<String, dynamic> get employeeJson => {
  'recipeId': article,
  'revisionId': revision,
  'revisionNumber': 1,
  'publishedAt': '2030-01-01T09:00:00Z',
  'content': contentJson,
  'currentProduced': contextJson(produced),
  'currentIngredients': [contextJson(ingredient)],
};
Future<(SessionController, PlatformController, RecipeController)> _setup(
  _Auth auth,
  _Api api,
) async {
  final s = SessionController(auth),
      p = PlatformController(s, api),
      c = RecipeController(s, p, api);
  final ready = Completer<void>();
  void loaded() {
    if (p.organization != null && !p.isBusy && !ready.isCompleted) {
      ready.complete();
    }
  }

  p.addListener(loaded);
  await s.signIn(username: 'admin', password: 'test');
  loaded();
  await ready.future;
  p.removeListener(loaded);
  addTearDown(() {
    c.dispose();
    p.dispose();
    s.dispose();
  });
  c.detail = RecipeDetailDto.fromJson(detailJson);
  c.editing = c.detail!.draft!.content.editable;
  c.selectedRevision = c.detail!.draft;
  c.selectedContext = c.detail!.currentIngredients;
  return (s, p, c);
}

void main() {
  for (final uncertain in [false, true]) {
    testWidgets(
      '${uncertain ? 'uncertain' : 'stale'} save adopts authoritative mg snapshots and rendered quantity',
      (tester) async {
        final api = _Api();
        final result = await tester.runAsync(() => _setup(_Auth(), api));
        final (_, _, c) = result!;
        c.managing = true;
        c.selectedSnapshots[line] = RecipeArticleSnapshot.fromJson(
          snapshotJson(ingredient),
        );
        c.changeQuantity(line, '2');
        api.failure = uncertain
            ? const StoreApiException('network', 'Lost response')
            : const StoreApiException(
                'stale_version',
                'Changed',
                statusCode: 409,
              );
        expect(
          await c.save(),
          uncertain ? RecipeOutcome.uncertain : RecipeOutcome.rejected,
        );
        final authoritative = detailJson;
        authoritative['recipe'] = articleJson(version: 3);
        final fresh = {
          ...snapshotJson(ingredient),
          'sku': 'MG-SKU',
          'name': 'Milligram ingredient',
          'unit': 'mg',
        };
        final content =
            authoritative['draft']['content'] as Map<String, dynamic>;
        content['ingredients'][0]['article'] = fresh;
        content['ingredients'][0]['quantity'] = '3.500';
        authoritative['currentIngredients'] = [
          {'article': fresh, 'isActive': true},
        ];
        api.failure = null;
        api.reads['${RecipeController.manageRoot}/$article'] = authoritative;
        await c.reloadForReview();
        expect(c.editing!.ingredients.single.quantity, '2');
        expect(c.selectedSnapshots[line]!.unit, 'kg');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: RecipeSection(controller: c)),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Geprüften Serverstand übernehmen'));
        await tester.pumpAndSettle();
        expect(c.selectedSnapshots, isEmpty);
        expect(
          c.ingredientSnapshot(c.editing!.ingredients.single)!.toJson(),
          fresh,
        );
        expect(c.editing!.ingredients.single.reselect, false);
        expect(c.editing!.ingredients.single.quantity, '3.500');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('recipe-quantity-$line')),
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('recipe-list')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('Gespeicherte Einheit: mg'), findsOneWidget);
        expect(find.text('1. MG-SKU · Milligram ingredient'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(
                find.byKey(const ValueKey('recipe-quantity-$line')),
              )
              .controller!
              .text,
          '3.500',
        );
        expect(find.textContaining('gespeichert kg'), findsNothing);
        api.reply = {
          'detail': authoritative,
          'revision': authoritative['draft'],
        };
        expect(await c.save(), RecipeOutcome.confirmed);
        final savedLine =
            (api.bodies.last['content'] as Map)['ingredients'][0] as Map;
        expect(savedLine['reselect'], false);
        expect(savedLine['quantity'], '3.500');
        expect(c.detail!.draft!.content.ingredients.single.article.unit, 'mg');
        api.reply = {
          'revision': {
            ...authoritative['draft'] as Map<String, dynamic>,
            'status': 'published',
            'publishedAt': '2030-01-01T09:00:00Z',
            'publishedBy': company,
            'publishOperationId': line,
            'publishExpectedVersion': 3,
            'publicationVersion': 4,
          },
          'replayed': false,
        };
        expect(await c.publish(), RecipeOutcome.confirmed);
        expect(
          c
              .confirmedPublication!
              .revision
              .content
              .ingredients
              .single
              .article
              .unit,
          'mg',
        );
      },
    );
  }
  testWidgets(
    'manager can recover initial discard using the normal empty draft action',
    (tester) async {
      final api = _Api();
      final result = await tester.runAsync(() => _setup(_Auth(), api));
      final (_, _, c) = result!;
      c.managing = true;
      final noDraft = {
        ...detailJson,
        'draft': null,
        'recipe': {...articleJson(), 'activeDraftRevisionId': null},
      };
      api.reply = {
        'detail': noDraft,
        'revision': {
          ...revisionJson(),
          'status': 'discarded',
          'discardedAt': '2030-01-01T09:00:00Z',
          'discardedBy': company,
        },
      };
      api.reads['${RecipeController.manageRoot}/$article'] = noDraft;
      expect(await c.discard(), RecipeOutcome.confirmed);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecipeSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Neuen leeren Entwurf erstellen'), findsOneWidget);
      const next = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
      final newDraft = detailJson;
      newDraft['recipe'] = {
        ...articleJson(version: 3),
        'activeDraftRevisionId': next,
      };
      newDraft['draft'] = {
        ...revisionJson(),
        'id': next,
        'revisionNumber': 2,
        'content': {
          ...contentJson,
          'batchDescription': '',
          'preparation': '',
          'ingredients': <Map<String, dynamic>>[],
        },
      };
      api.reply = {'detail': newDraft, 'revision': newDraft['draft']};
      api.reads['${RecipeController.manageRoot}/$article'] = newDraft;
      await tester.tap(find.byKey(const Key('recipe-new-draft')));
      await tester.pumpAndSettle();
      expect(c.detail!.recipe.id, article);
      expect(c.detail!.draft!.revisionNumber, 2);
      expect(c.editing!.ingredients, isEmpty);
      expect(find.byKey(const Key('recipe-batch')), findsOneWidget);
      expect(find.byKey(const Key('recipe-preparation')), findsOneWidget);
      expect(find.byKey(const Key('recipe-new-draft')), findsNothing);
    },
  );
  test('bounded employee paging retains literal query and safe DTO', () async {
    final api = _Api();
    final (_, _, c) = await _setup(_Auth(), api);
    api.reads[RecipeController.publicRoot] = {
      'items': [employeeJson],
      'nextCursor': 'cursor',
    };
    await c.search('%_\\');
    await c.search(c.query, more: true);
    expect(c.published, hasLength(2));
    expect(api.queries.last, {'q': '%_\\', 'after': 'cursor'});
    await c.openInstruction(article);
    expect(c.instruction!.content.preparation, literal);
  });
  test('dirty publication is blocked and saved preview stays exact', () async {
    final api = _Api();
    final (_, _, c) = await _setup(_Auth(), api);
    c.setEditing(
      RecipeDraftContent(
        batchDescription: 'Changed',
        preparation: 'changed',
        ingredients: c.editing!.ingredients,
      ),
    );
    expect(await c.publish(), RecipeOutcome.rejected);
    expect(api.bodies, isEmpty);
    expect(c.detail!.draft!.content.preparation, literal);
  });
  for (final code in [400, 409, 413, 415, 422]) {
    test('definitive $code retains unsaved composition', () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      c.changeQuantity(line, '2.125');
      api.failure = StoreApiException('rejected', 'Rejected', statusCode: code);
      expect(await c.save(), RecipeOutcome.rejected);
      expect(c.editing!.ingredients.single.quantity, '2.125');
      expect(c.pending, isNull);
      expect(c.needsReview, code == 409);
    });
  }
  test(
    'uncertain publication retains deep immutable exact retry and synchronous busy guard',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.hold = Completer<Map<String, dynamic>>();
      final first = c.publish();
      expect(await c.publish(), RecipeOutcome.busy);
      expect(api.bodies, hasLength(1));
      final retained = c.pending!;
      expect(
        () => retained.body['expectedVersion'] = 50,
        throwsUnsupportedError,
      );
      api.hold!.completeError(const StoreApiException('network', 'Lost'));
      expect(await first, RecipeOutcome.uncertain);
      api.hold = null;
      api.reply = {
        'revision': revisionJson(status: 'published'),
        'replayed': true,
      };
      expect(await c.retryPublication(), RecipeOutcome.confirmed);
      expect(api.bodies.last, retained.body);
      expect(c.pending, isNull);
      expect(c.confirmedPublication!.replayed, isTrue);
    },
  );
  test(
    'uncertain save requires reload and review rather than replay',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      c.changeQuantity(line, '3');
      api.failure = const StoreApiException('network', 'Lost');
      expect(await c.save(), RecipeOutcome.uncertain);
      expect(c.needsReview, isTrue);
      expect(
        () =>
            (c.pending!.body['content'] as Map)['batchDescription'] = 'mutated',
        throwsUnsupportedError,
      );
      expect(
        () => ((c.pending!.body['content'] as Map)['ingredients'] as List)
            .clear(),
        throwsUnsupportedError,
      );
      expect(await c.save(), RecipeOutcome.busy);
      api.failure = null;
      await c.reloadForReview();
      expect(c.reviewedReload, isTrue);
      c.acceptReviewedState();
      expect(c.pending, isNull);
      expect(c.editing!.ingredients.single.quantity, '1.250');
    },
  );
  test(
    'confirmed publication with failed refresh remains confirmed evidence',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      api.reply = {
        'revision': revisionJson(status: 'published'),
        'replayed': false,
      };
      api.readFailure = const StoreApiException('network', 'Offline');
      expect(await c.publish(), RecipeOutcome.confirmed);
      expect(c.confirmedPublication, isNotNull);
      expect(c.pending, isNull);
      expect(c.refreshWarning, isNotNull);
    },
  );
  test(
    'same-account replacement fences delayed mutation and clears every recipe surface',
    () async {
      final api = _Api();
      final auth = _Auth();
      final (s, _, c) = await _setup(auth, api);
      c.query = 'old';
      c.candidateQuery = 'old';
      c.candidates = [RecipeArticleContext.fromJson(contextJson(ingredient))];
      c.producedSelection = produced;
      c.selectedSnapshots[line] = RecipeArticleSnapshot.fromJson(
        snapshotJson(ingredient),
      );
      c.history = [c.detail!.draft!];
      api.hold = Completer<Map<String, dynamic>>();
      final command = c.save();
      await s.signOut();
      await s.signIn(username: 'admin', password: 'test');
      api.hold!.complete({'detail': detailJson, 'revision': revisionJson()});
      expect(await command, RecipeOutcome.fenced);
      expect(c.detail, isNull);
      expect(c.editing, isNull);
      expect(c.history, isEmpty);
      expect(c.candidates, isEmpty);
      expect(c.selectedSnapshots, isEmpty);
      expect(c.producedSelection, isNull);
      expect(c.pending, isNull);
      expect(c.query, isEmpty);
    },
  );
  test(
    'delayed old-session discovery cannot populate a replacement session',
    () async {
      final api = _Api();
      final (s, _, c) = await _setup(_Auth(), api);
      api.readHold = Completer<Map<String, dynamic>>();
      final read = c.search('secret');
      await s.signOut();
      await s.signIn(username: 'different', password: 'test');
      api.readHold!.complete({
        'items': [employeeJson],
        'nextCursor': null,
      });
      await read;
      expect(c.published, isEmpty);
      expect(c.query, isEmpty);
      expect(c.busy, isFalse);
    },
  );
  test(
    'exact Article ID reselection and historical context are separate from frozen content',
    () async {
      final api = _Api();
      final (_, _, c) = await _setup(_Auth(), api);
      final fresh = contextJson(ingredient);
      fresh['article'] = {
        ...snapshotJson(ingredient),
        'sku': 'RENAMED',
        'unit': 'L',
      };
      api.reads['/production/manage/article-candidates'] = {
        'items': [fresh],
        'nextCursor': null,
      };
      await c.refreshIngredient(line);
      expect(api.queries.last, {'id': ingredient});
      expect(c.ingredientSnapshot(c.editing!.ingredients.single)!.unit, 'L');
      expect(c.editing!.ingredients.single.quantity, '1.250');
      expect(c.editing!.ingredients.single.reselect, isTrue);
      expect(c.detail!.draft!.content.ingredients.single.article.unit, 'kg');
      await c.selectRevision(c.detail!.draft!);
      expect(c.selectedRevision!.content.preparation, literal);
    },
  );
  testWidgets('employee has only approved read and literal composition', (
    tester,
  ) async {
    final result = await tester.runAsync(
      () => _setup(_Auth(), _Api(role: 'employee')),
    );
    final (_, _, c) = result!;
    c.instruction = PublishedRecipeDto.fromJson(employeeJson);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RecipeSection(controller: c)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Verwalten'), findsNothing);
    await tester.scrollUntilVisible(
      find.widgetWithText(SelectableText, literal),
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('recipe-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.widgetWithText(SelectableText, literal), findsOneWidget);
  });
  testWidgets(
    'literal preview and mounted editor/search clear on different-account replacement',
    (tester) async {
      final api = _Api();
      final result = await tester.runAsync(() => _setup(_Auth(), api));
      final (s, _, c) = result!;
      c.managing = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: RecipeSection(controller: c)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('recipe-batch')),
        'PRIVATE BATCH',
      );
      await tester.enterText(
        find.byKey(const Key('recipe-article-search')),
        'PRIVATE PICKER',
      );
      expect(c.editing!.batchDescription, 'PRIVATE BATCH');
      await tester.runAsync(() async {
        await s.signOut();
        await s.signIn(username: 'different', password: 'test');
      });
      await tester.pumpAndSettle();
      expect(find.text('PRIVATE BATCH'), findsNothing);
      expect(find.text('PRIVATE PICKER'), findsNothing);
      expect(c.editing, isNull);
      expect(c.detail, isNull);
    },
  );
}

class _Auth implements StoreApi {
  int generation = 0;
  Completer<void>? statusGate;
  Completer<void> statusStarted = Completer<void>();
  @override
  Future<SessionResponse> login(LoginRequest r) async => SessionResponse(
    token: '${r.username}:${++generation}',
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
    user: SessionUser(
      id: r.username,
      username: r.username,
      companyId: company,
      locationId: location,
    ),
  );
  @override
  Future<SystemStatusResponse> systemStatus({
    required String token,
    required String locationId,
  }) async {
    if (statusGate != null) {
      if (!statusStarted.isCompleted) statusStarted.complete();
      await statusGate!.future;
    }
    return const SystemStatusResponse(companyId: company, locationId: location);
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

/// Transport recorder: server replay/lifecycle semantics are tested in PostgreSQL.
class _Api implements PlatformApi {
  _Api({this.role = 'admin'});
  final String role;
  final bodies = <Map<String, dynamic>>[], queries = <Map<String, String>?>[];
  final reads = <String, Map<String, dynamic>>{};
  Completer<Map<String, dynamic>>? hold, readHold;
  StoreApiException? failure, readFailure;
  Map<String, dynamic>? reply;
  @override
  Future<Map<String, dynamic>> post(
    String token,
    String route,
    Map<String, dynamic> body,
  ) async {
    bodies.add(body);
    if (hold != null) return hold!.future;
    if (failure != null) throw failure!;
    return reply ?? {'detail': detailJson, 'revision': revisionJson()};
  }

  @override
  Future<Map<String, dynamic>> get(
    String token,
    String route, {
    String? after,
    Map<String, String>? query,
  }) async {
    if (route == '/context') {
      return {
        'userId': token.split(':').first,
        'companyId': company,
        'locationId': location,
        'role': role,
        'permissions': [
          'production.recipes.read',
          if (role == 'admin') ...[
            'production.recipes.manage',
            'production.recipes.publish',
          ],
        ],
      };
    }
    if (route == '/organization') {
      return {
        'company': {'id': company, 'name': 'Test', 'version': 1},
        'locations': [
          {'id': location, 'companyId': company, 'name': 'Home', 'version': 1},
        ],
      };
    }
    queries.add(query);
    if (readHold != null) return readHold!.future;
    if (readFailure != null) throw readFailure!;
    if (reads.containsKey(route)) return reads[route]!;
    if (route == '${RecipeController.manageRoot}/$article') {
      return detailJson;
    }
    if (route == '${RecipeController.publicRoot}/$article') {
      return employeeJson;
    }
    if (route ==
        '${RecipeController.manageRoot}/$article/revisions/$revision') {
      return {
        'revision': revisionJson(),
        'currentProduced': contextJson(produced),
        'currentIngredients': [contextJson(ingredient)],
      };
    }
    return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
  }
}
