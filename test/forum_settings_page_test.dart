import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/forum_font.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/mobile_shell.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';
import 'support/shell_test_harness.dart';
import 'support/theme_settings.dart';

void main() {
  for (final (bottom, scale) in [(0.0, 1.0), (34.0, 1.0), (34.0, 2.0)]) {
    testWidgets(
      'mobile settings clear the dock at the scroll end ($bottom, $scale)',
      (tester) async {
        tester.view.padding = FakeViewPadding(top: 44, bottom: bottom);
        tester.view.viewPadding = FakeViewPadding(top: 44, bottom: bottom);
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpShell(tester, phone, instances: [instance('a.example')]);
        final shell = ShellScope.read(
          tester.element(find.byType(MobileForumRoot)),
        );
        shell.openCurrentSettings();
        await tester.pumpAndSettle();

        final page = find.byType(ForumSettingsPage);
        final dock = find.byKey(const ValueKey('mobile-bottom-bar'));
        Future<void> scrollToEnd(Finder control) async {
          final scrollable = find
              .ancestor(of: control, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(scrollable).position;
          position.jumpTo(position.maxScrollExtent);
          DScrollChrome.maybeOf(tester.element(page))!.reveal();
          await tester.pumpAndSettle();
          expect(position.pixels, closeTo(position.maxScrollExtent, .01));
          expect(
            tester.getRect(control).bottom,
            greaterThan(tester.getRect(scrollable).top),
          );
          expect(
            tester.getRect(control).bottom,
            lessThanOrEqualTo(tester.getRect(dock).top - 16),
          );
          expect(tester.takeException(), isNull);
        }

        final rawMarkdown = find.byKey(
          const ValueKey('raw-markdown-composers-switch'),
        );
        await scrollToEnd(rawMarkdown);
        // At large text sizes the row can be taller than the viewport.
        await tester.tapAt(
          tester.getBottomRight(rawMarkdown) - const Offset(16, 16),
        );
        await tester.pumpAndSettle();
        expect(shell.appSettings.rawMarkdownComposers, isTrue);

        await tester.ensureVisible(find.text('Themes'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Themes'));
        await tester.pumpAndSettle();
        await scrollToEnd(find.byKey(const ValueKey('theme-use-everywhere')));

        await tester.ensureVisible(find.text('Accessibility'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Accessibility'));
        await tester.pumpAndSettle();
        final disableGifs = find.byKey(
          const ValueKey('disable-gif-animations-switch'),
        );
        await scrollToEnd(disableGifs);
        await tester.tapAt(
          tester.getBottomRight(disableGifs) - const Offset(16, 16),
        );
        await tester.pumpAndSettle();
        expect(shell.appSettings.disableGifAnimations, isTrue);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.iOS,
        TargetPlatform.android,
      }),
    );
  }

  testWidgets('Display exposes raw Markdown on narrow screens', (tester) async {
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
    final rawMarkdown = find.byKey(
      const ValueKey('raw-markdown-composers-switch'),
    );
    await tester.ensureVisible(rawMarkdown);
    await tester.pumpAndSettle();
    expect(rawMarkdown.hitTestable(), findsOneWidget);
    await tester.tap(rawMarkdown);
    await tester.pumpAndSettle();
    expect(shell.appSettings.rawMarkdownComposers, isTrue);
    expect(tester.widget<DSwitchTile>(rawMarkdown).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Display changes the shared font, icons, and text scale', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();

    final systemFont = find.byKey(
      const ValueKey('display-font-system-reading'),
    );
    expect(tester.widget<DToggle>(systemFont).pressed, isTrue);
    expect(
      tester.getSize(find.byKey(const ValueKey('text-size-decrease'))).height,
      28,
    );
    await tester.tap(find.byKey(const ValueKey('display-font-lato-reading')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.readingFont, ForumFont.lato);
    expect(shell.forumSettings.shared.interfaceFont, ForumFont.system);
    expect(tester.widget<DToggle>(systemFont).pressed, isFalse);
    await tester.tap(
      find.byKey(const ValueKey('display-font-openSans-interface')),
    );
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.interfaceFont, ForumFont.openSans);
    expect(shell.forumSettings.shared.readingFont, ForumFont.lato);
    expect(
      find.byKey(const ValueKey('settings-content-width')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('display-icon-set-lucide')),
    );
    final defaultIcons = find.byKey(
      const ValueKey('display-icon-set-defaultSet'),
    );
    expect(tester.widget<DItem>(defaultIcons).selected, isTrue);
    expect(
      tester.widget<DItem>(defaultIcons).selectionStyle,
      DItemSelectionStyle.tinted,
    );
    final previewIcons = find.descendant(
      of: defaultIcons,
      matching: find.byType(DIcon),
    );
    expect(previewIcons, findsNWidgets(8));
    final centers = [
      for (var index = 0; index < 8; index++)
        tester.getCenter(previewIcons.at(index)),
    ];
    for (var index = 0; index < 4; index++) {
      expect(centers[index].dx, closeTo(centers[index + 4].dx, 0.001));
      expect(centers[index].dy, closeTo(centers[0].dy, 0.001));
      expect(centers[index + 4].dy, closeTo(centers[4].dy, 0.001));
    }
    await tester.tap(find.byKey(const ValueKey('display-icon-set-lucide')));
    await tester.pumpAndSettle();
    expect(shell.forumSettings.shared.iconSet, DIconSet.lucide);
    expect(tester.widget<DItem>(defaultIcons).selected, isFalse);

    await tester.ensureVisible(
      find.byKey(const ValueKey('text-size-increase')),
    );
    await tester.tap(find.byKey(const ValueKey('text-size-increase')));
    await tester.pumpAndSettle();
    expect(shell.appSettings.textScale, AppTextScale.percent105);
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
    expect(find.byKey(const ValueKey('settings-content-width')), findsNothing);
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
