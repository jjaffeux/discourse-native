import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
      testWidgets(
        'full settings supports narrow RTL large text in $brightness $platform',
        (tester) async {
          final shell = controller();
          addTearDown(shell.dispose);
          await shell.forumSettings.setThemeMode(
            'https://a.example',
            brightness == Brightness.light
                ? AppThemeMode.light
                : AppThemeMode.dark,
          );
          final semantics = tester.ensureSemantics();

          await pumpSettings(
            tester,
            shell,
            width: 360,
            scale: 2,
            platform: platform,
            direction: TextDirection.rtl,
          );
          expect(find.byType(DDialogContent), findsNothing);
          expect(find.byType(DSheetContent), findsNothing);
          expect(tester.takeException(), isNull);
          final font = find.byKey(const ValueKey('appearance-font-lato'));
          await tester.ensureVisible(font);
          await tester.tap(font);
          await tester.pumpAndSettle();
          expect(
            shell.forumSettings.themesFor('https://a.example').font,
            ForumFont.lato,
          );
          expect(tester.widget<DItem>(font).selected, isTrue);
          for (final option in ForumFont.values) {
            final row = find.byKey(ValueKey('appearance-font-${option.name}'));
            final sample = tester.widget<Text>(
              find.descendant(
                of: row,
                matching: find.text(
                  'The quick brown fox jumps over the lazy dog.',
                ),
              ),
            );
            expect(
              sample.style!.fontFamily,
              option.family ??
                  ThemeData(platform: platform).textTheme.bodyLarge!.fontFamily,
            );
            expect(
              sample.style!.fontFamilyFallback,
              forumFontFamilyFallback(option.family) ?? const [],
            );
          }
          expect(tester.takeException(), isNull);
          semantics.dispose();
        },
      );
    }
  }
}
