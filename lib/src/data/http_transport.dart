import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:discourse_native/l10n/strings.dart';
import 'package:http/http.dart' as http;

import 'http_basic_auth.dart';
import 'http_url_safety.dart';

/// Discourse's crawler policy must recognize anonymous native requests too.
/// Shared by API, appearance, live-update, and media HTTP producers.
const discourseUserAgent = 'DiscourseNative/1.0';

final class HttpResponseTooLargeException implements Exception {
  const HttpResponseTooLargeException(this.url, this.maxBytes);

  final Uri url;
  final int maxBytes;

  @override
  String toString() => appL10n.httpResponseTooLargeExceptionBytes(
    (url).toString(),
    (maxBytes).toString(),
  );
}

/// Whether a socket failure proves no connection was ever opened.
bool connectionNeverOpened(Object error) => switch (error) {
  // Dart's own words, unlike an OS error's text, so no locale changes them.
  SocketException(:final message)
      when message.startsWith('Failed host lookup') =>
    true,
  SocketException(osError: OSError(:final errorCode)) =>
    _connectionNeverOpened.contains(errorCode),
  _ => false,
};

/// ECONNREFUSED answers only a connection attempt: a peer resetting an open
/// connection reports ECONNRESET. Both kernels hold ENETUNREACH, EHOSTUNREACH
/// and ENETDOWN on an open connection as soft errors, reported only when
/// retransmission gives up, minutes after any write here has timed out. The
/// numbers differ per kernel, and Darwin's EPROTO is Linux's ENETDOWN, so only
/// the running kernel's own are recognised.
final Set<int> _connectionNeverOpened = switch (Platform.operatingSystem) {
  'macos' || 'ios' => const {61, 51, 65, 50},
  'linux' || 'android' => const {111, 101, 113, 100},
  _ => const {},
};

/// Rechecks transport safety at the final boundary and refuses redirects.
final class SafeHttpClient extends http.BaseClient {
  SafeHttpClient.owned(this._client, {HttpBasicAuthStore? basicAuth})
    : basicAuth = _authenticationFor(_client, basicAuth),
      _closeClient = true;

  SafeHttpClient.borrowed(this._client, {HttpBasicAuthStore? basicAuth})
    : basicAuth = _authenticationFor(_client, basicAuth),
      _closeClient = false;

  factory SafeHttpClient.create({HttpBasicAuthStore? basicAuth}) =>
      SafeHttpClient.owned(http.Client(), basicAuth: basicAuth);

  static HttpBasicAuthStore _authenticationFor(
    http.Client client,
    HttpBasicAuthStore? authentication,
  ) {
    if (client is SafeHttpClient) {
      if (authentication != null &&
          !identical(authentication, client.basicAuth)) {
        throw ArgumentError(
          'Wrapped HTTP clients must share server authentication.',
        );
      }
      return client.basicAuth;
    }
    return authentication ?? HttpBasicAuthStore.instance;
  }

  final HttpBasicAuthStore basicAuth;

  void authenticate(http.BaseRequest request) {
    requireSafeHttpUrl(request.url);
    final authorization = basicAuth.authorizationFor(request.url);
    if (authorization != null) {
      request.headers.putIfAbsent('Authorization', () => authorization);
    }
  }

