import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'discourse_api.dart';

/// Deduplicates image fetches and keeps their concurrency bounded.
///
/// Two problems make a plain `NetworkImage` the wrong tool for anything this
/// app draws off a site:
///
/// * A first render asks for three avatars per topic across thirty topics, or
///   thirty emoji across six posts. Fired at once that earns an HTTP 429 from
///   the site, and `NetworkImage` then retries the failures on every rebuild.
/// * The format is not always what the URL says, so the bytes have to be looked
///   at rather than the extension trusted.
///
/// So: cache by URL *including failures*, and cap how many are in flight.
///
/// Subclasses say what a successful response decodes to and nothing else; the
/// caching, the cooldown and the semaphore are the same problem whatever is
/// being fetched, and were worth solving once rather than twice.
abstract class ByteCache<T extends Object> {
  ByteCache({
    http.Client? client,
    this.maxConcurrent = 4,
    this.maxEntries = 2000,
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.maxCachedBytes = 32 * 1024 * 1024,
    this.retryAfter = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 10),
  }) : assert(maxConcurrent > 0),
       assert(maxEntries > 0),
       assert(maxResponseBytes > 0),
       assert(maxCachedBytes > 0),
       _client = client ?? http.Client();

  final http.Client _client;
  final int maxConcurrent;

  /// How many results or unique pending loads are held.
  ///
  /// The record `Store` is deliberately never evicted, because an evicted
  /// record is a blank spot on screen; an evicted image just fetches itself
  /// again the next time it is wanted, which is worth bounding the memory a
  /// long-lived session reading busy sites would otherwise accumulate.
  final int maxEntries;

  /// Largest response body this cache will accept.
  ///
  /// The response is read as a stream and cancelled as soon as it crosses this
  /// bound. A declared content length over the bound is rejected before any of
  /// the body is read.
  final int maxResponseBytes;

  /// Maximum encoded bytes retained across successful entries.
  ///
  /// Failures occupy an entry, so they still participate in [maxEntries], but
  /// cost no bytes here. Successful entries are evicted from the least recently
  /// used end until both limits are satisfied.
  final int maxCachedBytes;

  /// How long a *transient* failure is remembered. A rate limit is temporary,
  /// so caching it forever would leave images blank until the app restarts —
  /// but retrying immediately is what earned the rate limit.
  final Duration retryAfter;

  final Duration timeout;

  final Map<String, _CacheEntry<T>> _cache = {};
  final Map<String, DateTime> _transientFailures = {};
  final Map<String, Future<T?>> _inFlight = {};
  final Queue<_CacheWaiter> _waiting = Queue<_CacheWaiter>();
  int _active = 0;
  int _cachedBytes = 0;
  Object _generation = Object();

  /// What a 200 means here, or null when the bytes cannot be drawn.
  @protected
  T? decode(http.Response response);

  /// Already-known result, so a rebuild paints without going async again.
  bool isCached(String url) => _cache.containsKey(url) && !_cooledDown(url);

  /// Reads a known result and keeps an image that just painted LRU-recent.
  T? cached(String url) {
    final entry = _cache[url];
    if (entry != null) _touch(url);
    return entry?.value;
  }

  /// True once a transient failure is old enough to be worth retrying.
  bool _cooledDown(String url) {
    final failedAt = _transientFailures[url];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) > retryAfter;
  }

  /// Null means the image is unavailable — a 429, a 404, or a format we cannot
  /// draw. Failures are cached while retained; transient ones become eligible
  /// for retry after [retryAfter].
  Future<T?> load(String url) {
    if (_cooledDown(url)) {
      _cache.remove(url);
      _transientFailures.remove(url);
    }
    if (_cache.containsKey(url)) {
      _touch(url);
      return Future.value(_cache[url]?.value);
    }
    // A failure evicted to make room is still a failure: the eviction freed
    // the memory, not the rate limit that earned it.
    if (_transientFailures.containsKey(url)) return Future.value(null);
    final pending = _inFlight[url];
    if (pending != null) return pending;
    // A page can name arbitrarily many distinct remote images. The cache
    // capacity is also a natural bound for work waiting behind the semaphore:
    // accepting more requests than can be retained only grows Futures and URL
    // strings while a slow peer is preventing any of them from progressing.
    // Overflow is not cached, so a later visible rebuild can try again.
    if (_inFlight.length >= maxEntries) return Future.value(null);

    final generation = _generation;
    late final Future<T?> request;
    request = _fetch(url, generation).whenComplete(() {
      if (identical(_inFlight[url], request)) {
        final _ = _inFlight.remove(url);
      }
    });
    _inFlight[url] = request;
    return request;
  }

  /// Moves [url] to the most recently loaded end, and makes room if needed.
  void _put(String url, T? value, {required int byteSize}) {
    final replaced = _cache.remove(url);
    if (replaced != null) _cachedBytes -= replaced.byteSize;

    final entry = _CacheEntry(value, byteSize: byteSize);
    _cache[url] = entry;
    _cachedBytes += byteSize;

    while (_cache.length > maxEntries || _cachedBytes > maxCachedBytes) {
      final evicted = _cache.remove(_cache.keys.first)!;
      _cachedBytes -= evicted.byteSize;
    }
  }

  void _touch(String url) {
    final entry = _cache.remove(url);
    if (entry != null) _cache[url] = entry;
  }

  void _rememberTransientFailure(String url) {
    _transientFailures.remove(url);
    _transientFailures[url] = DateTime.now();
    while (_transientFailures.length > maxEntries) {
      _transientFailures.remove(_transientFailures.keys.first);
    }
  }

  Future<T?> _fetch(String url, Object generation) async {
    if (!await _acquire(generation)) return null;
    try {
      final downloaded = await _download(url);
      final response = downloaded.response;
      bool current() => identical(_generation, generation);

      if (response.statusCode != 200) {
        // 429 and 5xx pass; 404 and friends are permanent.
        if (current() &&
            (response.statusCode == 429 || response.statusCode >= 500)) {
          _rememberTransientFailure(url);
        }
        if (current()) _put(url, null, byteSize: 0);
        return null;
      }

      if (current()) _transientFailures.remove(url);
      if (downloaded.oversized) {
        // The URL is the cache key, and an image too large to accept is no more
        // drawable than a format [decode] rejects. Remembering that result also
        // prevents a rebuild from downloading and rejecting it again.
        if (current()) _put(url, null, byteSize: 0);
        return null;
      }

      final decoded = decode(response);
      if (current()) {
        _put(
          url,
          decoded,
          byteSize: decoded == null ? 0 : response.bodyBytes.length,
        );
      }
      return decoded;
    } catch (_) {
      // Offline or timed out: worth another go later.
      if (identical(_generation, generation)) {
        _rememberTransientFailure(url);
        _put(url, null, byteSize: 0);
      }
      return null;
    } finally {
      _release();
    }
  }

  Future<({http.Response response, bool oversized})> _download(
    String url,
  ) async {
    final elapsed = Stopwatch()..start();
    final request = http.Request('GET', Uri.parse(url))
      // Sites are friendlier to a request that identifies itself.
      ..headers['User-Agent'] = DiscourseApi.userAgent;
    final response = _client.send(request);
    late http.StreamedResponse streamed;
    try {
      streamed = await response.timeout(timeout);
    } on TimeoutException {
      response
          .then<void>((lateResponse) => _cancel(lateResponse.stream))
          .ignore();
      rethrow;
    }

    final contentLength = streamed.contentLength;
    if (contentLength != null && contentLength > maxResponseBytes) {
      _cancel(streamed.stream);
      return (response: _response(streamed, Uint8List(0)), oversized: true);
    }

    if (streamed.statusCode != 200) {
      _cancel(streamed.stream);
      return (response: _response(streamed, Uint8List(0)), oversized: false);
    }

    final Duration remaining;
    try {
      remaining = _remaining(elapsed);
    } on TimeoutException {
      _cancel(streamed.stream);
      rethrow;
    }
    final bytes = await _readAtMost(streamed.stream, remaining);
    return (
      response: _response(streamed, bytes ?? Uint8List(0)),
      oversized: bytes == null,
    );
  }

  Future<Uint8List?> _readAtMost(Stream<List<int>> stream, Duration remaining) {
    final chunks = BytesBuilder(copy: false);
    final result = Completer<Uint8List?>();
    StreamSubscription<List<int>>? subscription;
    var cancelOnListen = false;

    void cancel() {
      final active = subscription;
      if (active == null) {
        cancelOnListen = true;
      } else {
        active.cancel().ignore();
      }
    }

    subscription = stream.listen(
      (chunk) {
        if (result.isCompleted) return;
        if (chunks.length + chunk.length > maxResponseBytes) {
          result.complete(null);
          cancel();
          return;
        }
        chunks.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!result.isCompleted) result.completeError(error, stackTrace);
      },
      onDone: () {
        if (!result.isCompleted) result.complete(chunks.takeBytes());
      },
      cancelOnError: true,
    );
    if (cancelOnListen) subscription.cancel().ignore();

    return result.future.timeout(
      remaining,
      onTimeout: () {
        cancel();
        throw TimeoutException('Timed out fetching cached bytes', timeout);
      },
    );
  }

  void _cancel(Stream<List<int>> stream) =>
      stream.listen(null).cancel().ignore();

  Duration _remaining(Stopwatch elapsed) {
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Timed out fetching cached bytes', timeout);
    }
    return remaining;
  }

  static http.Response _response(
    http.StreamedResponse streamed,
    Uint8List bytes,
  ) => http.Response.bytes(
    bytes,
    streamed.statusCode,
    request: streamed.request,
    headers: streamed.headers,
    isRedirect: streamed.isRedirect,
    persistentConnection: streamed.persistentConnection,
    reasonPhrase: streamed.reasonPhrase,
  );

  Future<bool> _acquire(Object generation) {
    if (!identical(_generation, generation)) return Future.value(false);
    if (_active < maxConcurrent) {
      _active++;
      return Future.value(true);
    }
    final waiter = _CacheWaiter(generation);
    _waiting.add(waiter);
    return waiter.result.future;
  }

  void _release() {
    while (_waiting.isNotEmpty) {
      final waiter = _waiting.removeFirst();
      if (!identical(waiter.generation, _generation)) {
        waiter.result.complete(false);
        continue;
      }
      // Transfer this active slot directly to the waiter.
      waiter.result.complete(true);
      return;
    }
    _active--;
  }

  /// Test seam: forget everything fetched so far.
  void clear() {
    _generation = Object();
    _cache.clear();
    _cachedBytes = 0;
    _inFlight.clear();
    _transientFailures.clear();
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().result.complete(false);
    }
  }
}

final class _CacheWaiter {
  _CacheWaiter(this.generation);

  final Object generation;
  final Completer<bool> result = Completer<bool>();
}

class _CacheEntry<T extends Object> {
  const _CacheEntry(this.value, {required this.byteSize});

  final T? value;
  final int byteSize;
}
