/// Topics that have appeared at the top of a list since the reader last looked
/// at it.
///
/// This is the counting half of Discourse's `TopicTrackingState`
/// (`app/models/topic-tracking-state.js`, `notifyIncoming` and friends), and
/// deliberately only that half. Core's class does two jobs: it keeps a per-topic
/// read/unread state map for every badge in the app, and it counts what has
/// arrived since the visible list was fetched. Only the second is needed to draw
/// a banner, and it is the only one that works without a state map — see
/// [notify] for what that costs.
///
/// Pure state, no transport: [notify] takes a message exactly as it comes off
/// the wire. `SiteTracker` is what puts it there.
class IncomingTopics {
  /// Lists a newly created topic belongs at the top of.
  ///
  /// Core also counts it for `all` and `unseen`, which are routes this client
  /// does not have.
  static const Set<String> _newTopicLists = {'latest', 'new'};

  /// Lists a bumped topic belongs at the top of.
  ///
  /// Only `latest`, which is why its banner says "new or updated" where the new
  /// list's says "new" — a bump is an existing topic moving, not a new one.
  static const Set<String> _bumpedLists = {'latest'};

  /// Ids per list, in arrival order. A set because message_bus can repeat a
  /// message across a reconnect, and because a topic bumped twice is still one
  /// row — core dedupes here too (`_addIncoming`).
  final Map<String, Set<int>> _incoming = {};

  /// The ids to ask the site for, oldest first.
  ///
  /// [limit] returns a bounded view without consuming anything. The caller
  /// clears exactly that view only after the matching request succeeds, so a
  /// later page remains announced rather than disappearing behind the site's
  /// own response limit.
  List<int> topicIds(String list, {int? limit}) {
    final held = _incoming[list] ?? const <int>{};
    if (limit == null || limit >= held.length) return List.unmodifiable(held);
    if (limit <= 0) return const [];
    return List.unmodifiable(held.take(limit));
  }

  int count(String list) => _incoming[list]?.length ?? 0;

  /// Records one message from `/new` or `/latest`.
  ///
  /// Returns whether any count changed, so the caller can skip a rebuild for
  /// the messages that do not concern us — most of them.
  ///
  /// Two of core's filters are deliberately not applied, because both need
  /// state this client does not hold: topics in categories or with tags the
  /// user has muted, and topics the user has muted individually. A muted topic
  /// therefore counts here but does not come back when the list is fetched, so
  /// the banner can overstate by a row. That resolves itself — the ids are
  /// cleared whether or not they produced a topic — and the alternative is
  /// carrying the muted lists and the whole per-topic state map for a count.
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

  /// Forgets ids that have been fetched and inserted into [list].
  ///
  /// Every id that was asked for, not only those that came back: an id the site
  /// declined to return — muted, deleted, or past the page it serves — would
  /// otherwise sit in the count forever, with a banner that does nothing.
  bool clear(String list, Iterable<int> ids) {
    final held = _incoming[list];
    if (held == null) return false;

    final before = held.length;
    held.removeAll(ids);
    if (held.isEmpty) _incoming.remove(list);
    return held.length != before;
  }

  /// Forgets everything counted for [list], because it has just been refetched
  /// and whatever was incoming is now in it.
  bool reset(String list) => _incoming.remove(list) != null;

  /// Puts [ids] back after the refetch that consumed them failed.
  ///
  /// The announcement is still owed: the topics never landed in the list, so
  /// the banner has to keep counting them. Order is not restored — it only
  /// ever mattered to the request that asked for the ids, and the list route
  /// answers in its own.
  bool restore(String list, Iterable<int> ids) {
    if (ids.isEmpty) return false;
    final held = _incoming[list] ??= <int>{};
    final before = held.length;
    held.addAll(ids);
    return held.length != before;
  }

  void resetAll() => _incoming.clear();
}
