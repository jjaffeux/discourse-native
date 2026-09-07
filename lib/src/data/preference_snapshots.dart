/// Session-local values used to restore a layout before its first frame.
final class PreferenceSnapshots<K, V extends Object> {
  final Map<K, V> _values = {};
  final Map<K, Future<V>> _requests = {};

  V? peek(K key) => _values[key];

  void remember(K key, V value) => _values[key] = value;

  Future<V> ensure(K key, Future<V> Function() read) {
    final held = _values[key];
    if (held != null) return Future.value(held);
    return _requests.putIfAbsent(key, () {
      return read()
          .then((value) {
            // An interaction while storage was being read takes precedence over
            // that older snapshot, including while its write is still pending.
            return _values.putIfAbsent(key, () => value);
          })
          .whenComplete(() {
            final _ = _requests.remove(key);
          });
    });
  }
}
