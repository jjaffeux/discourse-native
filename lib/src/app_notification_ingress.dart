part of 'app_runtime.dart';

final class _NotificationIngress {
  static const _maximumPendingUrls = 16;

  StreamSubscription<String>? _subscription;
  final Queue<_PendingNotificationUrl> _pending = Queue();
  Object? _source;
  _NotificationDestination? _destination;
  bool _draining = false;
  bool _disposed = false;

  void listen(Stream<String> urls) {
    if (_disposed) return;
    final source = Object();
    _source = source;
    unawaited(_subscription?.cancel());
    _subscription = urls.listen((url) {
      if (_disposed || !identical(_source, source) || url.isEmpty) return;
      _pending.addLast(_PendingNotificationUrl(url));
      if (_pending.length > _maximumPendingUrls) _pending.removeFirst();
      _drain();
    }, onError: (Object error, StackTrace stackTrace) {});
  }

  void unavailable() {
    final previous = _destination;
    _destination = null;
    previous?.retire();
  }

  void ready(Future<bool> Function(String) navigate) {
    if (_disposed) return;
    final previous = _destination;
    _destination = _NotificationDestination(navigate);
    previous?.retire();
    _drain();
  }

  void dispose() {
    _disposed = true;
    _source = null;
    unavailable();
    _pending.clear();
    unawaited(_subscription?.cancel());
  }

  void _drain() {
    final destination = _destination;
    if (_draining || _pending.isEmpty || destination == null) return;
    _draining = true;
    unawaited(_deliver(destination));
  }

  Future<void> _deliver(_NotificationDestination destination) async {
    try {
      while (identical(_destination, destination) && _pending.isNotEmpty) {
        final pending = _pending.first;
        try {
          await destination.deliver(pending.url);
        } catch (_) {}
        if (!identical(_destination, destination)) return;
        _pending.remove(pending);
      }
    } finally {
      _draining = false;
      _drain();
    }
  }
}

final class _NotificationDestination {
  _NotificationDestination(this._navigate);

  final Future<bool> Function(String) _navigate;
  Completer<void>? _delivery;

  Future<void> deliver(String url) {
    final delivery = Completer<void>();
    _delivery = delivery;
    void finish([Object? error, StackTrace? stackTrace]) {
      if (identical(_delivery, delivery)) _delivery = null;
      if (delivery.isCompleted) return;
      if (error == null) {
        delivery.complete();
      } else {
        delivery.completeError(error, stackTrace!);
      }
    }

    unawaited(
      Future<bool>.sync(() => _navigate(url)).then<void>(
        (_) => finish(),
        onError: (Object error, StackTrace stackTrace) =>
            finish(error, stackTrace),
      ),
    );
    return delivery.future;
  }

  void retire() {
    final delivery = _delivery;
    _delivery = null;
    if (delivery != null && !delivery.isCompleted) delivery.complete();
  }
}

final class _PendingNotificationUrl {
  _PendingNotificationUrl(this.url);

  final String url;
}
