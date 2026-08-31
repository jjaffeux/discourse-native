import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Uint8List pngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
]);

void main() {
  group('absoluteEmojiUrl', () {
    test('resolves the root-relative src Discourse cooks', () {
      expect(
        absoluteEmojiUrl(
          '/images/emoji/twitter/slight_smile.png?v=15',
          'https://meta.discourse.org',
        ),
        'https://meta.discourse.org/images/emoji/twitter/slight_smile.png?v=15',
      );
    });

    test('resolves a subfolder install without doubling its base path', () {
      // A subfolder site cooks its base path into the src already, so the
      // src resolves against the origin; appending it to the stored site URL
      // would fetch /forum/forum/... and 404 every standard emoji.
      expect(
        absoluteEmojiUrl(
          '/forum/images/emoji/twitter/tada.png?v=15',
          'https://example.com/forum',
        ),
        'https://example.com/forum/images/emoji/twitter/tada.png?v=15',
      );
    });

    test('leaves an absolute src alone, for a site behind a CDN', () {
      const url = 'https://cdn.example/images/emoji/twitter/tada.png';
      expect(absoluteEmojiUrl(url, 'https://meta.discourse.org'), url);
    });

    test('gives a protocol-relative src a scheme', () {
      expect(
        absoluteEmojiUrl('//cdn.example/emoji/tada.png', 'https://site'),
        'https://cdn.example/emoji/tada.png',
      );
    });

    test('answers nothing when there is no site to resolve against', () {
      expect(absoluteEmojiUrl('/images/emoji/twitter/tada.png', null), isNull);
      expect(absoluteEmojiUrl(null, 'https://site'), isNull);
      expect(absoluteEmojiUrl('', 'https://site'), isNull);
    });
  });

  group('EmojiCache.load', () {
    test(
      'fetches a given URL once, however many times it is requested',
      () async {
        var requests = 0;
        final cache = EmojiCache(
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(pngBytes, 200);
          }),
        );

        await Future.wait([
          cache.load('https://site/emoji/tada.png'),
          cache.load('https://site/emoji/tada.png'),
        ]);
        await cache.load('https://site/emoji/tada.png');

        expect(requests, 1);
        expect(cache.isCached('https://site/emoji/tada.png'), isTrue);
      },
    );

    test(
      'remembers a rate limit rather than retrying it on every rebuild',
      () async {
        var requests = 0;
        final cache = EmojiCache(
          client: MockClient((_) async {
            requests++;
            return http.Response('slow down', 429);
          }),
        );

        expect(await cache.load('https://site/a.png'), isNull);
        expect(await cache.load('https://site/a.png'), isNull);
        expect(requests, 1);
      },
    );

    test('retries a rate limit once it has cooled down', () async {
      var requests = 0;
      final cache = EmojiCache(
        retryAfter: Duration.zero,
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('slow down', 429)
              : http.Response.bytes(pngBytes, 200);
        }),
      );

      expect(await cache.load('https://site/a.png'), isNull);
      expect(await cache.load('https://site/a.png'), isNotNull);
      expect(requests, 2);
    });

    test('never retries an emoji the site does not have', () async {
      var requests = 0;
      final cache = EmojiCache(
        retryAfter: Duration.zero,
        client: MockClient((_) async {
          requests++;
          return http.Response('gone', 404);
        }),
      );

      expect(await cache.load('https://site/nope.png'), isNull);
      expect(await cache.load('https://site/nope.png'), isNull);
      expect(requests, 1);
    });

    test(
      'treats a network failure as unavailable rather than throwing',
      () async {
        final cache = EmojiCache(
          client: MockClient((_) async => throw const _Down()),
        );

        expect(await cache.load('https://site/a.png'), isNull);
      },
    );

    test('does not throttle a cold picker by default', () async {
      var active = 0;
      var peak = 0;
      final gate = Completer<void>();

      final cache = EmojiCache(
        client: MockClient((_) async {
          active++;
          peak = peak > active ? peak : active;
          await gate.future;
          active--;
          return http.Response.bytes(pngBytes, 200);
        }),
      );

      final all = Future.wait([
        for (var i = 0; i < 30; i++) cache.load('https://cdn.site/$i.png'),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(peak, 30);

      gate.complete();
      await all;
    });

    test('forgets an empty body rather than caching a blank image', () async {
      final cache = EmojiCache(
        client: MockClient((_) async => http.Response('', 200)),
      );

      expect(await cache.load('https://site/a.png'), isNull);
    });
  });
}

class _Down implements Exception {
  const _Down();
}
