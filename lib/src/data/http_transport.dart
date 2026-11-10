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
  final sentRequest = _withAbortTrigger(request, timeoutAbort.future);
  final elapsed = Stopwatch()..start();
  final response = client.send(sentRequest);
  late http.StreamedResponse streamed;
  try {
    streamed = await response.timeout(timeout);
  } on TimeoutException {
    timeoutAbort.complete();
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
    timeoutAbort.complete();
    _cancel(streamed.stream);
    rethrow;
  }
  final Uint8List bytes;
  try {
    bytes = await _readBoundedBody(
      streamed.stream,
      request.url,
      maxBodyBytes,
      remaining,
    );
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
  Future<void> timeoutAbort,
) {
  final existingAbort = switch (request) {
    http.Abortable(:final abortTrigger?) => abortTrigger,
    _ => null,
  };
  final abortTrigger = existingAbort == null
      ? timeoutAbort
      : Future.any<void>([existingAbort, timeoutAbort]);
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
      throw TimeoutException(
        appL10n.timedOutReadingResponseFrom((url).toString()),
        timeout,
      );
    },
  );
}

Duration _remaining(Duration timeout, Stopwatch elapsed) {
  final remaining = timeout - elapsed.elapsed;
  if (remaining <= Duration.zero) {
    throw TimeoutException(appL10n.timedOutBeforeTheResponseBody, timeout);
  }
  return remaining;
}

void _cancel(Stream<List<int>> stream) => stream.listen(null).cancel().ignore();
