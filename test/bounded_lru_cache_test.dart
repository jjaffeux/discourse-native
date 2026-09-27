import 'package:discourse_native/src/foundation/bounded_lru_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('evicts least-recently-used entries and promotes reads', () {
    final cache = BoundedLruCache<String, int>(3)
      ..put('one', 1)
      ..put('two', 2)
      ..put('three', 3);

    expect(cache.read('one'), 1);
    cache.put('four', 4);

    expect(cache.length, 3);
    expect(cache.containsKey('one'), isTrue);
    expect(cache.containsKey('two'), isFalse);
    expect(cache.read('three'), 3);
    expect(cache.read('four'), 4);
  });

  test('remembers null values and promotes replacement writes', () {
    final cache = BoundedLruCache<String, String?>(2)
      ..put('missing', null)
      ..put('held', 'old');

    expect(cache.containsKey('missing'), isTrue);
    expect(cache.read('missing'), isNull);
    cache.put('held', 'new');
    cache.put('third', 'value');

    expect(cache.containsKey('missing'), isFalse);
    expect(cache.read('held'), 'new');
    expect(cache.read('third'), 'value');
  });

  test('clearing forgets every entry and keeps the capacity', () {
    final cache = BoundedLruCache<String, int>(2)
      ..put('one', 1)
      ..put('two', 2)
      ..clear();

    expect(cache.length, 0);
    expect(cache.read('one'), isNull);
    cache
      ..put('three', 3)
      ..put('four', 4)
      ..put('five', 5);
    expect(cache.snapshot, {'four': 4, 'five': 5});
  });
}
