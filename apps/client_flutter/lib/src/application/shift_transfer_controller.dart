import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';
import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum TransferOutcome { confirmed, rejected, uncertain, fenced, busy }

class PendingTransferCommand {
  PendingTransferCommand(
    this.identity,
    this.route,
    ShiftTransferCommandInput input,
  ) : kind = input.kind,
      body = Map.unmodifiable(input.toJson());
  final Object identity;
  final String route, kind;
  final Map<String, dynamic> body;
}

class ShiftTransferController extends ChangeNotifier {
  ShiftTransferController(
    this.session,
    this.platform,
    this.api, {
    this.self = true,
    String Function()? idFactory,
  }) : _newId = idFactory ?? _uuid {
    session.addListener(_sessionChanged);
    _sessionChanged();
  }
  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  final String Function() _newId;
  Object? _identity;
  Object? get sessionIdentity => _identity;
  bool _disposed = false, busy = false;
  String? error, refreshWarning, nextCursor, recipientCursor, status, direction;
  List<ShiftTransferDto> items = [];
  List<Map<String, dynamic>> recipients = [];
  ShiftTransferDto? detail;
  ShiftDto? source;
  String? sourceName;
  List<Map<String, dynamic>> sourceTasks = [];
  Map<String, dynamic>? recipient, lastConfirmed;
  String? confirmedId;
  PendingTransferCommand? pending;
  bool get locked => busy || pending != null;
  bool get canRead => platform.allows(
    self ? 'workforce.transfers.self.read' : 'workforce.transfers.manage',
  );
  String get root => self
      ? '/me/shift-transfers'
      : '/locations/${session.user!.locationId}/shift-transfers';
  bool _current(Object? identity) =>
      !_disposed &&
      identity != null &&
      identical(identity, _identity) &&
      identical(identity, session.sessionIdentity) &&
      session.isAuthenticated;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _sessionChanged() {
    if (identical(_identity, session.sessionIdentity)) return;
    _identity = session.sessionIdentity;
    busy = false;
    error = null;
    refreshWarning = null;
    nextCursor = null;
    recipientCursor = null;
    status = null;
    direction = null;
    items = [];
    recipients = [];
    detail = null;
    source = null;
    sourceName = null;
    sourceTasks = [];
    recipient = null;
    lastConfirmed = null;
    confirmedId = null;
    pending = null;
    _notify();
  }

