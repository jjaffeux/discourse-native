import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_controller.dart';
import 'chat_inbox_filters.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

/// One mixed list of channels and direct messages, most recent activity first.
List<ChatChannel> chatInboxConversations(
  ChatController chat,
  String siteUrl,
  ChatInboxFilter filter,
) {
  final settings = chat.siteConfigFor(siteUrl).chatSettings;
  return [
      if (settings.publicChannelsEnabled &&
          filter.kind != ChatInboxKind.directMessages)
        ...chat.publicChannels(siteUrl),
      if (filter.kind != ChatInboxKind.channels)
        ...chat.directChannels(siteUrl),
    ].where((channel) => !filter.unreadOnly || channel.badge.isVisible).toList()
    ..sort((a, b) {
      final aTime = chatInboxActivityAt(a);
      final bTime = chatInboxActivityAt(b);
      final recent = aTime == null
          ? (bTime == null ? 0 : 1)
          : bTime == null
          ? -1
          : bTime.compareTo(aTime);
      if (recent != 0) return recent;
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return title != 0 ? title : a.id.compareTo(b.id);
    });
}

String chatInboxEmptyMessage(ChatInboxFilter filter) => filter.unreadOnly
    ? 'No unread conversations.'
    : switch (filter.kind) {
        ChatInboxKind.all => 'No conversations yet.',
        ChatInboxKind.channels => 'You have not joined any channels yet.',
        ChatInboxKind.directMessages => 'You have no direct messages yet.',
      };

DateTime? chatInboxActivityAt(ChatChannel channel) {
  var latest = channel.lastMessageAt;
  for (final replyAt in channel.unreadThreadOverview.values) {
    if (latest == null || replyAt.isAfter(latest)) latest = replyAt;
  }
  return latest;
}

/// The activity and conversation-type dropdowns, plus the reader's presence.
class ChatInboxFilterBar extends StatelessWidget {
  const ChatInboxFilterBar({
    super.key,
    required this.siteUrl,
    required this.filters,
    this.compact = false,
  });

  final String siteUrl;
  final ChatInboxFilters filters;

  /// The desktop sidebar's narrow width: the type filter drops its icon so
  /// both filters and presence share one line at the default width.
  final bool compact;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: filters,
    builder: (context, _) {
      final filter = filters.filterFor(siteUrl);
      final dropdowns = <Widget>[
        _ChatFilter<bool>(
          key: const ValueKey('chat-inbox-activity-filter'),
          label: filter.unreadOnly ? 'Unread' : 'Recent',
          semanticLabel: 'Chat activity',
          value: filter.unreadOnly,
          entries: const [
            DSelectOption(value: false, label: 'Recent', child: Text('Recent')),
            DSelectOption(value: true, label: 'Unread', child: Text('Unread')),
          ],
          onChanged: (value) =>
              filters.update(siteUrl, filter.copyWith(unreadOnly: value)),
        ),
        _ChatFilter<ChatInboxKind>(
          key: const ValueKey('chat-inbox-kind-filter'),
          label: switch (filter.kind) {
            ChatInboxKind.all => 'All',
            ChatInboxKind.channels => 'Channels',
            ChatInboxKind.directMessages => 'DMs',
          },
          icon: compact ? null : DIcons.comment,
          semanticLabel: 'Conversation type',
          value: filter.kind,
          entries: const [
            DSelectOption(
              value: ChatInboxKind.all,
              label: 'All',
              child: Text('All'),
            ),
            DSelectOption(
              value: ChatInboxKind.channels,
              label: 'Channels',
              child: Text('Channels'),
            ),
            DSelectOption(
              value: ChatInboxKind.directMessages,
              label: 'Direct messages',
              child: Text('Direct messages'),
            ),
          ],
          onChanged: (value) =>
              filters.update(siteUrl, filter.copyWith(kind: value)),
        ),
      ];
      final presence = UserPresenceMenu(siteUrl: siteUrl);
      return Row(
        spacing: DSpacing.controlGap,
        children: [
          Expanded(
            child: Wrap(
              spacing: DSpacing.controlGap,
              runSpacing: DSpacing.controlGap,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: dropdowns,
            ),
          ),
          presence,
        ],
      );
    },
  );
}

