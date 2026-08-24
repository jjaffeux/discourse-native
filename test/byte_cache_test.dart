import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('rejects unsafe image URLs before reaching the transport', () async {
    final requested = <Uri>[];
    final cache = _TestByteCache(
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes([1], 200);
      }),
    );

    expect(await cache.load('http://images.example/avatar.png'), isNull);
    expect(await cache.load('//images.example/avatar.png'), isNull);
    expect(requested, isEmpty);

    expect(
      await cache.load('http://localhost:4200/avatar.png'),
      orderedEquals([1]),
    );
    expect(requested, [Uri.parse('http://localhost:4200/avatar.png')]);
  });

  test('never serves an unsafe URL from persistent storage', () async {
    final store = _SeededByteCacheStore()
      ..entries['http://images.example/avatar.png'] = Uint8List.fromList([
        1,
        2,
        3,
      ]);
    final requested = <Uri>[];
    final cache = _TestByteCache(
      store: store,
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes([4], 200);
      }),
    );

    expect(await cache.load('http://images.example/avatar.png'), isNull);
    expect(store.readUrls, isEmpty);
    expect(requested, isEmpty);
  });

  test('follows a bounded safe redirect explicitly', () async {
    final requested = <Uri>[];
    final cache = _TestByteCache(
      client: MockClient((request) async {
        requested.add(request.url);
        expect(request.followRedirects, isFalse);
        if (request.url.host == 'site.test') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://cdn.test/avatar.png'},
          );
        }
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );

    expect(
      await cache.load('https://site.test/avatar.png'),
      orderedEquals([1, 2, 3]),
    );
    expect(requested, [
      Uri.parse('https://site.test/avatar.png'),
      Uri.parse('https://cdn.test/avatar.png'),
    ]);
  });

  test('rejects an HTTPS redirect downgrade before following it', () async {
    final requested = <Uri>[];
    final cache = _TestByteCache(
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response(
          '',
          302,
          headers: {'location': 'http://localhost:4200/avatar.png'},
        );
      }),
    );

    expect(await cache.load('https://site.test/avatar.png'), isNull);
    expect(requested, [Uri.parse('https://site.test/avatar.png')]);
  });

  test('stops after the configured number of safe redirects', () async {
    var requests = 0;
    final cache = _TestByteCache(
      maxRedirects: 2,
      client: MockClient((request) async {
        requests++;
        return http.Response(
          '',
          302,
          headers: {'location': '/redirect-$requests.png'},
        );
      }),
    );

    expect(await cache.load('https://site.test/avatar.png'), isNull);
    expect(requests, 3);
  });

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

  test('clear prevents a stale response from repopulating disk', () async {
    final staleResponse = Completer<http.Response>();
    final store = _RecordingByteCacheStore();
    var requests = 0;
    final cache = _TestByteCache(
      store: store,
      client: MockClient((_) {
        requests++;
        if (requests == 1) return staleResponse.future;
        return Future.value(
          http.Response.bytes(
            [2],
            200,
            headers: {'cache-control': 'public, max-age=3600, immutable'},
          ),
        );
      }),
    );
    const url = 'https://site.test/image';

    final stale = cache.load(url);
    await Future<void>.delayed(Duration.zero);
    cache.clear();
    staleResponse.complete(
      http.Response.bytes(
        [1],
        200,
        headers: {'cache-control': 'public, max-age=3600, immutable'},
      ),
    );

    expect(await stale, orderedEquals([1]));
    expect(store.writes, isEmpty);

    expect(await cache.load(url), orderedEquals([2]));
    expect(store.writes, hasLength(1));
    expect(store.writes.single.url, url);
    expect(store.writes.single.bytes, orderedEquals([2]));
  });

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

  test(
    'bounds queued media work per origin and reuses capacity in FIFO order',
    () async {
      final coordinator = MediaRequestCoordinator(
        maxConcurrentPerOrigin: 1,
        maxQueuedPerOrigin: 2,
      );
      addTearDown(coordinator.close);
      final origin = Uri.parse('https://cdn.test');

      final firstLease = await coordinator.acquire(origin.resolve('/first'));
      final second = coordinator.acquire(origin.resolve('/second'));
      var thirdGranted = false;
      final third = coordinator.acquire(origin.resolve('/third')).then((lease) {
        thirdGranted = true;
        return lease;
      });

      await expectLater(
        coordinator.acquire(origin.resolve('/overflow')),
        throwsA(
          isA<MediaRequestOverloadException>()
              .having((error) => error.origin, 'origin', 'https://cdn.test')
              .having((error) => error.maxQueued, 'maxQueued', 2),
        ),
      );

      firstLease.release();
      final secondLease = await second;
      expect(thirdGranted, isFalse, reason: 'the oldest waiter runs first');
      secondLease.release();
      final thirdLease = await third;
      thirdLease.release();

      final afterDrain = await coordinator.acquire(origin.resolve('/later'));
      afterDrain.release();
    },
  );

  test(
    'shares concurrency and a 429 circuit breaker across media caches',
    () async {
      final coordinator = MediaRequestCoordinator(
        maxConcurrentPerOrigin: 2,
        defaultRateLimitCooldown: const Duration(milliseconds: 40),
      );
      addTearDown(coordinator.close);
      final rateLimitedResponse = Completer<void>();
      final activeResponse = Completer<void>();
      final rateLimitedStarted = Completer<void>();
      final activeStarted = Completer<void>();
      final requested = <Uri>[];
      var active = 0;
      var maximumActive = 0;

      final client = MockClient((request) async {
        requested.add(request.url);
        active++;
        maximumActive = maximumActive < active ? active : maximumActive;
        try {
          switch (request.url.path) {
            case '/rate-limited':
              rateLimitedStarted.complete();
              await rateLimitedResponse.future;
              return http.Response('slow down', 429);
            case '/active':
              activeStarted.complete();
              await activeResponse.future;
              return http.Response.bytes([2], 200);
            default:
              return http.Response.bytes([3], 200);
          }
        } finally {
          active--;
        }
      });
      final avatars = _TestByteCache(
        client: client,
        coordinator: coordinator,
        retryAfter: const Duration(milliseconds: 40),
      );
      final emoji = _TestByteCache(
        client: client,
        coordinator: coordinator,
        retryAfter: const Duration(milliseconds: 40),
      );
      final otherOrigin = _TestByteCache(
        client: client,
        coordinator: coordinator,
      );

      final limited = avatars.load('https://site.test/rate-limited');
      await rateLimitedStarted.future;
      final held = emoji.load('https://site.test/active');
      await activeStarted.future;
      final queued = <Future<Uint8List?>>[
        for (var index = 0; index < 5; index++)
          avatars.load('https://site.test/avatar-$index'),
        for (var index = 0; index < 5; index++)
          emoji.load('https://site.test/emoji-$index'),
      ];
      await Future<void>.delayed(Duration.zero);

      expect(requested, hasLength(2));
      expect(maximumActive, 2);
      rateLimitedResponse.complete();
      expect(await limited, isNull);
      await Future<void>.delayed(Duration.zero);

      expect(
        requested.where((url) => url.host == 'site.test'),
        hasLength(2),
        reason: 'distinct queued URLs must not drain after the first 429',
      );
      expect(
        await otherOrigin.load('https://other.test/emoji'),
        orderedEquals([3]),
        reason: 'the circuit breaker is scoped to one origin',
      );

      activeResponse.complete();
      expect(await held, orderedEquals([2]));
      expect(await Future.wait(queued), everyElement(isNull));
      expect(maximumActive, 2);
    },
  );

  testWidgets('closing a coordinator makes an active lease inert', (
    tester,
  ) async {
    final coordinator = MediaRequestCoordinator();
    final lease = await coordinator.acquire(
      Uri.parse('https://cdn.test/avatar.png'),
    );

    coordinator.close();
    lease.rateLimited({'retry-after': '3600'});
    lease.release();
    await tester.pump();

    await expectLater(
      coordinator.acquire(Uri.parse('https://cdn.test/other.png')),
      throwsA(isA<StateError>()),
    );
  });

  test('bounds persistent reads with the cache work semaphore', () async {
    final store = _BlockingByteCacheStore();
    final cache = _TestByteCache(
      maxConcurrent: 2,
      store: store,
      client: MockClient((_) async => http.Response.bytes([1], 200)),
    );

    final loads = [
      for (var index = 0; index < 8; index++)
        cache.load('https://site.test/avatar-$index'),
    ];
    await store.twoReadsStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(store.reads, 2);
    expect(store.maximumActive, 2);

    store.releaseReads.complete();
    expect(await Future.wait(loads), everyElement(orderedEquals([1])));
    expect(store.reads, 8);
    expect(store.maximumActive, 2);
  });

  test('a no-store redirect keeps public final bytes process-local', () async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileByteCacheStore(directory);
    await store.initialize();
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      if (request.url.host == 'site.test') {
        return http.Response(
          '',
          302,
          headers: {
            'location': 'https://cdn.test/avatar.png',
            'cache-control': 'no-store',
          },
        );
      }
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'cache-control': 'public, max-age=3600, immutable'},
      );
    });
    const url = 'https://site.test/avatar.png';

    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([1, 2, 3]),
    );
    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([1, 2, 3]),
    );

    expect(requested, [
      Uri.parse(url),
      Uri.parse('https://cdn.test/avatar.png'),
      Uri.parse(url),
      Uri.parse('https://cdn.test/avatar.png'),
    ]);
  });

  test('persistent policy handles directives and Vary conservatively', () {
    final now = DateTime.utc(2026, 8, 11, 12);
    final forbidden = <Map<String, String>>[
      {'Cache-Control': 'public, no-cache="etag, last-modified", max-age=3600'},
      {
        'cache-control':
            'public, private="set-cookie, authorization", max-age=3600',
      },
      {'Cache-Control': 'PUBLIC, NO-STORE, MAX-AGE=3600'},
      {'cache-control': 'public, max-age=3600', 'Vary': 'accept-encoding, *'},
    ];

    for (final headers in forbidden) {
      expect(
        responseAllowsPersistentByteCache(headers),
        isFalse,
        reason: '$headers',
      );
      expect(
        persistentByteCacheExpiry(headers, now),
        isNull,
        reason: '$headers',
      );
    }

    expect(
      persistentByteCacheExpiry({
        'cache-control': 'public, max-age=60, s-maxage=120',
        'age': '20',
      }, now),
      now.add(const Duration(seconds: 100)),
    );
  });

  test('pruning removes stale temporary files but not a live writer', () async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime.utc(2026, 8, 11, 12);
    final stale = File('${directory.path}/stale.tmp');
    final recent = File('${directory.path}/recent.tmp');
    await stale.writeAsBytes([1]);
    await recent.writeAsBytes([1]);
    await stale.setLastModified(now.subtract(const Duration(hours: 2)));
    await recent.setLastModified(now);

    await FileByteCacheStore(directory, clock: () => now).initialize();

    expect(await stale.exists(), isFalse);
    expect(await recent.exists(), isTrue);
  });

  test('rejects an oversized disk entry before returning its bytes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final now = DateTime.utc(2026, 8, 11, 12);
    final store = FileByteCacheStore(
      directory,
      maxEntryBytes: 4,
      clock: () => now,
    );
    await store.initialize();
    const url = 'https://cdn.test/oversized.png';
    await store.write(
      url,
      Uint8List.fromList([1, 2, 3, 4]),
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final entry = await directory
        .list()
        .where((entity) => entity.path.endsWith('.bin'))
        .cast<File>()
        .single;
    await entry.writeAsBytes(List<int>.filled(128, 9), mode: FileMode.append);

    expect(await store.read(url), isNull);
    expect(await entry.exists(), isFalse);
  });

  test('reuses fresh immutable bytes across cache instances', () async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileByteCacheStore(directory);
    await store.initialize();
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'cache-control': 'public, max-age=3600, immutable'},
      );
    });
    const url = 'https://cdn.test/avatar.png';

    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([1, 2, 3]),
    );
    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([1, 2, 3]),
    );

    expect(requests, 1, reason: 'the second cache represents a warm relaunch');
  });

  test('does not persist responses which forbid shared caching', () async {
    final directory = await Directory.systemTemp.createTemp(
      'discourse-native-byte-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final store = FileByteCacheStore(directory);
    await store.initialize();
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response.bytes(
        [requests],
        200,
        headers: {'cache-control': 'private, no-store, max-age=3600'},
      );
    });
    const url = 'https://cdn.test/private.png';

    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([1]),
    );
    expect(
      await _TestByteCache(client: client, store: store).load(url),
      orderedEquals([2]),
    );
    expect(requests, 2);
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
    super.maxRedirects,
    super.retryAfter,
    super.coordinator,
    super.store,
  });

  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}

final class _BlockingByteCacheStore implements ByteCacheStore {
  final Completer<void> twoReadsStarted = Completer<void>();
  final Completer<void> releaseReads = Completer<void>();
  int reads = 0;
  int _active = 0;
  int maximumActive = 0;

  @override
  Future<Uint8List?> read(String url) async {
    reads++;
    _active++;
    if (_active > maximumActive) maximumActive = _active;
    if (_active == 2 && !twoReadsStarted.isCompleted) {
      twoReadsStarted.complete();
    }
    await releaseReads.future;
    _active--;
    return null;
  }

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async {}
}

final class _RecordingByteCacheStore implements ByteCacheStore {
  final List<({String url, Uint8List bytes})> writes = [];

  @override
  Future<Uint8List?> read(String url) async => null;

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async {
    writes.add((url: url, bytes: bytes));
  }
}

final class _SeededByteCacheStore implements ByteCacheStore {
  final Map<String, Uint8List> entries = {};
  final List<String> readUrls = [];

  @override
  Future<Uint8List?> read(String url) async {
    readUrls.add(url);
    return entries[url];
  }

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async {
    entries[url] = bytes;
  }
}
