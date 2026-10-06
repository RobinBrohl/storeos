import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../identity/employee_links.dart';
import '../infrastructure/auth_store.dart';
import '../people/people_service.dart';
import '../platform/organization_service.dart';
import '../platform/platform_database.dart';
import 'stock_count.dart';
import 'stock_count_repository.dart';
import 'stock_repository.dart';

/// Coordinates public eligibility ports and Stock-owned records in the same
/// authorized Company transaction as ordinary Stock corrections.
class StockCountService {
  StockCountService(this.database)
    : _people = PeopleService(database),
      _links = EmployeeLinks(database),
      _organization = OrganizationService(database),
      _counts = StockCountRepository(
        database.schema,
        database.companyId,
        database.locationId,
      ),
      _stock = StockRepository(
        database.schema,
        database.companyId,
        database.locationId,
      );
  final PlatformDatabase database;
  final PeopleService _people;
  final EmployeeLinks _links;
  final OrganizationService _organization;
  final StockCountRepository _counts;
  final StockRepository _stock;

  Future<T> _run<T>(
    SessionPrincipal principal,
    String location,
    String capability,
    Future<T> Function(TxSession, PlatformActor) action,
  ) async {
    try {
      return await database.runAuthorized(principal, capability, (
        tx,
        actor,
      ) async {
        // Equality precedes every resource read and receipt lookup, including
        // registered same-Company Locations and historical lifecycle exceptions.
        if (location != database.locationId ||
            actor.locationId != database.locationId ||
            actor.companyId != database.companyId) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Execution Location is unavailable.',
          );
        }
        if (!capability.startsWith('stock.counts.self.') &&
            !permissionsForRole(actor.role).contains('stock.levels.manage')) {
          throw const PlatformFailure(
            403,
            'forbidden',
            'Stock management authority required.',
          );
        }
        await _organization.requireConfiguredLocation(tx, location);
        return action(tx, actor);
      });
    } on CountOperationConflict {
      throw const PlatformFailure(
        409,
        'operation_conflict',
        'Operation identity is already bound.',
      );
    } on ServerException catch (e) {
      if (e.code == '23505' && e.constraintName == 'stock_counts_pkey') {
        throw const PlatformFailure(
          409,
          'count_conflict',
          'Count identity already exists.',
        );
      }
      final unavailable =
          e.code?.startsWith('08') == true ||
          {'42501', '55P03', '57014', '57P01', '53300'}.contains(e.code);
      throw PlatformFailure(
        unavailable ? 503 : 500,
        unavailable ? 'database_unavailable' : 'internal_error',
        'Count database operation failed.',
      );
    } on PgException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Count database operation failed.',
      );
    } on SocketException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Count database operation failed.',
      );
    } on TimeoutException {
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Count database operation failed.',
      );
    } on StateError catch (e) {
      // The pinned postgres pool delegates this lifecycle failure to pool.
      // Preserve unrelated programming errors for the ordinary 500 boundary.
      if (e.message != 'request() may not be called on a closed Pool.') rethrow;
      throw const PlatformFailure(
        503,
        'database_unavailable',
        'Count database operation failed.',
      );
    }
  }

  String _id(String id) {
    try {
      return countId(id);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_count',
        'Invalid count identity.',
      );
    }
  }

  StockCountCommandInput _input(String kind, Map<String, dynamic> input) {
    try {
      return StockCountCommandInput.fromJson(kind, input);
    } on FormatException {
      throw const PlatformFailure(
        400,
        'invalid_count',
        'Invalid count command.',
      );
    }
  }

  Future<StockCount> _get(TxSession tx, String id, {String? employeeId}) async {
    final count = await _counts.find(tx, id);
    if (count == null ||
        (employeeId != null && employeeId != count.employeeId)) {
      throw const PlatformFailure(404, 'not_found', 'Count not found.');
    }
    return count;
  }

  Future<void> _eligible(TxSession tx, String employeeId) async {
    EmployeeDto person;
    try {
      person = await _people.get(tx, employeeId);
    } on PlatformFailure catch (e) {
      if (e.status != 404) rethrow;
      throw const PlatformFailure(
        422,
        'assignee_unavailable',
        'Assignee unavailable.',
      );
    }
    final now =
        (await tx.execute('SELECT clock_timestamp()')).single.first as DateTime;
    if (!person.isActive ||
        person.companyId != database.companyId ||
        person.locationId != database.locationId ||
        person.assignedFrom.isAfter(now) ||
        (person.assignedUntil != null &&
            !now.isBefore(person.assignedUntil!)) ||
        !await _links.canRecordStockCount(
          tx,
          employeeId,
          database.locationId,
        )) {
      throw const PlatformFailure(
        422,
        'assignee_unavailable',
        'Assignee unavailable.',
      );
    }
  }

  Future<String> _self(TxSession tx, PlatformActor actor) async {
    final link = await _links.forAccount(tx, actor.id);
    if (link == null ||
        link.companyId != actor.companyId ||
        link.locationId != database.locationId) {
      throw const PlatformFailure(
        404,
        'not_found',
        'Assigned counts unavailable.',
      );
    }
    try {
      await _eligible(tx, link.employeeId);
    } on PlatformFailure catch (e) {
      if (e.code != 'assignee_unavailable') rethrow;
      throw const PlatformFailure(
        404,
        'not_found',
        'Assigned counts unavailable.',
      );
    }
    return link.employeeId;
  }

  Future<Map<String, dynamic>> list(
    SessionPrincipal p,
    String location, {
    bool self = false,
    String? after,
  }) {
    location = _id(location);
    final cursor = _decodeCursor(after, {
      'location': location,
      'self': self,
    }, 'id');
    return _run(
      p,
      location,
      self ? 'stock.counts.self.read' : 'stock.counts.manage',
      (tx, actor) async {
        final employee = self ? await _self(tx, actor) : null;
        final rows = await _counts.page(
          tx,
          after: cursor as String?,
          employeeId: employee,
        );
        final items = rows.take(50).map(_summary).toList();
        return {
          'items': items,
          'nextCursor': rows.length > 50
              ? _cursor({'location': location, 'self': self, 'id': rows[49].id})
              : null,
        };
      },
    );
  }

  Future<Map<String, dynamic>> assignees(SessionPrincipal p, String location) {
    location = _id(location);
    return _run(p, location, 'stock.counts.manage', (tx, actor) async {
      final items = <Map<String, dynamic>>[];
      for (final person in await _people.list(tx)) {
        if (person.locationId != database.locationId) continue;
        try {
          await _eligible(tx, person.id);
          items.add({'id': person.id, 'displayName': person.displayName});
        } on PlatformFailure catch (e) {
          if (e.code != 'assignee_unavailable') rethrow;
        }
      }
      return {'items': items};
    });
  }

  Future<Map<String, dynamic>> get(
    SessionPrincipal p,
    String location,
    String id, {
    bool self = false,
  }) {
    location = _id(location);
    id = _id(id);
    return _run(
      p,
      location,
      self ? 'stock.counts.self.read' : 'stock.counts.manage',
      (tx, actor) async {
        final employee = self ? await _self(tx, actor) : null;
        return _detail(
          tx,
          await _get(tx, id, employeeId: employee),
          self: self,
        );
      },
    );
  }

  Future<Map<String, dynamic>> history(
    SessionPrincipal p,
    String location,
    String id,
    String lineId, {
    bool self = false,
    String? after,
  }) {
    location = _id(location);
    id = _id(id);
    lineId = _id(lineId);
    final scope = {
      'location': location,
      'count': id,
      'line': lineId,
      'self': self,
    };
    final before = _decodeCursor(after, scope, 'number');
    return _run(
      p,
      location,
      self ? 'stock.counts.self.read' : 'stock.counts.manage',
      (tx, actor) async {
        final employee = self ? await _self(tx, actor) : null;
        await _get(tx, id, employeeId: employee);
        if (!(await _counts.lines(tx, id)).any((l) => l.id == lineId)) {
          throw const PlatformFailure(404, 'not_found', 'Line not found.');
        }
        final rows = await _counts.rounds(
          tx,
          id,
          lineId,
          before: before as int?,
        );
        final items = rows
            .take(50)
            .map(
              (r) => _round(
                StockCountRound(countJson(r['round'])),
                r['observation'] == null
                    ? null
                    : StockCountObservation(countJson(r['observation'])),
                r['current'] as bool,
                self: self,
              ),
            )
            .toList();
        return {
          'items': items,
          'nextCursor': rows.length > 50
              ? _cursor({
                  ...scope,
                  'number': countJson(rows[49]['round'])['number'],
                })
              : null,
        };
      },
    );
  }

  Future<Map<String, dynamic>> open(
    SessionPrincipal p,
    String location,
    Map<String, dynamic> input,
  ) {
    location = _id(location);
    final command = _input('open', input);
    final payload = command.toJson();
    final id = payload['id'] as String;
    return _run(p, location, 'stock.counts.manage', (tx, actor) async {
      final replay = await _counts.replay(
        tx,
        command.operationId,
        id,
        actor.id,
        'open',
        payload,
      );
      if (replay != null) return replay.result;
      await _eligible(tx, payload['employeeId'] as String);
      if (payload['precedingCountId'] case final String preceding) {
        if ((await _get(tx, preceding)).status == 'open') {
          throw const PlatformFailure(
            409,
            'count_conflict',
            'Preceding count must be terminal.',
          );
        }
      }
      final levels = <StockLevelDto>[];
      for (final levelId in payload['stockLevelIds'] as List<String>) {
        final level = await _stock.find(tx, levelId);
        if (level == null) {
          throw const PlatformFailure(
            404,
            'not_found',
            'Selected Stock level not found.',
          );
        }
        if (level.version > maxJsonSafeInteger) {
          throw const PlatformFailure(
            409,
            'version_exhausted',
            'Stock version exhausted.',
          );
        }
        levels.add(level);
      }
      await _counts.open(tx, payload, actor.id);
      for (var i = 0; i < levels.length; i++) {
        final lineId = newUuid();
        await _counts.insertLine(tx, id, lineId, i + 1, levels[i]);
        await _counts.appendRound(
          tx,
          id,
          lineId,
          newUuid(),
          1,
          levels[i],
          actor.id,
          command.operationId,
          null,
        );
      }
      final count = await _get(tx, id);
      final result = await _detail(tx, count);
      await _finish(tx, actor, count, command, payload, result);
      return result;
    });
  }

  Future<Map<String, dynamic>> observe(
    SessionPrincipal p,
    String id,
    String lineId,
    Map<String, dynamic> input,
  ) {
    id = _id(id);
    lineId = _id(lineId);
    final command = _input('observation', input);
    final payload = {...command.toJson(), 'lineId': lineId};
    return _run(p, database.locationId, 'stock.counts.self.record', (
      tx,
      actor,
    ) async {
      final employee = await _self(tx, actor);
      final count = await _get(tx, id, employeeId: employee);
      final replay = await _counts.replay(
        tx,
        command.operationId,
        id,
        actor.id,
        command.kind,
        payload,
      );
      if (replay != null) return replay.result;
      count.requireOpen(payload['expectedVersion'] as int);
      final line = (await _counts.lines(
        tx,
        id,
      )).where((l) => l.id == lineId).firstOrNull;
      if (line == null) {
        throw const PlatformFailure(404, 'not_found', 'Line not found.');
      }
      if (line.round.id != payload['roundId']) {
        throw const PlatformFailure(
          409,
          'round_conflict',
          'Round was superseded.',
        );
      }
      if (line.observation != null) {
        throw const PlatformFailure(
          409,
          'observation_exists',
          'Round already observed.',
        );
      }
      final observationId = newUuid();
      await _counts.observe(tx, count, line, payload, actor.id, observationId);
      await _counts.advance(tx, count);
      final updated = await _get(tx, id);
      final result = await _detail(tx, updated, self: true);
      await _finish(
        tx,
        actor,
        updated,
        command,
        payload,
        result,
        extra: {
          'lineId': lineId,
          'roundId': line.round.id,
          'observationId': observationId,
        },
      );
      return result;
    });
  }

  Future<Map<String, dynamic>> command(
    SessionPrincipal p,
    String location,
    String id,
    String kind,
    Map<String, dynamic> input,
  ) {
    location = _id(location);
    id = _id(id);
    final command = _input(kind, input);
    final payload = command.toJson();
    if (!{'recount', 'approve', 'cancel'}.contains(kind)) {
      throw const PlatformFailure(
        400,
        'invalid_count',
        'Invalid manager command.',
      );
    }
    return _run(
      p,
      location,
      kind == 'approve' ? 'stock.counts.approve' : 'stock.counts.manage',
      (tx, actor) async {
        final count = await _get(tx, id);
        final replay = await _counts.replay(
          tx,
          command.operationId,
          id,
          actor.id,
          kind,
          payload,
        );
        if (replay != null) return replay.result;
        count.requireOpen(payload['expectedVersion'] as int);
        final lines = await _counts.lines(tx, id);
        if (kind == 'recount') {
          await _eligible(tx, count.employeeId);
          final selected = (payload['lineIds'] as List<String>).toSet();
          if (!selected.every((id) => lines.any((l) => l.id == id))) {
            throw const PlatformFailure(
              404,
              'not_found',
              'Selected line not found.',
            );
          }
          for (final line in lines.where((l) => selected.contains(l.id))) {
            if (line.round.number >= maxJsonSafeInteger) {
              throw const PlatformFailure(
                409,
                'version_exhausted',
                'Round number exhausted.',
              );
            }
            final level = await _stock.find(
              tx,
              line.identity['stock_level_id'] as String,
            );
            if (level == null ||
                level.stockUnit != line.identity['stock_unit']) {
              throw const PlatformFailure(
                409,
                'count_stale',
                'Stock unit unavailable.',
              );
            }
            await _counts.appendRound(
              tx,
              id,
              line.id,
              newUuid(),
              line.round.number + 1,
              level,
              actor.id,
              command.operationId,
              payload['reason'] as String,
            );
          }
          await _counts.advance(tx, count);
        } else if (kind == 'approve') {
          // Validate EVERY line before beginning effects. The transaction also
          // rolls back movements, outcomes, audit and receipts on later failures.
          for (final line in lines) {
            line.requireApproval(actor.id);
          }
          for (final line in lines) {
            String? movementId;
            if (line.discrepancy != 0) {
              movementId = newUuid();
              await _stock.updateQuantity(
                tx,
                id: line.identity['stock_level_id'] as String,
                expectedVersion: line.round.version,
                quantityScaled: line.observation!.quantity,
              );
              await _stock.insertMovement(
                tx,
                id: movementId,
                stockLevelId: line.identity['stock_level_id'] as String,
                articleId: line.identity['article_id'] as String,
                kind: 'count_correction',
                deltaScaled: line.discrepancy!,
                balanceAfterScaled: line.observation!.quantity,
                balanceVersion: line.round.version + 1,
                recordedBy: actor.id,
                note: null,
                countId: id,
                countLineId: line.id,
                countObservationId: line.observation!.id,
              );
              await database.audit(
                tx,
                actor,
                'stock.level.count_corrected',
                'stock_level',
                line.identity['stock_level_id'] as String,
                locationId: location,
                changes: {
                  'countId': id,
                  'lineId': line.id,
                  'observationId': line.observation!.id,
                  'movementId': movementId,
                  'oldVersion': line.round.version,
                  'version': line.round.version + 1,
                },
              );
            }
            await _counts.outcome(tx, line, movementId);
          }
          await _counts.advance(tx, count, status: 'approved', actor: actor.id);
        } else {
          await _counts.advance(
            tx,
            count,
            status: 'cancelled',
            actor: actor.id,
            reason: payload['reason'] as String,
          );
        }
        final updated = await _get(tx, id);
        final result = await _detail(tx, updated);
        await _finish(tx, actor, updated, command, payload, result);
        return result;
      },
    );
  }

  Future<void> _finish(
    TxSession tx,
    PlatformActor actor,
    StockCount count,
    StockCountCommandInput command,
    Map<String, dynamic> payload,
    Map<String, dynamic> result, {
    Map<String, dynamic> extra = const {},
  }) async {
    final action = switch (command.kind) {
      'open' => 'opened',
      'observation' => 'observed',
      'recount' => 'recount_requested',
      'approve' => 'approved',
      _ => 'cancelled',
    };
    await database.audit(
      tx,
      actor,
      'stock.count.$action',
      'stock_count',
      count.id,
      locationId: database.locationId,
      changes: {
        'countId': count.id,
        'employeeId': count.employeeId,
        'operationId': command.operationId,
        'version': count.version,
        'status': count.status,
        ...extra,
      },
    );
    await _counts.receipt(
      tx,
      count.id,
      command.operationId,
      actor.id,
      command.kind,
      payload,
      result,
    );
  }

  Map<String, dynamic> _summary(StockCount c) => {
    'id': c.id,
    'locationId': c.evidence['location_id'],
    'employeeId': c.employeeId,
    'purpose': c.evidence['purpose'],
    'status': c.status,
    'version': c.version,
    'openedAt': _time(c.evidence['opened_at']),
  };
  Future<Map<String, dynamic>> _detail(
    TxSession tx,
    StockCount c, {
    bool self = false,
  }) async => {
    ..._summary(c),
    if (!self) 'createdBy': c.evidence['created_by'],
    if (!self) 'precedingCountId': c.evidence['preceding_count_id'],
    if (!self)
      'approval': c.status == 'approved'
          ? {
              'approvedBy': c.evidence['approved_by'],
              'approvedAt': _time(c.evidence['approved_at']),
            }
          : null,
    if (!self)
      'cancellation': c.status == 'cancelled'
          ? {
              'cancelledBy': c.evidence['cancelled_by'],
              'cancelledAt': _time(c.evidence['cancelled_at']),
              'reason': c.evidence['cancellation_reason'],
            }
          : null,
    'lines': (await _counts.lines(tx, c.id))
        .map(
          (l) => {
            'id': l.id,
            'articleId': l.identity['article_id'],
            'position': l.identity['position'],
            'sku': l.identity['sku'],
            'name': l.identity['article_name'],
            'barcode': l.identity['barcode'],
            'stockUnit': l.identity['stock_unit'],
            'round': _round(l.round, l.observation, true, self: self),
            if (!self) 'stockLevelId': l.identity['stock_level_id'],
            if (!self)
              'currentStock': {
                'quantity': stockQuantityText(
                  l.currentStock['quantity_scaled'] as int,
                ),
                'version': l.currentStock['version'],
                'stockUnit': l.currentStock['stock_unit'],
                'updatedAt': _time(l.currentStock['updated_at']),
              },
            if (!self) 'stale': c.status == 'open' && l.stale,
            if (!self)
              'discrepancy': l.discrepancy == null
                  ? null
                  : stockDeltaText(l.discrepancy!),
            if (!self)
              'outcome': l.identity['approved_observation_id'] == null
                  ? null
                  : {
                      'observationId': l.identity['approved_observation_id'],
                      'discrepancy': stockDeltaText(
                        l.identity['discrepancy_scaled'] as int,
                      ),
                      'checkedStockVersion':
                          l.identity['checked_stock_version'],
                      'movementId': l.identity['movement_id'],
                    },
          },
        )
        .toList(),
  };
  Map<String, dynamic> _round(
    StockCountRound r,
    StockCountObservation? o,
    bool current, {
    required bool self,
  }) => {
    'id': r.id,
    'number': r.number,
    'current': current,
    'observation': o == null
        ? null
        : {
            'id': o.id,
            'quantity': stockQuantityText(o.quantity),
            'recordedAt': _time(o.evidence['recorded_at']),
            'note': o.evidence['note'],
            if (!self) 'recordedBy': o.recordedBy,
          },
    if (!self) 'baselineQuantity': stockQuantityText(r.quantity),
    if (!self) 'baselineVersion': r.version,
    if (!self) 'stockUnit': r.evidence['stock_unit'],
    if (!self) 'capturedAt': _time(r.evidence['captured_at']),
    if (!self) 'provenance': r.evidence['provenance'],
    if (!self) 'requestedBy': r.evidence['requested_by'],
    if (!self) 'reason': r.evidence['reason'],
    if (!self)
      'discrepancy': o == null ? null : stockDeltaText(o.quantity - r.quantity),
  };
  String _time(Object? v) =>
      DateTime.parse(v as String).toUtc().toIso8601String();
  String _cursor(Map<String, dynamic> v) =>
      base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', '');
  Object? _decodeCursor(String? value, Map<String, dynamic> scope, String key) {
    if (value == null) return null;
    try {
      if (value.length > 512) throw const FormatException();
      final c =
          jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(value))))
              as Map<String, dynamic>;
      if (c.length != scope.length + 1 ||
          !scope.entries.every((e) => c[e.key] == e.value) ||
          !c.containsKey(key)) {
        throw const FormatException();
      }
      final member = c[key];
      if (key == 'id') return countId(member);
      if (member is! int || member < 1 || member > maxJsonSafeInteger) {
        throw const FormatException();
      }
      return member;
    } catch (_) {
      throw const PlatformFailure(
        400,
        'invalid_cursor',
        'Invalid scoped cursor.',
      );
    }
  }
}
