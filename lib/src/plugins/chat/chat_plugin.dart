import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;

import '../../models/content_route.dart';
import '../../models/post.dart';
import '../../models/sidebar.dart';
import '../../shell/composer_controller.dart';
import '../../shell/shell_scope.dart';
import '../../theme/d_icons.dart';
import '../site_plugin.dart';
import 'chat_channel.dart';
import 'chat_channel_view.dart';

/// `chat`, as this app knows it.
///
/// The plugin gives a site channels and direct messages to read alongside its
/// topics. It is the first optional feature here that owns *navigation* and a
/// *screen* rather than decorating a record, which is why [SitePlugin] grew
/// [sidebarSections] and [content] for it.
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
class ChatPlugin implements SitePlugin<ChatChannel> {
  const ChatPlugin();

  @override
  String get name => 'chat';

  /// Named so the interface has an answer. Chat decorates no post, so nothing
  /// is ever filed under this and nothing looks it up — see [readPost].
  @override
  Type get record => ChatChannel;

  /// Always null. Chat is the first feature here that does not ride a payload
  /// this app was going to read anyway, which is the same fact that stops it
  /// using the enablement signal the rest of this interface turns on.
  @override
  ChatChannel? readPost(Map<String, dynamic> json, String siteUrl) => null;

  @override
  Widget? postBodyElement(String siteUrl, Post post, dom.Element element) =>
      null;

  @override
  List<ComposerToolbarContribution> composerToolbar(
    BuildContext context,
    ComposerController composer,
  ) => const [];

  @override
  ChatChannel? mergeAfterPostEdit(ChatChannel? held, ChatChannel? incoming) =>
      incoming;

  @override
  Widget? postFooter(String siteUrl, Post post) => null;

  @override
  PostMenuContribution postMenu(
    BuildContext context,
    String siteUrl,
    Post post,
  ) => PostMenuContribution.none;

  /// Nothing yet. Reading a channel live rides `/chat/:id` and the per-user
  /// tracking channel, neither of which is a topic — and `SiteTracker` watches
  /// exactly one topic at a time, so those want a subscription concept of their
  /// own rather than this hook.
  @override
  List<String> topicChannels(int topicId) => const [];

  @override
  List<int> stalePosts(String channel, Object? data) => const [];

  @override
  List<SidebarSection> sidebarSections(BuildContext context) {
    final controller = ShellScope.read(context);
    final siteUrl = controller.currentInstance?.url;
    if (siteUrl == null) return const [];

    final public = controller.chat.publicChannels(siteUrl);
    final direct = controller.chat.directChannels(siteUrl);

    // Nothing before the answer, and nothing after an answer with no channels
    // in it. A heading with no rows under it says something that is not true.
    return [
      if (public.isNotEmpty)
        SidebarSection(
          title: 'Chat',
          destinations: [for (final channel in public) _destination(channel)],
        ),
      if (direct.isNotEmpty)
        SidebarSection(
          title: 'Direct messages',
          destinations: [for (final channel in direct) _destination(channel)],
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
  SidebarDestination _destination(ChatChannel channel) => SidebarDestination(
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
    iconColor: channel.categoryColor,
    badge: channel.badge,
  );
}
