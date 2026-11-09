import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:flutter/widgets.dart';

import 'chat_channel.dart';
import 'chat_route.dart';

/// The sidebar row for [channel]. The builders stay optional because code
/// that only selects a destination, such as Chat's navigation service, has no
/// views to attach and must not depend on the libraries that define them.
SidebarDestination chatChannelDestination(
  ChatChannel channel, {
  VoidCallback? onTap,
  SidebarRowDecorationBuilder? prefixBuilder,
  SidebarRowDecorationBuilder? labelSuffixBuilder,
  Widget Function(BuildContext context, Widget child)? contextMenuBuilder,
}) => SidebarDestination(
  id: ChatRoute.channel(channel.id).routeId,
  label: channel.title,
  icon: switch (channel.kind) {
    ChatChannelKind.directMessage when channel.users.length > 1 => DIcons.users,
    ChatChannelKind.directMessage => DIcons.user,
    _ => DIcons.comment,
  },
  emoji: channel.emoji,
  avatarUrl: channel.avatarUrl,
  prefixBuilder: prefixBuilder,
  labelSuffixBuilder: labelSuffixBuilder,
  semanticDescription: channel.directUser?.status?.description,
  iconColor: channel.categoryColor,
  prefixBadgeIcon: channel.isCategoryChannel && channel.readRestricted
      ? DIcons.lock
      : null,
  badge: channel.badge,
  unreadCount: channel.tracking.unreadCount,
  preview: channel.lastMessagePreview,
  lastActivityAt: channel.lastMessageAt,
  onTap: onTap,
  contextMenuBuilder: contextMenuBuilder,
);
