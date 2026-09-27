import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'origin_cooldown.dart';
import 'origin_request_gate.dart';
import 'retry_after.dart';

/// Identity of one safe GET hop for in-flight request sharing.
///
/// Callers may share only the same representation and transport limits. The
/// header snapshot includes credentials so accounts stay isolated; it remains
/// process-local and is never logged. Redirects are checked by each caller
/// after the shared hop completes.
final class DiscourseGetRequestKey {
  DiscourseGetRequestKey(
    this.url, {
    required Map<String, String> headers,
    required this.timeout,
    required this.maxResponseBytes,
  }) : _headers = Map.unmodifiable({
         for (final entry in headers.entries)
           entry.key.toLowerCase(): entry.value,
       });

  final Uri url;
  final Map<String, String> _headers;
  final Duration timeout;
  final int maxResponseBytes;

  @override
  bool operator ==(Object other) =>
      other is DiscourseGetRequestKey &&
      other.url == url &&
      other.timeout == timeout &&
      other.maxResponseBytes == maxResponseBytes &&
      other._headers.length == _headers.length &&
      _headers.entries.every(
        (entry) => other._headers[entry.key] == entry.value,
      );

  @override
  int get hashCode => Object.hash(
    url,
    timeout,
    maxResponseBytes,
    Object.hashAllUnordered(
      _headers.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}

/// Bounds requests per origin and turns a site-wide 429 into a shared origin
/// cooldown.
///
/// This coordinator deliberately does not retry. A queued operation is sent
/// once when capacity and the server's cooldown allow it; an operation that
/// already received a response remains the caller's result.
final class DiscourseRequestCoordinator {
  DiscourseRequestCoordinator({
    this.maxConcurrentPerOrigin = 4,
    this.maxQueuedPerOrigin = 64,
    this.defaultRateLimitCooldown = const Duration(seconds: 15),
    DateTime Function()? clock,
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       assert(defaultRateLimitCooldown >= Duration.zero),
       _clock = clock ?? DateTime.now,
       _gate = OriginRequestGate(
         maxConcurrentPerOrigin: maxConcurrentPerOrigin,
         maxQueuedPerOrigin: maxQueuedPerOrigin,
         cooldownPolicy: OriginRequestCooldownPolicy.wait,
         cooldownFactory: cooldownFactory,
       );

  final int maxConcurrentPerOrigin;

  /// A slow or rate-limited site must not let refreshes and navigation retain
  /// an unlimited number of request closures, bodies, and completers. Active
  /// requests do not count toward this backlog limit.
  final int maxQueuedPerOrigin;
  final Duration defaultRateLimitCooldown;
  final DateTime Function() _clock;

  final OriginRequestGate _gate;
  final Map<DiscourseGetRequestKey, Future<http.Response>> _gets = {};

  Future<http.Response> run(
    Uri url,
    Future<http.Response> Function() send, {
    DiscourseGetRequestKey? coalesce,
    Future<void>? abortTrigger,
  }) {
    if (_gate.isClosed) {
      return Future.error(StateError('Request coordinator is closed.'));
    }

    if (coalesce case final key? when abortTrigger == null) {
      final active = _gets[key];
      if (active != null) return active;

      late final Future<http.Response> request;
      request = _enqueue(url, send).whenComplete(() {
        if (identical(_gets[key], request)) {
          final removed = _gets.remove(key);
          assert(identical(removed, request));
        }
      });
      _gets[key] = request;
      return request;
    }

    return _enqueue(url, send, abortTrigger: abortTrigger);
  }

  Future<http.Response> _enqueue(
    Uri url,
    Future<http.Response> Function() send, {
    Future<void>? abortTrigger,
  }) => _translateGateErrors(
    _gate.run(url, (lease) async {
      final response = await send();
      if (response.statusCode == 429 && _pausesOrigin(response)) {
        final delay =
            explicitRetryAfter(response, now: _clock()) ??
            defaultRateLimitCooldown;
        lease.extendCooldown(delay);
      }
      return response;
    }, abortTrigger: abortTrigger),
    url,
  );

  Future<T> _translateGateErrors<T>(Future<T> operation, Uri url) async {
    try {
      return await operation;
    } on OriginRequestGateCancelledException {
      throw http.RequestAbortedException(url);
    } on OriginRequestGateOverloadException catch (error) {
      throw DiscourseRequestOverloadException(error.origin, error.maxQueued);
    } on OriginRequestGateClosedException {
      throw StateError('Request coordinator is closed.');
    }
  }

  void close() {
    _gate.close();
    _gets.clear();
  }

  static const Duration maximumRetryAfter = Duration(hours: 1);

  /// Discourse names its request-wide limiters (per IP, per user API key) in
  /// `Discourse-Rate-Limit-Error-Code`; those mean the whole site should be
  /// left alone. A refusal of one action — a daily like allowance, a new
  /// user's first-day replies, search's per-minute budget — carries no such
  /// code, and pausing the origin for it would hold every read of the forum
  /// for up to [maximumRetryAfter]. Its caller still receives the 429 and its
  /// delay. A 429 the site did not recognisably render (a proxy, a CDN, an
  /// empty or plain-text body) keeps pausing the origin.
  static bool _pausesOrigin(http.Response response) {
    if (response.headers.containsKey('discourse-rate-limit-error-code')) {
      return true;
    }
    return !_refusesOnlyTheAction(response);
  }

  /// Action refusals are a sentence and a few fields; anything larger is not
  /// one, and is not worth decoding to find out.
  static const int _maxActionRefusalBytes = 16 * 1024;

  static bool _refusesOnlyTheAction(http.Response response) {
    if (response.bodyBytes.length > _maxActionRefusalBytes) return false;
    try {
      return switch (jsonDecode(response.body)) {
        // ApplicationController's rendering of RateLimiter::LimitExceeded.
        {'error_type': 'rate_limit'} => true,
        // Controllers that refuse with `failed_json`, such as search.
        {'failed': 'FAILED'} => true,
        _ => false,
      };
    } catch (_) {
      return false;
    }
  }

  /// The explicit server delay, preserving the write error contract while the
  /// coordinator separately supplies a conservative default when it is absent.
  static Duration? explicitRetryAfter(http.Response response, {DateTime? now}) {
    final headerDuration = parseRetryAfter(
      response.headers['retry-after'],
      maximum: maximumRetryAfter,
      now: now ?? DateTime.now(),
      serverDate: response.headers['date'],
    );
    if (headerDuration != null) return headerDuration;

    try {
      final body = jsonDecode(response.body);
      final extras = jsonObject(jsonObject(body)['extras']);
      return switch (extras['wait_seconds']) {
        final num seconds when seconds.isFinite && seconds >= 0 =>
          seconds >= maximumRetryAfter.inSeconds
              ? maximumRetryAfter
              : _safeRetryAfter(seconds.round()),
        final String seconds => _safeRetryAfter(int.tryParse(seconds)),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }

  static Duration? _safeRetryAfter(int? seconds) {
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds.clamp(0, maximumRetryAfter.inSeconds));
  }
}

final class DiscourseRequestOverloadException implements Exception {
  const DiscourseRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Request backlog for $origin already contains $maxQueued operations.';
}
