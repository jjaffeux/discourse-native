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
}
