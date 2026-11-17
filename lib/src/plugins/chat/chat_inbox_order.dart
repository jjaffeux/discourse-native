import 'dart:math' as math;

import 'chat_channel.dart';
import 'chat_inbox_filters.dart';

enum ChatInboxSectionKind {
  results,
  starred,
  channels,
  directMessages,
  allChats,
}

typedef ChatInboxSection = ({
  ChatInboxSectionKind kind,
  List<ChatChannel> channels,
});

/// What a chat's row counts as new: messages and mentions in the chat itself.
/// Replies in its threads are said once, by the way to the threads.
int chatInboxUnreadCount(ChatChannel channel) =>
    math.max(channel.tracking.unreadCount, channel.tracking.mentionCount);

/// A muted chat is never new, whatever is in it.
bool chatInboxIsNew(ChatChannel channel) =>
    !channel.membership.muted && chatInboxUnreadCount(channel) > 0;

/// Threads with replies the reader has not seen, across [channels].
int chatInboxUnreadThreads(Iterable<ChatChannel> channels) => channels.fold(
  0,
  (count, channel) =>
      count + (channel.threadingEnabled ? channel.unreadThreadCount : 0),
);

/// [channels] already follows actual message and unread-thread activity, so
/// each part taken from it in order stays the most recent first.
///
/// Every group leads with what is new and closes with what is muted. The one
/// list also leads each of its new and read parts with what is starred, as no
/// Starred group stands over it.
List<ChatInboxSection> chatInboxSections(
  List<ChatChannel> channels,
  ChatInboxSort sort,
) {
  List<ChatChannel> newFirst(
    Iterable<ChatChannel> group, {
    bool starredFirst = false,
  }) {
    final fresh = <ChatChannel>[];
    final read = <ChatChannel>[];
    final muted = <ChatChannel>[];
    for (final channel in group) {
      (channel.membership.muted
              ? muted
              : chatInboxIsNew(channel)
              ? fresh
              : read)
          .add(channel);
    }
    Iterable<ChatChannel> led(List<ChatChannel> part) => !starredFirst
        ? part
        : [
            ...part.where((channel) => channel.membership.starred),
            ...part.where((channel) => !channel.membership.starred),
          ];
    return [...led(fresh), ...led(read), ...muted];
  }

  return [
    if (sort == ChatInboxSort.newest)
      (
        kind: ChatInboxSectionKind.allChats,
        channels: newFirst(channels, starredFirst: true),
      )
    else ...[
      (
        kind: ChatInboxSectionKind.starred,
        channels: newFirst(channels.where((c) => c.membership.starred)),
      ),
      (
        kind: ChatInboxSectionKind.directMessages,
        channels: newFirst(
          channels.where((c) => !c.membership.starred && c.isDirectMessage),
        ),
      ),
      (
        kind: ChatInboxSectionKind.channels,
        channels: newFirst(
          channels.where((c) => !c.membership.starred && !c.isDirectMessage),
        ),
      ),
    ],
  ].where((section) => section.channels.isNotEmpty).toList();
}

/// The ids of [channels] in the order their groups list them. A list keyed on
/// this is laid out again when a chat changes group or rank, not only when
/// its activity moves it.
List<int> chatInboxOrder(List<ChatChannel> channels, ChatInboxSort sort) => [
  for (final section in chatInboxSections(channels, sort))
    for (final channel in section.channels) channel.id,
];

/// The rows a group shows before it is asked for the rest.
///
/// A group shows all that is new in it up to [mostUnread], and never fewer
/// than [few] rows. It folds only when more than one row would be folded, and
/// never when it stands alone. The row [keep] names is shown wherever it falls.
final class ChatInboxSectionSlice<T> {
  ChatInboxSectionSlice(
    List<T> items, {
    required bool expanded,
    required bool alone,
    bool Function(T item)? keep,
    bool Function(T item)? isNew,
  }) {
    final shownFolded = math.max(
      few,
      math.min(isNew == null ? 0 : items.where(isNew).length, mostUnread),
    );
    canFold = !alone && items.length > shownFolded + 1;
    var shown = expanded || !canFold ? items : items.take(shownFolded).toList();
    if (!expanded && canFold && keep != null) {
      final held = items.skip(shownFolded).where(keep).firstOrNull;
      if (held != null) shown = [...shown, held];
    }
    visible = shown;
    hidden = items.length - shown.length;
    if (isNew == null || hidden == 0) {
      hiddenUnread = 0;
    } else {
      final seen = Set<T>.identity()..addAll(shown);
      hiddenUnread = items
          .where((item) => !seen.contains(item) && isNew(item))
          .length;
    }
  }

  static const few = 4;
  static const mostUnread = 10;

  late final bool canFold;
  late final List<T> visible;
  late final int hidden;

  /// How many of the [hidden] rows are new.
  late final int hiddenUnread;
}
