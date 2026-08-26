import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/aggregate_view.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('starts with a mixed full-width feed and forum picker', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const user = DiscourseUser(
      username: 'sam',
      trackedCategoryIds: [1],
      watchedCategoryIds: [],
      watchedFirstPostCategoryIds: [],
    );
    final forums = [
      instance('one.example', title: 'One').copyWith(user: user),
      instance('two.example', title: 'Two').copyWith(user: user),
      instance('signed-out-one.example', title: 'Signed out one'),
      instance('signed-out-two.example', title: 'Signed out two'),
      instance('signed-out-three.example', title: 'Signed out three'),
    ];
    const defaultAggregatePath = '/filter.json?per_page=15';
    const firstFilterPath = '/filter.json?per_page=15&q=status%3Aopen';
    const secondFilterPath = '/filter.json?per_page=15&q=tag%3Aux';
    const filterOptions = [
      TopicFilterOption(name: 'status:', priority: 1),
      TopicFilterOption(name: 'tag:', type: 'tag', priority: 2),
    ];
    final authenticator = FakeAuthenticator()
      ..keys[forums[0].url] = 'one-key'
      ..keys[forums[1].url] = 'two-key';
    final api = FakeDiscourseApi(
      user: user,
      feeds: {
        '/latest.json': const [],
        for (final path in [
          defaultAggregatePath,
          firstFilterPath,
          secondFilterPath,
        ])
          path: [
            Topic(
              id: 42,
              title: 'Fresh cross-forum topic',
              slug: 'fresh-topic',
              categoryId: 1,
              seen: false,
              bumpedAt: DateTime.utc(2026, 1, 1),
            ),
          ],
      },
      filterOptionsByPath: const {
        defaultAggregatePath: filterOptions,
        firstFilterPath: filterOptions,
        secondFilterPath: filterOptions,
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'Followed', color: '0088CC'),
      ],
    );
    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore(forums),
        api: api,
        authenticator: authenticator,
        drafts: FakeDraftStore(),
        forumTabs: FakeForumTabStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AggregateView), findsOneWidget);
    expect(find.byType(InstanceSidebar), findsNothing);
    expect(find.byType(MainContent), findsNothing);
    expect(find.byType(TopicListRow), findsNWidgets(2));
    expect(find.text('Fresh cross-forum topic'), findsNWidgets(2));
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Aggregate filters'), findsOneWidget);
    expect(
      find.byKey(ValueKey('aggregate-filter-${forums[0].url}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('aggregate-filter-${forums[1].url}')),
      findsOneWidget,
    );
    expect(find.byType(TopicFilterInput), findsNWidgets(5));
    expect(find.text('Save filters').hitTestable(), findsOneWidget);

    await tester.enterText(
      find.byKey(ValueKey('aggregate-query-${forums[0].url}')),
      'status:open',
    );
    await tester.enterText(
      find.byKey(ValueKey('aggregate-query-${forums[1].url}')),
      'tag:ux',
    );
    await tester.tap(find.text('Save filters'));
    await tester.pumpAndSettle();

    expect(api.feedPaths, contains(firstFilterPath));
    expect(api.feedPaths, contains(secondFilterPath));

    await tester.tap(find.byKey(const ValueKey('aggregate-filter-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(ValueKey('aggregate-query-${forums[0].url}')),
          )
          .controller!
          .text,
      'status:open',
    );

    await tester.tap(find.text('None'));
    expect(find.text('Save filters').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Save filters'));
    await tester.pumpAndSettle();

    expect(find.text('No forums selected'), findsOneWidget);
    expect(find.byType(TopicListRow), findsNothing);
  });

  testWidgets('desktop exposes aggregate tab lifecycle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    try {
      const user = DiscourseUser(username: 'sam');
      final forum = instance('one.example', title: 'One').copyWith(user: user);
      final authenticator = FakeAuthenticator()..keys[forum.url] = 'key';
      await tester.pumpWidget(
        DiscourseApp(
          store: FakeInstanceStore([forum]),
          api: FakeDiscourseApi(
            user: user,
            feeds: const {'/latest.json': [], '/filter.json?per_page=30': []},
          ),
          authenticator: authenticator,
          drafts: FakeDraftStore(),
          forumTabs: FakeForumTabStore(),
          trackers: FakeSiteTracker.reset(),
          updater: FakeUpdater(),
          updateStore: FakeUpdateStore(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items,
        hasLength(1),
      );

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items,
        hasLength(2),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
