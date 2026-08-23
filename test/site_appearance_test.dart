import 'dart:convert';
import 'dart:ui';

import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SiteAppearance storage', () {
    test('round trips with value equality', () {
      final appearance = SiteAppearance(
        base: palette(),
        alternate: palette(brightness: Brightness.dark, offset: 40),
        mode: SiteAppearanceMode.alternate,
      );

      final decoded = SiteAppearance.fromJson(
        jsonDecode(jsonEncode(appearance.toJson())) as Map<String, dynamic>,
      );

      expect(decoded, appearance);
      expect(decoded.hashCode, appearance.hashCode);
      expect(decoded.isKnown, isTrue);
    });

    test('reads a snapshot from before appearance existed', () {
      expect(SiteAppearance.fromJson(const {}), const SiteAppearance.unknown());
      expect(const SiteAppearance.unknown().isKnown, isFalse);
    });

    test('accepts legacy light and dark field names and defaults the mode', () {
      final decoded = SiteAppearance.fromJson({
        'light': palette().toJson(),
        'dark': palette(brightness: Brightness.dark, offset: 40).toJson(),
        'mode': 'a-future-mode',
      });

      expect(decoded.base, palette());
      expect(decoded.alternate?.brightness, Brightness.dark);
      expect(decoded.mode, SiteAppearanceMode.followSystem);
    });

    test('maps the legacy persisted system mode to followSystem', () {
      final decoded = SiteAppearance.fromJson(const {'mode': 'system'});

      expect(decoded.mode, SiteAppearanceMode.followSystem);
      expect(decoded.toJson()['mode'], 'followSystem');
    });

    test('keeps a usable palette when its sibling is damaged', () {
      final decoded = SiteAppearance.fromJson({
        'base': const {'primary': 'not-a-color'},
        'alternate': palette(brightness: Brightness.dark).toJson(),
        'mode': 'alternate',
      });

      expect(decoded.base, isNull);
      expect(decoded.alternate, palette(brightness: Brightness.dark));
      expect(decoded.mode, SiteAppearanceMode.alternate);
    });
  });

  test('ResolvedSitePalette derives fields absent from an older snapshot', () {
    final palette = ResolvedSitePalette.fromJson(const {
      'primary': 0xFF111111,
      'secondary': 0xFFFFFFFF,
      'tertiary': 0xFF0088CC,
    });

    expect(palette.brightness, Brightness.light);
    expect(palette.borderRadius, defaultDiscourseBorderRadius);
    expect(palette.quaternary, const Color(0xFF0088CC));
    expect(palette.accentSubtle, palette.tertiary);
    expect(palette.headerBackground, const Color(0xFFFFFFFF));
    expect(palette.primaryLow, const Color(0xFFFFFFFF));
    expect(palette.metadataColor, palette.primaryHigh);
    expect(palette.contentBorderColor, palette.primaryLow);
    expect(palette.selectedForeground, palette.primary);
    expect(palette.mentionBackground, palette.primaryLow);
    expect(palette.codeKeyword, palette.tertiary);
  });

  test('ResolvedSitePalette persists a theme border radius', () {
    final json = palette().toJson()..['borderRadius'] = 11.5;
    final decoded = ResolvedSitePalette.fromJson(json);

    expect(decoded.borderRadius, 11.5);
    expect(decoded.toJson()['borderRadius'], 11.5);
  });

  test('ResolvedSitePalette accepts bounded decimal and hex color text', () {
    final json = palette().toJson()
      ..['primary'] = '4294967295'
      ..['secondary'] = '-2147483648'
      ..['tertiary'] = ' #123456 '
      ..['quaternary'] = '#12345678';

    final decoded = ResolvedSitePalette.fromJson(json);

    expect(decoded.primary, const Color(0xFFFFFFFF));
    expect(decoded.secondary, const Color(0x80000000));
    expect(decoded.tertiary, const Color(0xFF123456));
    expect(decoded.quaternary, const Color(0x12345678));
  });

  test('ResolvedSitePalette reads all-digit six-char color text as hex', () {
    final json = palette().toJson()..['primary'] = '222222';

    expect(ResolvedSitePalette.fromJson(json).primary, const Color(0xFF222222));
  });

  test('ResolvedSitePalette rejects oversized color text before parsing', () {
    final oversized = List.filled(200000, '9').join();
    final optional = palette().toJson()..['quaternary'] = oversized;
    final required = palette().toJson()..['primary'] = oversized;

    final decoded = ResolvedSitePalette.fromJson(optional);

    expect(decoded.quaternary, decoded.tertiary);
    expect(
      SiteAppearance.fromJson({
        'base': required,
        'alternate': palette(brightness: Brightness.dark).toJson(),
      }),
      SiteAppearance(alternate: palette(brightness: Brightness.dark)),
    );
  });
}

ResolvedSitePalette palette({
  Brightness brightness = Brightness.light,
  int offset = 0,
}) {
  Color color(int value) => Color(0xFF000000 | (value + offset));
  return ResolvedSitePalette(
    brightness: brightness,
    primary: color(1),
    secondary: color(2),
    tertiary: color(3),
    quaternary: color(4),
    headerBackground: color(5),
    headerPrimary: color(6),
    metadataColor: color(7),
    contentBorderColor: color(8),
    highlight: color(9),
    danger: color(10),
    success: color(11),
    love: color(12),
    selected: color(13),
    selectedForeground: color(14),
    hover: color(15),
    primaryVeryLow: color(16),
    primaryLow: color(17),
    primaryLowMid: color(18),
    primaryMedium: color(19),
    primaryHigh: color(20),
    primaryVeryHigh: color(21),
    secondaryVeryHigh: color(22),
    tertiaryLow: color(23),
    quaternaryLow: color(24),
    highlightLow: color(25),
    dangerLow: color(26),
    mentionBackground: color(27),
    codeBlockBackground: color(28),
    inlineCodeBackground: color(29),
    codeKeyword: color(30),
    codeString: color(31),
    codeComment: color(32),
    codeNumber: color(33),
    codeName: color(34),
    codeMeta: color(35),
    accentSubtle: color(36),
  );
}
