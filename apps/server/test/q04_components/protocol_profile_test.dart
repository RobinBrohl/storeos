// Synthetic bytes only. Imports deliberately exclude applications, database
// clients, IO, runner entrypoints and infrastructure capabilities.
import 'dart:convert';

import 'package:test/test.dart';

import '../../tool/q04/support/protocol_profile.dart';

List<int> u16(int n) => [n >> 8 & 255, n & 255];
List<int> u32(int n) => [n >> 24 & 255, n >> 16 & 255, n >> 8 & 255, n & 255];
List<int> z(String s) => [...utf8.encode(s), 0];
List<int> wire(String type, [List<int> body = const []]) => [
  type.codeUnitAt(0),
  ...u32(body.length + 4),
  ...body,
];
List<int> packet(List<int> body) => [...u32(body.length + 4), ...body];
List<int> startup() => packet([
  ...u32(196608),
  ...z('user'),
  ...z('synthetic_user'),
  ...z('database'),
  ...z('synthetic_database'),
  ...z('client_encoding'),
  ...z('UTF8'),
  0,
]);
List<int> query(String sql) => wire('Q', z(sql));
List<int> command(String tag) => wire('C', z(tag));
List<int> ready(String state) => wire('Z', state.codeUnits);
List<int> parse(String name, String sql, [List<int> oids = const []]) => wire(
  'P',
  [...z(name), ...z(sql), ...u16(oids.length), for (final n in oids) ...u32(n)],
);
List<int> bind(
  String portal,
  String statement, [
  List<int?> values = const [],
]) => wire('B', [
  ...z(portal),
  ...z(statement),
  ...u16(0),
  ...u16(values.length),
  for (final n in values) ...[...u32(n == null ? -1 : 1), ?n],
  ...u16(0),
]);
List<int> describe(String name, {bool portal = true}) =>
    wire('D', [portal ? 80 : 83, ...z(name)]);
List<int> execute(String name, {int maxRows = 0}) =>
    wire('E', [...z(name), ...u32(maxRows)]);
List<int> close(String name, {bool portal = true}) =>
    wire('C', [portal ? 80 : 83, ...z(name)]);
List<int> rowDescription() => wire('T', [
  ...u16(1),
  ...z('column'),
  ...u32(0),
  ...u16(0),
  ...u32(25),
  ...u16(-1),
  ...u32(-1),
  ...u16(0),
]);
List<int> row(String value) => wire('D', [
  ...u16(1),
  ...u32(utf8.encode(value).length),
  ...utf8.encode(value),
]);
List<int> error([String detail = 'synthetic_secret']) =>
    wire('E', [83, ...z('ERROR'), 67, ...z('22000'), 77, ...z(detail), 0]);

const sqlA = r'SELECT $1::text';
const sqlB = 'SELECT 2';
StatementSpec specA() => StatementSpec(
  id: 'a',
  sql: sqlA,
  parameterOids: [25],
  completionTag: 'SELECT 1',
);
StatementSpec specB() => StatementSpec(
  id: 'b',
  sql: sqlB,
  parameterOids: [],
  completionTag: 'SELECT 1',
);
const sqlC = 'UPDATE synthetic SET value = 1';
StatementSpec specC() => StatementSpec(
  id: 'c',
  sql: sqlC,
  parameterOids: [],
  completionTag: 'UPDATE 1',
  returnsRows: false,
);
const identity = BackendIdentity('cluster', 'database', 41, 'start-1');
const commandIdentity = CommandIdentity(
  company: 'company',
  location: 'location',
  resource: 'swap-request',
  operationId: 'approval-operation',
  expectedVersion: 3,
  frozenPayloadId: 'reviewed-command-specimen',
);
const operation = OperationIdentity(
  'run',
  'S05',
  1,
  'attempt',
  'W',
  command: commandIdentity,
);

ProtocolProfile session({ProtocolLimits? limits, int generation = 1}) {
  final p = ProtocolProfile(
    connectionGeneration: generation,
    authentication: AuthenticationMode.trust,
    limits: limits ?? ProtocolLimits(),
    catalogue: [specA(), specB(), specC()],
  );
  p.addFrontend(startup());
  p.addBackend([
    ...wire('R', u32(0)),
    ...wire('K', [...u32(41), ...u32(987654)]),
    ...ready('I'),
  ]);
  p.bindBackendIdentity(identity);
  p.drainEvents();
  return p;
}

void begin(ProtocolProfile p) {
  p.addFrontend(query('BEGIN;'));
  p.addBackend([...command('BEGIN'), ...ready('T')]);
  p.drainEvents();
}

void prepare(ProtocolProfile p, String name, {bool second = false}) {
  p.addFrontend([
    ...parse(name, second ? sqlB : sqlA, second ? [] : [25]),
    ...wire('S'),
  ]);
  p.addBackend([
    ...wire('1'),
    ...ready(p.state == ConnectionState.idle ? 'I' : 'T'),
  ]);
  p.drainEvents();
}

void request(
  ProtocolProfile p,
  String statement,
  String portal, {
  bool withParse = false,
  bool second = false,
}) {
  p.addFrontend([
    if (withParse)
      ...parse(statement, second ? sqlB : sqlA, second ? [] : [25]),
    ...bind(portal, statement, second ? [] : [65]),
    ...describe(portal),
    ...execute(portal),
    ...wire('S'),
  ]);
}

void response(
  ProtocolProfile p, {
  bool withParse = false,
  String tx = 'T',
  String data = 'value',
}) {
  p.addBackend([
    if (withParse) ...wire('1'),
    ...wire('2'),
    ...rowDescription(),
    ...row(data),
    ...command('SELECT 1'),
    ...ready(tx),
  ]);
}

void cleanup(ProtocolProfile p, String portal, {String tx = 'T'}) {
  p.addFrontend([...close(portal), ...wire('S')]);
  p.addBackend([...wire('3'), ...ready(tx)]);
  p.drainEvents();
}

TransactionTarget target(
  ProtocolProfile p, {
  OperationIdentity op = operation,
}) => TransactionTarget(
  p.connectionGeneration,
  p.transactionGeneration,
  identity,
  op,
);
TransactionTarget arm(ProtocolProfile p, CommitMode mode) {
  p.attributeTransaction(operation);
  final t = target(p);
  p.armCommit(t, mode);
  return t;
}

Matcher refuses([Refusal? reason]) => throwsA(
  isA<ProtocolRefusal>().having(
    (e) => reason == null || e.reason == reason,
    'safe reason',
    isTrue,
  ),
);
void discarded(ProtocolProfile p) {
  expect(p.state, ConnectionState.terminal);
  expect(p.frontend.bufferedBytes + p.backend.bufferedBytes, 0);
  expect(p.frontend.queuedFrames + p.backend.queuedFrames, 0);
  expect(p.statementCount + p.portalCount + p.pendingResponses, 0);
  expect(p.hasHeldCommit, isFalse);
  expect(p.heldNextFrameCount, 0);
  expect(p.heldNextWireBytes, 0);
}

