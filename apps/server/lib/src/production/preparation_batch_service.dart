import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../inventory/recipe_article_port.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'preparation_batch.dart';
import 'preparation_batch_repository.dart';
import 'recipe_repository.dart';

class PreparationBatchService {
  PreparationBatchService(this.database)
    : _batches = PreparationBatchRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _recipes = RecipeRepository(database.schema, database.companyId),
      _articles = RecipeArticlePort(database.schema, database.companyId),
      _links = EmployeeLinks(database),
      _people = PeopleService(database),
      _organization = OrganizationService(database);
  final PlatformDatabase database;
  final PreparationBatchRepository _batches;
  final RecipeRepository _recipes;
  final RecipeArticlePort _articles;
  final EmployeeLinks _links;
  final PeopleService _people;
  final OrganizationService _organization;
  Future<T> _run<T>(
    SessionPrincipal p,
    String location,
    String capability,
    Future<T> Function(TxSession, PlatformActor) work,
  ) async {
    try {
      return await database.runAuthorized(p, capability, (tx, actor) async {
        if (recipeId(location) != database.locationId ||
            actor.locationId != database.locationId ||
            actor.companyId != database.companyId) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Configured execution Location required.',
          );
        }
        await _organization.requireConfiguredLocation(tx, location);
        return work(tx, actor);
      });
    } on PreparationInputException catch (e) {
      throw PlatformFailure(400, e.code, e.message);
    } on RecipeInputException catch (e) {
      throw PlatformFailure(400, e.code, e.message);
    } on ServerException catch (e) {
      if (e.code == '23505' &&
          e.constraintName == 'production_preparation_batches_pkey') {
        throw const PlatformFailure(
          409,
          'operation_conflict',
          'Batch identity already bound.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Preparation database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Preparation database unavailable.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Preparation database unavailable.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Preparation database unavailable.',
      );
    } on StateError catch (e) {
      if (e.message != 'request() may not be called on a closed Pool.') rethrow;
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Preparation database unavailable.',
      );
    }
  }

  Future<String> _self(
    TxSession tx,
    PlatformActor actor, {
    bool fresh = false,
  }) async {
    final link = await _links.forAccount(tx, actor.id);
    EmployeeDto? person;
    if (link != null &&
        link.companyId == actor.companyId &&
        link.locationId == database.locationId) {
      try {
        person = await _people.get(tx, link.employeeId);
      } on PlatformFailure catch (e) {
        if (e.status != 404) rethrow;
      }
    }
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    if (person == null ||
        !person.isActive ||
        person.companyId != actor.companyId ||
        person.locationId != database.locationId ||
        person.assignedFrom.isAfter(now) ||
        (person.assignedUntil != null &&
            !now.isBefore(person.assignedUntil!))) {
      throw PlatformFailure(
        fresh ? 422 : 404,
        fresh ? 'operator_unavailable' : 'not_found',
        'Current operator unavailable.',
      );
    }
    return person.id;
  }

  Future<Map<String, dynamic>> _get(
    TxSession tx,
    String id, {
    String? employee,
  }) async {
    final b = await _batches.find(tx, recipeId(id));
    if (b == null || (employee != null && b['employeeId'] != employee)) {
      throw const PlatformFailure(404, 'not_found', 'Batch not found.');
    }
    return b;
  }

  Future<Map<String, dynamic>?> _replay(
    TxSession tx,
    PlatformActor actor,
    String id,
    PreparationCommandInput c,
  ) async {
    final r = await _batches.receipt(tx, c.operationId);
    if (r == null) return null;
    final stored = PreparationCommandInput.fromJson(
      r['kind'] as String,
      Map<String, dynamic>.from(r['payload'] as Map),
    );
    if (r['batch_id'] != id ||
        r['location_id'] != database.locationId ||
        r['actor_id'] != actor.id ||
        r['kind'] != c.kind ||
        stored.canonical != c.canonical) {
      throw const PlatformFailure(
        409,
        'operation_conflict',
        'Operation identity is already bound.',
      );
    }
    return {...Map<String, dynamic>.from(r['result'] as Map), 'replayed': true};
  }

  Future<void> _freshRecipe(TxSession tx, PreparationCommandInput c) async {
    final a = await _recipes.article(tx, c.payload['recipeId'] as String);
    final r = a == null
        ? null
        : await _recipes.revision(tx, a.id, c.payload['revisionId'] as String);
    if (a == null ||
        a.status != 'active' ||
        r == null ||
        r.status != 'published' ||
        a.currentPublishedRevisionId != r.id) {
      throw const PlatformFailure(
        422,
        'recipe_selection_unavailable',
        'Select the exact current approved Recipe revision.',
      );
    }
    final current = {
      for (final a in await _articles.read(tx, {
        r.content.produced.id,
        ...r.content.ingredients.map((i) => i.article.id),
      }))
        a.article.id: a,
    };
    if (current[r.content.produced.id]?.isActive != true) {
      throw const PlatformFailure(
        422,
        'article_unavailable',
        'Produced Article unavailable.',
      );
    }
    if (!await _articles.effectivelyAvailable(
      tx,
      database.locationId,
      r.content.produced.id,
    )) {
      throw const PlatformFailure(
        422,
        'not_in_assortment',
        'Produced Article is not effectively assorted at this Location.',
      );
    }
    for (final i in r.content.ingredients) {
      if (current[i.article.id]?.isActive != true) {
        throw const PlatformFailure(
          422,
          'article_unavailable',
          'Ingredient Article unavailable.',
        );
      }
      if (current[i.article.id]!.article.unit != i.article.unit) {
        throw const PlatformFailure(
          422,
          'ingredient_unit_changed',
          'Ingredient unit changed; reselect and review the Recipe.',
        );
      }
    }
  }

  Future<Map<String, dynamic>> command(
    SessionPrincipal p,
    String location,
    String? id,
    String kind,
    Map<String, dynamic> body, {
    bool self = true,
  }) => _run(
    p,
    location,
    self ? 'production.batches.self.execute' : 'production.batches.manage',
    (tx, actor) async {
      if ((!self && !{'manager_cancel', 'count_correct'}.contains(kind)) ||
          (self && !{'open', 'complete', 'employee_cancel'}.contains(kind))) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Command authority unavailable.',
        );
      }
      final c = PreparationCommandInput.fromJson(kind, body);
      final batchId = recipeId(kind == 'open' ? c.payload['batchId'] : id);
      final employee = self
          ? await _self(tx, actor, fresh: kind == 'open')
          : null;
      Map<String, dynamic>? b;
      if (kind != 'open') {
        b = await _get(tx, batchId, employee: employee);
      } else {
        b = await _batches.find(tx, batchId);
        if (b != null && b['employeeId'] != employee) {
          throw const PlatformFailure(404, 'not_found', 'Batch not found.');
        }
      }
      final replay = await _replay(tx, actor, batchId, c);
      if (replay != null) return replay;
      Map<String, dynamic> result;
      if (kind == 'open') {
        if (b != null) {
          throw const PlatformFailure(
            409,
            'operation_conflict',
            'Batch identity already exists.',
          );
        }
        await _freshRecipe(tx, c);
        await _batches.open(tx, employee!, actor.id, c);
        result = {'batch': await _get(tx, batchId), 'replayed': false};
      } else {
        final aggregate = PreparationBatch(
          PreparationBatchDto.fromJson(await _batches.detail(tx, b!)),
        );
        if (kind == 'count_correct') {
          aggregate.requireCorrection(
            c.payload['expectedVersion'] as int,
            c.payload['expectedLatestCorrectionNumber'] as int,
          );
          result = {
            'correction': await _batches.correct(
              tx,
              aggregate.evidence,
              actor.id,
              c,
            ),
            'replayed': false,
          };
        } else {
          aggregate.requireOpen(c.payload['expectedVersion'] as int);
          await _batches.terminal(tx, batchId, actor.id, c);
          result = {'batch': await _get(tx, batchId), 'replayed': false};
        }
      }
      await _batches.accept(tx, batchId, actor.id, c, result);
      final evidence = await _get(tx, batchId);
      await database.audit(
        tx,
        actor,
        'production.batch.${switch (kind) {
          'open' => 'opened',
          'complete' => 'completed',
          'count_correct' => 'count_corrected',
          _ => 'cancelled',
        }}',
        'preparation_batch',
        batchId,
        locationId: location,
        changes: {
          'batchId': batchId,
          'recipeId': evidence['recipeId'],
          'revisionId': evidence['revisionId'],
          'employeeId': evidence['employeeId'],
          'locationId': location,
          'operationId': c.operationId,
          'version': evidence['version'],
          'status': evidence['status'],
          if (kind == 'count_correct')
            'correctionNumber':
                (result['correction'] as Map)['correctionNumber'],
        },
      );
      return result;
    },
  );
  Future<Map<String, dynamic>> detail(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = true,
  }) => _run(
    p,
    location,
    self ? 'production.batches.self.read' : 'production.batches.manage',
    (tx, actor) async => _batches.detail(
      tx,
      await _get(tx, id, employee: self ? await _self(tx, actor) : null),
    ),
  );
  Future<Map<String, dynamic>> recipe(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = true,
  }) => _run(
    p,
    location,
    self ? 'production.batches.self.read' : 'production.batches.manage',
    (tx, actor) async {
      final b = await _get(
        tx,
        id,
        employee: self ? await _self(tx, actor) : null,
      );
      if (!permissionsForRole(actor.role).contains('production.recipes.read')) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Recipe read authority required.',
        );
      }
      final a = await _recipes.article(tx, b['recipeId'] as String);
      final r = await _recipes.revision(
        tx,
        b['recipeId'] as String,
        b['revisionId'] as String,
      );
      if (a == null || r == null || r.status != 'published') {
        throw const PlatformFailure(
          500,
          'internal_error',
          'Retained approved evidence unavailable.',
        );
      }
      final current = await _articles.read(tx, {
        r.content.produced.id,
        ...r.content.ingredients.map((i) => i.article.id),
      });
      final contexts = {for (final i in current) i.article.id: i};
      return {
        'recipeId': a.id,
        'revisionId': r.id,
        'revisionNumber': r.revisionNumber,
        'publishedAt': r.publishedAt,
        'content': r.content.toJson(),
        'currentProduced': contexts[r.content.produced.id]?.toJson(),
        'currentIngredients': current
            .where((i) => i.article.id != r.content.produced.id)
            .map((i) => i.toJson())
            .toList(),
        'warnings': [
          if (a.status == 'retired') 'recipe_retired',
          if (a.currentPublishedRevisionId != r.id) 'recipe_replaced',
          if (contexts[r.content.produced.id]?.isActive != true)
            'produced_article_inactive',
          if (!await _articles.effectivelyAvailable(
            tx,
            location,
            r.content.produced.id,
          ))
            'produced_not_in_assortment',
          for (final i in r.content.ingredients) ...[
            if (contexts[i.article.id]?.isActive != true)
              'ingredient_inactive:${i.article.id}',
            if (contexts[i.article.id]?.article.unit != i.article.unit)
              'ingredient_unit_changed:${i.article.id}',
          ],
        ],
      };
    },
  );
  Future<Map<String, dynamic>> list(
    SessionPrincipal p,
    String location, {
    bool self = true,
    String? status,
    String? after,
  }) => _run(
    p,
    location,
    self ? 'production.batches.self.read' : 'production.batches.manage',
    (tx, actor) async {
      final employee = self ? await _self(tx, actor) : null;
      if (status != null &&
          !['open', 'completed', 'cancelled'].contains(status)) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Invalid lifecycle filter.',
        );
      }
      final scope = {
        'company': database.companyId,
        'location': location,
        'self': self,
        'employee': employee,
        'status': status,
      };
      String? last;
      if (after != null) {
        try {
          if (after.length > 2048 ||
              !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(after)) {
            throw const FormatException();
          }
          final j = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(after))),
          );
          if (j is! Map ||
              j.length != 6 ||
              scope.entries.any((e) => j[e.key] != e.value)) {
            throw const FormatException();
          }
          last = recipeId(j['last']);
        } on FormatException {
          throw const PlatformFailure(
            400,
            'invalid_cursor',
            'Invalid scoped batch cursor.',
          );
        }
      }
      final rows = await _batches.page(
        tx,
        employee: employee,
        status: status,
        after: last,
      );
      return {
        'items': [for (final b in rows.take(50)) await _batches.detail(tx, b)],
        'nextCursor': rows.length > 50
            ? base64Url
                  .encode(
                    utf8.encode(
                      jsonEncode({...scope, 'last': rows[49]['batchId']}),
                    ),
                  )
                  .replaceAll('=', '')
            : null,
      };
    },
  );
}
