// Local fixture for reviewing the production mobile shell without account data.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/data/forum_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/plugins/voice/voice_module.dart';
import 'package:discourse_native/src/plugins/voice/voice_settings.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/bundled_plugins.dart';
import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  // This target can also run on macOS for a resizable mobile-layout review.
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  const site = 'https://mobile-review.invalid';
  const secondSite = 'https://second-review.invalid';
  final user = DiscourseUser(
    id: 7,
    username: 'joffrey',
    name: 'Joffrey',
    canCreateTopic: true,
    canSendPrivateMessages: true,
    plugins: PluginData.none.withValue(
      chatCurrentUserDataKey,
      const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
    ),
  );
  final config = SiteConfig(
    taggingEnabled: true,
    plugins: PluginData.none
        .withValue(eventSettingsKey, const EventSettings(enabled: true))
        .withValue(
          chatSettingsDataKey,
          const ChatSettings(chatEnabled: true, publicChannelsEnabled: true),
        )
        .withValue(
          voiceSettingsDataKey,
          const VoiceClientConfig(enabled: true),
        ),
  );
  final channels = [
    const ChatChannel(
      id: 9,
      title: 'General',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
      tracking: ChatTracking(unreadCount: 12),
      lastMessagePreview: 'What are you working on today?',
    ),
    const ChatChannel(
      id: 10,
      title: 'Design',
      kind: ChatChannelKind.category,
      membership: ChatMembership(following: true),
      lastMessagePreview: 'A little more room for the conversation.',
    ),
    const ChatChannel(
      id: 11,
      title: 'sam',
      kind: ChatChannelKind.directMessage,
      membership: ChatMembership(following: true),
      users: [ChatUser(id: 2, username: 'sam')],
      lastMessagePreview: 'This is looking good!',
    ),
  ];
  final topics = [
    for (final (id, title) in [
      (7, 'What are you working on this week?'),
      (8, 'A calmer reading experience on mobile'),
      (9, 'Share your favourite keyboard setup'),
      (10, 'September community update'),
      (11, 'A little corner for plant lovers'),
      (12, 'What are you reading right now?'),
    ])
      Topic(
        id: id,
        title: title,
        slug: 'topic-$id',
        postsCount: id,
        replyCount: id - 1,
        bumpedAt: DateTime.now().subtract(Duration(hours: id)),
        lastPosterUsername: 'sam',
      ),
  ];
  runApp(
    DiscourseApp(
      store: FakeInstanceStore([
        instance(
          'mobile-review.invalid',
          title: 'Dracula',
        ).copyWith(user: user, config: config),
        instance(
          'second-review.invalid',
          title: 'Discourse Meta',
        ).copyWith(user: user, config: config),
      ]),
      api: FakeDiscourseApi(
        user: user,
        categoryList: const [
          TopicCategory(
            id: 1,
            name: 'General',
            color: 'F6AD55',
            slug: 'general',
          ),
          TopicCategory(id: 2, name: 'Design', color: 'A78BFA', slug: 'design'),
        ],
        customSidebarSectionsBySite: const {
          site: [
            SidebarSection(
              id: 'custom-1',
              title: 'Resources',
              destinations: [
                SidebarDestination(
                  id: 'custom-handbook',
                  label: 'Community handbook',
                  icon: DIcons.bookOpenReader,
                  url: '/t/topic-7/7',
                ),
              ],
            ),
          ],
        },
        totals: chatNotificationTotals(unreadNotifications: 3),
        siteConfigs: {site: config, secondSite: config},
        feeds: {
          '/latest.json': topics,
          '/new.json': topics.take(2).toList(),
          '/unread.json': topics.take(3).toList(),
        },
        topics: {
          for (final topic in topics)
            topic.id: topicPayload(
              id: topic.id,
              title: topic.title,
              posts: [
                Post(
                  id: topic.id * 10,
                  postNumber: 1,
                  username: 'sam',
                  cooked:
                      '<p>Welcome to the conversation. This page uses the same reader and topic cards as the desktop app.</p>',
                ),
              ],
            ),
        },
        chatChannelsBySite: {
          for (final url in [site, secondSite])
            url: ChatChannels(
              public: channels.take(2).toList(),
              direct: [channels.last],
            ),
        },
        chatChannelsById: {for (final channel in channels) channel.id: channel},
        chatMessagesByKey: {
          for (final channel in channels)
            FakeDiscourseApi.chatMessagesKey(channel.id): (
              messages: [
                ChatMessage(
                  id: 1,
                  channelId: channel.id,
                  raw: 'What are you working on today?',
                  cooked: '<p>What are you working on today?</p>',
                  author: const ChatMessageAuthor(id: 2, username: 'sam'),
                  createdAt: DateTime.now(),
                ),
              ],
              canLoadMorePast: false,
              canLoadMoreFuture: false,
              targetMessageId: null,
            ),
        },
        pluginResponses: const {
          'GET /voice/rooms.json': {
            'rooms': [
              {
                'id': 7,
                'name': 'Watercooler',
                'slug': 'watercooler',
                'room_type': 'conference',
                'active_participants': <Object>[],
              },
            ],
            'can_create_room': true,
          },
        },
      ),
      pluginManifest: PluginManifest([
        ...bundledWidgetTestManifest.modules,
        const VoiceModule.withoutDiagnostics(),
      ]),
      authenticator: FakeAuthenticator()
        ..keys[site] = 'fixture'
        ..keys[secondSite] = 'fixture',
      appSettingsStore: AppSettingsStore(
        persistence: MemoryAppSettingsPersistence(),
      ),
      forumSettingsStore: ForumSettingsStore.memory(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
}
