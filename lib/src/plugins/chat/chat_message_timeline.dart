import 'dart:collection';

import 'chat_message.dart';

/// Must return a stable canonical record throughout one synchronous reduction.
typedef ChatTimelineMessageLookup = ChatMessage? Function(int messageId);

/// No-op reductions retain [ids] identity so views can reuse projected rows.
final class ChatTimelineSnapshot {
  const ChatTimelineSnapshot({required this.ids, required this.messageById});

  final List<int> ids;
  final ChatTimelineMessageLookup messageById;

  ChatMessage? _message(int id) => messageById(id);
}

enum ChatTimelineMergeMode { sortedUnion, prependPage, appendPage }

/// The edge whose newly arrived messages must survive a bounded reduction.
enum ChatTimelineRetainedEdge { past, future }

/// Where a message falls against the rows a window holds.
enum ChatTimelinePlacement { beforeHeld, insideHeld, afterHeld }

typedef ChatTimelineSeam = ({List<int> ids, List<ChatMessage> admittedPending});
typedef ChatTimelineRetention = ({
  List<int> ids,
  bool droppedPast,
  bool droppedFuture,
});

/// Canonical ids are unique and ordered by `(createdAt, id)`, except directional
/// pages stay on the side named by the server cursor.
abstract final class ChatMessageTimeline {
  /// Directional modes sort only the bounded new page; sorted union re-derives
  /// replacement windows and clock-skew fallbacks.
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

  /// Bounds one contiguous window while preserving the edge just extended.
  ///
  /// The discarded edge becomes pageable again in the controller. Returning
  /// the exact input on a no-op lets views retain their existing projection.
  static ChatTimelineRetention retain({
    required List<int> ids,
    required int maxLength,
    required ChatTimelineRetainedEdge edge,
  }) {
    assert(maxLength > 0);
    if (ids.length <= maxLength) {
      return (ids: ids, droppedPast: false, droppedFuture: false);
    }
    return switch (edge) {
      ChatTimelineRetainedEdge.past => (
        ids: List.unmodifiable(ids.take(maxLength)),
        droppedPast: false,
        droppedFuture: true,
      ),
      ChatTimelineRetainedEdge.future => (
        ids: List.unmodifiable(ids.skip(ids.length - maxLength)),
        droppedPast: true,
        droppedFuture: false,
      ),
    };
  }

  static ChatTimelinePlacement placement({
    required ChatTimelineSnapshot held,
    required ChatMessage message,
  }) {
    final newestId = held.ids.lastOrNull;
    final oldestId = held.ids.firstOrNull;
    if (newestId == null ||
        oldestId == null ||
        _sortsAfter(
          message,
          at: held._message(newestId)?.createdAt ?? _wireEpoch,
          id: newestId,
        )) {
      return ChatTimelinePlacement.afterHeld;
    }
    return _sortsAfter(
          message,
          at: held._message(oldestId)?.createdAt ?? _wireEpoch,
          id: oldestId,
        )
        ? ChatTimelinePlacement.insideHeld
        : ChatTimelinePlacement.beforeHeld;
  }

  /// Whether a row ordered by [createdAt] and [id] sorts before each of
  /// [rows], so a page of them was cut after it.
  static bool precedesAll(
    Iterable<ChatMessage> rows, {
    required DateTime? createdAt,
    required int id,
  }) {
    final at = createdAt ?? _wireEpoch;
    var compared = false;
    for (final row in rows) {
      if (!_sortsAfter(row, at: at, id: id)) return false;
      compared = true;
    }
    return compared;
  }

  /// Appends normal live arrivals; an earlier `client_created_at` re-derives
  /// the full order.
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
    return UnmodifiableListView([...held.ids, message.id]);
  }

  /// Admits only pending rows beyond the held cursor; older rows would falsely
  /// bridge an unseen gap. Records accompany ids so optimistic rows retire in
  /// the same commit.
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
    final messages = <int, ChatMessage>{
      for (final id in held.ids) id: ?held._message(id),
      for (final message in arrived) message.id: message,
    };
    final ordered = messages.entries.toList()
      ..sort((a, b) {
        final byDate = (a.value.createdAt ?? _wireEpoch).compareTo(
          b.value.createdAt ?? _wireEpoch,
        );
        return byDate != 0 ? byDate : a.key.compareTo(b.key);
      });
    return [for (final entry in ordered) entry.key];
  }

  static List<int> _mergeDirectional(
    List<int> held,
    Iterable<ChatMessage> arrived, {
    required bool prepend,
  }) {
    final dates = <int, DateTime>{};
    int? firstId;
    int? lastId;
    for (final message in arrived) {
      final id = message.id;
      dates[id] = message.createdAt ?? _wireEpoch;
      if (firstId == null || id < firstId) firstId = id;
      if (lastId == null || id > lastId) lastId = id;
    }
    if (firstId == null) return held;
    for (final id in held) {
      if (id < firstId || id > lastId!) continue;
      dates.remove(id);
      if (dates.isEmpty) return held;
    }
    final fresh = dates.keys.toList()
      ..sort((a, b) {
        final byDate = dates[a]!.compareTo(dates[b]!);
        return byDate != 0 ? byDate : a.compareTo(b);
      });

    return List.unmodifiable(
      prepend ? [...fresh, ...held] : [...held, ...fresh],
    );
  }
}
