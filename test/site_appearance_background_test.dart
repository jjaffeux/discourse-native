import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:discourse_native/src/data/site_appearance_loader.dart';
import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final stage in ['JSON', 'HTML', 'CSS']) {
    test(
      'large $stage lets an event run before appearance completes',
      () async {
        final target = switch (stage) {
          'JSON' => '/site.json',
          'HTML' => '/',
          _ => '/theme.css',
        };
        final responses = _responses(
          jsonPadding: stage == 'JSON' ? 64 * 1024 : 0,
          htmlRows: stage == 'HTML' ? 512 : 0,
          cssRules: stage == 'CSS' ? 512 : 0,
        );
        final event = Completer<void>();
        addTearDown(() => event.future);
        final client = _IsolateUnsafeClient((request) async {
          if (request.url.path == target) Timer.run(event.complete);
          return responses[request.url.path]!;
        });
        addTearDown(client.close);

        final appearance = await SiteAppearanceLoader(
          client: client,
        ).load(siteUrl: 'https://forum.example');

        expect(appearance, _expectedAppearance());
        expect(appearance?.toJson(), _expectedAppearance().toJson());
        expect(event.isCompleted, isTrue);
      },
    );
  }

  test('small responses complete without an event-loop round trip', () async {
    final event = Completer<void>();
    addTearDown(() => event.future);
    Timer.run(event.complete);
    final appearance = await _load(_responses());

    expect(appearance, _expectedAppearance());
    expect(event.isCompleted, isFalse);
  });

  test(
    'counts parent CSS for both palettes when choosing the worker',
    () async {
      // Every response is below 32 KB, but resolving the parent twice exceeds
      // the inline work limit. The parent's bytes are still fetched only once.
      final responses = _responses(cssRules: 128);
      expect(responses.values.every((r) => r.body.length < 32 * 1024), isTrue);
      final event = Completer<void>();
      addTearDown(() => event.future);
      final requests = <String>[];
      final client = _IsolateUnsafeClient((request) async {
        requests.add(request.url.path);
        if (request.url.path == '/theme.css') Timer.run(event.complete);
        return responses[request.url.path]!;
      });
      addTearDown(client.close);

      expect(
        await SiteAppearanceLoader(client: client).load(siteUrl: _siteUrl),
        _expectedAppearance(),
      );
      expect(event.isCompleted, isTrue);
      expect(requests.where((path) => path == '/theme.css'), hasLength(1));
    },
  );

  for (final alternate in [true, false]) {
    test('transfers the full appearance with alternate=$alternate', () async {
      final responses = _responses(
        jsonPadding: 64 * 1024,
        htmlRows: 512,
        cssRules: 512,
        alternate: alternate,
      );
      final small = await _load(_responses(alternate: alternate));
      final appearance = await _load(responses);

      expect(appearance, small);
      expect(appearance?.toJson(), small?.toJson());
      expect(appearance?.base?.brightness, Brightness.light);
      expect(appearance?.base?.tertiary, const Color(0xff123456));
      expect(appearance?.base?.hover, const Color(0x26123456));
      expect(appearance?.base?.borderRadius, 10);
      expect(
        appearance?.base?.avatarBorderRadius,
        const AvatarBorderRadius.pixels(10),
      );
      expect(
        appearance?.alternate?.brightness,
        alternate ? Brightness.dark : null,
      );
      expect(
        appearance?.mode,
        alternate ? SiteAppearanceMode.followSystem : SiteAppearanceMode.base,
      );
    });
  }

  test(
    'large document preserves discovery order, deduplication and cascade',
    () async {
      final responses = _responses(htmlRows: 512, cssRules: 128);
      responses['/'] = http.Response(
        _document(512).replaceFirst('</head>', '''
<link rel="stylesheet" data-target="common_theme" data-theme-id="6" href="/component.css">
<link rel="preload" data-target="common_theme" data-theme-id="5" href="/preload.css">
<link rel="stylesheet" data-target="common_theme" data-theme-id="5" href="/bad%link.css">
<link rel="preload StyleSheet" data-target="common_theme" data-theme-id="5" href="/later.css?v=1&amp;x=2">
<link rel="stylesheet" data-target="common_theme" data-theme-id="5" href="/theme.css">
</head>'''),
        200,
      );
      const laterCss = ':root { --tertiary: #654321 !important; }';
      responses['/later.css?v=1&x=2'] = http.Response(laterCss, 200);
      final requests = <String>[];
      final client = _IsolateUnsafeClient((request) async {
        final path =
            request.url.path +
            (request.url.hasQuery ? '?${request.url.query}' : '');
        requests.add(path);
        return responses[path]!;
      });
      addTearDown(client.close);

      final appearance = await SiteAppearanceLoader(
        client: client,
      ).load(siteUrl: _siteUrl);

      expect(requests.skip(4), [
        '/light.css',
        '/dark.css',
        '/theme.css',
        '/later.css?v=1&x=2',
      ]);
      expect(
        appearance,
        SiteAppearance(
          base: parseSiteAppearanceStylesheets([
            _palette,
            _theme(128),
            laterCss,
          ]),
          alternate: parseSiteAppearanceStylesheets([
            _darkPalette,
            _theme(128),
            laterCss,
          ]),
        ),
      );
      expect(appearance?.base?.tertiary, const Color(0xff654321));
    },
  );

  for (final large in [false, true]) {
    for (final path in ['/light.css', '/dark.css']) {
      test('attributes malformed $path to its source, large=$large', () async {
        final responses = _responses(cssRules: large ? 512 : 0);
        responses[path] = http.Response(':root { --primary: #fff; }', 200);
        await expectLater(_load(responses), _malformedAt(path));
      });
    }
    test(
      'reports the base first if both palettes are malformed, large=$large',
      () async {
        final responses = _responses(cssRules: large ? 512 : 0);
        responses['/light.css'] = http.Response(
          ':root { --primary: #fff; }',
          200,
        );
        responses['/dark.css'] = http.Response(
          ':root { --primary: #fff; }',
          200,
        );
        await expectLater(_load(responses), _malformedAt('/light.css'));
      },
    );
  }

  for (final path in ['/site.json', '/color-scheme-stylesheet/11/5.json']) {
    test('attributes background JSON errors to redirected $path', () async {
      final responses = _responses();
      responses[path] = http.Response(
        '',
        302,
        headers: {'location': '/invalid.json'},
      );
      responses['/invalid.json'] = http.Response(
        '{${' ' * (64 * 1024)}',
        200,
        headers: {'content-type': 'application/json'},
      );
      await expectLater(
        _load(responses),
        throwsA(
          isA<SiteAppearanceLoadException>()
              .having(
                (e) => e.failure,
                'failure',
                SiteAppearanceLoadFailure.malformed,
              )
              .having((e) => e.url, 'url', Uri.parse('$_siteUrl/invalid.json'))
              .having((e) => e.detail, 'detail', isA<FormatException>()),
        ),
      );
    });
  }

  for (final (contentType, encoding) in <(String?, Encoding)>[
    ('application/json', utf8),
    ('application/json; charset="utf-8"', utf8),
    ('application/json; charset=iso-8859-1', latin1),
    // package:http falls back to Latin-1 for an explicitly unknown charset.
    ('application/json; charset=unknown', latin1),
    (null, latin1),
  ]) {
    test(
      'keeps response decoding for large resolver JSON: $contentType',
      () async {
        final responses = _responses();
        final href = Uri.parse('$_siteUrl/café.css');
        responses['/color-scheme-stylesheet/10/5.json'] = http.Response.bytes(
          encoding.encode(
            jsonEncode({'new_href': '/café.css', 'padding': 'x' * (64 * 1024)}),
          ),
          200,
          headers: {'content-type': ?contentType},
        );
        final client = _IsolateUnsafeClient((request) async {
          if (request.url == href) return http.Response(_palette, 200);
          expect(request.url.path, isNot('/light.css'));
          return responses[request.url.path]!;
        });
        addTearDown(client.close);

        expect(
          await SiteAppearanceLoader(client: client).load(siteUrl: _siteUrl),
          _expectedAppearance(),
        );
      },
    );
  }

  // Opt-in scheduling evidence, not a device frame-time benchmark. Fixture
  // generation and result checks stay outside the measured refresh. The
  // largest 1 ms timer gap includes VM/host scheduling noise and approximates
  // event-loop blocking; total includes network mocks and worker startup.
  // flutter test test/site_appearance_background_test.dart \
  //   --dart-define=SITE_APPEARANCE_SCHEDULING_BENCHMARK=true \
  //   --plain-name 'appearance refresh scheduling benchmark' --reporter expanded
  if (const bool.fromEnvironment('SITE_APPEARANCE_SCHEDULING_BENCHMARK')) {
    test('appearance refresh scheduling benchmark', () async {
      for (final entry in {
        'small': _responses(),
        'JSON 128 KB': _responses(jsonPadding: 128 * 1024),
        'HTML 140 KB': _responses(htmlRows: 1024),
        'CSS 1024 rules': _responses(cssRules: 1024),
        'combined': _responses(
          jsonPadding: 128 * 1024,
          htmlRows: 1024,
          cssRules: 1024,
        ),
      }.entries) {
        final client = _IsolateUnsafeClient(
          (r) async => entry.value[r.url.path]!,
        );
        addTearDown(client.close);
        final loader = SiteAppearanceLoader(client: client);
        final expected = _expectedAppearance();
        for (var warmup = 0; warmup < 10; warmup++) {
          expect(await loader.load(siteUrl: _siteUrl), expected);
        }
        final samples = <({int total, int gap})>[];
        for (var sample = 0; sample < 15; sample++) {
          final watch = Stopwatch()..start();
          var previous = 0;
          var largestGap = 0;
          void tick() {
            final now = watch.elapsedMicroseconds;
            final gap = now - previous;
            if (gap > largestGap) largestGap = gap;
            previous = now;
          }

          final timer = Timer.periodic(
            const Duration(milliseconds: 1),
            (_) => tick(),
          );
          final SiteAppearance? appearance;
          try {
            appearance = await loader.load(siteUrl: _siteUrl);
            tick();
            watch.stop();
          } finally {
            timer.cancel();
          }
          samples.add((total: watch.elapsedMicroseconds, gap: largestGap));
          expect(appearance, expected);
        }
        final total = samples.map((s) => s.total).toList()..sort();
        final gap = samples.map((s) => s.gap).toList()..sort();
        // ignore: avoid_print
        print(
          '${entry.key}: 10 warmups, 15 samples; median total=${total[7]}us, '
          'median largest event gap=${gap[7]}us; p90 total=${total[13]}us, gap=${gap[13]}us',
        );
      }
    });
  }
}

