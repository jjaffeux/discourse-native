import 'dart:async';

import 'package:discourse_native/src/models/content_route.dart';
import 'package:discourse_native/src/models/discourse_user.dart';
import 'package:discourse_native/src/models/forum_workspace.dart';
import 'package:discourse_native/src/models/notification.dart';
import 'package:discourse_native/src/models/sidebar.dart';
import 'package:discourse_native/src/plugin_api/plugin_manifest.dart';
import 'package:discourse_native/src/plugin_api/plugin_scope.dart';
import 'package:discourse_native/src/plugin_api/site_plugin_api.dart';
import 'package:discourse_native/src/plugins/chat/chat_channel.dart';
import 'package:discourse_native/src/plugins/chat/chat_direct_message_search.dart';
import 'package:discourse_native/src/plugins/chat/chat_message.dart';
import 'package:discourse_native/src/plugins/chat/chat_notification_counter.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin.dart';
import 'package:discourse_native/src/plugins/chat/chat_plugin_data.dart';
import 'package:discourse_native/src/plugins/chat/chat_route.dart';
import 'package:discourse_native/src/plugins/chat/chat_services.dart';
import 'package:discourse_native/src/plugins/chat/chat_shell_service.dart';
import 'package:discourse_native/src/plugins/chat/chat_thread.dart';
import 'package:discourse_native/src/plugins/chat/chat_user_menu.dart';
import 'package:discourse_native/src/shell/adaptive_shell.dart';
import 'package:discourse_native/src/shell/composer_controller.dart';
import 'package:discourse_native/src/shell/main_content.dart';
import 'package:discourse_native/src/shell/notification_list.dart';
import 'package:discourse_native/src/shell/open_link.dart';
import 'package:discourse_native/src/shell/shell_controller.dart';
import 'package:discourse_native/src/shell/shell_scope.dart';
import 'package:discourse_native/src/theme/app_theme.dart';
import 'package:discourse_native/src/theme/d_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/bundled_plugins.dart';
import 'support/chat_shell.dart';
import 'support/fakes.dart';

const String _site = 'https://meta.discourse.org';
const String _otherSite = 'https://other.example';
final DiscourseUser _user = DiscourseUser(
  id: 7,
  username: 'reader',
  name: 'Reader',
  plugins: PluginData.none.withValue(
    chatCurrentUserDataKey,
    const ChatCurrentUser(hasChatEnabled: true, canDirectMessage: true),
  ),
);

ChatChannel _channel(int id, {String title = 'Support'}) => ChatChannel(
  id: id,
  title: title,
  kind: ChatChannelKind.category,
  membership: const ChatMembership(following: true),
  tracking: const ChatTracking(),
  threadingEnabled: true,
);

