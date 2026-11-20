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

/// The line of a chat that holds the words it was found by, shown in place of
/// whatever was said last, which may not hold them at all.
final class ChatInboxFoundLine {
  const ChatInboxFoundLine({
    required this.text,
    required this.query,
    required this.createdAt,
    this.authorId,
    this.authorName,
    this.authorAvatarUrl,
  });

  final String text;
  final String query;
  final DateTime? createdAt;
  final int? authorId;
  final String? authorName;
  final String? authorAvatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ChatInboxFoundLine &&
      other.text == text &&
      other.query == query &&
      other.createdAt == createdAt &&
      other.authorId == authorId &&
      other.authorName == authorName &&
      other.authorAvatarUrl == authorAvatarUrl;

  @override
  int get hashCode => Object.hash(
    text,
    query,
    createdAt,
    authorId,
    authorName,
    authorAvatarUrl,
  );
}

/// The chats some words found: those found by name first, then those found by
/// what was said in them. Either kind can have a matching line.
typedef ChatInboxResults = ({
  List<ChatChannel> channels,
  Map<int, ChatInboxFoundLine> lines,
});

/// What is new first, then the rest, then what is muted. [channels] keeps its
/// order within each part, and with [starredFirst] the new and the read parts
/// each lead with what is starred.
List<ChatChannel> chatInboxNewFirst(
  Iterable<ChatChannel> channels, {
  bool starredFirst = false,
}) {
  final fresh = <ChatChannel>[];
  final read = <ChatChannel>[];
  final muted = <ChatChannel>[];
  for (final channel in channels) {
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

/// [channels] already follows actual message and unread-thread activity, so
/// each part taken from it in order stays the most recent first.
///
/// Every group leads with what is new and closes with what is muted. The one
/// list also leads each of its new and read parts with what is starred, as no
/// Starred group stands over it.
List<ChatInboxSection> chatInboxSections(
  List<ChatChannel> channels,
  ChatInboxSort sort,
) => [
  if (sort == ChatInboxSort.newest)
    (
      kind: ChatInboxSectionKind.allChats,
      channels: chatInboxNewFirst(channels, starredFirst: true),
    )
  else ...[
    (
      kind: ChatInboxSectionKind.starred,
      channels: chatInboxNewFirst(channels.where((c) => c.membership.starred)),
    ),
    (
      kind: ChatInboxSectionKind.directMessages,
      channels: chatInboxNewFirst(
        channels.where((c) => !c.membership.starred && c.isDirectMessage),
      ),
    ),
    (
      kind: ChatInboxSectionKind.channels,
      channels: chatInboxNewFirst(
        channels.where((c) => !c.membership.starred && !c.isDirectMessage),
      ),
    ),
  ],
].where((section) => section.channels.isNotEmpty).toList();

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
/// than its configured minimum. It folds only when more than one row would be folded, and
/// never when it stands alone. The row [keep] names is shown wherever it falls.
final class ChatInboxSectionSlice<T> {
  ChatInboxSectionSlice(
    List<T> items, {
    required bool expanded,
    required bool alone,
    bool Function(T item)? keep,
    bool Function(T item)? isNew,
    int few = defaultFew,
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

  static const defaultFew = 4;
  static const mostUnread = 10;

  late final bool canFold;
  late final List<T> visible;
  late final int hidden;

  /// How many of the [hidden] rows are new.
  late final int hiddenUnread;
}
