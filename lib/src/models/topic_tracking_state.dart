import 'json.dart';
import 'sidebar.dart';
import 'topic.dart';

final class TopicTrackingState {
  TopicTrackingState([Iterable<TrackedTopicState> topics = const []]) {
    topics.forEach(_put);
  }

  factory TopicTrackingState.fromJson(Object? value) => TopicTrackingState([
    for (final item in jsonObjects(value)) ?TrackedTopicState.fromJson(item),
  ]);

  /// A settled row, neither new nor unread, counts toward nothing, yet a long
  /// session would keep one for every topic read or dismissed. Only the most
  /// recently changed are kept:
  /// they let a topic read on another device leave an unread list before that
  /// list reloads (`UnreadTopicFeed.isRead`), which concerns the pages a list
  /// has loaded, and 1024 is over thirty of core's 30-topic pages. Dropping an
  /// older row leaves its topic as a first snapshot leaves any topic settled
  /// when it was taken: absent, since core's report carries only new and
  /// unread topics. Countable rows are never dropped; they are the badges.
  static const _maxSettledTopics = 1024;

  final Map<int, TrackedTopicState> _topics = {};

  /// Ids of the settled rows in [_topics], least recently changed first.
  final Set<int> _settled = {};

  /// Sidebar badges are asked for per visible row on every sidebar rebuild.
  /// Indexes are built on first use and patched when a topic changes. Keys
  /// inside each bucket let replacement and removal avoid searching its rows.
  Map<int, Map<int, TrackedTopicState>>? _topicsByCategory;
  Map<int, Map<int, TrackedTopicState>>? _topicsByTag;

  /// The parent-to-children map depends only on the category list, which a
  /// site keeps by identity between configuration loads.
  Iterable<TopicCategory>? _childrenSource;
  Map<int, List<int>>? _childrenByParent;

  Iterable<TrackedTopicState> get topics => _topics.values;

  TrackedTopicState? topic(int topicId) => _topics[topicId];

  void _put(TrackedTopicState topic) {
    final topicId = topic.topicId;
    _updateDerived(_topics[topicId], topic);
    _topics[topicId] = topic;
    _settled.remove(topicId);
    if (topic.isNew || topic.isUnread) return;
    _settled.add(topicId);
    if (_settled.length > _maxSettledTopics) {
      final oldest = _settled.first;
      _remove(oldest);
    }
  }

  bool markRead(int topicId, int postNumber) {
    final held = _topics[topicId];
    if (held == null || postNumber <= (held.lastReadPostNumber ?? 0)) {
      return false;
    }
    _put(held.copyWith(lastReadPostNumber: postNumber, isSeen: true));
    return true;
  }

  /// Applies the acknowledged reset of the final post's read timing.
  void markLastPostUnread(int topicId, int lastReadPostNumber) {
    final held = _topics[topicId];
    if (held == null) return;
    _put(held.copyWith(lastReadPostNumber: lastReadPostNumber, isSeen: true));
  }

  /// Core's report stops at `TopicTrackingState::MAX_TOPICS` rows, so one
  /// that long may have left new and unread topics out.
  static const maxReportTopics = 5000;

  /// Carries into this report what [previous] knew of the topics it omits.
  /// Core reports only new and unread topics, so a settled row is kept as it
  /// was: dropping it would bring a topic read elsewhere back into an unread
  /// list loaded before that (see [_maxSettledTopics]). A [complete] report
  /// names every new and unread topic, so an omitted one is neither: like
  /// core's `_correctMissingState` for a complete list, an unread row is read
  /// through its highest post and a new one marked seen. A reply published
  /// later still moves past either.
  ///
  /// Call it once the messages buffered while the report loaded have been
  /// replayed onto it: any topic they touched is in the report by then, with
  /// state newer than what [previous] held.
  void keepOmitted(TopicTrackingState previous, {required bool complete}) {
    final kept = [
      for (final topicId in previous._settled)
        if (!_topics.containsKey(topicId)) previous._topics[topicId]!,
      if (complete)
        for (final topic in previous._topics.values)
          if (!_topics.containsKey(topic.topicId))
            if (topic.isUnread)
              topic.copyWith(
                lastReadPostNumber: topic.highestPostNumber,
                isSeen: true,
              )
            else if (topic.isNew)
              topic.copyWith(isSeen: true),
    ];
    if (kept.isEmpty) return;
    // The report and what was replayed onto it are newer than anything kept,
    // so its own settled rows stay the most recently changed.
    final own = [for (final topicId in _settled) _topics[topicId]!];
    _invalidateCounts();
    _settled.clear();
    kept.forEach(_put);
    own.forEach(_put);
  }

