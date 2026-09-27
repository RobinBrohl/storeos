import 'dart:convert';

import '../infrastructure/auth_store.dart';
import 'event_repository.dart';
import 'platform_database.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

class EventService {
  EventService(this.database)
    : _repository = EventRepository(
        pool: database.pool,
        schema: database.schema,
        companyId: database.companyId,
      );

  final PlatformDatabase database;
  final EventRepository _repository;

  Future<Map<String, dynamic>> list(
    SessionPrincipal principal, {
    String? after,
  }) {
    final cursor = decodeEventCursor(after);
    return database.runAuthorized(principal, 'events.read', (tx, actor) async {
      final rows = await _repository.page(
        tx,
        companyId: actor.companyId,
        before: cursor,
      );
      final page = rows.take(50).toList();
      final last = rows.length > 50 ? page.last : null;
      return {
        'items': page.map((event) => event.toJson()).toList(),
        'nextCursor': last == null
            ? null
            : encodeEventCursor(last.recordedAt, last.id),
      };
    });
  }

  Future<Map<String, dynamic>> replay(
    SessionPrincipal principal,
    String eventId,
  ) {
    if (!_uuidPattern.hasMatch(eventId)) {
      throw const PlatformFailure(400, 'invalid_id', 'Invalid event id.');
    }
    return database.runAuthorized(principal, 'events.write', (tx, actor) async {
      final state = await _repository.lockReplay(tx, eventId, actor.companyId);
      if (state == null) {
        throw const PlatformFailure(404, 'not_found', 'Event not found.');
      }
      if (state.status != 'dead_letter') {
        throw const PlatformFailure(
          409,
          'invalid_state',
          'Only failed events can be replayed.',
        );
      }
      await _repository.requeue(tx, eventId);
      await database.audit(
        tx,
        actor,
        'event.replayed',
        'event',
        eventId,
        locationId: state.locationId,
        changes: const {'status': 'pending'},
      );
      return {'eventId': eventId, 'status': 'pending'};
    });
  }
}

String encodeEventCursor(DateTime time, String id) => base64UrlEncode(
  utf8.encode('${time.toUtc().toIso8601String()}|$id'),
).replaceAll('=', '');

EventCursor? decodeEventCursor(String? after) {
  if (after == null || after.isEmpty) return null;
  if (after.length > 192 || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(after)) {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
  try {
    final decoded = utf8.decode(base64Url.decode(base64Url.normalize(after)));
    final parts = decoded.split('|');
    if (parts.length != 2 || !_uuidPattern.hasMatch(parts[1])) {
      throw const FormatException();
    }
    final time = DateTime.tryParse(parts[0]);
    if (time == null || !time.isUtc) throw const FormatException();
    return EventCursor(time, parts[1]);
  } on FormatException {
    throw const PlatformFailure(400, 'invalid_cursor', 'Invalid cursor.');
  }
}
