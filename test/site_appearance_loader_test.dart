import 'dart:async';
import 'dart:convert';

import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  group('JSON resolution', () {
    test('loads anonymous site defaults and credential-free CSS', () async {
      final client = _Client((request) async {
        return switch ((request.url.host, request.url.path)) {
          ('forum.example', '/community/site.json') => _response(
            request,
            _siteJson(),
            contentType: 'application/json',
          ),
          ('forum.example', '/community/color-scheme-stylesheet/10/5.json') =>
            _response(
              request,
              _details('/community/styles/light.css'),
              contentType: 'application/json',
            ),
          ('forum.example', '/community/color-scheme-stylesheet/11/5.json') =>
            _response(
              request,
              _details('https://cdn.example/dark.css'),
              contentType: 'application/json',
            ),
          ('forum.example', '/community/') => _response(
            request,
            _themeDocument(),
            contentType: 'text/html',
          ),
          ('forum.example', '/community/styles/light.css') => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          ('cdn.example', '/dark.css') => _response(
            request,
            _paletteCss.replaceFirst('light', 'dark'),
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      final appearance = await SiteAppearanceLoader(
        client: client,
      ).load(siteUrl: 'https://forum.example/community');

      expect(appearance?.mode, SiteAppearanceMode.followSystem);
      expect(appearance?.base?.brightness, Brightness.light);
      expect(appearance?.alternate?.brightness, Brightness.dark);
      expect(client.requests.map((request) => request.url.toString()), [
        'https://forum.example/community/site.json',
        'https://forum.example/community/color-scheme-stylesheet/10/5.json',
        'https://forum.example/community/color-scheme-stylesheet/11/5.json',
        'https://forum.example/community/',
        'https://forum.example/community/styles/light.css',
        'https://cdn.example/dark.css',
      ]);
      for (final request in client.requests) {
        expect(request.headers, isNot(contains('user-api-key')));
        expect(request.headers, isNot(contains('user-api-client-id')));
        expect(request.followRedirects, isFalse);
      }
    });

    test(
      'uses authenticated preferences and isolates CSS credentials',
      () async {
        final client = _Client((request) async {
          final path = request.url.path;
          if (path == '/site.json') {
            return _response(
              request,
              _siteJson(),
              contentType: 'application/json',
            );
          }
          if (path == '/u/alice.json') {
            return _response(
              request,
              _userJson(
                themeIds: const [6],
                colorSchemeId: 20,
                darkSchemeId: 21,
                interfaceColorMode: 3,
              ),
              contentType: 'application/json',
            );
          }
          if (path == '/color-scheme-stylesheet/20/6.json') {
            return _response(
              request,
              _details('/styles/light.css'),
              contentType: 'application/json',
            );
          }
          if (path == '/color-scheme-stylesheet/21/6.json') {
            return _response(
              request,
              _details('/styles/dark.css'),
              contentType: 'application/json',
            );
          }
          if (path == '/') {
            return _response(
              request,
              _themeDocument(),
              contentType: 'text/html',
            );
          }
          if (path == '/styles/light.css') {
            return _response(request, _paletteCss, contentType: 'text/css');
          }
          if (path == '/styles/dark.css') {
            return _response(
              request,
              _paletteCss.replaceFirst('light', 'dark'),
              contentType: 'text/css',
            );
          }
          throw StateError('Unexpected request: ${request.url}');
        });

        final appearance = await SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          username: 'alice',
          apiKey: 'secret-key',
          clientId: 'client-id',
        );

        expect(appearance?.mode, SiteAppearanceMode.alternate);
        expect(client.requests.map((request) => request.url.path), [
          '/site.json',
          '/u/alice.json',
          '/color-scheme-stylesheet/20/6.json',
          '/color-scheme-stylesheet/21/6.json',
          '/',
          '/styles/light.css',
          '/styles/dark.css',
        ]);
        for (final request in client.requests.take(4)) {
          expect(request.headers['accept'], 'application/json');
          expect(request.headers['user-api-key'], 'secret-key');
          expect(request.headers['user-api-client-id'], 'client-id');
        }
        expect(client.requests[4].headers['accept'], 'text/html');
        expect(client.requests[4].headers['user-api-key'], 'secret-key');
        expect(client.requests[4].headers['user-api-client-id'], 'client-id');
        for (final request in client.requests.skip(5)) {
          expect(request.headers['accept'], 'text/css');
          expect(request.headers, isNot(contains('user-api-key')));
          expect(request.headers, isNot(contains('user-api-client-id')));
        }
      },
    );

    test('applies selected theme CSS after the color definitions', () async {
      final metaCss = _paletteCss.replaceAll('#0088cc', '#7b5fe2');
      final client = _Client((request) async {
        return switch (request.url.path) {
          '/site.json' => _response(
            request,
            _siteJson(),
            contentType: 'application/json',
          ),
          '/color-scheme-stylesheet/10/5.json' => _response(
            request,
            _details('/light.css'),
            contentType: 'application/json',
          ),
          '/color-scheme-stylesheet/11/5.json' => _response(
            request,
            _details('/dark.css'),
            contentType: 'application/json',
          ),
          '/' => _response(
            request,
            _themeDocument(themeId: 5, href: '/theme.css'),
            contentType: 'text/html',
          ),
          '/light.css' => _response(request, metaCss, contentType: 'text/css'),
          '/dark.css' => _response(
            request,
            metaCss.replaceFirst('light', 'dark'),
            contentType: 'text/css',
          ),
          '/theme.css' => _response(
            request,
            _metaThemeCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      final appearance = await SiteAppearanceLoader(
        client: client,
      ).load(siteUrl: 'https://forum.example');

      expect(appearance?.base?.selected, const Color(0x267B5FE2));
      expect(appearance?.base?.hover, const Color(0x267B5FE2));
      expect(appearance?.base?.borderRadius, 8);
      expect(appearance?.alternate?.selected, const Color(0x267B5FE2));
      expect(appearance?.alternate?.hover, const Color(0x267B5FE2));
      expect(appearance?.alternate?.borderRadius, 8);
      final themeRequest = client.requests.singleWhere(
        (request) => request.url.path == '/theme.css',
      );
      expect(themeRequest.headers, isNot(contains('user-api-key')));
      expect(themeRequest.headers['accept'], 'text/css');
    });

    test('reads the forum document concurrently with scheme JSON', () async {
      final documentRequested = Completer<void>();
      final client = _Client((request) async {
        final path = request.url.path;
        if (path == '/site.json') {
          return _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          );
        }
        if (path == '/color-scheme-stylesheet/10/5.json') {
          // Held until the forum document request is observed. A loader that
          // serialises the document behind this batch deadlocks here and
          // fails through its transport timeout.
          await documentRequested.future;
          return _response(
            request,
            _details('/styles/colors.css'),
            contentType: 'application/json',
          );
        }
        if (path == '/') {
          documentRequested.complete();
          return _response(request, _themeDocument(), contentType: 'text/html');
        }
        if (path == '/styles/colors.css') {
          return _response(request, _paletteCss, contentType: 'text/css');
        }
        throw StateError('Unexpected request: ${request.url}');
      });

      expect(
        await SiteAppearanceLoader(
          client: client,
          timeout: const Duration(seconds: 1),
        ).load(siteUrl: 'https://forum.example'),
        isNotNull,
      );
    });

    test('returns null when modern site theme metadata is absent', () async {
      final client = _Client(
        (request) async =>
            _response(request, '{}', contentType: 'application/json'),
      );

      expect(
        await SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        isNull,
      );
      expect(client.requests, hasLength(1));
    });

    test('requires a username for authenticated preference lookup', () async {
      final client = _Client(
        (request) async =>
            _response(request, _siteJson(), contentType: 'application/json'),
      );

      await expectLater(
        SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          apiKey: 'secret-key',
          clientId: 'client-id',
        ),
        _failsWith(SiteAppearanceLoadFailure.malformed),
      );
      expect(client.requests, hasLength(1));
    });

    test('rejects malformed JSON', () async {
      final client = _Client(
        (request) async =>
            _response(request, '{broken', contentType: 'application/json'),
      );

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.malformed),
      );
    });
  });

  group('forum JSON transport', () {
    test('uses the final same-origin API base after a redirect', () async {
      final client = _Client((request) async {
        return switch (request.url.path) {
          '/old/site.json' => _response(
            request,
            '',
            statusCode: 302,
            headers: {'location': '/forum/site.json'},
          ),
          '/forum/site.json' => _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          ),
          '/forum/u/alice.json' => _response(
            request,
            _userJson(),
            contentType: 'application/json',
          ),
          '/forum/color-scheme-stylesheet/10/5.json' => _response(
            request,
            _details('/forum/styles/colors.css'),
            contentType: 'application/json',
          ),
          '/forum/' => _response(
            request,
            _themeDocument(),
            contentType: 'text/html',
          ),
          '/forum/styles/colors.css' => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      final appearance = await SiteAppearanceLoader(client: client).load(
        siteUrl: 'https://forum.example/old',
        username: 'alice',
        apiKey: 'secret-key',
        clientId: 'client-id',
      );

      expect(appearance?.base, isNotNull);
      expect(client.requests.map((request) => request.url.path), [
        '/old/site.json',
        '/forum/site.json',
        '/forum/u/alice.json',
        '/forum/color-scheme-stylesheet/10/5.json',
        '/forum/',
        '/forum/styles/colors.css',
      ]);
      for (final request in client.requests.take(5)) {
        expect(request.headers['user-api-key'], 'secret-key');
      }
      expect(client.requests.last.headers, isNot(contains('user-api-key')));
    });

    test('anonymous site metadata may follow a canonical redirect', () async {
      final client = _Client((request) async {
        return switch ((request.url.host, request.url.path)) {
          ('forum.example', '/site.json') => _response(
            request,
            '',
            statusCode: 302,
            headers: {
              'location': 'https://canonical.example/community/site.json',
            },
          ),
          ('canonical.example', '/community/site.json') => _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          ),
          (
            'canonical.example',
            '/community/color-scheme-stylesheet/10/5.json',
          ) =>
            _response(
              request,
              _details('/community/styles/colors.css'),
              contentType: 'application/json',
            ),
          ('canonical.example', '/community/') => _response(
            request,
            _themeDocument(),
            contentType: 'text/html',
          ),
          ('canonical.example', '/community/styles/colors.css') => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      expect(
        await SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        isNotNull,
      );
      expect(client.requests.map((request) => request.url.host), [
        'forum.example',
        'canonical.example',
        'canonical.example',
        'canonical.example',
        'canonical.example',
      ]);
    });

    test('never follows an authenticated cross-origin redirect', () async {
      final client = _Client(
        (request) async => _response(
          request,
          '',
          statusCode: 302,
          headers: {'location': 'https://other.example/site.json'},
        ),
      );

      await expectLater(
        SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          username: 'alice',
          apiKey: 'secret-key',
          clientId: 'client-id',
        ),
        _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
      );
      expect(client.requests, hasLength(1));
    });

    test('does not retry an authentication refusal anonymously', () async {
      final client = _Client(
        (request) async => _response(request, 'forbidden', statusCode: 403),
      );

      await expectLater(
        SiteAppearanceLoader(client: client).load(
          siteUrl: 'https://forum.example',
          username: 'alice',
          apiKey: 'rejected-key',
          clientId: 'client-id',
        ),
        _failsWith(SiteAppearanceLoadFailure.refused),
      );
      expect(client.requests, hasLength(1));
    });

    test('maps a non-success stylesheet resolver response', () async {
      final client = _Client((request) async {
        if (request.url.path == '/site.json') {
          return _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
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
    });

    test('rejects resolver JSON without a stylesheet href', () async {
      final client = _Client((request) async {
        if (request.url.path == '/site.json') {
          return _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          );
        }
        return _response(request, '{}', contentType: 'application/json');
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.malformed),
      );
      expect(client.requests, hasLength(3));
    });
  });

  group('stylesheet isolation', () {
    test('follows safe CDN redirects without credentials', () async {
      final client = _Client((request) async {
        return switch ((request.url.host, request.url.path)) {
          ('forum.example', '/site.json') => _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          ),
          ('forum.example', '/color-scheme-stylesheet/10/5.json') => _response(
            request,
            _details('https://cdn-one.example/colors.css'),
            contentType: 'application/json',
          ),
          ('forum.example', '/') => _response(
            request,
            _themeDocument(),
            contentType: 'text/html',
          ),
          ('cdn-one.example', '/colors.css') => _response(
            request,
            '',
            statusCode: 302,
            headers: {'location': 'https://cdn-two.example/colors.css'},
          ),
          ('cdn-two.example', '/colors.css') => _response(
            request,
            _paletteCss,
            contentType: 'text/css',
          ),
          _ => throw StateError('Unexpected request: ${request.url}'),
        };
      });

      expect(
        await SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        isNotNull,
      );
      for (final request in client.requests.skip(2)) {
        expect(request.headers, isNot(contains('user-api-key')));
      }
    });

    test('prevalidates every href before any CSS request', () async {
      final client = _Client((request) async {
        if (request.url.path == '/site.json') {
          return _response(
            request,
            _siteJson(),
            contentType: 'application/json',
          );
        }
        if (request.url.path.contains('/10/')) {
          return _response(
            request,
            _details('https://cdn.example/light.css'),
            contentType: 'application/json',
          );
        }
        if (request.url.path.contains('/11/')) {
          return _response(
            request,
            _details('http://127.0.0.1:8765/dark.css'),
            contentType: 'application/json',
          );
        }
        if (request.url.path == '/') {
          // The forum document legitimately starts alongside the resolver
          // JSON; only CSS subresources must wait for prevalidation.
          return _response(request, _themeDocument(), contentType: 'text/html');
        }
        throw StateError('No CSS request should start: ${request.url}');
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
      );
      expect(client.requests, hasLength(4));
    });

    test('prevalidates a parent theme href before any CSS request', () async {
      final client = _Client((request) async {
        return switch (request.url.path) {
          '/site.json' => _response(
            request,
            _siteJson(includeAlternate: false),
            contentType: 'application/json',
          ),
          '/color-scheme-stylesheet/10/5.json' => _response(
            request,
            _details('/light.css'),
            contentType: 'application/json',
          ),
          '/' => _response(
            request,
            _themeDocument(themeId: 5, href: 'http://127.0.0.1:8765/theme.css'),
            contentType: 'text/html',
          ),
          _ => throw StateError('No CSS request should start: ${request.url}'),
        };
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.unsafeUrl),
      );
      expect(client.requests, hasLength(3));
    });

    test('does not mix a valid base with a malformed alternate', () async {
      final client = _Client((request) async {
        final path = request.url.path;
        if (path == '/site.json') {
          return _response(
            request,
            _siteJson(),
            contentType: 'application/json',
          );
        }
        if (path == '/color-scheme-stylesheet/10/5.json') {
          return _response(
            request,
            _details('/light.css'),
            contentType: 'application/json',
          );
        }
        if (path == '/color-scheme-stylesheet/11/5.json') {
          return _response(
            request,
            _details('/dark.css'),
            contentType: 'application/json',
          );
        }
        if (path == '/') {
          return _response(request, _themeDocument(), contentType: 'text/html');
        }
        return _response(
          request,
          path == '/light.css' ? _paletteCss : ':root{--primary:#fff}',
          contentType: 'text/css',
        );
      });

      await expectLater(
        SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.malformed),
      );
      expect(client.requests, hasLength(6));
    });
  });

  group('bounds', () {
    test('stops at the configured redirect limit', () async {
      final client = _Client(
        (request) async => _response(
          request,
          '',
          statusCode: 302,
          headers: {'location': '/site.json'},
        ),
      );

      await expectLater(
        SiteAppearanceLoader(
          client: client,
          maxRedirects: 1,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.tooManyRedirects),
      );
      expect(client.requests, hasLength(2));
    });

    test('maps an oversized JSON response', () async {
      final client = _Client((request) async => _response(request, 'x' * 64));

      await expectLater(
        SiteAppearanceLoader(
          client: client,
          maxResponseBytes: 8,
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.responseTooLarge),
      );
    });

    test('maps a stalled response body', () async {
      final client = _Client(
        (request) async => http.StreamedResponse(
          Stream<List<int>>.fromFuture(Completer<List<int>>().future),
          200,
          request: request,
        ),
      );

      await expectLater(
        SiteAppearanceLoader(
          client: client,
          timeout: const Duration(milliseconds: 250),
        ).load(siteUrl: 'https://forum.example'),
        _failsWith(SiteAppearanceLoadFailure.timedOut),
      );
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

String _siteJson({bool includeAlternate = true}) => jsonEncode({
  'user_themes': [
    {
      'theme_id': 5,
      'name': 'Default',
      'default': true,
      'color_scheme_id': 10,
      'dark_color_scheme_id': includeAlternate ? 11 : null,
      'only_theme_color_schemes': false,
    },
    {
      'theme_id': 6,
      'name': 'Selected',
      'default': false,
      'color_scheme_id': 12,
      'dark_color_scheme_id': 13,
      'only_theme_color_schemes': false,
    },
  ],
  'user_color_schemes': [
    {'id': 20, 'theme_id': null, 'is_dark': false},
    {'id': 21, 'theme_id': null, 'is_dark': true},
  ],
});

String _userJson({
  List<int> themeIds = const [5],
  int? colorSchemeId,
  int? darkSchemeId,
  int interfaceColorMode = 1,
}) => jsonEncode({
  'user': {
    'username': 'alice',
    'user_option': {
      'theme_ids': themeIds,
      'color_scheme_id': colorSchemeId,
      'dark_scheme_id': darkSchemeId,
      'interface_color_mode': interfaceColorMode,
    },
  },
});

String _details(String href) => jsonEncode({'new_href': href});

String _themeDocument({int? themeId, String? href}) =>
    switch ((themeId, href)) {
      (final int id, final String stylesheet) =>
        '<html><head><link rel="stylesheet" data-target="common_theme" '
            'data-theme-id="$id" href="$stylesheet"></head></html>',
      _ => '<html><head><title>Forum</title></head></html>',
    };

const String _metaThemeCss = '''
:root {
  --theme-border-radius: .5rem;
  --d-border-radius: var(--theme-border-radius);
  --meta-color-surface-accent:
    oklch(from var(--tertiary) l c h / 0.15);
  --d-selected: var(--meta-color-surface-accent);
  --d-hover: var(--meta-color-surface-accent);
}
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
