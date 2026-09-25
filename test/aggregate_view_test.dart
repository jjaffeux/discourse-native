import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_filter.dart';
import 'package:discourse_native/src/shell/aggregate_view.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/topic_filter_input.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kDoubleTapMinTime;
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
  TopicFilterOption(name: 'category:', type: 'category', priority: 3),
  TopicFilterOption(
    name: 'group:',
    type: 'group',
    priority: 4,
    delimiters: [
      TopicFilterModifier(name: ','),
      TopicFilterModifier(name: '+'),
    ],
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('aggregate header and rows share the page width', (tester) async {
    await _pumpMixedAggregateView(tester);
    tester.view.physicalSize = const Size(2000, 800);
    final shell = ShellScope.read(tester.element(find.byType(AggregateView)));
    await shell.appSettings.setLimitContentSize(false);
    await tester.pumpAndSettle();

    final header = find.byKey(const ValueKey('aggregate-page-header'));
    final row = find.byKey(const ValueKey('topic-card-42')).first;
    final wide = tester.getRect(header);
    expect(wide.width, greaterThan(825));

    await shell.appSettings.setLimitContentSize(true);
    await tester.pumpAndSettle();
    final normal = tester.getRect(header);
    expect(normal.width, 825);
    expect(normal.center.dx, wide.center.dx);
    expect(tester.getRect(row).center.dx, normal.center.dx);
    final viewport = find.descendant(
      of: find.byType(AggregateView),
      matching: find.byType(CustomScrollView),
    );
    expect(tester.getSize(viewport.first).width, wide.width);
  });

  for (final empty in [false, true]) {
    testWidgets(
      'pull does not refresh ${empty ? 'empty' : 'short'} aggregate topics',
      (tester) async {
        final fixture = await _pumpMixedAggregateView(tester, empty: empty);
        final api = fixture.api;
        final before = api.feedPaths.length;
        expect(find.byType(DPullToRefresh), findsNothing);
        await tester.drag(
          find.byType(CustomScrollView).last,
          const Offset(0, 500),
        );
        await tester.pumpAndSettle();
        expect(api.feedPaths.length, before);
        expect(find.byType(DSpinner), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

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

    await _openAggregate(tester);
    await tester.pumpAndSettle();
    final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
    expect(emoji.name, 'megaphone');
    expect(emoji.siteUrl, forum.url);
  });

  testWidgets('shows token autocomplete inside the forum filters menu', (
    tester,
  ) async {
    final fixture = await _pumpMixedAggregateView(tester);
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    expect(find.text('One'), findsWidgets);
    expect(find.text('Two'), findsWidgets);
    expect(find.byKey(const ValueKey('aggregate-filter-button')), findsNothing);
    expect(
      find.byType(TopicFilterInput),
      findsNWidgets(fixture.forumUrls.length),
    );
    for (final input in tester.widgetList<TopicFilterInput>(
      find.byType(TopicFilterInput),
    )) {
      expect(input.tokenized, isTrue);
    }
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.text('2 topics from 2 forums'), findsNothing);
    expect(
      tester
          .widget<DItem>(find.byKey(const ValueKey('topic-card-42')).first)
          .variant,
      DItemVariant.standard,
    );
  });

  testWidgets('per-forum Apply preserves other drafts and collapsed state', (
    tester,
  ) async {
    final fixture = await _pumpMixedAggregateView(tester);
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    final one = fixture.forumUrls[0], two = fixture.forumUrls[1];
    final first = find.byKey(ValueKey('aggregate-query-$one'));
    final second = find.byKey(ValueKey('aggregate-query-$two'));
    await tester.enterText(first, 'status:open');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.enterText(second, 'tag:ux');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    expect(find.byType(TopicFilterInput), findsNothing);
    expect(
      find.byKey(const ValueKey('aggregate-refresh-button')),
      findsNothing,
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('discourse_native.aggregate_preferences'),
      contains('"filters_collapsed":true'),
    );
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    if (find.byType(TopicFilterInput).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
      await tester.pumpAndSettle();
    }
    expect(find.text('status: open'), findsOneWidget);
    expect(find.text('tag: ux'), findsOneWidget);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    if (find.byType(TopicFilterInput).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
      await tester.pumpAndSettle();
    }
    expect(find.text('status: open'), findsOneWidget);
    expect(find.text('tag: ux'), findsOneWidget);
    tester.view.physicalSize = const Size(1000, 800);
    await tester.pumpAndSettle();
    if (find.byType(TopicFilterInput).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
      await tester.pumpAndSettle();
    }
    expect(find.text('status: open'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('aggregate-apply-$one')));
    await tester.pumpAndSettle();
    expect(find.text('tag: ux'), findsOneWidget);
    expect(
      tester
          .widget<DButton>(find.byKey(ValueKey('aggregate-apply-$two')))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byKey(ValueKey('aggregate-apply-$two')));
    await tester.pumpAndSettle();
    expect(
      preferences.getString('discourse_native.aggregate_preferences'),
      contains('status:open'),
    );
    expect(
      preferences.getString('discourse_native.aggregate_preferences'),
      contains('tag:ux'),
    );
  });

  testWidgets('narrow inline filters scroll without overflow', (tester) async {
    await _pumpMixedAggregateView(tester);
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
  });

  testWidgets(
    'finds uncached subcategories and inserts their qualified paths',
    (tester) async {
      final fixture = await _pumpMixedAggregateView(tester);
      await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
      await tester.pumpAndSettle();
      final api = fixture.api;
      final siteUrl = fixture.forumUrls.first;

      final field = find.byKey(ValueKey('aggregate-query-$siteUrl'));
      final suggestions = find.byKey(
        const ValueKey('topic-filter-suggestions'),
      );

      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(suggestions, findsOneWidget);
      expect(suggestions, findsOneWidget);

      await tester.enterText(field, 'categ');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('category:'), findsOneWidget);
      expect(suggestions, findsOneWidget);

      await tester.enterText(field, 'category:bugs');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Design › Bugs'), findsOneWidget);
      expect(find.text('Discourse Native App › Bugs'), findsOneWidget);
      expect(api.categorySearchTerms, contains('bugs'));
      expect(api.categorySearchIncludeAncestors, contains(true));
      expect(suggestions, findsOneWidget);

      await tester.tap(find.text('Discourse Native App › Bugs'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        isEmpty,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('topic-filter-token-0')),
          matching: find.text('category: Discourse Native App › Bugs'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<DTooltip>(
              find
                  .ancestor(
                    of: find.byKey(const ValueKey('topic-filter-token-0')),
                    matching: find.byType(DTooltip),
                  )
                  .first,
            )
            .message,
        'category:discourse-native-app:bugs',
      );
    },
  );

  testWidgets('selected suggestions become tokens without a separator', (
    tester,
  ) async {
    final fixture = await _pumpMixedAggregateView(tester);
    await tester.tap(find.byKey(const ValueKey('aggregate-filter-collapse')));
    await tester.pumpAndSettle();
    final siteUrl = fixture.forumUrls.first;

    final field = find.byKey(ValueKey('aggregate-query-$siteUrl'));

    await tester.tap(field);
    await tester.enterText(field, 'group:2023');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    const groupName = '2023-cap-polo-order';
    await tester.tap(find.text(groupName));
    await tester.pump();

    expect(
      tester
          .widget<TextField>(
            find.descendant(of: field, matching: find.byType(TextField)),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-filter-token-0')),
        matching: find.text('group: $groupName'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(ValueKey('aggregate-query-clear-$siteUrl')));
    await tester.pumpAndSettle();
    await tester.enterText(field, 'tag:x');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final token = find.byKey(const ValueKey('topic-filter-token-0'));
    expect(
      tester.getTopLeft(field).dy,
      greaterThan(tester.getBottomLeft(token).dy),
    );
    expect(tester.takeException(), isNull);
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
      expect(
        tester
            .widget<ForumTabsBar>(find.byType(ForumTabsBar))
            .items
            .single
            .icon,
        DIcons.circleNodes,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('aggregate-rail-button')),
          matching: find.byWidgetPredicate(
            (widget) => widget is DIcon && widget.icon == DIcons.circleNodes,
          ),
        ),
        findsOneWidget,
      );
      final heroFinder = find.byKey(const ValueKey('aggregate-hero'));
      expect(tester.getCenter(heroFinder).dx, closeTo(500, 0.5));
      expect(tester.getCenter(heroFinder).dy, closeTo(24, 0.5));
      expect(find.text('Discourse'), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      final tabsFinder = find.byKey(const ValueKey('aggregate-tabs'));
      final toolbarFinder = find.byKey(
        const ValueKey('aggregate-filter-collapse'),
      );
      expect(
        tester.getBottomLeft(heroFinder).dy,
        lessThanOrEqualTo(tester.getTopLeft(tabsFinder).dy),
      );
      expect(
        tester.getBottomLeft(heroFinder).dy,
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
  testWidgets('reorders aggregate tabs behind the forum insertion bar', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await _pumpMixedAggregateView(tester);
      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      await tester.pumpAndSettle();

      List<String> order() => [
        for (final item
            in tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items)
          item.id,
      ];
      final [firstId, secondId] = order();
      final first = find.byKey(ValueKey('forum-tab-item-$firstId'));
      final second = find.byKey(ValueKey('forum-tab-item-$secondId'));
      final indicator = find.byKey(
        const ValueKey('forum-tab-drop-placeholder'),
      );

      final drag = await tester.startGesture(
        tester.getCenter(first),
        kind: PointerDeviceKind.mouse,
      );
      await drag.moveBy(const Offset(20, 0));
      await tester.pump();
      final secondRect = tester.getRect(second);
      await drag.moveTo(Offset(secondRect.right - 2, secondRect.center.dy));
      await tester.pumpAndSettle();

      expect(indicator, findsOneWidget);
      expect(
        tester.getRect(indicator).left,
        greaterThanOrEqualTo(secondRect.right),
      );

      await drag.up();
      await tester.pumpAndSettle();

      expect(indicator, findsNothing);
      expect(order(), [secondId, firstId]);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('closing a tab releases the scroll controller of its list', (
    tester,
  ) async {
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

    try {
      await _pumpMixedAggregateView(tester);

      AggregateViewState view() =>
          tester.state<AggregateViewState>(find.byType(AggregateView));
      expect(view().retainedScrollControllerCount, 1);

      await tester.tap(find.byKey(const ValueKey('forum-tabs-add')));
      await tester.pumpAndSettle();

      final tabs = tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items;
      expect(tabs, hasLength(2));
      expect(view().retainedScrollControllerCount, 2);

      await tester.tap(find.byKey(ValueKey('forum-tab-close-${tabs.last.id}')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<ForumTabsBar>(find.byType(ForumTabsBar)).items,
        hasLength(1),
      );
      expect(view().retainedScrollControllerCount, 1);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}

Future<({List<String> forumUrls, FakeDiscourseApi api})>
_pumpMixedAggregateView(WidgetTester tester, {bool empty = false}) async {
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
        path: empty
            ? []
            : [
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
    filterGroupSearches: const {
      '2023': [TopicFilterLookupValue(name: '2023-cap-polo-order')],
    },
    feedGates: <String, Completer<void>>{},
    categoryList: const [
      TopicCategory(id: 1, name: 'Design', slug: 'design', color: 'AA00AA'),
      TopicCategory(
        id: 2,
        name: 'Bugs',
        slug: 'bugs',
        color: 'BB00BB',
        parentCategoryId: 1,
      ),
    ],
    categorySearches: const {
      'bugs': [
        TopicCategory(
          id: 4,
          name: 'Bugs',
          slug: 'bugs',
          color: '00AACC',
          parentCategoryId: 3,
        ),
        TopicCategory(
          id: 2,
          name: 'Bugs',
          slug: 'bugs',
          color: 'BB00BB',
          parentCategoryId: 1,
        ),
        TopicCategory(
          id: 3,
          name: 'Discourse Native App',
          slug: 'discourse-native-app',
          color: '0088CC',
        ),
        TopicCategory(id: 1, name: 'Design', slug: 'design', color: 'AA00AA'),
      ],
    },
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
  await _openAggregate(tester);
  await tester.pumpAndSettle();
  expect(find.byType(TopicFilterInput), findsNothing);
  return (forumUrls: forums.map((forum) => forum.url).toList(), api: api);
}

Future<void> _openAggregate(WidgetTester tester) async {
  final menu = find.byKey(const ValueKey('mobile-menu-button'));
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
  await tester.tap(find.byKey(const ValueKey('aggregate-rail-button')));
  await tester.pumpAndSettle();
  expect(find.byTooltip('Close navigation'), findsNothing);
}
