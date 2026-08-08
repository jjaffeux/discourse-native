import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// A URL that cannot safely carry a Discourse API request.
final class UnsafeHttpTransportException implements Exception {
  const UnsafeHttpTransportException(this.url);

  final Uri url;

  @override
  String toString() => 'UnsafeHttpTransportException($url)';
}

/// A response whose declared or received body exceeded the caller's bound.
final class HttpResponseTooLargeException implements Exception {
  const HttpResponseTooLargeException(this.url, this.maxBytes);

  final Uri url;
  final int maxBytes;

  @override
  String toString() => 'HttpResponseTooLargeException($url, $maxBytes bytes)';
}

/// Accepts encrypted HTTP URLs and plaintext URLs for loopback development.
Uri requireSafeHttpUrl(Uri url) {
  if (!url.hasAuthority || url.host.isEmpty) {
    throw UnsafeHttpTransportException(url);
  }
  if (url.scheme == 'https') return url;
  if (url.scheme == 'http' && _isLoopbackHost(url.host)) return url;

  throw UnsafeHttpTransportException(url);
}

/// Resolves and validates a redirect without allowing an HTTPS downgrade.
Uri resolveSafeHttpRedirect(Uri source, String location) {
  final target = source.resolve(location);
  if (source.scheme == 'https' && target.scheme != 'https') {
    throw UnsafeHttpTransportException(target);
  }
  return requireSafeHttpUrl(target);
}

bool _isLoopbackHost(String host) {
  var normalized = host.toLowerCase();
  if (normalized.endsWith('.')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }

  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized == '::1') {
    return true;
  }

  final octets = normalized.split('.').map(int.tryParse).toList();
  return octets.length == 4 &&
      octets.every((octet) => octet != null && octet >= 0 && octet <= 255) &&
      octets.first == 127;
}

/// Enforces transport safety at the final request boundary and refuses
/// automatic redirects.
final class SafeHttpClient extends http.BaseClient {
  SafeHttpClient.owned(this._client) : _closeClient = true;

  SafeHttpClient.borrowed(this._client) : _closeClient = false;

  factory SafeHttpClient.create() => SafeHttpClient.owned(http.Client());

  final http.Client _client;
  final bool _closeClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requireSafeHttpUrl(request.url);
    request.followRedirects = false;
    return _client.send(request);
  }

  @override
  void close() {
    if (_closeClient) _client.close();
  }
}

/// Sends one request and buffers a bounded response within one total deadline.
///
/// `http.Response.fromStream` has neither a body limit nor a timeout once the
/// response headers arrive. API responses are buffered JSON, so callers need
/// both: a peer that stalls halfway through a body must not hold the operation
/// forever, and a false or absent content length must not allow unbounded
/// memory growth.
Future<http.Response> sendBoundedHttpRequest(
  http.Client client,
  http.BaseRequest request, {
  required Duration timeout,
  required int maxBodyBytes,
}) async {
  assert(timeout > Duration.zero);
  assert(maxBodyBytes > 0);

  final elapsed = Stopwatch()..start();
  final response = client.send(request);
  late http.StreamedResponse streamed;
  try {
    streamed = await response.timeout(timeout);
  } on TimeoutException {
    response
        .then<void>((lateResponse) => _cancel(lateResponse.stream))
        .ignore();
    rethrow;
  }
  final contentLength = streamed.contentLength;
  if (contentLength != null && contentLength > maxBodyBytes) {
    _cancel(streamed.stream);
    throw HttpResponseTooLargeException(request.url, maxBodyBytes);
  }

  final Duration remaining;
  try {
    remaining = _remaining(timeout, elapsed);
  } on TimeoutException {
    _cancel(streamed.stream);
    rethrow;
  }
  final bytes = await _readBoundedBody(
    streamed.stream,
    request.url,
    maxBodyBytes,
    remaining,
  );
  return http.Response.bytes(
    bytes,
    streamed.statusCode,
    request: streamed.request,
    headers: streamed.headers,
    isRedirect: streamed.isRedirect,
    persistentConnection: streamed.persistentConnection,
    reasonPhrase: streamed.reasonPhrase,
  );
}

Future<Uint8List> _readBoundedBody(
  Stream<List<int>> stream,
  Uri url,
  int maxBytes,
  Duration timeout,
) {
  final chunks = BytesBuilder(copy: false);
  final result = Completer<Uint8List>();
  StreamSubscription<List<int>>? subscription;
  var cancelOnListen = false;

  void cancel() {
    final active = subscription;
    if (active == null) {
      cancelOnListen = true;
    } else {
      active.cancel().ignore();
    }
  }

  subscription = stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (chunks.length + chunk.length > maxBytes) {
        result.completeError(HttpResponseTooLargeException(url, maxBytes));
        cancel();
        return;
      }
      chunks.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      if (!result.isCompleted) result.completeError(error, stackTrace);
    },
    onDone: () {
      if (!result.isCompleted) result.complete(chunks.takeBytes());
    },
    cancelOnError: true,
  );
  if (cancelOnListen) subscription.cancel().ignore();

  return result.future.timeout(
    timeout,
    onTimeout: () {
      cancel();
      throw TimeoutException('Timed out reading response from $url', timeout);
    },
  );
}

Duration _remaining(Duration timeout, Stopwatch elapsed) {
  final remaining = timeout - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException('Timed out before the response body', timeout);
  }
  return remaining;
}

void _cancel(Stream<List<int>> stream) => stream.listen(null).cancel().ignore();
