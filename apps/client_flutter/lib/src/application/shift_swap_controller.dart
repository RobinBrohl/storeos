import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:storeos_api_contracts/api_contracts.dart';

import '../data/platform_api.dart';
import '../data/store_api.dart';
import 'platform_controller.dart';
import 'session_controller.dart';

enum SwapOutcome {
  confirmed,
  rejected,
  uncertain,
  reconciliationRequired,
  fenced,
  busy,
}

enum SwapSubmission { submitting, uncertain, reconciliationRequired }

/// Memory-only authority basis. No bearer token or client authorization identity
/// is retained in a command payload.
class _SwapBinding {
  _SwapBinding(
    this.session,
    this.context,
    this.accountId,
    this.companyId,
    this.locationId,
  );
  final Object session, context;
  final String accountId, companyId, locationId;
}

/// An intended command is immutable, including its original evidence and state.
/// State transitions replace this object; retry cannot change route, IDs or body.
class PendingSwapCommand {
  PendingSwapCommand._(
    this._binding,
    this.route,
    ShiftSwapCommandInput input,
    this.requestId,
    Map<String, dynamic> evidence,
    this.state,
  ) : kind = input.kind,
      operationId = input.operationId,
      expectedVersion = input.expectedVersion,
      canonical = input.canonical,
      body = _freeze(input.toJson()) as Map<String, dynamic>,
      evidence = _freeze(evidence) as Map<String, dynamic>;

  final _SwapBinding _binding;
  Object get sessionIdentity => _binding.session;
  Object get contextIdentity => _binding.context;
  String get accountId => _binding.accountId;
  String get companyId => _binding.companyId;
  String get locationId => _binding.locationId;
  final String route, kind, operationId, requestId, canonical;
  final int expectedVersion;
  final Map<String, dynamic> body, evidence;
  final SwapSubmission state;

  PendingSwapCommand _withState(SwapSubmission value) => PendingSwapCommand._(
    _binding,
    route,
    ShiftSwapCommandInput.fromJson(kind, body),
    requestId,
    evidence,
    value,
  );
}

class ShiftSwapController extends ChangeNotifier {
  ShiftSwapController(
    this.session,
    this.platform,
    this.api, {
    this.self = true,
    String Function()? idFactory,
  }) : _newId = idFactory ?? _uuid {
    session.addListener(_contextChanged);
    platform.addListener(_contextChanged);
    _contextChanged();
  }

  final SessionController session;
  final PlatformController platform;
  final PlatformApi api;
  final bool self;
  final String Function() _newId;
  _SwapBinding? _binding;
  bool _disposed = false, _reading = false, _submitting = false;
  int _readGeneration = 0;
  int _submissionGeneration = 0;
  String? _error, _refreshWarning, _status, _direction;
  String? _nextCursor, _historyCursor, _colleagueCursor, _counterpartCursor;
  String? _historyId;
  List<ShiftSwapDto> _items = const [];
  List<ShiftSwapCommandResult> _history = const [];
  List<Map<String, dynamic>> _colleagues = const [], _counterparts = const [];
  ShiftSwapDetailDto? _detail;
  ShiftDto? _source;
  Map<String, dynamic>? _colleague, _counterpart;
  ShiftSwapLegDto? _selectedCounterpart;
  PendingSwapCommand? _pending;
  ShiftSwapCommandResult? _lastConfirmed;

  Object? get sessionIdentity => _binding?.session;
  bool get busy => _reading || _submitting;
  bool get locked => busy || _pending != null;
  String? get error => _error;
  String? get refreshWarning => _refreshWarning;
  String? get status => _status;
  String? get direction => _direction;
  String? get nextCursor => _nextCursor;
  String? get historyCursor => _historyCursor;
  String? get colleagueCursor => _colleagueCursor;
  String? get counterpartCursor => _counterpartCursor;
  List<ShiftSwapDto> get items => _items;
  List<ShiftSwapCommandResult> get history => _history;
  List<Map<String, dynamic>> get colleagues => _colleagues;
  List<Map<String, dynamic>> get counterparts => _counterparts;
  ShiftSwapDetailDto? get detail => _detail;
  ShiftDto? get source => _source;
  Map<String, dynamic>? get colleague => _colleague;
  Map<String, dynamic>? get counterpart => _counterpart;
  ShiftSwapLegDto? get selectedCounterpart => _selectedCounterpart;
  PendingSwapCommand? get pending => _pending;
  ShiftSwapCommandResult? get lastConfirmed => _lastConfirmed;
  bool get canRead =>
      _current(_binding) &&
      platform.allows(
        self ? 'workforce.swaps.self.read' : 'workforce.swaps.manage',
      );
  String _root(_SwapBinding b) =>
      self ? '/me/shift-swaps' : '/locations/${b.locationId}/shift-swaps';

