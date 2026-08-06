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
      // Not an error: a quote rendered outside the shell falls back to the
      // shortcode, which is what it did before emoji rendered at all.
      expect(absoluteEmojiUrl('/images/emoji/twitter/tada.png', null), isNull);
      expect(absoluteEmojiUrl(null, 'https://site'), isNull);
      expect(absoluteEmojiUrl('', 'https://site'), isNull);
    });
  });

  group('load', () {
    test(
      'fetches a given url once, however many times it is asked for',
      () async {
        // The point of the cache: the same handful of emoji repeat across every
        // post on a site.
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

    test('never has more than maxConcurrent requests in flight', () async {
      // A post can carry thirty emoji and a screen six posts, so this cap is
      // the whole reason this is not an Image.network.
      var active = 0;
      var peak = 0;
      final gate = Completer<void>();

      final cache = EmojiCache(
        maxConcurrent: 3,
        client: MockClient((_) async {
          active++;
          peak = peak > active ? peak : active;
          await gate.future;
          active--;
          return http.Response.bytes(pngBytes, 200);
        }),
      );

      final all = Future.wait([
        for (var i = 0; i < 30; i++) cache.load('https://site/$i.png'),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(peak, 3);

      gate.complete();
      await all;
      expect(peak, 3);
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
