import 'package:discourse_native/l10n/strings.dart';
import 'live_refresh_id.dart';

/// Which arrivals one topic list announces: what core's `notifyIncoming`
/// makes of the filter, category and tag that `trackIncoming` recorded for
/// the list on screen.
final class IncomingTopicsFilter {
  /// Latest counts a topic created and one bumped by a reply.
  const IncomingTopicsFilter.latest({this.categoryId, this.tagIds = const {}})
    : countsBumps = true,
      _countsCreated = true,
      _replies = _ReplyRule.never;

  /// New – topics, and New for a reader without unified New.
  const IncomingTopicsFilter.created({this.categoryId, this.tagIds = const {}})
    : countsBumps = false,
      _countsCreated = true,
      _replies = _ReplyRule.never;

  /// New, which unified New also fills with topics that have new replies.
  const IncomingTopicsFilter.newActivity({
    this.categoryId,
    this.tagIds = const {},
  }) : countsBumps = false,
       _countsCreated = true,
       _replies = _ReplyRule.whenUnifiedNew;

  /// Unseen counts a topic created and a reply to one the reader had read.
  const IncomingTopicsFilter.unseen({this.categoryId, this.tagIds = const {}})
    : countsBumps = false,
      _countsCreated = true,
      _replies = _ReplyRule.always;

  /// Unread counts only a reply to a topic the reader had read.
  const IncomingTopicsFilter.unread({this.categoryId, this.tagIds = const {}})
    : countsBumps = false,
      _countsCreated = false,
      _replies = _ReplyRule.always;

  final bool countsBumps;
  final bool _countsCreated;
  final _ReplyRule _replies;

  /// The list's category. A topic counts in it or in a category directly
  /// beneath it, never deeper, as core compares the payload's category and
  /// that category's parent.
  final int? categoryId;

  /// The tags the list is filtered by, all of which a topic must carry. The
  /// server lists a topic's tags by id, and only while tagging is enabled.
  final Set<int> tagIds;

  bool _admits(
    _Arrival arrival,
    int? Function(int categoryId)? parentCategoryOf, {
    required bool unifiedNew,
  }) {
    final counted = switch (arrival.kind) {
      _ArrivalKind.created => _countsCreated,
      _ArrivalKind.bumped => countsBumps,
      _ArrivalKind.replied => switch (_replies) {
        _ReplyRule.never => false,
        _ReplyRule.whenUnifiedNew => unifiedNew,
        _ReplyRule.always => true,
      },
    };
    if (!counted) return false;
    if (categoryId case final scope?) {
      final category = arrival.categoryId;
      if (category == null) return false;
      if (category != scope && parentCategoryOf?.call(category) != scope) {
        return false;
      }
    }
    return arrival.tagIds.containsAll(tagIds);
  }

  @override
  bool operator ==(Object other) =>
      other is IncomingTopicsFilter &&
      other.countsBumps == countsBumps &&
      other._countsCreated == _countsCreated &&
      other._replies == _replies &&
      other.categoryId == categoryId &&
      other.tagIds.length == tagIds.length &&
      other.tagIds.containsAll(tagIds);

  @override
  int get hashCode => Object.hash(
    countsBumps,
    _countsCreated,
    _replies,
    categoryId,
    Object.hashAllUnordered(tagIds),
  );

  @override
  String toString() => appL10n.incomingTopicsFilterCategoryIdTagIds(
    (countsBumps).toString(),
    (categoryId).toString(),
    (tagIds).toString(),
  );
}

enum _ReplyRule { never, whenUnifiedNew, always }

enum _ArrivalKind { created, bumped, replied }

final class _Arrival {
  _Arrival(this.kind, Object? payload)
    : categoryId = payload is Map
          ? liveRefreshId(payload['category_id'])
          : null,
      tagIds = {
        if (payload is Map && payload['tags'] is List)
          for (final tag in payload['tags'] as List)
            if (tag is Map) ?liveRefreshId(tag['id']),
      };

  final _ArrivalKind kind;
  final int? categoryId;
  final Set<int> tagIds;
}

