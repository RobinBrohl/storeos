/// Q04-C01: inert PostgreSQL 3.0 framing and ownership model.
///
/// Authority: Q04-SD v0.2 final msg_012ce1407493d61c016adadbd787a88191957f3c4e60c13dba
/// plus v0.3 msg_0081897a35b38204016adb7fd2796481919cc727cd5516200c.
/// The pinned postgres 3.5.17 emits BEGIN;/COMMIT;/ROLLBACK; simple queries,
/// Parse?/Bind/Describe(portal)/Execute(0)/Sync and Close/Sync exchanges.
/// PostgreSQL 17 protocol-flow and protocol-message-formats define the wire
/// layouts, object lifetimes, asynchronous messages and ReadyForQuery states.
///
/// No transport, timers, credentials, application imports or production hooks.
/// Forward decisions are model outputs, never evidence of actual socket writes.
/// Authentication, Bind and row bodies are transient and scrubbed after decoding.
/// GC/runtime copies and caller-owned input are outside this model's control.
///
/// Future feasibility gates: source-bound W/K/O SQL/OID/selected-value catalogue,
/// independently verified operation admission and backend identity, full real
/// driver traces (including BEGIN options and portal cleanup after errors),
/// cancellation-key authentication in a separately authorized volatile adapter,
/// real forwarding/withholding measurements and owner-approved resource limits.
/// Optional diagnostics, arbitrary pipelines, COPY, replication, SSL/GSS,
/// PortalSuspended and general simple SQL are deliberately refused.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

enum Refusal {
  malformed,
  length,
  resourceLimit,
  unsupported,
  sequence,
  ownership,
  backendError,
  timeout,
  eof,
  transportError,
  terminated,
}

final class ProtocolRefusal implements Exception {
  final Refusal reason;
  const ProtocolRefusal(this.reason);
  @override
  String toString() => 'ProtocolRefusal(${reason.name})';
}

Never _refuse(Refusal reason) => throw ProtocolRefusal(reason);

/// Candidate component limits only; these do not approve operational ceilings.
final class ProtocolLimits {
  final int maxFrameBytes;
  final int maxBufferedBytes;
  final int maxQueuedFrames;
  final int maxEvents;
  final int maxStatements;
  final int maxPortals;
  final int maxCatalogueEntries;
  final int maxNameBytes;
  final int maxParameters;
  final int maxColumns;
  final int maxRowsPerExchange;
  final int maxAsyncMessages;

  ProtocolLimits({
    this.maxFrameBytes = 1024 * 1024,
    this.maxBufferedBytes = 2 * 1024 * 1024,
    this.maxQueuedFrames = 64,
    this.maxEvents = 128,
    this.maxStatements = 64,
    this.maxPortals = 64,
    this.maxCatalogueEntries = 128,
    this.maxNameBytes = 128,
    this.maxParameters = 128,
    this.maxColumns = 128,
    this.maxRowsPerExchange = 4096,
    this.maxAsyncMessages = 256,
  }) {
    if (maxFrameBytes < 16 ||
        maxBufferedBytes < maxFrameBytes ||
        [
          maxQueuedFrames,
          maxEvents,
          maxStatements,
          maxPortals,
          maxCatalogueEntries,
          maxNameBytes,
          maxParameters,
          maxColumns,
          maxRowsPerExchange,
          maxAsyncMessages,
        ].any((n) => n < 1)) {
      throw ArgumentError('Invalid protocol limits');
    }
  }
}

/// A trusted, finite source catalogue entry. SQL and parameter values are never
/// copied into frame diagnostics. No SQL normalization or substring matching.
final class StatementSpec {
  final String id;
  final List<int> _sql;
  final List<int> parameterOids;
  final String completionTag;
  final bool returnsRows;

  StatementSpec({
    required this.id,
    required String sql,
    required List<int> parameterOids,
    required this.completionTag,
    this.returnsRows = true,
  }) : _sql = List<int>.unmodifiable(utf8.encode(sql)),
       parameterOids = List<int>.unmodifiable(parameterOids) {
    if (id.isEmpty ||
        id.length > 128 ||
        sql.isEmpty ||
        sql.contains('\u0000') ||
        parameterOids.any((n) => n < 0 || n > 0xffffffff) ||
        !RegExp(
          r'^(SELECT [0-9]+|UPDATE [0-9]+|DELETE [0-9]+|INSERT 0 [0-9]+)$',
        ).hasMatch(completionTag) ||
        completionTag.length > 64) {
      throw ArgumentError('Invalid catalogue entry');
    }
  }
  @override
  String toString() => 'StatementSpec';
}

enum Direction { frontend, backend }

enum FrameKind {
  startup,
  sslRequest,
  gssRequest,
  cancelRequest,
  query,
  parse,
  bind,
  describe,
  execute,
  flush,
  sync,
  close,
  terminate,
  password,
  authentication,
  backendKey,
  ready,
  parseComplete,
  bindComplete,
  closeComplete,
  parameterDescription,
  rowDescription,
  noData,
  dataRow,
  commandComplete,
  notice,
  parameterStatus,
  notification,
  error,
}

enum ReadyState { idle, transaction, failed }

enum Control { begin, commit, rollback }

enum AuthenticationMode { trust, scramSha256 }

/// A bounded semantic frame. Payloads, credentials and cancellation secrets are
/// never exposed or retained here. Object names are private routing metadata.
final class ProtocolFrame {
  final FrameKind kind;
  final int wireBytes;
  final String? _name;
  final String? _statement;
  final bool _portal;
  final StatementSpec? _spec;
  final int count;
  final int? backendPid;
  final int? authCode;
  final ReadyState? ready;
  final Control? control;
  final String? _tag;
  final List<int> _oids;
  final Object? _ingress;

  const ProtocolFrame._(
    this.kind,
    this.wireBytes, {
    this._name,
    this._statement,
    this._portal = false,
    this._spec,
    this.count = 0,
    this.backendPid,
    this.authCode,
    this.ready,
    this.control,
    this._tag,
    this._oids = const [],
    this._ingress,
  });

  @override
  String toString() => 'ProtocolFrame(${kind.name}, bytes=$wireBytes)';
}

final class _Cursor {
  final Uint8List bytes;
  int offset;
  _Cursor(this.bytes, this.offset);
  int get remaining => bytes.length - offset;
  void need(int n) {
    if (n < 0 || n > remaining) _refuse(Refusal.malformed);
  }

  int u8() {
    need(1);
    return bytes[offset++];
  }

  int u16() => (u8() << 8) | u8();
  int u32() => (u16() << 16) | u16();
  int i32() {
    final n = u32();
    return n >= 0x80000000 ? n - 0x100000000 : n;
  }