class _ChatFilter<T> extends StatelessWidget {
  const _ChatFilter({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.value,
    required this.entries,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final String semanticLabel;
  final T value;
  final List<DSelectEntry<T>> entries;
  final ValueChanged<T> onChanged;
  final DIconData? icon;

  @override
  Widget build(BuildContext context) => DSelect<T>.controlled(
    size: DControlSize.filter,
    value: value,
    semanticLabel: semanticLabel,
    entries: entries,
    width: 200,
    align: DPopoverAlign.start,
    alignItemWithTrigger: false,
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
    triggerBuilder: (context, state, _) => DButton(
      size: DControlSize.filter,
      variant: DButtonVariant.outline,
      semanticLabel: '$semanticLabel, $label',
      focusNode: state.focusNode,
      hasPopup: true,
      expanded: state.open,
      onPressed: state.toggle,
      icon: icon == null ? null : DIcon(icon!),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: DSpacing.controlGap,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: icon == null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const DIcon(DNativeIcons.filterChevron, size: 10),
        ],
      ),
    ),
  );
}

/// The inbox's way out to every channel and to the reader's threads.
class ChatInboxShortcuts extends StatelessWidget {
  const ChatInboxShortcuts({
    super.key,
    required this.browse,
    required this.myThreads,
    this.size = DControlSize.action,
    this.shortLabels = false,
  });

  final bool browse;
  final bool myThreads;
  final DControlSize size;

  /// "Browse" and "Threads", for a row as narrow as the desktop sidebar.
  final bool shortLabels;

  /// Below this width two full labels cannot sit side by side.
  static const double _rowWidth = 280;

  @override
  Widget build(BuildContext context) {
    final shell = PluginUiScope.require(context, chatShellService);
    final buttons = [
      if (browse)
        DButton(
          key: const ValueKey('chat-inbox-browse'),
          size: size,
          icon: const DIcon(DIcons.list),
          label: Text(shortLabels ? 'Browse' : 'Browse channels'),
          tooltip: shortLabels ? 'Browse channels' : null,
          variant: DButtonVariant.outline,
          onPressed: shell.openBrowseChannels,
        ),
      if (myThreads)
        DButton(
          key: const ValueKey('chat-inbox-my-threads'),
          size: size,
          icon: const DIcon(DIcons.comments),
          label: Text(shortLabels ? 'Threads' : 'My threads'),
          tooltip: shortLabels ? 'My threads' : null,
          variant: DButtonVariant.outline,
          onPressed: shell.openMyThreads,
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) =>
          shortLabels ||
              constraints.maxWidth >=
                  MediaQuery.textScalerOf(context).scale(_rowWidth)
          ? Row(
              spacing: DSpacing.controlGap,
              children: [for (final button in buttons) Expanded(child: button)],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: DSpacing.controlGap,
              children: buttons,
            ),
    );
  }
}

/// The desktop Chat panel's pinned actions: starting a conversation first,
/// then the ways out to every channel and to the reader's threads.
class ChatSidebarFooter extends StatelessWidget {
  const ChatSidebarFooter({
    super.key,
    required this.browse,
    required this.myThreads,
    required this.onStartMessage,
    required this.startMessageShortcut,
  });

  final bool browse;
  final bool myThreads;
  final VoidCallback? onStartMessage;
  final SingleActivator startMessageShortcut;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    key: const ValueKey('chat-sidebar-footer'),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: DTokens.of(context).border)),
    ),
    child: Padding(
      padding: const EdgeInsets.all(DSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: DSpacing.controlGap,
        children: [
          if (onStartMessage case final onPressed?)
            DButton(
              key: const ValueKey('chat-sidebar-start-message'),
              variant: DButtonVariant.primary,
              shape: DButtonShape.pill,
              icon: const DIcon(DIcons.plus),
              label: const Text('Start a message'),
              tooltip: 'Start a message',
              shortcut: DShortcut(startMessageShortcut),
              onPressed: onPressed,
            ),
          if (browse || myThreads)
            ChatInboxShortcuts(
              browse: browse,
              myThreads: myThreads,
              size: DControlSize.small,
              shortLabels: true,
            ),
        ],
      ),
    ),
  );
}

