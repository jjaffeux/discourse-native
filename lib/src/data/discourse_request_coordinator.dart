import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'origin_cooldown.dart';

/// Identity of one safe GET for in-flight request sharing.
///
/// Credentials are part of the identity so two accounts can never receive one
/// another's response. The value stays process-local and is never logged.
final class DiscourseGetRequestKey {
  const DiscourseGetRequestKey(this.url, {this.apiKey, this.clientId});

  final Uri url;
  final String? apiKey;
  final String? clientId;

  @override
  bool operator ==(Object other) =>
      other is DiscourseGetRequestKey &&
      other.url == url &&
      other.apiKey == apiKey &&
      other.clientId == clientId;

  @override
  int get hashCode => Object.hash(url, apiKey, clientId);
}

/// Bounds requests per origin and turns a 429 into a shared origin cooldown.
///
/// This coordinator deliberately does not retry. A queued operation is sent
/// once when capacity and the server's cooldown allow it; an operation that
/// already received a response remains the caller's result.
final class DiscourseRequestCoordinator {
  DiscourseRequestCoordinator({
    this.maxConcurrentPerOrigin = 4,
    this.maxQueuedPerOrigin = 64,
    this.defaultRateLimitCooldown = const Duration(seconds: 15),
    OriginCooldown Function()? cooldownFactory,
  }) : assert(maxConcurrentPerOrigin > 0),
       assert(maxQueuedPerOrigin > 0),
       assert(defaultRateLimitCooldown >= Duration.zero),
       _newCooldown = cooldownFactory ?? OriginCooldown.new;

  final int maxConcurrentPerOrigin;

  /// Maximum work retained behind the active slots for one origin.
  ///
  /// A slow or rate-limited site must not let refreshes and navigation retain
  /// an unlimited number of request closures, bodies, and completers. Active
  /// requests do not count toward this backlog limit.
  final int maxQueuedPerOrigin;
  final Duration defaultRateLimitCooldown;

  final OriginCooldown Function() _newCooldown;
  final Map<String, _OriginQueue> _origins = {};
  final Map<DiscourseGetRequestKey, Future<http.Response>> _gets = {};
  bool _closed = false;

  _OriginQueue _createOriginQueue() => _OriginQueue(cooldown: _newCooldown());

  Future<http.Response> run(
    Uri url,
    Future<http.Response> Function() send, {
    DiscourseGetRequestKey? coalesce,
  }) {
    if (_closed) {
      return Future.error(StateError('Request coordinator is closed.'));
    }

    if (coalesce case final key?) {
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

    return _enqueue(url, send);
  }

  Future<http.Response> _enqueue(
    Uri url,
    Future<http.Response> Function() send,
  ) {
    final origin = url.origin;
    final queue = _origins.putIfAbsent(origin, _createOriginQueue);
    if (queue.waiting.length >= maxQueuedPerOrigin) {
      return Future.error(
        DiscourseRequestOverloadException(origin, maxQueuedPerOrigin),
      );
    }
    final pending = _PendingRequest(send);
    queue.waiting.add(pending);
    _drain(origin, queue);
    return pending.result.future;
  }

  void _drain(String origin, _OriginQueue queue) {
    if (_closed) return;
    if (queue.cooldown.remaining != null) return;

    while (queue.active < maxConcurrentPerOrigin && queue.waiting.isNotEmpty) {
      final pending = queue.waiting.removeFirst();
      queue.active++;
      unawaited(_run(origin, queue, pending));
    }
    _forgetIdle(origin, queue);
  }

  Future<void> _run(
    String origin,
    _OriginQueue queue,
    _PendingRequest pending,
  ) async {
    try {
      final response = await pending.send();
      // An in-flight response may outlive close(). It must not re-arm the
      // origin cooldown: close() has already dropped the queue, so a wake
      // timer set now could never be cancelled.
      if (response.statusCode == 429 && !_closed) {
        final delay = explicitRetryAfter(response) ?? defaultRateLimitCooldown;
        queue.cooldown.extend(delay, onExpired: () => _drain(origin, queue));
      }
      pending.result.complete(response);
    } catch (error, stackTrace) {
      pending.result.completeError(error, stackTrace);
    } finally {
      queue.active--;
      _drain(origin, queue);
    }
  }

  void _forgetIdle(String origin, _OriginQueue queue) {
    if (queue.active == 0 &&
        queue.waiting.isEmpty &&
        queue.cooldown.remaining == null) {
      _origins.remove(origin);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final error = StateError('Request coordinator is closed.');
    for (final queue in _origins.values) {
      queue.cooldown.cancel();
      while (queue.waiting.isNotEmpty) {
        queue.waiting.removeFirst().result.completeError(error);
      }
    }
    _origins.clear();
    _gets.clear();
  }

  static const Duration maximumRetryAfter = Duration(hours: 1);

  /// The explicit server delay, preserving the write error contract while the
  /// coordinator separately supplies a conservative default when it is absent.
  static Duration? explicitRetryAfter(http.Response response) {
    final header = int.tryParse(response.headers['retry-after'] ?? '');
    final headerDuration = _safeRetryAfter(header);
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

/// A request rejected before delegation because an origin's backlog is full.
final class DiscourseRequestOverloadException implements Exception {
  const DiscourseRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Request backlog for $origin already contains $maxQueued operations.';
}

final class _OriginQueue {
  _OriginQueue({required this.cooldown});

  final OriginCooldown cooldown;
  final Queue<_PendingRequest> waiting = Queue();
  int active = 0;
}

final class _PendingRequest {
  _PendingRequest(this.send);

  final Future<http.Response> Function() send;
  final Completer<http.Response> result = Completer();
}