  void skip(int n) {
    need(n);
    offset += n;
  }

  (int, int) span() {
    final start = offset;
    while (u8() != 0) {}
    return (start, offset - 1);
  }

  String string(int maxBytes) {
    final (a, b) = span();
    if (b - a > maxBytes) _refuse(Refusal.resourceLimit);
    try {
      return utf8.decode(Uint8List.sublistView(bytes, a, b));
    } on FormatException {
      _refuse(Refusal.malformed);
    }
  }

  bool equals((int, int) range, List<int> expected) {
    final (a, b) = range;
    if (b - a != expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[a + i] != expected[i]) return false;
    }
    return true;
  }

  void end() {
    if (remaining != 0) _refuse(Refusal.malformed);
  }
}

/// Incremental framer. Only a five-byte header is allocated before validating
/// the advertised length. At most one validated wire frame is buffered; queued
/// results contain semantic metadata, never opaque wire bodies.
final class ProtocolFramer {
  final Direction direction;
  final ProtocolLimits limits;
  final List<StatementSpec> _catalogue;
  final _queue = ListQueue<ProtocolFrame>();
  final _header = Uint8List(5);
  int _headerUsed = 0;
  Uint8List? _frame;
  int _used = 0;
  Object? _frameIngress;
  bool _startup;
  bool _specialStartup = false;
  bool _terminal = false;
  int peakBufferedBytes = 0;

  ProtocolFramer({
    required this.direction,
    required this.limits,
    Iterable<StatementSpec> catalogue = const [],
    bool startup = false,
  }) : _startup = startup,
       _catalogue = _boundedCatalogue(catalogue, limits) {
    if (startup && direction != Direction.frontend) {
      throw ArgumentError('Startup is frontend only');
    }
    if (_catalogue.length > limits.maxCatalogueEntries ||
        _catalogue.map((e) => e.id).toSet().length != _catalogue.length ||
        _catalogue.any(
          (e) =>
              e._sql.length + 10 > limits.maxFrameBytes ||
              e.parameterOids.length > limits.maxParameters,
        )) {
      throw ArgumentError('Invalid bounded catalogue');
    }
    for (var i = 0; i < _catalogue.length; i++) {
      for (var j = 0; j < i; j++) {
        if (_same(_catalogue[i]._sql, _catalogue[j]._sql)) {
          throw ArgumentError('Ambiguous catalogue');
        }
      }
    }
  }
  static List<StatementSpec> _boundedCatalogue(
    Iterable<StatementSpec> entries,
    ProtocolLimits limits,
  ) {
    final result = <StatementSpec>[];
    for (final entry in entries) {
      if (result.length >= limits.maxCatalogueEntries) {
        throw ArgumentError('Catalogue limit exceeded');
      }
      result.add(entry);
    }
    return List<StatementSpec>.unmodifiable(result);
  }

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  int get bufferedBytes => _frame == null ? _headerUsed : _used;
  int get queuedFrames => _queue.length;
  bool get terminal => _terminal;
  ProtocolFrame? take() => _queue.isEmpty ? null : _queue.removeFirst();

  void discard() {
    _terminal = true;
    _frame?.fillRange(0, _frame!.length, 0);
    _frame = null;
    _header.fillRange(0, _header.length, 0);
    _used = _headerUsed = 0;
    _frameIngress = null;
    _queue.clear();
  }

  void add(List<int> chunk) => _add(chunk);

  /// Opaque provenance is captured at the first byte, including a partial
  /// header, and is never replaced when subsequent chunks finish that frame.
  void _add(List<int> chunk, {Object? ingress}) {
    if (_terminal) _refuse(Refusal.terminated);
    try {
      var i = 0;
      while (i < chunk.length) {
        if (_specialStartup) _refuse(Refusal.sequence);
        if (_frame == null) {
          if (_headerUsed == 0) _frameIngress = ingress;
          final headerSize = _startup ? 4 : 5;
          while (_headerUsed < headerSize && i < chunk.length) {
            final b = chunk[i++];
            if (b < 0 || b > 255) _refuse(Refusal.malformed);
            _header[_headerUsed++] = b;
          }
          if (_headerUsed != headerSize) break;
          final o = _startup ? 0 : 1;
          final length =
              (_header[o] << 24) |
              (_header[o + 1] << 16) |
              (_header[o + 2] << 8) |
              _header[o + 3];
          final total = length + (_startup ? 0 : 1);
          if (length < (_startup ? 8 : 4) ||
              length > 0x7fffffff ||
              total > limits.maxFrameBytes ||
              total > limits.maxBufferedBytes) {
            _refuse(Refusal.length);
          }
          // Unknown type is rejected before allocating the advertised body.
          if (!_startup && !_knownType(_header[0])) {
            _refuse(Refusal.unsupported);
          }
          _frame = Uint8List(total);
          _frame!.setRange(0, headerSize, _header);
          _used = headerSize;
          if (total > peakBufferedBytes) peakBufferedBytes = total;
        }
        final frame = _frame!;
        while (_used < frame.length && i < chunk.length) {
          final b = chunk[i++];
          if (b < 0 || b > 255) _refuse(Refusal.malformed);
          frame[_used++] = b;
        }
        if (_used != frame.length) break;
        if (_queue.length >= limits.maxQueuedFrames) {
          _refuse(Refusal.resourceLimit);
        }
        _queue.add(_decode(frame));
        frame.fillRange(0, frame.length, 0);
        _frame = null;
        _header.fillRange(0, _header.length, 0);
        _used = _headerUsed = 0;
        _frameIngress = null;
      }
    } on ProtocolRefusal {
      discard();
      rethrow;
    }
  }

  bool _knownType(int t) =>
      (direction == Direction.frontend
              ? 'QPBD EHS C Xp'.replaceAll(' ', '')
              : 'RKZ123tTnDCN SAE'.replaceAll(' ', ''))
          .codeUnits
          .contains(t);

