import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/site_config.dart';
import '../models/topic.dart';
import '../theme/d_icons.dart';
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
    this.segmentBuilder,
    this.exact = false,
  }) : assert(maxCategoryNesting > 0);

  final String siteUrl;
  final List<TopicCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<TopicCategory?>? onSelected;
  final String keyPrefix;
  final bool sheetOnMobile;
  final bool exact;

  /// The site's maximum depth, counting the root as level one.
  /// An existing deeper selection remains visible if cached settings change.
  final int maxCategoryNesting;

  /// Page filters can keep their existing editor behind the shared path artwork.
  final Widget Function(BuildContext, int, TopicCategory?, String, bool)?
  segmentBuilder;

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
    final short = DFitRow.tightOf(context);

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
              : exact
              ? context.l10n.filterNoSubcategories
              : context.l10n.subcategoryTopiccategoryselector);
      final iconOnly = short && path.isNotEmpty && level != path.length - 1;
      final icon = category != null
          ? CategoryIcon(
              key: ValueKey(('$prefix-selected-icon', category.id)),
              category: category,
              siteUrl: siteUrl,
              size: 14,
              squareSize: 10,
            )
          : level == 0
          ? const CategorySquare(color: null, size: 10)
          : exact
          ? const DIcon(noSubcategoriesIcon)
          : const DIcon(DIcons.plus);
      if (segmentBuilder case final builder?) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 180),
          child: builder(context, level, category, label, iconOnly),
        );
      }
      final semanticLabel = category != null
          ? context.l10n.categoryPathSegment(
              topicCategoryPathLabel(category, categoryFor: (id) => byId[id]),
            )
          : parent == null
          ? context.l10n.filterByCategory
          : exact
          ? context.l10n.filterNoSubcategories
          : context.l10n.filterBySubcategoryOf(parent.name);
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
              constraints: const BoxConstraints(maxWidth: 180),
              child: iconOnly
                  ? DButton.iconOnly(
                      size: DButtonSize.filter,
                      variant: DButtonVariant.quiet,
                      shape: DButtonShape.pill,
                      icon: icon,
                      tooltip: label,
                      semanticLabel: semanticLabel,
                      onPressed: onSelected == null ? null : trigger.toggle,
                      focusNode: trigger.focusNode,
                      expanded: trigger.open,
                      hasPopup: true,
                    )
                  : DButton(
                      size: DButtonSize.filter,
                      variant: DButtonVariant.quiet,
                      alignment: AlignmentDirectional.centerStart,
                      label: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: category == null && level > 0
                            ? TextStyle(
                                color: Color.lerp(
                                  DTokens.of(context).background,
                                  DTokens.of(context).foreground,
                                  .40,
                                ),
                              )
                            : null,
                      ),
                      icon: category != null || level == 0 ? icon : null,
                      semanticLabel: semanticLabel,
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
        child: DButtonGroup.quiet(
          selected: path.isNotEmpty,
          semanticLabel: context.l10n.filterByCategory,
          children: [
            for (var level = 0; level < levels; level++) ...[
              if (level > 0)
                DButtonGroupText(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: DIcon(
                    _pathSeparatorIcon,
                    size: 14,
                    color: DTokens.of(
                      context,
                    ).mutedForeground.withValues(alpha: .45),
                  ),
                ),
              segment(level),
            ],
          ],
        ),
      ),
    );
  }
}

const noSubcategoriesIcon = DIconData(
  'no-subcategories',
  '<svg viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<circle cx="8" cy="8" r="6" stroke="currentColor" stroke-width="1.5"/>'
      '<path d="m4 4 8 8" stroke="currentColor" stroke-width="1.5"/>'
      '</svg>',
);

const _pathSeparatorIcon = DIconData(
  'category-path-separator',
  '<svg viewBox="0 0 5 16" fill="none" xmlns="http://www.w3.org/2000/svg">'
      '<path d="M4 1 1 15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>'
      '</svg>',
);

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
