import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';

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
    this.defaultRateLimitCooldown = const Duration(seconds: 15),
  }) : assert(maxConcurrentPerOrigin > 0),
       assert(defaultRateLimitCooldown >= Duration.zero);

  final int maxConcurrentPerOrigin;
  final Duration defaultRateLimitCooldown;

  final Map<String, _OriginQueue> _origins = {};
  final Map<DiscourseGetRequestKey, Future<http.Response>> _gets = {};
  bool _closed = false;

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
    final queue = _origins.putIfAbsent(origin, _OriginQueue.new);
    final pending = _PendingRequest(send);
    queue.waiting.add(pending);
    _drain(origin, queue);
    return pending.result.future;
  }

  void _drain(String origin, _OriginQueue queue) {
    if (_closed) return;
    final now = DateTime.now();
    final blockedUntil = queue.blockedUntil;
    if (blockedUntil != null && blockedUntil.isAfter(now)) {
      _wakeAfter(origin, queue, blockedUntil.difference(now));
      return;
    }

    queue.blockedUntil = null;
    queue.wake?.cancel();
    queue.wake = null;
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
      if (response.statusCode == 429) {
        final delay = explicitRetryAfter(response) ?? defaultRateLimitCooldown;
        final until = DateTime.now().add(delay);
        if (queue.blockedUntil case final held? when held.isAfter(until)) {
          // A longer rate limit from another in-flight response still owns the
          // origin. Never shorten it because this response asked for less.
        } else {
          queue.blockedUntil = until;
          _wakeAfter(origin, queue, delay);
        }
      }
      pending.result.complete(response);
    } catch (error, stackTrace) {
      pending.result.completeError(error, stackTrace);
    } finally {
      queue.active--;
      _drain(origin, queue);
    }
  }

  void _wakeAfter(String origin, _OriginQueue queue, Duration delay) {
    queue.wake?.cancel();
    queue.wake = Timer(delay, () {
      queue.wake = null;
      _drain(origin, queue);
    });
  }

  void _forgetIdle(String origin, _OriginQueue queue) {
    if (queue.active == 0 &&
        queue.waiting.isEmpty &&
        queue.blockedUntil == null) {
      _origins.remove(origin);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final error = StateError('Request coordinator is closed.');
    for (final queue in _origins.values) {
      queue.wake?.cancel();
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

final class _OriginQueue {
  final Queue<_PendingRequest> waiting = Queue();
  int active = 0;
  DateTime? blockedUntil;
  Timer? wake;
}

final class _PendingRequest {
  _PendingRequest(this.send);

  final Future<http.Response> Function() send;
  final Completer<http.Response> result = Completer();
}
