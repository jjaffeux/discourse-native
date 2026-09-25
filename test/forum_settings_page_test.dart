import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

void main() {
  testWidgets('Display changes the shared font, icons, and text scale', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('display-font-lato')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.font, ForumFont.lato);

    await tester.ensureVisible(
      find.byKey(const ValueKey('display-icon-set-lucide')),
    );
    await tester.tap(find.byKey(const ValueKey('display-icon-set-lucide')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.iconSet, DIconSet.lucide);

    await tester.ensureVisible(
      find.byKey(const ValueKey('text-size-increase')),
    );
    await tester.tap(find.byKey(const ValueKey('text-size-increase')));
    await tester.pumpAndSettle();
    expect(shell.appSettings.textScale, AppTextScale.percent110);
    await tester.tap(find.byKey(const ValueKey('text-size-reset')));
    await tester.pumpAndSettle();
    expect(shell.appSettings.textScale, AppTextScale.percent100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Display remains usable at narrow width with large RTL text', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(
      tester,
      shell,
      width: 360,
      panelWidth: 360,
      scale: 2,
      direction: TextDirection.rtl,
    );
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('display-font-system')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('display-icon-set-tabler')),
    );
    await tester.tap(find.byKey(const ValueKey('display-icon-set-tabler')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.iconSet, DIconSet.tabler);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the forum default has no editing controls or duplicate mode switch',
    (tester) async {
      final shell = controller();
      addTearDown(shell.dispose);
      await pumpSettings(tester, shell);
      expect(
        tester
            .widget<DToggleGroup<AppThemeMode>>(
              find.byKey(const ValueKey('appearance-mode')),
            )
            .values,
        [AppThemeMode.system],
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
      final editButton = tester.widget<DButton>(
        find.byKey(const ValueKey(('edit-theme', 'forum'))),
      );
      expect(editButton.variant, DButtonVariant.outline);
      expect(
        find.byKey(const ValueKey(('theme-actions', 'forum'))),
        findsNothing,
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

  testWidgets('theme pencils appear on hover or for the selected row', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);

    for (final id in [
      'forum',
      for (final preset in forumThemePresetsFor(Brightness.light)) preset.id,
    ]) {
      final pencil = find.byKey(ValueKey(('edit-theme', id)));
      expect(pencil, findsOneWidget);
      expect(tester.widget<DButton>(pencil).variant, DButtonVariant.outline);
      expect(
        tester
            .widget<Opacity>(
              find.byKey(ValueKey(('edit-theme-visibility', id))),
            )
            .opacity,
        id == 'forum' ? 1 : 0,
      );
      expect(find.byKey(ValueKey(('theme-actions', id))), findsNothing);
    }
    expect(find.text('Customize'), findsNothing);

    final presetRow = find.byKey(const ValueKey(('theme-choice', 'wcag')));
    final presetVisibility = find.byKey(
      const ValueKey(('edit-theme-visibility', 'wcag')),
    );
    await tester.ensureVisible(presetRow);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(presetRow));
    await tester.pump();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 1);
    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 0);

    await tester.tap(presetRow);
    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(presetVisibility).opacity, 1);
    await tester.tap(find.byKey(const ValueKey(('edit-theme', 'wcag'))));
    await tester.pumpAndSettle();
    expect(find.byType(ForumThemeEditor), findsOneWidget);
  });

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
