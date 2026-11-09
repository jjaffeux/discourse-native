import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import 'chat_browse_channels_view.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_channel_destination.dart';
import 'chat_channel_info_view.dart';
import 'chat_channel_star_button.dart';
import 'chat_channel_threads_view.dart';
import 'chat_channel_view.dart';
import 'chat_channels_view.dart';
import 'chat_composer_target.dart';
import 'chat_controller.dart';
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
        MobileNavigationPlugin,
        HomepagePlugin,
        SidebarPanelPlugin,
        SidebarPanelListenablePlugin,
        ContentPlugin,
        ContentSearchPlugin,
        ContentChromePlugin,
        ContentMobilePageSheetPlugin,
        ContentMobileComposerPlugin,
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
  String get homepageId => 'chat';

  @override
  ContentRoute? homepage(SiteConfig config, DiscourseUser? user) {
    final settings = config.chatSettings;
    if (!settings.chatEnabled || !settings.publicChannelsEnabled) return null;
    if (user == null) {
      if (!settings.anonymousChatAllowed) return null;
    } else if (user.hasChatEnabled == false || user.canChat == false) {
      return null;
    }
    final option = config.homepageOptions
        ?.where((option) => option.id == homepageId)
        .firstOrNull;
    final path = option?.path;
    if (path == null) return null;
    final uri = Uri.tryParse(path);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final link = ChatLink.parse(path);
    if (link == null ||
        link.route.isThread ||
        link.route.isInfo ||
        link.messageId != null) {
      return null;
    }
    return ContentRoute(
      destination: ExtensionDestination(link.route.routeId),
      title: appL10n.chat,
      icon: DIcons.comment,
    );
  }

  @override
  List<GlobalSearchContribution> get searchContributions => const [
    ChatGlobalSearch(),
  ];

  @override
  List<UserPreferenceCodec> get userPreferenceCodecs => const [
    ChatUserPreferenceCodec(),
  ];

  static const PluginUserMenuSectionId notificationsSection =
      PluginUserMenuSectionId(owner: PluginId('chat'), name: 'notifications');

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
  List<PluginNotificationFeedSource> get notificationFeeds => [
    chatNotificationFeed,
  ];

  @override
  List<PluginNotificationType> get notificationTypes => chatNotificationTypes;

  @override
  List<PluginNotificationCounter> get notificationCounters => const [
    chatNotificationCounter,
  ];

  @override
  ComposerTargetKind get composerTargetKind => chatMessageComposerTarget;

  @override
  ComposerTargetPolicy createComposerTarget(
    ComposerTargetRequest request,
    ComposerTargetContext context,
  ) {
    final channelId = request.data[chatComposerChannelId];
    final threadId = request.data[chatComposerThreadId];
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
      kind: chatMessageComposerTarget,
      draftKey: threadId == null
          ? 'chat_$channelId'
          : 'chat_${channelId}_thread_$threadId',
      uploadType: chatMessageUploadType,
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
            label: appL10n.chat,
            badge: context.totals?.chatNotifications ?? 0,
            notificationTypes: chatNotificationFeed.filterByTypes,
            builder: (buildContext, actions) => ChatUserMenuNotifications(
              siteUrl: context.siteUrl,
              onOpened: actions.onDismiss,
            ),
            sliverBuilder: (buildContext, actions) =>
                ChatUserMenuNotifications.sliver(
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
    if (!chatAvailable) return const [];
    final authenticatedChatAvailable =
        chatAvailable && shell.currentUser != null;
    final publicChannelsEnabled =
        chatAvailable &&
        chat.siteConfigFor(siteUrl).chatSettings.publicChannelsEnabled;
    final actions = _panelActions(shell, siteUrl);

    final directoryOpen = {
      ChatRoute.inboxRouteId,
      ChatRoute.browseRouteId,
      ChatRoute.myThreadsRouteId,
    }.contains(shell.currentContent?.id);
    return [
      if (!context.isTouch && !directoryOpen)
        SidebarSection(
          id: 'chat-directories',
          title: appL10n.chat,
          showHeader: false,
          collapsible: false,
          destinations: [
            if (authenticatedChatAvailable)
              SidebarDestination(
                id: ChatRoute.inboxRouteId,
                label: appL10n.chats,
                icon: DIcons.comment,
                onTap: () => shell.openChats(newTab: true),
              ),
            if (authenticatedChatAvailable && publicChannelsEnabled)
              SidebarDestination(
                id: ChatRoute.browseRouteId,
                label: appL10n.channels,
                icon: DIcons.hashtag,
                onTap: () => shell.openBrowseChannels(newTab: true),
              ),
            if (actions.myThreads)
              SidebarDestination(
                id: ChatRoute.myThreadsRouteId,
                label: appL10n.threads,
                icon: DIcons.comments,
                onTap: () => shell.openMyThreads(newTab: true),
              ),
          ],
        ),
      if (authenticatedChatAvailable ||
          (publicChannelsEnabled && chat.publicChannels(siteUrl).isNotEmpty))
        SidebarSection(
          id: 'chat-inbox',
          title: appL10n.chats,
          showHeader: false,
          collapsible: false,
          // Keep the composer shortcut available through the section even
          // though the inbox has no visible section header.
          actionIcon: actions.startMessage ? DIcons.plus : null,
          actionLabel: actions.startMessage ? appL10n.startAMessage : null,
          actionShortcut: actions.startMessage
              ? newDirectMessageShortcutForPlatform(Theme.of(context).platform)
              : null,
          onAction: actions.startMessage
              ? () => _startMessage(context, shell, siteUrl)
              : null,
          pinnedHeaderBuilder: (_) => ChatSidebarInboxHeader(siteUrl: siteUrl),
          bodyBuilder: (_) =>
              ChatSidebarInbox(key: ValueKey(siteUrl), siteUrl: siteUrl),
          destinations: [
            for (final channel in chatInboxConversations(
              chat,
              siteUrl,
              const ChatInboxFilter(),
            ))
              _destination(
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

    final indicator = _indicator(shell, siteUrl);
    // What is urgent is the one unread chip, in the bar of places and on the
    // sidebar's switch alike; ordinary unread activity keeps its dot.
    Widget? badge({required bool mobile}) {
      if (!indicator.isVisible) return null;
      final key = ValueKey(
        mobile ? 'chat-mobile-unread-badge' : 'chat-sidebar-unread-badge',
      );
      final count = indicator.urgentCount;
      if (count == null) {
        return DNotificationDot(
          key: key,
          color: Theme.of(context).discourse.notificationIndicator,
          semanticLabel: appL10n.chatUnreadMessages,
        );
      }
      return DBadge.unreadChip(
        key: key,
        count: count,
        semanticLabel: appL10n.chatUrgent(count),
      );
    }

    final actions = _panelActions(shell, siteUrl);
    return SidebarPanelContribution(
      label: appL10n.chat,
      mobileBuilder: (_) =>
          ChatMobileSidebar(key: ValueKey(siteUrl), siteUrl: siteUrl),
      mobileAction: actions.startMessage
          ? SidebarPanelAction(
              label: appL10n.startAMessage,
              icon: DIcons.plus,
              onPressed: () => _startMessage(context, shell, siteUrl),
            )
          : null,
      badge: badge(mobile: false),
      mobileBadge: badge(mobile: true),
      icon: DIcons.comment,
      active: ChatRoute.ownsRouteId(shell.currentContent?.id),
      separateWhenActive: true,
      includeSectionsWhenInactive: false,
      showSwitch: true,
      onOpen: () => unawaited(shell.openShortcut()),
      onClose: shell.closeSidebarPanel,
    );
  }

  static ChatHeaderIndicator _indicator(
    ChatShellService shell,
    String siteUrl,
  ) {
    final user = shell.currentUser;
    return user == null || shell.doNotDisturbActive(siteUrl)
        ? ChatHeaderIndicator.none
        : shell.chat.headerIndicator(
            siteUrl,
            user.chatCurrentUser?.headerIndicatorPreference ??
                ChatHeaderIndicatorPreference.allNew,
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
      myThreads: settings.threadsEnabled,
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

  /// What [sidebarPanel] and [mobileNavigationDestinations] read through the
  /// controller. It notifies for every message, tracking echo and read credit
  /// in every followed channel, and almost none of them change any of this.
  static Listenable _chromeChanges(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final chat = PluginUiScope.require(context, chatControllerService);
    return _ChatChromeSelection(chat, () {
      final siteUrl = shell.currentSiteUrl;
      if (siteUrl == null) return null;
      final indicator = _indicator(shell, siteUrl);
      final settings = chat.siteConfigFor(siteUrl).chatSettings;
      return (
        siteUrl,
        shell.chatAvailable(siteUrl),
        shell.isConnected(siteUrl),
        settings.publicChannelsEnabled,
        settings.threadsEnabled,
        indicator.urgentCount,
        indicator.unread,
      );
    });
  }

  @override
  Listenable sidebarPanelListenable(BuildContext context) => Listenable.merge([
    PluginUiScope.require(context, chatShellService),
    _chromeChanges(context),
  ]);

  @override
  Listenable sidebarListenable(BuildContext context) =>
      PluginUiScope.require(context, chatControllerService);

  @override
  Listenable mobileNavigationListenable(BuildContext context) =>
      _chromeChanges(context);

  @override
  List<SidebarDestination> mobileNavigationDestinations(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final site = shell.currentSiteUrl;
    if (site == null || !shell.chatAvailable(site)) return const [];
    final chat = PluginUiScope.require(context, chatControllerService);
    final settings = chat.siteConfigFor(site).chatSettings;
    return [
      if (shell.isConnected(site) && settings.publicChannelsEnabled)
        SidebarDestination(
          id: ChatRoute.browseRouteId,
          label: context.l10n.channels,
          icon: DIcons.hashtag,
          onTap: shell.openBrowseChannels,
        ),
      if (shell.isConnected(site) && settings.threadsEnabled)
        SidebarDestination(
          id: ChatRoute.myThreadsRouteId,
          label: context.l10n.threads,
          icon: DIcons.comments,
          onTap: shell.openMyThreads,
        ),
    ];
  }

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
    return channel == null ? null : _destination(channel, siteUrl: siteUrl);
  }

  @override
  Listenable forumTabListenable(BuildContext context, String siteUrl) =>
      PluginUiScope.require(context, chatControllerService);

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final shell = PluginUiScope.require(context, chatShellService);
    final listKind = switch (route.id) {
      ChatRoute.channelsRouteId => ChatChannelListKind.channels,
      ChatRoute.starredRouteId => ChatChannelListKind.starred,
      ChatRoute.directMessagesRouteId => ChatChannelListKind.directMessages,
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
          ? Center(child: Text(context.l10n.chatChannelsAreNotAvailable))
          : ChatChannelsView(
              key: ValueKey((siteUrl, listKind)),
              siteUrl: siteUrl,
              kind: listKind,
            );
    }
    if (route.id == ChatRoute.inboxRouteId) {
      final siteUrl = shell.currentSiteUrl;
      return siteUrl == null
          ? const SizedBox.shrink()
          : !shell.chatAvailable(siteUrl)
          ? Center(child: Text(context.l10n.chatIsNotAvailable))
          : ChatMobileSidebar(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (route.id == ChatRoute.browseRouteId) {
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
          ? Center(child: Text(context.l10n.chatChannelsAreNotAvailable))
          : ChatBrowseChannelsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (ChatRoute.channelIdFromThreadsRoute(route.id) case final channelId?) {
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
          ? Center(child: Text(context.l10n.threadsAreNotAvailable))
          : ChatChannelThreadsView(
              key: ValueKey((siteUrl, channelId)),
              siteUrl: siteUrl,
              channelId: channelId,
            );
    }
    if (route.id == ChatRoute.myThreadsRouteId) {
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
          ? Center(child: Text(context.l10n.chatThreadsAreNotAvailable))
          : ChatMyThreadsView(key: ValueKey(siteUrl), siteUrl: siteUrl);
    }
    if (route.id == ChatRoute.searchRouteId) {
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
          ? Center(child: Text(context.l10n.chatSearchIsNotAvailable))
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
    return siteUrl == null ? null : shell.searchContextFor(siteUrl);
  }

  @override
  bool ownsContentChrome(BuildContext context, ContentRoute route) =>
      route.id == ChatRoute.inboxRouteId ||
      route.id == ChatRoute.browseRouteId ||
      route.id == ChatRoute.myThreadsRouteId ||
      ChatRoute.parse(route.id)?.isInfo == false;

  @override
  bool usesMobilePageSheet(BuildContext context, ContentRoute route) =>
      ChatRoute.parse(route.id)?.isInfo == false;

  @override
  bool ownsMobileComposer(BuildContext context, ContentRoute route) =>
      ChatRoute.parse(route.id)?.isInfo == false;

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
    if (!context.isTouch)
      ChatHeaderButton(
        ringColor: ringColor,
        trailingSpacing: DSpacing.controlGap,
      ),
  ];

  static SidebarDestination _destination(
    ChatChannel channel, {
    String? siteUrl,
    VoidCallback? onTap,
  }) {
    final directUser = channel.directUser;
    final avatarUrl = channel.avatarUrl;
    final status = directUser?.status;
    return chatChannelDestination(
      channel,
      onTap: onTap,
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

final class _ChatChromeSelection implements Listenable {
  _ChatChromeSelection(this._source, this._read);

  final Listenable _source;
  final Object? Function() _read;
  final Map<VoidCallback, VoidCallback> _forwarders = {};

  @override
  void addListener(VoidCallback listener) {
    var seen = _read();
    void forward() {
      final next = _read();
      if (next == seen) return;
      seen = next;
      listener();
    }

    _forwarders[listener] = forward;
    _source.addListener(forward);
  }

  @override
  void removeListener(VoidCallback listener) {
    final forward = _forwarders.remove(listener);
    if (forward != null) _source.removeListener(forward);
  }
}
