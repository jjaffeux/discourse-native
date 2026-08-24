import 'dart:async';
import 'dart:io';

import 'package:discourse_native/src/data/bounded_http_overrides.dart';
import 'package:discourse_native/src/diagnostics/recording_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HTTP diagnostic privacy', () {
    test('sanitizes credentials, fragments, and query values', () {
      final sanitized = sanitizeHttpDiagnosticUri(
        Uri.parse(
          'https://alice:password@example.com/path?token=secret&empty=&tag=a&tag=b#private',
        ),
      ).toString();

      expect(sanitized, startsWith('https://example.com/path?'));
      expect(sanitized, contains('token'));
      expect(sanitized, contains('empty'));
      expect('tag'.allMatches(sanitized), hasLength(2));
      expect(sanitized, isNot(contains('alice')));
      expect(sanitized, isNot(contains('password')));
      expect(sanitized, isNot(contains('secret')));
      expect(sanitized, isNot(contains('private')));
      expect(sanitized, isNot(contains('=a')));
      expect(sanitized, isNot(contains('=b')));
    });

    test('redacts URL values, credentials, tokens, and home paths', () {
      final home = Platform.environment['HOME'];
      final redacted = redactHttpDiagnosticText(
        'GET https://user:pass@example.com/data?token=secret&count=4#part '
        'redirect ftp://alice:ftp-secret@example.com/archive?token=ftp-value '
        'authorization: Basic basic-secret\n'
        'cookie: first=cookie-secret; second=another-secret\n'
        'Bearer standalone-secret api_key=key-secret '
        '${home ?? '/home/person'}/source/app.dart',
      );

      expect(redacted, contains('https://example.com/data?token&count'));
      expect(redacted, contains('ftp://example.com/archive?token'));
      expect(redacted, isNot(contains('user')));
      expect(redacted, isNot(contains('pass')));
      expect(redacted, isNot(contains('secret')));
      expect(redacted, isNot(contains('ftp-value')));
      if (home != null && home.isNotEmpty) {
        expect(redacted, isNot(contains(home)));
        expect(redacted, contains('<home>'));
      }
    });
  });

  group('RecordingHttpClient', () {
    test('records a successful request without retaining secrets', () async {
      final recorder = _Recorder(operationId: 'load-topic-42');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.created
          ..headers.set('x-request-id', 'request-123')
          ..headers.set('rate-limit', '20')
          ..headers.set('x-discourse-route', 'topic.show')
          ..headers.set('cf-ray', 'not-in-the-retention-policy')
          ..headers.set('x-correlation-id', 'also-not-retained')
          ..headers.set('x-private-header', 'response-secret')
          ..headers.set(HttpHeaders.setCookieHeader, 'session=cookie-secret')
          ..add(<int>[9, 8, 7, 6]);
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = RecordingHttpClient(HttpClient(), recorder);
      addTearDown(client.close);

      final request = await client.postUrl(
        Uri.parse(
          'http://${server.address.host}:${server.port}/topic/42?api_key=request-secret&page=3#private',
        ),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer auth-secret',
      );
      request
        ..add(<int>[1, 2, 3])
        ..write('xy');
      await request.addStream(Stream<List<int>>.value(<int>[4, 5]));
      final response = await request.close();
      final body = await response.expand((chunk) => chunk).toList();

      expect(body, <int>[9, 8, 7, 6]);
      expect(
        recorder.updates.map((update) => update.phase),
        <HttpDiagnosticPhase>[
          HttpDiagnosticPhase.started,
          HttpDiagnosticPhase.responseHeaders,
          HttpDiagnosticPhase.completed,
        ],
      );
      final terminal = recorder.updates.last;
      expect(terminal.eventId, recorder.updates.first.eventId);
      expect(terminal.operationId, 'load-topic-42');
      expect(terminal.method, 'POST');
      expect(terminal.statusCode, HttpStatus.created);
      expect(terminal.sentBytes, 7);
      expect(terminal.receivedBytes, 4);
      expect(terminal.headerDuration, isNotNull);
      expect(terminal.totalDuration, isNotNull);
      expect(terminal.responseHeaders['x-request-id'], 'request-123');
      expect(terminal.responseHeaders['rate-limit'], '20');
      expect(terminal.responseHeaders['x-discourse-route'], 'topic.show');
      expect(terminal.responseHeaders, contains(HttpHeaders.contentTypeHeader));
      expect(terminal.responseHeaders, isNot(contains('cf-ray')));
      expect(terminal.responseHeaders, isNot(contains('x-correlation-id')));
      expect(terminal.responseHeaders, isNot(contains('x-private-header')));
      expect(terminal.responseHeaders, isNot(contains('set-cookie')));
      expect(terminal.uri.query, 'api_key&page');
      final retained = recorder.updates.join('\n');
      expect(retained, isNot(contains('request-secret')));
      expect(retained, isNot(contains('auth-secret')));
      expect(retained, isNot(contains('response-secret')));
      expect(retained, isNot(contains('cookie-secret')));
      expect(retained, isNot(contains('#private')));
    });

    test('marks HTTP error statuses while preserving the response', () async {
      final recorder = _Recorder();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response
          ..statusCode = HttpStatus.serviceUnavailable
          ..write('temporarily unavailable');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = RecordingHttpClient(HttpClient(), recorder);
      addTearDown(client.close);

      final request = await client.getUrl(
        Uri.http('${server.address.host}:${server.port}', '/failure'),
      );
      final response = await request.close();
      await response.drain<void>();

      expect(response.statusCode, HttpStatus.serviceUnavailable);
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.completed);
      expect(recorder.updates.last.isError, isTrue);
    });

    test('records loopback connection refusal as terminal failed', () async {
      final portProbe = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final unusedPort = portProbe.port;
      await portProbe.close();
      final recorder = _Recorder();
      final client = RecordingHttpClient(HttpClient(), recorder);
      addTearDown(client.close);

      await expectLater(() async {
        final request = await client.getUrl(
          Uri.http('127.0.0.1:$unusedPort', '/refused'),
        );
        await request.close();
      }, throwsA(isA<SocketException>()));

      expect(recorder.updates.first.phase, HttpDiagnosticPhase.started);
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.failed);
      expect(recorder.updates.last.errorType, 'SocketException');
      expect(recorder.updates.last.totalDuration, isNotNull);
      expect(
        recorder.updates.where(
          (update) =>
              update.phase == HttpDiagnosticPhase.failed ||
              update.phase == HttpDiagnosticPhase.cancelled ||
              update.phase == HttpDiagnosticPhase.completed,
        ),
        hasLength(1),
      );
    });

    test('keeps a long-running response pending until its body ends', () async {
      final finishResponse = Completer<void>();
      addTearDown(() {
        if (!finishResponse.isCompleted) finishResponse.complete();
      });
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final subscription = server.listen((request) async {
        await request.drain<void>();
        request.response.write('partial');
        await request.response.flush();
        await finishResponse.future;
        request.response.write('-complete');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final recorder = _Recorder();
      final client = RecordingHttpClient(HttpClient(), recorder);
      addTearDown(client.close);

      final request = await client.getUrl(
        Uri.http('${server.address.host}:${server.port}', '/slow'),
      );
      final response = await request.close();

      expect(recorder.updates.map((update) => update.phase), [
        HttpDiagnosticPhase.started,
        HttpDiagnosticPhase.responseHeaders,
      ]);
      expect(recorder.updates.last.totalDuration, isNull);

      final body = response.transform(systemEncoding.decoder).join();
      await Future<void>.delayed(Duration.zero);
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.responseHeaders);

      finishResponse.complete();
      expect(await body, 'partial-complete');
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.completed);
      expect(recorder.updates.last.totalDuration, isNotNull);
    });

    test('records sanitized automatic redirect history', () async {
      final recorder = _Recorder();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final destination = Uri.parse(
        'http://${server.address.host}:${server.port}/destination?ticket=redirect-secret',
      );
      final subscription = server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/start') {
          await request.response.redirect(destination);
          return;
        }
        request.response.write('done');
        await request.response.close();
      });
      addTearDown(subscription.cancel);
      final client = RecordingHttpClient(HttpClient(), recorder);
      addTearDown(client.close);

      final request = await client.getUrl(
        Uri.parse('http://${server.address.host}:${server.port}/start'),
      );
      await (await request.close()).drain<void>();

      final terminal = recorder.updates.last;
      expect(terminal.redirects, hasLength(1));
      expect(terminal.redirects.single.statusCode, HttpStatus.found);
      expect(terminal.redirects.single.method, 'GET');
      expect(terminal.redirects.single.location.query, 'ticket');
      expect(
        terminal.redirects.single.location.toString(),
        isNot(contains('redirect-secret')),
      );
    });

    test('records request-open failures with the original stack', () async {
      final recorder = _Recorder();
      final client = RecordingHttpClient(
        _FakeHttpClient(
          onGetUrl: (_) => Future<HttpClientRequest>.error(
            StateError('failed https://example.com/path?token=raw-secret'),
            StackTrace.fromString(
              '${Platform.environment['HOME']}/source/client.dart:1',
            ),
          ),
        ),
        recorder,
      );

      await expectLater(
        client.getUrl(
          Uri.parse('https://example.com/path?token=request-secret'),
        ),
        throwsStateError,
      );

      final failure = recorder.updates.last;
      expect(failure.phase, HttpDiagnosticPhase.failed);
      expect(failure.errorType, 'StateError');
      expect(failure.errorMessage, contains('https://example.com/path?token'));
      expect(failure.errorMessage, isNot(contains('raw-secret')));
      expect(failure.stackTrace, contains('<home>'));
    });

    test('legacy open drops secrets from a malformed path fallback', () async {
      const path =
          'http://alice:user-info-secret@[::1/private'
          '?token=query-value-secret#fragment-value-secret';
      final recorder = _Recorder();
      final client = RecordingHttpClient(
        _FakeHttpClient(
          onOpen: (_, _, _, _) => Future<HttpClientRequest>.error(
            StateError('delegate rejected malformed path'),
          ),
        ),
        recorder,
      );

      await expectLater(
        client.open('GET', 'example.com', 80, path),
        throwsStateError,
      );

      final retained = recorder.updates.join('\n');
      expect(recorder.updates.first.uri.userInfo, isEmpty);
      expect(recorder.updates.first.uri.query, isEmpty);
      expect(recorder.updates.first.uri.fragment, isEmpty);
      expect(retained, isNot(contains('user-info-secret')));
      expect(retained, isNot(contains('-secret@')));
      expect(retained, isNot(contains('query-value-secret')));
      expect(retained, isNot(contains('fragment-value-secret')));
    });

    test(
      'legacy open collapses malformed absolute user-info with slash before @',
      () async {
        const secret = 'SLASH_BEFORE_AT_CREDENTIAL_SENTINEL';
        const path =
            'http://alice:$secret/broken@authority.example/[::1/private'
            '?token=query-value-secret#fragment-value-secret';
        final recorder = _Recorder();
        final client = RecordingHttpClient(
          _FakeHttpClient(
            onOpen: (_, _, _, _) => Future<HttpClientRequest>.error(
              StateError('delegate rejected malformed path'),
            ),
          ),
          recorder,
        );

        await expectLater(
          client.open('GET', 'example.com', 80, path),
          throwsStateError,
        );

        final retained = recorder.updates.join('\n');
        expect(
          recorder.updates.first.uri.host,
          'redacted-malformed-uri.invalid',
        );
        expect(retained, isNot(contains(secret)));
        expect(retained, isNot(contains('query-value-secret')));
        expect(retained, isNot(contains('fragment-value-secret')));
      },
    );

    test('records response stream errors and delivered byte count', () async {
      final recorder = _Recorder();
      final response = _FakeResponse(
        Stream<List<int>>.multi((controller) {
          controller
            ..add(<int>[1, 2, 3])
            ..addError(StateError('body failed'));
          unawaited(controller.close());
        }),
      );
      final client = RecordingHttpClient(
        _FakeHttpClient(
          onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
        ),
        recorder,
      );

      final request = await client.getUrl(Uri.https('example.com', '/stream'));
      final streamed = await request.close();
      await expectLater(streamed.drain<void>(), throwsStateError);

      final failure = recorder.updates.last;
      expect(failure.phase, HttpDiagnosticPhase.failed);
      expect(failure.receivedBytes, 3);
      expect(failure.errorMessage, contains('body failed'));
    });

    test(
      'a hostile response stack cannot replace the transport error',
      () async {
        final recorder = _Recorder();
        final original = StateError('original response failure');
        final response = _FakeResponse(
          Stream<List<int>>.error(original, _HostileStackTrace()),
        );
        final client = RecordingHttpClient(
          _FakeHttpClient(
            onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
          ),
          recorder,
        );

        final request = await client.getUrl(
          Uri.https('example.com', '/stream'),
        );
        await expectLater(
          (await request.close()).drain<void>(),
          throwsA(same(original)),
        );

        expect(recorder.updates.last.phase, HttpDiagnosticPhase.failed);
        expect(
          recorder.updates.last.errorMessage,
          contains('original response'),
        );
        expect(
          recorder.updates.last.stackTrace,
          contains('<error while formatting exception>'),
        );
      },
    );

    test(
      'a hostile request stack cannot disrupt addError delegation',
      () async {
        final delegate = _FakeHttpClientRequest(
          Uri.https('example.com', '/upload'),
          _FakeResponse(const Stream<List<int>>.empty()),
        );
        final recorder = _Recorder();
        final client = RecordingHttpClient(
          _FakeHttpClient(onGetUrl: (_) async => delegate),
          recorder,
        );
        final request = await client.getUrl(
          Uri.https('example.com', '/upload'),
        );
        final original = StateError('original request failure');
        final hostileStack = _HostileStackTrace();

        expect(() => request.addError(original, hostileStack), returnsNormally);

        expect(delegate.addedError, same(original));
        expect(delegate.addedStackTrace, same(hostileStack));
        expect(recorder.updates.last.phase, HttpDiagnosticPhase.failed);
        expect(
          recorder.updates.last.errorMessage,
          contains('original request'),
        );
        expect(
          recorder.updates.last.stackTrace,
          contains('<error while formatting exception>'),
        );
        await request.close();
        await delegate.close();
      },
    );

    test(
      'never retains a parser exception source from a body stream',
      () async {
        const secretBody = '{"api_key":"response-body-secret"}';
        final recorder = _Recorder();
        final response = _FakeResponse(
          Stream<List<int>>.error(
            const FormatException('invalid response JSON', secretBody, 1),
          ),
        );
        final client = RecordingHttpClient(
          _FakeHttpClient(
            onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
          ),
          recorder,
        );

        final request = await client.getUrl(
          Uri.https('example.com', '/stream'),
        );
        await expectLater(
          (await request.close()).drain<void>(),
          throwsFormatException,
        );

        expect(
          recorder.updates.last.errorMessage,
          contains('invalid response JSON'),
        );
        expect(recorder.updates.join('\n'), isNot(contains(secretBody)));
        expect(
          recorder.updates.join('\n'),
          isNot(contains('response-body-secret')),
        );
      },
    );

    test('records explicit response cancellation as neutral', () async {
      final recorder = _Recorder();
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      final client = RecordingHttpClient(
        _FakeHttpClient(
          onGetUrl: (uri) async =>
              _FakeHttpClientRequest(uri, _FakeResponse(body.stream)),
        ),
        recorder,
      );
      final request = await client.getUrl(Uri.https('example.com', '/stream'));
      final response = await request.close();
      final firstChunk = Completer<void>();
      final subscription = response.listen((_) => firstChunk.complete());
      body.add(<int>[1, 2]);
      await firstChunk.future;

      await subscription.cancel();

      expect(recorder.updates.last.phase, HttpDiagnosticPhase.cancelled);
      expect(recorder.updates.last.isError, isFalse);
      expect(recorder.updates.last.receivedBytes, 2);
    });

    test(
      'records explicit request abort as neutral and delegates it',
      () async {
        // The test intentionally terminates this request through abort().
        // ignore: close_sinks
        final delegateRequest = _FakeHttpClientRequest(
          Uri.https('example.com', '/abort'),
          _FakeResponse(const Stream<List<int>>.empty()),
        );
        final recorder = _Recorder();
        final client = RecordingHttpClient(
          _FakeHttpClient(onGetUrl: (_) async => delegateRequest),
          recorder,
        );
        // The test intentionally terminates this request through abort().
        // ignore: close_sinks
        final request = await client.getUrl(Uri.https('example.com', '/abort'));
        final cancellation = StateError('caller cancelled');
        final cancellationStack = StackTrace.fromString('caller abort stack');

        request.abort(cancellation, cancellationStack);

        expect(delegateRequest.aborts, 1);
        expect(delegateRequest.abortException, same(cancellation));
        expect(delegateRequest.abortStackTrace, same(cancellationStack));
        expect(recorder.updates.last.phase, HttpDiagnosticPhase.cancelled);
        expect(recorder.updates.last.isError, isFalse);
        expect(recorder.updates.last.errorMessage, isNull);
      },
    );

    test('coalesces overlapping request closes at the delegate', () async {
      // Closed through the recording request below.
      // ignore: close_sinks
      final delegateRequest = _FakeHttpClientRequest(
        Uri.https('example.com', '/close-once'),
        _FakeResponse(Stream<List<int>>.value(<int>[1])),
      );
      final recorder = _Recorder();
      final client = RecordingHttpClient(
        _FakeHttpClient(onGetUrl: (_) async => delegateRequest),
        recorder,
      );
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.https('example.com', '/close-once'),
      );

      final first = request.close();
      final overlapping = request.close();

      expect(overlapping, same(first));
      expect(delegateRequest.closes, 1);
      await (await first).drain<void>();
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.completed);
    });

    test('non-forced close delegates without cancelling active work', () async {
      // The test intentionally terminates this request through abort().
      // ignore: close_sinks
      final delegateRequest = _FakeHttpClientRequest(
        Uri.https('example.com', '/pending'),
        _FakeResponse(const Stream<List<int>>.empty()),
      );
      final delegateClient = _FakeHttpClient(
        onGetUrl: (_) async => delegateRequest,
      );
      final recorder = _Recorder();
      final client = RecordingHttpClient(delegateClient, recorder);
      // The test intentionally terminates this request through abort().
      // ignore: close_sinks
      final request = await client.getUrl(Uri.https('example.com', '/pending'));

      client.close(force: false);

      expect(delegateClient.closes, 1);
      expect(delegateClient.lastForceClose, isFalse);
      expect(recorder.updates, hasLength(1));
      expect(recorder.updates.single.phase, HttpDiagnosticPhase.started);

      request.abort();
      expect(recorder.updates.last.phase, HttpDiagnosticPhase.cancelled);
    });

    test('a throwing recorder cannot change request behavior', () async {
      final response = _FakeResponse(Stream<List<int>>.value(<int>[1]));
      final client = RecordingHttpClient(
        _FakeHttpClient(
          onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
        ),
        _ThrowingRecorder(),
      );

      final request = await client.getUrl(Uri.https('example.com', '/ok'));
      final result = await (await request.close()).single;

      expect(result, <int>[1]);
    });
  });

  group('RecordingHttpOverrides', () {
    test('preserves the previous client and proxy override', () {
      final previous = _FakeOverrides();
      final recording = RecordingHttpOverrides(_Recorder(), previous: previous);

      final client = recording.createHttpClient(null);
      client.close(force: true);

      expect(previous.clientsCreated, 1);
      expect(previous.client.closes, 1);
      expect(previous.client.lastForceClose, isTrue);
      expect(
        recording.findProxyFromEnvironment(
          Uri.https('example.com', '/'),
          const <String, String>{'https_proxy': 'proxy.example:8080'},
        ),
        'PROXY delegated.example:1234',
      );
    });

    test('replacement skips the prior recorder and retains its base', () async {
      final response = _FakeResponse(Stream<List<int>>.value(<int>[1, 2, 3]));
      final base = _FakeOverrides(
        client: _FakeHttpClient(
          onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
        ),
      );
      final priorRecorder = _Recorder();
      final replacementRecorder = _Recorder();
      final prior = RecordingHttpOverrides(priorRecorder, previous: base);
      final replacement = RecordingHttpOverrides(
        replacementRecorder,
        previous: prior,
      );

      expect(replacement.previous, same(base));
      final client = replacement.createHttpClient(null);
      addTearDown(client.close);
      final request = await client.getUrl(
        Uri.https('example.com', '/replacement'),
      );
      await (await request.close()).drain<void>();

      expect(base.clientsCreated, 1);
      expect(priorRecorder.updates, isEmpty);
      expect(
        replacementRecorder.updates.map((update) => update.phase),
        <HttpDiagnosticPhase>[
          HttpDiagnosticPhase.started,
          HttpDiagnosticPhase.responseHeaders,
          HttpDiagnosticPhase.completed,
        ],
      );
    });

    test(
      'production wrapper order replaces the complete prior app stack',
      () async {
        final response = _FakeResponse(Stream<List<int>>.value(<int>[1]));
        final baseClient = _FakeHttpClient(
          onGetUrl: (uri) async => _FakeHttpClientRequest(uri, response),
        );
        final base = _FakeOverrides(client: baseClient);
        final priorRecorder = _Recorder();
        final replacementRecorder = _Recorder();

        // AppBootstrap installs the bounded layer first and recording second.
        // Repeating that order must not leave Recording1 below Bounded2.
        final priorBounded = BoundedHttpOverrides(previous: base);
        final priorRecording = RecordingHttpOverrides(
          priorRecorder,
          previous: priorBounded,
        );
        final replacementBounded = BoundedHttpOverrides(
          previous: priorRecording,
        );
        final replacementRecording = RecordingHttpOverrides(
          replacementRecorder,
          previous: replacementBounded,
        );

        expect(replacementBounded.previous, same(base));
        final client = replacementRecording.createHttpClient(null);
        addTearDown(client.close);
        final request = await client.getUrl(
          Uri.https('example.com', '/repeated-bootstrap'),
        );
        await (await request.close()).drain<void>();

        expect(base.clientsCreated, 1);
        expect(baseClient.maxConnectionsPerHost, 4);
        expect(priorRecorder.updates, isEmpty);
        expect(
          replacementRecorder.updates.map((update) => update.phase),
          <HttpDiagnosticPhase>[
            HttpDiagnosticPhase.started,
            HttpDiagnosticPhase.responseHeaders,
            HttpDiagnosticPhase.completed,
          ],
        );
      },
    );
  });
}