  bool _current(_SwapBinding? b) =>
      !_disposed &&
      b != null &&
      identical(b, _binding) &&
      session.isAuthenticated &&
      identical(b.session, session.sessionIdentity) &&
      identical(b.session, platform.contextSessionIdentity) &&
      identical(b.context, platform.contextIdentity) &&
      session.user?.id == b.accountId &&
      session.user?.companyId == b.companyId &&
      session.user?.locationId == b.locationId &&
      platform.context?.companyId == b.companyId &&
      platform.context?.locationId == b.locationId;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearSelection() {
    _detail = null;
    _source = null;
    _colleague = null;
    _colleagues = const [];
    _colleagueCursor = null;
    _counterpart = null;
    _selectedCounterpart = null;
    _counterparts = const [];
    _counterpartCursor = null;
    _history = const [];
    _historyId = null;
    _historyCursor = null;
  }

  void _contextChanged() {
    if (_disposed || _current(_binding)) return;
    final user = session.user, context = platform.context;
    final binding =
        user != null &&
            context != null &&
            identical(
              session.sessionIdentity,
              platform.contextSessionIdentity,
            ) &&
            context.userId == user.id &&
            context.companyId == user.companyId &&
            context.locationId == user.locationId
        ? _SwapBinding(
            session.sessionIdentity!,
            platform.contextIdentity,
            user.id,
            user.companyId,
            user.locationId,
          )
        : null;
    if (_binding == null && binding == null) return;
    _binding = binding;
    _readGeneration++;
    _submissionGeneration++;
    _reading = _submitting = false;
    _error = _refreshWarning = _status = _direction = null;
    _nextCursor = null;
    _items = const [];
    _clearSelection();
    _pending = null;
    _lastConfirmed = null;
    _notify();
  }

  Future<Map<String, dynamic>> _get(
    _SwapBinding b,
    String route, {
    Map<String, String>? query,
  }) async {
    if (!_current(b)) throw const _Fenced();
    final result = await session.authorized((token) {
      if (!_current(b)) throw const _Fenced();
      return api.get(token, route, query: query);
    });
    if (!_current(b)) throw const _Fenced();
    return result;
  }

  // A later read supersedes an earlier read. Each task builds its result locally
  // and publishes only through this generation check after every network await.
  Future<void> _read(
    Future<void> Function(_SwapBinding, bool Function()) work,
  ) async {
    if (_pending != null || _submitting || !canRead) return;
    final b = _binding!, generation = ++_readGeneration;
    bool current() => _current(b) && generation == _readGeneration;
    _reading = true;
    _error = null;
    _notify();
    try {
      if (current()) await work(b, current);
    } catch (e) {
      if (current()) _error = _message(e);
    } finally {
      if (current()) {
        _reading = false;
        _notify();
      }
    }
  }

  void _scope(ShiftSwapDto dto, _SwapBinding b, [String? id]) {
    if (dto.json['companyId'] != b.companyId ||
        dto.json['locationId'] != b.locationId ||
        (id != null && dto.json['id'] != id)) {
      throw const FormatException('Swap scope mismatch.');
    }
  }

