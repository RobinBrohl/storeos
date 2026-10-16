import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../config.dart';
import 'upload_lifecycle.dart';

/// Owns the supplied listener, accepted sockets and all body lifecycle objects.
class GuardedHttpServer {
  GuardedHttpServer._(this._sockets, this._http, this._policy, this._schedule)
    : _requests = IngressPermits(_policy.requests),
      _bodies = IngressPermits(_policy.bodies);

  static Future<GuardedHttpServer> bind(
    Handler handler,
    Object address,
    int port, {
    HttpIngressPolicy policy = const HttpIngressPolicy(),
    IngressTimer schedule = Timer.new,
    Future<ServerSocket> Function(Object, int)? bindSocket,
  }) async {
    policy.validate();
    final listener = await (bindSocket ?? (a, p) => ServerSocket.bind(a, p))(
      address,
      port,
    );
    final sockets = AdmittedSockets(listener, policy, schedule: schedule);
    HttpServer? http;
    try {
      http = HttpServer.listenOn(sockets)..idleTimeout = policy.idleTimeout;
      final server = GuardedHttpServer._(sockets, http, policy, schedule);
      server._subscription = http.listen(
        (request) => server._accept(request, handler),
        onError: (Object _, StackTrace _) => unawaited(server.close()),
      );
      return server;
    } catch (_) {
      sockets.destroyAll();
      await listener.close();
      await http?.close(force: true);
      rethrow;
    }
  }

  final AdmittedSockets _sockets;
  final HttpServer _http;
  final HttpIngressPolicy _policy;
  final IngressTimer _schedule;
  final IngressPermits _requests;
  final IngressPermits _bodies;
  final _work = <Future<void>>{};
  late final StreamSubscription<HttpRequest> _subscription;
  Future<void>? _closing;
  bool _closed = false;

  int get port => _http.port;
  int get activeConnections => _sockets.active;
  int get activeRequests => _requests.active;
  int get incompleteBodies => _bodies.active;

  void _accept(HttpRequest request, Handler handler) {
    final connection = _sockets.forRequest(request);
    final releaseRequest = _closed ? null : _requests.acquire();
    final releaseBody = releaseRequest == null ? null : _bodies.acquire();
    if (connection == null || releaseRequest == null || releaseBody == null) {
      releaseRequest?.call();
      releaseBody?.call();
      connection?.destroy();
      // Fail closed even if native connection metadata cannot be matched.
      if (connection == null) request.response.deadline = Duration.zero;
      return;
    }
    connection.headersReceived();
    final upload = UploadLifecycle(
      input: request,
      response: request.response,
      terminate: connection.destroy,
      releaseBody: releaseBody,
      lifetime: _policy.bodyLifetime,
      discardWindow: _policy.discardWindow,
      schedule: _schedule,
      // Native request framing: absent length is empty unless it is chunked.
      // Resume to observe actual EOF; headers alone never mark completion.
      empty:
          !request.headers.chunkedTransferEncoding &&
          request.contentLength <= 0,
    );
    connection.upload = upload;
    final work = _serve(request, upload, handler, connection, releaseRequest);
    _work.add(work);
    unawaited(work.whenComplete(() => _work.remove(work)));
  }

  Future<void> _serve(
    HttpRequest request,
    UploadLifecycle upload,
    Handler handler,
    IngressSocket connection,
    void Function() releaseRequest,
  ) async {
    try {
      await shelf_io.handleRequest(_OwnedRequest(request, upload), (
        shelf,
      ) async {
        Response response;
        try {
          if (upload.empty) {
            await upload.finished;
            upload.requireComplete();
          }
          response = await handler(
            shelf.change(context: {UploadLifecycle.contextKey: upload}),
          );
        } on UploadAborted {
          return Response(400);
        }
        if (!upload.settled) {
          upload.discard();
          await upload.finished;
        }
        if (!upload.complete) return Response(400);
        return response;
      });
    } catch (_) {
      // Transport errors must not reach Shelf's request/credential error logger.
      connection.destroy();
    } finally {
      if (!upload.settled) upload.abort();
      connection.finishUpload(upload);
      // A disconnected valid transaction still holds its permit until it ends.
      releaseRequest();
    }
  }

  Future<void> close({bool force = true}) => _closing ??= _close();

  Future<void> _close() async {
    _closed = true;
    // listenOn does not close its supplied ServerSocket.
    final stopped = _sockets.close();
    _sockets.destroyAll();
    await _http.close(force: true);
    await stopped;
    await _subscription.cancel();
    await Future.wait(_work.toList());
  }
}

/// Public dart:io interface adapter; admission occurs before the HTTP parser.
class AdmittedSockets extends Stream<Socket> implements ServerSocket {
  AdmittedSockets(this.source, this.policy, {this.schedule = Timer.new})
    : _permits = IngressPermits(policy.connections);

