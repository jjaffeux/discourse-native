import 'dart:async';
import 'dart:typed_data';

import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'byte_cache_store.dart';
import 'discourse_api.dart';
import 'http_transport.dart';
import 'media_request_coordinator.dart';
import 'serial_operation_queue.dart';

abstract class ByteCache<T extends Object> {
  // Avatar and emoji caches, including replacement pipelines, share the same
  // store. A late disk write must finish before decoder rejection removes it,
  // and later readers must observe those accepted mutations.
  static final _storeOperations = ReadAfterWriteOperationQueue();

  // Disk persistence must not delay image delivery or accumulate unbounded
  // work after network slots are released. Share both limits across typed
  // caches and replacement pipelines, including writes still finishing after
  // close(). At capacity, skip optional persistence.
  static const _maxPendingStoreWrites = 16;
  static const _maxPendingStoreBytes = 16 * 1024 * 1024;
  static int _pendingStoreWrites = 0;
  static int _pendingStoreBytes = 0;

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
  final Map<String, _ByteCacheTransfer<T>> _inFlight = {};
  final Set<_ByteCacheTransfer<T>> _transfers = {};
  final List<_CacheWaiter<T>> _waiting = [];
  int _interactiveOvertakes = 0;
  int _active = 0;
  int _cachedBytes = 0;
  Object _generation = Object();
  bool _closed = false;

  @protected
  T? decode(http.Response response);

  @protected
  Map<String, String> requestHeaders(Uri url, Uri original) => const {};

  bool isCached(String url) => _cache.containsKey(url) && !_cooledDown(url);

  /// Response bytes currently retained for decoded entries.
  int get cachedBytes => _cachedBytes;

  /// Evicts least-recently-used entries until at most [bytes] are retained.
  ///
  /// This releases only what the cache retains: callers already holding
  /// delivered values keep them, and loads still in flight publish normally
  /// under this cache's own limits.
  void trimTo(int bytes) {
    assert(bytes >= 0);
    while (_cachedBytes > bytes) {
      _evictLeastRecentlyUsed();
    }
  }

  T? cached(String url) {
    final entry = _cache[url];
    if (entry != null) _touch(url);
    return entry?.value;
  }

  /// Forgets [value] after the platform image decoder rejects it.
  ///
  /// Decoder support belongs to the platform and cannot be determined while
  /// [decode] synchronously classifies a response. Only discard the entry if
  /// it is still the exact value the caller tried, so a late decoder failure
  /// cannot replace newer bytes for the same URL.
  @protected
  bool discardCachedValue(String url, T value) {
    final entry = _cache[url];
    if (entry == null || !identical(entry.value, value)) return false;

    _put(url, null, byteSize: 0);
    final persistent = store;
    if (persistent != null) {
      unawaited(_discardStoredValue(persistent, url));
    }
    return true;
  }

  Future<void> _discardStoredValue(
    ByteCacheStore persistent,
    String url,
  ) async {
    try {
      await _storeOperations.write<void>(
        owner: persistent,
        key: url,
        operation: () => persistent.remove(url),
      );
    } catch (_) {}
  }

  Future<void> _persist(
    ByteCacheStore persistent,
    String url,
    Uint8List bytes,
    DateTime expiresAt,
    Object generation,
  ) async {
    // A response can be a view into a larger transport buffer.
    final byteSize = bytes.buffer.lengthInBytes;
    if (_pendingStoreWrites >= _maxPendingStoreWrites ||
        _pendingStoreBytes + byteSize > _maxPendingStoreBytes) {
      return;
    }
    _pendingStoreWrites++;
    _pendingStoreBytes += byteSize;
    try {
      // Register before load() completes so replacement readers and decoder
      // rejections queue behind this write even if it has not started yet.
      await _storeOperations.write<void>(
        owner: persistent,
        key: url,
        operation: () async {
          if (!identical(_generation, generation)) return;
          await persistent.write(url, bytes, expiresAt: expiresAt);
        },
      );
    } catch (_) {
    } finally {
      _pendingStoreWrites--;
      _pendingStoreBytes -= byteSize;
    }
  }