  final http.Client _client;
  final bool _closeClient;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    authenticate(request);
    request.followRedirects = false;
    return _client.send(request);
  }

  @override
  void close() {
    if (_closeClient) _client.close();
  }
}

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

  final timeoutAbort = Completer<void>();
  final callerAbort = switch (request) {
    http.Abortable(:final abortTrigger?) => abortTrigger,
    _ => null,
  };
  final transportAbort = callerAbort == null
      ? timeoutAbort.future
      : Future.any<void>([callerAbort, timeoutAbort.future]);
  // A client can fail before subscribing to the abort trigger.
  transportAbort.ignore();
  final sentRequest = _withAbortTrigger(request, transportAbort);
  final abortError = callerAbort?.then(
    (_) => http.RequestAbortedException(request.url),
  );
  final elapsed = Stopwatch()..start();
  final response = Future<http.StreamedResponse>.sync(
    () => client.send(sentRequest),
  );
  late http.StreamedResponse streamed;
  try {
    streamed = await Future.any<http.StreamedResponse>([
      response,
      if (abortError != null)
        abortError.then<http.StreamedResponse>((error) => throw error),
    ]).timeout(timeout);
  } on TimeoutException {
    timeoutAbort.complete();
    cancelLateHttpResponse(response);
    rethrow;
  } on Object {
    if (abortError != null) cancelLateHttpResponse(response);
    rethrow;
  }
  final contentLength = streamed.contentLength;
  if (contentLength != null && contentLength > maxBodyBytes) {
    cancelUnreadHttpBody(streamed.stream).ignore();
    throw HttpResponseTooLargeException(request.url, maxBodyBytes);
  }

  final Duration remaining;
  try {
    remaining = _remaining(timeout, elapsed);
  } on TimeoutException {
    timeoutAbort.complete();
    cancelUnreadHttpBody(streamed.stream).ignore();
    rethrow;
  }
  final Uint8List bytes;
  try {
    bytes =
        await readBoundedHttpBody(
          streamed.stream,
          maxBytes: maxBodyBytes,
          timeout: remaining,
          abortError: abortError,
          timeoutError: TimeoutException(
            appL10n.timedOutReadingResponseFrom(request.url.toString()),
            remaining,
          ),
        ) ??
        (throw HttpResponseTooLargeException(request.url, maxBodyBytes));
  } on TimeoutException {
    timeoutAbort.complete();
    rethrow;
  }
  return http.Response.bytes(
    bytes,
    streamed.statusCode,
    // The abortable transport request is an implementation detail. Preserve
    // the caller's request identity in the buffered response, as this helper
    // did before deadline cancellation was added.
    request: request,
    headers: streamed.headers,
    isRedirect: streamed.isRedirect,
    persistentConnection: streamed.persistentConnection,
    reasonPhrase: streamed.reasonPhrase,
  );
}

http.BaseRequest _withAbortTrigger(
  http.BaseRequest request,
  Future<void> abortTrigger,
) {
  final http.BaseRequest abortable;
  switch (request) {
    case http.Request():
      abortable = http.AbortableRequest(
        request.method,
        request.url,
        abortTrigger: abortTrigger,
      )..bodyBytes = request.bodyBytes;
    case http.MultipartRequest():
      // A file part's stream can be read once, by whichever request finalizes
      // first. The caller's request is never finalized, so the parts move.
      abortable =
          http.AbortableMultipartRequest(
              request.method,
              request.url,
              abortTrigger: abortTrigger,
            )
            ..fields.addAll(request.fields)
            ..files.addAll(request.files);
    default:
      return request;
  }
  return abortable
    ..headers.addAll(request.headers)
    ..followRedirects = request.followRedirects
    ..maxRedirects = request.maxRedirects
    ..persistentConnection = request.persistentConnection;
}

/// Buffers a response up to [maxBytes], returning null on overflow.
Future<Uint8List?> readBoundedHttpBody(
  Stream<List<int>> stream, {
  required int maxBytes,
  required Duration timeout,
  required TimeoutException timeoutError,
  Future<Object>? abortError,
}) {
  final chunks = BytesBuilder(copy: false);
  final result = Completer<Uint8List?>();
  StreamSubscription<List<int>>? subscription;
  var cancelOnListen = false;

  void cancel() {
    chunks.clear();
    final active = subscription;
    if (active == null) {
      cancelOnListen = true;
    } else {
      active.cancel().ignore();
    }
  }

  void abort(Object error, [StackTrace? stackTrace]) {
    if (result.isCompleted) return;
    result.completeError(error, stackTrace);
    cancel();
  }

  abortError?.then<void>(abort, onError: abort).ignore();

  subscription = stream.listen(
    (chunk) {
      if (result.isCompleted) return;
      if (chunks.length + chunk.length > maxBytes) {
        result.complete(null);
        cancel();
        return;
      }
      chunks.add(chunk);
    },
    onError: (Object error, StackTrace stackTrace) {
      chunks.clear();
      if (!result.isCompleted) result.completeError(error, stackTrace);
    },
    onDone: () {
      if (!result.isCompleted) result.complete(chunks.takeBytes());
    },
    cancelOnError: true,
  );
  if (cancelOnListen) subscription.cancel().ignore();

  final deadline = Timer(timeout, () {
    if (result.isCompleted) return;
    result.completeError(timeoutError);
    cancel();
  });
  return result.future.whenComplete(deadline.cancel);
}

Duration _remaining(Duration timeout, Stopwatch elapsed) {
  final remaining = timeout - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException(appL10n.timedOutBeforeTheResponseBody, timeout);
  }
  return remaining;
}

/// Releases a response body whose bytes the caller will never consume.
Future<void> cancelUnreadHttpBody(Stream<List<int>> stream) =>
    stream.listen(null).cancel();

/// Releases the body if an abandoned request eventually returns headers.
void cancelLateHttpResponse(Future<http.StreamedResponse> pending) {
  pending
      .then<void>((response) => cancelUnreadHttpBody(response.stream))
      .ignore();
}