ChatThread _thread(int channelId, int threadId) {
  final originalMessageId = threadId == 3 ? 40 : threadId * 10;
  return ChatThread(
    id: threadId,
    channelId: channelId,
    status: 'open',
    replyCount: 1,
    lastMessageId: originalMessageId + 1,
    originalMessage: ChatThreadOriginalMessage(
      id: originalMessageId,
      channelId: channelId,
      author: const ChatMessageAuthor(id: 2, username: 'sam'),
      excerpt: 'Original message',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ShellController shell;
  late FakeDiscourseApi api;

  setUp(() async {
    api = FakeDiscourseApi(
      user: _user,
      totals: chatNotificationTotals(),
      chatNotificationList: const [
        DiscourseNotification.test(
          id: 51,
          typeId: NotificationTypeId(40),
          title: 'Support thread',
          data: {
            'display_username': 'sam',
            'chat_channel_id': 9,
            'chat_thread_id': 3,
            'chat_message_id': 44,
          },
        ),
      ],
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(
          public: [_channel(9)],
          direct: const [],
          hasThreads: true,
        ),
        _otherSite: ChatChannels(
          public: [_channel(12, title: 'Other support')],
          direct: const [],
        ),
      },
      chatDirectMessageSearches: {
        'sam': ChatDirectMessageSearchResults(const [
          ChatDirectMessageUser(
            identifier: 'u-2',
            matchQuality: 1,
            enabled: true,
            username: 'sam',
            name: 'Sam',
          ),
        ]),
        'previous': ChatDirectMessageSearchResults(const [
          ChatDirectMessageChannel(
            identifier: 'c-56',
            matchQuality: 1,
            enabled: true,
            channel: ChatChannel(
              id: 56,
              title: 'Previous conversation',
              kind: ChatChannelKind.directMessage,
              membership: ChatMembership(following: true),
              tracking: ChatTracking(),
            ),
          ),
        ]),
      },
      directMessageChannelsByUsername: const {
        'sam': ChatChannel(
          id: 55,
          title: 'Sam',
          kind: ChatChannelKind.directMessage,
          users: [ChatUser(id: 2, username: 'sam', name: 'Sam')],
          membership: ChatMembership(following: true),
          tracking: ChatTracking(),
        ),
      },
      chatThreadsByKey: {
        FakeDiscourseApi.chatThreadKey(9, 3): _thread(9, 3),
        FakeDiscourseApi.chatThreadKey(9, 4): _thread(9, 4),
        FakeDiscourseApi.chatThreadKey(12, 7): _thread(12, 7),
      },
      chatThreadPagesByOffset: {
        0: ChatThreadPage(
          threads: const [
            ChatThread(
              id: 3,
              channelId: 9,
              status: 'open',
              replyCount: 4,
              title: 'Support thread',
              tracking: ChatTracking(unreadCount: 2),
              originalMessage: ChatThreadOriginalMessage(
                id: 40,
                channelId: 9,
                author: ChatMessageAuthor(id: 2, username: 'sam'),
                excerpt: 'Can someone check this?',
              ),
            ),
          ],
          channels: [_channel(9)],
        ),
      },
      chatChannelThreadPagesByKey: {
        FakeDiscourseApi.chatChannelThreadPageKey(9, 0): ChatThreadPage(
          threads: [
            ChatThread(
              id: 3,
              channelId: 9,
              status: 'open',
              replyCount: 4,
              title: 'Support thread',
              lastMessageId: 44,
              tracking: const ChatTracking(unreadCount: 2),
              preview: ChatThreadPreview(
                threadId: 3,
                replyCount: 4,
                lastReplyId: 44,
                lastReplyAt: DateTime.utc(2026, 8, 24, 12),
                lastReplyExcerpt: 'Latest answer',
              ),
              originalMessage: const ChatThreadOriginalMessage(
                id: 40,
                channelId: 9,
                author: ChatMessageAuthor(id: 2, username: 'sam'),
                excerpt: 'Can someone check this?',
              ),
            ),
          ],
        ),
      },
    );
    final authenticator = FakeAuthenticator()
      ..keys[_site] = 'meta-key'
      ..keys[_otherSite] = 'other-key';
    shell = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
        instance('other.example').copyWith(user: _user),
      ]),
      api: api,
      authenticator: authenticator,
      drafts: FakeDraftStore(),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(shell.dispose);
    await shell.load();
  });

  test(
    'opens a thread route and hands its message to the mounted view',
    () async {
      expect(
        shell.pluginSession.require(chatShellService),
        isNot(isA<ShellController>()),
      );
      expect(
        shell.pluginSession.require(chatBookmarkHostService),
        isNot(isA<ShellController>()),
      );
      expect(
        shell.pluginSession.require(chatNotificationHostService),
        isNot(isA<ShellController>()),
      );

      expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/44'), isTrue);

      expect(shell.destinationId, 'chat-c-9');
      expect(shell.contentStack.map((route) => route.id), [
        'chat-c-9',
        'chat-c-9-t-3',
      ]);
      expect(shell.currentContent?.title, 'Thread');
      expect(shell.currentContent?.subtitle, 'Support');
      expect(shell.chatNavigation.value?.siteUrl, _site);
      expect(
        shell.chatNavigation.value?.route,
        ChatRoute.thread(channelId: 9, threadId: 3),
      );
      expect(shell.chatNavigation.value?.messageId, 44);
    },
  );

  test('Chat host ports reject foreign composer and feed namespaces', () async {
    final composerHost = shell.pluginSession.require(chatComposerHostService);
    const foreignTarget = ComposerTargetKind(
      owner: PluginId('foreign'),
      name: 'message',
    );

    expect(
      () => composerHost.buildComposer(
        const ComposerTargetRequest(
          kind: foreignTarget,
          siteUrl: _site,
          title: 'Foreign message',
        ),
      ),
      throwsA(
        isA<PluginInstallationException>().having(
          (error) => error.message,
          'message',
          allOf(contains('chat'), contains(foreignTarget.id)),
        ),
      ),
    );

    final composer = composerHost.buildComposer(
      const ComposerTargetRequest(
        kind: ChatPlugin.messageComposerTarget,
        siteUrl: _site,
        title: 'Support',
        data: {ChatPlugin.composerChannelId: 9},
      ),
    );
    expect(composer, isNotNull);
    composer!.dispose();

    final notificationHost = shell.pluginSession.require(
      chatNotificationHostService,
    );
    const foreignFeedId = PluginNotificationFeedId(
      owner: PluginId('foreign'),
      name: 'notifications',
    );
    const foreignFeed = PluginNotificationFeedSource(
      id: foreignFeedId,
      filterByTypes: [NotificationTypeName('chat_message')],
      reconnectMessage: 'Reconnect.',
      failureMessage: 'Failed.',
      emptyMessage: 'Empty.',
    );

    for (final access in <void Function()>[
      () => notificationHost.notificationFeedListenable(foreignFeedId),
      () => notificationHost.notificationFeedFor(foreignFeedId, _site),
      () => notificationHost.loadPluginNotificationFeed(_site, foreignFeed),
    ]) {
      expect(
        access,
        throwsA(
          isA<PluginInstallationException>().having(
            (error) => error.message,
            'message',
            allOf(contains('chat'), contains(foreignFeedId.id)),
          ),
        ),
      );
    }

    const undeclaredFeedId = PluginNotificationFeedId(
      owner: PluginId('chat'),
      name: 'undeclared',
    );
    expect(
      () => notificationHost.notificationFeedFor(undeclaredFeedId, _site),
      throwsA(
        isA<PluginInstallationException>().having(
          (error) => error.message,
          'message',
          allOf(contains('chat'), contains(undeclaredFeedId.id)),
        ),
      ),
    );
    expect(
      () => notificationHost.loadPluginNotificationFeed(
        _site,
        const PluginNotificationFeedSource(
          id: PluginNotificationFeedId(
            owner: PluginId('chat'),
            name: 'notifications',
          ),
          filterByTypes: [NotificationTypeName('chat_message')],
          reconnectMessage: 'Different reconnect message.',
          failureMessage: 'Different failure message.',
          emptyMessage: 'Different empty message.',
        ),
      ),
      throwsA(isA<PluginInstallationException>()),
    );

    expect(
      notificationHost.notificationFeedListenable(chatNotificationFeed.id),
      isNotNull,
    );
    await notificationHost.loadPluginNotificationFeed(
      _site,
      chatNotificationFeed,
    );
    expect(
      notificationHost
          .notificationFeedFor(chatNotificationFeed.id, _site)
          .notifications
          .map((notification) => notification.id),
      [51],
    );
  });

  test(
    'retargets the same route without adding a duplicate stack entry',
    () async {
      await shell.openChatUrl('$_site/chat/c/-/9/t/3/44');
      final stack = shell.contentStack;

      expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/45'), isTrue);

      expect(shell.contentStack, same(stack));
      expect(shell.chatNavigation.value?.messageId, 45);
    },
  );

  test('same-route Chat links reactivate compact content', () async {
    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/44'), isTrue);
    shell.selectInstance(0);
    expect(shell.mobilePane, MobilePane.sidebar);

    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/3/45'), isTrue);

    expect(shell.mobilePane, MobilePane.content);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 45);
  });

  test(
    'a superseded native Chat open cannot overwrite the latest intent',
    () async {
      final channelGate = Completer<void>();
      final gatedApi = FakeDiscourseApi(
        user: _user,
        feeds: const {'/latest.json': []},
        chatChannelGate: channelGate,
        chatChannelsBySite: {
          _site: ChatChannels(public: [_channel(9)]),
        },
      );
      final gated = ShellController(
        plugins: installedPlugins,
        instanceStore: FakeInstanceStore([
          instance('meta.discourse.org').copyWith(user: _user),
        ]),
        api: gatedApi,
        authenticator: FakeAuthenticator()..keys[_site] = 'meta-key',
        drafts: FakeDraftStore(),
        trackers: FakeSiteTracker.reset(),
        updater: FakeUpdater(),
        updateStore: FakeUpdateStore(),
        ownsApi: false,
      );
      addTearDown(gated.dispose);
      await gated.load();

      final first = gated.openChatUrl('$_site/chat/c/-/9/44');
      expect(
        await gated.openChatUrl('https://unknown.example/chat/c/-/9'),
        isFalse,
      );
      channelGate.complete();

      expect(await first, isFalse);
      expect(gated.currentContent?.id, 'latest');
      expect(gated.chatNavigation.value, isNull);
    },
  );

  test('a different thread replaces the previous thread history', () async {
    await shell.openChatUrl('$_site/chat/c/-/9/t/3');
    await shell.openChatUrl('$_site/chat/c/-/9/t/4');

    expect(shell.contentStack.map((route) => route.id), [
      'chat-c-9',
      'chat-c-9-t-4',
    ]);
    expect(shell.handleBack(), isTrue);
    expect(shell.currentContent?.id, 'chat-c-9');
  });

  test('cross-site Chat links switch only after access is confirmed', () async {
    expect(await shell.openChatUrl('$_otherSite/chat/c/-/12/88'), isTrue);

    expect(shell.currentInstance?.url, _otherSite);
    expect(shell.currentContent?.id, 'chat-c-12');
    expect(shell.chatNavigation.value?.messageId, 88);
  });

  test(
    'unknown sites and channels retain browser fallback semantics',
    () async {
      expect(
        await shell.openChatUrl('https://unknown.example/chat/c/-/9'),
        isFalse,
      );
      expect(await shell.openChatUrl('$_otherSite/chat/c/-/99'), isFalse);

      expect(shell.currentInstance?.url, _site);
      expect(shell.currentContent?.id, 'latest');
      expect(shell.chatNavigation.value, isNull);
    },
  );

  test('an inaccessible thread retains browser fallback semantics', () async {
    expect(await shell.openChatUrl('$_site/chat/c/-/9/t/99/44'), isFalse);

    expect(shell.currentInstance?.url, _site);
    expect(shell.currentContent?.id, 'latest');
    expect(shell.chatNavigation.value, isNull);
  });

  test('a persisted thread route restores and hydrates its channel', () async {
    final restoredApi = FakeDiscourseApi(
      user: _user,
      feeds: const {'/latest.json': []},
      chatChannelsBySite: {
        _site: ChatChannels(public: [_channel(9)], direct: const []),
      },
    );
    final restored = ShellController(
      plugins: installedPlugins,
      instanceStore: FakeInstanceStore([
        instance('meta.discourse.org').copyWith(user: _user),
      ]),
      api: restoredApi,
      authenticator: FakeAuthenticator()..keys[_site] = 'meta-key',
      drafts: FakeDraftStore(),
      forumTabs: FakeForumTabStore([
        ForumWorkspace(
          siteUrl: _site,
          accountIdentity: 'user:reader',
          tabs: [
            ForumTab(
              id: 'persisted-tab',
              rootDestinationId: 'chat-c-9',
              contentStack: const [
                ContentRoute(
                  id: 'chat-c-9',
                  title: 'Support',
                  icon: DIcons.comment,
                ),
                ContentRoute(
                  id: 'chat-c-9-t-3',
                  title: 'Thread',
                  icon: DIcons.comments,
                ),
              ],
            ),
          ],
          activeTabId: 'persisted-tab',
        ),
      ]),
      trackers: FakeSiteTracker.reset(),
      updater: FakeUpdater(),
      updateStore: FakeUpdateStore(),
      ownsApi: false,
    );
    addTearDown(restored.dispose);

    await restored.load();
    for (
      var attempt = 0;
      attempt < 20 && restored.chat.channel(_site, 9) == null;
      attempt++
    ) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(restored.currentContent?.id, 'chat-c-9-t-3');
    expect(restoredApi.chatChannelsRequested, contains(_site));
    expect(restored.chat.channel(_site, 9)?.title, 'Support');
  });

  testWidgets('generic openLink dispatches Chat before browser fallback', (
    tester,
  ) async {
    bool? opened;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                opened = await openLink(context, '/chat/c/-/9/t/3/44');
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 44);
  });

  testWidgets('a Chat notification opens natively before browser fallback', (
    tester,
  ) async {
    var opened = false;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          home: Scaffold(
            body: PluginNotificationsSection(
              siteUrl: _site,
              onOpened: () => opened = true,
              host: shell,
              source: chatNotificationFeed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NotificationRow));
    await tester.pumpAndSettle();

    expect(opened, isTrue);
    expect(api.markedRead, [51]);
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.chatNavigation.value?.messageId, 44);
  });

  testWidgets('My threads appears, loads account rows, and opens a thread', (
    tester,
  ) async {
    await shell.chat.loadChannels(_site);
    shell.accountActivity.applyCounts(_site, (_) => chatNotificationTotals());
    expect(shell.currentTotals?.hasChatEnabled, isTrue);
    expect(shell.chat.hasThreads(_site), isTrue);
    late List<SidebarSection> sections;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: PluginUiScope.own(
            chatPluginId,
            Builder(
              builder: (context) {
                sections = const ChatPlugin().sidebarSections(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
    expect(
      sections
          .expand((section) => section.destinations)
          .map((destination) => destination.id),
      contains(ChatPlugin.myThreadsRouteId),
    );

    shell.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.myThreadsRouteId,
        label: 'My threads',
        icon: DIcons.comments,
      ),
    );
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: MainContent(layout: ShellLayout.forWidth(900))),
        ),
      ),
    );
    for (
      var attempt = 0;
      attempt < 20 && find.text('Support thread').evaluate().isEmpty;
      attempt++
    ) {
      await tester.pump();
    }

    expect(find.text('Support thread'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-my-thread-unread-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chat-my-thread-3')));
    await tester.pump();
    expect(shell.currentContent?.id, 'chat-c-9-t-3');
    expect(shell.contentStack.map((route) => route.id), [
      ChatPlugin.myThreadsRouteId,
      'chat-c-9-t-3',
    ]);
    expect(shell.handleBack(), isTrue);
    expect(shell.currentContent?.id, ChatPlugin.myThreadsRouteId);
  });

  testWidgets('Direct messages + opens new and existing DMs from search', (
    tester,
  ) async {
    await shell.chat.loadChannels(_site);
    shell.accountActivity.applyCounts(_site, (_) => chatNotificationTotals());
    late SidebarSection directMessages;
    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: PluginUiScope.own(
            chatPluginId,
            Scaffold(
              body: Builder(
                builder: (context) {
                  directMessages = const ChatPlugin()
                      .sidebarSections(context)
                      .singleWhere(
                        (section) => section.id == 'direct-messages',
                      );
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(directMessages.destinations, isEmpty);
    expect(directMessages.actionLabel, 'Start a direct message');
    directMessages.onAction!();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('chat-new-direct-message-dialog')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('chat-new-direct-message-search')),
      'sam',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(api.chatDirectMessageSearchesRequested, ['sam']);
    await tester.tap(
      find.byKey(const ValueKey('chat-new-direct-message-user-sam')),
    );
    await tester.pumpAndSettle();

    expect(api.directMessageChannelsRequested, ['sam']);
    expect(shell.currentContent?.id, 'chat-c-55');
    expect(
      find.byKey(const ValueKey('chat-new-direct-message-dialog')),
      findsNothing,
    );

    directMessages.onAction!();
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('chat-new-direct-message-search')),
      'previous',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chat-new-direct-message-channel-56')),
    );
    await tester.pumpAndSettle();

    expect(api.chatDirectMessageSearchesRequested, ['sam', 'previous']);
    expect(api.directMessageChannelsRequested, ['sam']);
    expect(shell.currentContent?.id, 'chat-c-56');
  });

  testWidgets('channel header opens its live thread list and preserves Back', (
    tester,
  ) async {
    await shell.chat.loadChannels(_site);
    shell.accountActivity.applyCounts(_site, (_) => chatNotificationTotals());
    expect(shell.openChatChannel(9), isTrue);

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: MainContent(layout: ShellLayout.forWidth(900))),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('chat-channel-threads-button')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('chat-channel-threads-button')));
    await tester.pump();
    expect(shell.currentContent?.id, ChatPlugin.channelThreadsRouteId(9));

    for (
      var attempt = 0;
      attempt < 20 &&
          find
              .byKey(const ValueKey('chat-channel-thread-3'))
              .evaluate()
              .isEmpty;
      attempt++
    ) {
      await tester.pump();
    }
    expect(find.text('Support thread'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('chat-channel-thread-unread-3')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('chat-channel-thread-3')));
    await tester.pump();
    expect(shell.contentStack.map((route) => route.id), [
      'chat-c-9',
      ChatPlugin.channelThreadsRouteId(9),
      'chat-c-9-t-3',
    ]);

    expect(shell.handleBack(), isTrue);
    await tester.pump();
    expect(shell.currentContent?.id, ChatPlugin.channelThreadsRouteId(9));
    expect(find.byKey(const ValueKey('chat-channel-thread-3')), findsOneWidget);
  });

  testWidgets('channel header stars and unstars the current channel', (
    tester,
  ) async {
    await shell.chat.loadChannels(_site);
    expect(shell.openChatChannel(9), isTrue);

    await tester.pumpWidget(
      ShellScope(
        controller: shell,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: MainContent(layout: ShellLayout.forWidth(900))),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Add to starred channels'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to starred channels'));
    await tester.pumpAndSettle();

    expect(api.chatChannelStarsUpdated, const [(channelId: 9, starred: true)]);
    expect(shell.chat.channel(_site, 9)?.membership.starred, isTrue);
    expect(find.byTooltip('Remove from starred channels'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from starred channels'));
    await tester.pumpAndSettle();
    expect(api.chatChannelStarsUpdated, const [
      (channelId: 9, starred: true),
      (channelId: 9, starred: false),
    ]);
    expect(shell.chat.channel(_site, 9)?.membership.starred, isFalse);
  });

  test('imperative thread opening selects its owning site', () async {
    await shell.chat.loadChannels(_otherSite);

    shell.openChatThread(
      siteUrl: _otherSite,
      channelId: 12,
      threadId: 7,
      messageId: 91,
      focusComposer: true,
    );

    expect(shell.currentInstance?.url, _otherSite);
    expect(shell.contentStack.map((route) => route.id), [
      'chat-c-12',
      'chat-c-12-t-7',
    ]);
    expect(shell.chatNavigation.value?.messageId, 91);
    expect(shell.chatNavigation.value?.focusComposer, isTrue);
  });
}
