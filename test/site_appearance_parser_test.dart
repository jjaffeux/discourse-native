import 'dart:ui';

import 'package:discourse_native/src/data/site_appearance_parser.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('discoverSiteThemeStylesheets', () {
    test('finds only the selected parent common stylesheet', () {
      final result = discoverSiteThemeStylesheets(
        '''<html><head>
        <link rel="stylesheet" data-target="common_theme" data-theme-id="264"
              href="/styles/component.css">
        <link rel="stylesheet preload" data-target="common_theme"
              data-theme-id="331" href="styles/meta.css">
        <link rel="stylesheet" data-target="desktop_theme"
              data-theme-id="331" href="styles/desktop.css">
        <link rel="preload" data-target="common_theme" data-theme-id="331"
              href="styles/preload.css">
      </head></html>''',
        documentUrl: Uri.parse('https://forum.example/community/'),
        themeId: 331,
      );

      expect(result, [
        Uri.parse('https://forum.example/community/styles/meta.css'),
      ]);
    });

    test('skips malformed stylesheet hrefs', () {
      expect(
        discoverSiteThemeStylesheets(
          '''<link rel="stylesheet"
          data-target="common_theme" data-theme-id="5" href="%zz">''',
          documentUrl: Uri.parse('https://forum.example/'),
          themeId: 5,
        ),
        isEmpty,
      );
    });
  });

  group('resolveSiteAppearanceSelection', () {
    test('uses the anonymous site default and follows the system', () {
      final result = resolveSiteAppearanceSelection(site: _siteJson());

      expect(
        result,
        const SiteAppearanceSelection(
          themeId: 5,
          baseSchemeId: 10,
          alternateSchemeId: 11,
          mode: SiteAppearanceMode.followSystem,
        ),
      );
    });

    test('uses signed-in theme, schemes, and forced alternate mode', () {
      final result = resolveSiteAppearanceSelection(
        site: _siteJson(),
        user: _userJson(
          themeIds: const [6],
          colorSchemeId: 20,
          darkSchemeId: 21,
          interfaceColorMode: 3,
        ),
      );

      expect(
        result,
        const SiteAppearanceSelection(
          themeId: 6,
          baseSchemeId: 20,
          alternateSchemeId: 21,
          mode: SiteAppearanceMode.alternate,
        ),
      );
    });

    test('mirrors forced base mode', () {
      final result = resolveSiteAppearanceSelection(
        site: _siteJson(),
        user: _userJson(interfaceColorMode: 2),
      );

      expect(result?.mode, SiteAppearanceMode.base);
    });

    test('falls back from unavailable user choices to theme defaults', () {
      final result = resolveSiteAppearanceSelection(
        site: _siteJson(),
        user: _userJson(
          themeIds: const [999],
          colorSchemeId: 999,
          darkSchemeId: 998,
        ),
      );

      expect(
        result,
        const SiteAppearanceSelection(
          themeId: 5,
          baseSchemeId: 10,
          alternateSchemeId: 11,
          mode: SiteAppearanceMode.followSystem,
        ),
      );
    });

    test('a limited theme rejects schemes belonging to another theme', () {
      final result = resolveSiteAppearanceSelection(
        site: _siteJson(),
        user: _userJson(
          themeIds: const [7],
          colorSchemeId: 20,
          darkSchemeId: 21,
        ),
      );

      expect(result?.themeId, 7);
      expect(result?.baseSchemeId, 30);
      expect(result?.alternateSchemeId, 31);
    });

    test('a single scheme is fixed even when dark mode was requested', () {
      final site = _siteJson();
      final themes = site['user_themes']! as List<Object?>;
      themes[0] = {'theme_id': 5, 'default': true, 'color_scheme_id': 10};

      final result = resolveSiteAppearanceSelection(
        site: site,
        user: _userJson(interfaceColorMode: 3),
      );

      expect(result?.alternateSchemeId, isNull);
      expect(result?.mode, SiteAppearanceMode.base);
    });

    test('supports core theme IDs and nullable base scheme IDs', () {
      final result = resolveSiteAppearanceSelection(
        site: {
          'user_themes': [
            {
              'theme_id': '-1',
              'default': true,
              'color_scheme_id': null,
              'dark_color_scheme_id': '13',
            },
          ],
          'user_color_schemes': const <Object?>[],
        },
      );

      expect(result?.themeId, -1);
      expect(result?.baseSchemeId, -1);
      expect(result?.alternateSchemeId, 13);
    });

    test('returns null when modern theme metadata is unavailable', () {
      expect(resolveSiteAppearanceSelection(site: const {}), isNull);
      expect(resolveSiteAppearanceSelection(site: 'not json'), isNull);
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

    test('cascades theme aliases and relative alpha colors', () {
      final palette = parseSiteAppearanceStylesheets([
        _stylesheet({
          '--scheme-type': 'dark',
          '--primary': '#ffffff',
          '--secondary': '#1a1a1a',
          '--tertiary': '#7b5fe2',
          '--d-selected': '#d1f0ff',
          '--d-hover': '#f1ecff',
        }),
        '''@supports (color: lab(from red l 1 1% / calc(alpha + 0.1)))
            and (color: light-dark(red, red)) {
          :root { --d-selected: #badbad; }
        }
        :root {
          --meta-color-surface-accent:
            oklch(from var(--tertiary) l c h / 0.15);
          --d-selected: var(--meta-color-surface-accent);
          --d-hover: var(--meta-color-surface-accent);
        }''',
      ]);

      expect(palette?.selected, const Color(0x267B5FE2));
      expect(palette?.hover, const Color(0x267B5FE2));
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

Map<String, Object?> _siteJson() => {
  'user_themes': <Object?>[
    {
      'theme_id': 5,
      'default': true,
      'color_scheme_id': 10,
      'dark_color_scheme_id': 11,
      'only_theme_color_schemes': false,
    },
    {
      'theme_id': 6,
      'default': false,
      'color_scheme_id': 12,
      'dark_color_scheme_id': 13,
      'only_theme_color_schemes': false,
    },
    {
      'theme_id': 7,
      'default': false,
      'color_scheme_id': 30,
      'dark_color_scheme_id': 31,
      'only_theme_color_schemes': true,
    },
  ],
  'user_color_schemes': <Object?>[
    {'id': 20, 'theme_id': null, 'is_dark': false},
    {'id': 21, 'theme_id': null, 'is_dark': true},
    {'id': 30, 'theme_id': 7, 'is_dark': false},
    {'id': 31, 'theme_id': 7, 'is_dark': true},
  ],
};

Map<String, Object?> _userJson({
  List<int> themeIds = const [5],
  int? colorSchemeId,
  int? darkSchemeId,
  int interfaceColorMode = 1,
}) => {
  'user': {
    'user_option': {
      'theme_ids': themeIds,
      'color_scheme_id': colorSchemeId,
      'dark_scheme_id': darkSchemeId,
      'interface_color_mode': interfaceColorMode,
    },
  },
};

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