  ProtocolFrame _decode(Uint8List bytes) {
    final c = _Cursor(bytes, _startup ? 4 : 5);
    final size = bytes.length;
    ProtocolFrame f(
      FrameKind k, {
      String? name,
      String? statement,
      bool portal = false,
      StatementSpec? spec,
      int count = 0,
      int? pid,
      int? auth,
      ReadyState? ready,
      Control? control,
      String? tag,
      List<int> oids = const [],
    }) => ProtocolFrame._(
      k,
      size,
      name: name,
      statement: statement,
      portal: portal,
      spec: spec,
      count: count,
      backendPid: pid,
      authCode: auth,
      ready: ready,
      control: control,
      tag: tag,
      oids: oids,
      ingress: _frameIngress,
    );
    if (_startup) {
      final version = c.u32();
      _startup = false;
      if ([80877103, 80877104, 80877102].contains(version)) {
        _specialStartup = true;
        if (version == 80877102) {
          final pid = c.u32();
          c.skip(4); // Cancellation key is deliberately not materialized.
          c.end();
          if (pid == 0 || pid > 0x7fffffff) _refuse(Refusal.malformed);
          return f(FrameKind.cancelRequest, pid: pid);
        }
        c.end();
        return f(
          version == 80877103 ? FrameKind.sslRequest : FrameKind.gssRequest,
        );
      }
      if (version != 196608) _refuse(Refusal.unsupported);
      final keys = <String>{};
      while (c.remaining > 1) {
        final key = c.string(32);
        if (!{
              'user',
              'database',
              'client_encoding',
              'TimeZone',
              'application_name',
            }.contains(key) ||
            !keys.add(key)) {
          _refuse(Refusal.unsupported);
        }
        final value = c.span();
        if (key == 'client_encoding' && !c.equals(value, utf8.encode('UTF8'))) {
          _refuse(Refusal.unsupported);
        }
      }
      if (c.u8() != 0 ||
          !keys.containsAll({'user', 'database', 'client_encoding'})) {
        _refuse(Refusal.malformed);
      }
      c.end();
      return f(FrameKind.startup);
    }
    final t = String.fromCharCode(bytes[0]);
    if (direction == Direction.frontend) {
      switch (t) {
        case 'Q':
          final sql = c.span();
          c.end();
          for (final v in Control.values) {
            if (c.equals(sql, utf8.encode('${v.name.toUpperCase()};'))) {
              return f(FrameKind.query, control: v);
            }
          }
          _refuse(Refusal.unsupported);
        case 'P':
          final name = c.string(limits.maxNameBytes);
          final sql = c.span();
          final specs = _catalogue.where((e) => c.equals(sql, e._sql));
          if (specs.length != 1) _refuse(Refusal.unsupported);
          final spec = specs.single;
          final n = c.u16();
          if (n != spec.parameterOids.length) _refuse(Refusal.unsupported);
          for (final oid in spec.parameterOids) {
            if (c.u32() != oid) _refuse(Refusal.unsupported);
          }
          c.end();
          return f(FrameKind.parse, name: name, spec: spec);
        case 'B':
          final portal = c.string(limits.maxNameBytes);
          final statement = c.string(limits.maxNameBytes);
          final formats = c.u16();
          if (formats > limits.maxParameters) _refuse(Refusal.resourceLimit);
          for (var i = 0; i < formats; i++) {
            if (c.u16() > 1) _refuse(Refusal.unsupported);
          }
          final n = c.u16();
          if (n > limits.maxParameters) _refuse(Refusal.resourceLimit);
          if (formats != 0 && formats != 1 && formats != n) {
            _refuse(Refusal.malformed);
          }
          for (var i = 0; i < n; i++) {
            final length = c.i32();
            if (length < -1) _refuse(Refusal.malformed);
            if (length != -1) c.skip(length);
          }
          final results = c.u16();
          if (results > limits.maxColumns) _refuse(Refusal.resourceLimit);
          for (var i = 0; i < results; i++) {
            if (c.u16() > 1) _refuse(Refusal.unsupported);
          }
          c.end();
          return f(
            FrameKind.bind,
            name: portal,
            statement: statement,
            count: n,
          );
        case 'D':
        case 'C':
          final object = c.u8();
          if (object != 80 && object != 83) _refuse(Refusal.malformed);
          final name = c.string(limits.maxNameBytes);
          c.end();
          return f(
            t == 'D' ? FrameKind.describe : FrameKind.close,
            name: name,
            portal: object == 80,
          );
        case 'E':
          final name = c.string(limits.maxNameBytes);
          if (c.u32() != 0) _refuse(Refusal.unsupported);
          c.end();
          return f(FrameKind.execute, name: name);
        case 'p':
          if (c.remaining == 0) _refuse(Refusal.malformed);
          // SASLInitialResponse is identifiable without retaining its response.
          final prefix = utf8.encode('SCRAM-SHA-256\u0000');
          var initial = c.remaining >= prefix.length + 4;
          for (var i = 0; initial && i < prefix.length; i++) {
            if (bytes[c.offset + i] != prefix[i]) initial = false;
          }
          if (initial) {
            c.skip(prefix.length);
            final n = c.i32();
            if (n <= 0 || n != c.remaining) _refuse(Refusal.malformed);
          }
          c.skip(c.remaining);
          return f(FrameKind.password, count: initial ? 1 : 0);
        case 'H':
        case 'S':
        case 'X':
          c.end();
          return f(
            t == 'H'
                ? FrameKind.flush
                : t == 'S'
                ? FrameKind.sync
                : FrameKind.terminate,
          );
      }
    } else {
      switch (t) {
        case 'R':
          final code = c.u32();
          if (code == 10) {
            if (c.string(32) != 'SCRAM-SHA-256' || c.u8() != 0) {
              _refuse(Refusal.unsupported);
            }
          } else if (code == 11 || code == 12) {
            if (c.remaining == 0) _refuse(Refusal.malformed);
            c.skip(c.remaining);
          } else if (code != 0) {
            _refuse(Refusal.unsupported);
          }
          c.end();
          return f(FrameKind.authentication, auth: code);
        case 'K':
          final pid = c.u32();
          c.skip(4);
          c.end();
          if (pid == 0 || pid > 0x7fffffff) _refuse(Refusal.malformed);
          return f(FrameKind.backendKey, pid: pid);
        case 'Z':
          final s = c.u8();
          c.end();
          final ready = switch (s) {
            73 => ReadyState.idle,
            84 => ReadyState.transaction,
            69 => ReadyState.failed,
            _ => null,
          };
          if (ready == null) _refuse(Refusal.malformed);
          return f(FrameKind.ready, ready: ready);
        case '1':
        case '2':
        case '3':
        case 'n':
          c.end();
          return f(switch (t) {
            '1' => FrameKind.parseComplete,
            '2' => FrameKind.bindComplete,
            '3' => FrameKind.closeComplete,
            _ => FrameKind.noData,
          });
        case 't':
          final n = c.u16();
          if (n > limits.maxParameters) _refuse(Refusal.resourceLimit);
          final oids = List<int>.generate(n, (_) => c.u32());
          c.end();
          return f(
            FrameKind.parameterDescription,
            oids: List<int>.unmodifiable(oids),
          );
        case 'T':
          final n = c.u16();
          if (n > limits.maxColumns) _refuse(Refusal.resourceLimit);
          for (var i = 0; i < n; i++) {
            c.span();
            c.skip(16);
            if (c.u16() > 1) _refuse(Refusal.unsupported);
          }
          c.end();
          return f(FrameKind.rowDescription, count: n);
        case 'D':
          final n = c.u16();
          if (n > limits.maxColumns) _refuse(Refusal.resourceLimit);
          for (var i = 0; i < n; i++) {
            final length = c.i32();
            if (length < -1) _refuse(Refusal.malformed);
            if (length != -1) c.skip(length);
          }
          c.end();
          return f(FrameKind.dataRow, count: n);
        case 'C':
          final tag = c.string(64);
          c.end();
          if (!{
            'BEGIN',
            'COMMIT',
            'ROLLBACK',
            ..._catalogue.map((e) => e.completionTag),
          }.contains(tag)) {
            _refuse(Refusal.unsupported);
          }
          return f(FrameKind.commandComplete, tag: tag);
        case 'S':
          c.span();
          c.span();
          c.end();
          return f(FrameKind.parameterStatus);
        case 'A':
          c.skip(4);
          c.span();
          c.span();
          c.end();
          return f(FrameKind.notification);
        case 'N':
        case 'E':
          var fields = 0;
          while (c.u8() != 0) {
            c.span();
            fields++;
          }
          if (fields == 0) _refuse(Refusal.malformed);
          c.end();
          return f(t == 'N' ? FrameKind.notice : FrameKind.error);
      }
    }
    _refuse(Refusal.unsupported);
  }
}

