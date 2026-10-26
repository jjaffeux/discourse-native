import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a colour comes back from Oklab within a channel step', () {
    for (final color in [
      Colors.white,
      Colors.black,
      const Color(0xFF3188CC),
      const Color(0xFF8B1E1E),
      const Color(0xFF777777),
      const Color(0xFFF2E8C4),
    ]) {
      final back = Oklab.of(color).toColor();
      expect(back.a, 1);
      expect(back.r, closeTo(color.r, 1 / 255), reason: '$color');
      expect(back.g, closeTo(color.g, 1 / 255), reason: '$color');
      expect(back.b, closeTo(color.b, 1 / 255), reason: '$color');
    }
    expect(Oklab.of(Colors.white).lightness, closeTo(1, .001));
    expect(Oklab.of(Colors.black).lightness, closeTo(0, .001));
  });

  test('a lightness step keeps chroma and hue', () {
    final base = Oklab.of(const Color(0xFF3188CC));
    final stepped = Oklab.of(
      base.withLightness(base.lightness - .08).toColor(),
    );
    expect(stepped.lightness, closeTo(base.lightness - .08, .005));
    expect(stepped.a, closeTo(base.a, .005));
    expect(stepped.b, closeTo(base.b, .005));
  });

  test('the well fill is the background one Oklch step darker', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final tokens = theme.extension<DTokens>() ?? DTokens.fromTheme(theme);
      final base = Oklab.of(tokens.background);
      final well = Oklab.of(tokens.wellFill);
      expect(tokens.wellFill.a, 1);
      expect(well.lightness, closeTo(base.lightness - .08, .005));
      expect(well.a, closeTo(base.a, .005));
      expect(well.b, closeTo(base.b, .005));
    }
  });
}
