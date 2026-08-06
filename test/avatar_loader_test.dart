import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/avatar_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List bytes(String s) => Uint8List.fromList(s.codeUnits);

/// A one-pixel PNG header is enough to be recognisably not-SVG.
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
  group('looksLikeSvg', () {
    test('believes an svg content type', () {
      expect(
        AvatarLoader.looksLikeSvg(pngBytes, contentType: 'image/svg+xml'),
        isTrue,
      );
    });

    test('believes a declared raster type without sniffing', () {
      expect(
        AvatarLoader.looksLikeSvg(
          bytes('<svg xmlns="..."></svg>'),
          contentType: 'image/png',
        ),
        isFalse,
      );
    });

    test('sniffs when the type is missing or unhelpful', () {
      expect(
        AvatarLoader.looksLikeSvg(bytes('<svg width="10"></svg>')),
        isTrue,
      );
      expect(
        AvatarLoader.looksLikeSvg(
          bytes('<?xml version="1.0"?><svg></svg>'),
          contentType: 'application/octet-stream',
        ),
        isTrue,
      );
      expect(AvatarLoader.looksLikeSvg(pngBytes), isFalse);
    });
  });

  group('load', () {
    test('reports the format Discourse actually served', () async {
      final loader = AvatarLoader(
        client: MockClient(
          (_) async => http.Response.bytes(
            bytes('<svg></svg>'),
            200,
            // The URL says .png; only the response tells the truth.
            headers: {'content-type': 'image/svg+xml'},
          ),
        ),
      );

      final result = await loader.load('https://site/avatar/90/1.png');
      expect(result, isNotNull);
      expect(result!.isSvg, isTrue);
    });

    test(
      'fetches a given url once, however many times it is asked for',
      () async {
        var requests = 0;
        final loader = AvatarLoader(
          client: MockClient((_) async {
            requests++;
            return http.Response.bytes(pngBytes, 200);
          }),
        );

        await Future.wait([
          loader.load('https://site/a.png'),
          loader.load('https://site/a.png'),
        ]);
        await loader.load('https://site/a.png');

        expect(requests, 1);
        expect(loader.isCached('https://site/a.png'), isTrue);
      },
    );

    test('remembers a rate-limited avatar as unavailable', () async {
      var requests = 0;
      final loader = AvatarLoader(
        client: MockClient((_) async {
          requests++;
          return http.Response('slow down', 429);
        }),
      );

      expect(await loader.load('https://site/a.png'), isNull);
      expect(await loader.load('https://site/a.png'), isNull);

      // Retrying a 429 on every rebuild is what caused the problem.
      expect(requests, 1);
    });

    test('retries a rate limit once it has cooled down', () async {
      var requests = 0;
      final loader = AvatarLoader(
        // Effectively no cooldown, so the retry is observable.
        retryAfter: Duration.zero,
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response('slow down', 429)
              : http.Response.bytes(pngBytes, 200);
        }),
      );

      expect(await loader.load('https://site/a.png'), isNull);
      // A rate limit is temporary; blanking the avatar until restart is worse
      // than asking again later.
      expect(await loader.load('https://site/a.png'), isNotNull);
      expect(requests, 2);
    });

    test('never retries a permanent failure', () async {
      var requests = 0;
      final loader = AvatarLoader(
        retryAfter: Duration.zero,
        client: MockClient((_) async {
          requests++;
          return http.Response('gone', 404);
        }),
      );

      expect(await loader.load('https://site/a.png'), isNull);
      expect(await loader.load('https://site/a.png'), isNull);
      expect(requests, 1);
    });

    test(
      'treats a network failure as unavailable rather than throwing',
      () async {
        final loader = AvatarLoader(
          client: MockClient((_) async => throw const _Down()),
        );

        expect(await loader.load('https://site/a.png'), isNull);
      },
    );

    test('never has more than maxConcurrent requests in flight', () async {
      var active = 0;
      var peak = 0;
      final gate = Completer<void>();

      final loader = AvatarLoader(
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
        for (var i = 0; i < 20; i++) loader.load('https://site/$i.png'),
      ]);

      // Let the first wave start before releasing them.
      await Future<void>.delayed(Duration.zero);
      expect(peak, 3);

      gate.complete();
      await all;
      expect(peak, 3);
    });
  });
}

class _Down implements Exception {
  const _Down();
}
