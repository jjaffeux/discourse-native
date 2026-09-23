import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'fakes.dart';

const _site = 'https://a.example';

ShellController controller() => ShellController(
  instanceStore: FakeInstanceStore(),
  api: FakeDiscourseApi(),
  authenticator: FakeAuthenticator(),
  drafts: FakeDraftStore(),
  trackers: FakeSiteTracker.reset(),
  updateStore: FakeUpdateStore(),
  forumSettingsStore: ForumSettingsStore.memory(),
);

Future<void> pumpSettings(
  WidgetTester tester,
  ShellController shell, {
  double width = 960,
  double scale = 1,
  TargetPlatform platform = TargetPlatform.macOS,
  TextDirection direction = TextDirection.ltr,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ShellScope(
      controller: shell,
      child: ListenableBuilder(
        listenable: shell.forumSettings,
        builder: (context, _) {
          final mode = shell.forumSettings.themeModeFor(_site);
          final brightness = mode == AppThemeMode.dark
              ? Brightness.dark
              : Brightness.light;
          final preferences = shell.forumSettings.themesFor(_site);
          final palette = shell.forumSettings
              .appearanceFor(_site, null)
              ?.paletteForBrightness(brightness);
          final theme = palette == null
              ? AppTheme.forBrightness(brightness)
              : AppTheme.fromPalette(
                  palette,
                  fontFamily: preferences.effectiveFont.family,
                );
          return MaterialApp(
            theme: theme.copyWith(platform: platform),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: Directionality(textDirection: direction, child: child!),
            ),
            home: const ForumWindowBackground(
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 620,
                    child: ForumSettingsPage(siteUrl: _site),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}
