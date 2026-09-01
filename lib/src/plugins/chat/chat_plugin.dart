import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../models/composer_upload.dart';
import '../../models/content_route.dart';
import '../../models/forum_workspace.dart';
import '../../models/sidebar.dart';
import '../../models/user_card.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/composer_controller.dart';
import '../../shell/user_status.dart';
import '../../theme/d_button.dart';
import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import 'chat_browse_channels_view.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_channel_info_view.dart';
import 'chat_channel_search.dart';
import 'chat_channel_star_button.dart';
import 'chat_channel_threads_view.dart';
import 'chat_channel_view.dart';
import 'chat_drawer.dart';
import 'chat_emoji_usage.dart';
import 'chat_header_button.dart';
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
import 'chat_stream_target.dart';
import 'chat_thread_view.dart';
import 'chat_transcript.dart';
import 'chat_user_avatar.dart';
import 'chat_user_card.dart';
import 'chat_user_menu.dart';

const chatIconCatalog = PluginIconCatalog(
  owner: PluginId('chat'),
  entries: {'d-chat': DIcons.comment},
);

/// Notification totals gate channel fetches; fetched channels gate rendering.
/// Search has its own setting.
class ChatPlugin
    implements
        SitePlugin,
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
        ShellOverlayPlugin,
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
        PluginCurrentUserFeature {
  const ChatPlugin();

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
    final match = RegExp(r'^chat-c-([1-9]\d*)-threads$').firstMatch(routeId);
    return match == null ? null : int.parse(match.group(1)!);
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

    final starred = chat.starredChannels(siteUrl);
    final public = chat.unstarredPublicChannels(siteUrl);
    final direct = chat.unstarredDirectChannels(siteUrl);
    final settings = chat.siteConfigFor(siteUrl).chatSettings;
    final chatAvailable = shell.chatAvailable(siteUrl);
    final authenticatedChatAvailable =
        chatAvailable && shell.currentUser != null;
    final publicChannelsEnabled =
        chatAvailable && settings.publicChannelsEnabled;
    final searchEnabled = authenticatedChatAvailable && settings.searchEnabled;
    final myThreadsEnabled =
        authenticatedChatAvailable &&
        settings.threadsEnabled &&
        chat.hasThreads(siteUrl);
    final canCreateDirectMessage =
        authenticatedChatAvailable &&
        (shell.currentUser?.staff == true ||
            shell.currentUser?.canDirectMessage == true);

    return [
      if (authenticatedChatAvailable && settings.publicChannelsEnabled)
        SidebarSection(
          id: 'chat-browse',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: browseRouteId,
              label: 'Browse channels',
              icon: DIcons.list,
              onTap: shell.openBrowseChannels,
            ),
          ],
        ),
      if (myThreadsEnabled)
        SidebarSection(
          id: 'chat-my-threads',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: myThreadsRouteId,
              label: 'My threads',
              icon: DIcons.comments,
              onTap: shell.openMyThreads,
            ),
          ],
        ),
      if (searchEnabled)
        SidebarSection(
          id: 'chat-search',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: searchRouteId,
              label: 'Search',
              icon: DIcons.magnifyingGlass,
              onTap: shell.openSearch,
            ),
          ],
        ),
      if (authenticatedChatAvailable && starred.isNotEmpty)
        SidebarSection(
          id: 'chat-starred-channels',
          title: 'Starred channels',
          destinations: [
            for (final channel in starred)
              destination(
                channel,
                siteUrl: siteUrl,
                onTap: () => shell.openChannel(channel.id),
              ),
          ],
        ),
      if (publicChannelsEnabled && public.isNotEmpty)
        SidebarSection(
          id: 'chat',
          title: 'Chat',
          destinations: [
            for (final channel in public)
              destination(
                channel,
                siteUrl: siteUrl,
                onTap: () => shell.openChannel(channel.id),
              ),
          ],
        ),
      if (authenticatedChatAvailable &&
          chat.channelsLoaded(siteUrl) &&
          (direct.isNotEmpty || canCreateDirectMessage))
        SidebarSection(
          id: 'direct-messages',
          title: 'Direct messages',
          actionIcon: canCreateDirectMessage ? DIcons.plus : null,
          actionLabel: canCreateDirectMessage ? 'Start a direct message' : null,
          onAction: canCreateDirectMessage
              ? () => unawaited(
                  showChatNewDirectMessageDialog(
                    context: context,
                    siteUrl: siteUrl,
                    chat: chat,
                    shell: shell,
                  ),
                )
              : null,
          destinations: [
            for (final channel in direct)
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

    final active = ownsRouteId(shell.currentContent?.id);
    final available = shell.chatAvailable(siteUrl);
    if (!available && !active) return null;

    final mode = shell.separateSidebarMode;
    final anonymous = shell.currentUser == null;
    return SidebarPanelContribution(
      label: 'Chat',
      icon: DIcons.comment,
      active: active,
      separateWhenActive: shell.drawerActive
          ? mode == ChatSeparateSidebarMode.always
          : mode != ChatSeparateSidebarMode.never,
      // Anonymous visitors have no panel controls, so core leaves their Chat
      // sections in the forum panel until they enter full-page Chat.
      includeSectionsWhenInactive:
          anonymous || mode != ChatSeparateSidebarMode.always,
      showSwitch:
          !anonymous &&
          mode != ChatSeparateSidebarMode.never &&
          !shell.drawerActive,
      selectedDestinationId: shell.drawerExpanded
          ? _drawerSidebarDestinationId(shell.drawerCurrentContent?.id)
          : null,
      onOpen: () => unawaited(shell.openShortcut()),
      onClose: shell.closeSidebarPanel,
    );
  }

  static String? _drawerSidebarDestinationId(String? routeId) {
    if (routeId == null) return null;
    if (ChatRoute.parse(routeId) case final route?) {
      return ChatRoute.channel(route.channelId).routeId;
    }
    if (channelIdFromThreadsRoute(routeId) case final channelId?) {
      return ChatRoute.channel(channelId).routeId;
    }
    return routeId;
  }

  @override
  Listenable sidebarPanelListenable(BuildContext context) =>
      PluginUiScope.require(context, chatShellService);

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
    final drawerListKind = switch (route.id) {
      channelsRouteId => ChatDrawerChannelListKind.channels,
      starredRouteId => ChatDrawerChannelListKind.starred,
      directMessagesRouteId => ChatDrawerChannelListKind.directMessages,
      _ => null,
    };
    if (drawerListKind != null) {
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
          : ChatDrawerChannelsView(
              key: ValueKey((siteUrl, drawerListKind)),
              siteUrl: siteUrl,
              kind: drawerListKind,
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
            showHeader: !ChatDrawerScope.isDrawer(context),
          )
        : ChatChannelView(channelId: chatRoute.channelId);
  }

  @override
  bool ownsContentSearch(BuildContext context, ContentRoute route) {
    return ownsRouteId(route.id);
  }

  @override
  VoidCallback? contentSearchAction(BuildContext context, ContentRoute route) {
    if (!ownsContentSearch(context, route)) return null;
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    final available =
        siteUrl != null &&
        shell.isConnected(siteUrl) &&
        shell.chat.siteConfigFor(siteUrl).chatSearchEnabled == true &&
        shell.currentUser?.hasChatEnabled != false &&
        shell.currentTotals?.hasChatEnabled == true;
    if (!available) return null;

    final search = PluginUiScope.require(context, chatSearchControllerService);
    return () {
      shell.openSearch();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        search.requestGlobalFocus(siteUrl);
      });
    };
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      ChatRoute.parse(route.id)?.isThread ?? false;

  @override
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final shell = PluginUiScope.require(context, chatShellService);
    final siteUrl = shell.currentSiteUrl;
    final fullPageAction = shell.fullPageChatActive && shell.drawerAvailable
        ? DButton.iconOnly(
            key: const ValueKey('chat-close-full-page'),
            tooltip: 'Close full-screen chat',
            onPressed: () => unawaited(shell.openDrawerFromFullPage()),
            variant: DButtonVariant.flat,
            icon: const DIcon(DIcons.discourseCompress, size: 18),
          )
        : null;
    if (siteUrl == null || chatRoute == null) {
      return fullPageAction == null ? const [] : [fullPageAction];
    }
    if (chatRoute.isThread) {
      final target = ChatThreadTarget(
        channelId: chatRoute.channelId,
        threadId: chatRoute.threadId!,
      );
      return [
        ChatThreadNotificationButton(siteUrl: siteUrl, target: target),
        ChatThreadSettingsButton(siteUrl: siteUrl, target: target),
        ?fullPageAction,
      ];
    }
    if (chatRoute.isInfo) {
      return fullPageAction == null ? const [] : [fullPageAction];
    }
    return [
      ChatChannelSearchButton(siteUrl: siteUrl, channelId: chatRoute.channelId),
      ?fullPageAction,
    ];
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

  @override
  List<Widget> shellOverlays(BuildContext context) => [
    ChatDrawerOverlay(
      contentBuilder: (context, route) =>
          content(context, route) ?? const SizedBox.shrink(),
      headerActionsBuilder: contentHeaderActions,
      headerLeadingBuilder: contentHeaderLeading,
      headerTitleTrailingBuilder: contentHeaderTitleTrailing,
      headerTitleActionBuilder: contentHeaderTitleAction,
      showFooterForRoute: (route) => const {
        channelsRouteId,
        starredRouteId,
        directMessagesRouteId,
        myThreadsRouteId,
        searchRouteId,
      }.contains(route.id),
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
      onTap: onTap,
      hoverActionBuilder: siteUrl == null
          ? null
          : (context) =>
                ChatChannelMenuButton(siteUrl: siteUrl, channelId: channel.id),
      onLongPress: siteUrl == null
          ? null
          : (context) => unawaited(
              ChatChannelMenuButton.showSheet(
                context: context,
                siteUrl: siteUrl,
                channelId: channel.id,
              ),
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
        size: DButtonSize.small,
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
