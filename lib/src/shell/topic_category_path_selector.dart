import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/site_config.dart';
import '../models/topic.dart';
import 'category_icon.dart';
import 'topic_category_path.dart';

/// A joined category path with a searchable sibling menu at every level.
class TopicCategoryPathSelector extends StatelessWidget {
  const TopicCategoryPathSelector({
    super.key,
    required this.siteUrl,
    required this.categories,
    required this.selectedCategoryId,
    required this.onSelected,
    this.keyPrefix = 'category-path',
    this.sheetOnMobile = false,
    this.maxCategoryNesting = SiteConfig.defaultMaxCategoryNesting,
  }) : assert(maxCategoryNesting > 0);

  final String siteUrl;
  final List<TopicCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<TopicCategory?>? onSelected;
  final String keyPrefix;
  final bool sheetOnMobile;

  /// The site's maximum depth, counting the root as level one.
  /// An existing deeper selection remains visible if cached settings change.
  final int maxCategoryNesting;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final category in categories) category.id: category};
    final selected = byId[selectedCategoryId];
    final path = selected == null
        ? const <TopicCategory>[]
        : topicCategoryPath(selected, categoryFor: (id) => byId[id]);
    final children = <int?, List<TopicCategory>>{};
    for (final category in byId.values) {
      final parentId = byId.containsKey(category.parentCategoryId)
          ? category.parentCategoryId
          : null;
      (children[parentId] ??= []).add(category);
    }
    for (final siblings in children.values) {
      siblings.sort(_compareCategories);
    }
    final deeper = children[selected?.id] ?? const <TopicCategory>[];
    final levels =
        path.length +
        (path.isEmpty || path.length < maxCategoryNesting && deeper.isNotEmpty
            ? 1
            : 0);

    Widget segment(int level) {
      final category = level < path.length ? path[level] : null;
      final parent = level == 0 ? null : path[level - 1];
      final prefix = switch (level) {
        0 => '$keyPrefix-category',
        1 => '$keyPrefix-subcategory',
        _ => '$keyPrefix-subcategory-$level',
      };
      final label =
          category?.name ??
          (level == 0
              ? context.l10n.categories
              : context.l10n.subcategoryTopiccategoryselector);
      return KeyedSubtree(
        key: ValueKey((siteUrl, maxCategoryNesting, level, parent?.id)),
        child: TopicCategorySelector(
          key: ValueKey('$prefix-filter'),
          keyPrefix: prefix,
          siteUrl: siteUrl,
          categories: children[parent?.id] ?? const [],
          selected: category,
          parent: parent,
          includeAll: level == 0,
          clearSelectionLabel: parent != null && category != null
              ? context.l10n.allOfCategory(parent.name)
              : null,
          hasChildren: (item) =>
              level + 1 < maxCategoryNesting &&
              (children[item.id]?.isNotEmpty ?? false),
          sheetOnMobile: sheetOnMobile,
          onSelected: onSelected == null
              ? null
              : (value) => onSelected!(value ?? parent),
          triggerBuilder: (context, trigger) => Focus(
            canRequestFocus: false,
            skipTraversal: true,
            includeSemantics: false,
            onFocusChange: (focused) {
              if (!focused) return;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted && trigger.focusNode.hasFocus) {
                  Scrollable.ensureVisible(context, alignment: .5);
                }
              });
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 130),
              child: DButton(
                size: DButtonSize.filter,
                variant: DButtonVariant.outline,
                alignment: AlignmentDirectional.centerStart,
                label: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                icon: category != null
                    ? CategoryIcon(
                        key: ValueKey(('$prefix-selected-icon', category.id)),
                        category: category,
                        siteUrl: siteUrl,
                        size: 14,
                        squareSize: 10,
                      )
                    : level == 0
                    ? const CategorySquare(color: null, size: 10)
                    : null,
                semanticLabel: category != null
                    ? context.l10n.categoryPathSegment(
                        topicCategoryPathLabel(
                          category,
                          categoryFor: (id) => byId[id],
                        ),
                      )
                    : parent == null
                    ? context.l10n.filterByCategory
                    : context.l10n.filterBySubcategoryOf(parent.name),
                onPressed: onSelected == null ? null : trigger.toggle,
                focusNode: trigger.focusNode,
                expanded: trigger.open,
                hasPopup: true,
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(
          0,
          double.infinity,
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DButtonGroup(
          sharedOutline: true,
          semanticLabel: context.l10n.filterByCategory,
          children: [
            for (var level = 0; level < levels; level++) ...[
              if (level > 0)
                const DButtonGroupText(
                  padding: EdgeInsets.symmetric(horizontal: 3),
                  child: DBreadcrumbSeparator(),
                ),
              segment(level),
            ],
          ],
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
