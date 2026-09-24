import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

void main() {
  testWidgets(
    'the forum default has no editing controls or duplicate mode switch',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      expect(
        tester
            .widget<DRadioGroup<AppThemeMode>>(
              find.byKey(const ValueKey('appearance-mode')),
            )
            .groupValue,
        AppThemeMode.system,
      );
      // The font is an app setting, chosen in Settings.
      expect(find.text('Font'), findsNothing);
      expect(find.byKey(const ValueKey('theme-source')), findsNothing);
      expect(
        tester
            .widget<DItem>(
              find.byKey(const ValueKey(('theme-choice', 'forum'))),
            )
            .selected,
        isTrue,
      );
      expect(
        find.byKey(const ValueKey(('customize-theme', 'forum'))),
        findsOneWidget,
      );
      for (final control in ['appearance-theme-select', 'theme-sidebar']) {
        expect(find.byKey(ValueKey(control)), findsNothing, reason: control);
      }
      // Effects apply to every forum, so they live in the app's Settings.
      for (final control in [
        'theme-tint',
        'theme-opacity',
        'theme-texture',
        'theme-intensity',
      ]) {
        expect(find.byKey(ValueKey(control)), findsNothing, reason: control);
      }
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('appearance-mode'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const ValueKey('theme-picker'))).dy,
        ),
      );
      expect(find.byKey(const ValueKey('theme-shown-mode')), findsNothing);
      expect(
        shell.forumSettings.themeModeFor('https://a.example'),
        AppThemeMode.system,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
          semantics.dispose();
        },
      );
    }
  }
}
