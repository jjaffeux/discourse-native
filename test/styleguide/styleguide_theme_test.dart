import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview palettes retain the platform material policy', () {
    for (final platform in TargetPlatform.values) {
      for (final material in DAppearanceMaterial.values) {
        final current = DMaterialTheme.apply(
          AppTheme.light.copyWith(platform: platform),
          material,
        );
        expect(StyleguideTheme.current.resolve(current), same(current));
        for (final preview in StyleguideTheme.values.where(
          (value) => value != StyleguideTheme.current,
        )) {
          final theme = preview.resolve(current);
          expect(theme.platform, platform);
          expect(
            theme.extension<DMaterialTheme>()!.material,
            platform == TargetPlatform.macOS || platform == TargetPlatform.iOS
                ? DAppearanceMaterial.liquidGlass
                : material,
          );
        }
      }
    }
  });
}
