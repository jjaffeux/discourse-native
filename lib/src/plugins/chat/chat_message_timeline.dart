import 'chat_message.dart';

/// Reads one canonical message while a timeline reduction is in progress.
///
/// The answer must remain stable for the duration of a synchronous reduction.
/// Production supplies a read-only view of the message store; tests usually
/// supply a map. Keeping the records behind this narrow lookup lets the common
/// live-message path read only the newest row while the clock-skew fallback can
/// still derive the whole window.
typedef ChatTimelineMessageLookup = ChatMessage? Function(int messageId);

/// The canonical ids currently held and the records that explain their order.
///
/// [ids] is deliberately retained by identity. A no-op reduction returns that
/// exact list so the view can reuse its projected rows when only loading flags
/// change.
final class ChatTimelineSnapshot {
  const ChatTimelineSnapshot({required this.ids, required this.messageById});

  final List<int> ids;
  final ChatTimelineMessageLookup messageById;

  ChatMessage? _message(int id) => messageById(id);
}

/// How arrivals from an HTTP page relate to the held cursor.
enum ChatTimelineMergeMode {
  /// Re-derive a replacement window or a non-directional union.
  sortedUnion,

  /// The site returned the page immediately before the oldest id held.
  prependPage,

  /// The site returned the page immediately after the newest id held.
  appendPage,
}

/// The outcome of closing the gap between an anchored window and the present.
typedef ChatTimelineSeam = ({List<int> ids, List<ChatMessage> admittedPending});

/// Pure ordering policy for one canonical chat-message window.
///
/// The controller owns transport, the Store, pending-set mutation and
/// optimistic-row retirement. This module owns the subtler invariant beneath
/// all of them: canonical ids are unique and ordered by `(createdAt, id)`,
/// except that directional pages trust the site's cursor and stay on the side
/// it named rather than re-sorting the entire accumulated window.
abstract final class ChatMessageTimeline {
  /// Merges [arrived] according to [mode].
  ///
  /// A directional merge sorts and deduplicates only the fresh page. This keeps
  /// paging linear in the site's bounded response rather than in all history
  /// accumulated so far. [ChatTimelineMergeMode.sortedUnion] is the full
  /// derivation used for replacement windows and clock-skew fallbacks.
  static List<int> merge({
    required ChatTimelineSnapshot held,
    required Iterable<ChatMessage> arrived,
    required ChatTimelineMergeMode mode,
  }) => switch (mode) {
    ChatTimelineMergeMode.sortedUnion => _sortedUnion(held, arrived),
    ChatTimelineMergeMode.prependPage => _mergeDirectional(
      held.ids,
      arrived,
      prepend: true,
    ),
    ChatTimelineMergeMode.appendPage => _mergeDirectional(
      held.ids,
      arrived,
      prepend: false,
    ),
  };

  /// Admits one unheld live [message] to a window already at the present.
  ///
  /// Published messages ordinarily follow the newest row, so that path is a
  /// single lookup and append. Discourse may adopt a sender's earlier
  /// `client_created_at`; only that clock-skew case re-derives the full order.
  static List<int> admitLive({
    required ChatTimelineSnapshot held,
    required ChatMessage message,
  }) {
    final newestId = held.ids.lastOrNull;
    if (newestId != null &&
        !_sortsAfter(
          message,
          at: held._message(newestId)?.createdAt ?? _wireEpoch,
          id: newestId,
        )) {
      return _sortedUnion(held, [message]);
    }
    return List.unmodifiable([...held.ids, message.id]);
  }

  /// Folds pending live records that belong beyond [held]'s newest row.
  ///
  /// Older pending leftovers must not be merged: doing so would claim a
  /// contiguous window across an unseen gap. The admitted records are returned
  /// beside their ids because the controller must retire any optimistic local
  /// rows they canonicalize in the same commit.
  static ChatTimelineSeam closeSeam({
    required ChatTimelineSnapshot held,
    required Iterable<ChatMessage> pending,
  }) {
    final newestId = held.ids.lastOrNull;
    final List<ChatMessage> admitted;
    if (newestId == null) {
      admitted = pending.toList(growable: false);
    } else {
      final newestAt = held._message(newestId)?.createdAt ?? _wireEpoch;
      admitted = [
        for (final message in pending)
          if (_sortsAfter(message, at: newestAt, id: newestId)) message,
      ];
    }
    return (
      ids: admitted.isEmpty ? held.ids : _sortedUnion(held, admitted),
      admittedPending: admitted,
    );
  }

  /// Where a message with no wire date sorts: before dated messages, and among
  /// its own kind by id.
  static final DateTime _wireEpoch = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _sortsAfter(
    ChatMessage message, {
    required DateTime at,
    required int id,
  }) => switch ((message.createdAt ?? _wireEpoch).compareTo(at)) {
    > 0 => true,
    0 => message.id > id,
    _ => false,
  };

  static List<int> _sortedUnion(
    ChatTimelineSnapshot held,
    Iterable<ChatMessage> arrived,
  ) {
    final dates = <int, DateTime>{
      for (final id in held.ids)
        if (held._message(id) case final message?)
          id: message.createdAt ?? _wireEpoch,
      for (final message in arrived)
        message.id: message.createdAt ?? _wireEpoch,
    };

    return dates.keys.toList()..sort((a, b) {
      final byDate = dates[a]!.compareTo(dates[b]!);
      return byDate != 0 ? byDate : a.compareTo(b);
    });
  }

  static List<int> _mergeDirectional(
    List<int> held,
    Iterable<ChatMessage> arrived, {
    required bool prepend,
  }) {
    final heldIds = held.toSet();
    final dates = <int, DateTime>{
      for (final message in arrived)
        if (!heldIds.contains(message.id))
          message.id: message.createdAt ?? _wireEpoch,
    };
    final fresh = dates.keys.toList()
      ..sort((a, b) {
        final byDate = dates[a]!.compareTo(dates[b]!);
        return byDate != 0 ? byDate : a.compareTo(b);
      });
    if (fresh.isEmpty) return held;

    return List.unmodifiable(
      prepend ? [...fresh, ...held] : [...held, ...fresh],
    );
  }
}
