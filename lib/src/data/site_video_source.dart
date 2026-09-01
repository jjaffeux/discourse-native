import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_credentials.dart';
import 'http_transport.dart';
import 'site_lifecycle.dart';

/// A URL the native player can request without leaking forum credentials.
final class SiteVideoSource {
  const SiteVideoSource(this.url);

  final Uri url;
}

/// The forum kept a protected upload on an authenticated URL.
///
/// Passing the API key to a media stack would let a later GET or byte-range
/// redirect carry it to another origin. Callers degrade to external-open
/// instead of accepting that ambiguity.
final class SiteVideoSourceRequiresAuthenticationException
    implements Exception {
  const SiteVideoSourceRequiresAuthenticationException();

  @override
  String toString() => 'SiteVideoSourceRequiresAuthenticationException';
}

/// Resolves protected Discourse video URLs before handing them to a player.
///
/// Native media stacks own their redirect handling, and do not promise to
/// remove custom headers when a forum redirects a secure upload to a signed
/// object-store URL. This resolver walks that chain itself. User API headers
/// are attached only to hops on the connected forum origin; a final CDN URL is
/// therefore returned without them.
final class SiteVideoSourceResolver {
  SiteVideoSourceResolver({
    required this.credentials,
    required this.lifecycle,
    http.Client? client,
    this.maximumRedirects = 5,
    this.requestTimeout = const Duration(seconds: 15),
  }) : assert(maximumRedirects >= 0),
       assert(requestTimeout > Duration.zero),
       _client = client == null
           ? SafeHttpClient.create()
           : SafeHttpClient.borrowed(client);

  final ApiCredentialReader credentials;
  final SiteLifecycle lifecycle;
  final int maximumRedirects;
  final Duration requestTimeout;
  final http.Client _client;

  bool _closed = false;
  final Completer<void> _closedSignal = Completer<void>();
  final Set<Completer<void>> _abortTriggers = {};

  Future<SiteVideoSource> resolve({
    required String siteUrl,
    required Uri url,
  }) async {
    if (_closed) throw StateError('Video source resolver is closed.');

    final site = requireSafeHttpUrl(Uri.parse(siteUrl));
    var current = requireSafeHttpUrl(url);
    if (current.origin != site.origin || !_isSecureUpload(current)) {
      return SiteVideoSource(current);
    }

    final elapsed = Stopwatch()..start();
    final lease = lifecycle.capture(siteUrl);
    final apiKey = await _guard(credentials.apiKeyFor(siteUrl), elapsed);
    _requireCurrent(lease);
    if (apiKey == null) return SiteVideoSource(current);

    final clientId = await _guard(credentials.clientId(), elapsed);
    _requireCurrent(lease);
    final forumHeaders = <String, String>{
      'User-Api-Key': apiKey,
      if (clientId.isNotEmpty) 'User-Api-Client-Id': clientId,
    };

    for (var redirects = 0; ; redirects++) {
      _requireCurrent(lease);
      final onForum = current.origin == site.origin;
      final response = await _sendHead(
        current,
        onForum ? forumHeaders : const {},
        _remaining(elapsed),
      );
      _requireCurrent(lease);

      final location = response.headers['location'];
      if (!_redirectStatuses.contains(response.statusCode) ||
          location == null) {
        if (onForum) {
          throw const SiteVideoSourceRequiresAuthenticationException();
        }
        return SiteVideoSource(current);
      }
      if (redirects >= maximumRedirects) {
        throw StateError('Video source exceeded $maximumRedirects redirects.');
      }
      current = resolveSafeHttpRedirect(current, location);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _closedSignal.complete();
    for (final trigger in _abortTriggers.toList(growable: false)) {
      if (!trigger.isCompleted) trigger.complete();
    }
    _abortTriggers.clear();
    _client.close();
  }

  Future<http.StreamedResponse> _sendHead(
    Uri url,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    if (_closed) throw StateError('Video source resolver is closed.');
    final abort = Completer<void>();
    _abortTriggers.add(abort);
    final request = http.AbortableRequest(
      'HEAD',
      url,
      abortTrigger: abort.future,
    )..headers.addAll(headers);
    final pending = _client.send(request);
    try {
      final response = await Future.any<http.StreamedResponse>([
        pending.timeout(
          timeout,
          onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw TimeoutException('Timed out resolving video source', timeout);
          },
        ),
        _closedSignal.future.then<http.StreamedResponse>((_) {
          if (!abort.isCompleted) abort.complete();
          throw StateError('Video source resolver is closed.');
        }),
      ]);
      // Only status and redirect headers are needed. Do not wait for or buffer
      // a broken server's HEAD body, and release the connection promptly.
      await response.stream.listen(null).cancel();
      return response;
    } finally {
      _abortTriggers.remove(abort);
    }
  }

  Duration _remaining(Stopwatch elapsed) {
    if (_closed) throw StateError('Video source resolver is closed.');
    final remaining = requestTimeout - elapsed.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException(
        'Timed out resolving video source',
        requestTimeout,
      );
    }
    return remaining;
  }

  Future<T> _guard<T>(Future<T> operation, Stopwatch elapsed) => Future.any<T>([
    operation.timeout(_remaining(elapsed)),
    _closedSignal.future.then<T>((_) {
      throw StateError('Video source resolver is closed.');
    }),
  ]);

  static bool _isSecureUpload(Uri url) =>
      url.pathSegments.contains('secure-uploads');

  void _requireCurrent(SiteLease lease) {
    if (_closed) throw StateError('Video source resolver is closed.');
    if (!lease.isCurrent) {
      throw StateError('Video source belongs to an expired account session.');
    }
  }
}

const Set<int> _redirectStatuses = {301, 302, 303, 307, 308};
