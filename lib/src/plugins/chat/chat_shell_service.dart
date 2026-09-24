// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/foundation.dart';

import 'chat_bookmark.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_notification_counter.dart';
import 'chat_plugin.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_services.dart';
import 'chat_stream_target.dart';
import 'chat_user_preferences.dart';
import 'chat_wire.dart';

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
        PluginCurrentUserObserver,
        PluginBookmarkPresenter,
        PluginBookmarkTargetStrategy {
  ChatShellService({
    required this.chat,
    required PluginNavigationHost host,
    required this.composerHost,
    required this.store,
    required PluginPostFlagCatalogReader postFlagCatalog,
  }) : _host = host,
       _postFlagCatalog = postFlagCatalog {
    _lastHostPresentation = _hostPresentation;
    _lastHostInstance = _host.currentInstance;
    _host.changes.addListener(_handleHostChanged);
  }

  final ChatController chat;
  final PluginComposerHost composerHost;
  final Store store;
  final PluginNavigationHost _host;
  final PluginPostFlagCatalogReader _postFlagCatalog;
  final ChatNavigationHandoff navigation = ChatNavigationHandoff();
  final ValueNotifier<int> _changes = ValueNotifier(0);
  int _urlOpenGeneration = 0;
  bool _disposed = false;
  Object? _lastHostPresentation;
  DiscourseInstance? _lastHostInstance;

  // Topic pagination and reading progress notify the host without changing
  // anything exposed by this service. Do not rebuild chat chrome and sidebar
  // panels for those updates. Commands still read the host directly.
  Object get _hostPresentation => (
    _host.currentContent,
    _host.currentTotals,
    _host.forumActive,
    _host.readerContentBounds,
    _currentSiteCanUseChat,
    currentSiteUrl == null ? false : doNotDisturbActive(currentSiteUrl!),
    separateSidebarMode,
  );
  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  String? get currentSiteUrl => _host.currentInstance?.url;
  bool get forumActive => _host.forumActive;
  bool get desktopPanelsEnabled => _host.desktopPanelsEnabled;
  bool get showHeaderShortcut =>
      _host.forumActive && _host.currentInstance != null;
  DiscourseUser? get currentUser => _host.currentInstance?.user;
  NotificationTotals? get currentTotals => _host.currentTotals;
  ContentRoute? get currentContent => _host.currentContent;
  bool get fullPageChatActive =>
      ChatPlugin.ownsRouteId(_host.currentContent?.id);
  int? get visibleChannelId {
    if (!fullPageChatActive) return null;
    final id = currentContent?.id;
    if (id == null) return null;
    return ChatRoute.parse(id)?.channelId ??
        ChatPlugin.channelIdFromThreadsRoute(id);
  }

  bool get chatActive => fullPageChatActive;

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

  void _handleHostChanged() {
    if (_disposed) return;
    final presentation = _hostPresentation;
    if (!identical(_host.currentInstance, _lastHostInstance) ||
        presentation != _lastHostPresentation) {
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) {
      _lastHostPresentation = _hostPresentation;
      _lastHostInstance = _host.currentInstance;
      _changes.value++;
    }
  }

  @override
  Future<bool> openPluginUrl(
    String url, {
    PluginLinkOrigin origin = PluginLinkOrigin.direct,
  }) async {
    final absolute = resolveSiteUrl(url, _host.currentInstance?.url);
    final target = Uri.tryParse(absolute);
    if (target == null) return false;
    var index = _host.instances.indexWhere(
      (instance) => instance.serves(target),
    );
    // A link shaped like a chat route states the latest intent even when it
    // turns out to point nowhere this app can go; only then is the site
    // checked, so an earlier open completing late still stands down.
    final link = ChatLink.parse(
      absolute,
      siteUrl: index < 0 ? null : _host.instances[index].url,
    );
    if (link == null) return false;
    final generation = ++_urlOpenGeneration;
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

    index = _host.instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !_host.instances[index].isConnected) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);
    return _openRoute(
      siteUrl,
      link.route,
      messageId: link.messageId,
      mainPanel:
          origin == PluginLinkOrigin.mainPanel ||
          origin == PluginLinkOrigin.mainPanelNewTab,
      secondaryPanel:
          origin == PluginLinkOrigin.secondaryPanel ||
          origin == PluginLinkOrigin.secondaryPanelNewTab,
      newTab:
          origin == PluginLinkOrigin.newTab ||
          origin == PluginLinkOrigin.mainPanelNewTab ||
          origin == PluginLinkOrigin.secondaryPanelNewTab,
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

  final _routeRefreshers = <(String, String), Future<void> Function()>{};

  VoidCallback registerRouteRefresher(
    String siteUrl,
    String routeId,
    Future<void> Function() refresh,
  ) {
    final key = (siteUrl, routeId);
    _routeRefreshers[key] = refresh;
    return () {
      if (identical(_routeRefreshers[key], refresh)) {
        _routeRefreshers.remove(key);
      }
    };
  }

  @override
  PluginId get pluginPaneOwner => chatPluginId;

  @override
  bool ownsPluginPaneRoute(String routeId) => ChatPlugin.ownsRouteId(routeId);

  @override
  bool separatesPluginPane(String routeId) =>
      ChatPlugin.ownsRouteId(routeId) &&
      separateSidebarMode != ChatSeparateSidebarMode.never;

  @override
  Future<void> hydratePluginRoute(
    String siteUrl,
    String routeId, {
    bool force = false,
  }) async {
    if (!force) {
      await chat.loadChannels(siteUrl);
    } else if (_routeRefreshers[(siteUrl, routeId)] case final refresh?) {
      await refresh();
    } else if (ChatRoute.parse(routeId) != null) {
      await retryPluginRoute(siteUrl, routeId);
    } else if (routeId == ChatPlugin.myThreadsRouteId) {
      await chat.loadMyThreads(siteUrl, force: true);
    } else if (ChatPlugin.channelIdFromThreadsRoute(routeId)
        case final channelId?) {
      await chat.loadChannelThreads(siteUrl, channelId, force: true);
    } else {
      await chat.loadChannels(siteUrl, force: true);
    }
  }

  @override
  Future<void> pluginTotalsLoaded(
    String siteUrl,
    NotificationTotals totals, {
    required bool selected,
  }) async {
    if (!selected) return;
    if (totals.hasChatEnabled != true) {
      return;
    }
    await chat.loadChannels(siteUrl);
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      chat.attachTracker(siteUrl, channels);

  @override
  void pluginCurrentUserRefreshed(String siteUrl) =>
      chat.channelListPreferences.refresh(siteUrl);

  @override
  DiscourseUser mirrorUserPreference(
    DiscourseUser user,
    PreferenceSection section,
    UserPreferences preferences,
  ) {
    if (section != chatPreferenceSection) return user;
    final held = user.chatCurrentUser ?? const ChatCurrentUser();
    final updated = ChatCurrentUser(
      sendShortcut: held.sendShortcut,
      hasChatEnabled: held.hasChatEnabled,
      canChat: held.canChat,
      canDirectMessage: held.canDirectMessage,
      headerIndicatorPreference: held.headerIndicatorPreference,
      separateSidebarMode: switch (preferences
          .chatPreferences
          .separateSidebarMode) {
        ChatSeparateSidebarPreference.siteDefault =>
          ChatSeparateSidebarMode.siteDefault,
        ChatSeparateSidebarPreference.always => ChatSeparateSidebarMode.always,
        ChatSeparateSidebarPreference.fullscreen =>
          ChatSeparateSidebarMode.fullscreen,
        ChatSeparateSidebarPreference.never => ChatSeparateSidebarMode.never,
      },
      lastChannelId: held.lastChannelId,
      ignoredUsernames: held.ignoredUsernames,
      channelListPreferences: held.channelListPreferences,
    );
    return user.withPlugins(
      user.plugins.withValue(chatCurrentUserDataKey, updated),
    );
  }

  @override
  BookmarkTargetType get pluginBookmarkTarget => chatMessageBookmarkTarget;

  @override
  String get bookmarkFilterLabel => 'Chat';

  @override
  BookmarkPresentation? presentBookmark(String siteUrl, Bookmark bookmark) {
    if (bookmark.bookmarkableType != chatMessageBookmarkTarget.wireName &&
        bookmark.bookmarkableType != chatMessagePolymorphicWireType) {
      return null;
    }
    final link = ChatLink.parse(bookmark.path ?? '', siteUrl: siteUrl);
    final channel = link == null
        ? null
        : chat.channel(siteUrl, link.route.channelId);
    final title = channel?.title ?? bookmark.title;
    final username = _host.instances
        .where((instance) => instance.url == siteUrl)
        .firstOrNull
        ?.user
        ?.username;
    final author =
        bookmark.author != null &&
            bookmark.author!.toLowerCase() == username?.toLowerCase()
        ? 'you'
        : bookmark.author;
    final channelLabel = channel?.isDirectMessage == true
        ? title
        : '#${title.replaceFirst(RegExp(r'^#'), '')}';
    return BookmarkPresentation(
      title: title.isEmpty
          ? '${author ?? 'Someone'} in chat'
          : '${author ?? 'Someone'} in $channelLabel',
      typeLabel: 'Chat',
      filterLabel: bookmarkFilterLabel,
      contextLabel: title.isEmpty ? null : title,
      icon: DIcons.comment,
      color: channel?.categoryColor,
    );
  }

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

  void openChannels() {
    _activateSeparatedPane();
    _host.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.channelsRouteId,
        label: 'Chat',
        icon: DIcons.comments,
      ),
    );
  }

  void openBrowseChannels() {
    _activateSeparatedPane();
    _host.selectDestination(
      const SidebarDestination(
        id: ChatPlugin.browseRouteId,
        label: 'Browse channels',
        icon: DIcons.list,
      ),
    );
  }

  void openMyThreads() {
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
    if (desktopPanelsEnabled) {
      _host.pushContent(
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
    bool sourceStillCurrent() =>
        !_disposed && _host.currentContent?.id == shellRoute.id;
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

  Future<void> openShortcut() async {
    final instance = _host.currentInstance;
    if (instance == null || !instance.isConnected) return;
    final totals = _host.currentTotals;
    if (totals?.hasChatEnabled != true ||
        instance.user?.hasChatEnabled == false) {
      return;
    }
    final siteUrl = instance.url;
    await chat.loadChannels(siteUrl);
    if (_host.isDisposed || _host.currentInstance?.url != siteUrl) return;

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

  void closeSidebarPanel() {
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
      separateSidebarMode != ChatSeparateSidebarMode.never;

  bool _openRoute(
    String siteUrl,
    ChatRoute route, {
    int? messageId,
    bool focusComposer = false,
    bool mainPanel = false,
    bool secondaryPanel = false,
    bool newTab = false,
  }) {
    if (_host.currentInstance?.url != siteUrl) return false;
    final channel = chat.channel(siteUrl, route.channelId);
    if (channel == null) return false;
    if (desktopPanelsEnabled) {
      _host.pushContent(
        ContentRoute(
          id: route.routeId,
          title: route.isThread ? 'Thread' : channel.title,
          subtitle: route.isThread ? channel.title : null,
          icon: route.isThread ? DIcons.comments : DIcons.comment,
          openInMainPanel: mainPanel,
          openInSecondaryPanel: secondaryPanel,
        ),
        newTab: newTab,
      );
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
    if (route.isInfo) {
      return _openInfoRoute(siteUrl, channel, route);
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

  bool _openInfoRoute(String siteUrl, ChatChannel channel, ChatRoute route) {
    if (_host.currentInstance?.url != siteUrl || !route.isInfo) return false;
    if (desktopPanelsEnabled) return _openRoute(siteUrl, route);

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
    _routeRefreshers.clear();
    navigation.dispose();
    _changes.dispose();
  }
}
