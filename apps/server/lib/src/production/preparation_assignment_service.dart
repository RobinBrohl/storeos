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
import 'preparation_assignment.dart';
import 'preparation_assignment_repository.dart';
import 'preparation_batch_repository.dart';
import 'preparation_batch_service.dart';
import 'recipe_repository.dart';

class PreparationAssignmentService {
  PreparationAssignmentService(this.database)
    : _assignments = PreparationAssignmentRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _batches = PreparationBatchRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _batchService = PreparationBatchService(database),
      _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database),
      _recipes = RecipeRepository(database.schema, database.companyId),
      _articles = RecipeArticlePort(database.schema, database.companyId);
  final PlatformDatabase database;
  final PreparationAssignmentRepository _assignments;
  final PreparationBatchRepository _batches;
  final PreparationBatchService _batchService;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;
  final RecipeRepository _recipes;
  final RecipeArticlePort _articles;

  Future<T> _run<T>(
    SessionPrincipal p,
    String location,
    String capability,
    Future<T> Function(TxSession, PlatformActor, String) work,
  ) async {
    try {
      return await database.runAuthorized(p, capability, (tx, actor) async {
        final canonicalLocation = recipeId(location);
        if (canonicalLocation != database.locationId ||
            actor.locationId != database.locationId ||
            actor.companyId != database.companyId) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Configured execution Location required.',
          );
        }
        await _organization.requireConfiguredLocation(tx, canonicalLocation);
        _right(actor, 'production.recipes.read');
        return work(tx, actor, canonicalLocation);
      });
    } on PreparationInputException catch (e) {
      throw PlatformFailure(400, e.code, e.message);
    } on RecipeInputException catch (e) {
      throw PlatformFailure(400, e.code, e.message);
    } on ServerException catch (e) {
      if (e.code == '23505' &&
          e.constraintName == 'production_preparation_assignments_pkey') {
        throw const PlatformFailure(
          409,
          'already_exists',
          'Assignment identity already exists.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Assignment database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Assignment database unavailable.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Assignment database unavailable.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Assignment database unavailable.',
      );
    } on StateError catch (e) {
      if (e.message != 'request() may not be called on a closed Pool.') rethrow;
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Assignment database unavailable.',
      );
    }
  }

  void _right(PlatformActor actor, String capability) {
    if (!permissionsForRole(actor.role).contains(capability)) {
      throw const PlatformFailure(
        403,
        'forbidden',
        'Required authority unavailable.',
      );
    }
  }

  Future<bool> _eligible(TxSession tx, EmployeeDto employee) async {
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    return employee.companyId == database.companyId &&
        employee.locationId == database.locationId &&
        employee.isActive &&
        !employee.assignedFrom.isAfter(now) &&
        (employee.assignedUntil == null ||
            now.isBefore(employee.assignedUntil!));
  }

  Future<String> _self(TxSession tx, PlatformActor actor) async {
    final link = await _links.forAccount(tx, actor.id);
    if (link == null ||
        link.companyId != database.companyId ||
        link.locationId != database.locationId) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Current Employee unavailable.',
      );
    }
    final person = await _people.get(tx, link.employeeId);
    if (!await _eligible(tx, person)) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Current Employee unavailable.',
      );
    }
    return person.id;
  }

  Future<Map<String, dynamic>> _get(
    TxSession tx,
    String id, {
    String? employee,
    bool lock = false,
  }) async {
    final a = await _assignments.find(tx, recipeId(id), lock: lock);
    if (a == null || (employee != null && a['employeeId'] != employee)) {
      throw const PlatformFailure(404, 'not_found', 'Assignment not found.');
    }
    return a;
  }

  Future<Map<String, dynamic>?> _replay(
    TxSession tx,
    PlatformActor actor,
    String id,
    PreparationAssignmentCommandInput c,
  ) async {
    final r = await _assignments.receipt(tx, c.operationId);
    if (r == null) return null;
    if (r['assignment_id'] != id ||
        r['actor_id'] != actor.id ||
        r['location_id'] != database.locationId ||
        r['kind'] != c.kind ||
        PreparationAssignmentCommandInput.fromJson(
              r['kind'] as String,
              Map<String, dynamic>.from(r['payload'] as Map),
            ).canonical !=
            c.canonical) {
      throw const PlatformFailure(
        409,
        'operation_conflict',
        'Operation identity already bound.',
      );
    }
    return {...Map<String, dynamic>.from(r['result'] as Map), 'replayed': true};
  }

  Future<Map<String, dynamic>> command(
    SessionPrincipal p,
    String location,
    String? id,
    String kind,
    Map<String, dynamic> body, {
    bool self = false,
  }) => _run(
    p,
    location,
    self
        ? 'production.assignments.self.start'
        : 'production.assignments.manage',
    (tx, actor, location) async {
      if ((self && kind != 'start') ||
          (!self && !['create', 'withdraw'].contains(kind))) {
        throw const PlatformFailure(
          403,
          'forbidden',
          'Command authority unavailable.',
        );
      }
      if (self) _right(actor, 'production.batches.self.execute');
      final c = PreparationAssignmentCommandInput.fromJson(kind, body);
      final target = recipeId(kind == 'create' ? c.payload['id'] : id);
      final employee = self ? await _self(tx, actor) : null;
      Map<String, dynamic>? a;
      if (kind != 'create') {
        a = await _get(tx, target, employee: employee, lock: true);
      }
      final replay = await _replay(tx, actor, target, c);
      if (replay != null) return replay;
      Map<String, dynamic>? batch;
      if (kind == 'create') {
        if (await _assignments.find(tx, target) != null) {
          throw const PlatformFailure(
            409,
            'already_exists',
            'Assignment identity already exists.',
          );
        }
        EmployeeDto? person;
        try {
          person = await _people.get(tx, c.payload['employeeId'] as String);
        } on PlatformFailure catch (e) {
          if (e.status != 404) rethrow;
        }
        if (person == null ||
            !await _eligible(tx, person) ||
            !await _links.canStartPreparationAssignment(
              tx,
              person.id,
              location,
            )) {
          throw const PlatformFailure(
            422,
            'assignee_unavailable',
            'Select a currently eligible linked Employee.',
          );
        }
        if (person.version != c.payload['expectedEmployeeVersion']) {
          throw const PlatformFailure(
            409,
            'version_conflict',
            'Employee version changed.',
          );
        }
        await _batchService.validateAssignmentSelection(
          tx,
          c.payload['recipeId'] as String,
          c.payload['revisionId'] as String,
        );
        await _assignments.create(tx, actor.id, c);
      } else {
        PreparationAssignment(
          PreparationAssignmentDto.fromJson(a!),
        ).requireAssigned(c.payload['expectedVersion'] as int);
        if (kind == 'withdraw') {
          await _assignments.withdraw(tx, target, actor.id, c);
        } else {
          batch = await _batchService.openAssignedBatch(tx, actor, target);
          await _assignments.start(tx, target, batch, c);
        }
      }
      a = await _get(tx, target);
      final result = {'assignment': a, 'batch': ?batch, 'replayed': false};
      await _assignments.accept(tx, target, actor.id, c, result);
      await database.audit(
        tx,
        actor,
        'production.preparation_assignment.${switch (kind) {
          'create' => 'created',
          'withdraw' => 'withdrawn',
          _ => 'started',
        }}',
        'preparation_assignment',
        target,
        locationId: location,
        changes: {
          'assignmentId': target,
          'employeeId': a['employeeId'],
          'recipeId': a['recipeId'],
          'revisionId': a['revisionId'],
          'locationId': location,
          'operationId': c.operationId,
          'version': a['version'],
          'status': a['status'],
          if (batch != null) 'batchId': batch['batchId'],
        },
      );
      return result;
    },
  );
  Future<Map<String, dynamic>> _detail(
    TxSession tx,
    PlatformActor actor,
    Map<String, dynamic> a,
    bool self,
  ) async {
    Map<String, dynamic>? batch;
    if (a['batchId'] != null) {
      _right(
        actor,
        self ? 'production.batches.self.read' : 'production.batches.manage',
      );
      final b = await _batches.find(tx, a['batchId'] as String);
      if (b == null) {
        throw const PlatformFailure(
          500,
          'internal_error',
          'Linked Batch unavailable.',
        );
      }
      batch = await _batches.detail(tx, b);
    }
    return {...a, 'batch': batch};
  }

  Future<Map<String, dynamic>> detail(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = false,
  }) => _run(
    p,
    location,
    self ? 'production.assignments.self.read' : 'production.assignments.manage',
    (tx, actor, location) async => _detail(
      tx,
      actor,
      await _get(tx, id, employee: self ? await _self(tx, actor) : null),
      self,
    ),
  );
  Future<Map<String, dynamic>> list(
    SessionPrincipal p,
    String location, {
    bool self = false,
    String? status,
    String? after,
  }) => _run(
    p,
    location,
    self ? 'production.assignments.self.read' : 'production.assignments.manage',
    (tx, actor, location) async {
      final employee = self ? await _self(tx, actor) : null;
      if (status != null &&
          !['assigned', 'started', 'withdrawn'].contains(status)) {
        throw const PlatformFailure(
          400,
          'invalid_request',
          'Invalid lifecycle filter.',
        );
      }
      final scope = {
        'company': database.companyId,
        'location': location,
        'endpoint': 'preparation-assignments',
        'self': self,
        'employee': employee,
        'status': status,
      };
      final last = _cursor(after, scope);
      final rows = await _assignments.page(
        tx,
        employee: employee,
        status: status,
        after: last,
      );
      return {
        'items': rows.take(50).toList(),
        'nextCursor': rows.length > 50
            ? _encode({...scope, 'last': rows[49]['id']})
            : null,
      };
    },
  );
  String _encode(Map<String, dynamic> j) =>
      base64Url.encode(utf8.encode(jsonEncode(j))).replaceAll('=', '');
  String? _cursor(String? after, Map<String, dynamic> scope) {
    if (after == null) return null;
    try {
      if (after.length > 2048 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(after)) {
        throw const FormatException();
      }
      final j = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(after))),
      );
      if (j is! Map ||
          j.length != scope.length + 1 ||
          scope.entries.any((e) => j[e.key] != e.value)) {
        throw const FormatException();
      }
      return recipeId(j['last']);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped assignment cursor.',
      );
    }
  }

  Future<Map<String, dynamic>> assignees(
    SessionPrincipal p,
    String location, {
    String? after,
  }) => _run(p, location, 'production.assignments.manage', (
    tx,
    actor,
    location,
  ) async {
    final scope = {
      'company': database.companyId,
      'location': location,
      'endpoint': 'preparation-assignees',
    };
    final last = _cursor(after, scope);
    final people = (await _people.list(tx)).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    final eligible = <Map<String, dynamic>>[];
    for (final person in people) {
      if ((last == null || person.id.compareTo(last) > 0) &&
          await _eligible(tx, person) &&
          await _links.canStartPreparationAssignment(tx, person.id, location)) {
        eligible.add({
          'id': person.id,
          'displayName': person.displayName,
          'version': person.version,
        });
      }
      if (eligible.length == 51) break;
    }
    return {
      'items': eligible.take(50).toList(),
      'nextCursor': eligible.length > 50
          ? _encode({...scope, 'last': eligible[49]['id']})
          : null,
    };
  });
  Future<Map<String, dynamic>> history(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = false,
  }) => _run(
    p,
    location,
    self ? 'production.assignments.self.read' : 'production.assignments.manage',
    (tx, actor, location) async {
      final a = await _get(
        tx,
        id,
        employee: self ? await _self(tx, actor) : null,
      );
      final d = await _detail(tx, actor, a, self);
      return {'assignment': a, 'batch': d['batch']};
    },
  );
  Future<Map<String, dynamic>> recipe(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = false,
  }) => _run(
    p,
    location,
    self ? 'production.assignments.self.read' : 'production.assignments.manage',
    (tx, actor, location) async {
      final a = await _get(
        tx,
        id,
        employee: self ? await _self(tx, actor) : null,
      );
      final recipe = await _recipes.article(tx, a['recipeId'] as String);
      final r = await _recipes.revision(
        tx,
        a['recipeId'] as String,
        a['revisionId'] as String,
      );
      if (recipe == null || r == null || r.status != 'published') {
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
        'recipeId': recipe.id,
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
          if (recipe.status == 'retired') 'recipe_retired',
          if (recipe.currentPublishedRevisionId != r.id) 'recipe_replaced',
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
}
