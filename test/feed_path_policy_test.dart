import 'package:discourse_native/src/models/feed_path_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bounds the canonical encoded request, including literal Unicode', () {
    const prefix = '/latest.json?search=';
    final atLimit =
        '$prefix${'x' * (FeedPathPolicy.maximumEncodedLength - prefix.length)}';
    expect(FeedPathPolicy.accepts(atLimit), isTrue);
    expect(FeedPathPolicy.accepts('${atLimit}x'), isFalse);

    final literal =
        '$prefix${'中' * (FeedPathPolicy.maximumEncodedLength ~/ 9)}';
    expect(literal.length, lessThan(FeedPathPolicy.maximumEncodedLength));
    expect(
      Uri.parse(literal).toString().length,
      greaterThan(FeedPathPolicy.maximumEncodedLength),
    );
    expect(FeedPathPolicy.accepts(literal), isFalse);
  });

  test('keeps the original path bound separately from query expansion', () {
    final atLimit = '/${'a' * (FeedPathPolicy.maximumPathLength - 6)}.json';
    expect(atLimit, hasLength(FeedPathPolicy.maximumPathLength));
    expect(FeedPathPolicy.accepts('$atLimit?search=valid'), isTrue);
    expect(FeedPathPolicy.accepts('/a$atLimit'), isFalse);
  });

  test('accepts bounded Unicode searches and repeated encoded filters', () {
    for (final query in ['中' * 2048, '😀' * 1024]) {
      final path = Uri(
        path: '/c/support/12.json',
        queryParameters: {
          'search': query,
          'tags[]': ['help wanted', 'mobile'],
        },
      ).toString();
      expect(FeedPathPolicy.accepts(path), isTrue);
    }
  });

  test('rejects unsafe endpoints and lazily malformed UTF-8', () {
    for (final path in <Object?>[
      null,
      42,
      '',
      'latest.json',
      'https://other.example/latest.json',
      '//other.example/latest.json',
      '/latest',
      '/latest.json#private',
      '/%FF.json',
      '/%C3%28.json',
      '/latest.json?q=%FF',
      '/latest.json?tags[]=%E0%80%80',
    ]) {
      expect(FeedPathPolicy.accepts(path), isFalse, reason: '$path');
    }
  });
}
