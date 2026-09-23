import 'dart:async';

import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_plugin_data.dart';
import 'chat_services.dart';
import 'chat_shell_service.dart';
import 'chat_user_avatar.dart';

enum _ConversationKind { all, channels, directMessages }

/// Mobile's combined inbox keeps its filters while visiting a conversation.
class ChatMobileSidebar extends StatefulWidget {
  const ChatMobileSidebar({super.key, required this.siteUrl});

  final String siteUrl;

  @override
  State<ChatMobileSidebar> createState() => _ChatMobileSidebarState();
}

class _ChatMobileSidebarState extends State<ChatMobileSidebar> {
  _ConversationKind _kind = _ConversationKind.all;
  bool _unreadOnly = false;

  @override
  Widget build(BuildContext context) {
    final chat = PluginUiScope.require(context, chatControllerService);
    final shell = PluginUiScope.require(context, chatShellService);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, _) {
        final siteUrl = widget.siteUrl;
        final settings = chat.siteConfigFor(siteUrl).chatSettings;
        final channels =
            [
                  if (settings.publicChannelsEnabled &&
                      _kind != _ConversationKind.directMessages)
                    ...chat.publicChannels(siteUrl),
                  if (_kind != _ConversationKind.channels)
                    ...chat.directChannels(siteUrl),
                ]
                .where((channel) => !_unreadOnly || channel.badge.isVisible)
                .toList()
              ..sort((a, b) {
                final aTime = _activityAt(a);
                final bTime = _activityAt(b);
                final recent = aTime == null
                    ? (bTime == null ? 0 : 1)
                    : bTime == null
                    ? -1
                    : bTime.compareTo(aTime);
                if (recent != 0) return recent;
                final title = a.title.toLowerCase().compareTo(
                  b.title.toLowerCase(),
                );
                return title != 0 ? title : a.id.compareTo(b.id);
              });
        final error = chat.channelsError(siteUrl);
        final loading = !chat.channelsLoaded(siteUrl) && error == null;
        final colors = DTokens.of(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chat',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: DSpacing.md),
                  Row(
                    spacing: DSpacing.controlGap,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: DSpacing.controlGap,
                          runSpacing: DSpacing.controlGap,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _ChatFilter<bool>(
                              key: const ValueKey(
                                'mobile-chat-activity-filter',
                              ),
                              label: _unreadOnly ? 'Unread' : 'Recent',
                              semanticLabel: 'Chat activity',
                              value: _unreadOnly,
                              entries: const [
                                DSelectOption(
                                  value: false,
                                  label: 'Recent',
                                  child: Text('Recent'),
                                ),
                                DSelectOption(
                                  value: true,
                                  label: 'Unread',
                                  child: Text('Unread'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _unreadOnly = value),
                            ),
                            _ChatFilter<_ConversationKind>(
                              key: const ValueKey('mobile-chat-kind-filter'),
                              label: switch (_kind) {
                                _ConversationKind.all => 'All',
                                _ConversationKind.channels => 'Channels',
                                _ConversationKind.directMessages => 'DMs',
                              },
                              icon: DIcons.comment,
                              semanticLabel: 'Conversation type',
                              value: _kind,
                              entries: const [
                                DSelectOption(
                                  value: _ConversationKind.all,
                                  label: 'All',
                                  child: Text('All'),
                                ),
                                DSelectOption(
                                  value: _ConversationKind.channels,
                                  label: 'Channels',
                                  child: Text('Channels'),
                                ),
                                DSelectOption(
                                  value: _ConversationKind.directMessages,
                                  label: 'Direct messages',
                                  child: Text('Direct messages'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _kind = value),
                            ),
                          ],
                        ),
                      ),
                      UserPresenceMenu(siteUrl: siteUrl),
                    ],
                  ),
                  const SizedBox(height: DSpacing.sm),
                  DSeparator(color: colors.border),
                ],
              ),
            ),
            Expanded(
              child: loading
                  ? const Center(
                      child: DSpinner(semanticLabel: 'Loading conversations'),
                    )
                  : error != null && channels.isEmpty
                  ? DEmpty(
                      children: [
                        const DEmptyHeader(
                          children: [
                            DEmptyTitle('Could not load conversations'),
                          ],
                        ),
                        DButton(
                          label: const Text('Retry'),
                          onPressed: () => unawaited(
                            chat.loadChannels(siteUrl, force: true),
                          ),
                        ),
                      ],
                    )
                  : channels.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DSpacing.lg),
                        child: Text(
                          _unreadOnly
                              ? 'No unread conversations.'
                              : switch (_kind) {
                                  _ConversationKind.all =>
                                    'No conversations yet.',
                                  _ConversationKind.channels =>
                                    'You have not joined any channels yet.',
                                  _ConversationKind.directMessages =>
                                    'You have no direct messages yet.',
                                },
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: PageStorageKey((
                        'mobile-chat-list',
                        siteUrl,
                        _kind,
                        _unreadOnly,
                      )),
                      padding: EdgeInsets.zero,
                      itemCount: channels.length,
                      separatorBuilder: (context, _) =>
                          DSeparator(color: colors.border),
                      itemBuilder: (context, index) {
                        final channel = channels[index];
                        return ValueListenableBuilder<ChatChannel?>(
                          key: ValueKey(channel.id),
                          valueListenable: chat.channelRef(siteUrl, channel.id),
                          builder: (context, current, _) => _ConversationRow(
                            siteUrl: siteUrl,
                            channel: current ?? channel,
                            onPressed: () => shell.openChannel(channel.id),
                          ),
                        );
                      },
                    ),
            ),
            if (settings.publicChannelsEnabled ||
                (settings.threadsEnabled && chat.hasThreads(siteUrl)))
              DCardFooter(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Wrap(
                  spacing: DSpacing.controlGap,
                  runSpacing: DSpacing.controlGap,
                  children: [
                    if (settings.publicChannelsEnabled)
                      DButton(
                        key: const ValueKey('mobile-chat-browse'),
                        icon: const DIcon(DIcons.list),
                        label: const Text('Browse channels'),
                        variant: DButtonVariant.outline,
                        onPressed: shell.openBrowseChannels,
                      ),
                    if (settings.threadsEnabled && chat.hasThreads(siteUrl))
                      DButton(
                        key: const ValueKey('mobile-chat-my-threads'),
                        icon: const DIcon(DIcons.comments),
                        label: const Text('My threads'),
                        variant: DButtonVariant.outline,
                        onPressed: shell.openMyThreads,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
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
          const DIcon(DIcons.chevronDown),
        ],
      ),
    ),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({
    required this.siteUrl,
    required this.channel,
    required this.onPressed,
  });

  final String siteUrl;
  final ChatChannel channel;
  final VoidCallback onPressed;

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
    final at = _activityAt(channel)?.toLocal();
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    return ChatChannelMenu(
      siteUrl: siteUrl,
      channelId: channel.id,
      child: DItem(
        key: ValueKey('mobile-chat-channel-${channel.id}'),
        shape: DItemShape.fullWidth,
        onPressed: onPressed,
        children: [
          DItemMedia(
            variant: DItemMediaVariant.avatar,
            child: _ConversationAvatar(siteUrl: siteUrl, channel: channel),
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
                    if (channel.readRestricted)
                      const DIcon(DIcons.lock, size: 12),
                    if (at != null)
                      Text(
                        _activityLabel(context, at),
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
  const _ConversationAvatar({required this.siteUrl, required this.channel});

  final String siteUrl;
  final ChatChannel channel;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final color = channel.categoryColor ?? tokens.mutedForeground;
    final fallback = DAvatarFallback(
      backgroundColor: color.withValues(alpha: .22),
      foregroundColor: color,
      child: channel.isDirectMessage
          ? channel.isGroup || channel.users.length > 1
                ? const DIcon(DIcons.users, size: 20)
                : Text(
                    channel.title.characters.take(1).toString().toUpperCase(),
                  )
          : Text(
              '#',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w400,
              ),
            ),
    );
    if (channel.isDirectMessage &&
        channel.users.length == 1 &&
        !channel.isGroup) {
      return ChatUserAvatar(
        siteUrl: siteUrl,
        userId: channel.users.first.id,
        url: channel.avatarUrl,
        size: DAvatarSize.lg.dimension,
        fallback: fallback,
      );
    }
    return DAvatar(
      size: DAvatarSize.lg,
      border: false,
      decorative: true,
      fallback: fallback,
    );
  }
}

DateTime? _activityAt(ChatChannel channel) {
  var latest = channel.lastMessageAt;
  for (final replyAt in channel.unreadThreadOverview.values) {
    if (latest == null || replyAt.isAfter(latest)) latest = replyAt;
  }
  return latest;
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
