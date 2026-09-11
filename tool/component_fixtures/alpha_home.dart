import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test/support/fakes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Offline review fixture: never read or write account preferences.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();
  const user = DiscourseUser(username: 'sam');
  final forums = [
    instance('dev.example', title: 'Discourse Dev').copyWith(user: user),
    instance('meta.example', title: 'Discourse Meta').copyWith(user: user),
  ];
  final auth = FakeAuthenticator();
  for (final forum in forums) {
    auth.keys[forum.url] = 'fixture-key';
  }
  final topics = [
    for (var i = 0; i < 8; i++)
      Topic(
        id: i + 1,
        title: [
          'Cannot edit drafts',
          'Notifications menu icons',
          'Composer can mangle a mix of images and text',
          'Keyboard shortcuts',
        ][i % 4],
        slug: 'fixture',
        bumpedAt: DateTime.now().subtract(Duration(hours: i + 1)),
        categoryId: 1,
      ),
  ];
  runApp(
    DiscourseApp(
      store: FakeInstanceStore(forums),
      api: FakeDiscourseApi(
        user: user,
        feeds: {
          '/latest.json': topics,
          '/filter.json?per_page=15': topics,
          '/filter.json?per_page=30': topics,
        },
        filterOptionsByPath: const {
          '/filter.json?per_page=15': [
            TopicFilterOption(name: 'status:', priority: 1),
          ],
        },
        categoryList: const [
          TopicCategory(id: 1, name: 'Bugs', slug: 'bugs', color: '7B5FE2'),
        ],
      ),
      authenticator: auth,
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
    ),
  );
}
