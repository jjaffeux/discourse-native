import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/json.dart';
import 'origin_cooldown.dart';
import 'origin_request_gate.dart';

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

  final OriginRequestGate _gate;
  final Map<DiscourseGetRequestKey, Future<http.Response>> _gets = {};

  Future<http.Response> run(
    Uri url,
    Future<http.Response> Function() send, {
    DiscourseGetRequestKey? coalesce,
  }) {
    if (_gate.isClosed) {
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
  ) => _translateGateErrors(
    _gate.run(url, (lease) async {
      final response = await send();
      if (response.statusCode == 429) {
        final delay = explicitRetryAfter(response) ?? defaultRateLimitCooldown;
        lease.extendCooldown(delay);
      }
      return response;
    }),
  );

  Future<T> _translateGateErrors<T>(Future<T> operation) async {
    try {
      return await operation;
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

final class DiscourseRequestOverloadException implements Exception {
  const DiscourseRequestOverloadException(this.origin, this.maxQueued);

  final String origin;
  final int maxQueued;

  @override
  String toString() =>
      'Request backlog for $origin already contains $maxQueued operations.';
}
