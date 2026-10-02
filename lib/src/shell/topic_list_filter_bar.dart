import 'package:discourse_native/discourse_ui.dart';
import 'package:discourse_native/l10n/strings.dart';
import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/site_config.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import 'content_reading_lane.dart';
import 'forum_theme_surfaces.dart';
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
    this.leading,
    this.maxCategoryNesting = SiteConfig.defaultMaxCategoryNesting,
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
  final Widget? leading;
  final int maxCategoryNesting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedTags = [
      for (final value in selectedTagNames ?? [?selectedTagName])
        _selectedTag(knownTags, value),
    ];

    final controlChildren = <Widget>[
      TopicCategoryPathSelector(
        keyPrefix: 'topic-list',
        siteUrl: siteUrl,
        categories: categories,
        selectedCategoryId: selectedCategoryId,
        onSelected: onCategorySelected,
        sheetOnMobile: true,
        maxCategoryNesting: maxCategoryNesting,
      ),
      if (taggingEnabled)
        TopicTagSelector(
          key: const ValueKey('topic-list-tag-filter'),
          keyPrefix: 'topic-list-tag-filter',
          includeAll: true,
          sheetOnMobile: true,
          size: DButtonSize.filter,
          multiple: onTagsSelected != null,
          knownTags: [
            for (final tag in knownTags)
              TopicTag(id: tag.id, name: tag.name, slug: tag.slug),
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
              ?leading,
              Row(
                children: [
                  Expanded(child: controlChildren.first),
                  if (controlChildren.length > 1) ...[
                    const SizedBox(width: DSpacing.controlGap),
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
        ? Wrap(
            spacing: DSpacing.controlGap,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [?leading, ...controlChildren],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[
                leading!,
                const SizedBox(width: DSpacing.controlGap),
              ],
              for (var index = 0; index < controlChildren.length; index++) ...[
                if (index > 0) const SizedBox(width: DSpacing.controlGap),
                if (inline)
                  Flexible(child: controlChildren[index])
                else
                  controlChildren[index],
              ],
            ],
          );

    return Material(
      key: const ValueKey('topic-list-filter-bar'),
      color: ForumWindowBackground.surfaceColor(context, theme.shell.content),
      child: compact
          ? controls
          : wrap
          ? Align(
              widthFactor: 1,
              alignment: AlignmentDirectional.centerStart,
              child: controls,
            )
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

TopicTag _selectedTag(List<SidebarTag> knownTags, String value) {
  final known = _selectedKnownTag(knownTags, value);
  return TopicTag(id: known?.id, name: known?.name ?? value, slug: known?.slug);
}
