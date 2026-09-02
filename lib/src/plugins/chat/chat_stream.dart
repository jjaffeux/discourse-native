import 'package:flutter/foundation.dart';

import '../../foundation/calendar_day.dart';
import '../../models/site_config.dart';
import '../../shell/time_gap.dart';
import 'chat_message.dart';

@immutable
sealed class ChatStreamItem {
  const ChatStreamItem();
}

final class ChatStreamMessage extends ChatStreamItem {
  const ChatStreamMessage({required this.id, required this.chained});

  final int id;

  final bool chained;

  @override
  bool operator ==(Object other) =>
      other is ChatStreamMessage && other.id == id && other.chained == chained;

  @override
  int get hashCode => Object.hash(id, chained);
}

final class ChatStreamDay extends ChatStreamItem {
  const ChatStreamDay(this.day);

  /// Reader-local midnight, not server or UTC midnight.
  final DateTime day;

  @override
  bool operator ==(Object other) => other is ChatStreamDay && other.day == day;

  @override
  int get hashCode => day.hashCode;
}

final class ChatStreamTimeGap extends ChatStreamItem {
  const ChatStreamTimeGap({required this.messageId, required this.daysSince});

  final int messageId;
  final int daysSince;

  @override
  bool operator ==(Object other) =>
      other is ChatStreamTimeGap &&
      other.messageId == messageId &&
      other.daysSince == daysSince;

  @override
  int get hashCode => Object.hash(messageId, daysSince);
}

final class ChatStreamDeleted extends ChatStreamItem {
  ChatStreamDeleted(Iterable<int> messageIds)
    : messageIds = List.unmodifiable(messageIds);

  final List<int> messageIds;
  int get count => messageIds.length;

  @override
  bool operator ==(Object other) =>
      other is ChatStreamDeleted && listEquals(other.messageIds, messageIds);

  @override
  int get hashCode => Object.hashAll(messageIds);
}

final class ChatStreamNewDivider extends ChatStreamItem {
  const ChatStreamNewDivider();

  @override
  bool operator ==(Object other) => other is ChatStreamNewDivider;

  @override
  int get hashCode => 0;
}

// Mirrors Discourse's 300000ms message-chain window.
const Duration chatChainWindow = Duration(minutes: 5);

/// Requires one contiguous oldest-first window because every rule depends on
/// the preceding message.
List<ChatStreamItem> buildChatStream(
  List<ChatMessage> messages, {
  int? lastReadMessageId,
  int? newestMessageId,
  int showTimeGapDays = SiteConfig.defaultShowTimeGapDays,
}) {
  final items = <ChatStreamItem>[];

  // Like Discourse, omit a divider immediately above the sole newest unread row.
  final firstUnreadId = lastReadMessageId == null
      ? null
      : messages
            .where((message) => message.id > lastReadMessageId)
            .map((message) => message.id)
            .firstOrNull;
  final showDivider =
      firstUnreadId != null &&
      firstUnreadId != (newestMessageId ?? messages.lastOrNull?.id);

  ChatMessage? previous;
  final deletedRun = <int>[];

  void flushDeleted() {
    if (deletedRun.isEmpty) return;
    items.add(ChatStreamDeleted(deletedRun));
    deletedRun.clear();
  }

  for (final message in messages) {
    final day = calendarDay(message.createdAt);
    final previousDay = calendarDay(previous?.createdAt);
    final dayChanged = day != null && day != previousDay;
    final daysSince = timeGapDaysBetween(
      previous?.createdAt,
      message.createdAt,
    );
    final showTimeGap = daysSince != null && daysSince > showTimeGapDays;

    if (dayChanged) {
      // A deleted run cannot span a day separator.
      flushDeleted();
      items.add(ChatStreamDay(day));
    }

    if (showTimeGap) {
      flushDeleted();
      items.add(ChatStreamTimeGap(messageId: message.id, daysSince: daysSince));
    }

    if (showDivider && message.id == firstUnreadId) {
      flushDeleted();
      items.add(const ChatStreamNewDivider());
    }

    if (message.isDeleted) {
      deletedRun.add(message.id);
      // Keep the deleted predecessor so its collapsed run breaks speaker chaining.
      previous = message;
      continue;
    }

    flushDeleted();
    items.add(
      ChatStreamMessage(
        id: message.id,
        chained:
            !dayChanged &&
            !showTimeGap &&
            !(showDivider && message.id == firstUnreadId) &&
            _chains(message, previous),
      ),
    );
    previous = message;
  }

  flushDeleted();
  return items;
}

