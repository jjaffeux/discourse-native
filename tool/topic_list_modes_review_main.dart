import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/app_settings_store.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_registry.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugins/assign/assign_module.dart';
import 'package:discourse_native/src/plugins/assign/assign_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_module.dart';
import 'package:discourse_native/src/plugins/discourse_events/discourse_events_plugin.dart';
import 'package:discourse_native/src/plugins/discourse_events/event_data.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/app_settings_page.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline review of Card/Compact settings, event stamps, and assignments.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const user = DiscourseUser(
    id: 7,
    username: 'sam',
    unifiedNewEnabled: true,
    timezone: 'Europe/Paris',
  );
  final site = instance('list-modes-review.invalid').copyWith(
    user: user,
    config: SiteConfig(
      taggingEnabled: true,
      plugins: PluginData.none.withValue(
        eventSettingsKey,
        const EventSettings(enabled: true),
      ),
    ),
  );
  final rows = [
    Topic(
      id: 1,
      title: 'Sales Stage Cross Functional',
      slug: 'everyday-experience',
      categoryId: 1,
      postsCount: 25,
      lastPosterUsername: 'sam',
      unreadPosts: 4,
      tags: const [TopicTag(name: 'design')],
      excerpt:
          'Align on sales stages, handoffs, and our shared priorities for the next quarter.',
      plugins: const PluginRegistry([AssignPlugin(), EventTopicPlugin()])
          .readTopic(const {
            'event_starts_at': '2026-10-14T20:00:00+02:00',
            'event_ends_at': '2026-10-14T21:00:00+02:00',
            'event_timezone': 'Europe/Paris',
            'assigned_to_user': {'username': 'joffrey'},
            'indirectly_assigned_to': {
              '108': {
                'post_number': 8,
                'assigned_to': {'name': 'design'},
              },
            },
          }, site.url),
    ),
    Topic(
      id: 2,
      title: 'Community planning day',
      slug: 'smaller-screens',
      plugins: const PluginRegistry([AssignPlugin(), EventTopicPlugin()])
          .readTopic(const {
            'event_starts_at': '2026-10-16',
            'event_all_day': true,
            'assigned_to_group': {'name': 'design'},
          }, site.url),
      categoryId: 2,
      postsCount: 19,
      lastPosterUsername: 'hannah',
      seen: false,
      tags: const [
        TopicTag(name: 'design'),
        TopicTag(name: 'mobile'),
      ],
      excerpt:
          'An all-day gathering to plan what comes next for our community.',
    ),
    Topic(
      id: 3,
      title: 'Team offsite: product and design',
      plugins: const PluginRegistry([EventTopicPlugin()]).readTopic(const {
        'event_starts_at': '2026-10-22T09:00:00+02:00',
        'event_ends_at': '2026-10-23T17:00:00+02:00',
        'event_timezone': 'Europe/Paris',
      }, site.url),
      slug: 'building-this-week',
      categoryId: 1,
      postsCount: 43,
      lastPosterUsername: 'mei',
      lastReadPostNumber: 43,
      highestPostNumber: 43,
      excerpt: 'Two days together to shape the next chapter of the product.',
    ),
    const Topic(
      id: 4,
      title: 'Category permissions for growing communities',
      slug: 'category-permissions',
      categoryId: 3,
      postsCount: 8,
      lastPosterUsername: 'robin',
      lastReadPostNumber: 8,
      highestPostNumber: 8,
    ),
  ];
  final shell = ShellController(
    appSettingsStore: AppSettingsStore(
      persistence: MemoryAppSettingsPersistence(topicListMode: 'compact'),
    ),
    plugins: PluginInstaller.install(
      const PluginManifest([assignModule, discourseEventsModule]),
    ),
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: user,
      creatableFeedPaths: const {'/latest.json', '/new.json'},
      feeds: {
        '/latest.json': rows,
        '/latest.json?search=layout': [rows[1]],
        '/latest.json?search=missing': const [],
        '/new.json': rows,
        '/new.json?subset=topics': [rows[0], rows[2]],
        '/new.json?subset=replies': [rows[1], rows[3]],
        '/top.json?period=yearly': rows,
        '/hot.json': rows,
        '/new.json?category=3': [rows[3]],
        '/new.json?category=4': [rows[3]],
        '/c/support/3.json': [rows[3]],
        '/c/support/installation/4.json': [rows[3]],
      },
      categoryList: const [
        TopicCategory(
          id: 1,
          name: 'Community',
          slug: 'community',
          color: 'A787CB',
        ),
        TopicCategory(id: 2, name: 'UX', slug: 'ux', color: '53A7C5'),
        TopicCategory(id: 3, name: 'Support', slug: 'support', color: 'DFB567'),
        TopicCategory(
          id: 4,
          parentCategoryId: 3,
          name: 'Installation',
          slug: 'installation',
          color: 'DFB567',
        ),
      ],
      categorySiteTopTags: const [
        SidebarTag(id: 1, name: 'design', slug: 'design'),
        SidebarTag(id: 2, name: 'feedback', slug: 'feedback'),
      ],
      trackingState: TopicTrackingState([
        for (var i = 0; i < 83; i++)
          TrackedTopicState(
            topicId: 1000 + i,
            highestPostNumber: 1,
            createdInNewPeriod: true,
          ),
        for (var i = 0; i < 52; i++)
          TrackedTopicState(
            topicId: 2000 + i,
            highestPostNumber: 2,
            lastReadPostNumber: 1,
            notificationLevel: 2,
          ),
      ]),
    ),
    authenticator: FakeAuthenticator()..keys[site.url] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: false,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  for (final topic in rows) {
    shell.store.put(site.url, topic);
  }
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  runApp(_Review(shell: shell));
}