  bool _cooledDown(String url) {
    final failedAt = _transientFailures[url];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) > retryAfter;
  }

  Future<T?> load(String url) => _request(url, requestPriority).result;

  /// Owns demand for one URL until completion or [ByteCacheRequest.release].
  ByteCacheRequest<T> request(
    String url, {
    MediaRequestPriority priority = MediaRequestPriority.normal,
  }) {
    if (requestPool != null) {
      throw StateError('Pooled byte caches require completion-owned loads.');
    }
    return _request(url, priority);
  }

  ByteCacheRequest<T> _request(String url, MediaRequestPriority priority) {
    final owner = ByteCacheRequest<T>._(priority);
    if (_closed) return owner.._complete(null);
    try {
      requireSafeHttpUrl(Uri.parse(url));
    } catch (error) {
      return owner.._complete(null);
    }
    if (_cooledDown(url)) {
      _cache.remove(url);
      _transientFailures.remove(url);
    }
    if (_cache.containsKey(url)) {
      _touch(url);
      return owner.._complete(_cache[url]?.value);
    }
    if (_transientFailures.containsKey(url)) return owner.._complete(null);
    var transfer = _inFlight[url];
    if (transfer == null) {
      if (_inFlight.length >= maxEntries) return owner.._complete(null);
      transfer = _ByteCacheTransfer<T>(url, _generation);
      _inFlight[url] = transfer;
      _transfers.add(transfer);
    }
    final active = transfer;
    active.owners.add(owner);
    owner._onRelease = () {
      active.owners.remove(owner);
      if (active.owners.isEmpty) _retire(active);
    };
    if (!active.started) {
      active.started = true;
      unawaited(_run(active));
    }
    return owner;
  }

  Future<void> _run(_ByteCacheTransfer<T> transfer) async {
    final value = await _fetch(transfer);
    if (identical(_inFlight[transfer.url], transfer)) {
      _inFlight.remove(transfer.url);
    }
    _transfers.remove(transfer);
    for (final owner in transfer.owners) {
      owner._complete(_closed || transfer.cancelled ? null : value);
    }
    transfer.owners.clear();
  }

  void _retire(_ByteCacheTransfer<T> transfer) {
    if (transfer.cancelled) return;
    transfer.cancelled = true;
    if (identical(_inFlight[transfer.url], transfer)) {
      _inFlight.remove(transfer.url);
    }
    for (var index = _waiting.length - 1; index >= 0; index--) {
      if (identical(_waiting[index].transfer, transfer)) {
        _waiting.removeAt(index).result.complete(false);
      }
    }
    transfer.abort.complete();
    for (final owner in transfer.owners) {
      owner._complete(null);
    }
    transfer.owners.clear();
  }

  bool _canPublish(_ByteCacheTransfer<T> transfer) =>
      !transfer.cancelled &&
      identical(_generation, transfer.generation) &&
      identical(_inFlight[transfer.url], transfer);

  void _put(String url, T? value, {required int byteSize}) {
    final replaced = _cache.remove(url);
    if (replaced != null) _cachedBytes -= replaced.byteSize;

    final entry = _CacheEntry(value, byteSize: byteSize);
    _cache[url] = entry;
    _cachedBytes += byteSize;

    while (_cache.length > maxEntries || _cachedBytes > maxCachedBytes) {
      _evictLeastRecentlyUsed();
    }
  }

  void _evictLeastRecentlyUsed() {
    final evicted = _cache.remove(_cache.keys.first)!;
    _cachedBytes -= evicted.byteSize;
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

  Future<T?> _fetch(_ByteCacheTransfer<T> transfer) async {
    final url = transfer.url;
    final generation = transfer.generation;
    bool current() => _canPublish(transfer);
    // When this cache opts into work limiting, take its slot before disk too;
    // otherwise a cold screen could bypass the intended bound with one
    // filesystem read per visible image.
    if (!await _acquire(transfer)) return null;
    try {
      final persistent = store;
      if (persistent != null) {
        try {
          final bytes = await _storeOperations.read<Uint8List?>(
            owner: persistent,
            key: url,
            operation: () =>
                current() ? persistent.read(url) : Future.value(null),
          );
          if (bytes != null && current()) {
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
        } catch (_) {
          // Cache corruption or an unavailable cache directory is a miss,
          // never a reason to leave a drawable image blank.
        }
      }
      transfer.checkDemand();
      if (!identical(_generation, generation)) return null;

      final downloaded = await switch (requestPool) {
        final pool? => pool.run(url, () => _download(transfer)),
        null => _download(transfer),
      };
      final response = downloaded.response;
      transfer.checkDemand();

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
      if (decoded != null && persistent != null && downloaded.persistable) {
        final expiresAt = persistentByteCacheExpiry(
          response.headers,
          DateTime.now(),
        );
        if (expiresAt != null && current()) {
          unawaited(
            _persist(
              persistent,
              url,
              response.bodyBytes,
              expiresAt,
              generation,
            ),
          );
        }
      }
      return _closed ? null : decoded;
    } on _ByteCacheRequestCancelled {
      return null;
    } on MediaOriginRateLimitedException {
      // This URL never reached the network: another native-managed media
      // request put its whole origin into cooldown. Remember it as transient.
      if (current()) {
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
    } catch (error) {
      if (transfer.cancelled || !identical(_generation, generation)) {
        return null;
      }

      if (current()) {
        _rememberTransientFailure(url);
        _put(url, null, byteSize: 0);
      }
      return null;
    } finally {
      _release();
    }
  }

  Future<ByteCacheDownload> _download(_ByteCacheTransfer<T> transfer) async {
    final url = transfer.url;
    final elapsed = Stopwatch()..start();
    final original = requireSafeHttpUrl(Uri.parse(url));
    var current = original;
    var redirects = 0;
    var persistable = true;

    while (true) {
      transfer.checkDemand();
      final sent = await _send(current, original, elapsed, transfer);
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
            throw http.ClientException(appL10n.tooManyImageRedirects, current);
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
          bytes = await _readAtMost(streamed.stream, remaining, transfer);
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
  _send(
    Uri url,
    Uri original,
    Stopwatch elapsed,
    _ByteCacheTransfer<T> transfer,
  ) async {
    MediaRequestLease? lease;
    final timeoutAbort = Completer<void>.sync();
    transfer.checkDemand();
    if (_closed) throw StateError('Byte cache is closed.');
    unawaited(transfer.abort.future.then((_) => _abort(timeoutAbort)));
    Future<http.StreamedResponse>? response;
    try {
      if (_coordinator case final coordinator?) {
        final admissionTimer = Timer(
          _remaining(elapsed),
          () => _abort(timeoutAbort),
        );
        try {
          lease = await coordinator.acquire(
            url,
            relatedUrl: original,
            resolvePriority: () => transfer.priority,
            abortTrigger: timeoutAbort.future,
          );
        } on MediaRequestCancelledException {
          transfer.checkDemand();
          if (_closed) throw StateError('Byte cache is closed.');
          throw TimeoutException(appL10n.timedOutFetchingCachedBytes, timeout);
        } finally {
          admissionTimer.cancel();
        }
      }
      transfer.checkDemand();
      if (_closed) throw StateError('Byte cache is closed.');
      if (timeoutAbort.isCompleted) {
        throw TimeoutException(appL10n.timedOutFetchingCachedBytes, timeout);
      }
      final remaining = _remaining(elapsed);
      final request =
          http.AbortableRequest('GET', url, abortTrigger: timeoutAbort.future)
            ..headers['User-Agent'] = DiscourseApi.userAgent
            ..followRedirects = false;
      request.headers.addAll(requestHeaders(url, original));
      response = _client.send(request);
      final streamed = await Future.any<http.StreamedResponse>([
        response,
        transfer.abort.future.then(
          (_) => throw const _ByteCacheRequestCancelled(),
        ),
      ]).timeout(remaining);
      transfer.checkDemand();
      if (streamed.statusCode == 429 && lease != null) {
        // A CDN 429 also gates the source forum. Otherwise queued forum avatar
        // URLs would all continue producing redirects into the blocked CDN.
        lease.rateLimited(streamed.headers);
      }
      return (response: streamed, timeoutAbort: timeoutAbort, lease: lease);
    } catch (error) {
      if (error is TimeoutException || transfer.cancelled) _abort(timeoutAbort);
      response
          ?.then<void>(
            (lateResponse) => _cancel(lateResponse.stream),
            onError: (Object _, StackTrace _) {},
          )
          .ignore();
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

  Future<Uint8List?> _readAtMost(
    Stream<List<int>> stream,
    Duration remaining,
    _ByteCacheTransfer<T> transfer,
  ) {
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

    unawaited(
      transfer.abort.future.then((_) {
        if (result.isCompleted) return;
        chunks.clear();
        result.completeError(const _ByteCacheRequestCancelled());
        cancel();
      }),
    );
    subscription = stream.listen(
      (chunk) {
        if (result.isCompleted) return;
        if (chunks.length + chunk.length > maxResponseBytes) {
          chunks.clear();
          result.complete(null);
          cancel();
          return;
        }
        chunks.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        chunks.clear();
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
        chunks.clear();
        cancel();
        throw TimeoutException(appL10n.timedOutFetchingCachedBytes, timeout);
      },
    );
  }

  void _cancel(Stream<List<int>> stream) =>
      stream.listen(null).cancel().ignore();

  Duration _remaining(Stopwatch elapsed) {
    final remaining = timeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(appL10n.timedOutFetchingCachedBytes, timeout);
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

  Future<bool> _acquire(_ByteCacheTransfer<T> transfer) {
    if (transfer.cancelled || !identical(_generation, transfer.generation)) {
      return Future.value(false);
    }
    final limit = maxConcurrent;
    if (limit == null) return Future.value(true);
    if (_active < limit) {
      _active++;
      return Future.value(true);
    }
    final waiter = _CacheWaiter(transfer);
    _waiting.add(waiter);
    return waiter.result.future;
  }

  void _release() {
    if (maxConcurrent == null) return;
    for (var index = _waiting.length - 1; index >= 0; index--) {
      final waiter = _waiting[index];
      if (waiter.transfer.cancelled ||
          !identical(waiter.transfer.generation, _generation)) {
        _waiting.removeAt(index).result.complete(false);
      }
    }
    if (_waiting.isEmpty) {
      _active--;
      _interactiveOvertakes = 0;
      return;
    }
    final normal = _waiting.indexWhere(
      (waiter) => waiter.transfer.priority == MediaRequestPriority.normal,
    );
    final interactive = _waiting.indexWhere(
      (waiter) => waiter.transfer.priority == MediaRequestPriority.interactive,
    );
    final index = normal >= 0 && (interactive < 0 || _interactiveOvertakes >= 3)
        ? normal
        : interactive;
    _interactiveOvertakes = normal >= 0 && index == interactive
        ? _interactiveOvertakes + 1
        : 0;
    _waiting.removeAt(index).result.complete(true);
  }

  void clear() {
    _generation = Object();
    _cache.clear();
    _cachedBytes = 0;
    _inFlight.clear();
    _transientFailures.clear();
    while (_waiting.isNotEmpty) {
      _waiting.removeAt(0).result.complete(false);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    for (final transfer in _transfers.toList(growable: false)) {
      _retire(transfer);
    }
    clear();
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

/// A single consumer's demand, independent of other consumers of the URL.
final class ByteCacheRequest<T extends Object> {
  ByteCacheRequest._(this.priority);

  final Completer<T?> _result = Completer<T?>();
  void Function()? _onRelease;
  MediaRequestPriority priority;

  Future<T?> get result => _result.future;

  void release() {
    final release = _onRelease;
    _onRelease = null;
    _complete(null);
    release?.call();
  }

  void _complete(T? value) {
    _onRelease = null;
    if (!_result.isCompleted) _result.complete(value);
  }
}

final class _ByteCacheTransfer<T extends Object> {
  _ByteCacheTransfer(this.url, this.generation);

  final String url;
  final Object generation;
  final Set<ByteCacheRequest<T>> owners = {};
  // A revisit must not see an abandoned admission occupying the backlog cap.
  final Completer<void> abort = Completer<void>.sync();
  bool started = false;
  bool cancelled = false;

  MediaRequestPriority get priority =>
      owners.any((owner) => owner.priority == MediaRequestPriority.interactive)
      ? MediaRequestPriority.interactive
      : MediaRequestPriority.normal;

  void checkDemand() {
    if (cancelled) throw const _ByteCacheRequestCancelled();
  }
}

final class _ByteCacheRequestCancelled implements Exception {
  const _ByteCacheRequestCancelled();
}

final class _CacheWaiter<T extends Object> {
  _CacheWaiter(this.transfer);

  final _ByteCacheTransfer<T> transfer;
  final Completer<bool> result = Completer<bool>();
}

class _CacheEntry<T extends Object> {
  const _CacheEntry(this.value, {required this.byteSize});

  final T? value;
  final int byteSize;
}
