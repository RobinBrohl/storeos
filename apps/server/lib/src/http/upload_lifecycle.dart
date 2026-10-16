import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

typedef IngressTimer = Timer Function(Duration, void Function());

class UploadAborted implements Exception {
  const UploadAborted();
}

/// The sole native body subscriber. Cancellation transfers ownership to discard,
/// never to a second subscription. No broadcast queue or whole-body buffer.
class UploadLifecycle extends Stream<Uint8List> {
  UploadLifecycle({
    required Stream<Uint8List> input,
    required this.response,
    required this.terminate,
    required this.releaseBody,
    required Duration lifetime,
    required this.discardWindow,
    this.empty = false,
    IngressTimer schedule = Timer.new,
  }) : _schedule = schedule {
    response.deadline = lifetime;
    _absolute = schedule(lifetime, abort);
    _output = StreamController<Uint8List>(
      sync: true,
      onListen: () => _input.resume(),
      onPause: () => _input.pause(),
      onResume: () => _input.resume(),
      onCancel: () {
        if (!_settled) {
          _readerCancelled = true;
          discard();
        }
      },
    );
    _input = input.listen(
      (chunk) {
        if (!_settled && !_discarding) _output.add(chunk);
      },
      onError: (Object _, StackTrace _) => abort(),
      onDone: _eof,
    )..pause();
    if (empty) _input.resume();
  }

  final HttpResponse response;
  final void Function() terminate;
  final void Function() releaseBody;
  final Duration discardWindow;
  final bool empty;
  static const contextKey = 'storeos.http.upload';
  final IngressTimer _schedule;
  late final StreamController<Uint8List> _output;
  late final StreamSubscription<Uint8List> _input;
  late final Timer _absolute;
  Timer? _discardTimer;
  final _finished = Completer<void>();
  bool _settled = false;
  bool _complete = false;
  bool _discarding = false;
  bool _readerCancelled = false;

  bool get complete => _complete;
  bool get settled => _settled;
  Future<void> get finished => _finished.future;

  /// A cancelled reader/discard can later reach native EOF, but is not a
  /// successful command-body read. Only the original reader may authorize work.
  void requireComplete() {
    if (!_complete || _readerCancelled || _discarding) {
      throw const UploadAborted();
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _output.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  void discard() {
    if (_settled || _discarding) return;
    _discarding = true;
    response.persistentConnection = false;
    // The original absolute timer stays armed, even if this window ends later.
    _discardTimer = _schedule(discardWindow, abort);
    _input.resume();
  }

  void _eof() {
    if (_settled) return;
    _complete = true;
    _finish();
    response.deadline = null;
    if (!_readerCancelled) unawaited(_output.close());
  }

  void abort() {
    if (_settled) return;
    // Mark first: native destroy can synchronously notify this same lifecycle.
    _finish();
    // Replace the SDK timer with immediate native termination, not a null
    // deadline. Otherwise a destroyed request can retain its old SDK timer.
    response.deadline = Duration.zero;
    terminate();
    // Never await drain/cancel/response flush before transport destruction.
    unawaited(_input.cancel().catchError((Object _) {}));
    if (!_readerCancelled) {
      _output.addError(const UploadAborted());
      unawaited(_output.close());
    }
  }

  void _finish() {
    _settled = true;
    _absolute.cancel();
    _discardTimer?.cancel();
    releaseBody();
    _finished.complete();
  }
}

/// Synchronous admission; there is deliberately no waiter queue.
class IngressPermits {
  IngressPermits(this.limit);
  final int limit;
  int _active = 0;
  int get active => _active;

  void Function()? acquire() {
    if (_active >= limit) return null;
    _active++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _active--;
    };
  }
}
