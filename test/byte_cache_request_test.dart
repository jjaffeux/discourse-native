import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/src/data/byte_cache.dart';
import 'package:discourse_native/src/data/media_request_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const url = 'https://forum.example/image';

  test(
    'release settles one consumer while a peer and save keep one transfer',
    () async {
      final client = _Client();
      final cache = _Cache(client: client);
      addTearDown(cache.close);
      final first = cache.request(url);
      final second = cache.request(url);
      final save = cache.load(url);
      await _pump();
      expect(client.sent, hasLength(1));
      first.release();
      first.release();
      expect(await first.result, isNull);
      expect(client.sent.single.aborted, isFalse);
      client.sent.single.complete([1, 2, 3]);
      expect(await second.result, [1, 2, 3]);
      expect(await save, [1, 2, 3]);
      expect(await cache.load(url), [1, 2, 3]);
      expect(client.sent, hasLength(1));
    },
  );

  test(
    'a released local waiter never starts and an immediate revisit can start',
    () async {
      final client = _Client();
      final cache = _Cache(client: client, maxConcurrent: 1);
      addTearDown(cache.close);
      final blocker = cache.load('https://forum.example/blocker');
      final abandoned = cache.request(url);
      await _pump();
      abandoned.release();
      final revisit = cache.request(url);
      expect(await abandoned.result, isNull);
      expect(client.sent, hasLength(1));
      client.sent[0].complete([0]);
      expect(await blocker, [0]);
      await _pump();
      expect(client.sent.map((request) => request.url.path), [
        '/blocker',
        '/image',
      ]);
      client.sent[1].complete([4]);
      expect(await revisit.result, [4]);
    },
  );

  test(
    'cancelled headers free capacity and late responses cannot publish or cool down',
    () async {
      final client = _Client();
      final cache = _Cache(client: client, maxConcurrent: 1);
      addTearDown(cache.close);
      final abandoned = cache.request(url);
      await _pump();
      abandoned.release();
      final revisit = cache.request(url);
      expect(await abandoned.result, isNull);
      await _pump();
      expect(client.sent, hasLength(2));
      expect(client.sent.first.aborted, isTrue);
      client.sent[1].complete([2]);
      expect(await revisit.result, [2]);
      final lateCancelled = Completer<void>();
      final late = StreamController<List<int>>(
        onCancel: lateCancelled.complete,
      );
      client.sent.first.headers.complete(
        http.StreamedResponse(late.stream, 429),
      );
      await lateCancelled.future;
      expect(cache.cached(url), [2]);
      final next = cache.load('https://forum.example/next');
      await _pump();
      expect(client.sent, hasLength(3));
      client.sent[2].complete([3]);
      expect(await next, [3]);
      await late.close();
    },
  );

  test(
    'last owner directly cancels a partial body without retaining a failure',
    () async {
      final client = _Client();
      final cache = _Cache(client: client, maxConcurrent: 1);
      addTearDown(cache.close);
      final owner = cache.request(url);
      await _pump();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(onCancel: cancelled.complete);
      client.sent.single.headers.complete(
        http.StreamedResponse(body.stream, 200),
      );
      await _pump();
      body.add([9, 9]);
      await _pump();
      owner.release();
      expect(await owner.result, isNull);
      await cancelled.future;
      expect(cache.isCached(url), isFalse);
      final revisit = cache.request(url);
      await _pump();
      expect(client.sent, hasLength(2));
      client.sent[1].complete([1, 2]);
      expect(await revisit.result, [1, 2]);
      await body.close();
    },
  );

  test(
    'losing the final owner at a redirect never starts the next hop',
    () async {
      final client = _Client();
      final cache = _Cache(client: client);
      addTearDown(cache.close);
      final owner = cache.request(url);
      await _pump();
      final redirect = StreamController<List<int>>(onCancel: owner.release);
      client.sent.single.headers.complete(
        http.StreamedResponse(
          redirect.stream,
          302,
          headers: {'location': 'https://cdn.example/image'},
        ),
      );
      expect(await owner.result, isNull);
      await _pump();
      expect(client.sent, hasLength(1));
      expect(cache.isCached(url), isFalse);
      await redirect.close();
      final revisit = cache.request(url);
      await _pump();
      client.sent.last.complete([5]);
      expect(await revisit.result, [5]);
    },
  );

  test(
    'local admission reads shared consumers current priority and demotion',
    () async {
      final client = _Client();
      final cache = _Cache(client: client, maxConcurrent: 1);
      addTearDown(cache.close);
      final blocker = cache.load('https://forum.example/blocker');
      final first = cache.request('https://forum.example/first');
      final promoted = cache.request('https://forum.example/promoted');
      final peer = cache.request('https://forum.example/promoted');
      final demoted = cache.request(
        'https://forum.example/demoted',
        priority: MediaRequestPriority.interactive,
      );
      peer.priority = MediaRequestPriority.interactive;
      demoted.priority = MediaRequestPriority.normal;
      await _pump();
      client.sent[0].complete([0]);
      await blocker;
      await _pump();
      expect(client.sent.last.url.path, '/promoted');
      peer.release();
      expect(await peer.result, isNull);
      expect(client.sent.last.aborted, isFalse);
      client.sent.last.complete([1]);
      expect(await promoted.result, [1]);
      await _pump();
      expect(client.sent.last.url.path, '/first');
      client.sent.last.complete([2]);
      await first.result;
      await _pump();
      expect(client.sent.last.url.path, '/demoted');
      client.sent.last.complete([3]);
      await demoted.result;
    },
  );

  test(
    'normal local work gets a turn after three interactive overtakes',
    () async {
      final client = _Client();
      final cache = _Cache(client: client, maxConcurrent: 1);
      addTearDown(cache.close);
      final pending = <Future<Uint8List?>>[
        cache.load('https://forum.example/blocker'),
      ];
      pending.add(cache.request('https://forum.example/normal').result);
      for (var index = 0; index < 4; index++) {
        pending.add(
          cache
              .request(
                'https://forum.example/interactive$index',
                priority: MediaRequestPriority.interactive,
              )
              .result,
        );
      }
      await _pump();
      for (var index = 0; index < 6; index++) {
        client.sent[index].complete([index]);
        await _pump();
      }
      await Future.wait(pending);
      expect(client.sent.map((request) => request.url.path), [
        '/blocker',
        '/interactive0',
        '/interactive1',
        '/interactive2',
        '/normal',
        '/interactive3',
      ]);
    },
  );

  test(
    'coordinator reads promotion and demotion across independent caches',
    () async {
      final client = _Client();
      final coordinator = MediaRequestCoordinator(
        maxConcurrent: 1,
        maxConcurrentPerOrigin: 1,
      );
      final cache = _Cache(client: client, coordinator: coordinator);
      final peer = _Cache(client: client, coordinator: coordinator);
      addTearDown(() {
        cache.close();
        peer.close();
        coordinator.close();
      });
      final blocker = cache.load('https://forum.example/blocker');
      final first = cache.request('https://forum.example/first');
      final demoted = peer.request(
        'https://forum.example/demoted',
        priority: MediaRequestPriority.interactive,
      );
      final promoted = peer.request('https://forum.example/promoted');
      await _pump();
      demoted.priority = MediaRequestPriority.normal;
      promoted.priority = MediaRequestPriority.interactive;
      client.sent[0].complete([0]);
      await blocker;
      await _pump();
      expect(client.sent.last.url.path, '/promoted');
      client.sent.last.complete([1]);
      await promoted.result;
      await _pump();
      expect(client.sent.last.url.path, '/first');
      client.sent.last.complete([2]);
      await first.result;
      await _pump();
      client.sent.last.complete([3]);
      await demoted.result;
    },
  );

  test('cancelled coordinator waiter never sends or holds a slot', () async {
    final client = _Client();
    final coordinator = MediaRequestCoordinator(
      maxConcurrent: 1,
      maxConcurrentPerOrigin: 1,
      maxQueuedPerOrigin: 1,
    );
    final cache = _Cache(client: client, coordinator: coordinator);
    addTearDown(() {
      cache.close();
      coordinator.close();
    });
    final blocker = cache.load('https://forum.example/blocker');
    final abandoned = cache.request(url);
    await _pump();
    abandoned.release();
    final revisit = cache.request(url);
    expect(await abandoned.result, isNull);
    client.sent.first.complete([0]);
    await blocker;
    await _pump();
    expect(client.sent, hasLength(2));
    client.sent.last.complete([1]);
    expect(await revisit.result, [1]);
  });

  test(
    'pooled caches refuse cancellable demand before starting work',
    () async {
      final client = _Client();
      final pool = ByteCacheRequestPool();
      final first = _Cache(client: client, requestPool: pool);
      final peer = _Cache(client: client, requestPool: pool);
      addTearDown(() {
        first.close();
        peer.close();
        pool.close();
      });
      expect(() => first.request(url), throwsStateError);
      expect(client.sent, isEmpty);
      final a = first.load(url);
      final b = peer.load(url);
      await _pump();
      expect(client.sent, hasLength(1));
      client.sent.single.complete([6]);
      expect(await a, [6]);
      expect(await b, [6]);
    },
  );

  test(
    'close settles all active consumers and cancels an insensitive body',
    () async {
      final client = _Client();
      final cache = _Cache(client: client);
      final owner = cache.request(url);
      await _pump();
      final cancelled = Completer<void>();
      final body = StreamController<List<int>>(onCancel: cancelled.complete);
      client.sent.single.headers.complete(
        http.StreamedResponse(body.stream, 200),
      );
      await _pump();
      cache.close();
      expect(await owner.result, isNull);
      await cancelled.future;
      await body.close();
    },
  );
}

Future<void> _pump() => Future<void>.delayed(Duration.zero);

final class _Cache extends ByteCache<Uint8List> {
  _Cache({
    required super.client,
    super.maxConcurrent,
    super.coordinator,
    super.requestPool,
  });

  @override
  Uint8List? decode(http.Response response) => response.bodyBytes;
}

final class _Client extends http.BaseClient {
  final List<_Sent> sent = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final entry = _Sent(request.url);
    sent.add(entry);
    if (request is http.Abortable && request.abortTrigger != null) {
      unawaited(request.abortTrigger!.then((_) => entry.aborted = true));
    }
    return entry.headers.future;
  }
}

final class _Sent {
  _Sent(this.url);
  final Uri url;
  final Completer<http.StreamedResponse> headers = Completer();
  bool aborted = false;

  void complete(List<int> bytes) =>
      headers.complete(http.StreamedResponse(Stream.value(bytes), 200));
}
