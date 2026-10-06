// Stock-owned evidence seeded only through supported writers in isolated runs.
import 'dart:convert';

import 'package:storeos_api_contracts/api_contracts.dart';
import 'package:storeos_server/src/infrastructure/auth_store.dart';
import 'package:storeos_server/src/platform/platform_database.dart';
import 'package:storeos_server/src/stock/stock_count_service.dart';

typedef CountRequest =
    Future<Map<String, dynamic>> Function(
      String method,
      String route,
      Map<String, dynamic>? body,
      int status,
    );

Future<Map<String, String>> seedStockCounts(
  CountRequest manager,
  CountRequest worker,
  String location,
  String employee,
) async {
  const prefix = '/api/v1/platform';
  final root = '$prefix/locations/$location/stock-counts';
  final levels = <String>[];
  for (var i = 0; i < 2; i++) {
    final article = newUuid();
    await manager('POST', '$prefix/articles', {
      'id': article,
      'sku': 'COUNT-ACCEPT-$i',
      'barcode': null,
      'name': i == 0 ? 'Count flour <literal>' : 'Count pieces',
      'description': null,
      'unit': i == 0 ? 'kg' : 'Stk',
    }, 201);
    await manager('POST', '$prefix/locations/$location/assortment', {
      'id': newUuid(),
      'articleId': article,
    }, 201);
    final level = newUuid();
    await manager('POST', '$prefix/locations/$location/stock', {
      'id': level,
      'articleId': article,
      'quantity': i == 0 ? '10' : '5',
      'note': null,
    }, 201);
    levels.add(level);
  }
  Future<Map<String, dynamic>> open({String? preceding}) =>
      manager('POST', root, {
        'id': newUuid(),
        'operationId': newUuid(),
        'employeeId': employee,
        'stockLevelIds': levels,
        'purpose': 'Durable physical count <literal>',
        'precedingCountId': preceding,
      }, 201);
  List<dynamic> lines(Map<String, dynamic> c) => c['lines'] as List;
  Map<String, dynamic>? retainedObservation;
  String? retainedLine;
  Future<Map<String, dynamic>> observe(
    Map<String, dynamic> c,
    int index,
    String q,
  ) {
    final line = lines(c)[index];
    final payload = {
      'operationId': newUuid(),
      'expectedVersion': c['version'],
      'roundId': line['round']['id'],
      'quantity': q,
      'note': 'Physical evidence',
    };
    retainedObservation ??= payload;
    retainedLine ??= line['id'] as String;
    return worker(
      'POST',
      '$prefix/me/stock-counts/${c['id']}/lines/${line['id']}/observations',
      payload,
      200,
    );
  }

  var count = await open();
  final countId = count['id'] as String;
  count = await observe(count, 0, '9');
  count = await observe(count, 1, '5');
  await manager(
    'POST',
    '$prefix/locations/$location/stock/${levels[0]}/adjust',
    {
      'movementId': newUuid(),
      'expectedVersion': 1,
      'quantity': '12',
      'note': 'Count stays writable',
    },
    200,
  );
  final stale = await manager('POST', '$root/$countId/approve', {
    'operationId': newUuid(),
    'expectedVersion': count['version'],
  }, 409);
  if (stale['code'] != 'count_stale') throw StateError('Stale count accepted.');
  count = await manager('POST', '$root/$countId/recount', {
    'operationId': newUuid(),
    'expectedVersion': count['version'],
    'lineIds': [lines(count)[0]['id']],
    'reason': 'Fresh physical recount',
  }, 200);
  count = await observe(count, 0, '11');
  final approve = {
    'operationId': newUuid(),
    'expectedVersion': count['version'],
  };
  final approved = await manager(
    'POST',
    '$root/$countId/approve',
    approve,
    200,
  );
  if (lines(approved)[0]['outcome']['discrepancy'] != '-1' ||
      lines(approved)[0]['outcome']['movementId'] == null ||
      lines(approved)[1]['outcome']['discrepancy'] != '0' ||
      lines(approved)[1]['outcome']['movementId'] != null ||
      lines(approved)[1]['currentStock']['version'] != 1) {
    throw StateError('Mixed count outcome differs.');
  }
  var cancelled = await open();
  cancelled = await observe(cancelled, 0, '11');
  cancelled = await manager('POST', '$root/${cancelled['id']}/cancel', {
    'operationId': newUuid(),
    'expectedVersion': cancelled['version'],
    'reason': 'Linked replacement required',
  }, 200);
  final replacement = await open(preceding: cancelled['id'] as String);
  if (lines(replacement)[0]['round']['baselineQuantity'] != '11') {
    throw StateError('Replacement lacks fresh baseline.');
  }
  return {
    'approvedCountId': countId,
    'cancelledCountId': cancelled['id'] as String,
    'replacementCountId': replacement['id'] as String,
    'countApprovePayload': jsonEncode(approve),
    'countApproveResult': jsonEncode(approved),
    'countObservationPayload': jsonEncode(retainedObservation),
    'countObservationLineId': retainedLine!,
  };
}

