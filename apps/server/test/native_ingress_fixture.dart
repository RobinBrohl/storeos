import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:storeos_server/src/config.dart';
import 'package:storeos_server/src/http/guarded_http_server.dart';

// Adapted from the independent finite in-process native-parser reproducer.
// No network listener or connection is created; the production parser owns the
// controlled input and output exactly as it owns a physical Socket.
String nativeRequest(
  String method,
  String path, {
  String body = '',
  int? length,
  bool withLength = true,
  String extra = '',
}) =>
    '$method $path HTTP/1.1\r\nHost: localhost\r\nContent-Type: application/json\r\n${withLength ? 'Content-Length: ${length ?? utf8.encode(body).length}\r\n' : ''}$extra\r\n$body';
Future<void> pumpIngress() async {
  for (var i = 0; i < 15; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class NativeIngressFixture {
  NativeIngressFixture(this.server, this.listener, this.clock);
  static Future<NativeIngressFixture> make(
    Handler h, {
    HttpIngressPolicy policy = const HttpIngressPolicy(),
  }) async {
    final listener = MemoryListener(), clock = IngressClock();
    final server = await GuardedHttpServer.bind(
      h,
      '127.0.0.1',
      0,
      policy: policy,
      schedule: clock.schedule,
      bindSocket: (_, _) async => listener,
    );
    return NativeIngressFixture(server, listener, clock);
  }

  final GuardedHttpServer server;
  final MemoryListener listener;
  final IngressClock clock;
  int peers = 0;
  Future<MemoryTransport> accept() async {
    final socket = MemoryTransport(++peers);
    listener.input.add(socket);
    await pumpIngress();
    return socket;
  }

  Future<void> close() => server.close();
}

class MemoryListener extends Stream<Socket> implements ServerSocket {
  final input = StreamController<Socket>();
  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;
  @override
  int get port => 8080;
  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? data, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => input.stream.listen(
    data,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Future<ServerSocket> close() async {
    unawaited(input.close());
    return this;
  }
}

class MemoryTransport extends Stream<Uint8List> implements Socket {
  MemoryTransport(this.remotePort);
  final input = StreamController<Uint8List>();
  final writes = <int>[];
  final ended = Completer<void>();
  int destroys = 0;
  bool destroyed = false;
  String get output => latin1.decode(writes);
  void feed(String data) => input.add(Uint8List.fromList(utf8.encode(data)));
  @override
  final int remotePort;
  @override
  int get port => 8080;
  @override
  InternetAddress get address => InternetAddress.loopbackIPv4;
  @override
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? data, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => input.stream.listen(
    data,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  void destroy() {
    destroys++;
    if (destroyed) return;
    destroyed = true;
    unawaited(input.close());
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<void> close() async {
    if (!ended.isCompleted) ended.complete();
  }

  @override
  Future<void> get done => ended.future;
  @override
  void add(List<int> bytes) {
    if (!destroyed) writes.addAll(bytes);
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final bytes in stream) {
      add(bytes);
    }
  }

  @override
  Future<void> flush() async {}
  @override
  void addError(Object error, [StackTrace? trace]) {}
  @override
  bool setOption(SocketOption option, bool enabled) => true;
  @override
  Encoding encoding = utf8;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class IngressClock {
  Duration now = Duration.zero;
  final timers = <IngressTick>[];
  int get active => timers.where((x) => x.isActive).length;
  Timer schedule(Duration delay, void Function() callback) {
    final t = IngressTick(now + delay, callback);
    timers.add(t);
    return t;
  }

  void elapse(Duration duration) {
    final end = now + duration;
    while (true) {
      final due = timers.where((t) => t.isActive && t.at <= end).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      if (due.isEmpty) break;
      final t = due.first;
      now = t.at;
      t.cancel();
      t.callback();
    }
    now = end;
  }
}

class IngressTick implements Timer {
  IngressTick(this.at, this.callback);
  final Duration at;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int get tick => 0;
  @override
  void cancel() => isActive = false;
}
