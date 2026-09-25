import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/shell/forum_settings_controller.dart';
import 'package:discourse_native/src/shell/forum_theme_editor.dart';
import 'package:discourse_native/src/shell/forum_theme_thumbnail.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/theme_settings.dart';

const site = 'https://a.example';

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('theme mode and preset apply only to the current forum', (
    tester,
  ) async {
    final shell = controller(
      instances: const [
        DiscourseInstance(url: site, title: 'A'),
        DiscourseInstance(url: 'https://b.example', title: 'B'),
      ],
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpSettings(tester, shell);
    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const ValueKey('appearance-mode')),
        matching: find.text('Dark'),
      ),
    );
    expect(shell.forumSettings.themeModeFor(site), AppThemeMode.dark);
    expect(
      shell.forumSettings.themeModeFor('https://b.example'),
      AppThemeMode.system,
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey(('theme-choice', 'dracula'))),
    );
    expect(shell.forumSettings.themesFor(site).source, ForumThemeSource.preset);
    expect(
      shell.forumSettings.themesFor('https://b.example').source,
      ForumThemeSource.forum,
    );
  });

  testWidgets('new theme opens the editor and saves its own appearance', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tapVisible(tester, find.byKey(const ValueKey('new-theme')));
    expect(find.byType(ForumThemeEditor), findsOneWidget);
    expect(find.byKey(const ValueKey('all-themes')), findsOneWidget);
    final backButton = tester.widget<DButton>(
      find.byKey(const ValueKey('all-themes')),
    );
    expect(backButton.variant, DButtonVariant.inline);
    expect((backButton.icon! as DIcon).icon, DIcons.chevronLeft);
    final thumbnail = find.byKey(const ValueKey('theme-editor-thumbnail'));
    expect(tester.getSize(thumbnail), const Size(34, 34));
    expect(
      tester.getTopLeft(thumbnail).dx,
      greaterThan(
        tester.getTopRight(find.byKey(const ValueKey('all-themes'))).dx,
      ),
    );
    final originalBackground = tester
        .widget<ThemeThumbnail>(thumbnail)
        .theme
        .shell
        .content;
    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('theme-color-background')),
        matching: find.byType(EditableText),
      ),
      '#112233',
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ThemeThumbnail>(thumbnail).theme.shell.content,
      isNot(originalBackground),
    );
    expect(find.byKey(const ValueKey('theme-opacity')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-texture')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-save')), findsOneWidget);
    await tapVisible(tester, find.text('Paper'));
    final name = find.descendant(
      of: find.byKey(const ValueKey('theme-name')),
      matching: find.byType(EditableText),
    );
    await tester.enterText(name, 'My theme');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const ValueKey('theme-save')));
    expect(shell.forumSettings.themesFor(site).customTheme?.name, 'My theme');
    expect(
      shell.forumSettings
          .themesFor(site)
          .customTheme
          ?.forBrightness(Brightness.light)
          .background
          ?.effect,
      ForumBackgroundEffect.paper,
    );
    expect(find.byType(ForumThemeEditor), findsNothing);
  });

  testWidgets('Use on every forum copies the selected theme to Home too', (
    tester,
  ) async {
    final shell = controller(
      instances: const [DiscourseInstance(url: site, title: 'A')],
    );
    addTearDown(shell.dispose);
    await shell.load();
    await pumpSettings(tester, shell);
    await tapVisible(
      tester,
      find.byKey(const ValueKey(('theme-choice', 'wcag'))),
    );
    await tapVisible(
      tester,
      find.byKey(const ValueKey('theme-use-everywhere')),
    );
    expect(
      shell.forumSettings
          .themesFor(ForumSettingsController.homeSite)
          .presetFor(Brightness.light)
          ?.id,
      'wcag',
    );
  });

  testWidgets('Display and Accessibility controls use Native settings', (
    tester,
  ) async {
    final shell = controller();
    addTearDown(shell.dispose);
    await pumpSettings(tester, shell);
    await tapVisible(tester, find.text('Display').first);
    expect(
      find.byKey(const ValueKey('settings-content-width')),
      findsOneWidget,
    );
    await tapVisible(tester, find.text('Normal'));
    expect(shell.appSettings.limitContentSize, isTrue);
    await tapVisible(tester, find.text('Accessibility'));
    expect(find.byType(DSwitchTile), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('disable-gif-animations-switch')),
    );
    expect(shell.appSettings.disableGifAnimations, isTrue);
  });
}
