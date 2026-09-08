import 'package:flutter/foundation.dart' show listEquals, mapEquals;

import 'chat_channel.dart';

/// Records mutations and accepted tracking during one channel-list HTTP request.
/// Keeping dirty fields, rather than comparing only the final record with its
/// starting value, also preserves changes that return to their original value.
final class ChatChannelRefresh {
  ChatChannelRefresh({
    required Iterable<int> publicIds,
    required Iterable<int> directIds,
  }) : _publicIds = publicIds.toSet(),
       _directIds = directIds.toSet();

  final Set<int> _publicIds;
  final Set<int> _directIds;
  final Map<int, _ChannelChanges> _changes = {};
  final Set<int> _removed = {};

  Set<int> get preservedActivityChannelIds => {
    for (final entry in _changes.entries)
      if (entry.value.hasActivity) entry.key,
  };

  void recordChange(ChatChannel? before, ChatChannel after) {
    _removed.remove(after.id);
    final changes = _changes[after.id] ?? _ChannelChanges();
    changes.record(before, after);
    if (changes.hasChanges) _changes[after.id] = changes;
  }

  // A live acknowledgement can repeat an optimistic projection from before the
  // GET. It still owns activity, without claiming unrelated metadata fields.
  void recordTrackingState(ChatChannel channel) {
    _changes.putIfAbsent(channel.id, _ChannelChanges.new)._activity = channel;
  }

  void removeChannel(int channelId) {
    _removed.add(channelId);
    _changes.remove(channelId);
  }

  ChatChannels reconcile(
    ChatChannels snapshot, {
    required List<ChatChannel> public,
    required List<ChatChannel> direct,
  }) {
    List<ChatChannel> reconcileList(
      List<ChatChannel> incoming,
      List<ChatChannel> current,
      Set<int> previousIds,
    ) {
      final result = <int, ChatChannel>{};
      for (final channel in incoming) {
        if (_removed.contains(channel.id)) continue;
        // An intervening unfollow removes the row and its activity subscriptions.
        final changes = _changes[channel.id];
        if (changes?.stoppedFollowing == true) continue;
        result[channel.id] = changes?.apply(channel) ?? channel;
      }
      for (final channel in current) {
        if (!_removed.contains(channel.id) &&
            (!previousIds.contains(channel.id) ||
                _changes.containsKey(channel.id))) {
          result.putIfAbsent(channel.id, () => channel);
        }
      }
      return result.values.toList(growable: false);
    }

    return ChatChannels(
      public: reconcileList(snapshot.public, public, _publicIds),
      direct: reconcileList(snapshot.direct, direct, _directIds),
      hasThreads: snapshot.hasThreads,
      presence: snapshot.presence,
      newMessageBusLastIds: snapshot.newMessageBusLastIds,
      newMentionMessageBusLastIds: snapshot.newMentionMessageBusLastIds,
      kickMessageBusLastIds: snapshot.kickMessageBusLastIds,
      channelMessageBusLastIds: snapshot.channelMessageBusLastIds,
      newChannelBusLastId: snapshot.newChannelBusLastId,
      userTrackingBusLastId: snapshot.userTrackingBusLastId,
      userHasThreadsBusLastId: snapshot.userHasThreadsBusLastId,
      channelMetadataBusLastId: snapshot.channelMetadataBusLastId,
      channelEditsBusLastId: snapshot.channelEditsBusLastId,
      channelStatusBusLastId: snapshot.channelStatusBusLastId,
    );
  }
}

enum _Field {
  title,
  kind,
  chatableId,
  slug,
  emoji,
  description,
  categoryName,
  categoryColor,
  readRestricted,
  status,
  userSilenced,
  canModerate,
  canDeleteSelf,
  canDeleteOthers,
  canManagePins,
  canFlag,
  pinnedMessagesCount,
  membershipsCount,
  canJoin,
  isGroup,
  users,
  threadingEnabled,
  following,
  muted,
  notificationLevel,
  starred,
  lastViewedAt,
  lastViewedPinsAt,
  hasUnseenPins,
}

final class _ChannelChanges {
  final Map<_Field, Object?> _values = {};
  ChatChannel? _activity;

  bool get hasChanges => _values.isNotEmpty || _activity != null;
  bool get hasActivity => _activity != null;

  bool get stoppedFollowing => _values[_Field.following] == false;

