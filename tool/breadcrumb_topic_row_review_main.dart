// Offline review fixture mounting the real topic-list production surface.
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/macos_launch_screen.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:flutter/widgets.dart';

import '../test/support/fakes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MacOSLaunchScreen.dismissAfterFirstFlutterFrame();

  const parent = TopicCategory(
    id: 5,
    name: 'Discourse Native Application',
    color: '0088CC',
    slug: 'discourse-native-application',
  );
  const category = TopicCategory(
    id: 6,
    name: 'Feature requests with a deliberately long local-data label',
    color: '00AEEF',
    slug: 'feature-requests',
    parentCategoryId: 5,
  );
  final api = FakeDiscourseApi(
    feeds: {
      '/latest.json': [
        const Topic(
          id: 3,
          title: 'Source-exact topic-row Breadcrumb review',
          slug: 'source-exact-topic-row-breadcrumb-review',
          categoryId: 6,
        ),
      ],
      '/c/discourse-native-application/5.json': const [],
      '/c/discourse-native-application/feature-requests/6.json': const [],
    },
    categoryList: const [parent],
    feedCategoriesByPath: const {
      '/latest.json': [parent, category],
    },
  );

  runApp(
    DiscourseApp(
      store: FakeInstanceStore([
        instance('breadcrumb-review.invalid', title: 'Breadcrumb Review'),
      ]),
      api: api,
      authenticator: FakeAuthenticator(),
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
    ),
  );
}
