import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'origin_cooldown.dart';

/// One process-wide backpressure gate for native-managed media requests.
///
/// Avatar and emoji caches use separate HTTP clients. A per-client connection
/// limit therefore still let both caches drain four requests at once, and a
/// 429 for one URL did not stop the other distinct URLs already queued. This
/// coordinator limits their aggregate work by origin and turns the first 429
/// into an origin-wide circuit breaker.
final class MediaRequestCoordinator {
  MediaRequestCoordinator({
    this.maxConcurrentPerOrigin = 2,
    this.maxQueuedPerOrigin = 64,
    this.defaultRateLimitCooldown = const Duration(minutes: 2),
    DateTime Function()? clock,
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       assert(defaultRateLimitCooldown >= Duration.zero),
       _clock = clock ?? DateTime.now,
       _newCooldown = cooldownFactory ?? OriginCooldown.new;

  /// Shared by the production avatar and emoji singletons.
  static final shared = MediaRequestCoordinator();

  final int maxConcurrentPerOrigin;

  /// Maximum work retained behind the active slots for one origin.
  ///
  /// Active leases do not count toward this backlog limit.
  final int maxQueuedPerOrigin;
  final Duration defaultRateLimitCooldown;
  final DateTime Function() _clock;
  final OriginCooldown Function() _newCooldown;
  final Map<String, _MediaOriginQueue> _origins = {};
  bool _closed = false;

  _MediaOriginQueue _createOriginQueue() =>
      _MediaOriginQueue(cooldown: _newCooldown());

  Future<MediaRequestLease> acquire(Uri url, {Uri? relatedUrl}) {
    if (_closed) {
      return Future.error(StateError('Media request coordinator is closed.'));
    }

    final origin = url.origin;
    final queue = _origins.putIfAbsent(origin, _createOriginQueue);
    final remaining = queue.cooldown.remaining;
    if (remaining != null) {
      return Future.error(MediaOriginRateLimitedException(origin, remaining));
    }
    if (queue.waiting.length >= maxQueuedPerOrigin) {
      return Future.error(
        MediaRequestOverloadException(origin, maxQueuedPerOrigin),
      );
    }

    final pending = _PendingMediaRequest(relatedOrigin: relatedUrl?.origin);
    queue.waiting.add(pending);
    _drain(origin, queue);
    return pending.result.future;
  }

  void _drain(String origin, _MediaOriginQueue queue) {
    if (_closed) return;
    final remaining = queue.cooldown.remaining;
    if (remaining != null) {
      _rejectWaiting(origin, queue, remaining);
      return;
    }

    while (queue.active < maxConcurrentPerOrigin && queue.waiting.isNotEmpty) {
      final pending = queue.waiting.removeFirst();
      queue.active++;
      pending.result.complete(
        MediaRequestLease._(this, origin, relatedOrigin: pending.relatedOrigin),
      );
    }
    _forgetIdle(origin, queue);
  }

  void _release(String origin) {
    final queue = _origins[origin];
    if (queue == null) return;
    queue.active--;
    assert(queue.active >= 0);
    _drain(origin, queue);
  }

  void _rateLimited(
    String origin,
    String? relatedOrigin,
    Map<String, String> headers,
  ) {
    // An in-flight response may outlive close(). Its lease must become inert,
    // rather than recreating an origin queue and a long-lived wake timer.
    if (_closed) return;
    final delay = _retryAfter(headers) ?? defaultRateLimitCooldown;
    _block(origin, delay);
    if (relatedOrigin != null && relatedOrigin != origin) {
      _block(relatedOrigin, delay);
    }
  }

  void _block(String origin, Duration delay) {
    if (_closed) return;
    final queue = _origins.putIfAbsent(origin, _createOriginQueue);
    final remaining = queue.cooldown.extend(
      delay,
      onExpired: () => _drain(origin, queue),
    );
    if (remaining == null) {
      _drain(origin, queue);
      return;
    }
    _rejectWaiting(origin, queue, remaining);
  }

  void _rejectWaiting(
    String origin,
    _MediaOriginQueue queue,
    Duration remaining,
  ) {
    while (queue.waiting.isNotEmpty) {
      queue.waiting.removeFirst().result.completeError(
        MediaOriginRateLimitedException(origin, remaining),
      );
    }
  }

  void _forgetIdle(String origin, _MediaOriginQueue queue) {
    if (queue.active == 0 &&
        queue.waiting.isEmpty &&
        queue.cooldown.remaining == null) {
      _origins.remove(origin);
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
    if (_closed) return;
    _closed = true;
    final error = StateError('Media request coordinator is closed.');
    for (final queue in _origins.values) {
      queue.cooldown.cancel();
      while (queue.waiting.isNotEmpty) {
        queue.waiting.removeFirst().result.completeError(error);
      }
    }
    _origins.clear();
  }
}

/// A held origin slot. The caller releases it after consuming/cancelling the
/// response body so the cap applies to complete downloads, not just headers.
final class MediaRequestLease {
  MediaRequestLease._(this._owner, this.origin, {required this.relatedOrigin});

  final MediaRequestCoordinator _owner;
  final String origin;
  final String? relatedOrigin;
  bool _released = false;

  void rateLimited(Map<String, String> headers) {
    if (_released) return;
    _owner._rateLimited(origin, relatedOrigin, headers);
  }

  void release() {
    if (_released) return;
    _released = true;
    _owner._release(origin);
  }
}

/// Expected local rejection while an origin's server cooldown is active.
final class MediaOriginRateLimitedException implements Exception {
  const MediaOriginRateLimitedException(this.origin, this.retryAfter);

  final String origin;
  final Duration retryAfter;

  @override
  String toString() =>
      'Media requests to $origin are paused for ${retryAfter.inSeconds}s.';
}

/// A request rejected before delegation because an origin's backlog is full.
final class MediaRequestOverloadException implements Exception {
  const MediaRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Media request backlog for $origin already contains $maxQueued operations.';
}

final class _MediaOriginQueue {
  _MediaOriginQueue({required this.cooldown});

  final OriginCooldown cooldown;
  final Queue<_PendingMediaRequest> waiting = Queue();
  int active = 0;
}

final class _PendingMediaRequest {
  _PendingMediaRequest({required this.relatedOrigin});

  final String? relatedOrigin;
  final Completer<MediaRequestLease> result = Completer();
}
