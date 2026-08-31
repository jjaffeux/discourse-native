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
import 'chat_emoji_usage.dart';
import 'chat_header_button.dart';
import 'chat_my_threads_view.dart';
import 'chat_new_direct_message.dart';
import 'chat_notification_counter.dart';
import 'chat_notifications.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_search_view.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
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
        ContentPlugin,
        ContentSearchPlugin,
        ContentChromePlugin,
        ContentHeaderPlugin,
        ContentHeaderLeadingPlugin,
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

  static String channelThreadsRouteId(int channelId) =>
      'chat-c-$channelId-threads';

  static int? channelIdFromThreadsRoute(String routeId) {
    final match = RegExp(r'^chat-c-([1-9]\d*)-threads$').firstMatch(routeId);
    return match == null ? null : int.parse(match.group(1)!);
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
    final chatAvailable =
        shell.isConnected(siteUrl) &&
        shell.currentUser?.hasChatEnabled != false &&
        shell.currentTotals?.hasChatEnabled == true;
    final searchEnabled =
        chatAvailable && chat.siteConfigFor(siteUrl).chatSearchEnabled == true;
    final myThreadsEnabled = chatAvailable && chat.hasThreads(siteUrl);
    final canCreateDirectMessage =
        chatAvailable &&
        (shell.currentUser?.staff == true ||
            shell.currentUser?.canDirectMessage == true);

    return [
      if (chatAvailable)
        const SidebarSection(
          id: 'chat-browse',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: browseRouteId,
              label: 'Browse channels',
              icon: DIcons.list,
            ),
          ],
        ),
      if (myThreadsEnabled)
        const SidebarSection(
          id: 'chat-my-threads',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: myThreadsRouteId,
              label: 'My threads',
              icon: DIcons.comments,
            ),
          ],
        ),
      if (searchEnabled)
        const SidebarSection(
          id: 'chat-search',
          title: '',
          showHeader: false,
          collapsible: false,
          destinations: [
            SidebarDestination(
              id: searchRouteId,
              label: 'Search',
              icon: DIcons.magnifyingGlass,
            ),
          ],
        ),
      if (starred.isNotEmpty)
        SidebarSection(
          id: 'chat-starred-channels',
          title: 'Starred channels',
          destinations: [
            for (final channel in starred)
              destination(channel, siteUrl: siteUrl),
          ],
        ),
      if (public.isNotEmpty)
        SidebarSection(
          id: 'chat',
          title: 'Chat',
          destinations: [
            for (final channel in public)
              destination(channel, siteUrl: siteUrl),
          ],
        ),
      if (chat.channelsLoaded(siteUrl) &&
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
              destination(channel, siteUrl: siteUrl),
          ],
        ),
    ];
  }

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
    if (route.id == browseRouteId) {
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
        ? ChatThreadWorkspace(route: chatRoute)
        : ChatChannelView(channelId: chatRoute.channelId);
  }

  @override
  bool ownsContentSearch(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    return chatRoute != null ||
        route.id == browseRouteId ||
        route.id == myThreadsRouteId ||
        route.id == searchRouteId ||
        channelIdFromThreadsRoute(route.id) != null;
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
    final siteUrl = PluginUiScope.require(
      context,
      chatShellService,
    ).currentSiteUrl;
    if (siteUrl == null || chatRoute == null || chatRoute.isThread) {
      return const [];
    }
    if (chatRoute.isInfo) {
      return [
        ChatChannelStarButton(siteUrl: siteUrl, channelId: chatRoute.channelId),
      ];
    }
    return [
      _ChatChannelHeaderStatus(
        siteUrl: siteUrl,
        channelId: chatRoute.channelId,
      ),
      ChatChannelStarButton(siteUrl: siteUrl, channelId: chatRoute.channelId),
      _ChatChannelThreadsButton(
        siteUrl: siteUrl,
        channelId: chatRoute.channelId,
      ),
      ChatChannelSearchButton(siteUrl: siteUrl, channelId: chatRoute.channelId),
    ];
  }

  @override
  Widget? contentHeaderLeading(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final siteUrl = PluginUiScope.require(
      context,
      chatShellService,
    ).currentSiteUrl;
    if (siteUrl == null || chatRoute == null || chatRoute.isThread) return null;

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
          siteUrl: siteUrl,
          userId: user?.id,
          status: user?.status,
          showDescription: true,
          size: 16,
          style: Theme.of(context).textTheme.bodySmall,
          descriptionMaxWidth: 100,
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

class _ChatChannelThreadsButton extends StatelessWidget {
  const _ChatChannelThreadsButton({
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
        if (channel?.threadingEnabled != true) {
          return const SizedBox.shrink();
        }
        final unread = channel!.unreadThreadCount;
        return DButton.iconOnly(
          key: const ValueKey('chat-channel-threads-button'),
          onPressed: () => PluginUiScope.require(
            context,
            chatShellService,
          ).openChannelThreads(siteUrl: siteUrl, channelId: channelId),
          variant: DButtonVariant.flat,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const DIcon(DIcons.comments, size: 18),
          ),
          tooltip: 'Threads',
        );
      },
    );
  }
}
