part of 'chat_controller.dart';

final class _ChatChannelProjection {
  _ChatChannelProjection(this.dependencies, Iterable<ChatChannel> channels)
    : ids = [for (final channel in channels) channel.id];

  final List<Object?> dependencies;
  final List<int> ids;
}

/// Effective activity shared by inbox ordering and its displayed timestamp.
DateTime? chatInboxActivityAt(ChatChannel channel) {
  final messageAt = (channel.lastMessageId ?? 0) > 0
      ? channel.lastMessageAt
      : null;
  final threadAt = channel.latestUnreadThreadAt;
  return messageAt == null || (threadAt != null && threadAt.isAfter(messageAt))
      ? threadAt
      : messageAt;
}

extension on _ChatChannelDirectory {
  List<ChatChannel> _projectChannels(
    Object slot,
    List<Object?> dependencies,
    List<ChatChannel> Function() build, {
    bool mutable = false,
  }) {
    var projection = _projections[slot];
    if (projection == null ||
        !listEquals(projection.dependencies, dependencies)) {
      projection = _ChatChannelProjection(dependencies, build());
      if (_projections.length == 24 && !_projections.containsKey(slot)) {
        _projections.remove(_projections.keys.first);
      }
      _projections[slot] = projection;
    }
    final channels = _resolve(projection.ids);
    return mutable ? channels : List.unmodifiable(channels);
  }

  List<ChatChannel> _preferenceChannelList(
    List<ChatChannel> source, {
    required ChatChannelListSection section,
    required ChatChannelListFilter filter,
    required ChatChannelListSort sort,
    required DateTime now,
    required bool sidebar,
    int? activeChannelId,
  }) {
    final cutoff = now.subtract(const Duration(days: 30));
    final unreadCounts = Map<ChatChannel, int>.identity();
    int unread(ChatChannel channel) => unreadCounts.putIfAbsent(
      channel,
      () =>
          channel.tracking.unreadCount +
          channel.tracking.mentionCount +
          channel.tracking.watchedThreadsUnreadCount +
          (channel.threadingEnabled
              ? channel.unreadThreadsCountSinceLastViewed
              : 0),
    );
    final needsUnread =
        filter == ChatChannelListFilter.unread ||
        sort == ChatChannelListSort.priority;
    final needsUrgent = needsUnread || filter == ChatChannelListFilter.mentions;
    final needsActivity = sort != ChatChannelListSort.alphabetical;
    bool recentlyActive(ChatChannel channel) =>
        channel.lastMessageId != null &&
        channel.lastMessageId != 0 &&
        channel.lastMessageAt != null &&
        !channel.lastMessageAt!.isBefore(cutoff);
    int? unreadDependency(ChatChannel channel) {
      if (channel.membership.muted) return null;
      final retained = channel.id == activeChannelId;
      if (filter == ChatChannelListFilter.unread && !retained) {
        return unread(channel);
      }
      if (sort != ChatChannelListSort.priority) return null;
      final urgent =
          channel.tracking.mentionCount +
          channel.tracking.watchedThreadsUnreadCount;
      if (urgent > 0) return null;
      if (!retained &&
          (filter == ChatChannelListFilter.mentions ||
              (filter == ChatChannelListFilter.active &&
                  !recentlyActive(channel)))) {
        return null;
      }
      return unread(channel);
    }

    return _projectChannels(
      ('preference', section, sidebar),
      [
        (filter, sort, activeChannelId),
        for (final channel in source)
          (
            channel.id,
            channel.isDirectMessage,
            channel.isDirectMessage ? channel.title : channel.slug,
            needsUrgent ? channel.membership.muted : null,
            needsUrgent ? channel.tracking.mentionCount : null,
            needsUrgent ? channel.tracking.watchedThreadsUnreadCount : null,
            needsUnread ? channel.tracking.unreadCount : null,
            needsUnread ? unreadDependency(channel) : null,
            needsActivity
                ? (
                    channel.lastMessageId != null && channel.lastMessageId != 0,
                    channel.lastMessageAt,
                  )
                : null,
            filter == ChatChannelListFilter.active
                ? recentlyActive(channel)
                : null,
          ),
      ],
      () => projectChatChannelList(
        source,
        section: section,
        filter: filter,
        sort: sort,
        now: now,
        activeChannelId: activeChannelId,
        limit: section == ChatChannelListSection.directMessages ? 50 : null,
        retainActiveAtLimit: sidebar,
        unreadCountFor: unread,
      ),
    );
  }

  List<ChatChannel> _inboxConversations(
    ChatInboxFilter filter, {
    required bool publicChannelsEnabled,
  }) {
    if (filter.kind == ChatInboxKind.voiceRooms) return const [];
    final channels =
        [
              if (publicChannelsEnabled &&
                  filter.kind != ChatInboxKind.directMessages)
                ...publicChannels(),
              if (filter.kind != ChatInboxKind.channels) ...directChannels(),
            ]
            .where((channel) => !filter.unreadOnly || channel.badge.isVisible)
            .toList();
    if (channels.length < 2) return channels;
    final activity = {
      for (final channel in channels) channel.id: chatInboxActivityAt(channel),
    };
    return _projectChannels(
      ('inbox', filter.kind, filter.unreadOnly),
      [
        for (final channel in channels)
          (channel.id, channel.title, activity[channel.id]),
      ],
      () {
        final ranked =
            [
              for (final channel in channels)
                (
                  channel: channel,
                  activityAt: activity[channel.id],
                  title: channel.title.toLowerCase(),
                ),
            ]..sort((a, b) {
              final aTime = a.activityAt;
              final bTime = b.activityAt;
              final recent = aTime == null
                  ? (bTime == null ? 0 : 1)
                  : bTime == null
                  ? -1
                  : bTime.compareTo(aTime);
              if (recent != 0) return recent;
              final title = a.title.compareTo(b.title);
              return title != 0 ? title : a.channel.id.compareTo(b.channel.id);
            });
        return [for (final entry in ranked) entry.channel];
      },
      mutable: true,
    );
  }
}
