import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/app.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/data/draft_store.dart';
import 'package:discourse_native/src/data/emoji_cache.dart';
import 'package:discourse_native/src/data/topic_recommendations_tab_store.dart';
import 'package:discourse_native/src/data/topic_sidebar_store.dart';
import 'package:discourse_native/src/data/updater.dart';
import 'package:discourse_native/src/data/user_api_key.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/bookmark.dart';
import 'package:discourse_native/src/models/composer_draft.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_instance.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/found_hashtag.dart';
import 'package:discourse_native/src/models/found_user.dart';
import 'package:discourse_native/src/models/group_route.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/post.dart';
import 'package:discourse_native/src/models/post_creation.dart';
import 'package:discourse_native/src/models/post_flag.dart';
import 'package:discourse_native/src/models/post_likers.dart';
import 'package:discourse_native/src/models/search_results.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/sidebar_tag.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/topic_tracking_state.dart';
import 'package:discourse_native/src/models/user_activity.dart';
import 'package:discourse_native/src/models/user_card.dart';
import 'package:discourse_native/src/models/user_draft.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugins/assign/assignment.dart';
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary.dart';
import 'package:discourse_native/src/plugins/discourse_ai/ai_summary_plugin.dart';
import 'package:discourse_native/src/plugins/reactions/post_reactors.dart';
import 'package:discourse_native/src/plugins/reactions/reaction.dart';
import 'package:discourse_native/src/plugins/reactions/reaction_picker.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_row.dart';
import 'package:discourse_native/src/plugins/reactions/reactions_settings.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/bookmark_list.dart';
import 'package:discourse_native/src/shell/categories_page.dart';
import 'package:discourse_native/src/shell/composer_autocomplete.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/empty_state.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/hashtag.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/mention.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/post_footer.dart';
import 'package:discourse_native/src/shell/post_likes.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_metrics.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/shell/topic_category_path.dart';
import 'package:discourse_native/src/shell/topic_create_button.dart';
import 'package:discourse_native/src/shell/topic_list_view.dart';
import 'package:discourse_native/src/shell/topic_title.dart';
import 'package:discourse_native/src/shell/topic_view.dart';
import 'package:discourse_native/src/shell/user_activity.dart';
import 'package:discourse_native/src/shell/user_menu.dart';
import 'package:discourse_native/src/shell/user_menu_button.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show
        PointerEnterEvent,
        PointerExitEvent,
        kBackMouseButton,
        kForwardMouseButton,
        kLongPressTimeout,
        kMiddleMouseButton,
        kPrimaryMouseButton,
        kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

const Size phone = Size(390, 844);
const Size laptop = Size(1000, 800);
const Size desktop = Size(1440, 900);

Finder get activityIndicators => find.byWidgetPredicate(
  (widget) =>
      widget is CircularProgressIndicator ||
      widget is CupertinoActivityIndicator,
  description: 'adaptive activity indicator',
);

Finder minimumHeightDescendants(Finder root, double minimumHeight) =>
    find.descendant(
      of: root,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox &&
            widget.constraints.minHeight == minimumHeight,
      ),
    );

Finder minimumHeightAncestors(Finder child, double minimumHeight) =>
    find.ancestor(
      of: child,
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is ConstrainedBox &&
            widget.constraints.minHeight == minimumHeight,
      ),
    );

final List<DiscourseInstance> twoSites = List.unmodifiable([
  instance('meta.discourse.org', title: 'Discourse Meta'),
  instance('team.discourse.org', title: 'Discourse Team'),
]);

void _replaceEmojiCache(EmojiCache replacement) {
  final previous = EmojiCache.instance;
  EmojiCache.instance = replacement;
  addTearDown(() {
    replacement.clear();
    EmojiCache.instance = previous;
  });
}

