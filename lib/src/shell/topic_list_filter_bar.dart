import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import 'content_reading_lane.dart';
import 'topic_list_layout.dart';

typedef TopicListTagSearch =
    Future<List<TopicFilterLookupValue>> Function(String term);

class TopicListFilterBar extends StatelessWidget {
  const TopicListFilterBar({
    super.key,
    required this.siteUrl,
    required this.categories,
    required this.knownTags,
    required this.selectedCategoryId,
    required this.selectedTagName,
    required this.taggingEnabled,
    required this.searchTags,
    required this.onCategorySelected,
    required this.onTagSelected,
    this.inline = false,
    this.wrap = false,
    this.compact = false,
    this.selectedTagNames,
    this.onTagsSelected,
  });

  final String siteUrl;
  final List<TopicCategory> categories;
  final List<SidebarTag> knownTags;
  final int? selectedCategoryId;
  final String? selectedTagName;
  final bool taggingEnabled;
  final TopicListTagSearch searchTags;
  final ValueChanged<TopicCategory?> onCategorySelected;
  final ValueChanged<String?> onTagSelected;
  final bool inline;
  final bool wrap;
  final bool compact;
  final List<String>? selectedTagNames;
  final ValueChanged<List<String>>? onTagsSelected;

  @override
  Widget build(BuildContext context) {
    final byId = <int, TopicCategory>{
      for (final category in categories) category.id: category,
    };
    final selectedCategory = byId[selectedCategoryId];
    final rootCategory = switch (selectedCategory) {
      null => null,
      final category when category.parentCategoryId == null => category,
      final category => byId[category.parentCategoryId],
    };
    final rootCategories =
        categories
            .where((category) => category.parentCategoryId == null)
            .toList(growable: false)
          ..sort(_compareCategories);
    final subcategories = rootCategory == null
        ? const <TopicCategory>[]
        : (categories
              .where((category) => category.parentCategoryId == rootCategory.id)
              .toList(growable: false)
            ..sort(_compareCategories));
    final theme = Theme.of(context);
    final selectedTags = [
      for (final value in selectedTagNames ?? [?selectedTagName])
        _selectedTag(knownTags, value),
    ];

    final controlChildren = <Widget>[
      TopicCategorySelector(
        key: const ValueKey('topic-list-category-filter'),
        keyPrefix: 'topic-list-category',
        includeAll: true,
        size: DButtonSize.regular,
        siteUrl: siteUrl,
        categories: rootCategories,
        selected: rootCategory,
        onSelected: onCategorySelected,
      ),
      if (subcategories.isNotEmpty)
        KeyedSubtree(
          key: ValueKey(rootCategory!.id),
          child: TopicCategorySelector(
            key: const ValueKey('topic-list-subcategory-filter'),
            keyPrefix: 'topic-list-subcategory',
            includeAll: true,
            size: DButtonSize.regular,
            placeholder: 'Subcategories',
            siteUrl: siteUrl,
            parent: rootCategory,
            categories: subcategories,
            selected: selectedCategory?.parentCategoryId == null
                ? null
                : selectedCategory,
            onSelected: (category) =>
                onCategorySelected(category ?? rootCategory),
          ),
        ),
      if (taggingEnabled)
        TopicTagSelector(
          key: const ValueKey('topic-list-tag-filter'),
          keyPrefix: 'topic-list-tag-filter',
          includeAll: true,
          size: DButtonSize.regular,
          multiple: onTagsSelected != null,
          knownTags: [
            for (final tag in knownTags)
              TopicTag(id: tag.id, name: tag.name, slug: tag.slug),
          ],
          selectedTags: selectedTags,
          semanticLabel: selectedTags.isEmpty
              ? 'Filter by tag'
              : selectedTags.length > 1
              ? 'Filter by tags: ${selectedTags.map((tag) => tag.name).join(', ')}'
              : 'Tag: ${selectedTags.first.name}',
          search: (query) async => TopicTagSearch(
            tags: [
              for (final tag in await searchTags(query))
                TopicTag(name: tag.name),
            ],
          ),
          onChanged: (tags) {
            if (onTagsSelected case final onSelected?) {
              onSelected(tags.map((tag) => tag.name).toList());
            } else {
              final tag = tags.firstOrNull;
              onTagSelected(tag?.slug ?? tag?.name);
            }
          },
        ),
    ];
    final controls = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: controlChildren.first),
                  if (controlChildren.length > 1) ...[
                    const SizedBox(width: DSpacing.sm),
                    Expanded(child: controlChildren[1]),
                  ],
                ],
              ),
              if (controlChildren.length > 2) ...[
                const SizedBox(height: DSpacing.sm),
                controlChildren[2],
              ],
            ],
          )
        : wrap
        ? Wrap(spacing: 8, runSpacing: 8, children: controlChildren)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < controlChildren.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                if (inline)
                  Flexible(child: controlChildren[index])
                else
                  controlChildren[index],
              ],
            ],
          );

    return Material(
      key: const ValueKey('topic-list-filter-bar'),
      color: theme.shell.content,
      child: compact
          ? controls
          : wrap
          ? Align(alignment: AlignmentDirectional.centerStart, child: controls)
          : inline
          ? controls
          : ContentReadingLaneBox(
              widthLimit: topicListContentWidth,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: topicListHorizontalPadding,
                ),
                child: controls,
              ),
            ),
    );
  }
}

SidebarTag? _selectedKnownTag(List<SidebarTag> tags, String? selected) {
  if (selected == null) return null;
  final folded = selected.toLowerCase();
  for (final tag in tags) {
    if (tag.name.toLowerCase() == folded || tag.slug.toLowerCase() == folded) {
      return tag;
    }
  }
  return null;
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

TopicTag _selectedTag(List<SidebarTag> knownTags, String value) {
  final known = _selectedKnownTag(knownTags, value);
  return TopicTag(id: known?.id, name: known?.name ?? value, slug: known?.slug);
}
