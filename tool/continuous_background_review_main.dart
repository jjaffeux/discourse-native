// Local-only review of one shared canvas in list, split-reader and preview layouts.
// Switch between the three saved custom themes to inspect Normal, Lava and Noise.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/forum_background.dart';
import 'package:discourse_native/src/models/forum_theme.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/forum_theme_presets.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final forums = ForumSettingsStore.memory();
  final source = forumThemePresets.firstWhere((theme) => theme.id == 'dracula');
  final themes = [
    for (final effect in ForumBackgroundEffect.values)
      ForumTheme.fromJson({
        ...source.toJson(),
        'name': 'Continuous ${effect.name}',
        'background': ForumBackground(
          color: const Color(0xff874ad7),
          strength: .8,
          effect: effect,
        ).toJson(),
      }, id: 'custom-${effect.name}'),
  ];
  await forums.writeThemes(
    'https://dev.example',
    ForumThemePreferences(
      source: ForumThemeSource.custom,
      customId: 'custom-lava',
      customThemes: themes,
    ),
  );
  await forums.writeThemeMode('https://dev.example', AppThemeMode.dark);
  final topics = [
    for (var id = 1; id <= 20; id++)
      Topic(
        id: id,
        title: [
          'A continuous background across the app',
          'Making the topic list easier to scan',
          'Keyboard navigation between discussions',
        ][id % 3],
        slug: 'background-$id',
        replyCount: id,
      ),
  ];
  runApp(
    DiscourseApp(
      store: FakeInstanceStore(const [
        DiscourseInstance(url: 'https://dev.example', title: 'Discourse Dev'),
        DiscourseInstance(url: 'https://community.example', title: 'Community'),
      ]),
      api: FakeDiscourseApi(
        feeds: {'/latest.json': topics},
        topics: {
          for (final topic in topics)
            topic.id: (
              detail: TopicDetail(
                id: topic.id,
                title: topic.title,
                stream: [topic.id * 10],
                postsCount: 1,
              ),
              posts: [
                Post(
                  id: topic.id * 10,
                  postNumber: 1,
                  username: 'reviewer',
                  cooked:
                      '<p>The same canvas continues behind navigation, topic lists, and conversations.</p><p>Background colors and effects should flow through the whole window.</p><p>Resize the topic list or switch between light and dark modes to inspect the result.</p>',
                ),
              ],
            ),
        },
      ),
      authenticator: FakeAuthenticator(),
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
      forumSettingsStore: forums,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
}