/// Supplied by an independent observer; constructing this is no verification.
final class BackendIdentity {
  final String cluster;
  final String database;
  final int pid;
  final String backendStart;
  const BackendIdentity(
    this.cluster,
    this.database,
    this.pid,
    this.backendStart,
  );
  @override
  bool operator ==(Object other) =>
      other is BackendIdentity &&
      other.cluster == cluster &&
      other.database == database &&
      other.pid == pid &&
      other.backendStart == backendStart;
  @override
  int get hashCode => Object.hash(cluster, database, pid, backendStart);
  @override
  String toString() => 'BackendIdentity';
}

/// Externally attested admission context. The component never infers a business
/// operation from connection order or from unreviewed Bind values.
/// frozenPayloadId references an immutable reviewed specimen, not a hash or copy
/// of unrestricted SQL parameters. Its external binding remains a feasibility gate.
final class CommandIdentity {
  final String company;
  final String? location;
  final String resource;
  final String operationId;
  final int expectedVersion;
  final String frozenPayloadId;
  const CommandIdentity({
    required this.company,
    this.location,
    required this.resource,
    required this.operationId,
    required this.expectedVersion,
    required this.frozenPayloadId,
  });
  @override
  bool operator ==(Object other) =>
      other is CommandIdentity &&
      other.company == company &&
      other.location == location &&
      other.resource == resource &&
      other.operationId == operationId &&
      other.expectedVersion == expectedVersion &&
      other.frozenPayloadId == frozenPayloadId;
  @override
  int get hashCode => Object.hash(
    company,
    location,
    resource,
    operationId,
    expectedVersion,
    frozenPayloadId,
  );
  @override
  String toString() => 'CommandIdentity';
}

final class OperationIdentity {
  final String run;
  final String scenario;
  final int cycle;
  final String attempt;
  final String specimen;
  final CommandIdentity command;
  const OperationIdentity(
    this.run,
    this.scenario,
    this.cycle,
    this.attempt,
    this.specimen, {
    required this.command,
  });
  @override
  bool operator ==(Object other) =>
      other is OperationIdentity &&
      other.run == run &&
      other.scenario == scenario &&
      other.cycle == cycle &&
      other.attempt == attempt &&
      other.specimen == specimen &&
      other.command == command;
  @override
  int get hashCode =>
      Object.hash(run, scenario, cycle, attempt, specimen, command);
  @override
  String toString() => 'OperationIdentity';
}

final class TransactionTarget {
  final int connectionGeneration;
  final int transactionGeneration;
  final BackendIdentity backend;
  final OperationIdentity operation;
  const TransactionTarget(
    this.connectionGeneration,
    this.transactionGeneration,
    this.backend,
    this.operation,
  );
  @override
  bool operator ==(Object other) =>
      other is TransactionTarget &&
      other.connectionGeneration == connectionGeneration &&
      other.transactionGeneration == transactionGeneration &&
      other.backend == backend &&
      other.operation == operation;
  @override
  int get hashCode => Object.hash(
    connectionGeneration,
    transactionGeneration,
    backend,
    operation,
  );
  @override
  String toString() => 'TransactionTarget';
}

/// One allocator must belong to one future run; reconnects require a fresh ID.
final class ConnectionGenerations {
  int _last = 0;
  int next() => ++_last;
}

enum ConnectionState {
  startup,
  idle,
  transaction,
  failedTransaction,
  holdingNext,
  heldNext,
  heldCommit,
  commitGated,
  committedWithheld,
  cancellation,
  terminal,
}

enum CommitMode { s05Hold, s06WithholdCompletion }

enum Decision {
  forward,
  discard,
  asynchronous,
  holdNextFrame,
  heldNext,
  holdCommit,
  forwardCommit,
  withhold,
  settled,
  cancel,
  terminal,
}

final class ProtocolEvent {
  final Decision decision;
  final FrameKind? kind;
  final int? exchangeGeneration;
  final int? transactionGeneration;
  final int? statementGeneration;
  final int? portalGeneration;
  final Refusal? refusal;
  const ProtocolEvent._(
    this.decision, {
    this.kind,
    this.exchangeGeneration,
    this.transactionGeneration,
    this.statementGeneration,
    this.portalGeneration,
    this.refusal,
  });
  @override
  String toString() =>
      'ProtocolEvent(${decision.name}, ${kind?.name}, ${refusal?.name})';
}

final class _Statement {
  final int generation;
  final StatementSpec spec;
  bool confirmed = false;
  _Statement(this.generation, this.spec);
}

final class _Portal {
  final int generation;
  final _Statement statement;
  bool confirmed = false;
  _Portal(this.generation, this.statement);
}

enum _Owed { parse, bind, parameters, description, execute, close, ready }

