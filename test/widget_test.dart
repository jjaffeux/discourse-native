import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/fakes.dart';
import 'support/finders.dart';

/// Sizes chosen to sit either side of the shell's breakpoints (768 / 1200).
const Size phone = Size(390, 844);
const Size laptop = Size(1000, 800);
const Size desktop = Size(1440, 900);

final List<DiscourseInstance> twoSites = [
  instance('meta.discourse.org', title: 'Discourse Meta'),
  instance('team.discourse.org', title: 'Discourse Team'),
];

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  List<DiscourseInstance>? instances,
  FakeDiscourseApi? api,
  FakeInstanceStore? store,
  FakeAuthenticator? authenticator,
  FakeDraftStore? drafts,
  FakeUpdater? updater,
  FakeUpdateStore? updateStore,
  Key? key,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Emoji are fetched off the site, and any fixture carrying one would dial out
  // from a widget test. Answering 404 draws the shortcode, which is what these
  // tests looked like before emoji rendered at all — nothing here is about
  // artwork. Unlike avatars, which no fixture supplies a URL for, cooked HTML
  // is what most of these tests are made of, so this cannot be left to luck.
  EmojiCache.instance = EmojiCache(
    client: MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(EmojiCache.instance.clear);

  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: store ?? FakeInstanceStore(instances ?? twoSites),
      api: api ?? FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: drafts ?? FakeDraftStore(),
      // Never the real one: it opens a long poll, and its backoff timer
      // outlives the tree the binding then complains about.
      trackers: FakeSiteTracker.reset(),
      // Defaults to an updater that reports it cannot update, which is what
      // every test that is not about updating wants to see.
      updater: updater ?? FakeUpdater(),
      updateStore: updateStore ?? FakeUpdateStore(),
    ),
  );
  await tester.pumpAndSettle();
}

/// HtmlWidget renders into a bare RichText, which find.text and
/// find.textContaining both ignore.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

/// The surface the first post paints for itself, which is what hovering it
/// changes. The innermost [ColoredBox] above the body is the post's own.
Color postBackground(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find
          .ancestor(
            of: renderedText('First post body'),
            matching: find.byType(ColoredBox),
          )
          .first,
    )
    .color;

/// Catches what would have been handed to the platform browser.
List<String> watchBrowser(WidgetTester tester) {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
    return true;
  });
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  return launched;
}

final class _GatedUserCardApi extends FakeDiscourseApi {
  _GatedUserCardApi({
    required this.cardGate,
    required super.feeds,
    required super.topics,
  });

  final Completer<void> cardGate;
  final started = Completer<void>();
  final List<String> cardSites = [];

  @override
  Future<UserCard> userCard({
    required String siteUrl,
    required String username,
    String? apiKey,
    String? clientId,
  }) async {
    cardsRequested.add(username);
    cardSites.add(siteUrl);
    started.complete();
    await cardGate.future;
    return UserCard(
      username: username,
      name: 'First-site profile',
      title: 'From Meta',
    );
  }
}

/// The account avatar in the top right, wherever the layout has put it.
final Finder userMenu = find.byKey(UserMenuButton.avatarKey);

/// A sidebar entry by its label. Scoped to the sidebar because the user menu
/// names some of the same things — "Messages" is both a destination and a tab.
Finder sidebarDestination(String label) => find.descendant(
  of: find.byType(InstanceSidebar),
  matching: find.text(label),
);

/// Opens the account menu and walks to the section holding the real actions.
/// On touch that is a row leading to a nested sheet; with a pointer it is an
/// icon in the tab rail, named only by its tooltip.
Future<void> openProfileSection(WidgetTester tester) async {
  await tester.tap(userMenu);
  await tester.pumpAndSettle();

  final tab = find.byTooltip('Profile');
  await tester.tap(tab.evaluate().isEmpty ? find.text('Profile') : tab);
  await tester.pumpAndSettle();
}

/// Moves a mouse over the first post, which is what reveals its actions.
Future<TestGesture> hoverPost(
  WidgetTester tester, {
  String body = 'First post body',
}) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(gesture.removePointer);
  await gesture.moveTo(tester.getCenter(renderedText(body)));
  await tester.pumpAndSettle();
  return gesture;
}

