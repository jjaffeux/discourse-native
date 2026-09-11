import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/models/category_sidebar.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/list_link.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_filter_bar.dart';
import 'package:discourse_native/src/shell/topic_list_navigation.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const _legacyTotals = NotificationTotals(
  topicTrackingNew: 1054,
  topicTrackingUnread: 5,
);

const _unifiedTotals = NotificationTotals(topicTrackingNew: 1059);

const _user = DiscourseUser(id: 7, username: 'sam', unifiedNewEnabled: true);

const _latestTopic = Topic(id: 1, title: 'Latest topic', slug: 'latest-topic');

const _allNewTopic = Topic(
  id: 2,
  title: 'All new activity',
  slug: 'all-new-activity',
);

const _newTopic = Topic(id: 3, title: 'New topic only', slug: 'new-topic-only');

const _newReply = Topic(id: 4, title: 'New reply only', slug: 'new-reply-only');

const _topYearTopic = Topic(id: 6, title: 'Top this year', slug: 'top-year');

const _topWeekTopic = Topic(id: 7, title: 'Top this week', slug: 'top-week');

const _popularTopic = Topic(id: 8, title: 'Popular topic', slug: 'popular');

void main() {
  testWidgets(
    'list search uses server feeds and follows category and tag changes',
    (tester) async {
      const category = TopicCategory(
        id: 42,
        name: 'UX',
        slug: 'ux',
        color: '123456',
      );
      final setup = await _controller(categoryList: [category]);
      addTearDown(setup.controller.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(body: TopicListNavigation(child: SizedBox())),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-list-search')),
        'layout',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(setup.api.feedPaths.last, '/latest.json?search=layout');
      setup.controller.selectTopicListCategory(category);
      await tester.pumpAndSettle();
      expect(
        Uri.parse(setup.api.feedPaths.last).queryParameters['search'],
        'layout',
      );
      expect(setup.controller.topicListContent!.categoryId, 42);
      setup.controller.selectTopicListTags(['design', 'mobile']);
      await tester.pumpAndSettle();
      expect(setup.controller.topicListContent!.tagNames, ['design', 'mobile']);
      expect(setup.controller.topicListContent!.topicListSearch, 'layout');
      await setup.controller.selectTopicListMode(TopicListMode.unread);
      await tester.pumpAndSettle();
      expect(Uri.parse(setup.api.feedPaths.last).path, '/unread.json');
      expect(
        Uri.parse(setup.api.feedPaths.last).queryParameters['search'],
        'layout',
      );
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(setup.controller.topicListContent!.topicListSearch, isEmpty);
      expect(setup.controller.topicListContent!.categoryId, 42);
      expect(setup.controller.topicListContent!.tagNames, ['design', 'mobile']);
    },
  );

  for (final width in [320.0, 390.0, 760.0, 1120.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('focused toolbar fits $width at ${scale}x including RTL', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const parent = TopicCategory(
          id: 21,
          name: 'Product design and accessibility',
          slug: 'design',
          color: '3188CC',
        );
        const child = TopicCategory(
          id: 22,
          parentCategoryId: 21,
          name: 'Keyboard navigation and assistive technology',
          slug: 'keyboard',
          color: '3188CC',
        );
        final setup = await _controller(
          canCreateTopics: true,
          categoryList: [parent, child],
        );
        addTearDown(setup.controller.dispose);
        await setup.controller.selectTopicListMode(TopicListMode.newActivity);
        setup.controller.selectTopicListCategory(child);
        for (final direction in TextDirection.values) {
          await tester.pumpWidget(
            ShellScope(
              controller: setup.controller,
              child: MaterialApp(
                theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 850),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Directionality(
                    textDirection: direction,
                    child: const Scaffold(
                      body: MainContent(layout: ShellLayout.expanded),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('topic-list-filters')),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('topic-list-category-filter')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('topic-list-new-segments')),
            findsOneWidget,
          );
          for (final key in [
            'topic-list-category-filter',
            'topic-list-subcategory-filter',
            'topic-list-tag-filter',
            'topic-list-feed-tabs',
          ]) {
            final rect = tester.getRect(find.byKey(ValueKey(key)));
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(rect.right, lessThanOrEqualTo(width));
          }
          expect(
            find.byKey(const ValueKey('topic-list-ledger-header')),
            findsNothing,
          );
          expect(find.text('Clear all'), findsNothing);
          expect(find.text('Latest conversations'), findsNothing);
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  for (final stacked in [false, true]) {
    testWidgets(
      'narrow selectors combine tags with AND and preserve filters (stacked: $stacked)',
      (tester) async {
        tester.view.physicalSize = const Size(390, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const parent = TopicCategory(
          id: 42,
          name: 'Support',
          slug: 'support',
          color: '3188CC',
        );
        const child = TopicCategory(
          id: 43,
          parentCategoryId: 42,
          name: 'Installation',
          slug: 'installation',
          color: '3188CC',
        );
        final setup = await _controller(
          categoryList: [parent, child],
          categorySiteTopTags: const [
            SidebarTag(id: 5, name: 'release', slug: 'release'),
            SidebarTag(id: 6, name: 'approved', slug: 'approved'),
          ],
        );
        final shell = setup.controller;
        addTearDown(shell.dispose);
        await tester.pumpWidget(
          ShellScope(
            controller: shell,
            child: MaterialApp(
              theme: AppTheme.dark,
              home: Scaffold(
                body: TopicListNavigation(
                  stacked: stacked,
                  child: const SizedBox(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('topic-list-category-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Support').last);
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, 42);
        final parentRect = tester.getRect(
          find.byKey(const ValueKey('topic-list-category-filter')),
        );
        final childRect = tester.getRect(
          find.byKey(const ValueKey('topic-list-subcategory-filter')),
        );
        final tagRect = tester.getRect(
          find.byKey(const ValueKey('topic-list-tag-filter')),
        );
        expect(parentRect.top, childRect.top);
        expect(tagRect.top, greaterThanOrEqualTo(childRect.bottom));
        await tester.tap(
          find.byKey(const ValueKey('topic-list-subcategory-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Installation').last);
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, 43);
        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(('topic-list-tag-filter-option', 'release')),
          ),
        );
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, 43);
        expect(shell.topicListContent?.tagNames, ['release']);
        expect(
          setup.api.feedPaths.last,
          '/tags/c/support/installation/43/release.json',
        );
        expect(find.byKey(const ValueKey('topic-list-filters')), findsNothing);
        expect(
          find.byKey(const ValueKey('topic-list-clear-filters')),
          findsNothing,
        );
        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(('topic-list-tag-filter-option', 'approved')),
          ),
        );
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.tagNames, ['approved', 'release']);
        expect(find.text('Tags · 2'), findsOneWidget);
        final taggedFeed = Uri.parse(setup.api.feedPaths.last);
        expect(taggedFeed.path, '/latest.json');
        expect(taggedFeed.queryParameters['category'], '43');
        expect(taggedFeed.queryParametersAll['tags[]'], [
          'approved',
          'release',
        ]);
        expect(taggedFeed.queryParameters['match_all_tags'], 'true');

        // Returning to the parent retains tags and clears only the subcategory.
        await tester.tap(
          find.byKey(const ValueKey('topic-list-subcategory-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('All subcategories').last);
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.categoryId, 42);
        expect(shell.topicListContent?.tagNames, ['approved', 'release']);
        await shell.selectTopicListMode(TopicListMode.topWeekly);
        await tester.pumpAndSettle();
        final topFeed = Uri.parse(setup.api.feedPaths.last);
        expect(topFeed.path, '/top.json');
        expect(topFeed.queryParameters['period'], 'weekly');
        expect(topFeed.queryParameters['category'], '42');
        expect(topFeed.queryParametersAll['tags[]'], ['approved', 'release']);
        expect(topFeed.queryParameters['match_all_tags'], 'true');

        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(
            const ValueKey(('topic-list-tag-filter-option', 'approved')),
          ),
        );
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.tagNames, ['release']);
        expect(shell.topicListContent?.categoryId, 42);
        expect(shell.currentTopicListMode, TopicListMode.topWeekly);

        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('topic-list-tag-filter-all')),
        );
        await tester.pumpAndSettle();
        expect(shell.topicListContent?.tagNames, isEmpty);
        expect(shell.topicListContent?.categoryId, 42);
        expect(setup.api.feedPaths.last, '/top.json?period=weekly&category=42');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retired direct selector cannot change a replaced feed before rebuild',
    (tester) async {
      final setup = await _controller();
      addTearDown(setup.controller.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: TopicListNavigation(stacked: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final select = tester
          .widget<TopicListFilterBar>(find.byType(TopicListFilterBar))
          .onTagSelected;
      await setup.controller.selectTopicListMode(TopicListMode.topYearly);
      final replacement = setup.controller.topicListContent;
      final requests = [...setup.api.feedPaths];
      select('stale');
      await tester.pumpAndSettle();
      expect(setup.controller.topicListContent, replacement);
      expect(setup.api.feedPaths, requests);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('slug category links show working category and tag dropdowns', (
    tester,
  ) async {
    const query = 'status=open&assigned=nobody';
    const todo = TopicCategory(
      id: 5,
      name: 'Todo',
      slug: 'todo',
      color: '112233',
    );
    const later = TopicCategory(
      id: 6,
      name: 'Later',
      slug: 'later',
      color: '223344',
    );
    final setup = await _controller(
      config: const SiteConfig(taggingEnabled: true),
      categoryList: const [todo, later],
      categorySiteTopTags: const [
        SidebarTag(id: 4, name: 'urgent', slug: 'urgent'),
      ],
      extraFeeds: const {
        '/c/todo/5.json?$query': [],
        '/tags/c/todo/5/urgent.json?$query': [],
        '/tags/c/later/6/urgent.json?$query': [],
      },
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.expanded)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final opened = await openLink(
      tester.element(find.byType(MainContent)),
      '/c/todo?$query',
    );
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    final category = find.byKey(const ValueKey('topic-list-category-filter'));
    final tags = find.byKey(const ValueKey('topic-list-tag-filter'));
    expect(category, findsOneWidget);
    expect(tags, findsOneWidget);
    expect(
      find.descendant(of: category, matching: find.text('Todo')),
      findsOneWidget,
    );

    await tester.tap(tags);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey(('topic-list-tag-filter-option', 'urgent'))),
    );
    await tester.pumpAndSettle();
    expect(controller.topicListContent?.categoryId, todo.id);
    expect(controller.topicListContent?.tagNames, ['urgent']);

    await tester.tap(category);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(controller.topicListContent?.categoryId, later.id);
    expect(controller.topicListContent?.tagNames, ['urgent']);
    expect(setup.api.feedPaths, [
      '/latest.json',
      '/c/todo/5.json?$query',
      '/tags/c/todo/5/urgent.json?$query',
      '/tags/c/later/6/urgent.json?$query',
    ]);
  });

  testWidgets('category loading resolves restored and background slug routes', (
    tester,
  ) async {
    final categories = <TopicCategory>[];
    const path = '/c/todo.json?status=open&assigned=nobody';
    final setup = await _controller(
      categoryList: categories,
      forumTabsEnabled: true,
      extraFeeds: const {path: []},
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);
    await tester.pump();
    final restored = ContentRoute.fromJson(
      ContentRoute.list(
        ListLink.parse('/c/todo?status=open&assigned=nobody')!,
      ).toJson(),
    );
    controller.pushContent(restored);
    controller.openLinkInNewTab('/c/todo?status=open&assigned=nobody');
    final tabId = controller.activeTabId;
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicListNavigation(child: SizedBox())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    categories.add(
      const TopicCategory(id: 5, name: 'Todo', slug: 'todo', color: '112233'),
    );

    await controller.loadCategories(
      controller.currentInstance!.url,
      force: true,
    );
    await tester.pumpAndSettle();

    expect(controller.activeTabId, tabId);
    for (final tab in controller.tabsForCurrentForum) {
      expect(tab.currentContent.id, restored.id);
      expect(tab.currentContent.categoryId, 5);
    }
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-list-category-filter')),
        matching: find.text('Todo'),
      ),
      findsOneWidget,
    );
  });

  for (final stacked in [false, true]) {
    testWidgets(
      'retains hydrated filter controls on unrelated notifications (stacked: $stacked)',
      (tester) async {
        final directoryTags = [
          for (var id = 1; id <= 1000; id++)
            SidebarTag(id: id, name: 'Tag $id', slug: 'tag-$id'),
        ];
        final setup = await _controller(
          categoryList: const [
            TopicCategory(id: 1, name: 'Support', color: '123456'),
          ],
          tagList: directoryTags,
        );
        final controller = setup.controller;
        addTearDown(controller.dispose);
        await controller.loadTags(controller.currentInstance!.url);
        await tester.pumpWidget(
          ShellScope(
            controller: controller,
            child: MaterialApp(
              theme: AppTheme.light,
              home: Scaffold(
                body: TopicListNavigation(
                  stacked: stacked,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        TopicListFilterBar filters() =>
            tester.widget<TopicListFilterBar>(find.byType(TopicListFilterBar));
        final hydrated = filters();
        expect(hydrated.knownTags, hasLength(1000));
        var notifications = 0;
        controller.addListener(() => notifications++);
        var recreatedControls = 0;
        var previous = hydrated;
        for (var index = 0; index < 20; index++) {
          if (index.isEven) {
            controller.openAppSettingsModal();
          } else {
            controller.closeAppSettingsModal();
          }
          await tester.pump();
          final next = filters();
          if (!identical(next, previous)) recreatedControls++;
          previous = next;
        }
        expect(notifications, 20);
        expect(recreatedControls, 0);

        const added = SidebarTag(id: 1001, name: 'New tag', slug: 'new-tag');
        directoryTags.add(added);
        await controller.loadTags(controller.currentInstance!.url, force: true);
        await tester.pumpAndSettle();
        expect(filters(), isNot(same(hydrated)));
        expect(filters().knownTags.last, added);

        controller.selectTopicListTag(added.slug);
        await tester.pumpAndSettle();
        expect(find.text(added.name), findsOneWidget);
      },
    );
  }

  test('keeps New out of the connected sidebar', () {
    final site = instance('meta.discourse.org').copyWith(user: _user);
    final destinationIds = [
      for (final section in site.sections) ...[
        for (final destination in section.destinations) destination.id,
        for (final destination in section.moreDestinations) destination.id,
      ],
    ];

    expect(destinationIds, isNot(contains('new')));
  });

  testWidgets(
    'open tag picker keeps its query and selection through shell notifications',
    (tester) async {
      const tag = SidebarTag(id: 1, name: 'User experience', slug: 'ux');
      final setup = await _controller(categorySiteTopTags: const [tag]);
      final controller = setup.controller;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: TopicListNavigation(child: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-list-tag-filter')));
      await tester.pumpAndSettle();
      final query = find.byKey(const ValueKey('topic-list-tag-filter-query'));
      await tester.enterText(query, 'experience');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();

      controller.openAppSettingsModal();
      await tester.pump();
      controller.closeAppSettingsModal();
      await tester.pump();
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: query, matching: find.byType(TextField)),
            )
            .controller!
            .text,
        'experience',
      );
      await tester.tap(
        find.byKey(
          const ValueKey(('topic-list-tag-filter-option', 'User experience')),
        ),
      );
      await tester.pumpAndSettle();
      expect(controller.topicListContent?.tagNames, ['User experience']);
      expect(find.text('User experience'), findsOneWidget);
    },
  );

  test('topic-list routes round trip with the Discourse subset paths', () {
    const expectations = {
      TopicListMode.latest: (id: 'latest', path: null),
      TopicListMode.newActivity: (id: 'new', path: '/new.json'),
      TopicListMode.newTopics: (
        id: 'new-topics',
        path: '/new.json?subset=topics',
      ),
      TopicListMode.newReplies: (
        id: 'new-replies',
        path: '/new.json?subset=replies',
      ),
      TopicListMode.unread: (id: 'unread', path: '/unread.json'),
      TopicListMode.topAll: (id: 'top-all', path: '/top.json?period=all'),
      TopicListMode.topYearly: (
        id: 'top-yearly',
        path: '/top.json?period=yearly',
      ),
      TopicListMode.topQuarterly: (
        id: 'top-quarterly',
        path: '/top.json?period=quarterly',
      ),
      TopicListMode.topMonthly: (
        id: 'top-monthly',
        path: '/top.json?period=monthly',
      ),
      TopicListMode.topWeekly: (
        id: 'top-weekly',
        path: '/top.json?period=weekly',
      ),
      TopicListMode.topDaily: (id: 'top-daily', path: '/top.json?period=daily'),
      TopicListMode.popular: (id: 'hot', path: '/hot.json'),
    };

    for (final entry in expectations.entries) {
      final route = ContentRoute.topicList(entry.key);
      final restored = ContentRoute.fromJson(route.toJson());

      expect(route.id, entry.value.id);
      expect(route.feedPath, entry.value.path);
      expect(restored.id, entry.value.id);
      expect(restored.feedPath, entry.value.path);
      expect(TopicListMode.fromRoute(restored), entry.key);
    }
  });

  testWidgets(
    'waits for the unified tracking snapshot before splitting counts',
    (tester) async {
      final trackingStateGate = Completer<void>();
      final setup = await _controller(trackingStateGate: trackingStateGate);
      final controller = setup.controller;
      addTearDown(controller.dispose);
      await tester.pump();

      expect(setup.api.topicTrackingRequests, ['https://meta.discourse.org']);

      FakeSiteTracker.built.single.deliverTopicTracking(const {
        'topic_id': 4000,
        'message_type': 'unread',
        'payload': {'highest_post_number': 2, 'notification_level': 2},
      });

      expect(controller.topicListNewCounts, (all: 1059, topics: 0, replies: 0));

      trackingStateGate.complete();
      await tester.pumpAndSettle();

      expect(controller.topicListNewCounts, (
        all: 1060,
        topics: 1054,
        replies: 6,
      ));
    },
  );

  testWidgets('empty categories hide New counts despite forum activity', (
    tester,
  ) async {
    const category = TopicCategory(
      id: 42,
      name: 'Credentials',
      color: 'ff5500',
    );
    final setup = await _controller(categoryList: [category]);
    final controller = setup.controller;
    addTearDown(controller.dispose);
    await tester.pumpAndSettle();
    controller.selectTopicListCategory(category);
    await controller.selectTopicListMode(TopicListMode.newActivity);
    expect(controller.topicListContent?.categoryId, category.id);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: TopicListNavigation(stacked: true, child: SizedBox()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.topicListNewCounts, (all: 0, topics: 0, replies: 0));
    expect(controller.sidebarBadgeFor('latest').count, 1059);
    for (final entry in {
      'all': 'All',
      'topics': 'Topics',
      'replies': 'Replies',
    }.entries) {
      expect(
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byKey(ValueKey('topic-list-new-${entry.key}')),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data),
        [entry.value],
      );
    }
  });

  testWidgets('category counts wait for a complete tracking snapshot', (
    tester,
  ) async {
    const category = TopicCategory(
      id: 42,
      name: 'Credentials',
      color: 'ff5500',
    );
    final gate = Completer<void>();
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
    });
    final setup = await _controller(
      categoryList: [category],
      trackingStateGate: gate,
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);
    await tester.pumpAndSettle();
    controller.selectTopicListCategory(category);
    await controller.selectTopicListMode(TopicListMode.newActivity);
    expect(controller.topicListContent?.categoryId, category.id);
    await tester.pump();

    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 4000,
      'message_type': 'unread',
      'payload': {
        'category_id': 42,
        'highest_post_number': 2,
        'notification_level': 2,
      },
    });
    expect(controller.topicListNewCounts, (all: 0, topics: 0, replies: 0));
    expect(controller.sidebarBadgeFor('latest').count, 1059);

    gate.complete();
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 1, topics: 0, replies: 1));
    expect(controller.sidebarBadgeFor('latest').count, 1060);
  });

  testWidgets('New counts follow category and tag filters and live reads', (
    tester,
  ) async {
    const parent = TopicCategory(id: 1, name: 'Parent', color: '111111');
    const child = TopicCategory(
      id: 2,
      name: 'Child',
      color: '222222',
      parentCategoryId: 1,
    );
    final setup = await _controller(
      categoryList: [parent, child],
      categorySiteTopTags: const [
        SidebarTag(id: 7, name: 'Bug Fixes', slug: 'bug-fixes'),
        SidebarTag(id: 8, name: 'urgent', slug: 'urgent'),
      ],
      trackingState: TopicTrackingState(const [
        TrackedTopicState(
          topicId: 10,
          categoryId: 1,
          createdInNewPeriod: true,
          tagIds: {7, 8},
        ),
        TrackedTopicState(
          topicId: 11,
          categoryId: 2,
          highestPostNumber: 8,
          lastReadPostNumber: 1,
          notificationLevel: 2,
          tagIds: {7},
        ),
        TrackedTopicState(
          topicId: 12,
          categoryId: 99,
          createdInNewPeriod: true,
          tagIds: {7, 8},
        ),
        TrackedTopicState(
          topicId: 13,
          categoryId: 1,
          createdInNewPeriod: true,
          tagIds: {8},
        ),
      ]),
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);
    await controller.selectTopicListMode(TopicListMode.newActivity);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: TopicListNavigation(child: SizedBox())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 4, topics: 3, replies: 1));

    controller.selectTopicListCategory(parent);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 3, topics: 2, replies: 1));

    controller.selectTopicListTags(['bug-fixes']);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 2, topics: 1, replies: 1));
    expect(_tabText(tester, 'topic-list-new-all').data, 'All');
    expect(_tabText(tester, 'topic-list-new-topics').data, 'Topics');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-list-new-topics')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(_tabText(tester, 'topic-list-new-replies').data, 'Replies');
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-list-new-replies')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('topic-list-new-replies')));
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 2, topics: 1, replies: 1));
    expect(controller.sidebarBadgeFor('latest').count, 4);

    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 11,
      'message_type': 'read',
      'payload': {'last_read_post_number': 8},
    });
    await tester.pumpAndSettle();
    expect(_tabText(tester, 'topic-list-new-replies').data, 'Replies');
    expect(controller.sidebarBadgeFor('latest').count, 3);

    controller.selectTopicListTags(['Bug Fixes', 'urgent']);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 1, topics: 1, replies: 0));

    controller.selectTopicListCategory(null);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 2, topics: 2, replies: 0));

    controller.selectTopicListTags(['unknown']);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 0, topics: 0, replies: 0));

    controller.selectTopicListTags([]);
    await tester.pumpAndSettle();
    expect(controller.topicListNewCounts, (all: 3, topics: 3, replies: 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches every web discovery list inside Topics', (
    tester,
  ) async {
    final setup = await _controller();
    final controller = setup.controller;
    final api = setup.api;
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.compact)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic-list-navigation')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-list-category-filter')),
      findsOneWidget,
    );
    expect(find.text('1059'), findsNothing);
    expect(find.byKey(const ValueKey('topic-list-unread')), findsOneWidget);
    expect(find.text('Unread (5)'), findsNothing);
    expect(find.text('Top'), findsOneWidget);
    expect(find.text('Trending'), findsOneWidget);
    expect(find.text('Latest topic'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
    expect(controller.sidebarBadgeFor('latest').count, 1059);

    await _selectFeed(tester, 'topic-list-new');
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(controller.activeTab?.rootDestinationId, 'latest');
    expect(controller.contentStack, hasLength(1));
    expect(_tabText(tester, 'topic-list-new-all').data, 'All');
    expect(find.text('1059'), findsNothing);
    expect(find.text('1054'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('All new activity'), findsOneWidget);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('topic-list-new-segments')),
        matching: find.byType(DBadge),
      ),
      findsNWidgets(2),
    );

    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 4000,
      'message_type': 'unread',
      'payload': {'highest_post_number': 2, 'notification_level': 2},
    });
    // A tracking run notifies the shell once, after the delivery's microtask,
    // so the redraw lands in the frame after that notification.
    await tester.pump();
    await tester.pump();

    expect(find.text('1060'), findsNothing);
    expect(find.text('Unread (6)'), findsNothing);
    expect(_tabText(tester, 'topic-list-new-all').data, 'All');
    expect(find.text('1054'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(controller.sidebarBadgeFor('latest').count, 1060);

    await tester.tap(find.byKey(const ValueKey('topic-list-new-topics')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newTopics);
    expect(find.text('New topic only'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('topic-list-new-replies')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('topic-list-new-replies')));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.newReplies);
    expect(find.text('New reply only'), findsOneWidget);
    await _selectFeed(tester, 'topic-list-top');
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.topYearly);
    expect(find.text('Top this year'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-top-period')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('topic-list-top-period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.topWeekly);
    expect(find.text('Top this week'), findsOneWidget);
    await _selectFeed(tester, 'topic-list-popular');
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.popular);
    expect(find.text('Popular topic'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-top-period')), findsNothing);
    expect(
      api.feedPaths,
      containsAllInOrder(const [
        '/latest.json',
        '/new.json',
        '/new.json?subset=topics',
        '/new.json?subset=replies',
        '/top.json?period=yearly',
        '/top.json?period=weekly',
        '/hot.json',
      ]),
    );
    expect(tester.takeException(), isNull);

    await _selectFeed(tester, 'topic-list-latest');
    await tester.pumpAndSettle();

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(find.byKey(const ValueKey('topic-list-new-all')), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'Inbox new activity is inset and scales without clipping ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(325, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final setup = await _controller();
        addTearDown(setup.controller.dispose);
        await setup.controller.selectTopicListMode(TopicListMode.newActivity);
        final theme = (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: TargetPlatform.macOS,
        );
        Future<void> pump(double scale) async {
          await tester.pumpWidget(
            ShellScope(
              controller: setup.controller,
              child: MaterialApp(
                theme: theme,
                home: MediaQuery(
                  data: MediaQueryData(
                    size: const Size(325, 700),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: const Scaffold(
                    body: TopicListNavigation(stacked: true, child: SizedBox()),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await pump(1);
        final tabs = tester.getRect(
          find.byKey(const ValueKey('topic-list-feed-tabs')),
        );
        final segments = find.byKey(const ValueKey('topic-list-new-segments'));
        final segmentRect = tester.getRect(segments);
        expect(tabs.left, 16);
        expect(tabs.right, lessThanOrEqualTo(309));
        expect(segmentRect.left, tabs.left);
        final filters = tester.getRect(
          find.byKey(const ValueKey('topic-list-category-filter')),
        );
        expect(segmentRect.top, greaterThanOrEqualTo(filters.bottom + 12));
        expect(segmentRect.height, inInclusiveRange(32, 40));
        final all = find.byKey(const ValueKey('topic-list-new-all'));
        final topics = find.byKey(const ValueKey('topic-list-new-topics'));
        final replies = find.byKey(const ValueKey('topic-list-new-replies'));
        expect(tester.getRect(all).left, greaterThan(segmentRect.left));
        expect(
          tester.widget<DTabList<TopicListMode>>(segments).variant,
          DTabListVariant.defaultStyle,
        );
        expect(
          find.descendant(of: topics, matching: find.byType(DBadge)),
          findsOneWidget,
        );
        expect(find.text('All (1059)'), findsNothing);
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(topics);
        await tester.pumpAndSettle();
        await tester.tap(topics);
        await tester.pumpAndSettle();
        expect(setup.controller.currentTopicListMode, TopicListMode.newTopics);
        final semantics = tester.ensureSemantics();
        try {
          expect(tester.getSemantics(topics).label, 'Topics\n1054');
        } finally {
          semantics.dispose();
        }
        await pump(2);
        await tester.ensureVisible(replies);
        await tester.pumpAndSettle();
        await tester.tap(replies);
        await tester.pumpAndSettle();
        expect(setup.controller.currentTopicListMode, TopicListMode.newReplies);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'time range picker applies keyboard choices and cancels cleanly',
    (tester) async {
      final setup = await _controller();
      final controller = setup.controller;
      addTearDown(controller.dispose);
      await controller.selectTopicListMode(TopicListMode.topYearly);
      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
            home: const Scaffold(
              body: TopicListNavigation(stacked: true, child: SizedBox()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final trigger = find.byKey(const ValueKey('topic-list-top-period'));
      final picker = find.byType(DPopoverContent);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        expect(
          tester.getSemantics(find.bySemanticsLabel('Top period')),
          isSemantics(
            label: 'Top period',
            value: 'Year',
            isButton: true,
            hasTapAction: true,
          ),
        );
      } finally {
        semantics.dispose();
      }
      expect(find.text('Period'), findsNothing);
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      expect(picker, findsOneWidget);
      expect(find.text('Year'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(controller.currentTopicListMode, TopicListMode.topYearly);
      final requestsBeforeSelection = [...setup.api.feedPaths];

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(controller.currentTopicListMode, TopicListMode.topWeekly);
      expect(
        find.descendant(of: trigger, matching: find.text('Week')),
        findsOneWidget,
      );
      expect(setup.api.feedPaths, [
        ...requestsBeforeSelection,
        '/top.json?period=weekly',
      ]);

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(picker, findsNothing);
      expect(controller.currentTopicListMode, TopicListMode.topWeekly);
      expect(setup.api.feedPaths, [
        ...requestsBeforeSelection,
        '/top.json?period=weekly',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'wide toolbar keeps selectors before contextual controls without a table heading',
    (tester) async {
      tester.view.physicalSize = const Size(1120, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final setup = await _controller();
      addTearDown(setup.controller.dispose);
      await setup.controller.selectTopicListMode(TopicListMode.newActivity);
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const Scaffold(
              body: MainContent(layout: ShellLayout.expanded),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final category = tester.getRect(
        find.byKey(const ValueKey('topic-list-category-filter')),
      );
      final scope = tester.getRect(
        find.byKey(const ValueKey('topic-list-new-segments')),
      );
      expect(category.right, lessThan(scope.left));
      expect(category.center.dy, closeTo(scope.center.dy, 4));
      expect(
        find.byKey(const ValueKey('topic-list-ledger-header')),
        findsNothing,
      );
      expect(find.text('People'), findsNothing);
      expect(find.text('Latest conversations'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stacked in [false, true]) {
    testWidgets(
      'feed select retains keyboard focus across routes (stacked: $stacked)',
      (tester) async {
        final setup = await _controller();
        addTearDown(setup.controller.dispose);
        final semantics = tester.ensureSemantics();
        try {
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ShellScope(
              controller: setup.controller,
              child: MaterialApp(
                theme: stacked ? AppTheme.dark : AppTheme.light,
                home: Scaffold(
                  body: stacked
                      ? const MainContent(layout: ShellLayout.compact)
                      : const TopicListNavigation(child: SizedBox()),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          await _selectFeed(tester, 'topic-list-top');
          expect(
            setup.controller.currentTopicListMode,
            TopicListMode.topYearly,
          );
          await setup.controller.selectTopicListMode(TopicListMode.topWeekly);
          await tester.pumpAndSettle();
          final tabs = tester.widget<DTabs<TopicListMode>>(
            find.byType(DTabs<TopicListMode>).first,
          );
          expect(tabs.value, TopicListMode.topYearly);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(setup.controller.currentTopicListMode, TopicListMode.popular);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final stacked in [false, true]) {
    testWidgets(
      'new activity tabs preserve keyboard selection and route state ($stacked)',
      (tester) async {
        final setup = await _controller();
        addTearDown(setup.controller.dispose);
        await setup.controller.selectTopicListMode(TopicListMode.newActivity);
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            ShellScope(
              controller: setup.controller,
              child: MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(
                  body: TopicListNavigation(
                    stacked: stacked,
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final all = find.byKey(const ValueKey('topic-list-new-all'));
          final topics = find.byKey(const ValueKey('topic-list-new-topics'));
          final replies = find.byKey(const ValueKey('topic-list-new-replies'));
          bool selected(Finder tab) =>
              tester.getSemantics(tab).flagsCollection.isSelected ==
              Tristate.isTrue;
          bool focused(Finder tab) => tester
              .widget<FocusableActionDetector>(
                find.descendant(
                  of: tab,
                  matching: find.byType(FocusableActionDetector),
                ),
              )
              .focusNode!
              .hasPrimaryFocus;

          await tester.tap(all);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pumpAndSettle();
          expect(focused(topics), isTrue);
          expect(selected(all), isTrue);
          expect(
            setup.controller.currentTopicListMode,
            TopicListMode.newActivity,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(
            setup.controller.currentTopicListMode,
            TopicListMode.newTopics,
          );
          expect(selected(topics), isTrue);
          expect(focused(topics), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.end);
          await tester.sendKeyEvent(LogicalKeyboardKey.space);
          await tester.pumpAndSettle();
          expect(
            setup.controller.currentTopicListMode,
            TopicListMode.newReplies,
          );
          expect(selected(replies), isTrue);
          expect(focused(replies), isTrue);

          await setup.controller.selectTopicListMode(TopicListMode.newActivity);
          await tester.pumpAndSettle();
          expect(selected(all), isTrue);
          expect(selected(replies), isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final scenario in [
    (
      name: 'desktop',
      platform: TargetPlatform.macOS,
      size: const Size(1000, 700),
      layout: ShellLayout.expanded,
      forumTabsEnabled: true,
    ),
    (
      name: 'compact',
      platform: TargetPlatform.iOS,
      size: const Size(360, 800),
      layout: ShellLayout.compact,
      forumTabsEnabled: false,
    ),
  ]) {
    testWidgets(
      'signed-out ${scenario.name} discovery keeps the feed selector above filters and loads their feeds',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = scenario.platform;
        try {
          tester.view.physicalSize = scenario.size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          const category = TopicCategory(
            id: 42,
            name: 'Support',
            slug: 'support',
            color: '3188CC',
          );
          const categoryTopic = Topic(
            id: 9,
            title: 'Public support topic',
            slug: 'public-support-topic',
          );
          final setup = await _controller(
            user: null,
            forumTabsEnabled: scenario.forumTabsEnabled,
            categoryList: const [category],
            extraFeeds: const {
              '/c/support/42.json': [categoryTopic],
            },
          );
          final controller = setup.controller;
          addTearDown(controller.dispose);
          await tester.pumpWidget(
            ShellScope(
              controller: controller,
              child: MaterialApp(
                theme: AppTheme.dark,
                home: Scaffold(body: MainContent(layout: scenario.layout)),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(controller.currentInstance?.user, isNull);
          final primary = find.byKey(const ValueKey('topic-list-primary-row'));
          expect(primary, findsOneWidget);
          expect(find.byKey(const ValueKey('topic-list-top')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-list-popular')),
            findsOneWidget,
          );
          expect(find.text('More'), findsNothing);
          expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);
          final categoryFilter = tester.getRect(
            find.byKey(const ValueKey('topic-list-category-filter')),
          );
          expect(
            categoryFilter.top,
            greaterThanOrEqualTo(tester.getRect(primary).bottom),
          );
          expect(
            find.byKey(const ValueKey('topic-list-ledger-header')),
            findsNothing,
          );
          await _selectFeed(tester, 'topic-list-top');
          await tester.pumpAndSettle();
          expect(controller.currentTopicListMode, TopicListMode.topYearly);
          expect(find.text('Top this year'), findsOneWidget);
          await tester.tap(find.byKey(const ValueKey('topic-list-top-period')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Week'));
          await tester.pumpAndSettle();
          expect(controller.currentTopicListMode, TopicListMode.topWeekly);
          expect(find.text('Top this week'), findsOneWidget);
          await _selectFeed(tester, 'topic-list-popular');
          await tester.pumpAndSettle();
          expect(controller.currentTopicListMode, TopicListMode.popular);
          expect(find.text('Popular topic'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-list-top-period')),
            findsNothing,
          );
          await _selectFeed(tester, 'topic-list-latest');
          await tester.pumpAndSettle();
          expect(find.text('Latest topic'), findsOneWidget);

          await tester.ensureVisible(
            find.byKey(const ValueKey('topic-list-category-filter')),
          );
          await tester.tap(
            find.byKey(const ValueKey('topic-list-category-filter')),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Support'));
          await tester.pumpAndSettle();
          expect(controller.currentContent?.categoryId, category.id);
          expect(find.text('Public support topic'), findsOneWidget);
          expect(primary, findsOneWidget);
          expect(find.byKey(const ValueKey('topic-list-new')), findsNothing);
          expect(setup.api.feedPaths, [
            '/latest.json',
            '/top.json?period=yearly',
            '/top.json?period=weekly',
            '/hot.json',
            '/c/support/42.json',
          ]);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );
  }

  test('signed-out readers cannot select New or unread lists', () async {
    final setup = await _controller(user: null);
    addTearDown(setup.controller.dispose);
    await setup.controller.loadFeed('latest');
    final initialPaths = List<String>.of(setup.api.feedPaths);
    for (final mode in [
      TopicListMode.newActivity,
      TopicListMode.newTopics,
      TopicListMode.newReplies,
      TopicListMode.unread,
    ]) {
      await setup.controller.selectTopicListMode(mode);
      expect(setup.controller.currentTopicListMode, TopicListMode.latest);
    }
    expect(setup.api.feedPaths, initialPaths);
  });

  testWidgets(
    'heading, feed selector and creation stay on one row when resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final setup = await _controller(canCreateTopics: true);
      addTearDown(setup.controller.dispose);
      for (final width in [1800.0, 390.0]) {
        tester.view.physicalSize = Size(width, 700);
        await tester.pumpWidget(
          ShellScope(
            controller: setup.controller,
            child: MaterialApp(
              theme: AppTheme.dark.copyWith(platform: TargetPlatform.macOS),
              home: const Scaffold(
                body: MainContent(layout: ShellLayout.expanded),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heading = tester.getRect(
          find.byKey(const ValueKey('topic-list-heading')),
        );
        final select = tester.getRect(
          find.byKey(const ValueKey('topic-list-feed-tabs')),
        );
        final create = tester.getRect(find.byKey(TopicCreateButton.buttonKey));
        expect(select.top, greaterThanOrEqualTo(heading.top));
        expect(
          create.bottom,
          lessThanOrEqualTo(tester.view.physicalSize.height),
        );
        expect(select.right, lessThanOrEqualTo(tester.view.physicalSize.width));
        expect(
          find.byKey(const ValueKey('topic-list-category-filter')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-list-ledger-header')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('category and tag selections preserve each other in the feed', (
    tester,
  ) async {
    const parent = TopicCategory(
      id: 21,
      name: 'Discourse Native App',
      color: '563A93',
      slug: 'discourse-native-app',
    );
    const child = TopicCategory(
      id: 22,
      name: 'Design',
      color: '3188CC',
      slug: 'design',
      parentCategoryId: 21,
    );
    const ux = SidebarTag(id: 31, name: 'UX', slug: 'ux');
    const categoryTopic = Topic(
      id: 30,
      title: 'Category topic',
      slug: 'category-topic',
    );
    const combinedTopic = Topic(
      id: 31,
      title: 'Combined topic',
      slug: 'combined-topic',
    );
    final setup = await _controller(
      categoryList: const [parent, child],
      categorySiteTopTags: const [ux],
      extraFeeds: const {
        '/c/discourse-native-app/21.json': [categoryTopic],
        '/tag/ux.json': [combinedTopic],
        '/tags/c/discourse-native-app/21/ux.json': [combinedTopic],
        '/tags/c/discourse-native-app/design/22/ux.json': [combinedTopic],
        '/c/discourse-native-app/design/22.json': [categoryTopic],
      },
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.expanded)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    void expectHeading(String title) => expect(
      tester.widget<Text>(find.byKey(const ValueKey('topic-list-title'))).data,
      title,
    );
    expectHeading('Topics');
    controller.selectTopicListCategory(parent);
    await tester.pumpAndSettle();
    expect(controller.currentContent?.categoryId, parent.id);
    expectHeading(parent.name);
    expect(controller.currentContent?.tagName, isNull);
    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(find.text('Category topic'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
      findsOneWidget,
    );

    controller.selectTopicListTag(ux.slug);
    await tester.pumpAndSettle();
    expect(
      controller.currentContent?.feedPath,
      '/tags/c/discourse-native-app/21/ux.json',
    );
    expect(controller.currentContent?.categoryId, parent.id);
    expect(controller.currentContent?.tagName, ux.slug);
    expectHeading(parent.name);
    expect(find.text('Combined topic'), findsOneWidget);

    controller.selectTopicListCategory(null);
    await tester.pumpAndSettle();
    expect(controller.currentContent?.feedPath, '/tag/ux.json');
    expect(controller.currentContent?.categoryId, isNull);
    expectHeading('Topics');
    expect(controller.currentContent?.tagName, ux.slug);

    controller.selectTopicListCategory(parent);
    await tester.pumpAndSettle();
    expect(
      controller.currentContent?.feedPath,
      '/tags/c/discourse-native-app/21/ux.json',
    );

    controller.selectTopicListCategory(child);
    await tester.pumpAndSettle();
    expect(
      controller.currentContent?.feedPath,
      '/tags/c/discourse-native-app/design/22/ux.json',
    );
    expect(controller.currentContent?.categoryId, child.id);
    expectHeading(child.name);
    expect(controller.currentContent?.tagName, ux.slug);

    tester.view.physicalSize = const Size(651, 700);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('topic-list-category-filter')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('topic-list-filters')), findsNothing);
    expect(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('topic-list-tag-filter')), findsOneWidget);
    expect(tester.takeException(), isNull);

    controller.selectTopicListTag(null);
    await tester.pumpAndSettle();
    expect(
      controller.currentContent?.feedPath,
      '/c/discourse-native-app/design/22.json',
    );
    expect(controller.currentContent?.categoryId, child.id);
    expect(controller.currentContent?.tagName, isNull);
    expectHeading(child.name);

    controller.clearTopicListFilters();
    await tester.pumpAndSettle();
    expect(
      controller.currentContent,
      ContentRoute.topicList(TopicListMode.latest),
    );
    expect(find.text('Latest topic'), findsOneWidget);
    expectHeading('Topics');
    expect(find.textContaining('matching topics'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category routes show their names and retain the feed selector', (
    tester,
  ) async {
    const parent = TopicCategory(
      id: 21,
      name: 'Discourse Native App',
      color: '563A93',
      slug: 'discourse-native-app',
    );
    const child = TopicCategory(
      id: 22,
      name: 'Design',
      color: '3188CC',
      slug: 'design',
      parentCategoryId: 21,
    );
    const categories = [parent, child];
    final categoriesById = {
      for (final category in categories) category.id: category,
    };
    final setup = await _controller(
      categoryList: categories,
      extraFeeds: const {
        '/c/discourse-native-app/21.json': [],
        '/c/discourse-native-app/design/22.json': [],
      },
    );
    final controller = setup.controller;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(body: MainContent(layout: ShellLayout.expanded)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final category in categories) {
      controller.selectDestination(
        buildCategoryDestination(category, categoriesById: categoriesById),
      );
      await tester.pumpAndSettle();

      expect(controller.currentContent?.categoryId, category.id);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('topic-list-title')))
            .data,
        category.name,
      );
      expect(controller.currentTopicListMode, TopicListMode.latest);
      expect(
        find.byKey(const ValueKey('topic-list-primary-row')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('topic-list-feed-tabs')),
        findsOneWidget,
      );
    }

    const renamed = TopicCategory(
      id: 22,
      name: 'Design and product research across all community experiences',
      slug: 'design',
      color: '3188CC',
      parentCategoryId: 21,
    );
    controller.store.put(controller.currentInstance!.url, renamed);
    await tester.pump();
    final heading = find.byKey(const ValueKey('topic-list-title'));
    expect(tester.widget<Text>(heading).data, renamed.name);
    expect(find.byTooltip(renamed.name), findsNothing);
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(heading).maxLines, 1);
    expect(tester.widget<Text>(heading).overflow, TextOverflow.ellipsis);
    expect(tester.getRect(heading).right, lessThan(360));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'feed tabs can be reached and clicked in the desktop topic pane',
    (tester) async {
      final setup = await _controller();
      addTearDown(setup.controller.dispose);
      tester.view.physicalSize = const Size(1800, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      setup.controller.openTopic(_latestTopic);
      final theme = AppTheme.dark.copyWith(platform: TargetPlatform.macOS);
      await tester.pumpWidget(
        ShellScope(
          controller: setup.controller,
          child: MaterialApp(theme: theme, home: const AdaptiveShell()),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer();
      final tab = find.byKey(const ValueKey('topic-list-popular'));
      await tester.ensureVisible(tab);
      await tester.pumpAndSettle();
      await mouse.moveTo(tester.getCenter(tab));
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(setup.controller.currentTopicListMode, TopicListMode.popular);
    },
  );

  testWidgets('wide shell divides the sidebar from main content', (
    tester,
  ) async {
    final setup = await _controller();
    final controller = setup.controller;
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ShellScope(
        controller: controller,
        child: MaterialApp(theme: AppTheme.dark, home: const AdaptiveShell()),
      ),
    );
    await tester.pumpAndSettle();

    final divider = find.descendant(
      of: find.byKey(const ValueKey('sidebar-resize-handle')),
      matching: find.byType(ColoredBox),
    );
    expect(divider, findsOneWidget);
    expect(tester.getSize(divider).width, 1);
    final dividerColor = tester.widget<ColoredBox>(divider).color;
    expect(dividerColor, Theme.of(tester.element(divider)).shell.divider);
    expect(tester.takeException(), isNull);
  });

  test('legacy New has no reply subset and counts only new topics', () async {
    const user = DiscourseUser(id: 8, username: 'lee');
    final setup = await _controller(user: user);
    final controller = setup.controller;
    addTearDown(controller.dispose);

    expect(controller.newActivityCount, 1054);
    expect(controller.sidebarBadgeFor('latest').count, 5);

    await controller.selectTopicListMode(TopicListMode.newReplies);

    expect(controller.currentTopicListMode, TopicListMode.latest);
    expect(setup.api.feedPaths, isNot(contains('/new.json?subset=replies')));

    await controller.selectTopicListMode(TopicListMode.newActivity);

    expect(controller.currentTopicListMode, TopicListMode.newActivity);
    expect(setup.api.feedPaths, contains('/new.json'));
  });

  test('uses the forum-configured default period when entering Top', () async {
    final setup = await _controller(
      config: const SiteConfig(topPageDefaultPeriod: 'monthly'),
    );
    addTearDown(setup.controller.dispose);

    expect(setup.controller.defaultTopTopicListMode, TopicListMode.topMonthly);
  });
}

Text _tabText(WidgetTester tester, String key) => tester.widget<Text>(
  find
      .descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))
      .first,
);

Future<({ShellController controller, FakeDiscourseApi api})> _controller({
  DiscourseUser? user = _user,
  SiteConfig config = const SiteConfig.unknown(),
  Completer<void>? trackingStateGate,
  TopicTrackingState? trackingState,
  List<TopicCategory> categoryList = const [],
  List<SidebarTag> categorySiteTopTags = const [],
  List<SidebarTag> tagList = const [],
  Map<String, List<Topic>> extraFeeds = const {},
  bool canCreateTopics = false,
  bool forumTabsEnabled = false,
}) async {
  final totals = user == null
      ? const NotificationTotals()
      : user.unifiedNewEnabled
      ? _unifiedTotals
      : _legacyTotals;
  final site = instance(
    'meta.discourse.org',
    title: 'Discourse Meta',
  ).copyWith(user: user, notificationTotals: totals, config: config);
  final authenticator = FakeAuthenticator();
  if (user != null) authenticator.keys[site.url] = 'api-key';
  final api = FakeDiscourseApi(
    creatableFeedPaths: canCreateTopics ? const {'/latest.json'} : const {},
    user: user,
    totals: totals,
    trackingStateGate: trackingStateGate,
    trackingState:
        trackingState ??
        TopicTrackingState([
          for (var index = 0; index < 1054; index++)
            TrackedTopicState(
              topicId: 1000 + index,
              highestPostNumber: 1,
              createdInNewPeriod: true,
            ),
          for (var index = 0; index < 5; index++)
            TrackedTopicState(
              topicId: 3000 + index,
              highestPostNumber: 2,
              lastReadPostNumber: 1,
              notificationLevel: 2,
            ),
        ]),
    feeds: {
      '/latest.json': [_latestTopic],
      '/new.json': [_allNewTopic],
      '/new.json?subset=topics': [_newTopic],
      '/new.json?subset=replies': [_newReply],
      '/top.json?period=yearly': [_topYearTopic],
      '/top.json?period=weekly': [_topWeekTopic],
      '/hot.json': [_popularTopic],
      ...extraFeeds,
    },
    categoryList: categoryList,
    categorySiteTopTags: categorySiteTopTags,
    tagList: tagList,
  );
  final controller = ShellController(
    instanceStore: FakeInstanceStore([site]),
    api: api,
    authenticator: authenticator,
    drafts: FakeDraftStore(),
    forumTabs: FakeForumTabStore(),
    forumTabsEnabled: forumTabsEnabled,
    trackers: FakeSiteTracker.reset(),
    updater: FakeUpdater(),
    updateStore: FakeUpdateStore(),
    ownsApi: false,
  );
  await controller.load();
  return (controller: controller, api: api);
}

Future<void> _selectFeed(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}
