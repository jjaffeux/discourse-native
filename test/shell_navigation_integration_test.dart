import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        kBackMouseButton,
        kForwardMouseButton,
        kLongPressTimeout,
        kMiddleMouseButton,
        kPrimaryMouseButton,
        kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerShellNavigationTests();
  _registerShellUpdateTests();
}

void _registerShellNavigationTests() {
  group('forum search', () {
    testWidgets('uses the macOS title strip and current non-macOS headers', (
      tester,
    ) async {
      await pumpShell(tester, laptop);

      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
      final linuxLikeField = tester.getRect(find.byKey(ForumSearch.inputKey));
      expect(
        tester
            .getRect(find.byType(MainContent))
            .contains(linuxLikeField.center),
        isTrue,
      );

      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(
          tester,
          desktop,
          key: const ValueKey('mac-search-placement'),
        );
        final titleBar = tester.getRect(find.byType(ShellTitleBar));
        final macField = tester.getRect(find.byKey(ForumSearch.inputKey));
        expect(titleBar.contains(macField.center), isTrue);
        expect(
          tester.getSize(find.byType(ForumSearch)).height,
          lessThan(ShellTitleBar.height),
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('is unavailable on Aggregate', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(tester, desktop);
        final controller = ShellScope.read(
          tester.element(find.byType(ShellTitleBar)),
        );

        expect(find.byType(ForumSearch), findsOneWidget);

        controller.selectAggregate();
        await tester.pumpAndSettle();

        expect(find.byType(ForumSearch), findsNothing);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isFalse);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(find.byKey(ForumSearch.panelKey), findsNothing);

        controller.selectInstance(0);
        await tester.pump();

        expect(find.byType(ForumSearch), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(
          tester
              .widget<EditableText>(find.byKey(ForumSearch.inputKey))
              .focusNode
              .hasFocus,
          isTrue,
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('double clicking the macOS title strip toggles window zoom', (
      tester,
    ) async {
      final calls = <MethodCall>[];
      const channel = MethodChannel('org.discourse.native/window');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );

      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(tester, desktop);
        final titleBar = tester.getRect(find.byType(ShellTitleBar));
        final background = find.byKey(ShellTitleBar.maximizeGestureKey);

        expect(background, findsOneWidget);
        await tester.tapAt(titleBar.centerLeft + const Offset(76, 0));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(titleBar.centerLeft + const Offset(76, 0));
        await tester.pump(const Duration(milliseconds: 50));

        expect(calls, [isMethodCall('toggleMaximized', arguments: null)]);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('keeps compact sidebar identity above its search field', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      final title = tester.getRect(find.text('Discourse Meta'));
      final field = tester.getRect(find.byKey(ForumSearch.inputKey));
      final searchTarget = find
          .descendant(
            of: find.byKey(const ValueKey('instance-sidebar-search-target')),
            matching: find.byType(GestureDetector),
          )
          .first;
      expect(field.top, greaterThanOrEqualTo(title.bottom));
      expect(searchTarget, findsOneWidget);
      expect(tester.getSize(searchTarget).width, greaterThanOrEqualTo(44));
      expect(find.byType(InstanceSidebar), findsOneWidget);

      await tester.tap(searchTarget);
      await tester.pump();

      final focusNode = tester
          .widget<EditableText>(find.byKey(ForumSearch.inputKey))
          .focusNode;
      expect(focusNode.hasFocus, isTrue);
    });

    testWidgets(
      'opens initial options for an empty field and returns on clear',
      (tester) async {
        await pumpShell(tester, laptop);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );

        await tester.tap(find.byKey(ForumSearch.inputKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
        expect(
          find.byKey(const ValueKey('forum-search-quick-tip')),
          findsOneWidget,
        );

        await tester.enterText(find.byKey(ForumSearch.inputKey), 'matching');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('forum-search-clear')));
        await tester.pumpAndSettle();

        expect(controller.search.query, isEmpty);
        expect(controller.search.panelOpen, isTrue);
        expect(
          tester
              .widget<EditableText>(find.byKey(ForumSearch.inputKey))
              .focusNode
              .hasFocus,
          isTrue,
        );
        expect(
          find.byKey(const ValueKey('forum-search-quick-tip')),
          findsOneWidget,
        );
      },
    );

    testWidgets('searches live without navigating and opens the matched post', (
      tester,
    ) async {
      const hit = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 3,
        topicTitle: 'Search topic',
        topicSlug: 'search-topic',
        username: 'sam',
        excerpt: SearchExcerpt([
          SearchExcerptSegment('A '),
          SearchExcerptSegment('matching', highlighted: true),
          SearchExcerptSegment(' result'),
        ]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          'matching': SearchResults(hits: [hit]),
        },
        topics: {7: topicPayload(id: 7, title: 'Search topic')},
      );
      await pumpShell(tester, laptop, api: api);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      final routeBefore = controller.currentContent;

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'matching');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(api.searchesRequested.single.term, 'matching');
      expect(api.searchesRequested.single.typeFilter, 'exclude_topics');
      expect(controller.currentContent, routeBefore);
      expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
      expect(find.text('Search topic'), findsNothing);
      expect(
        find.byKey(const ValueKey('forum-search-topics-action')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('forum-search-topics-action')),
      );
      await tester.pumpAndSettle();

      expect(api.searchesRequested.last.typeFilter, isNull);
      expect(find.text('Search topic'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('search-hit-70')));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.topicPostNumbersOpened, [3]);
      expect(controller.currentContent?.topicId, 7);
      expect(controller.search.query, isEmpty);
    });

    testWidgets('renders site emoji in search titles and excerpts', (
      tester,
    ) async {
      const hit = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 3,
        topicTitle: 'News :sparkles:',
        topicSlug: 'news',
        username: 'sam',
        excerpt: SearchExcerpt([
          SearchExcerptSegment('Bard :'),
          SearchExcerptSegment('cry', highlighted: true),
          SearchExcerptSegment(': image'),
        ]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          'emoji': SearchResults(hits: [hit]),
        },
        emojisBySite: {
          'https://meta.discourse.org': const [
            SiteEmoji(name: 'sparkles', url: '/images/emoji/sparkles.png'),
            SiteEmoji(name: 'cry', url: '/images/emoji/cry.png'),
          ],
        },
      );
      await pumpShell(tester, laptop, api: api);
      replaceEmojiCache(
        MockClient((_) async => http.Response.bytes(emojiPng, 200)),
      );

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'emoji');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('forum-search-topics-action')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<SiteEmojiImage>(find.byType(SiteEmojiImage))
            .map((emoji) => emoji.name),
        ['sparkles', 'cry'],
      );
      expect(find.textContaining(':sparkles:'), findsNothing);
      expect(find.textContaining(':cry:'), findsNothing);
    });

    testWidgets('obeys core headline and tag presentation settings', (
      tester,
    ) async {
      const site = 'https://meta.discourse.org';
      const hit = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 1,
        topicTitle: 'Original title',
        topicSlug: 'original-title',
        topicTitleExcerpt: SearchExcerpt([
          SearchExcerptSegment('Highlighted title', highlighted: true),
        ]),
        tags: [TopicTag(name: 'hidden-tag')],
        pinned: true,
        username: 'sam',
        excerpt: SearchExcerpt([SearchExcerptSegment('A result')]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          'presentation': SearchResults(hits: [hit]),
        },
        siteConfigs: const {
          site: SiteConfig(
            taggingEnabled: false,
            usePgHeadlinesForExcerpt: true,
          ),
        },
      );
      await pumpShell(tester, laptop, api: api);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'presentation');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('forum-search-topics-action')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Highlighted title'), findsOneWidget);
      expect(find.text('Original title'), findsNothing);
      expect(find.text('hidden-tag'), findsNothing);
      expect(find.bySemanticsLabel('Pinned'), findsOneWidget);
    });

    testWidgets('shows core facets first and topics after Enter', (
      tester,
    ) async {
      const topic = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 3,
        topicTitle: 'Search topic',
        topicSlug: 'search-topic',
        username: 'sam',
        excerpt: SearchExcerpt([SearchExcerptSegment('A result')]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          '@sam test': SearchResults(
            hits: [topic],
            sections: [
              SearchResultSection(
                kind: SearchResultKind.topic,
                results: [topic],
              ),
              SearchResultSection(
                kind: SearchResultKind.category,
                results: [
                  SearchCategoryHit(
                    categoryId: 3,
                    name: 'Development',
                    slug: 'dev',
                  ),
                ],
              ),
              SearchResultSection(
                kind: SearchResultKind.tag,
                results: [SearchTagHit(tagId: 4, name: 'flaky-test')],
              ),
              SearchResultSection(
                kind: SearchResultKind.user,
                results: [
                  SearchUserHit(
                    userId: 5,
                    username: 'sam',
                    name: 'Sam Example',
                  ),
                ],
              ),
              SearchResultSection(
                kind: SearchResultKind.group,
                results: [
                  SearchGroupHit(
                    groupId: 6,
                    name: 'automation-test',
                    fullName: 'Automation Test',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      await pumpShell(tester, laptop, api: api);

      await tester.enterText(find.byKey(ForumSearch.inputKey), '@sam test');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      final searchInput = tester
          .widget<EditableText>(find.byKey(ForumSearch.inputKey))
          .focusNode;

      expect(api.searchesRequested.single.typeFilter, 'exclude_topics');
      expect(searchInput.hasFocus, isTrue);
      expect(controller.search.topicsActionSelected, isFalse);
      expect(find.byKey(const ValueKey('search-hit-70')), findsNothing);
      expect(
        find.byKey(const ValueKey('forum-search-topics-action')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('search-category-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-tag-4')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-user-5')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-group-6')), findsOneWidget);
      expect(find.text('flaky-test'), findsOneWidget);
      expect(find.text('Automation Test'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.search.topicsActionSelected, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.search.selectedResult, isA<SearchCategoryHit>());
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.search.topicsActionSelected, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(api.searchesRequested.last.typeFilter, isNull);
      expect(find.byKey(const ValueKey('search-hit-70')), findsOneWidget);
      expect(find.byKey(const ValueKey('search-tag-4')), findsNothing);
      expect(find.byKey(const ValueKey('search-group-6')), findsNothing);
    });

    testWidgets('supports the focus shortcut, arrows, enter, and escape', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        searchResults: {
          'matches': SearchResults(
            hits: [
              for (var id = 1; id <= 2; id++)
                SearchPostHit(
                  postId: id,
                  topicId: id,
                  postNumber: id + 1,
                  topicTitle: 'Result $id',
                  topicSlug: 'result-$id',
                  username: 'sam',
                  excerpt: const SearchExcerpt([SearchExcerptSegment('match')]),
                ),
            ],
          ),
        },
        topics: {2: topicPayload(id: 2, title: 'Result 2')},
      );
      await pumpShell(tester, laptop, api: api);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      final searchInput = tester
          .widget<EditableText>(find.byKey(ForumSearch.inputKey))
          .focusNode;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyK), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(searchInput.hasFocus, isFalse);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byKey(ForumSearch.inputKey))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'matches');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(searchInput.hasFocus, isTrue);
      expect(controller.search.selectedIndex, -1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.search.selectedIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.search.selectedIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(controller.search.selectedIndex, 0);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(controller.search.selectedIndex, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.topicsOpened, [2]);

      controller.handleBack(canReturnToSidebar: false);
      await tester.pumpAndSettle();
      controller.search.setQuery('matches');
      controller.search.requestFocus();
      await tester.pump();
      expect(
        tester
            .widget<EditableText>(find.byKey(ForumSearch.inputKey))
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.search.panelOpen, isFalse);
      expect(controller.search.query, 'matches');
      expect(
        tester
            .widget<EditableText>(find.byKey(ForumSearch.inputKey))
            .focusNode
            .hasFocus,
        isFalse,
      );
    });

    testWidgets('Command F opens search scoped to the current topic', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          topics: {7: topicPayload(id: 7, title: 'Scoped topic')},
          searchResults: const {'needle': SearchResults()},
        );
        final launched = watchBrowser(tester);
        await pumpShell(tester, laptop, api: api);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
        expect(controller.search.topicId, isNull);

        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'scoped-topic',
            title: 'Scoped topic',
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        expect(controller.search.topicId, 7);
        expect(find.text('Search this topic'), findsOneWidget);
        expect(
          tester
              .widget<EditableText>(find.byKey(ForumSearch.inputKey))
              .focusNode
              .hasFocus,
          isTrue,
        );

        await tester.enterText(find.byKey(ForumSearch.inputKey), 'needle');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(api.searchesRequested.single.term, 'needle');
        expect(api.searchesRequested.single.typeFilter, isNull);
        expect(api.searchesRequested.single.topicId, 7);

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(launched, [
          'https://meta.discourse.org/search?q=needle+topic%3A7',
        ]);
        expect(controller.search.topicId, isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('opens a scoped search result at its matched post', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const hit = SearchPostHit(
          postId: 70,
          topicId: 7,
          postNumber: 3,
          topicTitle: 'Scoped topic',
          topicSlug: 'scoped-topic',
          username: 'sam',
          excerpt: SearchExcerpt([SearchExcerptSegment('needle')]),
        );
        final api = FakeDiscourseApi(
          topics: {7: topicPayload(id: 7, title: 'Scoped topic')},
          searchResults: const {
            'needle': SearchResults(hits: [hit]),
          },
        );
        await pumpShell(tester, laptop, api: api);
        final controller = ShellScope.read(
          tester.element(find.byType(MainContent)),
        );

        controller.pushContent(
          ContentRoute.topic(
            topicId: 7,
            slug: 'scoped-topic',
            title: 'Scoped topic',
          ),
        );
        await tester.pumpAndSettle();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(ForumSearch.inputKey), 'needle');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('search-hit-70')));
        await tester.pumpAndSettle();

        expect(controller.currentContent?.topicId, 7);
        expect(controller.currentContent?.postNumber, 3);
        expect(controller.search.query, isEmpty);
        expect(controller.search.topicId, isNull);
        expect(api.topicPostNumbersOpened.last, 3);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('Ctrl Enter opens the selected result externally', (
      tester,
    ) async {
      const hit = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 2,
        topicTitle: 'External result',
        topicSlug: 'external-result',
        username: 'sam',
        excerpt: SearchExcerpt([SearchExcerptSegment('match')]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          'external': SearchResults(hits: [hit]),
        },
      );
      final launched = watchBrowser(tester);
      await pumpShell(tester, laptop, api: api);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'external');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/t/external-result/7/2']);
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('a second Enter opens the full search page', (tester) async {
      const hit = SearchPostHit(
        postId: 70,
        topicId: 7,
        postNumber: 1,
        topicTitle: 'Full search result',
        topicSlug: 'full-search-result',
        username: 'sam',
        excerpt: SearchExcerpt([SearchExcerptSegment('match')]),
      );
      final api = FakeDiscourseApi(
        searchResults: const {
          'two enters': SearchResults(hits: [hit]),
        },
      );
      final launched = watchBrowser(tester);
      await pumpShell(tester, laptop, api: api);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'two enters');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('search-hit-70')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/search?q=two+enters']);
      expect(find.byKey(ForumSearch.panelKey), findsNothing);
    });

    testWidgets('shows distinct selected and hovered result states', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        searchResults: {
          'matches': SearchResults(
            hits: [
              for (var id = 1; id <= 2; id++)
                SearchPostHit(
                  postId: id,
                  topicId: id,
                  postNumber: 1,
                  topicTitle: 'Result $id',
                  topicSlug: 'result-$id',
                  username: 'sam',
                  excerpt: const SearchExcerpt([SearchExcerptSegment('match')]),
                ),
            ],
          ),
        },
      );
      await pumpShell(tester, laptop, api: api);

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'matches');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      const firstKey = ValueKey('search-hit-1');
      const secondKey = ValueKey('search-hit-2');
      final theme = Theme.of(tester.element(find.byKey(firstKey)));
      Color? background(Key key) {
        final ink = tester.widget<Ink>(
          find.descendant(of: find.byKey(key), matching: find.byType(Ink)),
        );
        return (ink.decoration as BoxDecoration).color;
      }

      expect(background(firstKey), theme.shell.selected);
      expect(background(secondKey), Colors.transparent);
      expect(
        tester.widget<InkWell>(find.byKey(firstKey)).hoverColor,
        theme.shell.hover,
      );
      expect(
        tester.widget<InkWell>(find.byKey(secondKey)).hoverColor,
        theme.shell.hover,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      expect(background(firstKey), Colors.transparent);
      expect(background(secondKey), theme.shell.selected);
    });

    testWidgets('keeps the arrow-key selection visible', (tester) async {
      final api = FakeDiscourseApi(
        searchResults: {
          'many matches': SearchResults(
            hits: [
              for (var id = 1; id <= 8; id++)
                SearchPostHit(
                  postId: id,
                  topicId: id,
                  postNumber: 1,
                  topicTitle: 'Result $id',
                  topicSlug: 'result-$id',
                  username: 'sam',
                  excerpt: const SearchExcerpt([SearchExcerptSegment('match')]),
                ),
            ],
          ),
        },
      );
      await pumpShell(tester, laptop, api: api);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );

      await tester.enterText(find.byKey(ForumSearch.inputKey), 'many matches');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      for (var index = 0; index < 8; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.pump();

      expect(controller.search.selectedIndex, 7);
      final panel = tester.getRect(find.byKey(ForumSearch.panelKey));
      final selected = tester.getRect(
        find.byKey(const ValueKey('search-hit-8')),
      );
      expect(selected.top, greaterThanOrEqualTo(panel.top));
      expect(selected.bottom, lessThanOrEqualTo(panel.bottom));
    });

    testWidgets('closes and unfocuses when tapping outside the search input', (
      tester,
    ) async {
      await pumpShell(tester, laptop);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );

      controller.search.setQuery('matches');
      controller.search.requestFocus();
      await tester.pumpAndSettle();

      final searchInput = tester
          .widget<EditableText>(find.byKey(ForumSearch.inputKey))
          .focusNode;
      expect(controller.search.panelOpen, isTrue);
      expect(searchInput.hasFocus, isTrue);

      final content = tester.getRect(find.byType(MainContent));
      await tester.tapAt(content.bottomCenter - const Offset(0, 20));
      await tester.pumpAndSettle();

      expect(controller.search.panelOpen, isFalse);
      expect(searchInput.hasFocus, isFalse);
      expect(controller.search.query, 'matches');
    });
  });

  group('compact shell layout', () {
    testWidgets('shows the rail and the sidebar, but no main content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('selecting a destination replaces the sidebar with content', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      final topics = sidebarDestination('Topics');
      final target = find
          .ancestor(of: topics, matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(target).height, closeTo(38.4, 0.01));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(44));

      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('back returns from content to the sidebar', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
    });

    testWidgets('back unwinds the content stack before the sidebar', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      ShellScope.read(tester.element(find.byType(MainContent))).pushContent(
        const ContentRoute(
          id: 'topic-placeholder',
          title: 'Topic 1',
          icon: DIcons.comments,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Topic 1'), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
    });

    testWidgets('a system back at the root hands the gesture to the platform', (
      tester,
    ) async {
      final exits = _watchAppExits(tester);
      await pumpShell(tester, phone);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();

      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(exits, isEmpty);

      // Nothing left to unwind. The shell's own PopScope swallowed the event,
      // so leaving the app has to be an explicit request to the platform.
      await _systemBack(tester);
      await tester.pumpAndSettle();
      expect(exits, hasLength(1));
    });

    testWidgets('mouse side buttons stay within content history', (
      tester,
    ) async {
      await pumpShell(tester, phone);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      Future<void> tapMouseButton(int button) async {
        await tester.tap(
          find.byType(MainContent),
          buttons: button,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
      }

      await tapMouseButton(kBackMouseButton);
      expect(find.byType(MainContent), findsOneWidget);
      expect(shell.currentContent?.id, 'latest');

      shell.pushContent(
        const ContentRoute(
          id: 'compact-mouse-history',
          title: 'Compact mouse history',
          icon: DIcons.comments,
        ),
      );
      await tester.pumpAndSettle();

      await tapMouseButton(kBackMouseButton);
      expect(find.byType(MainContent), findsOneWidget);
      expect(shell.currentContent?.id, 'latest');

      await tapMouseButton(kForwardMouseButton);
      expect(shell.currentContent?.id, 'compact-mouse-history');
    });

    testWidgets('the avatar follows whichever pane is showing', (tester) async {
      await pumpShell(tester, phone);

      expect(userMenu, findsOneWidget);
      final onSidebar = tester.getRect(userMenu);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();

      expect(userMenu, findsOneWidget);
      expect(tester.getRect(userMenu), onSidebar);
    });
  });

  group('medium shell layout', () {
    testWidgets('shows rail, sidebar and content together', (tester) async {
      await pumpShell(tester, laptop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });
  });

  group('expanded shell layout', () {
    testWidgets('shows rail, sidebar and content', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });

    testWidgets(
      'mouse side buttons navigate content history and respect overlays',
      (tester) async {
        await pumpShell(tester, desktop);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.pushContent(
          const ContentRoute(
            id: 'mouse-history',
            title: 'Mouse history',
            icon: DIcons.comments,
          ),
        );
        await tester.pumpAndSettle();

        Future<void> tapMouseButton(int button, {Finder? target}) async {
          await tester.tap(
            target ?? contentText(shell.currentContent!.title).last,
            buttons: button,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pumpAndSettle();
        }

        for (final button in [kPrimaryMouseButton, kMiddleMouseButton]) {
          await tapMouseButton(button);
          expect(shell.currentContent?.id, 'mouse-history');
        }

        await tapMouseButton(kBackMouseButton);
        expect(shell.currentContent?.id, 'latest');

        unawaited(
          showDialog<void>(
            context: tester.element(find.byType(MainContent)),
            builder: (context) =>
                const AlertDialog(title: Text('Mouse navigation dialog')),
          ),
        );
        await tester.pumpAndSettle();

        await tapMouseButton(
          kForwardMouseButton,
          target: find.text('Mouse navigation dialog'),
        );
        expect(find.text('Mouse navigation dialog'), findsOneWidget);
        expect(shell.currentContent?.id, 'latest');

        await tapMouseButton(
          kBackMouseButton,
          target: find.text('Mouse navigation dialog'),
        );
        expect(find.text('Mouse navigation dialog'), findsNothing);
        expect(shell.currentContent?.id, 'latest');

        await tapMouseButton(kForwardMouseButton);
        expect(shell.currentContent?.id, 'mouse-history');
      },
    );

    testWidgets('mouse Back exits app Settings', (tester) async {
      await pumpShell(tester, desktop);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await tester.tap(find.byKey(const ValueKey('settings-rail-button')));
      await tester.pumpAndSettle();
      expect(shell.rootMode, ShellRootMode.settings);

      await tester.tap(
        find.byKey(const ValueKey('app-settings-form')),
        buttons: kBackMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(shell.rootMode, ShellRootMode.forum);
      expect(find.byType(MainContent), findsOneWidget);
    });

    testWidgets('the avatar sits in the top right corner', (tester) async {
      await pumpShell(tester, desktop);

      expect(userMenu, findsOneWidget);

      final content = tester.getRect(find.byType(MainContent));
      final avatar = tester.getRect(userMenu);

      expect(content.right - avatar.right, lessThan(16));
      expect(avatar.top - content.top, lessThan(shellHeaderHeight));
    });
  });

  testWidgets('switching instance swaps the sidebar contents', (tester) async {
    await pumpShell(tester, desktop);

    expect(find.text('Discourse Meta'), findsOneWidget);

    await tester.tap(find.text('DT'));
    await tester.pumpAndSettle();

    expect(find.text('Discourse Team'), findsOneWidget);
    expect(find.text('Discourse Meta'), findsNothing);
  });

  testWidgets('keeps Groups in More until the group route is active', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    expect(sidebarDestination('Groups'), findsNothing);
    expect(sidebarDestination('Filter'), findsNothing);
    expect(sidebarDestination('More'), findsOneWidget);

    await tester.tap(sidebarDestination('More'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Groups'), findsOneWidget);
    expect(find.widgetWithText(MenuItemButton, 'Filter'), findsOneWidget);

    await tester.tap(find.widgetWithText(MenuItemButton, 'Groups'));
    await tester.pumpAndSettle();

    expect(sidebarDestination('Groups'), findsOneWidget);
    expect(sidebarDestination('More'), findsOneWidget);

    await tester.tap(sidebarDestination('More'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(MenuItemButton, 'Groups'), findsNothing);
    expect(find.widgetWithText(MenuItemButton, 'Filter'), findsOneWidget);
  });

  testWidgets('promotes Groups for a group detail opened over another route', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );
    controller.pushContent(
      ContentRoute.group(
        GroupRoute.detail(
          'staff',
          section: GroupRoute.activity,
          subsection: GroupRoute.posts,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.destinationId, 'latest');
    expect(sidebarDestination('Groups'), findsOneWidget);
  });

  testWidgets('uses a home icon for the aggregate route', (tester) async {
    await pumpShell(tester, desktop);

    final aggregateButton = find.byKey(const ValueKey('aggregate-rail-button'));

    expect(
      find.descendant(of: aggregateButton, matching: find.dIcon(DIcons.house)),
      findsOneWidget,
    );
  });

  testWidgets('rail marker grows from idle dot through hover to active pill', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    Finder item(DiscourseInstance instance) =>
        find.byKey(ValueKey(instance.url));
    Finder indicator(DiscourseInstance instance) =>
        find.byKey(ValueKey('instance-rail-marker-${instance.url}'));
    AnimatedContainer marker(DiscourseInstance instance) =>
        tester.widget(indicator(instance));
    double targetHeight(DiscourseInstance instance) =>
        marker(instance).constraints!.minHeight;

    final selected = twoSites.first;
    final inactive = twoSites.last;
    expect(targetHeight(selected), 32);
    expect(targetHeight(inactive), 8);
    expect(marker(inactive).duration, const Duration(milliseconds: 180));
    expect(marker(inactive).curve, Curves.easeOutCubic);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(item(inactive)));
    await tester.pump();

    expect(targetHeight(inactive), 16);
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getSize(indicator(inactive)).height,
      allOf(greaterThan(8), lessThan(16)),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 16);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 8);

    await gesture.moveTo(tester.getCenter(item(inactive)));
    await tester.pumpAndSettle();
    await tester.tap(item(inactive));
    await tester.pump();

    expect(targetHeight(selected), 8);
    expect(targetHeight(inactive), 32);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(selected)).height, 8);
    expect(tester.getSize(indicator(inactive)).height, 32);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 32);
  });

  testWidgets('shows custom sidebar sections and opens their links', (
    tester,
  ) async {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: me);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final api = FakeDiscourseApi(
      feeds: const {'/c/roadmap/4.json': []},
      customSidebarSectionsBySite: {
        site.url: const [
          SidebarSection(
            id: 'custom-2',
            title: 'Projects',
            destinations: [
              SidebarDestination(
                id: 'custom-2-20',
                label: 'Roadmap',
                icon: DIcons.fire,
                url: '/c/roadmap/4',
              ),
            ],
          ),
        ],
      },
    );

    await pumpShell(
      tester,
      laptop,
      instances: [site],
      api: api,
      authenticator: auth,
    );

    expect(find.text('PROJECTS'), findsOneWidget);
    expect(sidebarDestination('Roadmap'), findsOneWidget);
    final moreTile = find
        .ancestor(
          of: sidebarDestination('More'),
          matching: find.byType(InkWell),
        )
        .first;
    final projectsHeader = find
        .ancestor(of: find.text('PROJECTS'), matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(projectsHeader).top - tester.getRect(moreTile).bottom,
      closeTo(7, 0.01),
    );
    final roadmapTile = find
        .ancestor(
          of: sidebarDestination('Roadmap'),
          matching: find.byType(InkWell),
        )
        .first;
    final categoriesHeader = find
        .ancestor(of: find.text('CATEGORIES'), matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(categoriesHeader).top - tester.getRect(roadmapTile).bottom,
      closeTo(7, 0.01),
    );
    expect(tester.getSize(projectsHeader).height, closeTo(24, 0.01));
    expect(tester.getSize(roadmapTile).height, closeTo(30, 0.01));

    await tester.tap(find.byTooltip('Collapse Projects'));
    await tester.pumpAndSettle();
    expect(sidebarDestination('Roadmap'), findsNothing);

    await tester.tap(find.byTooltip('Expand Projects'));
    await tester.pumpAndSettle();
    expect(sidebarDestination('Roadmap'), findsOneWidget);

    await tester.tap(sidebarDestination('Roadmap'));
    await tester.pumpAndSettle();

    expect(api.feedPaths, contains('/c/roadmap/4.json'));
  });

  testWidgets('keeps the sidebar scroll boundary stable near its end', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: me);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final destinations = [
      for (var index = 0; index < 24; index++)
        SidebarDestination(
          id: 'long-scroll-$index',
          label: 'Long destination $index',
          icon: DIcons.link,
        ),
    ];
    final api = FakeDiscourseApi(
      user: me,
      customSidebarSectionsBySite: {
        site.url: [
          SidebarSection(
            id: 'long-scroll-boundary',
            title: 'Long section',
            destinations: destinations,
          ),
        ],
      },
    );

    await pumpShell(
      tester,
      const Size(1000, 400),
      instances: [site],
      api: api,
      authenticator: auth,
    );

    final scrollable = find.descendant(
      of: find.byType(InstanceSidebar),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final initialMax = position.maxScrollExtent;
    expect(initialMax, greaterThan(position.viewportDimension));

    // The old two-child list let a macOS trackpad reach this estimated
    // boundary before the shorter plugin column was laid out. Lazy rows must
    // keep the replacement's exact boundary while materializing the end.
    position.jumpTo(initialMax);
    await tester.pumpAndSettle();

    expect(position.maxScrollExtent, closeTo(initialMax, 0.001));
    expect(position.pixels, closeTo(initialMax, 0.001));
  });

  testWidgets('uses a thin scrollbar in the sidebar', (tester) async {
    final previous = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpShell(tester, desktop);

      final scrollbar = find.descendant(
        of: find.byType(InstanceSidebar),
        matching: find.byType(Scrollbar),
      );
      expect(scrollbar, findsOneWidget);
      expect(
        ScrollbarTheme.of(
          tester.element(scrollbar),
        ).thickness?.resolve(const <WidgetState>{}),
        4,
      );
    } finally {
      debugDefaultTargetPlatformOverride = previous;
    }
  });

  testWidgets('builds only sidebar destinations near the viewport', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: me);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final destinations = [
      for (var index = 0; index < 200; index++)
        SidebarDestination(
          id: 'lazy-row-$index',
          label: 'Lazy destination $index',
          icon: DIcons.link,
        ),
    ];
    final api = FakeDiscourseApi(
      user: me,
      customSidebarSectionsBySite: {
        site.url: [
          SidebarSection(
            id: 'lazy-destinations',
            title: 'Lazy destinations',
            destinations: destinations,
            collapsible: false,
          ),
        ],
      },
    );

    await pumpShell(
      tester,
      const Size(1000, 400),
      instances: [site],
      api: api,
      authenticator: auth,
    );

    final sidebar = find.byType(InstanceSidebar);
    Finder row(int index) => find.descendant(
      of: sidebar,
      matching: find.byKey(ValueKey('lazy-row-$index')),
    );
    final mountedRows = find.descendant(
      of: sidebar,
      matching: find.byWidgetPredicate((widget) {
        final key = widget.key;
        return key is ValueKey<String> && key.value.startsWith('lazy-row-');
      }),
    );

    expect(row(199), findsNothing);
    expect(mountedRows.evaluate().length, lessThan(destinations.length ~/ 2));

    final scrollable = find.descendant(
      of: sidebar,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(row(199), 500, scrollable: scrollable);
    await tester.pumpAndSettle();

    expect(row(199), findsOneWidget);
    expect(mountedRows.evaluate().length, lessThan(destinations.length ~/ 2));
  });

  testWidgets('shows preferred categories and opens their native lists', (
    tester,
  ) async {
    const storedUser = DiscourseUser(
      id: 7,
      username: 'joffreyj',
      name: 'Joffrey',
    );
    const freshUser = DiscourseUser(
      id: 7,
      username: 'joffreyj',
      name: 'Joffrey',
      sidebarCategoryIds: [2],
    );
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: storedUser);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final api = FakeDiscourseApi(
      user: freshUser,
      feeds: const {
        '/latest.json': [],
        '/c/parent/1.json': [],
        '/c/parent/child/2.json': [
          Topic(
            id: 7,
            title: 'A category topic',
            slug: 'a-category-topic',
            categoryId: 2,
          ),
        ],
      },
      topics: {
        7: topicPayload(
          id: 7,
          title: 'A category topic',
          posts: const [
            Post(
              id: 70,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>Category topic body</p>',
            ),
          ],
          stream: const [70],
        ),
      },
      categoryList: const [
        TopicCategory(id: 1, name: 'Parent', color: '112233', slug: 'parent'),
        TopicCategory(
          id: 2,
          name: 'Child',
          color: '445566',
          slug: 'child',
          parentCategoryId: 1,
          readRestricted: true,
        ),
        TopicCategory(
          id: 3,
          name: 'Not selected',
          color: '778899',
          slug: 'not-selected',
        ),
      ],
    );

    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: api,
      authenticator: auth,
    );

    expect(find.text('CATEGORIES'), findsOneWidget);
    expect(sidebarDestination('Child'), findsOneWidget);
    expect(sidebarDestination('Parent'), findsNothing);
    expect(sidebarDestination('Not selected'), findsNothing);
    expect(sidebarDestination('All categories'), findsOneWidget);
    final childTile = find
        .ancestor(
          of: sidebarDestination('Child'),
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      find.descendant(
        of: childTile,
        matching: find.byWidgetPredicate(
          (widget) => widget is DIcon && widget.icon == DIcons.lock,
        ),
      ),
      findsOneWidget,
    );
    final categoryDecoration =
        tester
                .widget<Container>(
                  find.byKey(const ValueKey('sidebar-prefix-category-2')),
                )
                .decoration!
            as BoxDecoration;
    final categorySwatch = categoryDecoration.gradient! as LinearGradient;
    expect(categorySwatch.colors, const [Color(0xFF112233), Color(0xFF445566)]);

    await tester.tap(sidebarDestination('Child'));
    await tester.pumpAndSettle();

    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );
    expect(controller.currentUserFor(site.url)?.sidebarCategoryIds, [2]);
    expect(api.feedPaths.last, '/c/parent/child/2.json');
    expect(controller.destinationId, 'category-2');
    expect(controller.currentContent?.feedPath, '/c/parent/child/2.json');
    expect(controller.contentStack, hasLength(1));
    final parentBreadcrumb = find.byKey(
      const ValueKey('content-header-parent-category'),
    );
    expect(parentBreadcrumb, findsOneWidget);
    expect(find.bySemanticsLabel('Parent category: Parent'), findsOneWidget);
    final categoryTitle = find.byKey(
      const ValueKey('content-header-category-title'),
    );
    expect(categoryTitle, findsOneWidget);
    expect(
      (tester.getCenter(parentBreadcrumb).dy -
              tester.getCenter(categoryTitle).dy)
          .abs(),
      lessThan(1),
    );
    expect(
      find.descendant(
        of: find.byType(TopicListView),
        matching: find.bySemanticsLabel('Category: Child'),
      ),
      findsNothing,
    );

    await tester.tap(parentBreadcrumb);
    await tester.pumpAndSettle();

    expect(controller.currentContent?.id, 'category-1');
    expect(controller.currentContent?.feedPath, '/c/parent/1.json');
    expect(controller.contentStack, hasLength(2));

    expect(controller.handleBack(canReturnToSidebar: false), isTrue);
    await tester.pumpAndSettle();
    expect(controller.currentContent?.id, 'category-2');
    expect(find.text('A category topic'), findsOneWidget);

    await tester.tap(find.text('A category topic'));
    await tester.pumpAndSettle();
    expect(controller.contentStack, hasLength(2));
    expect(controller.currentContent?.topicId, 7);

    expect(controller.handleBack(canReturnToSidebar: false), isTrue);
    await tester.pumpAndSettle();
    expect(controller.destinationId, 'category-2');
    expect(controller.currentContent?.feedPath, '/c/parent/child/2.json');
    expect(find.text('A category topic'), findsOneWidget);
  });

  testWidgets('shows live unread counts beside category and tag rows', (
    tester,
  ) async {
    const tag = SidebarTag(id: 9, name: 'priority', slug: 'priority');
    const user = DiscourseUser(
      id: 7,
      username: 'joffreyj',
      sidebarCategoryIds: [1],
      sidebarTags: [tag],
      displaySidebarTags: true,
      sidebarShowCountOfNewItems: true,
    );
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: user);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final api = FakeDiscourseApi(
      user: user,
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'Support', color: '0088CC'),
      ],
      trackingState: TopicTrackingState.fromJson(const [
        {
          'topic_id': 42,
          'highest_post_number': 3,
          'last_read_post_number': 1,
          'category_id': 1,
          'notification_level': 2,
          'tags': [
            {'id': 9},
          ],
        },
      ]),
    );

    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: api,
      authenticator: auth,
    );

    Finder row(String label) => find
        .ancestor(of: sidebarDestination(label), matching: find.byType(InkWell))
        .first;
    Finder count(String label, int value) =>
        find.descendant(of: row(label), matching: find.text('$value'));

    expect(api.topicTrackingRequests, [site.url]);
    expect(count('Support', 1), findsOneWidget);
    expect(count('priority', 1), findsOneWidget);

    FakeSiteTracker.built.single.deliverTopicTracking(const {
      'topic_id': 43,
      'message_type': 'unread',
      'payload': {
        'highest_post_number': 2,
        'category_id': 1,
        'notification_level': 2,
        'tags': [
          {'id': 9},
        ],
      },
    });
    // A tracking run notifies the shell once, after the delivery's microtask,
    // so the redraw lands in the frame after that notification.
    await tester.pump();
    await tester.pump();

    expect(count('Support', 2), findsOneWidget);
    expect(count('priority', 2), findsOneWidget);
  });

  testWidgets('loads categories even when the default topic feed fails', (
    tester,
  ) async {
    final site = instance('meta.discourse.org', title: 'Discourse Meta');
    final api = FakeDiscourseApi(
      categoryList: const [
        TopicCategory(id: 1, name: 'Support', color: '888', slug: 'support'),
      ],
      siteConfigs: {site.url: const SiteConfig.unknown()},
    );

    await pumpShell(tester, desktop, instances: [site], api: api);

    expect(api.feedPaths, contains('/latest.json'));
    expect(api.categoryRequests, [site.url]);
    expect(find.text('CATEGORIES'), findsOneWidget);
    expect(sidebarDestination('Support'), findsOneWidget);
  });

  testWidgets('opens All categories as a native root-only page', (
    tester,
  ) async {
    final site = instance('meta.discourse.org', title: 'Discourse Meta');
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'Support', color: '0088CC', slug: 'support'),
        TopicCategory(
          id: 2,
          name: 'Support child',
          color: '22AA66',
          slug: 'child',
          parentCategoryId: 1,
        ),
        TopicCategory(
          id: 3,
          name: 'Announcements',
          color: 'FF8800',
          slug: 'announcements',
        ),
      ],
    );
    final launched = watchBrowser(tester);

    await pumpShell(tester, desktop, instances: [site], api: api);
    await tester.tap(sidebarDestination('All categories'));
    await tester.pumpAndSettle();

    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );
    expect(controller.destinationId, 'all-categories');
    expect(controller.currentContent?.id, 'all-categories');
    expect(find.byType(CategoriesPage), findsOneWidget);
    expect(find.byKey(const ValueKey('category-card-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('category-card-2')), findsNothing);
    expect(find.byKey(const ValueKey('category-card-3')), findsOneWidget);
    expect(launched, isEmpty);
  });

  testWidgets('category lists expose cascade filters above the topics', (
    tester,
  ) async {
    const parent = TopicCategory(
      id: 1,
      name: 'Discourse Native App',
      color: '563A93',
      slug: 'discourse-native-app',
    );
    const bugs = TopicCategory(
      id: 2,
      name: 'Bugs',
      color: 'C54F16',
      slug: 'bugs',
      parentCategoryId: 1,
      position: 1,
    );
    final site = instance('meta.discourse.org', title: 'Discourse Meta');
    final api = FakeDiscourseApi(
      feeds: const {
        '/latest.json': [],
        '/c/discourse-native-app/1.json': [
          Topic(
            id: 7,
            title: 'Parent category topic',
            slug: 'parent-category-topic',
            categoryId: 1,
          ),
          Topic(
            id: 8,
            title: 'Subcategory topic',
            slug: 'subcategory-topic',
            categoryId: 2,
          ),
        ],
        '/c/discourse-native-app/bugs/2.json': [],
      },
      categoryList: const [
        parent,
        bugs,
        TopicCategory(
          id: 3,
          name: 'Features',
          color: '3BBF7B',
          slug: 'features',
          parentCategoryId: 1,
          position: 2,
        ),
      ],
    );

    await pumpShell(tester, desktop, instances: [site], api: api);
    final controller = ShellScope.read(
      tester.element(find.byType(MainContent)),
    );

    controller.openCategory(parent);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('topic-list-filter-bar')), findsOneWidget);
    expect(
      find.bySemanticsLabel('Category: Discourse Native App'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Category: Bugs'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Parent category: Discourse Native App'),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('topic-list-subcategory-filter')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(('choice-menu-option', 2))));
    await tester.pumpAndSettle();

    expect(controller.currentContent?.id, 'category-2');
    expect(
      controller.currentContent?.feedPath,
      '/c/discourse-native-app/bugs/2.json',
    );
    expect(find.bySemanticsLabel('Subcategory: Bugs'), findsOneWidget);
    expect(find.byKey(const ValueKey('topic-list-filter-bar')), findsOneWidget);
  });

  testWidgets('retries an incomplete category supplement on feed refresh', (
    tester,
  ) async {
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: const DiscourseUser(id: 7, username: 'joffreyj'));
    final api = FakeDiscourseApi(
      user: site.user,
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'Support', color: '888888'),
      ],
      categoryLoadComplete: false,
      siteConfigs: {site.url: const SiteConfig.unknown()},
    );
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';

    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: api,
      authenticator: auth,
    );
    final initialRequests = api.categoryRequests.length;
    expect(sidebarDestination('Support'), findsOneWidget);

    await tester.tap(sidebarDestination('Topics'));
    await tester.pumpAndSettle();

    expect(api.categoryRequests.length, greaterThan(initialRequests));
  });

  testWidgets('uses anonymous category defaults from site settings', (
    tester,
  ) async {
    final site = instance('meta.discourse.org', title: 'Discourse Meta');
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(id: 1, name: 'Alpha', color: '111111', position: 20),
        TopicCategory(id: 2, name: 'Zulu', color: '222222', position: 10),
      ],
      siteConfigs: {
        site.url: const SiteConfig(
          fixedCategoryPositions: true,
          defaultNavigationMenuCategoryIds: [2],
        ),
      },
    );

    await pumpShell(tester, desktop, instances: [site], api: api);

    expect(sidebarDestination('Zulu'), findsOneWidget);
    expect(sidebarDestination('Alpha'), findsNothing);
  });

  testWidgets('draws a custom category emoji from its uploaded artwork', (
    tester,
  ) async {
    const upload = 'https://meta.discourse.org/uploads/default/party.png';
    final customEmojiGate = Completer<void>();
    addTearDown(() {
      if (!customEmojiGate.isCompleted) customEmojiGate.complete();
    });
    final site = instance('meta.discourse.org', title: 'Discourse Meta');
    final api = FakeDiscourseApi(
      feeds: const {'/latest.json': []},
      categoryList: const [
        TopicCategory(
          id: 1,
          name: 'Celebrations',
          color: '8844AA',
          styleType: 'emoji',
          emoji: 'party_blob',
        ),
      ],
      customEmojisBySite: {
        site.url: const {'party_blob': upload},
      },
      customEmojiGate: customEmojiGate,
      siteConfigs: {site.url: const SiteConfig.unknown()},
    );

    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: api,
      beforeSettle: () async {
        for (
          var attempt = 0;
          attempt < 10 && sidebarDestination('Celebrations').evaluate().isEmpty;
          attempt++
        ) {
          await tester.pump();
        }

        final tile = find.ancestor(
          of: sidebarDestination('Celebrations'),
          matching: find.byType(InkWell),
        );
        expect(
          find.descendant(
            of: tile,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is EmojiImage &&
                  widget.url.endsWith('/party_blob.png'),
            ),
          ),
          findsOneWidget,
        );
        customEmojiGate.complete();
      },
    );

    final tile = find.ancestor(
      of: sidebarDestination('Celebrations'),
      matching: find.byType(InkWell),
    );
    expect(api.customEmojisRequired, [site.url]);
    expect(
      find.descendant(
        of: tile,
        matching: find.byWidgetPredicate(
          (widget) => widget is EmojiImage && widget.url == upload,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the sidebar header shows only the forum title', (tester) async {
    await pumpShell(tester, desktop);

    final sidebar = find.byType(InstanceSidebar);
    expect(
      find.descendant(of: sidebar, matching: find.text('Discourse Meta')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sidebar, matching: find.text('meta.discourse.org')),
      findsNothing,
    );
  });

  testWidgets('the community section is headerless and always expanded', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => SharedPreferences.setMockInitialValues({}));

    await pumpShell(tester, desktop);

    expect(find.text('COMMUNITY'), findsNothing);
    expect(find.byTooltip('Collapse Community'), findsNothing);
    final topics = sidebarDestination('Topics');
    expect(topics, findsOneWidget);

    final topicsTile = find
        .ancestor(of: topics, matching: find.byType(InkWell))
        .first;
    final sidebar = tester.getRect(find.byType(InstanceSidebar));
    final tile = tester.getRect(topicsTile);
    expect(tile.top - sidebar.top - shellHeaderHeight, closeTo(10, 0.01));
    expect(tile.left - sidebar.left, closeTo(6, 0.01));
    expect(sidebar.right - tile.right, closeTo(6, 0.01));
    expect(tile.height, closeTo(30, 0.01));
    expect(tester.getRect(topics).left - sidebar.left, closeTo(38, 0.01));
  });

  testWidgets('sidebar destinations show a hand cursor and hover background', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    final destination = sidebarDestination('More');
    final inkWell = find
        .ancestor(of: destination, matching: find.byType(InkWell))
        .first;
    final cursor =
        tester.widget<InkWell>(inkWell).mouseCursor! as WidgetStateMouseCursor;
    final theme = Theme.of(tester.element(destination));
    Color? background() =>
        ((tester.widget<InkWell>(inkWell).child! as Container).decoration
                as BoxDecoration?)
            ?.color;

    expect(cursor.resolve({}), SystemMouseCursors.click);
    expect(cursor.resolve({WidgetState.disabled}), SystemMouseCursors.basic);
    expect(background(), isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(destination));
    await tester.pumpAndSettle();

    expect(background(), theme.shell.hover);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(background(), isNull);
  });

  testWidgets('the sidebar header opens a destructive forum menu', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    await tester.tap(find.text('Discourse Meta'));
    await tester.pumpAndSettle();

    final remove = find.widgetWithText(MenuItemButton, 'Remove forum');
    expect(remove, findsOneWidget);
    expect(find.text('More Options'), findsNothing);

    final button = tester.widget<MenuItemButton>(remove);
    final theme = Theme.of(tester.element(remove));
    expect(button.style?.foregroundColor?.resolve({}), theme.colorScheme.error);
    expect(button.style?.iconColor?.resolve({}), theme.colorScheme.error);

    await tester.tap(remove);
    await tester.pumpAndSettle();
    expect(find.text('Remove Discourse Meta?'), findsOneWidget);
  });

  testWidgets('hovering a forum shows its name in a rail callout', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    final forum = find.byKey(
      const ValueKey<String>('https://team.discourse.org'),
    );
    final tooltipFinder = find.descendant(
      of: forum,
      matching: find.byType(RawTooltip),
    );
    final callout = find.byKey(
      const ValueKey<String>(
        'instance-rail-callout-https://team.discourse.org',
      ),
    );
    expect(forum, findsOneWidget);
    expect(tooltipFinder, findsOneWidget);
    expect(callout, findsNothing);

    final tooltip = tester.widget<RawTooltip>(tooltipFinder);
    expect(tooltip.semanticsTooltip, 'Discourse Team');
    expect(tooltip.triggerMode, TooltipTriggerMode.manual);
    expect(tooltip.ignorePointer, isTrue);
    expect(tooltip.hoverDelay, const Duration(milliseconds: 280));
    expect(tooltip.dismissDelay, const Duration(milliseconds: 80));
    expect(tooltip.animationStyle.duration, const Duration(milliseconds: 120));
    expect(
      tooltip.animationStyle.reverseDuration,
      const Duration(milliseconds: 80),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(forum));

    await tester.pump(tooltip.hoverDelay - const Duration(milliseconds: 1));
    expect(callout, findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(callout, findsOneWidget);

    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: callout, matching: find.byType(FadeTransition)).first,
    );
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: callout, matching: find.byType(ScaleTransition)).first,
    );
    expect(fade.opacity.value, closeTo(0, 0.001));
    expect(scale.scale.value, closeTo(0.96, 0.001));
    expect(scale.alignment, Alignment.centerLeft);

    await tester.pump(const Duration(milliseconds: 60));
    expect(fade.opacity.value, allOf(greaterThan(0), lessThan(1)));
    expect(scale.scale.value, allOf(greaterThan(0.96), lessThan(1)));

    await tester.pumpAndSettle();
    expect(fade.opacity.value, 1);
    expect(scale.scale.value, 1);

    expect(
      find.descendant(of: callout, matching: find.text('Discourse Team')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: callout,
        matching: find.textContaining('team.discourse.org'),
      ),
      findsNothing,
    );
    expect(
      find.ancestor(of: callout, matching: find.byType(ExcludeSemantics)),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>(
          'instance-rail-callout-icon-https://team.discourse.org',
        ),
      ),
      findsOneWidget,
    );

    final calloutWidget = tester.widget<Container>(callout);
    final decoration = calloutWidget.decoration! as ShapeDecoration;
    final targetRect = tester.getRect(tooltipFinder);
    final calloutRect = tester.getRect(callout);
    final insets = decoration.shape.dimensions.resolve(TextDirection.ltr);
    final calloutPath = decoration.shape.getOuterPath(
      Offset.zero & calloutRect.size,
    );

    expect(calloutRect.center.dy, closeTo(targetRect.center.dy, 0.5));
    expect(calloutRect.left, greaterThan(targetRect.right));
    expect(calloutRect.left + insets.left, greaterThan(targetRect.right));
    expect(insets, const EdgeInsets.fromLTRB(8, 1, 1, 1));
    expect(calloutPath.contains(Offset(1, calloutRect.height / 2)), isTrue);
    expect(calloutPath.contains(const Offset(1, 1)), isFalse);
    expect(calloutPath.contains(Offset(insets.left + 0.5, 0.5)), isFalse);
    expect(decoration.color, const Color(0xFF3C3D43));
    expect(decoration.shape, isA<OutlinedBorder>());
    expect(
      (decoration.shape as OutlinedBorder).side,
      const BorderSide(color: Color(0xFF47484E)),
    );
    expect(decoration.shadows, const [
      BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
      BoxShadow(color: Color(0x24000000), blurRadius: 2, offset: Offset(0, 1)),
    ]);
    expect(
      calloutWidget.constraints,
      const BoxConstraints(minHeight: 36, maxWidth: 240),
    );
    expect(
      calloutWidget.padding,
      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
    final label = tester.widget<Text>(
      find.descendant(of: callout, matching: find.text('Discourse Team')),
    );
    expect(label.style!.color, const Color(0xFFF3F3F4));
    expect(label.style!.fontSize, 16);
    expect(label.style!.fontWeight, FontWeight.w600);

    await mouse.moveTo(Offset.zero);
    await tester.pump(tooltip.dismissDelay - const Duration(milliseconds: 1));
    expect(callout, findsOneWidget);
    expect(fade.opacity.value, 1);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 40));
    expect(callout, findsOneWidget);
    expect(fade.opacity.value, allOf(greaterThan(0), lessThan(1)));
    expect(scale.scale.value, allOf(greaterThan(0.96), lessThan(1)));

    await tester.pumpAndSettle();
    expect(callout, findsNothing);
  });

  testWidgets('forum callouts respect reduced motion', (tester) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    await pumpShell(tester, desktop);

    final forum = find.byKey(
      const ValueKey<String>('https://team.discourse.org'),
    );
    final tooltipFinder = find.descendant(
      of: forum,
      matching: find.byType(RawTooltip),
    );
    final callout = find.byKey(
      const ValueKey<String>(
        'instance-rail-callout-https://team.discourse.org',
      ),
    );
    final tooltip = tester.widget<RawTooltip>(tooltipFinder);
    expect(tooltip.animationStyle.duration, Duration.zero);
    expect(tooltip.animationStyle.reverseDuration, Duration.zero);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(forum));
    await tester.pump(tooltip.hoverDelay);
    await tester.pump();

    expect(callout, findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: callout, matching: find.byType(FadeTransition)).first,
    );
    final scale = tester.widget<ScaleTransition>(
      find.ancestor(of: callout, matching: find.byType(ScaleTransition)).first,
    );
    expect(fade.opacity.value, 1);
    expect(scale.scale.value, 1);
  });

  group('adding a site', () {
    testWidgets('shows the empty state with nothing connected', (tester) async {
      await pumpShell(tester, desktop, instances: const []);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('a looked-up site lands in the rail and is persisted', (
      tester,
    ) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(
        results: {
          'meta.discourse.org': instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ),
        },
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'meta.discourse.org');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(api.lookups, ['meta.discourse.org']);
      expect(find.byType(EmptyState), findsNothing);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.text('Discourse Meta'), findsOneWidget);
      expect(store.saveCount, 1);
    });

    testWidgets('a private site asks for sign-in before requesting content', (
      tester,
    ) async {
      final store = FakeInstanceStore(const []);
      final authenticator = _GatedConnectAuthenticator();
      final privateSite = instance(
        'meetup.discourse.org',
        title: 'Discourse Meetup',
      ).copyWith(loginRequired: true);
      final api = FakeDiscourseApi(
        results: {'meetup.discourse.org': privateSite},
        feeds: {
          '/latest.json': const [
            Topic(id: 7, title: 'Welcome inside', slug: 'welcome-inside'),
          ],
        },
      );

      await pumpShell(
        tester,
        desktop,
        store: store,
        api: api,
        authenticator: authenticator,
      );

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'meetup.discourse.org');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(
        find.text(
          'Discourse Meetup is a private forum. Sign in to view its topics '
          'and conversations.',
        ),
        findsOneWidget,
      );
      expect(find.dIcon(DIcons.lock), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(ForumTabsBar), findsNothing);
      expect(find.byType(ShellTitleBar), findsOneWidget);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(userMenu, findsNothing);
      final railBounds = tester.getRect(find.byType(InstanceRail));
      final gateBounds = tester.getRect(
        find.byKey(const ValueKey('private-forum-gate')),
      );
      expect(railBounds.left, 0);
      expect(railBounds.right, gateBounds.left);
      expect(railBounds.top, gateBounds.top);
      expect(
        find.byKey(const ValueKey('private-forum-chrome-placeholder')),
        findsNothing,
      );
      expect(gateBounds.right, desktop.width);
      expect(gateBounds.bottom, desktop.height);
      expect(api.feedPaths, isEmpty);
      expect(api.appearancesRequested, isEmpty);
      expect(api.siteConfigsRequested, isEmpty);
      expect(api.customEmojisRequired, isEmpty);
      expect(api.categoryRequests, isEmpty);
      expect(api.searchesRequested, isEmpty);
      expect(find.textContaining('Not allowed'), findsNothing);
      final controller = ShellScope.read(
        tester.element(find.byKey(const ValueKey('private-forum-sign-in'))),
      );
      expect(controller.search.siteUrl, isNull);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);

      await tester.tap(find.byKey(const ValueKey('private-forum-sign-in')));
      await tester.pump();
      await authenticator.started.future;
      await tester.pump();

      expect(find.text('Signing in…'), findsOneWidget);
      final signIn = find.byKey(const ValueKey('private-forum-sign-in'));
      expect(
        tester
            .widget<FilledButton>(
              find.descendant(of: signIn, matching: find.byType(FilledButton)),
            )
            .onPressed,
        isNull,
      );

      authenticator.gate.complete();
      await tester.pumpAndSettle();

      expect(authenticator.connected, ['https://meetup.discourse.org']);
      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Welcome inside'), findsOneWidget);
      expect(find.text('Sign in to continue'), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(controller.search.siteUrl, 'https://meetup.discourse.org');
      expect(find.byKey(ForumSearch.inputKey), findsOneWidget);
    });

    testWidgets('a failed lookup reports why and adds nothing', (tester) async {
      final store = FakeInstanceStore(const []);
      final api = FakeDiscourseApi(failure: SiteLookupFailure.notDiscourse);

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.text('Add a site'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'example.com');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('is not a Discourse forum'), findsOneWidget);
      expect(find.byType(EmptyState), findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('the same site cannot be added twice', (tester) async {
      final existing = instance('meta.discourse.org', title: 'Discourse Meta');
      final store = FakeInstanceStore([existing]);
      final api = FakeDiscourseApi(
        results: {'https://meta.discourse.org/': existing},
      );

      await pumpShell(tester, desktop, store: store, api: api);

      await tester.tap(find.byTooltip('Add a Discourse site'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField),
        'https://meta.discourse.org/',
      );
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already in your list'), findsOneWidget);
      expect(store.saveCount, 0);
    });
  });

  group('ordering sites', () {
    Finder railItem(String host) =>
        find.byKey(ValueKey<String>('https://$host'));
    Finder dragSource(String host) =>
        find.byKey(ValueKey<String>('instance-rail-drag-source-https://$host'));
    Finder dragFeedback(String host) => find.byKey(
      ValueKey<String>('instance-rail-drag-feedback-https://$host'),
    );
    const dropIndicator = ValueKey<String>('instance-rail-drop-indicator');
    const dropIndicatorLine = ValueKey<String>(
      'instance-rail-drop-indicator-line',
    );
    const dropIndicatorPin = ValueKey<String>(
      'instance-rail-drop-indicator-pin',
    );
    List<DiscourseInstance> overflowingSites() => [
      for (var index = 0; index < 24; index++)
        instance(
          'site-${index.toString().padLeft(2, '0')}.example',
          title: 'Site $index',
        ),
    ];
    Future<void> onPlatform(
      TargetPlatform platform,
      Future<void> Function() body,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    }

    testWidgets('dragging saves the order and restores it after restart', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final community = instance('community.example', title: 'Community');
        final support = instance('support.example', title: 'Support');
        final store = FakeInstanceStore([...twoSites, community, support]);
        await pumpShell(tester, desktop, store: store);

        final meta = railItem('meta.discourse.org');
        final team = railItem('team.discourse.org');
        final target = railItem('community.example');
        await tester.tap(team);
        await tester.pumpAndSettle();
        final controller = ShellScope.read(tester.element(team));
        final content = controller.currentContent;
        final metaTooltipElement = tester.element(
          find.descendant(of: meta, matching: find.byType(RawTooltip)),
        );
        final targetRect = tester.getRect(target);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(meta));
        await mouse.down(tester.getCenter(meta));
        await tester.pump();
        await mouse.moveBy(const Offset(0, 16));
        await tester.pump();
        expect(find.byKey(dropIndicator), findsNothing);

        // Each half of a row names a different insertion point. The pointer,
        // rather than the centred feedback avatar, decides which half wins.
        final topHalfPointer = Offset(targetRect.center.dx, targetRect.top + 4);
        await mouse.moveTo(topHalfPointer);
        await tester.pump();

        final indicator = find.byKey(dropIndicator);
        expect(indicator, findsOneWidget);
        expect(tester.getSize(indicator), const Size(46, 8));
        expect(
          tester.getRect(indicator).center.dy,
          closeTo(targetRect.top, 0.1),
        );
        final line = find.byKey(dropIndicatorLine);
        final pin = find.byKey(dropIndicatorPin);
        expect(tester.getSize(line), const Size(38, 2));
        expect(tester.getSize(pin), const Size.square(8));
        expect(
          tester.getRect(pin).left -
              tester.getRect(find.byType(InstanceRail)).left,
          5,
        );
        final lineDecoration =
            tester.widget<Container>(line).decoration! as BoxDecoration;
        final pinDecoration =
            tester.widget<Container>(pin).decoration! as BoxDecoration;
        final indicatorTheme = Theme.of(tester.element(indicator));
        expect(lineDecoration.color, indicatorTheme.colorScheme.primary);
        expect(pinDecoration.shape, BoxShape.circle);
        expect(pinDecoration.border, isA<Border>());
        final pinBorder = pinDecoration.border! as Border;
        expect(pinBorder.top.color, indicatorTheme.colorScheme.primary);
        expect(pinBorder.top.width, 2);
        expect(dragFeedback('meta.discourse.org'), findsOneWidget);
        expect(
          tester.getCenter(dragFeedback('meta.discourse.org')),
          topHalfPointer,
        );
        final fadedSource = tester.widget<Opacity>(
          dragSource('meta.discourse.org'),
        );
        expect(fadedSource.opacity, 0.3);
        expect(store.saveCount, 0);

        final bottomHalfPointer = Offset(
          targetRect.center.dx,
          targetRect.bottom - 4,
        );
        await mouse.moveTo(bottomHalfPointer);
        await tester.pump();

        expect(indicator, findsOneWidget);
        expect(
          tester.getRect(indicator).center.dy,
          closeTo(targetRect.bottom, 0.1),
        );
        expect(
          tester.getCenter(dragFeedback('meta.discourse.org')),
          bottomHalfPointer,
        );
        expect(store.saveCount, 0);

        await mouse.up();
        await tester.pumpAndSettle();

        expect(indicator, findsNothing);
        expect(dragFeedback('meta.discourse.org'), findsNothing);
        expect(store.saveCount, 1);
        expect(
          tester.getTopLeft(team).dy,
          lessThan(tester.getTopLeft(meta).dy),
        );
        expect(
          tester.element(
            find.descendant(of: meta, matching: find.byType(RawTooltip)),
          ),
          same(metaTooltipElement),
        );
        expect(controller.currentInstance?.url, 'https://team.discourse.org');
        expect(controller.currentContent, same(content));
        expect((await store.load()).map((site) => site.url), [
          'https://team.discourse.org',
          community.url,
          'https://meta.discourse.org',
          support.url,
        ]);

        await pumpShell(
          tester,
          desktop,
          store: store,
          key: const ValueKey('restarted-after-reorder'),
        );

        expect(
          tester.getTopLeft(team).dy,
          lessThan(tester.getTopLeft(meta).dy),
        );
        expect(find.text('Discourse Team'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a drop lands harmlessly after the dragged site is removed', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final store = FakeInstanceStore([
          ...twoSites,
          instance('community.example', title: 'Community'),
        ]);
        await pumpShell(tester, desktop, store: store);

        final meta = railItem('meta.discourse.org');
        final team = railItem('team.discourse.org');
        final controller = ShellScope.read(tester.element(meta));
        final teamRect = tester.getRect(team);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(meta));
        await mouse.down(tester.getCenter(meta));
        await tester.pump();
        await mouse.moveBy(const Offset(0, 16));
        await tester.pump();
        await mouse.moveTo(Offset(teamRect.center.dx, teamRect.bottom - 4));
        await tester.pump();

        // A background flow takes the dragged site away mid-drag. The drag
        // avatar outlives its Draggable, so the drop still arrives — over a
        // rail that no longer contains the dragged site.
        expect(
          await controller.removeInstance(controller.instances.first),
          isTrue,
        );
        await tester.pump();
        await mouse.moveBy(const Offset(0, 8));
        await tester.pump();
        await mouse.up();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect((await store.load()).map((site) => site.url), [
          'https://team.discourse.org',
          'https://community.example',
        ]);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('a quick ${platform.name} swipe scrolls instead of dragging', (
        tester,
      ) async {
        await onPlatform(platform, () async {
          final sites = overflowingSites();
          final store = FakeInstanceStore(sites);
          await pumpShell(tester, phone, store: store);

          final scrollable = find.descendant(
            of: find.byType(InstanceRail),
            matching: find.byType(Scrollable),
          );
          final position = tester.state<ScrollableState>(scrollable).position;
          final source = find.byKey(ValueKey<String>(sites[6].url));
          final touch = await tester.startGesture(
            tester.getCenter(source),
            kind: PointerDeviceKind.touch,
          );

          // Moving past touch slop before the long-press deadline must let the
          // rail's ListView win the gesture arena.
          await tester.pump(const Duration(milliseconds: 100));
          await touch.moveBy(const Offset(0, -40));
          await tester.pump(const Duration(milliseconds: 16));
          await touch.moveBy(const Offset(0, -120));
          await tester.pump(const Duration(milliseconds: 16));

          expect(position.pixels, greaterThan(0));
          expect(dragFeedback('site-06.example'), findsNothing);
          expect(find.byKey(dropIndicator), findsNothing);
          expect(find.text('More Options'), findsNothing);
          expect(store.saveCount, 0);

          await touch.up();
          await tester.pumpAndSettle();

          expect(position.pixels, greaterThan(0));
          expect(store.saveCount, 0);
          expect((await store.load()).map((site) => site.url), [
            for (final site in sites) site.url,
          ]);
        });
      });
    }

    testWidgets('an Android touch long press reorders only on drop', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.android, () async {
        final store = FakeInstanceStore(twoSites);
        await pumpShell(tester, phone, store: store);

        final meta = railItem('meta.discourse.org');
        final team = railItem('team.discourse.org');
        final teamRect = tester.getRect(team);
        final touch = await tester.startGesture(
          tester.getCenter(meta),
          kind: PointerDeviceKind.touch,
        );

        await tester.pump(kLongPressTimeout);

        expect(dragFeedback('meta.discourse.org'), findsOneWidget);
        expect(find.text('More Options'), findsNothing);
        final pointer = Offset(teamRect.center.dx, teamRect.bottom - 4);
        await touch.moveTo(pointer);
        await tester.pump();

        final indicator = find.byKey(dropIndicator);
        expect(indicator, findsOneWidget);
        expect(
          tester.getRect(indicator).center.dy,
          greaterThan(teamRect.center.dy),
        );
        final feedbackRect = tester.getRect(dragFeedback('meta.discourse.org'));
        expect(feedbackRect.center.dx, pointer.dx);
        expect(feedbackRect.bottom, pointer.dy - 12);
        final fadedSource = tester.widget<Opacity>(
          dragSource('meta.discourse.org'),
        );
        expect(fadedSource.opacity, 0.3);
        expect(store.saveCount, 0);
        expect(find.text('More Options'), findsNothing);

        await touch.up();
        await tester.pumpAndSettle();

        expect(indicator, findsNothing);
        expect(dragFeedback('meta.discourse.org'), findsNothing);
        expect(find.text('More Options'), findsNothing);
        expect(store.saveCount, 1);
        expect((await store.load()).map((site) => site.url), [
          'https://team.discourse.org',
          'https://meta.discourse.org',
        ]);
      });
    });

    testWidgets('canceling a touch drag neither moves nor opens actions', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      final meta = railItem('meta.discourse.org');
      final teamRect = tester.getRect(railItem('team.discourse.org'));
      final touch = await tester.startGesture(
        tester.getCenter(meta),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout);
      await touch.moveTo(Offset(teamRect.center.dx, teamRect.bottom - 4));
      await tester.pump();

      expect(find.byKey(dropIndicator), findsOneWidget);
      expect(dragFeedback('meta.discourse.org'), findsOneWidget);
      expect(store.saveCount, 0);

      await touch.cancel();
      await tester.pumpAndSettle();

      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('meta.discourse.org'), findsNothing);
      expect(find.text('More Options'), findsNothing);
      expect(store.saveCount, 0);
      expect((await store.load()).map((site) => site.url), [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a touch drop outside the rail does not open actions or save', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      final meta = railItem('meta.discourse.org');
      final railRect = tester.getRect(find.byType(InstanceRail));
      final touch = await tester.startGesture(
        tester.getCenter(meta),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout);
      await touch.moveTo(
        Offset(tester.getCenter(meta).dx, railRect.bottom - 2),
      );
      await tester.pump();

      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('meta.discourse.org'), findsOneWidget);
      expect(store.saveCount, 0);

      await touch.up();
      await tester.pumpAndSettle();

      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('meta.discourse.org'), findsNothing);
      expect(find.text('More Options'), findsNothing);
      expect(store.saveCount, 0);
      expect((await store.load()).map((site) => site.url), [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
    });

    testWidgets(
      'holding a touch drag at the edge reveals a later drop target',
      (tester) async {
        final sites = overflowingSites();
        final store = FakeInstanceStore(sites);
        await pumpShell(tester, phone, store: store);

        Finder item(int index) =>
            find.byKey(ValueKey<String>(sites[index].url));
        final scrollable = find.descendant(
          of: find.byType(InstanceRail),
          matching: find.byType(Scrollable),
        );
        expect(scrollable, findsOneWidget);
        final position = tester.state<ScrollableState>(scrollable).position;
        final viewport = tester.getRect(scrollable);
        expect(position.maxScrollExtent, greaterThan(0));

        final source = item(0);
        final target = item(20);
        final controller = ShellScope.read(tester.element(source));
        final content = controller.currentContent;
        final touch = await tester.startGesture(
          tester.getCenter(source),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(kLongPressTimeout);
        await touch.moveTo(Offset(viewport.center.dx, viewport.bottom - 2));
        await tester.pump();

        bool targetComfortablyVisible() {
          if (target.evaluate().isEmpty) return false;
          final center = tester.getCenter(target);
          return center.dy > viewport.top + 30 &&
              center.dy < viewport.bottom - 30;
        }

        for (
          var frame = 0;
          frame < 180 && !targetComfortablyVisible();
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(position.pixels, greaterThan(0));
        expect(targetComfortablyVisible(), isTrue);
        expect(store.saveCount, 0);
        expect(dragFeedback('site-00.example'), findsOneWidget);

        final targetRect = tester.getRect(target);
        await touch.moveTo(Offset(targetRect.center.dx, targetRect.bottom - 4));
        await tester.pump();

        expect(find.byKey(dropIndicator), findsOneWidget);
        expect(
          tester.getRect(find.byKey(dropIndicator)).center.dy,
          greaterThan(targetRect.center.dy),
        );
        expect(store.saveCount, 0);

        await touch.up();
        await tester.pumpAndSettle();

        expect(store.saveCount, 1);
        expect(controller.currentInstance?.url, sites.first.url);
        expect(controller.currentContent, same(content));
        expect((await store.load()).map((site) => site.url), [
          for (var index = 1; index <= 20; index++) sites[index].url,
          sites.first.url,
          for (var index = 21; index < sites.length; index++) sites[index].url,
        ]);
      },
    );

    testWidgets('an iOS touch drag auto-scrolls upward to an earlier target', (
      tester,
    ) async {
      await onPlatform(TargetPlatform.iOS, () async {
        final sites = overflowingSites();
        final store = FakeInstanceStore(sites);
        await pumpShell(tester, phone, store: store);

        Finder item(int index) =>
            find.byKey(ValueKey<String>(sites[index].url));
        final scrollable = find.descendant(
          of: find.byType(InstanceRail),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scrollable).position;
        final viewport = tester.getRect(scrollable);
        final startingPixels = position.maxScrollExtent;
        position.jumpTo(startingPixels);
        await tester.pump();

        final source = item(23);
        final target = item(3);
        final controller = ShellScope.read(tester.element(source));
        final content = controller.currentContent;
        final touch = await tester.startGesture(
          tester.getCenter(source),
          kind: PointerDeviceKind.touch,
        );
        await tester.pump(kLongPressTimeout);
        await touch.moveTo(Offset(viewport.center.dx, viewport.top + 2));
        await tester.pump();

        bool targetComfortablyVisible() {
          if (target.evaluate().isEmpty) return false;
          final center = tester.getCenter(target);
          return center.dy > viewport.top + 30 &&
              center.dy < viewport.bottom - 30;
        }

        for (
          var frame = 0;
          frame < 180 && !targetComfortablyVisible();
          frame++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(position.pixels, lessThan(startingPixels));
        expect(targetComfortablyVisible(), isTrue);
        expect(store.saveCount, 0);
        expect(dragFeedback('site-23.example'), findsOneWidget);

        final targetRect = tester.getRect(target);
        await touch.moveTo(Offset(targetRect.center.dx, targetRect.top + 4));
        await tester.pump();

        expect(find.byKey(dropIndicator), findsOneWidget);
        expect(
          tester.getRect(find.byKey(dropIndicator)).center.dy,
          lessThan(targetRect.center.dy),
        );
        expect(store.saveCount, 0);

        await touch.up();
        await tester.pumpAndSettle();

        expect(store.saveCount, 1);
        expect(controller.currentInstance?.url, sites.first.url);
        expect(controller.currentContent, same(content));
        expect((await store.load()).map((site) => site.url), [
          for (var index = 0; index < 3; index++) sites[index].url,
          sites.last.url,
          for (var index = 3; index < 23; index++) sites[index].url,
        ]);
      });
    });

    testWidgets('canceling an edge drag stops auto-scroll permanently', (
      tester,
    ) async {
      final sites = overflowingSites();
      final store = FakeInstanceStore(sites);
      await pumpShell(tester, phone, store: store);

      final scrollable = find.descendant(
        of: find.byType(InstanceRail),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      final viewport = tester.getRect(scrollable);
      final source = find.byKey(ValueKey<String>(sites.first.url));
      final touch = await tester.startGesture(
        tester.getCenter(source),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(kLongPressTimeout);
      await touch.moveTo(Offset(viewport.center.dx, viewport.bottom - 2));

      for (var frame = 0; frame < 12; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(position.pixels, greaterThan(0));

      await touch.cancel();
      await tester.pumpAndSettle();
      final stoppedPixels = position.pixels;
      await tester.pump(const Duration(seconds: 1));

      expect(position.pixels, stoppedPixels);
      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('site-00.example'), findsNothing);
      expect(find.text('More Options'), findsNothing);
      expect(store.saveCount, 0);
    });

    testWidgets('a second finger invalidates one row gesture safely', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      final meta = railItem('meta.discourse.org');
      final center = tester.getCenter(meta);
      final first = await tester.startGesture(
        center,
        pointer: 1,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump(const Duration(milliseconds: 100));
      final second = await tester.startGesture(
        center + const Offset(1, 1),
        pointer: 2,
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      await tester.pump(kLongPressTimeout);

      expect(dragFeedback('meta.discourse.org'), findsNothing);
      expect(find.byKey(dropIndicator), findsNothing);
      expect(find.text('More Options'), findsNothing);

      await first.up();
      await second.up();
      await tester.pumpAndSettle();

      expect(store.saveCount, 0);
      expect((await store.load()).map((site) => site.url), [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      expect(find.text('More Options'), findsOneWidget);
    });

    testWidgets('one forum keeps its stationary touch actions', (tester) async {
      final only = instance('only.example', title: 'Only Forum');
      final store = FakeInstanceStore([only]);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(railItem('only.example'));
      await tester.pumpAndSettle();

      expect(find.text('More Options'), findsOneWidget);
      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('only.example'), findsNothing);
      expect(store.saveCount, 0);

      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      expect(find.text('Move up'), findsNothing);
      expect(find.text('Move down'), findsNothing);
      expect(find.text('Remove forum'), findsOneWidget);
    });

    testWidgets('the touch actions can move a site without taking its slot', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      final meta = railItem('meta.discourse.org');
      final team = railItem('team.discourse.org');
      await tester.longPress(meta);
      await tester.pumpAndSettle();

      expect(store.saveCount, 0);
      expect((await store.load()).map((site) => site.url), [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
      expect(find.byKey(dropIndicator), findsNothing);
      expect(dragFeedback('meta.discourse.org'), findsNothing);
      expect(find.text('More Options'), findsOneWidget);
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsOneWidget);
      await tester.tap(find.text('Move down'));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(team).dy, lessThan(tester.getTopLeft(meta).dy));
      expect(find.text('Discourse Meta'), findsOneWidget);
      expect((await store.load()).map((site) => site.url), [
        'https://team.discourse.org',
        'https://meta.discourse.org',
      ]);
    });
  });

  group('removing a site', () {
    Finder railItem(String host) =>
        find.byKey(ValueKey<String>('https://$host'));

    final meta = railItem('meta.discourse.org');

    testWidgets('a long press leads to the removal through a sheet', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();

      expect(find.text('More Options'), findsOneWidget);
      expect(find.text('Remove forum'), findsNothing);

      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();

      expect(find.text('Remove forum'), findsOneWidget);
    });

    testWidgets('a right click offers the removal directly', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(tester, desktop, key: const ValueKey('macos'));

        await tester.tap(meta, buttons: kSecondaryButton);
        await tester.pumpAndSettle();

        expect(find.text('Remove forum'), findsOneWidget);
        expect(find.text('More Options'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('holding a site does not pop its tooltip as well', (
      tester,
    ) async {
      await pumpShell(tester, phone);

      final metaTooltip = find.descendant(
        of: meta,
        matching: find.byType(RawTooltip),
      );
      expect(
        tester.widget<RawTooltip>(metaTooltip).triggerMode,
        TooltipTriggerMode.manual,
      );
      await tester.longPress(meta);
      await tester.pumpAndSettle();

      // The tooltip's own long-press trigger would otherwise fire under the
      // menu, naming the site twice.
      expect(find.text('More Options'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>(
            'instance-rail-callout-https://meta.discourse.org',
          ),
        ),
        findsNothing,
      );
    });

    testWidgets('removing asks first, and answering no keeps the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();

      expect(find.text('Remove Discourse Meta?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(meta, findsOneWidget);
      expect(store.saveCount, 0);
    });

    testWidgets('confirming takes the site out of the rail and stores it', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final api = FakeDiscourseApi();
      final auth = FakeAuthenticator();

      await pumpShell(
        tester,
        phone,
        store: store,
        api: api,
        authenticator: auth,
      );

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(meta, findsNothing);
      expect(railItem('team.discourse.org'), findsOneWidget);
      expect(find.text('Discourse Team'), findsOneWidget);
      expect(auth.disconnected, ['https://meta.discourse.org']);
      // Persist the signed-out boundary before deleting credentials, then
      // persist the rail removal. Both writes are part of the transaction.
      expect(store.saveCount, 2);
    });

    testWidgets('a keychain that refuses cannot hold the site in the rail', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator(
        disconnectFailure: PlatformException(
          code: '-34018',
          message: "A required entitlement isn't present.",
        ),
      );

      await pumpShell(tester, phone, store: store, authenticator: auth);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(meta, findsNothing);
      // A failed keychain deletion cannot roll the durable signed-out boundary
      // or the subsequent rail removal back into the next launch.
      expect(store.saveCount, 2);
    });

    testWidgets('removing the last site leaves the empty state', (
      tester,
    ) async {
      final store = FakeInstanceStore([
        instance('meta.discourse.org', title: 'Discourse Meta'),
      ]);

      await pumpShell(tester, desktop, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('removing one site does not disturb the one being read', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
          ],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              const Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: [1],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await tester.longPress(railItem('team.discourse.org'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(renderedText('First post body'), findsOneWidget);
    });
  });
}

void _registerShellUpdateTests() {
  group('the update button', () {
    Finder updateButton() => find.dIcon(DIcons.arrowsRotate);

    testWidgets('is absent where an update cannot be installed', (
      tester,
    ) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(updateButton(), findsNothing);
    });

    testWidgets('is in the rail at every window size', (tester) async {
      for (final size in [phone, laptop, desktop]) {
        await pumpShell(
          tester,
          size,
          updater: FakeUpdater(isSupported: true),
          updateStore: FakeUpdateStore(lastChecked: DateTime.now()),
        );

        expect(updateButton(), findsOneWidget, reason: 'at $size');
      }
    });

    testWidgets('is in the rail with no sites connected', (tester) async {
      await pumpShell(
        tester,
        desktop,
        instances: const [],
        updater: FakeUpdater(isSupported: true),
        updateStore: FakeUpdateStore(lastChecked: DateTime.now()),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(updateButton(), findsOneWidget);
    });

    testWidgets('says nothing until a check finds something', (tester) async {
      await pumpShell(
        tester,
        desktop,
        updater: FakeUpdater(isSupported: true),
        updateStore: FakeUpdateStore(lastChecked: DateTime.now()),
      );

      expect(updateButton(), findsOneWidget);
      expect(find.dIcon(DIcons.download), findsNothing);
    });

    testWidgets('offers the release a launch check found', (tester) async {
      await pumpShell(
        tester,
        desktop,
        updater: FakeUpdater(
          isSupported: true,
          releases: {
            UpdateChannel.stable: const UpdateRelease(
              version: '1.4.0',
              channel: UpdateChannel.stable,
            ),
          },
        ),
        updateStore: FakeUpdateStore(),
      );
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.download), findsOneWidget);
      expect(find.byTooltip('Update to 1.4.0'), findsOneWidget);
    });

    testWidgets('tapping it opens the sheet rather than installing', (
      tester,
    ) async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {
          UpdateChannel.stable: const UpdateRelease(
            version: '1.4.0',
            channel: UpdateChannel.stable,
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        updater: updater,
        updateStore: FakeUpdateStore(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.download));
      await tester.pumpAndSettle();

      expect(find.text('App updates'), findsOneWidget);
      expect(updater.installCount, 0);
    });
  });

  group('checking for updates', () {
    Future<void> openSheet(
      WidgetTester tester, {
      required FakeUpdater updater,
      FakeUpdateStore? store,
    }) async {
      await pumpShell(
        tester,
        desktop,
        updater: updater,
        updateStore: store ?? FakeUpdateStore(lastChecked: DateTime.now()),
      );
      await tester.tap(find.dIcon(DIcons.arrowsRotate));
      await tester.pumpAndSettle();
    }

    testWidgets('the sheet says which channel is being followed', (
      tester,
    ) async {
      await openSheet(tester, updater: FakeUpdater(isSupported: true));

      expect(find.textContaining('stable channel'), findsOneWidget);
      expect(find.text('Stable'), findsOneWidget);
      expect(find.text('Canary'), findsOneWidget);
    });

    testWidgets('a check that finds nothing says so', (tester) async {
      await openSheet(tester, updater: FakeUpdater(isSupported: true));

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text("You're up to date."), findsOneWidget);
    });

    testWidgets('a check that finds a release offers it by version', (
      tester,
    ) async {
      await openSheet(
        tester,
        updater: FakeUpdater(
          isSupported: true,
          releases: {
            UpdateChannel.stable: const UpdateRelease(
              version: '1.4.0',
              channel: UpdateChannel.stable,
            ),
          },
        ),
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text('Download 1.4.0'), findsOneWidget);
    });

    testWidgets('a check in flight disables the button and spins', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openSheet(
        tester,
        updater: FakeUpdater(isSupported: true, gate: gate),
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pump();

      expect(find.text('Check for updates'), findsNothing);
      expect(activityIndicators, findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a check that cannot reach the server offers the releases '
        'page instead', (tester) async {
      final launched = watchBrowser(tester);
      await openSheet(
        tester,
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't reach the update server."), findsOneWidget);

      await tester.tap(find.text('Open the releases page'));
      await tester.pumpAndSettle();

      expect(launched.single, contains('/releases'));
    });

    testWidgets('a signature that does not verify is not reported as a '
        'network problem', (tester) async {
      await openSheet(
        tester,
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.untrusted),
        ),
      );

      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();

      expect(find.textContaining('signature'), findsOneWidget);
      expect(find.text("Couldn't reach the update server."), findsNothing);
    });

    testWidgets('a check nobody asked for fails quietly', (tester) async {
      await pumpShell(
        tester,
        desktop,
        updater: FakeUpdater(
          isSupported: true,
          checkFailure: const UpdateException(UpdateFailure.unreachable),
        ),
        updateStore: FakeUpdateStore(),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.descendant(
          of: find.byType(InstanceRail),
          matching: find.dIcon(DIcons.triangleExclamation),
        ),
        findsNothing,
      );
    });
  });

  group('downloading an update', () {
    FakeUpdater offering({
      List<double> progressSteps = const [0.25, 0.5, 1.0],
      UpdateException? downloadFailure,
    }) => FakeUpdater(
      isSupported: true,
      progressSteps: progressSteps,
      downloadFailure: downloadFailure,
      releases: {
        UpdateChannel.stable: const UpdateRelease(
          version: '1.4.0',
          channel: UpdateChannel.stable,
        ),
      },
    );

    Future<void> openOffer(WidgetTester tester, FakeUpdater updater) async {
      await pumpShell(
        tester,
        desktop,
        updater: updater,
        updateStore: FakeUpdateStore(),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.download));
      await tester.pumpAndSettle();
    }

    testWidgets('a finished download offers to restart', (tester) async {
      final updater = offering();
      await openOffer(tester, updater);

      await tester.tap(find.text('Download 1.4.0'));
      await tester.pumpAndSettle();

      expect(find.text('Restart and install'), findsOneWidget);
      expect(updater.downloadCount, 1);
    });

    testWidgets('restarting hands the app over to the updater', (tester) async {
      final updater = offering();
      await openOffer(tester, updater);

      await tester.tap(find.text('Download 1.4.0'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restart and install'));
      // pump, not pumpAndSettle: a successful install never comes back, so the
      // panel is left on an indeterminate spinner on purpose and there is no
      // settled state to wait for.
      await tester.pump();

      expect(updater.installCount, 1);
    });

    testWidgets('a download that fails leaves the release still on offer', (
      tester,
    ) async {
      await openOffer(
        tester,
        offering(
          downloadFailure: const UpdateException(UpdateFailure.untrusted),
        ),
      );

      await tester.tap(find.text('Download 1.4.0'));
      await tester.pumpAndSettle();

      expect(find.text('Download 1.4.0'), findsOneWidget);
    });

    testWidgets('a download survives the sheet being closed and reopened', (
      tester,
    ) async {
      final held = Completer<void>();
      final updater = FakeUpdater(
        isSupported: true,
        downloadGate: held,
        progressSteps: const [0.4],
        releases: {
          UpdateChannel.stable: const UpdateRelease(
            version: '1.4.0',
            channel: UpdateChannel.stable,
          ),
        },
      );
      await openOffer(tester, updater);

      await tester.tap(find.text('Download 1.4.0'));
      await tester.pump();
      expect(find.textContaining('Downloading'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.textContaining('Downloading'), findsNothing);

      await tester.tap(activityIndicators.last);
      await tester.pumpAndSettle();

      expect(find.text('Downloading — 40%'), findsOneWidget);
      expect(updater.downloadCount, 1);

      held.complete();
      await tester.pumpAndSettle();
    });
  });

  group('the release channel', () {
    testWidgets('defaults to the channel the build was made on', (
      tester,
    ) async {
      await pumpShell(
        tester,
        desktop,
        updater: FakeUpdater(isSupported: true),
        updateStore: FakeUpdateStore(lastChecked: DateTime.now()),
      );

      await tester.tap(find.dIcon(DIcons.arrowsRotate));
      await tester.pumpAndSettle();

      expect(find.textContaining('stable channel'), findsOneWidget);
    });

    testWidgets('a stored channel wins over the built-in one', (tester) async {
      await pumpShell(
        tester,
        desktop,
        updater: FakeUpdater(isSupported: true),
        updateStore: FakeUpdateStore(
          rawChannel: 'canary',
          lastChecked: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.arrowsRotate));
      await tester.pumpAndSettle();

      expect(find.textContaining('canary channel'), findsOneWidget);
    });

    testWidgets('switching channels persists it and asks the new one', (
      tester,
    ) async {
      final updater = FakeUpdater(isSupported: true);
      final store = FakeUpdateStore(lastChecked: DateTime.now());
      await pumpShell(tester, desktop, updater: updater, updateStore: store);

      await tester.tap(find.dIcon(DIcons.arrowsRotate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Canary'));
      await tester.pumpAndSettle();

      expect(store.rawChannel, 'canary');
      expect(updater.discardCount, 1);
      expect(updater.lastCheckedChannel, UpdateChannel.canary);
    });

    testWidgets('going back to an older stable says switch, not update', (
      tester,
    ) async {
      final updater = FakeUpdater(
        isSupported: true,
        releases: {
          UpdateChannel.stable: const UpdateRelease(
            version: '1.3.2',
            channel: UpdateChannel.stable,
            isDowngrade: true,
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        updater: updater,
        updateStore: FakeUpdateStore(
          rawChannel: 'canary',
          lastChecked: DateTime.now(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.arrowsRotate));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stable'));
      await tester.pumpAndSettle();

      expect(find.text('Switch to 1.3.2'), findsOneWidget);
    });
  });
}

final class _GatedConnectAuthenticator extends FakeAuthenticator {
  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> authorize(String siteUrl) async {
    started.complete();
    await gate.future;
    return super.authorize(siteUrl);
  }
}

List<MethodCall> _watchAppExits(WidgetTester tester) {
  final exits = <MethodCall>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'SystemNavigator.pop') exits.add(call);
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return exits;
}

/// Delivers the platform's back event the way Android does: through the
/// navigation channel, not by tapping an in-app affordance.
Future<void> _systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}