class IncomingTopics {
  /// The site's own unscoped lists, keyed by the destinations that show them.
  /// They count from the start; a scoped list counts once it is [track]ed.
  static const Map<String, IncomingTopicsFilter> _siteLists = {
    'latest': IncomingTopicsFilter.latest(),
    'new': IncomingTopicsFilter.newActivity(),
    'new-topics': IncomingTopicsFilter.created(),
    'unseen': IncomingTopicsFilter.unseen(),
    'unread': IncomingTopicsFilter.unread(),
  };

  /// How many scoped lists count at once: the most recently loaded ones.
  static const int trackedListCapacity = 64;

  /// How many arrivals one list holds. Past it the oldest is forgotten, and
  /// the list's next fetch shows it anyway.
  static const int heldTopicCapacity = 500;

  final Map<String, IncomingTopicsFilter> _trackedLists = {};
  int? Function(int categoryId)? _parentCategoryOf;
  bool _unifiedNew = false;
  final Map<String, Set<int>> _incoming = {};

  /// Makes [lists] the scoped lists that count arrivals, in the order they
  /// were loaded, replacing those tracked before. A list no longer among
  /// them stops counting and forgets what it held. [parentCategoryOf] is
  /// asked when a message arrives, as core looks the category up then.
  void track(
    Map<String, IncomingTopicsFilter> lists, {
    int? Function(int categoryId)? parentCategoryOf,
    bool unifiedNew = false,
  }) {
    final scoped = [
      for (final entry in lists.entries)
        if (!_siteLists.containsKey(entry.key)) entry,
    ];
    _trackedLists
      ..clear()
      ..addEntries(
        scoped.skip(
          scoped.length > trackedListCapacity
              ? scoped.length - trackedListCapacity
              : 0,
        ),
      );
    _parentCategoryOf = parentCategoryOf;
    _unifiedNew = unifiedNew;
    _incoming.removeWhere(
      (list, _) =>
          !_siteLists.containsKey(list) && !_trackedLists.containsKey(list),
    );
  }

  List<int> topicIds(String list, {int? limit}) {
    final held = _incoming[list] ?? const <int>{};
    if (limit == null || limit >= held.length) return List.unmodifiable(held);
    if (limit <= 0) return const [];
    return List.unmodifiable(held.take(limit));
  }

  int count(String list) => _incoming[list]?.length ?? 0;

  bool notify(Object? message) {
    if (message is! Map) return false;

    final topicId = liveRefreshId(message['topic_id']);
    if (topicId == null) return false;

    // `muted` and `unmuted` also arrive on /latest, and carry no payload; they
    // say a topic left or joined the reader's list, not that one arrived.
    final kind = switch (message['message_type']) {
      'new_topic' => _ArrivalKind.created,
      'latest' => _ArrivalKind.bumped,
      'unread' => _ArrivalKind.replied,
      _ => null,
    };
    if (kind == null) return false;
    final arrival = _Arrival(kind, message['payload']);

    var changed = false;
    for (final MapEntry(key: list, value: filter) in {
      ..._siteLists,
      ..._trackedLists,
    }.entries) {
      if (filter._admits(arrival, _parentCategoryOf, unifiedNew: _unifiedNew)) {
        changed |= _hold(list, [topicId]);
      }
    }
    return changed;
  }

  /// A `/delete` message: the topic will not come back from any list, so it
  /// stops counting as an arrival on every one of them.
  bool notifyDeleted(Object? message) {
    if (message is! Map) return false;
    final topicId = liveRefreshId(message['topic_id']);
    if (topicId == null) return false;

    var changed = false;
    for (final list in [..._incoming.keys]) {
      changed |= clear(list, [topicId]);
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
    return _hold(list, ids);
  }

  void resetAll() {
    _incoming.clear();
    _trackedLists.clear();
    _parentCategoryOf = null;
    _unifiedNew = false;
  }

  bool _hold(String list, Iterable<int> ids) {
    final held = _incoming[list] ??= <int>{};
    var changed = false;
    for (final id in ids) {
      changed |= held.add(id);
    }
    while (held.length > heldTopicCapacity) {
      held.remove(held.first);
    }
    return changed;
  }
}