final class _Exchange {
  final int generation;
  final int transaction;
  final Control? control;
  final owed = ListQueue<_Owed>();
  String stage;
  _Statement? statement;
  _Portal? portal;
  ProtocolFrame? closing;
  String? statementName;
  String? portalName;
  int discardedFrames = 0;
  int discardedBytes = 0;
  bool synced = false;
  bool error = false;
  int columns = -1;
  int rows = 0;
  _Exchange(this.generation, this.transaction, this.stage, {this.control});
}

/// Immutable eligibility at ingress, independent of later owner mutations.
final class _BackendIngress {
  final _Exchange? owner;
  final BackendIdentity? identity;
  final int transaction;
  final bool forwarded;
  final bool synced;
  _BackendIngress(this.owner, this.identity, this.transaction, this.forwarded)
    : synced = owner?.synced ?? false;
}

/// Pure duplex ownership model. Callers drain bounded decisions explicitly.
/// This class intentionally has no forwarding callback or executable entrypoint.
final class ProtocolProfile {
  final ProtocolLimits limits;
  final AuthenticationMode authentication;
  final int connectionGeneration;
  final ProtocolFramer frontend;
  final ProtocolFramer backend;
  final _events = ListQueue<ProtocolEvent>();
  final _statements = <String, _Statement>{};
  final _portals = <String, _Portal>{};
  ConnectionState _state = ConnectionState.startup;
  int _transactionGeneration = 0;
  ConnectionState get state => _state;
  int get transactionGeneration => _transactionGeneration;
  int _statementGeneration = 0;
  int _portalGeneration = 0;
  int _exchangeGeneration = 0;
  int _asyncCount = 0;
  int? _pid;
  BackendIdentity? _identity;
  OperationIdentity? _operation;
  bool _startupReceived = false;
  bool _startupReady = false;
  String _auth = 'initial';
  bool _authOk = false;
  _Exchange? _exchange;
  _Portal? _cleanup;
  TransactionTarget? _armed;
  CommitMode? _mode;
  bool _commitForwarded = false;
  bool _commitComplete = false;
  List<int>? _heldCommit;
  bool _holdNext = false;
  final _heldExchange = <ProtocolFrame>[];
  int _heldExchangeBytes = 0;
  Refusal? terminalReason;

  ProtocolProfile({
    required this.connectionGeneration,
    required this.limits,
    this.authentication = AuthenticationMode.scramSha256,
    Iterable<StatementSpec> catalogue = const [],
  }) : frontend = ProtocolFramer(
         direction: Direction.frontend,
         limits: limits,
         catalogue: catalogue,
         startup: true,
       ),
       backend = ProtocolFramer(
         direction: Direction.backend,
         limits: limits,
         catalogue: catalogue,
       ) {
    if (connectionGeneration < 1) throw ArgumentError('Invalid generation');
  }
  int get statementCount => _statements.length;
  int get portalCount => _portals.length;
  int get pendingResponses => _exchange?.owed.length ?? 0;
  bool get hasHeldCommit => _heldCommit != null;
  int get heldNextFrameCount => _heldExchange.length;
  int get heldNextWireBytes => _heldExchangeBytes;
  bool get responseGateInstalled =>
      state == ConnectionState.commitGated ||
      state == ConnectionState.committedWithheld;
  bool get _inputQuiescent =>
      frontend.bufferedBytes == 0 &&
      backend.bufferedBytes == 0 &&
      frontend.queuedFrames == 0 &&
      backend.queuedFrames == 0;
  bool get fullySettled =>
      _exchange == null && _cleanup == null && _inputQuiescent;
  int get authorizedCommitBytes => _commitForwarded ? _commitBytes.length : 0;
  // Exact Query("COMMIT;"): 'Q', length 12, eight payload bytes.
  static const _commitBytes = <int>[
    81,
    0,
    0,
    0,
    12,
    67,
    79,
    77,
    77,
    73,
    84,
    59,
    0,
  ];
  List<int> get heldCommitBytes =>
      List<int>.unmodifiable(_heldCommit ?? const []);

  List<ProtocolEvent> drainEvents() {
    final result = List<ProtocolEvent>.unmodifiable(_events);
    _events.clear();
    return result;
  }

  void _emit(Decision decision, [ProtocolFrame? frame]) {
    if (_events.length >= limits.maxEvents) _refuse(Refusal.resourceLimit);
    final e = _exchange;
    _events.add(
      ProtocolEvent._(
        decision,
        kind: frame?.kind,
        exchangeGeneration: e?.generation,
        transactionGeneration: e?.transaction,
        statementGeneration: e?.statement?.generation,
        portalGeneration: e?.portal?.generation,
      ),
    );
  }

  void _guard(void Function() action) {
    if (state == ConnectionState.terminal) _refuse(Refusal.terminated);
    try {
      action();
    } on ProtocolRefusal catch (e) {
      _terminate(e.reason);
      rethrow;
    }
  }

  void _terminate(Refusal reason) {
    if (state == ConnectionState.terminal) return;
    frontend.discard();
    backend.discard();
    _statements.clear();
    _portals.clear();
    _exchange = null;
    _cleanup = null;
    _armed = null;
    _mode = null;
    _operation = null;
    _identity = null;
    _pid = null;
    _heldCommit = null;
    _heldExchange.clear();
    _heldExchangeBytes = 0;
    _holdNext = false;
    _commitComplete = _commitForwarded = false;
    _events.clear();
    terminalReason = reason;
    _state = ConnectionState.terminal;
    _events.add(ProtocolEvent._(Decision.terminal, refusal: reason));
  }

  void timeout() => _terminate(Refusal.timeout);
  void eof() => _terminate(Refusal.eof);
  void transportError() => _terminate(Refusal.transportError);

  void addFrontend(List<int> bytes) => _guard(() {
    if (state == ConnectionState.cancellation) _refuse(Refusal.sequence);
    frontend.add(bytes);
    ProtocolFrame? f;
    while ((f = frontend.take()) != null) {
      _front(f!);
    }
  });
  void addBackend(List<int> bytes) => _guard(() {
    if (state == ConnectionState.cancellation) _refuse(Refusal.sequence);
    backend._add(
      bytes,
      ingress: _BackendIngress(
        _exchange,
        _identity,
        transactionGeneration,
        _commitForwarded,
      ),
    );
    ProtocolFrame? f;
    while ((f = backend.take()) != null) {
      _back(f!);
    }
  });

