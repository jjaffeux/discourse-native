class IncomingTopics {
  static const Set<String> _newTopicLists = {'latest', 'new'};

  static const Set<String> _bumpedLists = {'latest'};

  final Map<String, Set<int>> _incoming = {};

  List<int> topicIds(String list, {int? limit}) {
    final held = _incoming[list] ?? const <int>{};
    if (limit == null || limit >= held.length) return List.unmodifiable(held);
    if (limit <= 0) return const [];
    return List.unmodifiable(held.take(limit));
  }

  int count(String list) => _incoming[list]?.length ?? 0;

  bool notify(Object? message) {
    if (message is! Map) return false;

    final topicId = switch (message['topic_id']) {
      final num id => id.toInt(),
      _ => null,
    };
    if (topicId == null) return false;

    // `muted` and `unmuted` also arrive on /latest, and carry no payload; they
    // say a topic left or joined the reader's list, not that one arrived.
    final lists = switch (message['message_type']) {
      'new_topic' => _newTopicLists,
      'latest' => _bumpedLists,
      _ => const <String>{},
    };

    var changed = false;
    for (final list in lists) {
      changed |= (_incoming[list] ??= <int>{}).add(topicId);
    }
    return changed;
  }

  bool clear(String list, Iterable<int> ids) {
    final held = _incoming[list];
    if (held == null) return false;

    final before = held.length;
    held.removeAll(ids);
    if (held.isEmpty) _incoming.remove(list);
    return held.length != before;
  }

  bool reset(String list) => _incoming.remove(list) != null;

  bool restore(String list, Iterable<int> ids) {
    if (ids.isEmpty) return false;
    final held = _incoming[list] ??= <int>{};
    final before = held.length;
    held.addAll(ids);
    return held.length != before;
  }

  void resetAll() => _incoming.clear();
}