void main() {
  group('F01 ingress ownership regression', () {
    test('partial response cannot acquire a later ordinary extended owner', () {
      final p = session();
      begin(p);
      final bytes = wire('1');
      p.addBackend(bytes.sublist(0, 3));
      p.addFrontend([
        ...parse('a', sqlA, [25]),
        ...wire('S'),
      ]);
      expect(() => p.addBackend(bytes.sublist(3)), refuses(Refusal.ownership));
      discarded(p);
    });
    test(
      'fragmented asynchronous message may span an ordinary owner change',
      () {
        final p = session();
        begin(p);
        final notice = wire('N', [77, ...z('private notice'), 0]);
        p.addBackend(notice.sublist(0, 3));
        p.addFrontend([
          ...parse('a', sqlA, [25]),
          ...wire('S'),
        ]);
        p.addBackend([...notice.sublist(3), ...wire('1'), ...ready('T')]);
        expect(p.state, ConnectionState.transaction);
        expect(p.fullySettled, isTrue);
        expect(
          p
              .drainEvents()
              .where((e) => e.decision == Decision.asynchronous)
              .length,
          1,
        );
      },
    );
    final completion = command('COMMIT');
    for (var split = 1; split < completion.length; split++) {
      test(
        'review case before arm split $split of 11 refuses later ownership',
        () {
          final p = session();
          begin(p);
          p.attributeTransaction(operation);
          final t = target(p);
          p.addBackend(completion.sublist(0, split));
          expect(() {
            p.armCommit(t, CommitMode.s06WithholdCompletion);
            p.addFrontend(query('COMMIT;'));
            p.confirmCommitForwarded(t);
            p.addBackend([...completion.sublist(split), ...ready('I')]);
          }, refuses(Refusal.ownership));
          discarded(p);
        },
      );
      test(
        'review case before confirmation split $split of 11 refuses later ownership',
        () {
          final p = session();
          begin(p);
          final t = arm(p, CommitMode.s06WithholdCompletion);
          p.addFrontend(query('COMMIT;'));
          p.addBackend(completion.sublist(0, split));
          expect(() {
            p.confirmCommitForwarded(t);
            p.addBackend([...completion.sublist(split), ...ready('I')]);
          }, refuses(Refusal.ownership));
          discarded(p);
        },
      );
    }
    test('coalesced earlier Ready plus premature header is not settled', () {
      final p = session();
      p.addFrontend(query('BEGIN;'));
      p.addBackend([...command('BEGIN'), ...ready('T'), ...completion.take(1)]);
      expect(p.pendingResponses, 0);
      expect(p.fullySettled, isFalse);
      expect(
        () => p.attributeTransaction(operation),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('outstanding earlier exchange cannot become a COMMIT owner', () {
      final p = session();
      begin(p);
      p.attributeTransaction(operation);
      p.addFrontend([
        ...parse('a', sqlA, [25]),
        ...wire('S'),
      ]);
      expect(
        () => p.armCommit(target(p), CommitMode.s06WithholdCompletion),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test(
      'coalesced complete COMMIT response after confirmation remains valid',
      () {
        final p = session();
        begin(p);
        final t = arm(p, CommitMode.s06WithholdCompletion);
        p.addFrontend(query('COMMIT;'));
        p.confirmCommitForwarded(t);
        p.addBackend([...completion, ...ready('I')]);
        expect(p.state, ConnectionState.committedWithheld);
      },
    );
    test('all completion splits entirely after confirmation remain valid', () {
      for (var split = 1; split < completion.length; split++) {
        final p = session();
        begin(p);
        final t = arm(p, CommitMode.s06WithholdCompletion);
        p.addFrontend(query('COMMIT;'));
        p.confirmCommitForwarded(t);
        p.addBackend(completion.sublist(0, split));
        p.addBackend([...completion.sublist(split), ...ready('I')]);
        expect(p.state, ConnectionState.committedWithheld);
      }
    });
    test(
      'fragmented asynchronous messages retain their independent classification',
      () {
        final p = session();
        begin(p);
        final t = arm(p, CommitMode.s06WithholdCompletion);
        p.addFrontend(query('COMMIT;'));
        final notice = wire('N', [77, ...z('private notice'), 0]);
        p.addBackend(notice.sublist(0, 3));
        p.addBackend(notice.sublist(3));
        p.confirmCommitForwarded(t);
        final status = wire('S', [
          ...z('application_name'),
          ...z('private value'),
        ]);
        p.addBackend(status.sublist(0, 6));
        p.addBackend(status.sublist(6));
        expect(p.pendingResponses, 2);
        p.addBackend([...completion, ...ready('I')]);
        expect(p.state, ConnectionState.committedWithheld);
        expect('${p.drainEvents()}', isNot(contains('private')));
      },
    );
    test('premature Ready prefix cannot cross forwarding confirmation', () {
      final p = session();
      begin(p);
      final t = arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      p.addBackend(ready('I').sublist(0, 5));
      expect(() => p.confirmCommitForwarded(t), refuses(Refusal.ownership));
      discarded(p);
    });
    test('wrong backend cannot confirm forwarding', () {
      final p = session();
      begin(p);
      arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      expect(
        () => p.confirmCommitForwarded(
          TransactionTarget(
            1,
            1,
            const BackendIdentity('cluster', 'database', 41, 'stale-start'),
            operation,
          ),
        ),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('terminal cleanup scrubs an incomplete post-barrier completion', () {
      final p = session();
      begin(p);
      final t = arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      p.confirmCommitForwarded(t);
      p.addBackend(completion.sublist(0, 7));
      p.timeout();
      discarded(p);
      expect(
        () => p.addBackend(completion.sublist(7)),
        refuses(Refusal.terminated),
      );
    });
  });

  group('F02 bounded extended error recovery', () {
    List<int> tail() => [
      ...bind('p', 'a', [65]),
      ...describe('p'),
      ...execute('p'),
      ...wire('S'),
    ];
    ProtocolProfile earlyParseError({
      ProtocolLimits? limits,
      bool inTransaction = true,
    }) {
      final p = session(limits: limits);
      if (inTransaction) begin(p);
      p.addFrontend(parse('a', sqlA, [25]));
      p.addBackend(error('private error'));
      p.drainEvents();
      return p;
    }

    void recover(ProtocolProfile p, {String status = 'E'}) {
      p.addBackend(ready(status));
      expect(p.pendingResponses, 0);
      expect(p.fullySettled, isTrue);
      expect(
        p.state,
        status == 'E'
            ? ConnectionState.failedTransaction
            : ConnectionState.idle,
      );
    }

    test(
      'early Parse error accepts remaining coalesced aggregate without new objects or owners',
      () {
        final p = earlyParseError();
        expect(p.statementCount, 0);
        expect(p.portalCount, 0);
        expect(p.pendingResponses, 1);
        p.addFrontend(tail());
        expect(p.statementCount, 0);
        expect(p.portalCount, 0);
        expect(p.pendingResponses, 1);
        final discardedTail = p.drainEvents();
        expect(discardedTail.map((e) => e.decision), [
          Decision.discard,
          Decision.discard,
          Decision.discard,
          Decision.forward,
        ]);
        expect(discardedTail.every((e) => e.exchangeGeneration == 2), isTrue);
        recover(p);
        p.addFrontend(query('ROLLBACK;'));
        p.addBackend([...command('ROLLBACK'), ...ready('I')]);
        expect(p.state, ConnectionState.idle);
        begin(p);
        request(p, 'a', 'new', withParse: true);
        response(p, withParse: true);
        final nextExecution = p
            .drainEvents()
            .where((e) => e.decision == Decision.settled)
            .single;
        expect(nextExecution.portalGeneration, 1);
        cleanup(p, 'new');
        expect(p.transactionGeneration, 2);
        expect(p.fullySettled, isTrue);
      },
    );
    test(
      'fragmented Parse and Bind with early error retain one recovery owner',
      () {
        final p = session();
        begin(p);
        final bytes = parse('a', sqlA, [25]);
        for (final b in bytes) {
          p.addFrontend([b]);
        }
        final binding = bind('p', 'a', [65]);
        p.addFrontend(binding.sublist(0, 8));
        p.addBackend(error());
        p.addFrontend([
          ...binding.sublist(8),
          ...describe('p'),
          ...execute('p'),
          ...wire('S'),
        ]);
        expect(p.statementCount, 0);
        expect(p.portalCount, 0);
        recover(p);
      },
    );
    test('early Bind error discards only Describe/Execute/Flush/Sync tail', () {
      final p = session();
      begin(p);
      prepare(p, 'a');
      p.addFrontend(bind('p', 'a', [65]));
      p.addBackend(error());
      p.drainEvents();
      expect(p.statementCount, 1);
      expect(p.portalCount, 0);
      p.addFrontend([
        ...wire('H'),
        ...describe('p'),
        ...wire('H'),
        ...execute('p'),
        ...wire('S'),
      ]);
      expect(p.statementCount, 1);
      expect(p.portalCount, 0);
      expect(p.pendingResponses, 1);
      recover(p);
    });
    test('error after entire aggregate was decoded still owns Ready(E)', () {
      final p = session();
      begin(p);
      request(p, 'a', 'p', withParse: true);
      p.addBackend([...error(), ...ready('E')]);
      expect(p.state, ConnectionState.failedTransaction);
      expect(p.pendingResponses, 0);
      expect(p.statementCount + p.portalCount, 0);
    });
    test(
      'error outside explicit transaction recovers to idle only after Sync',
      () {
        final p = earlyParseError(inTransaction: false);
        p.addFrontend(tail());
        recover(p, status: 'I');
        request(p, 'a', 'new', withParse: true);
        response(p, withParse: true, tx: 'I');
        expect(p.fullySettled, isTrue);
      },
    );
    test('missing Sync cannot settle recovery', () {
      final p = earlyParseError();
      p.addFrontend([
        ...bind('p', 'a', [65]),
        ...describe('p'),
        ...execute('p'),
      ]);
      expect(() => p.addBackend(ready('E')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('partial Ready cannot acquire a later recovery Sync', () {
      final p = earlyParseError();
      p.addBackend(ready('E').sublist(0, 3));
      p.addFrontend(wire('S'));
      expect(
        () => p.addBackend(ready('E').sublist(3)),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('malformed Sync retains framing validation', () {
      final p = earlyParseError();
      expect(() => p.addFrontend(wire('S', [0])), refuses(Refusal.malformed));
      discarded(p);
    });
    for (final wrong in [
      parse('b', sqlA, [25]),
      query('COMMIT;'),
      execute('wrong'),
      bind('p', 'other', [65]),
      bind('p', 'a'),
      describe('p'),
    ]) {
      test(
        'contradictory supported recovery tail ${wrong[0]} ${wrong.length} refuses',
        () {
          final p = earlyParseError();
          expect(() => p.addFrontend(wrong), refuses());
          discarded(p);
        },
      );
    }
    test('unsupported message still refuses during recovery', () {
      final p = earlyParseError();
      expect(() => p.addFrontend(wire('?')), refuses(Refusal.unsupported));
      discarded(p);
    });
    test('duplicate Bind cannot bypass the recovery grammar', () {
      final p = earlyParseError();
      p.addFrontend(bind('p', 'a', [65]));
      expect(
        () => p.addFrontend(bind('p', 'a', [65])),
        refuses(Refusal.sequence),
      );
      discarded(p);
    });
    test('extra message after recovery Sync is refused before Ready', () {
      final p = earlyParseError();
      p.addFrontend(tail());
      expect(() => p.addFrontend(wire('H')), refuses(Refusal.sequence));
      discarded(p);
    });
    test('Ready(T) cannot rescue a failed transaction', () {
      final p = earlyParseError();
      p.addFrontend(tail());
      expect(() => p.addBackend(ready('T')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('discard mode frame-count bound survives event draining', () {
      final p = earlyParseError(limits: ProtocolLimits(maxQueuedFrames: 4));
      for (var i = 0; i < 4; i++) {
        p.addFrontend(wire('H'));
        p.drainEvents();
      }
      expect(() => p.addFrontend(wire('H')), refuses(Refusal.resourceLimit));
      discarded(p);
    });
    test('discard mode aggregate-byte budget survives fragmented calls', () {
      final p = earlyParseError(
        limits: ProtocolLimits(maxFrameBytes: 128, maxBufferedBytes: 128),
      );
      for (var i = 0; i < 25; i++) {
        p.addFrontend(wire('H'));
        p.drainEvents();
      }
      expect(() => p.addFrontend(wire('H')), refuses(Refusal.resourceLimit));
      discarded(p);
    });
    test(
      'malformed Bind still validates parameter lengths in discard mode',
      () {
        final p = earlyParseError();
        expect(
          () => p.addFrontend(
            wire('B', [
              ...z('p'),
              ...z('a'),
              ...u16(0),
              ...u16(1),
              ...u32(-2),
              ...u16(0),
            ]),
          ),
          refuses(Refusal.malformed),
        );
        discarded(p);
      },
    );
    test('armed S05 and S06 errors remain terminal', () {
      for (final mode in CommitMode.values) {
        final p = session();
        begin(p);
        final t = arm(p, mode);
        p.addFrontend(query('COMMIT;'));
        if (mode == CommitMode.s06WithholdCompletion) {
          p.confirmCommitForwarded(t);
        }
        expect(
          () => p.addBackend(error('private armed error')),
          refuses(Refusal.backendError),
        );
        discarded(p);
        expect(() => p.addFrontend(wire('S')), refuses(Refusal.terminated));
      }
    });
    test(
      'EOF during discarded partial Bind scrubs buffers and recovery state',
      () {
        final p = earlyParseError();
        p.addFrontend(bind('p', 'a', [65]).sublist(0, 8));
        p.eof();
        discarded(p);
        expect('${p.drainEvents()}', isNot(contains('private')));
      },
    );
  });

  group('bounded wire framing', () {
    test('startup protocol 3.0, no startup values retained', () {
      final f = ProtocolFramer(
        direction: Direction.frontend,
        limits: ProtocolLimits(),
        startup: true,
      );
      f.add(startup());
      final frame = f.take()!;
      expect(frame.kind, FrameKind.startup);
      expect(frame.wireBytes, startup().length);
      expect('$frame', isNot(contains('synthetic_user')));
      expect(f.bufferedBytes, 0);
    });
    for (final entry in {
      80877103: FrameKind.sslRequest,
      80877104: FrameKind.gssRequest,
    }.entries) {
      test('${entry.value} classified then refused without downgrade', () {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          startup: true,
        );
        f.add(packet(u32(entry.key)));
        expect(f.take()!.kind, entry.value);
        final p = ProtocolProfile(
          connectionGeneration: 1,
          limits: ProtocolLimits(),
        );
        expect(
          () => p.addFrontend(packet(u32(entry.key))),
          refuses(Refusal.unsupported),
        );
        discarded(p);
      });
    }
    test('every possible split in startup, including length header', () {
      final bytes = startup();
      for (var split = 0; split <= bytes.length; split++) {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          startup: true,
        );
        f.add(bytes.sublist(0, split));
        f.add(bytes.sublist(split));
        expect(f.take()!.kind, FrameKind.startup);
        expect(f.take(), isNull);
        expect(f.bufferedBytes, 0);
      }
    });
    test('every possible split in typed frame; no partial output', () {
      final bytes = query('COMMIT;');
      for (var split = 0; split < bytes.length; split++) {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
        );
        f.add(bytes.sublist(0, split));
        expect(f.take(), isNull);
        f.add(bytes.sublist(split));
        expect(f.take()!.control, Control.commit);
      }
    });
    test('coalesced frontend and backend frames preserve order', () {
      final f = ProtocolFramer(
        direction: Direction.frontend,
        limits: ProtocolLimits(),
      );
      f.add([...wire('H'), ...wire('S')]);
      expect(
        [f.take()!.kind, f.take()!.kind],
        [FrameKind.flush, FrameKind.sync],
      );
      final b = ProtocolFramer(
        direction: Direction.backend,
        limits: ProtocolLimits(),
      );
      b.add([...command('COMMIT'), ...ready('I')]);
      expect(
        [b.take()!.kind, b.take()!.kind],
        [FrameKind.commandComplete, FrameKind.ready],
      );
    });
    for (final length in [0, 1, 3, 0x80000000, 0xffffffff, 129]) {
      test('typed length $length rejected before body allocation', () {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(maxFrameBytes: 128, maxBufferedBytes: 128),
        );
        expect(() => f.add([81, ...u32(length)]), refuses(Refusal.length));
        expect(f.peakBufferedBytes, 0);
        expect(f.bufferedBytes, 0);
        expect(f.terminal, isTrue);
      });
    }
    for (final length in [0, 7, 0x80000000, 0xffffffff, 129]) {
      test('startup length $length refused before allocation', () {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          startup: true,
          limits: ProtocolLimits(maxFrameBytes: 128, maxBufferedBytes: 128),
        );
        expect(() => f.add(u32(length)), refuses(Refusal.length));
        expect(f.peakBufferedBytes, 0);
      });
    }
    for (final direction in Direction.values) {
      test('unknown ${direction.name} type rejected at header', () {
        final f = ProtocolFramer(
          direction: direction,
          limits: ProtocolLimits(),
        );
        expect(() => f.add(wire('?')), refuses(Refusal.unsupported));
        expect(f.peakBufferedBytes, 0);
      });
    }
    test('bounded queue discards even earlier complete queued frames', () {
      final f = ProtocolFramer(
        direction: Direction.frontend,
        limits: ProtocolLimits(maxQueuedFrames: 1),
      );
      expect(
        () => f.add([...wire('H'), ...wire('S')]),
        refuses(Refusal.resourceLimit),
      );
      expect(f.queuedFrames, 0);
      expect(f.bufferedBytes, 0);
      expect(() => f.add(wire('S')), refuses(Refusal.terminated));
    });
    test('frame exactly at configured limit is accepted', () {
      final frame = wire('p', List<int>.filled(123, 42));
      final f = ProtocolFramer(
        direction: Direction.frontend,
        limits: ProtocolLimits(maxFrameBytes: 128, maxBufferedBytes: 128),
      );
      f.add(frame);
      expect(f.take()!.wireBytes, 128);
      expect(f.peakBufferedBytes, 128);
    });
    test(
      'malformed byte, truncated cstring, trailing bytes and null lengths refuse',
      () {
        for (final bytes in [
          [256],
          wire('Q', 'COMMIT;'.codeUnits),
          wire('S', [0]),
          wire('B', [
            ...z(''),
            ...z(''),
            ...u16(0),
            ...u16(1),
            ...u32(-2),
            ...u16(0),
          ]),
        ]) {
          final f = ProtocolFramer(
            direction: Direction.frontend,
            limits: ProtocolLimits(),
          );
          expect(() => f.add(bytes), refuses());
          expect(f.bufferedBytes, 0);
        }
      },
    );
    test('startup unknown version, replication and non-UTF8 rejected', () {
      for (final bytes in [
        packet(u32(196609)),
        packet([...u32(196608), ...z('replication'), ...z('database'), 0]),
        packet([...u32(196608), ...z('client_encoding'), ...z('LATIN1'), 0]),
      ]) {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          startup: true,
        );
        expect(() => f.add(bytes), refuses());
      }
    });
    test('unbounded catalogue generator stops at the configured ceiling', () {
      var produced = 0;
      Iterable<StatementSpec> entries() sync* {
        while (true) {
          produced++;
          yield specA();
        }
      }

      expect(
        () => ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(maxCatalogueEntries: 2),
          catalogue: entries(),
        ),
        throwsArgumentError,
      );
      expect(produced, 3);
    });
    test('unsafe limits and ambiguous catalogue refused', () {
      expect(() => ProtocolLimits(maxQueuedFrames: 0), throwsArgumentError);
      expect(
        () => ProtocolLimits(maxFrameBytes: 256, maxBufferedBytes: 128),
        throwsArgumentError,
      );
      expect(
        () => ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          catalogue: [specA(), specA()],
        ),
        throwsArgumentError,
      );
    });
  });

  group('startup authentication and cancellation separation', () {
    test('no transaction admission before independent backend binding', () {
      final p = ProtocolProfile(
        connectionGeneration: 1,
        limits: ProtocolLimits(),
        authentication: AuthenticationMode.trust,
      );
      p.addFrontend(startup());
      p.addBackend([
        ...wire('R', u32(0)),
        ...wire('K', [...u32(41), ...u32(123)]),
        ...ready('I'),
      ]);
      expect(p.state, ConnectionState.startup);
      expect(() => p.addFrontend(query('BEGIN;')), refuses());
      discarded(p);
    });
    test('wrong backend/start identity cannot arm target', () {
      final p = session();
      begin(p);
      p.attributeTransaction(operation);
      expect(
        () => p.armCommit(
          TransactionTarget(
            1,
            1,
            const BackendIdentity(
              'cluster',
              'database',
              41,
              'reused-pid-new-start',
            ),
            operation,
          ),
          CommitMode.s05Hold,
        ),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('SCRAM finite handshake, opaque payloads never appear in events', () {
      final p = ProtocolProfile(
        connectionGeneration: 1,
        limits: ProtocolLimits(),
      );
      p.addFrontend(startup());
      p.addBackend(wire('R', [...u32(10), ...z('SCRAM-SHA-256'), 0]));
      p.addFrontend(
        wire('p', [...z('SCRAM-SHA-256'), ...u32(6), ...'secret'.codeUnits]),
      );
      p.addBackend(wire('R', [...u32(11), ...'server-secret'.codeUnits]));
      p.addFrontend(wire('p', 'client-secret'.codeUnits));
      p.addBackend([
        ...wire('R', [...u32(12), ...'proof-secret'.codeUnits]),
        ...wire('R', u32(0)),
        ...wire('K', [...u32(41), ...u32(987654)]),
        ...ready('I'),
      ]);
      p.bindBackendIdentity(identity);
      expect(p.state, ConnectionState.idle);
      expect('${p.drainEvents()}', isNot(contains('secret')));
    });
    test('default SCRAM never falls back to trust', () {
      final p = ProtocolProfile(
        connectionGeneration: 1,
        limits: ProtocolLimits(),
      );
      p.addFrontend(startup());
      expect(() => p.addBackend(wire('R', u32(0))), refuses());
      discarded(p);
    });
    test('unsupported client SASL mechanism fails closed', () {
      final p = ProtocolProfile(
        connectionGeneration: 1,
        limits: ProtocolLimits(),
      );
      p.addFrontend(startup());
      p.addBackend(wire('R', [...u32(10), ...z('SCRAM-SHA-256'), 0]));
      expect(
        () => p.addFrontend(
          wire('p', [...z('PLAIN'), ...u32(6), ...'secret'.codeUnits]),
        ),
        refuses(),
      );
      discarded(p);
    });
    test(
      'cancel request is separate, carries no key and consumes no application owner',
      () {
        final p = session();
        begin(p);
        request(p, 'a', 'p', withParse: true);
        final pending = p.pendingResponses;
        final c = ProtocolProfile(
          connectionGeneration: 2,
          limits: ProtocolLimits(),
        );
        final bytes = packet([...u32(80877102), ...u32(41), ...u32(987654)]);
        c.addFrontend(bytes);
        expect(c.state, ConnectionState.cancellation);
        expect(c.pendingResponses, 0);
        expect(c.transactionGeneration, 0);
        expect(c.drainEvents().single.decision, Decision.cancel);
        expect(p.pendingResponses, pending);
        expect(() => c.addBackend(ready('I')), refuses());
        discarded(c);
      },
    );
    test(
      'cancel on an existing application connection is not a transaction message',
      () {
        final p = session();
        expect(
          () =>
              p.addFrontend(packet([...u32(80877102), ...u32(41), ...u32(1)])),
          refuses(),
        );
        discarded(p);
      },
    );
  });

  group('statement, portal and response ownership', () {
    test(
      'generation allocated only after complete successful BEGIN/Ready(T)',
      () {
        final p = session();
        p.addFrontend(query('BEGIN;'));
        p.addBackend(command('BEGIN'));
        expect(p.transactionGeneration, 0);
        p.addBackend(ready('T'));
        expect(p.transactionGeneration, 1);
        p.addFrontend(query('ROLLBACK;'));
        p.addBackend([...command('ROLLBACK'), ...ready('I')]);
        begin(p);
        expect(p.transactionGeneration, 2);
        final generations = ConnectionGenerations();
        expect([generations.next(), generations.next()], [1, 2]);
      },
    );
    test(
      'Parse/Bind/Describe/Execute owns exact statement and portal generations',
      () {
        final p = session();
        begin(p);
        request(p, 'a', 'p', withParse: true);
        response(p, withParse: true);
        final settled = p
            .drainEvents()
            .where((e) => e.decision == Decision.settled)
            .single;
        expect(settled.transactionGeneration, 1);
        expect(settled.statementGeneration, 1);
        expect(settled.portalGeneration, 1);
        expect(settled.exchangeGeneration, 2);
        expect(p.fullySettled, isFalse);
        cleanup(p, 'p');
        expect(p.fullySettled, isTrue);
        expect(p.portalCount, 0);
        expect(p.statementCount, 1);
      },
    );
    test('coalesced frontend exchange, bytewise backend response', () {
      final p = session();
      begin(p);
      request(p, 'a', 'p', withParse: true);
      final bytes = [
        ...wire('1'),
        ...wire('2'),
        ...rowDescription(),
        ...row('value'),
        ...command('SELECT 1'),
        ...ready('T'),
      ];
      for (final b in bytes) {
        p.addBackend([b]);
      }
      expect(p.pendingResponses, 0);
      expect(p.state, ConnectionState.transaction);
    });
    test(
      'named statement persists across transaction; autocommit portal expires',
      () {
        final p = session();
        prepare(p, 'a');
        request(p, 'a', 'p');
        response(p, tx: 'I');
        expect(p.portalCount, 0);
        expect(p.fullySettled, isTrue);
        begin(p);
        expect(p.statementCount, 1);
        request(p, 'a', 'p2');
        response(p);
        cleanup(p, 'p2');
        p.addFrontend([...close('a', portal: false), ...wire('S')]);
        expect(p.statementCount, 1);
        p.addBackend(wire('3'));
        expect(p.statementCount, 0);
        expect(p.pendingResponses, 1);
        p.addBackend(ready('T'));
        expect(p.fullySettled, isTrue);
      },
    );
    test(
      'unnamed Parse replaces statement but cannot retarget existing portal',
      () {
        final p = session();
        begin(p);
        request(p, '', '', withParse: true);
        response(p, withParse: true);
        p.drainEvents();
        prepare(p, '', second: true);
        p.addFrontend([...describe('', portal: false), ...wire('S')]);
        p.addBackend([
          ...wire('t', u16(0)),
          ...rowDescription(),
          ...ready('T'),
        ]);
        final described = p
            .drainEvents()
            .where((e) => e.decision == Decision.settled)
            .single;
        expect(described.statementGeneration, 2);
        p.addFrontend([...close(''), ...wire('S')]);
        p.addBackend([...wire('3'), ...ready('T')]);
        final closed = p
            .drainEvents()
            .where((e) => e.decision == Decision.settled)
            .single;
        expect(closed.statementGeneration, 1);
        expect(closed.portalGeneration, 1);
        request(p, '', 'new', second: true);
        response(p);
        cleanup(p, 'new');
        p.addFrontend(query('COMMIT;'));
        p.addBackend([...command('COMMIT'), ...ready('I')]);
        expect(p.statementCount, 0);
      },
    );
    test('replacing occupied named statement refuses', () {
      final p = session();
      prepare(p, 'a');
      expect(() => prepare(p, 'a'), refuses(Refusal.sequence));
      discarded(p);
    });
    test('Bind cannot use missing or foreign statement', () {
      final p = session();
      expect(
        () => p.addFrontend(bind('p', 'missing')),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('Parse A followed by Bind B is not misassociated', () {
      final p = session();
      prepare(p, 'b', second: true);
      expect(
        () => p.addFrontend([
          ...parse('a', sqlA, [25]),
          ...bind('p', 'b'),
        ]),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('wrong parameter count/OID never accepted', () {
      final p = session();
      expect(() => p.addFrontend(parse('a', sqlA, [23])), refuses());
      discarded(p);
      final q = session();
      prepare(q, 'a');
      expect(() => q.addFrontend(bind('p', 'a')), refuses());
      discarded(q);
    });
    test('response order cannot skip ParseComplete', () {
      final p = session();
      request(p, 'a', 'p', withParse: true);
      expect(() => p.addBackend(wire('2')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('Execute must reference the exact described portal', () {
      final p = session();
      prepare(p, 'a');
      p.addFrontend([
        ...bind('p', 'a', [65]),
        ...describe('p'),
      ]);
      expect(
        () => p.addFrontend(execute('different')),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('Execute(maxRows>0) and PortalSuspended are unsupported', () {
      final p = session();
      prepare(p, 'a');
      p.addFrontend([
        ...bind('p', 'a', [65]),
        ...describe('p'),
      ]);
      expect(
        () => p.addFrontend(execute('p', maxRows: 1)),
        refuses(Refusal.unsupported),
      );
      discarded(p);
      final q = session();
      request(q, 'a', 'p', withParse: true);
      expect(() => q.addBackend(wire('s')), refuses(Refusal.unsupported));
      discarded(q);
    });
    test('Flush does not settle; responses may precede Sync', () {
      final p = session();
      p.addFrontend([
        ...parse('a', sqlA, [25]),
        ...wire('H'),
      ]);
      p.addBackend(wire('1'));
      expect(p.fullySettled, isFalse);
      p.addFrontend(wire('S'));
      p.addBackend(ready('I'));
      expect(p.fullySettled, isTrue);
    });
    test('Ready without Sync cannot settle a flushed exchange', () {
      final p = session();
      p.addFrontend([
        ...parse('a', sqlA, [25]),
        ...wire('H'),
      ]);
      p.addBackend(wire('1'));
      expect(() => p.addBackend(ready('I')), refuses());
      discarded(p);
    });
    test('pipeline and second response ownership refuse', () {
      final p = session();
      p.addFrontend(query('BEGIN;'));
      expect(() => p.addFrontend(query('COMMIT;')), refuses());
      discarded(p);
      final q = session();
      expect(() => q.addBackend(command('COMMIT')), refuses(Refusal.ownership));
      discarded(q);
    });
    test('close cannot settle before CloseComplete and Ready', () {
      final p = session();
      prepare(p, 'a');
      p.addFrontend([...close('a', portal: false), ...wire('S')]);
      expect(() => p.addBackend(ready('I')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('Ready I/T/E are distinct; wrong state refuses', () {
      final p = session();
      p.addFrontend(query('BEGIN;'));
      p.addBackend(command('BEGIN'));
      expect(() => p.addBackend(ready('I')), refuses(Refusal.ownership));
      discarded(p);
      final q = session();
      begin(q);
      prepare(q, 'a');
      request(q, 'a', 'p');
      q.addBackend([
        ...wire('2'),
        ...rowDescription(),
        ...error('secret'),
        ...ready('E'),
      ]);
      expect(q.state, ConnectionState.failedTransaction);
      expect(q.pendingResponses, 0);
      q.addFrontend(query('ROLLBACK;'));
      q.addBackend([...command('ROLLBACK'), ...ready('I')]);
      expect(q.state, ConnectionState.idle);
    });
    test('failed transaction cannot arm COMMIT', () {
      final p = session();
      begin(p);
      request(p, 'a', 'p', withParse: true);
      p.addBackend([...error(), ...ready('E')]);
      expect(
        () => p.armCommit(target(p), CommitMode.s05Hold),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('error before Sync drains only to supported Sync/Ready', () {
      final p = session();
      begin(p);
      p.addFrontend(parse('a', sqlA, [25]));
      p.addBackend(error());
      p.addFrontend(wire('S'));
      p.addBackend(ready('E'));
      expect(p.state, ConnectionState.failedTransaction);
      expect(p.statementCount, 0);
    });
    test(
      'asynchronous messages consume no owner, preserve response sequence',
      () {
        final p = session();
        begin(p);
        request(p, 'a', 'p', withParse: true);
        final debt = p.pendingResponses;
        p.addBackend([
          ...wire('N', [77, ...z('secret'), 0]),
          ...wire('S', [...z('application_name'), ...z('secret')]),
          ...wire('A', [...u32(41), ...z('channel'), ...z('secret')]),
        ]);
        expect(p.pendingResponses, debt);
        expect(
          p
              .drainEvents()
              .where((e) => e.decision == Decision.asynchronous)
              .length,
          3,
        );
        response(p, withParse: true);
        expect(p.pendingResponses, 0);
      },
    );
  });

  group('complete COMMIT targeting and terminal containment', () {
    test(
      'HELD_NEXT retains the selected full extended exchange through Sync',
      () {
        final p = session();
        begin(p);
        p.attributeTransaction(operation);
        p.armNextExchange(target(p));
        final frames = [
          parse('a', sqlA, [25]),
          bind('p', 'a', [65]),
          describe('p'),
          execute('p'),
          wire('H'),
          wire('S'),
        ];
        for (final frame in frames.take(5)) {
          p.addFrontend(frame);
        }
        expect(p.state, ConnectionState.holdingNext);
        expect(p.heldNextFrameCount, 5);
        p.addFrontend(frames.last.sublist(0, 4));
        expect(p.state, ConnectionState.holdingNext);
        p.addFrontend([frames.last.last]);
        expect(p.state, ConnectionState.heldNext);
        expect(
          p.heldNextWireBytes,
          frames.fold<int>(0, (n, f) => n + f.length),
        );
        final events = p.drainEvents();
        expect(events.map((e) => e.decision), [
          for (var i = 0; i < 6; i++) Decision.holdNextFrame,
          Decision.heldNext,
        ]);
        expect(events.every((e) => e.transactionGeneration == 1), isTrue);
        p.timeout();
        discarded(p);
      },
    );
    test('HELD_NEXT refuses backend responses for an unforwarded exchange', () {
      final p = session();
      begin(p);
      p.attributeTransaction(operation);
      p.armNextExchange(target(p));
      p.addFrontend(parse('a', sqlA, [25]));
      expect(() => p.addBackend(wire('1')), refuses(Refusal.sequence));
      discarded(p);
    });
    test(
      'HELD_NEXT aggregate bytes and frame count are separately bounded',
      () {
        final p = session(
          limits: ProtocolLimits(maxFrameBytes: 128, maxBufferedBytes: 128),
        );
        begin(p);
        p.attributeTransaction(operation);
        p.armNextExchange(target(p));
        p.addFrontend(parse('a', sqlA, [25]));
        p.addFrontend(
          wire('B', [
            ...z('p'),
            ...z('a'),
            ...u16(0),
            ...u16(1),
            ...u32(80),
            ...List<int>.filled(80, 65),
            ...u16(0),
          ]),
        );
        expect(
          () => p.addFrontend(describe('p')),
          refuses(Refusal.resourceLimit),
        );
        discarded(p);
        final q = session(limits: ProtocolLimits(maxQueuedFrames: 4));
        begin(q);
        q.attributeTransaction(operation);
        q.armNextExchange(target(q));
        for (final frame in [
          parse('a', sqlA, [25]),
          bind('p', 'a', [65]),
          describe('p'),
          execute('p'),
        ]) {
          q.addFrontend(frame);
        }
        expect(() => q.addFrontend(wire('S')), refuses(Refusal.resourceLimit));
        discarded(q);
      },
    );
    test(
      'HELD_NEXT cannot substitute Parse-only preparation for execution',
      () {
        final p = session();
        begin(p);
        p.attributeTransaction(operation);
        p.armNextExchange(target(p));
        p.addFrontend(parse('a', sqlA, [25]));
        expect(() => p.addFrontend(wire('S')), refuses(Refusal.unsupported));
        discarded(p);
      },
    );
    test('HELD_NEXT refuses wrong transaction before retaining any frame', () {
      final p = session();
      begin(p);
      p.attributeTransaction(operation);
      expect(
        () => p.armNextExchange(
          const TransactionTarget(1, 2, identity, operation),
        ),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test(
      'S05 holds the whole exact frame, including fragmented header/body',
      () {
        final p = session();
        begin(p);
        arm(p, CommitMode.s05Hold);
        final bytes = query('COMMIT;');
        for (var i = 0; i < bytes.length - 1; i++) {
          p.addFrontend([bytes[i]]);
        }
        expect(p.hasHeldCommit, isFalse);
        expect(p.drainEvents(), isEmpty);
        p.addFrontend([bytes.last]);
        expect(p.state, ConnectionState.heldCommit);
        expect(p.heldCommitBytes, bytes);
        expect(p.authorizedCommitBytes, 0);
        expect(p.drainEvents().single.decision, Decision.holdCommit);
        expect(() => p.confirmCommitForwarded(target(p)), refuses());
        discarded(p);
      },
    );
    test(
      'S06 installs gate before forwarding; withholds only owned complete completion',
      () {
        final p = session();
        begin(p);
        final t = arm(p, CommitMode.s06WithholdCompletion);
        p.addFrontend(query('COMMIT;'));
        expect(p.responseGateInstalled, isTrue);
        expect(p.authorizedCommitBytes, 0);
        expect(p.drainEvents().single.decision, Decision.forwardCommit);
        p.confirmCommitForwarded(t);
        expect(p.authorizedCommitBytes, 13);
        final completion = command('COMMIT');
        p.addBackend(completion.sublist(0, completion.length - 1));
        expect(p.drainEvents(), isEmpty);
        p.addBackend([completion.last]);
        expect(p.drainEvents().single.decision, Decision.withhold);
        expect(p.state, ConnectionState.commitGated);
        p.addBackend(ready('I'));
        final events = p.drainEvents();
        expect(events.map((e) => e.decision), [
          Decision.withhold,
          Decision.settled,
        ]);
        expect(
          events.every(
            (e) => e.exchangeGeneration == 2 && e.transactionGeneration == 1,
          ),
          isTrue,
        );
        expect(p.state, ConnectionState.committedWithheld);
        p.timeout();
        discarded(p);
      },
    );
    test('S06 response before confirmed single forwarding refuses', () {
      final p = session();
      begin(p);
      arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      expect(() => p.addBackend(command('COMMIT')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('S06 duplicate forwarding confirmation refuses', () {
      final p = session();
      begin(p);
      final t = arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      p.confirmCommitForwarded(t);
      expect(() => p.confirmCommitForwarded(t), refuses(Refusal.ownership));
      discarded(p);
    });
    for (final malformed in [
      command('ROLLBACK'),
      ready('I'),
      error(),
      wire('D', u16(0)),
    ]) {
      test(
        'S06 rejects non-COMMIT or out-of-order completion ${malformed[0]}',
        () {
          final p = session();
          begin(p);
          final t = arm(p, CommitMode.s06WithholdCompletion);
          p.addFrontend(query('COMMIT;'));
          p.confirmCommitForwarded(t);
          expect(() => p.addBackend(malformed), refuses());
          discarded(p);
        },
      );
    }
    test('S06 correct tag with Ready(T) cannot establish committed idle', () {
      final p = session();
      begin(p);
      final t = arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      p.confirmCommitForwarded(t);
      p.addBackend(command('COMMIT'));
      expect(() => p.addBackend(ready('T')), refuses(Refusal.ownership));
      discarded(p);
    });
    test(
      'wrong connection, transaction, operation or backend target refuses',
      () {
        for (final wrong in [
          const TransactionTarget(2, 1, identity, operation),
          const TransactionTarget(1, 2, identity, operation),
          const TransactionTarget(
            1,
            1,
            identity,
            OperationIdentity(
              'run',
              'S05',
              1,
              'duplicate',
              'W',
              command: commandIdentity,
            ),
          ),
          const TransactionTarget(
            1,
            1,
            BackendIdentity('other', 'database', 41, 'start-1'),
            operation,
          ),
        ]) {
          final p = session();
          begin(p);
          p.attributeTransaction(operation);
          expect(
            () => p.armCommit(wrong, CommitMode.s05Hold),
            refuses(Refusal.ownership),
          );
          discarded(p);
        }
      },
    );
    test('same connection later transaction does not inherit target', () {
      final p = session();
      begin(p);
      final old = target(p);
      p.addFrontend(query('COMMIT;'));
      p.addBackend([...command('COMMIT'), ...ready('I')]);
      begin(p);
      p.attributeTransaction(operation);
      expect(
        () => p.armCommit(old, CommitMode.s05Hold),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('no arming while portal cleanup or statement response remains', () {
      final p = session();
      begin(p);
      p.attributeTransaction(operation);
      request(p, 'a', 'p', withParse: true);
      response(p, withParse: true);
      expect(
        () => p.armCommit(target(p), CommitMode.s05Hold),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('plaintext COMMIT in Bind or DataRow cannot become a command', () {
      final p = session();
      begin(p);
      p.addFrontend([
        ...parse('a', sqlA, [25]),
        ...wire('B', [
          ...z('p'),
          ...z('a'),
          ...u16(0),
          ...u16(1),
          ...u32(7),
          ...'COMMIT;'.codeUnits,
          ...u16(0),
        ]),
        ...describe('p'),
        ...execute('p'),
        ...wire('S'),
      ]);
      response(p, withParse: true, data: 'COMMIT;');
      expect(p.state, ConnectionState.transaction);
      expect(p.hasHeldCommit, isFalse);
      expect(
        p.drainEvents().any(
          (e) =>
              e.decision == Decision.holdCommit ||
              e.decision == Decision.forwardCommit,
        ),
        isFalse,
      );
    });
    for (final sql in [
      'SELECT \'COMMIT;\';',
      '-- COMMIT;\nSELECT 1;',
      'COMMIT; SELECT 1;',
      'commit;',
      ' COMMIT;',
    ]) {
      test(
        'no substring/whitespace/case guessing for ${sql.length}-byte query',
        () {
          final p = session();
          begin(p);
          arm(p, CommitMode.s05Hold);
          expect(() => p.addFrontend(query(sql)), refuses(Refusal.unsupported));
          discarded(p);
        },
      );
    }
    test('COMMIT in an allowlisted Parse is still an extended statement', () {
      final spec = StatementSpec(
        id: 'literal',
        sql: "SELECT 'COMMIT;'",
        parameterOids: [],
        completionTag: 'SELECT 1',
      );
      final f = ProtocolFramer(
        direction: Direction.frontend,
        limits: ProtocolLimits(),
        catalogue: [spec],
      );
      f.add(parse('', "SELECT 'COMMIT;'"));
      final frame = f.take()!;
      expect(frame.kind, FrameKind.parse);
      expect(frame.control, isNull);
    });
    for (final end in ['timeout', 'eof', 'transportError', 'Terminate']) {
      test(
        '$end discards held COMMIT, pending bytes, objects and queued decisions',
        () {
          final p = session();
          begin(p);
          prepare(p, 'a');
          arm(p, CommitMode.s05Hold);
          p.addFrontend(query('COMMIT;'));
          if (end == 'timeout') {
            p.timeout();
          } else if (end == 'eof') {
            p.eof();
          } else if (end == 'transportError') {
            p.transportError();
          } else {
            expect(() => p.addFrontend(wire('X')), refuses(Refusal.terminated));
          }
          discarded(p);
          final originalReason = p.terminalReason;
          p.timeout();
          expect(p.terminalReason, originalReason);
          expect(
            () => p.addFrontend(query('COMMIT;')),
            refuses(Refusal.terminated),
          );
          expect(p.drainEvents().single.decision, Decision.terminal);
        },
      );
    }
    test(
      'notification invalidates an armed target without consuming ownership',
      () {
        final p = session();
        begin(p);
        arm(p, CommitMode.s05Hold);
        expect(
          () =>
              p.addBackend(wire('A', [...u32(41), ...z('x'), ...z('secret')])),
          refuses(Refusal.unsupported),
        );
        discarded(p);
      },
    );
  });

  group('resource ceilings and privacy negative controls', () {
    test(
      'consecutive unnamed autocommit executions need no invented Close',
      () {
        final p = session();
        for (var i = 0; i < 3; i++) {
          request(p, '', 'p/$i', withParse: true);
          response(p, withParse: true, tx: 'I');
          expect(p.fullySettled, isTrue);
          expect(p.portalCount, 0);
          p.drainEvents();
        }
        expect(p.statementCount, 1);
      },
    );
    test(
      'scoped command, version and frozen specimen are part of exact target',
      () {
        for (final wrong in [
          const CommandIdentity(
            company: 'other',
            location: 'location',
            resource: 'swap-request',
            operationId: 'approval-operation',
            expectedVersion: 3,
            frozenPayloadId: 'reviewed-command-specimen',
          ),
          const CommandIdentity(
            company: 'company',
            location: 'other',
            resource: 'swap-request',
            operationId: 'approval-operation',
            expectedVersion: 3,
            frozenPayloadId: 'reviewed-command-specimen',
          ),
          const CommandIdentity(
            company: 'company',
            location: 'location',
            resource: 'other',
            operationId: 'approval-operation',
            expectedVersion: 3,
            frozenPayloadId: 'reviewed-command-specimen',
          ),
          const CommandIdentity(
            company: 'company',
            location: 'location',
            resource: 'swap-request',
            operationId: 'other',
            expectedVersion: 3,
            frozenPayloadId: 'reviewed-command-specimen',
          ),
          const CommandIdentity(
            company: 'company',
            location: 'location',
            resource: 'swap-request',
            operationId: 'approval-operation',
            expectedVersion: 4,
            frozenPayloadId: 'reviewed-command-specimen',
          ),
          const CommandIdentity(
            company: 'company',
            location: 'location',
            resource: 'swap-request',
            operationId: 'approval-operation',
            expectedVersion: 3,
            frozenPayloadId: 'other',
          ),
        ]) {
          final p = session();
          begin(p);
          p.attributeTransaction(operation);
          final other = OperationIdentity(
            'run',
            'S05',
            1,
            'attempt',
            'W',
            command: wrong,
          );
          expect(
            () => p.armCommit(target(p, op: other), CommitMode.s05Hold),
            refuses(Refusal.ownership),
          );
          discarded(p);
        }
      },
    );
    test('S06 wrong write target is refused even after gate installation', () {
      final p = session();
      begin(p);
      arm(p, CommitMode.s06WithholdCompletion);
      p.addFrontend(query('COMMIT;'));
      expect(
        () => p.confirmCommitForwarded(
          const TransactionTarget(1, 2, identity, operation),
        ),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test('error after target arming clears prior objects and decisions', () {
      final p = session();
      begin(p);
      prepare(p, 'a');
      arm(p, CommitMode.s05Hold);
      expect(
        () => p.addBackend(error('private detail')),
        refuses(Refusal.backendError),
      );
      discarded(p);
    });
    test('EOF discards incomplete body and incomplete header', () {
      for (final length in [2, 8]) {
        final p = session();
        begin(p);
        p.addFrontend(query('COMMIT;').sublist(0, length));
        expect(p.frontend.bufferedBytes, length);
        p.eof();
        discarded(p);
      }
    });
    test('duplicate or unsolicited completions cannot be reassigned', () {
      final p = session();
      begin(p);
      prepare(p, 'a');
      expect(() => p.addBackend(wire('1')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('NoData supports a bounded DML execution, DataRow then refuses', () {
      void update(ProtocolProfile p) => p.addFrontend([
        ...parse('c', sqlC),
        ...bind('p', 'c'),
        ...describe('p'),
        ...execute('p'),
        ...wire('S'),
      ]);
      final p = session();
      begin(p);
      update(p);
      p.addBackend([
        ...wire('1'),
        ...wire('2'),
        ...wire('n'),
        ...command('UPDATE 1'),
        ...ready('T'),
      ]);
      cleanup(p, 'p');
      final q = session();
      begin(q);
      update(q);
      q.addBackend([...wire('1'), ...wire('2'), ...wire('n')]);
      expect(() => q.addBackend(row('COMMIT;')), refuses());
      discarded(q);
    });
    test('NoData cannot replace the declared SELECT result description', () {
      final p = session();
      begin(p);
      request(p, 'a', 'p', withParse: true);
      p.addBackend([...wire('1'), ...wire('2')]);
      expect(() => p.addBackend(wire('n')), refuses(Refusal.ownership));
      discarded(p);
    });
    test('closing stale portal after transaction end is refused', () {
      final p = session();
      request(p, 'a', 'p', withParse: true);
      response(p, withParse: true, tx: 'I');
      expect(
        () => p.addFrontend([...close('p'), ...wire('S')]),
        refuses(Refusal.ownership),
      );
      discarded(p);
    });
    test(
      'invalid UTF8 identifiers and malformed error fields stay sanitized',
      () {
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          catalogue: [specA()],
        );
        expect(
          () => f.add(wire('P', [255, 0, ...z(sqlA), ...u16(1), ...u32(25)])),
          refuses(Refusal.malformed),
        );
        final b = ProtocolFramer(
          direction: Direction.backend,
          limits: ProtocolLimits(),
        );
        expect(
          () => b.add(wire('E', [77, 115, 101, 99, 114, 101, 116])),
          refuses(Refusal.malformed),
        );
      },
    );
    test('bounded malformed corpus never escapes as raw parser errors', () {
      for (final direction in Direction.values) {
        for (final t
            in (direction == Direction.frontend
                    ? 'QPBDESHSCXp'
                    : 'RKZ123tTnDCNSAE')
                .codeUnits) {
          for (var n = 0; n < 20; n++) {
            final f = ProtocolFramer(
              direction: direction,
              limits: ProtocolLimits(maxFrameBytes: 128),
              catalogue: [specA()],
            );
            try {
              f.add([t, ...u32(n + 4), ...List<int>.filled(n, 255)]);
            } on ProtocolRefusal catch (e) {
              expect('$e', isNot(contains('255')));
              expect(f.terminal, isTrue);
              expect(f.bufferedBytes, 0);
            }
            expect(f.peakBufferedBytes, lessThanOrEqualTo(128));
          }
        }
      }
    });
    test('statement ceiling and name length refuse', () {
      final p = session(limits: ProtocolLimits(maxStatements: 1));
      prepare(p, 'a');
      expect(
        () => prepare(p, 'b', second: true),
        refuses(Refusal.resourceLimit),
      );
      discarded(p);
      final q = session(limits: ProtocolLimits(maxNameBytes: 2));
      expect(
        () => q.addFrontend(parse('long', sqlA, [25])),
        refuses(Refusal.resourceLimit),
      );
      discarded(q);
    });
    test('row count bound does not retain row payloads', () {
      final p = session(limits: ProtocolLimits(maxRowsPerExchange: 1));
      begin(p);
      request(p, 'a', 'p', withParse: true);
      p.addBackend([
        ...wire('1'),
        ...wire('2'),
        ...rowDescription(),
        ...row('secret'),
      ]);
      expect(() => p.addBackend(row('secret')), refuses(Refusal.resourceLimit));
      discarded(p);
    });
    test('async count and decision queue cannot grow indefinitely', () {
      final p = session(limits: ProtocolLimits(maxAsyncMessages: 1));
      p.addBackend(wire('N', [77, ...z('secret'), 0]));
      expect(
        () => p.addBackend(wire('N', [77, ...z('secret'), 0])),
        refuses(Refusal.resourceLimit),
      );
      discarded(p);
      final q = session(limits: ProtocolLimits(maxEvents: 4));
      q.addFrontend(query('BEGIN;'));
      q.addBackend([...command('BEGIN'), ...ready('T')]);
      expect(
        () => q.addFrontend(query('COMMIT;')),
        refuses(Refusal.resourceLimit),
      );
      discarded(q);
    });
    test('parameter/column counts are checked before collection growth', () {
      final f = ProtocolFramer(
        direction: Direction.backend,
        limits: ProtocolLimits(maxParameters: 1),
      );
      expect(() => f.add(wire('t', u16(2))), refuses(Refusal.resourceLimit));
      final b = ProtocolFramer(
        direction: Direction.backend,
        limits: ProtocolLimits(maxColumns: 1),
      );
      expect(() => b.add(wire('T', u16(2))), refuses(Refusal.resourceLimit));
    });
    test(
      'diagnostics never disclose startup, Bind, rows, auth, cancellation key or errors',
      () {
        const secret = 'sensitive-COMMIT-password-token';
        final f = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
        );
        f.add(wire('p', secret.codeUnits));
        expect('${f.take()}', isNot(contains(secret)));
        final p = session();
        begin(p);
        request(p, 'a', 'p', withParse: true);
        response(p, withParse: true, data: secret);
        expect('${p.drainEvents()}', isNot(contains(secret)));
        final e = ProtocolFramer(
          direction: Direction.backend,
          limits: ProtocolLimits(),
        );
        e.add(error(secret));
        expect('${e.take()}', isNot(contains(secret)));
        final c = ProtocolFramer(
          direction: Direction.frontend,
          limits: ProtocolLimits(),
          startup: true,
        );
        c.add(packet([...u32(80877102), ...u32(41), ...u32(987654)]));
        expect('${c.take()}', isNot(contains('987654')));
        expect(
          '${const ProtocolRefusal(Refusal.malformed)}',
          'ProtocolRefusal(malformed)',
        );
        expect(
          '$identity $operation ${target(p)} ${specA()}',
          'BackendIdentity OperationIdentity TransactionTarget StatementSpec',
        );
      },
    );
  });
}
