import 'package:flutter/material.dart';

import '../../models/content_route.dart';
import '../../models/sidebar.dart';
import '../../models/user_card.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../plugin_scope.dart';
import '../plugin_services.dart';
import '../site_plugin_api.dart';
import 'chat_channel.dart';
import 'chat_channel_search.dart';
import 'chat_channel_view.dart';
import 'chat_header_button.dart';
import 'chat_route.dart';
import 'chat_search_view.dart';
import 'chat_thread_view.dart';
import 'chat_user_card.dart';

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
        SidebarPlugin,
        ContentPlugin,
        ContentChromePlugin,
        ContentHeaderPlugin,
        ShellHeaderPlugin,
        UserCardRecordPlugin<ChatUserCardData>,
        UserCardActionPlugin {
  const ChatPlugin();

  static const String searchRouteId = 'chat-search';

  @override
  String get name => 'chat';

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
    final searchEnabled =
        controller.currentInstance?.isConnected == true &&
        controller.currentInstance?.config.chatSearchEnabled == true &&
        controller.currentInstance?.user?.hasChatEnabled != false &&
        controller.currentTotals?.hasChatEnabled == true;

    // Nothing before the answer, and nothing after an answer with no channels
    // in it. A heading with no rows under it says something that is not true.
    return [
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
          destinations: [for (final channel in starred) destination(channel)],
        ),
      if (public.isNotEmpty)
        SidebarSection(
          id: 'chat',
          title: 'Chat',
          destinations: [for (final channel in public) destination(channel)],
        ),
      if (direct.isNotEmpty)
        SidebarSection(
          id: 'direct-messages',
          title: 'Direct messages',
          destinations: [for (final channel in direct) destination(channel)],
        ),
    ];
  }

  @override
  Listenable sidebarListenable(BuildContext context) =>
      PluginScope.require(context, chatControllerService);

  @override
  Widget? content(BuildContext context, ContentRoute route) {
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
    return [
      ChatChannelSearchButton(siteUrl: siteUrl, channelId: chatRoute.channelId),
    ];
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
  static SidebarDestination destination(ChatChannel channel) =>
      SidebarDestination(
        id: ChatRoute.channel(channel.id).routeId,
        label: channel.title,
        icon: switch (channel.kind) {
          ChatChannelKind.directMessage when channel.users.length > 1 =>
            DIcons.users,
          ChatChannelKind.directMessage => DIcons.user,
          _ => DIcons.comment,
        },
        emoji: channel.emoji,
        avatarUrl: channel.avatarUrl,
        avatarUserId: channel.isDirectMessage && channel.users.length == 1
            ? channel.users.first.id
            : null,
        iconColor: channel.categoryColor,
        prefixBadgeIcon: channel.isCategoryChannel && channel.readRestricted
            ? DIcons.lock
            : null,
        badge: channel.badge,
      );
}
