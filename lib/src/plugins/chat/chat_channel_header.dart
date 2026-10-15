import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import 'chat_channel.dart';
import 'chat_channel_actions.dart';
import 'chat_controller.dart';
import 'chat_conversation_header.dart';
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
    required this.onOpenDetails,
    this.compact = false,
    this.now,
  });

  final String siteUrl;
  final int channelId;
  final ChatChannel? channel;
  final ChatStreamState stream;
  final ChatChannelActivity activity;
  final VoidCallback onOpenDetails;
  final bool compact;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    var latest = channel?.lastMessageId == null ? null : channel?.lastMessageAt;
    final loadedLatest = activity.latestAt;
    if (loadedLatest != null &&
        (latest == null || loadedLatest.isAfter(latest))) {
      latest = loadedLatest;
    }
    return ChatConversationHeader(
      key: ValueKey(
        compact ? 'chat-channel-compact-header' : 'chat-channel-header',
      ),
      title: channel?.title ?? context.l10n.chat,
      color: channel?.categoryColor,
      direct: channel?.isDirectMessage == true,
      kindLabel: channel?.isDirectMessage == true
          ? context.l10n.directMessage
          : context.l10n.channel,
      messageCount: activity.messageCount,
      threadCount: activity.threadIds.length,
      fetchedOnce: stream.fetchedOnce,
      partial: stream.canLoadMorePast || stream.canLoadMoreFuture,
      latest: latest,
      compact: compact,
      now: now,
      titleBuilder: (title) => ChatChannelMenu(
        siteUrl: siteUrl,
        channelId: channelId,
        child: DButton(
          key: const ValueKey('content-header-title-action'),
          variant: DButtonVariant.inline,
          density: DButtonDensity.inlineMetadata,
          semanticLabel: context.l10n.openDetails(
            channel?.title ?? context.l10n.chat,
          ),
          onPressed: onOpenDetails,
          label: title,
        ),
      ),
    );
  }
}