  void bindBackendIdentity(BackendIdentity identity) => _guard(() {
    if (state != ConnectionState.startup ||
        _identity != null ||
        identity.pid != _pid ||
        identity.cluster.isEmpty ||
        identity.database.isEmpty ||
        identity.backendStart.isEmpty ||
        [
          identity.cluster,
          identity.database,
          identity.backendStart,
        ].any((s) => s.length > 128)) {
      _refuse(Refusal.ownership);
    }
    _identity = identity;
    if (_startupReady) _state = ConnectionState.idle;
  });
  void attributeTransaction(OperationIdentity operation) => _guard(() {
    if (state != ConnectionState.transaction ||
        !fullySettled ||
        _operation != null ||
        operation.cycle < 1 ||
        operation.command.expectedVersion < 0 ||
        [
          operation.run,
          operation.scenario,
          operation.attempt,
          operation.specimen,
          operation.command.company,
          if (operation.command.location != null) operation.command.location!,
          operation.command.resource,
          operation.command.operationId,
          operation.command.frozenPayloadId,
        ].any((s) => s.isEmpty || s.length > 128)) {
      _refuse(Refusal.ownership);
    }
    _operation = operation;
  });
  bool _matches(TransactionTarget t) =>
      t.connectionGeneration == connectionGeneration &&
      t.transactionGeneration == transactionGeneration &&
      t.backend == _identity &&
      t.operation == _operation;
  void armCommit(TransactionTarget target, CommitMode mode) => _guard(() {
    if (state != ConnectionState.transaction ||
        !fullySettled ||
        _armed != null ||
        !_matches(target)) {
      _refuse(Refusal.ownership);
    }
    _armed = target;
    _mode = mode;
  });

  /// Pure HELD_NEXT model: withhold the next supported extended execution
  /// through Sync. Only sanitized frame representations are retained, bounded
  /// by both the frame-count and aggregate wire-byte limits. A future adapter
  /// must separately prove actual wire withholding without retaining evidence
  /// copies of unrestricted Bind payloads. There is no release operation.
  void armNextExchange(TransactionTarget target) => _guard(() {
    if (state != ConnectionState.transaction ||
        !fullySettled ||
        _armed != null ||
        !_matches(target)) {
      _refuse(Refusal.ownership);
    }
    _armed = target;
    _holdNext = true;
  });

  /// Synthetic acknowledgement of a future adapter's single write. This is not
  /// a socket counter. The response gate is already installed before this call.
  void confirmCommitForwarded(TransactionTarget target) => _guard(() {
    if (state != ConnectionState.commitGated ||
        _armed != target ||
        !_matches(target) ||
        _commitForwarded ||
        !_inputQuiescent ||
        _exchange?.control != Control.commit) {
      _refuse(Refusal.ownership);
    }
    _commitForwarded = true;
  });

  _Exchange _new(String stage, {Control? control}) {
    if (_exchange != null) _refuse(Refusal.sequence);
    return _exchange = _Exchange(
      ++_exchangeGeneration,
      transactionGeneration,
      stage,
      control: control,
    );
  }

  /// PostgreSQL discards the unprocessed tail of this extended exchange after
  /// ErrorResponse. Validate its finite grammar and ordinary framing, retain
  /// its existing owner, and account for bounded discards without object writes.
  void _discardFrontend(_Exchange e, ProtocolFrame f) {
    if (e.synced || e.control != null) _refuse(Refusal.sequence);
    if (e.discardedFrames >= limits.maxQueuedFrames ||
        f.wireBytes > limits.maxBufferedBytes - e.discardedBytes) {
      _refuse(Refusal.resourceLimit);
    }
    ++e.discardedFrames;
    e.discardedBytes += f.wireBytes;
    switch (f.kind) {
      case FrameKind.bind:
        if (e.stage != 'parsed' ||
            f._statement != e.statementName ||
            f.count != e.statement!.spec.parameterOids.length) {
          _refuse(Refusal.sequence);
        }
        e.portalName = f._name;
        e.stage = 'bound';
      case FrameKind.describe:
        if (f._portal && e.stage == 'bound' && f._name == e.portalName) {
          e.stage = 'described';
        } else if (!f._portal &&
            e.stage == 'parsed' &&
            f._name == e.statementName) {
          e.stage = 'statementDescription';
        } else {
          _refuse(Refusal.sequence);
        }
      case FrameKind.execute:
        if (e.stage != 'described' || f._name != e.portalName) {
          _refuse(Refusal.sequence);
        }
        e.stage = 'executed';
      case FrameKind.flush:
        if (!{
          'parsed',
          'bound',
          'described',
          'executed',
          'closed',
          'statementDescription',
        }.contains(e.stage)) {
          _refuse(Refusal.sequence);
        }
      case FrameKind.sync:
        e.synced = true;
        _emit(Decision.forward, f);
        return;
      default:
        _refuse(Refusal.sequence);
    }
    _emit(Decision.discard, f);
  }