  ShiftSwapDetailDto _parseDetail(
    Map<String, dynamic> raw,
    _SwapBinding b,
    String id,
  ) {
    final dto = ShiftSwapDetailDto.fromJson(raw);
    final request = ShiftSwapDto.fromJson(_object(dto.json['request']));
    _scope(request, b, id);
    if (self
        ? !{'source', 'recipient'}.contains(dto.json['participantRole'])
        : dto.json['participantRole'] != 'manager') {
      throw const FormatException('Swap mode mismatch.');
    }
    final accepted = _lastConfirmed?.request.json;
    if (accepted != null && accepted['id'] == id) {
      final fresh = request.json;
      if ((fresh['version'] as int) < (accepted['version'] as int)) {
        throw const FormatException('Detail predates accepted command.');
      }
      for (final key in [
        'sourceEmployeeId',
        'recipientEmployeeId',
        'requestedAt',
        'requestOperationId',
        'offeredAt',
        'offerOperationId',
        'confirmedAt',
        'confirmationOperationId',
        'terminalAt',
        'terminalOperationId',
        'terminalKind',
        'terminalReason',
      ]) {
        if (accepted[key] != null && accepted[key] != fresh[key]) {
          throw const FormatException('Detail contradicts accepted evidence.');
        }
      }
      final originals = accepted['legs'] as List, legs = fresh['legs'] as List;
      for (var i = 0; i < originals.length; i++) {
        if (i >= legs.length ||
            !_same(
              accepted['status'] == 'approved'
                  ? originals[i]
                  : _originalLeg(_object(originals[i])),
              accepted['status'] == 'approved'
                  ? legs[i]
                  : _originalLeg(_object(legs[i])),
            )) {
          throw const FormatException('Detail contradicts accepted pair.');
        }
      }
    }
    return dto;
  }

  Future<void> filter({String? state, String? way}) async {
    if (_pending != null || _submitting || !canRead) return;
    if ((state != null && !shiftSwapStates.contains(state)) ||
        (way != null && (!self || !{'incoming', 'outgoing'}.contains(way)))) {
      _error = 'Invalid swap filters.';
      _notify();
      return;
    }
    _status = state;
    _direction = way;
    await load();
  }

  Future<void> load({bool more = false}) => _read((b, current) async {
    if (more && _nextCursor == null) return;
    if (!more) {
      _items = const [];
      _nextCursor = null;
    }
    final raw = await _get(
      b,
      _root(b),
      query: {
        'status': ?_status,
        'direction': ?_direction,
        if (more) 'after': _nextCursor!,
      },
    );
    if (!current()) return;
    final page = ShiftSwapPageDto.fromJson(raw);
    final rows = (page.json['items'] as List).map((j) {
      final dto = ShiftSwapDto.fromJson(_object(j));
      _scope(dto, b);
      return dto;
    }).toList();
    _items = _merge(
      more ? _items : const [],
      rows,
      (r) => r.json['id'] as String,
      (r) => r.json,
    );
    _nextCursor = page.json['nextCursor'] as String?;
  });

  Future<void> select(String id) {
    final target = shiftUuid(id);
    return _read((b, current) async {
      _clearSelection();
      final raw = await _get(b, '${_root(b)}/$target');
      if (!current()) return;
      _detail = _parseDetail(raw, b, target);
      _refreshWarning = null;
    });
  }

  Future<void> loadHistory(String id, {bool more = false}) {
    final target = shiftUuid(id);
    return _read((b, current) async {
      if (more && (_historyId != target || _historyCursor == null)) return;
      if (!more) {
        _history = const [];
        _historyCursor = null;
        _historyId = target;
      }
      final raw = await _get(
        b,
        '${_root(b)}/$target/history',
        query: {if (more) 'after': _historyCursor!},
      );
      if (!current()) return;
      final (rows, cursor) = _historyPage(raw, b, target);
      final merged = _merge<ShiftSwapCommandResult>(
        more ? _history : const [],
        rows,
        (r) => r.json['operationId'] as String,
        (r) => r.json,
      );
      if (merged.length > 4 ||
          merged.indexed.any((e) => e.$2.json['acceptedVersion'] != e.$1 + 1)) {
        throw const FormatException('Invalid receipt order.');
      }
      _history = merged;
      _historyCursor = cursor;
    });
  }

  (List<ShiftSwapCommandResult>, String?) _historyPage(
    Map<String, dynamic> raw,
    _SwapBinding b,
    String id,
  ) {
    if (raw.length != 2 ||
        !raw.containsKey('items') ||
        !raw.containsKey('nextCursor') ||
        raw['items'] is! List ||
        (raw['items'] as List).length > 2) {
      throw const FormatException('Invalid history page.');
    }
    final cursor = raw['nextCursor'];
    if (cursor != null &&
        (cursor is! String || cursor.isEmpty || cursor.length > 2048)) {
      throw const FormatException('Invalid history cursor.');
    }
    final rows = (raw['items'] as List).map((j) {
      final result = ShiftSwapCommandResult.fromJson(_object(j));
      _scope(result.request, b, id);
      return result;
    }).toList();
    if (rows.map((r) => r.json['operationId']).toSet().length != rows.length) {
      throw const FormatException('Duplicate receipt.');
    }
    return (rows, cursor as String?);
  }

