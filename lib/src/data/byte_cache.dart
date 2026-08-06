import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'discourse_api.dart';

/// Fetches images once each, and not all at once.
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
    this.retryAfter = const Duration(minutes: 2),
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final int maxConcurrent;

  /// How long a *transient* failure is remembered. A rate limit is temporary,
  /// so caching it forever would leave images blank until the app restarts —
  /// but retrying immediately is what earned the rate limit.
  final Duration retryAfter;

  final Duration timeout;

  final Map<String, T?> _cache = {};
  final Map<String, DateTime> _transientFailures = {};
  final Map<String, Future<T?>> _inFlight = {};
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _active = 0;

  /// What a 200 means here, or null when the bytes cannot be drawn.
  @protected
  T? decode(http.Response response);

  /// Already-known result, so a rebuild paints without going async again.
  bool isCached(String url) => _cache.containsKey(url) && !_cooledDown(url);
  T? cached(String url) => _cache[url];

  /// True once a transient failure is old enough to be worth retrying.
  bool _cooledDown(String url) {
    final failedAt = _transientFailures[url];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) > retryAfter;
  }

  /// Null means the image is unavailable — a 429, a 404, or a format we cannot
  /// draw. Cached either way so it is asked for exactly once.
  Future<T?> load(String url) {
    if (_cooledDown(url)) {
      _cache.remove(url);
      _transientFailures.remove(url);
    }
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    return _inFlight[url] ??= _fetch(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<T?> _fetch(String url) async {
    await _acquire();
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            // Sites are friendlier to a request that identifies itself.
            headers: const {'User-Agent': DiscourseApi.userAgent},
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        // 429 and 5xx pass; 404 and friends are permanent.
        if (response.statusCode == 429 || response.statusCode >= 500) {
          _transientFailures[url] = DateTime.now();
        }
        return _cache[url] = null;
      }
      _transientFailures.remove(url);
      return _cache[url] = decode(response);
    } catch (_) {
      // Offline or timed out: worth another go later.
      _transientFailures[url] = DateTime.now();
      return _cache[url] = null;
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
      return;
    }
    _active--;
  }

  /// Test seam: forget everything fetched so far.
  void clear() {
    _cache.clear();
    _inFlight.clear();
    _transientFailures.clear();
  }
}