  void _front(ProtocolFrame f) {
    if (f.kind == FrameKind.sslRequest || f.kind == FrameKind.gssRequest) {
      _refuse(Refusal.unsupported);
    }
    if (f.kind == FrameKind.cancelRequest) {
      if (_startupReceived || state != ConnectionState.startup) {
        _refuse(Refusal.sequence);
      }
      _state = ConnectionState.cancellation;
      frontend.discard();
      backend.discard();
      _emit(Decision.cancel, f);
      return;
    }
    if (f.kind == FrameKind.terminate) _refuse(Refusal.terminated);
    if (state == ConnectionState.startup) {
      if (f.kind == FrameKind.startup && !_startupReceived) {
        _startupReceived = true;
        _emit(Decision.forward, f);
        return;
      }
      if (f.kind == FrameKind.password &&
          (_auth == 'clientFirst' || _auth == 'clientFinal')) {
        if ((_auth == 'clientFirst') != (f.count == 1)) {
          _refuse(Refusal.unsupported);
        }
        _auth = _auth == 'clientFirst' ? 'serverFirst' : 'serverFinal';
        _emit(Decision.forward, f);
        return;
      }
      _refuse(Refusal.sequence);
    }
    if ([
      ConnectionState.heldCommit,
      ConnectionState.heldNext,
      ConnectionState.commitGated,
      ConnectionState.committedWithheld,
    ].contains(state)) {
      _refuse(Refusal.sequence);
    }
    if (_exchange?.error ?? false) {
      _discardFrontend(_exchange!, f);
      return;
    }
    if (f.kind == FrameKind.query) {
      if (_holdNext) _refuse(Refusal.unsupported);
      if (!fullySettled ||
          (state != ConnectionState.idle &&
              state != ConnectionState.transaction &&
              state != ConnectionState.failedTransaction)) {
        _refuse(Refusal.sequence);
      }
      if ((f.control == Control.begin && state != ConnectionState.idle) ||
          (f.control != Control.begin && state == ConnectionState.idle) ||
          (f.control == Control.commit &&
              state == ConnectionState.failedTransaction)) {
        _refuse(Refusal.sequence);
      }
      // A simple query destroys the unnamed statement and unnamed portal.
      _statements.remove('');
      _portals.remove('');
      final e = _new('query', control: f.control);
      e.owed.addAll([_Owed.execute, _Owed.ready]);
      e.synced = true;
      if (_armed != null) {
        if (f.control != Control.commit || !_matches(_armed!)) {
          _refuse(Refusal.ownership);
        }
        _heldCommit = List<int>.unmodifiable(_commitBytes);
        if (_mode == CommitMode.s05Hold) {
          _state = ConnectionState.heldCommit;
          _emit(Decision.holdCommit, f);
        } else {
          _state =
              ConnectionState.commitGated; // Gate BEFORE forwarding decision.
          _emit(Decision.forwardCommit, f);
        }
      } else {
        _emit(Decision.forward, f);
      }
      return;
    }
    if (_armed != null && !_holdNext) _refuse(Refusal.ownership);
    if (_holdNext && state == ConnectionState.transaction) {
      if (f.kind != FrameKind.parse && f.kind != FrameKind.bind) {
        _refuse(Refusal.sequence);
      }
      _state = ConnectionState.holdingNext;
    }
    if (state == ConnectionState.failedTransaction) _refuse(Refusal.sequence);
    if (_exchange?.synced ?? false) _refuse(Refusal.sequence);
    switch (f.kind) {
      case FrameKind.parse:
        final e = _new('parsed');
        if (f._name!.isNotEmpty && _statements.containsKey(f._name)) {
          _refuse(Refusal.sequence);
        }
        if (!_statements.containsKey(f._name) &&
            _statements.length >= limits.maxStatements) {
          _refuse(Refusal.resourceLimit);
        }
        final statement = _Statement(++_statementGeneration, f._spec!);
        _statements[f._name] = statement;
        e.statement = statement;
        e.statementName = f._name;
        e.owed.add(_Owed.parse);
      case FrameKind.bind:
        final e = _exchange ?? _new('start');
        if (e.stage != 'start' && e.stage != 'parsed') {
          _refuse(Refusal.sequence);
        }
        if (_cleanup != null) _refuse(Refusal.sequence);
        final statement = _statements[f._statement];
        if (statement == null ||
            (!statement.confirmed && statement != e.statement) ||
            (e.stage == 'parsed' && statement != e.statement) ||
            f.count != statement.spec.parameterOids.length) {
          _refuse(Refusal.ownership);
        }
        if (f._name!.isNotEmpty && _portals.containsKey(f._name)) {
          _refuse(Refusal.sequence);
        }
        if (!_portals.containsKey(f._name) &&
            _portals.length >= limits.maxPortals) {
          _refuse(Refusal.resourceLimit);
        }
        final portal = _Portal(++_portalGeneration, statement);
        _portals[f._name] = portal;
        e.statement = statement;
        e.statementName = f._statement;
        e.portal = portal;
        e.portalName = f._name;
        e.stage = 'bound';
        e.owed.add(_Owed.bind);
      case FrameKind.describe:
        if (f._portal) {
          final e = _exchange;
          if (e == null ||
              e.stage != 'bound' ||
              _portals[f._name] != e.portal) {
            _refuse(Refusal.ownership);
          }
          e.stage = 'described';
          e.owed.add(_Owed.description);
        } else {
          final e = _exchange ?? _new('start');
          if ((e.stage != 'start' && e.stage != 'parsed') ||
              _statements[f._name] == null ||
              (e.stage == 'parsed' && _statements[f._name] != e.statement)) {
            _refuse(Refusal.sequence);
          }
          e.statement = _statements[f._name];
          e.statementName = f._name;
          e.stage = 'statementDescription';
          e.owed.addAll([_Owed.parameters, _Owed.description]);
        }
      case FrameKind.execute:
        final e = _exchange;
        if (e == null ||
            e.stage != 'described' ||
            _portals[f._name] != e.portal) {
          _refuse(Refusal.ownership);
        }
        e.stage = 'executed';
        e.owed.add(_Owed.execute);
      case FrameKind.close:
        final e = _new('closed');
        e.closing = f;
        if (f._portal) {
          e.portal = _portals[f._name];
          if (e.portal == null) _refuse(Refusal.ownership);
          e.statement = e.portal!.statement;
        } else {
          e.statement = _statements[f._name];
          if (e.statement == null || _cleanup != null) {
            _refuse(Refusal.ownership);
          }
        }
        e.owed.add(_Owed.close);
      case FrameKind.flush:
        if (_exchange == null || _exchange!.synced) _refuse(Refusal.sequence);
      case FrameKind.sync:
        final e = _exchange;
        if (e == null ||
            !{
              'parsed',
              'executed',
              'closed',
              'statementDescription',
            }.contains(e.stage)) {
          _refuse(Refusal.sequence);
        }
        e.synced = true;
        e.owed.add(_Owed.ready);
      default:
        _refuse(Refusal.sequence);
    }
    if (_holdNext) {
      if (!_matches(_armed!) ||
          _heldExchange.length >= limits.maxQueuedFrames ||
          f.wireBytes > limits.maxBufferedBytes - _heldExchangeBytes) {
        _refuse(Refusal.resourceLimit);
      }
      _heldExchange.add(f);
      _heldExchangeBytes += f.wireBytes;
      _emit(Decision.holdNextFrame, f);
      if (f.kind == FrameKind.sync) {
        // Parse-only and Close exchanges are not a selected business execution.
        if (_exchange!.stage != 'executed') _refuse(Refusal.unsupported);
        _state = ConnectionState.heldNext;
        _emit(Decision.heldNext, f);
      }
    } else {
      _emit(Decision.forward, f);
    }
  }

