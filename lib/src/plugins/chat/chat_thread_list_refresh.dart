import 'chat_thread.dart';

/// Records title and personal-state changes during one thread-list HTTP
/// request. The page it answers may predate them, so it must not put back an
/// older title, notification level, read position or unread count.
/// Keeping dirty fields, rather than comparing only the final record with its
/// starting value, also preserves changes that return to their original value.
final class ChatThreadListRefresh {
  final Map<int, _ThreadChanges> _changes = {};
  final Map<int, ({int channelId, DateTime deletedAt})> _sourceMoves = {};

  void recordSourceMoved(
    int channelId,
    Set<int> threadIds,
    DateTime deletedAt,
  ) {
    for (final threadId in threadIds) {
      _sourceMoves[threadId] = (channelId: channelId, deletedAt: deletedAt);
    }
  }

  void recordChange(ChatThread? before, ChatThread after) {
    final changes = _changes[after.id] ?? _ThreadChanges();
    changes.record(before, after);
    if (changes.hasChanges) _changes[after.id] = changes;
  }

  void recordTitleChange(int threadId) {
    (_changes[threadId] ??= _ThreadChanges()).title = true;
  }

  ChatThread projectSourceMoves(ChatThread incoming) {
    final move = _sourceMoves[incoming.id];
    return move != null && move.channelId == incoming.channelId
        ? incoming.withSourceMoved(move.deletedAt)
        : incoming;
  }

  /// Answers [incoming] carrying [held]'s values for every field changed
  /// since the request began, for the store to merge as usual.
  ChatThread reconcile(ChatThread incoming, ChatThread? held) {
    incoming = projectSourceMoves(incoming);
    final changes = _changes[incoming.id];
    if (changes == null || held == null) return incoming;
    final kept = held.membership;
    final reported = incoming.membership;
    final ChatThreadMembership? membership;
    if (kept == null) {
      // With nothing held, a changed level is a local removal, such as a
      // refused first notification choice.
      membership = changes.level ? null : reported;
    } else {
      // An unreported membership already merges to the held one.
      membership = reported?.copyWith(
        notificationLevel: changes.level ? kept.notificationLevel : null,
        lastReadMessageId: changes.activity ? kept.lastReadMessageId : null,
        clearLastReadMessageId:
            changes.activity && kept.lastReadMessageId == null,
      );
    }
    return incoming.copyWith(
      title: changes.title ? held.title : null,
      clearTitle: changes.title && held.title == null,
      membership: membership,
      clearMembership: membership == null,
      tracking: changes.activity ? held.tracking : null,
    );
  }
}

final class _ThreadChanges {
  bool title = false;
  bool level = false;
  bool activity = false;

  bool get hasChanges => title || level || activity;

  void record(ChatThread? before, ChatThread after) {
    if (before == null || before.title != after.title) title = true;
    final previous = before?.membership;
    final next = after.membership;
    if (before == null ||
        previous?.notificationLevel != next?.notificationLevel) {
      level = true;
    }
    // Read position and unread counts describe one personalized state. A late
    // page must not split that state.
    if (before == null ||
        previous?.lastReadMessageId != next?.lastReadMessageId ||
        before.tracking != after.tracking) {
      activity = true;
    }
  }
}
