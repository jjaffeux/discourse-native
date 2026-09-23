// Local-data fixture for the production mobile topic reader.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_theme_preferences.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const site = 'https://mobile-topic.invalid';
  const user = DiscourseUser(id: 7, username: 'reviewer', canCreateTopic: true);
  const title = 'Show & tell: houseplant shelfie thread';
  const topic = Topic(id: 7, title: title, slug: 'shelfie');
  final settings = ForumSettingsStore.memory();
  await settings.writeThemes(
    site,
    ForumThemePreferences(selectedId: 'dracula'),
  );
  await settings.writeThemeMode(site, AppThemeMode.dark);
  runApp(
    DiscourseApp(
      initialRootMode: ShellRootMode.forum,
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
      forumSettingsStore: settings,
      store: FakeInstanceStore([
        instance('mobile-topic.invalid', title: 'Dracula').copyWith(user: user),
      ]),
      api: FakeDiscourseApi(
        user: user,
        feeds: const {
          '/latest.json': [topic],
        },
        categoryList: const [
          TopicCategory(id: 1, name: 'plants', color: '2E9CD0'),
        ],
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
        topicTagSearches: const {
          '': TopicTagSearch(tags: [TopicTag(id: 1, name: 'show-and-tell')]),
        },
        topics: {
          7: (
            detail: const TopicDetail(
              id: 7,
              title: title,
              stream: [71, 72, 73, 74],
              postsCount: 4,
              replyCount: 3,
              views: 400,
              categoryId: 1,
              canCreatePost: true,
              canEditTags: true,
              canCloseTopic: true,
              tags: [TopicTag(id: 1, name: 'show-and-tell')],
              participants: [
                TopicParticipant(username: 'mira'),
                TopicParticipant(username: 'solene'),
                TopicParticipant(username: 'theo'),
              ],
            ),
            posts: [
              for (var i = 1; i <= 4; i++)
                Post(
                  id: 70 + i,
                  postNumber: i,
                  username: ['mira', 'solene', 'theo', 'violet'][i - 1],
                  cooked:
                      '<p>Drop your best shelfie below. I finally got my pothos to cascade properly after moving it away from the west window.</p><p>Happy to be told I have this backwards.</p>',
                ),
            ],
          ),
        },
      ),
      authenticator: FakeAuthenticator()..keys[site] = 'local-fixture',
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      forumTabs: FakeForumTabStore(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
}
