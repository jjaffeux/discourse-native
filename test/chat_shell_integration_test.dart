import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/app_settings.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/topic.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart'
    show SidebarPanelContribution, SidebarPanelPlugin, SitePlugin;
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer.dart';
import 'package:discourse_native/src/plugins/chat/chat_drawer_preferences_store.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/composer_panel.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/hover_action_toolbar.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_button.dart';
import 'package:discourse_native/src/theme/d_icon.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_shell.dart';
import 'support/fakes.dart';
import 'support/finders.dart';

import 'support/shell_test_harness.dart';

void main() {
  _registerChatShellTests();
}

void _registerChatShellTests() {
  group('chat', () {
    const me = DiscourseUser(id: 7, username: 'joffreyj', name: 'Joffrey');
    const site = 'https://meta.discourse.org';

    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => SharedPreferences.setMockInitialValues({}));

    final withChat = chatNotificationTotals();
    const withoutChat = NotificationTotals();

    SiteConfig chatConfig({
      bool searchEnabled = false,
      bool publicChannelsEnabled = true,
      bool threadsEnabled = true,
      ChatPreferredIndex preferredIndex = ChatPreferredIndex.channels,
      int channelRetentionDays = 0,
      ChatSeparateSidebarMode separateSidebarMode =
          ChatSeparateSidebarMode.never,
    }) => SiteConfig(
      plugins: PluginData.none.withValue(
        chatSettingsDataKey,
        ChatSettings(
          searchEnabled: searchEnabled,
          publicChannelsEnabled: publicChannelsEnabled,
          threadsEnabled: threadsEnabled,
          preferredIndex: preferredIndex,
          channelRetentionDays: channelRetentionDays,
          separateSidebarMode: separateSidebarMode,
        ),
      ),
    );

    DiscourseUser chatUser({
      bool? hasChatEnabled,
      bool? canDirectMessage,
      ChatHeaderIndicatorPreference headerIndicatorPreference =
          ChatHeaderIndicatorPreference.allNew,
      ChatSeparateSidebarMode separateSidebarMode =
          ChatSeparateSidebarMode.siteDefault,
      int? lastChannelId,
    }) => DiscourseUser(
      id: 7,
      username: 'joffreyj',
      plugins: PluginData.none.withValue(
        chatCurrentUserDataKey,
        ChatCurrentUser(
          hasChatEnabled: hasChatEnabled,
          canDirectMessage: canDirectMessage,
          headerIndicatorPreference: headerIndicatorPreference,
          separateSidebarMode: separateSidebarMode,
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
      bool threadingEnabled = false,
      int watchedThreads = 0,
      Map<int, DateTime> unreadThreadOverview = const {},
      DateTime? lastMessageAt,
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
      tracking: ChatTracking(
        unreadCount: unread,
        mentionCount: mentions,
        watchedThreadsUnreadCount: watchedThreads,
      ),
      threadingEnabled: threadingEnabled,
      unreadThreadOverview: unreadThreadOverview,
      lastMessageAt: lastMessageAt,
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
      String raw = '',
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
      raw: raw,
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
      DiscourseUser? user = me,
      ChatPresence presence = const ChatPresence(),
      bool hasThreads = false,
      SiteConfig config = const SiteConfig.unknown(),
      FakeForumTabStore? forumTabs,
      http.Client? mediaClient,
      ChatPreferredDisplayMode preferredDisplayMode =
          ChatPreferredDisplayMode.fullPage,
    }) async {
      await const ChatDrawerPreferencesStore().writePreferredDisplayMode(
        preferredDisplayMode,
      );
      final authenticator = FakeAuthenticator();
      if (user != null) authenticator.keys[site] = 'meta-key';
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
                  hasThreads: hasThreads,
                  presence: presence,
                ),
              },
              chatChannelGate: channelGate,
              chatMessagesByKey: messages,
              siteConfigs:
                  config.chatSettings.searchEnabled ||
                      !config.chatSettings.publicChannelsEnabled ||
                      !config.chatSettings.threadsEnabled ||
                      config.chatSettings.preferredIndex !=
                          ChatPreferredIndex.channels ||
                      config.chatSettings.separateSidebarMode !=
                          ChatSeparateSidebarMode.never
                  ? {site: config}
                  : const {},
            ),
        instances: [
          instance(
            'meta.discourse.org',
            title: 'Meta',
          ).copyWith(user: user, config: config),
        ],
        authenticator: authenticator,
        forumTabs: forumTabs,
        mediaClient: mediaClient,
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

      testWidgets(
        'opens a modeless desktop drawer without replacing the forum route',
        (tester) async {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            feeds: const {'/latest.json': []},
            categoryList: const [
              TopicCategory(id: 1, name: 'Support', color: '888888'),
            ],
            categoryLoadComplete: false,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
            chatMessagesByKey: {key(9): page(const [])},
          );
          await pumpChat(
            tester,
            api: api,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final forumRoute = shell.currentContent?.id;

          await tester.tap(shortcut);
          await tester.pumpAndSettle();

          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
          expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);
          expect(
            tester.getSize(find.byKey(ChatDrawerOverlay.expandedKey)),
            const Size(400, 530),
          );
          expect(
            find.descendant(
              of: find.byKey(ChatDrawerOverlay.drawerKey),
              matching: find.byType(ModalBarrier),
            ),
            findsNothing,
          );
          expect(shell.currentContent?.id, forumRoute);
          expect(shortcut, findsOneWidget);
          expect(
            find.byKey(const ValueKey('chat-drawer-channel-9')),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();

          expect(find.byType(ChatChannelView), findsOneWidget);
          expect(shell.currentContent?.id, forumRoute);
          expect(
            shell.chat.channel(site, 9)?.membership.lastViewedAt,
            isNotNull,
          );
          expect(find.byKey(ChatDrawerOverlay.overflowButtonKey), findsNothing);
          expect(
            find.byKey(ChatDrawerOverlay.fullPageButtonKey),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(ChatDrawerOverlay.fullPageButtonKey),
              matching: find.dIcon(DIcons.discourseExpand),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(ChatDrawerOverlay.collapseButtonKey),
              matching: find.dIcon(DIcons.minus),
            ),
            findsOneWidget,
          );

          final categoryRequests = api.categoryRequests.length;
          await tester.tap(sidebarDestination('Topics'));
          await tester.pumpAndSettle();

          expect(api.categoryRequests.length, greaterThan(categoryRequests));
          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
          expect(shell.currentContent?.id, forumRoute);
        },
      );

      testWidgets(
        'keeps list headers free of channel actions and stars channel titles',
        (tester) async {
          await pumpChat(
            tester,
            public: [
              channel(
                9,
                title: 'general',
                starred: true,
                threadingEnabled: true,
              ),
            ],
            messages: {key(9): page(const [])},
            hasThreads: true,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );

          await tester.tap(shortcut);
          await tester.pumpAndSettle();

          final header = find.byKey(ChatDrawerOverlay.headerKey);
          expect(
            find.descendant(
              of: header,
              matching: find.byKey(const ValueKey('chat-channel-star-button')),
            ),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('chat-channel-threads-button')),
            findsNothing,
          );
          expect(
            find.descendant(
              of: find.byKey(ChatDrawerFooter.footerKey),
              matching: find.byTooltip('My threads'),
            ),
            findsOneWidget,
          );

          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();

          final title = find.descendant(
            of: header,
            matching: find.text('general'),
          );
          final star = find.descendant(
            of: header,
            matching: find.byKey(const ValueKey('chat-channel-star-button')),
          );
          expect(star, findsOneWidget);
          expect(
            tester.getRect(star).left - tester.getRect(title).right,
            closeTo(5, 0.01),
          );
          expect(
            find.byKey(const ValueKey('chat-channel-threads-button')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'drawer rows keep muted urgency and expose web list actions',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9, emoji: 'bug', mentions: 100, muted: true)],
            direct: [dm(12)],
            user: chatUser(canDirectMessage: true),
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();

          final row = find.byKey(const ValueKey('chat-drawer-channel-9'));
          final emoji = find.descendant(
            of: row,
            matching: find.byType(EmojiImage),
          );
          expect(emoji, findsOneWidget);
          expect(
            tester.widget<EmojiImage>(emoji).url,
            shell.emojiUrlFor(site, 'bug'),
          );
          expect(
            find.descendant(of: row, matching: find.text('99+')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: row,
              matching: find.byKey(
                const ValueKey('chat-channel-menu-button-9'),
              ),
            ),
            findsOneWidget,
          );
          final title = tester.widget<Text>(
            find.descendant(of: row, matching: find.text('Bugs')),
          );
          expect(title.style?.color?.a, lessThan(1));

          final browse = find.byKey(
            const ValueKey('chat-drawer-browse-action'),
          );
          expect(browse, findsOneWidget);
          await tester.tap(browse);
          await tester.pumpAndSettle();
          expect(chatShell.drawerCurrentContent?.id, ChatPlugin.browseRouteId);

          chatShell.openDirectMessages();
          await tester.pumpAndSettle();
          final newMessage = find.byKey(
            const ValueKey('chat-drawer-new-message-action'),
          );
          expect(newMessage, findsOneWidget);
          await tester.tap(newMessage);
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('chat-new-direct-message-dialog')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'a minimum-width channel header moves secondary actions into overflow',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          addTearDown(() => SharedPreferences.setMockInitialValues({}));
          await const ChatDrawerPreferencesStore().writeDrawerSize(
            width: 250,
            height: 530,
          );
          await pumpChat(
            tester,
            public: [channel(9)],
            messages: {key(9): page(const [])},
            config: chatConfig(searchEnabled: true),
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();

          final header = find.byKey(ChatDrawerOverlay.headerKey);
          expect(
            tester.getSize(find.byKey(ChatDrawerOverlay.expandedKey)).width,
            250,
          );
          expect(
            find.descendant(of: header, matching: find.byTooltip('Back')),
            findsOneWidget,
          );
          expect(
            find.descendant(of: header, matching: find.text('Bugs')),
            findsOneWidget,
          );
          expect(
            find.byKey(ChatDrawerOverlay.collapseButtonKey),
            findsOneWidget,
          );
          expect(find.byKey(ChatDrawerOverlay.closeButtonKey), findsOneWidget);
          expect(
            find.byKey(ChatDrawerOverlay.overflowButtonKey),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('chat-channel-star-button'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('chat-channel-search-button'))
                .hitTestable(),
            findsNothing,
          );
          expect(
            find.byKey(ChatDrawerOverlay.fullPageButtonKey).hitTestable(),
            findsNothing,
          );
          expect(tester.takeException(), isNull);

          await tester.tap(find.byKey(ChatDrawerOverlay.overflowButtonKey));
          await tester.pumpAndSettle();

          expect(
            find
                .byKey(const ValueKey('chat-channel-star-button'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('chat-channel-search-button'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(ChatDrawerOverlay.fullPageButtonKey).hitTestable(),
            findsOneWidget,
          );

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(
            find
                .byKey(const ValueKey('chat-channel-star-button'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);

          await tester.tap(find.byKey(ChatDrawerOverlay.overflowButtonKey));
          await tester.pumpAndSettle();

          await tester.tap(
            find
                .byKey(const ValueKey('chat-channel-search-button'))
                .hitTestable(),
          );
          await tester.pumpAndSettle();

          expect(
            find.byKey(const ValueKey('chat-channel-search-field')),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('chat-channel-star-button'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets('drawer state immediately updates separate sidebar policy', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          user: chatUser(separateSidebarMode: ChatSeparateSidebarMode.always),
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );

        expect(sidebarDestination('Topics'), findsOneWidget);
        expect(sidebarDestination('Bugs'), findsNothing);

        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
        expect(sidebarDestination('Topics'), findsNothing);
        expect(sidebarDestination('Bugs'), findsOneWidget);

        await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
        await tester.pumpAndSettle();

        expect(sidebarDestination('Topics'), findsOneWidget);
        expect(sidebarDestination('Bugs'), findsNothing);
      });

      testWidgets(
        'the active drawer channel is selected in the forum sidebar',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9, threadingEnabled: true)],
            messages: {key(9): page(const [])},
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          Text sidebarLabel() =>
              tester.widget<Text>(sidebarDestination('Bugs'));
          expect(sidebarLabel().style?.fontWeight, FontWeight.w400);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();

          expect(sidebarLabel().style?.fontWeight, FontWeight.w600);

          expect(
            chatShell.openChannelInfo(siteUrl: site, channelId: 9),
            isTrue,
          );
          await tester.pumpAndSettle();
          expect(sidebarLabel().style?.fontWeight, FontWeight.w600);

          expect(
            chatShell.openChannelThreads(siteUrl: site, channelId: 9),
            isTrue,
          );
          await tester.pumpAndSettle();
          expect(sidebarLabel().style?.fontWeight, FontWeight.w600);

          await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
          await tester.pumpAndSettle();
          expect(sidebarLabel().style?.fontWeight, FontWeight.w400);

          await tester.tap(find.byKey(ChatDrawerOverlay.headerKey));
          await tester.pumpAndSettle();
          expect(sidebarLabel().style?.fontWeight, FontWeight.w600);

          await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
          await tester.pumpAndSettle();

          expect(sidebarLabel().style?.fontWeight, FontWeight.w400);
        },
      );

      testWidgets('Alt arrows cycle channels and unread channels with wrap', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [
            channel(9),
            channel(10, title: 'Support', unread: 1),
          ],
          direct: [dm(12, title: 'hawk', unread: 1)],
          messages: {
            key(9): page(const []),
            key(10): page(const []),
            key(12): page(const []),
          },
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final chatShell = shell.pluginSession.require(chatShellService);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(chatShell.drawerCurrentContent?.id, ChatChannel.routeId(10));

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(chatShell.drawerCurrentContent?.id, ChatChannel.routeId(9));

        await tester.tap(find.byKey(const ValueKey('chat-composer')));
        await tester.pump();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(
          chatShell.drawerCurrentContent?.id,
          ChatChannel.routeId(10),
          reason: 'the web shortcut remains global while editing text',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        await tester.pumpAndSettle();
        expect(chatShell.drawerCurrentContent?.id, ChatChannel.routeId(12));
      });

      testWidgets('permission revocation closes an open drawer immediately', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final chatShell = shell.pluginSession.require(chatShellService);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();
        final editor = tester.widget<EditableText>(
          find.descendant(
            of: find.byKey(const ValueKey('chat-composer')),
            matching: find.byType(EditableText),
          ),
        );
        await tester.enterText(
          find.descendant(
            of: find.byKey(const ValueKey('chat-composer')),
            matching: find.byType(EditableText),
          ),
          'draft survives permission refresh',
        );
        expect(editor.focusNode.hasFocus, isTrue);
        expect(chatShell.drawerActive, isTrue);

        shell.accountActivity.applyCounts(site, (_) => withoutChat);
        await chatShell.pluginTotalsLoaded(site, withoutChat, selected: true);
        await tester.pumpAndSettle();

        expect(chatShell.drawerActive, isFalse);
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
        expect(shortcut, findsNothing);
        expect(editor.focusNode.hasFocus, isFalse);
        expect(editor.controller.text, 'draft survives permission refresh');
      });

      testWidgets('disconnect clears drawer history and viewing state', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final chatShell = shell.pluginSession.require(chatShellService);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();
        expect(chatShell.drawerContentStack, isNotEmpty);
        final tracker = FakeSiteTracker.built.single;
        expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);

        await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(ChatDrawerOverlay.collapseButtonKey)).width,
          lessThanOrEqualTo(1),
        );
        expect(tracker.pluginChannelCallbacks['/chat/9'], isNotEmpty);

        await shell.disconnectCurrentInstance();
        await tester.pumpAndSettle();

        expect(chatShell.drawerActive, isFalse);
        expect(chatShell.drawerContentStack, isEmpty);
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
        expect(tracker.pluginChannelCallbacks['/chat/9'], isEmpty);
      });

      testWidgets(
        'drawer Back follows route context and is absent on index routes',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9, threadingEnabled: true)],
            direct: [dm(12)],
            user: chatUser(canDirectMessage: true),
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();

          expect(chatShell.openChannel(9), isTrue);
          for (final openIndex in <void Function()>[
            chatShell.openChannels,
            chatShell.openStarredChannels,
            chatShell.openDirectMessages,
            chatShell.openMyThreads,
            chatShell.openSearch,
          ]) {
            openIndex();
            expect(chatShell.drawerCanGoBack, isFalse);
            expect(chatShell.openChannel(9), isTrue);
          }

          chatShell.forget(site);
          expect(chatShell.openChannel(9), isTrue);
          expect(chatShell.drawerContentStack.map((route) => route.id), [
            'chat-c-9',
          ]);
          expect(chatShell.drawerCanGoBack, isTrue);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.channelsRouteId,
          );

          chatShell.forget(site);
          expect(chatShell.openChannel(12), isTrue);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.directMessagesRouteId,
          );

          chatShell.forget(site);
          chatShell.openStarredChannels();
          expect(chatShell.openChannel(9), isTrue);
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, ChatPlugin.starredRouteId);

          chatShell.forget(site);
          chatShell.openSearch();
          expect(chatShell.openChannel(9), isTrue);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.channelsRouteId,
          );

          chatShell.forget(site);
          chatShell.openMyThreads();
          expect(chatShell.openChannel(12), isTrue);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.directMessagesRouteId,
          );

          chatShell.forget(site);
          chatShell.openStarredChannels();
          chatShell.openBrowseChannels();
          expect(chatShell.drawerCanGoBack, isTrue);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.channelsRouteId,
          );

          chatShell.forget(site);
          expect(
            chatShell.openChannelInfo(siteUrl: site, channelId: 9),
            isTrue,
          );
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');

          chatShell.forget(site);
          chatShell.openMyThreads();
          expect(
            chatShell.openChannelInfo(siteUrl: site, channelId: 9),
            isTrue,
          );
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');

          chatShell.forget(site);
          expect(
            chatShell.openChannelThreads(siteUrl: site, channelId: 9),
            isTrue,
          );
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');

          chatShell.forget(site);
          chatShell.openSearch();
          expect(
            chatShell.openChannelThreads(siteUrl: site, channelId: 9),
            isTrue,
          );
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');

          chatShell.forget(site);
          chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');

          chatShell.forget(site);
          chatShell.openMyThreads();
          chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.myThreadsRouteId,
          );

          chatShell.forget(site);
          expect(
            chatShell.openChannelThreads(siteUrl: site, channelId: 9),
            isTrue,
          );
          chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
          chatShell.drawerBack();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.channelThreadsRouteId(9),
          );

          chatShell.forget(site);
          chatShell.openSearch();
          chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
          chatShell.drawerBack();
          expect(chatShell.drawerCurrentContent?.id, 'chat-c-9');
          chatShell.closeDrawer();
          await tester.pump();
        },
      );

      testWidgets('drawer initial route honors the preferred Chat index', (
        tester,
      ) async {
        Future<String?> openInitialRoute({
          required SiteConfig config,
          DiscourseUser? user,
          List<ChatChannel> direct = const [],
          bool hasThreads = false,
          bool starred = false,
        }) async {
          await pumpChat(
            tester,
            public: [channel(9, starred: starred)],
            direct: direct,
            hasThreads: hasThreads,
            user: user ?? chatUser(canDirectMessage: true),
            config: config,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          return shell.pluginSession
              .require(chatShellService)
              .drawerCurrentContent
              ?.id;
        }

        expect(
          await openInitialRoute(
            config: chatConfig(preferredIndex: ChatPreferredIndex.myThreads),
            hasThreads: true,
            starred: true,
          ),
          ChatPlugin.starredRouteId,
        );
        expect(
          await openInitialRoute(
            config: chatConfig(preferredIndex: ChatPreferredIndex.myThreads),
            hasThreads: true,
          ),
          ChatPlugin.myThreadsRouteId,
        );
        expect(
          await openInitialRoute(
            config: chatConfig(
              preferredIndex: ChatPreferredIndex.directMessages,
            ),
            user: chatUser(canDirectMessage: false),
            direct: [dm(12)],
          ),
          ChatPlugin.directMessagesRouteId,
        );
        expect(
          await openInitialRoute(
            config: chatConfig(preferredIndex: ChatPreferredIndex.myThreads),
          ),
          ChatPlugin.channelsRouteId,
        );
        expect(
          await openInitialRoute(
            config: chatConfig(publicChannelsEnabled: false),
            user: chatUser(canDirectMessage: false),
          ),
          isNull,
        );
      });

      testWidgets('disabled public and thread routes stay unavailable', (
        tester,
      ) async {
        final config = chatConfig(
          publicChannelsEnabled: false,
          threadsEnabled: false,
        );
        await pumpChat(
          tester,
          public: [channel(9, threadingEnabled: true)],
          direct: [dm(12)],
          hasThreads: true,
          user: chatUser(canDirectMessage: true),
          config: config,
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        expect(sidebarDestination('Browse channels'), findsNothing);
        expect(sidebarDestination('My threads'), findsNothing);
        expect(sidebarDestination('Bugs'), findsNothing);

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final chatShell = shell.pluginSession.require(chatShellService);
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(
          chatShell.drawerCurrentContent?.id,
          ChatPlugin.directMessagesRouteId,
        );
        expect(
          chatShell.openChannelThreads(siteUrl: site, channelId: 9),
          isFalse,
        );

        chatShell.openBrowseChannels();
        await tester.pumpAndSettle();
        expect(find.text('Chat channels are not available.'), findsOneWidget);
        chatShell.openMyThreads();
        await tester.pumpAndSettle();
        expect(find.text('Chat threads are not available.'), findsOneWidget);
      });

      testWidgets('collapse, close, and Escape retain the drawer route', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-drawer-channel-9')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.collapsedKey), findsOneWidget);
        expect(find.byType(ChatChannelView), findsNothing);
        expect(find.byKey(ChatDrawerOverlay.fullPageButtonKey), findsNothing);
        expect(
          tester.getSize(find.byKey(ChatDrawerOverlay.collapseButtonKey)).width,
          lessThanOrEqualTo(1),
        );

        final collapsedToggle = find.descendant(
          of: find.byKey(ChatDrawerOverlay.collapseButtonKey),
          matching: find.byType(FilledButton),
        );
        Focus.of(
          tester.element(
            find.descendant(of: collapsedToggle, matching: find.byType(DIcon)),
          ),
        ).requestFocus();
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(ChatDrawerOverlay.collapseButtonKey)).width,
          greaterThan(1),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(ChatChannelView), findsOneWidget);

        await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);

        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        expect(find.byType(ChatChannelView), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('chat-composer')));
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
      });

      testWidgets('collapse and close retain an in-progress message edit', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {
            key(9): page([
              msg(
                41,
                author: 7,
                username: 'joffreyj',
                raw: 'Original message',
                cooked: '<p>Original message</p>',
              ),
            ]),
          },
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();

        final composer = find.byKey(const ValueKey('chat-composer'));
        await tester.tap(composer);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsOneWidget,
        );

        Finder editor() =>
            find.descendant(of: composer, matching: find.byType(EditableText));
        await tester.enterText(editor(), 'Modified while editing');
        await tester.pump();

        await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
        await tester.pumpAndSettle();
        expect(editor(), findsNothing);
        await tester.tap(find.byKey(ChatDrawerOverlay.headerKey));
        await tester.pumpAndSettle();
        expect(
          tester.widget<EditableText>(editor()).controller.text,
          'Modified while editing',
        );

        await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('chat-composer-edit-cancel')),
          findsOneWidget,
        );
        expect(
          tester.widget<EditableText>(editor()).controller.text,
          'Modified while editing',
        );
      });

      testWidgets('Escape dismisses a modal before the drawer', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        unawaited(
          showDialog<void>(
            context: tester.element(find.byKey(ChatDrawerOverlay.expandedKey)),
            builder: (context) => const AlertDialog(
              title: Text('Layered dialog'),
              content: Text('Dismiss me first'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Layered dialog'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Layered dialog'), findsNothing);
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
      });

      testWidgets('Escape closes scoped channel search before the drawer', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          config: chatConfig(searchEnabled: true),
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-search-button')),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-channel-search-field')),
          findsOneWidget,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('chat-channel-search-field')),
          findsNothing,
        );
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
      });

      testWidgets('closing the drawer resets scoped channel search', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          config: chatConfig(searchEnabled: true),
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-search-button')),
        );
        await tester.pumpAndSettle();
        final search = find.byKey(const ValueKey('chat-channel-search-field'));
        await tester.enterText(search, 'stale query');

        await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(search, findsNothing);
        expect(
          find.byKey(const ValueKey('chat-channel-search-button')),
          findsOneWidget,
        );
      });

      testWidgets(
        'footer exposes empty capable routes and leaves an emptied Starred list',
        (tester) async {
          await pumpChat(
            tester,
            public: [channel(9, starred: true)],
            messages: {key(9): page(const [])},
            user: chatUser(canDirectMessage: true),
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          expect(chatShell.drawerCurrentContent?.id, ChatPlugin.starredRouteId);
          expect(find.byKey(ChatDrawerFooter.footerKey), findsOneWidget);
          expect(find.byTooltip('DMs'), findsOneWidget);

          expect(await shell.chat.updateChannelStarred(site, 9, false), isNull);
          await tester.pumpAndSettle();

          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.channelsRouteId,
          );
          expect(find.text('You have no starred channels.'), findsNothing);

          await tester.tap(
            find.descendant(
              of: find.byKey(ChatDrawerFooter.footerKey),
              matching: find.byTooltip('DMs'),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            chatShell.drawerCurrentContent?.id,
            ChatPlugin.directMessagesRouteId,
          );
          expect(find.text('You have no direct messages yet.'), findsOneWidget);
          expect(find.byKey(ChatDrawerFooter.footerKey), findsOneWidget);

          await tester.tap(
            find.descendant(
              of: find.byKey(ChatDrawerFooter.footerKey),
              matching: find.byTooltip('Channels'),
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();
          expect(chatShell.drawerCurrentContent?.id, ChatChannel.routeId(9));
          expect(chatShell.drawerActive, isTrue);
          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
          expect(find.byType(ChatChannelView), findsOneWidget);
          expect(find.byKey(ChatDrawerFooter.footerKey), findsNothing);
        },
      );

      testWidgets(
        'full-page round trip restores the exact forum and Chat routes',
        (tester) async {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            feeds: const {'/latest.json': []},
            creatableFeedPaths: const {'/latest.json'},
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
            chatMessagesByKey: {key(9): page(const [])},
          );
          await pumpChat(
            tester,
            api: api,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final forumRoute = shell.currentContent?.id;

          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();
          Finder editor() => find.descendant(
            of: find.byKey(const ValueKey('chat-composer')),
            matching: find.byType(EditableText),
          );
          await tester.enterText(editor(), 'draft before maximizing');
          await tester.pump();
          await tester.tap(find.byKey(ChatDrawerOverlay.fullPageButtonKey));
          await tester.pumpAndSettle();

          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
          expect(shell.currentContent?.id, 'chat-c-9');
          expect(
            find.byKey(const ValueKey('chat-close-full-page')),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byKey(const ValueKey('chat-close-full-page')),
              matching: find.dIcon(DIcons.discourseCompress),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<EditableText>(editor()).controller.text,
            'draft before maximizing',
          );

          await tester.enterText(editor(), 'sent from full page');
          await tester.tap(find.byKey(const ValueKey('chat-composer-send')));
          await tester.pumpAndSettle();
          expect(api.chatMessagesSent.single.message, 'sent from full page');
          expect(
            tester.widget<EditableText>(editor()).controller.text,
            isEmpty,
          );

          await tester.tap(find.byKey(const ValueKey('chat-close-full-page')));
          await tester.pumpAndSettle();

          expect(shell.currentContent?.id, forumRoute);
          expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);
          expect(find.byType(ChatChannelView), findsOneWidget);
          expect(
            tester.widget<EditableText>(editor()).controller.text,
            isEmpty,
          );
          expect(
            (await SharedPreferences.getInstance()).getString(
              ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
            ),
            'DRAWER_CHAT',
          );
        },
      );

      testWidgets(
        'a compact layout forces full page without replacing the preference',
        (tester) async {
          await pumpChat(
            tester,
            size: phone,
            public: [channel(9)],
            messages: {key(9): page(const [])},
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );

          await tester.tap(shortcut);
          await tester.pumpAndSettle();

          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
          expect(find.byType(ChatChannelView), findsOneWidget);
          expect(
            (await SharedPreferences.getInstance()).getString(
              ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
            ),
            'DRAWER_CHAT',
          );
        },
      );

      testWidgets(
        'a direct message link bypasses retained hidden drawer consumers',
        (tester) async {
          final target = msg(41, cooked: '<p>Exact target</p>');
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            feeds: const {'/latest.json': []},
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
            chatMessagesByKey: {
              key(9): page(const []),
              FakeDiscourseApi.chatMessagesKey(9, targetMessageId: 41): (
                messages: [target],
                canLoadMorePast: false,
                canLoadMoreFuture: false,
                targetMessageId: 41,
              ),
            },
          );
          await pumpChat(
            tester,
            api: api,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ChatDrawerOverlay.closeButtonKey));
          await tester.pumpAndSettle();

          expect(
            await chatShell.openPluginUrl(
              '$site/chat/c/-/9/41',
              origin: PluginLinkOrigin.direct,
            ),
            isTrue,
          );
          await tester.pumpAndSettle();

          expect(chatShell.drawerActive, isFalse);
          expect(shell.currentContent?.id, 'chat-c-9');
          expect(
            find.byKey(const ValueKey('chat-message-highlight')),
            findsOneWidget,
          );
          expect(api.chatMessagesRequested.last.targetMessageId, 41);
        },
      );

      testWidgets('shrinking an open drawer promotes its exact route', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();

        tester.view.physicalSize = phone;
        await tester.pumpAndSettle();

        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
        expect(shell.currentContent?.id, 'chat-c-9');
        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(
          (await SharedPreferences.getInstance()).getString(
            ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
          ),
          'DRAWER_CHAT',
        );
      });

      testWidgets('the global minus shortcut opens and closes the drawer', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);

        final collapseButton = find.descendant(
          of: find.byKey(ChatDrawerOverlay.collapseButtonKey),
          matching: find.byType(FilledButton),
        );
        Focus.of(
          tester.element(
            find.descendant(of: collapseButton, matching: find.byType(DIcon)),
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
      });

      testWidgets('the global minus shortcut restores drawer preference', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-drawer-channel-9')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ChatDrawerOverlay.fullPageButtonKey));
        await tester.pumpAndSettle();
        expect(find.byKey(ChatDrawerOverlay.drawerKey), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-close-full-page')),
          findsOneWidget,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pumpAndSettle();

        expect(find.byKey(ChatDrawerOverlay.expandedKey), findsOneWidget);
        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(
          find.byKey(const ValueKey('chat-close-full-page')),
          findsNothing,
        );
        expect(
          (await SharedPreferences.getInstance()).getString(
            ChatDrawerPreferencesStore.preferredDisplayModeStorageKey,
          ),
          'DRAWER_CHAT',
        );
      });

      testWidgets('resizes from the top-start corner and persists the size', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        await const ChatDrawerPreferencesStore().writeDrawerSize(
          width: 480,
          height: 600,
        );
        await pumpChat(
          tester,
          public: [channel(9)],
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        final drawer = find.byKey(ChatDrawerOverlay.expandedKey);
        expect(tester.getSize(drawer), const Size(480, 600));

        final resizeHandle = find.byKey(ChatDrawerOverlay.resizeHandleKey);
        expect(tester.getSize(resizeHandle), const Size.square(15));
        expect(
          find.descendant(of: resizeHandle, matching: find.byType(CustomPaint)),
          findsNothing,
        );

        await tester.drag(resizeHandle, const Offset(-80, -70));
        await tester.pumpAndSettle();

        expect(tester.getSize(drawer), const Size(560, 670));
        final preferences = await SharedPreferences.getInstance();
        expect(
          preferences.getDouble(
            ChatDrawerPreferencesStore.drawerWidthStorageKey,
          ),
          560,
        );
        expect(
          preferences.getDouble(
            ChatDrawerPreferencesStore.drawerHeightStorageKey,
          ),
          670,
        );
      });

      testWidgets('keeps expanded and collapsed drawers above the safe area', (
        tester,
      ) async {
        tester.view.viewPadding = const FakeViewPadding(bottom: 34);
        addTearDown(tester.view.resetViewPadding);
        await pumpChat(
          tester,
          public: [channel(9)],
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        final overlay = find.byKey(ChatDrawerOverlay.drawerKey);
        final expanded = find.byKey(ChatDrawerOverlay.expandedKey);
        final expectedInset =
            tester.view.viewPadding.bottom / tester.view.devicePixelRatio;
        expect(
          tester.getRect(overlay).bottom - tester.getRect(expanded).bottom,
          closeTo(expectedInset, 0.1),
        );

        await tester.tap(find.byKey(ChatDrawerOverlay.collapseButtonKey));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(overlay).bottom -
              tester.getRect(find.byKey(ChatDrawerOverlay.collapsedKey)).bottom,
          closeTo(expectedInset, 0.1),
        );
      });

      testWidgets('a wide drawer keeps thread routes in one pane', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        await const ChatDrawerPreferencesStore().writeDrawerSize(
          width: 700,
          height: 600,
        );
        final threadedChannel = channel(9, threadingEnabled: true);
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
          chatChannelsBySite: {
            site: ChatChannels(public: [threadedChannel]),
          },
          chatThreadsByKey: const {
            '9~3': ChatThread(
              id: 3,
              channelId: 9,
              status: 'open',
              replyCount: 0,
              title: 'Drawer thread',
              originalMessage: ChatThreadOriginalMessage(
                id: 30,
                channelId: 9,
                author: ChatMessageAuthor(id: 7, username: 'joffreyj'),
              ),
              membership: ChatThreadMembership(threadId: 3),
            ),
            '9~4': ChatThread(
              id: 4,
              channelId: 9,
              status: 'open',
              replyCount: 0,
              title: 'Second drawer thread',
              membership: ChatThreadMembership(threadId: 4),
            ),
          },
          chatMessagesByKey: {
            'thread-9-3': page(const []),
            'thread-9-4': page(const []),
          },
        );
        await pumpChat(
          tester,
          api: api,
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final chatShell = shell.pluginSession.require(chatShellService);

        await tester.tap(shortcut);
        await tester.pumpAndSettle();
        chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
        await tester.pumpAndSettle();

        expect(
          tester.getSize(find.byKey(ChatDrawerOverlay.expandedKey)).width,
          700,
        );
        expect(find.byKey(const ValueKey('chat-channel-pane')), findsNothing);
        expect(find.byKey(const ValueKey('chat-thread-pane')), findsNothing);
        expect(find.byType(ChatThreadView), findsOneWidget);
        expect(find.text('Drawer thread'), findsOneWidget);
        expect(find.byTooltip('Thread notifications'), findsOneWidget);
        expect(find.byTooltip('Thread settings'), findsOneWidget);

        chatShell.openThread(siteUrl: site, channelId: 9, threadId: 4);
        await tester.pumpAndSettle();

        expect(find.text('Second drawer thread'), findsOneWidget);
        expect(
          api.chatThreadMessagesRequested.map((request) => request.threadId),
          contains(4),
        );
      });

      testWidgets('a narrow drawer keeps thread notification selection alive', (
        tester,
      ) async {
        final previousPlatform = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          SharedPreferences.setMockInitialValues({});
          addTearDown(() => SharedPreferences.setMockInitialValues({}));
          await const ChatDrawerPreferencesStore().writeDrawerSize(
            width: 250,
            height: 530,
          );
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            feeds: const {'/latest.json': []},
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9, threadingEnabled: true)]),
            },
            chatThreadsByKey: const {
              '9~3': ChatThread(
                id: 3,
                channelId: 9,
                status: 'open',
                replyCount: 0,
                title: 'Narrow thread',
                membership: ChatThreadMembership(
                  threadId: 3,
                  notificationLevel: ChatThreadNotificationLevel.normal,
                ),
              ),
            },
            chatMessagesByKey: {'thread-9-3': page(const [])},
          );
          await pumpChat(
            tester,
            api: api,
            preferredDisplayMode: ChatPreferredDisplayMode.drawer,
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          final chatShell = shell.pluginSession.require(chatShellService);

          await tester.tap(shortcut);
          await tester.pumpAndSettle();
          chatShell.openThread(siteUrl: site, channelId: 9, threadId: 3);
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(ChatDrawerOverlay.overflowButtonKey));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('Thread notifications'));
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('choice-menu-surface')),
            findsOneWidget,
          );

          await tester.tap(find.text('Tracking'));
          await tester.pumpAndSettle();

          expect(
            api.chatThreadNotificationLevelsUpdated.single.notificationLevel,
            ChatThreadNotificationLevel.tracking,
          );
          expect(
            find.byKey(const ValueKey('choice-menu-surface')),
            findsNothing,
          );
          expect(find.byKey(ChatDrawerOverlay.drawerKey), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = previousPlatform;
        }
      });

      testWidgets('avoids only the actual movable composer rectangle', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        addTearDown(() => SharedPreferences.setMockInitialValues({}));
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          feeds: const {'/latest.json': []},
          creatableFeedPaths: const {'/latest.json'},
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)]),
          },
        );
        await pumpChat(
          tester,
          api: api,
          preferredDisplayMode: ChatPreferredDisplayMode.drawer,
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        await tester.tap(shortcut);
        await tester.pumpAndSettle();

        await shell.openNewTopic();
        await tester.pumpAndSettle();

        final composer = find.byType(ComposerPanel);
        final drawer = find.byKey(ChatDrawerOverlay.expandedKey);
        final overlay = find.byKey(ChatDrawerOverlay.drawerKey);
        expect(composer, findsOneWidget);
        expect(
          tester.getRect(drawer).bottom,
          closeTo(tester.getRect(composer).top, 1),
        );

        await tester.drag(
          find.byKey(const ValueKey('composer-resize-right')),
          const Offset(-1000, 0),
        );
        await tester.drag(
          find.byKey(const ValueKey('composer-drag-handle')),
          const Offset(-1000, 0),
        );
        await tester.pumpAndSettle();

        expect(
          tester.getRect(composer).right,
          lessThan(tester.getRect(drawer).left),
        );
        expect(
          tester.getRect(drawer).bottom,
          closeTo(tester.getRect(overlay).bottom, 1),
        );
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
      group('separate sidebar modes', () {
        for (final scenario in [
          (
            name: 'an explicit never preference overrides the site',
            userMode: ChatSeparateSidebarMode.never,
            siteMode: ChatSeparateSidebarMode.always,
            effectiveMode: ChatSeparateSidebarMode.never,
          ),
          (
            name: 'an explicit always preference overrides the site',
            userMode: ChatSeparateSidebarMode.always,
            siteMode: ChatSeparateSidebarMode.never,
            effectiveMode: ChatSeparateSidebarMode.always,
          ),
          (
            name: 'fullscreen separates only after entering Chat',
            userMode: ChatSeparateSidebarMode.fullscreen,
            siteMode: ChatSeparateSidebarMode.never,
            effectiveMode: ChatSeparateSidebarMode.fullscreen,
          ),
          (
            name: 'the default preference inherits the site setting',
            userMode: ChatSeparateSidebarMode.siteDefault,
            siteMode: ChatSeparateSidebarMode.always,
            effectiveMode: ChatSeparateSidebarMode.always,
          ),
        ]) {
          testWidgets(scenario.name, (tester) async {
            await pumpChat(
              tester,
              public: [channel(9)],
              messages: {key(9): page(const [])},
              user: chatUser(separateSidebarMode: scenario.userMode),
              config: chatConfig(separateSidebarMode: scenario.siteMode),
            );

            const chatSwitch = ValueKey('sidebar-panel-switch-chat');
            const forumSwitch = ValueKey('sidebar-panel-switch-main');
            final separates =
                scenario.effectiveMode != ChatSeparateSidebarMode.never;
            final combinesOffChat =
                scenario.effectiveMode != ChatSeparateSidebarMode.always;

            expect(sidebarDestination('Topics'), findsOneWidget);
            expect(
              sidebarDestination('Bugs'),
              combinesOffChat ? findsOneWidget : findsNothing,
            );
            expect(
              find.byKey(chatSwitch),
              separates ? findsOneWidget : findsNothing,
            );
            expect(find.byKey(forumSwitch), findsNothing);

            await tester.tap(
              combinesOffChat
                  ? sidebarDestination('Bugs')
                  : find.byKey(chatSwitch),
            );
            await tester.pumpAndSettle();

            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );
            expect(shell.currentContent?.id, 'chat-c-9');
            expect(
              sidebarDestination('Topics'),
              separates ? findsNothing : findsOneWidget,
            );
            expect(sidebarDestination('Bugs'), findsOneWidget);
            expect(
              find.byKey(forumSwitch),
              separates ? findsOneWidget : findsNothing,
            );
            expect(find.byKey(chatSwitch), findsNothing);
            expect(
              find.byTooltip(separates ? 'Exit chat' : 'Chat'),
              findsOneWidget,
            );
          });
        }

        testWidgets('appears when Chat totals arrive after the sidebar', (
          tester,
        ) async {
          await pumpChat(
            tester,
            totals: withoutChat,
            public: [channel(9)],
            messages: {key(9): page(const [])},
            user: chatUser(separateSidebarMode: ChatSeparateSidebarMode.always),
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );

          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            findsNothing,
          );

          shell.accountActivity.applyCounts(site, (_) => withChat);
          await tester.pumpAndSettle();

          expect(shell.currentTotals?.hasChatEnabled, isTrue);
          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
          );
          await tester.pumpAndSettle();

          expect(shell.currentContent?.id, 'chat-c-9');
          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-main')),
            findsOneWidget,
          );
        });

        for (final scenario in [
          (mode: ChatSeparateSidebarMode.never, separates: false),
          (mode: ChatSeparateSidebarMode.always, separates: true),
          (mode: ChatSeparateSidebarMode.fullscreen, separates: true),
        ]) {
          testWidgets(
            'anonymous public Chat honors site mode ${scenario.mode.wireName}',
            (tester) async {
              await pumpChat(
                tester,
                public: [channel(9)],
                messages: {key(9): page(const [])},
                user: null,
                config: chatConfig(separateSidebarMode: scenario.mode),
              );
              final shell = ShellScope.read(
                tester.element(find.byType(MainContent)),
              );
              await shell.chat.loadChannels(site);
              await tester.pumpAndSettle();

              expect(shell.currentInstance?.user, isNull);
              expect(sidebarDestination('Topics'), findsOneWidget);
              expect(sidebarDestination('Bugs'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-chat')),
                findsNothing,
              );
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-main')),
                findsNothing,
              );
              expect(find.byKey(ChatHeaderButton.buttonKey), findsNothing);

              await tester.tap(sidebarDestination('Bugs'));
              await tester.pumpAndSettle();

              expect(shell.currentContent?.id, 'chat-c-9');
              expect(
                sidebarDestination('Topics'),
                scenario.separates ? findsNothing : findsOneWidget,
              );
              expect(sidebarDestination('Bugs'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-main')),
                findsNothing,
              );
              expect(find.byKey(ChatHeaderButton.buttonKey), findsNothing);
            },
          );
        }

        testWidgets('switches between the exact last forum and Chat routes', (
          tester,
        ) async {
          await pumpChat(
            tester,
            public: [channel(9)],
            messages: {key(9): page(const [])},
            user: chatUser(separateSidebarMode: ChatSeparateSidebarMode.always),
            config: chatConfig(
              searchEnabled: true,
              separateSidebarMode: ChatSeparateSidebarMode.never,
            ),
          );
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          shell.pushContent(
            const ContentRoute(
              id: 'forum-detail',
              title: 'Forum detail',
              icon: DIcons.comments,
            ),
          );
          await tester.pumpAndSettle();

          expect(shell.currentContent?.id, 'forum-detail');
          expect(sidebarDestination('Topics'), findsOneWidget);
          expect(sidebarDestination('Bugs'), findsNothing);

          await tester.tap(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
          );
          await tester.pumpAndSettle();
          expect(shell.currentContent?.id, 'chat-c-9');
          expect(sidebarDestination('Topics'), findsNothing);
          expect(sidebarDestination('Search'), findsOneWidget);

          await tester.tap(sidebarDestination('Search'));
          await tester.pumpAndSettle();
          expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
          expect(sidebarDestination('Topics'), findsNothing);
          expect(find.byTooltip('Exit chat'), findsOneWidget);

          await tester.tap(
            find.byKey(const ValueKey('sidebar-panel-switch-main')),
          );
          await tester.pumpAndSettle();
          expect(shell.currentContent?.id, 'forum-detail');
          expect(sidebarDestination('Topics'), findsOneWidget);
          expect(sidebarDestination('Bugs'), findsNothing);

          await tester.tap(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
          );
          await tester.pumpAndSettle();
          expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
          expect(sidebarDestination('Topics'), findsNothing);
          expect(sidebarDestination('Search'), findsOneWidget);
          expect(find.byTooltip('Exit chat'), findsOneWidget);
        });

        testWidgets(
          'ordinary forum navigation preserves the auxiliary Chat pane',
          (tester) async {
            await pumpChat(
              tester,
              public: [channel(9)],
              messages: {key(9): page(const [])},
              user: chatUser(
                separateSidebarMode: ChatSeparateSidebarMode.always,
              ),
              config: chatConfig(searchEnabled: true),
            );
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            );
            await tester.pumpAndSettle();
            await tester.tap(sidebarDestination('Search'));
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(shell.contentStack.map((route) => route.id), [
              ChatPlugin.searchRouteId,
            ]);

            shell.selectDestination(
              const SidebarDestination(
                id: 'latest',
                label: 'Topics',
                icon: DIcons.layerGroup,
              ),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'latest');
            expect(shell.destinationId, 'latest');
            expect(shell.contentStack.map((route) => route.id), ['latest']);
            expect(sidebarDestination('Topics'), findsOneWidget);
            expect(sidebarDestination('Bugs'), findsNothing);

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(shell.contentStack.map((route) => route.id), [
              ChatPlugin.searchRouteId,
            ]);
            expect(sidebarDestination('Topics'), findsNothing);
            expect(sidebarDestination('Search'), findsOneWidget);
          },
        );

        for (final replace in [false, true]) {
          testWidgets(
            'cold direct ${replace ? 'replace' : 'push'} starts a clean Chat pane',
            (tester) async {
              await pumpChat(
                tester,
                public: [channel(9)],
                messages: {key(9): page(const [])},
                user: chatUser(
                  separateSidebarMode: ChatSeparateSidebarMode.always,
                ),
                config: chatConfig(searchEnabled: true),
              );
              final shell = ShellScope.read(
                tester.element(find.byType(MainContent)),
              );
              final forumRoute = ContentRoute(
                id: replace ? 'forum-before-replace' : 'forum-before-push',
                title: replace ? 'Forum before replace' : 'Forum before push',
                icon: DIcons.comments,
              );
              shell.selectDestination(
                SidebarDestination(
                  id: forumRoute.id,
                  label: forumRoute.title,
                  icon: forumRoute.icon,
                ),
              );
              await tester.pumpAndSettle();

              const chatRoute = ContentRoute(
                id: ChatPlugin.searchRouteId,
                title: 'Search',
                icon: DIcons.magnifyingGlass,
              );
              if (replace) {
                shell.replaceCurrentContent(chatRoute);
              } else {
                shell.pushContent(chatRoute);
              }
              await tester.pumpAndSettle();

              expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
              expect(shell.contentStack.map((route) => route.id), [
                ChatPlugin.searchRouteId,
              ]);
              expect(shell.canPopContent, isFalse);
              expect(shell.handleBack(canReturnToSidebar: false), isFalse);
              expect(shell.currentContent?.id, ChatPlugin.searchRouteId);

              await tester.tap(
                find.byKey(const ValueKey('sidebar-panel-switch-main')),
              );
              await tester.pumpAndSettle();

              expect(shell.currentContent, forumRoute);
              expect(shell.contentStack, [forumRoute]);
            },
          );
        }

        test(
          'direct entry switches between plugin owners via the Forum pane',
          () async {
            final plugins = PluginInstaller.install(
              const PluginManifest([
                _PanePolicyModule('alpha'),
                _PanePolicyModule('beta'),
              ]),
            );
            final shell = ShellController(
              instanceStore: FakeInstanceStore([
                instance('meta.discourse.org', title: 'Meta'),
              ]),
              api: FakeDiscourseApi(),
              authenticator: FakeAuthenticator(),
              drafts: FakeDraftStore(),
              forumTabs: FakeForumTabStore(),
              trackers: FakeSiteTracker.reset(),
              plugins: plugins,
            );
            addTearDown(() async {
              shell.dispose();
              await shell.pluginTeardown;
              await plugins.close();
            });
            await shell.load();

            const forum = SidebarDestination(
              id: 'forum-exact',
              label: 'Exact Forum route',
              icon: DIcons.layerGroup,
            );
            shell.selectDestination(forum);

            expect(shell.activatePluginPane(const PluginId('alpha')), isFalse);
            shell.pushContent(
              const ContentRoute(
                id: 'alpha-root',
                title: 'Alpha root',
                icon: DIcons.comments,
              ),
            );
            shell.pushContent(
              const ContentRoute(
                id: 'alpha-detail',
                title: 'Alpha detail',
                icon: DIcons.comments,
              ),
            );
            expect(shell.contentStack.map((route) => route.id), [
              'alpha-root',
              'alpha-detail',
            ]);

            expect(shell.activatePluginPane(const PluginId('beta')), isFalse);
            shell.pushContent(
              const ContentRoute(
                id: 'beta-root',
                title: 'Beta root',
                icon: DIcons.comments,
              ),
            );
            expect(shell.contentStack.map((route) => route.id), ['beta-root']);

            shell.deactivatePluginPane(const PluginId('alpha'));
            expect(shell.contentStack.map((route) => route.id), ['beta-root']);

            shell.deactivatePluginPane(const PluginId('beta'));
            expect(shell.contentStack.map((route) => route.id), [
              'forum-exact',
            ]);

            expect(shell.activatePluginPane(const PluginId('alpha')), isTrue);
            expect(shell.contentStack.map((route) => route.id), [
              'alpha-root',
              'alpha-detail',
            ]);
          },
        );

        testWidgets(
          'a restored plugin panel switches through another panel to Forum',
          (tester) async {
            final authenticator = FakeAuthenticator()..keys[site] = 'meta-key';
            await pumpShell(
              tester,
              desktop,
              instances: [
                instance(
                  'meta.discourse.org',
                  title: 'Meta',
                ).copyWith(user: me),
              ],
              api: FakeDiscourseApi(user: me),
              authenticator: authenticator,
              forumTabs: FakeForumTabStore([
                ForumWorkspace(
                  siteUrl: site,
                  accountIdentity: 'user:joffreyj',
                  tabs: [
                    ForumTab(
                      id: 'restored-alpha',
                      rootDestinationId: 'alpha-root',
                      contentStack: const [
                        ContentRoute(
                          id: 'alpha-root',
                          title: 'Alpha root',
                          icon: DIcons.comments,
                        ),
                      ],
                    ),
                  ],
                  activeTabId: 'restored-alpha',
                ),
              ]),
              pluginManifest: const PluginManifest([
                _PanePolicyModule('alpha'),
                _PanePolicyModule('beta'),
              ]),
            );
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );

            expect(shell.currentContent?.id, 'alpha-root');
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-main')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-beta')),
              findsOneWidget,
            );

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-beta')),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'beta-root');
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-main')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-alpha')),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-beta')),
              findsNothing,
            );

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-main')),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'latest');
          },
        );

        testWidgets(
          'forum push preserves both pane histories without a hybrid stack',
          (tester) async {
            await pumpChat(
              tester,
              public: [channel(9)],
              messages: {key(9): page(const [])},
              user: chatUser(
                separateSidebarMode: ChatSeparateSidebarMode.always,
              ),
              config: chatConfig(searchEnabled: true),
            );
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );
            shell.selectDestination(
              const SidebarDestination(
                id: 'forum-detail-a',
                label: 'Forum detail A',
                icon: DIcons.layerGroup,
              ),
            );
            await tester.pumpAndSettle();
            expect(shell.contentStack.map((route) => route.id), [
              'forum-detail-a',
            ]);

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            );
            await tester.pumpAndSettle();
            await tester.tap(sidebarDestination('Search'));
            await tester.pumpAndSettle();
            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);

            shell.pushContent(
              const ContentRoute(
                id: 'forum-detail-b',
                title: 'Forum detail B',
                icon: DIcons.comments,
              ),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'forum-detail-b');
            expect(shell.contentStack.map((route) => route.id), [
              'forum-detail-a',
              'forum-detail-b',
            ]);
            expect(
              shell.contentStack.any(
                (route) => ChatPlugin.ownsRouteId(route.id),
              ),
              isFalse,
            );

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            );
            await tester.pumpAndSettle();
            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(shell.contentStack.map((route) => route.id), [
              ChatPlugin.searchRouteId,
            ]);

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-main')),
            );
            await tester.pumpAndSettle();
            expect(shell.currentContent?.id, 'forum-detail-b');
            expect(shell.contentStack.map((route) => route.id), [
              'forum-detail-a',
              'forum-detail-b',
            ]);
          },
        );

        testWidgets(
          'adopts a restored separated Chat route before forum navigation',
          (tester) async {
            final forumTabs = FakeForumTabStore([
              ForumWorkspace(
                siteUrl: site,
                accountIdentity: 'user:joffreyj',
                tabs: [
                  ForumTab(
                    id: 'restored-chat',
                    rootDestinationId: ChatPlugin.searchRouteId,
                    contentStack: const [
                      ContentRoute(
                        id: ChatPlugin.searchRouteId,
                        title: 'Search',
                        icon: DIcons.magnifyingGlass,
                      ),
                    ],
                  ),
                ],
                activeTabId: 'restored-chat',
              ),
            ]);
            await pumpChat(
              tester,
              public: [channel(9)],
              user: chatUser(
                separateSidebarMode: ChatSeparateSidebarMode.always,
              ),
              config: chatConfig(searchEnabled: true),
              forumTabs: forumTabs,
            );
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );

            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(sidebarDestination('Topics'), findsNothing);

            shell.pushContent(
              const ContentRoute(
                id: 'forum-restored-target',
                title: 'Restored forum target',
                icon: DIcons.comments,
              ),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'forum-restored-target');
            expect(shell.contentStack.map((route) => route.id), [
              'latest',
              'forum-restored-target',
            ]);
            expect(
              shell.contentStack.any(
                (route) => ChatPlugin.ownsRouteId(route.id),
              ),
              isFalse,
            );

            await tester.tap(
              find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            );
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(shell.contentStack.map((route) => route.id), [
              ChatPlugin.searchRouteId,
            ]);
          },
        );
      });

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

      testWidgets('tabs from global search to its sort control', (
        tester,
      ) async {
        await pumpChat(tester, config: chatConfig(searchEnabled: true));

        await tester.tap(sidebarDestination('Search'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-search-field')));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(
          _primaryFocusIsWithin(find.byKey(const ValueKey('chat-search-sort'))),
          isTrue,
        );
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

        await tester.tap(
          find.byKey(const ValueKey('chat-channel-search-field')),
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _primaryFocusIsWithin(find.widgetWithText(DButton, 'Done')),
          isTrue,
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

      testWidgets('tabs through the browse channel filters in order', (
        tester,
      ) async {
        await pumpChat(tester);

        await tester.tap(sidebarDestination('Browse channels'));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-browse-filter')));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(
          _primaryFocusIsWithin(
            find.byKey(const ValueKey('chat-browse-status')),
          ),
          isTrue,
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _primaryFocusIsWithin(
            find.byKey(const ValueKey('chat-browse-joined')),
          ),
          isTrue,
        );
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
          // The compact desktop sidebar leaves one pixel around each side of a
          // round avatar inside its 20-pixel prefix slot.
          final size = tester.getSize(avatar);
          expect(size, const Size.square(18));
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
        expect(tester.getSize(ring), const Size.square(18));

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
      testWidgets(
        'shows a direct-message status after the channel star and its text on hover',
        (tester) async {
          await pumpChat(
            tester,
            direct: [
              dm(
                12,
                users: const [
                  ChatUser(
                    id: 2,
                    username: 'hawk',
                    avatarUrl: '$site/user_avatar/h/90.png',
                    status: UserStatus(
                      description: 'Working today',
                      emoji: 'computer',
                    ),
                  ),
                ],
              ),
            ],
            messages: {key(12): page(const [])},
            mediaClient: MockClient(
              (_) async => http.Response.bytes(emojiPng, 200),
            ),
          );
          await tester.tap(sidebarDestination('hawk'));
          await tester.pumpAndSettle();

          final titleAction = find.byKey(
            const ValueKey('content-header-title-action'),
          );
          final title = find.descendant(
            of: titleAction,
            matching: find.text('hawk'),
          );
          final status = find.descendant(
            of: titleAction,
            matching: find.byKey(const ValueKey('chat-channel-header-status')),
          );
          final star = find.descendant(
            of: titleAction,
            matching: find.byKey(const ValueKey('chat-channel-star-button')),
          );
          final emoji = find.descendant(
            of: status,
            matching: find.byType(SiteEmojiImage),
          );

          expect(star, findsOneWidget);
          expect(status, findsOneWidget);
          expect(emoji, findsOneWidget);
          expect(
            tester.getRect(star).left - tester.getRect(title).right,
            closeTo(0, 0.01),
          );
          expect(
            tester.getRect(emoji).left,
            greaterThan(tester.getRect(star).right),
          );
          expect(
            find.descendant(
              of: titleAction,
              matching: find.text('Working today'),
            ),
            findsNothing,
          );

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(tester.getCenter(emoji));
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pumpAndSettle();

          expect(find.text('Working today'), findsOneWidget);
        },
      );

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

bool _primaryFocusIsWithin(Finder finder) {
  final focusedContext = FocusManager.instance.primaryFocus?.context;
  if (focusedContext == null) return false;
  final targets = finder.evaluate().toSet();
  if (targets.contains(focusedContext)) return true;
  var matches = false;
  focusedContext.visitAncestorElements((ancestor) {
    if (!targets.contains(ancestor)) return true;
    matches = true;
    return false;
  });
  return matches;
}

final class _PanePolicyModule implements PluginModule {
  const _PanePolicyModule(this.id);

  final String id;

  @override
  PluginDescriptor get descriptor => PluginDescriptor(id: PluginId(id));

  @override
  void register(PluginRegistrar registrar) {
    registrar.addCapability(_PanePanel(id));
    registrar.addSession(
      (_, _) => PluginSessionContribution(
        lifecycle: _PanePolicyLifecycle(),
        capabilities: [_PanePolicy(id)],
      ),
    );
  }
}

final class _PanePanel implements SitePlugin, SidebarPanelPlugin {
  const _PanePanel(this.id);

  final String id;

  @override
  String get name => id;

  @override
  SidebarPanelContribution sidebarPanel(BuildContext context) {
    final shell = ShellScope.read(context);
    final owner = PluginId(id);
    return SidebarPanelContribution(
      label: id,
      icon: DIcons.comments,
      active: shell.currentContent?.id.startsWith('$id-') == true,
      separateWhenActive: true,
      includeSectionsWhenInactive: false,
      showSwitch: true,
      onOpen: () {
        shell.activatePluginPane(owner);
        shell.pushContent(
          ContentRoute(
            id: '$id-root',
            title: '$id root',
            icon: DIcons.comments,
          ),
        );
      },
      onClose: () => shell.deactivatePluginPane(owner),
    );
  }
}

final class _PanePolicy implements PluginPaneRoutePolicy {
  const _PanePolicy(this.id);

  final String id;

  @override
  PluginId get pluginPaneOwner => PluginId(id);

  @override
  bool ownsPluginPaneRoute(String routeId) => routeId.startsWith('$id-');

  @override
  bool separatesPluginPane(String routeId) => ownsPluginPaneRoute(routeId);
}

final class _PanePolicyLifecycle extends PluginSessionLifecycle {}
