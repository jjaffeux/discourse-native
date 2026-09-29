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

List<CategoryDirectoryEntry> categoryDirectoryEntries({
  required List<int> rootCategoryIds,
  required Iterable<TopicCategory> categories,
  required Map<int, int> unreadTopicCounts,
  Set<int> mutedCategoryIds = const {},
}) {
  final byId = {for (final category in categories) category.id: category};
  final children = <int, List<TopicCategory>>{};
  for (final category in byId.values) {
    if (category.parentCategoryId case final parent?) {
      (children[parent] ??= []).add(category);
    }
  }
  bool isMuted(TopicCategory category) =>
      category.isMuted || mutedCategoryIds.contains(category.id);

  final result = <CategoryDirectoryEntry>[];
  for (final rootId in rootCategoryIds) {
    final root = byId[rootId];
    if (root == null) continue;
    final descendants = <TopicCategory>[];
    final visited = <int>{rootId};
    final pending = [...?children[rootId]?.reversed];
    while (pending.isNotEmpty) {
      final child = pending.removeLast();
      if (!visited.add(child.id)) continue;
      descendants.add(child);
      pending.addAll(children[child.id]?.reversed ?? const []);
    }
    final family = [root, ...descendants];
    final topics = [
      for (final category in family)
        if (!isMuted(category)) ...category.featuredTopics,
    ];
    // Featured order can put an old pinned topic first. Prefer the
    // newest reported activity, retaining server order without dates.
    CategoryFeaturedTopic? latest;
    for (final topic in topics) {
      if (latest == null ||
          (topic.activityAt != null &&
              (latest.activityAt == null ||
                  topic.activityAt!.isAfter(latest.activityAt!)))) {
        latest = topic;
      }
    }
    result.add(
      CategoryDirectoryEntry(
        category: root,
        subcategories: descendants,
        muted: isMuted(root),
        unreadTopicCount: isMuted(root)
            ? 0
            : family.fold(
                0,
                (count, category) =>
                    count +
                    (isMuted(category)
                        ? 0
                        : unreadTopicCounts[category.id] ?? 0),
              ),
        topicCount: family.fold(
          0,
          (count, category) => count + category.topicCount,
        ),
        latestTopic: isMuted(root) ? null : latest,
      ),
    );
  }
  return result;
}
