import 'dart:math';
import 'dart:ui';

import 'package:discourse_native/src/foundation/palette_contrast.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/site_appearance.dart';
import 'package:flutter_test/flutter_test.dart';

// Every surface a resolved palette sets text on, and every level of text.
List<(String, Color)> _surfaces(ResolvedSitePalette p) => [
  ('ground', p.secondary),
  ('panel', p.primaryVeryLow),
  ('header', p.headerBackground),
  ('hover', p.hover),
  ('floating', p.secondaryVeryHigh),
  ('raised', p.primaryLow),
  ('selected', p.selected),
  ('code block', p.codeBlockBackground),
  ('inline code', p.inlineCodeBackground),
];

List<(String, Color)> _texts(ResolvedSitePalette p) => [
  ('body', p.primaryVeryHigh),
  ('metadata', p.metadataColor),
  ('medium', p.primaryMedium),
  ('comment', p.codeComment),
  ('accent', p.tertiary),
  ('code string', p.codeString),
  ('code number', p.codeNumber),
];

List<(String, Color)> _fills(ResolvedSitePalette p) => [
  ('accent fill', p.tertiaryLow),
  ('highlight fill', p.quaternaryLow),
  ('danger fill', p.dangerLow),
  ('mention', p.mentionBackground),
  ('your mention', p.currentUserMentionBackground),
];

void main() {
  test('every preset reads at WCAG AA in both modes, plain and tinted', () {
    for (final preset in forumThemePresets) {
      for (final mode in Brightness.values) {
        for (final tint in [0.0, .5, 1.0]) {
          final palette = preset.copyWith(tint: tint).resolve(mode);
          final where = '${preset.id} $mode tint $tint';
          for (final (surface, under) in _surfaces(palette)) {
            for (final (level, text) in [
              ('text', palette.primary),
              ..._texts(palette),
            ]) {
              expect(
                contrastRatio(text, under),
                greaterThanOrEqualTo(textContrast),
                reason: '$where: $level on $surface',
              );
            }
          }
          for (final (fill, under) in _fills(palette)) {
            expect(
              contrastRatio(palette.primary, under),
              greaterThanOrEqualTo(textContrast),
              reason: '$where: text on $fill',
            );
          }
          expect(
            contrastRatio(palette.primaryVeryHigh, palette.secondary),
            greaterThanOrEqualTo(
              min(
                bodyContrast,
                contrastRatio(palette.primary, palette.secondary),
              ),
            ),
            reason: '$where: body text where the palette reaches 7:1',
          );
        }
      }
    }
  });

  test('a level that cannot pass takes all of the text, and no more', () {
    final random = Random(7);
    Color any() => Color.fromARGB(
      255,
      random.nextInt(256),
      random.nextInt(256),
      random.nextInt(256),
    );
    for (var i = 0; i < 300; i++) {
      final ground = any();
      final mode = ground.computeLuminance() > .18
          ? Brightness.light
          : Brightness.dark;
      final palette = ForumTheme(
        id: 'generated',
        name: 'Generated',
        brightness: mode,
        primary: standOut(any(), ground),
        secondary: ground,
        tertiary: any(),
        quaternary: any(),
        danger: any(),
        success: any(),
        love: any(),
        tint: random.nextDouble(),
      ).resolve(mode);
      for (final (surface, under) in _surfaces(palette)) {
        for (final (level, text) in _texts(palette)) {
          expect(
            contrastRatio(text, under) >= textContrast ||
                text == palette.primary,
            isTrue,
            reason: '#$i $level on $surface',
          );
        }
      }
    }
  });

  test('levels keep their reference shares where those already pass', () {
    final wcag = forumThemePresets.firstWhere((t) => t.id == 'wcag');
    final palette = wcag.resolve(Brightness.light);
    Color share(double amount) =>
        Color(Color.lerp(wcag.secondary, wcag.primary, amount)!.toARGB32());
    expect(palette.primaryVeryHigh, share(.90));
    expect(palette.metadataColor, share(.70));
    expect(palette.hover, share(.08));
    expect(palette.primaryLow, share(.12));
    expect(palette.tertiary, wcag.tertiary);
  });

  test('a palette published for one mode gets a readable other half', () {
    for (final preset in forumThemePresets.where((t) => t.alternate == null)) {
      final target = preset.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark;
      final half = preset.forBrightness(target);
      final where = '${preset.id} $target';
      expect(half.brightness, target);
      expect(
        half.secondary.computeLuminance() > half.primary.computeLuminance(),
        target == Brightness.light,
        reason: '$where: ground and text the other way round',
      );
      for (final color in [
        half.primary,
        half.tertiary,
        half.quaternary,
        half.danger,
        half.success,
        half.love,
      ]) {
        expect(
          contrastRatio(color, half.secondary),
          greaterThanOrEqualTo(textContrast),
          reason: where,
        );
      }
    }
  });

  test('standOut moves a colour only as far as it must', () {
    const white = Color(0xffffffff);
    const grey = Color(0xffcccccc);
    final moved = standOut(grey, white);
    expect(contrastRatio(moved, white), greaterThanOrEqualTo(textContrast));
    expect(contrastRatio(moved, white), lessThan(textContrast + .15));
    expect(moved.computeLuminance(), lessThan(grey.computeLuminance()));
    const ink = Color(0xff222222);
    expect(standOut(ink, white), ink);
  });
}
