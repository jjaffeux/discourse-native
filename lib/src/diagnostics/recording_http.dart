import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'diagnostics_redactor.dart';

/// The lifecycle states emitted for one HTTP transaction.
enum HttpDiagnosticPhase {
  started,
  responseHeaders,
  completed,
  failed,
  cancelled,
}

/// Redirect metadata that is safe to retain in diagnostics.
final class HttpDiagnosticRedirect {
  const HttpDiagnosticRedirect({
    required this.statusCode,
    required this.method,
    required this.location,
  });

  final int statusCode;
  final String method;
  final Uri location;
}

/// An immutable update for a single HTTP transaction.
///
/// Updates with the same [eventId] describe the same transaction. URIs and
/// error text are sanitized before this object is constructed, request header
/// values and bodies are never inspected, and [responseHeaders] contains only
/// explicitly allowlisted metadata.
final class HttpDiagnosticRecord {
  const HttpDiagnosticRecord({
    required this.eventId,
    required this.phase,
    required this.timestamp,
    required this.method,
    required this.uri,
    required this.sentBytes,
    required this.receivedBytes,
    this.operationId,
    this.statusCode,
    this.reasonPhrase,
    this.redirects = const <HttpDiagnosticRedirect>[],
    this.responseHeaders = const <String, String>{},
    this.headerDuration,
    this.totalDuration,
    this.errorType,
    this.errorMessage,
    this.stackTrace,
  });

  final String eventId;
  final HttpDiagnosticPhase phase;
  final DateTime timestamp;
  final String method;
  final Uri uri;
  final String? operationId;
  final int? statusCode;
  final String? reasonPhrase;
  final List<HttpDiagnosticRedirect> redirects;
  final Map<String, String> responseHeaders;
  final Duration? headerDuration;
  final Duration? totalDuration;
  final int sentBytes;
  final int receivedBytes;
  final String? errorType;
  final String? errorMessage;
  final String? stackTrace;

  bool get isError =>
      phase == HttpDiagnosticPhase.failed ||
      (statusCode != null && statusCode! >= HttpStatus.badRequest);

  @override
  String toString() {
    return 'HttpDiagnosticRecord($phase, $method $uri, status: $statusCode, '
        'sent: $sentBytes, received: $receivedBytes, error: $errorMessage)';
  }
}

/// Narrow adapter implemented by the app-owned diagnostics controller.
///
/// Implementations should be nonthrowing. The recording HTTP layer also
/// guards every call so a faulty diagnostics backend can never affect a
/// request.
abstract interface class HttpDiagnosticsRecorder {
  String? get currentOperationId;

  void recordHttp(HttpDiagnosticRecord update);
}

/// A process-wide [HttpOverrides] that records clients created through
/// `HttpClient()` while preserving an override that was already installed.
final class RecordingHttpOverrides extends HttpOverrides {
  RecordingHttpOverrides(
    this.recorder, {
    HttpOverrides? previous,
    DateTime Function()? clock,
  }) : previous = _withoutRecordingOverride(previous ?? HttpOverrides.current),
       _clock = clock ?? _utcNow;

  final HttpDiagnosticsRecorder recorder;

  final HttpOverrides? previous;
  final DateTime Function() _clock;

  /// Installs this override globally and returns it for later inspection.
  ///
  /// This should be called from the root zone before any HTTP clients are
  /// created. The currently active non-recording override is retained and
  /// delegated to; an older recording layer is replaced so one request cannot
  /// be emitted to both the old and replacement recorders.
  static RecordingHttpOverrides install(
    HttpDiagnosticsRecorder recorder, {
    DateTime Function()? clock,
  }) {
    final override = RecordingHttpOverrides(
      recorder,
      previous: HttpOverrides.current,
      clock: clock,
    );
    HttpOverrides.global = override;
    return override;
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client =
        previous?.createHttpClient(context) ?? super.createHttpClient(context);
    return RecordingHttpClient(client, recorder, clock: _clock);
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
    return previous?.findProxyFromEnvironment(url, environment) ??
        super.findProxyFromEnvironment(url, environment);
  }
}

/// A fully delegating [HttpClient] that wraps every opened request.
final class RecordingHttpClient implements HttpClient {
  RecordingHttpClient(
    this._delegate,
    this._recorder, {
    DateTime Function()? clock,
  }) : _clock = clock ?? _utcNow;

  final HttpClient _delegate;
  final HttpDiagnosticsRecorder _recorder;
  final DateTime Function() _clock;
  final Set<_HttpTransaction> _active = <_HttpTransaction>{};

