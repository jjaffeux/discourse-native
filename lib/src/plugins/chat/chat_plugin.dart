import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'chat_browse_channels_view.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_channel_info_view.dart';
import 'chat_channel_star_button.dart';
import 'chat_channel_threads_view.dart';
import 'chat_channel_view.dart';
import 'chat_channels_view.dart';
import 'chat_emoji_usage.dart';
import 'chat_global_search.dart';
import 'chat_header_button.dart';
import 'chat_inbox.dart';
import 'chat_inbox_filters.dart';
import 'chat_mobile_sidebar.dart';
import 'chat_my_threads_view.dart';
import 'chat_new_direct_message.dart';
import 'chat_notification_counter.dart';
import 'chat_notifications.dart';
import 'chat_plugin_data.dart';
import 'chat_preferences.dart';
import 'chat_route.dart';
import 'chat_search_view.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_shortcuts.dart';
import 'chat_stream_target.dart';
import 'chat_thread_view.dart';
import 'chat_transcript.dart';
import 'chat_user_avatar.dart';
import 'chat_user_card.dart';
import 'chat_user_menu.dart';
import 'chat_user_preferences.dart';

const chatIconCatalog = PluginIconCatalog(
  owner: PluginId('chat'),
  entries: {
    'd-chat': DIcons.comment,
    'notification.chat_quoted': DIcons.quoteRight,
  },
);

