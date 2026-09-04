import 'dart:async';

import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import '../theme/d_button.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_picker.dart';
import 'choice_menu.dart';
import 'content_reading_lane.dart';

typedef TopicListTagSearch =
    Future<List<TopicFilterLookupValue>> Function(String term);

class TopicListFilterBar extends StatelessWidget {
  const TopicListFilterBar({
    super.key,
    required this.categories,
    required this.knownTags,
    required this.selectedCategoryId,
    required this.selectedTagName,
    required this.taggingEnabled,
    required this.searchTags,
    required this.onCategorySelected,
    required this.onTagSelected,
    required this.onReset,
  });

  final List<TopicCategory> categories;
  final List<SidebarTag> knownTags;
  final int? selectedCategoryId;
  final String? selectedTagName;
  final bool taggingEnabled;
  final TopicListTagSearch searchTags;
  final ValueChanged<TopicCategory?> onCategorySelected;
  final ValueChanged<String?> onTagSelected;
  final VoidCallback onReset;

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
    final hasFilters = selectedCategoryId != null || selectedTagName != null;
    final theme = Theme.of(context);

    return Material(
      key: const ValueKey('topic-list-filter-bar'),
      color: theme.shell.sidebar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.shell.divider)),
        ),
        child: ContentReadingLaneBox(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: constraints.maxWidth - 32,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _CategoryFilterAnchor(
                      categories: rootCategories,
                      selected: rootCategory,
                      onSelected: onCategorySelected,
                    ),
                    if (subcategories.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _SubcategoryFilterAnchor(
                        parent: rootCategory!,
                        subcategories: subcategories,
                        selected: selectedCategory?.parentCategoryId == null
                            ? null
                            : selectedCategory,
                        onSelected: onCategorySelected,
                      ),
                    ],
                    if (taggingEnabled) ...[
                      const SizedBox(width: 8),
                      _TagFilterAnchor(
                        knownTags: knownTags,
                        selectedTagName: selectedTagName,
                        search: searchTags,
                        onSelected: onTagSelected,
                      ),
                    ],
                    if (hasFilters) ...[
                      const SizedBox(width: 4),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 40),
                        child: DButton(
                          key: const ValueKey('topic-list-filter-reset'),
                          label: const Text('Reset'),
                          icon: const DIcon(DIcons.arrowsRotate, size: 14),
                          semanticLabel: 'Reset topic filters',
                          onPressed: onReset,
                          variant: DButtonVariant.flat,
                          size: DButtonSize.small,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryFilterAnchor extends StatelessWidget {
  const _CategoryFilterAnchor({
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  final List<TopicCategory> categories;
  final TopicCategory? selected;
  final ValueChanged<TopicCategory?> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceMenuAnchor<int>(
    title: 'Categories',
    showPopoverTitle: false,
    value: selected?.id ?? 0,
    options: [
      const ChoiceMenuOption<int>(
        value: 0,
        title: 'All categories',
        description: '',
        icon: DIcons.layerGroup,
      ),
      for (final category in categories)
        ChoiceMenuOption<int>(
          value: category.id,
          title: category.name,
          description: '',
          icon: DIcons.folder,
        ),
    ],
    filterHint: 'Filter categories',
    filterEmptyMessage: 'No matching categories.',
    alwaysVisibleValues: const {0},
    onSelected: (categoryId) => onSelected(
      categoryId == 0
          ? null
          : categories.firstWhere((category) => category.id == categoryId),
    ),
    builder: (context, openMenu) => _FilterButton(
      key: const ValueKey('topic-list-category-filter'),
      label: selected?.name ?? 'All categories',
      color: selected == null ? null : Color(selected!.colorValue),
      semanticLabel: selected == null
          ? 'Filter by category'
          : 'Category: ${selected!.name}',
      onPressed: openMenu,
      minimumWidth: 150,
      maximumWidth: 260,
    ),
  );
}

class _SubcategoryFilterAnchor extends StatelessWidget {
  const _SubcategoryFilterAnchor({
    required this.parent,
    required this.subcategories,
    required this.selected,
    required this.onSelected,
  });

  final TopicCategory parent;
  final List<TopicCategory> subcategories;
  final TopicCategory? selected;
  final ValueChanged<TopicCategory> onSelected;

  @override
  Widget build(BuildContext context) => ChoiceMenuAnchor<int>(
    title: 'Subcategories of ${parent.name}',
    value: selected?.id ?? 0,
    options: [
      ChoiceMenuOption<int>(
        value: 0,
        title: 'All subcategories',
        description: '',
        icon: DIcons.layerGroup,
      ),
      for (final category in subcategories)
        ChoiceMenuOption<int>(
          value: category.id,
          title: category.name,
          description: '',
          icon: DIcons.folder,
        ),
    ],
    filterHint: 'Filter subcategories',
    filterEmptyMessage: 'No matching subcategories.',
    alwaysVisibleValues: const {0},
    onSelected: (categoryId) => onSelected(
      categoryId == 0
          ? parent
          : subcategories.firstWhere((category) => category.id == categoryId),
    ),
    builder: (context, openMenu) => _FilterButton(
      key: const ValueKey('topic-list-subcategory-filter'),
      label: selected?.name ?? 'Subcategories',
      color: selected == null ? null : Color(selected!.colorValue),
      semanticLabel: selected == null
          ? 'Filter by subcategory of ${parent.name}'
          : 'Subcategory: ${selected!.name}',
      onPressed: openMenu,
      minimumWidth: 140,
      maximumWidth: 230,
    ),
  );
}

class _TagFilterAnchor extends StatefulWidget {
  const _TagFilterAnchor({
    required this.knownTags,
    required this.selectedTagName,
    required this.search,
    required this.onSelected,
  });

  final List<SidebarTag> knownTags;
  final String? selectedTagName;
  final TopicListTagSearch search;
  final ValueChanged<String?> onSelected;

  @override
  State<_TagFilterAnchor> createState() => _TagFilterAnchorState();
}

class _TagFilterAnchorState extends State<_TagFilterAnchor> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _showing = false;

  Future<void> _show() async {
    final anchorContext = _anchorKey.currentContext;
    if (_showing || anchorContext == null) return;
    _showing = true;
    try {
      final selected = await showAnchoredPicker<String>(
        context: context,
        anchorContext: anchorContext,
        title: 'Tags',
        barrierLabel: 'Dismiss tag filter',
        popoverKey: const ValueKey('topic-list-tag-filter-popover'),
        builder: (pickerContext) => _TagFilterPicker(
          knownTags: widget.knownTags,
          selectedTagName: widget.selectedTagName,
          search: widget.search,
          onSelected: Navigator.of(pickerContext).pop,
        ),
      );
      if (!mounted || selected == null) return;
      final normalized = selected.isEmpty ? null : selected;
      if (normalized != widget.selectedTagName) widget.onSelected(normalized);
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedKnownTag(
      widget.knownTags,
      widget.selectedTagName,
    );
    return SizedBox(
      key: _anchorKey,
      child: _FilterButton(
        key: const ValueKey('topic-list-tag-filter'),
        label: selected?.name ?? widget.selectedTagName ?? 'Tags',
        icon: const DIcon(DIcons.tag, size: 14),
        semanticLabel: widget.selectedTagName == null
            ? 'Filter by tag'
            : 'Tag: ${selected?.name ?? widget.selectedTagName}',
        onPressed: _show,
        minimumWidth: 104,
        maximumWidth: 210,
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    required this.minimumWidth,
    required this.maximumWidth,
    this.color,
    this.icon,
  });

  final String label;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double minimumWidth;
  final double maximumWidth;
  final Color? color;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      minWidth: minimumWidth,
      maxWidth: maximumWidth,
      minHeight: 40,
    ),
    child: DButton(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          const DIcon(DIcons.chevronRight, size: 12),
        ],
      ),
      icon: icon ?? (color == null ? null : _ColorSquare(color: color!)),
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      alignment: Alignment.centerLeft,
      size: DButtonSize.small,
    ),
  );
}

class _ColorSquare extends StatelessWidget {
  const _ColorSquare({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _TagFilterPicker extends StatefulWidget {
  const _TagFilterPicker({
    required this.knownTags,
    required this.selectedTagName,
    required this.search,
    required this.onSelected,
  });

  final List<SidebarTag> knownTags;
  final String? selectedTagName;
  final TopicListTagSearch search;
  final ValueChanged<String> onSelected;

  @override
  State<_TagFilterPicker> createState() => _TagFilterPickerState();
}

class _TagFilterPickerState extends State<_TagFilterPicker> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  late final LatestWinsQueuedLookupController<String, List<_TagChoice>> _lookup;
  List<_TagChoice> _results = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _lookup = LatestWinsQueuedLookupController(
      lookup: _searchTags,
      onResult: (result) {
        setState(() {
          _results = result;
          _loading = false;
        });
      },
      onError: (_, _) {
        setState(() {
          _results = _knownChoices(_query.text);
          _loading = false;
        });
      },
    );
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
    _query.dispose();
    super.dispose();
  }

  void _changed(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(value));
  }

  void _search(String term) {
    setState(() => _loading = true);
    _lookup.request(term);
  }

  Future<List<_TagChoice>> _searchTags(String term) async {
    final byLabel = <String, _TagChoice>{};
    for (final choice in _knownChoices(term)) {
      byLabel.putIfAbsent(choice.label.toLowerCase(), () => choice);
    }
    for (final tag in await widget.search(term.trim())) {
      byLabel.putIfAbsent(
        tag.name.toLowerCase(),
        () => _TagChoice(value: tag.name, label: tag.name),
      );
    }
    return List.unmodifiable(byLabel.values);
  }

  List<_TagChoice> _knownChoices(String term) {
    final query = term.trim().toLowerCase();
    return [
      for (final tag in widget.knownTags)
        if (query.isEmpty ||
            tag.name.toLowerCase().contains(query) ||
            tag.slug.toLowerCase().contains(query))
          _TagChoice(value: tag.slug, label: tag.name),
    ];
  }

  void _submitQuery() {
    if (_results.isNotEmpty) widget.onSelected(_results.first.value);
  }

  @override
  Widget build(BuildContext context) {
    return AnchoredPickerContent(
      queryKey: const ValueKey('topic-list-tag-filter-query'),
      queryController: _query,
      queryHint: 'Search tags…',
      onQueryChanged: _changed,
      onQuerySubmitted: (_) => _submitQuery(),
      separatorKey: const ValueKey('topic-list-tag-filter-divider'),
      children: [
        AnchoredPickerOption(
          key: const ValueKey('topic-list-tag-filter-all'),
          selected: widget.selectedTagName == null,
          showSelectionIndicator: true,
          leading: const DIcon(DIcons.tag, size: 16),
          title: const Text('All tags'),
          onTap: () => widget.onSelected(''),
        ),
        if (_loading)
          const AnchoredPickerProgress()
        else ...[
          for (final tag in _results)
            AnchoredPickerOption(
              key: ValueKey(('topic-list-tag-filter-option', tag.value)),
              selected: _sameTag(tag, widget.selectedTagName),
              showSelectionIndicator: true,
              leading: const DIcon(DIcons.tag, size: 16),
              title: Text(tag.label),
              onTap: () => widget.onSelected(tag.value),
            ),
          if (_results.isEmpty)
            AnchoredPickerMessage(
              _query.text.trim().isEmpty
                  ? 'No tags are available.'
                  : 'No matching tags.',
            ),
        ],
      ],
    );
  }
}

@immutable
class _TagChoice {
  const _TagChoice({required this.value, required this.label});

  final String value;
  final String label;
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

bool _sameTag(_TagChoice choice, String? selected) {
  if (selected == null) return false;
  final folded = selected.toLowerCase();
  return choice.value.toLowerCase() == folded ||
      choice.label.toLowerCase() == folded;
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