  /// Count queries stay lazy; initialized counts follow per-topic deltas.
  ({int newTopics, int newReplies})? _newActivityCounts;

  static const _maxScopedCounts = 64;
  static const _maxScopeTags = 8;
  final Map<_TopicTrackingScope, _ScopedActivityCounts> _scopedCounts = {};

  ({int newTopics, int newReplies}) get newActivityCounts =>
      _newActivityCounts ??= _countNewActivity(topics);

  ({int newTopics, int newReplies}) newActivityCountsFor({
    int? categoryId,
    Iterable<TopicCategory> categories = const [],
    Set<int> tagIds = const {},
  }) {
    if (categoryId == null && tagIds.isEmpty) return newActivityCounts;
    if (categoryId != null) _childrenFor(categories);
    final scope = tagIds.length <= _maxScopeTags
        ? _TopicTrackingScope(categoryId, tagIds)
        : null;
    if (scope != null) {
      final held = _scopedCounts[scope];
      if (held != null) return held.counts;
    }
    final descendants = categoryId != null
        ? _descendantCategoryIds(categoryId, _childrenFor(categories))
        : null;
    final candidates = categoryId != null
        ? _categoryTopics(categoryId, descendants!)
        : _tagTopics(tagIds.first);
    final counts = _countNewActivity(
      tagIds.isEmpty
          ? candidates
          : candidates.where((topic) => topic.tagIds.containsAll(tagIds)),
    );
    if (scope != null) {
      if (_scopedCounts.length == _maxScopedCounts) {
        _scopedCounts.remove(_scopedCounts.keys.first);
      }
      _scopedCounts[scope] = _ScopedActivityCounts(counts, descendants);
    }
    return counts;
  }

  ({int newTopics, int newReplies}) _countNewActivity(
    Iterable<TrackedTopicState> candidates,
  ) {
    var newTopics = 0;
    var newReplies = 0;
    for (final topic in candidates) {
      final contribution = _activityFor(topic);
      newTopics += contribution.newTopics;
      newReplies += contribution.newReplies;
    }
    return (newTopics: newTopics, newReplies: newReplies);
  }

  SidebarBadge categoryBadge({
    required int categoryId,
    required Iterable<TopicCategory> categories,
    required bool unifiedNew,
    required bool showCount,
  }) => _badge(
    newActivityCountsFor(categoryId: categoryId, categories: categories),
    unifiedNew: unifiedNew,
    showCount: showCount,
  );

  Iterable<TrackedTopicState> _categoryTopics(
    int categoryId,
    Set<int> descendants,
  ) sync* {
    final byCategory = _topicsByCategory ??= _indexBy(
      (topic) => [?topic.categoryId],
    );
    for (final id in descendants) {
      for (final topic
          in byCategory[id]?.values ?? const <TrackedTopicState>[]) {
        // Core excludes descendant category definition topics from the parent.
        if (!topic.isCategoryTopic || topic.categoryId == categoryId) {
          yield topic;
        }
      }
    }
  }

  SidebarBadge tagBadge({
    required int tagId,
    required bool unifiedNew,
    required bool showCount,
  }) => _badge(
    newActivityCountsFor(tagIds: {tagId}),
    unifiedNew: unifiedNew,
    showCount: showCount,
  );

  Iterable<TrackedTopicState> _tagTopics(int tagId) =>
      (_topicsByTag ??= _indexBy((topic) => topic.tagIds))[tagId]?.values ??
      const <TrackedTopicState>[];

  Map<int, Map<int, TrackedTopicState>> _indexBy(
    Iterable<int> Function(TrackedTopicState topic) keysOf,
  ) {
    final index = <int, Map<int, TrackedTopicState>>{};
    for (final topic in _topics.values) {
      for (final key in keysOf(topic)) {
        (index[key] ??= {})[topic.topicId] = topic;
      }
    }
    return index;
  }

  TrackedTopicState? _remove(int topicId) {
    final previous = _topics.remove(topicId);
    _settled.remove(topicId);
    if (previous != null) _updateDerived(previous, null);
    return previous;
  }

