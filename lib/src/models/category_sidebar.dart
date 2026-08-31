import 'package:flutter/widgets.dart';

import '../theme/d_icons.dart';
import 'sidebar.dart';
import 'topic.dart';

const int topSidebarCategoriesToShow = 5;

SidebarSection buildCategorySidebarSection({
  required List<TopicCategory> categories,
  required bool connected,
  List<int> preferredCategoryIds = const [],
  List<int> defaultCategoryIds = const [],
  bool fixedCategoryPositions = false,
  bool allowUncategorizedTopics = false,
}) {
  final byId = {for (final category in categories) category.id: category};
  final displayable = allowUncategorizedTopics
      ? categories
      : categories
            .where((category) => !category.isUncategorized)
            .toList(growable: false);
  final selectedIds = connected ? preferredCategoryIds : defaultCategoryIds;
  final selected = selectedIds.where(byId.containsKey).toSet();
  final ordered = _hierarchical(
    displayable,
    fixedCategoryPositions: fixedCategoryPositions,
  );

  final List<TopicCategory> visible;
  if (selectedIds.isNotEmpty) {
    visible = ordered
        .where((category) => selected.contains(category.id))
        .toList(growable: false);
  } else {
    final fallback = _topCategories(
      displayable,
      fixedCategoryPositions: fixedCategoryPositions,
    );
    final fallbackIds = {for (final category in fallback) category.id};
    visible = connected
        ? ordered
              .where((category) => fallbackIds.contains(category.id))
              .toList(growable: false)
        : fallback;
  }

  return SidebarSection(
    id: 'categories',
    title: 'Categories',
    destinations: List.unmodifiable([
      for (final category in visible)
        buildCategoryDestination(category, categoriesById: byId),
      const SidebarDestination(
        id: 'all-categories',
        label: 'All categories',
        icon: DIcons.list,
      ),
    ]),
  );
}

List<TopicCategory> _topCategories(
  List<TopicCategory> categories, {
  required bool fixedCategoryPositions,
}) {
  final roots =
      [
        for (final category in categories)
          if (category.parentCategoryId == null) category,
      ]..sort((left, right) {
        final compared = fixedCategoryPositions
            ? _comparePosition(left, right)
            : right.topicCount.compareTo(left.topicCount);
        return compared != 0 ? compared : _comparePosition(left, right);
      });
  return roots.take(topSidebarCategoriesToShow).toList(growable: false);
}

List<TopicCategory> _hierarchical(
  List<TopicCategory> categories, {
  required bool fixedCategoryPositions,
}) {
  final sorted = [...categories]
    ..sort((left, right) {
      final compared = fixedCategoryPositions
          ? _comparePosition(left, right)
          : _compareNames(left.name, right.name);
      return compared != 0 ? compared : _comparePosition(left, right);
    });
  final ids = {for (final category in sorted) category.id};
  final children = <int?, List<TopicCategory>>{};
  for (final category in sorted) {
    // A missing parent cannot be traversed. Treat the category as a root so a
    // partial response never makes a visible category disappear.
    final parentId = ids.contains(category.parentCategoryId)
        ? category.parentCategoryId
        : null;
    (children[parentId] ??= []).add(category);
  }

  final result = <TopicCategory>[];
  final visited = <int>{};

  void append(List<TopicCategory> roots) {
    // Category nesting is site-controlled. Preserve recursive preorder with
    // an explicit stack so a malformed very deep parent chain cannot exhaust
    // the UI isolate's call stack while the sidebar is being rebuilt.
    final pending = <TopicCategory>[];
    void pushReversed(List<TopicCategory> values) {
      for (var index = values.length - 1; index >= 0; index--) {
        pending.add(values[index]);
      }
    }

    pushReversed(roots);
    while (pending.isNotEmpty) {
      final category = pending.removeLast();
      // A malformed parent cycle must not recurse forever.
      if (!visited.add(category.id)) continue;
      result.add(category);
      pushReversed(children[category.id] ?? const []);
    }
  }

  append(children[null] ?? const []);
  // Include anything trapped in a malformed cycle once, in stable name order.
  append(sorted);
  return result;
}

int _compareNames(String left, String right) {
  final folded = left.toLowerCase().compareTo(right.toLowerCase());
  return folded != 0 ? folded : left.compareTo(right);
}

int _comparePosition(TopicCategory left, TopicCategory right) {
  final leftPosition = left.position;
  final rightPosition = right.position;
  if (leftPosition == null && rightPosition != null) return 1;
  if (leftPosition != null && rightPosition == null) return -1;
  final positioned = (leftPosition ?? 0).compareTo(rightPosition ?? 0);
  return positioned != 0 ? positioned : left.id.compareTo(right.id);
}

SidebarDestination buildCategoryDestination(
  TopicCategory category, {
  required Map<int, TopicCategory> categoriesById,
}) {
  final categoryColor = Color(category.colorValue);
  final parent = categoriesById[category.parentCategoryId];
  final styleType = category.styleType;
  final icon = styleType == 'icon'
      ? DIcons.byName[category.icon] ?? DIcons.folder
      : DIcons.folder;

  return SidebarDestination(
    id: 'category-${category.id}',
    label: category.name,
    icon: icon,
    color: styleType == 'square' ? categoryColor : null,
    parentColor: styleType == 'square' && parent != null
        ? Color(parent.colorValue)
        : null,
    emoji: styleType == 'emoji' ? category.emoji : null,
    iconColor: styleType == 'icon' ? categoryColor : null,
    routeColor: categoryColor,
    prefixBadgeIcon: category.readRestricted ? DIcons.lock : null,
    feedPath: _categoryFeedPath(category, categoriesById),
  );
}

String _categoryFeedPath(TopicCategory category, Map<int, TopicCategory> byId) {
  final chain = <TopicCategory>[];
  final visited = <int>{};
  TopicCategory? current = category;
  while (current != null && visited.add(current.id)) {
    chain.add(current);
    current = byId[current.parentCategoryId];
  }

  final decodedSlugs = <String>[
    for (final item in chain.reversed)
      _decodedSlug(item.slug, fallback: '${item.id}-category'),
  ];
  final uri = Uri(pathSegments: ['c', ...decodedSlugs, '${category.id}.json']);
  return '/${uri.toString()}';
}

String _decodedSlug(String slug, {required String fallback}) {
  final value = slug.trim().isEmpty ? fallback : slug;
  try {
    return Uri.decodeComponent(value);
  } on FormatException {
    return value;
  }
}
