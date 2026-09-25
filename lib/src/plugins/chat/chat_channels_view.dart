import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_channel_list_actions.dart';
import 'chat_channel_list_preferences.dart';
import 'chat_new_direct_message.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

enum ChatChannelListKind { channels, starred, directMessages }

class ChatChannelsView extends StatelessWidget {
  const ChatChannelsView({
    super.key,
    required this.siteUrl,
    required this.kind,
    this.header,
  });

  final String siteUrl;
  final ChatChannelListKind kind;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final section = switch (kind) {
          ChatChannelListKind.channels => ChatChannelListSection.channels,
          ChatChannelListKind.starred => ChatChannelListSection.starred,
          ChatChannelListKind.directMessages =>
            ChatChannelListSection.directMessages,
        };
        final channels = chat.channelList(
          siteUrl,
          section,
          sidebar: false,
          activeChannelId: shell.visibleChannelId,
        );
        final loading =
            !chat.channelsLoaded(siteUrl) &&
            chat.channelsError(siteUrl) == null;
        final filtered =
            !chat.channelListPreferences.bypassed(siteUrl, section) &&
            chat.channelListPreferences
                    .preferencesFor(siteUrl)
                    .filterFor(section) !=
                ChatChannelListFilter.all;
        final action = switch (kind) {
          ChatChannelListKind.channels
              when chat
                  .siteConfigFor(siteUrl)
                  .chatSettings
                  .publicChannelsEnabled =>
            _ChannelListListAction(
              key: const ValueKey('chat-channel-list-browse-action'),
              label: 'Browse',
              tooltip: 'Browse channels',
              icon: DIcons.plus,
              onPressed: shell.openBrowseChannels,
            ),
          ChatChannelListKind.directMessages
              when shell.currentUser?.staff == true ||
                  shell.currentUser?.canDirectMessage == true =>
            _ChannelListListAction(
              key: const ValueKey('chat-channel-list-new-message-action'),
              label: 'New',
              tooltip: 'New message',
              icon: DIcons.plus,
              onPressed: () => unawaited(
                showChatNewDirectMessageDialog(
                  context: context,
                  siteUrl: siteUrl,
                  chat: chat,
                  shell: shell,
                ),
              ),
            ),
          _ => null,
        };
        final colors = Theme.of(context).colorScheme;
        return Column(
          children: [
            ContentReadingLaneBox(
              key: const ValueKey('chat-channel-list-list-heading'),
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
              child: ConstrainedBox(
                key: const ValueKey('chat-channel-list-heading-content'),
                constraints: BoxConstraints(
                  minHeight: MediaQuery.textScalerOf(context).scale(36),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final heading =
                        header ??
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                switch (kind) {
                                  ChatChannelListKind.channels => 'Channels',
                                  ChatChannelListKind.starred => 'Starred',
                                  ChatChannelListKind.directMessages =>
                                    'Direct messages',
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (loading)
                              DSkeleton(
                                width: 20,
                                height: 12,
                                color: skeletonFill(context),
                              )
                            else
                              Text(
                                '${channels.length}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                          ],
                        );
                    final actions = loading
                        ? <Widget>[]
                        : <Widget>[
                            ChatChannelListActions(
                              controller: chat.channelListPreferences,
                              siteUrl: siteUrl,
                              section: section,
                            ),
                            if (action != null) ...[
                              const SizedBox(width: DSpacing.controlGap),
                              action,
                            ],
                          ];
                    if (header != null &&
                        constraints.maxWidth <
                            MediaQuery.textScalerOf(context).scale(320)) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          heading,
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: actions,
                            ),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: heading),
                        ...actions,
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: ContentReadingLane(
                basePadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                builder: (context, lane) => loading
                    ? _ChatChannelListLoadingSkeleton(padding: lane.padding)
                    : channels.isEmpty
                    ? Padding(
                        padding: lane.padding,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              filtered
                                  ? 'No channels match this filter.'
                                  : switch (kind) {
                                      ChatChannelListKind.channels =>
                                        'You have not joined any channels yet.',
                                      ChatChannelListKind.starred =>
                                        'You have no starred channels.',
                                      ChatChannelListKind.directMessages =>
                                        'You have no direct messages yet.',
                                    },
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: PageStorageKey<ChatChannelListKind>(kind),
                        padding: lane.padding,
                        itemCount: channels.length,
                        itemBuilder: (context, index) {
                          final channel = channels[index];
                          return ValueListenableBuilder<ChatChannel?>(
                            key: ValueKey(channel.id),
                            valueListenable: chat.channelRef(
                              siteUrl,
                              channel.id,
                            ),
                            builder: (context, current, _) =>
                                _ChannelListChannelRow(
                                  siteUrl: siteUrl,
                                  channel: current ?? channel,
                                  onTap: () => shell.openChannel(channel.id),
                                ),
                          );
                        },
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatChannelListLoadingSkeleton extends StatelessWidget {
  const _ChatChannelListLoadingSkeleton({required this.padding});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('chat-sidebar-loading-skeleton'),
    semanticsLabel: 'Loading chat channels',
    color: skeletonFill(context),
    expand: true,
    child: ListView(
      padding: padding,
      children: [
        for (var row = 0; row < 5; row++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const DSkeleton.circle(diameter: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .65 : .5,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 14),
                      ),
                      const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .85 : .7,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _ChannelListListAction extends StatelessWidget {
  const _ChannelListListAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final String tooltip;
  final DIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => DButton(
    label: Text(label),
    tooltip: tooltip,
    icon: DIcon(icon),
    onPressed: onPressed,
    variant: DButtonVariant.outline,
    size: DButtonSize.small,
  );
}

class _ChannelListChannelRow extends StatelessWidget {
  const _ChannelListChannelRow({
    required this.siteUrl,
    required this.channel,
    required this.onTap,
  });

  final String siteUrl;
  final ChatChannel channel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = _channelBadge(channel);
    final muted = channel.membership.muted;
    final theme = Theme.of(context);
    final foreground = muted
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.55)
        : theme.colorScheme.onSurface;
    final directUser = channel.isDirectMessage && channel.users.length == 1
        ? channel.users.first
        : null;
    final status = directUser?.status;
    final colors = theme.colorScheme;
    final at = _channelActivityAt(channel);
    final preview =
        channel.lastMessagePreview ??
        (channel.lastMessageId == null ? 'No messages yet' : '');
    return ChatChannelMenu(
      siteUrl: siteUrl,
      channelId: channel.id,
      child: DItem(
        key: ValueKey('chat-channel-list-channel-${channel.id}'),
        size: DItemSize.sm,
        onPressed: onTap,
        semanticLabel: badge.isVisible ? 'Unread conversation' : null,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: _ChannelListChannelPrefix(
              siteUrl: siteUrl,
              channel: channel,
              foreground: foreground,
            ),
          ),
          DItemContent(
            children: [
              DItemTitle(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: foreground,
                          fontWeight: badge.isVisible
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (channel.readRestricted) ...[
                      const SizedBox(width: DSpacing.xs),
                      DIcon(DIcons.lock, size: 10, color: foreground),
                    ],
                    if (status != null)
                      UserStatusMessage(
                        siteUrl: siteUrl,
                        userId: directUser!.id,
                        status: status,
                        size: 14,
                        leadingGap: 4,
                      ),
                  ],
                ),
              ),
              DItemDescription(
                child: SiteEmojiText.plain(
                  preview,
                  key: ValueKey('chat-channel-list-preview-${channel.id}'),
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (at != null || badge.isVisible)
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (at != null)
                  Text(
                    relativeTime(at),
                    key: ValueKey('chat-channel-list-time-${channel.id}'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                if (badge.isVisible) _ChannelListBadge(badge: badge),
              ],
            ),
          ChatChannelMenu(siteUrl: siteUrl, channelId: channel.id),
        ],
      ),
    );
  }
}

class _ChannelListChannelPrefix extends StatelessWidget {
  const _ChannelListChannelPrefix({
    required this.siteUrl,
    required this.channel,
    required this.foreground,
  });

  final String siteUrl;
  final ChatChannel channel;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    Widget art;
    if (channel.isDirectMessage && channel.users.length == 1) {
      final user = channel.users.first;
      art = ChatUserAvatar(
        siteUrl: siteUrl,
        userId: user.id,
        url: channel.avatarUrl,
        size: 36,
        fallback: DIcon(DIcons.user, size: 18, color: foreground),
      );
    } else if (channel.isDirectMessage) {
      art = DIcon(DIcons.users, size: 18, color: foreground);
    } else if (channel.emoji case final emoji?) {
      final emojiHost = PluginUiScope.require(context, chatEmojiHostService);
      art = EmojiImage(
        url: emojiHost.resolveUrl(siteUrl, emoji),
        size: 18,
        alt: ':$emoji:',
      );
    } else {
      art = DIcon(
        DIcons.comment,
        size: 18,
        color: channel.categoryColor ?? foreground,
      );
    }
    return DAvatar(
      dimension: 36,
      decorative: true,
      borderRadius: BorderRadius.circular(DTokens.of(context).radius),
      child: art,
    );
  }
}

DateTime? _channelActivityAt(ChatChannel channel) {
  var latest = channel.lastMessageAt;
  for (final threadAt in channel.unreadThreadOverview.values) {
    if (latest == null || threadAt.isAfter(latest)) latest = threadAt;
  }
  return latest;
}

SidebarBadge _channelBadge(ChatChannel channel) {
  final urgent =
      channel.tracking.mentionCount +
      channel.tracking.watchedThreadsUnreadCount +
      (channel.isDirectMessage ? channel.tracking.unreadCount : 0);
  if (urgent > 0) return SidebarBadge.urgentCount(urgent);
  if (channel.tracking.unreadCount > 0 ||
      channel.unreadThreadsCountSinceLastViewed > 0) {
    return const SidebarBadge.dot();
  }
  return SidebarBadge.none;
}

class _ChannelListBadge extends StatelessWidget {
  const _ChannelListBadge({required this.badge});

  final SidebarBadge badge;

  @override
  Widget build(BuildContext context) {
    if (badge.dot) {
      return DNotificationDot(
        color: Theme.of(context).discourse.notificationIndicator,
      );
    }
    return DBadge(
      semanticLabel: '${badge.count} urgent notifications',
      backgroundColor: Theme.of(context).discourse.success,
      foregroundColor: Theme.of(context).discourse.notificationForeground,
      child: Text(badge.count > 99 ? '99+' : '${badge.count}'),
    );
  }
}