class _Review extends StatefulWidget {
  const _Review({required this.shell});
  final ShellController shell;
  @override
  State<_Review> createState() => _ReviewState();
}

class _ReviewState extends State<_Review> {
  var _dark = false;
  var _narrow = false;
  var _large = false;
  var _rtl = false;

  @override
  void dispose() {
    widget.shell.dispose();
    unawaited(widget.shell.plugins.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ShellScope(
    controller: widget.shell,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _dark ? AppTheme.dark : AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    DButton(
                      label: const Text('Settings'),
                      onPressed: () => showAppSettingsModal(context),
                    ),
                    DButton(
                      label: const Text('Card'),
                      onPressed: () => widget.shell.appSettings
                          .setTopicListMode(TopicListDisplayMode.card),
                    ),
                    DButton(
                      label: const Text('Compact'),
                      onPressed: () => widget.shell.appSettings
                          .setTopicListMode(TopicListDisplayMode.compact),
                    ),
                    DButton(
                      label: Text(_narrow ? 'Wide pane' : '390px pane'),
                      onPressed: () => setState(() => _narrow = !_narrow),
                    ),
                    DButton(
                      label: Text(_dark ? 'Light theme' : 'Dark theme'),
                      onPressed: () => setState(() => _dark = !_dark),
                    ),
                    DButton(
                      label: Text(_large ? '100% text' : '200% text'),
                      onPressed: () => setState(() => _large = !_large),
                    ),
                    DButton(
                      label: Text(_rtl ? 'LTR' : 'RTL'),
                      onPressed: () => setState(() => _rtl = !_rtl),
                    ),
                    DButton(
                      label: const Text('Styleguide'),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ComponentStyleguidePage(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: _narrow ? 390 : 1120,
                    child: LayoutBuilder(
                      builder: (context, constraints) => MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          textScaler: TextScaler.linear(_large ? 2 : 1),
                        ),
                        child: Directionality(
                          textDirection: _rtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                          child: Navigator(
                            onGenerateRoute: (_) => MaterialPageRoute<void>(
                              builder: (_) => const MainContent(
                                layout: ShellLayout.expanded,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
