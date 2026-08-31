import 'dart:collection';

final class BoundedLruCache<K, V> {
  BoundedLruCache(this.capacity) : assert(capacity > 0);

  final int capacity;
  final LinkedHashMap<K, V> _values = LinkedHashMap<K, V>();

  int get length => _values.length;

  bool containsKey(K key) => _values.containsKey(key);

  V? read(K key) {
    if (!_values.containsKey(key)) return null;
    final value = _values.remove(key) as V;
    _values[key] = value;
    return value;
  }

  void put(K key, V value) {
    _values.remove(key);
    _values[key] = value;
    if (_values.length > capacity) _values.remove(_values.keys.first);
  }
}