/// The inbox's error state: nothing to show and a way to ask again.
class ChatInboxError extends StatelessWidget {
  const ChatInboxError({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => DEmpty(
    children: [
      const DEmptyHeader(
        children: [DEmptyTitle('Could not load conversations')],
      ),
      DButton(label: const Text('Retry'), onPressed: onRetry),
    ],
  );
}

/// A conversation in the inbox: who or where, when, and what is new.
class ChatInboxRow extends StatelessWidget {
  const ChatInboxRow({
    super.key,
    required this.siteUrl,
    required this.channel,
    required this.onPressed,
    this.compact = false,
    this.selected = false,
  });

  final String siteUrl;
  final ChatChannel channel;
  final VoidCallback onPressed;

  /// The desktop sidebar's denser, rounded row; mobile's is flush and larger.
  final bool compact;
  final bool selected;

  static const double compactAvatarSize = 32;

  @override
  Widget build(BuildContext context) {
    final unread = channel.badge.isVisible;
    final count = channel.tracking.unreadCount;
    final threadCount = channel.tracking.watchedThreadsUnreadCount > 0
        ? channel.tracking.watchedThreadsUnreadCount
        : channel.unreadThreadsCountSinceLastViewed;
    final currentUser = PluginUiScope.require(
      context,
      chatShellService,
    ).currentUser;
    final ownMessage =
        currentUser?.id != null && channel.lastMessageUserId == currentUser?.id;
    final messagePreview = channel.lastMessagePreview;
    final preview = unread && count > 0
        ? '$count new ${count == 1 ? 'message' : 'messages'}'
        : unread && threadCount > 0
        ? '$threadCount unread ${threadCount == 1 ? 'thread' : 'threads'}'
        : unread && channel.tracking.mentionCount > 0
        ? '${channel.tracking.mentionCount} new ${channel.tracking.mentionCount == 1 ? 'mention' : 'mentions'}'
        : (messagePreview == null
                  ? null
                  : '${ownMessage ? 'you: ' : ''}$messagePreview') ??
              (channel.lastMessageId == null ? 'No messages yet' : '');
    final at = chatInboxActivityAt(channel)?.toLocal();
    final directUser = channel.isDirectMessage && channel.users.length == 1
        ? channel.users.first
        : null;
    final status = directUser?.status;
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    return ChatChannelMenu(
      siteUrl: siteUrl,
      channelId: channel.id,
      child: DItem(
        key: ValueKey('chat-inbox-channel-${channel.id}'),
        shape: compact ? DItemShape.standard : DItemShape.fullWidth,
        size: compact ? DItemSize.sm : DItemSize.standard,
        selected: selected,
        onPressed: onPressed,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: _ConversationAvatar(
              siteUrl: siteUrl,
              channel: channel,
              size: compact ? compactAvatarSize : DAvatarSize.lg.dimension,
            ),
          ),
          DItemContent(
            children: [
              DItemTitle(
                child: Row(
                  spacing: DSpacing.sm,
                  children: [
                    Expanded(
                      child: Text(
                        channel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (status != null)
                      UserStatusMessage(
                        siteUrl: siteUrl,
                        userId: directUser!.id,
                        status: status,
                        size: 14,
                      ),
                    if (channel.readRestricted)
                      const DIcon(DIcons.lock, size: 12),
                    if (at != null)
                      Text(
                        compact
                            ? relativeTime(at)
                            : _activityLabel(context, at),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: tokens.mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
              DItemDescription(
                child: SiteEmojiText.plain(
                  preview,
                  siteUrl: siteUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: unread ? tokens.foreground : tokens.mutedForeground,
                    fontWeight: unread ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConversationAvatar extends StatelessWidget {
  const _ConversationAvatar({
    required this.siteUrl,
    required this.channel,
    required this.size,
  });

  final String siteUrl;
  final ChatChannel channel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final color = channel.categoryColor ?? tokens.mutedForeground;
    final fallback = DAvatarFallback(
      backgroundColor: color.withValues(alpha: .22),
      foregroundColor: color,
      child: channel.isDirectMessage
          ? channel.isGroup || channel.users.length > 1
                ? DIcon(DIcons.users, size: size / 2)
                : Text(
                    channel.title.characters.take(1).toString().toUpperCase(),
                  )
          : Text(
              '#',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontSize: size * .6,
                fontWeight: FontWeight.w400,
              ),
            ),
    );
    if (!channel.isDirectMessage && channel.emoji != null) {
      final emojiHost = PluginUiScope.require(context, chatEmojiHostService);
      return DAvatar(
        dimension: size,
        border: false,
        decorative: true,
        fallback: DAvatarFallback(
          backgroundColor: color.withValues(alpha: .22),
          child: EmojiImage(
            url: emojiHost.resolveUrl(siteUrl, channel.emoji!),
            size: size / 2,
            alt: ':${channel.emoji}:',
          ),
        ),
      );
    }
    if (channel.isDirectMessage &&
        channel.users.length == 1 &&
        !channel.isGroup) {
      return ChatUserAvatar(
        siteUrl: siteUrl,
        userId: channel.users.first.id,
        url: channel.avatarUrl,
        size: size,
        fallback: fallback,
      );
    }
    return DAvatar(
      dimension: size,
      border: false,
      decorative: true,
      fallback: fallback,
    );
  }
}

String _activityLabel(BuildContext context, DateTime at) {
  final now = DateTime.now();
  final localizations = MaterialLocalizations.of(context);
  if (at.year == now.year && at.month == now.month && at.day == now.day) {
    return localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(at),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }
  return localizations.formatShortDate(at);
}

/// The desktop sidebar's inbox: the mobile inbox's filters and ordering laid
/// out as slivers, so it scrolls with the panel's other sections.
class ChatSidebarInbox extends StatelessWidget {
  const ChatSidebarInbox({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    final filters = chat.inboxFilters;
    return ListenableBuilder(
      listenable: Listenable.merge([chat, filters, shell]),
      builder: (context, _) {
        final filter = filters.filterFor(siteUrl);
        final channels = chatInboxConversations(chat, siteUrl, filter);
        final error = chat.channelsError(siteUrl);
        final loading = !chat.channelsLoaded(siteUrl) && error == null;
        final selectedId = shell.visibleChannelId;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: DSpacing.sm),
                child: ChatInboxFilterBar(
                  siteUrl: siteUrl,
                  filters: filters,
                  compact: true,
                ),
              ),
            ),
            if (loading)
              const SliverToBoxAdapter(child: _ChatSidebarInboxSkeleton())
            else if (error != null && channels.isEmpty)
              SliverToBoxAdapter(
                child: ChatInboxError(
                  onRetry: () =>
                      unawaited(chat.loadChannels(siteUrl, force: true)),
                ),
              )
            else if (channels.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  key: const ValueKey('chat-inbox-empty'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: DSpacing.md,
                    vertical: DSpacing.lg,
                  ),
                  child: Text(
                    chatInboxEmptyMessage(filter),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DTokens.of(context).mutedForeground,
                    ),
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: channels.length,
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<int>) return null;
                  final index = channels.indexWhere(
                    (channel) => channel.id == key.value,
                  );
                  return index < 0 ? null : index;
                },
                itemBuilder: (context, index) {
                  final channel = channels[index];
                  return ValueListenableBuilder<ChatChannel?>(
                    key: ValueKey(channel.id),
                    valueListenable: chat.channelRef(siteUrl, channel.id),
                    builder: (context, current, _) => ChatInboxRow(
                      siteUrl: siteUrl,
                      channel: current ?? channel,
                      compact: true,
                      selected: channel.id == selectedId,
                      onPressed: () => shell.openChannel(channel.id),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// Reserves the rows the inbox is about to draw; the filters above it are
/// already final, so only the rows are placeholders.
class _ChatSidebarInboxSkeleton extends StatelessWidget {
  const _ChatSidebarInboxSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('chat-inbox-loading-skeleton'),
    semanticsLabel: 'Loading conversations',
    color: skeletonFill(context, on: SkeletonSurface.panel),
    child: Column(
      children: [
        for (var row = 0; row < 6; row++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              spacing: 12,
              children: [
                const DSkeleton.circle(
                  diameter: ChatInboxRow.compactAvatarSize,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 6,
                    children: [
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .65 : .5,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 12),
                      ),
                      FractionallySizedBox(
                        widthFactor: row.isEven ? .85 : .7,
                        alignment: AlignmentDirectional.centerStart,
                        child: const DSkeleton(height: 10),
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
