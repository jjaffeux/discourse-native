// Local-data review of forum settings and per-forum theme switching.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final settings = ForumSettingsStore.memory();
  await settings.writeThemes(
    'https://dev.example',
    ForumThemePreferences(
      customThemes: [
        forumThemePresets
            .firstWhere((theme) => theme.id == 'solarized')
            .copyWith(id: 'custom-paper', name: 'Paper'),
        forumThemePresets
            .firstWhere((theme) => theme.id == 'dracula')
            .copyWith(id: 'custom-midnight', name: 'Midnight'),
      ],
    ),
  );
  runApp(
    DiscourseApp(
      store: FakeInstanceStore(const [
        DiscourseInstance(url: 'https://dev.example', title: 'Discourse Dev'),
        DiscourseInstance(url: 'https://community.example', title: 'Community'),
      ]),
      api: FakeDiscourseApi(feeds: const {'/latest.json': []}),
      authenticator: FakeAuthenticator(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
      forumSettingsStore: settings,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
}