void main() {
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
      expect(field.top, greaterThanOrEqualTo(title.bottom));
      expect(find.byType(InstanceSidebar), findsOneWidget);
    });

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
      );
      await pumpShell(tester, laptop, api: api);
      EmojiCache.instance = EmojiCache(
        client: MockClient((_) async => http.Response.bytes(emojiPng, 200)),
      );
      addTearDown(EmojiCache.instance.clear);

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
      expect(controller.search.topicsActionSelected, isTrue);
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
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
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
      expect(controller.search.selectedIndex, 0);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(api.topicsOpened, [2]);

      controller.search.setQuery('matches');
      controller.search.requestFocus();
      await tester.pump();
      expect(searchInput.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.search.panelOpen, isFalse);
      expect(controller.search.query, 'matches');
      expect(searchInput.hasFocus, isFalse);
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

      for (var index = 1; index < 8; index++) {
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

  group('compact', () {
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

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail never goes away.
      expect(find.byType(InstanceRail), findsOneWidget);
    });

    testWidgets('back returns from content to the sidebar', (tester) async {
      await pumpShell(tester, phone);

      await tester.tap(find.text('Messages'));
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

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace with deeper view'));
      await tester.pumpAndSettle();

      expect(find.text('Topic 1'), findsWidgets);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      // First back pops the stack; the sidebar is still not showing.
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
    });

    testWidgets('the avatar follows whichever pane is showing', (tester) async {
      await pumpShell(tester, phone);

      // Only one pane is on screen at a time, so there is only ever one.
      expect(userMenu, findsOneWidget);
      final onSidebar = tester.getRect(userMenu);

      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      expect(userMenu, findsOneWidget);
      // Same corner, now belonging to the content header.
      expect(tester.getRect(userMenu), onSidebar);
    });
  });

  group('medium', () {
    testWidgets('shows rail, sidebar and content together', (tester) async {
      await pumpShell(tester, laptop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });
  });

  group('expanded', () {
    testWidgets('shows rail, sidebar and content', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsOneWidget);
    });

    testWidgets('the avatar sits in the top right corner', (tester) async {
      await pumpShell(tester, desktop);

      // Only in the column reaching furthest right: the sidebar's own header
      // stays free of it while the main content is on screen.
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

    // Second entry in the rail.
    await tester.tap(find.text('DT'));
    await tester.pumpAndSettle();

    expect(find.text('Discourse Team'), findsOneWidget);
    expect(find.text('Discourse Meta'), findsNothing);
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
    final filterTile = find
        .ancestor(
          of: sidebarDestination('Filter'),
          matching: find.byType(InkWell),
        )
        .first;
    final projectsHeader = find
        .ancestor(of: find.text('PROJECTS'), matching: find.byType(InkWell))
        .first;
    expect(
      tester.getRect(projectsHeader).top - tester.getRect(filterTile).bottom,
      lessThanOrEqualTo(2),
    );

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
    final sidebarTop = tester.getTopLeft(find.byType(InstanceSidebar)).dy;
    expect(
      tester.getTopLeft(topicsTile).dy - sidebarTop - shellHeaderHeight,
      greaterThanOrEqualTo(8),
    );
  });

  testWidgets('sidebar section chevrons follow their actions', (tester) async {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    final site = instance(
      'meta.discourse.org',
      title: 'Discourse Meta',
    ).copyWith(user: me);
    final auth = FakeAuthenticator()..keys[site.url] = 'api-key';
    final api = FakeDiscourseApi(
      pluginResponses: {
        'GET /resenha/rooms.json': {
          'rooms': [
            {
              'id': 7,
              'name': 'Conf Room 1',
              'slug': 'conf-room-1',
              'public': false,
              'ephemeral': false,
              'room_type': 'stage',
              'member_count': 0,
              'message_bus_last_id': 91,
              'active_participants': <Object?>[],
              'video_enabled': false,
              'video_allowed': false,
              'max_quality_profile': 'standard',
            },
          ],
          'can_create_room': true,
          'index_message_bus_last_id': 144,
        },
      },
    );

    await pumpShell(
      tester,
      desktop,
      instances: [site],
      api: api,
      authenticator: auth,
    );

    final action = find.byTooltip('Create voice room');
    final chevron = find.byTooltip('Collapse Voice rooms');
    expect(action, findsOneWidget);
    expect(chevron, findsOneWidget);
    expect(tester.getCenter(action).dx, lessThan(tester.getCenter(chevron).dx));
    // A larger action would make this header taller than adjacent sections.
    expect(tester.getSize(action), tester.getSize(chevron));
  });

  testWidgets('sidebar destinations show a background when hovered', (
    tester,
  ) async {
    await pumpShell(tester, desktop);

    final destination = sidebarDestination('Messages');
    final inkWell = find
        .ancestor(of: destination, matching: find.byType(InkWell))
        .first;
    final theme = Theme.of(tester.element(destination));
    Color? background() =>
        ((tester.widget<InkWell>(inkWell).child! as Container).decoration
                as BoxDecoration?)
            ?.color;

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

  group('adding a site', () {
    testWidgets('shows the empty state with nothing connected', (tester) async {
      await pumpShell(tester, desktop, instances: const []);

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      // The rail is still there, holding the add button.
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

      await tester.tap(find.dIcon(DIcons.plus));
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

  group('removing a site', () {
    /// The rail draws no text of its own, so a site is identified by the
    /// tooltip naming it.
    Finder railItem(String title, String host) =>
        find.byTooltip('$title\n$host');

    final meta = railItem('Discourse Meta', 'meta.discourse.org');

    testWidgets('a long press leads to the removal through a sheet', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      await pumpShell(tester, phone, store: store);

      await tester.longPress(meta);
      await tester.pumpAndSettle();

      // A thumb ends up inside the menu it just opened, so the destructive
      // action is not in it — only the way to it.
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
        // A distinct key rebuilds the tree against the platform in effect.
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

      await tester.longPress(meta);
      await tester.pumpAndSettle();

      // The tooltip's own long-press trigger would otherwise fire under the
      // menu, naming the site twice.
      expect(find.text('Discourse Meta\nmeta.discourse.org'), findsNothing);
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
      expect(railItem('Discourse Team', 'team.discourse.org'), findsOneWidget);
      // The site that was being read went away, so the one left takes over.
      expect(find.text('Discourse Team'), findsOneWidget);
      expect(auth.disconnected, ['https://meta.discourse.org']);
      expect(store.saveCount, 1);
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

      // Abandoning the removal half done is the worse answer: the key is gone
      // from the site either way, and the user is left unable to remove it.
      expect(meta, findsNothing);
      expect(store.saveCount, 1);
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
              Post(
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

      await tester.longPress(railItem('Discourse Team', 'team.discourse.org'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More Options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove forum'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      // The reader was on the other site; taking this one away is not a reason
      // to throw away where they were.
      expect(renderedText('First post body'), findsOneWidget);
    });
  });

  group('topic lists', () {
    final latest = [
      const Topic(
        id: 1,
        title: 'Welcome to the forum',
        slug: 'welcome',
        categoryId: 5,
      ),
      const Topic(
        id: 2,
        title: 'Something unread',
        slug: 'unread-one',
        unreadPosts: 3,
      ),
    ];

    testWidgets('the default destination loads latest on open', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      expect(find.text('Something unread'), findsOneWidget);
      // The placeholder is gone.
      expect(find.text('Replace with deeper view'), findsNothing);
    });

    testWidgets('an authorized public list offers the topic composer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
        categoryList: const [
          TopicCategory(id: 5, name: 'Support', color: '0088CC', permission: 1),
        ],
        composerCapabilities: const TopicComposerCapabilities(
          canTagTopics: true,
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(tester, desktop, api: api, authenticator: authenticator);

      expect(find.byTooltip('New topic'), findsOneWidget);
      await tester.tap(find.byTooltip('New topic'));
      await tester.pumpAndSettle();

      expect(find.text('Create a new topic'), findsOneWidget);
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Create topic'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      final categoryRequestCount = api.categoryRequests.length;
      final capabilityRequestCount = api.topicComposerCapabilityRequests.length;

      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byTooltip('New topic'));
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).visibleComposer,
        isNotNull,
      );
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.categoryRequests, hasLength(categoryRequestCount));
      expect(
        api.topicComposerCapabilityRequests,
        hasLength(capabilityRequestCount),
      );

      final fields = find.descendant(
        of: find.byType(ComposerPanel),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'A native topic');
      await tester.enterText(fields.at(1), 'Created from the docked composer.');
      await tester.pump();
      final composer = ShellScope.read(
        tester.element(find.byType(MainContent)),
      ).visibleComposer!;
      expect(composer.title.text, 'A native topic');
      expect(composer.raw, 'Created from the docked composer.');
      expect(composer.canSubmit, isTrue);
      await tester.tap(find.text('Create topic'));
      await tester.pumpAndSettle();

      expect(api.topicsCreated.single['title'], 'A native topic');
      expect(api.topicsCreated.single['categoryId'], isNull);
      expect(find.byType(ComposerPanel), findsNothing);
      expect(find.text('A native topic'), findsOneWidget);
      expect(
        api.feedPaths.where((path) => path == '/latest.json').length,
        greaterThanOrEqualTo(2),
      );
    });

    /// Messages is the only destination the sidebar offers besides Topics, and
    /// the inbox is named after the signed-in user, so reaching it means
    /// connecting first.
    const inbox = '/topics/private-messages/joffreyj.json';

    testWidgets('picking a destination fetches its own list', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains(inbox));
      expect(find.text('A private message'), findsOneWidget);
    });

    testWidgets(
      'messages never offers New Topic even if its feed says it can',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': latest,
            inbox: [
              const Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
          creatableFeedPaths: const {'/latest.json', inbox},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(userMenu);
        await tester.pumpAndSettle();
        await tester.tap(sidebarDestination('Messages'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('New topic'), findsNothing);
      },
    );

    testWidgets('a list is not refetched when revisited', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(
        api.feedPaths.where((p) => p == '/latest.json').length,
        2,
        reason: 'sign-in refreshes the personalized list, revisiting reuses it',
      );
    });

    testWidgets('tapping the destination on screen asks for it again', (
      tester,
    ) async {
      // A mouse cannot pull to refresh, so the destination is its own
      // affordance: tapping what is already there re-fetches the list.
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      expect(api.feedPaths, ['/latest.json']);

      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json', '/latest.json']);
    });

    testWidgets('unread topics carry a count', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('mirrored unread fields produce one undoubled count', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Tracked topic',
              slug: 'tracked-topic',
              unreadPosts: 3,
              newPosts: 3,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('6'), findsNothing);
    });

    testWidgets('caught-up titles are dimmed independently of badges', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 8,
              title: 'Caught up',
              slug: 'caught-up',
              lastReadPostNumber: 5,
              highestPostNumber: 5,
            ),
            const Topic(
              id: 9,
              title: 'Not caught up',
              slug: 'not-caught-up',
              lastReadPostNumber: 4,
              highestPostNumber: 5,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      final context = tester.element(find.text('Caught up'));
      final colors = Theme.of(context).colorScheme;
      expect(
        tester.widget<Text>(find.text('Caught up')).style?.color,
        colors.onSurfaceVariant,
      );
      expect(
        tester.widget<Text>(find.text('Not caught up')).style?.color,
        colors.onSurface,
      );
    });

    testWidgets('an unseen flat topic carries the new-topic dot', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Never opened',
              slug: 'never-opened',
              seen: false,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.byKey(const ValueKey('new-topic-dot')), findsOneWidget);
      expect(find.bySemanticsLabel('New topic'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-replies-dot')), findsNothing);
    });

    testWidgets('topic state follows the title instead of the row edge', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Short title',
              slug: 'short-title',
              seen: false,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      final title = tester.getRect(find.text('Short title'));
      final dot = tester.getRect(find.byKey(const ValueKey('new-topic-dot')));
      expect(dot.left - title.right, moreOrLessEquals(8, epsilon: 0.01));
    });

    testWidgets('a nested topic only carries its new-replies dot', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: 'Nested topic',
              slug: 'nested-topic',
              isNestedView: true,
              hasNewReplies: true,
              seen: false,
              unreadPosts: 5,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.byKey(const ValueKey('new-replies-dot')), findsOneWidget);
      expect(find.bySemanticsLabel('Topic has new replies'), findsOneWidget);
      expect(find.byKey(const ValueKey('new-topic-dot')), findsNothing);
      expect(find.text('5'), findsNothing);
    });

    testWidgets('category badges render once categories arrive', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '0088CC'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('Feature'), findsOneWidget);
    });

    testWidgets('topic tags render after the category in server order', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'A tagged topic',
              slug: 'a-tagged-topic',
              categoryId: 5,
              tags: [
                TopicTag(id: 8, name: 'design', slug: 'design'),
                TopicTag(id: 9, name: 'accessibility', slug: 'accessibility'),
              ],
            ),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '0088CC'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('design,'), findsOneWidget);
      expect(find.text('accessibility'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Tags: design, accessibility'),
        findsOneWidget,
      );
      expect(
        tester.getTopRight(find.text('Feature')).dx,
        lessThan(tester.getTopLeft(find.text('design,')).dx),
      );
    });

    testWidgets('long topic tags wrap without overflowing a phone row', (
      tester,
    ) async {
      final longName = 'a-very-long-${List.filled(30, 'tag-name-').join()}';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            Topic(
              id: 3,
              title: 'A tagged topic',
              slug: 'a-tagged-topic',
              tags: [
                const TopicTag(name: 'design'),
                TopicTag(name: longName),
                const TopicTag(name: 'accessibility'),
                const TopicTag(name: 'mobile'),
                const TopicTag(name: 'support'),
              ],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();

      expect(find.text('design,'), findsOneWidget);
      expect(find.textContaining(longName), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing list reports it instead of crashing', (
      tester,
    ) async {
      // No feeds configured, so the call throws.
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);

      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('messages has no list endpoint without a username', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('Messages'));
      await tester.pumpAndSettle();

      // The inbox path is named after the account, so with no signed-in user
      // it falls back to the placeholder rather than firing a bad request.
      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Replace with deeper view'), findsOneWidget);
    });
  });

  group('incoming topics', () {
    final onList = [
      const Topic(id: 1, title: 'Welcome to the forum', slug: 'welcome'),
      const Topic(id: 2, title: 'Something else', slug: 'something-else'),
    ];

    /// `/new`, shaped as `TopicTrackingState.publish_new` sends it.
    Map<String, Object?> created(int topicId) => {
      'topic_id': topicId,
      'message_type': 'new_topic',
      'payload': {'highest_post_number': 1, 'created_in_new_period': true},
    };

    /// `/latest`, published when a post bumps a topic that already exists.
    Map<String, Object?> bumped(int topicId) => {
      'topic_id': topicId,
      'message_type': 'latest',
      'payload': {'bumped_at': '2026-08-06T09:00:00.000Z'},
    };

    /// The tracker for the site the shell opened on.
    FakeSiteTracker tracker() => FakeSiteTracker.built.first;

    Future<void> pumpWithFeeds(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      await pumpShell(tester, desktop, api: api);
      // The tracker is opened once the keychain has answered.
      await tester.pumpAndSettle();
    }

    testWidgets('a topic created on the site announces itself', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      expect(find.textContaining('See '), findsNothing);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
    });

    testWidgets('the count is of topics, not of messages', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker()
        ..deliver(created(99))
        ..deliver(created(100))
        // A reply to one of them is the same row, not another one.
        ..deliver(bumped(99));
      await tester.pumpAndSettle();

      expect(find.text('See 2 new or updated topics'), findsOneWidget);
    });

    testWidgets('tapping it fetches those topics and puts them on top', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=99': [
            const Topic(id: 99, title: 'Just posted', slug: 'just-posted'),
          ],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      // Asked of the list route itself, so the row arrives with everything
      // that list draws rather than as a bare topic.
      expect(api.feedPaths, contains('/latest.json?topic_ids=99'));
      expect(find.text('Just posted'), findsOneWidget);
      expect(find.text('Welcome to the forum'), findsOneWidget);
      // Nothing left to announce.
      expect(find.textContaining('See '), findsNothing);
    });

    testWidgets('a topic that was only bumped is moved, not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': onList,
          '/latest.json?topic_ids=2': [onList[1]],
        },
      );
      await pumpWithFeeds(tester, api);

      tracker().deliver(bumped(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('Something else'), findsOneWidget);
    });

    testWidgets('a fetch that fails leaves the banner to be tried again', (
      tester,
    ) async {
      // No `topic_ids` feed configured, so the call throws.
      final api = FakeDiscourseApi(feeds: {'/latest.json': onList});
      await pumpWithFeeds(tester, api);

      tracker().deliver(created(99));
      await tester.pumpAndSettle();
      await tester.tap(find.text('See 1 new or updated topic'));
      await tester.pumpAndSettle();

      expect(find.text('See 1 new or updated topic'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('refetching the list clears what it is about to contain', (
      tester,
    ) async {
      // Pull-to-refresh replaces the list wholesale, so what the banner was
      // offering to fetch arrives in the response instead.
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(feeds: {'/latest.json': onList}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
      // The tracker is opened once the keychain has answered.
      await tester.pump();

      FakeSiteTracker.built.first.deliver(created(99));
      expect(controller.incomingCount('latest'), 1);

      await controller.loadFeed('latest', force: true);

      expect(controller.incomingCount('latest'), 0);
    });

    testWidgets('only the site being read holds a connection open', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      expect(FakeSiteTracker.built, hasLength(1));

      // Second entry in the rail.
      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built, hasLength(2));
      expect(FakeSiteTracker.built.first.polling, isFalse);
      expect(FakeSiteTracker.built.last.polling, isTrue);
    });

    testWidgets('an app coming back to the front reconnects at once', (
      tester,
    ) async {
      await pumpWithFeeds(tester, FakeDiscourseApi());

      // Backgrounded, the connection is left to the client's own pacing.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tracker().pollNowCalls, 0);

      // Back in front, it is asked immediately rather than waiting out a
      // backoff that started while the connection was dead.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tracker().pollNowCalls, 1);
    });
  });

  group('live counters', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

    final dot = find.byKey(UserMenuButton.unreadDotKey);

    /// A site that is already signed in, so the counter channels have an
    /// account to be named after.
    Future<FakeSiteTracker> pumpConnected(
      WidgetTester tester, {
      NotificationTotals totals = const NotificationTotals(),
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(totals: totals),
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.pumpAndSettle();
      return FakeSiteTracker.built.first;
    }

    testWidgets('the account id is what names the counter channels', (
      tester,
    ) async {
      final tracker = await pumpConnected(tester);

      expect(tracker.userId, 7);
    });

    testWidgets('a notification arriving marks the avatar', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(dot, findsNothing);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 1,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(dot, findsOneWidget);
    });

    testWidgets('reading them somewhere else takes the mark away', (
      tester,
    ) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      expect(dot, findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 0,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(dot, findsNothing);
    });

    testWidgets('the counts move with it, not just the mark', (tester) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      // The rail badge, which is everything addressed to this account.
      expect(find.text('3'), findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 5,
        'new_personal_messages_notifications_count': 2,
      });
      await tester.pumpAndSettle();

      expect(find.text('5'), findsOneWidget);
      // And the private messages counted once, under their own name.
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a filling review queue marks it too', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(dot, findsNothing);

      // Published on a channel of its own, and only to staff.
      tracker.deliverReviewableCounts(const {
        'reviewable_count': 4,
        'unseen_reviewable_count': 2,
      });
      await tester.pumpAndSettle();

      expect(dot, findsOneWidget);
    });

    testWidgets('a site with nobody signed in has no counters to track', (
      tester,
    ) async {
      await pumpShell(tester, desktop);
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.first.userId, isNull);
      expect(dot, findsNothing);
    });
  });

  group('infinite scroll', () {
    // The rail and sidebar scroll too, so target the topic list.
    final topicList = find.descendant(
      of: find.byType(TopicListView),
      matching: find.byType(SuperListView),
    );

    List<Topic> page(int from, int count) => [
      for (var i = from; i < from + count; i++)
        Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
    ];

    testWidgets('reaching the end appends the next page', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          '/latest.json?page=1': page(31, 30),
        },
        // Discourse reports it without the extension.
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('Topic 1'), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      // The extension was added before requesting.
      expect(api.feedPaths, contains('/latest.json?page=1'));
      expect(find.text('Topic 31'), findsOneWidget);
    });

    testWidgets('the next page can be asked for from inside a layout', (
      tester,
    ) async {
      // The caller this stands in for is the load-more handler. A viewport
      // that has to correct its scroll position starts a scroll from inside
      // its own layout, and the notification that comes out of it reaches the
      // handler there — so the controller is asked for a page mid-frame, where
      // marking the tree dirty is an error rather than a rebuild.
      //
      // Re-creating that correction takes a precise pile of geometry;
      // LayoutBuilder puts the call in the same phase directly, which is the
      // part that has to hold.
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(
          feeds: {
            '/latest.json': page(1, 3),
            '/latest.json?page=1': page(4, 3),
          },
          nextPages: {'/latest.json': '/latest?page=1'},
        ),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await tester.pumpWidget(
        ShellScope(
          controller: controller,
          child: MaterialApp(
            home: LayoutBuilder(
              builder: (context, _) {
                unawaited(ShellScope.of(context).loadMoreFeed('latest'));
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // And the page was actually fetched, rather than the ask being dropped.
      expect(controller.currentFeed?.topicIds, hasLength(6));
    });

    testWidgets('a topic repeated across pages is not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          // Topic 30 got bumped and comes back on page two.
          '/latest.json?page=1': [...page(30, 1), ...page(31, 5)],
        },
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      expect(find.text('Topic 30'), findsOneWidget);
    });

    testWidgets('a last page stops further requests', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': page(1, 30)});

      await pumpShell(tester, desktop, api: api);
      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

      // No more_topics_url, so nothing beyond the first request.
      expect(api.feedPaths, ['/latest.json']);
    });
  });

  testWidgets('a response landing after the shell is gone is ignored', (
    tester,
  ) async {
    tester.view.physicalSize = desktop;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final gate = Completer<void>();
    final api = FakeDiscourseApi(feeds: const {'/latest.json': []}, gate: gate);

    await tester.pumpWidget(
      DiscourseApp(
        store: FakeInstanceStore(twoSites),
        api: api,
        authenticator: FakeAuthenticator(),
      ),
    );
    // Let load() and the first feed request start, but not finish.
    await tester.pump();

    // The shell goes away while the request is still in flight.
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();

    // Notifying a disposed ChangeNotifier throws; the controller must not.
    expect(tester.takeException(), isNull);
  });

  group('opening a topic', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post post(int id, int number, String body) => Post(
      id: id,
      postNumber: number,
      username: 'joffreyj',
      cooked: '<p>$body</p>',
    );

    TopicPayload detail({
      List<int> stream = const [1],
      TopicRecommendations? recommendations,
    }) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [post(1, 1, 'First post body')],
      stream: stream,
      recommendations: recommendations,
    );

    testWidgets('tapping a row replaces the list with the topic', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(find.byType(TopicView), findsOneWidget);
      expect(find.byType(TopicListView), findsNothing);
      // The cooked HTML is rendered, not shown as markup.
      expect(renderedText('First post body'), findsOneWidget);
      expect(renderedText('<p>'), findsNothing);
    });

    testWidgets('an unread row opens at its first unread post', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              unreadPosts: 5,
              lastReadPostNumber: 5,
              highestPostNumber: 10,
            ),
          ],
        },
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicPostNumbersOpened, [6]);
      expect(
        ShellScope.of(
          tester.element(find.byType(TopicView)),
        ).currentContent?.postNumber,
        6,
      );
    });

    testWidgets('back returns to the list without refetching it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.byType(TopicListView), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('reading a topic clears its unread count on every list it is '
        'in', (tester) async {
      // A list holds ids, and there is one topic behind an id — so reading it
      // is one write, and no list has to be told anything.
      final unread = [
        const Topic(
          id: 7,
          title: 'A real topic',
          slug: 'a-real-topic',
          unreadPosts: 3,
        ),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': unread},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      // The row it was opened from.
      expect(find.text('3'), findsNothing);

      // There is nothing left holding a count: the topic itself now reads as
      // read, so any other list holding its id draws the corrected row without
      // a fetch and without being told.
      final controller = ShellScope.of(
        tester.element(find.byType(InstanceRail)),
      );
      expect(
        controller.store
            .read<Topic>(controller.currentInstance!.url, 7)!
            .hasUnread,
        isFalse,
      );
    });

    testWidgets('back lands where the list was left, not at the top', (
      tester,
    ) async {
      final many = [
        for (var i = 1; i <= 60; i++)
          Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': many},
        topics: {for (final topic in many) topic.id: detail()},
      );

      await pumpShell(tester, desktop, api: api);

      final list = find.descendant(
        of: find.byType(TopicListView),
        matching: find.byType(Scrollable),
      );
      // Far enough down that the top of the list is no longer built.
      final row = find.text('Topic 40');
      await tester.scrollUntilVisible(row, 400, scrollable: list);
      await tester.pumpAndSettle();
      expect(find.text('Topic 1'), findsNothing);

      await tester.tap(
        find.ancestor(of: row, matching: find.byType(InkWell)).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      // Back on the list, still down among the forties rather than at the top.
      expect(find.text('Topic 40'), findsOneWidget);
      expect(find.text('Topic 1'), findsNothing);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('a topic that fails to load says so', (tester) async {
      // No topics configured, so the fetch throws.
      final api = FakeDiscourseApi(feeds: {'/latest.json': listed});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load this topic"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remaining posts are fetched by id, not by page', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        // Twenty arrive with the topic; the rest are ids only.
        topics: {
          7: detail(stream: [1, 2, 3]),
        },
        postsById: {
          2: post(2, 2, 'Second post body'),
          3: post(3, 3, 'Third post body'),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2, 3],
      ]);
      expect(renderedText('Second post body'), findsOneWidget);
    });

    testWidgets('shows suggested and discourse-ai related tabs at the end', (
      tester,
    ) async {
      const recommendations = TopicRecommendations(
        suggested: [
          Topic(id: 8, title: 'A suggested topic', slug: 'a-suggested-topic'),
        ],
        related: [
          Topic(id: 9, title: 'An AI related topic', slug: 'an-ai-topic'),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(recommendations: recommendations),
          9: topicPayload(
            id: 9,
            title: 'An AI related topic',
            posts: [post(9, 1, 'Related topic body')],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Related'), findsOneWidget);
      expect(find.text('A suggested topic'), findsOneWidget);
      expect(find.text('An AI related topic'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('related-topics-tab')));
      await tester.pumpAndSettle();

      expect(find.text('A suggested topic'), findsNothing);
      expect(find.text('An AI related topic'), findsOneWidget);

      await tester.tap(find.text('An AI related topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Related topic body'), findsOneWidget);
    });

    testWidgets('gets more topics with the final page of a long topic', (
      tester,
    ) async {
      const recommendations = TopicRecommendations(
        suggested: [
          Topic(id: 8, title: 'Suggested at the end', slug: 'suggested-end'),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(stream: [1, 2]),
        },
        postsById: {2: post(2, 2, 'Last post body')},
        postRecommendations: {7: recommendations},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2],
      ]);
      expect(renderedText('Last post body'), findsOneWidget);
      expect(find.text('Suggested at the end'), findsOneWidget);
    });

    testWidgets('a topic already held is not refetched', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
    });

    testWidgets('the post under the pointer is picked out', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final hover = Theme.of(
        tester.element(find.byType(TopicView)),
      ).shell.hover;

      // Idle posts take the column's own surface rather than painting one.
      expect(postBackground(tester), Colors.transparent);

      final gesture = await hoverPost(tester);
      expect(postBackground(tester), hover);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(postBackground(tester), Colors.transparent);
    });
  });

  group('connecting', () {
    testWidgets('the avatar says so until you connect', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byTooltip('Not signed in'), findsOneWidget);
    });

    testWidgets('connecting records the account against the site', (
      tester,
    ) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Authorized against the selected site, not some other one.
      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsNothing);
      // First the old identity is removed, then the verified one is recorded.
      expect(store.saveCount, 2);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Not signed in'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Nothing is left on screen to hold the failure, so it is announced.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('could not be verified'), findsOneWidget);
    });

    testWidgets('a browser that never opened is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.launchFailed);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // The distinction that matters: the user did not choose this, so unlike
      // a cancellation it cannot pass silently.
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not open'), findsOneWidget);
    });

    testWidgets('counters appear once connected', (tester) async {
      final api = FakeDiscourseApi(
        totals: const NotificationTotals(
          unreadNotifications: 3,
          unreadPersonalMessages: 2,
          topicTrackingUnread: 12,
          topicTrackingNew: 7,
        ),
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      // Messages is the one sidebar entry with a count of its own.
      expect(find.text('2'), findsOneWidget);
      // Topic tracking has no entry to sit on: the sidebar collapses Latest,
      // New and Unread into a single Topics destination.
      expect(find.text('12'), findsNothing);
      expect(find.text('7'), findsNothing);
      // Rail badge is things addressed to you: 3 + 2.
      expect(find.text('5'), findsOneWidget);
      // All of it from the one totals call.
      expect(api.totalsCalls, 1);
    });

    testWidgets('a site whose counters fail still renders', (tester) async {
      // totals: null makes the call throw.
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching to a connected site refreshes its counters', (
      tester,
    ) async {
      final connected = [
        instance('meta.discourse.org', title: 'Discourse Meta'),
        instance('team.discourse.org', title: 'Discourse Team'),
      ];
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(
        tester,
        desktop,
        instances: connected,
        api: api,
        authenticator: auth,
      );

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      final afterConnect = api.totalsCalls;

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(api.totalsCalls, greaterThan(afterConnect));
      expect(auth.connected, [
        'https://meta.discourse.org',
        'https://team.discourse.org',
      ]);
    });

    testWidgets('disconnecting revokes the key with the site', (tester) async {
      final api = FakeDiscourseApi(totals: const NotificationTotals());
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, api: api, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      await openProfileSection(tester);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      // Told the site, not just our own keychain.
      expect(api.revoked, ['https://meta.discourse.org']);
      expect(auth.disconnected, ['https://meta.discourse.org']);
    });

    testWidgets('disconnecting forgets the key and the account', (
      tester,
    ) async {
      final auth = FakeAuthenticator();
      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Joffrey'), findsOneWidget);

      await openProfileSection(tester);
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();

      expect(auth.disconnected, ['https://meta.discourse.org']);
      // Both sheets are gone with it, and the avatar is back to signed out.
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byTooltip('Not signed in'), findsOneWidget);
    });
  });

  group('the user menu', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');
    final connected = [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    /// These instances carry an account without having been through the
    /// connect flow, which is what would otherwise have left a key behind.
    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'api-key';

    const notifications = [
      DiscourseNotification(
        id: 1,
        kind: NotificationKind.replied,
        actor: 'sam',
        title: 'Better image handling',
        topicId: 7,
        slug: 'better-image-handling',
        path: '/t/better-image-handling/7',
      ),
      DiscourseNotification(
        id: 2,
        kind: NotificationKind.liked,
        read: true,
        actor: 'david',
        title: 'Merge CVSS',
        topicId: 8,
        path: '/t/merge-cvss/8',
      ),
      // This app has no badge page, so this one leads out to the browser.
      DiscourseNotification(
        id: 3,
        kind: NotificationKind.grantedBadge,
        badgeName: 'Nice Reply',
        path: '/badges/24/nice-reply',
      ),
      // And this one points at nothing at all.
      DiscourseNotification(
        id: 4,
        kind: NotificationKind.unknown,
        title: 'Something from a plugin',
      ),
    ];

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
    }

    /// Opens the notifications tab on a touch layout, which is a sheet of its
    /// own on top of the menu.
    Future<void> openNotifications(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    }

    testWidgets('a thumb gets a sheet, and one sheet per section inside it', (
      tester,
    ) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);

      // Listed rather than tabbed, and no popover in sight.
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('@joffreyj · meta.discourse.org'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(find.textContaining('joshua.m replied to'), findsOneWidget);
      // The sheet it came from is still under this one — nested, not swapped —
      // so the way out of this one is back to it.
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.dIcon(DIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.textContaining('joshua.m replied to'), findsNothing);
    });

    testWidgets('a title bar takes the avatar off the columns', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          key: const ValueKey('macos'),
        );

        expect(userMenu, findsOneWidget);
        final avatar = tester.getRect(userMenu);

        // In the strip spanning the window, above every column rather than
        // inside one of them.
        expect(
          tester.getRect(find.byType(ShellTitleBar)).contains(avatar.center),
          isTrue,
        );
        expect(
          avatar.bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(MainContent)).top),
        );
        expect(desktop.width - avatar.right, lessThan(16));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a pointer gets a popover with a tab per section', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        // A distinct key rebuilds the tree against the platform in effect.
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: FakeDiscourseApi(notificationList: notifications),
          authenticator: signedIn(),
          key: const ValueKey('macos'),
        );
        await openMenu(tester);

        expect(find.byType(UserMenuPanel), findsOneWidget);
        // Opens on the notifications tab, the way Discourse does.
        expect(
          find.textContaining('sam replied to Better image handling'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Likes'));
        await tester.pumpAndSettle();

        expect(find.text('Likes'), findsOneWidget);
        expect(find.textContaining('sam replied to'), findsNothing);
        expect(find.textContaining('liked your post'), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the pointer messages tab opens the full inbox', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': const [],
            '/topics/private-messages/joffreyj.json': const [
              Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: api,
          authenticator: signedIn(),
          key: const ValueKey('pointer-messages'),
        );
        await openMenu(tester);

        await tester.tap(find.byTooltip('Messages'));
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.text('A private message'), findsOneWidget);
        expect(
          api.feedPaths,
          contains('/topics/private-messages/joffreyj.json'),
        );
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('the touch messages row opens the full inbox', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [],
          '/topics/private-messages/joffreyj.json': const [
            Topic(id: 9, title: 'A private message', slug: 'a-pm'),
          ],
        },
      );
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      // The instance sidebar is still mounted under the modal sheet.
      await tester.tap(find.text('Messages').last);
      await tester.pumpAndSettle();

      expect(find.text('Joffrey'), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.text('A private message'), findsOneWidget);
    });

    testWidgets('the account section is last and holds the disconnect', (
      tester,
    ) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);

      // Nothing else in the menu can act on the account.
      expect(find.text('Disconnect'), findsNothing);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('everything not built yet is orange', (tester) async {
      await pumpShell(tester, phone, instances: connected);
      await openMenu(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final placeholder = Theme.of(
        tester.element(find.text('Preferences')),
      ).shell.placeholder;

      expect(
        tester.widget<Text>(find.text('Preferences')).style?.color,
        placeholder,
      );
      // ...and the one thing that works is not.
      expect(
        tester.widget<Text>(find.text('Disconnect')).style?.color,
        isNot(placeholder),
      );
    });

    testWidgets('the notifications tab reads what the site sent', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(api.notificationCalls, 1);
      // A sentence per kind, phrased from the payload rather than listed as
      // whatever the site called it.
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('david liked your post in Merge CVSS'),
        findsOneWidget,
      );
      expect(
        find.textContaining('You earned the Nice Reply badge'),
        findsOneWidget,
      );
      // Nothing in here is a stand-in any more.
      final tab = tester.widget<Text>(find.text('Notifications').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens its topic and marks it read', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        notificationList: notifications,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Better image handling',
            posts: [
              Post(
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

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(
        find.textContaining('sam replied to Better image handling'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.markedRead, [1]);
      // Both sheets are out of the way of the topic they led to.
      expect(find.byType(NotificationRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('one the app has no page for opens the browser', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('You earned the Nice Reply badge'));
      await tester.pumpAndSettle();

      // Resolved against the site it came from, since Discourse writes its own
      // links site-relative.
      expect(launched, ['https://meta.discourse.org/badges/24/nice-reply']);
      expect(api.markedRead, [3]);
      expect(find.byType(NotificationRow), findsNothing);
    });

    testWidgets('one with nowhere to go is read where it stands', (
      tester,
    ) async {
      final api = FakeDiscourseApi(notificationList: notifications);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.textContaining('Something from a plugin'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [4]);
      expect(launched, isEmpty);
      // Closing the menu would only have revealed the screen it was already
      // over, so it stays.
      expect(find.byType(NotificationRow), findsWidgets);
    });

    testWidgets('notifications that will not load can be asked for again', (
      tester,
    ) async {
      // No list configured, so the fetch throws.
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.notificationCalls, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty inbox says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(notificationList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);

      expect(find.text('Nothing new.'), findsOneWidget);
    });

    testWidgets('reopening the tab asks the site again', (tester) async {
      final api = FakeDiscourseApi(notificationList: notifications);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openNotifications(tester);
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();

      // A list of what other people just did is stale within minutes.
      expect(api.notificationCalls, 2);
      // ...and the rows already in hand stay put while it is refetched.
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
    });

    const bookmarks = [
      // Site-relative, which is what the parse leaves a topic link as — see
      // `Bookmark._path`.
      Bookmark(
        id: 8,
        title: 'Thinking about the next project',
        name: 'read this properly',
        author: 'sam',
        path: '/t/next-project/7/3',
      ),
      // Bookmarked on something this app has no view for, so it leads out to
      // the browser, and keeps the absolute URL the site sent.
      Bookmark(
        id: 9,
        title: 'A message in #dev',
        author: 'david',
        path: 'https://meta.discourse.org/chat/c/-/9/44',
      ),
    ];

    /// A reminder that has come due, which the tab lists above the bookmarks.
    const reminder = DiscourseNotification(
      id: 41,
      kind: NotificationKind.bookmarkReminder,
      title: 'Better image handling',
      topicId: 7,
      slug: 'better-image-handling',
      path: '/t/better-image-handling/7',
    );

    Future<void> openBookmarks(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Bookmarks'));
      await tester.pumpAndSettle();
    }

    testWidgets('the bookmarks tab reads what the site sent', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      // The account's own bookmarks; Discourse refuses anybody else's.
      expect(api.bookmarksRequested, ['joffreyj']);
      // The reminder first, then what is kept.
      expect(
        find.textContaining('Reminder: Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sam Thinking about the next project'),
        findsOneWidget,
      );
      // Nothing in here is a stand-in any more.
      final tab = tester.widget<Text>(find.text('Bookmarks').first);
      expect(
        tab.style?.color,
        isNot(Theme.of(tester.element(find.text('Profile'))).shell.placeholder),
      );
    });

    testWidgets('tapping one opens the topic it was kept from', (tester) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Thinking about the next project',
            posts: [
              Post(
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

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      // Both sheets are out of the way of the topic they led to.
      expect(find.byType(BookmarkRow), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('a topic opens here even when the site named another host', (
      tester,
    ) async {
      // Straight off the wire, because it is the parse that has to take the
      // host off: `Discourse.base_url` is the site's own idea of where it
      // lives, and a development site's is not the origin the app connected
      // through. Left alone, its own topics look like somebody else's and go
      // to the browser.
      final api = FakeDiscourseApi(
        bookmarkList: [
          Bookmark.fromJson(const {
            'id': 8,
            'title': 'Thinking about the next project',
            'bookmarkable_url': 'http://localhost:4200/t/next-project/7/3',
            'user': {'username': 'sam'},
          }),
        ],
        topics: {
          7: topicPayload(id: 7, title: 'Thinking about the next project'),
        },
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: [instance('localhost:3000').copyWith(user: me)],
        api: api,
        authenticator: FakeAuthenticator()
          ..keys['https://localhost:3000'] = 'api-key',
      );
      await openBookmarks(tester);
      await tester.tap(
        find.textContaining('sam Thinking about the next project'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(launched, isEmpty);
    });

    testWidgets('one on something the app has no page for opens the browser', (
      tester,
    ) async {
      final api = FakeDiscourseApi(bookmarkList: bookmarks);
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('david A message in #dev'));
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/chat/c/-/9/44']);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a reminder in here is read like any other notification', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        bookmarkList: bookmarks,
        reminderList: const [reminder],
        topics: {7: topicPayload(id: 7, title: 'Better image handling')},
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      await tester.tap(find.textContaining('Reminder: Better image handling'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [41]);
      expect(api.topicsOpened, [7]);
    });

    testWidgets('nothing kept says so rather than spinning', (tester) async {
      final api = FakeDiscourseApi(bookmarkList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.text('Nothing bookmarked yet.'), findsOneWidget);
    });

    testWidgets('bookmarks that will not load can be asked for again', (
      tester,
    ) async {
      // No list configured, so the fetch throws.
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.bookmarksRequested.length, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('user cards', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final detail = topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          name: 'Joffrey',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
    );

    final card = UserCard(
      username: 'joffreyj',
      name: 'Joffrey',
      title: 'Team member',
      bioExcerpt: '<p>Builds the thing.</p>',
      createdAt: DateTime.utc(2015, 3, 4),
      badgeCount: 12,
    );

    Future<void> openTopic(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping an avatar opens the card', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      await tester.tap(
        find.descendant(
          of: find.byType(TopicView),
          matching: find.byType(AvatarImage),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(find.text('@joffreyj'), findsOneWidget);
      expect(find.text('Team member'), findsOneWidget);
      expect(renderedText('Builds the thing.'), findsOneWidget);
      expect(find.text('Mar 2015'), findsOneWidget);
    });

    testWidgets('tapping the name opens the same card, already held', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': card},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsOneWidget);

      // Dismiss by tapping the barrier, then open it again.
      await tester.tapAt(const Offset(20, 500));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsNothing);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.text('@joffreyj'), findsOneWidget);
      expect(api.cardsRequested, ['joffreyj']);
    });

    testWidgets('a card that fails to load offers a retry', (tester) async {
      // No cards configured, so the fetch throws.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail},
      );

      await openTopic(tester, api);
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj', 'joffreyj']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an open card keeps the site that it was loaded from', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = _GatedUserCardApi(
        cardGate: gate,
        feeds: {'/latest.json': listed},
        topics: {7: detail},
      );

      await openTopic(tester, api);
      final shell = ShellScope.read(tester.element(find.byType(TopicView)));

      await tester.tap(find.text('Joffrey'));
      await tester.pump();
      await api.started.future;
      await tester.pump(const Duration(milliseconds: 200));

      shell.selectInstance(1);
      await tester.pump();

      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(api.cardSites, ['https://meta.discourse.org']);
      expect(shell.currentInstance?.url, 'https://team.discourse.org');
      expect(find.text('First-site profile'), findsOneWidget);
      expect(find.text('From Meta'), findsOneWidget);
    });
  });

  group('following links', () {
    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    /// A topic whose only post is a single link, so there is something to tap.
    TopicPayload linking(String href, String label) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          cooked: '<p><a href="$href">$label</a></p>',
        ),
      ],
      stream: const [1],
    );

    /// The topic behind every link below, titled differently from its slug so
    /// the header can be told apart from the guess made before it arrived.
    final landed = topicPayload(
      id: 9,
      title: 'The other one [solved]',
      posts: const [
        Post(
          id: 2,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>Other topic body</p>',
        ),
      ],
      stream: const [2],
    );

    Future<List<String>> openPostLinking(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      final launched = watchBrowser(tester);
      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return launched;
    }

    testWidgets('a topic on the site being read opens here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: linking(
            'https://meta.discourse.org/t/the-other-one/9',
            'the other one',
          ),
          9: landed,
        },
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the other one'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Other topic body'), findsOneWidget);
      // The slug was only a stand-in until the topic named itself.
      expect(find.text('The other one [solved]'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a topic on another site in the rail switches to it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: linking(
            'https://team.discourse.org/t/the-other-one/9',
            'over on team',
          ),
          9: landed,
        },
      );

      final launched = await openPostLinking(tester, api);
      expect(find.text('Discourse Meta'), findsOneWidget);

      await tester.tapOnText(find.textRange.ofSubstring('over on team'));
      await tester.pumpAndSettle();

      expect(find.text('Discourse Team'), findsOneWidget);
      expect(renderedText('Other topic body'), findsOneWidget);
      expect(launched, isEmpty);

      // The site's own list is what the topic sits on top of, so back lands
      // there rather than on the site the link was read from.
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.text('Discourse Team'), findsOneWidget);
    });

    testWidgets('a topic on a site not in the rail goes to the browser', (
      tester,
    ) async {
      const url = 'https://example.com/t/the-other-one/9';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'somewhere else'), 9: landed},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('somewhere else'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.topicsOpened, [7]);
      expect(renderedText('somewhere else'), findsOneWidget);
    });

    testWidgets('a page that is not a topic goes to the browser', (
      tester,
    ) async {
      // Same site, but nothing here can draw it.
      const url = 'https://meta.discourse.org/faq';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'the faq')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the faq'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.topicsOpened, [7]);
    });

    testWidgets('a site-relative link is read as this site', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking('/t/the-other-one/9', 'the other one'), 9: landed},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the other one'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Other topic body'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a category link opens the list here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        topics: {7: linking('/c/bug/5', 'the bug category')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the bug category'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/c/bug/5.json'));
      expect(find.text('A bug report'), findsOneWidget);
      expect(launched, isEmpty);

      // Pushed over the topic rather than replacing the sidebar's selection,
      // so there is a way back to what was being read.
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();
      expect(renderedText('the bug category'), findsOneWidget);
    });

    testWidgets('a subcategory keeps its whole path', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/parent/child/12.json': [
            const Topic(id: 3, title: 'Nested topic', slug: 'nested-topic'),
          ],
        },
        topics: {7: linking('/c/parent/child/12', 'the nested one')},
      );

      await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the nested one'));
      await tester.pumpAndSettle();

      // `/c/child/12.json` would be a different category, and would 404.
      expect(api.feedPaths, contains('/c/parent/child/12.json'));
      expect(find.text('Nested topic'), findsOneWidget);
    });

    testWidgets('a tag link opens the list here', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/tag/ux/3.json': [
            const Topic(id: 4, title: 'A tagged topic', slug: 'a-tagged-topic'),
          ],
        },
        topics: {7: linking('/tag/ux/3', 'the ux tag')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the ux tag'));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/tag/ux/3.json'));
      expect(find.text('A tagged topic'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a filtered category list goes to the browser', (tester) async {
      // A real route, but one this app has no screen for. Showing the
      // unfiltered list instead would be answering a different question.
      const url = 'https://meta.discourse.org/c/bug/5/l/top';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'the top of it')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the top of it'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
      expect(api.feedPaths, isNot(contains('/c/bug/5/l/top.json')));
    });

    testWidgets('a category on a site not in the rail goes to the browser', (
      tester,
    ) async {
      const url = 'https://example.com/c/bug/5';
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: linking(url, 'somewhere else')},
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('somewhere else'));
      await tester.pumpAndSettle();

      expect(launched, [url]);
    });

    testWidgets('the same category is not stacked twice', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        topics: {7: linking('/c/bug/5', 'the bug category')},
      );

      await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('the bug category'));
      await tester.pumpAndSettle();

      // Already looking at it: the list is not fetched again, and one tap back
      // still reaches the post.
      final before = api.feedPaths.length;
      await tester.tap(find.text('A bug report'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(api.feedPaths.length, before);
      expect(find.text('A bug report'), findsOneWidget);
    });

    testWidgets('a cooked hashtag opens the list it names', (tester) async {
      // The whole feature end to end: the markup Discourse actually writes,
      // drawn as a pill, tapped, landing on the category's own list — without
      // the browser being involved at any point.
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': listed,
          '/c/bug/5.json': [
            const Topic(id: 3, title: 'A bug report', slug: 'a-bug-report'),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Bug', color: '0088CC', slug: 'bug'),
        ],
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked:
                    '<p>filed under <a class="hashtag-cooked" href="/c/bug/5" '
                    'data-type="category" data-slug="bug" data-id="5" '
                    'data-style-type="square"><span '
                    'class="hashtag-icon-placeholder"></span>'
                    '<span>Bug</span></a></p>',
              ),
            ],
            stream: const [1],
          ),
        },
      );

      final launched = await openPostLinking(tester, api);
      expect(find.byType(HashtagPill), findsOneWidget);

      await tester.tap(find.byType(HashtagPill));
      await tester.pumpAndSettle();

      expect(api.feedPaths, contains('/c/bug/5.json'));
      expect(find.text('A bug report'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('a mention opens the card', (tester) async {
      // The markup Discourse actually cooks for `@joffreyj`, which the `/u/`
      // case above does not cover: a mention is drawn as a pill, and a pill
      // claims the anchor — so it stops being an ordinary link and has to
      // carry the tap itself.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked:
                    '<p>ask <a class="mention" href="/u/joffreyj">'
                    '@joffreyj</a> about it</p>',
              ),
            ],
            stream: const [1],
          ),
        },
        cards: {
          'joffreyj': UserCard(
            username: 'joffreyj',
            name: 'Joffrey',
            createdAt: DateTime.utc(2015, 3, 4),
          ),
        },
      );

      final launched = await openPostLinking(tester, api);
      await tester.tapOnText(find.textRange.ofSubstring('@joffreyj'));
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(launched, isEmpty);
    });
  });

  group('replying', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
      instance(
        'team.discourse.org',
        title: 'Discourse Team',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() => FakeAuthenticator()
      ..keys['https://meta.discourse.org'] = 'meta-key'
      ..keys['https://team.discourse.org'] = 'team-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({bool canCreatePost = true}) => topicPayload(
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
      stream: const [1],
      postsCount: 1,
      canCreatePost: canCreatePost,
    );

    /// Opens the topic, which is where every reply starts.
    Future<void> openTopic(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
    }

    Finder sendButton() => find.widgetWithText(FilledButton, 'Reply');

    testWidgets('the reply affordances wait for permission to use them', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(canCreatePost: false)},
      );

      await openTopic(tester, api);

      // can_create_post is the whole question — the guardian behind it has
      // already accounted for closed, archived and who may post past them.
      expect(find.byTooltip('Reply to this topic'), findsNothing);
      await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('replying to a topic posts what was typed', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      // The topic is still readable underneath, which is the point of docking
      // it rather than opening a sheet.
      expect(renderedText('First post body'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Sounds good to me.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created, hasLength(1));
      expect(api.created.single['raw'], 'Sounds good to me.');
      expect(api.created.single['topicId'], 7);
      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
      expect(api.created.single['draftKey'], 'topic_7');
      // Replying to the topic addresses no particular post.
      expect(api.created.single['replyToPostNumber'], isNull);

      // Posted, so the composer is done and the reply is in the stream.
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('Sounds good to me.'), findsOneWidget);
    });

    testWidgets('replying to a post addresses it by post number', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await hoverPost(tester);
      await tester.tap(find.byTooltip('Reply to this post'));
      await tester.pumpAndSettle();

      expect(find.text('Reply to @sam'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Agreed.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['replyToPostNumber'], 1);
    });

    testWidgets('always reports how long the reply took to type', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quick one.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Absent means zero to Discourse, which silences the account on a first
      // post rather than merely queueing it.
      expect(api.created.single['typingDurationMsecs'], isNotNull);
      expect(api.created.single['composerOpenDurationMsecs'], isNotNull);
    });

    testWidgets('cmd-enter sends without reaching for the button', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Shipped.');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      expect(api.created.single['raw'], 'Shipped.');
    });

    testWidgets('a refused reply keeps the text and says why', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.validation,
          errors: ['Body is too short (minimum is 20 characters)'],
          statusCode: 422,
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'no');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(
        find.text('Body is too short (minimum is 20 characters)'),
        findsOneWidget,
      );
      // Losing what someone wrote because the server said no is the one
      // unforgivable thing a composer can do.
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('no'), findsOneWidget);
    });

    testWidgets('a queued reply is not shown as posted', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          message: 'Your post is in the queue.',
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Held for review.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Success, and nothing to put in the stream: the author would otherwise
      // see a reply nobody else can.
      expect(find.text('Your post is in the queue.'), findsOneWidget);
      expect(renderedText('Held for review.'), findsNothing);

      // It was accepted, so sending again would queue a second copy.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('undo does not hand a queued reply back', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          message: 'Your post is in the queue.',
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Held for review.');
      await tester.pumpAndSettle();
      // What gets recorded for undo is throttled. Without waiting that out
      // there is nothing on the stack, and this passes on a composer that
      // would hand the reply straight back.
      await tester.pump(const Duration(milliseconds: 600));

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Undo reaching back over the clear is the double post the clear is
      // there to prevent: the text returns, and the send button it returns
      // under works.
      expect(find.text('Held for review.'), findsNothing);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);
    });

    testWidgets('switching sites mid-reply does not post to the new one', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Meant for meta.');
      await tester.pumpAndSettle();

      // Switching sites hides the composer rather than discarding it, and it
      // stays bound to where it was opened. (The rail draws initials.)
      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.text('DM'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Meant for meta.'), findsOneWidget);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['siteUrl'], 'https://meta.discourse.org');
    });

    testWidgets('a rate limit holds sending back until the wait is up', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(
          WriteFailure.rateLimited,
          errors: ['You are posting too quickly.'],
          statusCode: 429,
          retryAfter: Duration(seconds: 2),
        ),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Too eager.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.text('You are posting too quickly.'), findsOneWidget);
      // Sending again during the wait only earns another refusal.
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('an unreachable site is checked rather than retried', (
      tester,
    ) async {
      // The post was created; only the answer was lost. Sending again would
      // publish it twice, since a user API key gets no idempotency.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(),
          // What the check finds when it re-reads the topic.
        },
        postsById: {
          2: const Post(
            id: 2,
            postNumber: 2,
            username: 'joffreyj',
            cooked: '<p>It landed.</p>',
            raw: 'It landed.',
          ),
        },
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'It landed.');
      await tester.pumpAndSettle();

      // The re-read shows the post that was made after all.
      api.topics[7] = topicPayload(
        id: 7,
        title: 'A real topic',
        posts: [detail().posts.first],
        stream: const [1, 2],
        postsCount: 2,
        canCreatePost: true,
      );

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Only ever one create, whatever happened to its answer.
      expect(api.created, hasLength(1));
      // The tail was read with the markdown, so the match is exact rather
      // than a guess at what the server made of it.
      expect(api.postFetches.last, contains(2));
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('It landed.'), findsOneWidget);
    });

    testWidgets('a check that finds nothing lets the reply be sent again', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Never arrived.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Nothing in the topic matches it, so it really did not post.
      expect(find.text("Couldn't reach the site."), findsOneWidget);
      expect(find.text('Never arrived.'), findsOneWidget);
      expect(tester.widget<FilledButton>(sendButton()).onPressed, isNotNull);
    });

    testWidgets('a check that cannot be made holds sending back', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        writeFailure: const WriteException(WriteFailure.unreachable),
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Unknown fate.');
      await tester.pumpAndSettle();

      // The site is unreachable for the check too.
      api.topics.remove(7);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      // Whether it posted is unknown, and guessing wrong means posting twice.
      expect(find.textContaining('may have posted'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Check again');
      expect(button, findsOneWidget);
      expect(find.text('Unknown fate.'), findsOneWidget);

      // Checking again is the way out, and it does not send anything.
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.created, hasLength(1));
    });

    testWidgets('a post keeps its actions out of the way until hovered', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      // A long topic should not read as a column of buttons.
      expect(find.byTooltip('Reply to this post'), findsNothing);

      final gesture = await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Leaving takes them away on the very next frame — no grace period to
      // wait out, which reads as lag.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('the menu follows its post, and stays in the viewport', (
      tester,
    ) async {
      // One post far taller than the window, which is the case that put the
      // menu above the fold when it was pinned to the post's top edge.
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Top of the long post</p>${'<p>filler</p>' * 120}',
              ),
            ],
            stream: const [1],
            postsCount: 1,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      await hoverPost(tester, body: 'Top of the long post');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final before = tester.getTopLeft(find.byTooltip('Reply to this post'));
      final viewport = tester.getRect(find.byType(TopicView));
      expect(before.dy, greaterThanOrEqualTo(viewport.top));

      await tester.drag(find.byType(TopicView), const Offset(0, -400));
      await tester.pumpAndSettle();

      // Still there, and still inside the topic rather than over the header.
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
      final after = tester.getTopLeft(find.byTooltip('Reply to this post'));
      expect(after.dy, greaterThanOrEqualTo(viewport.top));
      expect(after.dy, lessThan(viewport.bottom));
    });

    testWidgets('the menu goes when its post scrolls out of sight', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              for (var i = 1; i <= 20; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'sam',
                  cooked: '<p>Post body $i</p>',
                ),
            ],
            stream: [for (var i = 1; i <= 20; i++) i],
            postsCount: 20,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final gesture = await hoverPost(tester, body: 'Post body 5');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Park the pointer outside the list so no other post picks the menu up,
      // then scroll post 5 away.
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await tester.drag(find.byType(TopicView), const Offset(0, -600));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('on a touch screen the actions arrive as a sheet', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.longPress(renderedText('First post body'));
      await tester.pumpAndSettle();

      // There is no pointer to hover with, so the same action is reached by
      // holding the post.
      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);

      await tester.tap(find.widgetWithText(ListTile, 'Reply'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Reply to @sam'), findsOneWidget);
    });

    testWidgets('closing the composer sends nothing', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.created, isEmpty);
    });
  });

  group('editing and deleting', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    Post mine({
      bool canEdit = true,
      bool canDelete = true,
      bool canRecover = false,
      DateTime? deletedAt,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'joffreyj',
      cooked: '<p>First post body</p>',
      canEdit: canEdit,
      canDelete: canDelete,
      canRecover: canRecover,
      deletedAt: deletedAt,
    );

    TopicPayload detail(Post post) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [post],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required Post post,
      Map<int, Post> postsById = const {},
      WriteException? writeFailure,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(post)},
        postsById: postsById,
        writeFailure: writeFailure,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('a post nobody may touch offers nothing but a reply', (
      tester,
    ) async {
      await openTopic(tester, post: mine(canEdit: false, canDelete: false));

      await hoverPost(tester);

      // can_edit and can_delete are the whole question: the guardian behind
      // them has already weighed ownership, staff, the edit window and the
      // state of the topic.
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
      expect(find.byTooltip('Edit this post'), findsNothing);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('editing a post sends the markdown, not the HTML', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(),
        // The stream carries cooked HTML, so the raw has to be fetched before
        // there is anything to edit.
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            raw: 'First **post** body',
          ),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      expect(find.text('Edit post #1'), findsOneWidget);
      expect(find.text('First **post** body'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'First **post** body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(api.updated.single['postId'], 1);
      expect(api.updated.single['raw'], 'First **post** body!');
      // Sent, so the composer goes and the rewritten post is what is drawn.
      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('First **post** body!'), findsOneWidget);
    });

    testWidgets('an edit nobody has changed cannot be saved', (tester) async {
      await openTopic(
        tester,
        post: mine(),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            raw: 'First post body',
          ),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      // Not a rule of ours — the site refuses an unchanged edit — but there is
      // no reason to spend a request finding that out.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('an edit never saves over a post it could not read', (
      tester,
    ) async {
      // No raw to be had: the fetch answers with nothing for this id.
      await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      // The field is empty, and saving that would blank the post rather than
      // leave it alone — so there is nothing to press.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('deleting re-reads what it did, and offers the undo', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(),
        // Staff get a soft delete: the post is still there, and still theirs
        // to put back.
        postsById: {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            canRecover: true,
            deletedAt: DateTime(2026),
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Delete this post'));
      await tester.pumpAndSettle();

      // Nothing to confirm: the undo is the next thing in the same menu.
      expect(api.deleted, [1]);
      // Shown as deleted rather than taken away, because the person who can
      // undo it is the person looking at it.
      expect(find.text('deleted'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Put this post back'), findsOneWidget);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('a post that is really gone stops being drawn', (tester) async {
      // Nothing comes back for the id, which is the site saying it is no
      // longer there — or no longer ours to see.
      final api = await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Delete this post'));
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(renderedText('First post body'), findsNothing);
    });

    testWidgets('recovering puts the post back', (tester) async {
      final api = await openTopic(
        tester,
        post: mine(
          canDelete: false,
          canRecover: true,
          deletedAt: DateTime(2026),
        ),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            canDelete: true,
          ),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Put this post back'));
      await tester.pumpAndSettle();

      expect(api.recovered, [1]);
      expect(find.text('deleted'), findsNothing);
    });

    testWidgets('a refused delete says why and leaves the post alone', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(),
        writeFailure: const WriteException(WriteFailure.forbidden),
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Delete this post'));
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.textContaining("You can't post that here"), findsOneWidget);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('on a touch screen the same actions arrive as a sheet', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await tester.longPress(renderedText('First post body'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Delete'), findsOneWidget);
    });
  });

  group('optional site features', () {
    const site = 'https://meta.discourse.org';

    final reactionsOn = SiteConfig.fromSettings(const {
      'emoji_set': 'apple',
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    });

    ShellController controllerWith(
      WidgetTester tester,
      FakeDiscourseApi api, {
      FakeInstanceStore? store,
    }) {
      final controller = ShellController(
        instanceStore:
            store ?? FakeInstanceStore([instance('meta.discourse.org')]),
        api: api,
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updateStore: FakeUpdateStore(),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    FakeDiscourseApi serving({Map<String, SiteConfig> configs = const {}}) =>
        FakeDiscourseApi(
          feeds: {'/latest.json': const []},
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
              stream: const [1],
            ),
          },
          siteConfigs: configs,
        );

    testWidgets('what a site has is asked for when a topic is opened', (
      tester,
    ) async {
      // Not at launch: a site whose topics are never read is never asked, and
      // nothing before a topic needs the answer.
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(tester, api);
      await controller.load();

      expect(api.siteConfigsRequested, isEmpty);

      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
      expect(controller.siteConfigFor(site).emojiSet, 'apple');
      expect(controller.siteConfigFor(site).mainReaction, 'heart');
    });

    testWidgets('a site is only asked once', (tester) async {
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(tester, api);
      await controller.load();

      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();
      await controller.loadTopic(7, 'a-real-topic', force: true);
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
    });

    testWidgets('the answer is remembered between launches', (tester) async {
      // It decides rendering, so a site drawing google emoji must not draw
      // twitter's through the first topic of every launch.
      final store = FakeInstanceStore([instance('meta.discourse.org')]);
      final controller = controllerWith(
        tester,
        serving(configs: {site: reactionsOn}),
        store: store,
      );
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      final stored = await store.load();
      expect(stored.single.config, reactionsOn);
    });

    testWidgets('a stored answer stands until this session has its own', (
      tester,
    ) async {
      final controller = controllerWith(
        tester,
        // This site will refuse, so nothing but the stored copy is available.
        serving(),
        store: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(config: reactionsOn),
        ]),
      );
      await controller.load();

      expect(controller.siteConfigFor(site).emojiSet, 'apple');
    });

    testWidgets('a site that will not answer is drawn as plain core', (
      tester,
    ) async {
      final controller = controllerWith(tester, serving());
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      // No loading state and no error state: every field is core's default, so
      // there is nothing here worth telling a reader about.
      expect(controller.siteConfigFor(site), const SiteConfig.unknown());
    });

    testWidgets('a site that will not answer is given up on, not hammered', (
      tester,
    ) async {
      // Deliberately unlike the categories fetch, which marks a site done
      // before it has asked and so gets one attempt per session with no way
      // back. A few tries, then left alone.
      final api = serving();
      final controller = controllerWith(tester, api);
      await controller.load();

      for (var i = 0; i < 6; i++) {
        await controller.loadTopic(7, 'a-real-topic', force: true);
        await tester.pump();
      }

      expect(api.siteConfigsRequested, hasLength(3));
    });

    testWidgets('signing out forgets what the site said', (tester) async {
      // On a login_required site the settings were only readable as that
      // account, so keeping an answer that can no longer be refreshed would
      // leave the shell drawing something it cannot correct.
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(
        tester,
        api,
        store: FakeInstanceStore([
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(username: 'joffreyj')),
        ]),
      );
      await controller.load();
      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();
      expect(controller.siteConfigFor(site), reactionsOn);

      await controller.disconnectCurrentInstance();

      expect(controller.siteConfigFor(site), const SiteConfig.unknown());
    });

    testWidgets('a post no feature claims keeps the core footer', (
      tester,
    ) async {
      // The load-bearing default. Every plugin is opt-in from the payload, so
      // a site running plain core draws exactly what it drew before any of this
      // existed.
      await pumpShell(
        tester,
        desktop,
        api: FakeDiscourseApi(
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
                  likeCount: 2,
                ),
              ],
              stream: const [1],
            ),
          },
        ),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byType(PostFooter), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PostFooter),
          matching: find.byType(PostLikes),
        ),
        findsOneWidget,
      );
    });
  });

  group('likes', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    /// A post in whichever of the four states a like can leave it in.
    Post post({
      int likeCount = 0,
      bool liked = false,
      bool canLike = true,
      bool canUnlike = false,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'sam',
      cooked: '<p>First post body</p>',
      likeCount: likeCount,
      liked: liked,
      canLike: canLike,
      canUnlike: canUnlike,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required Post first,
      Map<int, List<PostLiker>> likersById = const {},
      Map<int, Post> likeResponses = const {},
      Map<int, Post> postsById = const {},
      WriteException? likeFailure,
      Completer<void>? likerGate,
      Completer<void>? likeGate,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [first],
            stream: const [1],
            postsCount: 1,
          ),
        },
        postsById: postsById,
        likersById: likersById,
        likeResponses: likeResponses,
        likeFailure: likeFailure,
        likerGate: likerGate,
        likeGate: likeGate,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    /// The count under the post, which is also what opens the list of names.
    Finder count(String value) =>
        find.descendant(of: find.byType(PostLikes), matching: find.text(value));

    testWidgets('a post nobody has liked says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, first: post());

      // No count: an empty one would be a row of zeroes down a topic nobody
      // has got round to reading yet.
      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('0'), findsNothing);

      // The heart is in the menu instead, which is out of the way until the
      // post is pointed at.
      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsOneWidget);
    });

    testWidgets(
      'liking from the menu draws the count before the site answers',
      (tester) async {
        final api = await openTopic(tester, first: post());

        await hoverPost(tester);
        await tester.tap(find.byTooltip('Like this post'));
        await tester.pumpAndSettle();

        expect(api.liked, [1]);
        expect(count('1'), findsOneWidget);
      },
    );

    testWidgets('a like of your own is the heart that takes it back', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await hoverPost(tester);

      expect(find.byTooltip('Remove your like'), findsOneWidget);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('a like past the undo window leaves nothing to press', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false),
      );

      await hoverPost(tester);

      // The count still says it was liked, and by whom — the button would
      // only be one that refuses.
      expect(count('1'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('the site has the last word on the count', (tester) async {
      // Two other people liked it while this reader was reading, which is
      // what the post the route answers with is for.
      await openTopic(
        tester,
        first: post(),
        likeResponses: {
          1: post(likeCount: 3, liked: true, canLike: false, canUnlike: true),
        },
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(count('3'), findsOneWidget);
    });

    testWidgets('tapping a like of your own takes it back', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1, liked: true, canLike: false, canUnlike: true),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.unliked, [1]);
      expect(api.liked, isEmpty);
      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('1'), findsNothing);
    });

    testWidgets('tapping somebody else\'s adds yours to it', (tester) async {
      final api = await openTopic(tester, first: post(likeCount: 1));

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('a refused like says why and puts the count back', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      await tester.tap(count('1'));
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('1'), findsOneWidget);
      expect(count('2'), findsNothing);
    });

    testWidgets('a post you may not like still shows what others thought', (
      tester,
    ) async {
      // Your own post: the site reports the count and no way to act on it.
      final api = await openTopic(
        tester,
        first: post(likeCount: 2, canLike: false),
      );

      expect(count('2'), findsOneWidget);

      await hoverPost(tester);
      expect(find.byTooltip('Like this post'), findsNothing);

      await tester.tap(count('2'));
      await tester.pumpAndSettle();
      expect(api.liked, isEmpty);
    });

    testWidgets('resting on the count says who liked it', (tester) async {
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      // Crossing the count on the way somewhere else must not open it, or
      // spend a request finding out who liked a post nobody asked about.
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.likersRequested, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(api.likersRequested, [1]);
      expect(find.text('Sam Saffron'), findsOneWidget);
      // No name on the account, so the username is the name.
      expect(find.text('codinghorror'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('and says so when it cannot find out', (tester) async {
      await openTopic(tester, first: post(likeCount: 2));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(count('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
    });

    testWidgets('on a touch screen the names arrive as a sheet', (
      tester,
    ) async {
      await openTopic(
        tester,
        first: post(likeCount: 1),
        likersById: {
          1: const [PostLiker(id: 3, username: 'sam', name: 'Sam Saffron')],
        },
      );

      // The post underneath opens its own sheet on a long press; the count is
      // the nearer of the two and wins.
      await tester.longPress(count('1'));
      await tester.pumpAndSettle();

      expect(find.text('1 like'), findsOneWidget);
      expect(find.text('Sam Saffron'), findsOneWidget);
    });

    testWidgets('liking with the panel open leaves it saying something true', (
      tester,
    ) async {
      // Refused, which is the case that used to strand the panel: the names
      // were thrown away when the like was made and nothing put them back.
      final api = await openTopic(
        tester,
        first: post(likeCount: 2),
        likersById: {
          1: const [
            PostLiker(id: 3, username: 'sam', name: 'Sam Saffron'),
            PostLiker(id: 4, username: 'codinghorror'),
          ],
        },
        likeFailure: const WriteException(WriteFailure.rateLimited),
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final pill = tester.getCenter(count('2'));
      await gesture.moveTo(pill);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsOneWidget);

      // Pressed without the pointer ever leaving the pill, so the panel is
      // still open when the refusal comes back.
      await gesture.down(pill);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('2'), findsOneWidget);
      // Names, not a spinner, and asked for again rather than assumed.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(api.likersRequested, [1, 1]);
    });

    testWidgets('a double tap does not send two contradicting writes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        first: post(likeCount: 1),
        likeGate: gate,
      );

      // Twice, before the first has come back. The second reads the guess the
      // first wrote, so unguarded it would send an undo of a like the site has
      // not recorded yet — and whichever answer landed last would win.
      await tester.tap(count('1'));
      await tester.pump();
      await tester.tap(count('2'));
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(api.liked, [1]);
      expect(api.unliked, isEmpty);
      expect(count('2'), findsOneWidget);
    });

    testWidgets('editing a post you liked leaves the like alone', (
      tester,
    ) async {
      // `PostsController#update` serializes without the reader's own post
      // actions, so the edit comes back claiming the post is unliked and
      // likeable — on a post they have in fact already liked.
      final api = await openTopic(
        tester,
        first: Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
          canEdit: true,
          likeCount: 3,
          liked: true,
          canUnlike: true,
        ),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First post body</p>',
            canEdit: true,
            raw: 'First post body',
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
      // The heart survived the typo fix.
      expect(count('3'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('First post body!')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your like'), findsOneWidget);
    });
  });

  group('reactions', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');
    const site = 'https://meta.discourse.org';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    final configured = SiteConfig.fromSettings(const {
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    });

    /// A post as a reactions site serializes one. Built through [Post.fromJson]
    /// rather than the constructor deliberately: there is no way to hand a post
    /// a reactions block except by the site having sent one, which is what
    /// makes the plugin-less default hold.
    Post post({
      int id = 1,
      List<({String id, int count})> reactions = const [],
      String? mine,
      int userCount = 0,
      bool canAct = true,
      bool canUndo = false,
      bool plugin = true,
      bool canEdit = false,
    }) => Post.fromJson({
      'id': id,
      'post_number': id,
      'username': 'sam',
      // The first post keeps the body every other group uses, so `hoverPost`
      // finds it the same way.
      'cooked': id == 1 ? '<p>First post body</p>' : '<p>Post $id body</p>',
      if (canEdit) 'can_edit': true,
      'actions_summary': [
        {
          'id': 2,
          if (canAct) 'can_act': true,
          if (canUndo) 'can_undo': true,
          if (mine != null) 'acted': true,
        },
      ],
      if (plugin) ...{
        'reactions': [
          for (final r in reactions)
            {'id': r.id, 'type': 'emoji', 'count': r.count},
        ],
        'current_user_reaction': ?(mine == null
            ? null
            : {'id': mine, 'type': 'emoji', 'can_undo': true}),
        'reaction_users_count': userCount,
      },
    }, site);

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required List<Post> posts,
      SiteConfig? config,
      Map<String, String> customEmojis = const {},
      Map<String, PostReactors> reactorsById = const {},
      Map<int, Post> postsById = const {},
      Map<int, Post> reactionResponses = const {},
      WriteException? reactionFailure,
      Completer<void>? reactionGate,
    }) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: posts,
            stream: [for (final p in posts) p.id],
            postsCount: posts.length,
          ),
        },
        siteConfigs: config == null ? const {} : {site: config},
        customEmojisBySite: customEmojis.isEmpty
            ? const {}
            : {site: customEmojis},
        postsById: postsById,
        reactorsById: reactorsById,
        reactionResponses: reactionResponses,
        reactionFailure: reactionFailure,
        reactionGate: reactionGate,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      return api;
    }

    /// A pill in the row, by its count.
    Finder pill(String value) => find.descendant(
      of: find.byType(ReactionsRow),
      matching: find.text(value),
    );

    testWidgets('a site with reactions draws them where the likes were', (
      tester,
    ) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'heart', count: 5), (id: 'clap', count: 2)],
            userCount: 7,
          ),
        ],
      );

      expect(find.byType(ReactionsRow), findsOneWidget);
      // Not both: the like count on a reactions site is inflated by the shadow
      // likes reacting leaves behind, so drawing it would say 7 hearts.
      expect(find.byType(PostLikes), findsNothing);
      expect(pill('5'), findsOneWidget);
      expect(pill('2'), findsOneWidget);
      // And no grand total beside them — it is not their sum and can exceed it.
      expect(pill('7'), findsNothing);
    });

    testWidgets('a post nobody has reacted to says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, config: configured, posts: [post()]);

      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('0'), findsNothing);
    });

    testWidgets('a post on a site without the plugin keeps its likes', (
      tester,
    ) async {
      // The load-bearing default: absence of the key, not absence of a setting.
      await openTopic(tester, posts: [post(plugin: false)]);

      expect(find.byType(PostLikes), findsOneWidget);
      expect(find.byType(ReactionsRow), findsNothing);
    });

    testWidgets('a custom emoji is drawn from its upload, not the set', (
      tester,
    ) async {
      // Custom emoji are uploads: they 404 at the set's address, which is
      // what used to leave the pill drawing its name as text. The site's own
      // map is what knows where they live.
      const upload = 'https://meta.discourse.org/uploads/default/party.png';
      await openTopic(
        tester,
        config: configured,
        customEmojis: const {'party_blob': upload},
        posts: [
          post(reactions: [(id: 'party_blob', count: 1)], userCount: 1),
        ],
      );

      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is EmojiImage && widget.url == upload,
        ),
        findsOneWidget,
      );
      // And nothing asks the set for it — that request would 404.
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is EmojiImage && widget.url.contains('/images/emoji/'),
        ),
        findsNothing,
      );
    });

    testWidgets('the menu offers a reaction and never a like', (tester) async {
      // Offering Like here would write /post_actions, which on a post the
      // reader reacted to destroys the shadow like and orphans the reaction.
      await openTopic(tester, config: configured, posts: [post()]);
      await hoverPost(tester);

      expect(find.byTooltip('Like this post'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
    });

    testWidgets('the menu names the reaction the reader actually gave', (
      tester,
    ) async {
      // A reader who clapped has a shadow like, so `can_act` is true and the
      // naive label would read "Like this post" — on a tap that replaces their
      // clap.
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
          ),
        ],
      );
      await hoverPost(tester);

      expect(find.byTooltip('Remove your clap reaction'), findsOneWidget);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('reacting draws the row before the site answers', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pump();

      // Drawn while the request is still in flight.
      expect(api.reacted, [(postId: 1, reaction: 'heart')]);
      expect(pill('1'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a refused reaction says why and puts the row back', (
      tester,
    ) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 2)], userCount: 2),
        ],
        reactionFailure: const WriteException(
          WriteFailure.rateLimited,
          statusCode: 429,
        ),
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(pill('2'), findsOneWidget);
      expect(find.textContaining('Too fast'), findsOneWidget);
    });

    testWidgets('a reaction the site no longer has drops that row alone', (
      tester,
    ) async {
      // A 404 means the plugin went away *or* the post did, and the route
      // answers the same bytes for both. Emptying every footer in the topic
      // because a moderator deleted one post would be the wrong guess.
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 1)], userCount: 1),
          post(id: 2, reactions: [(id: 'clap', count: 3)], userCount: 3),
        ],
        reactionFailure: const WriteException(
          WriteFailure.validation,
          statusCode: 404,
        ),
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      // The neighbour keeps its row until the topic is read again.
      expect(pill('3'), findsOneWidget);
      expect(pill('1'), findsNothing);
    });

    testWidgets('a double tap does not send two contradicting writes', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      // Tapped by position, because the first tap relabels the entry the
      // instant it is pressed — the row is drawn before the site answers.
      final target = tester.getCenter(find.byTooltip('Like this post'));
      await tester.tapAt(target);
      await tester.pump();
      await tester.tapAt(target);
      await tester.pump();

      expect(api.reacted, hasLength(1));
      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('a site that has not said which reaction is a like is asked', (
      tester,
    ) async {
      // `heart` is not in the default enabled list, and the setting is enum
      // constrained — so a guess earns a 422 saying only "Sorry, an error has
      // occurred". The picker is the honest answer instead.
      final api = await openTopic(tester, posts: [post()]);
      await hoverPost(tester);

      expect(find.byTooltip('React to this post'), findsOneWidget);
      await tester.tap(find.byTooltip('React to this post'));
      await tester.pumpAndSettle();

      expect(api.reacted, isEmpty);
      expect(
        find.textContaining('which reactions this site allows'),
        findsOneWidget,
      );
    });

    testWidgets('the picker offers what the site allows', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
          ),
        ],
        reactorsById: const {},
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Remove your clap reaction'));
      await tester.pumpAndSettle();

      // Taking one back is one tap; the picker is not involved.
      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
    });

    testWidgets('a reaction can be picked from the grid', (tester) async {
      // The main reaction is not the only one a site allows, and the menu's
      // toggle can only give it or take back what is held — the grid is where
      // the rest are chosen.
      final api = await openTopic(tester, config: configured, posts: [post()]);

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Pick a reaction'));
      await tester.pumpAndSettle();

      // The site's list, main reaction first: heart, +1, clap.
      final cells = find.descendant(
        of: find.byType(ReactionGrid),
        matching: find.byType(InkWell),
      );
      expect(cells, findsNWidgets(3));

      await tester.tap(cells.at(1));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: '+1')]);
      expect(pill('1'), findsOneWidget);
    });

    testWidgets('the write answer updates the reader and not the counts', (
      tester,
    ) async {
      // The plugin builds `reactions` one way for a read and another for a
      // write, and the write's copy drops reactions whose emoji no longer
      // exists — so its counts are not the row's. Only what the answer says
      // about this reader is taken.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'heart', count: 2)], userCount: 2),
        ],
        reactionResponses: {
          1: post(
            reactions: [(id: 'heart', count: 9)],
            mine: 'heart',
            userCount: 9,
            canUndo: true,
            canAct: false,
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'heart')]);
      // The pill keeps the count it was drawn with — the optimistic one — and
      // never shows the nine the write's answer carries.
      expect(pill('3'), findsOneWidget);
      expect(pill('9'), findsNothing);

      // What the answer says about the reader stands: the menu names the
      // reaction they now hold.
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your heart reaction'), findsOneWidget);
    });

    testWidgets('editing a post you reacted to leaves the reaction alone', (
      tester,
    ) async {
      // The edit answer is serialized without the reader's post actions, and
      // for the plugin that means the reaction itself: taken literally it
      // would swap the footer back to the like one — whose heart writes
      // through a route that destroys the reaction.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canUndo: true,
            canAct: false,
            canEdit: true,
          ),
        ],
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'sam',
            cooked: '<p>First post body</p>',
            canEdit: true,
            raw: 'First post body',
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tester.tap(find.byTooltip('Edit this post'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
      // The reaction survived the typo fix: the row, its count, and what the
      // menu names.
      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('1'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('First post body!')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Remove your clap reaction'), findsOneWidget);
    });

    testWidgets('resting on a pill says who gave that one', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
        reactorsById: {
          '1:clap': const PostReactors(
            postId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'codinghorror', reaction: 'clap'),
            ],
          ),
        },
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(pill('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // Narrowed to the emoji that was pointed at, not the whole post.
      expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
      final named = find.descendant(
        of: find.byType(ReactorList),
        matching: find.text('sam'),
      );
      expect(named, findsOneWidget);
      expect(find.text('codinghorror'), findsOneWidget);
    });

    testWidgets('somebody else reacting arrives without a refresh', (
      tester,
    ) async {
      // The channel carries which emoji changed and no counts at all, so it is
      // an invalidation hint — the post is read again through the route whose
      // numbers agree with what the row was drawn from.
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
        postsById: {
          1: post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        },
      );

      final tracker = FakeSiteTracker.built.last;
      expect(tracker.watchedTopic, 7);
      expect(tracker.watchedChannels, ['/topic/7/reactions', '/polls/7']);

      tracker.deliverTopicMessage('/topic/7/reactions', {
        'post_id': 1,
        'reactions': ['clap', null],
      });
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [1],
      ]);
      expect(pill('2'), findsOneWidget);
    });

    testWidgets('leaving the topic stops listening to it', (tester) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
      );
      expect(FakeSiteTracker.built.last.watchedTopic, 7);

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.last.watchedTopic, isNull);
    });

    testWidgets('a write of this reader own is not read back over', (
      tester,
    ) async {
      // The echo of their own reaction arrives while their request is still in
      // flight. Reading the post again would land the site's answer on top of
      // a guess the site has not seen yet.
      final gate = Completer<void>();
      final api = await openTopic(
        tester,
        config: configured,
        posts: [post()],
        reactionGate: gate,
      );

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Like this post'));
      await tester.pump();

      FakeSiteTracker.built.last.deliverTopicMessage('/topic/7/reactions', {
        'post_id': 1,
        'reactions': ['heart', null],
      });
      await tester.pump();

      expect(api.postFetches, isEmpty);

      gate.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('and says so when it cannot find out', (tester) async {
      await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(pill('2')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.textContaining('who reacted'), findsOneWidget);
    });
  });

  group('composer toolbar', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail() => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    Future<void> openComposer(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    testWidgets('never turns spell check on', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);

      // `EditableText` routes around `controller.buildTextSpan` entirely once
      // spell check results arrive (editable_text.dart:5984), so a
      // spell-checked composer is one with no markdown highlighting — and it
      // would fail by flickering rather than by breaking. This is the tripwire.
      expect(
        tester
            .widget<TextField>(find.byType(TextField))
            .spellCheckConfiguration,
        isNull,
      );
    });

    testWidgets('marks up the markdown around the selection', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'say hello');
      await tester.pumpAndSettle();

      // Select "hello".
      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.bold));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say **hello**');

      // The selection stayed on the word, so italic composes onto it.
      await tester.tap(find.dIcon(DIcons.italic));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say ***hello***');
    });
  });

  group('composer autocomplete', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail() => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: const [
        Post(
          id: 1,
          postNumber: 1,
          username: 'sam',
          cooked: '<p>First post body</p>',
        ),
      ],
      stream: const [1],
      postsCount: 1,
      canCreatePost: true,
    );

    FakeDiscourseApi api() => FakeDiscourseApi(
      feeds: {'/latest.json': listed},
      topics: {7: detail()},
      userSearches: {
        'sa': const [
          FoundUser(username: 'sam', name: 'Sam Saffron'),
          FoundUser(username: 'sally'),
        ],
      },
      hashtagSearches: {
        'ran': const [
          FoundHashtag(
            type: 'category',
            ref: 'random',
            slug: 'random',
            text: 'Random',
            id: 5,
            colors: ['0088CC'],
          ),
          FoundHashtag(
            type: 'tag',
            ref: 'random::tag',
            slug: 'random',
            text: 'random',
            id: 12,
            styleType: 'icon',
            icon: 'tag',
            secondaryText: 'x0',
          ),
        ],
      },
      emojisBySite: {
        'https://meta.discourse.org': const [
          SiteEmoji(name: 'smile', url: 'https://meta.discourse.org/s.png'),
          SiteEmoji(name: 'smirk', url: 'https://meta.discourse.org/k.png'),
        ],
      },
    );

    Future<void> openComposer(WidgetTester tester, FakeDiscourseApi api) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    TextField field(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField));

    testWidgets('offers people once enough has been typed', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      // Asserted on the real name and the second username, both of which are
      // unique — `sam` also wrote the post being replied to.
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(find.text('sally'), findsOneWidget);
      // The topic is part of the question: Discourse ranks people already in
      // it first, which is what puts the person being replied to at the top.
      expect(fake.userSearchesRequested.single.topicId, 7);
    });

    testWidgets('writes the whole mention when one is picked', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sam ');
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('arrowing down picks the second name', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sally ');
    });

    testWidgets('escape closes the list, not the reply', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(find.text('Sam Saffron'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // The list is gone and the half-written reply is still there. Getting
      // this wrong throws away what somebody was writing, which is why the
      // popup handles keys through a plain Focus rather than a second
      // CallbackShortcuts — that one reports a key handled whenever an
      // activator matches, open or not.
      expect(find.text('Sam Saffron'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(field(tester).controller!.text, 'hey @sa');

      // And the second one still closes the composer.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('cmd+enter still sends with the list open', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pump();
      expect(find.text('Sam Saffron'), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.meta);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.meta);
      await tester.pumpAndSettle();

      // An open list does not get to decide when a reply is posted.
      expect(fake.created.single['raw'], 'hey @sa');
    });

    testWidgets('offers emoji without asking the site again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'a :sm');
      await tester.pumpAndSettle();

      expect(find.text('smile'), findsOneWidget);
      expect(find.text('smirk'), findsOneWidget);
      // Fetched once when the composer opened, not per keystroke.
      expect(fake.emojisRequested, ['https://meta.discourse.org']);
    });

    testWidgets('offers categories and tags once # is typed', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();

      expect(fake.hashtagSearchesRequested, ['ran']);
      // The site's own name for each, so a subcategory reads as one.
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('random'), findsOneWidget);
      // A tag says how many topics carry it; a category does not.
      expect(find.text('x0'), findsOneWidget);
    });

    testWidgets('writes the ref, not the slug, when one is picked', (
      tester,
    ) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();

      // The tag, whose slug collides with the category's — which is the whole
      // reason the site sends a `ref` at all.
      await tester.tap(find.text('random'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'see #random::tag ');
    });

    testWidgets('a picked hashtag pills without asking again', (tester) async {
      // The site already said what `random` is when it offered it, so
      // accepting it is not a reason to ask a second time. This is the path
      // almost every hashtag in a post takes.
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Random'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'see #random ');
      expect(find.byType(HashtagPill), findsOneWidget);
      expect(fake.hashtagLookupsRequested, isEmpty);
    });

    testWidgets('a picked mention pills without asking again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sa');
      await tester.pumpAndSettle();
      // By the real name, which only the suggestion row carries — the post
      // under the composer is by `sam` too.
      await tester.tap(find.text('Sam Saffron'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sam ');
      expect(find.byType(MentionPill), findsOneWidget);
      expect(fake.mentionChecksRequested, isEmpty);
    });

    testWidgets('a hand-typed name is checked once, then pills', (
      tester,
    ) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        realUsernames: const {'sam'},
      );
      await openComposer(tester, fake);

      // Typed out rather than picked, so nothing has vouched for it yet.
      await tester.enterText(find.byType(TextField), 'ask @sam now');
      await tester.pumpAndSettle();

      expect(fake.mentionChecksRequested, [
        {'sam'},
      ]);
      expect(find.byType(MentionPill), findsOneWidget);
    });

    testWidgets('a hand-typed name nobody has stays text', (tester) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'ask @nobody now');
      await tester.pumpAndSettle();

      expect(fake.mentionChecksRequested, [
        {'nobody'},
      ]);
      expect(find.byType(MentionPill), findsNothing);
    });

    testWidgets('says nothing about a hash inside a word', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'issue a#ran');
      await tester.pumpAndSettle();

      expect(fake.hashtagSearchesRequested, isEmpty);
    });

    testWidgets('writes the shortcode when an emoji is picked', (tester) async {
      await openComposer(tester, api());

      await tester.enterText(find.byType(TextField), 'a :sm');
      await tester.pumpAndSettle();

      await tester.tap(find.text('smirk'));
      await tester.pumpAndSettle();

      // Still markdown. The picture, when there is one, is a drawing of this.
      expect(field(tester).controller!.text, 'a :smirk: ');
    });

    testWidgets('draws the artwork for a shortcode that was written', (
      tester,
    ) async {
      // Through the real reply composer rather than the controller alone.
      // `resolveEmoji` is injected per composer, and it was once wired to the
      // edit composer and not this one — which the controller's own tests
      // could not see, because they pass the resolver themselves.
      await openComposer(tester, api());

      // `pumpShell` answers 404 for every emoji, which is right for the tests
      // that are about cooked HTML and wrong for this one. Swapped after the
      // shell is up so only this composer sees artwork.
      EmojiCache.instance = EmojiCache(
        client: MockClient((_) async => http.Response.bytes(emojiPng, 200)),
      );
      addTearDown(EmojiCache.instance.clear);

      await tester.enterText(find.byType(TextField), 'hey :smile:');
      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsOneWidget);
      // And the shortcode is still every character of what will be posted.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'hey :smile:',
      );
    });

    testWidgets('says nothing about an email address', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'write to sam@example');
      await tester.pump(ComposerAutocomplete.debounce);
      await tester.pumpAndSettle();

      expect(fake.userSearchesRequested, isEmpty);
    });
  });

  group('drafts', () {
    const me = DiscourseUser(username: 'joffreyj', name: 'Joffrey');

    List<DiscourseInstance> connectedSites() => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'meta-key';

    final listed = [
      const Topic(id: 7, title: 'A real topic', slug: 'a-real-topic'),
    ];

    TopicPayload detail({ComposerDraft? draft, int draftSequence = 0}) =>
        topicPayload(
          id: 7,
          title: 'A real topic',
          posts: const [
            Post(
              id: 1,
              postNumber: 1,
              username: 'sam',
              cooked: '<p>First post body</p>',
            ),
          ],
          stream: const [1],
          postsCount: 1,
          canCreatePost: true,
          draft: draft,
          draftSequence: draftSequence,
        );

    Future<void> openComposer(
      WidgetTester tester,
      FakeDiscourseApi api, {
      FakeDraftStore? drafts,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
        drafts: drafts,
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    /// Lets the debounce elapse so the save actually goes out.
    Future<void> settleDraft(WidgetTester tester) async {
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
    }

    testWidgets('typing is saved to the site after a pause', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Half a thought');
      await tester.pumpAndSettle();

      // Not per keystroke.
      expect(api.draftsSaved, isEmpty);

      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['draftKey'], 'topic_7');
      // Sequenced against what the topic payload came with.
      expect(api.draftsSaved.single['sequence'], 4);
      expect(api.draftsSaved.single['data'], contains('Half a thought'));
    });

    testWidgets('a new draft after a queued reply uses its returned sequence', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        creation: const PostCreation(
          outcome: PostOutcome.enqueued,
          draftSequence: 9,
        ),
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Held for review');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
      await tester.pumpAndSettle();
      api.draftsSaved.clear();

      await tester.enterText(find.byType(TextField), 'A different reply');
      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['sequence'], 9);
      expect(api.draftsSaved.single['data'], contains('A different reply'));
    });

    testWidgets('a slow save cannot clear a newer draft', (tester) async {
      final gate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: gate,
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'First revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Latest revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      expect(api.draftsSaved, hasLength(1));

      gate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Latest revision'));
      expect(drafts.events.where((event) => event == 'clear'), hasLength(1));
      expect(drafts.events.last, 'clear');
    });

    testWidgets('a draft is put back when the composer is reopened', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Come back to this');
      await settleDraft(tester);

      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      // Closing is how you get the topic back, not how you throw a reply away.
      expect(find.text('Come back to this'), findsOneWidget);
    });

    testWidgets('a draft the site already had is restored on open', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            draft: const ComposerDraft(
              reply: 'Started in a browser',
              replyToPostNumber: 1,
              replyToUsername: 'sam',
            ),
          ),
        },
      );

      await openComposer(tester, api);

      // It arrives with the topic payload, so no request of its own.
      expect(find.text('Started in a browser'), findsOneWidget);
      // And it remembers who it was answering.
      expect(find.text('Reply to @sam'), findsOneWidget);
    });

    testWidgets('a draft the site would not take is kept on the device', (
      tester,
    ) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Written offline');
      await settleDraft(tester);

      // The local copy is written first and only removed once the site has the
      // same text, so a failed sync cannot lose it.
      expect(drafts.saved, hasLength(1));
      expect(drafts.saved.values.single, contains('Written offline'));
      expect(
        find.text('Not saved on the site — kept on this device only.'),
        findsOneWidget,
      );
    });

    testWidgets('the sync stops asking a site that will not answer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api);

      for (
        var attempt = 1;
        attempt <= ComposerController.maxDraftFailures;
        attempt++
      ) {
        await tester.enterText(find.byType(TextField), 'Attempt $attempt');
        await settleDraft(tester);
      }
      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));

      await tester.enterText(find.byType(TextField), 'And one more');
      await settleDraft(tester);

      // Still exactly as many: it gave up rather than kept hammering.
      expect(api.draftsSaved, hasLength(ComposerController.maxDraftFailures));
    });

    testWidgets('posting clears the draft it was written as', (tester) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        draftFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Going out now');
      await settleDraft(tester);
      expect(drafts.saved, isNotEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Reply'));
      await tester.pumpAndSettle();

      // Discourse deletes its own copy when it accepts a post; ours has to go
      // too, or reopening the composer offers to write the reply again.
      expect(drafts.saved, isEmpty);
    });
  });

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
      // The one that proves it is app-level rather than per-site: the rail is
      // the only surface that survives having nothing to show.
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
        // No last-checked stamp, so load() looks straight away.
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
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

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

      // The exact string, not a substring: the topic list behind the sheet is
      // also failing to reach a site, and says so in nearly the same words.
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

      // The launch check failed. Nobody asked, so nothing is said.
      //
      // Scoped to the rail: the topic list behind it uses the same warning
      // icon for its own unrelated failure to reach a site.
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

      // The same button, so trying again is the obvious thing to do.
      expect(find.text('Download 1.4.0'), findsOneWidget);
    });

    testWidgets('a download survives the sheet being closed and reopened', (
      tester,
    ) async {
      // The deviation from _AddInstanceForm earns its own test: a site lookup
      // may die with the sheet that started it, but a download must not.
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

      // Close the sheet with the download still in flight.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(find.textContaining('Downloading'), findsNothing);

      await tester.tap(find.byType(CircularProgressIndicator).last);
      await tester.pumpAndSettle();

      // Still the same download, at the same point, not restarted.
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

  group('chat', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    const site = 'https://meta.discourse.org';

    /// Totals from a site that has chat, which is the only thing that makes
    /// this app ask for channels at all.
    const withChat = NotificationTotals(
      chatNotifications: 0,
      hasChatEnabled: true,
    );
    const withoutChat = NotificationTotals();

    ChatChannel channel(
      int id, {
      String title = 'Bugs',
      String? slug,
      String? emoji,
      String? color,
      int unread = 0,
      int mentions = 0,
      bool muted = false,
      int? lastRead,
    }) => ChatChannel(
      id: id,
      title: title,
      kind: ChatChannelKind.category,
      slug: slug ?? title.toLowerCase(),
      emoji: emoji,
      categoryColor: color == null
          ? null
          : Color(int.parse('FF$color', radix: 16)),
      membership: ChatMembership(
        following: true,
        muted: muted,
        lastReadMessageId: lastRead,
      ),
      tracking: ChatTracking(unreadCount: unread, mentionCount: mentions),
    );

    ChatChannel dm(
      int id, {
      String title = 'hawk',
      List<ChatUser>? users,
      int unread = 0,
      int mentions = 0,
      int watchedThreads = 0,
    }) => ChatChannel(
      id: id,
      title: title,
      kind: ChatChannelKind.directMessage,
      users:
          users ??
          const [
            ChatUser(
              id: 2,
              username: 'hawk',
              avatarUrl: '$site/user_avatar/h/90.png',
            ),
          ],
      membership: const ChatMembership(following: true),
      tracking: ChatTracking(
        unreadCount: unread,
        mentionCount: mentions,
        watchedThreadsUnreadCount: watchedThreads,
      ),
    );

    ChatMessage msg(
      int id, {
      String cooked = '<p>Hello there</p>',
      int author = 2,
      String username = 'sam',
      int minute = 0,
      List<ChatUpload> uploads = const [],
      List<ChatReaction> reactions = const [],
      ChatThreadPreview? thread,
    }) => ChatMessage(
      id: id,
      channelId: 9,
      cooked: cooked,
      author: ChatMessageAuthor(id: author, username: username),
      createdAt: DateTime.utc(2026, 5, 5, 10, minute),
      uploads: uploads,
      reactions: reactions,
      thread: thread,
    );

    ChatMessagePage page(
      List<ChatMessage> messages, {
      bool canLoadMorePast = false,
      bool canLoadMoreFuture = false,
    }) => (
      messages: messages,
      canLoadMorePast: canLoadMorePast,
      canLoadMoreFuture: canLoadMoreFuture,
    );

    String key(int channelId, {int? before, int? after}) =>
        FakeDiscourseApi.chatMessagesKey(
          channelId,
          before: before,
          after: after,
        );

    /// A signed-in site, so the totals call the chat gate hangs off has an
    /// account to be made as.
    Future<void> pumpChat(
      WidgetTester tester, {
      NotificationTotals totals = withChat,
      List<ChatChannel> public = const [],
      List<ChatChannel> direct = const [],
      Map<String, ChatMessagePage> messages = const {},
      FakeDiscourseApi? api,
      Size size = desktop,
      Completer<void>? channelGate,
      DiscourseUser user = me,
    }) async {
      await pumpShell(
        tester,
        size,
        api:
            api ??
            FakeDiscourseApi(
              totals: totals,
              user: user,
              chatChannelsBySite: {site: (public: public, direct: direct)},
              chatChannelGate: channelGate,
              chatMessagesByKey: messages,
            ),
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: user),
        ],
        authenticator: FakeAuthenticator()..keys[site] = 'meta-key',
      );
      await tester.pumpAndSettle();
    }

    /// Settles the tree, then waits out the half second a channel has to sit
    /// still before the reader is credited with what is on it.
    ///
    /// The second pump is not belt and braces: `pumpAndSettle` stops when no
    /// more frames are scheduled, and a pending timer schedules none — so
    /// without it the debounce is a coin toss on how many frames the fetch
    /// happened to cause.
    Future<void> pumpUntilRead(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    }

    group('in the header', () {
      final shortcut = find.byKey(ChatHeaderButton.buttonKey);
      final dot = find.byKey(ChatHeaderButton.unreadDotKey);
      final urgent = find.byKey(ChatHeaderButton.urgentBadgeKey);

      testWidgets('is shown only for an account allowed to chat', (
        tester,
      ) async {
        await pumpChat(tester);
        expect(shortcut, findsOneWidget);

        await pumpChat(tester, totals: withoutChat);
        expect(shortcut, findsNothing);

        await pumpChat(
          tester,
          user: const DiscourseUser(
            id: 7,
            username: 'joffreyj',
            hasChatEnabled: false,
          ),
        );
        expect(shortcut, findsNothing);
      });

      testWidgets('draws a quiet dot for ordinary public activity', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9, unread: 42)]);

        expect(dot, findsOneWidget);
        expect(urgent, findsNothing);
        expect(find.text('42'), findsNothing);
      });

      testWidgets('draws the aggregate urgent count and caps it at 99+', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, mentions: 2)],
          direct: [dm(12, unread: 98, watchedThreads: 1)],
        );

        expect(urgent, findsOneWidget);
        expect(find.text('99+'), findsOneWidget);
        expect(dot, findsNothing);
      });

      testWidgets('honours the account’s indicator preference', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9, unread: 4)],
          user: const DiscourseUser(
            id: 7,
            username: 'joffreyj',
            chatHeaderIndicatorPreference:
                ChatHeaderIndicatorPreference.directMessagesAndMentions,
          ),
        );

        expect(shortcut, findsOneWidget);
        expect(dot, findsNothing);
        expect(urgent, findsNothing);
      });

      testWidgets('suppresses every indicator during Do Not Disturb', (
        tester,
      ) async {
        await pumpChat(
          tester,
          direct: [dm(12, unread: 3)],
          user: DiscourseUser(
            id: 7,
            username: 'joffreyj',
            doNotDisturbUntil: DateTime.now().add(const Duration(days: 1)),
          ),
        );

        expect(shortcut, findsOneWidget);
        expect(dot, findsNothing);
        expect(urgent, findsNothing);
      });

      testWidgets('restores waiting activity when Do Not Disturb expires', (
        tester,
      ) async {
        await pumpChat(
          tester,
          direct: [dm(12, unread: 3)],
          user: DiscourseUser(
            id: 7,
            username: 'joffreyj',
            doNotDisturbUntil: DateTime.now().add(const Duration(seconds: 1)),
          ),
        );
        expect(urgent, findsNothing);

        await tester.pump(const Duration(seconds: 2));

        expect(urgent, findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      });

      testWidgets('opens the server’s last chat channel', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          direct: [dm(12)],
          messages: {key(9): page(const [])},
          user: const DiscourseUser(
            id: 7,
            username: 'joffreyj',
            lastChatChannelId: 9,
          ),
        );

        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        final shell = ShellScope.read(
          tester.element(find.byType(ChatChannelView)),
        );
        expect(shell.currentContent?.id, ChatChannel.routeId(9));
      });

      testWidgets('disappears while chat is active on a compact shell', (
        tester,
      ) async {
        await pumpChat(
          tester,
          size: phone,
          public: [channel(9)],
          messages: {key(9): page(const [])},
        );
        expect(shortcut, findsOneWidget);

        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(shortcut, findsNothing);
      });
    });

    group('in the sidebar', () {
      testWidgets('draws nothing on a site whose totals never mentioned chat', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withoutChat,
          chatChannelsBySite: {
            site: (public: [channel(9)], direct: const []),
          },
        );

        await pumpChat(tester, api: api);

        expect(find.text('CHAT'), findsNothing);
        // And nothing was even asked for: absence of the key is a complete
        // answer, not a reason to go and check.
        expect(api.chatChannelsRequested, isEmpty);
      });

      testWidgets('asks a site for channels once its totals said it has them', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9)], direct: const []),
          },
        );

        await pumpChat(tester, api: api);

        expect(api.chatChannelsRequested, [site]);
        expect(sidebarDestination('Bugs'), findsOneWidget);
      });

      testWidgets('draws nothing while the channel list is still on its way', (
        tester,
      ) async {
        // A heading that appears and then vanishes is worse than one that
        // arrives late, and a section with a spinner in it says something
        // untrue about how many channels there are.
        final gate = Completer<void>();
        await pumpChat(tester, public: [channel(9)], channelGate: gate);

        expect(find.text('CHAT'), findsNothing);

        final shell = ShellScope.read(
          tester.element(find.byType(InstanceSidebar)),
        );
        var shellNotifications = 0;
        void countShellNotification() => shellNotifications += 1;
        shell.addListener(countShellNotification);
        addTearDown(() => shell.removeListener(countShellNotification));

        gate.complete();
        await tester.pumpAndSettle();

        expect(find.text('CHAT'), findsOneWidget);
        expect(shellNotifications, 0);
      });

      testWidgets('draws nothing for an account that follows no channels', (
        tester,
      ) async {
        await pumpChat(tester);

        expect(find.text('CHAT'), findsNothing);
        expect(find.text('DIRECT MESSAGES'), findsNothing);
      });

      testWidgets('lists the public channels above the direct messages', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, title: 'Bugs')],
          direct: [dm(12, title: 'hawk')],
        );

        final chatHeading = tester.getTopLeft(find.text('CHAT')).dy;
        final dmHeading = tester.getTopLeft(find.text('DIRECT MESSAGES')).dy;
        expect(chatHeading, lessThan(dmHeading));
        expect(sidebarDestination('Bugs'), findsOneWidget);
        expect(sidebarDestination('hawk'), findsOneWidget);
      });

      testWidgets(
        'draws a channel emoji where an ordinary entry draws an icon',
        (tester) async {
          await pumpChat(tester, public: [channel(9, emoji: 'bug')]);

          // The artwork is answered 404 in these tests, so the shortcode is what
          // lands — which is exactly the fallback the emoji widget promises.
          expect(
            find.descendant(
              of: find.byType(InstanceSidebar),
              matching: find.byType(EmojiImage),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('draws the other person’s face on a one-to-one conversation', (
        tester,
      ) async {
        await pumpChat(tester, direct: [dm(12)]);

        final avatar = find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.byType(AvatarImage),
        );
        expect(avatar, findsOneWidget);
        // Round, not an ellipse: the row's prefix slot is a fixed width, and a
        // fixed width is a tight constraint that a SizedBox inside it cannot
        // shrink below. See the message tile's own version of this.
        final size = tester.getSize(avatar);
        expect(size.width, size.height);
      });

      testWidgets('draws a dot rather than a number, however much is unread', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9, unread: 42)]);

        expect(
          find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.text('42'),
          ),
          findsNothing,
        );
        expect(sidebarDestination('Bugs'), findsOneWidget);
      });

      testWidgets('forgets a disconnected site’s channels', (tester) async {
        // Reconnecting can land on a different account, and what the last one
        // was in is none of its business.
        await pumpChat(tester, size: phone, public: [channel(9)]);
        expect(sidebarDestination('Bugs'), findsOneWidget);

        await tester.longPress(find.byTooltip('Meta\nmeta.discourse.org'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('More Options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove forum'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();

        expect(sidebarDestination('Bugs'), findsNothing);
      });
    });

    group('a channel', () {
      testWidgets('draws a round avatar rather than an oval', (tester) async {
        // The gutter that keeps a chained row's body aligned is a fixed width,
        // and a fixed width is a *tight* constraint — which a SizedBox inside it
        // cannot shrink below, so the avatar came out gutter-wide and
        // avatar-tall and ClipOval turned it into an ellipse.
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([msg(1)]),
          },
        );
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        final size = tester.getSize(
          find.descendant(
            of: find.byType(ChatMessageTile),
            matching: find.byType(AvatarImage),
          ),
        );

        expect(size.width, size.height);
      });

      testWidgets('opens the channel the sidebar entry names', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([msg(1)]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(renderedText('Hello there'), findsOneWidget);
      });

      testWidgets('updates a loading channel without notifying the shell', (
        tester,
      ) async {
        final gate = Completer<void>();
        await pumpChat(
          tester,
          api: FakeDiscourseApi(
            totals: withChat,
            chatChannelsBySite: {
              site: (public: [channel(9)], direct: const []),
            },
            chatMessagesByKey: {
              key(9): page([msg(1)]),
            },
            chatMessageGate: gate,
          ),
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        var shellNotifications = 0;
        void countShellNotification() => shellNotifications += 1;
        shell.addListener(countShellNotification);
        addTearDown(() => shell.removeListener(countShellNotification));

        gate.complete();
        await tester.pumpAndSettle();

        expect(renderedText('Hello there'), findsOneWidget);
        expect(shellNotifications, 0);
      });

      testWidgets('puts the newest message at the bottom', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(1, cooked: '<p>Older</p>'),
              msg(2, cooked: '<p>Newer</p>', minute: 1),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(
          tester.getTopLeft(renderedText('Older')).dy,
          lessThan(tester.getTopLeft(renderedText('Newer')).dy),
        );
      });

      testWidgets('hides the name on a message chained to the one above', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(1, cooked: '<p>One</p>'),
              msg(2, cooked: '<p>Two</p>', minute: 1),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        // Two messages, one name: the second belongs to the first's run.
        expect(find.text('sam'), findsOneWidget);
      });

      testWidgets('shows the name again once somebody else speaks', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(1, cooked: '<p>One</p>'),
              msg(
                2,
                cooked: '<p>Two</p>',
                minute: 1,
                author: 3,
                username: 'kris',
              ),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('sam'), findsOneWidget);
        expect(find.text('kris'), findsOneWidget);
      });

      testWidgets('draws an image a message carried outside its cooked body', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(
                1,
                cooked: '',
                uploads: const [
                  ChatUpload(
                    url: '/uploads/shot.png',
                    originalFilename: 'shot.png',
                    kind: ChatUploadKind.image,
                    width: 400,
                    height: 200,
                  ),
                ],
              ),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.byType(ChatUploads), findsOneWidget);
      });

      testWidgets('names a file it cannot draw rather than dropping it', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(
                1,
                uploads: const [
                  ChatUpload(
                    url: '/uploads/notes.pdf',
                    originalFilename: 'notes.pdf',
                    kind: ChatUploadKind.attachment,
                    humanFilesize: '12 KB',
                  ),
                ],
              ),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('notes.pdf'), findsOneWidget);
        expect(find.text('12 KB'), findsOneWidget);
      });

      testWidgets(
        'shows the reactions a message has without offering to add one',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9)],
            messages: {
              key(9): page([
                msg(
                  1,
                  reactions: const [
                    ChatReaction(emoji: 'heart', count: 3, reacted: true),
                  ],
                ),
              ]),
            },
          );

          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          expect(find.text('3'), findsOneWidget);
          // Reacting is a write, and this step makes none.
          expect(find.byType(ReactionPill), findsNothing);
        },
      );

      testWidgets('says how many replies a message gathered into a thread', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(
                1,
                thread: const ChatThreadPreview(
                  threadId: 3,
                  replyCount: 7,
                  lastReplyUsername: 'kris',
                ),
              ),
            ]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('7 replies'), findsOneWidget);
      });

      testWidgets('says so when a channel has no messages in it yet', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page([])},
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('No messages here yet.'), findsOneWidget);
      });

      testWidgets('says so when a channel will not load at all', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9)]);

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('Could not load this channel.'), findsOneWidget);
      });

      testWidgets(
        'asks for older messages when a short channel does not fill the window',
        (tester) async {
          // Nothing to scroll, so the scroll threshold can never fire — the last
          // row being built is what says the top of the stream is on screen.
          final api = FakeDiscourseApi(
            totals: withChat,
            chatChannelsBySite: {
              site: (public: [channel(9)], direct: const []),
            },
            chatMessagesByKey: {
              key(9): page([msg(5, minute: 5)], canLoadMorePast: true),
              key(9, before: 5): page([msg(1)]),
            },
          );

          await pumpChat(tester, api: api);
          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          expect(api.chatMessagesRequested.map((ask) => ask.before), [null, 5]);
          expect(renderedText('Hello there'), findsNWidgets(2));
        },
      );

      testWidgets('stops asking once the site says there is nothing older', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([msg(5)]),
          },
        );

        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(api.chatMessagesRequested, hasLength(1));
      });

      testWidgets(
        'divides the messages the reader has not seen from the rest',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9, lastRead: 1)],
            messages: {
              key(9): page([
                msg(1, cooked: '<p>Seen</p>'),
                msg(2, cooked: '<p>Unseen</p>', minute: 1),
                msg(3, cooked: '<p>Also unseen</p>', minute: 2),
              ]),
            },
          );

          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          expect(find.text('New'), findsOneWidget);
        },
      );

      testWidgets(
        'opens where the reader left off, not at the newest message',
        (tester) async {
          // The reason the open is anchored at all. Landing at the live edge
          // would put the newest message on screen, and the reader would be
          // credited with a backlog they have not looked at.
          final backlog = [
            for (var id = 1; id <= 40; id++) msg(id, minute: id),
          ];
          final api = FakeDiscourseApi(
            totals: withChat,
            chatChannelsBySite: {
              site: (
                public: [channel(9, lastRead: 5, unread: 35)],
                direct: const [],
              ),
            },
            chatMessagesByKey: {key(9): page(backlog)},
          );

          await pumpChat(tester, api: api, size: phone);
          await tester.tap(sidebarDestination('Bugs'));
          await pumpUntilRead(tester);

          // It asked the site to place them, rather than placing them itself.
          expect(api.chatMessagesRequested.single.fromLastRead, isTrue);
          // Credited with what the screen holds around message 5, and nowhere
          // near the forty the channel has.
          final marked = api.chatReadsMarked.single.messageId;
          expect(marked, greaterThan(5));
          expect(marked, lessThan(40));
          // And the line they left off at is on screen, which is the point of
          // landing there.
          expect(find.text('New'), findsOneWidget);
        },
      );

      testWidgets('holds the reader still when the present is paged in', (
        tester,
      ) async {
        // Newer messages land *under* a reversed list and push it up by their
        // own height. Without pinning, catching up on three messages would
        // carry the reader thirty forward and credit them with the lot.
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9, lastRead: 1)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1),
              msg(2, minute: 1),
              msg(3, minute: 2),
            ], canLoadMoreFuture: true),
            key(9, after: 3): page([
              for (var id = 4; id <= 33; id++) msg(id, minute: id),
            ]),
          },
        );

        await pumpChat(tester, api: api, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await pumpUntilRead(tester);

        // The window reached the present — and the reader did not.
        expect(api.chatMessagesRequested.last.after, 3);
        expect(
          api.chatReadsMarked.map((mark) => mark.messageId),
          isNot(contains(33)),
        );
      });

      testWidgets('offers the way back to the present, and takes it', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9, lastRead: 1)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1, cooked: '<p>Back then</p>'),
              msg(2, cooked: '<p>Also back then</p>', minute: 1),
            ], canLoadMoreFuture: true),
            // What the site answers once the window is asked for afresh.
            FakeDiscourseApi.chatMessagesLatestKey(9): page([
              msg(80, cooked: '<p>Right now</p>', minute: 80),
            ]),
          },
        );

        await pumpChat(tester, api: api, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        // A window with messages still in front of it is not the present, so
        // the button is there whatever the scroll position says.
        final button = find.dIcon(DIcons.chevronDown);
        expect(button, findsOneWidget);

        await tester.tap(button);
        await tester.pumpAndSettle();

        expect(api.chatMessagesRequested.last.fromLastRead, isFalse);
        expect(renderedText('Right now'), findsOneWidget);
        expect(button, findsNothing);
      });

      testWidgets(
        'leaves the divider where it was, though reading has moved past it',
        (tester) async {
          // Reading the channel credits the reader with all three messages
          // within the pump below. A divider drawn from the membership would
          // have gone with it; this one is pinned to the fetch.
          final api = FakeDiscourseApi(
            totals: withChat,
            chatChannelsBySite: {
              site: (public: [channel(9, lastRead: 1)], direct: const []),
            },
            chatMessagesByKey: {
              key(9): page([msg(1), msg(2, minute: 1), msg(3, minute: 2)]),
            },
          );

          await pumpChat(tester, api: api);
          await tester.tap(sidebarDestination('Bugs'));
          await pumpUntilRead(tester);

          expect(api.chatReadsMarked, [(channelId: 9, messageId: 3)]);
          expect(find.text('New'), findsOneWidget);
        },
      );

      testWidgets('credits the reader with the messages it puts on screen', (
        tester,
      ) async {
        // The whole path: the viewport is measured, the newest row on it is a
        // message, and the site is told about that one.
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (
              public: [channel(9, unread: 3, lastRead: 1)],
              direct: const [],
            ),
          },
          chatMessagesByKey: {
            key(9): page([msg(1), msg(2, minute: 1), msg(3, minute: 2)]),
          },
        );

        await pumpChat(tester, api: api);
        expect(api.chatReadsMarked, isEmpty);

        await tester.tap(sidebarDestination('Bugs'));
        await pumpUntilRead(tester);

        expect(api.chatReadsMarked, [(channelId: 9, messageId: 3)]);
      });

      testWidgets('credits the reader on the way out of a channel', (
        tester,
      ) async {
        // Discourse writes from its teardown for this: leaving inside the
        // debounce window is leaving having read it, and a cancelled timer
        // would throw that away.
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9, unread: 1)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([msg(1)]),
          },
        );

        await pumpChat(tester, api: api, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Still inside the 500ms the reader has to hold still for.
        expect(api.chatReadsMarked, isEmpty);

        await tester.tap(find.dIcon(DIcons.arrowLeft));
        await tester.pumpAndSettle();

        expect(api.chatReadsMarked, [(channelId: 9, messageId: 1)]);
      });

      testWidgets('tells the site nothing about a channel nobody opened', (
        tester,
      ) async {
        // Drawing a row in the sidebar is not reading it.
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: (public: [channel(9, unread: 3)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([msg(1)]),
          },
        );

        await pumpChat(tester, api: api);

        expect(api.chatReadsMarked, isEmpty);
      });

      testWidgets('shows the channel on its own pane on a phone', (
        tester,
      ) async {
        await pumpChat(
          tester,
          size: phone,
          public: [channel(9)],
          messages: {
            key(9): page([msg(1)]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        // The sidebar has given way to the channel, and back returns to it.
        expect(find.byType(InstanceSidebar), findsNothing);
        expect(renderedText('Hello there'), findsOneWidget);

        await tester.tap(find.dIcon(DIcons.arrowLeft));
        await tester.pumpAndSettle();

        expect(find.byType(InstanceSidebar), findsOneWidget);
      });
    });
  });
}

/// A 1x1 transparent PNG — the smallest thing `Image.memory` will accept.
final Uint8List emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