const _siteUrl = 'https://forum.example';

Future<SiteAppearance?> _load(Map<String, http.Response> responses) async {
  final client = _IsolateUnsafeClient(
    (request) async => responses[request.url.path]!,
  );
  try {
    return await SiteAppearanceLoader(client: client).load(siteUrl: _siteUrl);
  } finally {
    client.close();
  }
}

Matcher _malformedAt(String path) => throwsA(
  isA<SiteAppearanceLoadException>()
      .having((e) => e.failure, 'failure', SiteAppearanceLoadFailure.malformed)
      .having((e) => e.url, 'url', Uri.parse('$_siteUrl$path')),
);

// A callback that accidentally captures the loader/client cannot be sent to
// compute. Successful public results exercise the real native transfer path.
final class _IsolateUnsafeClient extends MockClient {
  _IsolateUnsafeClient(super.handler);

  final _port = RawReceivePort();

  @override
  void close() {
    _port.close();
    super.close();
  }
}

Map<String, http.Response> _responses({
  int jsonPadding = 0,
  int htmlRows = 0,
  int cssRules = 0,
  bool alternate = true,
}) => {
  '/site.json': http.Response(
    jsonEncode({
      'user_themes': [
        {
          'theme_id': 5,
          'default': true,
          'color_scheme_id': 10,
          'dark_color_scheme_id': alternate ? 11 : null,
        },
      ],
      'padding': 'x' * jsonPadding,
    }),
    200,
    headers: {'content-type': 'application/json'},
  ),
  '/color-scheme-stylesheet/10/5.json': http.Response(
    '{"new_href":"/light.css"}',
    200,
  ),
  '/color-scheme-stylesheet/11/5.json': http.Response(
    '{"new_href":"/dark.css"}',
    200,
  ),
  '/': http.Response(_document(htmlRows), 200),
  '/light.css': http.Response(_palette, 200),
  '/dark.css': http.Response(_darkPalette, 200),
  '/theme.css': http.Response(_theme(cssRules), 200),
};

