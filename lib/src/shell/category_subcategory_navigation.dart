import 'package:flutter/material.dart';

import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'choice_menu.dart';
import 'content_reading_lane.dart';

class CategorySubcategoryNavigation extends StatelessWidget {
  const CategorySubcategoryNavigation({
    super.key,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
  });

  final List<TopicCategory> categories;
  final int selectedCategoryId;
  final ValueChanged<TopicCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final byId = <int, TopicCategory>{
      for (final category in categories) category.id: category,
    };
    final selected = byId[selectedCategoryId];
    if (selected == null) return const SizedBox.shrink();

    final parent = selected.parentCategoryId == null
        ? selected
        : byId[selected.parentCategoryId!];
    if (parent == null) return const SizedBox.shrink();

    final subcategories =
        categories
            .where((category) => category.parentCategoryId == parent.id)
            .toList(growable: false)
          ..sort(_compareCategories);
    if (subcategories.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('category-subcategory-navigation'),
      color: theme.shell.panel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.shell.divider)),
        ),
        child: ContentReadingLaneBox(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final visibleSubcategories = _visibleSubcategories(
                subcategories,
                selectedCategoryId: selected.id,
                maximumVisible: _maximumVisible(constraints.maxWidth),
              );
              final hasOverflow =
                  visibleSubcategories.length < subcategories.length;

              return Semantics(
                container: true,
                label: 'Subcategories of ${parent.name}',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _CategoryNavigationButton(
                      key: ValueKey(('subcategory-navigation', parent.id)),
                      category: parent,
                      label: 'All topics',
                      selected: selected.id == parent.id,
                      showColor: false,
                      onPressed: () => onSelected(parent),
                    ),
                    for (final category in visibleSubcategories)
                      _CategoryNavigationButton(
                        key: ValueKey(('subcategory-navigation', category.id)),
                        category: category,
                        label: category.name,
                        selected: selected.id == category.id,
                        onPressed: () => onSelected(category),
                      ),
                    if (hasOverflow)
                      _SubcategoryOverflowButton(
                        parent: parent,
                        subcategories: subcategories,
                        selected: selected,
                        onSelected: onSelected,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

int _compareCategories(TopicCategory left, TopicCategory right) {
  final leftPosition = left.position;
  final rightPosition = right.position;
  if (leftPosition != null || rightPosition != null) {
    if (leftPosition == null) return 1;
    if (rightPosition == null) return -1;
    final positioned = leftPosition.compareTo(rightPosition);
    if (positioned != 0) return positioned;
  }
  final folded = left.name.toLowerCase().compareTo(right.name.toLowerCase());
  return folded != 0 ? folded : left.id.compareTo(right.id);
}

int _maximumVisible(double width) {
  if (width >= 840) return 5;
  if (width >= 620) return 4;
  if (width >= 460) return 3;
  if (width >= 340) return 2;
  return 1;
}

List<TopicCategory> _visibleSubcategories(
  List<TopicCategory> subcategories, {
  required int selectedCategoryId,
  required int maximumVisible,
}) {
  if (subcategories.length <= maximumVisible) return subcategories;

  final visible = subcategories.take(maximumVisible).toList(growable: true);
  final selectedIndex = subcategories.indexWhere(
    (category) => category.id == selectedCategoryId,
  );
  if (selectedIndex >= maximumVisible) {
    visible[visible.length - 1] = subcategories[selectedIndex];
    visible.sort(
      (left, right) =>
          subcategories.indexOf(left).compareTo(subcategories.indexOf(right)),
    );
  }
  return visible;
}

class _CategoryNavigationButton extends StatelessWidget {
  const _CategoryNavigationButton({
    super.key,
    required this.category,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.showColor = true,
  });

  final TopicCategory category;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final bool showColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 40, maxWidth: 220),
    child: DButton(
      label: Text(label),
      icon: showColor ? _CategoryColorSquare(category: category) : null,
      semanticLabel: selected ? '$label, selected' : label,
      onPressed: onPressed,
      variant: selected ? DButtonVariant.primary : DButtonVariant.standard,
      size: DButtonSize.small,
    ),
  );
}

class _CategoryColorSquare extends StatelessWidget {
  const _CategoryColorSquare({required this.category});

  final TopicCategory category;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: Color(category.colorValue),
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _SubcategoryOverflowButton extends StatelessWidget {
  const _SubcategoryOverflowButton({
    required this.parent,
    required this.subcategories,
    required this.selected,
    required this.onSelected,
  });

  final TopicCategory parent;
  final List<TopicCategory> subcategories;
  final TopicCategory selected;
  final ValueChanged<TopicCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final categories = [parent, ...subcategories];
    return ChoiceMenuAnchor<int>(
      title: 'Subcategories of ${parent.name}',
      value: selected.id,
      options: [
        for (final category in categories)
          ChoiceMenuOption<int>(
            value: category.id,
            title: category.id == parent.id ? 'All topics' : category.name,
            description: category.id == parent.id
                ? 'Show every topic in ${parent.name}'
                : 'Show topics in ${category.name}',
            icon: DIcons.folder,
          ),
      ],
      onSelected: (categoryId) => onSelected(
        categories.firstWhere((category) => category.id == categoryId),
      ),
      builder: (context, openMenu) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: DButton(
          key: const ValueKey('subcategory-navigation-more'),
          label: const Text('More'),
          icon: const DIcon(DIcons.chevronDown, size: 14),
          semanticLabel: 'More subcategories',
          tooltip: 'Browse all subcategories',
          onPressed: openMenu,
          size: DButtonSize.small,
        ),
      ),
    );
  }
}
