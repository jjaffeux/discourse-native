import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'topic_list_filter_bar.dart';

typedef TopicListFilterSelection = ({
  TopicCategory? category,
  List<String> tags,
});

/// A staged edit of the current feed's category and tags.
/// The caller keys this surface by feed ownership so a retired feed dismisses it.
class TopicListFilterSheet extends StatefulWidget {
  const TopicListFilterSheet({
    super.key,
    required this.siteUrl,
    required this.categories,
    required this.knownTags,
    required this.categoryId,
    required this.tags,
    required this.taggingEnabled,
    required this.searchTags,
    required this.onApply,
    this.showLabel = true,
    this.multiple = true,
  });

  final String siteUrl;
  final List<TopicCategory> categories;
  final List<SidebarTag> knownTags;
  final int? categoryId;
  final List<String> tags;
  final bool taggingEnabled;
  final TopicListTagSearch searchTags;
  final ValueChanged<TopicListFilterSelection> onApply;
  final bool showLabel;
  final bool multiple;

  @override
  State<TopicListFilterSheet> createState() => _TopicListFilterSheetState();
}

class _TopicListFilterSheetState extends State<TopicListFilterSheet> {
  final _sheet = DSheetController<void>();
  int? _categoryId;
  List<String> _tags = [];

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = (widget.categoryId == null ? 0 : 1) + widget.tags.length;
    return DSheet<void>(
      controller: _sheet,
      trigger: DSheetTrigger(
        builder: (context, open) {
          void show() {
            setState(() {
              _categoryId = widget.categoryId;
              _tags = List.of(widget.tags);
            });
            open();
          }

          final label = count == 0 ? 'Filters' : 'Filters, $count active';
          return widget.showLabel || count > 0
              ? DButton(
                  key: const ValueKey('topic-list-filters'),
                  variant: DButtonVariant.outline,
                  size: DButtonSize.small,
                  icon: const DIcon(DIcons.filter, size: 14),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showLabel) const Text('Filters'),
                      if (widget.showLabel && count > 0)
                        const SizedBox(width: 6),
                      if (count > 0)
                        DBadge(
                          variant: DBadgeVariant.secondary,
                          child: Text('$count'),
                        ),
                    ],
                  ),
                  semanticLabel: label,
                  onPressed: show,
                )
              : DButton.iconOnly(
                  key: const ValueKey('topic-list-filters'),
                  variant: DButtonVariant.outline,
                  size: DButtonSize.small,
                  icon: const DIcon(DIcons.filter, size: 14),
                  tooltip: label,
                  semanticLabel: label,
                  onPressed: show,
                );
        },
      ),
      content: DSheetContent(
        key: const ValueKey('topic-list-filter-sheet'),
        side: DSheetSide.bottom,
        topBottomMaxHeightFactor: .85,
        semanticLabel: 'Topic filters',
        children: [
          const DSheetHeader(
            children: [
              DSheetTitle(child: Text('Filters')),
              DSheetDescription(child: Text('Refine the current topic list.')),
            ],
          ),
          DSheetBody(
            child: TopicListFilterBar(
              vertical: true,
              siteUrl: widget.siteUrl,
              categories: widget.categories,
              knownTags: widget.knownTags,
              selectedCategoryId: _categoryId,
              selectedTagName: _tags.firstOrNull,
              selectedTagNames: widget.multiple ? _tags : null,
              taggingEnabled: widget.taggingEnabled,
              searchTags: widget.searchTags,
              onCategorySelected: (category) =>
                  setState(() => _categoryId = category?.id),
              onTagSelected: (tag) => setState(() => _tags = [?tag]),
              onTagsSelected: widget.multiple
                  ? (tags) => setState(() => _tags = tags)
                  : null,
            ),
          ),
          DSheetFooter(
            children: [
              DButton(
                key: const ValueKey('topic-list-apply-filters'),
                label: const Text('Apply filters'),
                onPressed: () {
                  final selection = (
                    category: widget.categories
                        .where((c) => c.id == _categoryId)
                        .firstOrNull,
                    tags: List<String>.of(_tags),
                  );
                  _sheet.close();
                  widget.onApply(selection);
                },
              ),
              DButton(
                key: const ValueKey('topic-list-reset-filters'),
                variant: DButtonVariant.ghost,
                label: const Text('Reset'),
                onPressed: () => setState(() {
                  _categoryId = null;
                  _tags = [];
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
