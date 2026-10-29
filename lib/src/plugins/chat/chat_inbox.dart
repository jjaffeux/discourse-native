import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'chat_browse_navigation.dart';
import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_controller.dart';
import 'chat_inbox_filters.dart';
import 'chat_inbox_rooms.dart';
import 'chat_search_entry.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

export 'chat_controller.dart' show chatInboxActivityAt;

/// One mixed list of channels and direct messages, most recent activity first.
List<ChatChannel> chatInboxConversations(
  ChatController chat,
  String siteUrl,
  ChatInboxFilter filter,
) => chat.inboxConversations(siteUrl, filter);

String chatInboxEmptyMessage(ChatInboxFilter filter) => filter.unreadOnly
    ? appL10n.noUnreadConversations
    : switch (filter.kind) {
        ChatInboxKind.all => appL10n.noConversationsYet,
        ChatInboxKind.channels => appL10n.youHaveNotJoinedAnyChannelsYet,
        ChatInboxKind.directMessages => appL10n.youHaveNoDirectMessagesYet,
        ChatInboxKind.voiceRooms => appL10n.noVoiceRoomsYet,
      };

/// Shared activity and grouping choices for the inbox and sidebar.
class ChatInboxFilterBar extends StatelessWidget {
  const ChatInboxFilterBar({
    super.key,
    required this.siteUrl,
    required this.filters,
  });

  final String siteUrl;
  final ChatInboxFilters filters;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: filters,
    builder: (context, _) {
      final filter = filters.filterFor(siteUrl);
      return Wrap(
        spacing: DSpacing.controlGap,
        runSpacing: DSpacing.controlGap,
        children: [
          ChatBrowseFilter<bool>(
            key: const ValueKey('chat-inbox-activity-filter'),
            label: filter.unreadOnly
                ? context.l10n.unread
                : context.l10n.recent,
            emphasized: true,
            semanticLabel: context.l10n.chatActivity,
            value: filter.unreadOnly,
            options: {false: context.l10n.recent, true: context.l10n.unread},
            onChanged: (value) =>
                filters.update(siteUrl, filter.copyWith(unreadOnly: value)),
          ),
          ChatBrowseFilter<ChatInboxSort>(
            key: const ValueKey('chat-inbox-sort-filter'),
            label: filter.sort == ChatInboxSort.byType
                ? context.l10n.chatOrderByType
                : context.l10n.chatOrderNewest,
            semanticLabel: context.l10n.chatOrder,
            value: filter.sort,
            options: {
              ChatInboxSort.byType: context.l10n.chatOrderByType,
              ChatInboxSort.newest: context.l10n.chatOrderNewest,
            },
            onChanged: (value) =>
                filters.update(siteUrl, filter.copyWith(sort: value)),
          ),
        ],
      );
    },
  );
}

enum ChatInboxSectionKind { starred, channels, directMessages, allChats }

typedef ChatInboxSection = ({
  ChatInboxSectionKind kind,
  List<ChatChannel> channels,
});

/// [channels] already follows actual message and unread-thread activity.
List<ChatInboxSection> chatInboxSections(
  List<ChatChannel> channels,
  ChatInboxSort sort,
) => [
  if (sort == ChatInboxSort.newest)
    (kind: ChatInboxSectionKind.allChats, channels: channels)
  else ...[
    (
      kind: ChatInboxSectionKind.starred,
      channels: [
        for (final c in channels)
          if (c.membership.starred) c,
      ],
    ),
    (
      kind: ChatInboxSectionKind.channels,
      channels: [
        for (final c in channels)
          if (!c.membership.starred && !c.isDirectMessage) c,
      ],
    ),
    (
      kind: ChatInboxSectionKind.directMessages,
      channels: [
        for (final c in channels)
          if (!c.membership.starred && c.isDirectMessage) c,
      ],
    ),
  ],
].where((section) => section.channels.isNotEmpty).toList();

DIconData _inboxSectionIcon(ChatInboxSectionKind kind) => switch (kind) {
  ChatInboxSectionKind.starred => DIcons.star,
  ChatInboxSectionKind.channels => DIcons.hashtag,
  ChatInboxSectionKind.directMessages => DIcons.user,
  ChatInboxSectionKind.allChats => DIcons.comments,
};

