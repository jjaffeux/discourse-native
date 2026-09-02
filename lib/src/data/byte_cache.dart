import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../diagnostics/diagnostics_controller.dart';
import 'byte_cache_store.dart';
import 'discourse_api.dart';
import 'http_transport.dart';
import 'media_request_coordinator.dart';

abstract class ByteCache<T extends Object> {
  ByteCache({
    http.Client? client,
    this.maxConcurrent,
    this.maxEntries = 2000,
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.maxCachedBytes = 32 * 1024 * 1024,
    this.retryAfter = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 10),
    this.maxRedirects = 5,
    MediaRequestCoordinator? coordinator,
    this.requestPriority = MediaRequestPriority.normal,
    this.requestPool,
    this.store,
  }) : assert(maxConcurrent == null || maxConcurrent > 0),
       assert(maxEntries > 0),
       assert(maxResponseBytes > 0),
       assert(maxCachedBytes > 0),
       assert(maxRedirects >= 0),
       _coordinator =
           coordinator ??
           (maxConcurrent == null
               ? null
               : MediaRequestCoordinator(
                   maxConcurrent: maxConcurrent,
                   maxConcurrentPerOrigin: maxConcurrent,
                   defaultRateLimitCooldown: retryAfter,
                 )),
       _ownsCoordinator = coordinator == null && maxConcurrent != null,
       _client = client == null
           ? SafeHttpClient.create()
           : SafeHttpClient.borrowed(client);

  final http.Client _client;
  final MediaRequestCoordinator? _coordinator;
  final bool _ownsCoordinator;
  final MediaRequestPriority requestPriority;
  final ByteCacheRequestPool? requestPool;
  final ByteCacheStore? store;

  final int? maxConcurrent;

  final int maxEntries;

  final int maxResponseBytes;

  final int maxCachedBytes;

  final Duration retryAfter;

  final Duration timeout;

  final int maxRedirects;

  final Map<String, _CacheEntry<T>> _cache = {};
  final Map<String, DateTime> _transientFailures = {};
  final Map<String, Future<T?>> _inFlight = {};
  final Queue<_CacheWaiter> _waiting = Queue<_CacheWaiter>();
  int _active = 0;
  int _cachedBytes = 0;
  Object _generation = Object();
  final Set<Completer<void>> _activeAborts = {};
  bool _closed = false;

  @protected
  T? decode(http.Response response);

  @protected
  Map<String, String> requestHeaders(Uri url, Uri original) => const {};

  bool isCached(String url) => _cache.containsKey(url) && !_cooledDown(url);

  T? cached(String url) {
    final entry = _cache[url];
    if (entry != null) _touch(url);
    return entry?.value;
  }

  bool _cooledDown(String url) {
    final failedAt = _transientFailures[url];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) > retryAfter;
  }

  Future<T?> load(String url) {
    if (_closed) return Future.value(null);
    // Validate before consulting either memory or persistent storage. An
    // unsafe key must never be served merely because another cache generation
    // or a tampered cache directory happened to retain bytes under it.
    try {
      requireSafeHttpUrl(Uri.parse(url));
    } catch (error, stackTrace) {
      _report(error, stackTrace, url, 'image.url');
      return Future.value(null);
    }
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
    // When this cache opts into work limiting, take its slot before disk too;
    // otherwise a cold screen could bypass the intended bound with one
    // filesystem read per visible image.
    if (!await _acquire(generation)) return null;
    try {
      final persistent = store;
      if (persistent != null) {
        try {
          final bytes = await persistent.read(url);
          if (bytes != null && identical(_generation, generation)) {
            final response = http.Response.bytes(
              bytes,
              200,
              request: http.Request('GET', Uri.parse(url)),
            );
            final decoded = decode(response);
            if (decoded != null) {
              _put(url, decoded, byteSize: bytes.length);
              return decoded;
            }
          }
        } catch (error, stackTrace) {
          // Cache corruption or an unavailable cache directory is a miss,
          // never a reason to leave a drawable image blank.
          _report(error, stackTrace, url, 'image.cacheRead');
        }
      }
      if (!identical(_generation, generation)) return null;

      final downloaded = await switch (requestPool) {
        final pool? => pool.run(url, () => _download(url)),
        null => _download(url),
      };
      final response = downloaded.response;
      bool current() => identical(_generation, generation);

      if (response.statusCode != 200) {
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
        _report(
          HttpResponseTooLargeException(Uri.parse(url), maxResponseBytes),
          StackTrace.current,
          url,
          'image.download',
        );
        if (current()) _put(url, null, byteSize: 0);
        return null;
      }

      final decoded = decode(response);
      if (decoded == null) {
        _report(
          const FormatException('Downloaded image could not be decoded.'),
          StackTrace.current,
          url,
          'image.decode',
        );
      }
      if (current()) {
        _put(
          url,
          decoded,
          byteSize: decoded == null ? 0 : response.bodyBytes.length,
        );
      }
      if (decoded != null && persistent != null && downloaded.persistable) {
        final expiresAt = persistentByteCacheExpiry(
          response.headers,
          DateTime.now(),
        );
        if (expiresAt != null && current()) {
          try {
            await persistent.write(
              url,
              response.bodyBytes,
              expiresAt: expiresAt,
            );
          } catch (error, stackTrace) {
            _report(error, stackTrace, url, 'image.cacheWrite');
          }
        }
      }
      return _closed ? null : decoded;
    } on MediaOriginRateLimitedException {
      // This URL never reached the network: another native-managed media
      // request put its whole origin into cooldown. Remember it as transient
      // without producing one diagnostic per rejected avatar/emoji.
      if (identical(_generation, generation)) {
        _rememberTransientFailure(url);
        _put(url, null, byteSize: 0);
      }
      return null;
    } on MediaRequestOverloadException {
      // A backlog rejection never reached the network and says nothing about
      // this URL, only that its origin's queue was full. Like in-memory
      // overflow it is neither cached nor remembered as a failure, so a later
      // visible rebuild can try again once the backlog drains.
      return null;
    } catch (error, stackTrace) {
      if (!identical(_generation, generation)) return null;
      _report(error, stackTrace, url, 'image.load');
      if (identical(_generation, generation)) {
        _rememberTransientFailure(url);
        _put(url, null, byteSize: 0);
      }
      return null;
    } finally {
      _release();
    }
  }

  static void _report(
    Object error,
    StackTrace stackTrace,
    String url,
    String operation,
  ) {
    final uri = Uri.tryParse(url);
    final location = uri == null ? '' : ' ${uri.host}${uri.path}';
    DiagnosticsSink.current.reportError(
      error,
      stackTrace,
      operation: '$operation$location',
      source: 'image',
      severity: DiagnosticSeverity.warning,
      handled: true,
      degraded: true,
    );
  }

  Future<ByteCacheDownload> _download(String url) async {
    final elapsed = Stopwatch()..start();
    final original = requireSafeHttpUrl(Uri.parse(url));
    var current = original;
    var redirects = 0;
    var persistable = true;

    while (true) {
      final sent = await _send(current, original, elapsed);
      try {
        final streamed = sent.response;
        // The bytes are keyed by the original URL, so every response which
        // resolves that URL participates in its storage policy. In particular,
        // a public CDN target must not override a private/no-store redirect.
        persistable =
            persistable && responseAllowsPersistentByteCache(streamed.headers);
        final location = streamed.headers['location'];
        if (_isRedirect(streamed.statusCode) && location != null) {
          _cancel(streamed.stream);
          if (redirects >= maxRedirects) {
            throw http.ClientException('Too many image redirects', current);
          }
          current = resolveSafeHttpRedirect(current, location);
          redirects++;
          continue;
        }

        final contentLength = streamed.contentLength;
        if (contentLength != null && contentLength > maxResponseBytes) {
          _cancel(streamed.stream);
          return (
            response: _response(streamed, Uint8List(0)),
            oversized: true,
            persistable: persistable,
          );
        }

        if (streamed.statusCode != 200) {
          _cancel(streamed.stream);
          return (
            response: _response(streamed, Uint8List(0)),
            oversized: false,
            persistable: persistable,
          );
        }

        final Duration remaining;
        try {
          remaining = _remaining(elapsed);
        } on TimeoutException {
          _abort(sent.timeoutAbort);
          _cancel(streamed.stream);
          rethrow;
        }
        final Uint8List? bytes;
        try {
          bytes = await _readAtMost(streamed.stream, remaining);
        } on TimeoutException {
          _abort(sent.timeoutAbort);
          rethrow;
        }
        return (
          response: _response(streamed, bytes ?? Uint8List(0)),
          oversized: bytes == null,
          persistable: persistable,
        );
      } finally {
        _activeAborts.remove(sent.timeoutAbort);
        sent.lease?.release();
      }
    }
  }

  Future<
    ({
      http.StreamedResponse response,
      Completer<void> timeoutAbort,
      MediaRequestLease? lease,
    })
  >
  _send(Uri url, Uri original, Stopwatch elapsed) async {
    final lease = await _coordinator?.acquire(
      url,
      relatedUrl: original,
      priority: requestPriority,
    );
    final timeoutAbort = Completer<void>();
    if (_closed) {
      lease?.release();
      return Future.error(StateError('Byte cache is closed.'));
    }
    _activeAborts.add(timeoutAbort);
    Future<http.StreamedResponse>? response;
    try {
      // A bounded request may have waited for admission. Do not start it after
      // this load's complete timeout budget has elapsed.
      final remaining = _remaining(elapsed);
      final request =
          http.AbortableRequest('GET', url, abortTrigger: timeoutAbort.future)
            ..headers['User-Agent'] = DiscourseApi.userAgent
            ..followRedirects = false;
      request.headers.addAll(requestHeaders(url, original));
      response = _client.send(request);
      final streamed = await response.timeout(remaining);
      if (streamed.statusCode == 429 && lease != null) {
        // A CDN 429 also gates the source forum. Otherwise queued forum avatar
        // URLs would all continue producing redirects into the blocked CDN.
        lease.rateLimited(streamed.headers);
      }
      return (response: streamed, timeoutAbort: timeoutAbort, lease: lease);
    } on TimeoutException {
      _abort(timeoutAbort);
      _activeAborts.remove(timeoutAbort);
      response
          ?.then<void>(
            (lateResponse) => _cancel(lateResponse.stream),
            onError: (Object _, StackTrace _) {},
          )
          .ignore();
      lease?.release();
      rethrow;
    } catch (_) {
      _activeAborts.remove(timeoutAbort);
      lease?.release();
      rethrow;
    }
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;

  static void _abort(Completer<void> abort) {
    if (!abort.isCompleted) abort.complete();
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
    final limit = maxConcurrent;
    if (limit == null) return Future.value(true);
    if (_active < limit) {
      _active++;
      return Future.value(true);
    }
    final waiter = _CacheWaiter(generation);
    _waiting.add(waiter);
    return waiter.result.future;
  }

  void _release() {
    if (maxConcurrent == null) return;
    while (_waiting.isNotEmpty) {
      final waiter = _waiting.removeFirst();
      if (!identical(waiter.generation, _generation)) {
        waiter.result.complete(false);
        continue;
      }
      waiter.result.complete(true);
      return;
    }
    _active--;
  }

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

  void close() {
    if (_closed) return;
    _closed = true;
    clear();
    for (final abort in _activeAborts.toList(growable: false)) {
      _abort(abort);
    }
    _activeAborts.clear();
    if (_ownsCoordinator) _coordinator?.close();
    _client.close();
  }
}

typedef ByteCacheDownload = ({
  http.Response response,
  bool oversized,
  bool persistable,
});

/// Coalesces raw downloads for caches with the same public-media policy.
///
/// Decoding and memory publication remain with each typed [ByteCache]. The
/// owner closes the whole pool together, so one cache cannot cancel a transfer
/// which a longer-lived peer still expects to complete.
final class ByteCacheRequestPool {
  final Map<String, Future<ByteCacheDownload>> _inFlight = {};
  bool _closed = false;

  Future<ByteCacheDownload> run(
    String url,
    Future<ByteCacheDownload> Function() download,
  ) {
    if (_closed) {
      return Future.error(StateError('Byte cache request pool is closed.'));
    }
    final pending = _inFlight[url];
    if (pending != null) return pending;

    late final Future<ByteCacheDownload> request;
    request = download().whenComplete(() {
      if (identical(_inFlight[url], request)) {
        final _ = _inFlight.remove(url);
      }
    });
    _inFlight[url] = request;
    return request;
  }

  void close() {
    _closed = true;
    _inFlight.clear();
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
