import 'dart:async';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../models/composer_upload.dart';
import '../../models/content_route.dart';
import '../../models/forum_workspace.dart';
import '../../models/sidebar.dart';
import '../../models/user_card.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_scope.dart';
import '../../plugin_api/site_plugin_api.dart';
import '../../shell/composer_controller.dart';
import '../../shell/shell_scope.dart';
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

/// Chat's legacy sidebar icon alias. The glyph remains a neutral core asset;
/// only the plugin-specific `d-chat` meaning belongs to Chat.
const chatIconCatalog = PluginIconCatalog(
  owner: PluginId('chat'),
  entries: {'d-chat': DIcons.comment},
);

/// `chat`, as this app knows it.
///
/// The plugin gives a site channels and direct messages to read alongside its
/// topics. It is the first optional feature here that owns *navigation* and a
/// *screen* rather than decorating a record, so it implements [SidebarPlugin]
/// and [ContentPlugin] without pretending to have a post-record capability.
///
/// ## It cannot use the enablement rule the rest of this interface turns on
///
/// A post arrives whether or not the reader cares about reactions, so its
/// payload can be the gate: an absent key means the site does not have the
/// feature. A channel list arrives only if you ask for it, so its absence
/// proves nothing at all — a site without chat and a site nobody asked look
/// exactly alike.
///
/// The nearest thing to the rule is `chat_notifications` on
/// `/notifications/totals.json`, which this app already fetches for every
/// connected site on launch. It is serialized only when the site has chat, this
/// reader may use it, and they have not switched it off — three questions
/// answered by one absent key, scoped by the same guardian that decided the
/// rest of the payload. `ShellController._refreshOne` reads it, and it decides
/// only whether to **ask**. What comes back still decides whether to **draw**
/// channel sections: they exist because there are channels. Search is a
/// separate endpoint and uses its own explicit client setting so an older site
/// that has Chat but not search is never probed.
///
/// Which is also why there is no loading state and no empty heading. A heading
/// that appears and then vanishes is worse than one that arrives late, and a
/// section with a spinner in it says something false about how many channels
/// there are.
class ChatPlugin
    implements
        SitePlugin,
        IconCatalogPlugin,
        SidebarPlugin,
        ContentPlugin,
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
        PluginCurrentUserFeature,
        ComposerUploadPolicyPlugin {
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
      uploadsEnabled: context.config.chatUploadsEnabled,
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
  bool allowsComposerUploads(PluginData siteSettings, {required bool isChat}) =>
      !isChat || siteSettings.chatSettings.uploadsEnabled;

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
    final controller = ShellScope.read(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return const [];
    final chat = PluginScope.require(context, chatControllerService);

    final starred = chat.starredChannels(siteUrl);
    final public = chat.unstarredPublicChannels(siteUrl);
    final direct = chat.unstarredDirectChannels(siteUrl);
    final chatAvailable =
        controller.currentInstance?.isConnected == true &&
        controller.currentInstance?.user?.hasChatEnabled != false &&
        controller.currentTotals?.hasChatEnabled == true;
    final searchEnabled =
        chatAvailable &&
        controller.currentInstance?.config.chatSearchEnabled == true;
    final myThreadsEnabled = chatAvailable && chat.hasThreads(siteUrl);

    // Nothing before the answer, and nothing after an answer with no channels
    // in it. A heading with no rows under it says something that is not true.
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
      if (direct.isNotEmpty)
        SidebarSection(
          id: 'direct-messages',
          title: 'Direct messages',
          destinations: [
            for (final channel in direct)
              destination(channel, siteUrl: siteUrl),
          ],
        ),
    ];
  }

  @override
  Listenable sidebarListenable(BuildContext context) =>
      PluginScope.require(context, chatControllerService);

  @override
  SidebarDestination? forumTabDestination(
    BuildContext context,
    String siteUrl,
    ForumTab tab,
  ) {
    final route = ChatRoute.parse(tab.currentContent.id);
    if (route == null) return null;
    final channel = PluginScope.require(
      context,
      chatControllerService,
    ).channel(siteUrl, route.channelId);
    return channel == null ? null : destination(channel, siteUrl: siteUrl);
  }

  @override
  Listenable forumTabListenable(BuildContext context, String siteUrl) =>
      PluginScope.require(context, chatControllerService);

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    if (route.id == browseRouteId) {
      final controller = ShellScope.read(context);
      final instance = controller.currentInstance;
      final siteUrl = instance?.url;
      final available =
          instance?.isConnected == true &&
          instance?.user?.hasChatEnabled != false &&
          controller.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat channels are not available.'))
          : ChatBrowseChannelsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (channelIdFromThreadsRoute(route.id) case final channelId?) {
      final controller = ShellScope.read(context);
      final instance = controller.currentInstance;
      final siteUrl = instance?.url;
      final chat = PluginScope.require(context, chatControllerService);
      final available =
          instance?.isConnected == true &&
          instance?.user?.hasChatEnabled != false &&
          controller.currentTotals?.hasChatEnabled == true &&
          siteUrl != null &&
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
      final controller = ShellScope.read(context);
      final instance = controller.currentInstance;
      final siteUrl = instance?.url;
      final available =
          instance?.isConnected == true &&
          instance?.user?.hasChatEnabled != false &&
          controller.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat threads are not available.'))
          : ChatMyThreadsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (route.id == searchRouteId) {
      final controller = ShellScope.read(context);
      final instance = controller.currentInstance;
      final siteUrl = instance?.url;
      final available =
          instance?.isConnected == true &&
          instance?.config.chatSearchEnabled == true &&
          instance?.user?.hasChatEnabled != false &&
          controller.currentTotals?.hasChatEnabled == true;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !available
          ? const Center(child: Text('Chat search is not available.'))
          : ChatSearchView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    final chatRoute = ChatRoute.parse(route.id);
    if (chatRoute == null) return null;
    if (chatRoute.isInfo) {
      final siteUrl = ShellScope.read(context).currentInstance?.url;
      if (siteUrl == null) return const SizedBox.shrink();
      return ChatChannelInfoView(
        key: ValueKey((siteUrl, chatRoute.channelId, chatRoute.infoTab)),
        siteUrl: siteUrl,
        channelId: chatRoute.channelId,
        tab: chatRoute.infoTab!,
        chat: PluginScope.require(context, chatControllerService),
      );
    }
    return chatRoute.isThread
        ? ChatThreadWorkspace(route: chatRoute)
        : ChatChannelView(channelId: chatRoute.channelId);
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      ChatRoute.parse(route.id)?.isThread ?? false;

  @override
  List<Widget> contentHeaderActions(BuildContext context, ContentRoute route) {
    final chatRoute = ChatRoute.parse(route.id);
    final siteUrl = ShellScope.read(context).currentInstance?.url;
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
    final siteUrl = ShellScope.read(context).currentInstance?.url;
    if (siteUrl == null || chatRoute == null || chatRoute.isThread) return null;

    final chat = PluginScope.require(context, chatControllerService);
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
    final shell = ShellScope.read(context);
    final chatShell = PluginScope.require(context, chatShellService);
    final siteUrl = shell.currentInstance?.url;
    if (siteUrl == null ||
        chatRoute == null ||
        chatRoute.isThread ||
        chatRoute.isInfo) {
      return null;
    }
    return () => chatShell.openChannelInfo(
      siteUrl: siteUrl,
      channelId: chatRoute.channelId,
    );
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

  /// One channel as a sidebar row.
  ///
  /// A conversation with one other person shows their face; a group shows the
  /// glyph for several people; a channel shows its emoji, or `comment` — which
  /// is what Discourse's own `d-chat` resolves to — tinted with the colour of
  /// the category it lives in.
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
    final chat = PluginScope.require(context, chatControllerService);
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
    final chat = PluginScope.require(context, chatControllerService);
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
    final chat = PluginScope.require(context, chatControllerService);
    return ValueListenableBuilder<ChatChannel?>(
      valueListenable: chat.channelRef(siteUrl, channelId),
      builder: (context, channel, _) {
        if (channel?.threadingEnabled != true) {
          return const SizedBox.shrink();
        }
        final unread = channel!.unreadThreadCount;
        return DButton.iconOnly(
          key: const ValueKey('chat-channel-threads-button'),
          onPressed: () => PluginScope.require(
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
