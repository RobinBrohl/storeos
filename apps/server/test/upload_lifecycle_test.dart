import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/http/api_support.dart';

import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/guarded_http_server.dart';
import 'package:storeos_server/src/http/upload_lifecycle.dart';
import 'package:test/test.dart';

void main() {
  test(
    'completion gate rejects reader cancellation and synthetic reader EOF',
    () async {
      final f = _Upload();
      final request = Request(
        'POST',
        Uri.parse('http://localhost/logout'),
        body: f.upload.take(1),
        context: {UploadLifecycle.contextKey: f.upload},
      );
      var mutations = 0;
      final guarded = () async {
        await completeRequestBody(request);
        mutations++;
      }();
      final failure = expectLater(guarded, throwsA(isA<UploadAborted>()));
      f.input.add(Uint8List.fromList([1]));
      await failure;
      expect(mutations, 0);
      expect(f.upload.complete, false);
      await f.input.close();
      expect(f.upload.complete, true);
      expect(f.upload.requireComplete, throwsA(isA<UploadAborted>()));
      expect(mutations, 0);
      expect(f.bodyReleases, 1);
    },
  );

  test(
    'duplicate completion cleanup cannot repeat a guarded mutation',
    () async {
      final f = _Upload();
      final request = Request(
        'POST',
        Uri.parse('http://localhost/logout'),
        body: f.upload,
        context: {UploadLifecycle.contextKey: f.upload},
      );
      var mutations = 0;
      final guarded = () async {
        await completeRequestBody(request);
        mutations++;
      }();
      await f.input.close();
      await guarded;
      await f.input.close();
      f.upload.abort();
      f.upload.discard();
      f.clock.elapse(const Duration(seconds: 60));
      expect(mutations, 1);
      expect(f.bodyReleases, 1);
      expect(f.upload.complete, true);
    },
  );

  test('complete native EOF clears deadline and releases once', () async {
    final f = _Upload();
    final bytes = f.upload.toList();
    f.input.add(Uint8List.fromList([1, 2]));
    await f.input.close();
    expect(await bytes, [
      [1, 2],
    ]);
    f.clock.elapse(const Duration(seconds: 60));
    expect(f.response.deadlines, [const Duration(seconds: 30), null]);
    expect(f.bodyReleases, 1);
    expect(f.socket.destroys, 0);
    f.upload.abort();
    expect(f.bodyReleases, 1);
    f.connection.destroy();
  });

  test(
    'expiration invokes production two-direction socket destruction',
    () async {
      final f = _Upload();
      final result = f.upload.drain<void>();
      final failure = expectLater(result, throwsA(isA<UploadAborted>()));
      f.input.add(Uint8List.fromList([123]));
      await _pump();
      f.clock.elapse(const Duration(seconds: 30));
      expect(f.socket.destroys, 1);
      expect(f.connectionReleases, 1);
      expect(f.bodyReleases, 1);
      expect(f.response.deadlines.last, Duration.zero);
      expect(f.upload.complete, false);
      await failure;
      await f.input.close();
    },
  );

  test(
    'parser rejection and cancellation transfer to bounded discard',
    () async {
      final f = _Upload();
      final read = f.upload.listen((_) {});
      await read.cancel();
      expect(f.upload.complete, false);
      expect(f.response.deadlines.last, const Duration(seconds: 30));
      expect(f.response.persistentConnection, false);
      f.input.add(Uint8List.fromList(List.filled(1000, 1)));
      await _pump();
      f.clock.elapse(const Duration(seconds: 1));
      expect(f.socket.destroys, 1);
      expect(f.bodyReleases, 1);
      expect(f.clock.active, 0);
      await f.input.close();
    },
  );

  test(
    'error response cannot extend an almost expired body deadline',
    () async {
      final f = _Upload();
      final errors = <Object>[];
      f.upload.listen((_) {}, onError: errors.add);
      f.clock.elapse(const Duration(milliseconds: 29900));
      f.upload.discard();
      f.upload.discard();
      f.clock.elapse(const Duration(milliseconds: 100));
      expect(f.socket.destroys, 1);
      await _pump();
      expect(errors, [isA<UploadAborted>()]);
      expect(f.bodyReleases, 1);
      await f.input.close();
    },
  );

  test('successful EOF wins a same-instant timeout callback race', () async {
    final f = _Upload();
    final result = f.upload.drain<void>();
    final timeout = f.clock.timers.last.callback;
    await f.input.close();
    await result;
    timeout(); // A queued callback is harmless even after timer cancellation.
    expect(f.upload.complete, true);
    expect(f.socket.destroys, 0);
    expect(f.bodyReleases, 1);
    f.connection.destroy();
  });

  test(
    'timeout wins EOF race; no late partial command is dispatched',
    () async {
      final f = _Upload();
      var commands = 0;
      final result = f.upload.toList().then((_) => commands++);
      final failure = expectLater(result, throwsA(isA<UploadAborted>()));
      f.clock.elapse(const Duration(seconds: 30));
      await f.input.close();
      await failure;
      expect(commands, 0);
      expect(f.upload.complete, false);
    },
  );

  test('input error followed by done is never genuine EOF', () async {
    final f = _Upload();
    final failure = expectLater(
      f.upload.drain<void>(),
      throwsA(isA<UploadAborted>()),
    );
    f.input.addError(const FormatException('synthetic input error'));
    await _pump();
    await f.input.close();
    await failure;
    expect(f.upload.complete, false);
    expect(f.socket.destroys, 1);
    expect(f.bodyReleases, 1);
  });

  test(
    'duplicate abort, transport close and cleanup release exactly once',
    () async {
      final f = _Upload();
      final failure = expectLater(
        f.upload.drain<void>(),
        throwsA(isA<UploadAborted>()),
      );
      f.upload.abort();
      f.upload.abort();
      f.connection.destroy();
      f.connection.destroy();
      f.clock.elapse(const Duration(seconds: 60));
      await failure;
      await f.input.close();
      expect(f.bodyReleases, 1);
      expect(f.connectionReleases, 1);
      expect(f.socket.destroys, 1);
      expect(f.clock.active, 0);
    },
  );

  test('termination precedes waiting for native input cancellation', () async {
    final cancelled = Completer<void>();
    final f = _Upload(onCancel: () => cancelled.future);
    final failure = expectLater(
      f.upload.drain<void>(),
      throwsA(isA<UploadAborted>()),
    );
    f.upload.abort();
    expect(cancelled.isCompleted, false);
    expect(f.socket.destroys, 1);
    expect(f.bodyReleases, 1);
    cancelled.complete();
    await failure;
    await f.input.close();
  });

  test(
    'reader backpressure reaches sole native subscription without a queue',
    () async {
      final f = _Upload();
      expect(f.input.isPaused, true);
      final seen = <Uint8List>[];
      final reader = f.upload.listen(seen.add);
      reader.pause();
      expect(f.input.isPaused, true);
      f.input.add(Uint8List.fromList([1]));
      await _pump();
      expect(seen, isEmpty);
      reader.resume();
      await _pump();
      expect(seen, [
        [1],
      ]);
      await f.input.close();
      expect(f.upload.complete, true);
      f.connection.destroy();
    },
  );

  test(
    'one native subscription; cancelled reader discard retains no chunks',
    () async {
      var listens = 0;
      final f = _Upload(onListen: () => listens++);
      final reader = f.upload.listen((_) {});
      await reader.cancel();
      for (var i = 0; i < 10; i++) {
        f.input.add(Uint8List.fromList([i]));
        await _pump();
      }
      await f.input.close();
      expect(listens, 1);
      expect(f.upload.complete, true);
      expect(f.clock.active, 0);
      f.connection.destroy();
    },
  );

  test(
    'valid completed work outlives cleared upload deadline and disconnect',
    () async {
      final f = _Upload();
      final body = f.upload.drain<void>();
      await f.input.close();
      await body;
      final business = Completer<void>();
      var committed = false;
      final work = business.future.then((_) => committed = true);
      f.connection.destroy();
      f.clock.elapse(const Duration(seconds: 60));
      business.complete();
      await work;
      expect(committed, true);
      expect(f.upload.complete, true);
    },
  );

  test('request and body admission have no waiters and idempotent release', () {
    final permits = IngressPermits(2);
    final a = permits.acquire()!;
    final b = permits.acquire()!;
    for (var i = 0; i < 10; i++) {
      expect(permits.acquire(), null);
    }
    expect(permits.active, 2);
    a();
    a();
    expect(permits.active, 1);
    final c = permits.acquire()!;
    b();
    c();
    expect(permits.active, 0);
  });

  test(
    'shutdown destroys active uploads and cancels all lifecycle timers',
    () async {
      final f = _Upload();
      final failure = expectLater(
        f.upload.drain<void>(),
        throwsA(isA<UploadAborted>()),
      );
      f.connection.destroy();
      await failure;
      await f.input.close();
      expect(f.clock.active, 0);
      expect(f.bodyReleases, 1);
      expect(f.connectionReleases, 1);
      expect(f.upload.complete, false);
    },
  );

  test(
    'pre-header connection admission and shutdown own all sockets',
    () async {
      final listener = _Listener();
      final clock = _Clock();
      final sockets = AdmittedSockets(
        listener,
        const HttpIngressPolicy(connections: 1, requests: 1, bodies: 1),
        schedule: clock.schedule,
      );
      final accepted = <Socket>[];
      final subscription = sockets.listen(accepted.add);
      final a = _Socket(1);
      final b = _Socket(2);
      listener.input.add(a);
      listener.input.add(b);
      await _pump();
      expect(accepted, hasLength(1));
      expect(sockets.active, 1);
      expect(b.destroys, 1);
      sockets.destroyAll();
      sockets.destroyAll();
      expect(sockets.active, 0);
      expect(a.destroys, 1);
      expect(clock.active, 0);
      await sockets.close();
      await subscription.cancel();
    },
  );

  test('headerless connection expires without any HTTP request', () async {
    final clock = _Clock();
    final socket = _Socket(1);
    var released = 0;
    final connection = IngressSocket(
      socket,
      () => released++,
      const Duration(seconds: 30),
      schedule: clock.schedule,
    );
    clock.elapse(const Duration(seconds: 30));
    connection.destroy();
    expect(socket.destroys, 1);
    expect(released, 1);
    expect(clock.active, 0);
  });

  test(
    'ambiguous connection metadata cannot replace a live socket owner',
    () async {
      final listener = _Listener();
      final clock = _Clock();
      final sockets = AdmittedSockets(
        listener,
        const HttpIngressPolicy(connections: 2, requests: 2, bodies: 1),
        schedule: clock.schedule,
      );
      final accepted = <Socket>[];
      final subscription = sockets.listen(accepted.add);
      final a = _Socket(1);
      final ambiguous = _Socket(1);
      listener.input.add(a);
      listener.input.add(ambiguous);
      await _pump();
      expect(accepted, hasLength(1));
      expect(sockets.active, 1);
      expect(a.destroys, 0);
      expect(ambiguous.destroys, 1);
      sockets.destroyAll();
      expect(a.destroys, 1);
      expect(sockets.active, 0);
      await sockets.close();
      await subscription.cancel();
    },
  );

  test('queued old header timer cannot destroy dispatched or later work', () {
    final clock = _Clock();
    final socket = _Socket(1);
    final connection = IngressSocket(
      socket,
      () {},
      const Duration(seconds: 30),
      schedule: clock.schedule,
    );
    final old = clock.timers.single.callback;
    connection.headersReceived();
    old();
    expect(socket.destroys, 0);
    connection.awaitHeaders();
    old();
    expect(socket.destroys, 0);
    connection.destroy();
  });

  test(
    'old pipelined response cleanup cannot clear the next upload owner',
    () async {
      final f = _Upload();
      final firstBody = f.upload.drain<void>();
      await f.input.close();
      await firstBody;
      final input = StreamController<Uint8List>();
      final next = UploadLifecycle(
        input: input.stream,
        response: _Response(),
        terminate: f.connection.destroy,
        releaseBody: () {},
        lifetime: const Duration(seconds: 30),
        discardWindow: const Duration(seconds: 1),
        schedule: f.clock.schedule,
      );
      f.connection.upload = next;
      f.connection.finishUpload(f.upload);
      expect(f.connection.upload, same(next));
      final secondBody = next.drain<void>();
      await input.close();
      await secondBody;
      // Simulate business work continuing after its genuine body EOF.
      f.clock.elapse(const Duration(seconds: 60));
      expect(f.socket.destroys, 0);
      f.connection.finishUpload(next);
      expect(f.connection.upload, null);
      f.clock.elapse(const Duration(seconds: 30));
      expect(f.socket.destroys, 1);
    },
  );

  test(
    'send-side completion forces destroy before releasing connection',
    () async {
      final socket = _Socket(1);
      final events = socket.events;
      IngressSocket(
        socket,
        () => events.add('release'),
        const Duration(seconds: 30),
      );
      socket.outputDone.complete();
      await _pump();
      expect(events, ['destroy', 'release']);
    },
  );

  test('startup bind failure creates no listener or lifecycle', () async {
    await expectLater(
      GuardedHttpServer.bind(
        (_) => throw StateError('unused'),
        '127.0.0.1',
        0,
        bindSocket: (_, _) async =>
            throw const SocketException('synthetic bind failure'),
      ),
      throwsA(isA<SocketException>()),
    );
  });

  test('startup listen failure rolls back supplied listener', () async {
    final listener = _Listener(failListen: true);
    await expectLater(
      GuardedHttpServer.bind(
        (_) => throw StateError('unused'),
        '127.0.0.1',
        0,
        bindSocket: (_, _) async => listener,
      ),
      throwsStateError,
    );
    expect(listener.closed, true);
  });
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

class _Upload {
  _Upload({FutureOr<void> Function()? onCancel, void Function()? onListen}) {
    input = StreamController<Uint8List>(onCancel: onCancel, onListen: onListen);
    connection = IngressSocket(
      socket,
      () => connectionReleases++,
      const Duration(seconds: 30),
      schedule: clock.schedule,
    );
    connection.headersReceived();
    upload = UploadLifecycle(
      input: input.stream,
      response: response,
      terminate: connection.destroy,
      releaseBody: () => bodyReleases++,
      lifetime: const Duration(seconds: 30),
      discardWindow: const Duration(seconds: 1),
      schedule: clock.schedule,
    );
    connection.upload = upload;
  }
  final clock = _Clock();
  final response = _Response();
  final socket = _Socket(1);
  late final StreamController<Uint8List> input;
  late final IngressSocket connection;
  late final UploadLifecycle upload;
  var bodyReleases = 0;
  var connectionReleases = 0;
}

class _Response implements HttpResponse {
  final deadlines = <Duration?>[];
  @override
  set deadline(Duration? value) => deadlines.add(value);
  @override
  bool persistentConnection = true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clock {
  var now = Duration.zero;
  final timers = <_Timer>[];
  int get active => timers.where((t) => t.isActive).length;
  Timer schedule(Duration delay, void Function() callback) {
    final timer = _Timer(now + delay, callback);
    timers.add(timer);
    return timer;
  }

  void elapse(Duration duration) {
    final end = now + duration;
    while (true) {
      final due = timers.where((t) => t.isActive && t.at <= end).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final timer = due.first;
      now = timer.at;
      timer.cancel();
      timer.callback();
    }
    now = end;
  }
}

class _Timer implements Timer {
  _Timer(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  void cancel() => isActive = false;
  @override
  int get tick => isActive ? 0 : 1;
}

class _Socket extends Stream<Uint8List> implements Socket {
  _Socket(this.remotePort);
  final outputDone = Completer<void>();
  final events = <String>[];
  int destroys = 0;
  @override
  final int remotePort;
  @override
  int get port => 8080;
  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;
  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;
  @override
  Future<void> get done => outputDone.future;
  @override
  void destroy() {
    destroys++;
    events.add('destroy');
    if (!outputDone.isCompleted) outputDone.complete();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => const Stream<Uint8List>.empty().listen(onData, onDone: onDone);
  @override
  Encoding encoding = utf8;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Listener extends Stream<Socket> implements ServerSocket {
  _Listener({this.failListen = false});
  final bool failListen;
  final input = StreamController<Socket>();
  bool closed = false;
  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;
  @override
  int get port => 8080;
  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    if (failListen) throw StateError('synthetic listen failure');
    return input.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<ServerSocket> close() async {
    closed = true;
    unawaited(input.close());
    return this;
  }
}
