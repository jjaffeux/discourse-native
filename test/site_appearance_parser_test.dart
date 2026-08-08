import 'dart:ui';

import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('discoverSiteAppearanceStylesheets', () {
    final documentUrl = Uri.parse('https://forum.example/community/');

    test('resolves a base stylesheet against the final document URL', () {
      final result = discoverSiteAppearanceStylesheets('''<html><head>
          <link data-x="1" class="extra light-scheme" href="styles/colors.css"
                REL="preload stylesheet" media="all">
        </head></html>''', documentUrl: documentUrl);

      expect(
        result,
        SiteAppearanceStylesheets(
          base: Uri.parse('https://forum.example/community/styles/colors.css'),
          alternate: null,
          mode: SiteAppearanceMode.base,
        ),
      );
    });

    test('accepts single-quoted and unquoted link attributes', () {
      final result = discoverSiteAppearanceStylesheets(
        "<head><link class='light-scheme' rel=stylesheet "
        "href='styles/colors.css'></head>",
        documentUrl: documentUrl,
      );

      expect(
        result?.base,
        Uri.parse('https://forum.example/community/styles/colors.css'),
      );
      expect(result?.mode, SiteAppearanceMode.base);
    });

    test('finds CDN and site-relative hrefs in an automatic pair', () {
      final result = discoverSiteAppearanceStylesheets('''<head>
          <link rel="stylesheet" class="light-scheme"
                media="(prefers-color-scheme: light)"
                href="/community/styles/light.css">
          <link href="//cdn.example/dark.css" class="dark-scheme other"
                media="(prefers-color-scheme: dark)" rel="stylesheet">
        </head>''', documentUrl: documentUrl);

      expect(
        result?.base,
        Uri.parse('https://forum.example/community/styles/light.css'),
      );
      expect(result?.alternate, Uri.parse('https://cdn.example/dark.css'));
      expect(result?.mode, SiteAppearanceMode.followSystem);
    });

    test('recognizes legacy automatic media', () {
      final result = discoverSiteAppearanceStylesheets(
        _html(baseMedia: 'all', alternateMedia: '(prefers-color-scheme: dark)'),
        documentUrl: documentUrl,
      );

      expect(result?.mode, SiteAppearanceMode.followSystem);
    });

    test('normalizes whitespace and case in current automatic media', () {
      final result = discoverSiteAppearanceStylesheets(
        _html(
          baseMedia: ' ( PREFERS-COLOR-SCHEME : LIGHT ) ',
          alternateMedia: ' ( prefers-color-scheme : DARK ) ',
        ),
        documentUrl: documentUrl,
      );

      expect(result?.mode, SiteAppearanceMode.followSystem);
    });

    test('recognizes forced base and alternate modes', () {
      final base = discoverSiteAppearanceStylesheets(
        _html(baseMedia: 'all', alternateMedia: 'none'),
        documentUrl: documentUrl,
      );
      final alternate = discoverSiteAppearanceStylesheets(
        _html(baseMedia: 'none', alternateMedia: 'all'),
        documentUrl: documentUrl,
      );

      expect(base?.mode, SiteAppearanceMode.base);
      expect(alternate?.mode, SiteAppearanceMode.alternate);
    });

    test('skips malformed candidates and non-stylesheet links', () {
      final result = discoverSiteAppearanceStylesheets('''<head>
          <link rel="preload" class="light-scheme" href="ignored.css">
          <link rel="stylesheet" class="light-scheme" href="%zz">
          <link rel="stylesheet" class="light-scheme" href="valid.css">
        </head>''', documentUrl: documentUrl);

      expect(
        result?.base,
        Uri.parse('https://forum.example/community/valid.css'),
      );
    });

    test('returns null without a valid base stylesheet', () {
      expect(
        discoverSiteAppearanceStylesheets(
          '<head><link rel="stylesheet" href="colors.css"></head>',
          documentUrl: documentUrl,
        ),
        isNull,
      );
    });

    test('returns null for ambiguous duplicate scheme links', () {
      expect(
        discoverSiteAppearanceStylesheets('''<head>
          <link rel="stylesheet" class="light-scheme" href="one.css">
          <link rel="stylesheet" class="light-scheme" href="two.css">
        </head>''', documentUrl: documentUrl),
        isNull,
      );
    });

    test('rejects swapped, malformed, and unsupported media pairs', () {
      for (final (baseMedia, alternateMedia) in [
        ('(prefers-color-scheme: dark)', '(prefers-color-scheme: light)'),
        ('all', 'all'),
        ('none', 'none'),
        ('screen', 'print'),
        (
          '(prefers-color-scheme: light) and (min-width: 1px)',
          '(prefers-color-scheme: dark)',
        ),
      ]) {
        expect(
          discoverSiteAppearanceStylesheets(
            _html(baseMedia: baseMedia, alternateMedia: alternateMedia),
            documentUrl: documentUrl,
          ),
          isNull,
          reason: '$baseMedia / $alternateMedia',
        );
      }
    });

    test('keeps a single base link fixed despite unknown media', () {
      final result = discoverSiteAppearanceStylesheets(
        '''<head><link rel="stylesheet" class="light-scheme"
             media="screen and (min-width: 1px)" href="base.css"></head>''',
        documentUrl: documentUrl,
      );

      expect(result?.mode, SiteAppearanceMode.base);
    });
  });

  group('parseSiteAppearanceStylesheet', () {
    test('reads all normalized roles and the scheme type', () {
      final palette = parseSiteAppearanceStylesheet(_stylesheet());

      expect(palette?.brightness, Brightness.light);
      expect(palette?.primary, const Color(0xFF111111));
      expect(palette?.secondary, const Color(0xFFFFFFFF));
      expect(palette?.tertiary, const Color(0xFF0088CC));
      expect(palette?.metadataColor, const Color(0xFF666666));
      expect(palette?.contentBorderColor, const Color(0xFFE1E1E1));
      expect(palette?.selectedForeground, const Color(0xFF0A0A0A));
      expect(palette?.mentionBackground, palette?.primaryLow);
      expect(palette?.codeNumber, const Color(0xFFAA11AA));
      expect(palette?.codeName, const Color(0xFFAA11AA));
      expect(palette?.codeMeta, const Color(0xFF113355));
    });

    test('applies later global root declarations but not scoped rules', () {
      final palette = parseSiteAppearanceStylesheet('''${_stylesheet()}
        @media (min-width: 1px) { :root { --tertiary: #AAAAAA; } }
        :root.theme-preview { --tertiary: #BBBBBB; }
        html:root { --tertiary: #123456; }
        :root { --tertiary: #654321; }
        ''');

      expect(palette?.tertiary, const Color(0xFF654321));
    });

    test('honors important declarations across root rules', () {
      final palette = parseSiteAppearanceStylesheet('''${_stylesheet()}
        :root { --tertiary: #010203 !important; }
        :root { --tertiary: #AABBCC; }
        ''');

      expect(palette?.tertiary, const Color(0xFF010203));
    });

    test('falls back when the newest important color is unsupported', () {
      final palette = parseSiteAppearanceStylesheet('''${_stylesheet()}
        :root { --tertiary: color(display-p3 1 0 0) !important; }
        ''');

      expect(palette?.tertiary, const Color(0xFF0088CC));
    });

    test('keeps an earlier color when a later override is unsupported', () {
      final palette = parseSiteAppearanceStylesheet('''${_stylesheet()}
        :root { --primary: color(display-p3 1 0 0); }
        ''');

      expect(palette?.primary, const Color(0xFF111111));
    });

    test('bounds sibling variable substitutions per candidate', () {
      final aliases = List.filled(80, 'var(--hljs-meta)').join();
      final palette = parseSiteAppearanceStylesheet('''
        ${_stylesheet({'--hljs-meta': '/**/'})}
        :root { --primary: #123456$aliases; }
      ''');

      expect(palette?.primary, const Color(0xFF111111));
    });

    test('bounds expanded variable output per candidate', () {
      final largeNumberFragment = List.filled(1000, '0').join();
      final aliases = List.filled(5, 'var(--hljs-meta)').join();
      final palette = parseSiteAppearanceStylesheet('''
        ${_stylesheet({'--hljs-meta': largeNumberFragment})}
        :root { --primary: rgb(${aliases}1 2 3); }
      ''');

      expect(palette?.primary, const Color(0xFF111111));
    });

    test('caps pathological candidate cascades', () {
      final invalidOverrides = List.filled(
        80,
        '--primary: not-a-color;',
      ).join();
      final palette = parseSiteAppearanceStylesheet('''
        ${_stylesheet({'--primary': 'invalid-oldest'})}
        :root { --primary: #123456; $invalidOverrides }
      ''');

      expect(palette, isNull);
    });

    test('derives optional roles when only core colors are present', () {
      final palette = parseSiteAppearanceStylesheet(''':root {
        --scheme-type: dark;
        --primary: #eeeeee;
        --secondary: #111111;
        --tertiary: #00aaff;
      }''');

      expect(palette, isNotNull);
      expect(palette?.brightness, Brightness.dark);
      expect(palette?.headerBackground, const Color(0xFF111111));
      expect(palette?.metadataColor, palette?.primaryHigh);
      expect(palette?.contentBorderColor, palette?.primaryLow);
      expect(palette?.selectedForeground, palette?.primary);
      expect(palette?.codeKeyword, palette?.tertiary);
    });

    test(
      'resolves aliases, nested fallbacks, and aliases inside functions',
      () {
        final palette = parseSiteAppearanceStylesheet(
          _stylesheet({
            '--primary': 'var(--missing, var(--tertiary))',
            '--mention-background-color': 'var(--primary-low, #010101)',
            '--hljs-bg': 'rgb(var(--missing-rgb, 1 2 3) / 50%)',
          }),
        );

        expect(palette?.primary, const Color(0xFF0088CC));
        expect(palette?.mentionBackground, palette?.primaryLow);
        expect(palette?.codeBlockBackground, const Color(0x80010203));
      },
    );

    test('rejects cyclic aliases even when every name is present', () {
      final palette = parseSiteAppearanceStylesheet(
        _stylesheet({
          '--primary': 'var(--secondary)',
          '--secondary': 'var(--primary)',
        }),
      );

      expect(palette, isNull);
    });

    test('supports CSS hex, functional, and named colors', () {
      final palette = parseSiteAppearanceStylesheet(
        _stylesheet({
          '--primary': '#abc',
          '--secondary': '#11223344',
          '--tertiary': 'rgb(1 2 3 / 50%)',
          '--quaternary': 'rgba(4, 5, 6, .25)',
          '--header_background': 'hsl(120 100% 50%)',
          '--header_primary': 'hsla(240, 100%, 50%, 25%)',
          '--highlight': 'transparent',
          '--danger': 'black',
          '--success': 'white',
          '--love': 'red',
        }),
      );

      expect(palette?.primary, const Color(0xFFAABBCC));
      expect(palette?.secondary, const Color(0x44112233));
      expect(palette?.tertiary, const Color(0x80010203));
      expect(palette?.quaternary, const Color(0x40040506));
      expect(palette?.headerBackground, const Color(0xFF00FF00));
      expect(palette?.headerPrimary, const Color(0x400000FF));
      expect(palette?.highlight, const Color(0x00000000));
      expect(palette?.danger, const Color(0xFF000000));
      expect(palette?.success, const Color(0xFFFFFFFF));
      expect(palette?.love, const Color(0xFFFF0000));
    });

    test('uses dark scheme type even for the base stylesheet role', () {
      final palette = parseSiteAppearanceStylesheet(
        _stylesheet({'--scheme-type': 'dark'}),
      );

      expect(palette?.brightness, Brightness.dark);
    });

    test('rejects missing core roles, bad colors, and missing scheme type', () {
      expect(
        parseSiteAppearanceStylesheet(
          _stylesheet({'--primary': 'not-a-color'}),
        ),
        isNull,
      );
      expect(
        parseSiteAppearanceStylesheet(':root { --scheme-type: light; }'),
        isNull,
      );
      expect(
        parseSiteAppearanceStylesheet(_stylesheet({'--scheme-type': 'sepia'})),
        isNull,
      );
      expect(
        parseSiteAppearanceStylesheet(
          _stylesheet({'--primary': 'rgb(NaN 0 0)'}),
        ),
        isNull,
      );
    });
  });
}

