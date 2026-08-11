import 'package:flutter/material.dart';

import '../../models/content_route.dart';
import '../../models/sidebar.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin.dart';
import 'chat_channel.dart';
import 'chat_channel_view.dart';

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
/// only whether to **ask**. What comes back still decides whether to **draw**:
/// nothing here is drawn from a setting, the sections exist because there are
/// channels.
///
/// Which is also why there is no loading state and no empty heading. A heading
/// that appears and then vanishes is worse than one that arrives late, and a
/// section with a spinner in it says something false about how many channels
/// there are.
class ChatPlugin implements SitePlugin, SidebarPlugin, ContentPlugin {
  const ChatPlugin();

  @override
  String get name => 'chat';

  @override
  List<SidebarSection> sidebarSections(BuildContext context) {
    final controller = ShellScope.read(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return const [];

    final starred = controller.chat.starredChannels(siteUrl);
    final public = controller.chat.unstarredPublicChannels(siteUrl);
    final direct = controller.chat.unstarredDirectChannels(siteUrl);

    // Nothing before the answer, and nothing after an answer with no channels
    // in it. A heading with no rows under it says something that is not true.
    return [
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
      ShellScope.read(context).chat;

  @override
  Widget? content(BuildContext context, ContentRoute route) {
    final channelId = ChatChannel.channelIdIn(route.id);
    if (channelId == null) return null;
    return ChatChannelView(channelId: channelId);
  }

  /// One channel as a sidebar row.
  ///
  /// A conversation with one other person shows their face; a group shows the
  /// glyph for several people; a channel shows its emoji, or `comment` — which
  /// is what Discourse's own `d-chat` resolves to — tinted with the colour of
  /// the category it lives in.
  static SidebarDestination destination(ChatChannel channel) =>
      SidebarDestination(
        id: ChatChannel.routeId(channel.id),
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
        badge: channel.badge,
      );
}