Future<void> verifyRestoredStockCounts(
  PlatformDatabase db,
  SessionPrincipal manager,
  SessionPrincipal worker,
  Map<String, dynamic> evidence, {
  SessionPrincipal? otherWorker,
}) async {
  final service = StockCountService(db);
  final id = evidence['approvedCountId'] as String;
  final result = await service.get(manager, db.locationId, id);
  if (result['status'] != 'approved' || (result['lines'] as List).length != 2) {
    throw StateError('Restored count terminal evidence differs.');
  }
  final blind = await service.get(worker, db.locationId, id, self: true);
  EmployeeCountDto.fromJson(blind);
  if (otherWorker != null) {
    // A successful own list proves B has current eligible Employee context;
    // denials must come from foreign Count ownership, not a missing link.
    final own = await service.list(otherWorker, db.locationId, self: true);
    if ((own['items'] as List).any((c) => c['id'] == id)) {
      throw StateError('Restored foreign Count appeared in own list.');
    }
    Future<void> denied(Future<Map<String, dynamic>> request) async {
      try {
        await request;
      } on PlatformFailure catch (e) {
        if (e.status == 404 && e.code == 'not_found') return;
        rethrow;
      }
      throw StateError('Restored other Employee accessed foreign Count.');
    }

    await denied(service.get(otherWorker, db.locationId, id, self: true));
    await denied(
      service.history(
        otherWorker,
        db.locationId,
        id,
        evidence['countObservationLineId'] as String,
        self: true,
      ),
    );
    await denied(
      service.observe(
        otherWorker,
        id,
        evidence['countObservationLineId'] as String,
        jsonDecode(evidence['countObservationPayload'] as String)
            as Map<String, dynamic>,
      ),
    );
  }
  for (final line in blind['lines'] as List) {
    final history = await service.history(
      worker,
      db.locationId,
      id,
      line['id'] as String,
      self: true,
    );
    for (final round in history['items'] as List) {
      EmployeeCountRoundDto.fromJson(round as Map<String, dynamic>);
    }
  }
  final replay = await service.command(
    manager,
    db.locationId,
    id,
    'approve',
    jsonDecode(evidence['countApprovePayload'] as String)
        as Map<String, dynamic>,
  );
  // PostgreSQL JSONB changes object key order; compare values recursively.
  Object? sorted(Object? v) => v is Map
      ? {
          for (final key in (v.keys.cast<String>().toList()..sort()))
            key: sorted(v[key]),
        }
      : v is List
      ? v.map(sorted).toList()
      : v;
  if (jsonEncode(sorted(replay)) !=
      jsonEncode(
        sorted(jsonDecode(evidence['countApproveResult'] as String)),
      )) {
    throw StateError('Restored count replay lost original evidence.');
  }
  final replacement = await service.get(
    manager,
    db.locationId,
    evidence['replacementCountId'] as String,
  );
  if (replacement['precedingCountId'] != evidence['cancelledCountId'] ||
      replacement['status'] != 'open') {
    throw StateError('Restored follow-up differs.');
  }
}