/// Notification totals gate channel fetches; fetched channels gate rendering.
/// Search has its own setting.
class ChatPlugin
    implements
        SitePlugin,
        GlobalSearchPlugin,
        CookingPlugin,
        IconCatalogPlugin,
        SidebarPlugin,
        SidebarPanelPlugin,
        SidebarPanelListenablePlugin,
        ContentPlugin,
        ContentSearchPlugin,
        ContentChromePlugin,
        ContentHeaderPlugin,
        ContentHeaderLeadingPlugin,
        ContentHeaderTitleTrailingPlugin,
        ContentHeaderTitlePlugin,
        ForumTabPlugin,
        ShellHeaderPlugin,
        UserCardRecordPlugin<ChatUserCardData>,
        UserCardActionPlugin,
        CookedElementPlugin,
        ComposerTargetPlugin,
        UserMenuSectionPlugin,
        NotificationFeedPlugin,
        NotificationTypePlugin,
        NotificationCounterPlugin,
        SiteSettingsPlugin<ChatSettings>,
        CurrentUserPlugin<ChatCurrentUser>,
        UserPreferenceSectionPlugin,
        UserPreferencesPlugin,
        PluginCurrentUserFeature {
  const ChatPlugin();

  @override
  List<GlobalSearchContribution> get searchContributions => const [
    ChatGlobalSearch(),
  ];

  @override
  List<UserPreferenceCodec> get userPreferenceCodecs => const [
    ChatUserPreferenceCodec(),
  ];

  static const ComposerTargetKind messageComposerTarget = ComposerTargetKind(
    owner: PluginId('chat'),
    name: 'message',
  );
  static const ComposerUploadType messageUploadType = ComposerUploadType(
    'chat-composer',
  );
  static const String composerChannelId = 'channelId';
  static const String composerThreadId = 'threadId';
  static const PluginUserMenuSectionId notificationsSection =
      PluginUserMenuSectionId(owner: PluginId('chat'), name: 'notifications');

  static const String searchRouteId = 'chat-search';
  static const String myThreadsRouteId = 'chat-my-threads';
  static const String browseRouteId = 'chat-browse';
  static const String channelsRouteId = 'chat-channels';
  static const String starredRouteId = 'chat-starred';
  static const String directMessagesRouteId = 'chat-direct-messages';

  static String channelThreadsRouteId(int channelId) =>
      'chat-c-$channelId-threads';

  static int? channelIdFromThreadsRoute(String routeId) {
    if (routeId.length > ChatRoute.maximumRouteIdLength) return null;
    final match = RegExp(r'^chat-c-([1-9]\d*)-threads$').firstMatch(routeId);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static bool ownsRouteId(String? routeId) =>
      routeId != null &&
      (ChatRoute.parse(routeId) != null ||
          routeId == browseRouteId ||
          routeId == channelsRouteId ||
          routeId == starredRouteId ||
          routeId == directMessagesRouteId ||
          routeId == myThreadsRouteId ||
          routeId == searchRouteId ||
          channelIdFromThreadsRoute(routeId) != null);

  @override
  List<CookingProfile> get cookingProfiles => const [CookingProfile.chat];
  @override
  List<CookingModule> get cookingModules => [
    CookingModule(
      id: 'chat-source',
      owner: 'chat',
      version: '1',
      profiles: const ['chat'],
      enabledSetting: 'chat_enabled',
    ),
    CookingModule(
      id: 'chat-html-inline',
      owner: 'chat',
      version: '1',
      enabledSetting: 'chat_enabled',
    ),
    CookingModule(
      id: 'chat-transcript',
      owner: 'chat',
      version: '1',
      enabledSetting: 'chat_enabled',
    ),
    CookingModule(
      id: 'chat-slash-format',
      owner: 'chat',
      version: '1',
      profiles: const ['chat'],
      dependencies: const ['chat-source'],
      enabledSetting: 'chat_enabled',
    ),
  ];
  @override
  Map<String, Object?> projectCookingContext(CookingPluginData data) {
    final settings = data.read(chatSettingsDataKey);
    return {
      'settings': {'chat_enabled': settings?.chatEnabled ?? true},
    };
  }

  @override
  String get name => 'chat';

  @override
  PluginIconCatalog get iconCatalog => chatIconCatalog;

  @override
  List<PluginNotificationFeedSource> get notificationFeeds => const [
    chatNotificationFeed,
  ];

  @override
  List<PluginNotificationType> get notificationTypes => chatNotificationTypes;

  @override
  List<PluginNotificationCounter> get notificationCounters => const [
    chatNotificationCounter,
  ];

  @override
  ComposerTargetKind get composerTargetKind => messageComposerTarget;

  @override
  ComposerTargetPolicy createComposerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) {
    final channelId = request.data[composerChannelId];
    final threadId = request.data[composerThreadId];
    if (channelId is! int ||
        channelId <= 0 ||
        (threadId != null && (threadId is! int || threadId <= 0))) {
      throw ArgumentError.value(
        request.data,
        'request.data',
        'Invalid chat target.',
      );
    }
    return ComposerTargetPolicy(
      kind: messageComposerTarget,
      draftKey: threadId == null
          ? 'chat_$channelId'
          : 'chat_${channelId}_thread_$threadId',
      uploadType: messageUploadType,
      uploadDisposition: ComposerUploadDisposition.retainAttachment,
      uploadsEnabled: context.siteSettings.chatSettings.uploadsEnabled,
      supportsEditing: true,
      emojiUsageContext: chatEmojiUsageContext,
      mentionTopicId: null,
      validate: (state) =>
          state.raw.isNotEmpty || state.completedUploadCount > 0,
    );
  }

  @override
  List<PluginUserMenuSection> userMenuSections(PluginUserMenuContext context) =>
      context.totals?.hasChatEnabled == true &&
          context.user.hasChatEnabled != false
      ? [
          PluginUserMenuSection(
            id: notificationsSection,
            icon: DIcons.comment,
            label: 'Chat',
            badge: context.totals?.chatNotifications ?? 0,
            notificationTypes: chatNotificationFeed.filterByTypes,
            builder: (buildContext, actions) => ChatUserMenuNotifications(
              siteUrl: context.siteUrl,
              onOpened: actions.onDismiss,
            ),
          ),
        ]
      : const [];

  @override
  PluginDataPersistenceCodec<ChatSettings> get siteSettingsCodec =>
      chatSettingsPersistenceCodec;

  @override
  ChatSettings readSiteSettings(Map<String, dynamic> json, String siteUrl) =>
      ChatSettings.fromSettings(json);

  @override
  PluginDataPersistenceCodec<ChatCurrentUser> get currentUserCodec =>
      chatCurrentUserPersistenceCodec;

  @override
  ChatCurrentUser readCurrentUser(Map<String, dynamic> json, String siteUrl) =>
      ChatCurrentUser.fromCurrentUser(json);

  @override
  PluginUserPreferenceSection? userPreferenceSection(
    BuildContext context,
    PluginUserPreferenceContext preferences,
  ) => chatUserPreferenceSection(preferences);

  @override
  bool currentUserFeatureEnabled(PluginData currentUser) =>
      currentUser.chatCurrentUser?.hasChatEnabled != false;

  @override
  Widget? cookedElement(String? siteUrl, dom.Element element) =>
      chatTranscriptWidgetBuilder(element, siteUrl: siteUrl);

  @override
  PluginDataKey<ChatUserCardData> get record => chatUserCardKey;

  @override
  ChatUserCardData? readUserCard(Map<String, dynamic> json, String siteUrl) =>
      json.containsKey('can_chat_user')
      ? ChatUserCardData(canChat: json['can_chat_user'] == true)
      : null;

  @override
  List<Widget> userCardActions(
    BuildContext context,
    String siteUrl,
    UserCard user,
    VoidCallback close,
  ) => user.plugins.get(chatUserCardKey)?.canChat == true
      ? [ChatUserCardButton(siteUrl: siteUrl, user: user, close: close)]
      : const [];

  @override
  List<SidebarSection> sidebarSections(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    if (siteUrl == null) return const [];
    final chat = PluginUiScope.require(context, chatControllerService);

    final chatAvailable = shell.chatAvailable(siteUrl);
    final authenticatedChatAvailable =
        chatAvailable && shell.currentUser != null;
    final publicChannelsEnabled =
        chatAvailable &&
        chat.siteConfigFor(siteUrl).chatSettings.publicChannelsEnabled;
    final actions = _panelActions(shell, siteUrl);

    return [
      if (authenticatedChatAvailable ||
          (publicChannelsEnabled && chat.publicChannels(siteUrl).isNotEmpty))
        SidebarSection(
          id: 'chat-inbox',
          title: 'Conversations',
          showHeader: false,
          collapsible: false,
          // The footer draws this action; the section still owns its
          // keyboard shortcut, which the shell reads from every section.
          actionIcon: actions.startMessage ? DIcons.plus : null,
          actionLabel: actions.startMessage ? 'Start a message' : null,
          actionShortcut: actions.startMessage
              ? newDirectMessageShortcutForPlatform(Theme.of(context).platform)
              : null,
          onAction: actions.startMessage
              ? () => _startMessage(context, shell, siteUrl)
              : null,
          bodyBuilder: (_) =>
              ChatSidebarInbox(key: ValueKey(siteUrl), siteUrl: siteUrl),
          destinations: [
            for (final channel in chatInboxConversations(
              chat,
              siteUrl,
              const ChatInboxFilter(),
            ))
              destination(
                channel,
                siteUrl: siteUrl,
                onTap: () => shell.openChannel(channel.id),
              ),
          ],
        ),
    ];
  }

  @override
  SidebarPanelContribution? sidebarPanel(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    if (siteUrl == null) return null;

    if (!shell.chatAvailable(siteUrl)) return null;

    final unreadCount = shell.chat.unreadMessageCount(siteUrl);
    final actions = _panelActions(shell, siteUrl);
    return SidebarPanelContribution(
      label: 'Chat',
      mobileBuilder: (_) =>
          ChatMobileSidebar(key: ValueKey(siteUrl), siteUrl: siteUrl),
      mobileAction: actions.startMessage
          ? SidebarPanelAction(
              label: 'Start a message',
              icon: DIcons.plus,
              onPressed: () => _startMessage(context, shell, siteUrl),
            )
          : null,
      footerBuilder: actions.startMessage || actions.browse || actions.myThreads
          ? (context) => ChatSidebarFooter(
              browse: actions.browse,
              myThreads: actions.myThreads,
              onStartMessage: actions.startMessage
                  ? () => _startMessage(context, shell, siteUrl)
                  : null,
              startMessageShortcut: newDirectMessageShortcutForPlatform(
                Theme.of(context).platform,
              ),
            )
          : null,
      badge: unreadCount > 0
          ? DBadge(
              key: const ValueKey('chat-sidebar-unread-badge'),
              size: DBadgeSize.compact,
              backgroundColor: Theme.of(context).discourse.success,
              foregroundColor: Theme.of(
                context,
              ).discourse.notificationForeground,
              semanticLabel:
                  '$unreadCount unread ${unreadCount == 1 ? 'message' : 'messages'}',
              child: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
            )
          : null,
      icon: DIcons.comment,
      active: ownsRouteId(shell.currentContent?.id),
      separateWhenActive: true,
      includeSectionsWhenInactive: false,
      showSwitch: true,
      onOpen: () => unawaited(shell.openShortcut()),
      onClose: shell.closeSidebarPanel,
    );
  }

  static ({bool browse, bool myThreads, bool startMessage}) _panelActions(
    ChatShellService shell,
    String siteUrl,
  ) {
    final user = shell.currentUser;
    if (user == null || !shell.chatAvailable(siteUrl)) {
      return (browse: false, myThreads: false, startMessage: false);
    }
    final settings = shell.chat.siteConfigFor(siteUrl).chatSettings;
    return (
      browse: settings.publicChannelsEnabled,
      myThreads: settings.threadsEnabled && shell.chat.hasThreads(siteUrl),
      startMessage: user.staff || user.canDirectMessage == true,
    );
  }

  static void _startMessage(
    BuildContext context,
    ChatShellService shell,
    String siteUrl,
  ) => unawaited(
    showChatNewDirectMessageDialog(
      context: context,
      siteUrl: siteUrl,
      chat: shell.chat,
      shell: shell,
    ),
  );

  @override
  Listenable sidebarPanelListenable(BuildContext context) => Listenable.merge([
    PluginUiScope.require(context, chatShellService),
    PluginUiScope.require(context, chatControllerService),
  ]);

  @override
  Listenable sidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, chatControllerService);

  @override
  SidebarDestination? forumTabDestination(
    BuildContext context,
    String siteUrl,
    ForumTab tab,
  ) {
    final route = ChatRoute.parse(tab.currentContent.id);
    if (route == null) return null;
    final channel = PluginUiScope.require(
      context,
      chatControllerService,
    ).channel(siteUrl, route.channelId);
    return channel == null ? null : destination(channel, siteUrl: siteUrl);
  }

  @override
  Listenable forumTabListenable(BuildContext context, String siteUrl) =>
      PluginUiScope.require(context, chatControllerService);

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final shell = PluginUiScope.require(context, chatShellService);
    final listKind = switch (route.id) {
      channelsRouteId => ChatChannelListKind.channels,
      starredRouteId => ChatChannelListKind.starred,
      directMessagesRouteId => ChatChannelListKind.directMessages,
      _ => null,
    };
    if (listKind != null) {
      final siteUrl = shell.currentSiteUrl;
      final available =
          siteUrl != null &&
          shell.isConnected(siteUrl) &&
          shell.currentUser?.hasChatEnabled != false &&
          shell.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat channels are not available.'))
          : ChatChannelsView(
              key: ValueKey((siteUrl, listKind)),
              siteUrl: siteUrl,
              kind: listKind,
            );
    }
    if (route.id == browseRouteId) {
      final siteUrl = shell.currentSiteUrl;
      final available =
          siteUrl != null &&
          shell.isConnected(siteUrl) &&
          shell.chat
              .siteConfigFor(siteUrl)
              .chatSettings
              .publicChannelsEnabled &&
          shell.currentUser?.hasChatEnabled != false &&
          shell.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat channels are not available.'))
          : ChatBrowseChannelsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (channelIdFromThreadsRoute(route.id) case final channelId?) {
      final siteUrl = shell.currentSiteUrl;
      final chat = PluginUiScope.require(context, chatControllerService);
      final available =
          siteUrl != null &&
          shell.isConnected(siteUrl) &&
          shell.currentUser?.hasChatEnabled != false &&
          shell.currentTotals?.hasChatEnabled == true &&
          chat.siteConfigFor(siteUrl).chatSettings.threadsEnabled &&
          chat.channel(siteUrl, channelId)?.threadingEnabled == true;
      return !available
          ? const Center(child: Text('Threads are not available.'))
          : ChatChannelThreadsView(
              key: ValueKey((siteUrl, channelId)),
              siteUrl: siteUrl,
              channelId: channelId,
            );
    }
    if (route.id == myThreadsRouteId) {
      final siteUrl = shell.currentSiteUrl;
      final available =
          siteUrl != null &&
          shell.isConnected(siteUrl) &&
          shell.chat.siteConfigFor(siteUrl).chatSettings.threadsEnabled &&
          shell.currentUser?.hasChatEnabled != false &&
          shell.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat threads are not available.'))
          : ChatMyThreadsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (route.id == searchRouteId) {
      final siteUrl = shell.currentSiteUrl;
      final available =
          siteUrl != null &&
          shell.isConnected(siteUrl) &&
          shell.chat.siteConfigFor(siteUrl).chatSearchEnabled == true &&
          shell.currentUser?.hasChatEnabled != false &&
          shell.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat search is not available.'))
          : ChatSearchView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    final chatRoute = ChatRoute.parse(route.id);
    if (chatRoute == null) return null;
    if (chatRoute.isInfo) {
      final siteUrl = shell.currentSiteUrl;
      if (siteUrl == null) return const SizedBox.shrink();
      return ChatChannelInfoView(
        key: ValueKey((siteUrl, chatRoute.channelId, chatRoute.infoTab)),
        siteUrl: siteUrl,
        channelId: chatRoute.channelId,
        tab: chatRoute.infoTab!,
        chat: PluginUiScope.require(context, chatControllerService),
      );
    }
    return chatRoute.isThread
        ? ChatThreadWorkspace(
            key: ValueKey((shell.currentSiteUrl, route.id)),
            route: chatRoute,
          )
        : ChatChannelView(channelId: chatRoute.channelId);
  }

  @override
  GlobalSearchContext? contentSearchContext(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    if (!shell.fullPageChatActive) return null;
    final siteUrl = shell.currentSiteUrl;
    final available =
        siteUrl != null &&
        shell.isConnected(siteUrl) &&
        shell.chat.siteConfigFor(siteUrl).chatSearchEnabled == true &&
        shell.currentUser?.hasChatEnabled != false &&
        shell.currentTotals?.hasChatEnabled == true;
    if (!available) return null;

    final route = shell.currentContent;
    final channelId = route == null
        ? null
        : ChatRoute.parse(route.id)?.channelId;
    return GlobalSearchContext(
      scope: chatSearchScope,
      condition: channelId == null
          ? null
          : GlobalSearchCondition(
              filterId: 'chatChannel',
              value: ['$channelId'],
            ),
      label: channelId == null
          ? null
          : shell.chat.channel(siteUrl, channelId)?.title,
    );
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      ChatRoute.parse(route.id)?.isThread ?? false;

  @override
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    if (siteUrl == null || chatRoute == null) {
      return const [];
    }
    if (chatRoute.isThread) {
      final target = ChatThreadTarget(
        channelId: chatRoute.channelId,
        threadId: chatRoute.threadId!,
      );
      return [
        ChatThreadNotificationButton(siteUrl: siteUrl, target: target),
        ChatThreadSettingsButton(siteUrl: siteUrl, target: target),
      ];
    }
    return const [];
  }

  @override
  Widget? contentHeaderLeading(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final siteUrl = PluginUiScope.require(
      context,
      chatShellService,
    ).currentSiteUrl;
    if (siteUrl == null || chatRoute == null) return null;
    if (chatRoute.isThread) {
      return const DIcon(DIcons.comments, size: 18);
    }

    final chat = PluginUiScope.require(context, chatControllerService);
    final channel = chat.channel(siteUrl, chatRoute.channelId);
    if (channel == null ||
        channel.avatarUrl == null ||
        channel.users.length != 1) {
      return null;
    }

    return _ChatChannelHeaderAvatar(
      siteUrl: siteUrl,
      channelId: channel.id,
      fallbackIcon: route.icon,
    );
  }

  @override
  Widget? contentHeaderTitleTrailing(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final siteUrl = PluginUiScope.require(
      context,
      chatShellService,
    ).currentSiteUrl;
    if (siteUrl == null ||
        chatRoute == null ||
        chatRoute.isThread ||
        chatRoute.isInfo) {
      return null;
    }

    return _ChatChannelHeaderTrailing(
      siteUrl: siteUrl,
      channelId: chatRoute.channelId,
    );
  }

  @override
  VoidCallback? contentHeaderTitleAction(
    BuildContext context,
    ContentRoute route,
  ) {
    final chatRoute = ChatRoute.parse(route.id);
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    if (siteUrl == null ||
        chatRoute == null ||
        chatRoute.isThread ||
        chatRoute.isInfo) {
      return null;
    }
    return () =>
        shell.openChannelInfo(siteUrl: siteUrl, channelId: chatRoute.channelId);
  }

  @override
  List<Widget> shellHeaderActions(
    BuildContext context, {
    required PluginHeaderSurface surface,
    required bool compact,
    Color? ringColor,
  }) => [
    ChatHeaderButton(
      hideWhenChatActive: surface == PluginHeaderSurface.content && compact,
      ringColor: ringColor,
    ),
  ];

  static SidebarDestination destination(
    ChatChannel channel, {
    String? siteUrl,
    VoidCallback? onTap,
  }) {
    final directUser = channel.isDirectMessage && channel.users.length == 1
        ? channel.users.first
        : null;
    final avatarUrl = channel.avatarUrl;
    final status = directUser?.status;
    return SidebarDestination(
      id: ChatRoute.channel(channel.id).routeId,
      label: channel.title,
      icon: switch (channel.kind) {
        ChatChannelKind.directMessage when channel.users.length > 1 =>
          DIcons.users,
        ChatChannelKind.directMessage => DIcons.user,
        _ => DIcons.comment,
      },
      emoji: channel.emoji,
      avatarUrl: avatarUrl,
      prefixBuilder: siteUrl == null || directUser == null || avatarUrl == null
          ? null
          : (context, size) => ChatUserAvatar(
              siteUrl: siteUrl,
              userId: directUser.id,
              url: avatarUrl,
              size: size,
              fallback: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
      labelSuffixBuilder: siteUrl == null || status == null
          ? null
          : (context, size) => UserStatusMessage(
              siteUrl: siteUrl,
              userId: directUser!.id,
              status: status,
              size: size,
              leadingGap: size <= 13 ? 4 : 5,
            ),
      semanticDescription: status?.description,
      iconColor: channel.categoryColor,
      prefixBadgeIcon: channel.isCategoryChannel && channel.readRestricted
          ? DIcons.lock
          : null,
      badge: channel.badge,
      unreadCount: channel.tracking.unreadCount,
      preview: channel.lastMessagePreview,
      lastActivityAt: channel.lastMessageAt,
      onTap: onTap,
      contextMenuBuilder: siteUrl == null
          ? null
          : (context, child) => ChatChannelMenu(
              siteUrl: siteUrl,
              channelId: channel.id,
              child: child,
            ),
    );
  }
}

class _ChatChannelHeaderTrailing extends StatelessWidget {
  const _ChatChannelHeaderTrailing({
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ChatChannelStarButton(
        siteUrl: siteUrl,
        channelId: channelId,
        size: DButtonSize.large,
      ),
      _ChatChannelHeaderStatus(siteUrl: siteUrl, channelId: channelId),
    ],
  );
}

class _ChatChannelHeaderStatus extends StatelessWidget {
  const _ChatChannelHeaderStatus({
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        final user =
            channel?.isDirectMessage == true && channel!.users.length == 1
            ? channel.users.single
            : null;
        return UserStatusMessage(
          key: const ValueKey('chat-channel-header-status'),
          siteUrl: siteUrl,
          userId: user?.id,
          status: user?.status,
          size: 16,
          leadingGap: 5,
        );
      },
    );
  }
}

class _ChatChannelHeaderAvatar extends StatelessWidget {
  const _ChatChannelHeaderAvatar({
    required this.siteUrl,
    required this.channelId,
    required this.fallbackIcon,
  });

  final String siteUrl;
  final int channelId;
  final DIconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        final user = channel != null && channel.users.length == 1
            ? channel.users.single
            : null;
        if (channel?.isDirectMessage != true || user?.avatarUrl == null) {
          return DIcon(
            fallbackIcon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
        }
        return ChatUserAvatar(
          siteUrl: siteUrl,
          userId: user!.id,
          url: user.avatarUrl,
          size: 18,
          fallback: DIcon(
            DIcons.user,
            size: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        );
      },
    );
  }
}
