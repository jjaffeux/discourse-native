import 'dart:async';
import 'dart:io' show HttpDate;
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache_store.dart';
import 'package:discourse_native/src/data/media_pipeline.dart';
import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:discourse_native/src/data/origin_cooldown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/manual_scheduler.dart';

void main() {
  test(
    'avatar and emoji work share aggregate and per-origin concurrency caps',
    () async {
      final release = Completer<void>();
      final firstWaveStarted = Completer<void>();
      var active = 0;
      var maximumActive = 0;
      final activeByOrigin = <String, int>{};
      final maximumByOrigin = <String, int>{};
      final requests = <Uri>[];
      final pipeline = MediaPipeline(
        maxConcurrent: 3,
        maxConcurrentPerOrigin: 2,
        client: MockClient((request) async {
          requests.add(request.url);
          active++;
          maximumActive = maximumActive < active ? active : maximumActive;
          final origin = request.url.origin;
          final originActive = (activeByOrigin[origin] ?? 0) + 1;
          activeByOrigin[origin] = originActive;
          final originMaximum = maximumByOrigin[origin] ?? 0;
          if (originActive > originMaximum) {
            maximumByOrigin[origin] = originActive;
          }
          if (active == 3 && !firstWaveStarted.isCompleted) {
            firstWaveStarted.complete();
          }
          await release.future;
          active--;
          activeByOrigin[origin] = originActive - 1;
          return http.Response.bytes([1], 200);
        }),
      );
      addTearDown(pipeline.close);

      final firstAvatar = pipeline.avatars.load('https://one.test/avatar-1');
      final sameUrlEmoji = pipeline.emoji.load('https://one.test/avatar-1');
      final loads = <Future<Object?>>[
        firstAvatar,
        sameUrlEmoji,
        pipeline.emoji.load('https://one.test/emoji-1'),
        pipeline.avatars.load('https://one.test/avatar-2'),
        pipeline.emoji.load('https://two.test/emoji-1'),
        pipeline.avatars.load('https://two.test/avatar-1'),
        pipeline.emoji.load('https://two.test/emoji-2'),
      ];

      await firstWaveStarted.future;
      expect(active, 3);
      expect(maximumActive, 3);
      expect(maximumByOrigin['https://one.test'], 2);
      expect(requests, hasLength(3));

      release.complete();
      expect(await Future.wait(loads), everyElement(isNotNull));
      expect(maximumActive, 3);
      expect(maximumByOrigin, {'https://one.test': 2, 'https://two.test': 2});
      expect(
        requests.where(
          (url) => url.origin == 'https://one.test' && url.path == '/avatar-1',
        ),
        hasLength(1),
        reason: 'the typed caches share one raw transfer for an exact URL',
      );
    },
  );

  test('the default cap starts a wide emoji picker burst', () async {
    final release = Completer<void>();
    final burstStarted = Completer<void>();
    final requested = <Uri>[];
    final pipeline = MediaPipeline(
      client: MockClient((request) async {
        requested.add(request.url);
        if (requested.length ==
                MediaRequestCoordinator.defaultMaxConcurrentPerOrigin &&
            !burstStarted.isCompleted) {
          burstStarted.complete();
        }
        await release.future;
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(pipeline.close);

    final loads = [
      for (var index = 0; index < 20; index++)
        pipeline.emoji.load('https://emoji.test/$index.png'),
    ];
    await burstStarted.future;

    expect(
      requested,
      hasLength(MediaRequestCoordinator.defaultMaxConcurrentPerOrigin),
    );
    release.complete();
    expect(await Future.wait(loads), everyElement(isNotNull));
  });

  test('picker emoji overtake queued avatar work', () async {
    final firstStarted = Completer<void>();
    final pickerStarted = Completer<void>();
    final queuedAvatarStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    final releasePicker = Completer<void>();
    final releaseQueuedAvatar = Completer<void>();
    final requested = <String>[];
    final pipeline = MediaPipeline(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      client: MockClient((request) async {
        final path = request.url.path;
        requested.add(path);
        switch (path) {
          case '/active-avatar':
            firstStarted.complete();
            await releaseFirst.future;
            break;
          case '/picker-emoji':
            pickerStarted.complete();
            await releasePicker.future;
            break;
          case '/queued-avatar':
            queuedAvatarStarted.complete();
            await releaseQueuedAvatar.future;
            break;
        }
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(pipeline.close);

    final active = pipeline.avatars.load('https://media.test/active-avatar');
    await firstStarted.future;
    final queuedAvatar = pipeline.avatars.load(
      'https://media.test/queued-avatar',
    );
    final pickerEmoji = pipeline.emoji.load('https://media.test/picker-emoji');

    releaseFirst.complete();
    await pickerStarted.future;
    expect(requested, ['/active-avatar', '/picker-emoji']);
    expect(queuedAvatarStarted.isCompleted, isFalse);

    releasePicker.complete();
    await queuedAvatarStarted.future;
    releaseQueuedAvatar.complete();
    expect(
      await Future.wait([active, queuedAvatar, pickerEmoji]),
      everyElement(isNotNull),
    );
    expect(requested, ['/active-avatar', '/picker-emoji', '/queued-avatar']);
  });

  test('an avatar 429 cools down queued emoji on the same origin', () async {
    final scheduler = ManualScheduler();
    final limitedResponse = Completer<http.Response>();
    final limitedStarted = Completer<void>();
    final requested = <Uri>[];
    final pipeline = MediaPipeline(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      rateLimitCooldown: const Duration(minutes: 1),
      cooldownFactory: () => OriginCooldown(
        clock: scheduler.now,
        timerFactory: scheduler.createTimer,
      ),
      client: MockClient((request) async {
        requested.add(request.url);
        if (request.url.path == '/limited') {
          limitedStarted.complete();
          return limitedResponse.future;
        }
        return http.Response.bytes([2], 200);
      }),
    );
    addTearDown(pipeline.close);

    final limited = pipeline.avatars.load('https://media.test/limited');
    await limitedStarted.future;
    final queuedEmoji = pipeline.emoji.load('https://media.test/queued');
    limitedResponse.complete(http.Response('slow down', 429));

    expect(await limited, isNull);
    expect(await queuedEmoji, isNull);
    expect(requested.map((url) => url.path), ['/limited']);
    expect(
      await pipeline.emoji.load('https://media.test/during-cooldown'),
      isNull,
    );
    expect(requested.map((url) => url.path), ['/limited']);

    scheduler.advance(const Duration(minutes: 1));
    expect(
      (await pipeline.emoji.load('https://media.test/after-cooldown'))?.bytes,
      orderedEquals([2]),
    );
    expect(requested.map((url) => url.path), ['/limited', '/after-cooldown']);
  });

  test('a Retry-After date is measured against the pipeline clock', () async {
    final scheduler = ManualScheduler();
    final now = DateTime.utc(2000);
    final requested = <String>[];
    final pipeline = MediaPipeline(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      clock: () => now,
      cooldownFactory: () => OriginCooldown(
        clock: scheduler.now,
        timerFactory: scheduler.createTimer,
      ),
      client: MockClient((request) async {
        requested.add(request.url.path);
        if (request.url.path == '/limited') {
          return http.Response(
            'slow down',
            429,
            headers: {
              'retry-after': HttpDate.format(
                now.add(const Duration(seconds: 30)),
              ),
            },
          );
        }
        return http.Response.bytes([2], 200);
      }),
    );
    addTearDown(pipeline.close);

    expect(await pipeline.avatars.load('https://media.test/limited'), isNull);
    expect(
      await pipeline.emoji.load('https://media.test/during-cooldown'),
      isNull,
    );
    scheduler.advance(const Duration(seconds: 30));
    expect(
      (await pipeline.emoji.load('https://media.test/after-cooldown'))?.bytes,
      orderedEquals([2]),
    );
    expect(requested, ['/limited', '/after-cooldown']);
  });

  test('a failed URL is retried once the rate-limit cooldown passes', () async {
    var attempts = 0;
    final pipeline = MediaPipeline(
      rateLimitCooldown: const Duration(milliseconds: 1),
      client: MockClient(
        (_) async => ++attempts == 1
            ? http.Response('unavailable', 503)
            : http.Response.bytes([4], 200),
      ),
    );
    addTearDown(pipeline.close);
    const url = 'https://media.test/avatar';

    expect(await pipeline.avatars.load(url), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect((await pipeline.avatars.load(url))?.bytes, orderedEquals([4]));
  });

  test('the backlog cap bounds avatar and emoji work together', () async {
    final release = Completer<void>();
    final started = Completer<void>();
    final requested = <String>[];
    final pipeline = MediaPipeline(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      maxQueuedPerOrigin: 1,
      client: MockClient((request) async {
        requested.add(request.url.path);
        if (!started.isCompleted) started.complete();
        await release.future;
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(pipeline.close);
    final active = pipeline.avatars.load('https://media.test/active');
    await started.future;
    final queued = pipeline.emoji.load('https://media.test/queued');

    final overflow = pipeline.avatars.load('https://media.test/overflow');
    var overflowSettled = false;
    unawaited(overflow.then<void>((_) => overflowSettled = true));
    await pumpEventQueue();
    expect(overflowSettled, isTrue);
    expect(await overflow, isNull);

    release.complete();
    expect(await Future.wait([active, queued]), everyElement(isNotNull));
    expect(requested, ['/active', '/queued']);
  });

  test('avatar and emoji caches read through the pipeline store', () async {
    final store = _MemoryByteCacheStore({
      'https://media.test/avatar': Uint8List.fromList([7]),
      'https://media.test/emoji': Uint8List.fromList([8]),
    });
    final requested = <Uri>[];
    final pipeline = MediaPipeline(
      store: store,
      client: MockClient((request) async {
        requested.add(request.url);
        return http.Response.bytes([1], 200);
      }),
    );
    addTearDown(pipeline.close);

    expect(
      (await pipeline.avatars.load('https://media.test/avatar'))?.bytes,
      orderedEquals([7]),
    );
    expect(
      (await pipeline.emoji.load('https://media.test/emoji'))?.bytes,
      orderedEquals([8]),
    );
    expect(requested, isEmpty);
  });

  test('close empties both typed caches and cancels cooldowns', () async {
    final scheduler = ManualScheduler();
    final pipeline = MediaPipeline(
      rateLimitCooldown: const Duration(minutes: 1),
      cooldownFactory: () => OriginCooldown(
        clock: scheduler.now,
        timerFactory: scheduler.createTimer,
      ),
      client: MockClient(
        (request) async => request.url.host == 'limited.test'
            ? http.Response('slow down', 429)
            : http.Response.bytes([1], 200),
      ),
    );
    const avatarUrl = 'https://media.test/avatar';
    const emojiUrl = 'https://media.test/emoji';
    await pipeline.avatars.load(avatarUrl);
    await pipeline.emoji.load(emojiUrl);
    expect(await pipeline.avatars.load('https://limited.test/avatar'), isNull);
    expect(pipeline.avatars.isCached(avatarUrl), isTrue);
    expect(pipeline.emoji.isCached(emojiUrl), isTrue);
    expect(scheduler.activeTimerCount, 1);

    pipeline.close();

    expect(pipeline.avatars.isCached(avatarUrl), isFalse);
    expect(pipeline.emoji.isCached(emojiUrl), isFalse);
    expect(scheduler.activeTimerCount, 0);
  });

  test('close aborts active work and drops queued work', () async {
    final client = _AbortRecordingClient();
    final pipeline = MediaPipeline(
      client: client,
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
    );
    final active = pipeline.avatars.load('https://media.test/avatar');
    await client.started.future;
    final queued = pipeline.emoji.load('https://media.test/emoji');

    pipeline.close();

    await client.aborted.future;
    expect(await active, isNull);
    expect(await queued, isNull);
    expect(pipeline.isClosed, isTrue);
    expect(pipeline.avatars.isCached('https://media.test/avatar'), isFalse);
    expect(
      await pipeline.avatars.load('https://media.test/after-close'),
      isNull,
    );
    expect(client.requests, [Uri.parse('https://media.test/avatar')]);
    expect(client.closed, isFalse, reason: 'a borrowed client stays open');
  });

  test(
    'replacement closes the old caches before new results publish',
    () async {
      final oldResponse = Completer<http.Response>();
      final oldStarted = Completer<void>();
      final oldPipeline = MediaPipeline(
        client: MockClient((request) {
          oldStarted.complete();
          return oldResponse.future;
        }),
      );
      MediaPipeline.replace(oldPipeline);
      addTearDown(() => MediaPipeline.replace(MediaPipeline()));
      const url = 'https://media.test/avatar';
      final stale = oldPipeline.avatars.load(url);
      await oldStarted.future;

      final replacement = MediaPipeline(
        client: MockClient((_) async => http.Response.bytes([2], 200)),
      );
      MediaPipeline.replace(replacement);
      oldResponse.complete(http.Response.bytes([1], 200));

      expect(await stale, isNull);
      expect(oldPipeline.isClosed, isTrue);
      expect(oldPipeline.avatars.isCached(url), isFalse);
      final fresh = await MediaPipeline.instance.avatars.load(url);
      expect(fresh?.bytes, orderedEquals([2]));
      expect(
        MediaPipeline.instance.avatars.cached(url)?.bytes,
        orderedEquals([2]),
      );
    },
  );

  test('replacing the pipeline with itself keeps it open', () async {
    final pipeline = MediaPipeline(
      client: MockClient((_) async => http.Response.bytes([3], 200)),
    );
    MediaPipeline.replace(pipeline);
    addTearDown(() => MediaPipeline.replace(MediaPipeline()));

    MediaPipeline.replace(pipeline);

    expect(pipeline.isClosed, isFalse);
    expect(
      (await MediaPipeline.instance.avatars.load(
        'https://media.test/avatar',
      ))?.bytes,
      orderedEquals([3]),
    );
  });
}

final class _MemoryByteCacheStore implements ByteCacheStore {
  _MemoryByteCacheStore(this._entries);

  final Map<String, Uint8List> _entries;

  @override
  Future<Uint8List?> read(String url) async => _entries[url];

  @override
  Future<void> write(
    String url,
    Uint8List bytes, {
    required DateTime expiresAt,
  }) async => _entries[url] = bytes;

  @override
  Future<void> remove(String url) async => _entries.remove(url);
}

final class _AbortRecordingClient extends http.BaseClient {
  final Completer<void> started = Completer<void>();
  final Completer<void> aborted = Completer<void>();
  final List<Uri> requests = [];
  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request.url);
    if (!started.isCompleted) started.complete();
    final abortTrigger = switch (request) {
      http.Abortable(:final abortTrigger?) => abortTrigger,
      _ => throw StateError('Expected an abortable media request.'),
    };
    return abortTrigger.then((_) {
      if (!aborted.isCompleted) aborted.complete();
      throw http.ClientException('aborted', request.url);
    });
  }
}