String _inboxSectionLabel(BuildContext context, ChatInboxSectionKind kind) =>
    switch (kind) {
      ChatInboxSectionKind.starred => context.l10n.starred,
      ChatInboxSectionKind.channels => context.l10n.channels,
      ChatInboxSectionKind.directMessages => context.l10n.directMessages,
      ChatInboxSectionKind.allChats => context.l10n.chatAllChats,
    };

class ChatInboxSectionHeading extends StatelessWidget {
  const ChatInboxSectionHeading({super.key, required this.kind});
  final ChatInboxSectionKind kind;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 2),
    child: Row(
      spacing: DSpacing.xs,
      children: [
        DIcon(
          _inboxSectionIcon(kind),
          size: 11,
          color: DTokens.of(context).mutedForeground,
        ),
        Flexible(
          child: Text(
            _inboxSectionLabel(context, kind),
            style: TextStyle(
              fontSize: DiscourseTypography.xs,
              fontWeight: FontWeight.w600,
              color: DTokens.of(context).mutedForeground,
            ),
          ),
        ),
      ],
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
      DEmptyHeader(
        children: [DEmptyTitle(context.l10n.couldNotLoadConversations)],
      ),
      DButton(label: Text(context.l10n.retry), onPressed: onRetry),
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
  Widget build(BuildContext context) => LayoutBuilder(builder: _buildRow);

  Widget _buildRow(BuildContext context, BoxConstraints constraints) {
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
    final sender = ownMessage
        ? 'you: '
        : !channel.isDirectMessage && channel.lastMessageUsername != null
        ? '${channel.lastMessageUsername}: '
        : '';
    final preview = unread && count > (compact ? 0 : 1)
        ? context.l10n.messageChatinbox(count)
        : unread && threadCount > 0
        ? context.l10n.unreadChatinbox(threadCount)
        : unread && channel.tracking.mentionCount > 0
        ? context.l10n.messageNewChatinbox(channel.tracking.mentionCount)
        : (messagePreview == null ? null : '$sender$messagePreview') ??
              (channel.lastMessageId == null ? context.l10n.noMessagesYet : '');
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
        shape: compact ? DItemShape.menu : DItemShape.fullWidth,
        padding: !compact && constraints.maxWidth < 600
            ? const EdgeInsets.symmetric(vertical: DSpacing.md)
            : null,
        size: compact ? DItemSize.sm : DItemSize.standard,
        selected: selected,
        cornerAction: compact && !context.isTouch
            ? ChatChannelMenu(
                siteUrl: siteUrl,
                channelId: channel.id,
                channel: channel,
              )
            : null,
        selectionStyle: compact
            ? DItemSelectionStyle.sidebar
            : DItemSelectionStyle.leadingAccent,
        showSelectionIndicator: false,
        onPressed: onPressed,
        semanticLabel: unread ? context.l10n.unreadConversation : null,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: ChatConversationAvatar(
              siteUrl: siteUrl,
              channel: channel,
              size: compact ? compactAvatarSize : DAvatarSize.lg.dimension,
            ),
          ),
          DItemContent(
            children: [
              DItemTitle(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: compact && !context.isTouch ? DSpacing.xl : 0,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) => Row(
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
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * .45,
                            ),
                            child: Text(
                              _activityLabel(context, at),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: tokens.mutedForeground,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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

class ChatConversationAvatar extends StatelessWidget {
  const ChatConversationAvatar({
    super.key,
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
        borderRadius: BorderRadius.circular(DRadius.bubble),
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
      borderRadius: channel.isDirectMessage
          ? null
          : BorderRadius.circular(DRadius.bubble),
      decorative: true,
      fallback: fallback,
    );
  }
}

String _activityLabel(BuildContext context, DateTime at) {
  final now = DateTime.now();
  if (at.year == now.year && at.month == now.month && at.day == now.day) {
    return clockTimeLabel(context, at);
  }
  return MaterialLocalizations.of(context).formatShortDate(at);
}

/// Shared chat controls pin across conversations and the voice room section.
class ChatSidebarInboxHeader extends StatelessWidget {
  const ChatSidebarInboxHeader({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChatSearchEntry(siteUrl: siteUrl),
      ChatInboxFilterBar(
        siteUrl: siteUrl,
        filters: PluginUiScope.require(
          context,
          chatControllerService,
        ).inboxFilters,
      ),
    ],
  );
}

/// The desktop sidebar's inbox: the mobile inbox's filters and ordering laid
/// out as slivers, so it scrolls with the panel's other sections.
///
/// The chat controller notifies for every message in every followed channel,
/// and the panel rebuilds this section with it. The list is laid out again
/// only when the conversations it shows, or their order, change; each row
/// follows its own channel and whether it is open.
class ChatSidebarInbox extends StatefulWidget {
  const ChatSidebarInbox({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatSidebarInbox> createState() => _ChatSidebarInboxState();
}

@immutable
final class _ChatSidebarInboxLayout {
  const _ChatSidebarInboxLayout({
    required this.filter,
    required this.channelIds,
    required this.starredIds,
    required this.loading,
    required this.failed,
    required this.empty,
  });

  final ChatInboxFilter filter;
  final List<int> channelIds;
  final List<int> starredIds;
  final bool loading;
  final bool failed;
  final bool empty;

  @override
  bool operator ==(Object other) =>
      other is _ChatSidebarInboxLayout &&
      filter == other.filter &&
      loading == other.loading &&
      failed == other.failed &&
      empty == other.empty &&
      listEquals(channelIds, other.channelIds) &&
      listEquals(starredIds, other.starredIds);

  @override
  int get hashCode => Object.hash(
    filter,
    loading,
    failed,
    empty,
    Object.hashAll(channelIds),
    Object.hashAll(starredIds),
  );
}

class _ChatSidebarInboxState extends State<ChatSidebarInbox> {
  ChatController? _chat;
  ChatInboxRooms? _rooms;
  Listenable? _sources;
  late _ChatSidebarInboxLayout _layout;
  Widget? _content;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final chat = PluginUiScope.require(context, chatControllerService);
    final rooms = PluginUiScope.optional(context, chatInboxRoomsService);
    if (!identical(chat, _chat) || !identical(rooms, _rooms)) {
      _sources?.removeListener(_changed);
      _chat = chat;
      _rooms = rooms;
      _sources = Listenable.merge([chat, chat.inboxFilters, rooms])
        ..addListener(_changed);
    }
    _layout = _read();
    _content = null;
  }

  @override
  void didUpdateWidget(ChatSidebarInbox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl == widget.siteUrl) return;
    _layout = _read();
    _content = null;
  }

  _ChatSidebarInboxLayout _read() {
    final chat = _chat!;
    final siteUrl = widget.siteUrl;
    final filter = chat.inboxFilters.filterFor(siteUrl);
    final channels = chatInboxConversations(chat, siteUrl, filter);
    final error = chat.channelsError(siteUrl);
    return _ChatSidebarInboxLayout(
      filter: filter,
      channelIds: [for (final channel in channels) channel.id],
      starredIds: [
        for (final channel in channels)
          if (channel.membership.starred) channel.id,
      ],
      loading: !chat.channelsLoaded(siteUrl) && error == null,
      failed: error != null && channels.isEmpty,
      empty: channels.isEmpty && (_rooms?.rooms(siteUrl).isEmpty ?? true),
    );
  }

  void _changed() {
    final layout = _read();
    if (layout == _layout) return;
    setState(() {
      _layout = layout;
      _content = null;
    });
  }

  @override
  void dispose() {
    _sources?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _content ??= _buildContent();

  Widget _buildContent() {
    final chat = _chat!;
    final siteUrl = widget.siteUrl;
    final layout = _layout;
    final sections = chatInboxSections([
      for (final id in layout.channelIds) ?chat.channel(siteUrl, id),
    ], layout.filter.sort);
    return SliverMainAxisGroup(
      slivers: [
        if (layout.loading)
          const SliverToBoxAdapter(child: _ChatSidebarInboxSkeleton())
        else if (layout.failed)
          SliverToBoxAdapter(
            child: ChatInboxError(
              onRetry: () => unawaited(chat.loadChannels(siteUrl, force: true)),
            ),
          )
        else if (layout.empty)
          SliverToBoxAdapter(
            child: _ChatSidebarInboxEmpty(filter: layout.filter),
          )
        else
          for (final section in sections) _section(section),
      ],
    );
  }

  Widget _section(ChatInboxSection section) {
    final indexes = {
      for (final (index, channel) in section.channels.indexed)
        channel.id: index,
    };
    return DCollapsible(
      key: ValueKey(section.kind),
      defaultOpen: true,
      child: DSidebarGroup.sliver(
        padding: EdgeInsets.zero,
        header: DCollapsibleTrigger(
          builder: (context, state) => DSidebarGroupLabel(
            child: Row(
              spacing: DSpacing.sm,
              children: [
                DIcon(_inboxSectionIcon(section.kind), size: 16),
                Expanded(
                  child: Text(_inboxSectionLabel(context, section.kind)),
                ),
                DIcon(
                  state.open ? DIcons.chevronDown : DIcons.chevronRight,
                  size: 10,
                ),
              ],
            ),
          ),
        ),
        sliver: DCollapsibleContent.sliver(
          sliver: SliverList.builder(
            itemCount: section.channels.length,
            findChildIndexCallback: (key) =>
                key is ValueKey<int> ? indexes[key.value] : null,
            itemBuilder: (context, index) => _ChatSidebarInboxEntry(
              key: ValueKey(section.channels[index].id),
              siteUrl: widget.siteUrl,
              channelId: section.channels[index].id,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatSidebarInboxEntry extends StatefulWidget {
  const _ChatSidebarInboxEntry({
    super.key,
    required this.siteUrl,
    required this.channelId,
  });

  final String siteUrl;
  final int channelId;

  @override
  State<_ChatSidebarInboxEntry> createState() => _ChatSidebarInboxEntryState();
}

class _ChatSidebarInboxEntryState extends State<_ChatSidebarInboxEntry> {
  Widget? _content;

  @override
  void didUpdateWidget(_ChatSidebarInboxEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.channelId != widget.channelId) {
      _content = null;
    }
  }

  // Reordering rebuilds the list's delegate. Keep the mounted row's listeners
  // and content, so only its own channel or selection redraws it.
  @override
  Widget build(BuildContext context) =>
      _content ??= PluginServiceSelector<ChatShellService, bool>(
        service: chatShellService,
        select: (shell) => shell.visibleChannelId == widget.channelId,
        builder: (context, selected, _) => ValueListenableBuilder<ChatChannel?>(
          valueListenable: PluginUiScope.require(
            context,
            chatControllerService,
          ).channelRef(widget.siteUrl, widget.channelId),
          // The id came from the store, so a gap means the channel was
          // just removed and the list is one frame from dropping it.
          builder: (context, channel, _) => channel == null
              ? const SizedBox.shrink()
              : ChatInboxRow(
                  siteUrl: widget.siteUrl,
                  channel: channel,
                  compact: true,
                  selected: selected,
                  onPressed: () => PluginUiScope.require(
                    context,
                    chatShellService,
                  ).openChannel(widget.channelId),
                ),
        ),
      );
}

class _ChatSidebarInboxEmpty extends StatelessWidget {
  const _ChatSidebarInboxEmpty({required this.filter});

  final ChatInboxFilter filter;

  @override
  Widget build(BuildContext context) => Padding(
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
  );
}

/// Reserves the rows the inbox is about to draw; the filters above it are
/// already final, so only the rows are placeholders.
class _ChatSidebarInboxSkeleton extends StatelessWidget {
  const _ChatSidebarInboxSkeleton();

  @override
  Widget build(BuildContext context) => DSkeletonRegion(
    key: const ValueKey('chat-inbox-loading-skeleton'),
    semanticsLabel: context.l10n.loadingConversations,
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
