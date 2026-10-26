import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview palettes retain the platform', () {
    for (final platform in TargetPlatform.values) {
      final current = AppTheme.light.copyWith(platform: platform);
      expect(StyleguideTheme.current.resolve(current), same(current));
      for (final preview in StyleguideTheme.values.where(
        (value) => value != StyleguideTheme.current,
      )) {
        final theme = preview.resolve(current);
        expect(theme.platform, platform);
      }
    }
  });
}
