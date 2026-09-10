// Local-only fixture mounting the production docked composer.
// API calls and drafts are in memory; preferences use an isolated prefix.
import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('composer_docking_review.');
  const user = DiscourseUser(
    id: 7,
    username: 'reviewer',
    canCreateTopic: true,
    canSendPrivateMessages: true,
  );
  final topics = [
    for (var id = 1; id <= 20; id++)
      Topic(id: id, title: 'Review topic $id', slug: 'review-topic-$id'),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'first-review.invalid',
        title: 'First review site',
      ).copyWith(user: user),
      instance(
        'second-review.invalid',
        title: 'Second review site',
      ).copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': topics,
        '/topics/private-messages/reviewer.json': topics,
      },
      topics: {
        for (final topic in topics)
          topic.id: (
            detail: TopicDetail(
              id: topic.id,
              title: topic.title,
              stream: [topic.id],
              postsCount: 1,
            ),
            posts: [
              Post(
                id: topic.id,
                postNumber: 1,
                username: 'reviewer',
                cooked: '<p>Local content for inspecting panel boundaries.</p>',
              ),
            ],
          ),
      },
      creatableFeedPaths: const {'/latest.json'},
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://first-review.invalid'] = 'local-fixture'
      ..keys['https://second-review.invalid'] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.openNewTopicFromSidebar();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  var dark = false;
  var rtl = false;
  runApp(
    ShellScope(
      controller: shell,
      child: StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) => DToaster(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        DButton(
                          label: const Text('First draft'),
                          onPressed: () {
                            shell.selectInstance(0);
                            unawaited(shell.openNewTopicFromSidebar());
                          },
                        ),
                        DButton(
                          label: const Text('Topics'),
                          onPressed: () => shell.selectDestination(
                            const SidebarDestination(
                              id: 'latest',
                              label: 'Topics',
                              icon: DIcons.layerGroup,
                            ),
                          ),
                        ),
                        DButton(
                          label: const Text('Messages'),
                          onPressed: () => shell.selectDestination(
                            const SidebarDestination(
                              id: 'messages',
                              label: 'Messages',
                              icon: DIcons.inbox,
                            ),
                          ),
                        ),
                        DButton(
                          label: Text(dark ? 'Light' : 'Dark'),
                          onPressed: () => setState(() => dark = !dark),
                        ),
                        DButton(
                          label: Text(rtl ? 'LTR' : 'RTL'),
                          onPressed: () => setState(() => rtl = !rtl),
                        ),
                        DButton(
                          label: const Text('Second draft'),
                          onPressed: () {
                            shell.selectInstance(1);
                            unawaited(shell.openNewTopicFromSidebar());
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: DDirection(
                      textDirection: rtl
                          ? TextDirection.rtl
                          : TextDirection.ltr,
                      child: const AdaptiveShell(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
