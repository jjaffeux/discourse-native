import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../test/support/fakes.dart';

// Offline fixture mounting the real toolbar, taxonomy selectors and feed rows.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const user = DiscourseUser(id: 7, username: 'sam', unifiedNewEnabled: true);
  final site = instance(
    'toolbar-review.invalid',
  ).copyWith(user: user, config: const SiteConfig(taggingEnabled: true));
  const rows = [
    Topic(
      id: 1,
      title: 'What would make your everyday Discourse experience better?',
      slug: 'everyday-experience',
      categoryId: 1,
      postsCount: 25,
    ),
    Topic(
      id: 2,
      title: 'A simpler way to browse topics on smaller screens',
      slug: 'smaller-screens',
      categoryId: 2,
      postsCount: 19,
    ),
    Topic(
      id: 3,
      title: 'Share what you have been building this week',
      slug: 'building-this-week',
      categoryId: 1,
      postsCount: 43,
    ),
    Topic(
      id: 4,
      title: 'Category permissions for growing communities',
      slug: 'category-permissions',
      categoryId: 3,
      postsCount: 8,
    ),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: FakeDiscourseApi(
      user: user,
      creatableFeedPaths: const {'/latest.json', '/new.json'},
      feeds: {
        '/latest.json': rows,
        '/new.json': rows,
        '/new.json?subset=topics': [rows[0], rows[2]],
        '/new.json?subset=replies': [rows[1], rows[3]],
        '/top.json?period=yearly': rows,
        '/hot.json': rows,
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
  await shell.selectTopicListMode(TopicListMode.newActivity);
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
  var _dark = true;
  var _narrow = false;
  var _large = false;
  var _rtl = false;

  @override
  void dispose() {
    widget.shell.dispose();
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
