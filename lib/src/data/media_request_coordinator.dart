import 'dart:async';

import 'package:discourse_native/l10n/strings.dart';

import 'origin_cooldown.dart';
import 'origin_request_gate.dart';
import 'retry_after.dart';

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
    int maxConcurrent = defaultMaxConcurrent,
    int maxConcurrentPerOrigin = defaultMaxConcurrentPerOrigin,
    int maxQueuedPerOrigin = 64,
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

  final Duration defaultRateLimitCooldown;
  final DateTime Function() _clock;
  final OriginRequestGate _gate;

  Future<MediaRequestLease> acquire(
    Uri url, {
    Uri? relatedUrl,
    MediaRequestPriority priority = MediaRequestPriority.normal,
    Future<void>? abortTrigger,
  }) {
    return _finishAcquire(
      _gate.acquire(
        url,
        abortTrigger: abortTrigger,
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
    } on OriginRequestGateCancelledException {
      throw const MediaRequestCancelledException();
    }
  }

  void _rateLimited(
    OriginRequestLease lease,
    Uri? relatedUrl,
    Map<String, String> headers,
  ) {
    if (_gate.isClosed) return;
    final delay =
        parseRetryAfter(
          headers['retry-after'],
          maximum: _maximumRetryAfter,
          now: _clock(),
          serverDate: headers['date'],
        ) ??
        defaultRateLimitCooldown;
    lease.extendCooldown(delay);
    if (relatedUrl != null && relatedUrl.origin != lease.origin) {
      _gate.extendCooldown(relatedUrl, delay);
    }
  }

  static const _maximumRetryAfter = Duration(hours: 1);

  void close() {
    _gate.close();
  }
}

enum MediaRequestPriority { normal, interactive }

final class MediaRequestCancelledException implements Exception {
  const MediaRequestCancelledException();
}

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
  String toString() => appL10n.mediaRequestsToArePausedForS(
    (origin).toString(),
    (retryAfter.inSeconds).toString(),
  );
}

final class MediaRequestOverloadException implements Exception {
  const MediaRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() => appL10n.mediaRequestBacklogForAlreadyContainsOperations(
    (origin).toString(),
    (maxQueued).toString(),
  );
}