  final ServerSocket source;
  final HttpIngressPolicy policy;
  final IngressTimer schedule;
  final IngressPermits _permits;
  final _connections = <String, IngressSocket>{};
  bool _closed = false;
  int get active => _permits.active;

  static String _key(InternetAddress address, int remote, int local) =>
      '${address.address}/$remote/$local';

  IngressSocket? forRequest(HttpRequest request) {
    final info = request.connectionInfo;
    return info == null
        ? null
        : _connections[_key(
            info.remoteAddress,
            info.remotePort,
            info.localPort,
          )];
  }

  @override
  StreamSubscription<Socket> listen(
    void Function(Socket)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => source.listen(
    (socket) {
      final release = _closed ? null : _permits.acquire();
      if (release == null) {
        socket.destroy();
        return;
      }
      final key = _key(socket.remoteAddress, socket.remotePort, socket.port);
      // Public HttpConnectionInfo omits the destination address. A wildcard
      // listener can therefore have ambiguous peer/local-port tuples. Never
      // replace an admitted owner: reject the new socket before HTTP parsing.
      if (_connections.containsKey(key)) {
        socket.destroy();
        release();
        return;
      }
      final admitted = IngressSocket(
        socket,
        () {
          _connections.remove(key);
          release();
        },
        policy.bodyLifetime,
        schedule: schedule,
      );
      _connections[key] = admitted;
      onData?.call(admitted);
    },
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void destroyAll() {
    for (final connection in _connections.values.toList()) {
      connection.destroy();
    }
  }

  @override
  int get port => source.port;
  @override
  InternetAddress get address => source.address;
  @override
  Future<ServerSocket> close() {
    _closed = true;
    return source.close();
  }
}

/// Intercepts actual native destruction; a send-side done event triggers our own
/// two-direction destroy before releasing admission, never release on done alone.
class IngressSocket extends Stream<Uint8List> implements Socket {
  IngressSocket(
    this.source,
    this.release,
    this.headerLifetime, {
    this.schedule = Timer.new,
  }) {
    awaitHeaders();
    unawaited(
      source.done.then((_) => destroy(), onError: (Object _) => destroy()),
    );
  }

  final Socket source;
  final void Function() release;
  final Duration headerLifetime;
  final IngressTimer schedule;
  UploadLifecycle? upload;
  Timer? _headers;
  bool _destroyed = false;

  void headersReceived() {
    _headers?.cancel();
    _headers = null;
  }

  void finishUpload(UploadLifecycle finished) {
    // The native parser can dispatch the next pipelined request before the
    // previous response Future resumes. Its ownership must survive old cleanup.
    if (!identical(upload, finished)) return;
    upload = null;
    awaitHeaders();
  }

  void awaitHeaders() {
    if (_destroyed || _headers != null) return;
    late final Timer timer;
    timer = schedule(headerLifetime, () {
      if (identical(_headers, timer)) destroy();
    });
    _headers = timer;
  }

  @override
  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _headers?.cancel();
    source.destroy();
    upload?.abort();
    release();
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => source.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  Encoding get encoding => source.encoding;
  @override
  set encoding(Encoding value) => source.encoding = value;
  @override
  void add(List<int> data) => source.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      source.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => source.addStream(stream);
  @override
  Future<void> flush() => source.flush();
  @override
  Future close() => source.close();
  @override
  Future get done => source.done;
  @override
  void write(Object? object) => source.write(object);
  @override
  void writeln([Object? object = '']) => source.writeln(object);
  @override
  void writeAll(Iterable objects, [String separator = '']) =>
      source.writeAll(objects, separator);
  @override
  void writeCharCode(int code) => source.writeCharCode(code);
  @override
  int get port => source.port;
  @override
  int get remotePort => source.remotePort;
  @override
  InternetAddress get address => source.address;
  @override
  InternetAddress get remoteAddress => source.remoteAddress;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      source.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => source.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => source.setRawOption(option);
}

class _OwnedRequest extends Stream<Uint8List> implements HttpRequest {
  _OwnedRequest(this.source, this.body);
  final HttpRequest source;
  final UploadLifecycle body;
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => body.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  HttpResponse get response => source.response;
  @override
  HttpHeaders get headers => source.headers;
  @override
  String get method => source.method;
  @override
  Uri get uri => source.uri;
  @override
  Uri get requestedUri => source.requestedUri;
  @override
  String get protocolVersion => source.protocolVersion;
  @override
  int get contentLength => source.contentLength;
  @override
  bool get persistentConnection => source.persistentConnection;
  @override
  List<Cookie> get cookies => source.cookies;
  @override
  X509Certificate? get certificate => source.certificate;
  @override
  HttpSession get session => source.session;
  @override
  HttpConnectionInfo? get connectionInfo => source.connectionInfo;
}
