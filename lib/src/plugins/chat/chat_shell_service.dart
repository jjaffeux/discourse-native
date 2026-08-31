// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/store.dart';
import '../../models/bookmark.dart';
import '../../models/content_route.dart';
import '../../models/discourse_user.dart';
import '../../models/notification_totals.dart';
import '../../models/post_flag.dart';
import '../../models/sidebar.dart';
import '../../plugin_api/core_plugin_host.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_runtime.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'chat_bookmark.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
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
        PluginTotalsObserver,
        PluginTrackerAttachment,
        PluginBookmarkTargetStrategy {
  ChatShellService({
    required this.chat,
    required PluginNavigationHost host,
    required this.composerHost,
    required this.store,
    required PluginPostFlagCatalogReader postFlagCatalog,
  }) : _host = host,
       _postFlagCatalog = postFlagCatalog;

  final ChatController chat;
  final PluginComposerHost composerHost;
  final Store store;
  final PluginNavigationHost _host;
  final PluginPostFlagCatalogReader _postFlagCatalog;
  final ChatNavigationHandoff navigation = ChatNavigationHandoff();
  int _urlOpenGeneration = 0;

  @override
  void addListener(VoidCallback listener) =>
      _host.changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _host.changes.removeListener(listener);

  String? get currentSiteUrl => _host.currentInstance?.url;
  bool get showHeaderShortcut =>
      _host.forumActive && _host.currentInstance != null;
  DiscourseUser? get currentUser => _host.currentInstance?.user;
  NotificationTotals? get currentTotals => _host.currentTotals;
  ContentRoute? get currentContent => _host.currentContent;
  bool get chatActive =>
      ChatRoute.parse(_host.currentContent?.id ?? '') != null;

  bool isConnected(String siteUrl) =>
      _host.currentInstance?.url == siteUrl &&
      _host.currentInstance?.isConnected == true;

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

  @override
  Future<bool> openPluginUrl(String url) async {
    final generation = ++_urlOpenGeneration;
    final absolute = resolveSiteUrl(url, _host.currentInstance?.url);
    final link = ChatLink.parse(absolute);
    if (link == null) return false;

    var index = _host.instances.indexWhere(
      (instance) => instance.serves(link.uri),
    );
    if (index < 0 || !_host.instances[index].isConnected) return false;

    final siteUrl = _host.instances[index].url;
    await chat.loadChannels(siteUrl);
    if (_host.isDisposed || generation != _urlOpenGeneration) return false;
    if (chat.channel(siteUrl, link.route.channelId) == null) return false;
    if (link.route.threadId case final threadId?) {
      final detail = await chat.refreshThreadDetail(
        siteUrl,
        ChatThreadTarget(channelId: link.route.channelId, threadId: threadId),
      );
      if (_host.isDisposed || generation != _urlOpenGeneration) return false;
      if (detail == null) return false;
    }

    index = _host.instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !_host.instances[index].isConnected) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);
    return _openRoute(siteUrl, link.route, messageId: link.messageId);
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
  bool handlesPluginRoute(String routeId) => ChatRoute.parse(routeId) != null;

  @override
  Future<void> hydratePluginRoute(String siteUrl, String routeId) =>
      chat.loadChannels(siteUrl);

  @override
  Future<void> pluginTotalsLoaded(
    String siteUrl,
    NotificationTotals totals, {
    required bool selected,
  }) async {
    if (selected && totals.hasChatEnabled == true) {
      await chat.loadChannels(siteUrl);
    }
  }

  @override
  void attachPluginTracker(String siteUrl, PluginLiveChannelHandle channels) =>
      chat.attachTracker(siteUrl, channels);

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

  void openBrowseChannels() => _host.selectDestination(
    const SidebarDestination(
      id: ChatPlugin.browseRouteId,
      label: 'Browse channels',
      icon: DIcons.list,
    ),
  );

  void returnToChannel(int channelId) => openChannel(channelId);

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
    if (instance == null || !instance.isConnected) return false;
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
    final channel = chat.channel(siteUrl, channelId);
    if (channel?.threadingEnabled != true) return false;
    if (_host.currentInstance?.url != siteUrl) _host.selectInstance(index);

    final routeId = ChatPlugin.channelThreadsRouteId(channelId);
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
    final route = _host.currentContent;
    final chatRoute = route == null ? null : ChatRoute.parse(route.id);
    final channel = chat.channel(siteUrl, channelId);
    if (markdown.trim().isEmpty ||
        channelId <= 0 ||
        chatRoute?.channelId != channelId ||
        channel == null) {
      return 'The topic composer is no longer available here.';
    }
    final result = await composerHost.openNewTopic(
      OpenNewTopicComposerRequest(
        siteUrl: siteUrl,
        sourceRouteId: route!.id,
        seed: ComposerSeed(raw: markdown),
        initialCategoryId: channel.isCategoryChannel
            ? channel.chatableId
            : null,
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
    if (_host.currentInstance?.url != siteUrl) return;
    final channel = chat.shortcutChannel(
      siteUrl,
      lastChannelId: _host.currentInstance?.user?.lastChatChannelId,
    );
    if (channel != null) {
      _host.selectDestination(ChatPlugin.destination(channel));
    }
  }

  bool _openRoute(
    String siteUrl,
    ChatRoute route, {
    int? messageId,
    bool focusComposer = false,
  }) {
    if (_host.currentInstance?.url != siteUrl) return false;
    final channel = chat.channel(siteUrl, route.channelId);
    if (channel == null) return false;
    if (route.isInfo) return _openInfoRoute(siteUrl, channel, route);

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

  void dispose() => navigation.dispose();
}
