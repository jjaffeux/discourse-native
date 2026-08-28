import 'dart:async';

import '../../data/site_tracker.dart';
import '../../data/store.dart';
import '../../models/bookmark.dart';
import '../../models/content_route.dart';
import '../../models/notification_totals.dart';
import '../../plugin_api/plugin_manifest.dart';
import '../../plugin_api/plugin_runtime.dart';
import '../../plugin_api/shell_extensions.dart';
import '../../shell/site_url.dart';
import '../../theme/d_icons.dart';
import 'chat_bookmark.dart';
import 'chat_channel.dart';
import 'chat_controller.dart';
import 'chat_message.dart';
import 'chat_plugin.dart';
import 'chat_plugin_data.dart';
import 'chat_route.dart';
import 'chat_services.dart';
import 'chat_stream_target.dart';

const chatShellService = PluginServiceKey<ChatShellService>(
  owner: chatPluginId,
  name: 'shell',
);

/// Chat's routing, hydration, and bookmark integration for one shell session.
final class ChatShellService
    implements
        PluginLinkHandler,
        PluginRouteRetry,
        PluginRouteHydrator,
        PluginTotalsObserver,
        PluginTrackerAttachment,
        PluginBookmarkTargetStrategy {
  ChatShellService({
    required this.chat,
    required this.host,
    required this.store,
  });

  final ChatController chat;
  final PluginNavigationHost host;
  final Store store;
  final ChatNavigationHandoff navigation = ChatNavigationHandoff();
  int _urlOpenGeneration = 0;

  @override
  Future<bool> openPluginUrl(String url) async {
    final generation = ++_urlOpenGeneration;
    final absolute = resolveSiteUrl(url, host.currentInstance?.url);
    final link = ChatLink.parse(absolute);
    if (link == null) return false;

    var index = host.instances.indexWhere(
      (instance) => instance.serves(link.uri),
    );
    if (index < 0 || !host.instances[index].isConnected) return false;

    final siteUrl = host.instances[index].url;
    await chat.loadChannels(siteUrl);
    if (host.isDisposed || generation != _urlOpenGeneration) return false;
    if (chat.channel(siteUrl, link.route.channelId) == null) return false;
    if (link.route.threadId case final threadId?) {
      final detail = await chat.refreshThreadDetail(
        siteUrl,
        ChatThreadTarget(channelId: link.route.channelId, threadId: threadId),
      );
      if (host.isDisposed || generation != _urlOpenGeneration) return false;
      if (detail == null) return false;
    }

    index = host.instances.indexWhere((instance) => instance.url == siteUrl);
    if (index < 0 || !host.instances[index].isConnected) return false;
    if (host.currentInstance?.url != siteUrl) host.selectInstance(index);
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
  void attachPluginTracker(String siteUrl, SiteTracker tracker) =>
      chat.attachTracker(siteUrl, tracker);

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
    final message = store.read<ChatMessage>(siteUrl, targetId);
    if (message != null) await chat.reconcileMessageBookmark(siteUrl, message);
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
    final index = host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !host.instances[index].isConnected) return;
    if (host.currentInstance?.url != siteUrl) host.selectInstance(index);
    _openRoute(
      siteUrl,
      ChatRoute.thread(channelId: channelId, threadId: threadId),
      messageId: messageId,
      focusComposer: focusComposer,
    );
  }

  bool openChannel(int channelId, {int? messageId}) {
    if (channelId <= 0 || (messageId != null && messageId <= 0)) return false;
    final instance = host.currentInstance;
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
    final index = host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !host.instances[index].isConnected) return false;
    final channel = chat.channel(siteUrl, channelId);
    if (channel == null) return false;
    if (host.currentInstance?.url != siteUrl) host.selectInstance(index);
    return _openInfoRoute(
      siteUrl,
      channel,
      ChatRoute.info(channelId: channelId, tab: tab),
    );
  }

  bool openChannelThreads({required String siteUrl, required int channelId}) {
    if (channelId <= 0) return false;
    final index = host.instances.indexWhere(
      (instance) => instance.url == siteUrl,
    );
    if (index < 0 || !host.instances[index].isConnected) return false;
    final channel = chat.channel(siteUrl, channelId);
    if (channel?.threadingEnabled != true) return false;
    if (host.currentInstance?.url != siteUrl) host.selectInstance(index);

    final routeId = ChatPlugin.channelThreadsRouteId(channelId);
    if (host.currentContent?.id != routeId) {
      final currentChatRoute = switch (host.currentContent?.id) {
        final id? => ChatRoute.parse(id),
        null => null,
      };
      if (currentChatRoute?.channelId != channelId ||
          currentChatRoute?.isThread == true) {
        host.selectDestination(ChatPlugin.destination(channel!));
      }
      host.pushContent(
        ContentRoute(
          id: routeId,
          title: 'Threads',
          subtitle: channel!.title,
          icon: DIcons.comments,
        ),
      );
    }
    host.showPluginContent();
    return true;
  }

  bool revealChannelMessage({
    required String siteUrl,
    required int channelId,
    required int messageId,
  }) {
    if (channelId <= 0 ||
        messageId <= 0 ||
        host.currentInstance?.url != siteUrl ||
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
    final route = host.currentContent;
    final chatRoute = route == null ? null : ChatRoute.parse(route.id);
    final channel = chat.channel(siteUrl, channelId);
    if (channelId <= 0 ||
        chatRoute?.channelId != channelId ||
        channel == null) {
      return 'The topic composer is no longer available here.';
    }
    return host.insertPluginTranscriptIntoNewTopic(
      siteUrl: siteUrl,
      sourceRouteId: route!.id,
      markdown: markdown,
      initialCategoryId: channel.isCategoryChannel ? channel.chatableId : null,
    );
  }

  Future<void> openShortcut() async {
    final instance = host.currentInstance;
    if (instance == null || !instance.isConnected) return;
    final totals = host.currentTotals;
    if (totals?.hasChatEnabled != true ||
        instance.user?.hasChatEnabled == false) {
      return;
    }
    final siteUrl = instance.url;
    await chat.loadChannels(siteUrl);
    if (host.currentInstance?.url != siteUrl) return;
    final channel = chat.shortcutChannel(
      siteUrl,
      lastChannelId: host.currentInstance?.user?.lastChatChannelId,
    );
    if (channel != null) {
      host.selectDestination(ChatPlugin.destination(channel));
    }
  }

  bool _openRoute(
    String siteUrl,
    ChatRoute route, {
    int? messageId,
    bool focusComposer = false,
  }) {
    if (host.currentInstance?.url != siteUrl) return false;
    final channel = chat.channel(siteUrl, route.channelId);
    if (channel == null) return false;
    if (route.isInfo) return _openInfoRoute(siteUrl, channel, route);

    final currentRoute = switch (host.currentContent?.id) {
      final id? => ChatRoute.parse(id),
      null => null,
    };
    if (route.isThread) {
      if (currentRoute != route) {
        final currentThreadsChannelId = switch (host.currentContent?.id) {
          final id? => ChatPlugin.channelIdFromThreadsRoute(id),
          null => null,
        };
        final preservesThreadList =
            host.currentContent?.id == ChatPlugin.myThreadsRouteId ||
            currentThreadsChannelId == route.channelId;
        if (currentRoute?.threadId != null ||
            !preservesThreadList &&
                currentRoute?.channelId != route.channelId) {
          host.selectDestination(ChatPlugin.destination(channel));
        }
        host.pushContent(
          ContentRoute(
            id: route.routeId,
            title: 'Thread',
            subtitle: channel.title,
            icon: DIcons.comments,
          ),
        );
      }
    } else if (currentRoute != route || host.contentStack.length != 1) {
      host.selectDestination(ChatPlugin.destination(channel));
    }

    navigation.offer(
      ChatNavigationTarget(
        siteUrl: siteUrl,
        route: route,
        messageId: messageId,
        focusComposer: focusComposer,
      ),
    );
    host.showPluginContent();
    return true;
  }

  bool _openInfoRoute(String siteUrl, ChatChannel channel, ChatRoute route) {
    if (host.currentInstance?.url != siteUrl || !route.isInfo) return false;
    final currentRoute = switch (host.currentContent?.id) {
      final id? => ChatRoute.parse(id),
      null => null,
    };
    final content = ContentRoute(
      id: route.routeId,
      title: channel.title,
      icon: DIcons.comment,
    );
    if (currentRoute?.isInfo == true && currentRoute?.channelId == channel.id) {
      host.replaceCurrentContent(content);
    } else {
      if (currentRoute?.channelId != channel.id ||
          currentRoute?.isThread == true) {
        host.selectDestination(ChatPlugin.destination(channel));
      }
      host.pushContent(content);
    }
    return true;
  }

  void dispose() => navigation.dispose();
}