  void _updateDerived(TrackedTopicState? previous, TrackedTopicState? next) {
    if (_topicsByCategory == null &&
        _topicsByTag == null &&
        _newActivityCounts == null &&
        _scopedCounts.isEmpty) {
      return;
    }
    _updateIndex(
      _topicsByCategory,
      previous,
      next,
      (topic) => [?topic.categoryId],
    );
    _updateIndex(_topicsByTag, previous, next, (topic) => topic.tagIds);
    final before = _activityFor(previous);
    final after = _activityFor(next);
    if (_newActivityCounts case final counts?) {
      _newActivityCounts = _adjustCounts(counts, before, after);
    }
    for (final entry in _scopedCounts.entries) {
      final scope = entry.key;
      final held = entry.value;
      held.counts = _adjustCounts(
        held.counts,
        previous != null && scope.includes(previous, held.categoryIds)
            ? before
            : (newTopics: 0, newReplies: 0),
        next != null && scope.includes(next, held.categoryIds)
            ? after
            : (newTopics: 0, newReplies: 0),
      );
    }
  }

  void _updateIndex(
    Map<int, Map<int, TrackedTopicState>>? index,
    TrackedTopicState? previous,
    TrackedTopicState? next,
    Iterable<int> Function(TrackedTopicState topic) keysOf,
  ) {
    if (index == null) return;
    if (previous != null) {
      for (final key in keysOf(previous)) {
        final bucket = index[key];
        bucket?.remove(previous.topicId);
        if (bucket != null && bucket.isEmpty) index.remove(key);
      }
    }
    if (next != null) {
      for (final key in keysOf(next)) {
        (index[key] ??= {})[next.topicId] = next;
      }
    }
  }

  Map<int, List<int>> _childrenFor(Iterable<TopicCategory> categories) {
    if (!identical(categories, _childrenSource)) {
      _scopedCounts.clear();
      _childrenSource = categories;
      _childrenByParent = _childrenByParentOf(categories);
    }
    return _childrenByParent!;
  }

  SidebarBadge _badge(
    ({int newTopics, int newReplies}) counts, {
    required bool unifiedNew,
    required bool showCount,
  }) {
    final (newTopics: fresh, newReplies: unread) = counts;
    // Core's legacy New mode prioritizes unread and only shows new when no
    // unread topic exists. Unified New combines both kinds in one badge.
    final count = unifiedNew ? unread + fresh : (unread > 0 ? unread : fresh);
    if (count <= 0) return SidebarBadge.none;
    return showCount ? SidebarBadge.count(count) : const SidebarBadge.dot();
  }

  void _invalidateCounts() {
    _topicsByCategory = null;
    _topicsByTag = null;
    _newActivityCounts = null;
    _scopedCounts.clear();
  }

  bool applyMessage(Object? value) {
    if (value is! Map) return false;
    final topicId = jsonIntOrNull(value['topic_id']);
    final type = jsonText(value['message_type']);

    if (type == 'dismiss_new' || type == 'dismiss_new_posts') {
      final ids = <int>[
        for (final id in jsonArray(jsonObject(value['payload'])['topic_ids']))
          ?jsonIntOrNull(id),
      ];
      var changed = false;
      for (final id in ids) {
        final held = _topics[id];
        if (held == null) continue;
        final next = type == 'dismiss_new'
            ? held.copyWith(isSeen: true)
            : held.copyWith(lastReadPostNumber: held.highestPostNumber);
        if (next != held) {
          if (ids.length > 1 && !changed) _invalidateCounts();
          _put(next);
          changed = true;
        }
      }
      return changed;
    }

    if (topicId == null || topicId <= 0 || type == null) return false;
    final held = _topics[topicId];
    switch (type) {
      case 'notification_level_change':
        final level = jsonObject(value['payload'])['notification_level'];
        if (held == null || level is! int || level < 0 || level > 3) {
          return false;
        }
        if (held.notificationLevel == level) return false;
        _put(held.copyWith(notificationLevel: level));
        return true;
      case 'delete':
        if (held == null || held.deleted) return false;
        _put(held.copyWith(deleted: true));
        return true;
      case 'recover':
        if (held == null || !held.deleted) return false;
        _put(held.copyWith(deleted: false));
        return true;
      case 'destroy':
        return _remove(topicId) != null;
      case 'new_topic':
      case 'unread':
      case 'read':
        final payload = jsonObject(value['payload']);
        if (held != null && _predates(payload, held)) return false;
        final merged = TrackedTopicState.fromMessage(
          topicId: topicId,
          payload: payload,
          previous: held,
          unread: type == 'unread',
        );
        if (merged == held) return false;
        _put(merged);
        return true;
      default:
        // `latest`, `muted`, and `unmuted` affect other client state but do
        // not alter core's countable per-topic snapshot.
        return false;
    }
  }

