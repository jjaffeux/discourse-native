// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/bookmark.dart';
import '../../models/content_route.dart';
import '../../models/discourse_user.dart';
import '../../models/notification_totals.dart';
import '../../models/post_flag.dart';
import '../../models/sidebar.dart';
import '../../models/user_preferences.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_runtime.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'chat_bookmark.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_drawer_preferences_store.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_services.dart';
import 'chat_stream_target.dart';

const chatShellService = PluginServiceKey<ChatShellService>(
  owner: chatPluginId,
  name: 'shell',
);

final class ChatShellService
    implements
        Listenable,
        PluginLinkHandler,
        PluginRouteRetry,
        PluginRouteHydrator,
        PluginPaneRoutePolicy,
        PluginTotalsObserver,
        PluginTrackerAttachment,
        PluginUserPreferenceMirror,
        PluginBookmarkTargetStrategy {
  ChatShellService({
    required this.chat,
    required PluginNavigationHost host,
    required this.composerHost,
    required this.store,
    required PluginPostFlagCatalogReader postFlagCatalog,
    ChatDrawerPreferencesStore? drawerPreferences,
  }) : _host = host,
       _postFlagCatalog = postFlagCatalog,
       _drawerPreferences =
           drawerPreferences ?? const ChatDrawerPreferencesStore() {
    _host.changes.addListener(_handleHostChanged);
    _drawerPreferencesRestored = _restoreDrawerPreferences();
  }

  final ChatController chat;
  final PluginComposerHost composerHost;
  final Store store;
  final PluginNavigationHost _host;
  final PluginPostFlagCatalogReader _postFlagCatalog;
  final ChatDrawerPreferencesStore _drawerPreferences;
  final ChatNavigationHandoff navigation = ChatNavigationHandoff();
  final ValueNotifier<int> _changes = ValueNotifier(0);
  late final Future<void> _drawerPreferencesRestored;
  int _displayPreferenceGeneration = 0;
  int _urlOpenGeneration = 0;
  bool _disposed = false;
  bool _drawerAvailable = false;
  bool _drawerActive = false;
  bool _drawerExpanded = true;
  bool _fullPagePreservesAppRoute = false;
  String? _drawerSiteUrl;
  List<ContentRoute> _drawerContentStack = const [];
  String? _drawerViewingSiteUrl;
  ChatStreamTarget? _drawerViewingTarget;
  Object? _drawerViewingToken;
  ChatPreferredDisplayMode _preferredDisplayMode =
      ChatPreferredDisplayMode.drawer;

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  String? get currentSiteUrl => _host.currentInstance?.url;
  bool get forumActive => _host.forumActive;
  bool get showHeaderShortcut =>
      _host.forumActive && _host.currentInstance != null;
  DiscourseUser? get currentUser => _host.currentInstance?.user;
  NotificationTotals? get currentTotals => _host.currentTotals;
  Rect? get floatingComposerBounds => _host.floatingComposerBounds;
  ContentRoute? get currentContent =>
      drawerActive ? drawerCurrentContent : _host.currentContent;
  bool get fullPageChatActive =>
      ChatPlugin.ownsRouteId(_host.currentContent?.id);
  bool get chatActive => drawerActive || fullPageChatActive;
  bool get drawerAvailable =>
      _drawerAvailable && forumActive && _currentSiteCanUseChat;
  bool get drawerActive =>
      _drawerActive && _drawerSiteUrl == currentSiteUrl && drawerAvailable;
  bool get drawerExpanded => drawerActive && _drawerExpanded;
  bool get drawerCanGoBack => drawerActive && _drawerStackAfterBack() != null;
  bool get drawerShowingStarred =>
      drawerActive && drawerCurrentContent?.id == ChatPlugin.starredRouteId;
  ContentRoute? get drawerCurrentContent =>
      _drawerSiteUrl != currentSiteUrl || _drawerContentStack.isEmpty
      ? null
      : _drawerContentStack.last;
  List<ContentRoute> get drawerContentStack =>
      List.unmodifiable(_drawerContentStack);
  ChatPreferredDisplayMode get preferredDisplayMode => _preferredDisplayMode;
  bool get _currentSiteCanUseChat {
    final instance = _host.currentInstance;
    if (instance == null || !instance.isConnected) return false;
    return chat.siteConfigFor(instance.url).chatSettings.chatEnabled &&
        instance.user?.hasChatEnabled != false &&
        _host.currentTotals?.hasChatEnabled == true;
  }

  ChatSeparateSidebarMode get separateSidebarMode {
    final siteUrl = currentSiteUrl;
    if (siteUrl == null) return ChatSeparateSidebarMode.never;
    return effectiveChatSeparateSidebarMode(
      settings: chat.siteConfigFor(siteUrl).chatSettings,
      currentUser: currentUser?.chatCurrentUser,
    );
  }

  bool isConnected(String siteUrl) =>
      _host.currentInstance?.url == siteUrl &&
      _host.currentInstance?.isConnected == true;

  /// Public Chat is readable without an account when the site exposes it.
  /// Account-only Chat features still use [isConnected].
  bool chatAvailable(String siteUrl) {
    final instance = _host.currentInstance;
    if (instance == null || instance.url != siteUrl) {
      return false;
    }
    final settings = chat.siteConfigFor(siteUrl).chatSettings;
    if (!settings.chatEnabled) return false;
    final user = instance.user;
    if (user == null) return settings.publicChannelsEnabled;
    return _host.currentTotals?.hasChatEnabled == true &&
        instance.isConnected &&
        user.hasChatEnabled != false;
  }

  bool doNotDisturbActive(String siteUrl, {DateTime? now}) =>
      _host.currentInstance?.url == siteUrl &&
      (_host.currentInstance?.user?.doNotDisturbUntil?.isAfter(
            now ?? DateTime.now(),
          ) ??
          false);

  List<PostFlagType> postFlagTypesFor(String siteUrl) =>
      _postFlagCatalog(siteUrl);

  int showTimeGapDaysFor(String siteUrl) =>
      chat.siteConfigFor(siteUrl).showTimeGapDays;

  /// The overlay reports whether its local constraints can host a drawer.
  /// A stored drawer preference is deliberately retained across compact
  /// layouts, where Chat is temporarily forced into the full-page surface.
  void updateDrawerAvailability(bool available) {
    if (_disposed || _drawerAvailable == available) return;
    _drawerAvailable = available;
    if (!available && _drawerActive) {
      unawaited(openFullPageFromDrawer(persistPreference: false));
    } else if (available &&
        _fullPagePreservesAppRoute &&
        fullPageChatActive &&
        _preferredDisplayMode == ChatPreferredDisplayMode.drawer) {
      unawaited(openDrawerFromFullPage(persistPreference: false));
    }
    _notify();
  }

  void toggleDrawerExpanded() {
    if (!drawerActive) return;
    _drawerExpanded = !_drawerExpanded;
    _notify();
  }

  void expandDrawer() {
    if (!drawerActive || _drawerExpanded) return;
    _drawerExpanded = true;
    _notify();
  }

  void closeDrawer() {
    if (!_drawerActive) return;
    _drawerActive = false;
    _drawerExpanded = true;
    _syncDrawerViewing();
    _notify();
  }

  void drawerBack() {
    final next = drawerActive ? _drawerStackAfterBack() : null;
    if (next == null) return;
    _drawerContentStack = next;
    _syncDrawerViewing();
    _notify();
  }

  /// Matches the web drawer's Alt+Up/Down channel switcher. Its order is the
  /// sidebar order, rather than the activity order used by drawer index rows.
  /// Shift narrows the cycle to channels with any unread activity.
  bool cycleDrawerChannel({required bool forward, bool unreadOnly = false}) {
    final siteUrl = currentSiteUrl;
    if (!chatActive || siteUrl == null) return false;
    final orderedChannels = <ChatChannel>[
      ...chat.starredChannels(siteUrl),
      ...chat.unstarredPublicChannels(siteUrl),
      ...chat.unstarredDirectChannels(siteUrl).take(50),
    ];
    if (orderedChannels.isEmpty) return false;

    bool hasUnread(ChatChannel channel) =>
        channel.tracking.unreadCount +
            channel.tracking.mentionCount +
            channel.tracking.watchedThreadsUnreadCount +
            channel.unreadThreadCount >
        0;

    final currentChannelId = switch (currentContent?.id) {
      final id? => ChatRoute.parse(id)?.channelId,
      null => null,
    };
    if (currentChannelId == null) return false;
    var channels = orderedChannels;
    if (unreadOnly) {
      channels = orderedChannels.where(hasUnread).toList();
      final activeIndex = orderedChannels.indexWhere(
        (channel) => channel.id == currentChannelId,
      );
      final activeHasActivity = channels.any(
        (channel) => channel.id == currentChannelId,
      );
      if (activeIndex >= 0 && !activeHasActivity) {
        var insertAfter = -1;
        for (var index = activeIndex - 1; index >= 0; index--) {
          final previousId = orderedChannels[index].id;
          final previousActivityIndex = channels.indexWhere(
            (channel) => channel.id == previousId,
          );
          if (previousActivityIndex >= 0) {
            insertAfter = previousActivityIndex;
            break;
          }
        }
        channels.insert(insertAfter + 1, orderedChannels[activeIndex]);
      }
    }
    if (channels.isEmpty) return false;

    final currentIndex = channels.indexWhere(
      (channel) => channel.id == currentChannelId,
    );
    final nextIndex = currentIndex < 0
        ? (forward ? 0 : channels.length - 1)
        : (currentIndex + (forward ? 1 : -1)) % channels.length;
    final nextChannelId = channels[nextIndex].id;
    if (nextChannelId != currentChannelId) openChannel(nextChannelId);
    return true;
  }

  Future<void> openFullPageFromDrawer({bool persistPreference = true}) async {
    if (!_drawerActive) return;
    final siteUrl = _drawerSiteUrl;
    if (siteUrl == null || _host.currentInstance?.url != siteUrl) {
      closeDrawer();
      return;
    }

    final routes = _fullPageRoutesForDrawer(
      _drawerContentStack.isEmpty
          ? [_chatIndexRoute()]
          : List<ContentRoute>.of(_drawerContentStack),
    );
    _drawerActive = false;
    _drawerExpanded = true;
    _syncDrawerViewing();
    _fullPagePreservesAppRoute = true;
    if (persistPreference) {
      _displayPreferenceGeneration++;
      _preferredDisplayMode = ChatPreferredDisplayMode.fullPage;
    }
    _notify();

    _host.activatePluginPane(chatPluginId);
    _restoreFullPageStack(routes);
    if (persistPreference) {
      await _drawerPreferences.writePreferredDisplayMode(
        ChatPreferredDisplayMode.fullPage,
      );
    }
  }

  Future<void> openDrawerFromFullPage({bool persistPreference = true}) async {
    if (!drawerAvailable || !fullPageChatActive) return;
    final siteUrl = currentSiteUrl;
    if (siteUrl == null) return;
    final routes = [
      for (final route in _host.contentStack)
        if (ChatPlugin.ownsRouteId(route.id)) route,
    ];
    _drawerSiteUrl = siteUrl;
    final retainedRoutes = routes.skip(math.max(0, routes.length - 10));
    _drawerContentStack = List.unmodifiable(
      routes.isEmpty ? [_chatIndexRoute()] : retainedRoutes,
    );

    _host.deactivatePluginPane(chatPluginId);
    _fullPagePreservesAppRoute = false;
    if (persistPreference) _displayPreferenceGeneration++;
    _preferredDisplayMode = ChatPreferredDisplayMode.drawer;
    _drawerActive = true;
    _drawerExpanded = true;
    _syncDrawerViewing();
    _notify();
    if (persistPreference) {
      await _drawerPreferences.writePreferredDisplayMode(
        ChatPreferredDisplayMode.drawer,
      );
    }
  }

  Future<void> _restoreDrawerPreferences() async {
    final generation = _displayPreferenceGeneration;
    final restored = await _drawerPreferences.readPreferredDisplayMode();
    if (_disposed ||
        generation != _displayPreferenceGeneration ||
        restored == null ||
        restored == _preferredDisplayMode) {
      return;
    }
    _preferredDisplayMode = restored;
    _notify();
  }

  void _handleHostChanged() {
    if (_disposed) return;
    final currentSite = _host.currentInstance?.url;
    if (_drawerActive &&
        (_drawerSiteUrl != currentSite ||
            !_host.forumActive ||
            !_currentSiteCanUseChat ||
            ChatPlugin.ownsRouteId(_host.currentContent?.id))) {
      _drawerActive = false;
      _drawerExpanded = true;
      _syncDrawerViewing();
    }
    if (_fullPagePreservesAppRoute &&
        !ChatPlugin.ownsRouteId(_host.currentContent?.id)) {
      _fullPagePreservesAppRoute = false;
    }
    _notify();
  }

  void forget(String siteUrl) {
    if (_drawerSiteUrl == siteUrl) {
      _drawerActive = false;
      _drawerExpanded = true;
      _drawerSiteUrl = null;
      _drawerContentStack = const [];
    }
    if (_drawerViewingSiteUrl == siteUrl) _endDrawerViewing();
    _notify();
  }

  void _notify() {
    if (!_disposed) _changes.value++;
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    final absolute = resolveSiteUrl(url, _host.currentInstance?.url);
    final link = ChatLink.parse(absolute);
    if (link == null) return false;
    final generation = ++_urlOpenGeneration;

    var index = _host.instances.indexWhere(
      (instance) => instance.serves(link.uri),
    );
    if (index < 0 || !_host.instances[index].isConnected) return false;

    final siteUrl = _host.instances[index].url;
    await chat.loadChannels(siteUrl);
    if (_host.isDisposed || generation != _urlOpenGeneration) return true;
    if (chat.channel(siteUrl, link.route.channelId) == null) return false;
    if (link.route.threadId case final threadId?) {
      final detail = await chat.refreshThreadDetail(
        siteUrl,
        ChatThreadTarget(channelId: link.route.channelId, threadId: threadId),
      );
      if (_host.isDisposed || generation != _urlOpenGeneration) return true;
      if (detail == null) return false;
    }
    if (origin == PluginLinkOrigin.inApp) {
      await _drawerPreferencesRestored;
      if (_host.isDisposed || generation != _urlOpenGeneration) return true;
    }

    index = _host.instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !_host.instances[index].isConnected) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);
    return _openRoute(
      siteUrl,
      link.route,
      messageId: link.messageId,
      forceFullPage: origin == PluginLinkOrigin.direct,
    );
  }

  @override
  Future<PluginRouteRetryResult> retryPluginRoute(
    String siteUrl,
    String routeId,
  ) async {
    final route = ChatRoute.parse(routeId);
    if (route == null) return PluginRouteRetryResult.notHandled;
    final target = route.isThread
        ? ChatThreadTarget(
            channelId: route.channelId,
            threadId: route.threadId!,
          )
        : ChatChannelTarget(route.channelId);
    if (target case final ChatThreadTarget thread) {
      await chat.openThread(siteUrl, thread, force: true);
    } else {
      await chat.openChannel(siteUrl, route.channelId, force: true);
    }
    return chat.streamFor(siteUrl, target).error == null
        ? PluginRouteRetryResult.succeeded
        : PluginRouteRetryResult.failed;
  }

  @override
  bool handlesPluginRoute(String routeId) => ChatPlugin.ownsRouteId(routeId);

  @override
  PluginId get pluginPaneOwner => chatPluginId;

  @override
  bool ownsPluginPaneRoute(String routeId) => ChatPlugin.ownsRouteId(routeId);

  @override
  bool separatesPluginPane(String routeId) =>
      ChatPlugin.ownsRouteId(routeId) &&
      (_fullPagePreservesAppRoute ||
          separateSidebarMode != ChatSeparateSidebarMode.never);

  @override
  Future<void> hydratePluginRoute(String siteUrl, String routeId) =>
      chat.loadChannels(siteUrl);

  @override
  Future<void> pluginTotalsLoaded(
    String siteUrl,
    NotificationTotals totals, {
    required bool selected,
  }) async {
    if (!selected) return;
    if (totals.hasChatEnabled != true) {
      closeDrawer();
      return;
    }
    await chat.loadChannels(siteUrl);
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      chat.attachTracker(siteUrl, channels);

  @override
  DiscourseUser mirrorUserPreference(
    DiscourseUser user,
    PreferenceSection section,
    UserPreferences preferences,
  ) {
    if (section != PreferenceSection.chat) return user;
    final held = user.chatCurrentUser ?? const ChatCurrentUser();
    final updated = ChatCurrentUser(
      hasChatEnabled: held.hasChatEnabled,
      canChat: held.canChat,
      canDirectMessage: held.canDirectMessage,
      headerIndicatorPreference: held.headerIndicatorPreference,
      separateSidebarMode: switch (preferences.chatSeparateSidebarMode) {
        ChatSeparateSidebarPreference.siteDefault =>
          ChatSeparateSidebarMode.siteDefault,
        ChatSeparateSidebarPreference.always => ChatSeparateSidebarMode.always,
        ChatSeparateSidebarPreference.fullscreen =>
          ChatSeparateSidebarMode.fullscreen,
        ChatSeparateSidebarPreference.never => ChatSeparateSidebarMode.never,
      },
      lastChannelId: held.lastChannelId,
      ignoredUsernames: held.ignoredUsernames,
    );
    return user.withPlugins(
      user.plugins.withValue(chatCurrentUserDataKey, updated),
    );
  }

  @override
  BookmarkTargetType get pluginBookmarkTarget => chatMessageBookmarkTarget;

  @override
  void putPluginBookmark(String siteUrl, int targetId, Bookmark bookmark) =>
      chat.putMessageBookmark(siteUrl, targetId, bookmark);

  @override
  void removePluginBookmark(String siteUrl, int targetId) =>
      chat.removeMessageBookmark(siteUrl, targetId);

  @override
  Future<void> reconcilePluginBookmark(String siteUrl, int targetId) async {
    final message = chat.message(siteUrl, targetId);
    if (message != null) await chat.reconcileMessageBookmark(siteUrl, message);
  }

  void openBrowseChannels() {
    if (_shouldNavigateDrawer) {
      _openDrawerRoute(
        const ContentRoute(
          id: ChatPlugin.browseRouteId,
          title: 'Channels',
          icon: DIcons.list,
        ),
      );
      return;
    }
    _activateSeparatedPane();
    _host.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.browseRouteId,
        label: 'Browse channels',
        icon: DIcons.list,
      ),
    );
  }

  void openChannels() => _openDrawerRoute(_chatIndexRoute());

  void openStarredChannels() => _openDrawerRoute(_chatStarredRoute());

  void leaveEmptyStarredRoute() {
    final siteUrl = currentSiteUrl;
    if (!_drawerActive ||
        _drawerSiteUrl != siteUrl ||
        !drawerShowingStarred ||
        siteUrl == null ||
        chat.starredChannels(siteUrl).isNotEmpty) {
      return;
    }

    final preceding = _drawerContentStack.take(
      math.max(0, _drawerContentStack.length - 1),
    );
    final next = _chatIndexRoute();
    final routes = [...preceding];
    if (routes.lastOrNull?.id != next.id) routes.add(next);
    _drawerContentStack = List.unmodifiable(routes);
    _syncDrawerViewing();
    _notify();
  }

  void openDirectMessages() => _openDrawerRoute(_chatDirectMessagesRoute());

  void openMyThreads() {
    if (_shouldNavigateDrawer) {
      _openDrawerRoute(_chatMyThreadsRoute());
      return;
    }
    _activateSeparatedPane();
    _host.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.myThreadsRouteId,
        label: 'My threads',
        icon: DIcons.comments,
      ),
    );
  }

  void openSearch() {
    if (_shouldNavigateDrawer) {
      _openDrawerRoute(
        const ContentRoute(
          id: ChatPlugin.searchRouteId,
          title: 'Search chat',
          icon: DIcons.magnifyingGlass,
        ),
      );
      return;
    }
    _activateSeparatedPane();
    _host.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.searchRouteId,
        label: 'Search',
        icon: DIcons.magnifyingGlass,
      ),
    );
  }

  void returnToChannel(int channelId) {
    if (drawerActive &&
        _drawerContentStack.length > 1 &&
        ChatRoute.parse(
              _drawerContentStack[_drawerContentStack.length - 2].id,
            )?.channelId ==
            channelId) {
      drawerBack();
      return;
    }
    openChannel(channelId);
  }

  void openThread({
    required String siteUrl,
    required int channelId,
    required int threadId,
    int? messageId,
    bool focusComposer = false,
  }) {
    if (channelId <= 0 ||
        threadId <= 0 ||
        (messageId != null && messageId <= 0)) {
      return;
    }
    final index = _host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !_host.instances[index].isConnected) return;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);
    _openRoute(
      siteUrl,
      ChatRoute.thread(channelId: channelId, threadId: threadId),
      messageId: messageId,
      focusComposer: focusComposer,
    );
  }

  bool openChannel(int channelId, {int? messageId}) {
    if (channelId <= 0 || (messageId != null && messageId <= 0)) return false;
    final instance = _host.currentInstance;
    if (instance == null ||
        (instance.user == null
            ? !chatAvailable(instance.url)
            : !instance.isConnected)) {
      return false;
    }
    final channel = chat.channel(instance.url, channelId);
    if (channel == null || (instance.user == null && channel.isDirectMessage)) {
      return false;
    }
    return _openRoute(
      instance.url,
      ChatRoute.channel(channelId),
      messageId: messageId,
    );
  }

  bool openChannelInfo({
    required String siteUrl,
    required int channelId,
    ChatChannelInfoTab tab = ChatChannelInfoTab.settings,
  }) {
    if (channelId <= 0) return false;
    final index = _host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !_host.instances[index].isConnected) return false;
    final channel = chat.channel(siteUrl, channelId);
    if (channel == null) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);
    return _openInfoRoute(
      siteUrl,
      channel,
      ChatRoute.info(channelId: channelId, tab: tab),
    );
  }

  bool openChannelThreads({required String siteUrl, required int channelId}) {
    if (channelId <= 0) return false;
    final index = _host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !_host.instances[index].isConnected) return false;
    if (!chat.siteConfigFor(siteUrl).chatSettings.threadsEnabled) return false;
    final channel = chat.channel(siteUrl, channelId);
    if (channel?.threadingEnabled != true) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);

    final routeId = ChatPlugin.channelThreadsRouteId(channelId);
    if (_shouldNavigateDrawer) {
      _openDrawerRoute(
        ContentRoute(
          id: routeId,
          title: 'Threads',
          subtitle: channel!.title,
          icon: DIcons.comments,
        ),
      );
      return true;
    }
    _activateSeparatedPane();

    if (_host.currentContent?.id != routeId) {
      final currentChatRoute = switch (_host.currentContent?.id) {
        final id? => ChatRoute.parse(id),
        null => null,
      };
      if (currentChatRoute?.channelId != channelId ||
          currentChatRoute?.isThread == true) {
        _host.selectDestination(ChatPlugin.destination(channel!));
      }
      _host.pushContent(
        ContentRoute(
          id: routeId,
          title: 'Threads',
          subtitle: channel!.title,
          icon: DIcons.comments,
        ),
      );
    }
    _host.showPluginContent();
    return true;
  }

  bool revealChannelMessage({
    required String siteUrl,
    required int channelId,
    required int messageId,
  }) {
    if (channelId <= 0 ||
        messageId <= 0 ||
        _host.currentInstance?.url != siteUrl ||
        chat.channel(siteUrl, channelId) == null) {
      return false;
    }
    navigation.offer(
      ChatNavigationTarget(
        siteUrl: siteUrl,
        route: ChatRoute.channel(channelId),
        messageId: messageId,
      ),
    );
    return true;
  }

  Future<String?> openQuote(
    String siteUrl,
    int channelId,
    String markdown,
  ) async {
    final route = currentContent;
    final chatRoute = route == null ? null : ChatRoute.parse(route.id);
    final shellRoute = _host.currentContent;
    final channel = chat.channel(siteUrl, channelId);
    if (markdown.trim().isEmpty ||
        channelId <= 0 ||
        chatRoute?.channelId != channelId ||
        shellRoute == null ||
        channel == null) {
      return 'The topic composer is no longer available here.';
    }
    final drawerSourceRouteId = drawerActive ? route!.id : null;
    bool sourceStillCurrent() =>
        !_disposed &&
        _host.currentContent?.id == shellRoute.id &&
        (drawerSourceRouteId == null ||
            (drawerActive && currentContent?.id == drawerSourceRouteId));
    final result = await composerHost.openNewTopic(
      OpenNewTopicComposerRequest(
        siteUrl: siteUrl,
        sourceRouteId: shellRoute.id,
        seed: ComposerSeed(raw: markdown),
        initialCategoryId: channel.isCategoryChannel
            ? channel.chatableId
            : null,
        sourceStillCurrent: sourceStillCurrent,
      ),
    );
    return switch (result) {
      OpenComposerResult.opened => null,
      OpenComposerResult.unavailable || OpenComposerResult.sourceChanged =>
        'The topic composer is no longer available here.',
    };
  }

  Future<void> openShortcut({bool? drawerAvailable}) async {
    if (drawerAvailable != null) {
      updateDrawerAvailability(drawerAvailable);
    }
    final instance = _host.currentInstance;
    if (instance == null || !instance.isConnected) return;
    final totals = _host.currentTotals;
    if (totals?.hasChatEnabled != true ||
        instance.user?.hasChatEnabled == false) {
      return;
    }
    final siteUrl = instance.url;
    await chat.loadChannels(siteUrl);
    if (_host.currentInstance?.url != siteUrl) return;
    await _drawerPreferencesRestored;
    if (_shouldNavigateDrawer) {
      final initialRoute = _initialDrawerRoute(siteUrl);
      if (initialRoute == null) {
        forget(siteUrl);
        return;
      }
      if (_drawerActive && _drawerSiteUrl == siteUrl) {
        _openDrawerRoute(initialRoute, expand: true);
      } else {
        final reopensSameSite = _drawerSiteUrl == siteUrl;
        _drawerSiteUrl = siteUrl;
        if (_drawerContentStack.isEmpty || !reopensSameSite) {
          _drawerContentStack = [initialRoute];
        }
        _drawerActive = true;
        _drawerExpanded = true;
        _syncDrawerViewing();
        _notify();
      }
      return;
    }
    if (_drawerAvailable &&
        _preferredDisplayMode == ChatPreferredDisplayMode.fullPage &&
        separateSidebarMode == ChatSeparateSidebarMode.never) {
      _fullPagePreservesAppRoute = true;
      _host.activatePluginPane(chatPluginId);
    }
    if (_activateSeparatedPane()) {
      _host.showPluginContent();
      return;
    }
    final channel = chat.shortcutChannel(
      siteUrl,
      lastChannelId: _host.currentInstance?.user?.lastChatChannelId,
    );
    if (channel != null) {
      _openRoute(siteUrl, ChatRoute.channel(channel.id));
    } else {
      openBrowseChannels();
    }
  }

  /// The web `-` shortcut chooses drawer mode before routing. This differs
  /// from the header button, which follows the persisted display preference.
  Future<void> openDrawerShortcut() async {
    if (drawerActive) {
      closeDrawer();
      return;
    }
    if (!drawerAvailable || !_currentSiteCanUseChat) return;
    if (fullPageChatActive) {
      await openDrawerFromFullPage();
      return;
    }

    final preferenceChanged =
        _preferredDisplayMode != ChatPreferredDisplayMode.drawer;
    if (preferenceChanged) {
      _displayPreferenceGeneration++;
      _preferredDisplayMode = ChatPreferredDisplayMode.drawer;
      _notify();
    }
    await openShortcut(drawerAvailable: true);
    if (preferenceChanged) {
      await _drawerPreferences.writePreferredDisplayMode(
        ChatPreferredDisplayMode.drawer,
      );
    }
  }

  void closeSidebarPanel() {
    if (drawerActive) {
      closeDrawer();
      return;
    }
    if (!_usesSidebarPaneNavigation || !chatActive) {
      return;
    }
    _host.deactivatePluginPane(chatPluginId);
  }

  bool _activateSeparatedPane() {
    if (!_usesSidebarPaneNavigation || fullPageChatActive) {
      return false;
    }
    return _host.activatePluginPane(chatPluginId);
  }

  bool get _usesSidebarPaneNavigation =>
      _fullPagePreservesAppRoute ||
      separateSidebarMode != ChatSeparateSidebarMode.never;

  bool get _shouldNavigateDrawer =>
      (_drawerActive && _drawerSiteUrl == currentSiteUrl) ||
      (drawerAvailable &&
          !fullPageChatActive &&
          _preferredDisplayMode == ChatPreferredDisplayMode.drawer);

  bool _openRoute(
    String siteUrl,
    ChatRoute route, {
    int? messageId,
    bool focusComposer = false,
    bool forceFullPage = false,
  }) {
    if (_host.currentInstance?.url != siteUrl) return false;
    final channel = chat.channel(siteUrl, route.channelId);
    if (channel == null) return false;
    if (route.isInfo) {
      return _openInfoRoute(
        siteUrl,
        channel,
        route,
        forceFullPage: forceFullPage,
      );
    }
    if (!forceFullPage && _shouldNavigateDrawer) {
      _openDrawerRoute(
        ContentRoute(
          id: route.routeId,
          title: route.isThread ? 'Thread' : channel.title,
          subtitle: route.isThread ? channel.title : null,
          icon: route.isThread ? DIcons.comments : DIcons.comment,
        ),
      );
      navigation.offer(
        ChatNavigationTarget(
          siteUrl: siteUrl,
          route: route,
          messageId: messageId,
          focusComposer: focusComposer,
        ),
      );
      return true;
    }
    if (_drawerActive) {
      _drawerActive = false;
      _drawerExpanded = true;
      _syncDrawerViewing();
      _notify();
    }
    _activateSeparatedPane();

    final currentRoute = switch (_host.currentContent?.id) {
      final id? => ChatRoute.parse(id),
      null => null,
    };
    if (route.isThread) {
      if (currentRoute != route) {
        final currentThreadsChannelId = switch (_host.currentContent?.id) {
          final id? => ChatPlugin.channelIdFromThreadsRoute(id),
          null => null,
        };
        final preservesThreadList =
            _host.currentContent?.id == ChatPlugin.myThreadsRouteId ||
            currentThreadsChannelId == route.channelId;
        if (currentRoute?.threadId != null ||
            !preservesThreadList &&
                currentRoute?.channelId != route.channelId) {
          _host.selectDestination(ChatPlugin.destination(channel));
        }
        _host.pushContent(
          ContentRoute(
            id: route.routeId,
            title: 'Thread',
            subtitle: channel.title,
            icon: DIcons.comments,
          ),
        );
      }
    } else if (currentRoute != route || _host.contentStack.length != 1) {
      _host.selectDestination(ChatPlugin.destination(channel));
    }

    navigation.offer(
      ChatNavigationTarget(
        siteUrl: siteUrl,
        route: route,
        messageId: messageId,
        focusComposer: focusComposer,
      ),
    );
    _host.showPluginContent();
    return true;
  }

  void _openDrawerRoute(ContentRoute route, {bool expand = true}) {
    final siteUrl = currentSiteUrl;
    if (siteUrl == null || !_drawerAvailable) return;
    if (_drawerSiteUrl != siteUrl) {
      _drawerSiteUrl = siteUrl;
      _drawerContentStack = const [];
    }

    final current = drawerCurrentContent;
    if (current?.id != route.id) {
      final next = [..._drawerContentStack, route];
      _drawerContentStack = List.unmodifiable(
        next.length <= 10 ? next : next.skip(next.length - 10),
      );
    }
    _drawerActive = true;
    if (expand) _drawerExpanded = true;
    _syncDrawerViewing();
    _notify();
  }

  List<ContentRoute>? _drawerStackAfterBack() {
    final current = drawerCurrentContent;
    if (current == null || _drawerRoutesWithoutBack.contains(current.id)) {
      return null;
    }

    final preceding = List<ContentRoute>.of(
      _drawerContentStack.take(math.max(0, _drawerContentStack.length - 1)),
    );
    final previous = preceding.lastOrNull;
    ContentRoute? target;

    if (ChatRoute.parse(current.id) case final route?) {
      if (route.isInfo) {
        target = _drawerChannelRoute(route.channelId);
      } else if (route.isThread) {
        final previousIsThreadIndex =
            previous?.id == ChatPlugin.myThreadsRouteId ||
            previous?.id == ChatPlugin.channelThreadsRouteId(route.channelId);
        target = previousIsThreadIndex
            ? previous
            : _drawerChannelRoute(route.channelId);
      } else {
        final channel = chat.channel(currentSiteUrl!, route.channelId);
        final previousIsChannelIndex =
            previous?.id == ChatPlugin.browseRouteId ||
            previous?.id == ChatPlugin.starredRouteId;
        if (previousIsChannelIndex) {
          target = previous;
        } else if (channel?.isDirectMessage == true) {
          target = _chatDirectMessagesRoute();
        } else {
          target = _chatIndexRoute();
        }
      }
    } else if (ChatPlugin.channelIdFromThreadsRoute(current.id)
        case final channelId?) {
      target = _drawerChannelRoute(channelId);
    } else if (current.id == ChatPlugin.browseRouteId) {
      target = _chatIndexRoute();
    } else {
      target = previous;
    }

    if (target == null) return null;
    if (previous?.id == target.id) {
      return List.unmodifiable(preceding);
    }
    return List.unmodifiable([...preceding, target]);
  }

  ContentRoute? _drawerChannelRoute(int channelId) {
    final siteUrl = currentSiteUrl;
    if (siteUrl == null) return null;
    final channel = chat.channel(siteUrl, channelId);
    if (channel == null) return null;
    return ContentRoute(
      id: ChatRoute.channel(channelId).routeId,
      title: channel.title,
      icon: DIcons.comment,
    );
  }

  void _syncDrawerViewing() {
    ChatStreamTarget? target;
    final siteUrl = _drawerActive ? _drawerSiteUrl : null;
    final content = drawerCurrentContent;
    if (siteUrl != null && content != null) {
      if (ChatRoute.parse(content.id) case final route?) {
        target = route.isThread
            ? ChatThreadTarget(
                channelId: route.channelId,
                threadId: route.threadId!,
              )
            : ChatChannelTarget(route.channelId);
      } else if (ChatPlugin.channelIdFromThreadsRoute(content.id)
          case final channelId?) {
        target = ChatChannelTarget(channelId);
      }
    }
    if (_drawerViewingSiteUrl == siteUrl &&
        _drawerViewingTarget == target &&
        _drawerViewingToken != null) {
      return;
    }
    _endDrawerViewing();
    if (siteUrl == null || target == null) return;
    _drawerViewingSiteUrl = siteUrl;
    _drawerViewingTarget = target;
    _drawerViewingToken = switch (target) {
      final ChatThreadTarget thread => chat.beginViewingThread(siteUrl, thread),
      final ChatChannelTarget channel => chat.beginViewingChannel(
        siteUrl,
        channel.channelId,
      ),
    };
  }

  void _endDrawerViewing() {
    final siteUrl = _drawerViewingSiteUrl;
    final target = _drawerViewingTarget;
    final token = _drawerViewingToken;
    _drawerViewingSiteUrl = null;
    _drawerViewingTarget = null;
    _drawerViewingToken = null;
    if (siteUrl == null || target == null || token == null) return;
    switch (target) {
      case final ChatThreadTarget thread:
        chat.endViewingThread(siteUrl, thread, token);
      case final ChatChannelTarget channel:
        chat.endViewingChannel(siteUrl, channel.channelId, token);
    }
  }

  ContentRoute? _initialDrawerRoute(String siteUrl) {
    if (chat.starredChannels(siteUrl).isNotEmpty) {
      return _chatStarredRoute();
    }

    final settings = chat.siteConfigFor(siteUrl).chatSettings;
    final user = currentUser;
    final canAccessDirectMessages =
        user?.staff == true ||
        user?.canDirectMessage == true ||
        chat.directChannels(siteUrl).isNotEmpty;
    switch (settings.preferredIndex) {
      case ChatPreferredIndex.myThreads
          when settings.threadsEnabled && chat.hasThreads(siteUrl):
        return _chatMyThreadsRoute();
      case ChatPreferredIndex.directMessages when canAccessDirectMessages:
        return _chatDirectMessagesRoute();
      case ChatPreferredIndex.channels ||
          ChatPreferredIndex.directMessages ||
          ChatPreferredIndex.myThreads:
        break;
    }

    if (settings.publicChannelsEnabled) return _chatIndexRoute();
    if (canAccessDirectMessages) return _chatDirectMessagesRoute();
    return null;
  }

  static ContentRoute _chatIndexRoute() => const ContentRoute(
    id: ChatPlugin.channelsRouteId,
    title: 'Chat',
    icon: DIcons.comments,
  );

  static ContentRoute _chatStarredRoute() => const ContentRoute(
    id: ChatPlugin.starredRouteId,
    title: 'Starred',
    icon: DIcons.star,
  );

  static ContentRoute _chatDirectMessagesRoute() => const ContentRoute(
    id: ChatPlugin.directMessagesRouteId,
    title: 'Chat',
    icon: DIcons.users,
  );

  static ContentRoute _chatMyThreadsRoute() => const ContentRoute(
    id: ChatPlugin.myThreadsRouteId,
    title: 'My threads',
    icon: DIcons.comments,
  );

  static const Set<String> _drawerRoutesWithoutBack = {
    ChatPlugin.channelsRouteId,
    ChatPlugin.starredRouteId,
    ChatPlugin.directMessagesRouteId,
    ChatPlugin.myThreadsRouteId,
    ChatPlugin.searchRouteId,
  };

  List<ContentRoute> _fullPageRoutesForDrawer(List<ContentRoute> routes) {
    if (routes.isEmpty) return routes;
    final first = routes.first;
    ContentRoute? parent;
    final chatRoute = ChatRoute.parse(first.id);
    if (chatRoute != null && (chatRoute.isThread || chatRoute.isInfo)) {
      parent = _drawerChannelRoute(chatRoute.channelId);
    } else {
      final channelId = ChatPlugin.channelIdFromThreadsRoute(first.id);
      if (channelId != null) parent = _drawerChannelRoute(channelId);
    }
    if (parent == null || parent.id == first.id) return routes;
    return [parent, ...routes];
  }

  void _restoreFullPageStack(List<ContentRoute> routes) {
    if (routes.isEmpty || _host.currentInstance == null) return;
    final first = routes.first;
    _host.selectDestination(
      SidebarDestination(id: first.id, label: first.title, icon: first.icon),
    );
    for (final route in routes.skip(1)) {
      _host.pushContent(route);
    }
    if (ChatRoute.parse(routes.last.id) case final route?) {
      navigation.offer(
        ChatNavigationTarget(siteUrl: currentSiteUrl!, route: route),
      );
    }
    _host.showPluginContent();
  }

  bool _openInfoRoute(
    String siteUrl,
    ChatChannel channel,
    ChatRoute route, {
    bool forceFullPage = false,
  }) {
    if (_host.currentInstance?.url != siteUrl || !route.isInfo) return false;
    if (!forceFullPage && _shouldNavigateDrawer) {
      _openDrawerRoute(
        ContentRoute(
          id: route.routeId,
          title: channel.title,
          subtitle: switch (route.infoTab) {
            ChatChannelInfoTab.members => 'Members',
            _ => 'Settings',
          },
          icon: DIcons.comment,
        ),
      );
      return true;
    }
    _activateSeparatedPane();
    final currentRoute = switch (_host.currentContent?.id) {
      final id? => ChatRoute.parse(id),
      null => null,
    };
    final content = ContentRoute(
      id: route.routeId,
      title: channel.title,
      icon: DIcons.comment,
    );
    if (currentRoute?.isInfo == true && currentRoute?.channelId == channel.id) {
      _host.replaceCurrentContent(content);
    } else {
      if (currentRoute?.channelId != channel.id ||
          currentRoute?.isThread == true) {
        _host.selectDestination(ChatPlugin.destination(channel));
      }
      _host.pushContent(content);
    }
    return true;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _host.changes.removeListener(_handleHostChanged);
    _endDrawerViewing();
    navigation.dispose();
    _changes.dispose();
  }
}