  _HttpTransaction _start(String method, Uri uri) {
    late final _HttpTransaction transaction;
    transaction = _HttpTransaction(
      recorder: _recorder,
      method: method,
      uri: sanitizeHttpDiagnosticUri(uri),
      clock: _clock,
      onTerminal: () => _active.remove(transaction),
    );
    _active.add(transaction);
    return transaction;
  }

  Future<HttpClientRequest> _open(
    String method,
    Uri diagnosticUri,
    Future<HttpClientRequest> Function() delegate,
  ) async {
    final transaction = _start(method, diagnosticUri);
    try {
      // The returned wrapper owns and exposes this sink to the caller.
      // ignore: close_sinks
      final request = await delegate();
      return _RecordingHttpClientRequest(request, transaction);
    } on Object catch (error, stackTrace) {
      transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    return _open(
      method,
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.open(method, host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    return _open(method, url, () => _delegate.openUrl(method, url));
  }

  @override
  Future<HttpClientRequest> get(String host, int port, String path) {
    return _open(
      'GET',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.get(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    return _open('GET', url, () => _delegate.getUrl(url));
  }

  @override
  Future<HttpClientRequest> post(String host, int port, String path) {
    return _open(
      'POST',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.post(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> postUrl(Uri url) {
    return _open('POST', url, () => _delegate.postUrl(url));
  }

  @override
  Future<HttpClientRequest> put(String host, int port, String path) {
    return _open(
      'PUT',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.put(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> putUrl(Uri url) {
    return _open('PUT', url, () => _delegate.putUrl(url));
  }

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) {
    return _open(
      'DELETE',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.delete(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) {
    return _open('DELETE', url, () => _delegate.deleteUrl(url));
  }

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) {
    return _open(
      'PATCH',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.patch(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> patchUrl(Uri url) {
    return _open('PATCH', url, () => _delegate.patchUrl(url));
  }

  @override
  Future<HttpClientRequest> head(String host, int port, String path) {
    return _open(
      'HEAD',
      _diagnosticUriFromParts(host, port, path),
      () => _delegate.head(host, port, path),
    );
  }

  @override
  Future<HttpClientRequest> headUrl(Uri url) {
    return _open('HEAD', url, () => _delegate.headUrl(url));
  }

  @override
  Duration get idleTimeout => _delegate.idleTimeout;

  @override
  set idleTimeout(Duration value) => _delegate.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _delegate.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _delegate.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _delegate.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) =>
      _delegate.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _delegate.autoUncompress;

  @override
  set autoUncompress(bool value) => _delegate.autoUncompress = value;

  @override
  String? get userAgent => _delegate.userAgent;

  @override
  set userAgent(String? value) => _delegate.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? value,
  ) => _delegate.authenticate = value;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _delegate.addCredentials(url, realm, credentials);

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    value,
  ) => _delegate.connectionFactory = value;

  @override
  set findProxy(String Function(Uri url)? value) => _delegate.findProxy = value;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    value,
  ) => _delegate.authenticateProxy = value;

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _delegate.addProxyCredentials(host, port, realm, credentials);

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? value,
  ) => _delegate.badCertificateCallback = value;

  @override
  set keyLog(void Function(String line)? value) => _delegate.keyLog = value;

  @override
  void close({bool force = false}) {
    if (force) {
      for (final transaction in _active.toList(growable: false)) {
        transaction.cancel();
      }
    }
    _delegate.close(force: force);
  }
}

/// A fully delegating request that counts body bytes without retaining them.
final class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest(this._delegate, this._transaction);

  final HttpClientRequest _delegate;
  final _HttpTransaction _transaction;
  Future<HttpClientResponse>? _trackedDone;
  bool _closeStarted = false;

  Future<HttpClientResponse> _track(Future<HttpClientResponse> response) async {
    try {
      final value = await response;
      _transaction.responseHeaders(value);
      return _RecordingHttpClientResponse(value, _transaction);
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  bool get persistentConnection => _delegate.persistentConnection;

  @override
  set persistentConnection(bool value) =>
      _delegate.persistentConnection = value;

  @override
  bool get followRedirects => _delegate.followRedirects;

  @override
  set followRedirects(bool value) => _delegate.followRedirects = value;

  @override
  int get maxRedirects => _delegate.maxRedirects;

  @override
  set maxRedirects(int value) => _delegate.maxRedirects = value;

  @override
  String get method => _delegate.method;

  @override
  Uri get uri => _delegate.uri;

  @override
  int get contentLength => _delegate.contentLength;

  @override
  set contentLength(int value) => _delegate.contentLength = value;

  @override
  bool get bufferOutput => _delegate.bufferOutput;

  @override
  set bufferOutput(bool value) => _delegate.bufferOutput = value;

  @override
  HttpHeaders get headers => _delegate.headers;

  @override
  List<Cookie> get cookies => _delegate.cookies;

  @override
  Future<HttpClientResponse> get done =>
      _trackedDone ??= _track(_delegate.done);

  @override
  Future<HttpClientResponse> close() {
    if (_closeStarted) return done;
    _closeStarted = true;
    try {
      final response = _delegate.close();
      return _trackedDone ??= _track(response);
    } on Object catch (error, stackTrace) {
      _closeStarted = false;
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  HttpConnectionInfo? get connectionInfo => _delegate.connectionInfo;

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    _transaction.cancel();
    _delegate.abort(exception, stackTrace);
  }

  @override
  Encoding get encoding => _delegate.encoding;

  @override
  set encoding(Encoding value) => _delegate.encoding = value;

  @override
  void add(List<int> data) {
    try {
      _delegate.add(data);
      _transaction.addSentBytes(data.length);
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  void write(Object? object) {
    try {
      final text = object?.toString() ?? 'null';
      _delegate.write(text);
      _transaction.addSentBytes(_encodedLength(text));
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  void writeAll(Iterable<Object?> objects, [String separator = '']) {
    var first = true;
    for (final object in objects) {
      if (!first) write(separator);
      first = false;
      write(object);
    }
  }

  @override
  void writeln([Object? object = '']) {
    write(object);
    write('\n');
  }

  @override
  void writeCharCode(int charCode) {
    try {
      final text = String.fromCharCode(charCode);
      _delegate.writeCharCode(charCode);
      _transaction.addSentBytes(_encodedLength(text));
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  int _encodedLength(String value) {
    try {
      return encoding.encode(value).length;
    } on Object {
      return 0;
    }
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    final resolvedStack = stackTrace ?? StackTrace.current;
    try {
      _delegate.addError(error, stackTrace);
      _transaction.fail(error, resolvedStack);
    } on Object catch (delegateError, delegateStack) {
      _transaction.fail(delegateError, delegateStack);
      rethrow;
    }
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    final counted = stream.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          _transaction.addSentBytes(data.length);
          sink.add(data);
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          _transaction.fail(error, stackTrace);
          sink.addError(error, stackTrace);
        },
      ),
    );
    try {
      await _delegate.addStream(counted);
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> flush() async {
    try {
      await _delegate.flush();
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }
}

/// A response stream that records delivered bytes and its terminal state.
final class _RecordingHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _RecordingHttpClientResponse(this._delegate, this._transaction);

  final HttpClientResponse _delegate;
  final _HttpTransaction _transaction;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final tracked = _delegate.transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          _transaction.addReceivedBytes(data.length);
          sink.add(data);
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          _transaction.fail(error, stackTrace);
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          _transaction.complete();
          sink.close();
        },
      ),
    );
    // Ownership is transferred to the subscription wrapper returned below.
    // ignore: cancel_subscriptions
    final subscription = tracked.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    return _RecordingStreamSubscription(subscription, _transaction.cancel);
  }

  @override
  int get statusCode => _delegate.statusCode;

  @override
  String get reasonPhrase => _delegate.reasonPhrase;

  @override
  int get contentLength => _delegate.contentLength;

  @override
  HttpClientResponseCompressionState get compressionState =>
      _delegate.compressionState;

  @override
  bool get persistentConnection => _delegate.persistentConnection;

  @override
  bool get isRedirect => _delegate.isRedirect;

  @override
  List<RedirectInfo> get redirects => _delegate.redirects;

  @override
  Future<HttpClientResponse> redirect([
    String? method,
    Uri? url,
    bool? followLoops,
  ]) async {
    try {
      final response = await _delegate.redirect(method, url, followLoops);
      _transaction.responseHeaders(response);
      return _RecordingHttpClientResponse(response, _transaction);
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  HttpHeaders get headers => _delegate.headers;

  @override
  Future<Socket> detachSocket() async {
    try {
      final socket = await _delegate.detachSocket();
      _transaction.complete();
      return socket;
    } on Object catch (error, stackTrace) {
      _transaction.fail(error, stackTrace);
      rethrow;
    }
  }

  @override
  List<Cookie> get cookies => _delegate.cookies;

  @override
  X509Certificate? get certificate => _delegate.certificate;

  @override
  HttpConnectionInfo? get connectionInfo => _delegate.connectionInfo;
}

final class _RecordingStreamSubscription<T> implements StreamSubscription<T> {
  _RecordingStreamSubscription(this._delegate, this._onCancel);

  final StreamSubscription<T> _delegate;
  final void Function() _onCancel;
  bool _cancelled = false;

  @override
  Future<void> cancel() {
    if (!_cancelled) {
      _cancelled = true;
      _onCancel();
    }
    return _delegate.cancel();
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture<E>(futureValue);
}

final class _HttpTransaction {
  _HttpTransaction({
    required this.recorder,
    required this.method,
    required this.uri,
    required this.clock,
    required this.onTerminal,
  }) : eventId = _nextEventId(clock()),
       _stopwatch = Stopwatch()..start() {
    try {
      operationId = recorder.currentOperationId;
    } on Object {
      operationId = null;
    }
    _emit(HttpDiagnosticPhase.started);
  }

  final HttpDiagnosticsRecorder recorder;
  final String eventId;
  final String method;
  final Uri uri;
  final DateTime Function() clock;
  final void Function() onTerminal;
  final Stopwatch _stopwatch;
  late final String? operationId;

  int sentBytes = 0;
  int receivedBytes = 0;
  int? statusCode;
  String? reasonPhrase;
  List<HttpDiagnosticRedirect> redirects = const <HttpDiagnosticRedirect>[];
  Map<String, String> responseHeaderValues = const <String, String>{};
  Duration? headerDuration;
  bool _terminal = false;

  void addSentBytes(int count) {
    if (!_terminal) sentBytes += count;
  }

  void addReceivedBytes(int count) {
    if (!_terminal) receivedBytes += count;
  }

  void responseHeaders(HttpClientResponse response) {
    if (_terminal) return;
    headerDuration ??= _stopwatch.elapsed;
    try {
      statusCode = response.statusCode;
    } on Object {
      // Diagnostics must not influence access to the actual response.
    }
    try {
      reasonPhrase = redactHttpDiagnosticText(response.reasonPhrase);
    } on Object {
      // Diagnostics must not influence access to the actual response.
    }
    try {
      redirects = List<HttpDiagnosticRedirect>.unmodifiable(
        response.redirects.map(
          (redirect) => HttpDiagnosticRedirect(
            statusCode: redirect.statusCode,
            method: redirect.method,
            location: sanitizeHttpDiagnosticUri(redirect.location),
          ),
        ),
      );
    } on Object {
      redirects = const <HttpDiagnosticRedirect>[];
    }
    try {
      responseHeaderValues = _safeResponseHeaders(response.headers);
    } on Object {
      responseHeaderValues = const <String, String>{};
    }
    _emit(HttpDiagnosticPhase.responseHeaders);
  }

  void complete() {
    if (_terminal) return;
    _terminal = true;
    _stopwatch.stop();
    _emit(HttpDiagnosticPhase.completed, totalDuration: _stopwatch.elapsed);
    onTerminal();
  }

  void fail(Object error, StackTrace stackTrace) {
    if (_terminal) return;
    _terminal = true;
    _stopwatch.stop();
    _emit(
      HttpDiagnosticPhase.failed,
      totalDuration: _stopwatch.elapsed,
      errorType: _safeRuntimeType(error),
      errorMessage: redactHttpDiagnosticText(_safeErrorMessage(error)),
      stackTrace: redactHttpDiagnosticText(_safeToString(stackTrace)),
    );
    onTerminal();
  }

  void cancel() {
    if (_terminal) return;
    _terminal = true;
    _stopwatch.stop();
    _emit(HttpDiagnosticPhase.cancelled, totalDuration: _stopwatch.elapsed);
    onTerminal();
  }

  void _emit(
    HttpDiagnosticPhase phase, {
    Duration? totalDuration,
    String? errorType,
    String? errorMessage,
    String? stackTrace,
  }) {
    try {
      recorder.recordHttp(
        HttpDiagnosticRecord(
          eventId: eventId,
          phase: phase,
          timestamp: clock().toUtc(),
          method: method,
          uri: uri,
          operationId: operationId,
          statusCode: statusCode,
          reasonPhrase: reasonPhrase,
          redirects: redirects,
          responseHeaders: responseHeaderValues,
          headerDuration: headerDuration,
          totalDuration: totalDuration,
          sentBytes: sentBytes,
          receivedBytes: receivedBytes,
          errorType: errorType,
          errorMessage: errorMessage,
          stackTrace: stackTrace,
        ),
      );
    } on Object {
      // Recording is deliberately best-effort and must never break HTTP.
    }
  }
}

Map<String, String> _safeResponseHeaders(HttpHeaders headers) {
  final values = <String, String>{};
  headers.forEach((name, headerValues) {
    final normalized = name.toLowerCase();
    if (!DiagnosticsRedactor.allowedResponseHeaders.contains(normalized)) {
      return;
    }
    values[normalized] = DiagnosticsRedactor.scrub(headerValues.join(', '));
  });
  return Map<String, String>.unmodifiable(values);
}

/// Removes URI credentials, fragments, and every query value while retaining
/// query names (including duplicates) for useful request identification.
Uri sanitizeHttpDiagnosticUri(Uri uri) {
  try {
    return Uri.parse(DiagnosticsRedactor.uri(uri));
  } on Object {
    return Uri(path: uri.path);
  }
}

/// Redacts URL query values, common credential-shaped values, and the user's
/// home directory from diagnostic error text and stack traces.
String redactHttpDiagnosticText(String value) =>
    DiagnosticsRedactor.scrub(value);

Uri _diagnosticUriFromParts(String host, int port, String path) {
  try {
    final reference = Uri.parse(path);
    return Uri(
      scheme: 'http',
      host: host,
      port: port,
      path: reference.path,
      query: reference.hasQuery ? reference.query : null,
    );
  } on Object {
    return _fallbackDiagnosticUri(path);
  }
}

Uri _fallbackDiagnosticUri(String rawPath) {
  final malformedAbsolute = RegExp(
    r'^[ \t\r\n]*([a-z][a-z0-9+.-]*):\/\/',
    caseSensitive: false,
  ).firstMatch(rawPath);
  if (malformedAbsolute != null) {
    // Once parsing an absolute reference has failed, apparent authority/path
    // delimiters are not trustworthy. In particular, malformed user-info can
    // contain a slash before its terminating `@`; encoding the raw text as a
    // relative path would preserve that credential verbatim. Keep only the
    // scheme and an unmistakable safe placeholder.
    return Uri(
      scheme: malformedAbsolute.group(1)!.toLowerCase(),
      host: 'redacted-malformed-uri.invalid',
    );
  }

  var path = rawPath;
  final query = path.indexOf('?');
  final fragment = path.indexOf('#');
  final privateStart = switch ((query, fragment)) {
    (-1, -1) => -1,
    (-1, _) => fragment,
    (_, -1) => query,
    _ => query < fragment ? query : fragment,
  };
  if (privateStart >= 0) path = path.substring(0, privateStart);

  // A malformed absolute reference can still contain URI user-info even
  // though it could not be parsed. Remove the whole prefix through the last
  // `@` in its authority before turning the remainder into an encoded path.
  final authority = RegExp(
    r'^(?:[a-z][a-z0-9+.-]*:)?//([^/]*)',
    caseSensitive: false,
  ).firstMatch(path);
  final rawAuthority = authority?.group(1);
  final userInfoEnd = rawAuthority?.lastIndexOf('@') ?? -1;
  if (authority != null && userInfoEnd >= 0) {
    final completeAuthority = authority.group(0)!;
    final authorityStart =
        authority.start + completeAuthority.length - rawAuthority!.length;
    path = path.replaceRange(
      authorityStart,
      authorityStart + userInfoEnd + 1,
      '',
    );
  }

  try {
    return Uri(path: path);
  } on Object {
    return Uri(path: '/');
  }
}

String _safeRuntimeType(Object value) {
  try {
    return value.runtimeType.toString();
  } on Object {
    return 'Object';
  }
}

String _safeToString(Object value) {
  try {
    return value.toString();
  } on Object {
    return '<error while formatting exception>';
  }
}

String _safeErrorMessage(Object value) {
  if (value case FormatException(:final message, :final offset)) {
    return '$message${offset == null ? '' : ' at $offset'}';
  }
  return _safeToString(value);
}

HttpOverrides? _withoutRecordingOverride(HttpOverrides? override) {
  // App bootstrap replacement must keep connection limits and proxy behavior,
  // but retaining an earlier recording layer would duplicate every event and
  // keep its obsolete recorder alive for the process lifetime.
  while (override is RecordingHttpOverrides) {
    override = override.previous;
  }
  return override;
}

DateTime _utcNow() => DateTime.now().toUtc();

int _eventSequence = 0;

String _nextEventId(DateTime timestamp) {
  _eventSequence += 1;
  return 'http-${timestamp.toUtc().microsecondsSinceEpoch}-$_eventSequence';
}