final class _Recorder implements HttpDiagnosticsRecorder {
  _Recorder({this.operationId});

  final String? operationId;
  final List<HttpDiagnosticRecord> updates = <HttpDiagnosticRecord>[];

  @override
  String? get currentOperationId => operationId;

  @override
  void recordHttp(HttpDiagnosticRecord update) => updates.add(update);
}

final class _ThrowingRecorder implements HttpDiagnosticsRecorder {
  @override
  String? get currentOperationId => throw StateError('recorder unavailable');

  @override
  void recordHttp(HttpDiagnosticRecord update) {
    throw StateError('recorder unavailable');
  }
}

final class _FakeOverrides extends HttpOverrides {
  _FakeOverrides({_FakeHttpClient? client})
    : client = client ?? _FakeHttpClient();

  final _FakeHttpClient client;
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated += 1;
    return client;
  }

  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) =>
      'PROXY delegated.example:1234';
}

final class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.onGetUrl, this.onOpen});

  final Future<HttpClientRequest> Function(Uri uri)? onGetUrl;
  final Future<HttpClientRequest> Function(
    String method,
    String host,
    int port,
    String path,
  )?
  onOpen;
  int closes = 0;
  bool? lastForceClose;

  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> getUrl(Uri url) {
    final callback = onGetUrl;
    if (callback == null) {
      throw StateError('No getUrl callback configured');
    }
    return callback(url);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) {
    final callback = onOpen;
    if (callback == null) {
      throw StateError('No open callback configured');
    }
    return callback(method, host, port, path);
  }

  @override
  void close({bool force = false}) {
    closes += 1;
    lastForceClose = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, HttpClientResponse response)
    : _response = Future<HttpClientResponse>.value(response);

  final Future<HttpClientResponse> _response;
  int closes = 0;
  int aborts = 0;
  Object? abortException;
  StackTrace? abortStackTrace;
  Object? addedError;
  StackTrace? addedStackTrace;

  @override
  final Uri uri;

  @override
  String get method => 'GET';

  @override
  Future<HttpClientResponse> get done => _response;

  @override
  Future<HttpClientResponse> close() {
    closes += 1;
    return _response;
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) {
    aborts += 1;
    abortException = exception;
    abortStackTrace = stackTrace;
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    addedError = error;
    addedStackTrace = stackTrace;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _HostileStackTrace implements StackTrace {
  @override
  String toString() => throw StateError('stack formatting failed');
}

final class _FakeResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeResponse(this._stream);

  final Stream<List<int>> _stream;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  String get reasonPhrase => 'OK';

  @override
  List<RedirectInfo> get redirects => const <RedirectInfo>[];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> data)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
