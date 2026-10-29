import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'content_reading_lane.dart';
import 'topic_category_path.dart';
import 'topic_filter_controller.dart';
import 'topic_filter_scope.dart';
import 'topic_list_actions.dart';
import 'topic_list_layout.dart';

typedef TopicListTagSearch =
    Future<List<TopicFilterLookupValue>> Function(String term);

class TopicListFilterBar extends StatefulWidget {
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
    this.selectedTagNames,
    this.onTagsSelected,
    this.leading,
    this.trailing,
    this.maxCategoryNesting = SiteConfig.defaultMaxCategoryNesting,
    this.filterQuery,
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
  final List<String>? selectedTagNames;
  final ValueChanged<List<String>>? onTagsSelected;
  final Widget? leading;
  final Widget? trailing;
  final int maxCategoryNesting;
  final String? filterQuery;

  @override
  State<TopicListFilterBar> createState() => _TopicListFilterBarState();
}

class _TopicListFilterBarState extends State<TopicListFilterBar> {
  // A menu keeps its editor when Backspace removes the segment it opened
  // from; its key moves to the last remaining segment of the shortened path.
  final _categoryMenuKeys = <int, GlobalKey>{};
  int? _openCategoryLevel;

  @override
  Widget build(BuildContext context) {
    final selectedTags = [
      for (final value in widget.selectedTagNames ?? [?widget.selectedTagName])
        _selectedTag(widget.knownTags, value),
    ];

    final displayedCategoryId =
        widget.selectedCategoryId ??
        parseTopicFilterScope(
          splitTopicFilterQuery(widget.filterQuery ?? '')
              .map(
                (token) =>
                    token.startsWith('=category:') ? token.substring(1) : token,
              )
              .join(' '),
          widget.categories,
        ).categoryId;
    final byId = {
      for (final category in widget.categories) category.id: category,
    };
    final selected = byId[displayedCategoryId];
    final path = selected == null
        ? <TopicCategory>[]
        : topicCategoryPath(selected, categoryFor: (id) => byId[id]);
    final hasDeeper = widget.categories.any(
      (category) => category.parentCategoryId == selected?.id,
    );
    final lastLevel = path.isEmpty
        ? 0
        : hasDeeper && path.length < widget.maxCategoryNesting
        ? path.length
        : path.length - 1;
    final activeLevel = _openCategoryLevel?.clamp(0, lastLevel);
    final exact = splitTopicFilterQuery(
      widget.filterQuery ?? '',
    ).any((token) => token.startsWith('=category:'));
    final controlChildren = <Widget>[
      if (widget.filterQuery != null) ...[
        TopicCategoryPathSelector(
          keyPrefix: 'topic-list',
          siteUrl: widget.siteUrl,
          categories: widget.categories,
          selectedCategoryId: displayedCategoryId,
          exact: exact,
          onSelected: widget.onCategorySelected,
          maxCategoryNesting: widget.maxCategoryNesting,
          segmentBuilder: (context, level, category, label, iconOnly) =>
              TopicListFilterMenu(
                key: _categoryMenuKeys.putIfAbsent(
                  level == activeLevel ? _openCategoryLevel! : level,
                  GlobalKey.new,
                ),
                onOpenChanged: (open) {
                  if (mounted) {
                    setState(() => _openCategoryLevel = open ? level : null);
                  }
                },
                siteUrl: widget.siteUrl,
                query: widget.filterQuery!,
                filterKey: 'category',
                categoryParentId: level == 0 ? null : path[level - 1].id,
                triggerKey: ValueKey(
                  level == 0
                      ? 'topic-list-category-filter'
                      : 'topic-list-subcategory-filter-$level',
                ),
                label: label,
                iconOnly: iconOnly,
                dimLabel: category == null && level > 0 && !exact,
                icon: category != null
                    ? CategoryIcon(
                        category: category,
                        siteUrl: widget.siteUrl,
                        size: 12,
                        squareSize: 10,
                      )
                    : level == 0
                    ? const CategorySquare(color: null, size: 10)
                    : !iconOnly
                    ? null
                    : exact
                    ? const DIcon(noSubcategoriesIcon)
                    : const DIcon(DIcons.plus),
              ),
        ),
        if (widget.taggingEnabled)
          TopicListFilterMenu(
            siteUrl: widget.siteUrl,
            query: widget.filterQuery!,
            filterKey: 'tag',
            triggerKey: const ValueKey('topic-list-tag-filter'),
            label: topicListTagFilterLabel(
              widget.filterQuery!,
              context.l10n.tags,
            ),
            icon: const DIcon(DIcons.tag, size: 12),
          ),
      ],
      if (widget.filterQuery == null)
        TopicCategoryPathSelector(
          keyPrefix: 'topic-list',
          siteUrl: widget.siteUrl,
          categories: widget.categories,
          selectedCategoryId: widget.selectedCategoryId,
          onSelected: widget.onCategorySelected,
          sheetOnMobile: true,
          maxCategoryNesting: widget.maxCategoryNesting,
        ),
      if (widget.taggingEnabled && widget.filterQuery == null)
        TopicTagSelector(
          key: const ValueKey('topic-list-tag-filter'),
          keyPrefix: 'topic-list-tag-filter',
          includeAll: true,
          quiet: true,
          sheetOnMobile: true,
          size: DButtonSize.filter,
          multiple: widget.onTagsSelected != null,
          knownTags: [
            for (final tag in widget.knownTags)
              TopicTag(
                id: tag.id,
                name: tag.name,
                slug: tag.slug,
                count: tag.count,
              ),
          ],
          selectedTags: selectedTags,
          semanticLabel: selectedTags.isEmpty
              ? context.l10n.filterByTag
              : selectedTags.length > 1
              ? context.l10n.filterByTags(
                  (selectedTags.map((tag) => tag.name).join(', ')).toString(),
                )
              : context.l10n.tagTopiclistfilterbar(
                  (selectedTags.first.name).toString(),
                ),
          search: (query) async => TopicTagSearch(
            tags: [
              for (final tag in await widget.searchTags(query))
                TopicTag(
                  name: tag.name,
                  count: int.tryParse(tag.description ?? '') ?? 0,
                ),
            ],
          ),
          onChanged: (tags) {
            if (widget.onTagsSelected case final onSelected?) {
              onSelected(tags.map((tag) => tag.name).toList());
            } else {
              final tag = tags.firstOrNull;
              widget.onTagSelected(tag?.slug ?? tag?.name);
            }
          },
        ),
    ];
    // On one line, the Filters menu down to its glyph and count once they do
    // not all fit, and wrapped at full length when even that is too wide.
    final controls = widget.wrap
        ? DFitRow(
            runSpacing: 8,
            children: [?widget.leading, ...controlChildren, ?widget.trailing],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: DSpacing.sm),
              ],
              for (var index = 0; index < controlChildren.length; index++) ...[
                if (index > 0) const SizedBox(width: DSpacing.sm),
                if (widget.inline)
                  Flexible(child: controlChildren[index])
                else
                  controlChildren[index],
              ],
              if (widget.trailing != null) ...[
                const SizedBox(width: DSpacing.sm),
                widget.trailing!,
              ],
            ],
          );

    return KeyedSubtree(
      key: const ValueKey('topic-list-filter-bar'),
      child: widget.wrap
          ? Align(
              widthFactor: 1,
              alignment: AlignmentDirectional.centerStart,
              child: controls,
            )
          : widget.inline
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

TopicTag _selectedTag(List<SidebarTag> knownTags, String value) {
  final known = _selectedKnownTag(knownTags, value);
  return TopicTag(id: known?.id, name: known?.name ?? value, slug: known?.slug);
}
