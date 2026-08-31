import '../models/topic.dart';

const String topicCategoryPathSeparator = ' › ';

String topicCategoryPathLabel(
  TopicCategory category, {
  TopicCategory? parent,
}) => parent == null
    ? category.name
    : '${parent.name}$topicCategoryPathSeparator${category.name}';
