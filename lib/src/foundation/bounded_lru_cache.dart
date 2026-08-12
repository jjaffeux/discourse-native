import 'dart:collection';

/// A tiny least-recently-used map with an exact entry ceiling.
///
/// Reads promote entries. Writes replace and promote an existing key, then
/// discard the least-recently-used key when the ceiling is exceeded. Values
/// may be nullable; [containsKey] distinguishes a remembered null from a miss.
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