Future<void> pumpShell(
  WidgetTester tester,
  Size size, {
  List<DiscourseInstance>? instances,
  FakeDiscourseApi? api,
  FakeInstanceStore? store,
  FakeAuthenticator? authenticator,
  FakeDraftStore? drafts,
  FakeForumTabStore? forumTabs,
  FakeUpdater? updater,
  FakeUpdateStore? updateStore,
  Key? key,
  Future<void> Function()? beforeSettle,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Cooked emoji would otherwise trigger network requests in widget tests.
  _replaceEmojiCache(
    EmojiCache(client: MockClient((_) async => http.Response('', 404))),
  );

  await tester.pumpWidget(
    DiscourseApp(
      key: key,
      store: store ?? FakeInstanceStore(instances ?? twoSites),
      api: api ?? FakeDiscourseApi(),
      authenticator: authenticator ?? FakeAuthenticator(),
      drafts: drafts ?? FakeDraftStore(),
      forumTabs: forumTabs ?? FakeForumTabStore(),
      trackers: FakeSiteTracker.reset(),
      updater: updater ?? FakeUpdater(),
      updateStore: updateStore ?? FakeUpdateStore(),
      initialRootMode: ShellRootMode.forum,
      pluginManifest: bundledWidgetTestManifest,
    ),
  );
  if (beforeSettle != null) {
    await tester.pump();
    await beforeSettle();
  }
  await tester.pumpAndSettle();
}

/// HtmlWidget renders into a bare RichText, which find.text and
/// find.textContaining both ignore.
Finder renderedText(String text) => find.byWidgetPredicate(
  (widget) => widget is RichText && widget.text.toPlainText().contains(text),
  description: 'rendered text containing "$text"',
);

/// The surface the first post paints for itself. The innermost [ColoredBox]
/// above the body is the post's own.
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

List<String> watchClipboard(WidgetTester tester) {
  final copied = <String>[];
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied.add((call.arguments as Map)['text'] as String);
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

List<MethodCall> watchAppExits(WidgetTester tester) {
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
Future<void> systemBack(WidgetTester tester) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.navigation.name,
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
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

final class _FailingUserActivityApi extends FakeDiscourseApi {
  int calls = 0;

  @override
  Future<UserActivityPage> userActivity({
    required String siteUrl,
    required String apiKey,
    required String username,
    int offset = 0,
    int limit = 30,
    String? clientId,
  }) async {
    calls++;
    throw StateError('offline');
  }
}

final class _GatedConnectAuthenticator extends FakeAuthenticator {
  final gate = Completer<void>();
  final started = Completer<void>();

  @override
  Future<UserApiCredentials> connect(String siteUrl) async {
    started.complete();
    await gate.future;
    return super.connect(siteUrl);
  }
}

final Finder userMenu = find.byWidgetPredicate(
  (widget) =>
      widget.key == UserMenuButton.avatarKey ||
      widget.key == UserMenuButton.signInKey,
  description: 'account menu or sign-in action',
);

Finder sidebarDestination(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is! Text || widget.data != label) return false;

  var inSidebar = false;
  element.visitAncestorElements((ancestor) {
    inSidebar |= ancestor.widget is InstanceSidebar;
    return true;
  });
  return inSidebar;
}, description: 'sidebar destination labelled "$label"');

Finder contentText(String label) => find.byElementPredicate((element) {
  final widget = element.widget;
  if (widget is! Text || widget.data != label) return false;

  var inMainContent = false;
  var inForumTabs = false;
  element.visitAncestorElements((ancestor) {
    inMainContent |= ancestor.widget is MainContent;
    inForumTabs |= ancestor.widget is ForumTabsBar;
    return true;
  });
  return inMainContent && !inForumTabs;
}, description: 'content text labelled "$label"');

Future<void> openProfileSection(WidgetTester tester) async {
  await tester.tap(userMenu);
  await tester.pumpAndSettle();

  final tab = find.byTooltip('Profile');
  await tester.tap(tab.evaluate().isEmpty ? find.text('Profile') : tab);
  await tester.pumpAndSettle();
}

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

Future<void> tapPostAction(WidgetTester tester, String tooltip) async {
  var action = find.byTooltip(tooltip);
  if (action.evaluate().isEmpty) {
    final more = find.byTooltip('More actions');
    expect(more, findsOneWidget);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final label = switch (tooltip) {
      'Share this post' => 'Share',
      'Edit this post' => 'Edit',
      'Delete this post' => 'Delete',
      'Allow community members to edit this post' => 'Make wiki',
      'Return this to ordinary post editing' => 'Remove wiki',
      'Prevent further edits to this post' => 'Lock post',
      'Allow this post to be edited again' => 'Unlock post',
      'Restore this hidden post' => 'Unhide post',
      'Mark this as an official moderator post' => 'Convert to moderator post',
      'Remove the moderator styling from this post' => 'Revert to regular post',
      'Add a staff notice above this post' => 'Add post notice',
      'Change or remove the staff notice' => 'Change post notice',
      'Assign this post to another account' => 'Change owner',
      'Permanently delete this post' => 'Permanently delete',
      'Put this post back' => 'Undelete',
      _ => throw StateError('No visible label for post action: $tooltip'),
    };
    action = find.widgetWithText(MenuItemButton, label);
  }
  expect(action, findsOneWidget);
  await tester.tap(action);
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
      _replaceEmojiCache(
        EmojiCache(
          client: MockClient((_) async => http.Response.bytes(emojiPng, 200)),
        ),
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
      final exits = watchAppExits(tester);
      await pumpShell(tester, phone);

      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();

      await systemBack(tester);
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(exits, isEmpty);

      // Nothing left to unwind. The shell's own PopScope swallowed the event,
      // so leaving the app has to be an explicit request to the platform.
      await systemBack(tester);
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
    expect(targetHeight(selected), 40);
    expect(targetHeight(inactive), 8);
    expect(marker(inactive).duration, const Duration(milliseconds: 180));
    expect(marker(inactive).curve, Curves.easeOutCubic);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(item(inactive)));
    await tester.pump();

    expect(targetHeight(inactive), 20);
    await tester.pump(const Duration(milliseconds: 90));
    expect(
      tester.getSize(indicator(inactive)).height,
      allOf(greaterThan(8), lessThan(20)),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 20);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 8);

    await gesture.moveTo(tester.getCenter(item(inactive)));
    await tester.pumpAndSettle();
    await tester.tap(item(inactive));
    await tester.pump();

    expect(targetHeight(selected), 8);
    expect(targetHeight(inactive), 40);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(selected)).height, 8);
    expect(tester.getSize(indicator(inactive)).height, 40);

    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(tester.getSize(indicator(inactive)).height, 40);
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
      closeTo(9, 0.01),
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
      closeTo(9, 0.01),
    );
    expect(tester.getSize(projectsHeader).height, closeTo(35.2, 0.01));
    expect(tester.getSize(roadmapTile).height, closeTo(35.2, 0.01));

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
        '/c/parent/child/2.json': [
          Topic(id: 7, title: 'A category topic', slug: 'a-category-topic'),
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
    expect(tile.top - sidebar.top - shellHeaderHeight, closeTo(16, 0.01));
    expect(tile.left - sidebar.left, closeTo(8, 0.01));
    expect(sidebar.right - tile.right, closeTo(8, 0.01));
    expect(tile.height, closeTo(35.2, 0.01));
    expect(tester.getRect(topics).left - sidebar.left, closeTo(44, 0.01));
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
        expect(tester.getSize(indicator), const Size(62, 8));
        expect(
          tester.getRect(indicator).center.dy,
          closeTo(targetRect.top, 0.1),
        );
        final line = find.byKey(dropIndicatorLine);
        final pin = find.byKey(dropIndicatorPin);
        expect(tester.getSize(line), const Size(54, 2));
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

      expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
      await tester.tap(find.byKey(TopicCreateButton.buttonKey));
      await tester.pumpAndSettle();

      expect(find.text('Create a new topic'), findsOneWidget);
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(find.text('Create topic'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
      final categoryRequestCount = api.categoryRequests.length;
      final capabilityRequestCount = api.topicComposerCapabilityRequests.length;

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byKey(TopicCreateButton.buttonKey));
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
      expect(contentText('A native topic'), findsOneWidget);
      expect(
        api.feedPaths.where((path) => path == '/latest.json').length,
        greaterThanOrEqualTo(2),
      );
    });

    const inbox = '/topics/private-messages/joffreyj.json';

    testWidgets(
      'the sidebar puts New Topic below Messages and opens it globally',
      (tester) async {
        const user = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          canCreateTopic: true,
        );
        final api = FakeDiscourseApi(
          user: user,
          feeds: {
            '/latest.json': latest,
            inbox: [
              const Topic(id: 9, title: 'A private message', slug: 'a-pm'),
            ],
          },
          creatableFeedPaths: const {'/latest.json'},
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: user),
          ],
          api: api,
          authenticator: authenticator,
        );

        final messages = sidebarDestination('Messages');
        final newTopic = sidebarDestination('New Topic');
        final drafts = sidebarDestination('Drafts');
        expect(newTopic, findsOneWidget);
        expect(
          tester.getTopLeft(messages).dy,
          lessThan(tester.getTopLeft(newTopic).dy),
        );
        expect(
          tester.getTopLeft(newTopic).dy,
          lessThan(tester.getTopLeft(drafts).dy),
        );
        final newTopicTile = find
            .ancestor(of: newTopic, matching: find.byType(InkWell))
            .first;
        expect(
          find.descendant(of: newTopicTile, matching: find.dIcon(DIcons.plus)),
          findsOneWidget,
        );

        await tester.tap(messages);
        await tester.pumpAndSettle();
        expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);

        await tester.tap(newTopic);
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsOneWidget);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.currentContent?.isMessages, isTrue);
        expect(shell.visibleComposer?.target.isNewTopic, isTrue);
        expect(shell.visibleComposer?.target.originFeedId, 'latest');
      },
    );

    testWidgets('C opens New Topic across forum routes but not Aggregate', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {
          '/latest.json': latest,
          inbox: const [Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyC), isTrue);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.currentContent?.isMessages, isTrue);
      expect(shell.visibleComposer?.target.isNewTopic, isTrue);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      shell.selectAggregate();
      await tester.pumpAndSettle();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyC), isFalse);
      await tester.pump();
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('C leaves focused forum form controls alone', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      shell.openPreferences('https://meta.discourse.org');
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey(('like-notification-frequency', 1))),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(
        find.byKey(const ValueKey('preferences-section-profile')),
      );
      await tester.pumpAndSettle();
      final timezone = find.descendant(
        of: find.byKey(const ValueKey('preferences-timezone')),
        matching: find.byType(EditableText),
      );
      await tester.tap(timezone);
      await tester.pump();
      expect(tester.widget<EditableText>(timezone).focusNode.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('the sidebar hides New Topic when the account cannot post', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: false,
      );
      final api = FakeDiscourseApi(user: user, feeds: {'/latest.json': latest});
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      expect(sidebarDestination('New Topic'), findsNothing);
    });

    testWidgets('compact New Topic reveals the composer pane', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        user: user,
        feeds: {'/latest.json': latest},
        creatableFeedPaths: const {'/latest.json'},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        phone,
        instances: [instance('meta.discourse.org').copyWith(user: user)],
        api: api,
        authenticator: authenticator,
      );

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      await tester.tap(sidebarDestination('New Topic'));
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        ShellScope.read(tester.element(find.byType(MainContent))).mobilePane,
        MobilePane.content,
      );
    });

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

    testWidgets('switches between personal and eligible group inboxes', (
      tester,
    ) async {
      const teamInbox = '/topics/private-messages-group/joffreyj/team.json';
      final api = FakeDiscourseApi(
        user: const DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          messageGroupNames: ['team', 'tech-advocates'],
        ),
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
          teamInbox: [
            const Topic(id: 10, title: 'Team escalation', slug: 'team-pm'),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('message-inbox-picker')),
        findsOneWidget,
      );
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('A private message'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      expect(find.text('team'), findsOneWidget);
      expect(find.text('tech-advocates'), findsOneWidget);
      await tester.tap(find.text('team'));
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(api.feedPaths, contains(teamInbox));
      expect(find.text('Team escalation'), findsOneWidget);
      expect(find.text('A private message'), findsNothing);
      expect(controller.currentContent?.messageGroupName, 'team');
      expect(controller.currentFeedId, 'messages-group-team');
      expect(controller.canCreateTopicHere, isFalse);

      await tester.tap(find.byKey(const ValueKey('message-inbox-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();

      expect(find.text('A private message'), findsOneWidget);
      expect(controller.currentContent?.id, 'messages');
      expect(api.feedPaths.where((path) => path == inbox), hasLength(1));
    });

    testWidgets('restores the selected group inbox', (tester) async {
      const groupInbox =
          '/topics/private-messages-group/joffreyj/tech-advocates.json';
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        messageGroupNames: ['tech-advocates'],
      );
      final forumTabs = FakeForumTabStore([
        ForumWorkspace(
          siteUrl: 'https://meta.discourse.org',
          accountIdentity: 'user:joffreyj',
          activeTabId: 'group-inbox-tab',
          tabs: [
            ForumTab(
              id: 'group-inbox-tab',
              rootDestinationId: 'messages',
              contentStack: [
                ContentRoute.messages(groupName: 'tech-advocates'),
              ],
            ),
          ],
        ),
      ]);
      final api = FakeDiscourseApi(
        user: user,
        feeds: {
          groupInbox: [
            const Topic(
              id: 10,
              title: 'Restored group message',
              slug: 'restored-group-pm',
            ),
          ],
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: user),
        ],
        api: api,
        authenticator: authenticator,
        forumTabs: forumTabs,
      );

      expect(api.feedPaths, [groupInbox]);
      expect(find.text('tech-advocates'), findsOneWidget);
      expect(find.text('Restored group message'), findsOneWidget);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentContent?.messageGroupName,
        'tech-advocates',
      );
    });

    testWidgets('messages uses a topic-row skeleton while loading', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': latest,
          inbox: [const Topic(id: 9, title: 'A private message', slug: 'a-pm')],
        },
        feedGates: {inbox: gate},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      await tester.tap(sidebarDestination('Messages'));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('topic-list-loading-skeleton')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Loading messages'), findsOneWidget);
      expect(activityIndicators, findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('A private message'), findsOneWidget);
      semantics.dispose();
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

        expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);
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

    testWidgets('closed topics carry a lock before the title', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 9,
              title: 'Closed topic',
              slug: 'closed-topic',
              categoryId: 5,
              closed: true,
            ),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Feature', color: '00C58E'),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      final title = find.text('Closed topic');
      final row = minimumHeightAncestors(title, TopicListRow.minimumHeight);
      final lock = find.descendant(of: row, matching: find.dIcon(DIcons.lock));
      final lockGlyph = find.descendant(
        of: lock,
        matching: find.byType(SvgPicture),
      );
      final categoryBlock = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.minWidth == 9 &&
              widget.constraints?.maxWidth == 9 &&
              widget.constraints?.minHeight == 9 &&
              widget.constraints?.maxHeight == 9,
        ),
      );

      expect(lock, findsOneWidget);
      expect(tester.getTopLeft(lock).dx, lessThan(tester.getTopLeft(title).dx));
      expect(lockGlyph, findsOneWidget);
      expect(categoryBlock, findsOneWidget);
      expect(
        tester.getTopLeft(lockGlyph).dx,
        tester.getTopLeft(categoryBlock).dx,
      );
      expect(find.bySemanticsLabel('Closed topic'), findsOneWidget);
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
      final theme = Theme.of(context);
      expect(
        tester.widget<Text>(find.text('Caught up')).style?.color,
        theme.discourse.whisper,
      );
      expect(
        tester.widget<Text>(find.text('Not caught up')).style?.color,
        theme.colorScheme.onSurface,
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

      final title = find.text('Short title');
      final titleEnd = tester.getTopLeft(title).dx + _textWidth(tester, title);
      final dot = tester.getRect(find.byKey(const ValueKey('new-topic-dot')));
      expect(dot.left - titleEnd, moreOrLessEquals(8, epsilon: 0.5));
    });

    testWidgets('topic state follows the end of a wrapped title', (
      tester,
    ) async {
      const title = 'Footnotes can scroll?';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: title,
              slug: 'wrapped-new-topic',
              seen: false,
              posterAvatars: ['', '', ''],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(find.text(title));
      final dot = _inlineWidgetBoxes(tester, find.text(title)).last;
      expect(titleRect.height, greaterThan(24));
      expect(dot.center.dy, greaterThan(titleRect.center.dy));
      expect(dot.bottom, lessThanOrEqualTo(titleRect.bottom));
    });

    testWidgets('unread count follows the end of a wrapped title', (
      tester,
    ) async {
      const title = 'Footnotes can scroll?';
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 9,
              title: title,
              slug: 'wrapped-unread-topic',
              unreadPosts: 3,
              posterAvatars: ['', '', ''],
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final titleRect = tester.getRect(find.text(title));
      final count = _inlineWidgetBoxes(tester, find.text(title)).last;
      expect(titleRect.height, greaterThan(24));
      expect(count.center.dy, greaterThan(titleRect.center.dy));
      expect(count.bottom, lessThanOrEqualTo(titleRect.bottom));
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

      expect(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.text('Feature'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('category badges use an embedded off-page subcategory', (
      tester,
    ) async {
      const parent = TopicCategory(
        id: 5,
        name: 'Discourse Native Application',
        color: '0088CC',
      );
      const category = TopicCategory(
        id: 6,
        name: 'Feature requests',
        color: '00AEEF',
        parentCategoryId: 5,
      );
      final categoryPath = topicCategoryPathLabel(category, parent: parent);
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'Off-page child topic',
              slug: 'off-page-child-topic',
              categoryId: 6,
            ),
          ],
        },
        categoryList: const [parent],
        feedCategoriesByPath: const {
          '/latest.json': [parent, category],
        },
      );

      await pumpShell(tester, desktop, api: api);

      expect(
        find.descendant(
          of: find.byType(TopicListView),
          matching: find.text(categoryPath),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Category: $categoryPath'), findsOneWidget);
      final categoryLabel = tester.widget<Text>(find.text(categoryPath));
      expect(categoryLabel.maxLines, isNull);
      expect(categoryLabel.overflow, isNull);
      expect(tester.getSize(find.text(categoryPath)).width, greaterThan(200));
      expect(api.categoryIdsRequested, isEmpty);
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
          '/c/feature/5.json': const [],
          '/tag/design/8.json': const [],
        },
        categoryList: const [
          TopicCategory(
            id: 5,
            name: 'Feature',
            color: '0088CC',
            slug: 'feature',
          ),
        ],
      );

      await pumpShell(tester, desktop, api: api);

      expect(find.text('design,'), findsOneWidget);
      expect(find.text('accessibility'), findsOneWidget);
      expect(find.bySemanticsLabel('Tag: design'), findsOneWidget);
      expect(find.bySemanticsLabel('Tag: accessibility'), findsOneWidget);
      expect(
        tester.getSize(find.bySemanticsLabel('Category: Feature')).height,
        greaterThanOrEqualTo(24),
      );
      expect(
        tester.getSize(find.bySemanticsLabel('Tag: design')).height,
        greaterThanOrEqualTo(24),
      );
      final category = find.descendant(
        of: find.byType(TopicListView),
        matching: find.text('Feature'),
      );
      expect(
        tester.getTopRight(category).dx,
        lessThan(tester.getTopLeft(find.text('design,')).dx),
      );

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      await tester.tap(category);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'category-5');
      expect(controller.currentContent?.feedPath, '/c/feature/5.json');
      expect(api.topicsOpened, isEmpty);

      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(find.text('design,'));
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'tag-8');
      expect(controller.currentContent?.feedPath, '/tag/design/8.json');
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('public and private tag feeds keep distinct identities', (
      tester,
    ) async {
      const tag = TopicTag(
        id: 8,
        name: 'priority / private',
        slug: 'priority%20%2F%20private',
      );
      const reader = DiscourseUser(id: 1, username: 'reader');
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {
          '/latest.json': const [
            Topic(
              id: 2,
              title: 'A public tagged topic',
              slug: 'a-public-tagged-topic',
              tags: [tag],
            ),
            Topic(
              id: 3,
              title: 'A private tagged topic',
              slug: 'a-private-tagged-topic',
              privateMessage: true,
              tags: [tag],
            ),
          ],
          '/tag/priority%20%2F%20private/8.json': const [],
          '/topics/private-messages-tags/reader/'
                  'priority%20%2F%20private.json':
              const [],
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );

      final tagLinks = find.bySemanticsLabel('Tag: ${tag.name}');
      expect(tagLinks, findsNWidgets(2));
      await tester.tap(tagLinks.first);
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(controller.currentContent?.id, 'tag-8');
      expect(
        controller.currentContent?.feedPath,
        '/tag/priority%20%2F%20private/8.json',
      );

      expect(controller.handleBack(canReturnToSidebar: false), isTrue);
      await tester.pumpAndSettle();
      await tester.tap(tagLinks.last);
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'pm-tag-8');
      expect(
        controller.currentContent?.feedPath,
        '/topics/private-messages-tags/reader/'
        'priority%20%2F%20private.json',
      );
      expect(
        api.feedPaths,
        containsAll([
          '/tag/priority%20%2F%20private/8.json',
          '/topics/private-messages-tags/reader/'
              'priority%20%2F%20private.json',
        ]),
      );
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('an idless numeric topic tag resolves before navigation', (
      tester,
    ) async {
      const tag = TopicTag(name: '2024');
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 3,
              title: 'A numeric tagged topic',
              slug: 'a-numeric-tagged-topic',
              tags: [tag],
            ),
          ],
          '/tag/2024/77.json': const [],
        },
        hashtagSearches: const {
          '2024': [
            FoundHashtag(
              type: 'tag',
              ref: '2024::tag',
              slug: '2024',
              text: '2024',
              id: 77,
            ),
          ],
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text(tag.name));
      await tester.pumpAndSettle();

      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      expect(api.hashtagSearchesRequested, ['2024']);
      expect(controller.currentContent?.id, 'tag-77');
      expect(controller.currentContent?.feedPath, '/tag/2024/77.json');
      expect(api.topicsOpened, isEmpty);
    });

    testWidgets('a late numeric tag lookup cannot reopen content after Back', (
      tester,
    ) async {
      const tag = TopicTag(name: '2024');
      final hashtagGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': const [
            Topic(
              id: 3,
              title: 'A numeric tagged topic',
              slug: 'a-numeric-tagged-topic',
              tags: [tag],
            ),
          ],
          '/tag/2024/77.json': const [],
        },
        hashtagSearchGate: hashtagGate,
        hashtagSearches: const {
          '2024': [
            FoundHashtag(
              type: 'tag',
              ref: '2024::tag',
              slug: '2024',
              text: '2024',
              id: 77,
            ),
          ],
        },
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      await tester.tap(find.text(tag.name));
      await tester.pump();
      expect(api.hashtagSearchesRequested, ['2024']);

      expect(controller.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      hashtagGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(InstanceSidebar), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);
      expect(api.feedPaths, isNot(contains('/tag/2024/77.json')));
      expect(api.topicsOpened, isEmpty);
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
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(find.text('design,'), findsOneWidget);
      expect(find.textContaining(longName), findsOneWidget);
      expect(find.text('support'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long category name ellipsizes instead of overflowing', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': latest},
        categoryList: [
          TopicCategory(
            id: 5,
            name: 'Feature ${List.filled(30, 'requests-').join()}',
            color: '0088CC',
          ),
        ],
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('many topic tags stay inline and wrap from the row edge', (
      tester,
    ) async {
      const tags = [
        TopicTag(name: 'sea2'),
        TopicTag(name: 'sea1'),
        TopicTag(name: 'dub1'),
        TopicTag(name: 'blz-prod-eu'),
        TopicTag(name: 'blz-prod-us'),
        TopicTag(name: 'dub2'),
        TopicTag(name: 'sjc6'),
        TopicTag(name: 'dev-alert'),
        TopicTag(name: 'cdck-prod-meta'),
        TopicTag(name: 'yyz2'),
        TopicTag(name: 'agc-prod-us'),
        TopicTag(name: 'sea3'),
        TopicTag(name: 'yyz1'),
        TopicTag(name: 'epic-prod-us2'),
      ];
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': [
            const Topic(
              id: 3,
              title: 'A heavily tagged topic',
              slug: 'a-heavily-tagged-topic',
              categoryId: 5,
              tags: tags,
            ),
          ],
        },
        categoryList: const [
          TopicCategory(id: 5, name: 'Alerts', color: 'E45735'),
        ],
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();

      final category = tester.getTopLeft(find.text('Alerts'));
      final tagPositions = [
        for (var index = 0; index < tags.length; index++)
          tester.getTopLeft(
            find.text(
              '${tags[index].name}${index == tags.length - 1 ? '' : ','}',
            ),
          ),
      ];

      expect(tagPositions.first.dy, closeTo(category.dy, 0.01));
      final nextRunTop = tagPositions
          .map((position) => position.dy)
          .firstWhere((top) => top > tagPositions.first.dy);
      final nextRunLeft = tagPositions
          .where((position) => position.dy == nextRunTop)
          .map((position) => position.dx)
          .reduce((left, right) => left < right ? left : right);
      final rowLeft = tester.getTopLeft(find.text('A heavily tagged topic')).dx;
      expect(nextRunTop - tagPositions.first.dy, lessThanOrEqualTo(24));
      expect(nextRunLeft, closeTo(rowLeft, 0.01));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failing list reports it instead of crashing', (
      tester,
    ) async {
      final api = FakeDiscourseApi();

      await pumpShell(tester, desktop, api: api);

      expect(find.byType(TopicListView), findsOneWidget);
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-out readers do not see account pages in the sidebar', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);

      expect(sidebarDestination('Messages'), findsNothing);
      expect(sidebarDestination('Drafts'), findsNothing);
      expect(sidebarDestination('New Topic'), findsNothing);
      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('a signed-out Messages route explains the account boundary', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': latest});

      await pumpShell(tester, desktop, api: api);
      final controller = ShellScope.read(
        tester.element(find.byType(MainContent)),
      );
      controller.selectDestination(
        const SidebarDestination(
          id: 'messages',
          label: 'Messages',
          icon: DIcons.inbox,
        ),
      );
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json']);
      expect(find.text('Sign in to view your messages'), findsOneWidget);
      expect(
        find.text(
          'Private messages are tied to your forum account and aren’t '
          'available while you’re signed out.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('messages-sign-in')), findsOneWidget);
      expect(find.text('Replace with deeper view'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('messages-sign-in')));
      await tester.pumpAndSettle();

      expect(controller.currentContent?.id, 'latest');
      expect(sidebarDestination('Messages'), findsOneWidget);
      expect(find.text('Sign in to view your messages'), findsNothing);
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

    FakeSiteTracker tracker() => FakeSiteTracker.built.first;

    Future<void> pumpWithFeeds(
      WidgetTester tester,
      FakeDiscourseApi api,
    ) async {
      await pumpShell(tester, desktop, api: api);
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

      expect(api.feedPaths, contains('/latest.json?topic_ids=99'));
      expect(find.text('Just posted'), findsOneWidget);
      expect(find.text('Welcome to the forum'), findsOneWidget);
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
      final controller = ShellController(
        instanceStore: FakeInstanceStore(twoSites),
        api: FakeDiscourseApi(feeds: {'/latest.json': onList}),
        authenticator: FakeAuthenticator(),
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
      );
      addTearDown(controller.dispose);
      await controller.load();
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

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tracker().pollNowCalls, 0);
      expect(tracker().polling, isFalse);

      // Back in front, it is asked immediately rather than waiting out a
      // backoff that started while the connection was dead.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tracker().pollNowCalls, 1);
      expect(tracker().polling, isTrue);
    });
  });

  group('live counters', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');

    final avatarBadge = find.byKey(UserMenuButton.unreadDotKey);

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

    testWidgets('the account ID is what names the counter channels', (
      tester,
    ) async {
      final tracker = await pumpConnected(tester);

      expect(tracker.userId, 7);
    });

    testWidgets('the account avatar uses a hand cursor without a hover fill', (
      tester,
    ) async {
      await pumpConnected(tester);

      final avatar = find.byKey(UserMenuButton.avatarKey);
      final inkWell = tester.widget<InkWell>(avatar);
      final material = tester.widget<Material>(
        find.ancestor(of: avatar, matching: find.byType(Material)).first,
      );
      final theme = Theme.of(tester.element(avatar));
      final cursor = inkWell.mouseCursor! as WidgetStateMouseCursor;

      expect(cursor.resolve(const {}), SystemMouseCursors.click);
      expect(
        cursor.resolve(const {WidgetState.disabled}),
        SystemMouseCursors.basic,
      );
      expect(inkWell.hoverColor, Colors.transparent);
      expect(inkWell.focusColor, theme.shell.hover);
      expect(
        inkWell.borderRadius,
        BorderRadius.circular(theme.discourseButtons.borderRadius),
      );
      expect(material.type, MaterialType.transparency);
    });

    testWidgets('the account avatar carries a legible success count', (
      tester,
    ) async {
      await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      final badge = tester.widget<Container>(avatarBadge);
      final decoration = badge.decoration! as BoxDecoration;
      final theme = Theme.of(tester.element(avatarBadge));
      final size = tester.getSize(avatarBadge);

      expect(decoration.color, theme.discourse.success);
      expect(decoration.color, isNot(theme.colorScheme.error));
      expect(size.width, greaterThanOrEqualTo(20));
      expect(size.height, greaterThanOrEqualTo(20));
      expect(
        find.descendant(of: avatarBadge, matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('a notification arriving marks the avatar', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(avatarBadge, findsNothing);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 1,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsOneWidget);
    });

    testWidgets('reading them somewhere else takes the mark away', (
      tester,
    ) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );

      expect(avatarBadge, findsOneWidget);

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 0,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsNothing);
    });

    testWidgets('the counts move with it, not just the mark', (tester) async {
      final tracker = await pumpConnected(
        tester,
        totals: const NotificationTotals(unreadNotifications: 3),
      );
      final railBadge = find.byKey(
        const ValueKey('instance-rail-badge-https://meta.discourse.org'),
      );

      expect(
        find.descendant(of: railBadge, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatarBadge, matching: find.text('3')),
        findsOneWidget,
      );

      tracker.deliverNotification(const {
        'all_unread_notifications_count': 5,
        'new_personal_messages_notifications_count': 2,
      });
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: railBadge, matching: find.text('5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: avatarBadge, matching: find.text('5')),
        findsOneWidget,
      );
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('an inactive connected forum keeps its rail count live', (
      tester,
    ) async {
      const firstUrl = 'https://meta.discourse.org';
      const secondUrl = 'https://team.discourse.org';
      final authenticator = FakeAuthenticator()
        ..keys[firstUrl] = 'meta-key'
        ..keys[secondUrl] = 'team-key';
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: me),
          instance('team.discourse.org', title: 'Team').copyWith(user: me),
        ],
        authenticator: authenticator,
      );

      final inactive = FakeSiteTracker.built.singleWhere(
        (tracker) => tracker.siteUrl == secondUrl,
      );
      expect(inactive.polling, isTrue);
      expect(avatarBadge, findsNothing);

      inactive.deliverNotification(const {
        'all_unread_notifications_count': 2,
        'new_personal_messages_notifications_count': 0,
      });
      await tester.pumpAndSettle();

      final railBadge = find.byKey(
        const ValueKey('instance-rail-badge-$secondUrl'),
      );
      expect(
        find.descendant(of: railBadge, matching: find.text('2')),
        findsOneWidget,
      );
      expect(avatarBadge, findsNothing);
    });

    testWidgets('a filling review queue marks it too', (tester) async {
      final tracker = await pumpConnected(tester);

      expect(avatarBadge, findsNothing);

      // Published on a channel of its own, and only to staff.
      tracker.deliverReviewableCounts(const {
        'reviewable_count': 4,
        'unseen_reviewable_count': 2,
      });
      await tester.pumpAndSettle();

      expect(avatarBadge, findsOneWidget);
    });

    testWidgets('a site with nobody signed in has no counters to track', (
      tester,
    ) async {
      await pumpShell(tester, desktop);
      await tester.pumpAndSettle();

      expect(FakeSiteTracker.built.first.userId, isNull);
      expect(avatarBadge, findsNothing);
    });
  });

  group('infinite scroll', () {
    final topicList = find.descendant(
      of: find.byType(TopicListView),
      matching: find.byType(SuperListView),
    );

    List<Topic> page(int from, int count) => [
      for (var i = from; i < from + count; i++)
        Topic(id: i, title: 'Topic $i', slug: 'topic-$i'),
    ];

    testWidgets('pulling past the first topic does not refetch the list', (
      tester,
    ) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': page(1, 30)});

      await pumpShell(tester, desktop, api: api);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, 1200));
      await tester.pumpAndSettle();

      expect(api.feedPaths, ['/latest.json']);
    });

    testWidgets('reaching the end appends the next page', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
          '/latest.json?page=1': page(31, 30),
        },
        nextPages: {'/latest.json': '/latest?page=1'},
      );

      await pumpShell(tester, desktop, api: api);
      expect(find.text('Topic 1'), findsOneWidget);
      expect(api.feedPaths, ['/latest.json']);

      await tester.drag(topicList, const Offset(0, -6000));
      await tester.pumpAndSettle();

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
      expect(controller.currentFeed?.topicIds, hasLength(6));
    });

    testWidgets('a topic repeated across pages is not duplicated', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {
          '/latest.json': page(1, 30),
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
        forumTabs: FakeForumTabStore(),
        initialRootMode: ShellRootMode.forum,
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pump();

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
      Map<int, List<int>> gapsBefore = const {},
      Map<int, List<int>> gapsAfter = const {},
      TopicRecommendations? recommendations,
      TopicNotificationLevel notificationLevel = TopicNotificationLevel.normal,
      bool pinned = false,
      bool unpinned = false,
      bool pinnedGlobally = false,
      bool closed = false,
      bool archived = false,
      bool visible = true,
      bool canCloseTopic = false,
      bool canArchiveTopic = false,
      bool canToggleTopicVisibility = false,
      bool canDeleteTopic = false,
      bool canRecoverTopic = false,
      bool canFlagTopic = false,
      bool canCreatePost = false,
      List<PostActionSummary> topicActions = const [],
      List<Bookmark> bookmarks = const [],
    }) => topicPayload(
      id: 7,
      title: 'A real topic',
      posts: [post(1, 1, 'First post body')],
      stream: stream,
      gapsBefore: gapsBefore,
      gapsAfter: gapsAfter,
      recommendations: recommendations,
      notificationLevel: notificationLevel,
      pinned: pinned,
      unpinned: unpinned,
      pinnedGlobally: pinnedGlobally,
      closed: closed,
      archived: archived,
      visible: visible,
      canCloseTopic: canCloseTopic,
      canArchiveTopic: canArchiveTopic,
      canToggleTopicVisibility: canToggleTopicVisibility,
      canDeleteTopic: canDeleteTopic,
      canRecoverTopic: canRecoverTopic,
      canFlagTopic: canFlagTopic,
      canCreatePost: canCreatePost,
      topicActions: topicActions,
      bookmarks: bookmarks,
    );

    TopicRecommendations suggestedRecommendations(Topic topic) =>
        TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [topic],
            ),
          ],
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
      expect(find.byType(InlineTopicTitleEditor), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-header-title-field')),
        findsNothing,
      );
      expect(renderedText('First post body'), findsOneWidget);
      expect(renderedText('<p>'), findsNothing);
    });

    testWidgets(
      'editable topic header saves title and preserves topic metadata',
      (tester) async {
        const tags = [
          TopicTag(id: 8, name: 'design'),
          TopicTag(id: 9, name: 'mobile'),
        ];
        final base = topicPayload(
          id: 7,
          title: 'A real topic',
          posts: [post(1, 1, 'First post body')],
          categoryId: 5,
          tags: tags,
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (detail: base.detail.copyWith(canEdit: true), posts: base.posts),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final editor = find.byType(InlineTopicTitleEditor);
        final field = find.byKey(const ValueKey('topic-header-title-field'));
        expect(editor, findsOneWidget);
        expect(field, findsOneWidget);
        expect(
          tester
              .widget<MouseRegion>(
                find.byKey(const ValueKey('topic-header-title-pointer')),
              )
              .cursor,
          SystemMouseCursors.text,
        );

        final editorRect = tester.getRect(editor);
        await tester.tapAt(Offset(editorRect.left + 1, editorRect.center.dy));
        await tester.pump();
        var textField = tester.widget<TextField>(field);
        expect(textField.focusNode?.hasFocus, isTrue);
        expect(textField.controller?.selection.baseOffset, 0);

        await tester.enterText(field, '  Renamed topic  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(api.topicsUpdated, [
          {
            'topicId': 7,
            'title': 'Renamed topic',
            'originalTitle': 'A real topic',
            'categoryId': 5,
            'tags': tags,
            'originalTags': tags,
          },
        ]);
        final shell = ShellScope.read(tester.element(find.byType(TopicView)));
        expect(shell.currentTopic?.title, 'Renamed topic');
        expect(shell.currentContent?.title, 'Renamed topic');
        expect(find.byType(ComposerPanel), findsNothing);
        textField = tester.widget<TextField>(field);
        expect(textField.focusNode?.hasFocus, isFalse);

        await tester.tap(field);
        await tester.enterText(field, ' Renamed topic ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(api.topicsUpdated, hasLength(1));
        expect(
          tester.widget<TextField>(field).controller?.text,
          'Renamed topic',
        );

        await tester.tap(field);
        await tester.enterText(field, '');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        textField = tester.widget<TextField>(field);
        expect(api.topicsUpdated, hasLength(1));
        expect(textField.controller?.text, '');
        expect(textField.focusNode?.hasFocus, isTrue);
        expect(find.text('A topic title is required.'), findsOneWidget);
      },
    );

    testWidgets(
      'lays the header across the floating sidebar and keeps actions ordered',
      (tester) async {
        const longTitle =
            'Chris weekly update for 2026 with roadmap decisions, operational '
            'priorities, cross-team blockers, and every next step we agreed on';
        final plugins = PluginData.none.withValue(
          assignmentsDataKey,
          Assignments(
            canAssign: true,
            direct: const Assignment(
              assignee: AssignmentUser(username: 'sam', name: 'Sam Example'),
            ),
          ),
        );
        final tags = [
          for (final name in const [
            'weekly-update',
            '2026',
            'team',
            'async',
            'roadmap',
            'priorities',
          ])
            TopicTag(name: name),
        ];
        final api = FakeDiscourseApi(
          feeds: {
            '/latest.json': [
              const Topic(id: 7, title: longTitle, slug: 'weekly-update'),
            ],
          },
          categoryList: const [
            TopicCategory(id: 5, name: 'Announcements', color: '7C3AED'),
          ],
          topics: {
            7: topicPayload(
              id: 7,
              title: longTitle,
              posts: [post(1, 1, 'First post body')],
              categoryId: 5,
              tags: tags,
              canCreatePost: true,
              notificationLevel: TopicNotificationLevel.tracking,
              plugins: plugins,
            ),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(find.text(longTitle));
        await tester.pumpAndSettle();

        final header = find.byKey(const ValueKey('topic-content-header'));
        final title = find.byKey(const ValueKey('topic-header-title'));
        final sidebarToggle = find.byKey(
          const ValueKey('topic-sidebar-toggle'),
        );
        final notificationLevel = find.byKey(
          const ValueKey('topic-notification-level-button'),
        );
        final bookmark = find.byKey(const ValueKey('topic-bookmark-button'));
        final share = find.byKey(const ValueKey('topic-share-button'));
        final more = find.byKey(const ValueKey('topic-status-button'));
        expect(header, findsOneWidget);
        expect(title, findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.byTooltip('Back')),
          findsOneWidget,
        );
        final titleWidget = tester.widget<TopicTitle>(title);
        expect(titleWidget.maxLines, 1);
        expect(titleWidget.overflow, TextOverflow.ellipsis);
        final titleTooltip = tester.widget<Tooltip>(
          find.ancestor(of: title, matching: find.byType(Tooltip)),
        );
        expect(titleTooltip.message, longTitle);
        expect(tester.getSize(title).height, lessThan(30));
        expect(
          find.byKey(const ValueKey('topic-header-metadata')),
          findsNothing,
        );
        expect(
          find.descendant(of: header, matching: sidebarToggle),
          findsOneWidget,
        );
        expect(
          find.descendant(of: header, matching: notificationLevel),
          findsOneWidget,
        );
        expect(find.descendant(of: header, matching: bookmark), findsOneWidget);
        expect(find.descendant(of: header, matching: share), findsOneWidget);
        expect(
          find.descendant(of: share, matching: find.dIcon(DIcons.link)),
          findsOneWidget,
        );
        expect(
          find.descendant(of: share, matching: find.text('Share')),
          findsNothing,
        );
        expect(find.descendant(of: header, matching: more), findsOneWidget);
        expect(
          find.descendant(of: header, matching: find.text('Tracking')),
          findsNothing,
        );

        final sidebar = find.byKey(const ValueKey('topic-sidebar-panel'));
        final sidebarSurface = find.byKey(
          const ValueKey('topic-sidebar-surface'),
        );
        final properties = find.byKey(const ValueKey('topic-properties-card'));
        expect(sidebar, findsOneWidget);
        expect(
          find.descendant(of: sidebar, matching: sidebarToggle),
          findsNothing,
        );
        final topicRect = tester.getRect(find.byType(TopicView));
        final sidebarRect = tester.getRect(sidebar);
        final headerRect = tester.getRect(header);
        final surfaceRect = tester.getRect(sidebarSurface);
        final titleRect = tester.getRect(title);
        final toggleRect = tester.getRect(sidebarToggle);
        final notificationRect = tester.getRect(notificationLevel);
        final bookmarkRect = tester.getRect(bookmark);
        final shareRect = tester.getRect(share);
        final replyButton = find.byKey(const ValueKey('topic-reply-button'));
        final replyRect = tester.getRect(replyButton);
        expect(
          tester.widget<DButton>(replyButton).alignment,
          Alignment.centerLeft,
        );
        final moreRect = tester.getRect(more);
        expect(sidebarRect.top, headerRect.bottom);
        expect(sidebarRect.bottom, topicRect.bottom);
        expect(headerRect.left, topicRect.left);
        expect(headerRect.right, topicRect.right);
        expect(surfaceRect, sidebarRect);
        expect(
          tester.widget<Padding>(sidebarSurface).padding,
          const EdgeInsets.fromLTRB(12, 12, 12, 16),
        );
        final sidebarScroll = find.byKey(
          const ValueKey('topic-sidebar-scroll-view'),
        );
        expect(
          find.descendant(of: sidebar, matching: sidebarScroll),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: properties),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: replyButton),
          findsOneWidget,
        );
        expect(
          tester.getRect(find.byType(SuperListView)).right,
          topicRect.right,
        );
        expect(
          tester.widget<SuperListView>(find.byType(SuperListView)).padding,
          const EdgeInsets.only(right: 344),
        );
        expect(titleRect.right, lessThanOrEqualTo(moreRect.left));
        expect(shareRect.right, lessThanOrEqualTo(bookmarkRect.left));
        expect(bookmarkRect.right, lessThanOrEqualTo(notificationRect.left));
        expect(notificationRect.right, lessThanOrEqualTo(toggleRect.left));
        expect(headerRect.right - toggleRect.right, lessThanOrEqualTo(8.1));
        expect(replyRect.left, greaterThan(surfaceRect.left));
        expect(replyRect.right, lessThan(surfaceRect.right));
        expect(
          find.descendant(of: more, matching: find.dIcon(DIcons.ellipsis)),
          findsOneWidget,
        );
        expect(properties, findsOneWidget);
        expect(
          find.descendant(of: properties, matching: find.text('Announcements')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-tags-edit-indicator')),
          findsNothing,
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('topic-sidebar-category-color')),
          ),
          const Size.square(9),
        );
        for (final tag in tags) {
          final tagPill = find.byKey(ValueKey(('topic-sidebar-tag', tag.name)));
          expect(
            find.descendant(of: properties, matching: tagPill),
            findsOneWidget,
          );
          final tagText = tester.widget<Text>(
            find.descendant(of: tagPill, matching: find.text(tag.name)),
          );
          expect(
            tagText.style?.fontSize,
            Theme.of(tester.element(tagPill)).textTheme.labelSmall?.fontSize,
          );
          expect(
            find.descendant(
              of: tagPill,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).shape ==
                        BoxShape.circle,
              ),
            ),
            findsNothing,
          );
        }
        final topicAssignment = find.byKey(const Key('assign-topic-property'));
        expect(
          find.descendant(of: properties, matching: topicAssignment),
          findsNothing,
        );
        expect(
          find.descendant(of: sidebarScroll, matching: topicAssignment),
          findsOneWidget,
        );
        expect(find.text('Assignments'), findsOneWidget);
        expect(find.text('Topic · Sam Example'), findsOneWidget);
        expect(
          tester.getRect(topicAssignment).top,
          greaterThan(tester.getRect(properties).bottom),
        );

        expect(
          find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('topic-reply-button')),
          ),
          findsNothing,
        );
        expect(find.descendant(of: sidebar, matching: more), findsNothing);
        expect(find.descendant(of: header, matching: more), findsOneWidget);
        expect(
          find.descendant(
            of: sidebar,
            matching: find.byKey(const ValueKey('topic-reply-button')),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sidebar, matching: notificationLevel),
          findsNothing,
        );
        expect(find.descendant(of: sidebar, matching: bookmark), findsNothing);
        expect(find.text('Topic context'), findsNothing);
        expect(find.text('Actions'), findsNothing);
        expect(find.text('Properties'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('keeps the pinned sidebar outside the topic scroll view', (
      tester,
    ) async {
      final longBody = List.generate(
        80,
        (index) => 'Scrollable post line $index',
      ).join('<br>');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [post(1, 1, longBody)],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final topicView = find.byType(TopicView);
      final sidebar = find.byKey(const ValueKey('topic-sidebar-panel'));
      final verticalScrollables = find.descendant(
        of: topicView,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down,
        ),
      );
      expect(verticalScrollables, findsNWidgets(2));
      expect(
        find.descendant(
          of: sidebar,
          matching: find.byKey(const ValueKey('topic-sidebar-scroll-view')),
        ),
        findsOneWidget,
      );
      final sidebarRect = tester.getRect(sidebar);
      final postStream = tester.widget<SuperListView>(
        find.byType(SuperListView),
      );

      await tester.drag(find.byType(SuperListView), const Offset(0, -500));
      await tester.pumpAndSettle();

      expect(postStream.controller!.position.pixels, greaterThan(0));
      expect(tester.getRect(sidebar), sidebarRect);
    });

    testWidgets(
      'scrolls the maximum assignment card together with sidebar actions',
      (tester) async {
        final plugins = PluginData.none.withValue(
          assignmentsDataKey,
          Assignments(
            canAssign: false,
            postAssignments: {
              for (var id = 2; id <= Assignments.maximumPerTopic + 1; id++)
                id: Assignment(
                  assignee: AssignmentUser(
                    username: 'assignee-$id',
                    name: 'Assignee $id',
                  ),
                  postId: id,
                  postNumber: id,
                ),
            },
          ),
        );
        const recommendations = TopicRecommendations(
          sources: [
            TopicRecommendationSource(
              definition: coreSuggestedTopicRecommendationSource,
              topics: [
                Topic(id: 8, title: 'Reachable related topic', slug: 'related'),
              ],
            ),
          ],
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A real topic',
              posts: [post(1, 1, 'First post body')],
              canCreatePost: true,
              recommendations: recommendations,
              plugins: plugins,
            ),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();

        final sidebarScroll = find.byKey(
          const ValueKey('topic-sidebar-scroll-view'),
        );
        final reply = find.byKey(const ValueKey('topic-reply-button'));
        final moreTopics = find.text('More topics');
        final sidebarScrollable = find.descendant(
          of: sidebarScroll,
          matching: find.byType(Scrollable),
        );
        final sidebarPosition = tester
            .state<ScrollableState>(sidebarScrollable)
            .position;
        final postPosition = tester
            .widget<SuperListView>(find.byType(SuperListView))
            .controller!
            .position;
        final replyRect = tester.getRect(reply);
        final postPixels = postPosition.pixels;

        expect(sidebarPosition.maxScrollExtent, greaterThan(0));
        expect(
          find.descendant(of: sidebarScroll, matching: reply),
          findsOneWidget,
        );
        expect(reply.hitTestable(), findsOneWidget);
        expect(moreTopics.hitTestable(), findsNothing);

        await tester.drag(sidebarScroll, const Offset(0, -5000));
        await tester.pumpAndSettle();

        expect(sidebarPosition.pixels, greaterThan(0));
        expect(moreTopics.hitTestable(), findsOneWidget);
        expect(reply.hitTestable(), findsNothing);
        expect(tester.getRect(reply).top, lessThan(replyRect.top));
        expect(postPosition.pixels, postPixels);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('uses a thin scrollbar for topic posts', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();

        final scrollbar = find.descendant(
          of: find.byType(SuperListView),
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

    testWidgets('promotes sharing and overflows administrative actions', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 1, username: 'reader');
      const spam = PostFlagType(
        id: 8,
        nameKey: 'spam',
        name: 'Spam',
        description: 'Promotional content',
        appliesTo: ['Topic'],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            pinned: true,
            canCloseTopic: true,
            canFlagTopic: true,
            canCreatePost: true,
            topicActions: const [PostActionSummary(id: 8, canAct: true)],
          ),
        },
        categoryPostActionCatalog: const SitePostActionCatalog(
          topicFlags: [spam],
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      for (final tooltip in [
        'Share topic',
        'Bookmark this topic',
        'More topic actions',
        'Topic notifications',
        'Reply to this topic',
      ]) {
        final trigger = find.byTooltip(tooltip);
        expect(trigger, findsOneWidget, reason: tooltip);
        final button = find.ancestor(
          of: trigger,
          matching: find.byType(DButton),
        );
        expect(button, findsOneWidget, reason: tooltip);
      }

      expect(find.byTooltip('Flag this topic'), findsNothing);
      expect(find.byTooltip('Pinned topic options'), findsNothing);

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();

      expect(find.text('Share topic'), findsNothing);
      expect(find.text('Flag topic'), findsOneWidget);
      expect(find.text('Unpin topic'), findsOneWidget);
      expect(find.text('Close topic'), findsOneWidget);
    });

    testWidgets(
      'sidebar taxonomy values show subcategory parents and navigate',
      (tester) async {
        const parent = TopicCategory(
          id: 4,
          name: 'Trust and safety',
          color: '7C3AED',
          slug: 'trust-and-safety',
        );
        const category = TopicCategory(
          id: 5,
          name: 'Security',
          color: 'EC4899',
          slug: 'security',
          parentCategoryId: 4,
        );
        final categoryPath = topicCategoryPathLabel(category, parent: parent);
        const tag = TopicTag(name: 'security / fix');
        const reader = DiscourseUser(id: 1, username: 'reader');
        final base = topicPayload(
          id: 7,
          title: 'A real topic',
          posts: [post(1, 1, 'First post body')],
          categoryId: category.id,
          tags: const [tag],
        );
        final api = FakeDiscourseApi(
          user: reader,
          feeds: {
            '/latest.json': listed,
            '/c/trust-and-safety/security/5.json': const [],
            '/topics/private-messages-tags/reader/'
                    'security%20%2F%20fix.json':
                const [],
          },
          categoryList: const [parent, category],
          topics: {
            7: (
              detail: base.detail.copyWith(
                canEdit: true,
                canEditTags: true,
                privateMessage: true,
              ),
              posts: base.posts,
            ),
          },
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('topic-sidebar-tags-edit-indicator')),
          findsOneWidget,
        );
        expect(find.byTooltip('Edit topic category'), findsOneWidget);
        expect(find.byTooltip('Edit topic tags'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('topic-sidebar-category')),
            matching: find.text(categoryPath),
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Category: $categoryPath'),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('topic-sidebar-category-action')),
              )
              .height,
          greaterThanOrEqualTo(32),
        );
        expect(
          tester.getSize(find.bySemanticsLabel('Tag: ${tag.name}')).height,
          greaterThanOrEqualTo(32),
        );
        expect(
          tester.getSize(
            find.byKey(const ValueKey('topic-sidebar-category-edit-action')),
          ),
          const Size.square(32),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('topic-sidebar-add-tag'))),
          const Size.square(32),
        );

        final controller = ShellScope.read(
          tester.element(find.byType(TopicView)),
        );
        await tester.tap(find.byKey(const ValueKey('topic-sidebar-category')));
        await tester.pumpAndSettle();

        expect(controller.currentContent?.id, 'category-5');
        expect(
          controller.currentContent?.feedPath,
          '/c/trust-and-safety/security/5.json',
        );
        expect(
          find.byKey(const ValueKey('topic-category-picker-popover')),
          findsNothing,
        );

        expect(controller.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(('topic-sidebar-tag', tag.name))));
        await tester.pumpAndSettle();

        expect(
          controller.currentContent?.id,
          'list-/topics/private-messages-tags/reader/'
          'security%20%2F%20fix.json',
        );
        expect(
          controller.currentContent?.feedPath,
          '/topics/private-messages-tags/reader/'
          'security%20%2F%20fix.json',
        );
        expect(
          find.byKey(const ValueKey('topic-tag-picker-popover')),
          findsNothing,
        );
        expect(api.topicsUpdated, isEmpty);
        expect(api.topicTagsUpdated, isEmpty);
      },
    );

    testWidgets(
      'uncategorized sidebar picker server-searches and saves a subcategory',
      (tester) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          const support = TopicCategory(
            id: 5,
            name: 'Support',
            color: '0088CC',
            permission: 1,
          );
          const supportDocs = TopicCategory(
            id: 6,
            name: 'Support docs',
            color: '00AEEF',
            parentCategoryId: 5,
          );
          final supportDocsPath = topicCategoryPathLabel(
            supportDocs,
            parent: support,
          );
          final base = detail();
          final api = FakeDiscourseApi(
            feeds: {'/latest.json': listed},
            categoryList: const [support],
            categorySearches: const {
              '': [support],
              'support': [support],
              'docs': [supportDocs],
            },
            topics: {
              7: (
                detail: base.detail.copyWith(canEdit: true),
                posts: base.posts,
              ),
            },
          );
          const reader = DiscourseUser(id: 1, username: 'reader');
          final authenticator = FakeAuthenticator()
            ..keys['https://meta.discourse.org'] = 'meta-key';

          await pumpShell(
            tester,
            desktop,
            instances: [instance('meta.discourse.org').copyWith(user: reader)],
            api: api,
            authenticator: authenticator,
          );
          await tester.tap(contentText('A real topic'));
          await tester.pumpAndSettle();

          final categoryProperty = find.byKey(
            const ValueKey('topic-sidebar-category-property'),
          );
          expect(categoryProperty, findsOneWidget);
          expect(find.byTooltip('Edit topic category'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-sidebar-category-edit-indicator')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: categoryProperty,
              matching: find.text('Uncategorized'),
            ),
            findsOneWidget,
          );

          final categoryAction = find.byKey(
            const ValueKey('topic-sidebar-category-edit-action'),
          );
          expect(categoryAction, findsOneWidget);
          final categoryInk = find.descendant(
            of: categoryAction,
            matching: find.byType(InkWell),
          );
          expect(categoryInk, findsOneWidget);
          expect(
            tester.widget<InkWell>(categoryInk).mouseCursor,
            SystemMouseCursors.click,
          );
          expect(
            tester.widget<InkWell>(categoryInk).hoverColor,
            Colors.transparent,
          );
          expect(
            tester.getSize(categoryAction).width,
            lessThan(tester.getSize(categoryProperty).width),
          );

          await tester.tap(categoryAction);
          await tester.pumpAndSettle();

          expect(find.byType(ComposerPanel), findsNothing);
          expect(find.byType(Dialog), findsNothing);
          expect(find.byType(BottomSheet), findsNothing);
          final picker = find.byKey(
            const ValueKey('topic-category-picker-popover'),
          );
          expect(picker, findsOneWidget);
          expect(
            find.descendant(
              of: picker,
              matching: find.byKey(
                const ValueKey('topic-category-picker-query'),
              ),
            ),
            findsOneWidget,
          );
          expect(tester.getSize(picker).width, 252);
          final categoryQuery = find.byKey(
            const ValueKey('topic-category-picker-query'),
          );
          expect(
            tester.widget<TextField>(categoryQuery).style?.fontSize,
            DiscourseTypography.fontDown1,
          );
          expect(
            tester.getSize(categoryQuery).height,
            inInclusiveRange(34, 42),
          );
          final categoryDivider = find.byKey(
            const ValueKey('topic-category-picker-divider'),
          );
          expect(
            tester.getSize(categoryDivider).width,
            tester.getSize(picker).width - 2,
          );
          final supportOption = find.byKey(
            const ValueKey('topic-category-option-5'),
          );
          expect(supportOption, findsOneWidget);
          final supportTile = tester.widget<ListTile>(
            find.descendant(of: supportOption, matching: find.byType(ListTile)),
          );
          expect(supportTile.minTileHeight, 32);
          expect(
            supportTile.titleTextStyle?.fontSize,
            DiscourseTypography.fontDown1,
          );
          await tester.enterText(categoryQuery, 'support');
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          expect(supportOption, findsOneWidget);
          expect(
            find.byKey(const ValueKey('topic-category-option-6')),
            findsNothing,
          );
          await tester.enterText(categoryQuery, 'docs');
          await tester.pump(const Duration(milliseconds: 250));
          await tester.pumpAndSettle();
          final supportDocsOption = find.byKey(
            const ValueKey('topic-category-option-6'),
          );
          final supportDocsTile = tester.widget<ListTile>(
            find.descendant(
              of: supportDocsOption,
              matching: find.byType(ListTile),
            ),
          );
          expect(
            supportDocsTile.contentPadding,
            const EdgeInsets.only(left: 26, right: 10),
          );
          expect(
            find.descendant(
              of: supportDocsOption,
              matching: find.text(supportDocsPath),
            ),
            findsOneWidget,
          );
          expect(api.categoryPagesRequested, isNot(contains(2)));
          expect(api.categorySearchTerms, ['', 'support', 'docs']);
          await tester.tap(
            find.byKey(const ValueKey('topic-category-option-6')),
          );
          await tester.pumpAndSettle();

          expect(api.topicsUpdated.single, {
            'topicId': 7,
            'title': 'A real topic',
            'originalTitle': 'A real topic',
            'categoryId': 6,
            'tags': const <TopicTag>[],
            'originalTags': const <TopicTag>[],
          });
          expect(api.topicTagsUpdated, isEmpty);
          expect(
            find.descendant(
              of: categoryProperty,
              matching: find.text(supportDocsPath),
            ),
            findsOneWidget,
          );
          expect(picker, findsNothing);
          expect(find.byType(ComposerPanel), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      },
    );

    testWidgets('empty editable sidebar tags open a popover and save a tag', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const design = TopicTag(id: 8, name: 'design');
        const mobile = TopicTag(id: 9, name: 'mobile');
        final base = detail();
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (
              detail: base.detail.copyWith(canEditTags: true),
              posts: base.posts,
            ),
          },
          composerCapabilities: const TopicComposerCapabilities(
            canTagTopics: true,
            maxTagsPerTopic: 5,
          ),
          topicTagSearches: const {
            '': TopicTagSearch(tags: [design, mobile]),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final tagsProperty = find.byKey(
          const ValueKey('topic-sidebar-tags-property'),
        );
        final addTag = find.byKey(const ValueKey('topic-sidebar-add-tag'));
        expect(tagsProperty, findsOneWidget);
        expect(find.byTooltip('Add tag'), findsOneWidget);
        expect(find.text('Add tag'), findsOneWidget);
        expect(addTag, findsOneWidget);
        expect(tester.getSize(addTag).height, lessThan(24));
        expect(
          tester.getSize(addTag).width,
          lessThan(tester.getSize(tagsProperty).width * 0.75),
        );
        expect(
          tester.getCenter(find.text('Tags')).dy,
          closeTo(tester.getCenter(addTag).dy, 1),
        );

        final tagsRect = tester.getRect(tagsProperty);
        await tester.tapAt(Offset(tagsRect.left + 12, tagsRect.center.dy));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-tag-picker-popover')),
          findsNothing,
        );

        await tester.tap(addTag);
        await tester.pumpAndSettle();

        final picker = find.byKey(const ValueKey('topic-tag-picker-popover'));
        expect(picker, findsOneWidget);
        expect(tester.getSize(picker).width, 252);

        final query = find.byKey(const ValueKey('topic-tag-picker-query'));
        final queryWidget = tester.widget<TextField>(query);
        expect(queryWidget.style?.fontSize, DiscourseTypography.fontDown1);
        expect(tester.getSize(query).height, inInclusiveRange(34, 42));

        final divider = find.descendant(
          of: picker,
          matching: find.byKey(const ValueKey('topic-tag-picker-divider')),
        );
        expect(divider, findsOneWidget);
        expect(tester.getSize(divider).width, tester.getSize(picker).width - 2);

        expect(
          find.descendant(of: picker, matching: find.dIcon(DIcons.tag)),
          findsNothing,
        );
        expect(find.byType(ComposerPanel), findsNothing);
        expect(
          find.descendant(
            of: picker,
            matching: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
          ),
          findsOneWidget,
        );
        final mobileOption = tester.widget<ListTile>(
          find.descendant(
            of: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
            matching: find.byType(ListTile),
          ),
        );
        expect(mobileOption.minTileHeight, 32);
        expect(
          mobileOption.titleTextStyle?.fontSize,
          DiscourseTypography.fontDown1,
        );
        expect((mobileOption.leading! as Row).children, hasLength(1));
        await tester.tap(
          find.descendant(
            of: picker,
            matching: find.byKey(
              const ValueKey(('topic-tag-picker-option', 'mobile')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated.single, {
          'topicId': 7,
          'tags': const [mobile],
        });
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'mobile'))),
          findsOneWidget,
        );
        expect(find.text('mobile'), findsOneWidget);
        expect(picker, findsNothing);
        expect(find.byType(ComposerPanel), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('sidebar tag popover creates and removes tags', (tester) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        const design = TopicTag(id: 8, name: 'design');
        final base = detail();
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: (
              detail: base.detail.copyWith(
                canEditTags: true,
                tags: const [design],
              ),
              posts: base.posts,
            ),
          },
          composerCapabilities: const TopicComposerCapabilities(
            canTagTopics: true,
            canCreateTag: true,
            tagsFilterRegexp:
                r'''[\/\?#\[\]@!\$&'\(\)\*\+,;=%\\`^\s|\{\}"<>]+''',
            maxTagLength: 20,
            maxTagsPerTopic: 5,
          ),
          topicTagSearches: const {
            '': TopicTagSearch(tags: [design]),
            'mobile': TopicTagSearch(),
          },
        );
        const reader = DiscourseUser(id: 1, username: 'reader');
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        final addTag = find.byKey(const ValueKey('topic-sidebar-add-tag'));
        await tester.tap(addTag);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('topic-tag-picker-query')),
          'mobile',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Create new tag: “mobile”'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('topic-tag-picker-create')));
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated.single, {
          'topicId': 7,
          'tags': const [design, TopicTag(name: 'mobile')],
        });
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'mobile'))),
          findsOneWidget,
        );

        await tester.tap(addTag);
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey(('topic-tag-picker-option', 'design'))),
        );
        await tester.pumpAndSettle();

        expect(api.topicTagsUpdated, hasLength(2));
        expect(api.topicTagsUpdated.last, {
          'topicId': 7,
          'tags': const [TopicTag(name: 'mobile')],
        });
        expect(
          find.byKey(const ValueKey(('topic-sidebar-tag', 'design'))),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    });

    testWidgets('only a topic bookmark gives its action the core accent', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 1, username: 'reader');
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      Future<DButtonVariant> bookmarkVariant(Bookmark bookmark) async {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: detail(bookmarks: [bookmark]),
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: [instance('meta.discourse.org').copyWith(user: reader)],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();
        return tester
            .widget<DButton>(
              find.byKey(const ValueKey('topic-bookmark-button')),
            )
            .variant;
      }

      expect(
        await bookmarkVariant(const Bookmark(id: 1, bookmarkableType: 'Topic')),
        DButtonVariant.transparentPrimary,
      );
      expect(
        await bookmarkVariant(const Bookmark(id: 2, bookmarkableType: 'Post')),
        DButtonVariant.flat,
      );
    });

    testWidgets('offers copy and system share for core’s canonical link', (
      tester,
    ) async {
      final copied = watchClipboard(tester);
      const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
      final shares = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        shares.add(call);
        return 'test-share-target';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      const reader = DiscourseUser(username: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        user: reader,
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: reader, config: const SiteConfig.unknown()),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-share-button')));
      await tester.pumpAndSettle();

      const url = 'https://meta.discourse.org/t/a-real-topic/7?u=reader';
      expect(find.text('Share this topic'), findsOneWidget);
      expect(find.text(url), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-share-copy')));
      await tester.pumpAndSettle();
      expect(copied, [url]);

      await tester.tap(find.byKey(const ValueKey('topic-share-system')));
      await tester.pumpAndSettle();
      expect(shares, hasLength(1));
      expect(shares.single.method, 'share');
      expect((shares.single.arguments as Map)['text'], url);
      expect((shares.single.arguments as Map)['subject'], 'A real topic');
    });

    testWidgets('post sharing targets that post and can continue elsewhere', (
      tester,
    ) async {
      const reader = DiscourseUser(id: 7, username: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            canCreatePost: true,
            canReplyAsNewTopic: true,
            posts: [
              post(1, 1, 'First post body'),
              post(2, 2, 'Second post body'),
            ],
          ),
        },
        user: reader,
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: reader, config: const SiteConfig.unknown()),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(renderedText('Second post body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Share this post');
      await tester.pumpAndSettle();

      expect(find.text('Share post #2'), findsOneWidget);
      expect(
        find.text('https://meta.discourse.org/t/a-real-topic/7/2?u=reader'),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('topic-share-reply-as-new-topic')),
      );
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.visibleComposer, isNotNull);
      expect(
        shell.visibleComposer?.raw,
        'Continue the discussion from [A real topic]'
        '(https://meta.discourse.org/t/a-real-topic/7/2)',
      );
    });

    testWidgets('a permitted reader can flag the whole topic', (tester) async {
      const spam = PostFlagType(
        id: 8,
        nameKey: 'spam',
        name: 'Spam',
        description: '<p>This topic is promotional.</p>',
        appliesTo: ['Topic'],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            canFlagTopic: true,
            topicActions: const [PostActionSummary(id: 8, canAct: true)],
          ),
        },
        categoryPostActionCatalog: const SitePostActionCatalog(
          topicFlags: [spam],
        ),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
          ).copyWith(user: const DiscourseUser(id: 1, username: 'reader')),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Flag topic'));
      await tester.pumpAndSettle();

      expect(find.text('Spam'), findsOneWidget);
      expect(renderedText('This topic is promotional.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('post-flag-submit')));
      await tester.pumpAndSettle();

      expect(api.topicFlagsCreated, [
        (topicId: 7, postActionTypeId: 8, message: null),
      ]);
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      expect(find.text('Flag topic'), findsNothing);
    });

    testWidgets('shows the web topic map beneath the opening post', (
      tester,
    ) async {
      final posts = [
        post(1, 1, 'First post body'),
        post(2, 2, 'Second post body'),
        post(3, 3, 'Third post body'),
        post(4, 4, 'Fourth post body'),
      ];
      const participants = [
        TopicParticipant(username: 'sam', name: 'Sam'),
        TopicParticipant(username: 'lee', name: 'Lee'),
        TopicParticipant(username: 'pat', name: 'Pat'),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: posts,
            views: 218,
            likeCount: 9,
            participantCount: 6,
            wordCount: 2500,
            participants: participants,
            links: const [
              TopicMapLink(
                url: 'https://discourse.org',
                title: 'Discourse homepage',
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-map')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-views')), findsOneWidget);
      expect(find.text('218'), findsOneWidget);
      expect(find.text('views'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-likes')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-links')), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-map-users')), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-map-links')));
      await tester.pumpAndSettle();
      expect(find.text('Discourse homepage'), findsOneWidget);
    });

    testWidgets('shows a hand cursor and expands reflected post links', (
      tester,
    ) async {
      final links = [
        for (var index = 1; index <= 6; index++)
          PostInboundLink(
            url: '/t/source-$index/$index',
            title: 'Source $index',
          ),
        const PostInboundLink(url: '/t/duplicate/99', title: 'Source 1'),
      ];
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
                username: 'joffreyj',
                cooked: '<p>First post body</p>',
                inboundLinks: links,
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('Source 1'), findsOneWidget);
      expect(find.text('Source 5'), findsOneWidget);
      expect(find.text('Source 6'), findsNothing);
      expect(find.text('1 more link'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.ancestor(
                of: find.text('Source 1'),
                matching: find.byType(InkWell),
              ),
            )
            .mouseCursor,
        SystemMouseCursors.click,
      );

      await tester.tap(find.text('1 more link'));
      await tester.pumpAndSettle();

      expect(find.text('Source 6'), findsOneWidget);
      expect(find.text('Source 1'), findsOneWidget);
    });

    testWidgets('renders site emoji in reflected post link titles', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(name: 'mega', url: '/images/emoji/mega.png'),
          ],
        },
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked: '<p>First post body</p>',
                inboundLinks: [
                  PostInboundLink(
                    url: '/t/weekly-updates/99',
                    title: "Keegan's Weekly Updates (2025) :mega:",
                  ),
                ],
              ),
            ],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      _replaceEmojiCache(
        EmojiCache(
          client: MockClient((_) async => http.Response.bytes(emojiPng, 200)),
        ),
      );

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final emoji = tester.widget<SiteEmojiImage>(find.byType(SiteEmojiImage));
      expect(emoji.name, 'mega');
      expect(
        find.bySemanticsLabel("Keegan's Weekly Updates (2025) :mega:"),
        findsOneWidget,
      );
    });

    testWidgets('summarizes top replies and restores the complete stream', (
      tester,
    ) async {
      final first = post(1, 1, 'First post body');
      final second = post(2, 2, 'Ordinary reply');
      final top = post(3, 3, 'Top reply');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [first, second, top],
            hasSummary: true,
          ),
        },
        summaryTopics: {
          7: topicPayload(id: 7, title: 'A real topic', posts: [first, top]),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(renderedText('Ordinary reply'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-summary-button')));
      await tester.pumpAndSettle();

      expect(api.topicSummariesOpened, [7]);
      expect(renderedText('Ordinary reply'), findsNothing);
      expect(renderedText('Top reply'), findsOneWidget);
      expect(find.text('Show all'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('topic-summary-button')));
      await tester.pumpAndSettle();

      expect(renderedText('Ordinary reply'), findsOneWidget);
      expect(find.text('Summarize'), findsOneWidget);
    });

    testWidgets('prefers the Discourse AI summary over the core summary', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [post(1, 1, 'First post body')],
            hasSummary: true,
            plugins: PluginData.none.withValue(
              aiSummaryAvailabilityDataKey,
              const AiSummaryAvailability(
                summarizable: true,
                hasCachedSummary: true,
              ),
            ),
          ),
        },
        pluginResponses: const {
          'GET /discourse-ai/summarization/t/7.json': {
            'ai_topic_summary': {
              'summarized_text': 'A concise AI summary.',
              'algorithm': 'test-model',
            },
          },
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('ai-topic-summary-button'));
      expect(action, findsOneWidget);
      expect(find.byKey(const ValueKey('topic-summary-button')), findsNothing);
      expect(find.text('Summarize'), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();

      expect(find.text('Topic summary'), findsOneWidget);
      expect(find.text('A concise AI summary.'), findsOneWidget);
      expect(find.text('Generated with test-model'), findsOneWidget);
      expect(api.pluginReadPaths, ['/discourse-ai/summarization/t/7.json']);
    });

    testWidgets('a signed-in topic exposes all web notification levels', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = previousPlatform);
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(notificationLevel: TopicNotificationLevel.tracking)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final trigger = find.byTooltip('Topic notifications');
      expect(trigger, findsOneWidget);
      DIconData triggerIcon() => tester
          .widget<DIcon>(
            find.descendant(of: trigger, matching: find.byType(DIcon)),
          )
          .icon;
      expect(triggerIcon(), DIcons.bell);

      await tester.tap(trigger);
      await tester.pumpAndSettle();

      expect(find.text('Topic notifications'), findsNothing);
      expect(find.text('Watching'), findsOneWidget);
      expect(find.text('Every reply and unread count'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(
            const ValueKey((
              'choice-menu-option',
              TopicNotificationLevel.tracking,
            )),
          ),
          matching: find.text('Tracking'),
        ),
        findsOneWidget,
      );
      expect(find.text('Mentions, replies, and unread count'), findsOneWidget);
      expect(find.text('Normal'), findsOneWidget);
      expect(find.text('Mentions and replies only'), findsOneWidget);
      expect(find.text('Muted'), findsOneWidget);
      expect(find.text('No notifications; hidden from Latest'), findsOneWidget);
      final muted = find.byKey(
        const ValueKey(('choice-menu-option', TopicNotificationLevel.muted)),
      );
      expect(
        tester
            .widgetList<DIcon>(
              find.descendant(of: muted, matching: find.byType(DIcon)),
            )
            .map((icon) => icon.icon),
        contains(DIcons.discourseBellSlash),
      );

      await tester.tap(muted);
      await tester.pumpAndSettle();

      expect(api.topicNotificationLevelsUpdated, const [
        (topicId: 7, notificationLevel: TopicNotificationLevel.muted),
      ]);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentTopic?.notificationLevel,
        TopicNotificationLevel.muted,
      );
      expect(triggerIcon(), DIcons.discourseBellSlash);
      debugDefaultTargetPlatformOverride = previousPlatform;
    });

    testWidgets('a rejected notification change restores the confirmed level', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(notificationLevel: TopicNotificationLevel.tracking)},
        writeFailure: const WriteException(WriteFailure.forbidden),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Topic notifications'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(
          const ValueKey(('choice-menu-option', TopicNotificationLevel.muted)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).currentTopic?.notificationLevel,
        TopicNotificationLevel.tracking,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps action hover affordances inside the viewport', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(
            canCloseTopic: true,
            canArchiveTopic: true,
            canToggleTopicVisibility: true,
            canDeleteTopic: true,
          ),
        },
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(508, 700);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      final trigger = find.byKey(const ValueKey('topic-status-button'));
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final item = find.byKey(const ValueKey('topic-status-closed'));
      final button = tester.widget<TextButton>(
        find.descendant(of: item, matching: find.byType(TextButton)),
      );
      final theme = Theme.of(tester.element(item));
      final hoverColor = Color.alphaBlend(
        theme.colorScheme.onSurface.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.10 : 0.06,
        ),
        theme.shell.floating,
      );
      expect(
        button.style!.backgroundColor!.resolve({WidgetState.hovered}),
        hoverColor,
      );
      expect(button.style!.mouseCursor!.resolve({}), SystemMouseCursors.click);

      final menuSurface = find.byKey(const ValueKey('command-menu-surface'));
      expect(menuSurface, findsOneWidget);
      final menuRect = tester.getRect(menuSurface);
      expect(menuRect.left, greaterThanOrEqualTo(10));
      expect(menuRect.top, greaterThanOrEqualTo(10));
      expect(menuRect.right, lessThanOrEqualTo(498));
      expect(menuRect.bottom, lessThanOrEqualTo(690));
    });

    testWidgets(
      'gates status actions by guardian permissions and updates state',
      (tester) async {
        const reader = DiscourseUser(username: 'reader', name: 'Reader');
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {
            7: detail(
              canCloseTopic: true,
              canArchiveTopic: true,
              canToggleTopicVisibility: true,
            ),
          },
        );
        final authenticator = FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key';

        await pumpShell(
          tester,
          desktop,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: reader),
          ],
          api: api,
          authenticator: authenticator,
        );
        await tester.tap(contentText('A real topic'));
        await tester.pumpAndSettle();

        Future<void> choose(String label) async {
          await tester.tap(find.byTooltip('More topic actions'));
          await tester.pumpAndSettle();
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
        }

        await choose('Close topic');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.closed,
          isTrue,
        );
        await choose('Archive topic');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.archived,
          isTrue,
        );
        await choose('Make topic unlisted');
        expect(
          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).currentTopic?.visible,
          isFalse,
        );
        expect(api.topicStatusesUpdated, const [
          (topicId: 7, status: TopicStatusProperty.closed, enabled: true),
          (topicId: 7, status: TopicStatusProperty.archived, enabled: true),
          (topicId: 7, status: TopicStatusProperty.visible, enabled: false),
        ]);

        await tester.tap(find.byTooltip('More topic actions'));
        await tester.pumpAndSettle();
        expect(find.text('Open topic'), findsOneWidget);
        expect(find.text('Unarchive topic'), findsOneWidget);
        expect(find.text('Make topic visible'), findsOneWidget);
      },
    );

    testWidgets('staff can delete and recover a topic from its action menu', (
      tester,
    ) async {
      const reader = DiscourseUser(
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {'/latest.json': listed},
        topics: {7: detail(canDeleteTopic: true)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-delete-confirm')));
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicsDeleted, [7]);
      expect(shell.currentTopic?.deletedAt, isNotNull);
      expect(shell.currentTopic?.canRecoverTopic, isTrue);

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover topic'));
      await tester.pumpAndSettle();

      expect(api.topicsRecovered, [7]);
      expect(shell.currentTopic?.deletedAt, isNull);
      expect(shell.currentTopic?.canDeleteTopic, isTrue);
    });

    testWidgets('share stays available when guardian-gated actions do not', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-share-button')), findsOneWidget);
      final more = tester.widget<DButton>(
        find.byKey(const ValueKey('topic-status-button')),
      );
      expect(more.onPressed, isNull);
      expect(find.text('Close topic'), findsNothing);
      expect(find.text('Archive topic'), findsNothing);
      expect(find.text('Delete topic'), findsNothing);
    });

    testWidgets('a personalized topic pin can be dismissed and restored', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              pinned: true,
            ),
          ],
        },
        topics: {7: detail(pinned: true, pinnedGlobally: true)},
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      final trigger = find.byTooltip('More topic actions');
      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin topic'));
      await tester.pumpAndSettle();

      var shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicPinPreferencesUpdated, const [
        (topicId: 7, pinned: false),
      ]);
      expect(shell.currentTopic?.pinned, isFalse);
      expect(shell.currentTopic?.unpinned, isTrue);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isFalse,
      );

      await tester.tap(trigger);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin topic'));
      await tester.pumpAndSettle();

      shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.topicPinPreferencesUpdated, const [
        (topicId: 7, pinned: false),
        (topicId: 7, pinned: true),
      ]);
      expect(shell.currentTopic?.pinned, isTrue);
      expect(shell.currentTopic?.unpinned, isFalse);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isTrue,
      );
    });

    testWidgets('a rejected topic pin change restores the prior preference', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader', name: 'Reader');
      final api = FakeDiscourseApi(
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'A real topic',
              slug: 'a-real-topic',
              pinned: true,
            ),
          ],
        },
        topics: {7: detail(pinned: true)},
        writeFailure: const WriteException(WriteFailure.forbidden),
      );
      final authenticator = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'meta-key';

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
        authenticator: authenticator,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Unpin topic'));
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.currentTopic?.pinned, isTrue);
      expect(shell.currentTopic?.unpinned, isFalse);
      expect(
        shell.store.read<Topic>('https://meta.discourse.org', 7)?.pinned,
        isTrue,
      );
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('ordinary topics do not show personalized pin controls', (
      tester,
    ) async {
      const reader = DiscourseUser(username: 'reader');
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(
        tester,
        desktop,
        instances: [instance('meta.discourse.org').copyWith(user: reader)],
        api: api,
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More topic actions'));
      await tester.pumpAndSettle();
      expect(find.text('Pin topic'), findsNothing);
      expect(find.text('Unpin topic'), findsNothing);
    });

    testWidgets('signed-out topics do not expose notification controls', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Topic notifications'), findsNothing);
    });

    testWidgets('shows a faithful skeleton while the topic is loading', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        topicGate: gate,
      );

      await pumpShell(tester, phone, api: api);
      await tester.tap(sidebarDestination('Topics'));
      await tester.pumpAndSettle();
      final semantics = tester.ensureSemantics();
      try {
        await tester.tap(find.text('A real topic'));
        await tester.pump();

        expect(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          findsOneWidget,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('topic-loading-skeleton-content')),
              )
              .height,
          greaterThanOrEqualTo(
            tester
                .getSize(find.byKey(const ValueKey('topic-loading-skeleton')))
                .height,
          ),
        );
        final skeletonPosts = minimumHeightDescendants(
          find.byKey(const ValueKey('topic-loading-skeleton')),
          TopicView.minimumPostHeight,
        );
        expect(skeletonPosts, findsWidgets);
        expect(
          tester.getSize(skeletonPosts.first).height,
          greaterThanOrEqualTo(TopicView.minimumPostHeight),
        );
        expect(find.bySemanticsLabel('Loading topic'), findsOneWidget);
        expect(activityIndicators, findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }

      gate.complete();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-loading-skeleton')),
        findsNothing,
      );
      expect(renderedText('First post body'), findsOneWidget);
      final loadedPosts = minimumHeightDescendants(
        find.byType(TopicView),
        TopicView.minimumPostHeight,
      );
      expect(loadedPosts, findsOneWidget);
      expect(
        tester.getSize(loadedPosts.first).height,
        greaterThanOrEqualTo(TopicView.minimumPostHeight),
      );
      expect(tester.takeException(), isNull);
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

      expect(find.text('3'), findsNothing);

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

      expect(find.text('Topic 40'), findsOneWidget);
      expect(find.text('Topic 1'), findsNothing);
      expect(
        tester.state<ScrollableState>(list).position.pixels,
        greaterThan(0),
      );
    });

    testWidgets('a topic that fails to load says so', (tester) async {
      final api = FakeDiscourseApi(feeds: {'/latest.json': listed});

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.textContaining("Couldn't load this topic"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('remaining posts are fetched by ID, not by page', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
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

    testWidgets('shows and expands server-provided hidden replies', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              post(1, 1, 'First post body'),
              post(4, 4, 'Fourth post body'),
            ],
            stream: const [1, 4],
            gapsBefore: const {
              4: [2, 3],
            },
            postsCount: 4,
          ),
        },
        postsById: {
          2: post(2, 2, 'Hidden second post'),
          3: post(3, 3, 'Hidden third post'),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('VIEW 2 HIDDEN REPLIES'), findsOneWidget);
      expect(renderedText('Hidden second post'), findsNothing);
      expect(api.postFetches, isEmpty);

      await tester.tap(find.text('VIEW 2 HIDDEN REPLIES'));
      await tester.pumpAndSettle();

      expect(api.postFetches, [
        [2, 3],
      ]);
      expect(find.text('VIEW 2 HIDDEN REPLIES'), findsNothing);
      expect(renderedText('Hidden second post'), findsOneWidget);
      expect(renderedText('Hidden third post'), findsOneWidget);
      expect(
        tester.getTopLeft(renderedText('Hidden second post')).dy,
        lessThan(tester.getTopLeft(renderedText('Fourth post body')).dy),
      );
    });

    testWidgets('shows ordered recommendation-source tabs in a panel', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'Locations :earth_africa:',
                slug: 'locations',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
            topics: [
              Topic(
                id: 9,
                title: 'An AI topic :sparkles:',
                slug: 'an-ai-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: TopicRecommendationSourceDefinition(
              id: TopicRecommendationSourceId('test/nearby'),
              label: 'Nearby',
              icon: DIcons.globe,
            ),
            topics: [Topic(id: 10, title: 'A nearby topic', slug: 'nearby')],
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(
              name: 'earth_africa',
              url: 'https://emoji.discourse-cdn.com/twitter/earth_africa.png',
            ),
            SiteEmoji(
              name: 'sparkles',
              url: 'https://emoji.discourse-cdn.com/twitter/sparkles.png',
            ),
          ],
        },
        topics: {
          7: detail(recommendations: recommendations),
          9: topicPayload(
            id: 9,
            title: 'An AI topic :sparkles:',
            posts: [post(9, 1, 'Related topic body')],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(find.text('More topics'), findsOneWidget);
      expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      expect(find.text('Suggested'), findsOneWidget);
      expect(find.text('Related'), findsOneWidget);
      expect(find.text('Nearby'), findsOneWidget);
      final earth = find.byWidgetPredicate(
        (widget) => widget is SiteEmojiImage && widget.name == 'earth_africa',
      );
      final sparkles = find.byWidgetPredicate(
        (widget) => widget is SiteEmojiImage && widget.name == 'sparkles',
      );
      expect(earth, findsOneWidget);
      expect(sparkles, findsNothing);

      await tester.tap(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
      );
      await tester.pumpAndSettle();

      expect(earth, findsNothing);
      expect(sparkles, findsOneWidget);

      await tester.tap(sparkles);
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 9]);
      expect(renderedText('Related topic body'), findsOneWidget);
    });

    testWidgets('hides a lone recommendation tab and compacts topic titles', (
      tester,
    ) async {
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'A compact suggested topic',
                slug: 'a-compact-suggested-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('More topics'), findsOneWidget);
      expect(find.text('Suggested'), findsNothing);
      final compactTitle = tester.widget<TopicTitle>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TopicTitle &&
              widget.title == 'A compact suggested topic',
        ),
      );
      expect(compactTitle.style?.fontSize, DiscourseTypography.base);
      expect(
        compactTitle.style?.fontSize,
        lessThan(DiscourseTypography.fontUp1),
      );
    });

    testWidgets('omits More topics when every source is empty', (tester) async {
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-more-topics-card')),
        findsNothing,
      );
      expect(find.text('More topics'), findsNothing);
    });

    testWidgets('reserves the topic sidebar while a topic loads', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'A suggested topic',
          slug: 'a-suggested-topic',
        ),
      );
      final topicGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
        topicGate: topicGate,
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pump();
      final semantics = tester.ensureSemantics();

      final loadingPanel = find.byKey(
        const ValueKey('topic-recommendations-loading-skeleton'),
      );
      expect(loadingPanel, findsOneWidget);
      expect(find.bySemanticsLabel('Loading more topics'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('topic-sidebar-panel'))).width,
        344,
      );
      final loadingPostWidth = tester
          .getSize(find.byKey(const ValueKey('topic-loading-skeleton')))
          .width;

      topicGate.complete();
      await tester.pumpAndSettle();

      expect(loadingPanel, findsNothing);
      expect(find.text('A suggested topic'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        loadingPostWidth + 344,
      );
      semantics.dispose();
    });

    testWidgets('keeps the panel width while final-page topics load', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Suggested at the end',
          slug: 'suggested-end',
        ),
      );
      final postGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: detail(stream: [1, 2]),
        },
        postsById: {2: post(2, 2, 'Last post body')},
        postRecommendations: {7: recommendations},
        postGate: postGate,
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(api.postFetches, [
        [2],
      ]);
      final loadingPanel = find.byKey(
        const ValueKey('topic-recommendations-loading-skeleton'),
      );
      expect(loadingPanel, findsOneWidget);
      final loadingPostWidth = tester.getSize(find.byType(SuperListView)).width;

      postGate.complete();
      await tester.pumpAndSettle();

      expect(loadingPanel, findsNothing);
      expect(find.text('Suggested at the end'), findsOneWidget);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        loadingPostWidth,
      );
    });

    testWidgets('remembers a hidden topic sidebar for the forum', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      final recommendations = suggestedRecommendations(
        const Topic(id: 8, title: 'Remembered suggestion', slug: 'remembered'),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(find.text('Remembered suggestion'), findsOneWidget);
      final postViewportWidth = tester
          .getSize(find.byType(SuperListView))
          .width;
      expect(
        tester.widget<SuperListView>(find.byType(SuperListView)).padding,
        const EdgeInsets.only(right: 344),
      );

      await tester.tap(find.byTooltip('Hide topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
      expect(find.text('Remembered suggestion'), findsNothing);
      expect(
        tester.getSize(find.byType(SuperListView)).width,
        postViewportWidth,
      );
      expect(
        tester.widget<SuperListView>(find.byType(SuperListView)).padding,
        EdgeInsets.zero,
      );
      // The UI intentionally fires this optional preference write without
      // blocking. Read through the same serialized store boundary so the
      // replacement below cannot overtake that write.
      expect(
        await const TopicSidebarStore().read(
          siteUrl: 'https://meta.discourse.org',
        ),
        isTrue,
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        key: const ValueKey('restored-topics-panel'),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
      expect(find.text('Remembered suggestion'), findsNothing);
    });

    testWidgets('remembers the more topics tab for the forum', (tester) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      const recommendations = TopicRecommendations(
        sources: [
          TopicRecommendationSource(
            definition: coreSuggestedTopicRecommendationSource,
            topics: [
              Topic(
                id: 8,
                title: 'A suggested topic',
                slug: 'a-suggested-topic',
              ),
            ],
          ),
          TopicRecommendationSource(
            definition: discourseAiRelatedTopicRecommendationSource,
            topics: [
              Topic(id: 9, title: 'An AI related topic', slug: 'an-ai-topic'),
            ],
          ),
        ],
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      expect(find.text('A suggested topic'), findsOneWidget);

      await tester.tap(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('An AI related topic'), findsOneWidget);
      // The UI intentionally fires this optional preference write without
      // blocking. Read through the same serialized store boundary so the
      // replacement below cannot overtake that write.
      expect(
        await const TopicRecommendationsTabStore().read(
          siteUrl: 'https://meta.discourse.org',
        ),
        discourseAiRelatedTopicRecommendationSourceId,
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        key: const ValueKey('restored-topics-tab'),
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('An AI related topic'), findsOneWidget);
      expect(find.text('A suggested topic'), findsNothing);
    });

    testWidgets('falls back when the remembered tab has no topics', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      addTearDown(() => SharedPreferences.setMockInitialValues({}));
      await const TopicRecommendationsTabStore().write(
        siteUrl: 'https://meta.discourse.org',
        sourceId: discourseAiRelatedTopicRecommendationSourceId,
      );
      final recommendations = suggestedRecommendations(
        const Topic(id: 8, title: 'Only suggestion', slug: 'only-suggestion'),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('Only suggestion'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('topic-recommendations-tab-discourse-ai/related'),
        ),
        findsNothing,
      );
    });

    testWidgets('keeps recommendations below the posts on narrow layouts', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Narrow suggestion',
          slug: 'narrow-suggestion',
        ),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(recommendations: recommendations)},
      );

      await pumpShell(tester, laptop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
      expect(find.text('Narrow suggestion'), findsOneWidget);
      expect(find.byTooltip('Show topic sidebar'), findsOneWidget);

      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsOneWidget);
      expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      expect(find.byKey(const ValueKey('topic-status-button')), findsOneWidget);

      await tester.tap(find.byTooltip('Hide topic sidebar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
    });

    testWidgets(
      'automatically unpins the sidebar when an expanded shell is too narrow',
      (tester) async {
        final recommendations = suggestedRecommendations(
          const Topic(
            id: 8,
            title: 'Responsive suggestion',
            slug: 'responsive-suggestion',
          ),
        );
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail(recommendations: recommendations)},
        );

        await pumpShell(tester, desktop, api: api);
        await tester.tap(find.text('A real topic'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('topic-sidebar-panel')),
          findsOneWidget,
        );

        // This remains above the shell's expanded breakpoint, but its topic
        // viewport can no longer leave 640px for posts beside the 344px panel.
        tester.view.physicalSize = const Size(1240, 800);
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('topic-sidebar-panel')), findsNothing);
        expect(find.text('Responsive suggestion'), findsOneWidget);
        expect(find.byTooltip('Show topic sidebar'), findsOneWidget);
        expect(
          tester.widget<SuperListView>(find.byType(SuperListView)).padding,
          EdgeInsets.zero,
        );

        await tester.tap(find.byTooltip('Show topic sidebar'));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('topic-sidebar-panel')),
          findsOneWidget,
        );
        expect(find.byTooltip('Hide topic sidebar'), findsOneWidget);
      },
    );

    testWidgets('gets more topics with the final page of a long topic', (
      tester,
    ) async {
      final recommendations = suggestedRecommendations(
        const Topic(
          id: 8,
          title: 'Suggested at the end',
          slug: 'suggested-end',
        ),
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

    testWidgets('hovering a post leaves its surface unchanged', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(postBackground(tester), Colors.transparent);

      final gesture = await hoverPost(tester);
      expect(postBackground(tester), Colors.transparent);

      await gesture.moveTo(Offset.zero);
      await tester.pumpAndSettle();
      expect(postBackground(tester), Colors.transparent);
    });

    testWidgets('whisper posts use core styling and an indicator', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              post(1, 1, 'First post body'),
              const Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>A private aside</p>',
                postType: Post.whisperPostType,
              ),
            ],
            stream: const [1, 2],
          ),
        },
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.dIcon(DIcons.farEyeSlash), findsOneWidget);
      expect(find.byTooltip('This post is a private whisper'), findsOneWidget);

      final whisper = tester.widget<RichText>(renderedText('A private aside'));
      expect(whisper.text.style?.fontStyle, FontStyle.italic);
      expect(
        whisper.text.style?.color,
        Theme.of(tester.element(find.byType(TopicView))).discourse.whisper,
      );
    });
  });

  group('connecting', () {
    testWidgets('signed-out sites show sign-up and sign-in actions', (
      tester,
    ) async {
      await pumpShell(tester, desktop);

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);

      final signUp = tester.getRect(find.byKey(UserMenuButton.signUpKey));
      final signUpLabel = tester.getRect(find.text('Sign up'));
      expect(signUpLabel.left - signUp.left, moreOrLessEquals(11.4));
      expect(signUp.right - signUpLabel.right, moreOrLessEquals(11.4));

      final signIn = tester.getRect(find.byKey(UserMenuButton.signInKey));
      final signInIcon = tester.getRect(find.dIcon(DIcons.user));
      final signInLabel = tester.getRect(find.text('Sign in'));
      expect(signInIcon.left - signIn.left, moreOrLessEquals(11.4));
      expect(signIn.right - signInLabel.right, moreOrLessEquals(11.4));
    });

    testWidgets('aggregate hides forum account actions', (tester) async {
      await pumpShell(tester, desktop);

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);

      final controller = ShellScope.read(
        tester.element(find.byType(ShellTitleBar)),
      );
      controller.selectAggregate();
      await tester.pump();

      expect(find.byKey(UserMenuButton.signUpKey), findsNothing);
      expect(find.byKey(UserMenuButton.signInKey), findsNothing);
      expect(find.byKey(UserMenuButton.avatarKey), findsNothing);

      controller.selectInstance(0);
      await tester.pump();

      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
    });

    testWidgets('sign-up opens the selected forum registration page', (
      tester,
    ) async {
      final launched = watchBrowser(tester);
      await pumpShell(tester, desktop);

      await tester.tap(find.byKey(UserMenuButton.signUpKey));
      await tester.pumpAndSettle();

      expect(launched, ['https://meta.discourse.org/signup']);
    });

    testWidgets('records the account against the site', (tester) async {
      final store = FakeInstanceStore(twoSites);
      final auth = FakeAuthenticator();

      await pumpShell(tester, desktop, store: store, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(auth.connected, ['https://meta.discourse.org']);
      expect(find.byTooltip('Joffrey'), findsOneWidget);
      expect(find.text('meta.discourse.org'), findsNothing);
      expect(store.saveCount, 2);
    });

    testWidgets('backing out of the browser is not an error', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.cancelled);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('an unverifiable reply is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.badReply);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('could not be verified'), findsOneWidget);
    });

    testWidgets('a browser that never opened is surfaced', (tester) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.launchFailed);

      await pumpShell(tester, desktop, authenticator: auth);

      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not open'), findsOneWidget);
    });

    testWidgets('a private-site sign-in failure stays actionable in the gate', (
      tester,
    ) async {
      final auth = FakeAuthenticator(failure: UserApiAuthFailure.launchFailed);
      final api = FakeDiscourseApi();
      final privateSite = instance(
        'meetup.discourse.org',
        title: 'Discourse Meetup',
      ).copyWith(loginRequired: true);
      final publicSite = instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      );

      await pumpShell(
        tester,
        desktop,
        instances: [privateSite, publicSite],
        api: api,
        authenticator: auth,
      );

      expect(api.feedPaths, isEmpty);
      expect(api.appearancesRequested, isEmpty);
      expect(api.siteConfigsRequested, isEmpty);
      expect(api.customEmojisRequired, isEmpty);
      expect(api.categoryRequests, isEmpty);

      expect(find.byType(MainContent), findsNothing);
      expect(find.byType(InstanceRail), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsNothing);
      expect(find.byType(ForumTabsBar), findsNothing);
      expect(find.byType(ShellTitleBar), findsOneWidget);
      expect(find.byKey(ForumSearch.inputKey), findsNothing);
      expect(userMenu, findsNothing);
      expect(find.byKey(ValueKey(privateSite.url)), findsOneWidget);
      expect(find.byKey(ValueKey(publicSite.url)), findsOneWidget);

      await tester.tap(find.byKey(ValueKey(publicSite.url)));
      await tester.pumpAndSettle();
      expect(find.byType(MainContent), findsOneWidget);
      expect(find.byType(InstanceSidebar), findsOneWidget);

      await tester.tap(find.byKey(ValueKey(privateSite.url)));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.byType(MainContent), findsNothing);

      await tester.tap(find.byKey(const ValueKey('private-forum-sign-in')));
      await tester.pumpAndSettle();

      expect(find.text('Sign in to continue'), findsOneWidget);
      expect(find.textContaining('Could not open'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('private-forum-sign-in')),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('counters appear once connected', (tester) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 4,
      );
      final api = FakeDiscourseApi(
        user: user,
        totals: const NotificationTotals(
          unreadNotifications: 3,
          unreadPersonalMessages: 2,
          topicTrackingNew: 19,
        ),
      );

      await pumpShell(tester, desktop, api: api);
      await tester.tap(userMenu);
      await tester.pumpAndSettle();

      Finder countFor(String destinationId, String count) => find.descendant(
        of: find.byKey(ValueKey(destinationId)),
        matching: find.text(count),
      );

      expect(countFor('latest', '19'), findsOneWidget);
      expect(countFor('messages', '2'), findsOneWidget);
      expect(countFor('drafts', '4'), findsOneWidget);
      expect(find.text('5'), findsNWidgets(2));
      expect(api.totalsCalls, 1);
    });

    testWidgets('a site whose counters fail still renders', (tester) async {
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
      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.byKey(UserMenuButton.signUpKey), findsOneWidget);
      expect(find.byKey(UserMenuButton.signInKey), findsOneWidget);
    });
  });

  group('the user menu', () {
    const me = DiscourseUser(
      username: 'joffreyj',
      name: 'Joffrey',
      hidePresence: false,
    );
    final connected = [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: me),
    ];

    FakeAuthenticator signedIn() =>
        FakeAuthenticator()..keys['https://meta.discourse.org'] = 'api-key';

    const notifications = [
      DiscourseNotification.test(
        id: 1,
        typeId: NotificationTypeId(2),
        title: 'Better image handling',
        topicId: 7,
        slug: 'better-image-handling',
        data: {'display_username': 'sam'},
      ),
      DiscourseNotification.test(
        id: 2,
        typeId: NotificationTypeId(5),
        read: true,
        title: 'Merge CVSS',
        topicId: 8,
        slug: 'merge-cvss',
        data: {'display_username': 'david'},
      ),
      DiscourseNotification.test(
        id: 3,
        typeId: NotificationTypeId(12),
        data: {
          'badge_id': 24,
          'badge_name': 'Nice Reply',
          'badge_slug': 'nice-reply',
        },
      ),
      DiscourseNotification.test(
        id: 4,
        typeId: NotificationTypeId(4242),
        title: 'Something from a plugin',
      ),
    ];

    final chatEnabledTotals = chatNotificationTotals(chatNotifications: 1);
    const emptyChatChannels = ChatChannels(
      public: <ChatChannel>[],
      direct: <ChatChannel>[],
    );
    final chatMention = DiscourseNotification.fromJson(const {
      'id': 51,
      'notification_type': 29,
      'read': false,
      'created_at': '2026-08-09T08:00:00.000Z',
      'data': {
        'chat_message_id': 44,
        'chat_channel_id': 9,
        'chat_channel_title': '#dev',
        'mentioned_by_username': 'sam',
      },
    });

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(userMenu);
      await tester.pumpAndSettle();
    }

    Future<void> openNotifications(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Notifications'));
      await tester.pumpAndSettle();
    }

    Future<void> openReplies(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();
    }

    Future<void> openChat(WidgetTester tester) async {
      await openMenu(tester);
      await tester.tap(find.text('Chat'));
      await tester.pumpAndSettle();
    }

    testWidgets('notification rows render site emoji shortcodes', (
      tester,
    ) async {
      const notification = DiscourseNotification.test(
        id: 52,
        typeId: NotificationTypeId(2),
        title: ':telephone: Engineering call',
        data: {'display_username': 'sam'},
      );
      final api = FakeDiscourseApi(
        notificationList: const [notification],
        emojisBySite: const {
          'https://meta.discourse.org': [
            SiteEmoji(name: 'telephone', url: '/images/emoji/telephone.png'),
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
      await openNotifications(tester);

      final row = find.byType(NotificationRow);
      expect(
        find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SiteEmojiImage>(
              find.descendant(of: row, matching: find.byType(SiteEmojiImage)),
            )
            .name,
        'telephone',
      );
      expect(api.emojisRequested, ['https://meta.discourse.org']);
    });

    testWidgets('a thumb gets a sheet, and one sheet per section inside it', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        replyNotificationList: [notifications.first],
      );
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.byType(UserMenuPanel), findsNothing);
      expect(find.text('Joffrey'), findsOneWidget);
      expect(find.text('@joffreyj · meta.discourse.org'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Replies')).style?.color,
        isNot(Theme.of(tester.element(find.text('Replies'))).shell.placeholder),
      );

      await tester.tap(find.text('Replies'));
      await tester.pumpAndSettle();

      expect(api.replyNotificationCalls, 1);
      expect(api.notificationFilters.single, userMenuReplyNotificationTypes);
      expect(
        find.textContaining('sam replied to Better image handling'),
        findsOneWidget,
      );
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.dIcon(DIcons.arrowLeft), findsOneWidget);

      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(find.text('Profile'), findsOneWidget);
      expect(find.textContaining('sam replied to'), findsNothing);
    });

    testWidgets('a title bar takes the avatar off the columns', (tester) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          key: const ValueKey('macos'),
        );

        expect(userMenu, findsOneWidget);
        final avatar = tester.getRect(userMenu);

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

    testWidgets('a reply opens its topic and is marked read', (tester) async {
      final api = FakeDiscourseApi(
        replyNotificationList: [notifications.first],
        topics: {
          7: topicPayload(
            id: 7,
            title: 'Better image handling',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
            ],
            stream: const [1],
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
      await openReplies(tester);
      await tester.tap(
        find.textContaining('sam replied to Better image handling'),
      );
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7]);
      expect(api.markedRead, [1]);
      expect(find.byType(RepliesSection), findsNothing);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('a reaction notification refreshes a post already open', (
      tester,
    ) async {
      const notification = DiscourseNotification.test(
        id: 5,
        typeId: NotificationTypeId(25),
        title: 'Better image handling',
        topicId: 7,
        postNumber: 1,
        slug: 'better-image-handling',
        data: {'display_username': 'david'},
      );
      Post reactionPost(List<Reaction> reactions) => Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>First post body</p>',
        plugins: PluginData.none.withValue(
          reactionsDataKey,
          Reactions(entries: reactions, userCount: reactions.length),
        ),
      );
      final topics = <int, TopicPayload>{
        7: topicPayload(
          id: 7,
          title: 'Better image handling',
          posts: [reactionPost(const [])],
        ),
      };
      final api = FakeDiscourseApi(
        notificationList: const [notification],
        feeds: const {
          '/latest.json': [
            Topic(
              id: 7,
              title: 'Better image handling',
              slug: 'better-image-handling',
            ),
          ],
        },
        topics: topics,
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      final controller = tester
          .widget<ShellScope>(find.byType(ShellScope))
          .notifier!;
      controller.pushContent(
        ContentRoute.topic(
          topicId: 7,
          slug: 'better-image-handling',
          title: 'Better image handling',
        ),
      );
      await controller.loadTopic(7, 'better-image-handling');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('post-reaction-1-clap')), findsNothing);

      topics[7] = topicPayload(
        id: 7,
        title: 'Better image handling',
        posts: [
          reactionPost(const [Reaction(id: 'clap', count: 1)]),
        ],
      );
      await tester.tap(find.byTooltip('Show topic sidebar'));
      await tester.pumpAndSettle();
      await openNotifications(tester);
      await tester.tap(find.textContaining('david reacted to your post in'));
      await tester.pumpAndSettle();

      expect(api.topicsOpened, [7, 7]);
      expect(api.markedRead, [5]);
      expect(
        find.byKey(const ValueKey('post-reaction-1-clap')),
        findsOneWidget,
      );
    });

    testWidgets('Replies can retry a failed filtered request', (tester) async {
      final api = FakeDiscourseApi();

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openReplies(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.replyNotificationCalls, 2);
      expect(api.notificationCalls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty Replies tab stops waiting', (tester) async {
      final api = FakeDiscourseApi(replyNotificationList: const []);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openReplies(tester);

      expect(find.text('Nothing new.'), findsOneWidget);
    });

    testWidgets('the pointer Chat tab requests and renders its own feed', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = FakeDiscourseApi(
          totals: chatEnabledTotals,
          notificationList: const [],
          chatNotificationList: [chatMention],
          chatChannelsBySite: const {
            'https://meta.discourse.org': emptyChatChannels,
          },
        );
        await pumpShell(
          tester,
          desktop,
          instances: connected,
          api: api,
          authenticator: signedIn(),
          key: const ValueKey('pointer-chat-menu'),
        );
        await openMenu(tester);

        final chatTab = find.descendant(
          of: find.byType(UserMenuPanel),
          matching: find.byTooltip('Chat'),
        );
        expect(chatTab, findsOneWidget);
        await tester.tap(chatTab);
        await tester.pumpAndSettle();

        expect(
          find.textContaining('sam mentioned you in #dev'),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(NotificationRow),
            matching: find.dIcon(DIcons.comment),
          ),
          findsOneWidget,
        );
        expect(api.chatNotificationCalls, 1);
        expect(api.notificationCalls, 1);
        expect(api.replyNotificationCalls, 0);
        expect(api.notificationFilters, [
          const <NotificationTypeName>[],
          chatNotificationFeed.filterByTypes,
        ]);

        final title = find.text('Chat');
        final placeholder = Theme.of(tester.element(title)).shell.placeholder;
        expect(tester.widget<Text>(title).style?.color, isNot(placeholder));
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('a Chat row marks read, opens its link, and dismisses', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatNotificationList: [chatMention],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);
      await tester.tap(find.textContaining('sam mentioned you in #dev'));
      await tester.pumpAndSettle();

      expect(api.markedRead, [51]);
      expect(launched, ['https://meta.discourse.org/chat/c/-/9/44']);
      expect(find.byType(ChatUserMenuNotifications), findsNothing);
      expect(find.text('@joffreyj · meta.discourse.org'), findsNothing);
      expect(api.notificationFilters, [chatNotificationFeed.filterByTypes]);
    });

    testWidgets('an empty Chat tab explains that there is no activity', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatNotificationList: const [],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);

      expect(
        find.text('You don’t have any chat notifications yet.'),
        findsOneWidget,
      );
      expect(api.chatNotificationCalls, 1);
    });

    testWidgets('Chat can retry a failed filtered request', (tester) async {
      final api = FakeDiscourseApi(
        totals: chatEnabledTotals,
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openChat(tester);

      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(api.chatNotificationCalls, 2);
      expect(api.notificationCalls, 0);
      expect(api.notificationFilters, [
        chatNotificationFeed.filterByTypes,
        chatNotificationFeed.filterByTypes,
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Chat is hidden when the site does not make it available', (
      tester,
    ) async {
      final api = FakeDiscourseApi(totals: const NotificationTotals());

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.text('Chat'), findsNothing);
      expect(api.chatNotificationCalls, 0);
    });

    testWidgets('Chat is hidden when the current user disabled it', (
      tester,
    ) async {
      final userWithoutChat = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: false),
        ),
      );
      final api = FakeDiscourseApi(
        user: userWithoutChat,
        totals: chatEnabledTotals,
        chatNotificationList: [chatMention],
        chatChannelsBySite: const {
          'https://meta.discourse.org': emptyChatChannels,
        },
      );

      await pumpShell(
        tester,
        phone,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: userWithoutChat),
        ],
        api: api,
        authenticator: signedIn(),
      );
      await openMenu(tester);

      expect(find.text('Chat'), findsNothing);
      expect(api.chatNotificationCalls, 0);
    });

    testWidgets('a pointer gets a popover with a tab per section', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
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
        expect(
          find.textContaining('sam replied to Better image handling'),
          findsOneWidget,
        );

        await tester.tap(find.byTooltip('Likes'));
        await tester.pumpAndSettle();

        expect(find.text('Likes'), findsOneWidget);
        expect(find.textContaining('sam replied to'), findsNothing);
        expect(find.textContaining('liked your post'), findsNWidgets(2));
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

      expect(find.text('Disconnect'), findsNothing);

      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      expect(find.text('Preferences'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('Preferences hides topic creation and its drafts menu', (
      tester,
    ) async {
      const user = DiscourseUser(
        id: 7,
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 1,
      );
      final api = FakeDiscourseApi(
        feeds: const {'/latest.json': []},
        creatableFeedPaths: const {'/latest.json'},
        user: user,
      );
      await pumpShell(
        tester,
        desktop,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: user),
        ],
        api: api,
        authenticator: signedIn(),
      );

      expect(find.byKey(TopicCreateButton.buttonKey), findsOneWidget);
      expect(find.byTooltip('Open the latest drafts menu'), findsOneWidget);

      await openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-preferences')));
      await tester.pumpAndSettle();

      expect(find.byKey(TopicCreateButton.buttonKey), findsNothing);
      expect(find.byTooltip('Open the latest drafts menu'), findsNothing);
      expect(
        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).canCreateTopicHere,
        isFalse,
      );
    });

    testWidgets('only unfinished profile rows are orange', (tester) async {
      await pumpShell(
        tester,
        phone,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: me.withHidePresence(false)),
        ],
      );
      await openMenu(tester);
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();

      final placeholder = Theme.of(
        tester.element(find.text('Preferences')),
      ).shell.placeholder;

      expect(
        tester.widget<Text>(find.text('Preferences')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Summary')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Activity')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Online')).style?.color,
        isNot(placeholder),
      );
      expect(
        tester.widget<Text>(find.text('Disconnect')).style?.color,
        isNot(placeholder),
      );
    });

    testWidgets(
      'profile Activity opens an accessible native stream and preserves Back',
      (tester) async {
        const activity = UserActivityItem(
          actionType: UserActivityItem.replyActionType,
          topicId: 7,
          postNumber: 4,
          postId: 74,
          title: 'A useful discussion',
          slug: 'a-useful-discussion',
          username: 'joffreyj',
          excerpt: '<p>A useful reply &amp; follow-up</p>',
          categoryId: 5,
        );
        final api = FakeDiscourseApi(
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
          userActivityItems: const [activity],
          userActivityCategories: const [
            TopicCategory(id: 5, name: 'Support', color: '0088CC'),
          ],
          topics: {
            7: topicPayload(
              id: 7,
              title: 'A useful discussion',
              posts: const [
                Post(
                  id: 74,
                  postNumber: 4,
                  username: 'joffreyj',
                  cooked: '<p>A useful reply &amp; follow-up</p>',
                ),
              ],
              stream: const [74],
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

        await openProfileSection(tester);
        final activityAction = find.byKey(
          const ValueKey('user-menu-row-activity'),
        );
        expect(activityAction, findsOneWidget);
        final menuSemantics = tester.ensureSemantics();
        try {
          expect(
            tester.getSemantics(activityAction),
            isSemantics(label: 'Activity', isButton: true, hasTapAction: true),
          );
          expect(
            tester.getSize(activityAction).height,
            greaterThanOrEqualTo(44),
          );
        } finally {
          menuSemantics.dispose();
        }
        expect(
          tester.widget<Text>(find.text('Activity').last).style?.color,
          isNot(
            Theme.of(
              tester.element(find.text('Preferences')),
            ).shell.placeholder,
          ),
        );

        await tester.tap(activityAction);
        await tester.pumpAndSettle();

        expect(find.byType(UserMenuPanel), findsNothing);
        expect(find.byType(UserActivityView), findsOneWidget);
        expect(find.byType(TopicCreateButton), findsNothing);
        expect(api.userActivityRequests, [
          (
            siteUrl: 'https://meta.discourse.org',
            username: 'joffreyj',
            offset: 0,
            limit: 30,
          ),
        ]);
        final shell = ShellScope.read(
          tester.element(find.byType(UserActivityView)),
        );
        expect(shell.currentContent?.id, 'activity');
        expect(shell.contentStack.last.title, 'Activity');

        final row = find.byKey(const ValueKey('user-activity-row-7/4'));
        final target = find.byKey(
          const ValueKey('user-activity-row-target-7/4'),
        );
        expect(row, findsOneWidget);
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
        final semantics = tester.ensureSemantics();
        try {
          final node = tester.getSemantics(row);
          expect(node.label, contains('A useful discussion'));
          expect(node.label, contains('Reply by joffreyj'));
          expect(node.label, contains('Support'));
          expect(node.label, contains('A useful reply & follow-up'));
          final data = node.getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);

          final inkWell = find.descendant(
            of: row,
            matching: find.byType(InkWell),
          );
          final focusChild = find
              .descendant(of: inkWell, matching: find.byType(MouseRegion))
              .first;
          final focus = Focus.of(tester.element(focusChild));
          focus.requestFocus();
          await tester.pumpAndSettle();
          expect(focus.hasPrimaryFocus, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
        } finally {
          semantics.dispose();
        }

        expect(api.topicsOpened, [7]);
        expect(api.topicPostNumbersOpened, [4]);
        expect(shell.currentContent?.topicId, 7);

        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(find.byType(UserActivityView), findsOneWidget);
        expect(shell.handleBack(canReturnToSidebar: false), isTrue);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, isNot('activity'));
      },
    );

    testWidgets('Activity exposes loading, refresh, and empty states', (
      tester,
    ) async {
      final gate = Completer<void>();
      final api = FakeDiscourseApi(userActivityGate: gate);
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );

      await openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-activity')));
      // Let both sheets dismiss and the loader cross its asynchronous shell
      // and credential boundaries. Do not settle: the skeleton intentionally
      // animates until the gated request returns.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final semantics = tester.ensureSemantics();
      try {
        expect(find.bySemanticsLabel('Loading activity'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('No activity yet'), findsOneWidget);
      expect(
        find.textContaining('Topics you create and replies you post'),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView).last, const Offset(0, 320));
      await tester.pumpAndSettle();
      expect(api.userActivityRequests, hasLength(2));
    });

    testWidgets('Activity failure remains a retryable native page', (
      tester,
    ) async {
      final api = _FailingUserActivityApi();
      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );

      await openProfileSection(tester);
      await tester.tap(find.byKey(const ValueKey('user-menu-row-activity')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining("Couldn't load activity from"),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(api.calls, 2);
      expect(find.byType(UserActivityView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a persisted Activity route restores in the wide shell', (
      tester,
    ) async {
      final forumTabs = FakeForumTabStore([
        ForumWorkspace(
          siteUrl: 'https://meta.discourse.org',
          accountIdentity: 'user:joffreyj',
          activeTabId: 'restored-tab',
          tabs: [
            ForumTab(
              id: 'restored-tab',
              rootDestinationId: 'latest',
              contentStack: [
                const ContentRoute(
                  id: 'latest',
                  title: 'Latest',
                  icon: DIcons.layerGroup,
                ),
                ContentRoute.userActivity(),
              ],
            ),
          ],
        ),
      ]);
      final api = FakeDiscourseApi(userActivityItems: const []);

      await pumpShell(
        tester,
        desktop,
        instances: connected,
        api: api,
        authenticator: signedIn(),
        forumTabs: forumTabs,
      );

      expect(find.byType(UserActivityView), findsOneWidget);
      expect(find.text('No activity yet'), findsOneWidget);
      final shell = ShellScope.read(
        tester.element(find.byType(UserActivityView)),
      );
      expect(shell.currentContent?.id, 'activity');
      expect(shell.canPopContent, isTrue);
      expect(api.userActivityRequests, hasLength(1));
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
      expect(find.byType(NotificationRow), findsNWidgets(4));
    });

    testWidgets('notifications that will not load can be asked for again', (
      tester,
    ) async {
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

      expect(api.notificationCalls, 2);
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
      Bookmark(
        id: 9,
        title: 'A message in #dev',
        author: 'david',
        path: 'https://meta.discourse.org/chat/c/-/9/44',
      ),
    ];

    const reminder = DiscourseNotification.test(
      id: 41,
      typeId: NotificationTypeId(24),
      title: 'Better image handling',
      topicId: 7,
      slug: 'better-image-handling',
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

      expect(api.bookmarksRequested, ['joffreyj']);
      expect(
        find.textContaining('Reminder: Better image handling'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sam Thinking about the next project'),
        findsOneWidget,
      );
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

    testWidgets('a channel-message bookmark opens its exact target natively', (
      tester,
    ) async {
      const emptyPage = (
        messages: <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: 44,
      );
      final api = FakeDiscourseApi(
        bookmarkList: [bookmarks[1]],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Dev',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatMessagesByKey: const {'9~target~44': emptyPage},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      final shell = ShellScope.read(
        tester.element(find.byType(BookmarkSection)),
      );

      await tester.tap(find.textContaining('david A message in #dev'));
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(shell.currentContent?.id, 'chat-c-9');
      expect(
        api.chatMessagesRequested.map((request) => request.targetMessageId),
        contains(44),
      );
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a thread bookmark opens its exact reply natively', (
      tester,
    ) async {
      const threadBookmark = Bookmark(
        id: 10,
        title: 'A reply in the support thread',
        author: 'kris',
        path: '/chat/c/-/9/t/3/45',
      );
      const emptyPage = (
        messages: <ChatMessage>[],
        canLoadMorePast: false,
        canLoadMoreFuture: false,
        targetMessageId: 45,
      );
      final api = FakeDiscourseApi(
        bookmarkList: const [threadBookmark],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Support',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatThreadsByKey: const {
          '9~3': ChatThread(
            id: 3,
            channelId: 9,
            status: 'open',
            replyCount: 2,
            membership: ChatThreadMembership(threadId: 3),
          ),
        },
        chatMessagesByKey: const {'thread-9-3~target~45': emptyPage},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);
      final shell = ShellScope.read(
        tester.element(find.byType(BookmarkSection)),
      );

      await tester.tap(
        find.textContaining('kris A reply in the support thread'),
      );
      await tester.pumpAndSettle();

      expect(launched, isEmpty);
      expect(shell.currentContent?.id, 'chat-c-9-t-3');
      expect(
        api.chatThreadMessagesRequested.map(
          (request) => request.targetMessageId,
        ),
        contains(45),
      );
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('an unclaimable Chat bookmark keeps browser fallback', (
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

    testWidgets('an inaccessible thread bookmark keeps browser fallback', (
      tester,
    ) async {
      const path = 'https://meta.discourse.org/chat/c/-/9/t/99/45';
      final api = FakeDiscourseApi(
        bookmarkList: const [
          Bookmark(
            id: 12,
            title: 'Inaccessible support thread',
            author: 'kris',
            path: path,
          ),
        ],
        chatChannelsBySite: const {
          'https://meta.discourse.org': ChatChannels(
            public: [
              ChatChannel(
                id: 9,
                title: 'Support',
                kind: ChatChannelKind.category,
                membership: ChatMembership(following: true),
                threadingEnabled: true,
              ),
            ],
          ),
        },
        chatThreadsByKey: const {},
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: connected,
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      await tester.tap(find.textContaining('kris Inaccessible support thread'));
      await tester.pumpAndSettle();

      expect(launched, [path]);
      expect(find.byType(BookmarkRow), findsNothing);
    });

    testWidgets('a Chat bookmark on a disconnected site opens the browser', (
      tester,
    ) async {
      const path = 'https://team.discourse.org/chat/c/-/9/t/3/45';
      final api = FakeDiscourseApi(
        bookmarkList: const [
          Bookmark(
            id: 11,
            title: 'Disconnected support thread',
            author: 'kris',
            path: path,
          ),
        ],
      );
      final launched = watchBrowser(tester);

      await pumpShell(
        tester,
        phone,
        instances: [
          ...connected,
          instance('team.discourse.org', title: 'Discourse Team'),
        ],
        api: api,
        authenticator: signedIn(),
      );
      await openBookmarks(tester);

      await tester.tap(find.textContaining('kris Disconnected support thread'));
      await tester.pumpAndSettle();

      expect(launched, [path]);
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
      location: 'Paris',
      website: 'https://discourse.org',
      websiteName: 'discourse.org',
      createdAt: DateTime.utc(2015, 3, 4),
      timeRead: 7200,
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
      final semantics = tester.ensureSemantics();
      final profileTargets = find.bySemanticsLabel(
        'View profile for @joffreyj',
      );
      final profileSemantics = find.semantics.byLabel(
        'View profile for @joffreyj',
      );
      expect(profileTargets, findsNWidgets(2));
      expect(
        tester
            .getSemantics(profileTargets.first)
            .getSemanticsData()
            .flagsCollection
            .isButton,
        isTrue,
      );
      tester.semantics.tap(profileSemantics.first);
      await tester.pumpAndSettle();

      expect(api.cardsRequested, ['joffreyj']);
      expect(find.text('@joffreyj'), findsOneWidget);
      expect(find.text('Team member'), findsOneWidget);
      expect(renderedText('Builds the thing.'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('discourse.org'), findsOneWidget);
      expect(find.textContaining('Mar 2015'), findsOneWidget);
      expect(find.textContaining('2h'), findsOneWidget);
      expect(find.text('12 badges'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('user-card-surface'))).width,
        624,
      );
      semantics.dispose();
    });

    testWidgets('Chat contributes a card action and opens a direct message', (
      tester,
    ) async {
      final reader = DiscourseUser(
        id: 7,
        username: 'reader',
        plugins: PluginData.none.withValue(
          chatCurrentUserDataKey,
          const ChatCurrentUser(hasChatEnabled: true),
        ),
      );
      final chatCard = UserCard.fromJson(
        const {
          'username': 'joffreyj',
          'name': 'Joffrey',
          'can_chat_user': true,
        },
        'https://meta.discourse.org',
        extensions: pluginRegistry,
      );
      const directMessage = ChatChannel(
        id: 55,
        title: 'Joffrey',
        kind: ChatChannelKind.directMessage,
      );
      final api = FakeDiscourseApi(
        user: reader,
        feeds: {'/latest.json': listed},
        topics: {7: detail},
        cards: {'joffreyj': chatCard},
        directMessageChannelsByUsername: const {'joffreyj': directMessage},
        chatMessagesByKey: const {
          '55': (
            messages: <ChatMessage>[],
            canLoadMorePast: false,
            canLoadMoreFuture: false,
            targetMessageId: null,
          ),
        },
      );
      final auth = FakeAuthenticator()
        ..keys['https://meta.discourse.org'] = 'api-key';

      await pumpShell(
        tester,
        phone,
        api: api,
        authenticator: auth,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: reader),
        ],
      );
      await tester.tap(find.text('Topics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(FilledButton, 'Chat'), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const ValueKey('user-card-surface'))).width,
        366,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Chat'));
      await tester.pumpAndSettle();

      expect(api.directMessageChannelsRequested, ['joffreyj']);
      expect(find.byType(ChatChannelView), findsOneWidget);
      expect(find.byKey(const ValueKey('user-card-surface')), findsNothing);
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

      await tester.tapAt(const Offset(20, 500));
      await tester.pumpAndSettle();
      expect(find.text('@joffreyj'), findsNothing);

      await tester.tap(find.text('Joffrey'));
      await tester.pumpAndSettle();

      expect(find.text('@joffreyj'), findsOneWidget);
      expect(api.cardsRequested, ['joffreyj']);
    });

    testWidgets('a card that fails to load offers a retry', (tester) async {
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
      expect(contentText('The other one [solved]'), findsOneWidget);
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

      final before = api.feedPaths.length;
      await tester.tap(find.text('A bug report'));
      await tester.pumpAndSettle();
      await tester.tap(find.dIcon(DIcons.arrowLeft));
      await tester.pumpAndSettle();

      expect(api.feedPaths.length, before);
      expect(find.text('A bug report'), findsOneWidget);
    });

    testWidgets('a cooked hashtag opens the list it names', (tester) async {
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

    List<DiscourseInstance> connectedSites({DiscourseUser user = me}) => [
      instance(
        'meta.discourse.org',
        title: 'Discourse Meta',
      ).copyWith(user: user),
      instance(
        'team.discourse.org',
        title: 'Discourse Team',
      ).copyWith(user: user),
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

    Future<void> openTopic(
      WidgetTester tester,
      FakeDiscourseApi api, {
      DiscourseUser user = me,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(user: user),
        authenticator: signedIn(),
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
    }

    Finder sendButton() => find.descendant(
      of: find.byType(ComposerPanel),
      matching: find.widgetWithText(FilledButton, 'Reply'),
    );

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

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('Shift R opens a topic reply only where replying is allowed', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: signedIn(),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isFalse);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyR), isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));
      expect(shell.visibleComposer?.target.replyToPostNumber, isNull);
    });

    testWidgets(
      'Shift R does not retarget a reply while its editor has focus',
      (tester) async {
        final api = FakeDiscourseApi(
          feeds: {'/latest.json': listed},
          topics: {7: detail()},
        );

        await openTopic(tester, api);
        await hoverPost(tester);
        await tester.tap(find.byTooltip('Reply to this post'));
        await tester.pumpAndSettle();

        final shell = ShellScope.read(
          tester.element(find.byType(ComposerPanel)),
        );
        expect(shell.visibleComposer?.target.replyToPostNumber, 1);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(shell.visibleComposer?.target.replyToPostNumber, 1);
      },
    );

    testWidgets('to a topic posts what was typed', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-reply-options')),
        findsNothing,
      );
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
      expect(api.created.single['replyToPostNumber'], isNull);

      expect(find.byType(ComposerPanel), findsNothing);
      expect(renderedText('Sounds good to me.'), findsOneWidget);
    });

    testWidgets('a whisperer can toggle and submit a whispered reply', (
      tester,
    ) async {
      const whisperer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        whisperer: true,
      );
      final api = FakeDiscourseApi(
        user: whisperer,
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openTopic(tester, api, user: whisperer);
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'For the team only.');
      await tester.pump();
      final shell = ShellScope.read(tester.element(find.byType(ComposerPanel)));

      final replyOptions = find.byKey(const ValueKey('composer-reply-options'));
      final composerTitle = find.byKey(const ValueKey('composer-title'));
      expect(replyOptions, findsOneWidget);
      expect(
        find.descendant(of: replyOptions, matching: find.text('Topic')),
        findsNothing,
      );
      expect(
        find.descendant(of: replyOptions, matching: find.dIcon(DIcons.reply)),
        findsOneWidget,
      );
      expect(
        tester.getTopRight(replyOptions).dx,
        lessThan(tester.getTopLeft(composerTitle).dx),
      );
      expect(tester.widget<Text>(composerTitle).data, 'Reply to A real topic');

      await tester.tap(replyOptions);
      await tester.pumpAndSettle();

      final toggle = find.byKey(const ValueKey('composer-toggle-whisper'));
      final whisperSwitch = find.byKey(
        const ValueKey('composer-whisper-switch'),
      );
      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(whisperSwitch).value, isFalse);

      await tester.tap(whisperSwitch);
      await tester.pump();

      expect(toggle, findsOneWidget);
      expect(tester.widget<Switch>(whisperSwitch).value, isTrue);
      expect(shell.visibleComposer?.whisper, isTrue);

      await shell.submitComposer();
      await tester.pumpAndSettle();

      expect(api.created.single['whisper'], isTrue);
    });

    testWidgets('to a post addresses it by post number', (tester) async {
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

    testWidgets('a reply to a whisper stays whispered without a toggle', (
      tester,
    ) async {
      const whisperer = DiscourseUser(username: 'joffreyj', whisperer: true);
      final api = FakeDiscourseApi(
        user: whisperer,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'moderator',
                cooked: '<p>Whisper body</p>',
                postType: Post.whisperPostType,
              ),
            ],
            stream: const [1, 2],
            postsCount: 2,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api, user: whisperer);
      await hoverPost(tester, body: 'Whisper body');
      await tester.tap(find.byTooltip('Reply to this post'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-reply-options')),
        findsNothing,
      );
      await tester.enterText(find.byType(TextField), 'Following up privately.');
      await tester.pumpAndSettle();
      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(api.created.single['replyToPostNumber'], 2);
      expect(api.created.single['whisper'], isTrue);
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

      expect(find.text('Your post is in the queue.'), findsOneWidget);
      expect(renderedText('Held for review.'), findsNothing);

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

      await tester.tap(find.text('DT'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.text('DM'));
      await tester.pumpAndSettle();
      await tester.tap(contentText('A real topic'));
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
        topics: {7: detail()},
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

      expect(api.created, hasLength(1));
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

      api.topics.remove(7);

      await tester.tap(sendButton());
      await tester.pumpAndSettle();

      expect(find.textContaining('may have posted'), findsOneWidget);
      final button = find.widgetWithText(FilledButton, 'Check again');
      expect(button, findsOneWidget);
      expect(find.text('Unknown fate.'), findsOneWidget);

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
      expect(find.byTooltip('Reply to this post'), findsNothing);

      final gesture = await hoverPost(tester);
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // Crossing onto the overlaid toolbar must not make the post lose its
      // hover target before the toolbar can receive the same pointer update.
      final toolbar = find.byType(HoverActionToolbar);
      await gesture.moveTo(tester.getCenter(toolbar));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      // The macOS embedder can report the overlaid toolbar's enter before the
      // post underneath exits. Neither callback ordering may close the menu.
      final toolbarRegion = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: toolbar,
              matching: find.byWidgetPredicate(
                (widget) => widget is MouseRegion && widget.onHover != null,
              ),
            )
            .first,
      );
      final postRegion = tester.widget<MouseRegion>(
        find
            .ancestor(
              of: renderedText('First post body'),
              matching: find.byWidgetPredicate(
                (widget) => widget is MouseRegion && widget.onHover != null,
              ),
            )
            .first,
      );
      toolbarRegion.onEnter!(const PointerEnterEvent());
      postRegion.onExit!(const PointerExitEvent());
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);
    });

    testWidgets('copy link writes core post URLs to the clipboard', (
      tester,
    ) async {
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
                username: 'sam',
                cooked: '<p>First post body</p>',
              ),
              Post(
                id: 2,
                postNumber: 2,
                username: 'sam',
                cooked: '<p>Second post body</p>',
              ),
            ],
            stream: const [1, 2],
            postsCount: 2,
            canCreatePost: true,
          ),
        },
      );
      final copied = watchClipboard(tester);

      await openTopic(tester, api);
      final gesture = await hoverPost(tester);

      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, [
        'https://meta.discourse.org/t/a-real-topic/7?u=joffreyj',
      ]);
      expect(find.text('Link copied!'), findsOneWidget);

      await gesture.moveTo(tester.getCenter(renderedText('Second post body')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, [
        'https://meta.discourse.org/t/a-real-topic/7?u=joffreyj',
        'https://meta.discourse.org/t/a-real-topic/7/2?u=joffreyj',
      ]);
    });

    testWidgets('copy link is available to anonymous readers', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(canCreatePost: false)},
      );
      final copied = watchClipboard(tester);

      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [instance('meta.discourse.org', title: 'Discourse Meta')],
      );
      await tester.tap(contentText('A real topic'));
      await tester.pumpAndSettle();
      await hoverPost(tester);

      expect(find.byTooltip('Reply to this post'), findsNothing);
      await tester.tap(find.byTooltip('Copy a link to this post to clipboard'));
      await tester.pumpAndSettle();

      expect(copied, ['https://meta.discourse.org/t/a-real-topic/7']);
    });

    testWidgets('scrolling hides the post menu until the pointer moves again', (
      tester,
    ) async {
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
      final gesture = await hoverPost(tester, body: 'Top of the long post');
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final scroll = await tester.startGesture(
        tester.getCenter(find.byType(TopicView)),
      );
      await scroll.moveBy(const Offset(0, -400));
      await tester.pump();

      // The toolbar leaves before the drag ends, rather than following the post
      // and recomputing its overlay position on every scroll tick.
      expect(find.byTooltip('Reply to this post'), findsNothing);
      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsNothing);

      await scroll.up();
      await tester.pumpAndSettle();

      // Ending the scroll is not enough: rows have moved under a stationary
      // pointer, so showing an action surface now would pick one accidentally.
      expect(find.byTooltip('Reply to this post'), findsNothing);

      await gesture.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
    });

    testWidgets('a recycled post stays closed under a stationary pointer', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              for (var i = 1; i <= 30; i++)
                Post(
                  id: i,
                  postNumber: i,
                  username: 'sam',
                  cooked: '<p>Post body $i</p>',
                ),
            ],
            stream: [for (var i = 1; i <= 30; i++) i],
            postsCount: 30,
            canCreatePost: true,
          ),
        },
      );

      await openTopic(tester, api);
      final list = find.byType(SuperListView);
      final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await pointer.addPointer(location: Offset.zero);
      addTearDown(pointer.removePointer);
      await pointer.moveTo(tester.getCenter(list));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);

      final scrollable = find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first;
      final position = tester.state<ScrollableState>(scrollable).position;
      position.jumpTo(1200);
      await tester.pump();
      await tester.pump();

      // A synchronous jump can build a fresh row after scrolling has
      // already ended. Its synthetic enter must not be mistaken for real
      // pointer movement and create an overlay during mouse hit testing.
      expect(find.byTooltip('Reply to this post'), findsNothing);
      expect(tester.takeException(), isNull);

      await pointer.moveBy(const Offset(0, 1));
      await tester.pump();
      expect(find.byTooltip('Reply to this post'), findsOneWidget);
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
      await tester.longPress(find.text('sam'));
      await tester.pumpAndSettle();

      // There is no pointer to hover with, so the same action is reached by
      // holding a non-selectable part of the post. Holding its body selects
      // text and opens the quote toolbar instead.
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
      await tester.tap(find.byTooltip('Save and close'));
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
      bool wiki = false,
      bool canWiki = false,
      DateTime? deletedAt,
    }) => Post(
      id: 1,
      postNumber: 1,
      username: 'joffreyj',
      cooked: '<p>First post body</p>',
      canEdit: canEdit,
      canDelete: canDelete,
      canRecover: canRecover,
      wiki: wiki,
      canWiki: canWiki,
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
      expect(find.byTooltip('Edit this post'), findsOneWidget);
      await tapPostAction(tester, 'Edit this post');
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
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      // Not a rule of ours — the site refuses an unchanged edit — but there is
      // no reason to spend a request finding that out.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('closing a changed edit asks before discarding it', (
      tester,
    ) async {
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
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Changed post body');
      await tester.pumpAndSettle();

      expect(find.text('Cancel edit'), findsOneWidget);
      await tester.tap(find.byTooltip('Close composer'));
      await tester.pumpAndSettle();

      expect(find.text('Do you want to discard your changes?'), findsOneWidget);
      expect(find.text('Discard changes'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Changed post body'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('an edit never saves over a post it could not read', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('re-reads a soft-deleted post and offers undo', (tester) async {
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
      await tapPostAction(tester, 'Delete this post');
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.text('deleted'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('More actions'), findsOneWidget);
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      expect(find.text('Undelete'), findsOneWidget);
      expect(find.byTooltip('Put this post back'), findsNothing);
      expect(find.byTooltip('Delete this post'), findsNothing);
    });

    testWidgets('a guardian-authorized post can become and stop being a wiki', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        post: mine(canWiki: true),
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First post body</p>',
            wiki: true,
            canWiki: true,
          ),
        },
      );

      final gesture = await hoverPost(tester);
      await tapPostAction(tester, 'Allow community members to edit this post');
      await tester.pumpAndSettle();

      expect(api.postWikiUpdates, const [(postId: 1, wiki: true)]);
      expect(find.text('wiki'), findsOneWidget);

      api.postsById[1] = const Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First post body</p>',
        wiki: false,
        canWiki: true,
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('First post body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Return this to ordinary post editing');
      await tester.pumpAndSettle();

      expect(api.postWikiUpdates, const [
        (postId: 1, wiki: true),
        (postId: 1, wiki: false),
      ]);
      expect(find.text('wiki'), findsNothing);
    });

    testWidgets('staff can lock and unlock an authored post', (tester) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Lockable body</p>',
          locked: true,
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Lockable body</p>',
              ),
            ],
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Lockable body');
      await tapPostAction(tester, 'Prevent further edits to this post');
      await tester.pumpAndSettle();
      expect(api.postLockUpdates, const [(postId: 1, locked: true)]);
      expect(find.text('locked'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Lockable body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Lockable body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Allow this post to be edited again');
      await tester.pumpAndSettle();

      expect(api.postLockUpdates, const [
        (postId: 1, locked: true),
        (postId: 1, locked: false),
      ]);
      expect(find.text('locked'), findsNothing);
    });

    testWidgets('staff can restore a flagged-hidden post', (tester) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Hidden body</p>',
                hidden: true,
              ),
            ],
          ),
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            userId: 7,
            username: 'joffreyj',
            cooked: '<p>Visible body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      expect(find.text('hidden'), findsOneWidget);
      await hoverPost(tester, body: 'Hidden body');
      await tapPostAction(tester, 'Restore this hidden post');
      await tester.pumpAndSettle();

      expect(api.postsUnhidden, [1]);
      expect(find.text('hidden'), findsNothing);
      expect(renderedText('Visible body'), findsOneWidget);
    });

    testWidgets('staff can convert and revert a moderator post', (
      tester,
    ) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Official body</p>',
          postType: Post.moderatorPostType,
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Official body</p>',
              ),
            ],
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Official body');
      await tapPostAction(tester, 'Mark this as an official moderator post');
      await tester.pumpAndSettle();
      expect(api.postTypeUpdates, const [
        (postId: 1, postType: Post.moderatorPostType),
      ]);
      expect(find.text('moderator'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Official body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Official body')));
      await tester.pumpAndSettle();
      await tapPostAction(
        tester,
        'Remove the moderator styling from this post',
      );
      await tester.pumpAndSettle();

      expect(api.postTypeUpdates, const [
        (postId: 1, postType: Post.moderatorPostType),
        (postId: 1, postType: Post.regularPostType),
      ]);
      expect(find.text('moderator'), findsNothing);
    });

    testWidgets('staff-note guardians can add and remove a post notice', (
      tester,
    ) async {
      const staff = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        staff: true,
      );
      final refreshed = <int, Post>{
        1: const Post(
          id: 1,
          postNumber: 1,
          userId: 7,
          username: 'joffreyj',
          cooked: '<p>Noticeable body</p>',
          notice: PostNotice(
            type: 'custom',
            raw: 'Please read this carefully.',
            cooked: '<p>Please <strong>read</strong> this carefully.</p>',
          ),
        ),
      };
      final api = FakeDiscourseApi(
        user: staff,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Noticeable body</p>',
              ),
            ],
            canEditStaffNotes: true,
          ),
        },
        postsById: refreshed,
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(user: staff),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      final gesture = await hoverPost(tester, body: 'Noticeable body');
      await tapPostAction(tester, 'Add a staff notice above this post');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('post-notice-text')),
        '  Please read this carefully.  ',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-notice-save')));
      await tester.pumpAndSettle();

      expect(api.postNoticeUpdates, const [
        (postId: 1, notice: 'Please read this carefully.'),
      ]);
      expect(find.byKey(const ValueKey('post-notice-1')), findsOneWidget);
      expect(renderedText('Please read this carefully.'), findsOneWidget);

      refreshed[1] = const Post(
        id: 1,
        postNumber: 1,
        userId: 7,
        username: 'joffreyj',
        cooked: '<p>Noticeable body</p>',
      );
      await gesture.moveTo(Offset.zero);
      await tester.pump();
      await gesture.moveTo(tester.getCenter(renderedText('Noticeable body')));
      await tester.pumpAndSettle();
      await tapPostAction(tester, 'Change or remove the staff notice');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('post-notice-delete')));
      await tester.pumpAndSettle();

      expect(api.postNoticeUpdates, const [
        (postId: 1, notice: 'Please read this carefully.'),
        (postId: 1, notice: null),
      ]);
      expect(find.byKey(const ValueKey('post-notice-1')), findsNothing);
    });

    testWidgets('post-owner guardians can reassign one post directly', (
      tester,
    ) async {
      const ownerGuardian = DiscourseUser(
        id: 9,
        username: 'moderator',
        name: 'Moderator',
        canChangePostOwner: true,
      );
      final api = FakeDiscourseApi(
        user: ownerGuardian,
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [
              Post(
                id: 1,
                postNumber: 1,
                userId: 7,
                username: 'joffreyj',
                cooked: '<p>Owned body</p>',
              ),
            ],
          ),
        },
        userSearches: const {
          'kris': [FoundUser(username: 'kris', name: 'Kris')],
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            userId: 12,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>Owned body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Meta',
          ).copyWith(user: ownerGuardian),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();

      await hoverPost(tester, body: 'Owned body');
      await tapPostAction(tester, 'Assign this post to another account');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-change-owner-search')),
        'kris',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
      await tester.pumpAndSettle();

      expect(api.postOwnersChanged, hasLength(1));
      expect(api.postOwnersChanged.single.topicId, 7);
      expect(api.postOwnersChanged.single.postIds, [1]);
      expect(api.postOwnersChanged.single.username, 'kris');
      expect(find.text('Kris'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('admins can permanently delete a reply after preflight', (
      tester,
    ) async {
      final deletedReply = Post(
        id: 2,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Deleted reply body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canRecover: true,
        canPermanentlyDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [
              const Post(
                id: 1,
                postNumber: 1,
                username: 'joffreyj',
                cooked: '<p>First permanent body</p>',
              ),
              deletedReply,
            ],
          ),
        },
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>First permanent body</p>',
          ),
        },
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

      await hoverPost(tester, body: 'Deleted reply body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();
      expect(api.permanentDeletionChecks, [2]);
      expect(
        find.byKey(const ValueKey('post-permanent-delete-dialog')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('post-permanent-delete-confirmation')),
        'PERMANENTLY DELETE',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('post-permanent-delete-submit')),
      );
      await tester.pumpAndSettle();

      expect(api.postsPermanentlyDeleted, const [(topicId: 7, postId: 2)]);
      expect(renderedText('Deleted reply body'), findsNothing);
      expect(renderedText('First permanent body'), findsOneWidget);
    });

    testWidgets('permanent-delete preflight surfaces the server refusal', (
      tester,
    ) async {
      final deletedReply = Post(
        id: 2,
        postNumber: 2,
        username: 'sam',
        cooked: '<p>Cooldown reply body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canPermanentlyDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(id: 7, title: 'A real topic', posts: [deletedReply]),
        },
        permanentDeletionAllowed: false,
        permanentDeletionReason: 'Wait five minutes or use another admin.',
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

      await hoverPost(tester, body: 'Cooldown reply body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();

      expect(api.permanentDeletionChecks, [2]);
      expect(
        find.text('Wait five minutes or use another admin.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('post-permanent-delete-dialog')),
        findsNothing,
      );
      expect(api.postsPermanentlyDeleted, isEmpty);
    });

    testWidgets('permanently deleting the opening post removes the topic', (
      tester,
    ) async {
      final openingPost = Post(
        id: 1,
        postNumber: 1,
        username: 'sam',
        cooked: '<p>Deleted opening body</p>',
        deletedAt: DateTime.utc(2026, 8, 25),
        canRecover: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: [openingPost],
            deletedAt: DateTime.utc(2026, 8, 25),
            canRecoverTopic: true,
            canPermanentlyDelete: true,
          ),
        },
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

      await hoverPost(tester, body: 'Deleted opening body');
      await tapPostAction(tester, 'Permanently delete this post');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('post-permanent-delete-confirmation')),
        'permanently delete',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('post-permanent-delete-submit')),
      );
      await tester.pumpAndSettle();

      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(api.permanentDeletionChecks, [1]);
      expect(api.topicsPermanentlyDeleted, [7]);
      expect(shell.currentContent?.topicId, isNull);
      expect(find.byType(TopicView), findsNothing);
      expect(renderedText('Deleted opening body'), findsNothing);
    });

    testWidgets('selects, merges, and bulk-deletes guardian-authorized posts', (
      tester,
    ) async {
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First selected body</p>',
        canDelete: true,
      );
      const second = Post(
        id: 2,
        postNumber: 2,
        username: 'joffreyj',
        cooked: '<p>Second selected body</p>',
        canDelete: true,
      );
      const third = Post(
        id: 3,
        postNumber: 3,
        username: 'sam',
        cooked: '<p>Third selected body</p>',
        canDelete: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [first, second, third],
            canSplitMergeTopic: true,
          ),
        },
        postsById: {
          1: const Post(
            id: 1,
            postNumber: 1,
            username: 'joffreyj',
            cooked: '<p>Merged selected body</p>',
            canDelete: true,
          ),
        },
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

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.tap(find.byKey(const ValueKey('topic-post-select-2')));
      await tester.pumpAndSettle();
      expect(find.text('2 posts selected'), findsOneWidget);

      final mergeAction = find.byKey(
        const ValueKey('topic-selected-posts-merge'),
      );
      await tester.ensureVisible(mergeAction);
      await tester.tap(mergeAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-selected-merge-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.merged, const [
        [1, 2],
      ]);
      expect(renderedText('Merged selected body'), findsOneWidget);
      expect(renderedText('Second selected body'), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-3')));
      await tester.pumpAndSettle();
      final deleteAction = find.byKey(
        const ValueKey('topic-selected-posts-delete'),
      );
      await tester.ensureVisible(deleteAction);
      await tester.tap(deleteAction);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('topic-selected-delete-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.bulkDeleted, const [
        [3],
      ]);
      expect(renderedText('Third selected body'), findsNothing);
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('moves selected posts to a searched existing topic', (
      tester,
    ) async {
      const sourcePosts = [
        Post(
          id: 1,
          postNumber: 1,
          username: 'joffreyj',
          cooked: '<p>Move this body</p>',
        ),
        Post(
          id: 2,
          postNumber: 2,
          username: 'sam',
          cooked: '<p>Leave this body</p>',
        ),
      ];
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: sourcePosts,
            canMovePosts: true,
          ),
          99: topicPayload(
            id: 99,
            title: 'Destination topic',
            posts: const [
              Post(
                id: 99,
                postNumber: 1,
                username: 'sam',
                cooked: '<p>Destination body</p>',
              ),
            ],
          ),
        },
        searchResults: const {
          'Destination': SearchResults(
            hits: [
              SearchPostHit(
                postId: 99,
                topicId: 99,
                postNumber: 1,
                topicTitle: 'Destination topic',
                topicSlug: 'destination-topic',
                username: 'sam',
                excerpt: SearchExcerpt([]),
              ),
            ],
          ),
        },
      );
      api.topicMoveUrl = '/t/destination-topic/99';
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
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-selected-posts-move')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Existing topic'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('topic-move-posts-search')),
        'Destination',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Destination topic'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('topic-move-posts-chronological')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('topic-move-posts-submit')));
      await tester.pumpAndSettle();

      expect(api.movedTopicPosts, hasLength(1));
      expect(api.movedTopicPosts.single.topicId, 7);
      expect(api.movedTopicPosts.single.postIds, [1]);
      expect(api.movedTopicPosts.single.destinationTopicId, 99);
      expect(api.movedTopicPosts.single.chronologicalOrder, isTrue);
      expect(renderedText('Destination body'), findsOneWidget);
      expect(api.topicsOpened, contains(99));
    });

    testWidgets('changes the owner of same-author selected posts', (
      tester,
    ) async {
      const first = Post(
        id: 1,
        postNumber: 1,
        username: 'joffreyj',
        cooked: '<p>First owner body</p>',
      );
      const second = Post(
        id: 2,
        postNumber: 2,
        username: 'joffreyj',
        cooked: '<p>Second owner body</p>',
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {
          7: topicPayload(
            id: 7,
            title: 'A real topic',
            posts: const [first, second],
            canSplitMergeTopic: true,
          ),
        },
        userSearches: const {
          'kris': [FoundUser(username: 'kris', name: 'Kris')],
        },
        user: const DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          canChangePostOwner: true,
        ),
        postsById: const {
          1: Post(
            id: 1,
            postNumber: 1,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>First owner body</p>',
          ),
          2: Post(
            id: 2,
            postNumber: 2,
            username: 'kris',
            name: 'Kris',
            cooked: '<p>Second owner body</p>',
          ),
        },
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance('meta.discourse.org', title: 'Meta').copyWith(
            user: const DiscourseUser(
              username: 'joffreyj',
              name: 'Joffrey',
              canChangePostOwner: true,
            ),
          ),
        ],
        authenticator: FakeAuthenticator()
          ..keys['https://meta.discourse.org'] = 'meta-key',
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-status-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-select-posts')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('topic-post-select-1')));
      await tester.tap(find.byKey(const ValueKey('topic-post-select-2')));
      await tester.pumpAndSettle();
      final action = find.byKey(
        const ValueKey('topic-selected-posts-change-owner'),
      );
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('topic-change-owner-search')),
        'kris',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Kris'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('topic-change-owner-submit')));
      await tester.pumpAndSettle();

      expect(api.postOwnersChanged, hasLength(1));
      expect(api.postOwnersChanged.single.topicId, 7);
      expect(api.postOwnersChanged.single.postIds, [1, 2]);
      expect(api.postOwnersChanged.single.username, 'kris');
      expect(find.text('Kris'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('topic-selected-posts-toolbar')),
        findsNothing,
      );
    });

    testWidgets('a post that is really gone stops being drawn', (tester) async {
      // Nothing comes back for the id, which is the site saying it is no
      // longer there — or no longer ours to see.
      final api = await openTopic(tester, post: mine());

      await hoverPost(tester);
      await tapPostAction(tester, 'Delete this post');
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
      await tapPostAction(tester, 'Put this post back');
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
      await tapPostAction(tester, 'Delete this post');
      await tester.pumpAndSettle();

      expect(api.deleted, [1]);
      expect(find.textContaining("You can't post that here"), findsOneWidget);
      expect(renderedText('First post body'), findsOneWidget);
    });

    testWidgets('on a touch screen the same actions arrive as a sheet', (
      tester,
    ) async {
      await openTopic(tester, post: mine());

      await tester.longPress(find.text('joffreyj'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Reply'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Edit'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Delete'), findsOneWidget);
    });
  });

  group('optional site features', () {
    const site = 'https://meta.discourse.org';

    final reactionsOn = installedPlugins.models.siteConfig(const {
      'emoji_set': 'apple',
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    }, site);

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
        plugins: installedPlugins,
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

    testWidgets('site settings load with category navigation and are reused', (
      tester,
    ) async {
      final api = serving(configs: {site: reactionsOn});
      final controller = controllerWith(tester, api);
      await controller.load();
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
      expect(controller.siteConfigFor(site).emojiSet, 'apple');
      expect(controller.siteConfigFor(site).mainReaction, 'heart');

      await controller.loadTopic(7, 'a-real-topic');
      await tester.pump();

      expect(api.siteConfigsRequested, [site]);
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

      expect(controller.siteConfigFor(site), const SiteConfig.unknown());
    });

    testWidgets('a site that will not answer is given up on, not hammered', (
      tester,
    ) async {
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

    Finder count(String value) =>
        find.descendant(of: find.byType(PostLikes), matching: find.text(value));

    testWidgets('a post nobody has liked says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, first: post());

      expect(find.byType(PostLikes), findsOneWidget);
      expect(count('0'), findsNothing);

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

      expect(count('1'), findsOneWidget);
      expect(find.byTooltip('Remove your like'), findsNothing);
      expect(find.byTooltip('Like this post'), findsNothing);
    });

    testWidgets('the site has the last word on the count', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.likersRequested, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(api.likersRequested, [1]);
      expect(find.text('Sam Saffron'), findsOneWidget);
      expect(find.text('codinghorror'), findsOneWidget);

      await gesture.moveTo(Offset.zero);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(find.text('Sam Saffron'), findsNothing);
    });

    testWidgets('a failed liker lookup explains that names are unavailable', (
      tester,
    ) async {
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

      await tester.longPress(count('1'));
      await tester.pumpAndSettle();

      expect(find.text('1 like'), findsOneWidget);
      expect(find.text('Sam Saffron'), findsOneWidget);
    });

    testWidgets('liking with the panel open leaves it saying something true', (
      tester,
    ) async {
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

      await gesture.down(pill);
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.textContaining('Too fast'), findsOneWidget);
      expect(count('2'), findsOneWidget);
      expect(activityIndicators, findsNothing);
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
        first: const Post(
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
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
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

    final configured = installedPlugins.models.siteConfig(const {
      'discourse_reactions_enabled': true,
      'discourse_reactions_reaction_for_like': 'heart',
      'discourse_reactions_enabled_reactions': '+1|clap',
    }, site);

    Post post({
      int id = 1,
      List<({String id, int count})> reactions = const [],
      String? mine,
      int userCount = 0,
      bool canAct = true,
      bool canUndo = false,
      bool plugin = true,
      bool canEdit = false,
    }) => Post.fromJson(
      {
        'id': id,
        'post_number': id,
        'username': 'sam',
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
      },
      site,
      extensions: pluginRegistry,
    );

    Future<FakeDiscourseApi> openTopic(
      WidgetTester tester, {
      required List<Post> posts,
      SiteConfig? config,
      Map<String, String> customEmojis = const {},
      List<SiteEmoji> emojis = const [],
      Map<String, PostReactors> reactorsById = const {},
      Map<int, Post> postsById = const {},
      Map<int, Post> reactionResponses = const {},
      WriteException? reactionFailure,
      Completer<void>? reactionGate,
      Completer<void>? siteConfigGate,
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
        siteConfigGate: siteConfigGate,
        customEmojisBySite: customEmojis.isEmpty
            ? const {}
            : {site: customEmojis},
        emojisBySite: emojis.isEmpty ? const {} : {site: emojis},
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

    testWidgets('an existing reaction row offers another configured reaction', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );
      final semantics = tester.ensureSemantics();
      try {
        final launcher = find.bySemanticsLabel('Add reaction');
        expect(launcher, findsOneWidget);
        expect(tester.getSize(launcher), const Size.square(44));
        expect(
          tester.getSemantics(launcher),
          isSemantics(isButton: true, isFocusable: true, hasTapAction: true),
        );

        await tester.tap(launcher);
        await tester.pumpAndSettle();

        expect(find.byType(ReactionGrid), findsOneWidget);
        await tester.tap(find.bySemanticsLabel('+1'));
        await tester.pumpAndSettle();

        expect(api.reacted, [(postId: 1, reaction: '+1')]);
        expect(find.bySemanticsLabel('1 +1 reaction'), findsOneWidget);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('an any-emoji post reaction row opens the full picker', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();

      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'wave')]);
      expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
    });

    testWidgets('the post picker waits for the site reaction policy', (
      tester,
    ) async {
      final gate = Completer<void>();
      await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
        siteConfigGate: gate,
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pump();
      expect(find.byType(ReactionGrid), findsNothing);
      expect(find.byType(EmojiPicker), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ReactionGrid), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);
    });

    testWidgets('a picker cannot react after the post loses permission', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 2)], userCount: 2),
        ],
      );
      final controller = ShellScope.read(
        tester.element(find.byType(ReactionsRow)),
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();
      controller.store.put(
        site,
        post(reactions: [(id: 'clap', count: 2)], userCount: 2, canAct: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);

      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, isEmpty);
    });

    testWidgets('the full picker survives its last post pill disappearing', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: installedPlugins.models.siteConfig(const {
          'discourse_reactions_enabled': true,
          'discourse_reactions_reaction_for_like': 'heart',
          'discourse_reactions_enabled_reactions': 'clap',
          'discourse_reactions_allow_any_emoji': true,
        }, site),
        emojis: const [
          SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
        ],
        posts: [
          post(reactions: [(id: 'clap', count: 1)], userCount: 1),
        ],
      );
      final controller = ShellScope.read(
        tester.element(find.byType(ReactionsRow)),
      );

      await tester.tap(find.bySemanticsLabel('Add reaction'));
      await tester.pumpAndSettle();
      controller.store.put(site, post());
      await tester.pumpAndSettle();

      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(find.byType(EmojiPicker), findsOneWidget);
      await tester.tap(find.byTooltip(':wave:'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'wave')]);
    });

    testWidgets('a post nobody has reacted to says so by saying nothing', (
      tester,
    ) async {
      await openTopic(tester, config: configured, posts: [post()]);

      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('0'), findsNothing);
      expect(find.byType(ReactionPickerButton), findsNothing);
    });

    testWidgets('clicking an existing reaction adds the reader to it', (
      tester,
    ) async {
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
              PostReactor(id: 4, username: 'ada', reaction: 'clap'),
            ],
          ),
        },
      );
      final semantics = tester.ensureSemantics();
      final target = find.bySemanticsLabel('2 clap reactions');
      final semanticTarget = find.semantics.byLabel('2 clap reactions');

      expect(
        tester.getSemantics(target).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      tester.semantics.tap(semanticTarget);
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(find.byType(ReactorList), findsNothing);
      expect(pill('3'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a read-only reaction still opens its reactor list', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 2)],
            userCount: 2,
            canAct: false,
          ),
        ],
        reactorsById: {
          '1:clap': const PostReactors(
            postId: 1,
            filter: 'clap',
            total: 2,
            reactors: [
              PostReactor(id: 3, username: 'sam', reaction: 'clap'),
              PostReactor(id: 4, username: 'ada', reaction: 'clap'),
            ],
          ),
        },
      );

      await tester.tap(find.bySemanticsLabel('2 clap reactions'));
      await tester.pumpAndSettle();

      expect(find.byType(ReactorList), findsOneWidget);
      expect(find.byType(ReactionPickerButton), findsNothing);
      expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
      expect(api.reacted, isEmpty);
    });

    testWidgets('a touch long press opens reactors without changing reaction', (
      tester,
    ) async {
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
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
                PostReactor(id: 4, username: 'ada', reaction: 'clap'),
              ],
            ),
          },
        );

        await tester.longPress(find.bySemanticsLabel('2 clap reactions'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactorList), findsOneWidget);
        expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
        expect(api.reacted, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = previous;
      }
    });

    testWidgets('clicking another reaction changes the one the reader holds', (
      tester,
    ) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'heart', count: 2), (id: 'clap', count: 1)],
            mine: 'heart',
            userCount: 3,
            canAct: false,
            canUndo: true,
          ),
        ],
      );

      await tester.tap(find.bySemanticsLabel('1 clap reaction'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(pill('1'), findsOneWidget);
      expect(pill('2'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
        isSemantics(isSelected: true),
      );
    });

    testWidgets('clicking the highlighted reaction removes it', (tester) async {
      final api = await openTopic(
        tester,
        config: configured,
        posts: [
          post(
            reactions: [(id: 'clap', count: 1)],
            mine: 'clap',
            userCount: 1,
            canAct: false,
            canUndo: true,
          ),
        ],
      );

      await tester.tap(find.bySemanticsLabel('1 clap reaction'));
      await tester.pumpAndSettle();

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
      expect(find.byType(ReactionsRow), findsOneWidget);
      expect(pill('1'), findsNothing);
    });

    testWidgets('a post on a site without the plugin keeps its likes', (
      tester,
    ) async {
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

      expect(api.reacted, [(postId: 1, reaction: 'clap')]);
    });

    testWidgets('a reaction can be picked from the grid', (tester) async {
      final api = await openTopic(tester, config: configured, posts: [post()]);

      await hoverPost(tester);
      await tester.tap(find.byTooltip('Pick a reaction'));
      await tester.pumpAndSettle();

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

    testWidgets('an any-emoji site opens the full picker from the toolbar', (
      tester,
    ) async {
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final api = await openTopic(
          tester,
          config: installedPlugins.models.siteConfig(const {
            'discourse_reactions_enabled': true,
            'discourse_reactions_reaction_for_like': 'heart',
            'discourse_reactions_enabled_reactions': 'clap',
            'discourse_reactions_allow_any_emoji': true,
          }, site),
          emojis: const [
            SiteEmoji(name: 'wave', url: 'https://meta.discourse.org/wave.png'),
          ],
          posts: [post()],
        );

        await hoverPost(tester);
        final launcherRect = tester.getRect(find.byTooltip('Pick a reaction'));
        await tester.tap(find.byTooltip('Pick a reaction'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactionGrid), findsNothing);
        expect(find.byType(EmojiPicker), findsOneWidget);
        final pickerRect = tester.getRect(
          find.byKey(const ValueKey('emoji-picker-desktop-popover')),
        );
        expect(pickerRect.top, closeTo(launcherRect.bottom + 8, 0.01));
        expect(
          launcherRect.center.dx,
          inInclusiveRange(pickerRect.left, pickerRect.right),
        );

        await tester.tap(find.byTooltip(':wave:'));
        await tester.pumpAndSettle();

        expect(api.reacted, [(postId: 1, reaction: 'wave')]);
        expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
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
      expect(pill('3'), findsOneWidget);
      expect(pill('9'), findsNothing);

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
      await tapPostAction(tester, 'Edit this post');
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'First post body!');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(api.updated, hasLength(1));
      expect(renderedText('First post body!'), findsOneWidget);
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

      expect(api.reactorsRequested, [(postId: 1, filter: 'clap')]);
      final named = find.descendant(
        of: find.byType(ReactorList),
        matching: find.text('sam'),
      );
      expect(named, findsOneWidget);
      expect(find.text('codinghorror'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ReactorList),
          matching: find.byType(SiteEmojiImage),
        ),
        findsNothing,
      );
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
      expect(tracker.watchedChannels, [
        '/topic/7',
        '/topic/7/reactions',
        '/polls/7',
        '/staff/topic-assignment',
      ]);

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

    testWidgets("a write of this reader's own is not read back over", (
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

    testWidgets('a failed reactor lookup explains that names are unavailable', (
      tester,
    ) async {
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

      final field = tester.widget<TextField>(find.byType(TextField));
      field.controller!.selection = const TextSelection(
        baseOffset: 4,
        extentOffset: 9,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.dIcon(DIcons.bold));
      await tester.pumpAndSettle();
      expect(field.controller!.text, 'say **hello**');

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

      expect(fake.created.single['raw'], 'hey @sa');
    });

    testWidgets('offers emoji without asking the site again', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'a :sm');
      await tester.pumpAndSettle();

      expect(find.text('smile'), findsOneWidget);
      expect(find.text('smirk'), findsOneWidget);
      expect(fake.emojisRequested, ['https://meta.discourse.org']);
    });

    testWidgets('offers categories and tags once # is typed', (tester) async {
      final fake = api();
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'see #ran');
      await tester.pumpAndSettle();

      expect(fake.hashtagSearchesRequested, ['ran']);
      expect(find.text('Random'), findsOneWidget);
      expect(find.text('random'), findsOneWidget);
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
      await tester.tap(find.text('Sam Saffron'));
      await tester.pumpAndSettle();

      expect(field(tester).controller!.text, 'hey @sam ');
      expect(find.byType(MentionPill), findsOneWidget);
      expect(fake.mentionChecksRequested, isEmpty);
    });

    testWidgets('a mention uses the hand cursor over its pill', (tester) async {
      final fake = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
        realUsernames: const {'sam'},
      );
      await openComposer(tester, fake);

      await tester.enterText(find.byType(TextField), 'hey @sam there');
      await tester.pumpAndSettle();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.moveTo(tester.getCenter(find.text('@sam')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.click,
      );

      await mouse.moveTo(tester.getCenter(find.byType(TextField)));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.text,
      );
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

      expect(field(tester).controller!.text, 'a :smirk: ');
    });

    testWidgets('draws the artwork for a shortcode that was written', (
      tester,
    ) async {
      // Controller tests inject the resolver and cannot catch shell wiring gaps.
      await openComposer(tester, api());

      // Override the shell fixture's network-free emoji fallback for this case.
      _replaceEmojiCache(
        EmojiCache(
          client: MockClient((_) async => http.Response.bytes(emojiPng, 200)),
        ),
      );

      await tester.enterText(find.byType(TextField), 'hey :smile:');
      await tester.pumpAndSettle();

      expect(find.byType(EmojiImage), findsOneWidget);
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
      FakeAuthenticator? authenticator,
    }) async {
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: connectedSites(),
        authenticator: authenticator ?? signedIn(),
        drafts: drafts,
      );
      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
    }

    Future<void> settleDraft(WidgetTester tester) async {
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
    }

    testWidgets('discard closes an empty reply without confirmation', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 0,
        ),
      ]);
    });

    testWidgets('save and close removes an empty reply draft', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api);
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 0,
        ),
      ]);
    });

    testWidgets('close waits for draft restoration before choosing an action', (
      tester,
    ) async {
      final drafts = _GatedDraftReadStore();
      addTearDown(() {
        if (!drafts.release.isCompleted) drafts.release.complete();
      });
      await drafts.write(
        'https://meta.discourse.org',
        'topic_7',
        const ComposerDraft(reply: 'Restored after close was pressed').encode(),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api, drafts: drafts);
      expect(drafts.started.isCompleted, isTrue);
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pump();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.userDraftsDeleted, isEmpty);

      drafts.release.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(drafts.saved.values.single, contains('Restored after close'));
    });

    testWidgets('a failed local read is retried before close can delete', (
      tester,
    ) async {
      final drafts = _FlakyDraftStore(readFailures: 1);
      await drafts.write(
        'https://meta.discourse.org',
        'topic_7',
        const ComposerDraft(reply: 'Temporarily unreadable').encode(),
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail()},
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      expect(shell.visibleComposer?.text.text, isEmpty);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(api.userDraftsDeleted, isEmpty);

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(drafts.saved.values.single, contains('Temporarily unreadable'));
    });

    testWidgets('close does not delete an unseen draft after restore fails', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreFailure: const WriteException(WriteFailure.unreachable),
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Recovered server draft',
            title: 'Recovered title',
          ),
          sequence: 3,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't check for an existing draft. Try again."),
        findsOneWidget,
      );
      expect(api.userDraftsDeleted, isEmpty);

      api.draftRestoreFailure = null;
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
    });

    testWidgets('closing a PM preserves a draft for different recipients', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canSendPrivateMessages: true,
      );
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        user: writer,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Message for moderators',
            title: 'Moderation question',
            action: ComposerDraft.privateMessageAction,
            archetypeId: ComposerDraft.privateMessageArchetype,
            recipients: 'moderators',
          ),
          sequence: 5,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      shell.openPrivateMessage(
        siteUrl: 'https://meta.discourse.org',
        targetRecipients: 'tech-leads',
      );
      await tester.pumpAndSettle();

      expect(shell.visibleComposer?.text.text, isEmpty);
      expect(shell.visibleComposer?.hasUnappliedDraft, isTrue);
      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(api.draftsSaved, isEmpty);
    });

    testWidgets('discarding a fresh PM cannot delete another PM draft', (
      tester,
    ) async {
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canSendPrivateMessages: true,
      );
      final api = FakeDiscourseApi(
        user: writer,
        feeds: {'/latest.json': listed},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Message for moderators',
            title: 'Moderation question',
            action: ComposerDraft.privateMessageAction,
            archetypeId: ComposerDraft.privateMessageArchetype,
            recipients: 'moderators',
          ),
          sequence: 5,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      shell.openPrivateMessage(
        siteUrl: 'https://meta.discourse.org',
        targetRecipients: 'tech-leads',
      );
      await tester.pump();
      shell.visibleComposer!.text.text = 'A new message not saved yet';
      restoreGate.complete();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer!.protectsUnappliedDraft, isTrue);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, isEmpty);
      expect(api.draftsSaved, isEmpty);
    });

    testWidgets(
      'discard restores another PM after its replacement save was in flight',
      (tester) async {
        final saveGate = Completer<void>();
        addTearDown(() {
          if (!saveGate.isCompleted) saveGate.complete();
        });
        const writer = DiscourseUser(
          username: 'joffreyj',
          name: 'Joffrey',
          canSendPrivateMessages: true,
        );
        const preserved = ComposerDraft(
          reply: 'Message for moderators',
          title: 'Moderation question',
          action: ComposerDraft.privateMessageAction,
          archetypeId: ComposerDraft.privateMessageArchetype,
          recipients: 'moderators',
        );
        final drafts = FakeDraftStore();
        final api = FakeDiscourseApi(
          user: writer,
          feeds: {'/latest.json': listed},
          draftGate: saveGate,
          draftToRestore: const (draft: preserved, sequence: 5),
        );
        await pumpShell(
          tester,
          desktop,
          api: api,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: writer),
          ],
          authenticator: signedIn(),
          drafts: drafts,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.openPrivateMessage(
          siteUrl: 'https://meta.discourse.org',
          targetRecipients: 'tech-leads',
        );
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        expect(composer.protectsUnappliedDraft, isTrue);
        composer
          ..title.text = 'Replacement title'
          ..text.text = 'Replacement already saving';
        await tester.pump(ComposerController.draftDebounce);
        await tester.pump();
        expect(api.draftsSaved, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('composer-discard')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('composer-confirm-discard')),
        );
        await tester.pump();
        expect(composer.discarding, isTrue);

        saveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsNothing);
        expect(api.userDraftsDeleted, isEmpty);
        expect(api.draftsSaved, hasLength(2));
        expect(
          api.draftsSaved.first['data'],
          contains('Replacement already saving'),
        );
        expect(api.draftsSaved.last['sequence'], 6);
        expect(api.draftsSaved.last['data'], preserved.encode());
        expect(drafts.saved, isEmpty);
      },
    );

    testWidgets(
      'discard keeps a local PM after its replacement save was in flight',
      (tester) async {
        final saveGate = Completer<void>();
        addTearDown(() {
          if (!saveGate.isCompleted) saveGate.complete();
        });
        const writer = DiscourseUser(
          username: 'joffreyj',
          name: 'Joffrey',
          canSendPrivateMessages: true,
        );
        const preserved = ComposerDraft(
          reply: 'Local message for moderators',
          title: 'Local moderation question',
          action: ComposerDraft.privateMessageAction,
          archetypeId: ComposerDraft.privateMessageArchetype,
          recipients: 'moderators',
        );
        final drafts = FakeDraftStore();
        await drafts.write(
          'https://meta.discourse.org',
          ComposerDraft.newPrivateMessageDraftKey,
          preserved.encode(),
        );
        final api = FakeDiscourseApi(
          user: writer,
          feeds: {'/latest.json': listed},
          draftGate: saveGate,
        );
        await pumpShell(
          tester,
          desktop,
          api: api,
          instances: [
            instance(
              'meta.discourse.org',
              title: 'Discourse Meta',
            ).copyWith(user: writer),
          ],
          authenticator: signedIn(),
          drafts: drafts,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        shell.openPrivateMessage(
          siteUrl: 'https://meta.discourse.org',
          targetRecipients: 'tech-leads',
        );
        await tester.pumpAndSettle();
        final composer = shell.visibleComposer!;
        expect(composer.protectsUnappliedDraft, isTrue);
        composer
          ..title.text = 'Replacement title'
          ..text.text = 'Replacement already saving';
        await tester.pump(ComposerController.draftDebounce);
        await tester.pump();
        expect(api.draftsSaved, hasLength(1));

        await tester.tap(find.byKey(const ValueKey('composer-discard')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('composer-confirm-discard')),
        );
        await tester.pump();
        saveGate.complete();
        await tester.pumpAndSettle();

        expect(find.byType(ComposerPanel), findsNothing);
        expect(api.draftsSaved, hasLength(1));
        expect(api.userDraftsDeleted, const [
          (
            siteUrl: 'https://meta.discourse.org',
            draftKey: ComposerDraft.newPrivateMessageDraftKey,
            sequence: 1,
          ),
        ]);
        expect(drafts.saved.values.single, preserved.encode());
      },
    );

    testWidgets('a late restore cannot regress the draft sequence', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(reply: 'Older server snapshot'),
          sequence: 1,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pump();
      final composer = shell.visibleComposer!;
      composer.title.text = 'A topic title';
      composer.text.text = 'First local revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));
      composer.text.text = 'Second local revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(2));

      restoreGate.complete();
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();
      expect(composer.draftSequence, 2);
      expect(composer.text.text, 'Second local revision');

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(api.userDraftsDeleted.single.sequence, 2);
    });

    testWidgets('a late restore preserves taxonomy and advances its sequence', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        canCreateTopic: true,
      );
      final restoreGate = Completer<void>();
      addTearDown(() {
        if (!restoreGate.isCompleted) restoreGate.complete();
      });
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        creatableFeedPaths: const {'/latest.json'},
        draftRestoreGate: restoreGate,
        draftToRestore: const (
          draft: ComposerDraft(
            reply: 'Older server text',
            title: 'Older title',
            categoryId: 3,
          ),
          sequence: 7,
        ),
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await shell.openNewTopic();
      await tester.pump();
      final composer = shell.visibleComposer!;
      composer.setCategory(99);

      restoreGate.complete();
      await tester.pump(ComposerController.draftDebounce);
      await tester.pumpAndSettle();

      expect(composer.categoryId, 99);
      expect(composer.title.text, isEmpty);
      expect(composer.text.text, isEmpty);
      expect(composer.draftSequence, 8);
      expect(api.draftsSaved.single['sequence'], 7);
      expect(api.draftsSaved.single['data'], contains('"categoryId":99'));
    });

    testWidgets('discard confirmation can keep or remove a changed reply', (
      tester,
    ) async {
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Come back to this');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();

      expect(find.text('Do you want to discard your post?'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      expect(find.text('Come back to this'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsNothing,
      );
      expect(find.text('Come back to this'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsNothing);
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 5,
        ),
      ]);
      expect(drafts.saved, isEmpty);
      expect(drafts.events.last, 'clear');
    });

    testWidgets('composer discard removes the cached draft and badge', (
      tester,
    ) async {
      const draft = ComposerDraft(reply: 'Draft from the list');
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 1,
      );
      final api = FakeDiscourseApi(
        user: writer,
        userDraftList: const [
          UserDraft(
            key: 'topic_7',
            sequence: 4,
            data: draft,
            topicId: 7,
            title: 'A real topic',
            slug: 'a-real-topic',
          ),
        ],
        feeds: {'/latest.json': listed},
        topics: {7: detail(draft: draft, draftSequence: 4)},
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await shell.draftList.load(shell.currentInstance!, refresh: true);

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(
        shell.draftList.feedFor(shell.currentInstance!.url).drafts,
        isEmpty,
      );
      expect(shell.draftCountFor(shell.currentInstance!.url), 0);
    });

    testWidgets('empty close does not decrement unrelated draft counts', (
      tester,
    ) async {
      const writer = DiscourseUser(
        username: 'joffreyj',
        name: 'Joffrey',
        draftCount: 3,
      );
      final api = FakeDiscourseApi(
        user: writer,
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 5)},
      );
      await pumpShell(
        tester,
        desktop,
        api: api,
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Discourse Meta',
          ).copyWith(user: writer),
        ],
        authenticator: signedIn(),
      );
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.byTooltip('Reply to this topic'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Save and close'));
        await tester.pumpAndSettle();
      }

      expect(shell.draftCountFor(shell.currentInstance!.url), 3);
    });

    testWidgets('discard locks editing and preserves a concurrent change', (
      tester,
    ) async {
      final deleteGate = Completer<void>();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftDeleteGate: deleteGate,
      );

      await openComposer(tester, api);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      final composer = shell.visibleComposer!;
      await tester.enterText(find.byType(TextField), 'First revision');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      final confirm = find.byKey(const ValueKey('composer-confirm-discard'));
      await tester.tap(confirm);
      await tester.tap(confirm);
      await tester.pump();

      expect(api.userDraftsDeleted, hasLength(1));
      expect(composer.discarding, isTrue);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byType(ComposerPanel),
                matching: find.byType(EditableText),
              ),
            )
            .readOnly,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('composer-discard-dialog')),
        findsOneWidget,
      );

      // An upload or plugin can still finish programmatically while the field
      // is locked. The revision check must keep and re-save that newer text.
      composer.text.text = 'Changed during discard';
      deleteGate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text(
          'This draft changed before it could be discarded. '
          'Review it and try again.',
        ),
        findsOneWidget,
      );
      expect(composer.discarding, isFalse);
      expect(api.draftsSaved.last['data'], contains('Changed during discard'));
    });

    testWidgets('discard waits for an older save of the same draft key', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Save still in flight');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));
      await tester.enterText(find.byType(TextField), 'Queued latest revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(api.draftsSaved, hasLength(1));

      shell.closeComposer();
      shell.openReply();
      await tester.pumpAndSettle();
      expect(shell.visibleComposer?.text.text, 'Queued latest revision');

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pump();
      expect(api.userDraftsDeleted, isEmpty);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Queued latest revision'));
      expect(api.userDraftsDeleted, const [
        (
          siteUrl: 'https://meta.discourse.org',
          draftKey: 'topic_7',
          sequence: 6,
        ),
      ]);
      expect(find.byType(ComposerPanel), findsNothing);
    });

    testWidgets('a new composer stays locally durable behind an old save', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Old first revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Old queued revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      shell.closeComposer();
      shell.openReply();
      await tester.pump();
      final newComposer = shell.visibleComposer!;
      newComposer.text.text = 'New first revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(
        drafts.saved.values.single,
        contains('New first revision'),
        reason: 'the new text must be durable before the old request returns',
      );

      newComposer.text.text = 'New queued revision';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(
        drafts.saved.values.single,
        contains('New queued revision'),
        reason: 'a queued revision must not live only in memory',
      );

      shell.closeComposer();
      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(3));
      expect(api.draftsSaved[1]['data'], contains('Old queued revision'));
      expect(api.draftsSaved.last['data'], contains('New queued revision'));
      expect(shell.currentTopic?.draft?.reply, 'New queued revision');
      expect(drafts.saved, isEmpty);
    });

    testWidgets('restore sees an old remote save when its local write failed', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = _FailingDraftStore(failures: 1);
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Remote-only revision');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      expect(drafts.saved, isEmpty);
      expect(api.draftsSaved, hasLength(1));

      shell.closeComposer();
      shell.openReply();
      await tester.pump();
      expect(find.text('Remote-only revision'), findsNothing);

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(find.text('Remote-only revision'), findsOneWidget);
      expect(api.userDraftsDeleted, isEmpty);
    });

    testWidgets('retired saves cannot cross a reconnected account boundary', (
      tester,
    ) async {
      final saveGate = Completer<void>();
      final drafts = FakeDraftStore();
      final auth = signedIn();
      final api = FakeDiscourseApi(
        user: me,
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftGate: saveGate,
      );

      await openComposer(tester, api, drafts: drafts, authenticator: auth);
      final shell = ShellScope.read(tester.element(find.byType(MainContent)));
      await tester.enterText(find.byType(TextField), 'Account A first');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Account A queued');
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();
      shell.closeComposer();

      await shell.disconnectCurrentInstance();
      await shell.connectCurrentInstance();
      await tester.pumpAndSettle();
      expect(auth.keys['https://meta.discourse.org'], 'api-key');

      await tester.tap(find.text('A real topic'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();
      final accountBComposer = shell.visibleComposer!;
      accountBComposer.text.text = 'Account B draft';
      await tester.pump(ComposerController.draftDebounce);
      await tester.pump();

      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.first['apiKey'], 'meta-key');
      expect(api.draftsSaved.last['apiKey'], 'api-key');
      expect(api.draftsSaved.last['data'], contains('Account B draft'));
      expect(drafts.saved.values.single, contains('Account B draft'));

      saveGate.complete();
      await tester.pumpAndSettle();

      expect(api.draftsSaved, hasLength(2));
      expect(
        api.draftsSaved.where(
          (save) => (save['data'] as String).contains('Account A queued'),
        ),
        isEmpty,
      );
    });

    testWidgets('a failed discard keeps the draft and the queue usable', (
      tester,
    ) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
        draftDeleteFailure: const WriteException(WriteFailure.unreachable),
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Keep this revision');
      await settleDraft(tester);
      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't discard this draft. Try again."),
        findsOneWidget,
      );
      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['sequence'], 5);
      expect(api.draftsSaved.last['data'], contains('Keep this revision'));

      await tester.tap(find.byKey(const ValueKey('composer-cancel-discard')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Queue still works');
      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(3));
      expect(api.draftsSaved.last['sequence'], 6);
      expect(api.draftsSaved.last['data'], contains('Queue still works'));
    });

    testWidgets('a failed local clear keeps and re-saves the composer', (
      tester,
    ) async {
      final drafts = _FlakyDraftStore();
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api, drafts: drafts);
      await tester.enterText(find.byType(TextField), 'Must not resurrect');
      await settleDraft(tester);
      drafts.clearFailures = 1;

      await tester.tap(find.byKey(const ValueKey('composer-discard')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-confirm-discard')));
      await tester.pumpAndSettle();

      expect(find.byType(ComposerPanel), findsOneWidget);
      expect(
        find.text("Couldn't discard this draft. Try again."),
        findsOneWidget,
      );
      expect(api.userDraftsDeleted, hasLength(1));
      expect(api.draftsSaved, hasLength(2));
      expect(api.draftsSaved.last['data'], contains('Must not resurrect'));
      expect(drafts.saved, isEmpty);
    });

    testWidgets('typing is saved to the site after a pause', (tester) async {
      final api = FakeDiscourseApi(
        feeds: {'/latest.json': listed},
        topics: {7: detail(draftSequence: 4)},
      );

      await openComposer(tester, api);
      await tester.enterText(find.byType(TextField), 'Half a thought');
      await tester.pumpAndSettle();

      expect(api.draftsSaved, isEmpty);

      await settleDraft(tester);

      expect(api.draftsSaved, hasLength(1));
      expect(api.draftsSaved.single['draftKey'], 'topic_7');
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
      await tester.tap(
        find.descendant(
          of: find.byType(ComposerPanel),
          matching: find.widgetWithText(FilledButton, 'Reply'),
        ),
      );
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

      await tester.tap(find.byTooltip('Save and close'));
      await tester.pumpAndSettle();
      expect(find.byType(ComposerPanel), findsNothing);

      await tester.tap(find.byTooltip('Reply to this topic'));
      await tester.pumpAndSettle();

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

      expect(find.text('Started in a browser'), findsOneWidget);
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

      await tester.tap(
        find.descendant(
          of: find.byType(ComposerPanel),
          matching: find.widgetWithText(FilledButton, 'Reply'),
        ),
      );
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

  group('chat', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    const site = 'https://meta.discourse.org';

    final withChat = chatNotificationTotals();
    const withoutChat = NotificationTotals();

    SiteConfig chatConfig({
      bool searchEnabled = false,
      int channelRetentionDays = 0,
    }) => SiteConfig(
      plugins: PluginData.none.withValue(
        chatSettingsDataKey,
        ChatSettings(
          searchEnabled: searchEnabled,
          channelRetentionDays: channelRetentionDays,
        ),
      ),
    );

    DiscourseUser chatUser({
      bool? hasChatEnabled,
      ChatHeaderIndicatorPreference headerIndicatorPreference =
          ChatHeaderIndicatorPreference.allNew,
      int? lastChannelId,
    }) => DiscourseUser(
      id: 7,
      username: 'joffreyj',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        ChatCurrentUser(
          hasChatEnabled: hasChatEnabled,
          headerIndicatorPreference: headerIndicatorPreference,
          lastChannelId: lastChannelId,
        ),
      ),
    );

    ChatChannel channel(
      int id, {
      String title = 'Bugs',
      String? slug,
      String? emoji,
      String? description,
      String? categoryName = 'Bug',
      String? color,
      int unread = 0,
      int mentions = 0,
      bool muted = false,
      bool starred = false,
      ChatChannelNotificationLevel notificationLevel =
          ChatChannelNotificationLevel.mention,
      bool following = true,
      bool readRestricted = false,
      ChatChannelStatus status = ChatChannelStatus.open,
      bool canJoin = false,
      int membershipsCount = 0,
      int? lastRead,
    }) => ChatChannel(
      id: id,
      title: title,
      kind: ChatChannelKind.category,
      slug: slug ?? title.toLowerCase(),
      emoji: emoji,
      description: description,
      categoryName: categoryName,
      categoryColor: color == null
          ? null
          : Color(int.parse('FF$color', radix: 16)),
      readRestricted: readRestricted,
      status: status,
      canJoin: canJoin,
      membershipsCount: membershipsCount,
      membership: ChatMembership(
        following: following,
        muted: muted,
        notificationLevel: notificationLevel,
        starred: starred,
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
      bool starred = false,
      int? lastMessageId,
      DateTime? lastMessageAt,
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
      membership: ChatMembership(following: true, starred: starred),
      tracking: ChatTracking(
        unreadCount: unread,
        mentionCount: mentions,
        watchedThreadsUnreadCount: watchedThreads,
      ),
      lastMessageId: lastMessageId,
      lastMessageAt: lastMessageAt,
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
      targetMessageId: null,
    );

    String key(int channelId, {int? before, int? after}) =>
        FakeDiscourseApi.chatMessagesKey(
          channelId,
          before: before,
          after: after,
        );

    Future<void> pumpChat(
      WidgetTester tester, {
      NotificationTotals? totals,
      List<ChatChannel> public = const [],
      List<ChatChannel> direct = const [],
      Map<String, ChatMessagePage> messages = const {},
      FakeDiscourseApi? api,
      Size size = desktop,
      Completer<void>? channelGate,
      DiscourseUser user = me,
      ChatPresence presence = const ChatPresence(),
      SiteConfig config = const SiteConfig.unknown(),
    }) async {
      await pumpShell(
        tester,
        size,
        api:
            api ??
            FakeDiscourseApi(
              totals: totals ?? withChat,
              user: user,
              chatChannelsBySite: {
                site: ChatChannels(
                  public: public,
                  direct: direct,
                  presence: presence,
                ),
              },
              chatChannelGate: channelGate,
              chatMessagesByKey: messages,
              siteConfigs: config.chatSettings.searchEnabled
                  ? {site: config}
                  : const {},
            ),
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Meta',
          ).copyWith(user: user, config: config),
        ],
        authenticator: FakeAuthenticator()..keys[site] = 'meta-key',
      );
      await tester.pumpAndSettle();
    }

    /// `pumpAndSettle` does not advance an unscheduled dwell timer.
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

        await pumpChat(tester, user: chatUser(hasChatEnabled: false));
        expect(shortcut, findsNothing);
      });

      testWidgets('is hidden on Aggregate', (tester) async {
        await pumpChat(tester);
        expect(shortcut, findsOneWidget);

        final controller = ShellScope.read(
          tester.element(find.byType(ShellTitleBar)),
        );
        controller.selectAggregate();
        await tester.pump();

        expect(shortcut, findsNothing);

        controller.selectInstance(0);
        await tester.pump();

        expect(shortcut, findsOneWidget);
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
          user: chatUser(
            headerIndicatorPreference:
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
            doNotDisturbUntil: DateTime.now().add(const Duration(minutes: 1)),
          ),
        );
        expect(urgent, findsNothing);

        await tester.pump(const Duration(minutes: 1, seconds: 1));

        expect(urgent, findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      });

      testWidgets('opens the server’s last chat channel', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          direct: [dm(12)],
          messages: {key(9): page(const [])},
          user: chatUser(lastChannelId: 9),
        );

        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        final shell = ShellScope.read(
          tester.element(find.byType(ChatChannelView)),
        );
        expect(shell.currentContent?.id, ChatChannel.routeId(9));
        expect(shell.chat.channel(site, 9)?.membership.lastViewedAt, isNotNull);
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
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
        );

        await pumpChat(tester, api: api);

        expect(find.text('CHAT'), findsNothing);
        expect(api.chatChannelsRequested, isEmpty);
      });

      testWidgets('asks a site for channels once its totals said it has them', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
        );

        await pumpChat(tester, api: api);

        expect(api.chatChannelsRequested, [site]);
        expect(sidebarDestination('Bugs'), findsOneWidget);
      });

      testWidgets('draws nothing while the channel list is still on its way', (
        tester,
      ) async {
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

      testWidgets('offers search only when the site explicitly enables it', (
        tester,
      ) async {
        await pumpChat(tester);
        expect(sidebarDestination('Search'), findsNothing);

        await pumpChat(tester, config: chatConfig(searchEnabled: true));
        expect(sidebarDestination('Search'), findsOneWidget);

        await tester.tap(sidebarDestination('Search'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('chat-search-field')), findsOneWidget);
      });

      testWidgets('keeps the improved search sort menu inside the viewport', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(tester, config: chatConfig(searchEnabled: true));

          await tester.tap(sidebarDestination('Search'));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-search-sort')));
          await tester.pumpAndSettle();

          final surface = find.byKey(const ValueKey('choice-menu-surface'));
          expect(surface, findsOneWidget);
          expect(
            tester.getRect(surface).right,
            lessThanOrEqualTo(desktop.width - 12),
          );
          expect(find.text('Sort search results'), findsOneWidget);
          expect(find.text('Best matching messages first'), findsOneWidget);
          expect(find.text('Newest messages first'), findsOneWidget);
          expect(find.byType(DropdownButton<ChatSearchSort>), findsNothing);

          await tester.tap(
            find.byKey(
              const ValueKey(('choice-menu-option', ChatSearchSort.latest)),
            ),
          );
          await tester.pumpAndSettle();

          expect(surface, findsNothing);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('chat-search-sort')),
              matching: find.text('Latest'),
            ),
            findsOneWidget,
          );
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('toggles the inline search bar from a channel header', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          config: chatConfig(searchEnabled: true),
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-channel-search-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('chat-channel-search-button')),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('chat-channel-search-field')),
          findsOneWidget,
        );
      });

      testWidgets('Command F opens and refocuses global Chat search', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(
            tester,
            public: [channel(9)],
            messages: {key(9): page(const [])},
            config: chatConfig(searchEnabled: true),
          );

          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();

          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final searchField = tester
              .widget<EditableText>(
                find.descendant(
                  of: find.byKey(const ValueKey('chat-search-field')),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode;
          expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
          expect(searchField.hasFocus, isTrue);

          searchField.unfocus();
          await tester.pump();
          expect(searchField.hasFocus, isFalse);

          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();
          expect(searchField.hasFocus, isTrue);
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('Command F stays native when Chat search is unavailable', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(
            tester,
            public: [channel(9)],
            messages: {key(9): page(const [])},
          );

          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isFalse);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pump();

          expect(find.byKey(const ValueKey('chat-search-field')), findsNothing);
          expect(find.byKey(ForumSearch.panelKey), findsNothing);
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('opens a global search result at its exact message', (
        tester,
      ) async {
        final searchMessage = msg(40, cooked: '<p>needle</p>');
        final config = chatConfig(searchEnabled: true);
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          siteConfigs: {site: config},
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatSearchPagesByKey: {
            FakeDiscourseApi.chatSearchKey('needle'): ChatSearchPage(
              hits: [
                ChatSearchHit(
                  message: searchMessage,
                  channel: channel(9),
                  excerpt: 'needle',
                ),
              ],
            ),
          },
          chatMessagesByKey: {
            FakeDiscourseApi.chatMessagesKey(9, targetMessageId: 40): page([
              searchMessage,
            ]),
          },
        );
        await pumpChat(tester, api: api, config: config);

        await tester.tap(sidebarDestination('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('chat-search-field')),
          'needle',
        );
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();

        final message = find.byKey(const ValueKey('chat-message-40'));
        expect(message, findsOneWidget);
        await tester.tap(
          find.ancestor(of: message, matching: find.byType(InkWell)).first,
        );
        await tester.pumpAndSettle();

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.currentContent?.id, 'chat-c-9');
        expect(api.chatMessagesRequested.last.targetMessageId, 40);
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

      testWidgets('reveals the web channel menu on desktop hover', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(tester, public: [channel(9)]);

          final reveal = find.byKey(
            const ValueKey('sidebar-hover-action-chat-c-9'),
          );
          expect(tester.widget<AnimatedOpacity>(reveal).opacity, 0);

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(sidebarDestination('Bugs')));
          await tester.pumpAndSettle();

          expect(tester.widget<AnimatedOpacity>(reveal).opacity, 1);
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('chat-channel-menu-button-9')),
              matching: find.dIcon(DIcons.ellipsisVertical),
            ),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-button-9')),
          );
          await tester.pumpAndSettle();

          expect(
            find.widgetWithText(SubmenuButton, 'Notifications'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(MenuItemButton, 'Channel settings'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(MenuItemButton, 'Add to starred channels'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(MenuItemButton, 'Leave channel'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-settings-9')),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('chat-channel-settings')),
            findsOneWidget,
          );
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('changes channel notifications and starring from the menu', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
          );
          await pumpChat(tester, api: api);

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(sidebarDestination('Bugs')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-button-9')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-channel-notifications-9')),
          );
          await tester.pumpAndSettle();

          final selected = find.descendant(
            of: find.byKey(
              const ValueKey('chat-channel-notification-9-mention'),
            ),
            matching: find.dIcon(DIcons.check),
          );
          expect(selected, findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('chat-channel-notification-9-always')),
          );
          await tester.pumpAndSettle();

          expect(api.chatChannelNotificationsUpdated, const [
            (
              channelId: 9,
              muted: null,
              notificationLevel: ChatChannelNotificationLevel.always,
            ),
          ]);

          await mouse.moveTo(Offset.zero);
          await tester.pumpAndSettle();
          await mouse.moveTo(tester.getCenter(sidebarDestination('Bugs')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-button-9')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-star-9')),
          );
          await tester.pumpAndSettle();

          expect(api.chatChannelStarsUpdated, const [
            (channelId: 9, starred: true),
          ]);
          expect(find.text('STARRED CHANNELS'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets(
        'closes a direct message and falls back to a public channel',
        (tester) async {
          final previous = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            final api = FakeDiscourseApi(
              totals: withChat,
              user: me,
              chatChannelsBySite: {
                site: ChatChannels(public: [channel(9)], direct: [dm(12)]),
              },
              chatMessagesByKey: {key(9): page(const [])},
            );
            await pumpChat(tester, api: api);

            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: Offset.zero);
            addTearDown(mouse.removePointer);
            await mouse.moveTo(tester.getCenter(sidebarDestination('hawk')));
            await tester.pumpAndSettle();
            await tester.tap(
              find.byKey(const ValueKey('chat-channel-menu-button-12')),
            );
            await tester.pumpAndSettle();

            expect(
              find.widgetWithText(MenuItemButton, 'Close channel'),
              findsOneWidget,
            );
            await tester.tap(
              find.byKey(const ValueKey('chat-channel-menu-leave-12')),
            );
            await tester.pumpAndSettle();

            expect(api.chatChannelFollowsUpdated, const [
              (channelId: 12, following: false),
            ]);
            expect(sidebarDestination('hawk'), findsNothing);
            expect(sidebarDestination('Bugs'), findsOneWidget);
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );
            expect(shell.currentContent?.id, ChatChannel.routeId(9));
          } finally {
            debugDefaultTargetPlatformOverride = previous;
          }
        },
      );

      testWidgets('opens the channel actions from a long press on touch', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
          );
          await pumpChat(tester, api: api, size: phone);

          expect(
            find.byKey(const ValueKey('chat-channel-menu-button-9')),
            findsNothing,
          );
          await tester.longPress(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          expect(
            find.widgetWithText(ListTile, 'Notifications'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ListTile, 'Channel settings'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ListTile, 'Add to starred channels'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ListTile, 'Leave channel'),
            findsOneWidget,
          );

          await tester.tap(
            find.byKey(const ValueKey('chat-channel-notifications-9')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Mentions only'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('chat-channel-notification-9-always')),
          );
          await tester.pumpAndSettle();

          expect(api.chatChannelNotificationsUpdated, const [
            (
              channelId: 9,
              muted: null,
              notificationLevel: ChatChannelNotificationLevel.always,
            ),
          ]);
          expect(
            find.widgetWithText(ListTile, 'Channel settings'),
            findsNothing,
          );
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('browses, filters, and joins public channels', (
        tester,
      ) async {
        final joined = channel(9, membershipsCount: 42);
        final support = channel(
          10,
          title: 'Support',
          description: 'Ask the community for help.',
          following: false,
          canJoin: true,
          membershipsCount: 7,
        );
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [joined]),
          },
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): ChatChannelBrowsePage(
              channels: [joined, support],
            ),
            FakeDiscourseApi.chatBrowseKey(filter: 'sup'):
                ChatChannelBrowsePage(channels: [support]),
          },
        );
        await pumpChat(tester, api: api);

        await tester.tap(sidebarDestination('Browse channels'));
        await tester.pumpAndSettle();

        expect(find.text('Ask the community for help.'), findsOneWidget);
        expect(find.text('7 members'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('chat-browse-filter')),
          'sup',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-browse-channel-9')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('chat-browse-channel-10')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('chat-join-10')));
        await tester.pumpAndSettle();

        expect(api.chatBrowseRequested, const [
          (
            filter: '',
            status: ChatChannelBrowseStatus.all,
            offset: 0,
            limit: ChatChannelBrowsePage.pageSize,
          ),
          (
            filter: 'sup',
            status: ChatChannelBrowseStatus.all,
            offset: 0,
            limit: ChatChannelBrowsePage.pageSize,
          ),
        ]);
        expect(api.chatChannelFollowsUpdated, const [
          (channelId: 10, following: true),
        ]);
        expect(sidebarDestination('Support'), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-unfollow-10')), findsOneWidget);
      });

      testWidgets('reorders direct messages when a new message arrives', (
        tester,
      ) async {
        await pumpChat(
          tester,
          direct: [
            dm(
              12,
              title: 'First',
              lastMessageId: 50,
              lastMessageAt: DateTime.utc(2026, 8, 8, 12),
            ),
            dm(
              13,
              title: 'Second',
              lastMessageId: 40,
              lastMessageAt: DateTime.utc(2026, 8, 8, 10),
            ),
          ],
        );

        expect(
          tester.getTopLeft(sidebarDestination('First')).dy,
          lessThan(tester.getTopLeft(sidebarDestination('Second')).dy),
        );

        FakeSiteTracker.built.single.deliverPluginMessage(
          '/chat/13/new-messages',
          {
            'type': 'channel',
            'channel_id': 13,
            'message': {
              'id': 60,
              'chat_channel_id': 13,
              'created_at': '2026-08-08T13:00:00.000Z',
              'user': {'id': 2, 'username': 'hawk'},
            },
          },
        );
        await tester.pump();

        expect(
          tester.getTopLeft(sidebarDestination('Second')).dy,
          lessThan(tester.getTopLeft(sidebarDestination('First')).dy),
        );
      });

      testWidgets(
        'lists starred public channels and DMs first without duplicating them',
        (tester) async {
          await pumpChat(
            tester,
            public: [
              channel(9, title: 'Alpha', starred: true),
              channel(10, title: 'Bugs'),
            ],
            direct: [
              dm(12, title: 'Zoe', starred: true),
              dm(13, title: 'Alice', starred: true),
              dm(14, title: 'hawk'),
            ],
          );

          final starredHeading = tester
              .getTopLeft(find.text('STARRED CHANNELS'))
              .dy;
          final chatHeading = tester.getTopLeft(find.text('CHAT')).dy;
          final dmHeading = tester.getTopLeft(find.text('DIRECT MESSAGES')).dy;
          expect(starredHeading, lessThan(chatHeading));
          expect(chatHeading, lessThan(dmHeading));

          final alpha = tester.getTopLeft(sidebarDestination('Alpha')).dy;
          final alice = tester.getTopLeft(sidebarDestination('Alice')).dy;
          final zoe = tester.getTopLeft(sidebarDestination('Zoe')).dy;
          expect(alpha, lessThan(alice));
          expect(alice, lessThan(zoe));
          expect(sidebarDestination('Alpha'), findsOneWidget);
          expect(sidebarDestination('Alice'), findsOneWidget);
          expect(sidebarDestination('Zoe'), findsOneWidget);
        },
      );

      testWidgets(
        'draws a channel emoji where an ordinary entry draws an icon',
        (tester) async {
          await pumpChat(tester, public: [channel(9, emoji: 'bug')]);

          expect(
            find.descendant(
              of: find.byType(InstanceSidebar),
              matching: find.byType(EmojiImage),
            ),
            findsOneWidget,
          );
        },
      );

      testWidgets('marks a channel linked to a private category', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9, readRestricted: true)]);

        expect(
          find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.dIcon(DIcons.lock),
          ),
          findsOneWidget,
        );
      });

      testWidgets(
        'draws the other person’s face on a one-to-one conversation',
        (tester) async {
          await pumpChat(tester, direct: [dm(12)]);

          final avatar = find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.byType(AvatarImage),
          );
          expect(avatar, findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(InstanceSidebar),
              matching: find.byType(ChatUserAvatar),
            ),
            findsOneWidget,
          );
          // Core leaves one pixel around each side of a round avatar inside its
          // 24-pixel prefix slot.
          final size = tester.getSize(avatar);
          expect(size, const Size.square(22));
        },
      );

      testWidgets('rings an online direct-message user in the sidebar', (
        tester,
      ) async {
        await pumpChat(
          tester,
          direct: [dm(12)],
          presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
        );

        final ring = find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.byKey(ChatUserAvatar.onlineRingKey(2)),
        );
        expect(ring, findsOneWidget);
        expect(tester.getSize(ring), const Size.square(22));

        final tracker = FakeSiteTracker.built.single;
        tracker.deliverPluginMessage('/presence/chat/online', {
          'leaving_user_ids': [2],
        });
        await tester.pump();

        expect(ring, findsNothing);
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

      testWidgets('uses core sidebar colors for unread and urgent dots', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, unread: 1)],
          direct: [dm(12, unread: 1)],
        );

        const unreadKey = ValueKey('sidebar-badge-chat-c-9');
        const urgentKey = ValueKey('sidebar-badge-chat-c-12');
        final theme = Theme.of(tester.element(find.byKey(urgentKey)));
        Color? dotColor(Key key) =>
            (tester.widget<Container>(find.byKey(key)).decoration!
                    as BoxDecoration)
                .color;

        expect(dotColor(unreadKey), theme.discourse.unreadIndicator);
        expect(dotColor(urgentKey), theme.discourse.success);
      });

      testWidgets('keeps the unread dot beside the channel label', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, title: 'Pulse-Inbox', unread: 1)],
        );

        final label = tester.getRect(sidebarDestination('Pulse-Inbox'));
        final dot = tester.getRect(
          find.byKey(const ValueKey('sidebar-badge-chat-c-9')),
        );

        expect(dot.left - label.right, inInclusiveRange(0, 8));
      });

      testWidgets('an open channel tab mirrors live channel presentation', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final channels = <String, ChatChannels>{
            site: ChatChannels(
              public: [channel(9, emoji: 'bug', color: '0088CC', unread: 42)],
              direct: const [],
            ),
          };
          await pumpChat(
            tester,
            api: FakeDiscourseApi(
              totals: withChat,
              user: me,
              chatChannelsBySite: channels,
              chatMessagesByKey: {
                key(9): page([msg(1)]),
              },
            ),
          );

          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          ForumTabItem item() => tester
              .widget<ForumTabsBar>(find.byType(ForumTabsBar))
              .items
              .single;

          expect(item().title, 'Bugs');
          expect(item().icon, DIcons.comment);
          expect(item().iconColor, const Color(0xFF0088CC));
          expect(item().emojiName, 'bug');
          expect(item().emojiUrl, isNotNull);
          expect(item().badge, const SidebarBadge.dot());

          channels[site] = ChatChannels(
            public: [channel(9, emoji: 'bug', color: '0088CC')],
            direct: const [],
          );
          final controller = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          await controller.chat.loadChannels(site, force: true);
          await tester.pump();

          expect(item().badge, SidebarBadge.none);
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('uses the shared online avatar in a direct-message tab', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(
            tester,
            direct: [dm(12)],
            presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
            messages: {key(12): page(const [])},
          );

          await tester.tap(sidebarDestination('hawk'));
          await tester.pumpAndSettle();

          final tab = find.byType(ForumTabsBar);
          final item = tester.widget<ForumTabsBar>(tab).items.single;
          expect(item.avatarUrl, isNotNull);
          expect(item.prefixBuilder, isNotNull);
          expect(
            find.descendant(of: tab, matching: find.byType(ChatUserAvatar)),
            findsOneWidget,
          );
          final ring = find.descendant(
            of: tab,
            matching: find.byKey(ChatUserAvatar.onlineRingKey(2)),
          );
          expect(ring, findsOneWidget);
          expect(tester.getSize(ring), const Size.square(15));
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('forgets a disconnected site’s channels', (tester) async {
        await pumpChat(tester, size: phone, public: [channel(9)]);
        expect(sidebarDestination('Bugs'), findsOneWidget);

        await tester.longPress(
          find.byKey(const ValueKey<String>('https://meta.discourse.org')),
        );
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
      testWidgets('shows a direct-message avatar and its live presence', (
        tester,
      ) async {
        await pumpChat(
          tester,
          direct: [dm(12)],
          presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
          messages: {key(12): page(const [])},
        );
        await tester.tap(sidebarDestination('hawk'));
        await tester.pumpAndSettle();

        final leading = find.byKey(const ValueKey('content-header-leading'));
        expect(
          find.descendant(of: leading, matching: find.byType(ChatUserAvatar)),
          findsOneWidget,
        );
        final ring = find.descendant(
          of: leading,
          matching: find.byKey(ChatUserAvatar.onlineRingKey(2)),
        );
        expect(ring, findsOneWidget);

        FakeSiteTracker.built.single.deliverPluginMessage(
          '/presence/chat/online',
          {
            'leaving_user_ids': [2],
          },
        );
        await tester.pump();

        expect(ring, findsNothing);
        expect(
          find.descendant(of: leading, matching: find.byType(ChatUserAvatar)),
          findsOneWidget,
        );
      });

      testWidgets('the channel title opens routed settings and Back returns', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [
            channel(
              9,
              categoryName: 'Management',
              color: 'A8C832',
              readRestricted: true,
            ),
          ],
          messages: {key(9): page(const [])},
          config: chatConfig(channelRetentionDays: 180),
        );
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.currentContent?.id, 'chat-c-9-info-settings');
        expect(shell.contentStack.map((route) => route.id), [
          'chat-c-9',
          'chat-c-9-info-settings',
        ]);
        expect(
          find.byKey(const ValueKey('chat-channel-settings')),
          findsOneWidget,
        );
        expect(find.text('Management'), findsOneWidget);
        expect(find.text('180 days'), findsOneWidget);

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();

        expect(shell.currentContent?.id, 'chat-c-9');
        expect(find.byType(ChatChannelView), findsOneWidget);
      });

      testWidgets('shows and filters the channel member directory', (
        tester,
      ) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        addTearDown(
          () => debugDefaultTargetPlatformOverride = previousPlatform,
        );

        final memberPages = <String, ChatChannelMembersPage>{
          FakeDiscourseApi.chatChannelMembersKey(9): (
            members: const [
              ChatUser(id: 2, username: 'sam', name: 'Sam'),
              ChatUser(id: 3, username: 'hawk', name: 'Hawk'),
            ],
            totalRows: 2,
            canLoadMore: false,
          ),
          FakeDiscourseApi.chatChannelMembersKey(9, username: 'ha'): (
            members: const [ChatUser(id: 3, username: 'hawk', name: 'Hawk')],
            totalRows: 3,
            canLoadMore: false,
          ),
        };
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [
                channel(
                  9,
                  description: 'A place to discuss bug reports.',
                  membershipsCount: 2,
                ),
              ],
              direct: const [],
              channelMetadataBusLastId: 80,
            ),
          },
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelMemberPagesByKey: memberPages,
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();

        expect(find.text('A place to discuss bug reports.'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-channel-edit-title')),
          findsNothing,
        );
        expect(find.text('Members (2)'), findsOneWidget);
        expect(find.text('Sam'), findsNothing);

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final tabs = find.byKey(const ValueKey('chat-channel-info-tabs'));
        final settingsLane = find.byKey(
          const ValueKey('chat-channel-settings-lane-content'),
        );
        final centeredSettingsLeft = tester.getTopLeft(settingsLane).dx;
        final tabsRect = tester.getRect(tabs);
        expect(tester.getSize(settingsLane).width, 760);
        expect(tabsRect.width, greaterThan(825));

        await shell.appSettings.setContentAlignment(ContentAlignment.left);
        await tester.pump();
        expect(
          tester.getTopLeft(settingsLane).dx,
          lessThan(centeredSettingsLeft),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setContentAlignment(ContentAlignment.right);
        await tester.pump();
        expect(
          tester.getTopLeft(settingsLane).dx,
          greaterThan(centeredSettingsLeft),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setContentAlignment(ContentAlignment.center);
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('chat-channel-info-members-tab')),
        );
        await tester.pumpAndSettle();

        expect(shell.currentContent?.id, 'chat-c-9-info-members');
        expect(shell.contentStack.map((route) => route.id), [
          'chat-c-9',
          'chat-c-9-info-members',
        ]);

        expect(find.text('Sam'), findsOneWidget);
        expect(find.text('Hawk'), findsOneWidget);

        final memberFilterLane = find.byKey(
          const ValueKey('chat-channel-member-filter-lane-content'),
        );
        final firstMember = find.byKey(const ValueKey('chat-channel-member-2'));
        final memberList = find.byKey(
          const ValueKey('chat-channel-member-list'),
        );
        final centeredFilterLeft = tester.getTopLeft(memberFilterLane).dx;
        final centeredMemberLeft = tester.getTopLeft(firstMember).dx;
        expect(tester.getSize(memberFilterLane).width, 760);
        expect(tester.getSize(firstMember).width, 760);
        expect(tester.getSize(memberList).width, tabsRect.width);
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setContentAlignment(ContentAlignment.left);
        await tester.pump();
        expect(
          tester.getTopLeft(memberFilterLane).dx,
          lessThan(centeredFilterLeft),
        );
        expect(tester.getTopLeft(firstMember).dx, lessThan(centeredMemberLeft));
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setContentAlignment(ContentAlignment.right);
        await tester.pump();
        expect(
          tester.getTopLeft(memberFilterLane).dx,
          greaterThan(centeredFilterLeft),
        );
        expect(
          tester.getTopLeft(firstMember).dx,
          greaterThan(centeredMemberLeft),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setContentAlignment(ContentAlignment.center);
        await tester.pump();
        debugDefaultTargetPlatformOverride = previousPlatform;

        memberPages[FakeDiscourseApi.chatChannelMembersKey(9)] = (
          members: const [
            ChatUser(id: 2, username: 'sam', name: 'Sam'),
            ChatUser(id: 3, username: 'hawk', name: 'Hawk'),
            ChatUser(id: 4, username: 'kris', name: 'Kris'),
          ],
          totalRows: 3,
          canLoadMore: false,
        );
        FakeSiteTracker.built.single.deliverPluginMessage(
          '/chat/channel-metadata',
          {'chat_channel_id': 9, 'memberships_count': 3},
        );
        await tester.pumpAndSettle();

        expect(find.text('Members (3)'), findsOneWidget);
        expect(find.text('Kris'), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('chat-channel-member-filter')),
          'ha',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('Sam'), findsNothing);
        expect(find.text('Hawk'), findsOneWidget);
        expect(api.chatChannelMembersRequested, const [
          (channelId: 9, username: '', offset: 0, limit: 20),
          (channelId: 9, username: '', offset: 0, limit: 20),
          (channelId: 9, username: 'ha', offset: 0, limit: 20),
        ]);
      });

      testWidgets('staff rename a category channel from routed settings', (
        tester,
      ) async {
        const staff = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          staff: true,
        );
        final api = FakeDiscourseApi(
          totals: withChat,
          user: staff,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, slug: 'bugs')],
              direct: const [],
            ),
          },
          chatChannelUpdateResponse: channel(
            9,
            title: 'Bug reports',
            slug: 'bug-reports',
          ),
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelMemberPagesByKey: {
            FakeDiscourseApi.chatChannelMembersKey(9): (
              members: const [],
              totalRows: 0,
              canLoadMore: false,
            ),
          },
        );
        await pumpChat(tester, api: api, user: staff);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-channel-edit-title')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('chat-channel-title-input')),
          'Bug reports',
        );
        await tester.enterText(
          find.byKey(const ValueKey('chat-channel-slug-input')),
          'bug-reports',
        );
        await tester.tap(find.byKey(const ValueKey('chat-channel-title-save')));
        await tester.pumpAndSettle();

        expect(api.chatChannelMetadataUpdates, const [
          (
            channelId: 9,
            name: 'Bug reports',
            slug: 'bug-reports',
            description: null,
          ),
        ]);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.title, 'Bug reports');
        expect(sidebarDestination('Bug reports'), findsOneWidget);
      });

      testWidgets('staff can remove a category channel description', (
        tester,
      ) async {
        const staff = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          staff: true,
        );
        final api = FakeDiscourseApi(
          totals: withChat,
          user: staff,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, description: 'Old description')],
              direct: const [],
            ),
          },
          chatChannelUpdateResponse: channel(9),
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelMemberPagesByKey: {
            FakeDiscourseApi.chatChannelMembersKey(9): (
              members: const [],
              totalRows: 0,
              canLoadMore: false,
            ),
          },
        );
        await pumpChat(tester, api: api, user: staff);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-edit-description')),
        );
        await tester.pumpAndSettle();

        final descriptionInput = find.byKey(
          const ValueKey('chat-channel-description-input'),
        );
        await tester.enterText(descriptionInput, 'x');
        await tester.enterText(descriptionInput, '');
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-description-save')),
        );
        await tester.pumpAndSettle();

        expect(api.chatChannelMetadataUpdates.single.description, '');
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.description, isNull);
        expect(
          find.text('Tell people what this channel is about.'),
          findsOneWidget,
        );
      });

      testWidgets('staff toggle threading from routed channel settings', (
        tester,
      ) async {
        const staff = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          staff: true,
        );
        final api = FakeDiscourseApi(
          totals: withChat,
          user: staff,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatChannelUpdateResponse: const ChatChannel(
            id: 9,
            title: 'Bugs',
            kind: ChatChannelKind.category,
            slug: 'bugs',
            membership: ChatMembership(following: true),
            threadingEnabled: true,
          ),
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelMemberPagesByKey: {
            FakeDiscourseApi.chatChannelMembersKey(9): (
              members: const [],
              totalRows: 0,
              canLoadMore: false,
            ),
          },
        );
        await pumpChat(tester, api: api, user: staff);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();

        final threadingSwitch = find.byKey(
          const ValueKey('chat-channel-threading-switch'),
        );
        expect(threadingSwitch, findsOneWidget);
        expect(tester.widget<Switch>(threadingSwitch).value, isFalse);

        await tester.tap(threadingSwitch);
        await tester.pumpAndSettle();

        expect(api.chatChannelThreadingUpdates, const [
          (channelId: 9, enabled: true),
        ]);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.threadingEnabled, isTrue);
        expect(tester.widget<Switch>(threadingSwitch).value, isTrue);
      });

      testWidgets('staff close an open category channel after confirmation', (
        tester,
      ) async {
        const staff = DiscourseUser(
          id: 7,
          username: 'joffreyj',
          name: 'Joffrey',
          staff: true,
        );
        final api = FakeDiscourseApi(
          totals: withChat,
          user: staff,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatChannelStatusResponse: channel(
            9,
            status: ChatChannelStatus.closed,
          ),
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelMemberPagesByKey: {
            FakeDiscourseApi.chatChannelMembersKey(9): (
              members: const [],
              totalRows: 0,
              canLoadMore: false,
            ),
          },
        );
        await pumpChat(tester, api: api, user: staff);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-toggle-status')),
        );
        await tester.pumpAndSettle();

        final statusDialog = find.byKey(
          const ValueKey('chat-channel-status-dialog'),
        );
        expect(statusDialog, findsOneWidget);
        expect(
          find.descendant(
            of: statusDialog,
            matching: find.text('Close channel'),
          ),
          findsNWidgets(2),
        );
        expect(find.textContaining('prevents non-staff users'), findsOneWidget);
        final confirm = find.byKey(
          const ValueKey('chat-channel-status-confirm'),
        );
        expect(confirm, findsOneWidget);
        await tester.tap(confirm);
        await tester.pumpAndSettle();

        expect(api.chatChannelStatusesUpdated, const [
          (channelId: 9, status: ChatChannelStatus.closed),
        ]);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.status, ChatChannelStatus.closed);
        expect(find.text('Open channel'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-channel-threading-switch')),
          findsNothing,
        );
      });

      testWidgets('changes push notifications from routed channel settings', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {key(9): page(const [])},
          chatChannelNotificationMembership: const ChatMembership(
            following: true,
          ),
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Mentions only'), findsOneWidget);
        expect(find.text('Mute channel'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-channel-info-button')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('chat-channel-notification-button')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('chat-channel-notification-setting')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Never'), findsOneWidget);
        expect(find.text('All activity'), findsOneWidget);
        await tester.tap(find.text('All activity').last);
        await tester.pumpAndSettle();

        expect(api.chatChannelNotificationsUpdated, const [
          (
            channelId: 9,
            muted: null,
            notificationLevel: ChatChannelNotificationLevel.always,
          ),
        ]);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(
          shell.chat.channel(site, 9)?.membership.notificationLevel,
          ChatChannelNotificationLevel.always,
        );
      });

      testWidgets('leaves a public channel from settings and opens browse', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {key(9): page(const [])},
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('content-header-title-action')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('chat-channel-leave')));
        await tester.pumpAndSettle();

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(api.chatChannelFollowsUpdated, const [
          (channelId: 9, following: false),
        ]);
        expect(shell.currentContent?.id, 'chat-browse');
        expect(sidebarDestination('Bugs'), findsNothing);
      });

      testWidgets('draws a round avatar rather than an oval', (tester) async {
        // The fixed-width gutter gives its child a tight constraint.
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

      testWidgets('rings an online user in the site success colour', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          presence: const ChatPresence(userIds: {2}, lastMessageId: 47),
          messages: {
            key(9): page([msg(1, author: 2)]),
          },
        );
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        final ring = find.byKey(ChatUserAvatar.onlineRingKey(2));
        expect(ring, findsOneWidget);
        expect(tester.getSize(ring), const Size.square(28));
        final decoration =
            tester
                    .widget<DecoratedBox>(
                      find.descendant(
                        of: ring,
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        final theme = Theme.of(tester.element(ring));
        expect(
          (decoration.border! as Border).top.color,
          theme.discourse.success,
        );
        expect((decoration.border! as Border).top.width, 1);
        expect(decoration.color, theme.shell.content);

        final tracker = FakeSiteTracker.built.single;
        tracker.deliverPluginMessage('/presence/chat/online', {
          'leaving_user_ids': [2],
        });
        await tester.pump();
        expect(ring, findsNothing);

        tracker.deliverPluginMessage('/presence/chat/online', {
          'entering_users': [
            {'id': 2, 'username': 'sam'},
          ],
        });
        await tester.pump();
        expect(ring, findsOneWidget);
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
              site: ChatChannels(public: [channel(9)], direct: const []),
            },
            chatMessagesByKey: {
              key(9): page([msg(1)]),
            },
            chatMessageGate: gate,
          ),
        );

        final semantics = tester.ensureSemantics();
        try {
          await tester.tap(sidebarDestination('Bugs'));
          await tester.pump();
          expect(
            find.byKey(const ValueKey('chat-loading-skeleton')),
            findsOneWidget,
          );
          expect(
            tester
                .getSize(
                  find.byKey(const ValueKey('chat-loading-skeleton-content')),
                )
                .height,
            greaterThanOrEqualTo(
              tester
                  .getSize(find.byKey(const ValueKey('chat-loading-skeleton')))
                  .height,
            ),
          );
          final skeletonMessages = minimumHeightDescendants(
            find.byKey(const ValueKey('chat-loading-skeleton')),
            ChatMessageTile.minimumUnchainedHeight,
          );
          final chainedSkeletonMessages = minimumHeightDescendants(
            find.byKey(const ValueKey('chat-loading-skeleton')),
            ChatMessageTile.minimumChainedHeight,
          );
          expect(skeletonMessages, findsWidgets);
          expect(chainedSkeletonMessages, findsWidgets);
          expect(
            tester.getSize(skeletonMessages.first).height,
            greaterThanOrEqualTo(ChatMessageTile.minimumUnchainedHeight),
          );
          expect(
            tester.getSize(chainedSkeletonMessages.first).height,
            greaterThanOrEqualTo(ChatMessageTile.minimumChainedHeight),
          );
          expect(find.bySemanticsLabel('Loading chat channel'), findsOneWidget);
          expect(find.byKey(const ValueKey('chat-composer')), findsOneWidget);
          expect(activityIndicators, findsNothing);
          expect(tester.takeException(), isNull);

          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          var shellNotifications = 0;
          void countShellNotification() => shellNotifications += 1;
          shell.addListener(countShellNotification);
          addTearDown(() => shell.removeListener(countShellNotification));

          gate.complete();
          await tester.pumpAndSettle();

          expect(renderedText('Hello there'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('chat-loading-skeleton')),
            findsNothing,
          );
          final loadedMessage = minimumHeightAncestors(
            find.byKey(const ValueKey('chat-message-1')),
            ChatMessageTile.minimumUnchainedHeight,
          );
          expect(
            tester.getSize(loadedMessage.first).height,
            greaterThanOrEqualTo(ChatMessageTile.minimumUnchainedHeight),
          );
          expect(shellNotifications, 0);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
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

      testWidgets('keeps newest-message actions above the composer', (
        tester,
      ) async {
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

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(renderedText('Newer')));
        await tester.pump();

        expect(find.byType(HoverActionToolbar), findsOneWidget);
        expect(
          tester.getRect(find.byType(HoverActionToolbar)).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('chat-composer'))).top,
          ),
        );
      });

      testWidgets('keeps an ordinary newest message close to the composer', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([msg(1, cooked: '<p>Newest</p>')]),
          },
        );

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        final message = tester.getRect(
          find.byKey(const ValueKey('chat-message-1')),
        );
        final composer = tester.getRect(
          find.byKey(const ValueKey('chat-composer')),
        );

        expect(composer.top - message.bottom, 14);
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

        expect(find.text('sam'), findsOneWidget);

        expect(ChatMessageTile.gutter, 42);
        expect(
          tester
              .widget<Padding>(find.byKey(const ValueKey('chat-message-1')))
              .padding,
          const EdgeInsets.fromLTRB(16, 10.4, 16, 2.4),
        );
        expect(
          tester
              .widget<Padding>(find.byKey(const ValueKey('chat-message-2')))
              .padding,
          const EdgeInsets.fromLTRB(16, 2.4, 16, 2.4),
        );
        final firstMessage = minimumHeightAncestors(
          find.byKey(const ValueKey('chat-message-1')),
          ChatMessageTile.minimumUnchainedHeight,
        );
        final secondMessage = minimumHeightAncestors(
          find.byKey(const ValueKey('chat-message-2')),
          ChatMessageTile.minimumChainedHeight,
        );
        expect(
          tester.getSize(firstMessage.first).height,
          greaterThanOrEqualTo(ChatMessageTile.minimumUnchainedHeight),
        );
        expect(
          tester.getSize(secondMessage.first).height,
          greaterThanOrEqualTo(ChatMessageTile.minimumChainedHeight),
        );
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

      testWidgets('directly adds and removes existing message reactions', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(
                1,
                reactions: const [
                  ChatReaction(emoji: 'heart', count: 3, reacted: true),
                  ChatReaction(emoji: 'clap', count: 2),
                ],
              ),
            ]),
          },
        );
        await pumpChat(tester, api: api);

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('3'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);

        final mine = tester.widget<Container>(
          find.byKey(const ValueKey('chat-reaction-heart')),
        );
        final other = tester.widget<Container>(
          find.byKey(const ValueKey('chat-reaction-clap')),
        );
        final mineDecoration = mine.decoration! as BoxDecoration;
        final otherDecoration = other.decoration! as BoxDecoration;
        expect(find.byType(ReactionPill), findsNWidgets(2));
        expect(
          tester
              .widget<Padding>(find.byKey(const ValueKey('chat-reactions')))
              .padding,
          const EdgeInsets.only(top: 10),
        );
        expect(mine.padding, const EdgeInsets.fromLTRB(8, 4, 9, 4));
        expect(mineDecoration.borderRadius, BorderRadius.circular(14));
        expect(mineDecoration.border, isNotNull);
        expect(mineDecoration.color, otherDecoration.color);
        expect(otherDecoration.borderRadius, BorderRadius.circular(14));
        expect(otherDecoration.border, isNotNull);
        expect(
          (mineDecoration.border! as Border).top.color,
          isNot((otherDecoration.border! as Border).top.color),
        );

        final heart = find.bySemanticsLabel('3 heart reactions');
        final clap = find.bySemanticsLabel('2 clap reactions');
        expect(tester.getSize(heart).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(heart).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSemantics(heart),
          isSemantics(
            isButton: true,
            isSelected: true,
            onTapHint: 'remove your reaction',
          ),
        );
        expect(
          tester.getSemantics(clap),
          isSemantics(
            isButton: true,
            isSelected: false,
            onTapHint: 'add this reaction',
          ),
        );

        await tester.tap(heart);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-reaction-clap')));
        await tester.pumpAndSettle();

        expect(api.chatReactionsSet.map((write) => write.action), [
          ChatReactionAction.remove,
          ChatReactionAction.add,
        ]);
        expect(api.chatReactionsSet.map((write) => write.emoji), [
          'heart',
          'clap',
        ]);
        expect(find.bySemanticsLabel('2 heart reactions'), findsOneWidget);
        expect(find.bySemanticsLabel('3 clap reactions'), findsOneWidget);
      });

      testWidgets('visibly highlights a reaction under the mouse', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(1, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
            ]),
          },
        );
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        final reaction = find.byKey(const ValueKey('chat-reaction-clap'));
        BoxDecoration decoration() =>
            tester.widget<Container>(reaction).decoration! as BoxDecoration;

        final theme = Theme.of(tester.element(reaction));
        final rect = tester.getRect(reaction);
        final hoverFill = Color.alphaBlend(
          theme.colorScheme.onSurface.withValues(alpha: 0.08),
          theme.shell.floating,
        );
        expect(decoration().color, theme.shell.floating);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(reaction));
        await tester.pump();

        expect(decoration().color, hoverFill);
        expect(tester.getRect(reaction), rect);

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        expect(decoration().color, theme.shell.floating);
      });

      testWidgets('an existing message reaction offers the full emoji picker', (
        tester,
      ) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)], direct: const []),
            },
            chatMessagesByKey: {
              key(9): page([
                msg(
                  1,
                  reactions: const [ChatReaction(emoji: 'clap', count: 2)],
                ),
              ]),
            },
            emojisBySite: const {
              site: [
                SiteEmoji(
                  name: 'wave',
                  url: 'https://meta.discourse.org/wave.png',
                ),
              ],
            },
          );
          await pumpChat(tester, api: api);
          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          final launcher = find.bySemanticsLabel('Add reaction');
          expect(launcher, findsOneWidget);
          expect(tester.getSize(launcher), const Size.square(44));
          final launcherRect = tester.getRect(launcher);
          await tester.tap(launcher);
          await tester.pumpAndSettle();

          expect(find.byType(EmojiPicker), findsOneWidget);
          final pickerRect = tester.getRect(
            find.byKey(const ValueKey('emoji-picker-desktop-popover')),
          );
          expect(pickerRect.left, closeTo(launcherRect.left, 0.01));
          expect(pickerRect.bottom, closeTo(launcherRect.top - 8, 0.01));
          await tester.tap(find.byTooltip(':wave:'));
          await tester.pumpAndSettle();

          expect(api.chatReactionsSet, hasLength(1));
          expect(api.chatReactionsSet.single.channelId, 9);
          expect(api.chatReactionsSet.single.messageId, 1);
          expect(api.chatReactionsSet.single.emoji, 'wave');
          expect(api.chatReactionsSet.single.action, ChatReactionAction.add);
          expect(find.bySemanticsLabel('1 wave reaction'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });

      testWidgets('the chat picker survives its last pill disappearing', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1, reactions: const [ChatReaction(emoji: 'clap', count: 1)]),
            ]),
          },
          emojisBySite: const {
            site: [
              SiteEmoji(
                name: 'wave',
                url: 'https://meta.discourse.org/wave.png',
              ),
            ],
          },
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        final controller = ShellScope.read(
          tester.element(find.byType(ReactionPills)),
        );

        await tester.tap(find.bySemanticsLabel('Add reaction'));
        await tester.pumpAndSettle();
        controller.chat.putRecordForTesting(site, msg(1));
        await tester.pumpAndSettle();

        expect(find.byType(ReactionPickerButton), findsNothing);
        expect(find.byType(EmojiPicker), findsOneWidget);
        await tester.tap(find.byTooltip(':wave:'));
        await tester.pumpAndSettle();

        expect(api.chatReactionsSet, hasLength(1));
        expect(api.chatReactionsSet.single.emoji, 'wave');
        expect(api.chatReactionsSet.single.action, ChatReactionAction.add);
      });

      testWidgets('a read-only channel keeps its reaction row read-only', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, status: ChatChannelStatus.readOnly)],
          messages: {
            key(9): page([
              msg(1, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
            ]),
          },
        );
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactionPickerButton), findsNothing);
        expect(
          tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
          isSemantics(onTapHint: 'show who reacted'),
        );
      });

      testWidgets('leaving a channel still permits removing your reaction', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, following: false)],
              direct: const [],
            ),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(
                1,
                reactions: const [
                  ChatReaction(emoji: 'heart', count: 2, reacted: true),
                  ChatReaction(emoji: 'clap', count: 2),
                ],
              ),
            ]),
          },
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.byType(ReactionPickerButton), findsNothing);
        expect(
          tester.getSemantics(find.bySemanticsLabel('2 heart reactions')),
          isSemantics(onTapHint: 'remove your reaction'),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
          isSemantics(onTapHint: 'show who reacted'),
        );

        await tester.tap(find.bySemanticsLabel('2 heart reactions'));
        await tester.pumpAndSettle();

        expect(api.chatReactionsSet, hasLength(1));
        expect(api.chatReactionsSet.single.action, ChatReactionAction.remove);
        expect(api.chatReactionsSet.single.emoji, 'heart');
      });

      testWidgets('hovering a message reaction uses chat reactor data', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
            ]),
          },
          chatReactorsById: {
            ChatMessageReactors.key(9, 1, 'clap'): const ChatMessageReactors(
              channelId: 9,
              messageId: 1,
              filter: 'clap',
              total: 2,
              reactors: [
                ChatReactor(
                  id: 3,
                  username: 'sam',
                  name: 'Sam Saffron',
                  reaction: 'clap',
                ),
                ChatReactor(id: 4, username: 'codinghorror', reaction: 'clap'),
              ],
            ),
          },
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        final gesture = await tester.createGesture(
          kind: PointerDeviceKind.mouse,
        );
        await gesture.addPointer(location: Offset.zero);
        addTearDown(gesture.removePointer);
        await gesture.moveTo(
          tester.getCenter(find.bySemanticsLabel('2 clap reactions')),
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(api.chatReactorsRequested, [
          (channelId: 9, messageId: 1, filter: 'clap'),
        ]);
        expect(find.byType(ReactionUsersList), findsOneWidget);
        expect(find.text('Sam Saffron'), findsOneWidget);
        expect(find.text('codinghorror'), findsOneWidget);
        expect(api.reactorsRequested, isEmpty);
      });

      testWidgets('rolls back a refused message reaction and reports it', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1, reactions: const [ChatReaction(emoji: 'clap', count: 2)]),
            ]),
          },
          chatReactionFailure: const WriteException(
            WriteFailure.validation,
            errors: ['That emoji is unavailable.'],
          ),
        );
        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('chat-reaction-clap')));
        await tester.pumpAndSettle();

        expect(find.text('That emoji is unavailable.'), findsOneWidget);
        final reaction = find.byKey(const ValueKey('chat-reaction-clap'));
        expect(reaction, findsOneWidget);
        expect(
          find.descendant(of: reaction, matching: find.text('2')),
          findsOneWidget,
        );
      });

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

      testWidgets('replaces the forum workspace when it cannot be reached', (
        tester,
      ) async {
        final messages = <String, ChatMessagePage>{};
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)], direct: const []),
          },
          chatMessagesByKey: messages,
        );
        await pumpChat(tester, api: api);

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(find.text('Meta'), findsOneWidget);
        expect(
          find.text(
            "We couldn't reach this community. Check its address or your "
            'internet connection, then try again.',
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('unavailable-forum-gate')),
          findsOneWidget,
        );
        expect(find.byType(MainContent), findsNothing);
        expect(find.byType(InstanceRail), findsOneWidget);
        expect(find.byType(InstanceSidebar), findsNothing);
        expect(find.byKey(const ValueKey('forum-tabs-bar')), findsNothing);
        expect(find.byType(ShellTitleBar), findsOneWidget);
        expect(find.text('General'), findsNothing);
        expect(find.byType(ChatComposer), findsNothing);
        expect(
          find.byKey(const ValueKey('unavailable-forum-remove')),
          findsOneWidget,
        );
        final retryButton = tester.widget<FilledButton>(
          find.descendant(
            of: find.byKey(const ValueKey('unavailable-forum-retry')),
            matching: find.byType(FilledButton),
          ),
        );
        final removeButton = tester.widget<FilledButton>(
          find.descendant(
            of: find.byKey(const ValueKey('unavailable-forum-remove')),
            matching: find.byType(FilledButton),
          ),
        );
        expect(retryButton.style?.visualDensity, VisualDensity.standard);
        expect(removeButton.style?.visualDensity, VisualDensity.standard);

        await tester.tap(
          find.byKey(const ValueKey('unavailable-forum-remove')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove Meta?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        messages[key(9)] = page([msg(1)]);
        await tester.tap(find.byKey(const ValueKey('unavailable-forum-retry')));
        await tester.pumpAndSettle();

        expect(api.chatMessagesRequested, hasLength(2));
        expect(
          find.byKey(const ValueKey('unavailable-forum-gate')),
          findsNothing,
        );
        expect(renderedText('Hello there'), findsOneWidget);
        expect(find.byType(ChatComposer), findsOneWidget);
      });

      testWidgets(
        'asks for older messages when a short channel does not fill the window',
        (tester) async {
          // Nothing to scroll, so the scroll threshold can never fire — the last
          // row being built is what says the top of the stream is on screen.
          final api = FakeDiscourseApi(
            totals: withChat,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)], direct: const []),
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
            site: ChatChannels(public: [channel(9)], direct: const []),
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
              site: ChatChannels(
                public: [channel(9, lastRead: 5, unread: 35)],
                direct: const [],
              ),
            },
            chatMessagesByKey: {key(9): page(backlog)},
          );

          await pumpChat(tester, api: api, size: phone);
          await tester.tap(sidebarDestination('Bugs'));
          await pumpUntilRead(tester);

          expect(api.chatMessagesRequested.single.fromLastRead, isTrue);
          final marked = api.chatReadsMarked.single.messageId;
          expect(marked, greaterThan(5));
          expect(marked, lessThan(40));
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
            site: ChatChannels(
              public: [channel(9, lastRead: 1)],
              direct: const [],
            ),
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
            site: ChatChannels(
              public: [channel(9, lastRead: 1)],
              direct: const [],
            ),
          },
          chatMessagesByKey: {
            key(9): page([
              msg(1, cooked: '<p>Back then</p>'),
              msg(2, cooked: '<p>Also back then</p>', minute: 1),
            ], canLoadMoreFuture: true),
            FakeDiscourseApi.chatMessagesLatestKey(9): page([
              msg(80, cooked: '<p>Right now</p>', minute: 80),
            ]),
          },
        );

        await pumpChat(tester, api: api, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

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
              site: ChatChannels(
                public: [channel(9, lastRead: 1)],
                direct: const [],
              ),
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
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: ChatChannels(
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
        expect(
          find.byKey(const ValueKey('sidebar-badge-chat-c-9')),
          findsNothing,
        );
      });

      testWidgets('clears a stale unread dot when already read to the bottom', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, unread: 1, lastRead: 3)],
              direct: const [],
            ),
          },
          chatMessagesByKey: {
            key(9): page([msg(1), msg(2, minute: 1), msg(3, minute: 2)]),
          },
        );

        await pumpChat(tester, api: api);
        await tester.tap(sidebarDestination('Bugs'));
        await pumpUntilRead(tester);

        expect(api.chatReadsMarked, isEmpty);
        expect(
          find.byKey(const ValueKey('sidebar-badge-chat-c-9')),
          findsNothing,
        );
      });

      testWidgets('does not credit a reader who leaves before the dwell', (
        tester,
      ) async {
        // A visible row is not read until it has stayed in front of the reader
        // for the full dwell. Replacing the pane must not flush that timer.
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, unread: 1)],
              direct: const [],
            ),
          },
          chatMessagesByKey: {
            key(9): page([msg(1)]),
          },
        );

        await pumpChat(tester, api: api, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(api.chatReadsMarked, isEmpty);

        await tester.tap(find.dIcon(DIcons.arrowLeft));
        await tester.pumpAndSettle();

        expect(api.chatReadsMarked, isEmpty);
      });

      testWidgets('tells the site nothing about a channel nobody opened', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          chatChannelsBySite: {
            site: ChatChannels(
              public: [channel(9, unread: 3)],
              direct: const [],
            ),
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

        expect(find.byType(InstanceSidebar), findsNothing);
        expect(renderedText('Hello there'), findsOneWidget);

        await tester.tap(find.dIcon(DIcons.arrowLeft));
        await tester.pumpAndSettle();

        expect(find.byType(InstanceSidebar), findsOneWidget);
      });
    });
  });
}

