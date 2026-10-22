import 'topic.dart';

enum CategoryDirectoryScope { all, unread, withTopics }

/// A server-listed root and its accessible descendants, in server order.
class CategoryDirectoryEntry {
  CategoryDirectoryEntry({
    required this.category,
    required this.subcategories,
    required this.muted,
    required this.unreadTopicCount,
    required this.topicCount,
    required this.latestTopic,
  });

  final TopicCategory category;
  final List<TopicCategory> subcategories;
  final bool muted;
  final int unreadTopicCount;
  final int topicCount;
  final CategoryFeaturedTopic? latestTopic;

  bool matches(CategoryDirectoryScope scope) => switch (scope) {
    CategoryDirectoryScope.all => true,
    CategoryDirectoryScope.unread => unreadTopicCount > 0,
    CategoryDirectoryScope.withTopics =>
      topicCount > 0 ||
          category.featuredTopics.isNotEmpty ||
          subcategories.any((category) => category.featuredTopics.isNotEmpty),
  };
}

class CategoryDirectory {
  CategoryDirectory({
    required List<int> rootCategoryIds,
    required Iterable<TopicCategory> categories,
  }) : _rootCategoryIds = rootCategoryIds,
       categoriesById = {
         for (final category in categories) category.id: category,
       } {
    final sourceChildren = _categoryChildren(categoriesById.values);
    final reachable = <int>{};
    for (final rootId in rootCategoryIds) {
      final root = categoriesById[rootId];
      if (root == null || !reachable.add(rootId)) continue;
      _accessible[rootId] = root;
      for (final descendant in _categoryDescendants(
        rootId,
        sourceChildren,
        visited: reachable,
      )) {
        _accessible[descendant.id] = descendant;
      }
    }
    _children = _categoryChildren(_accessible.values);
  }

  final List<int> _rootCategoryIds;
  final Map<int, TopicCategory> categoriesById;
  final _accessible = <int, TopicCategory>{};
  late final Map<int, List<TopicCategory>> _children;

  Iterable<TopicCategory> get accessibleCategories => _accessible.values;

  bool containsCategory(int? categoryId) => _accessible.containsKey(categoryId);

  Iterable<TopicCategory> visibleCategories({
    int? parentCategoryId,
    bool searching = false,
  }) sync* {
    if (searching) {
      yield* _accessible.values;
    } else if (containsCategory(parentCategoryId)) {
      yield* _children[parentCategoryId] ?? const [];
    } else {
      for (final rootId in _rootCategoryIds) {
        if (_accessible[rootId] case final category?) yield category;
      }
    }
  }

  List<CategoryDirectoryEntry> entries({
    int? parentCategoryId,
    bool searching = false,
    CategoryDirectoryScope scope = CategoryDirectoryScope.all,
    bool Function(TopicCategory)? matchesCategory,
    required Map<int, int> unreadTopicCounts,
    Set<int> mutedCategoryIds = const {},
  }) {
    final result = <CategoryDirectoryEntry>[];
    for (final category in visibleCategories(
      parentCategoryId: parentCategoryId,
      searching: searching,
    )) {
      if (scope == CategoryDirectoryScope.all &&
          matchesCategory != null &&
          !matchesCategory(category)) {
        continue;
      }
      final entry = _categoryDirectoryEntry(
        category,
        _children,
        unreadTopicCounts,
        mutedCategoryIds,
      );
      if (!entry.matches(scope)) continue;
      if (scope != CategoryDirectoryScope.all &&
          matchesCategory != null &&
          !matchesCategory(category)) {
        continue;
      }
      result.add(entry);
    }
    return result;
  }
}

List<CategoryDirectoryEntry> categoryDirectoryEntries({
  required List<int> rootCategoryIds,
  required Iterable<TopicCategory> categories,
  required Map<int, int> unreadTopicCounts,
  Set<int> mutedCategoryIds = const {},
}) {
  final byId = {for (final category in categories) category.id: category};
  final children = _categoryChildren(byId.values);
  return [
    for (final rootId in rootCategoryIds)
      if (byId[rootId] case final root?)
        _categoryDirectoryEntry(
          root,
          children,
          unreadTopicCounts,
          mutedCategoryIds,
        ),
  ];
}

Map<int, List<TopicCategory>> _categoryChildren(
  Iterable<TopicCategory> categories,
) {
  final children = <int, List<TopicCategory>>{};
  for (final category in categories) {
    if (category.parentCategoryId case final parent?) {
      (children[parent] ??= []).add(category);
    }
  }
  return children;
}

Iterable<TopicCategory> _categoryDescendants(
  int rootId,
  Map<int, List<TopicCategory>> children, {
  Set<int>? visited,
}) sync* {
  final seen = visited ?? <int>{};
  seen.add(rootId);
  final pending = [...?children[rootId]?.reversed];
  while (pending.isNotEmpty) {
    final child = pending.removeLast();
    if (!seen.add(child.id)) continue;
    yield child;
    pending.addAll(children[child.id]?.reversed ?? const []);
  }
}

CategoryDirectoryEntry _categoryDirectoryEntry(
  TopicCategory root,
  Map<int, List<TopicCategory>> children,
  Map<int, int> unreadTopicCounts,
  Set<int> mutedCategoryIds,
) {
  bool isMuted(TopicCategory category) =>
      category.isMuted || mutedCategoryIds.contains(category.id);

  final descendants = _categoryDescendants(root.id, children).toList();
  final family = [root, ...descendants];
  var unreadTopicCount = 0;
  var topicCount = 0;
  CategoryFeaturedTopic? latest;
  for (final category in family) {
    topicCount += category.topicCount;
    if (isMuted(category)) continue;
    unreadTopicCount += unreadTopicCounts[category.id] ?? 0;
    // Activity can differ from featured order because old topics can be pinned.
    for (final topic in category.featuredTopics) {
      if (latest == null ||
          (topic.activityAt != null &&
              (latest.activityAt == null ||
                  topic.activityAt!.isAfter(latest.activityAt!)))) {
        latest = topic;
      }
    }
  }
  final muted = isMuted(root);
  return CategoryDirectoryEntry(
    category: root,
    subcategories: descendants,
    muted: muted,
    unreadTopicCount: muted ? 0 : unreadTopicCount,
    topicCount: topicCount,
    latestTopic: muted ? null : latest,
  );
}
