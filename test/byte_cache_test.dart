import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('coalesces in-flight requests and reuses the cached result', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final cache = _TestByteCache(
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    );

    final first = cache.load('https://site.test/image');
    final second = cache.load('https://site.test/image');
    await Future<void>.delayed(Duration.zero);

    expect(requests, 1);

    response.complete(http.Response.bytes([1, 2, 3], 200));
    final results = await Future.wait([first, second]);

    expect(results, everyElement(orderedEquals([1, 2, 3])));
    expect(await cache.load('https://site.test/image'), [1, 2, 3]);
    expect(requests, 1);
  });

  test(
    'clear rejects stale cache writes and preserves a newer request',
    () async {
      final responses = List.generate(3, (_) => Completer<http.Response>());
      var requests = 0;
      final cache = _TestByteCache(
        client: MockClient((_) => responses[requests++].future),
      );
      const url = 'https://site.test/image';

      final old = cache.load(url);
      await Future<void>.delayed(Duration.zero);
      cache.clear();
      final fresh = cache.load(url);
      await Future<void>.delayed(Duration.zero);

      responses[0].complete(http.Response.bytes([1], 200));
      expect(await old, orderedEquals([1]));
      expect(cache.isCached(url), isFalse);

      final coalesced = cache.load(url);
      await Future<void>.delayed(Duration.zero);
      for (var index = 1; index < requests; index++) {
        responses[index].complete(http.Response.bytes([2], 200));
      }

      final results = await Future.wait([fresh, coalesced]);
      expect(results[0], orderedEquals([2]));
      expect(results[1], orderedEquals([2]));
      expect(requests, 2);
      expect(cache.cached(url), orderedEquals([2]));
    },
  );

  test('clear drops queued stale requests before transport', () async {
    final activeResponse = Completer<http.Response>();
    final requested = <String>[];
    final cache = _TestByteCache(
      maxConcurrent: 1,
      client: MockClient((request) {
        final name = request.url.pathSegments.single;
        requested.add(name);
        if (name == 'active') return activeResponse.future;
        return Future.value(http.Response.bytes([name.length], 200));
      }),
    );

    final active = cache.load('https://site.test/active');
    await Future<void>.delayed(Duration.zero);
    final stale = cache.load('https://site.test/stale');
    await Future<void>.delayed(Duration.zero);
    expect(requested, ['active']);

    cache.clear();
    expect(await stale, isNull);

    final fresh = cache.load('https://site.test/fresh');
    await Future<void>.delayed(Duration.zero);
    expect(requested, ['active']);

    activeResponse.complete(http.Response.bytes([1], 200));
    expect(await active, orderedEquals([1]));
    expect(await fresh, orderedEquals([5]));
    expect(requested, ['active', 'fresh']);
  });

  test('bounds unique work waiting behind the semaphore', () async {
    final activeResponse = Completer<http.Response>();
    final requested = <String>[];
    final cache = _TestByteCache(
      maxConcurrent: 1,
      maxEntries: 2,
      client: MockClient((request) {
        final name = request.url.pathSegments.single;
        requested.add(name);
        if (name == 'active') return activeResponse.future;
        return Future.value(http.Response.bytes([name.length], 200));
      }),
    );

    final active = cache.load('https://site.test/active');
    await Future<void>.delayed(Duration.zero);
    final queued = cache.load('https://site.test/queued');
    final overflow = cache.load('https://site.test/overflow');

    expect(await overflow, isNull);
    expect(requested, ['active']);

    activeResponse.complete(http.Response.bytes([1], 200));
    await Future.wait([active, queued]);
    expect(requested, ['active', 'queued']);

    expect(await cache.load('https://site.test/overflow'), orderedEquals([8]));
    expect(requested, ['active', 'queued', 'overflow']);
  });

  test(
    'rejects a declared oversized response before reading its body',
    () async {
      var requests = 0;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);

      final cache = _TestByteCache(
        maxResponseBytes: 4,
        client: MockClient.streaming((request, _) async {
          requests++;
          return http.StreamedResponse(
            body.stream,
            200,
            contentLength: 5,
            request: request,
          );
        }),
      );

      expect(await cache.load('https://site.test/too-large'), isNull);
      expect(cancelled, isTrue);
      expect(cache.isCached('https://site.test/too-large'), isTrue);

      expect(await cache.load('https://site.test/too-large'), isNull);
      expect(requests, 1);
    },
  );

  testWidgets('rejected response cleanup does not leave a timeout timer', (
    tester,
  ) async {
    final cache = _TestByteCache(
      client: MockClient((_) async => http.Response('', 404)),
    );

    unawaited(cache.load('https://site.test/missing'));
    await tester.pump();

    expect(cache.isCached('https://site.test/missing'), isTrue);
  });

  testWidgets('a successful stream completes under widget fake time', (
    _,
  ) async {
    final cache = _TestByteCache(
      client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)),
    );

    expect(
      await cache.load('https://site.test/widget-image'),
      orderedEquals([1, 2, 3]),
    );
  });

  test(
    'stops an unbounded stream as soon as it crosses the response limit',
    () async {
      var yieldedChunks = 0;

      Stream<List<int>> oversizedBody() async* {
        for (var i = 0; i < 100; i++) {
          yieldedChunks++;
          yield [1, 2, 3, 4];
        }
      }

      final cache = _TestByteCache(
        maxResponseBytes: 6,
        client: MockClient.streaming(
          (request, _) async =>
              http.StreamedResponse(oversizedBody(), 200, request: request),
        ),
      );

      expect(await cache.load('https://site.test/stream'), isNull);
      expect(yieldedChunks, 2);
      expect(cache.isCached('https://site.test/stream'), isTrue);
    },
  );

  test('cancels a body whose headers arrive after the timeout', () async {
    var cancelled = false;
    final response = Completer<http.StreamedResponse>();
    final body = StreamController<List<int>>(onCancel: () => cancelled = true);
    addTearDown(body.close);
    final cache = _TestByteCache(
      timeout: const Duration(milliseconds: 100),
      client: MockClient.streaming((request, _) => response.future),
    );

    expect(await cache.load('https://site.test/slow'), isNull);
    response.complete(http.StreamedResponse(body.stream, 200));
    await Future<void>.delayed(Duration.zero);

    expect(cancelled, isTrue);
  });

  test(
    'evicts least-recently-used entries to stay within the byte budget',
    () async {
      final requests = <String, int>{};
      final cache = _TestByteCache(
        maxResponseBytes: 3,
        maxCachedBytes: 6,
        client: MockClient((request) async {
          final key = request.url.pathSegments.single;
          requests.update(key, (count) => count + 1, ifAbsent: () => 1);
          return http.Response.bytes([key.codeUnitAt(0), 1, 2], 200);
        }),
      );

      await cache.load('https://site.test/a');
      await cache.load('https://site.test/b');
      await cache.load('https://site.test/a');
      await cache.load('https://site.test/c');

      expect(cache.isCached('https://site.test/a'), isTrue);
      expect(cache.isCached('https://site.test/b'), isFalse);
      expect(cache.isCached('https://site.test/c'), isTrue);
      expect(requests, {'a': 1, 'b': 1, 'c': 1});

      await cache.load('https://site.test/b');
      expect(requests['b'], 2);
    },
  );

  test('synchronous cache reads keep a visible image recent', () async {
    final cache = _TestByteCache(
      maxEntries: 2,
      client: MockClient(
        (request) async => http.Response.bytes([
          request.url.pathSegments.single.codeUnitAt(0),
        ], 200),
      ),
    );

    await cache.load('https://site.test/a');
    await cache.load('https://site.test/b');
    expect(cache.cached('https://site.test/a'), orderedEquals([97]));

    await cache.load('https://site.test/c');

    expect(cache.isCached('https://site.test/a'), isTrue);
    expect(cache.isCached('https://site.test/b'), isFalse);
    expect(cache.isCached('https://site.test/c'), isTrue);
  });

  test('bounds cooldown records along with cached entries', () async {
    final requests = <String, int>{};
    final cache = _TestByteCache(
      maxEntries: 2,
      client: MockClient((request) async {
        final key = request.url.pathSegments.single;
        requests.update(key, (count) => count + 1, ifAbsent: () => 1);
        return http.Response('', 503);
      }),
    );

    await cache.load('https://site.test/a');
    await cache.load('https://site.test/b');
    await cache.load('https://site.test/c');
    await cache.load('https://site.test/a');

    expect(requests, {'a': 2, 'b': 1, 'c': 1});
  });
}

class _TestByteCache extends ByteCache<Uint8List> {
  _TestByteCache({
    required super.client,
    super.maxConcurrent,
    super.maxEntries = 2000,
    super.maxResponseBytes = 1024,
    super.maxCachedBytes = 4096,
    super.timeout = const Duration(seconds: 10),
  });

  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}
