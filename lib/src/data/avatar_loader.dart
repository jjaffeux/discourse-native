import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// What came back for an avatar URL.
class AvatarBytes {
  const AvatarBytes(this.bytes, {required this.isSvg});

  final Uint8List bytes;
  final bool isSvg;
}

/// Fetches avatars once each, and not all at once.
///
/// Two problems make a plain `NetworkImage` the wrong tool here:
///
/// * Discourse serves some avatars as SVG even though the URL ends in `.png`,
///   so the format cannot be known from the URL — only from the bytes.
/// * A first render asks for three avatars per topic across thirty topics. Fired
///   at once that earns an HTTP 429 from the site, and the failures are then
///   retried on every rebuild.
///
/// So: cache by URL including failures, and cap how many are in flight.
class AvatarLoader {
  AvatarLoader({
    http.Client? client,
    this.maxConcurrent = 4,
    this.retryAfter = const Duration(minutes: 2),
  }) : _client = client ?? http.Client();

  /// Swappable so tests do not reach the network.
  static AvatarLoader instance = AvatarLoader();

  final http.Client _client;
  final int maxConcurrent;

  /// How long a *transient* failure is remembered. A rate limit is temporary,
  /// so caching it forever would leave avatars blank until the app restarts —
  /// but retrying immediately is what earned the rate limit.
  final Duration retryAfter;

  final Map<String, AvatarBytes?> _cache = {};
  final Map<String, DateTime> _transientFailures = {};
  final Map<String, Future<AvatarBytes?>> _inFlight = {};
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();
  int _active = 0;

  /// Already-known result, so a rebuild paints without going async again.
  bool isCached(String url) => _cache.containsKey(url) && !_cooledDown(url);
  AvatarBytes? cached(String url) => _cache[url];

  /// True once a transient failure is old enough to be worth retrying.
  bool _cooledDown(String url) {
    final failedAt = _transientFailures[url];
    if (failedAt == null) return false;
    return DateTime.now().difference(failedAt) > retryAfter;
  }

  /// Null means the avatar is unavailable — a 429, a 404, or a format we
  /// cannot draw. Cached either way so it is asked for exactly once.
  Future<AvatarBytes?> load(String url) {
    if (_cooledDown(url)) {
      _cache.remove(url);
      _transientFailures.remove(url);
    }
    if (_cache.containsKey(url)) return Future.value(_cache[url]);
    return _inFlight[url] ??= _fetch(url).whenComplete(() {
      _inFlight.remove(url);
    });
  }

  Future<AvatarBytes?> _fetch(String url) async {
    await _acquire();
    try {
      final response = await _client
          .get(
            Uri.parse(url),
            // Sites are friendlier to a request that identifies itself.
            headers: const {'User-Agent': 'DiscourseNative/1.0'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        // 429 and 5xx pass; 404 and friends are permanent.
        if (response.statusCode == 429 || response.statusCode >= 500) {
          _transientFailures[url] = DateTime.now();
        }
        return _cache[url] = null;
      }
      _transientFailures.remove(url);
      return _cache[url] = AvatarBytes(
        response.bodyBytes,
        isSvg: looksLikeSvg(
          response.bodyBytes,
          contentType: response.headers['content-type'],
        ),
      );
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

  /// Content type first; some CDNs mislabel, so fall back to sniffing the
  /// leading bytes for an SVG or XML prolog.
  static bool looksLikeSvg(Uint8List bytes, {String? contentType}) {
    if (contentType != null && contentType.contains('image/svg')) return true;
    if (contentType != null && contentType.startsWith('image/')) {
      // A declared raster type is trustworthy; do not sniff further.
      return false;
    }

    final head = String.fromCharCodes(bytes.take(256)).trimLeft().toLowerCase();
    return head.startsWith('<svg') ||
        (head.startsWith('<?xml') && head.contains('<svg'));
  }

  /// Test seam: forget everything fetched so far.
  void clear() {
    _cache.clear();
    _inFlight.clear();
    _transientFailures.clear();
  }
}