  Future<Map<String, dynamic>> _get(
    Object identity,
    String route, {
    Map<String, String>? query,
  }) async {
    if (!_current(identity)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    final result = await session.authorized((token) {
      if (!_current(identity)) {
        throw const StoreApiException('stale_session', 'Session changed.');
      }
      return api.get(token, route, query: query);
    });
    if (!_current(identity)) {
      throw const StoreApiException('stale_session', 'Session changed.');
    }
    return result;
  }

  Future<void> _read(Future<void> Function(Object) work) async {
    if (locked || !canRead || !_current(_identity)) return;
    final identity = _identity!;
    busy = true;
    error = null;
    _notify();
    try {
      await work(identity);
    } catch (e) {
      if (_current(identity)) {
        error = e is StoreApiException
            ? '${e.code}: ${e.message}'
            : 'Could not load transfer evidence.';
      }
    } finally {
      if (_current(identity)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> load({bool more = false}) => _read((identity) async {
    if (!more) {
      items = [];
      nextCursor = null;
    }
    final page = await _get(
      identity,
      root,
      query: {
        'status': ?status,
        'direction': ?direction,
        if (more && nextCursor != null) 'after': nextCursor!,
      },
    );
    items = [
      if (more) ...items,
      ...(page['items'] as List).map(
        (j) => ShiftTransferDto.fromJson(Map<String, dynamic>.from(j as Map)),
      ),
    ];
    nextCursor = page['nextCursor'] as String?;
  });
  Future<void> filter({String? state, String? way}) async {
    if (locked) return;
    status = state;
    direction = way;
    await load();
  }

  Future<void> select(String id) => _read((identity) async {
    detail = null;
    source = null;
    sourceName = null;
    recipients = [];
    sourceTasks = [];
    recipient = null;
    if (id != confirmedId) {
      lastConfirmed = null;
      confirmedId = null;
    }
    detail = ShiftTransferDto.fromJson(await _get(identity, '$root/$id'));
    refreshWarning = null;
  });
  Future<void> chooseSource(ShiftDto shift, {bool more = false}) => _read((
    identity,
  ) async {
    if (!self || !platform.allows('workforce.transfers.self.request')) return;
    if (!more) {
      source = null;
      sourceName = null;
      detail = null;
      recipient = null;
      recipients = [];
      sourceTasks = [];
      recipientCursor = null;
      lastConfirmed = null;
      confirmedId = null;
    }
    final page = await _get(
      identity,
      '/employee-home/shifts/${shift.id}/transfer-recipients',
      query: {if (more && recipientCursor != null) 'after': recipientCursor!},
    );
    source = ShiftDto.fromJson(Map<String, dynamic>.from(page['shift'] as Map));
    sourceName = page['sourceName'] as String;
    sourceTasks = (page['tasks'] as List)
        .map((j) => Map<String, dynamic>.from(j as Map))
        .toList();
    recipients = [
      if (more) ...recipients,
      ...(page['items'] as List).map(
        (j) => Map<String, dynamic>.from(j as Map),
      ),
    ];
    recipientCursor = page['nextCursor'] as String?;
  });
  void chooseRecipient(Map<String, dynamic>? value) {
    if (locked) return;
    recipient = value;
    _notify();
  }

  void closeDetail() {
    if (locked) return;
    detail = null;
    source = null;
    sourceName = null;
    recipients = [];
    sourceTasks = [];
    recipient = null;
    lastConfirmed = null;
    confirmedId = null;
    refreshWarning = null;
    _notify();
  }

  String get participantRole =>
      detail?.json['participantRole'] as String? ?? '';
  bool can(String action) {
    if (locked || detail == null) return false;
    final active = {'proposed', 'accepted'}.contains(detail!.status),
        actionable = detail!.json['actionable'] == true;
    if (!self) {
      return platform.allows('workforce.transfers.manage') &&
          (action == 'reject'
              ? active
              : action == 'approve' &&
                    platform.allows('workforce.shifts.manage') &&
                    platform.allows('tasks.instances.read') &&
                    detail!.status == 'accepted' &&
                    actionable &&
                    session.user!.id != detail!.json['proposedBy'] &&
                    session.user!.id != detail!.json['acceptedBy']);
    }
    if (action == 'withdraw') {
      return active &&
          (participantRole == 'source'
              ? platform.allows('workforce.transfers.self.request')
              : participantRole == 'recipient' &&
                    detail!.status == 'accepted' &&
                    platform.allows('workforce.transfers.self.respond'));
    }
    return participantRole == 'recipient' &&
        platform.allows('workforce.transfers.self.respond') &&
        detail!.status == 'proposed' &&
        (action == 'decline' || action == 'accept' && actionable);
  }

  Future<TransferOutcome> propose() {
    if (source == null ||
        recipient == null ||
        !platform.allows('workforce.transfers.self.request')) {
      return Future.value(TransferOutcome.rejected);
    }
    return _submit('propose', root, {
      'operationId': _newId(),
      'requestId': _newId(),
      'sourceShiftId': source!.id,
      'expectedSourceVersion': source!.version,
      'recipientEmployeeId': recipient!['employeeId'],
    });
  }

  Future<TransferOutcome> act(String action, {String? reason}) {
    if (!can(action)) return Future.value(TransferOutcome.rejected);
    final kind = !self
        ? 'manager_$action'
        : action == 'withdraw'
        ? '${participantRole}_withdraw'
        : action;
    return _submit(kind, '$root/${detail!.id}/$action', {
      'operationId': _newId(),
      'expectedVersion': detail!.version,
      'reason': ?reason,
    });
  }

  Future<TransferOutcome> _submit(
    String kind,
    String route,
    Map<String, dynamic> body,
  ) async {
    if (locked || !_current(_identity)) return TransferOutcome.busy;
    try {
      pending = PendingTransferCommand(
        _identity!,
        route,
        ShiftTransferCommandInput.fromJson(kind, body),
      );
    } on TransferInputException catch (e) {
      error = e.message;
      _notify();
      return TransferOutcome.rejected;
    }
    return retry();
  }

  Future<TransferOutcome> retry() async {
    final c = pending;
    if (c == null || busy) return TransferOutcome.busy;
    if (!_current(c.identity)) return TransferOutcome.fenced;
    busy = true;
    error = null;
    _notify();
    try {
      final result = await session.authorized((token) {
        if (!_current(c.identity)) {
          throw const StoreApiException('stale_session', 'Session changed.');
        }
        return api.post(token, c.route, c.body);
      });
      if (!_current(c.identity)) return TransferOutcome.fenced;
      final confirmed = ShiftTransferDto.fromJson(
        Map<String, dynamic>.from(result['request'] as Map),
      );
      lastConfirmed = Map.unmodifiable(result);
      confirmedId = confirmed.id;
      pending = null;
      detail = null;
      source = null;
      sourceName = null;
      sourceTasks = [];
      recipients = [];
      recipient = null;
      items = items.where((r) => r.id != confirmedId).toList();
      refreshWarning = null;
      _notify();
      try {
        detail = ShiftTransferDto.fromJson(
          await _get(c.identity, '$root/$confirmedId'),
        );
      } catch (_) {
        if (_current(c.identity)) {
          refreshWarning =
              'Command confirmed. Current transfer detail is unavailable. Reload before further actions.';
        }
      }
      return _current(c.identity)
          ? TransferOutcome.confirmed
          : TransferOutcome.fenced;
    } on StoreApiException catch (e) {
      if (!_current(c.identity)) return TransferOutcome.fenced;
      if ({400, 401, 403, 404, 409, 413, 415, 422}.contains(e.statusCode)) {
        pending = null;
        if ({401, 403, 404, 409, 422}.contains(e.statusCode)) {
          detail = null;
          source = null;
          sourceName = null;
          recipient = null;
          refreshWarning =
              'Reload current transfer evidence before another action.';
        }
        error = '${e.code}: ${e.message}';
        return TransferOutcome.rejected;
      }
      error = 'Outcome unconfirmed. Retry the exact same command.';
      return TransferOutcome.uncertain;
    } catch (_) {
      if (!_current(c.identity)) return TransferOutcome.fenced;
      error = 'Outcome unconfirmed. Retry the exact same command.';
      return TransferOutcome.uncertain;
    } finally {
      if (_current(c.identity)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    session.removeListener(_sessionChanged);
    super.dispose();
  }
}

String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