  Future<void> chooseSource(ShiftDto shift, {bool more = false}) {
    // Copy through the existing DTO before the caller can alter picker state.
    final selected = ShiftDto.fromJson(shift.toJson());
    return _read((b, current) async {
      if (!self ||
          !platform.allows('workforce.swaps.self.request') ||
          selected.companyId != b.companyId ||
          selected.locationId != b.locationId ||
          selected.status != 'published') {
        return;
      }
      if (more &&
          (_source?.id != selected.id ||
              _source?.version != selected.version ||
              _colleagueCursor == null)) {
        return;
      }
      if (!more) _clearSelection();
      final raw = await _get(
        b,
        '/employee-home/shifts/${selected.id}/swap-colleagues',
        query: {if (more) 'after': _colleagueCursor!},
      );
      if (!current()) return;
      final page = ShiftSwapColleaguePageDto.fromJson(raw);
      _colleagues = _merge(
        more ? _colleagues : const [],
        (page.json['items'] as List).map(_object).toList(),
        (r) => r['employeeId'] as String,
        (r) => r,
      );
      _source = selected;
      _colleagueCursor = page.json['nextCursor'] as String?;
    });
  }

  void chooseColleague(String? employeeId) {
    if (locked || !canRead || !self) return;
    if (employeeId == null) {
      _colleague = null;
      _notify();
      return;
    }
    final id = shiftUuid(employeeId);
    final matches = _colleagues.where((r) => r['employeeId'] == id);
    if (matches.isEmpty) return;
    _colleague = matches.single;
    _notify();
  }

  bool get _mayDiscover =>
      self &&
      canRead &&
      _detail?.json['participantRole'] == 'recipient' &&
      (_detail?.json['request'] as Map?)?['status'] == 'requested' &&
      _detail?.json['actionable'] == true &&
      platform.allows('workforce.swaps.self.respond') &&
      (_detail?.json['availableActions'] as List?)?.contains('offer') == true;

  Future<void> loadCounterparts({bool more = false}) {
    if (!_mayDiscover) return Future.value();
    final id = (_detail!.json['request'] as Map)['id'] as String;
    return _read((b, current) async {
      if (more && _counterpartCursor == null) return;
      if (!more) {
        _counterparts = const [];
        _counterpartCursor = null;
        _counterpart = null;
        _selectedCounterpart = null;
      }
      final raw = await _get(
        b,
        '${_root(b)}/$id/counterparts',
        query: {if (more) 'after': _counterpartCursor!},
      );
      if (!current()) return;
      final page = ShiftSwapCounterpartPageDto.fromJson(raw);
      _counterparts = _merge(
        more ? _counterparts : const [],
        (page.json['items'] as List).map(_object).toList(),
        (r) => r['shiftId'] as String,
        (r) => r,
      );
      _counterpartCursor = page.json['nextCursor'] as String?;
    });
  }

  Future<void> chooseCounterpart(String shiftId) {
    if (!_mayDiscover) return Future.value();
    final id = shiftUuid(shiftId),
        matches = _counterparts.where((r) => r['shiftId'] == id);
    if (matches.isEmpty) return Future.value();
    final candidate = matches.single,
        request = _object(_detail!.json['request']);
    return _read((b, current) async {
      _counterpart = null;
      _selectedCounterpart = null;
      final raw = await _get(
        b,
        '${_root(b)}/${request['id']}/counterparts/$id',
      );
      if (!current()) return;
      final leg = ShiftSwapLegDto.fromJson(raw), j = leg.json;
      if (j['leg'] != 'b' ||
          j['sourceShiftId'] != id ||
          j['sourceVersion'] != candidate['version'] ||
          j['sourceEmployeeId'] != request['recipientEmployeeId'] ||
          j['incomingEmployeeId'] != request['sourceEmployeeId'] ||
          j['replacementShiftId'] != null ||
          shiftInstant(j['startsAt']) != shiftInstant(candidate['startsAt']) ||
          shiftInstant(j['endsAt']) != shiftInstant(candidate['endsAt'])) {
        throw const FormatException(
          'Counterpart evidence changed. Reload candidates.',
        );
      }
      _counterpart = candidate;
      _selectedCounterpart = leg;
    });
  }

