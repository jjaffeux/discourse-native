import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/category_feed.dart';
import 'package:discourse_native/src/plugins/chat/chat_my_threads_view.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/content_reading_lane.dart';
import 'package:discourse_native/src/shell/draft_list.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/groups_page.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/tags_page.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/styleguide/styleguide_chrome.dart';
import 'package:discourse_native/src/styleguide/styleguide_page.dart';
import 'package:discourse_native/src/styleguide/styleguide_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fakes.dart';

/// Offline review entrypoint. Every screen below is a production widget.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // This deliberately test-only executable must never persist account settings.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  final controller = ShellController(
    instanceStore: FakeInstanceStore([
      instance('empty.example', title: 'Local fixture'),
    ]),
    api: FakeDiscourseApi(),
    authenticator: FakeAuthenticator(),
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await controller.load();
  runApp(EmptyReviewApp(controller: controller));
}

class EmptyReviewApp extends StatefulWidget {
  const EmptyReviewApp({super.key, required this.controller});
  final ShellController controller;
  @override
  State<EmptyReviewApp> createState() => _EmptyReviewAppState();
}

class _EmptyReviewAppState extends State<EmptyReviewApp> {
  String _page = 'Styleguide';
  StyleguideTheme _theme = StyleguideTheme.light;
  bool _rtl = false;
  bool _large = false;
  bool _retry = false;
  @override
  void dispose() {
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: _theme.resolve(ThemeData.light()),
    home: ShellScope(
      controller: widget.controller,
      child: ContentAlignmentScope(
        controller: widget.controller.appSettings,
        child: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Wrap(
                  spacing: 4,
                  children: [
                    for (final page in [
                      'Styleguide',
                      'No sites',
                      'Categories',
                      'Category error',
                      'Tags',
                      'Drafts',
                      'Activity',
                      'Groups',
                      'Chat retry',
                    ])
                      StyleguideAction(
                        label: page,
                        selected: _page == page,
                        onPressed: () => setState(() => _page = page),
                      ),
                    StyleguideAction(
                      label: _theme.name,
                      onPressed: () => setState(
                        () => _theme =
                            StyleguideTheme.values[(_theme.index + 1) %
                                StyleguideTheme.values.length],
                      ),
                    ),
                    StyleguideAction(
                      label: 'RTL',
                      selected: _rtl,
                      onPressed: () => setState(() => _rtl = !_rtl),
                    ),
                    StyleguideAction(
                      label: '200%',
                      selected: _large,
                      onPressed: () => setState(() => _large = !_large),
                    ),
                  ],
                ),
                Expanded(
                  child: Builder(
                    builder: (context) => MediaQuery(
                      data: MediaQuery.of(
                        context,
                      ).copyWith(textScaler: TextScaler.linear(_large ? 2 : 1)),
                      child: Directionality(
                        textDirection: _rtl
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: switch (_page) {
                          'No sites' => const EmptyState(),
                          'Categories' => const CategoriesPage(
                            siteUrl: 'https://empty.example',
                            feed: CategoryFeed(loaded: true),
                          ),
                          'Category error' => const CategoriesPage(
                            siteUrl: 'https://empty.example',
                            feed: CategoryFeed(
                              loaded: true,
                              error: 'Local category request failed',
                            ),
                          ),
                          'Tags' => const TagsPage(
                            siteUrl: 'https://empty.example',
                          ),
                          'Drafts' => const DraftListView(
                            siteUrl: 'https://empty.example',
                          ),
                          'Activity' => const UserActivityView(
                            siteUrl: 'https://empty.example',
                          ),
                          'Groups' => const GroupsPage(
                            siteUrl: 'https://empty.example',
                            data: GroupsPageData(loaded: true),
                          ),
                          'Chat retry' => ChatThreadListMessage(
                            icon: DIcons.comments,
                            message: _retry
                                ? 'No threads yet.'
                                : 'Local request failed.',
                            action: _retry ? null : 'Try again',
                            onAction: () => setState(() => _retry = true),
                          ),
                          _ => const ComponentStyleguidePage(),
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
