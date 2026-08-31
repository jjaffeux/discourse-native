import 'dart:async';
import 'dart:io';

import 'origin_cooldown.dart';
import 'origin_request_gate.dart';

/// Aggregate and per-origin backpressure shared by native media caches.
///
/// Configured media caches can use separate HTTP clients. A per-client
/// connection limit would still let them drain independently, and a 429 for
/// one URL would not stop other distinct URLs already queued. This coordinator
/// limits opted-in work across clients and by origin, and turns the first 429
/// into a circuit breaker for every cache using it. Interactive media can move
/// ahead of queued background artwork without bypassing either limit.
final class MediaRequestCoordinator {
  static const defaultMaxConcurrent = 16;
  static const defaultMaxConcurrentPerOrigin = 8;

  MediaRequestCoordinator({
    this.maxConcurrent = defaultMaxConcurrent,
    this.maxConcurrentPerOrigin = defaultMaxConcurrentPerOrigin,
    this.maxQueuedPerOrigin = 64,
    this.defaultRateLimitCooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrent > 0),
       assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       assert(defaultRateLimitCooldown >= Duration.zero),
       _clock = clock ?? DateTime.now,
       _gate = OriginRequestGate(
         maxConcurrent: maxConcurrent,
         maxConcurrentPerOrigin: maxConcurrentPerOrigin,
         maxQueuedPerOrigin: maxQueuedPerOrigin,
         cooldownPolicy: OriginRequestCooldownPolicy.reject,
         cooldownFactory: cooldownFactory,
       );

  final int maxConcurrent;
  final int maxConcurrentPerOrigin;

  /// Active leases do not count toward this backlog limit.
  final int maxQueuedPerOrigin;
  final Duration defaultRateLimitCooldown;
  final DateTime Function() _clock;
  final OriginRequestGate _gate;

  Future<MediaRequestLease> acquire(
    Uri url, {
    Uri? relatedUrl,
    MediaRequestPriority priority = MediaRequestPriority.normal,
  }) {
    if (_gate.isClosed) {
      return Future.error(StateError('Media request coordinator is closed.'));
    }

    return _finishAcquire(
      _gate.acquire(
        url,
        priority: switch (priority) {
          MediaRequestPriority.normal => OriginRequestPriority.normal,
          MediaRequestPriority.interactive => OriginRequestPriority.interactive,
        },
      ),
      relatedUrl,
    );
  }

  Future<MediaRequestLease> _finishAcquire(
    Future<OriginRequestLease> admission,
    Uri? relatedUrl,
  ) async {
    try {
      final lease = await admission;
      return MediaRequestLease._(this, lease, relatedUrl: relatedUrl);
    } on OriginRequestGateCooldownException catch (error) {
      throw MediaOriginRateLimitedException(error.origin, error.retryAfter);
    } on OriginRequestGateOverloadException catch (error) {
      throw MediaRequestOverloadException(error.origin, error.maxQueued);
    } on OriginRequestGateClosedException {
      throw StateError('Media request coordinator is closed.');
    }
  }

  void _rateLimited(
    OriginRequestLease lease,
    Uri? relatedUrl,
    Map<String, String> headers,
  ) {
    if (_gate.isClosed) return;
    final delay = _retryAfter(headers) ?? defaultRateLimitCooldown;
    lease.extendCooldown(delay);
    if (relatedUrl != null && relatedUrl.origin != lease.origin) {
      _gate.extendCooldown(relatedUrl, delay);
    }
  }

  static const _maximumRetryAfter = Duration(hours: 1);

  Duration? _retryAfter(Map<String, String> headers) {
    final value = headers['retry-after']?.trim();
    if (value == null || value.isEmpty) return null;

    final seconds = int.tryParse(value);
    if (seconds != null && seconds >= 0) {
      return Duration(seconds: seconds.clamp(0, _maximumRetryAfter.inSeconds));
    }

    DateTime? date;
    try {
      date = HttpDate.parse(value);
    } on HttpException {
      return null;
    }
    final delay = date.difference(_clock().toUtc());
    if (delay <= Duration.zero) return Duration.zero;
    return delay > _maximumRetryAfter ? _maximumRetryAfter : delay;
  }

  void close() {
    _gate.close();
  }
}

enum MediaRequestPriority { normal, interactive }

/// A held origin slot. The caller releases it after consuming/cancelling the
/// response body so the cap applies to complete downloads, not just headers.
final class MediaRequestLease {
  MediaRequestLease._(this._owner, this._lease, {required Uri? relatedUrl})
    : origin = _lease.origin,
      relatedOrigin = relatedUrl?.origin,
      _relatedUrl = relatedUrl;

  final MediaRequestCoordinator _owner;
  final OriginRequestLease _lease;
  final Uri? _relatedUrl;
  final String origin;
  final String? relatedOrigin;
  bool _released = false;

  void rateLimited(Map<String, String> headers) {
    if (_released) return;
    _owner._rateLimited(_lease, _relatedUrl, headers);
  }

  void release() {
    if (_released) return;
    _released = true;
    _lease.release();
  }
}

final class MediaOriginRateLimitedException implements Exception {
  const MediaOriginRateLimitedException(this.origin, this.retryAfter);

  final String origin;
  final Duration retryAfter;

  @override
  String toString() =>
      'Media requests to $origin are paused for ${retryAfter.inSeconds}s.';
}

final class MediaRequestOverloadException implements Exception {
  const MediaRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Media request backlog for $origin already contains $maxQueued operations.';
}