String _html({required String baseMedia, required String alternateMedia}) =>
    '''<head>
      <link rel="stylesheet" class="light-scheme" media="$baseMedia"
            href="light.css">
      <link rel="stylesheet" class="dark-scheme" media="$alternateMedia"
            href="dark.css">
    </head>''';

String _stylesheet([Map<String, String> overrides = const {}]) {
  final values = <String, String>{
    '--scheme-type': 'light',
    '--primary': '#111111',
    '--secondary': '#FFFFFF',
    '--tertiary': '#0088CC',
    '--quaternary': '#E45735',
    '--header_background': '#FFFFFF',
    '--header_primary': '#333333',
    '--metadata-color': '#666666',
    '--content-border-color': '#E1E1E1',
    '--highlight': '#FFFF4D',
    '--danger': '#C80001',
    '--success': '#009900',
    '--love': '#FA6C8D',
    '--d-selected': '#D1F0FF',
    '--d-selected-text-color': '#0A0A0A',
    '--d-hover': '#F2F2F2',
    '--primary-very-low': '#F8F8F8',
    '--primary-low': '#E9E9E9',
    '--primary-low-mid': '#B2B2B2',
    '--primary-medium': '#919191',
    '--primary-high': '#646464',
    '--primary-very-high': '#414141',
    '--secondary-very-high': '#F7F7F7',
    '--tertiary-low': '#D9F2FF',
    '--quaternary-low': '#F6CDC3',
    '--highlight-low': '#FFFFB8',
    '--danger-low': '#F9E6E6',
    '--mention-background-color': 'var(--primary-low)',
    '--hljs-bg': '#F8F8F8',
    '--inline-code-bg': '#F2F2F2',
    '--hljs-keyword': '#7A239A',
    '--hljs-string': '#247A32',
    '--hljs-comment': '#687080',
    '--hljs-title': '#AA11AA',
    '--hljs-meta': '#113355',
    '--hljs-attribute': '#226688',
    ...overrides,
  };
  return ':root{${values.entries.map((e) => '${e.key}:${e.value};').join()}}';
}