  bool can(String kind) {
    if (locked ||
        !canRead ||
        _detail == null ||
        !shiftSwapKinds.contains(kind)) {
      return false;
    }
    if (!(_detail!.json['availableActions'] as List).contains(kind)) {
      return false;
    }
    if (!self) {
      return kind == 'manager_reject' ||
          kind == 'manager_approve' &&
              _detail!.json['actionable'] == true &&
              platform.allows('workforce.shifts.manage') &&
              platform.allows('tasks.instances.read');
    }
    final permission = kind == 'source_withdraw'
        ? 'workforce.swaps.self.request'
        : 'workforce.swaps.self.respond';
    if (!platform.allows(permission)) return false;
    if ({'offer', 'confirm'}.contains(kind) &&
        _detail!.json['actionable'] != true) {
      return false;
    }
    return kind != 'offer' ||
        (_counterpart != null && _selectedCounterpart != null);
  }

  bool get canRequest =>
      !locked &&
      self &&
      canRead &&
      platform.allows('workforce.swaps.self.request') &&
      _source != null &&
      _colleague != null;

  Future<SwapOutcome> request() {
    if (_pending != null || busy) return Future.value(SwapOutcome.busy);
    if (!canRequest) return Future.value(SwapOutcome.rejected);
    return _submit(
      'request',
      _root(_binding!),
      {
        'operationId': _newId(),
        'requestId': _newId(),
        'sourceShiftId': _source!.id,
        'expectedSourceVersion': _source!.version,
        'recipientEmployeeId': _colleague!['employeeId'],
      },
      {'source': _source!.toJson()},
    );
  }

  Future<SwapOutcome> act(String action, {String? reason}) {
    if (_pending != null || busy) return Future.value(SwapOutcome.busy);
    final role = _detail?.json['participantRole'];
    final kind =
        action == 'withdraw' && self && {'source', 'recipient'}.contains(role)
        ? '${role}_withdraw'
        : !self && {'approve', 'reject'}.contains(action)
        ? 'manager_$action'
        : action;
    if (!can(kind) || (kind.endsWith('_withdraw') && action != 'withdraw')) {
      return Future.value(SwapOutcome.rejected);
    }
    final request = _object(_detail!.json['request']);
    final suffix = kind.endsWith('_withdraw')
        ? 'withdraw'
        : kind.startsWith('manager_')
        ? kind.substring(8)
        : kind;
    return _submit(
      kind,
      '${_root(_binding!)}/${request['id']}/$suffix',
      {
        'operationId': _newId(),
        'expectedVersion': request['version'],
        if (kind == 'offer') ...{
          'counterpartShiftId': _selectedCounterpart!.json['sourceShiftId'],
          'expectedCounterpartVersion':
              _selectedCounterpart!.json['sourceVersion'],
        },
        if (kind.endsWith('_withdraw') || kind == 'manager_reject')
          'reason': reason,
      },
      {
        'request': request,
        if (kind == 'offer') 'counterpart': _selectedCounterpart!.json,
      },
    );
  }

  Future<SwapOutcome> _submit(
    String kind,
    String route,
    Map<String, dynamic> body,
    Map<String, dynamic> evidence,
  ) {
    if (locked || !_current(_binding)) return Future.value(SwapOutcome.busy);
    try {
      final input = ShiftSwapCommandInput.fromJson(kind, body);
      _pending = PendingSwapCommand._(
        _binding!,
        route,
        input,
        kind == 'request'
            ? input.payload['requestId'] as String
            : _object(evidence['request'])['id'] as String,
        evidence,
        SwapSubmission.submitting,
      );
    } on SwapInputException catch (e) {
      _error = e.message;
      _notify();
      return Future.value(SwapOutcome.rejected);
    }
    return retry();
  }