SiteAppearance _expectedAppearance() => SiteAppearance(
  base: parseSiteAppearanceStylesheets([_palette, _theme(0)]),
  alternate: parseSiteAppearanceStylesheets([_darkPalette, _theme(0)]),
);

String _document(int rows) =>
    '''
<html><head><link rel="stylesheet" data-target="common_theme" data-theme-id="5" href="/theme.css"></head><body>
${List.generate(rows, (i) => '<article class="topic"><h2>Topic $i</h2><p>Some synthetic text with <a href="/t/$i">a link</a> and <span>content</span>.</p></article>').join('\n')}
</body></html>
''';

String _theme(int rules) =>
    '''
img.avatar { border-radius: var(--radius); }
:root { --tertiary: #123456 !important; }
${List.generate(rules, (i) => '.component-$i .content > a:hover { color: var(--primary); background: var(--secondary); padding: calc(var(--space) * 2); content: "braces { ; }"; }').join('\n')}
@media (min-width: 1px) {
  :root { --primary: #badbad !important; }
  img.avatar { border-radius: 0 !important; }
}
:root { --tertiary: #abcdef; --radius: calc(var(--space-2) + 2px);
--d-border-radius: var(--radius); --d-hover: oklch(from var(--tertiary) l c h / 0.15); }
.avatar { border-radius: 0; }
.directory img.avatar { border-radius: 0 !important; }
''';

const _palette = '''
:root { --scheme-type: light; --primary: #222; --secondary: #fff;
--tertiary: #08c; --quaternary: #e45735; --header_background: #fff;
--header_primary: #222; --highlight: #ff4; --danger: #c00;
--success: #090; --love: #f68; }
''';

final _darkPalette = _palette
    .replaceFirst('light', 'dark')
    .replaceFirst('--primary: #222', '--primary: #eee')
    .replaceFirst('--secondary: #fff', '--secondary: #111');
