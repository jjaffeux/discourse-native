import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/diagnostics/diagnostics.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import 'fakes.dart';

Future<ShellController> topicListScrollController({
  int count = 500,
  TopicListDisplayMode mode = TopicListDisplayMode.card,
  bool events = false,
  bool assignments = false,
}) async {
  const user = DiscourseUser(id: 7, username: 'sam', timezone: 'Europe/Paris');
  final site = instance('scroll.example').copyWith(
    user: user,
    config: SiteConfig(
      plugins: PluginData.none.withValue(
        eventSettingsKey,
        const EventSettings(enabled: true),
      ),
    ),
  );
  const registry = PluginRegistry([AssignPlugin(), EventTopicPlugin()]);
  final controller = ShellController(
    plugins: PluginInstaller.install(
      const PluginManifest([assignModule, discourseEventsModule]),
    ),
    appSettingsStore: AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(topicListMode: mode.name),
    ),
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': [
          for (var id = 1; id <= count; id++)
            Topic(
              id: id,
              title: id.isEven
                  ? 'Topic $id with a longer title that can wrap onto a second line'
                  : 'Topic $id',
              slug: 'topic-$id',
              categoryId: 2,
              tags: const [
                TopicTag(name: 'performance'),
                TopicTag(name: 'support'),
              ],
              views: id * 10,
              postsCount: id % 30 + 1,
              replyCount: id % 30,
              lastPosterUsername: 'sam',
              bumpedAt: DateTime.utc(2026, 9, 1),
              closed: id % 7 == 0,
              bookmarked: id % 11 == 0,
              plugins: registry.readTopic({
                if (events && id % 3 != 0) ...{
                  'event_starts_at': '2026-10-14T20:00:00+02:00',
                  'event_ends_at': '2026-10-14T21:00:00+02:00',
                  'event_timezone': 'Europe/Paris',
                },
                if (assignments && id.isOdd) ...{
                  'can_assign': false,
                  'assigned_to_user': {'username': 'joffrey'},
                  if (id % 5 == 0)
                    'indirectly_assigned_to': {
                      '108': {
                        'post_number': 8,
                        'assigned_to': {'name': 'design'},
                      },
                    },
                },
              }, site.url),
            ),
        ],
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'General', color: '0088CC'),
        TopicCategory(
          id: 2,
          name: 'Development',
          color: '00AA88',
          parentCategoryId: 1,
        ),
      ],
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'key',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await controller.load();
  await controller.loadFeed('latest');
  final feed = controller.currentFeed!;
  if (feed.topicIds.length != count ||
      feed.topicIds.any(
        (id) =>
            controller.store.read<Topic>(controller.currentInstance!.url, id) ==
            null,
      )) {
    throw StateError('The scroll fixture must retain all requested topics.');
  }
  return controller;
}

class TopicListScrollFixture extends StatelessWidget {
  const TopicListScrollFixture({
    super.key,
    required this.controller,
    required this.diagnostics,
    this.listKey,
    this.width = 800,
  });

  final ShellController controller;
  final DiagnosticsController diagnostics;
  final GlobalKey? listKey;
  final double width;

  @override
  Widget build(BuildContext context) => DiagnosticsScope(
    controller: diagnostics,
    child: ShellScope(
      controller: controller,
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 600,
              child: TopicListView(key: listKey, feed: controller.currentFeed!),
            ),
          ),
        ),
      ),
    ),
  );
}
