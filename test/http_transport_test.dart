import 'dart:async';

import 'package:discourse_native/src/data/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('requireSafeHttpUrl', () {
    test('accepts HTTPS', () {
      final url = Uri.parse('https://forum.example/path');

      expect(requireSafeHttpUrl(url), same(url));
    });

    test('accepts HTTP loopback forms', () {
      for (final value in [
        'http://localhost:4200',
        'http://dev.localhost:4200',
        'http://LOCALHOST.:4200',
        'http://127.0.0.1:4200',
        'http://127.255.255.254:4200',
        'http://[::1]:4200',
      ]) {
        final url = Uri.parse(value);
        expect(requireSafeHttpUrl(url), same(url), reason: value);
      }
    });

    test('rejects remote and malformed HTTP hosts', () {
      for (final value in [
        'http://forum.example',
        'http://192.168.1.2',
        'http://127.0.0.999',
        'http://127.0.0',
      ]) {
        expect(
          () => requireSafeHttpUrl(Uri.parse(value)),
          throwsA(isA<UnsafeHttpTransportException>()),
          reason: value,
        );
      }
    });

    test('rejects URLs without an authority and host', () {
      for (final value in [
        'https:relative/path',
        'https:///missing-host',
        'http:localhost/path',
      ]) {
        expect(
          () => requireSafeHttpUrl(Uri.parse(value)),
          throwsA(isA<UnsafeHttpTransportException>()),
          reason: value,
        );
      }
    });
  });

  group('resolveSafeHttpRedirect', () {
    test('resolves a relative location against its source', () {
      expect(
        resolveSafeHttpRedirect(
          Uri.parse('https://forum.example/old/path'),
          '../new/path',
        ),
        Uri.parse('https://forum.example/new/path'),
      );
    });

    test('rejects an HTTPS downgrade, including to loopback', () {
      expect(
        () => resolveSafeHttpRedirect(
          Uri.parse('https://forum.example/path'),
          'http://localhost:4200/path',
        ),
        throwsA(isA<UnsafeHttpTransportException>()),
      );
    });
  });

  group('SafeHttpClient', () {
    test('refuses automatic redirects at the request boundary', () async {
      late bool followRedirects;
      final client = SafeHttpClient.owned(
        _Client((request) async {
          followRedirects = request.followRedirects;
          return _response(request, statusCode: 302);
        }),
      );
      addTearDown(client.close);

      await client.send(http.Request('GET', Uri.https('forum.example', '/')));

      expect(followRedirects, isFalse);
    });

    test('rejects an unsafe request before delegation', () async {
      var delegated = false;
      final client = SafeHttpClient.owned(
        _Client((request) async {
          delegated = true;
          return _response(request);
        }),
      );
      addTearDown(client.close);

      expect(
        () => client.send(http.Request('GET', Uri.http('forum.example', '/'))),
        throwsA(isA<UnsafeHttpTransportException>()),
      );
      expect(delegated, isFalse);
    });

    test('closes owned clients but leaves borrowed clients open', () {
      var ownedCloses = 0;
      var borrowedCloses = 0;
      final owned = SafeHttpClient.owned(
        _Client(
          (request) async => _response(request),
          onClose: () => ownedCloses += 1,
        ),
      );
      final borrowed = SafeHttpClient.borrowed(
        _Client(
          (request) async => _response(request),
          onClose: () => borrowedCloses += 1,
        ),
      );

      owned.close();
      borrowed.close();

      expect(ownedCloses, 1);
      expect(borrowedCloses, 0);
    });
  });

  group('sendBoundedHttpRequest', () {
    test('preserves response metadata and body', () async {
      final request = http.Request('GET', Uri.https('forum.example', '/data'));
      final response = await sendBoundedHttpRequest(
        _Client(
          (request) async => http.StreamedResponse(
            Stream.value([1, 2, 3]),
            201,
            request: request,
            headers: {'content-type': 'application/octet-stream'},
            reasonPhrase: 'Created',
          ),
        ),
        request,
        timeout: const Duration(seconds: 1),
        maxBodyBytes: 10,
      );

      expect(response.bodyBytes, [1, 2, 3]);
      expect(response.statusCode, 201);
      expect(response.reasonPhrase, 'Created');
      expect(response.request, same(request));
    });

    test('rejects a declared oversized body before reading it', () async {
      var listened = false;
      var cancelled = false;
      final body = StreamController<List<int>>(
        onListen: () => listened = true,
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final request = http.Request('GET', Uri.https('forum.example', '/data'));

      await expectLater(
        sendBoundedHttpRequest(
          _Client(
            (request) async => http.StreamedResponse(
              body.stream,
              200,
              request: request,
              contentLength: 11,
            ),
          ),
          request,
          timeout: const Duration(seconds: 1),
          maxBodyBytes: 10,
        ),
        throwsA(isA<HttpResponseTooLargeException>()),
      );

      expect(listened, isTrue);
      expect(cancelled, isTrue);
    });

    test('cancels a body once received bytes exceed the limit', () async {
      var cancelled = false;
      late StreamController<List<int>> body;
      body = StreamController<List<int>>(
        onListen: () {
          body.add([1, 2, 3]);
          body.add([4, 5, 6]);
        },
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final request = http.Request('GET', Uri.https('forum.example', '/data'));

      await expectLater(
        sendBoundedHttpRequest(
          _Client(
            (request) async =>
                http.StreamedResponse(body.stream, 200, request: request),
          ),
          request,
          timeout: const Duration(seconds: 1),
          maxBodyBytes: 5,
        ),
        throwsA(isA<HttpResponseTooLargeException>()),
      );

      expect(cancelled, isTrue);
    });

    test('the deadline covers a body that never finishes', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final request = http.Request('GET', Uri.https('forum.example', '/data'));

      await expectLater(
        sendBoundedHttpRequest(
          _Client(
            (request) async =>
                http.StreamedResponse(body.stream, 200, request: request),
          ),
          request,
          timeout: const Duration(milliseconds: 100),
          maxBodyBytes: 10,
        ),
        throwsA(isA<TimeoutException>()),
      );

      expect(cancelled, isTrue);
    });

    test(
      'cancels a response whose headers arrive after the deadline',
      () async {
        var cancelled = false;
        final headers = Completer<http.StreamedResponse>();
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        addTearDown(body.close);
        final request = http.Request(
          'GET',
          Uri.https('forum.example', '/data'),
        );

        final result = sendBoundedHttpRequest(
          _Client((request) => headers.future),
          request,
          timeout: const Duration(milliseconds: 100),
          maxBodyBytes: 10,
        );
        await expectLater(result, throwsA(isA<TimeoutException>()));

        headers.complete(http.StreamedResponse(body.stream, 200));
        await Future<void>.delayed(Duration.zero);

        expect(cancelled, isTrue);
      },
    );
  });
}

final class _Client extends http.BaseClient {
  _Client(this._send, {this.onClose});

  final Future<http.StreamedResponse> Function(http.BaseRequest request) _send;
  final void Function()? onClose;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _send(request);

  @override
  void close() => onClose?.call();
}

http.StreamedResponse _response(
  http.BaseRequest request, {
  int statusCode = 200,
}) => http.StreamedResponse(
  const Stream<List<int>>.empty(),
  statusCode,
  request: request,
);
