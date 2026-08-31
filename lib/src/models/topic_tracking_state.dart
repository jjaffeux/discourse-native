import 'json.dart';
import 'sidebar.dart';
import 'topic.dart';

final class TopicTrackingState {
  TopicTrackingState([Iterable<TrackedTopicState> topics = const []])
    : _topics = {for (final topic in topics) topic.topicId: topic};

  factory TopicTrackingState.fromJson(Object? value) => TopicTrackingState([
    for (final item in jsonObjects(value)) ?TrackedTopicState.fromJson(item),
  ]);

  final Map<int, TrackedTopicState> _topics;

  Iterable<TrackedTopicState> get topics => _topics.values;

  SidebarBadge categoryBadge({
    required int categoryId,
    required Iterable<TopicCategory> categories,
    required bool unifiedNew,
    required bool showCount,
  }) {
    final descendants = _descendantCategoryIds(categoryId, categories);
    return _badge(
      topics.where((topic) {
        if (!descendants.contains(topic.categoryId)) return false;
        // A child category's definition topic belongs to that child only. Core
        // excludes it when calculating the recursive parent-category count.
        return !topic.isCategoryTopic || topic.categoryId == categoryId;
      }),
      unifiedNew: unifiedNew,
      showCount: showCount,
    );
  }

  SidebarBadge tagBadge({
    required int tagId,
    required bool unifiedNew,
    required bool showCount,
  }) => _badge(
    topics.where((topic) => topic.tagIds.contains(tagId)),
    unifiedNew: unifiedNew,
    showCount: showCount,
  );

  SidebarBadge _badge(
    Iterable<TrackedTopicState> candidates, {
    required bool unifiedNew,
    required bool showCount,
  }) {
    var unread = 0;
    var fresh = 0;
    for (final topic in candidates) {
      if (topic.isUnread) {
        unread++;
      } else if (topic.isNew) {
        fresh++;
      }
    }

    // Core's legacy New mode prioritizes unread and only shows new when no
    // unread topic exists. Unified New combines both kinds in one badge.
    final count = unifiedNew ? unread + fresh : (unread > 0 ? unread : fresh);
    if (count <= 0) return SidebarBadge.none;
    return showCount ? SidebarBadge.count(count) : const SidebarBadge.dot();
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
          _topics[id] = next;
          changed = true;
        }
      }
      return changed;
    }

    if (topicId == null || topicId <= 0 || type == null) return false;
    final held = _topics[topicId];
    switch (type) {
      case 'delete':
        if (held == null || held.deleted) return false;
        _topics[topicId] = held.copyWith(deleted: true);
        return true;
      case 'recover':
        if (held == null || !held.deleted) return false;
        _topics[topicId] = held.copyWith(deleted: false);
        return true;
      case 'destroy':
        return _topics.remove(topicId) != null;
      case 'new_topic':
      case 'unread':
      case 'read':
        final payload = jsonObject(value['payload']);
        final merged = TrackedTopicState.fromMessage(
          topicId: topicId,
          payload: payload,
          previous: held,
          unread: type == 'unread',
        );
        if (merged == held) return false;
        _topics[topicId] = merged;
        return true;
      default:
        // `latest`, `muted`, and `unmuted` affect other client state but do
        // not alter core's countable per-topic snapshot.
        return false;
    }
  }
}

Set<int> _descendantCategoryIds(
  int categoryId,
  Iterable<TopicCategory> categories,
) {
  final children = <int, List<int>>{};
  for (final category in categories) {
    final parentId = category.parentCategoryId;
    if (parentId != null) (children[parentId] ??= []).add(category.id);
  }

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
      tagIds: Set.unmodifiable([
        for (final tag in jsonObjects(json['tags']))
          if (jsonIntOrNull(tag['id']) case final id? when id > 0) id,
      ]),
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
          ? Set.unmodifiable([
              for (final tag in jsonObjects(payload['tags']))
                if (jsonIntOrNull(tag['id']) case final id? when id > 0) id,
            ])
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
    bool? isSeen,
    bool? deleted,
  }) => TrackedTopicState(
    topicId: topicId,
    highestPostNumber: highestPostNumber,
    lastReadPostNumber: lastReadPostNumber ?? this.lastReadPostNumber,
    categoryId: categoryId,
    isCategoryTopic: isCategoryTopic,
    notificationLevel: notificationLevel,
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

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
