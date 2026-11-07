import 'dart:async';

/// Session-local values used to restore a layout before its first frame.
final class PreferenceSnapshots<K, V extends Object> {
  final Map<K, V> _values = {};
  final Map<K, Future<V>> _requests = {};

  V? peek(K key) => _values[key];

  void remember(K key, V value) => _values[key] = value;

  Future<V> ensure(K key, Future<V> Function() read) {
    final held = _values[key];
    if (held != null) return Future.value(held);
    final pending = _requests[key];
    if (pending != null) return pending;
    final result = Completer<V>();
    final request = result.future;
    _requests[key] = request;
    unawaited(
      Future<V>.sync(read)
          .then((value) {
            // Forgotten while storage was being read: the caller still gets the
            // value, but nothing later peeks it.
            if (!identical(_requests[key], request)) return value;
            // An interaction while storage was being read takes precedence over
            // that older snapshot, including while its write is still pending.
            return _values.putIfAbsent(key, () => value);
          })
          .then<void>(
            (value) {
              if (identical(_requests[key], request)) {
                final _ = _requests.remove(key);
              }
              result.complete(value);
            },
            onError: (Object error, StackTrace stack) {
              if (identical(_requests[key], request)) {
                final _ = _requests.remove(key);
              }
              result.completeError(error, stack);
            },
          ),
    );
    return request;
  }

  /// Drops every value [test] accepts, and keeps a read of one still in
  /// flight from holding what it read.
  void forgetWhere(bool Function(K key) test) {
    _values.removeWhere((key, _) => test(key));
    _requests.removeWhere((key, _) => test(key));
  }
}