  void record(ChatChannel? before, ChatChannel after) {
    void field(_Field key, Object? previous, Object? next) {
      final equal = previous is List && next is List
          ? listEquals(previous, next)
          : previous == next;
      if (before == null || !equal) _values[key] = next;
    }

    field(_Field.title, before?.title, after.title);
    field(_Field.kind, before?.kind, after.kind);
    field(_Field.chatableId, before?.chatableId, after.chatableId);
    field(_Field.slug, before?.slug, after.slug);
    field(_Field.emoji, before?.emoji, after.emoji);
    field(_Field.description, before?.description, after.description);
    field(_Field.categoryName, before?.categoryName, after.categoryName);
    field(_Field.categoryColor, before?.categoryColor, after.categoryColor);
    field(_Field.readRestricted, before?.readRestricted, after.readRestricted);
    field(_Field.status, before?.status, after.status);
    field(_Field.userSilenced, before?.userSilenced, after.userSilenced);
    field(_Field.canModerate, before?.canModerate, after.canModerate);
    field(_Field.canDeleteSelf, before?.canDeleteSelf, after.canDeleteSelf);
    field(
      _Field.canDeleteOthers,
      before?.canDeleteOthers,
      after.canDeleteOthers,
    );
    field(_Field.canManagePins, before?.canManagePins, after.canManagePins);
    field(_Field.canFlag, before?.canFlag, after.canFlag);
    field(
      _Field.pinnedMessagesCount,
      before?.pinnedMessagesCount,
      after.pinnedMessagesCount,
    );
    field(
      _Field.membershipsCount,
      before?.membershipsCount,
      after.membershipsCount,
    );
    field(_Field.canJoin, before?.canJoin, after.canJoin);
    field(_Field.isGroup, before?.isGroup, after.isGroup);
    field(_Field.users, before?.users, after.users);
    field(
      _Field.threadingEnabled,
      before?.threadingEnabled,
      after.threadingEnabled,
    );
    field(
      _Field.following,
      before?.membership.following,
      after.membership.following,
    );
    field(_Field.muted, before?.membership.muted, after.membership.muted);
    field(
      _Field.notificationLevel,
      before?.membership.notificationLevel,
      after.membership.notificationLevel,
    );
    field(_Field.starred, before?.membership.starred, after.membership.starred);
    field(
      _Field.lastViewedAt,
      before?.membership.lastViewedAt,
      after.membership.lastViewedAt,
    );
    field(
      _Field.lastViewedPinsAt,
      before?.membership.lastViewedPinsAt,
      after.membership.lastViewedPinsAt,
    );
    field(
      _Field.hasUnseenPins,
      before?.membership.hasUnseenPins,
      after.membership.hasUnseenPins,
    );

    // Read position, exact counts, thread overview, and latest activity describe
    // one personalized state. A late snapshot must not split that state.
    if (before == null ||
        before.membership.lastReadMessageId !=
            after.membership.lastReadMessageId ||
        before.tracking != after.tracking ||
        !mapEquals(before.unreadThreadOverview, after.unreadThreadOverview) ||
        before.lastMessageId != after.lastMessageId ||
        before.lastMessageAt != after.lastMessageAt ||
        before.lastMessagePreview != after.lastMessagePreview) {
      _activity = after;
    }
  }

  T _value<T>(_Field field, T snapshot) =>
      _values.containsKey(field) ? _values[field] as T : snapshot;

  ChatChannel apply(ChatChannel snapshot) {
    final activity = _activity ?? snapshot;
    return ChatChannel(
      id: snapshot.id,
      title: _value(_Field.title, snapshot.title),
      kind: _value(_Field.kind, snapshot.kind),
      chatableId: _value(_Field.chatableId, snapshot.chatableId),
      slug: _value(_Field.slug, snapshot.slug),
      emoji: _value(_Field.emoji, snapshot.emoji),
      description: _value(_Field.description, snapshot.description),
      categoryName: _value(_Field.categoryName, snapshot.categoryName),
      categoryColor: _value(_Field.categoryColor, snapshot.categoryColor),
      readRestricted: _value(_Field.readRestricted, snapshot.readRestricted),
      status: _value(_Field.status, snapshot.status),
      userSilenced: _value(_Field.userSilenced, snapshot.userSilenced),
      canModerate: _value(_Field.canModerate, snapshot.canModerate),
      canDeleteSelf: _value(_Field.canDeleteSelf, snapshot.canDeleteSelf),
      canDeleteOthers: _value(_Field.canDeleteOthers, snapshot.canDeleteOthers),
      canManagePins: _value(_Field.canManagePins, snapshot.canManagePins),
      canFlag: _value(_Field.canFlag, snapshot.canFlag),
      pinnedMessagesCount: _value(
        _Field.pinnedMessagesCount,
        snapshot.pinnedMessagesCount,
      ),
      membershipsCount: _value(
        _Field.membershipsCount,
        snapshot.membershipsCount,
      ),
      canJoin: _value(_Field.canJoin, snapshot.canJoin),
      isGroup: _value(_Field.isGroup, snapshot.isGroup),
      users: _value(_Field.users, snapshot.users),
      threadingEnabled: _value(
        _Field.threadingEnabled,
        snapshot.threadingEnabled,
      ),
      membership: ChatMembership(
        following: _value(_Field.following, snapshot.membership.following),
        muted: _value(_Field.muted, snapshot.membership.muted),
        notificationLevel: _value(
          _Field.notificationLevel,
          snapshot.membership.notificationLevel,
        ),
        starred: _value(_Field.starred, snapshot.membership.starred),
        lastViewedAt: _value(
          _Field.lastViewedAt,
          snapshot.membership.lastViewedAt,
        ),
        lastViewedPinsAt: _value(
          _Field.lastViewedPinsAt,
          snapshot.membership.lastViewedPinsAt,
        ),
        hasUnseenPins: _value(
          _Field.hasUnseenPins,
          snapshot.membership.hasUnseenPins,
        ),
        lastReadMessageId: activity.membership.lastReadMessageId,
      ),
      tracking: activity.tracking,
      unreadThreadOverview: activity.unreadThreadOverview,
      lastMessageId: activity.lastMessageId,
      lastMessageAt: activity.lastMessageAt,
      lastMessagePreview: activity.lastMessagePreview,
      messageBus: snapshot.messageBus,
    );
  }
}