  /// Whether [payload] is behind [held] on the reader's last read post or the
  /// topic's highest post, and ahead on neither. Core moves both only
  /// forward — it publishes `read` only when the reader got further — save
  /// that deleting the last post lowers the highest one. Such a message was
  /// therefore published before the row was known: a snapshot read after it,
  /// or a message on another channel that the same poll delivered first,
  /// since core answers a backlog channel by channel rather than in the
  /// order it published. Applying it would take the topic back.
  static bool _predates(Map<String, dynamic> payload, TrackedTopicState held) {
    var behind = false;
    var ahead = false;
    void compare(int reported, int current) {
      if (reported < current) behind = true;
      if (reported > current) ahead = true;
    }

    if (jsonIntOrNull(payload['highest_post_number']) case final highest?) {
      compare(highest, held.highestPostNumber);
    }
    if (payload.containsKey('last_read_post_number')) {
      compare(
        jsonIntOrNull(payload['last_read_post_number']) ?? 0,
        held.lastReadPostNumber ?? 0,
      );
    }
    return behind && !ahead;
  }
}

({int newTopics, int newReplies}) _activityFor(TrackedTopicState? topic) {
  if (topic == null) return (newTopics: 0, newReplies: 0);
  if (topic.isUnread) return (newTopics: 0, newReplies: 1);
  return (newTopics: topic.isNew ? 1 : 0, newReplies: 0);
}

({int newTopics, int newReplies}) _adjustCounts(
  ({int newTopics, int newReplies}) counts,
  ({int newTopics, int newReplies}) before,
  ({int newTopics, int newReplies}) after,
) => (
  newTopics: counts.newTopics - before.newTopics + after.newTopics,
  newReplies: counts.newReplies - before.newReplies + after.newReplies,
);

final class _ScopedActivityCounts {
  _ScopedActivityCounts(this.counts, this.categoryIds);

  ({int newTopics, int newReplies}) counts;
  final Set<int>? categoryIds;
}

final class _TopicTrackingScope {
  _TopicTrackingScope(this.categoryId, Set<int> tagIds)
    : tagIds = Set.unmodifiable(tagIds);

  final int? categoryId;
  final Set<int> tagIds;

  bool includes(TrackedTopicState topic, Set<int>? categoryIds) =>
      (categoryId == null ||
          (categoryIds!.contains(topic.categoryId) &&
              (!topic.isCategoryTopic || topic.categoryId == categoryId))) &&
      topic.tagIds.containsAll(tagIds);

  @override
  bool operator ==(Object other) =>
      other is _TopicTrackingScope &&
      other.categoryId == categoryId &&
      _setEquals(other.tagIds, tagIds);

  @override
  int get hashCode => Object.hash(categoryId, Object.hashAllUnordered(tagIds));
}

Map<int, List<int>> _childrenByParentOf(Iterable<TopicCategory> categories) {
  final children = <int, List<int>>{};
  for (final category in categories) {
    final parentId = category.parentCategoryId;
    if (parentId != null) (children[parentId] ??= []).add(category.id);
  }
  return children;
}

Set<int> _descendantCategoryIds(int categoryId, Map<int, List<int>> children) {
  final result = <int>{categoryId};
  final pending = <int>[categoryId];
  while (pending.isNotEmpty) {
    final parentId = pending.removeLast();
    for (final childId in children[parentId] ?? const <int>[]) {
      if (result.add(childId)) pending.add(childId);
    }
  }
  return result;
}

final class TrackedTopicState {
  const TrackedTopicState({
    required this.topicId,
    this.highestPostNumber = 0,
    this.lastReadPostNumber,
    this.categoryId,
    this.isCategoryTopic = false,
    this.notificationLevel,
    this.createdInNewPeriod = false,
    this.isSeen = false,
    this.tagIds = const {},
    this.deleted = false,
  });

  static TrackedTopicState? fromJson(Map<String, dynamic> json) {
    final topicId = jsonIntOrNull(json['topic_id']);
    if (topicId == null || topicId <= 0) return null;
    return TrackedTopicState(
      topicId: topicId,
      highestPostNumber: _nonNegative(jsonInt(json['highest_post_number'])),
      lastReadPostNumber: jsonIntOrNull(json['last_read_post_number']),
      categoryId: jsonIntOrNull(json['category_id']),
      isCategoryTopic: json['is_category_topic'] == true,
      notificationLevel: jsonIntOrNull(json['notification_level']),
      createdInNewPeriod: json['created_in_new_period'] == true,
      isSeen: json['is_seen'] == true,
      tagIds: _tagIds(json['tags']),
      deleted: json['deleted'] == true,
    );
  }

