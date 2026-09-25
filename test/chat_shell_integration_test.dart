import 'dart:async';
import 'dart:ui' show ImageByteFormat, PointerDeviceKind;

import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/src/data/discourse_api.dart';
import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification_totals.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/models/site_config.dart';
import 'package:discourse_native/src/models/site_emoji.dart';
import 'package:discourse_native/src/models/user_status.dart';
import 'package:discourse_native/src/plugin_api/plugin_data.dart';
import 'package:discourse_native/src/plugin_api/plugin_runtime.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/shell_extensions.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart'
    show SidebarPanelContribution, SidebarPanelPlugin, SitePlugin;
import 'package:discourse_native/src/plugins/chat/chat_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel_view.dart';
import 'package:discourse_native/src/plugins/chat/chat_composer.dart';
import 'package:discourse_native/src/plugins/chat/chat_global_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_header_button.dart';
import 'package:discourse_native/src/plugins/chat/chat_inbox.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_message_tile.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_reactors.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_uploads.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_avatar.dart';
import 'package:discourse_native/src/shell/avatar_image.dart';
import 'package:discourse_native/src/shell/emoji.dart';
import 'package:discourse_native/src/shell/emoji_picker.dart';
import 'package:discourse_native/src/shell/forum_search.dart';
import 'package:discourse_native/src/shell/forum_tabs_bar.dart';
import 'package:discourse_native/src/shell/global_search_models.dart';
import 'package:discourse_native/src/shell/instance_rail.dart';
import 'package:discourse_native/src/shell/instance_sidebar.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/reaction_presentation.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/shell/site_emoji_image.dart';
import 'package:discourse_native/src/shell/title_bar.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
      int? lastMessageId,
      DateTime? lastMessageAt,
      String? lastMessagePreview,
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
      lastMessageId: lastMessageId,
      lastMessageAt: lastMessageAt,
      lastMessagePreview: lastMessagePreview,
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
      String? lastMessagePreview,
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
      lastMessagePreview: lastMessagePreview,
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

    var startOnChatSidebar = false;
    setUp(() => startOnChatSidebar = false);

    Future<void> selectChatSidebar(WidgetTester tester) async {
      final mobileTab = find.byKey(const ValueKey('mobile-mode-panel/chat'));
      final tab = mobileTab.evaluate().isNotEmpty
          ? mobileTab
          : find.byKey(const ValueKey('sidebar-panel-switch-chat'));
      if (tab.evaluate().isNotEmpty) {
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await tester.pumpAndSettle();
      }
    }

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
    }) async {
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
      if (startOnChatSidebar) await selectChatSidebar(tester);
    }

    /// `pumpAndSettle` does not advance an unscheduled dwell timer.
    Future<void> pumpUntilRead(WidgetTester tester) async {
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 600));
    }

    for (final brightness in Brightness.values) {
      testWidgets(
        'desktop channel corners reveal the ${brightness.name} workspace',
        (tester) async {
          tester.platformDispatcher.platformBrightnessTestValue = brightness;
          addTearDown(
            tester.platformDispatcher.clearPlatformBrightnessTestValue,
          );
          const notifications = MethodChannel(
            'org.discourse.native/notification_opens',
          );
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(notifications, (_) async => null);
          addTearDown(
            () => messenger.setMockMethodCallHandler(notifications, null),
          );
          await pumpChat(
            tester,
            api: FakeDiscourseApi(
              feeds: const {'/latest.json': []},
              totals: withChat,
              user: me,
              chatChannelsBySite: {
                site: ChatChannels(public: [channel(9)]),
              },
              chatMessagesByKey: {key(9): page(const [])},
            ),
          );
          ShellScope.read(
            tester.element(find.byType(InstanceSidebar)),
          ).openChatChannel(9);
          await tester.pumpAndSettle();

          final content = find.byKey(const ValueKey('desktop-panel-main'));
          final theme = Theme.of(tester.element(content));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find
                .ancestor(of: content, matching: find.byType(RepaintBoundary))
                .last,
          );
          final bounds = tester
              .getRect(content)
              .shift(-boundary.localToGlobal(Offset.zero));
          await tester.runAsync(() async {
            final image = await boundary.toImage();
            try {
              final pixels = (await image.toByteData(
                format: ImageByteFormat.rawRgba,
              ))!;
              for (final point in [
                bounds.topLeft,
                bounds.bottomLeft - const Offset(0, 1),
                bounds.topRight - const Offset(1, 0),
                bounds.bottomRight - const Offset(1, 1),
              ]) {
                final offset =
                    (point.dy.round() * image.width + point.dx.round()) * 4;
                final expected = theme.scaffoldBackgroundColor.toARGB32();
                for (var channel = 0; channel < 3; channel++) {
                  expect(
                    pixels.getUint8(offset + channel),
                    (expected >> (16 - channel * 8)) & 255,
                    reason: 'Workspace background at $point',
                  );
                }
              }
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      );
    }

    group('contextual global search', () {
      for (final keyboard in [false, true]) {
        for (final direct in [false, true]) {
          testWidgets(
            '${keyboard ? 'contextual shortcut' : 'global click'} searches from ${direct ? 'DM' : 'channel'} and opens its result',
            (tester) async {
              final target = direct ? dm(12) : channel(9);
              final config = chatConfig(searchEnabled: true);
              final requestPath = Uri(
                path: '/chat/api/search.json',
                queryParameters: {
                  'query': 'needle',
                  'sort': 'relevance',
                  'offset': '0',
                  'limit': '20',
                  if (keyboard) 'channel_id': '${target.id}',
                },
              ).toString();
              final api = FakeDiscourseApi(
                feeds: const {'/latest.json': []},
                totals: withChat,
                user: me,
                siteConfigs: {site: config},
                chatChannelsBySite: {
                  site: ChatChannels(
                    public: direct ? const [] : [target],
                    direct: direct ? [target] : const [],
                  ),
                },
                chatMessagesByKey: {
                  key(target.id): page(const []),
                  FakeDiscourseApi.chatMessagesKey(
                    target.id,
                    targetMessageId: 40,
                  ): page([
                    ChatMessage(
                      id: 40,
                      channelId: target.id,
                      cooked: '<p>Target channel message</p>',
                      author: const ChatMessageAuthor(id: 2, username: 'sam'),
                      createdAt: DateTime.utc(2026, 9, 13),
                    ),
                  ]),
                },
                pluginResponses: {
                  'GET /site/settings.json': {
                    'chat_enabled': true,
                    'chat_search_enabled': true,
                  },
                  'GET /session/current.json': {
                    'current_user': {
                      'has_chat_enabled': true,
                      'can_chat': true,
                    },
                  },
                  'GET $requestPath': {
                    'messages': [
                      {
                        'id': 40,
                        'chat_channel_id': target.id,
                        'channel': {'id': target.id, 'title': target.title},
                        'user': {'username': 'sam'},
                        'excerpt': '<p>Needle from global search</p>',
                      },
                    ],
                  },
                },
              );
              await pumpChat(tester, api: api, config: config);
              final shell = ShellScope.read(
                tester.element(find.byType(MainContent)),
              );
              final chatShell = shell.pluginSession.require(chatShellService);

              final underlying = shell.currentContent;
              shell.openChatChannel(target.id);
              await tester.pumpAndSettle();
              await tester.pump();
              expect(
                find.byKey(const ValueKey('chat-channel-search-button')),
                findsNothing,
              );

              Future<void> open() async {
                if (keyboard) {
                  await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
                  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
                  await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
                  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
                  await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
                } else {
                  await tester.tap(find.byKey(ForumSearch.inputKey));
                }
                await tester.pumpAndSettle();
              }

              await open();
              expect(
                shell.globalSearch.scope,
                keyboard ? chatSearchScope : GlobalSearchScope.all,
              );
              expect(
                shell.globalSearch.conditions.map(
                  (condition) => condition.filterId,
                ),
                keyboard ? ['chatChannel'] : <String>[],
              );
              expect(
                shell.globalSearch.conditions.map(
                  (condition) => condition.text,
                ),
                keyboard ? ['${target.id}'] : <String>[],
              );
              if (keyboard) {
                expect(
                  shell.globalSearch.choiceLabel('chatChannel', '${target.id}'),
                  target.title,
                );
                await tester.tap(find.byTooltip('Remove Channel condition'));
                await tester.pumpAndSettle();
              }
              await open();
              expect(
                shell.globalSearch.conditions.map(
                  (condition) => condition.text,
                ),
                keyboard ? ['${target.id}'] : <String>[],
              );
              await tester.tap(
                find.byKey(const ValueKey('global-search-scope-users')),
              );
              await tester.pumpAndSettle();
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
              await tester.pumpAndSettle();
              expect(chatShell.fullPageChatActive, isTrue);
              await open();
              expect(
                shell.globalSearch.conditions.map(
                  (condition) => condition.text,
                ),
                keyboard ? ['${target.id}'] : <String>[],
              );
              await tester.enterText(
                find.byKey(ForumSearch.inputKey),
                'needle',
              );
              await tester.pump(const Duration(milliseconds: 400));
              await tester.pumpAndSettle();
              expect(api.pluginReadPaths, contains(requestPath));
              await tester.tap(find.text('Needle from global search'));
              await tester.pumpAndSettle();
              expect(find.byKey(ForumSearch.panelKey), findsNothing);
              expect(chatShell.fullPageChatActive, isTrue);
              expect(
                chatShell.currentContent?.id,
                ChatRoute.channel(target.id).routeId,
              );
              expect(renderedText('Target channel message'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('chat-channel-search-bar')),
                findsNothing,
              );
              shell.selectDestination(
                SidebarDestination(
                  id: underlying!.id,
                  label: underlying.title,
                  icon: underlying.icon,
                ),
              );
              await tester.pumpAndSettle();
              await open();
              expect(
                shell.globalSearch.scope,
                keyboard ? GlobalSearchScope.forum : GlobalSearchScope.all,
              );
              expect(
                shell.globalSearch.conditionsFor(chatSearchScope),
                isEmpty,
              );
              expect(tester.takeException(), isNull);
            },
            variant: TargetPlatformVariant.only(TargetPlatform.macOS),
          );
        }
      }
    });

    group('in the header', () {
      final shortcut = find.byKey(ChatHeaderButton.buttonKey);
      final dot = find.byKey(ChatHeaderButton.unreadDotKey);
      final urgent = find.byKey(ChatHeaderButton.urgentBadgeKey);

      testWidgets('opens full-page Chat despite a legacy drawer preference', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({
          'discourse_chat_preferred_mode': 'DRAWER_CHAT',
          'discourse_chat_drawer_size_width': 480.0,
          'discourse_chat_drawer_size_height': 600.0,
        });
        await pumpChat(
          tester,
          public: [channel(9)],
          messages: {key(9): page(const [])},
        );
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        await shell.pluginSession.require(chatShellService).openShortcut();
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, ChatRoute.channel(9).routeId);
        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-drawer')), findsNothing);
        expect(
          find.byKey(const ValueKey('chat-close-full-page')),
          findsNothing,
        );

        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.minus);
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, ChatRoute.channel(9).routeId);
        expect(find.byKey(const ValueKey('chat-drawer')), findsNothing);

        tester.view.physicalSize = phone;
        await tester.pumpAndSettle();
        tester.view.physicalSize = desktop;
        await tester.pumpAndSettle();
        expect(shell.currentContent?.id, ChatRoute.channel(9).routeId);
        expect(find.byType(ChatChannelView), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-drawer')), findsNothing);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('is shown only for an account allowed to chat', (
        tester,
      ) async {
        await pumpChat(tester);
        expect(shortcut, findsOneWidget);

        await pumpChat(tester, totals: withoutChat);
        expect(shortcut, findsNothing);

        await pumpChat(tester, user: chatUser(hasChatEnabled: false));
        expect(shortcut, findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

      testWidgets('draws a quiet dot for ordinary public activity', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9, unread: 42)]);

        expect(dot, findsOneWidget);
        expect(urgent, findsNothing);
        expect(
          find.descendant(of: shortcut, matching: find.text('42')),
          findsNothing,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
        expect(tester.widget<Text>(urgent).data, '3');
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.fuchsia));

      testWidgets(
        'shows the mobile Chat mode only while its sidebar is visible',
        (tester) async {
          await pumpChat(
            tester,
            size: phone,
            public: [channel(9)],
            messages: {key(9): page(const [])},
          );
          expect(
            find.byKey(const ValueKey('mobile-mode-panel/chat')),
            findsOneWidget,
          );

          await selectChatSidebar(tester);
          await tester.tap(sidebarDestination('Bugs'));
          await tester.pumpAndSettle();

          expect(find.byType(ChatChannelView), findsOneWidget);
          expect(shortcut, findsNothing);
          expect(
            find.byKey(const ValueKey('mobile-mode-panel/chat')),
            findsNothing,
          );
        },
      );
    });

    group('in the sidebar', () {
      setUp(() => startOnChatSidebar = true);
      group('separate sidebar modes', () {
        setUp(() => startOnChatSidebar = false);

        // Legacy pane handoffs remain supported by the navigation service;
        // sidebar tabs themselves now only choose which destinations to show.
        Future<void> switchPane(WidgetTester tester, String owner) async {
          final context = tester.element(find.byType(InstanceSidebar));
          final shell = ShellScope.read(context);
          final panels = PluginScope.of(
            context,
          ).registry.sidebarPanels(context);
          final panel = owner == 'main'
              ? panels.firstWhere((panel) => panel.panel.active).panel
              : panels.firstWhere((panel) => panel.owner.value == owner).panel;
          shell.switchSidebarPanel(
            owner == 'main' ? panel.onClose : panel.onOpen,
          );
          await tester.pumpAndSettle();
        }

        testWidgets('keeps both panel tabs above the sidebar destinations', (
          tester,
        ) async {
          await pumpChat(tester, public: [channel(9)]);
          final tabs = find.byKey(const ValueKey('sidebar-panel-tabs'));
          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-main')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('sidebar-panel-switch-chat')),
            findsOneWidget,
          );
          expect(
            tester.getRect(tabs).bottom,
            lessThanOrEqualTo(tester.getRect(sidebarDestination('Topics')).top),
          );
          expect(
            find.descendant(
              of: find.byType(InstanceSidebar),
              matching: find.byType(DSidebarFooter),
            ),
            findsNothing,
          );
        }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

        for (final scenario in [
          (
            name: 'tabs replace an explicit never preference',
            userMode: ChatSeparateSidebarMode.never,
            siteMode: ChatSeparateSidebarMode.always,
            effectiveMode: ChatSeparateSidebarMode.never,
          ),
          (
            name: 'tabs retain explicit always separation',
            userMode: ChatSeparateSidebarMode.always,
            siteMode: ChatSeparateSidebarMode.never,
            effectiveMode: ChatSeparateSidebarMode.always,
          ),
          (
            name: 'tabs separate fullscreen Chat before entry',
            userMode: ChatSeparateSidebarMode.fullscreen,
            siteMode: ChatSeparateSidebarMode.never,
            effectiveMode: ChatSeparateSidebarMode.fullscreen,
          ),
          (
            name: 'tabs separate Chat with the default preference',
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

            expect(sidebarDestination('Topics'), findsOneWidget);
            expect(sidebarDestination('Bugs'), findsNothing);
            expect(find.byKey(chatSwitch), findsOneWidget);
            expect(find.byKey(forumSwitch), findsOneWidget);

            await tester.tap(find.byKey(chatSwitch));
            await tester.pumpAndSettle();

            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );
            expect(shell.currentContent?.id, 'latest');
            expect(sidebarDestination('Topics'), findsNothing);
            expect(sidebarDestination('Bugs'), findsOneWidget);
            expect(find.byKey(forumSwitch), findsOneWidget);
            expect(find.byKey(chatSwitch), findsOneWidget);
          }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
        }

        testWidgets('appears when Chat totals arrive after the sidebar', (
          tester,
        ) async {
          final semantics = tester.ensureSemantics();
          try {
            await pumpChat(
              tester,
              totals: withoutChat,
              public: [channel(9)],
              messages: {key(9): page(const [])},
              user: chatUser(
                separateSidebarMode: ChatSeparateSidebarMode.always,
              ),
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

            expect(find.bySemanticsLabel('Chat navigation'), findsOneWidget);
            expect(find.bySemanticsLabel('Forum navigation'), findsNothing);
            expect(shell.currentContent?.id, 'latest');
            expect(
              find.byKey(const ValueKey('sidebar-panel-switch-main')),
              findsOneWidget,
            );
          } finally {
            semantics.dispose();
          }
        }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

        for (final scenario in [
          (mode: ChatSeparateSidebarMode.never, separates: false),
          (mode: ChatSeparateSidebarMode.always, separates: true),
          (mode: ChatSeparateSidebarMode.fullscreen, separates: true),
        ]) {
          testWidgets(
            'anonymous public Chat has tabs with site mode ${scenario.mode.wireName}',
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
              expect(sidebarDestination('Bugs'), findsNothing);
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-chat')),
                findsOneWidget,
              );
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-main')),
                findsOneWidget,
              );
              expect(find.byKey(ChatHeaderButton.buttonKey), findsNothing);

              await tester.tap(
                find.byKey(const ValueKey('sidebar-panel-switch-chat')),
              );
              await tester.pumpAndSettle();
              await tester.tap(sidebarDestination('Bugs'));
              await tester.pumpAndSettle();

              expect(shell.currentContent?.id, 'chat-c-9');
              expect(sidebarDestination('Topics'), findsNothing);
              expect(sidebarDestination('Bugs'), findsOneWidget);
              expect(
                find.byKey(const ValueKey('sidebar-panel-switch-main')),
                findsOneWidget,
              );
              expect(find.byKey(ChatHeaderButton.buttonKey), findsNothing);
            },
            variant: TargetPlatformVariant.only(TargetPlatform.linux),
          );
        }

        for (final mode in [
          ChatSeparateSidebarMode.always,
          ChatSeparateSidebarMode.fullscreen,
        ]) {
          testWidgets(
            'switches between forum and Chat in new tabs with $mode',
            (tester) async {
              await pumpChat(
                tester,
                public: [channel(9)],
                forumTabs: FakeForumTabStore(),
                messages: {key(9): page(const [])},
                user: chatUser(separateSidebarMode: mode),
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

              final forumTab = shell.activeTab!;
              final initialTabCount = shell.tabsForCurrentForum.length;
              expect(shell.currentContent?.id, 'forum-detail');
              expect(sidebarDestination('Topics'), findsOneWidget);
              expect(sidebarDestination('Bugs'), findsNothing);

              await switchPane(tester, 'chat');
              await tester.pumpAndSettle();
              expect(shell.tabsForCurrentForum, hasLength(initialTabCount + 1));
              expect(shell.activeTabId, isNot(forumTab.id));
              expect(
                shell.currentWorkspace!.tabById(forumTab.id),
                same(forumTab),
              );
              expect(shell.currentContent?.id, 'chat-c-9');
              expect(sidebarDestination('Topics'), findsNothing);
              expect(sidebarDestination('Search'), findsNothing);

              ShellScope.read(
                tester.element(find.byType(MainContent)),
              ).pluginSession.require(chatShellService).openSearch();
              await tester.pumpAndSettle();
              expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
              expect(sidebarDestination('Topics'), findsNothing);
              expect(find.byTooltip('Exit chat'), findsNothing);

              final chatTab = shell.activeTab!;
              await switchPane(tester, 'main');
              await tester.pumpAndSettle();
              expect(shell.tabsForCurrentForum, hasLength(initialTabCount + 3));
              expect(shell.activeTabId, isNot(chatTab.id));
              expect(
                shell.currentWorkspace!.tabById(chatTab.id),
                same(chatTab),
              );
              expect(shell.currentContent, forumTab.currentContent);
              expect(shell.currentContent?.id, 'forum-detail');
              expect(sidebarDestination('Topics'), findsOneWidget);
              expect(sidebarDestination('Bugs'), findsNothing);

              await switchPane(tester, 'chat');
              await tester.pumpAndSettle();
              expect(shell.currentContent?.id, 'chat-c-9');
              expect(sidebarDestination('Topics'), findsNothing);
              expect(sidebarDestination('Search'), findsNothing);
              expect(find.byTooltip('Exit chat'), findsNothing);
              expect(shell.tabsForCurrentForum, hasLength(initialTabCount + 4));

              shell.selectTab(forumTab.id);
              await tester.pumpAndSettle();
              expect(shell.contentStack, forumTab.contentStack);
              shell.selectTab(chatTab.id);
              await tester.pumpAndSettle();
              expect(shell.contentStack, chatTab.contentStack);
            },
            variant: TargetPlatformVariant.only(TargetPlatform.macOS),
          );
        }

        testWidgets(
          'forum and Chat navigation preserve their original document tabs',
          (tester) async {
            await pumpChat(
              tester,
              public: [channel(9)],
              messages: {key(9): page(const [])},
              config: chatConfig(searchEnabled: true),
            );
            final shell = ShellScope.read(
              tester.element(find.byType(MainContent)),
            );
            final forum = shell.activeTab!;
            shell.pluginSession.require(chatShellService).openSearch();
            await tester.pumpAndSettle();
            final search = shell.activeTab!;
            expect(search.panel, forum.panel);
            expect(search.id, isNot(forum.id));
            shell.selectDestination(
              const SidebarDestination(
                id: 'latest',
                label: 'Topics',
                icon: DIcons.layerGroup,
              ),
            );
            await tester.pumpAndSettle();
            expect(shell.currentWorkspace!.tabById(search.id), search);
            expect(shell.currentWorkspace!.tabById(forum.id), forum);
            expect(shell.activeTabId, isNot(search.id));
            shell.selectTab(search.id);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('chat-search-field')),
              findsOneWidget,
            );
          },
          variant: TargetPlatformVariant.only(TargetPlatform.linux),
        );

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
            await switchPane(tester, 'beta');
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
              findsOneWidget,
            );
            await switchPane(tester, 'main');
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, 'latest');
          },
          variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
              ChatPlugin.searchRouteId,
              'forum-restored-target',
            ]);
            expect(
              shell.contentStack.any(
                (route) => ChatPlugin.ownsRouteId(route.id),
              ),
              isTrue,
            );

            shell.selectTab('restored-chat');
            await tester.pumpAndSettle();

            expect(shell.currentContent?.id, ChatPlugin.searchRouteId);
            expect(shell.contentStack.map((route) => route.id), [
              ChatPlugin.searchRouteId,
            ]);
          },
          variant: TargetPlatformVariant.only(TargetPlatform.linux),
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

        expect(find.widgetWithText(DSidebarMenuButton, 'Chat'), findsNothing);
        expect(api.chatChannelsRequested, isEmpty);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('shows skeletons while the channel list is on its way', (
        tester,
      ) async {
        startOnChatSidebar = false;
        final gate = Completer<void>();
        await pumpChat(tester, public: [channel(9)], channelGate: gate);
        await tester.tap(
          find.byKey(const ValueKey('sidebar-panel-switch-chat')),
        );
        await tester.pump();

        final placeholder = find.byKey(
          const ValueKey('chat-inbox-loading-skeleton'),
        );
        expect(placeholder, findsOneWidget);
        // The filters are already final; only the rows are placeholders.
        expect(
          find.byKey(const ValueKey('chat-inbox-activity-filter')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-inbox-kind-filter')),
          findsOneWidget,
        );

        final shell = ShellScope.read(
          tester.element(find.byType(InstanceSidebar)),
        );
        var shellNotifications = 0;
        void countShellNotification() => shellNotifications += 1;
        shell.addListener(countShellNotification);
        addTearDown(() => shell.removeListener(countShellNotification));

        gate.complete();
        await tester.pumpAndSettle();

        expect(placeholder, findsNothing);
        expect(sidebarDestination('Bugs'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sidebar-panel-switch-chat')),
          findsOneWidget,
        );
        expect(shellNotifications, 0);
      }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

      testWidgets('draws nothing for an account that follows no channels', (
        tester,
      ) async {
        await pumpChat(tester);

        expect(find.widgetWithText(DSidebarMenuButton, 'Chat'), findsNothing);
        expect(
          find.widgetWithText(DSidebarMenuButton, 'Direct messages'),
          findsNothing,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets(
        'omits sidebar search even when the site enables chat search',
        (tester) async {
          await pumpChat(tester);
          expect(sidebarDestination('Search'), findsNothing);

          await pumpChat(tester, config: chatConfig(searchEnabled: true));
          expect(sidebarDestination('Search'), findsNothing);

          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).pluginSession.require(chatShellService).openSearch();
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('chat-search-field')),
            findsOneWidget,
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );

      testWidgets('keeps the improved search sort menu inside the viewport', (
        tester,
      ) async {
        final previous = debugDefaultTargetPlatformOverride;
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await pumpChat(tester, config: chatConfig(searchEnabled: true));

          ShellScope.read(
            tester.element(find.byType(MainContent)),
          ).pluginSession.require(chatShellService).openSearch();
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

        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).pluginSession.require(chatShellService).openSearch();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('chat-search-field')));
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();

        expect(
          _primaryFocusIsWithin(find.byKey(const ValueKey('chat-search-sort'))),
          isTrue,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('Command F opens and refocuses global search from Chat', (
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
                  of: find.byKey(ForumSearch.inputKey),
                  matching: find.byType(EditableText),
                ),
              )
              .focusNode;
          expect(shell.currentContent?.id, ChatRoute.channel(9).routeId);
          expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
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

      testWidgets(
        'Command F still opens global search when Chat search is unavailable',
        (tester) async {
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
            expect(await tester.sendKeyEvent(LogicalKeyboardKey.keyF), isTrue);
            await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
            await tester.pump();

            expect(
              find.byKey(const ValueKey('chat-search-field')),
              findsNothing,
            );
            expect(find.byKey(ForumSearch.panelKey), findsOneWidget);
          } finally {
            debugDefaultTargetPlatformOverride = previous;
          }
        },
      );

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

        ShellScope.read(
          tester.element(find.byType(MainContent)),
        ).pluginSession.require(chatShellService).openSearch();
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('mixes channels and direct messages by recent activity', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [
            channel(
              9,
              title: 'Bugs',
              starred: true,
              lastMessageId: 50,
              lastMessageAt: DateTime.utc(2026, 8, 8, 10),
            ),
            channel(
              10,
              title: 'Design',
              lastMessageId: 51,
              lastMessageAt: DateTime.utc(2026, 8, 8, 12),
            ),
          ],
          direct: [
            dm(
              12,
              title: 'hawk',
              lastMessageId: 52,
              lastMessageAt: DateTime.utc(2026, 8, 8, 11),
            ),
          ],
        );

        for (final title in ['Starred channels', 'Chat', 'Direct messages']) {
          expect(find.widgetWithText(DSidebarMenuButton, title), findsNothing);
        }
        final rows = [
          'Design',
          'hawk',
          'Bugs',
        ].map((title) => tester.getTopLeft(sidebarDestination(title)).dy);
        expect(rows, orderedEquals([...rows]..sort()));
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('keeps the inbox filters while switching sidebar panels', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [channel(9, title: 'Bugs', unread: 2)],
          direct: [dm(12, title: 'hawk')],
        );

        await tester.tap(
          find.byKey(const ValueKey('chat-inbox-activity-filter')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Unread').last);
        await tester.pumpAndSettle();
        expect(sidebarDestination('Bugs'), findsOneWidget);
        expect(sidebarDestination('hawk'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('sidebar-panel-switch-main')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('sidebar-panel-switch-chat')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Unread'), findsOneWidget);
        expect(sidebarDestination('Bugs'), findsOneWidget);
        expect(sidebarDestination('hawk'), findsNothing);

        await tester.tap(find.byKey(const ValueKey('chat-inbox-kind-filter')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Direct messages').last);
        await tester.pumpAndSettle();
        expect(sidebarDestination('Bugs'), findsNothing);
        expect(find.text('No unread conversations.'), findsOneWidget);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('marks the open conversation in the inbox', (tester) async {
        await pumpChat(
          tester,
          public: [channel(9, title: 'Bugs')],
          direct: [dm(12, title: 'hawk')],
          messages: {
            key(9): page([msg(1)]),
          },
        );
        DItem row(int id) => tester.widget<DItem>(
          find.byKey(ValueKey('chat-inbox-channel-$id')),
        );
        expect(row(9).selected, isFalse);

        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();

        expect(row(9).selected, isTrue);
        expect(row(12).selected, isFalse);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      for (final directMessage in [false, true]) {
        testWidgets(
          'opens ${directMessage ? 'DM' : 'channel'} menu on right click without hover dots',
          (tester) async {
            final previous = debugDefaultTargetPlatformOverride;
            debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            try {
              final title = directMessage ? 'hawk' : 'Bugs';
              await pumpChat(
                tester,
                public: directMessage ? [] : [channel(9)],
                direct: directMessage ? [dm(9)] : [],
              );

              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: Offset.zero);
              addTearDown(mouse.removePointer);
              await mouse.moveTo(tester.getCenter(sidebarDestination(title)));
              await tester.pumpAndSettle();

              expect(
                find.byKey(const ValueKey('chat-channel-menu-button-9')),
                findsNothing,
              );
              expect(find.byType(DContextMenuContent), findsNothing);
              final shell = ShellScope.read(
                tester.element(find.byType(InstanceSidebar)),
              );
              final currentContent = shell.currentContent?.id;

              await tester.tap(
                sidebarDestination(title),
                buttons: kSecondaryMouseButton,
              );
              await tester.pumpAndSettle();

              expect(shell.currentContent?.id, currentContent);
              expect(
                find.widgetWithText(DDropdownMenuSub, 'Notifications'),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(DDropdownMenuItem, 'Channel settings'),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(
                  DDropdownMenuItem,
                  'Add to starred channels',
                ),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(
                  DDropdownMenuItem,
                  directMessage ? 'Close channel' : 'Leave channel',
                ),
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
          },
        );
      }

      testWidgets('opens channel actions from the row keyboard focus', (
        tester,
      ) async {
        await pumpChat(tester, public: [channel(9)]);
        final shell = ShellScope.read(
          tester.element(find.byType(InstanceSidebar)),
        );
        final currentContent = shell.currentContent?.id;
        final focus = Focus.of(tester.element(sidebarDestination('Bugs')));
        focus.requestFocus();
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.f10);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pumpAndSettle();
        expect(find.text('Channel settings'), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Channel settings'), findsNothing);
        expect(shell.currentContent?.id, currentContent);
        expect(focus.hasFocus, isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        await tester.pumpAndSettle();
        expect(find.text('Channel settings'), findsOneWidget);
      }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

      testWidgets('keeps channel notifications open during diagonal movement', (
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
            sidebarDestination('Bugs'),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();

          final trigger = tester.getRect(
            find.byKey(const ValueKey('chat-channel-notifications-9')),
          );
          await mouse.moveTo(trigger.center);
          await tester.pumpAndSettle();
          final popup = tester.getRect(find.byType(DDropdownMenuContent).last);
          final opensRight = popup.center.dx > trigger.center.dx;
          final origin = Offset(
            opensRight ? trigger.left + 24 : trigger.right - 24,
            trigger.center.dy,
          );
          final edge = opensRight ? popup.left : popup.right;
          await mouse.moveTo(origin);
          await tester.pump();
          final settings = tester.getCenter(
            find.byKey(const ValueKey('chat-channel-menu-settings-9')),
          );
          await mouse.moveTo(
            Offset(origin.dx + (edge - origin.dx) * .7, settings.dy),
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.text('Mute channel'), findsOneWidget);

          final mute = tester.getCenter(
            find.byKey(const ValueKey('chat-channel-mute-9')),
          );
          await mouse.moveTo(mute);
          await mouse.down(mute);
          await mouse.up();
          await tester.pumpAndSettle();
          expect(api.chatChannelNotificationsUpdated, const [
            (channelId: 9, muted: true, notificationLevel: null),
          ]);
          expect(find.text('Channel settings'), findsNothing);
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
            sidebarDestination('Bugs'),
            buttons: kSecondaryMouseButton,
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
            sidebarDestination('Bugs'),
            buttons: kSecondaryMouseButton,
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find.byKey(const ValueKey('chat-channel-menu-star-9')),
          );
          await tester.pumpAndSettle();

          expect(api.chatChannelStarsUpdated, const [
            (channelId: 9, starred: true),
          ]);
          // The inbox orders by activity alone, so starring keeps the row.
          expect(sidebarDestination('Bugs'), findsOneWidget);
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
              sidebarDestination('hawk'),
              buttons: kSecondaryMouseButton,
            );
            await tester.pumpAndSettle();

            expect(
              find.widgetWithText(DDropdownMenuItem, 'Close channel'),
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

      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        testWidgets(
          'touch long press opens the channel menu without navigating on $platform',
          (tester) async {
            final previous = debugDefaultTargetPlatformOverride;
            debugDefaultTargetPlatformOverride = platform;
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
                findsOneWidget,
              );
              final shell = ShellScope.read(
                tester.element(find.byType(InstanceSidebar)),
              );
              final currentContent = shell.currentContent?.id;
              await tester.longPress(sidebarDestination('Bugs'));
              await tester.pumpAndSettle();

              expect(shell.currentContent?.id, currentContent);
              expect(find.byType(InstanceSidebar), findsOneWidget);
              expect(
                find.widgetWithText(DDropdownMenuSub, 'Notifications'),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(DDropdownMenuItem, 'Channel settings'),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(
                  DDropdownMenuItem,
                  'Add to starred channels',
                ),
                findsOneWidget,
              );
              expect(
                find.widgetWithText(DDropdownMenuItem, 'Leave channel'),
                findsOneWidget,
              );

              await tester.tap(
                find.byKey(const ValueKey('chat-channel-notifications-9')),
              );
              await tester.pumpAndSettle();
              expect(find.text('Mentions only'), findsOneWidget);

              await tester.tap(
                find.byKey(
                  const ValueKey('chat-channel-notification-9-always'),
                ),
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
                find.widgetWithText(DDropdownMenuItem, 'Channel settings'),
                findsNothing,
              );
            } finally {
              debugDefaultTargetPlatformOverride = previous;
            }
          },
        );
      }

      testWidgets(
        'refreshes the current channel without replacing its composer',
        (tester) async {
          final api = FakeDiscourseApi(
            totals: withChat,
            user: me,
            chatChannelsBySite: {
              site: ChatChannels(public: [channel(9)]),
            },
            chatMessagesByKey: {
              key(9): page([msg(1)]),
            },
          );
          await pumpChat(tester, api: api);
          final shell = ShellScope.read(
            tester.element(find.byType(MainContent)),
          );
          shell.openChatChannel(9);
          await tester.pumpAndSettle();
          final editor = find.descendant(
            of: find.byType(ChatComposer),
            matching: find.byType(EditableText),
          );
          final composer = tester.widget<EditableText>(editor).controller;
          await tester.enterText(editor, 'Keep this chat draft');
          await tester.pumpAndSettle();
          final history = shell.contentStack;
          api.chatMessagesRequested.clear();
          api.chatMessagesByKey[key(9)] = page([
            msg(1, cooked: '<p>Refreshed channel message</p>'),
          ]);

          unawaited(shell.refreshCurrentTab());
          await tester.pumpAndSettle();

          expect(api.chatMessagesRequested, hasLength(1));
          expect(api.chatMessagesRequested.single.channelId, 9);
          expect(renderedText('Refreshed channel message'), findsOneWidget);
          expect(shell.contentStack, history);
          expect(
            tester.widget<EditableText>(editor).controller,
            same(composer),
          );
          expect(composer.text, 'Keep this chat draft');
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
      );

      testWidgets('refreshes browse results with the current channel filter', (
        tester,
      ) async {
        final api = FakeDiscourseApi(
          totals: withChat,
          user: me,
          chatChannelsBySite: {
            site: ChatChannels(public: [channel(9)]),
          },
          chatBrowsePagesByKey: {
            FakeDiscourseApi.chatBrowseKey(): const ChatChannelBrowsePage(
              channels: [],
            ),
            FakeDiscourseApi.chatBrowseKey(filter: 'sup'):
                const ChatChannelBrowsePage(channels: []),
          },
        );
        await pumpChat(tester, api: api);
        await tester.tap(find.byKey(const ValueKey('chat-inbox-browse')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('chat-browse-filter')),
          'sup',
        );
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        api.chatBrowseRequested.clear();
        api.chatBrowsePagesByKey[FakeDiscourseApi.chatBrowseKey(
          filter: 'sup',
        )] = ChatChannelBrowsePage(
          channels: [channel(10, title: 'Support')],
        );

        unawaited(shell.refreshCurrentTab());
        await tester.pumpAndSettle();

        expect(api.chatBrowseRequested, const [
          (
            filter: 'sup',
            status: ChatChannelBrowseStatus.all,
            offset: 0,
            limit: ChatChannelBrowsePage.pageSize,
          ),
        ]);
        expect(
          find.byKey(const ValueKey('chat-browse-channel-10')),
          findsOneWidget,
        );
        expect(shell.currentContent?.id, ChatPlugin.browseRouteId);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

        await tester.tap(find.byKey(const ValueKey('chat-inbox-browse')));
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('tabs through the browse channel filters in order', (
        tester,
      ) async {
        await pumpChat(tester);

        await tester.tap(find.byKey(const ValueKey('chat-inbox-browse')));
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets(
        'draws the other person’s face on a one-to-one conversation',
        (tester) async {
          await pumpChat(tester, direct: [dm(12)]);

          final chatAvatar = find.descendant(
            of: find.byType(InstanceSidebar),
            matching: find.byType(ChatUserAvatar),
          );
          final avatar = find.descendant(
            of: chatAvatar,
            matching: find.byType(AvatarImage),
          );
          expect(avatar, findsOneWidget);
          expect(chatAvatar, findsOneWidget);
          expect(
            tester.getSize(avatar),
            const Size.square(ChatInboxRow.compactAvatarSize),
          );
        },
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
        expect(
          tester.getSize(ring),
          const Size.square(ChatInboxRow.compactAvatarSize),
        );

        final tracker = FakeSiteTracker.built.single;
        tracker.deliverPluginMessage('/presence/chat/online', {
          'leaving_user_ids': [2],
        });
        await tester.pump();

        expect(ring, findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('an unread conversation leads with what is new', (
        tester,
      ) async {
        await pumpChat(
          tester,
          public: [
            channel(9, title: 'Bugs', unread: 42),
            channel(10, title: 'Design', mentions: 1),
          ],
          direct: [dm(12, title: 'hawk', lastMessagePreview: 'See you')],
        );

        Finder preview(String text) => find.descendant(
          of: find.byType(InstanceSidebar),
          matching: find.text(text, findRichText: true),
        );
        expect(preview('42 new messages'), findsOneWidget);
        expect(preview('1 new mention'), findsOneWidget);
        expect(preview('See you'), findsOneWidget);
        FontWeight? weight(String title) =>
            tester.widget<Text>(sidebarDestination(title)).style?.fontWeight;
        expect(weight('Bugs'), FontWeight.w700);
        expect(weight('hawk'), FontWeight.w500);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
              .singleWhere((item) => item.title == 'Bugs');

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
          final item = tester
              .widget<ForumTabsBar>(tab)
              .items
              .singleWhere((item) => item.title == 'hawk');
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
          expect(tester.getSize(ring), const Size.square(16));
        } finally {
          debugDefaultTargetPlatformOverride = previous;
        }
      });

      testWidgets('forgets a disconnected site’s channels', (tester) async {
        await pumpChat(tester, size: phone, public: [channel(9)]);
        expect(sidebarDestination('Bugs'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('mobile-mode-home')));
        await tester.pumpAndSettle();
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
      setUp(() => startOnChatSidebar = true);
      testWidgets('channel header separator follows the page reading lane', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1600, 900);
        addTearDown(tester.view.resetPhysicalSize);
        await pumpChat(
          tester,
          direct: [dm(12)],
          messages: {key(12): page(const [])},
        );
        await tester.tap(sidebarDestination('hawk'));
        await tester.pumpAndSettle();

        final separator = find.byKey(
          const ValueKey('content-header-separator'),
        );
        final pageSurface = find
            .ancestor(of: separator, matching: find.byType(DPageSurface))
            .first;
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));

        for (final limited in [false, true]) {
          await shell.appSettings.setLimitContentSize(limited);
          await tester.pumpAndSettle();
          final pageRect = tester.getRect(pageSurface);
          final lineRect = tester.getRect(separator);
          final inset = limited && pageRect.width > DPageReadingLane.maxWidth
              ? (pageRect.width - DPageReadingLane.maxWidth) / 2
              : 0.0;
          expect(lineRect.left, closeTo(pageRect.left + inset + 16, 1));
          expect(lineRect.right, closeTo(pageRect.right - inset - 16, 1));
        }
      });

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
          final status = find.byKey(
            const ValueKey('chat-channel-header-status'),
          );
          final star = find.byKey(const ValueKey('chat-channel-star-button'));
          final emoji = find.descendant(
            of: status,
            matching: find.byType(SiteEmojiImage),
          );

          expect(star, findsOneWidget);
          expect(status, findsOneWidget);
          expect(emoji, findsOneWidget);
          expect(
            tester.getRect(star).left - tester.getRect(titleAction).right,
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
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        expect(
          shell.contentStack.map((route) => route.id),
          containsAllInOrder(['chat-c-9', 'chat-c-9-info-settings']),
        );
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

      testWidgets('stacks grouped channel details on a phone', (tester) async {
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
              public: [
                channel(9, description: 'A place to discuss bug reports.'),
              ],
              direct: const [],
            ),
          },
          chatMessagesByKey: {key(9): page(const [])},
        );
        await pumpChat(tester, api: api, user: staff, size: phone);
        await tester.tap(sidebarDestination('Bugs'));
        await tester.pumpAndSettle();
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(
          shell.pluginSession
              .require(chatShellService)
              .openChannelInfo(siteUrl: site, channelId: 9),
          isTrue,
        );
        await tester.pumpAndSettle();

        final identity = find.byKey(
          const ValueKey('chat-channel-summary-identity'),
        );
        final summary = find.byKey(const ValueKey('chat-channel-summary'));
        final edit = find.byKey(const ValueKey('chat-channel-edit-details'));
        final settingsTab = find.byKey(
          const ValueKey('chat-channel-info-settings-tab'),
        );
        final summaryTitle = find.descendant(
          of: summary,
          matching: find.text('Bugs'),
        );
        final settingsLabel = find.descendant(
          of: settingsTab,
          matching: find.text('Settings'),
        );
        final theme = Theme.of(tester.element(summary));
        expect(
          tester.getTopLeft(edit).dy,
          greaterThanOrEqualTo(tester.getBottomLeft(identity).dy),
        );
        expect(tester.getSize(settingsTab).height, 62);
        expect(
          tester
              .getSize(
                find.descendant(
                  of: settingsTab,
                  matching: find.byType(AnimatedContainer),
                ),
              )
              .height,
          62,
        );
        expect(
          tester
              .getSize(find.byKey(const ValueKey('chat-channel-info-tabs')))
              .height,
          62,
        );
        final settingsStyle = DefaultTextStyle.of(
          tester.element(settingsLabel),
        ).style;
        expect(settingsStyle.fontSize, 16);
        expect(settingsStyle.fontWeight, FontWeight.w600);
        expect(
          tester.widget<Text>(summaryTitle).style?.fontSize,
          theme.textTheme.titleLarge?.fontSize,
        );
        expect(
          tester.widget<Text>(summaryTitle).style?.fontWeight,
          FontWeight.w500,
        );
        expect(find.text('Your notifications'), findsOneWidget);
        expect(find.text('Conversation'), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.text('Your notifications'))
              .style
              ?.fontWeight,
          FontWeight.w500,
        );
        expect(
          tester.widget<Text>(find.text('Mute channel')).style?.fontWeight,
          FontWeight.w500,
        );
        expect(
          tester
              .widget<Text>(
                find.text(
                  'Hide unread indicators and stop channel notifications.',
                ),
              )
              .style
              ?.fontSize,
          theme.textTheme.bodyMedium?.fontSize,
        );
        expect(find.text('Only affects you'), findsNothing);
        expect(find.text('Shared setting'), findsNothing);
        expect(find.text('Staff'), findsNothing);
        expect(tester.takeException(), isNull);
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
            rowCount: 2,
            totalRows: 2,
            canLoadMore: false,
          ),
          FakeDiscourseApi.chatChannelMembersKey(9, username: 'ha'): (
            members: const [ChatUser(id: 3, username: 'hawk', name: 'Hawk')],
            rowCount: 1,
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
          find.byKey(const ValueKey('chat-channel-edit-details')),
          findsNothing,
        );
        expect(find.text('Your notifications'), findsOneWidget);
        expect(find.text('Only affects you'), findsNothing);
        expect(find.text('Message history'), findsOneWidget);
        expect(find.text('Members (2)'), findsOneWidget);
        expect(find.text('Sam'), findsNothing);

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        final tabs = find.byKey(const ValueKey('chat-channel-info-tabs'));
        final settingsLane = find.byKey(
          const ValueKey('chat-channel-settings-lane-content'),
        );
        final centeredSettingsLeft = tester.getTopLeft(settingsLane).dx;
        final settingsWidth = tester.getSize(settingsLane).width;
        final tabsRect = tester.getRect(tabs);
        expect(tester.getSize(settingsLane).width, lessThanOrEqualTo(760));
        expect(tabsRect.width, tester.getSize(find.byType(MainContent)).width);

        await shell.appSettings.setLimitContentSize(false);
        await tester.pump();
        expect(
          tester.getTopLeft(settingsLane).dx,
          closeTo(centeredSettingsLeft, 0.001),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setLimitContentSize(true);
        await tester.pump();
        expect(
          tester.getTopLeft(settingsLane).dx,
          closeTo(centeredSettingsLeft, 0.001),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setLimitContentSize(false);
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('chat-channel-info-members-tab')),
        );
        await tester.pumpAndSettle();

        expect(shell.currentContent?.id, 'chat-c-9-info-members');
        expect(
          shell.contentStack.map((route) => route.id),
          containsAllInOrder(['chat-c-9', 'chat-c-9-info-members']),
        );

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
        expect(tester.getSize(memberFilterLane).width, settingsWidth);
        expect(tester.getSize(firstMember).width, settingsWidth);
        expect(tester.getSize(memberList).width, tabsRect.width);
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setLimitContentSize(false);
        await tester.pump();
        expect(
          tester.getTopLeft(memberFilterLane).dx,
          closeTo(centeredFilterLeft, 0.001),
        );
        expect(
          tester.getTopLeft(firstMember).dx,
          closeTo(centeredMemberLeft, 0.001),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setLimitContentSize(true);
        await tester.pump();
        expect(
          tester.getTopLeft(memberFilterLane).dx,
          closeTo(centeredFilterLeft, 0.001),
        );
        expect(
          tester.getTopLeft(firstMember).dx,
          closeTo(centeredMemberLeft, 0.001),
        );
        expect(tester.getRect(tabs), tabsRect);

        await shell.appSettings.setLimitContentSize(false);
        await tester.pump();
        debugDefaultTargetPlatformOverride = previousPlatform;

        memberPages[FakeDiscourseApi.chatChannelMembersKey(9)] = (
          members: const [
            ChatUser(id: 2, username: 'sam', name: 'Sam'),
            ChatUser(id: 3, username: 'hawk', name: 'Hawk'),
            ChatUser(id: 4, username: 'kris', name: 'Kris'),
          ],
          rowCount: 3,
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
              rowCount: 0,
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
          find.byKey(const ValueKey('chat-channel-edit-details')),
        );
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const ValueKey('chat-channel-title-input')),
          'Bug reports',
        );
        await tester.enterText(
          find.byKey(const ValueKey('chat-channel-slug-input')),
          'bug-reports',
        );
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-details-save')),
        );
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
              rowCount: 0,
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
          find.byKey(const ValueKey('chat-channel-edit-details')),
        );
        await tester.pumpAndSettle();

        final descriptionInput = find.byKey(
          const ValueKey('chat-channel-description-input'),
        );
        await tester.enterText(descriptionInput, 'x');
        await tester.enterText(descriptionInput, '');
        await tester.tap(
          find.byKey(const ValueKey('chat-channel-details-save')),
        );
        await tester.pumpAndSettle();

        expect(api.chatChannelMetadataUpdates.single.description, '');
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.description, isNull);
        expect(
          find.text('Tell people what this channel is about.'),
          findsOneWidget,
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
              rowCount: 0,
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
        expect(find.text('Conversation'), findsOneWidget);
        expect(find.text('Shared setting'), findsNothing);
        expect(find.text('Channel management'), findsOneWidget);
        expect(find.text('Staff'), findsNothing);
        expect(find.text('Leave this channel'), findsOneWidget);
        expect(threadingSwitch, findsOneWidget);
        expect(tester.widget<DSwitch>(threadingSwitch).value, isFalse);

        await tester.ensureVisible(threadingSwitch);
        await tester.pumpAndSettle();
        await tester.tap(threadingSwitch);
        await tester.pumpAndSettle();

        expect(api.chatChannelThreadingUpdates, const [
          (channelId: 9, enabled: true),
        ]);
        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(shell.chat.channel(site, 9)?.threadingEnabled, isTrue);
        expect(tester.widget<DSwitch>(threadingSwitch).value, isTrue);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
              rowCount: 0,
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
        final statusButton = find.byKey(
          const ValueKey('chat-channel-toggle-status'),
        );
        await tester.ensureVisible(statusButton);
        await tester.pumpAndSettle();
        await tester.tap(statusButton);
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

        final leaveButton = find.byKey(const ValueKey('chat-channel-leave'));
        await tester.ensureVisible(leaveButton);
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(DButton, 'Leave channel').hitTestable(),
          findsOneWidget,
        );
        expect(
          tester.widget<DButton>(leaveButton).variant,
          DButtonVariant.outline,
        );
        await tester.tap(leaveButton);
        await tester.pumpAndSettle();

        final shell = ShellScope.read(tester.element(find.byType(MainContent)));
        expect(api.chatChannelFollowsUpdated, const [
          (channelId: 9, following: false),
        ]);
        expect(shell.currentContent?.id, 'chat-browse');
        expect(sidebarDestination('Bugs'), findsNothing);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        final avatar = tester.widget<DAvatar>(ring);
        expect(avatar.ring, isTrue);
        expect(avatar.ringSemanticLabel, 'Online');
        expect(
          tester.getSize(
            find.descendant(of: ring, matching: find.byType(AvatarImage)),
          ),
          const Size.square(24),
        );

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
          expect(
            find.byKey(const ValueKey('chat-message-bubble-1')),
            findsOneWidget,
          );
          expect(shellNotifications, 0);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

        final more = find.byKey(const ValueKey('chat-message-more-actions-2'));
        expect(more.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(more).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byKey(const ValueKey('chat-composer'))).top,
          ),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        expect(find.byType(DMessage), findsNWidgets(2));
        expect(find.byType(DMessageContent), findsNWidgets(2));

        expect(
          tester
              .widget<Padding>(find.byKey(const ValueKey('chat-message-1')))
              .padding,
          const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
        );
        expect(
          tester
              .widget<Padding>(find.byKey(const ValueKey('chat-message-2')))
              .padding,
          const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 8),
        );
        final first = tester.getRect(
          find.byKey(const ValueKey('chat-message-bubble-1')),
        );
        final second = tester.getRect(
          find.byKey(const ValueKey('chat-message-bubble-2')),
        );
        expect(second.top - first.bottom, 4);
        expect(first.left, second.left);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

        final mine = tester.widget<DToggle>(
          find.byKey(const ValueKey('chat-reaction-heart')),
        );
        final other = tester.widget<DToggle>(
          find.byKey(const ValueKey('chat-reaction-clap')),
        );
        expect(find.byType(ReactionPill), findsNWidgets(2));
        expect(mine.variant, DToggleVariant.outline);
        expect(other.variant, DToggleVariant.outline);
        expect(mine.pressed, isTrue);
        expect(other.pressed, isFalse);

        final heart = find.bySemanticsLabel('3 heart reactions');
        final clap = find.bySemanticsLabel('2 clap reactions');
        expect(tester.getSize(heart).width, greaterThanOrEqualTo(44));
        expect(tester.getSize(heart).height, greaterThanOrEqualTo(44));
        expect(
          tester.getSemantics(heart),
          isSemantics(
            isButton: true,
            hasToggledState: true,
            isToggled: true,
            hint: 'remove your reaction',
            onLongPressHint: 'show who reacted',
          ),
        );
        expect(
          tester.getSemantics(clap),
          isSemantics(
            isButton: true,
            hasToggledState: true,
            isToggled: false,
            hint: 'add this reaction',
            onLongPressHint: 'show who reacted',
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
            tester
                    .widget<AnimatedContainer>(
                      find.descendant(
                        of: reaction,
                        matching: find.byType(AnimatedContainer),
                      ),
                    )
                    .decoration!
                as BoxDecoration;
        final resting = decoration().color;
        final rect = tester.getRect(reaction);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(reaction));
        await tester.pump();

        await tester.pumpAndSettle();
        expect(decoration().color, isNot(resting));
        expect(tester.getRect(reaction), rect);

        await mouse.moveTo(Offset.zero);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(decoration().color, resting);
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: Offset.zero);
          addTearDown(mouse.removePointer);
          await mouse.moveTo(
            tester.getCenter(find.byType(ChatMessageTile).first),
          );
          await tester.pump();
          final launcher = find.bySemanticsLabel('Add reaction');
          expect(launcher, findsOneWidget);
          expect(tester.getSize(launcher), const Size.square(28));
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
          tester.element(find.byType(ChatMessageTile).first),
        );

        await tester.longPress(find.text('Hello there', findRichText: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('React'));
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
          isSemantics(hasTapAction: false, onLongPressHint: 'show who reacted'),
        );
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
          isSemantics(
            hint: 'remove your reaction',
            onLongPressHint: 'show who reacted',
          ),
        );
        expect(
          tester.getSemantics(find.bySemanticsLabel('2 clap reactions')),
          isSemantics(hasTapAction: false, onLongPressHint: 'show who reacted'),
        );

        await tester.tap(find.bySemanticsLabel('2 heart reactions'));
        await tester.pumpAndSettle();

        expect(api.chatReactionsSet, hasLength(1));
        expect(api.chatReactionsSet.single.action, ChatReactionAction.remove);
        expect(api.chatReactionsSet.single.emoji, 'heart');
      }, variant: TargetPlatformVariant.only(TargetPlatform.android));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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

        final button = find.bySemanticsLabel('Jump to latest messages');
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
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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
      }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

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

        expect(renderedText('Hello there'), findsNothing);
        expect(find.text('Channels'), findsOneWidget);
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
