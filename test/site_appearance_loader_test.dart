import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('transport fixture is a parseable appearance stylesheet', () {
    expect(parseSiteAppearanceStylesheet(_paletteCss), isNotNull);
  });

  group('document request', () {
    test('keeps a subfolder and authenticates only the forum HTML', () async {
      final client = _Client((request) async {
        return switch (request.url.toString()) {
          'https://forum.example/community/' => _response(
            request,
            _document('assets/colors.css'),
            contentType: 'text/html',
          ),
          'https://forum.example/community/assets/colors.css' => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });
      final loader = SiteAppearanceLoader(client: client);

      final appearance = await loader.load(
        siteUrl: 'https://forum.example/community',
        apiKey: 'secret-key',
        clientId: 'client-id',
      );

      expect(appearance?.base?.brightness, Brightness.light);
      expect(appearance?.base?.tertiary, const Color(0xFF0088CC));
      expect(client.requests.map((request) => request.url.toString()), [
        'https://forum.example/community/',
        'https://forum.example/community/assets/colors.css',
      ]);
      expect(
        client.requests.first.headers,
        containsPair('accept', 'text/html'),
      );
      expect(
        client.requests.first.headers,
        containsPair('user-agent', 'DiscourseNative/1.0'),
      );
      expect(
        client.requests.first.headers,
        containsPair('user-api-key', 'secret-key'),
      );
      expect(
        client.requests.first.headers,
        containsPair('user-api-client-id', 'client-id'),
      );
      expect(client.requests.last.headers, containsPair('accept', 'text/css'));
      expect(client.requests.last.headers, isNot(contains('user-api-key')));
      expect(
        client.requests.last.headers,
        isNot(contains('user-api-client-id')),
      );
      expect(
        client.requests.every((request) => !request.followRedirects),
        isTrue,
      );
    });

    test('anonymous HTML carries no user API identity', () async {
      final client = _Client(
        (request) async => _response(
          request,
          '<!doctype html><title>No appearance</title>',
          contentType: 'text/html',
        ),
      );

      expect(
        await SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          clientId: 'client-id-without-a-key',
        ),
        isNull,
      );

      expect(client.requests.single.headers, {
        'accept': 'text/html',
        'user-agent': 'DiscourseNative/1.0',
      });
    });

    test(
      'anonymous HTML follows a safe canonical cross-origin redirect',
      () async {
        final client = _Client((request) async {
          return switch (request.url.toString()) {
            'https://forum.example/' => _response(
              request,
              '',
              statusCode: 302,
              headers: {'location': 'https://canonical.example/community/'},
            ),
            'https://canonical.example/community/' => _response(
              request,
              _document('assets/colors.css'),
              contentType: 'text/html',
            ),
            'https://canonical.example/community/assets/colors.css' =>
              _response(request, _paletteCss, contentType: 'text/css'),
            _ => throw StateError('Unexpected request: ${request.url}'),
          };
        });

        final appearance = await SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          clientId: 'anonymous-client-id',
        );

        expect(appearance?.base, isNotNull);
        expect(client.requests.map((request) => request.url.toString()), [
          'https://forum.example/',
          'https://canonical.example/community/',
          'https://canonical.example/community/assets/colors.css',
        ]);
        for (final request in client.requests) {
          expect(request.headers, isNot(contains('user-api-key')));
          expect(request.headers, isNot(contains('user-api-client-id')));
        }
      },
    );

    test(
      'same-origin redirects retain authentication and set the final base',
      () async {
        final client = _Client((request) async {
          return switch (request.url.path) {
            '/old/' => _response(
              request,
              '',
              statusCode: 302,
              headers: {'location': '/forum/'},
            ),
            '/forum/' => _response(
              request,
              _document('colors.css'),
              contentType: 'text/html',
            ),
            '/forum/colors.css' => _response(
              request,
              _paletteCss,
              contentType: 'text/css',
            ),
            _ => throw StateError('Unexpected request: ${request.url}'),
          };
        });

        final appearance = await SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example/old',
          apiKey: 'secret-key',
          clientId: 'client-id',
        );

        expect(appearance?.base, isNotNull);
        expect(client.requests.map((request) => request.url.path), [
          '/old/',
          '/forum/',
          '/forum/colors.css',
        ]);
        for (final request in client.requests.take(2)) {
          expect(request.headers['user-api-key'], 'secret-key');
          expect(request.headers['user-api-client-id'], 'client-id');
        }
        expect(client.requests.last.headers, isNot(contains('user-api-key')));
      },
    );

    test(
      'rejects a cross-origin authenticated redirect before following it',
      () async {
        final client = _Client(
          (request) async => _response(
            request,
            '',
            statusCode: 302,
            headers: {'location': 'https://other.example/forum/'},
          ),
        );

        await expectLater(
          SiteAppearanceLoader(client: client).load(
            siteUrl: 'https://forum.example',
            apiKey: 'secret-key',
            clientId: 'client-id',
          ),
          _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
        );

        expect(client.requests, hasLength(1));
        expect(client.requests.single.url.host, 'forum.example');
      },
    );

    test(
      'rejects an HTTPS downgrade before forwarding authentication',
      () async {
        final client = _Client(
          (request) async => _response(
            request,
            '',
            statusCode: 302,
            headers: {'location': 'http://forum.example/insecure/'},
          ),
        );

        await expectLater(
          SiteAppearanceLoader(client: client).load(
            siteUrl: 'https://forum.example',
            apiKey: 'secret-key',
            clientId: 'client-id',
          ),
          _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
        );

        expect(client.requests, hasLength(1));
        expect(client.requests.single.url.scheme, 'https');
      },
    );

    test('an authentication refusal is never retried anonymously', () async {
      final client = _Client(
        (request) async => _response(request, 'forbidden', statusCode: 403),
      );

      await expectLater(
        SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          apiKey: 'rejected-key',
          clientId: 'client-id',
        ),
        _failsWith(SiteAppearanceLoadFailure.refused),
      );

      expect(client.requests, hasLength(1));
      expect(client.requests.single.headers['user-api-key'], 'rejected-key');
    });
  });

  group('stylesheet requests', () {
    test('treats a non-success stylesheet response as unavailable', () async {
      final client = _Client((request) async {
        if (request.url.host == 'forum.example') {
          return _response(
            request,
            _document('https://cdn.example/colors.css'),
            contentType: 'text/html',
          );
        }
        return _response(request, 'unavailable', statusCode: 503);
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.unavailable),
      );

      expect(client.requests, hasLength(2));
      expect(client.requests.last.headers, isNot(contains('user-api-key')));
    });

    test('may follow safe cross-CDN redirects without credentials', () async {
      final client = _Client((request) async {
        return switch (request.url.host) {
          'forum.example' => _response(
            request,
            _document('https://first.cdn.example/colors.css'),
            contentType: 'text/html',
          ),
          'first.cdn.example' => _response(
            request,
            '',
            statusCode: 302,
            headers: {'location': 'https://second.cdn.example/final.css'},
          ),
          'second.cdn.example' => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      final appearance = await SiteAppearanceLoader(client: client).load(
        siteUrl: 'https://forum.example',
        apiKey: 'secret-key',
        clientId: 'client-id',
      );

      expect(appearance?.base, isNotNull);
      expect(client.requests.map((request) => request.url.host), [
        'forum.example',
        'first.cdn.example',
        'second.cdn.example',
      ]);
      for (final request in client.requests.skip(1)) {
        expect(request.headers['accept'], 'text/css');
        expect(request.headers, isNot(contains('user-api-key')));
        expect(request.headers, isNot(contains('user-api-client-id')));
      }
    });

    test('refuses an HTTPS stylesheet downgrade', () async {
      final client = _Client((request) async {
        if (request.url.host == 'forum.example') {
          return _response(
            request,
            _document('https://cdn.example/colors.css'),
            contentType: 'text/html',
          );
        }
        return _response(
          request,
          '',
          statusCode: 302,
          headers: {'location': 'http://cdn.example/colors.css'},
        );
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
      );

      expect(client.requests, hasLength(2));
    });

    test(
      'rejects an initial loopback downgrade before any stylesheet request',
      () async {
        final client = _Client((request) async {
          if (request.url.host == 'forum.example') {
            return _response(
              request,
              _document(
                'https://cdn.example/base.css',
                alternate: 'http://127.0.0.1:4567/local-action',
              ),
              contentType: 'text/html',
            );
          }
          throw StateError('A stylesheet request must not be sent');
        });

        await expectLater(
          SiteAppearanceLoader(
            client: client,
          ).load(siteUrl: 'https://forum.example'),
          _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
        );

        expect(client.requests, hasLength(1));
      },
    );

    test('does not return a partially parsed two-palette appearance', () async {
      final client = _Client((request) async {
        return switch (request.url.path) {
          '/' => _response(
            request,
            _document('base.css', alternate: 'alternate.css'),
            contentType: 'text/html',
          ),
          '/base.css' => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          '/alternate.css' => _response(
            request,
            ':root { --primary: definitely-not-a-color; }',
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.malformed),
      );

      expect(client.requests.map((request) => request.url.path), [
        '/',
        '/base.css',
        '/alternate.css',
      ]);
    });
  });

  group('bounds', () {
    test('stops at the configured redirect limit', () async {
      final client = _Client(
        (request) async => _response(
          request,
          '',
          statusCode: 302,
          headers: {
            'location': request.url.path == '/one/' ? '/two/' : '/three/',
          },
        ),
      );

      await expectLater(
        SiteAppearanceLoader(
          client: client,
          maxRedirects: 1,
        ).load(siteUrl: 'https://forum.example/one', apiKey: 'secret-key'),
        _failsWith(SiteAppearanceLoadFailure.tooManyRedirects),
      );

      expect(client.requests.map((request) => request.url.path), [
        '/one/',
        '/two/',
      ]);
    });

    test(
      'maps an oversized response to the optional capability failure',
      () async {
        final client = _Client(
          (request) async => http.StreamedResponse(
            Stream.value(utf8.encode('too large')),
            200,
            request: request,
            contentLength: 9,
          ),
        );

        await expectLater(
          SiteAppearanceLoader(
            client: client,
            maxResponseBytes: 4,
          ).load(siteUrl: 'https://forum.example'),
          _failsWith(SiteAppearanceLoadFailure.responseTooLarge),
        );
      },
    );

    test('maps a stalled body to the optional capability failure', () async {
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      addTearDown(body.close);
      final client = _Client(
        (request) async =>
            http.StreamedResponse(body.stream, 200, request: request),
      );

      await expectLater(
        SiteAppearanceLoader(
          client: client,
          timeout: const Duration(milliseconds: 25),
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.timedOut),
      );
      expect(cancelled, isTrue);
    });
  });
}

Matcher _failsWith(SiteAppearanceLoadFailure failure) => throwsA(
  isA<SiteAppearanceLoadException>().having(
    (error) => error.failure,
    'failure',
    failure,
  ),
);

String _document(String base, {String? alternate}) =>
    '''
<!doctype html>
<html>
  <head>
    <meta name="color-scheme" content="light dark">
    <link href="$base" media="(prefers-color-scheme: light)"
          rel="stylesheet" class="light-scheme" data-scheme-id="1">
    ${alternate == null ? '' : '''
    <link href="$alternate" media="(prefers-color-scheme: dark)"
          rel="stylesheet" class="dark-scheme" data-scheme-id="2">
    '''}
  </head>
</html>
''';

const String _paletteCss = '''
:root {
  --scheme-type: light;
  --primary: #222222;
  --secondary: #ffffff;
  --tertiary: #0088cc;
  --quaternary: #e45735;
  --header_background: #ffffff;
  --header_primary: #222222;
  --highlight: #ffff4d;
  --danger: #c80001;
  --success: #009900;
  --love: #fa6c8d;
  --d-selected: #d1f0ff;
  --d-hover: #f1ecff;
  --primary-very-low: #f8f8f8;
  --primary-low: #eeeeee;
  --primary-low-mid: #cccccc;
  --primary-medium: #999999;
  --primary-high: #666666;
  --primary-very-high: #444444;
  --secondary-very-high: #eeeeee;
  --tertiary-low: #ddf2ff;
  --quaternary-low: #f8ded8;
  --highlight-low: #ffffcc;
  --danger-low: #ffe0e0;
  --mention-background-color: #eeeeee;
  --hljs-bg: #f8f8f8;
  --inline-code-bg: #f8f8f8;
  --hljs-keyword: #8b2fa0;
  --hljs-string: #2e7d32;
  --hljs-comment: #6b7280;
  --hljs-number: #b35309;
  --hljs-title: #1a56b0;
  --hljs-name: #1a56b0;
  --hljs-attribute: #00707a;
  --hljs-meta: #00707a;
}
''';

final class _RecordedRequest {
  const _RecordedRequest({
    required this.url,
    required this.headers,
    required this.followRedirects,
  });

  final Uri url;
  final Map<String, String> headers;
  final bool followRedirects;
}

final class _Client extends http.BaseClient {
  _Client(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;
  final List<_RecordedRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(
      _RecordedRequest(
        url: request.url,
        headers: {
          for (final entry in request.headers.entries)
            entry.key.toLowerCase(): entry.value,
        },
        followRedirects: request.followRedirects,
      ),
    );
    return handler(request);
  }
}

http.StreamedResponse _response(
  http.BaseRequest request,
  String body, {
  int statusCode = 200,
  String? contentType,
  Map<String, String> headers = const {},
}) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    request: request,
    contentLength: bytes.length,
    headers: {
      if (contentType != null) 'content-type': '$contentType; charset=utf-8',
      ...headers,
    },
  );
}