  factory TrackedTopicState.fromMessage({
    required int topicId,
    required Map<String, dynamic> payload,
    required TrackedTopicState? previous,
    required bool unread,
  }) {
    final highest = jsonIntOrNull(payload['highest_post_number']);
    final lastReadPresent = payload.containsKey('last_read_post_number');
    final notificationPresent = payload.containsKey('notification_level');
    final tagsPresent = payload.containsKey('tags');
    final resolvedHighest = _nonNegative(
      highest ?? previous?.highestPostNumber ?? 0,
    );
    return TrackedTopicState(
      topicId: topicId,
      highestPostNumber: resolvedHighest,
      lastReadPostNumber: lastReadPresent
          ? jsonIntOrNull(payload['last_read_post_number'])
          : unread
          ? (previous?.lastReadPostNumber ??
                (resolvedHighest > 0 ? resolvedHighest - 1 : 0))
          : previous?.lastReadPostNumber,
      categoryId: jsonIntOrNull(payload['category_id']) ?? previous?.categoryId,
      isCategoryTopic: payload.containsKey('is_category_topic')
          ? payload['is_category_topic'] == true
          : (previous?.isCategoryTopic ?? false),
      notificationLevel: notificationPresent
          ? jsonIntOrNull(payload['notification_level'])
          : unread
          ? (previous?.notificationLevel ?? 2)
          : previous?.notificationLevel,
      createdInNewPeriod: payload.containsKey('created_in_new_period')
          ? payload['created_in_new_period'] == true
          : (previous?.createdInNewPeriod ?? false),
      isSeen: payload.containsKey('is_seen')
          ? payload['is_seen'] == true
          : (previous?.isSeen ?? false),
      tagIds: tagsPresent
          ? _tagIds(payload['tags'])
          : (previous?.tagIds ?? const {}),
      deleted: previous?.deleted ?? false,
    );
  }

  final int topicId;
  final int highestPostNumber;
  final int? lastReadPostNumber;
  final int? categoryId;
  final bool isCategoryTopic;
  final int? notificationLevel;
  final bool createdInNewPeriod;
  final bool isSeen;
  final Set<int> tagIds;
  final bool deleted;

  bool get isUnread =>
      !deleted &&
      lastReadPostNumber != null &&
      lastReadPostNumber! < highestPostNumber &&
      (notificationLevel ?? 0) >= 2;

  bool get isNew =>
      !deleted &&
      lastReadPostNumber == null &&
      (notificationLevel == null || notificationLevel! >= 2) &&
      createdInNewPeriod &&
      !isSeen;

  TrackedTopicState copyWith({
    int? lastReadPostNumber,
    int? notificationLevel,
    bool? isSeen,
    bool? deleted,
  }) => TrackedTopicState(
    topicId: topicId,
    highestPostNumber: highestPostNumber,
    lastReadPostNumber: lastReadPostNumber ?? this.lastReadPostNumber,
    categoryId: categoryId,
    isCategoryTopic: isCategoryTopic,
    notificationLevel: notificationLevel ?? this.notificationLevel,
    createdInNewPeriod: createdInNewPeriod,
    isSeen: isSeen ?? this.isSeen,
    tagIds: tagIds,
    deleted: deleted ?? this.deleted,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackedTopicState &&
      other.topicId == topicId &&
      other.highestPostNumber == highestPostNumber &&
      other.lastReadPostNumber == lastReadPostNumber &&
      other.categoryId == categoryId &&
      other.isCategoryTopic == isCategoryTopic &&
      other.notificationLevel == notificationLevel &&
      other.createdInNewPeriod == createdInNewPeriod &&
      other.isSeen == isSeen &&
      _setEquals(other.tagIds, tagIds) &&
      other.deleted == deleted;

  @override
  int get hashCode => Object.hash(
    topicId,
    highestPostNumber,
    lastReadPostNumber,
    categoryId,
    isCategoryTopic,
    notificationLevel,
    createdInNewPeriod,
    isSeen,
    Object.hashAllUnordered(tagIds),
    deleted,
  );
}

int _nonNegative(int value) => value < 0 ? 0 : value;

/// Most topics carry no tag, and those rows share one empty set.
Set<int> _tagIds(Object? tags) {
  final ids = [
    for (final tag in jsonObjects(tags))
      if (jsonIntOrNull(tag['id']) case final id? when id > 0) id,
  ];
  return ids.isEmpty ? const {} : Set.unmodifiable(ids);
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
