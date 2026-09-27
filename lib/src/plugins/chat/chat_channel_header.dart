import 'package:discourse_native/discourse_plugin_sdk.dart';
import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_channel.dart';
import 'chat_channel_star_button.dart';
import 'chat_controller.dart';
import 'chat_message.dart';

/// Metadata accumulated alongside the transcript without rereading its window
/// for read receipts, paging flags, or newly appended messages.
@immutable
class ChatChannelActivity {
  const ChatChannelActivity({
    this.messageCount = 0,
    this.threadIds = const {},
    this.latestAt,
  });

  final int messageCount;
  final Set<int> threadIds;
  final DateTime? latestAt;

  ChatChannelActivity adding(Iterable<ChatMessage> messages) {
    var count = messageCount;
    final threads = {...threadIds};
    var latest = latestAt;
    for (final message in messages) {
      if (message.isDeleted || message.isOptimistic) continue;
      count++;
      if (message.thread case final thread?) threads.add(thread.threadId);
      final date = message.createdAt;
      if (date != null && (latest == null || date.isAfter(latest))) {
        latest = date;
      }
    }
    return ChatChannelActivity(
      messageCount: count,
      threadIds: Set.unmodifiable(threads),
      latestAt: latest,
    );
  }
}

/// Conversation identity and activity, aligned with the channel reading lane.
class ChatChannelHeader extends StatelessWidget {
  const ChatChannelHeader({
    super.key,
    required this.siteUrl,
    required this.channelId,
    required this.channel,
    required this.stream,
    required this.activity,
    required this.onBack,
    required this.onOpenDetails,
    this.now,
  });

  final String siteUrl;
  final int channelId;
  final ChatChannel? channel;
  final ChatStreamState stream;
  final ChatChannelActivity activity;
  final VoidCallback onBack;
  final VoidCallback onOpenDetails;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final title = channel?.title ?? 'Chat';
    final direct = channel?.isDirectMessage == true;
    final user = direct && channel!.users.length == 1
        ? channel!.users.single
        : null;
    final threadCount = activity.threadIds.length;
    // The API supplies a window, not a channel-wide message/thread total.
    final partial = stream.canLoadMorePast || stream.canLoadMoreFuture;
    final suffix = partial ? '+' : '';
    var latest = channel?.lastMessageId == null ? null : channel?.lastMessageAt;
    final loadedLatest = activity.latestAt;
    if (loadedLatest != null &&
        (latest == null || loadedLatest.isAfter(latest))) {
      latest = loadedLatest;
    }
    final secondary = theme.discourse.primaryHigh;
    final emphasis = TextStyle(color: secondary, fontWeight: FontWeight.w600);
    final metadata = <InlineSpan>[
      TextSpan(text: direct ? 'Direct message' : 'Channel'),
      if (stream.fetchedOnce || activity.messageCount > 0)
        TextSpan(
          children: [
            TextSpan(text: '${activity.messageCount}$suffix', style: emphasis),
            TextSpan(
              text: activity.messageCount == 1 && !partial
                  ? ' message'
                  : ' messages',
            ),
          ],
        ),
      if (threadCount > 0)
        TextSpan(
          children: [
            TextSpan(text: '$threadCount$suffix', style: emphasis),
            TextSpan(
              text: threadCount == 1 && !partial ? ' thread' : ' threads',
            ),
          ],
        ),
      if (latest != null)
        TextSpan(
          children: [
            TextSpan(
              text: 'last ${_dayLabel(latest, now ?? DateTime.now())} at ',
            ),
            TextSpan(
              text: clockTimeLabel(context, latest.toLocal()).toLowerCase(),
              style: emphasis,
            ),
          ],
        ),
    ];

    return Padding(
      key: const ValueKey('chat-channel-header'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DButton(
            key: const ValueKey('chat-channel-back'),
            variant: DButtonVariant.inline,
            density: DButtonDensity.backLink,
            icon: const DIcon(DIcons.chevronLeft),
            label: const Text('Chat'),
            onPressed: onBack,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              DAvatar(
                key: const ValueKey('chat-channel-header-marker'),
                dimension: 12,
                border: false,
                decorative: true,
                borderRadius: BorderRadius.circular(direct ? 6 : 3),
                fallback: DAvatarFallback(
                  backgroundColor:
                      channel?.categoryColor ?? tokens.mutedForeground,
                  child: const SizedBox.shrink(),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: DButton(
                  key: const ValueKey('content-header-title-action'),
                  variant: DButtonVariant.inline,
                  semanticLabel: 'Open $title details',
                  onPressed: onOpenDetails,
                  label: DText(
                    title,
                    variant: DTextVariant.h3,
                    headingLevel: 1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              ChatChannelStarButton(siteUrl: siteUrl, channelId: channelId),
              UserStatusMessage(
                key: const ValueKey('chat-channel-header-status'),
                siteUrl: siteUrl,
                userId: user?.id,
                status: user?.status,
                size: 16,
                leadingGap: 5,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            key: const ValueKey('chat-channel-header-metadata'),
            spacing: 7,
            runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var index = 0; index < metadata.length; index++) ...[
                if (index > 0)
                  DText(
                    '·',
                    style: TextStyle(
                      fontSize: DiscourseTypography.preview,
                      height: DiscourseTypography.lineHeightSmall,
                      color: theme.discourse.primaryLowMid,
                    ),
                  ),
                DText.rich(
                  metadata[index],
                  style: TextStyle(
                    fontSize: DiscourseTypography.preview,
                    height: DiscourseTypography.lineHeightSmall,
                    color: tokens.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          DSeparator(
            key: const ValueKey('content-header-separator'),
            color: theme.shell.divider,
            space: 1,
          ),
        ],
      ),
    );
  }

  String _dayLabel(DateTime date, DateTime now) {
    final local = date.toLocal();
    final today = now.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (day == DateTime(today.year, today.month, today.day)) return 'today';
    if (day == DateTime(today.year, today.month, today.day - 1)) {
      return 'yesterday';
    }
    return DateFormat(
      local.year == today.year ? 'MMM d' : 'MMM d, y',
    ).format(local);
  }
}
