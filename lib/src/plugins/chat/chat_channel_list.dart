import 'chat_channel.dart';
import 'chat_channel_list_preferences.dart';

/// Core's preference ordering, shared by sidebar and full-page lists.
List<ChatChannel> projectChatChannelList(
  Iterable<ChatChannel> channels, {
  required ChatChannelListFilter filter,
  required ChatChannelListSort sort,
  required ChatChannelListSection section,
  required DateTime now,
  int? activeChannelId,
  int? limit,
  bool retainActiveAtLimit = false,
}) {
  // Filtering and priority comparisons share one calculation per channel.
  // Keep this local so changed tracking and last-viewed times are read next time.
  // Identity keys avoid hashing the channel's complete thread collection.
  final unreadCounts = Map<ChatChannel, int>.identity();
  int unread(ChatChannel channel) =>
      unreadCounts.putIfAbsent(channel, () => _unread(channel));
  final priorities = Map<ChatChannel, int>.identity();
  int priority(ChatChannel channel) => priorities.putIfAbsent(
    channel,
    () => channel.membership.muted
        ? 2
        : _urgent(channel) > 0
        ? 0
        : unread(channel) > 0
        ? 1
        : 2,
  );
  final cutoff = now.subtract(const Duration(days: 30));
  final result = channels.where((channel) {
    if (channel.id == activeChannelId) return true;
    return switch (filter) {
      ChatChannelListFilter.all => true,
      ChatChannelListFilter.active =>
        channel.lastMessageId != null &&
            channel.lastMessageId != 0 &&
            channel.lastMessageAt != null &&
            !channel.lastMessageAt!.isBefore(cutoff),
      ChatChannelListFilter.unread =>
        !channel.membership.muted && unread(channel) > 0,
      ChatChannelListFilter.mentions =>
        !channel.membership.muted && _urgent(channel) > 0,
    };
  }).toList();
  result.sort((a, b) {
    if (sort == ChatChannelListSort.alphabetical) {
      if (section == ChatChannelListSection.starred &&
          a.isDirectMessage != b.isDirectMessage) {
        return a.isDirectMessage ? 1 : -1;
      }
      return _alphabetical(a, b);
    }
    if (sort == ChatChannelListSort.priority) {
      final compared = priority(a).compareTo(priority(b));
      if (compared != 0) return compared;
    }
    final recent = _recency(a, b);
    return recent != 0 ? recent : _alphabetical(a, b);
  });
  if (limit == null || result.length <= limit) return List.unmodifiable(result);
  final limited = result.take(limit).toList();
  if (retainActiveAtLimit &&
      limit > 0 &&
      !limited.any((channel) => channel.id == activeChannelId)) {
    final active = result
        .where((channel) => channel.id == activeChannelId)
        .firstOrNull;
    if (active != null) limited[limit - 1] = active;
  }
  return List.unmodifiable(limited);
}

int _urgent(ChatChannel channel) =>
    channel.tracking.mentionCount + channel.tracking.watchedThreadsUnreadCount;
int _unread(ChatChannel channel) =>
    channel.tracking.unreadCount +
    _urgent(channel) +
    (channel.threadingEnabled ? channel.unreadThreadsCountSinceLastViewed : 0);

int _alphabetical(ChatChannel a, ChatChannel b) {
  String name(ChatChannel channel) =>
      (channel.isDirectMessage ? channel.title : channel.slug ?? '')
          .toLowerCase();
  final compared = name(a).compareTo(name(b));
  return compared != 0 ? compared : a.id.compareTo(b.id);
}

int _recency(ChatChannel a, ChatChannel b) {
  bool hasActivity(ChatChannel channel) =>
      channel.lastMessageId != null &&
      channel.lastMessageId != 0 &&
      channel.lastMessageAt != null;
  final aHasActivity = hasActivity(a);
  final bHasActivity = hasActivity(b);
  if (aHasActivity != bHasActivity) return aHasActivity ? -1 : 1;
  return aHasActivity ? b.lastMessageAt!.compareTo(a.lastMessageAt!) : 0;
}
