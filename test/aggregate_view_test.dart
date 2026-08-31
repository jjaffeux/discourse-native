import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/aggregate_view.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kDoubleTapMinTime;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

const _defaultAggregatePath = '/filter.json?per_page=15';
const _firstFilterPath = '/filter.json?per_page=15&q=status%3Aopen';
const _secondFilterPath = '/filter.json?per_page=15&q=tag%3Aux';
const _filterOptions = [
  TopicFilterOption(name: 'status:', priority: 1),
  TopicFilterOption(name: 'tag:', type: 'tag', priority: 2),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders Discourse emoji aliases in cross-forum topic titles', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    const user = DiscourseUser(username: 'sam');
    final forum = instance('one.example', title: 'One').copyWith(user: user);
    final authenticator = FakeAuthenticator()..keys[forum.url] = 'key';
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {
        '/latest.json': [],
        '/filter.json?per_page=30': [
          Topic(id: 42, title: 'Weekly updates :mega:', slug: 'weekly'),
        ],
      },
      emojisBySite: {
        forum.url: const [
          SiteEmoji(name: 'megaphone', url: '/images/emoji/megaphone.png'),
        ],
      },
    );

    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore([forum]),
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

    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'megaphone');
    expect(emoji.siteUrl, forum.url);
  });

  testWidgets('renders a mixed full-width feed above its controls', (
    tester,
  ) async {
    final fixture = await _pumpMixedAggregateView(tester);
    final forumUrls = fixture.forumUrls;

    expect(find.byType(AggregateView), findsOneWidget);
    expect(find.byType(InstanceSidebar), findsNothing);
    expect(find.byType(MainContent), findsNothing);
    expect(find.text('Discourse (alpha)'), findsOneWidget);
    expect(find.text('Every forum. One shared feed.'), findsNothing);
    final heroFinder = find.byKey(const ValueKey('aggregate-hero'));
    final hero = tester.widget<Container>(heroFinder);
    expect(tester.getSize(heroFinder).height, 64);
    final heroGradient = (hero.decoration! as BoxDecoration).gradient!;
    expect((heroGradient as LinearGradient).colors, const [
      Color(0xFF503281),
      Color(0xFF39245C),
    ]);
    expect(
      find.descendant(of: heroFinder, matching: find.byType(ImageFiltered)),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: heroFinder,
        matching: find.byKey(const ValueKey('aggregate-hero-badge-bell')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: heroFinder,
        matching: find.byKey(const ValueKey('aggregate-hero-badge-quote')),
      ),
      findsOneWidget,
    );
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('aggregate-hero'))),
      ).colorScheme.primary,
      const Color(0xFF7B5FE2),
    );
    expect(
      find.descendant(
        of: heroFinder,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.comments,
        ),
      ),
      findsNothing,
    );
    expect(find.byType(TopicListRow), findsNWidgets(2));
    expect(find.text('Fresh cross-forum topic'), findsNWidgets(2));
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    final toolbarFinder = find.byKey(const ValueKey('aggregate-tab-toolbar'));
    final firstCardFinder = find.byKey(
      ValueKey('aggregate-topic-card-${forumUrls[0]}-42'),
    );
    expect(find.text('2 topics from 2 forums'), findsOneWidget);
    expect(
      tester.getBottomLeft(heroFinder).dy,
      lessThanOrEqualTo(tester.getTopLeft(toolbarFinder).dy),
    );
    expect(
      tester.getBottomLeft(toolbarFinder).dy,
      lessThanOrEqualTo(tester.getTopLeft(firstCardFinder).dy),
    );
    expect(
      find.descendant(
        of: toolbarFinder,
        matching: find.byKey(const ValueKey('aggregate-filter-button')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: toolbarFinder,
        matching: find.byKey(const ValueKey('aggregate-refresh-button')),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('aggregate-topic-card-${forumUrls[0]}-42')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('aggregate-topic-card-${forumUrls[1]}-42')),
      findsOneWidget,
    );
  });

  testWidgets('desktop caps feed cards while toolbar stays full width', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final fixture = await _pumpMixedAggregateView(tester);
      final firstCard = find.byKey(
        ValueKey('aggregate-topic-card-${fixture.forumUrls[0]}-42'),
      );
      final viewport = find.descendant(
        of: find.byType(AggregateView),
        matching: find.byType(ListView),
      );
      final toolbar = find.byKey(const ValueKey('aggregate-tab-toolbar'));

      expect(tester.getSize(firstCard).width, 825);
      expect(tester.getSize(viewport).width, greaterThan(825));
      expect(tester.getSize(toolbar).width, tester.getSize(viewport).width);
      expect(
        tester.getCenter(firstCard).dx,
        closeTo(tester.getCenter(viewport).dx, 0.001),
      );
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('saves exact per-forum filters and can exclude every forum', (
    tester,
  ) async {
    final fixture = await _pumpMixedAggregateView(tester);
    final api = fixture.api;
    final forumUrls = fixture.forumUrls;

    await tester.tap(find.byKey(const ValueKey('aggregate-filter-button')));
    await tester.pumpAndSettle();
    expect(find.text('Aggregate filters'), findsOneWidget);
    expect(
      find.byKey(ValueKey('aggregate-filter-${forumUrls[0]}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('aggregate-filter-${forumUrls[1]}')),
      findsOneWidget,
    );
    expect(find.byType(TopicFilterInput), findsNWidgets(5));
    expect(find.text('Save filters').hitTestable(), findsOneWidget);

    await tester.enterText(
      find.byKey(ValueKey('aggregate-query-${forumUrls[0]}')),
      'status:open',
    );
    await tester.enterText(
      find.byKey(ValueKey('aggregate-query-${forumUrls[1]}')),
      'tag:ux',
    );
    final requestsBeforeSave = api.feedPaths.length;
    await tester.tap(find.text('Save filters'));
    await tester.pumpAndSettle();

    expect(
      api.feedPaths.skip(requestsBeforeSave),
      unorderedEquals([_firstFilterPath, _secondFilterPath]),
    );

    await tester.tap(find.byKey(const ValueKey('aggregate-filter-button')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(ValueKey('aggregate-query-${forumUrls[0]}')),
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
      final heroFinder = find.byKey(const ValueKey('aggregate-hero'));
      final tabsFinder = find.byKey(const ValueKey('aggregate-tabs'));
      final toolbarFinder = find.byKey(const ValueKey('aggregate-tab-toolbar'));
      expect(
        tester.getBottomLeft(heroFinder).dy,
        lessThanOrEqualTo(tester.getTopLeft(tabsFinder).dy),
      );
      expect(
        tester.getBottomLeft(tabsFinder).dy,
        lessThanOrEqualTo(tester.getTopLeft(toolbarFinder).dy),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('aggregate-tabs')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.layerGroup,
          ),
        ),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items,
        hasLength(2),
      );

      // The first click also switches away from Aggregate 2. Renaming must
      // survive that controller-driven rebuild and still recognize the
      // complete double click.
      await tester.tap(find.text('Aggregate 1'));
      await tester.pump(kDoubleTapMinTime);
      await tester.tap(find.text('Aggregate 1'));
      await tester.pump();
      final renamedTab = tester
          .widget<ForumTabsBar>(find.byType(ForumTabsBar))
          .items
          .first;
      final renameField = find.byKey(
        ValueKey('forum-tab-rename-${renamedTab.id}'),
      );
      await tester.enterText(renameField, 'Product triage');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('Product triage'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

Future<({List<String> forumUrls, FakeDiscourseApi api})>
_pumpMixedAggregateView(WidgetTester tester) async {
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
  final authenticator = FakeAuthenticator()
    ..keys[forums[0].url] = 'one-key'
    ..keys[forums[1].url] = 'two-key';
  final api = FakeDiscourseApi(
    user: user,
    feeds: {
      '/latest.json': const [],
      for (final path in [
        _defaultAggregatePath,
        _firstFilterPath,
        _secondFilterPath,
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
      _defaultAggregatePath: _filterOptions,
      _firstFilterPath: _filterOptions,
      _secondFilterPath: _filterOptions,
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
  return (forumUrls: forums.map((forum) => forum.url).toList(), api: api);
}