final class _GatedDraftReadStore extends FakeDraftStore {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return super.read(siteUrl, draftKey);
  }
}

final class _FailingDraftStore extends FakeDraftStore {
  _FailingDraftStore({required this.failures});

  int failures;

  @override
  Future<void> write(
    String siteUrl,
    String draftKey,
    String data, {
    bool Function()? ifCurrent,
  }) async {
    if (failures > 0) {
      failures--;
      throw const DraftWriteException();
    }
    return super.write(siteUrl, draftKey, data, ifCurrent: ifCurrent);
  }
}

final class _FlakyDraftStore extends FakeDraftStore {
  _FlakyDraftStore({this.readFailures = 0});

  int readFailures;
  int clearFailures = 0;

  @override
  Future<String?> read(String siteUrl, String draftKey) async {
    if (readFailures > 0) {
      readFailures--;
      throw StateError('Draft read failed');
    }
    return super.read(siteUrl, draftKey);
  }

  @override
  Future<void> clear(
    String siteUrl,
    String draftKey, {
    bool Function()? ifCurrent,
  }) async {
    if (clearFailures > 0) {
      clearFailures--;
      throw StateError('Draft clear failed');
    }
    return super.clear(siteUrl, draftKey, ifCurrent: ifCurrent);
  }
}

double _textWidth(WidgetTester tester, Finder text) {
  final widget = tester.widget<Text>(text);
  final context = tester.element(text);
  final painter = TextPainter(
    text: TextSpan(text: widget.textSpan!.toPlainText(), style: widget.style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  return painter.width;
}

List<Rect> _inlineWidgetBoxes(WidgetTester tester, Finder text) {
  final paragraph = tester.renderObject<RenderParagraph>(text);
  final boxes = <Rect>[];
  paragraph.visitChildren((child) {
    final box = child as RenderBox;
    boxes.add(box.localToGlobal(Offset.zero) & box.size);
  });
  return boxes;
}

/// A 1x1 transparent PNG — the smallest thing `Image.memory` will accept.
final Uint8List emojiPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