  Future<SwapOutcome> retry() async {
    final command = _pending;
    if (command == null || busy) return SwapOutcome.busy;
    final b = command._binding;
    if (!_current(b)) return SwapOutcome.fenced;
    final generation = ++_submissionGeneration;
    bool current() => _current(b) && generation == _submissionGeneration;
    final unresolved = command.state != SwapSubmission.submitting;
    _submitting = true;
    _error = null;
    _pending = command._withState(SwapSubmission.submitting);
    _notify();
    var outcome = SwapOutcome.uncertain;
    try {
      final raw = await session.authorized((token) {
        if (!current()) throw const _Fenced();
        return api.post(token, command.route, command.body);
      });
      if (!current()) return SwapOutcome.fenced;
      final result = _accepted(command, raw);
      outcome = await _confirm(command, result, current);
    } catch (e) {
      if (!current()) return SwapOutcome.fenced;
      final definitive =
          e is StoreApiException &&
          {400, 401, 403, 404, 409, 413, 415, 422}.contains(e.statusCode);
      if (definitive && !unresolved) {
        _pending = null;
        _clearSelection();
        _error = _message(e);
        _refreshWarning =
            'Reload authorized swap evidence before another action.';
        outcome = SwapOutcome.rejected;
      } else {
        _clearSelection();
        _pending = command._withState(
          definitive
              ? SwapSubmission.reconciliationRequired
              : SwapSubmission.uncertain,
        );
        _error = definitive
            ? '${_message(e)} The earlier outcome remains unknown. Explicit reconciliation or exact retry is required.'
            : 'Swap outcome unknown. Retry the exact command or explicitly reconcile its receipt.';
        outcome = definitive
            ? SwapOutcome.reconciliationRequired
            : SwapOutcome.uncertain;
      }
    } finally {
      if (current()) {
        _submitting = false;
        _notify();
      }
    }
    return current() ? outcome : SwapOutcome.fenced;
  }

  /// A negative/absent read never proves rollback. Only the exact original
  /// accepted receipt can resolve an uncertain intent within this session.
  Future<SwapOutcome> reconcile() async {
    final command = _pending;
    if (command == null || busy) return SwapOutcome.busy;
    final b = command._binding;
    if (!_current(b)) return SwapOutcome.fenced;
    final generation = ++_submissionGeneration;
    bool current() => _current(b) && generation == _submissionGeneration;
    bool ownsPending() => current() && identical(_pending, command);
    _submitting = true;
    _notify();
    var outcome = SwapOutcome.reconciliationRequired;
    try {
      String? cursor;
      final seen = <String>{};
      pages:
      for (var page = 0; page < 2; page++) {
        if (!ownsPending()) return SwapOutcome.fenced;
        final raw = await _get(
          b,
          '${_root(b)}/${command.requestId}/history',
          query: {'after': ?cursor},
        );
        if (!ownsPending()) return SwapOutcome.fenced;
        final (receipts, next) = _historyPage(raw, b, command.requestId);
        for (final receipt in receipts) {
          if (receipt.json['operationId'] == command.operationId) {
            outcome = await _confirm(
              command,
              _accepted(command, receipt.json),
              current,
            );
            break pages;
          }
        }
        if (next == null || !seen.add(next)) break;
        cursor = next;
      }
      if (outcome == SwapOutcome.reconciliationRequired && ownsPending()) {
        _pending = command._withState(SwapSubmission.reconciliationRequired);
        _error =
            'No confirming receipt found. The original outcome remains unknown.';
      }
    } catch (e) {
      if (!ownsPending()) return SwapOutcome.fenced;
      _pending = command._withState(SwapSubmission.reconciliationRequired);
      _error = '${_message(e)} The original outcome remains unknown.';
    } finally {
      if (current()) {
        // Complete all owned state before publishing: listeners may synchronously
        // invalidate this binding or start another explicit retry/reconciliation.
        _submitting = false;
        _notify();
      }
    }
    return current() ? outcome : SwapOutcome.fenced;
  }

