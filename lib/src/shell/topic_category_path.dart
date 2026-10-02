import '../models/topic.dart';

const String topicCategoryPathSeparator = ' › ';

/// Resolves every available ancestor, from the root to [category].
List<TopicCategory> topicCategoryPath(
  TopicCategory category, {
  required TopicCategory? Function(int id) categoryFor,
}) {
  final path = <TopicCategory>[];
  final visited = <int>{};
  TopicCategory? current = category;
  while (current != null && visited.add(current.id)) {
    path.add(current);
    final parentId = current.parentCategoryId;
    current = parentId == null ? null : categoryFor(parentId);
  }
  return path.reversed.toList(growable: false);
}

String topicCategoryPathLabel(
  TopicCategory category, {
  TopicCategory? parent,
  TopicCategory? Function(int id)? categoryFor,
}) => topicCategoryPath(
  category,
  categoryFor: categoryFor ?? (id) => parent?.id == id ? parent : null,
).map((item) => item.name).join(topicCategoryPathSeparator);