/// Reprojects only a prepended page and the old window's leading seam. Null
/// means the projection has no non-deleted splice point and must be rebuilt.
List<ChatStreamItem>? prependChatStream({
  required List<ChatStreamItem> existingItems,
  required List<ChatMessage> prepended,
  required List<ChatMessage> existingLeading,
  int? lastReadMessageId,
  int? newestMessageId,
  int showTimeGapDays = SiteConfig.defaultShowTimeGapDays,
}) {
  if (prepended.isEmpty || existingLeading.isEmpty) return null;

  final boundary = existingLeading.last;
  if (boundary.isDeleted) return null;

  final boundaryRow = existingItems.indexWhere(
    (item) => item is ChatStreamMessage && item.id == boundary.id,
  );
  if (boundaryRow < 0) return null;

  return [
    ...buildChatStream(
      [...prepended, ...existingLeading],
      lastReadMessageId: lastReadMessageId,
      newestMessageId: newestMessageId,
      showTimeGapDays: showTimeGapDays,
    ),
    ...existingItems.skip(boundaryRow + 1),
  ];
}

/// Reprojects only an appended run and the held window's trailing seam:
/// [existingTrailing] is the last non-deleted held message followed by any
/// deleted run after it. Null means the held rows would change as well and
/// the projection must be rebuilt: there is no non-deleted splice point, or a
/// held sole newest unread row now needs the divider the full projection
/// omits above it.
List<ChatStreamItem>? appendChatStream({
  required List<ChatStreamItem> existingItems,
  required List<ChatMessage> existingTrailing,
  required List<ChatMessage> appended,
  int? lastReadMessageId,
  int? newestMessageId,
  int showTimeGapDays = SiteConfig.defaultShowTimeGapDays,
}) {
  if (appended.isEmpty || existingTrailing.isEmpty) return null;

  final boundary = existingTrailing.first;
  if (boundary.isDeleted) return null;

  final boundaryRow = existingItems.lastIndexWhere(
    (item) => item is ChatStreamMessage && item.id == boundary.id,
  );
  if (boundaryRow < 0) return null;

  // Ids ascend along the window, so the kept rows hold the first unread row
  // exactly when their last row is unread. They then own the divider: a row
  // that has none was the sole newest unread and gains one only through a
  // full projection. A first unread row in the rebuilt tail, or none at all,
  // lets the tail place the divider the way the full projection would.
  final keptRowsHoldFirstUnread =
      lastReadMessageId != null && boundary.id > lastReadMessageId;
  if (keptRowsHoldFirstUnread &&
      !existingItems
          .take(boundaryRow + 1)
          .any((item) => item is ChatStreamNewDivider)) {
    return null;
  }

  final tail = buildChatStream(
    [...existingTrailing, ...appended],
    lastReadMessageId: keptRowsHoldFirstUnread ? null : lastReadMessageId,
    newestMessageId: newestMessageId,
    showTimeGapDays: showTimeGapDays,
  );
  final tailBoundaryRow = tail.indexWhere(
    (item) => item is ChatStreamMessage && item.id == boundary.id,
  );
  if (tailBoundaryRow < 0) return null;

  return [
    ...existingItems.take(boundaryRow + 1),
    ...tail.skip(tailBoundaryRow + 1),
  ];
}

/// Matches Discourse's speaker-chain rules except `firstOfResults`: this client
/// proves page adjacency, so transport boundaries do not create visual seams.
bool _chains(ChatMessage message, ChatMessage? previous) {
  if (previous == null) return false;

  // Core always gives a pinned message its own speaker header, even when the
  // same author spoke immediately before it.
  if (message.pinned) return false;

  // A collapsed deleted row breaks the visible speaker run.
  if (previous.isDeleted) return false;

  // Webhook messages never share a speaker run.
  if (message.isWebhook || previous.isWebhook) return false;

  if (message.author.id != previous.author.id) return false;

  final (at, before) = (message.createdAt, previous.createdAt);
  if (at == null || before == null) return false;
  if (at.difference(before).abs() > chatChainWindow) return false;

  // A reply chains only when it answers the immediately preceding row.
  if (message.replyTo case final reply?) {
    return reply.id == previous.id;
  }

  return true;
}