  ShiftSwapCommandResult _accepted(
    PendingSwapCommand c,
    Map<String, dynamic> raw,
  ) {
    final result = ShiftSwapCommandResult.fromJson(raw),
        request = result.request.json;
    _scope(result.request, c._binding, c.requestId);
    if (result.json['operationId'] != c.operationId ||
        result.json['kind'] != c.kind ||
        result.json['acceptedVersion'] !=
            (c.kind == 'request' ? 1 : c.expectedVersion + 1)) {
      throw const FormatException('Command confirmation mismatch.');
    }
    final legs = (request['legs'] as List).map(_object).toList();
    if (c.kind == 'request') {
      final source = ShiftDto.fromJson(_object(c.evidence['source']));
      if (legs.first['sourceShiftId'] != source.id ||
          legs.first['sourceVersion'] != source.version ||
          legs.first['sourceEmployeeId'] != source.draft.employeeId ||
          request['recipientEmployeeId'] != c.body['recipientEmployeeId'] ||
          shiftInstant(legs.first['startsAt']) != source.draft.startsAt ||
          shiftInstant(legs.first['endsAt']) != source.draft.endsAt) {
        throw const FormatException('Source confirmation mismatch.');
      }
    } else {
      final before = _object(c.evidence['request']);
      for (final key in [
        'sourceEmployeeId',
        'recipientEmployeeId',
        'requestedAt',
        'requestOperationId',
        'offeredAt',
        'offerOperationId',
        'confirmedAt',
        'confirmationOperationId',
      ]) {
        if (before[key] != null && before[key] != request[key]) {
          throw const FormatException('Consent evidence mismatch.');
        }
      }
      final originalLegs = (before['legs'] as List).map(_object).toList();
      for (var i = 0; i < originalLegs.length; i++) {
        if (!_same(_originalLeg(originalLegs[i]), _originalLeg(legs[i]))) {
          throw const FormatException('Original leg mismatch.');
        }
      }
      if (c.kind == 'offer' &&
          !_same(
            _originalLeg(_object(c.evidence['counterpart'])),
            _originalLeg(legs[1]),
          )) {
        throw const FormatException('Offered pair mismatch.');
      }
    }
    if (c.body.containsKey('reason') &&
        request['terminalReason'] != c.body['reason']) {
      throw const FormatException('Closure reason mismatch.');
    }
    return result;
  }

  Future<SwapOutcome> _confirm(
    PendingSwapCommand c,
    ShiftSwapCommandResult result,
    bool Function() current,
  ) async {
    final b = c._binding;
    if (!current()) return SwapOutcome.fenced;
    _lastConfirmed = result;
    _pending = null;
    _clearSelection();
    _items = List.unmodifiable(
      _items.where((r) => r.json['id'] != c.requestId),
    );
    _nextCursor = null;
    _error = _refreshWarning = null;
    _notify();
    try {
      if (!current()) return SwapOutcome.fenced;
      final raw = await _get(b, '${_root(b)}/${c.requestId}');
      if (!current()) return SwapOutcome.fenced;
      _detail = _parseDetail(raw, b, c.requestId);
    } catch (_) {
      if (current()) {
        _refreshWarning =
            'Command confirmed. Current swap detail is unavailable. Reload authorized detail before another action.';
      }
    }
    return current() ? SwapOutcome.confirmed : SwapOutcome.fenced;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _submissionGeneration++;
    session.removeListener(_contextChanged);
    platform.removeListener(_contextChanged);
    _binding = null;
    _reading = _submitting = false;
    _error = _refreshWarning = _status = _direction = null;
    _nextCursor = null;
    _pending = null;
    _lastConfirmed = null;
    _items = const [];
    _clearSelection();
    super.dispose();
  }
}

class _Fenced implements Exception {
  const _Fenced();
}

Map<String, dynamic> _object(Object? v) {
  if (v is! Map<String, dynamic>) {
    throw const FormatException('Object required.');
  }
  return v;
}

Object? _freeze(Object? v) {
  if (v is Map<String, dynamic>) {
    return Map<String, dynamic>.unmodifiable(
      v.map((k, v) => MapEntry(k, _freeze(v))),
    );
  }
  if (v is List) return List<Object?>.unmodifiable(v.map(_freeze));
  return v;
}

Map<String, dynamic> _originalLeg(Map<String, dynamic> j) => {...j}
  ..remove('replacementShiftId')
  ..remove('taskLinks');
bool _same(Object? a, Object? b) {
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && _same(a[k], b[k]));
  }
  if (a is List && b is List) {
    return a.length == b.length && a.indexed.every((e) => _same(e.$2, b[e.$1]));
  }
  return a == b;
}

List<T> _merge<T>(
  List<T> before,
  List<T> page,
  String Function(T) id,
  Map<String, dynamic> Function(T) json,
) {
  final rows = {for (final r in before) id(r): r};
  for (final r in page) {
    final old = rows[id(r)];
    if (old != null && !_same(json(old), json(r))) {
      throw const FormatException(
        'Paged evidence changed. Reload the first page.',
      );
    }
    rows[id(r)] = r;
  }
  return List.unmodifiable(rows.values);
}

String _message(Object e) => e is StoreApiException
    ? '${e.code}: ${e.message}'
    : 'Could not load valid swap evidence.';
String _uuid() {
  final r = Random.secure(), b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 15) | 64;
  b[8] = (b[8] & 63) | 128;
  final h = b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
