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

typedef ChatTimelineSeam = ({List<int> ids, List<ChatMessage> admittedPending});

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
    return List.unmodifiable([...held.ids, message.id]);
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
