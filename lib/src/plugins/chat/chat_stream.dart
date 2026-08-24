import 'package:flutter/foundation.dart';

import '../../foundation/calendar_day.dart';
import '../../models/site_config.dart';
import '../../shell/time_gap.dart';
import 'chat_message.dart';

/// One row of a channel, in the order it is read.
///
/// A union rather than a list of messages with flags hung off them, because
/// three of the four rows are not messages at all: a day separator stands
/// between two of them, and a run of deleted ones collapses into a single row
/// that is none of them in particular.
///
/// Pure — nothing here imports Flutter beyond `foundation`, so the whole of the
/// grouping can be tested without pumping a widget.
@immutable
sealed class ChatStreamItem {
  const ChatStreamItem();
}

/// A message, and whether it belongs to the run above it.
final class ChatStreamMessage extends ChatStreamItem {
  const ChatStreamMessage({required this.id, required this.chained});

  final int id;

  /// True when the avatar, the name and the time are the same answer as the row
  /// above, so this row draws none of them.
  final bool chained;

  @override
  bool operator ==(Object other) =>
      other is ChatStreamMessage && other.id == id && other.chained == chained;

  @override
  int get hashCode => Object.hash(id, chained);
}

/// The start of a calendar day, drawn above its first message.
final class ChatStreamDay extends ChatStreamItem {
  const ChatStreamDay(this.day);

  /// Local midnight. Local rather than UTC deliberately: "yesterday" means the
  /// reader's yesterday, not the server's.
  final DateTime day;

  @override
  bool operator ==(Object other) => other is ChatStreamDay && other.day == day;

  @override
  int get hashCode => day.hashCode;
}

/// A long silence immediately before [messageId].
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

/// A run of consecutive deleted messages, drawn as one row.
///
/// Only a moderator is ever sent these, and without the collapse they see a
/// column of empty tiles where a conversation used to be.
final class ChatStreamDeleted extends ChatStreamItem {
  const ChatStreamDeleted(this.count);

  final int count;

  @override
  bool operator ==(Object other) =>
      other is ChatStreamDeleted && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

/// Where the messages the reader has not seen begin.
final class ChatStreamNewDivider extends ChatStreamItem {
  const ChatStreamNewDivider();

  @override
  bool operator ==(Object other) => other is ChatStreamNewDivider;

  @override
  int get hashCode => 0;
}

/// How long a silence has to be before the next message starts a new run.
///
/// Five minutes, which is Discourse's own number
/// (`chat-message.gjs`, `300000` ms). Long enough that a burst of typing stays
/// one block, short enough that picking a conversation back up after lunch does
/// not read as one.
const Duration chatChainWindow = Duration(minutes: 5);

/// Turns a channel's messages into the rows that draw it.
///
/// [messages] must be in the order the stream holds them — oldest first,
/// contiguous — because every rule here is about a message's relationship to
/// the one before it.
///
/// [lastReadMessageId] places the unread divider, and null leaves it out.
List<ChatStreamItem> buildChatStream(
  List<ChatMessage> messages, {
  int? lastReadMessageId,
  int? newestMessageId,
  int showTimeGapDays = SiteConfig.defaultShowTimeGapDays,
}) {
  final items = <ChatStreamItem>[];

  // Suppressed when everything is read, and — like Discourse — when the first
  // unread message is the newest one there is: a divider immediately above the
  // last row separates nothing from nothing.
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
  var deletedRun = 0;

  void flushDeleted() {
    if (deletedRun == 0) return;
    items.add(ChatStreamDeleted(deletedRun));
    deletedRun = 0;
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
      // A day separator ends whatever was above it, deleted run included:
      // "3 messages deleted" spanning a date boundary would put them on a day
      // half of them were not written on.
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
      deletedRun++;
      // Deliberately still the previous message for the next row's chaining
      // rule, which asks whether the row above was deleted precisely so that a
      // collapsed run breaks the chain across it.
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

/// Extends an existing projection with a page immediately before it.
///
/// Only the new page and the seam need projecting again. [existingLeading]
/// starts at the old window's first message and ends at its first non-deleted
/// message. That last row is a safe splice point: it flushes any deleted run,
/// and every later row depends only on messages that have not changed.
///
/// Null means the supplied projection has no safe seam and the caller should
/// rebuild the whole stream. This is rare (an existing window made entirely of
/// moderator-visible deleted messages), but correctness is worth the fallback.
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

/// Whether [message] belongs to the run [previous] is part of.
///
/// Every condition here is one Discourse's own `hideUserInfo` checks, save one
/// it has and this does not: it additionally breaks the chain at the first
/// message of whichever page was fetched most recently, `firstOfResults`. That
/// rule exists because the web assembles its stream out of pages whose adjacency
/// it cannot vouch for. Here the stream is one contiguous ascending list by
/// construction — `openChannel` replaces it outright and `loadOlder` prepends
/// the page immediately before it — so a page boundary carries no information,
/// and honouring it would put a seam in the middle of a conversation whose only
/// cause is how the bytes arrived.
bool _chains(ChatMessage message, ChatMessage? previous) {
  // Nothing above to join.
  if (previous == null) return false;

  // A deleted message became a "N messages deleted" row, which is a different
  // voice interrupting; and the row after it has no visible neighbour to share
  // a header with.
  if (previous.isDeleted) return false;

  // An integration is not somebody, so two of its messages in a row are not one
  // person talking — and a person's message after one is not a continuation.
  if (message.isWebhook || previous.isWebhook) return false;

  // The first outgoing overlay may sit after a window anchored arbitrarily far
  // behind the present. Its local timestamp cannot prove adjacency across that
  // unseen gap, so it always starts a new run. Consecutive optimistic messages
  // may still group with one another.
  if (message.isOptimistic && !previous.isOptimistic) return false;

  if (message.author.id != previous.author.id) return false;

  final (at, before) = (message.createdAt, previous.createdAt);
  if (at == null || before == null) return false;
  if (at.difference(before).abs() > chatChainWindow) return false;

  // Answering something is a new thought unless the thing answered is the row
  // immediately above, in which case the reply arrow would point at a message
  // the reader can already see and the run reads as continuous.
  if (message.replyTo case final reply?) {
    return reply.id == previous.id;
  }

  return true;
}
