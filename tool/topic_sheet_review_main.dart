// Local data only; mounts the production topic sheet and Native styleguide example.
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/styleguide/examples/sheet_examples.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setPrefix('topic_sheet_review.');
  const user = DiscourseUser(id: 7, username: 'reviewer', canCreateTopic: true);
  final titles = [
    'A calmer way to move between conversations',
    'Making the topic list easier to scan',
    'Keyboard navigation between discussions',
    'Keeping category colors useful and subtle',
  ];
  final topics = [
    for (var id = 1; id <= 24; id++)
      Topic(
        id: id,
        title: titles[(id - 1) % titles.length],
        slug: 'review-$id',
        excerpt: 'Open a conversation without losing your place in the list.',
        replyCount: 5,
      ),
  ];
  final shell = ShellController(
    instanceStore: FakeInstanceStore([
      instance(
        'topic-sheet.invalid',
        title: 'Discourse Meta',
      ).copyWith(user: user),
    ]),
    api: FakeDiscourseApi(
      user: user,
      feeds: {'/latest.json': topics},
      creatableFeedPaths: const {'/latest.json'},
      topics: {
        for (final topic in topics)
          topic.id: (
            detail: TopicDetail(
              id: topic.id,
              title: topic.title,
              stream: [for (var i = 1; i <= 6; i++) topic.id * 10 + i],
              postsCount: 6,
              canCreatePost: true,
            ),
            posts: [
              for (var i = 1; i <= 6; i++)
                Post(
                  id: topic.id * 10 + i,
                  postNumber: i,
                  username: i.isOdd ? 'sam' : 'hannah',
                  cooked: i.isOdd
                      ? '<p>The topic list is my starting point. I would like to open a discussion, reply, and return to the same place without rebuilding my context.</p><p>A conversation can have its own space while the list stays underneath it.</p>'
                      : '<p>The reply editor should belong to the conversation too. If I close it for a moment, I want my draft to be there when I return.</p>',
                ),
            ],
          ),
      },
    ),
    authenticator: FakeAuthenticator()
      ..keys['https://topic-sheet.invalid'] = 'local-fixture',
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
  );
  await shell.load();
  await shell.loadFeed('latest');
  shell.openTopicFromList(topics.first);
  var dark = false;
  var narrow = false;
  var styleguide = false;
  runApp(
    ShellScope(
      controller: shell,
      child: StatefulBuilder(
        builder: (context, setState) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, child) =>
              DFocusHighlight(child: DToaster(child: child!)),
          home: Scaffold(
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      DButton(
                        label: Text(dark ? 'Light' : 'Dark'),
                        onPressed: () => setState(() => dark = !dark),
                      ),
                      DButton(
                        label: Text(narrow ? 'Wide window' : 'Narrow window'),
                        onPressed: () => setState(() => narrow = !narrow),
                      ),
                      DButton(
                        label: Text(
                          styleguide ? 'Application' : 'Sheet styleguide',
                        ),
                        onPressed: () =>
                            setState(() => styleguide = !styleguide),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SizedBox(
                      width: narrow ? 650 : double.infinity,
                      child: styleguide
                          ? sheetExamples.examples
                                .firstWhere(
                                  (example) => example.title == 'Non-modal',
                                )
                                .builder(context)
                          : const AdaptiveShell(),
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
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
}
