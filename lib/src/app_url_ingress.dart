part of 'app_runtime.dart';

/// Every URL the platform hands the app to navigate to — a tapped push, or a
/// `discourse://open` request from another application — waits here until a
/// loaded shell can take it, and is then delivered one at a time in arrival
/// order, so the newest navigation is the one left showing.
final class _UrlIngress {
  static const _maximumPendingUrls = 16;

  final _notifications = _UrlSource();
  final _links = _UrlSource();
  final Queue<_PendingUrl> _pending = Queue();
  void Function(RequestedLinkOutcome outcome)? _presentLink;
  _UrlDestination? _destination;
  bool _draining = false;
  bool _disposed = false;

  void listenNotifications(Stream<String> urls) {
    if (_disposed) return;
    _notifications.listen(urls, (url) => _accept(_NotificationUrl(url)));
  }

  void listenLinks(
    Stream<String> requests,
    void Function(RequestedLinkOutcome outcome) present,
  ) {
    if (_disposed) return;
    _presentLink = present;
    _links.listen(requests, (request) => _accept(_LinkRequest(request)));
  }

  void _accept(_PendingUrl url) {
    if (_disposed) return;
    _pending.addLast(url);
    if (_pending.length > _maximumPendingUrls) _pending.removeFirst();
    _drain();
  }

  void unavailable() {
    final previous = _destination;
    _destination = null;
    previous?.retire();
  }

  void ready(ShellController controller) {
    if (_disposed) return;
    final previous = _destination;
    if (identical(previous?.controller, controller)) return;
    _destination = _UrlDestination(controller);
    previous?.retire();
    _drain();
  }

  void dispose() {
    _disposed = true;
    _presentLink = null;
    unavailable();
    _pending.clear();
    _notifications.cancel();
    _links.cancel();
  }

  void _drain() {
    final destination = _destination;
    if (_draining || _pending.isEmpty || destination == null) return;
    _draining = true;
    unawaited(_deliver(destination));
  }

  Future<void> _deliver(_UrlDestination destination) async {
    try {
      while (identical(_destination, destination) && _pending.isNotEmpty) {
        final pending = _pending.first;
        // Requests that piled up while the shell loaded name pages the user
        // has since asked to replace; only the newest is still wanted.
        if (pending is _LinkRequest &&
            _pending.any(
              (later) => later is _LinkRequest && !identical(later, pending),
            )) {
          _pending.remove(pending);
          continue;
        }
        RequestedLinkOutcome? outcome;
        try {
          switch (pending) {
            case _NotificationUrl(:final url):
              await destination.deliver(
                (controller) => controller.openNotificationUrl(url),
              );
            case _LinkRequest(:final url):
              outcome = await destination.deliver(
                (controller) => controller.openRequestedLink(url),
              );
          }
        } catch (_) {}
        if (!identical(_destination, destination)) return;
        _pending.remove(pending);
        if (outcome != null) {
          try {
            _presentLink?.call(outcome);
          } catch (_) {
            // A presenter failure cannot hold back the URLs queued behind it.
          }
        }
      }
    } finally {
      _draining = false;
      _drain();
    }
  }
}

/// One replaceable stream of URLs. A source that is replaced or cancelled
/// while it is still being attached must not keep feeding the ingress.
final class _UrlSource {
  StreamSubscription<String>? _subscription;
  Object? _owner;

  void listen(Stream<String> urls, void Function(String url) accept) {
    final owner = Object();
    _owner = owner;
    final previous = _subscription;
    _subscription = null;
    _cancel(previous);
    if (!identical(_owner, owner)) return;
    final subscription = urls.listen((url) {
      if (!identical(_owner, owner) || url.isEmpty) return;
      accept(url);
    }, onError: (Object error, StackTrace stackTrace) {});
    if (identical(_owner, owner)) {
      _subscription = subscription;
    } else {
      _cancel(subscription);
    }
  }

  void cancel() {
    _owner = null;
    final subscription = _subscription;
    _subscription = null;
    _cancel(subscription);
  }

  void _cancel(StreamSubscription<String>? subscription) {
    try {
      subscription?.cancel().ignore();
    } catch (_) {
      // A retired source cannot veto replacement or shutdown.
    }
  }
}

final class _UrlDestination {
  _UrlDestination(this.controller);

  final ShellController controller;
  Completer<Object?>? _delivery;

  /// Completes with null when this destination is retired first: the URL was
  /// not delivered as far as the ingress is concerned, and stays queued.
  Future<T?> deliver<T extends Object>(
    Future<T> Function(ShellController controller) open,
  ) {
    final delivery = Completer<T?>();
    _delivery = delivery;
    void finish(T? result, [Object? error, StackTrace? stackTrace]) {
      if (identical(_delivery, delivery)) _delivery = null;
      if (delivery.isCompleted) return;
      if (error == null) {
        delivery.complete(result);
      } else {
        delivery.completeError(error, stackTrace!);
      }
    }

    unawaited(
      Future<T>.sync(() => open(controller)).then<void>(
        finish,
        onError: (Object error, StackTrace stackTrace) =>
            finish(null, error, stackTrace),
      ),
    );
    return delivery.future;
  }

  void retire() {
    final delivery = _delivery;
    _delivery = null;
    if (delivery != null && !delivery.isCompleted) delivery.complete(null);
  }
}

sealed class _PendingUrl {
  _PendingUrl(this.url);

  final String url;
}

final class _NotificationUrl extends _PendingUrl {
  _NotificationUrl(super.url);
}

final class _LinkRequest extends _PendingUrl {
  _LinkRequest(super.url);
}