  void _back(ProtocolFrame f) {
    if (!_startupReceived) _refuse(Refusal.sequence);
    if ([
      FrameKind.notice,
      FrameKind.parameterStatus,
      FrameKind.notification,
    ].contains(f.kind)) {
      if (state == ConnectionState.startup &&
          ((f.kind == FrameKind.parameterStatus && !_authOk) ||
              f.kind == FrameKind.notification)) {
        _refuse(Refusal.sequence);
      }
      if (++_asyncCount > limits.maxAsyncMessages) {
        _refuse(Refusal.resourceLimit);
      }
      if (f.kind == FrameKind.notification && _armed != null) {
        _refuse(Refusal.unsupported);
      }
      _emit(Decision.asynchronous, f);
      return;
    }
    if (state == ConnectionState.startup) {
      switch (f.kind) {
        case FrameKind.authentication:
          if (_authOk || _startupReady) _refuse(Refusal.sequence);
          if (f.authCode == 10 &&
              _auth == 'initial' &&
              authentication == AuthenticationMode.scramSha256) {
            _auth = 'clientFirst';
          } else if (f.authCode == 11 && _auth == 'serverFirst') {
            _auth = 'clientFinal';
          } else if (f.authCode == 12 && _auth == 'serverFinal') {
            _auth = 'ok';
          } else if (f.authCode == 0 &&
              ((_auth == 'initial' &&
                      authentication == AuthenticationMode.trust) ||
                  _auth == 'ok') &&
              !_authOk) {
            _authOk = true;
          } else {
            _refuse(Refusal.sequence);
          }
        case FrameKind.backendKey:
          if (!_authOk || _pid != null) _refuse(Refusal.sequence);
          _pid = f.backendPid;
        case FrameKind.ready:
          if (!_authOk ||
              _pid == null ||
              _startupReady ||
              f.ready != ReadyState.idle) {
            _refuse(Refusal.sequence);
          }
          _startupReady = true;
          if (_identity != null) _state = ConnectionState.idle;
        case FrameKind.error:
          _refuse(Refusal.backendError);
        default:
          _refuse(Refusal.sequence);
      }
      _emit(Decision.forward, f);
      return;
    }
    if (f.kind == FrameKind.error && _armed != null) {
      _refuse(Refusal.backendError);
    }
    if (state == ConnectionState.holdingNext ||
        state == ConnectionState.heldNext ||
        state == ConnectionState.heldCommit ||
        state == ConnectionState.committedWithheld) {
      _refuse(Refusal.sequence);
    }
    final e = _exchange;
    if (e == null) _refuse(Refusal.ownership);
    final ingress = f._ingress;
    if (ingress is! _BackendIngress ||
        !identical(ingress.owner, e) ||
        ingress.identity != _identity ||
        ingress.transaction != e.transaction ||
        (f.kind == FrameKind.ready && !ingress.synced)) {
      _refuse(Refusal.ownership);
    }
    if (state == ConnectionState.commitGated &&
        (!_commitForwarded || !ingress.forwarded)) {
      _refuse(Refusal.ownership);
    }
    if (f.kind == FrameKind.error) {
      if (e.error) _refuse(Refusal.backendError);
      e.error = true;
      e.owed.clear();
      e.owed.add(_Owed.ready);
      // Unconfirmed objects cannot survive an error-to-Sync boundary.
      _statements.removeWhere((_, s) => !s.confirmed);
      _portals.removeWhere((_, p) => !p.confirmed);
      _emit(Decision.forward, f);
      return;
    }
    if (e.owed.isEmpty) _refuse(Refusal.ownership);
    final expected = e.owed.first;
    if (e.error && f.kind != FrameKind.ready) _refuse(Refusal.sequence);
    switch (expected) {
      case _Owed.parse:
        if (f.kind != FrameKind.parseComplete) _refuse(Refusal.ownership);
        e.statement!.confirmed = true;
      case _Owed.bind:
        if (f.kind != FrameKind.bindComplete) _refuse(Refusal.ownership);
        e.portal!.confirmed = true;
      case _Owed.parameters:
        if (f.kind != FrameKind.parameterDescription ||
            !ProtocolFramer._same(f._oids, e.statement!.spec.parameterOids)) {
          _refuse(Refusal.ownership);
        }
      case _Owed.description:
        if (f.kind != FrameKind.rowDescription && f.kind != FrameKind.noData) {
          _refuse(Refusal.ownership);
        }
        if ((f.kind == FrameKind.rowDescription) !=
            e.statement!.spec.returnsRows) {
          _refuse(Refusal.ownership);
        }
        e.columns = f.kind == FrameKind.noData ? -1 : f.count;
      case _Owed.execute:
        if (f.kind == FrameKind.dataRow) {
          if (e.columns < 0 ||
              f.count != e.columns ||
              ++e.rows > limits.maxRowsPerExchange) {
            _refuse(Refusal.resourceLimit);
          }
          _emit(Decision.forward, f);
          return;
        }
        if (f.kind != FrameKind.commandComplete) _refuse(Refusal.ownership);
        final tag =
            e.control?.name.toUpperCase() ?? e.statement?.spec.completionTag;
        if (f._tag != tag) _refuse(Refusal.ownership);
        if (state == ConnectionState.commitGated) _commitComplete = true;
      case _Owed.close:
        if (f.kind != FrameKind.closeComplete) _refuse(Refusal.ownership);
        final close = e.closing!;
        if (close._portal) {
          _portals.remove(close._name);
          if (_cleanup == e.portal) _cleanup = null;
        } else {
          _statements.remove(close._name);
        }
      case _Owed.ready:
        if (f.kind != FrameKind.ready || !e.synced) _refuse(Refusal.ownership);
        final expectedState = e.error
            ? (state == ConnectionState.idle
                  ? ReadyState.idle
                  : ReadyState.failed)
            : e.control == Control.begin
            ? ReadyState.transaction
            : (e.control == Control.commit || e.control == Control.rollback)
            ? ReadyState.idle
            : state == ConnectionState.idle
            ? ReadyState.idle
            : ReadyState.transaction;
        if (f.ready != expectedState) _refuse(Refusal.ownership);
        if (e.error) {
          _state = f.ready == ReadyState.failed
              ? ConnectionState.failedTransaction
              : ConnectionState.idle;
          _cleanup = null;
          _operation = null;
        } else if (e.control == Control.begin) {
          ++_transactionGeneration;
          _state = ConnectionState.transaction;
        } else if (e.control == Control.commit ||
            e.control == Control.rollback) {
          if (state == ConnectionState.commitGated) {
            if (!_commitComplete) _refuse(Refusal.ownership);
            _state = ConnectionState.committedWithheld;
          } else {
            _state = ConnectionState.idle;
          }
          _operation = null;
        } else if (e.stage == 'executed' && f.ready == ReadyState.transaction) {
          _cleanup = e.portal;
        }
        if (f.ready == ReadyState.idle) {
          // postgres 3.5.17 only queues explicit portal cleanup after T.
          // At I the implicit/explicit transaction ended and portals are gone.
          _portals.clear();
          _cleanup = null;
        }
    }
    e.owed.removeFirst();
    _emit(responseGateInstalled ? Decision.withhold : Decision.forward, f);
    if (expected == _Owed.ready) {
      if (e.owed.isNotEmpty) _refuse(Refusal.ownership);
      _emit(Decision.settled, f);
      _exchange = null;
    }
  }
}
