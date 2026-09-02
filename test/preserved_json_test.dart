import 'package:discourse_native/src/plugin_api/preserved_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('freezeJson', () {
    test('copies scalars, lists, and string-keyed maps as immutable trees', () {
      final frozen = freezeJson({
        'name': 'opaque',
        'flags': [true, 2, 2.5, null],
        'nested': {'depth': 1},
      });

      expect(frozen.valid, isTrue);
      final value = frozen.value! as Map<String, Object?>;
      expect(value, {
        'name': 'opaque',
        'flags': [true, 2, 2.5, null],
        'nested': {'depth': 1},
      });
      expect(() => value['name'] = 'changed', throwsUnsupportedError);
      expect(
        () => (value['flags']! as List<Object?>).add(false),
        throwsUnsupportedError,
      );
      expect(
        () => (value['nested']! as Map<String, Object?>).clear(),
        throwsUnsupportedError,
      );
    });

    test('refuses a tree holding a non-finite number anywhere', () {
      for (final value in [
        double.nan,
        double.infinity,
        [1, double.negativeInfinity],
        {
          'deep': [
            {'n': double.nan},
          ],
        },
      ]) {
        expect(freezeJson(value), (
          valid: false,
          value: null,
        ), reason: '$value');
      }
    });

    test('refuses a tree holding a non-string key or an unknown object', () {
      expect(freezeJson({1: 'one'}), (valid: false, value: null));
      expect(
        freezeJson({
          'outer': {2: 'two'},
        }),
        (valid: false, value: null),
      );
      expect(freezeJson(DateTime.utc(2026)), (valid: false, value: null));
    });
  });

  group('preserveJsonNamespaces', () {
    test('keeps carriable namespaces and drops the others individually', () {
      final preserved = preserveJsonNamespaces({
        'future-plugin/site-settings': {'token': 'opaque'},
        '': {'ignored': true},
        7: {'ignored': true},
        'broken-plugin': double.nan,
        'scalar-plugin': 'text',
      });

      expect(preserved, {
        'future-plugin/site-settings': {'token': 'opaque'},
        'scalar-plugin': 'text',
      });
    });

    test('answers an empty map for anything that is not a map', () {
      expect(preserveJsonNamespaces(null), isEmpty);
      expect(preserveJsonNamespaces(['a']), isEmpty);
      expect(preserveJsonNamespaces('a'), isEmpty);
    });
  });

  group('deepJsonEquals and deepJsonHash', () {
    test('compare nested collections structurally with a matching hash', () {
      final left = {
        'list': [
          1,
          {'a': 'b'},
        ],
        'map': {'x': 1, 'y': 2},
      };
      final right = {
        'map': {'y': 2, 'x': 1},
        'list': [
          1,
          {'a': 'b'},
        ],
      };

      expect(deepJsonEquals(left, right), isTrue);
      expect(deepJsonHash(left), deepJsonHash(right));
    });

    test('distinguish differing length, order, keys, and scalar values', () {
      expect(deepJsonEquals([1, 2], [1, 2, 3]), isFalse);
      expect(deepJsonEquals([1, 2], [2, 1]), isFalse);
      expect(deepJsonEquals({'a': 1}, {'b': 1}), isFalse);
      expect(deepJsonEquals({'a': 1}, {'a': 2}), isFalse);
      expect(deepJsonEquals('a', 'b'), isFalse);
      expect(deepJsonEquals(null, {}), isFalse);
    });
  });
}
