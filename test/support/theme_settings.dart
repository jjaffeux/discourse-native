import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/forum_settings_page.dart';
import 'package:discourse_native/src/shell/forum_theme_surfaces.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

const _site = 'https://a.example';

ShellController controller({
  Iterable<DiscourseInstance> instances = const [],
}) => ShellController(
  instanceStore: FakeInstanceStore(instances),
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
  double panelWidth = 620,
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
      child: ContentSettingsScope(
        controller: shell.appSettings,
        child: ListenableBuilder(
          listenable: shell.forumSettings,
          builder: (context, _) {
            final mode = shell.forumSettings.themeModeFor(_site);
            final brightness =
                shell.forumSettings.previewBrightnessFor(_site) ??
                (mode == AppThemeMode.dark
                    ? Brightness.dark
                    : Brightness.light);
            final font = shell.forumSettings.shared.font;
            final palette = shell.forumSettings
                .appearanceFor(_site, null)
                ?.paletteForBrightness(brightness);
            final theme = palette == null
                ? AppTheme.forBrightness(brightness, fontFamily: font.family)
                : AppTheme.fromPalette(palette, fontFamily: font.family);
            return MaterialApp(
              theme: theme.copyWith(platform: platform),
              // The app hosts toasts above every page.
              builder: (context, child) => DToaster(
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: Directionality(
                    textDirection: direction,
                    child: child!,
                  ),
                ),
              ),
              home: ForumWindowBackground(
                child: Scaffold(
                  body: Center(
                    child: SizedBox(
                      width: panelWidth,
                      child: const ForumSettingsPage(siteUrl: _site),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Themes'));
  await tester.pumpAndSettle();
}
