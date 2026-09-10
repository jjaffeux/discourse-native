import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/sidebar_tag.dart';
import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
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

    final controlChildren = <Widget>[
      _CategoryFilterAnchor(
        siteUrl: siteUrl,
        categories: rootCategories,
        selected: rootCategory,
        onSelected: onCategorySelected,
      ),
      if (subcategories.isNotEmpty)
        _CategoryFilterAnchor(
          key: ValueKey(rootCategory!.id),
          siteUrl: siteUrl,
          parent: rootCategory,
          categories: subcategories,
          selected: selectedCategory?.parentCategoryId == null
              ? null
              : selectedCategory,
          onSelected: onCategorySelected,
        ),
      if (taggingEnabled)
        _TagFilterAnchor(
          knownTags: knownTags,
          selectedTagName: selectedTagName,
          selectedTagNames: selectedTagNames,
          onTagsSelected: onTagsSelected,
          search: searchTags,
          onSelected: onTagSelected,
        ),
    ];
    final controls = wrap
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
      child: wrap
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

class _CategoryFilterAnchor extends StatefulWidget {
  const _CategoryFilterAnchor({
    super.key,
    required this.siteUrl,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.parent,
  });

  final String siteUrl;
  final List<TopicCategory> categories;
  final TopicCategory? selected;
  final TopicCategory? parent;
  final ValueChanged<TopicCategory?> onSelected;

  @override
  State<_CategoryFilterAnchor> createState() => _CategoryFilterAnchorState();
}

class _CategoryFilterAnchorState extends State<_CategoryFilterAnchor> {
  final _combobox = DComboboxController<int>();
  String _query = '';

  List<TopicCategory> get _matches => widget.categories
      .where(
        (category) =>
            category.name.toLowerCase().contains(_query.trim().toLowerCase()),
      )
      .toList(growable: false);

  void _highlight(int? value) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _combobox.isOpen) _combobox.highlight(value);
    });
  }

  @override
  void dispose() {
    _combobox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subcategories = widget.parent != null;
    final kind = subcategories ? 'subcategory' : 'category';
    final noun = subcategories ? 'subcategories' : 'categories';
    final selected = widget.selected;
    final matches = _matches;
    return DCombobox<int>.controlled(
      controller: _combobox,
      value: selected?.id ?? 0,
      query: _query,
      filterLocally: false,
      onQueryChanged: (query, _) {
        setState(() => _query = query);
        _highlight(
          query.trim().isEmpty ? selected?.id ?? 0 : _matches.firstOrNull?.id,
        );
      },
      onOpenChanged: (open, _) {
        setState(() => _query = '');
        if (open) _highlight(selected?.id ?? 0);
      },
      options: [
        DComboboxOption(
          value: 0,
          label: 'All $noun',
          itemKey: ValueKey(('topic-list-$kind-option', 0)),
        ),
        for (final category in matches)
          DComboboxOption(
            value: category.id,
            label: category.name,
            itemKey: ValueKey(('topic-list-$kind-option', category.id)),
          ),
      ],
      onChanged: (categoryId, _) => widget.onSelected(
        categoryId == null || categoryId == 0
            ? widget.parent
            : widget.categories.firstWhere(
                (category) => category.id == categoryId,
              ),
      ),
      anchor: DComboboxTrigger<int>(
        builder: (context, trigger) => _FilterButton(
          key: ValueKey('topic-list-$kind-filter'),
          active: selected != null,
          label:
              selected?.name ??
              (subcategories ? 'Subcategories' : 'Categories'),
          icon: selected == null
              ? null
              : CategoryIcon(
                  category: selected,
                  siteUrl: widget.siteUrl,
                  size: 14,
                  squareSize: 10,
                ),
          semanticLabel: selected == null
              ? subcategories
                    ? 'Filter by subcategory of ${widget.parent!.name}'
                    : 'Filter by category'
              : '${subcategories ? 'Subcategory' : 'Category'}: ${selected.name}',
          onPressed: trigger.toggle,
          focusNode: trigger.focusNode,
          expanded: trigger.open,
          maximumWidth: subcategories ? 230 : 260,
        ),
      ),
      content: DComboboxContent(
        key: ValueKey('topic-list-$kind-popover'),
        semanticLabel: subcategories
            ? 'Subcategories of ${widget.parent!.name}'
            : 'Categories',
        width: 320,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: DComboboxInput<int>(
              key: ValueKey('topic-list-$kind-query'),
              placeholder: 'Filter $noun',
              semanticLabel: 'Filter $noun',
              registerAsAnchor: false,
              showTrigger: false,
            ),
          ),
          DComboboxList<int>(
            itemBuilder: (context, option) => Row(
              children: [
                if (option.value == 0)
                  const DIcon(DIcons.layerGroup, size: 16)
                else
                  CategoryIcon(
                    key: ValueKey((
                      'topic-list-category-indicator',
                      option.value,
                    )),
                    category: widget.categories.firstWhere(
                      (category) => category.id == option.value,
                    ),
                    siteUrl: widget.siteUrl,
                    size: 16,
                    squareSize: 10,
                  ),
                const SizedBox(width: 8),
                Expanded(child: Text(option.label)),
              ],
            ),
          ),
          if (matches.isEmpty)
            DComboboxStatus(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('No matching $noun.'),
              ),
            ),
        ],
      ),
    );
  }
}

class _TagFilterAnchor extends StatefulWidget {
  const _TagFilterAnchor({
    required this.knownTags,
    required this.selectedTagName,
    required this.search,
    required this.onSelected,
    this.selectedTagNames,
    this.onTagsSelected,
  });

  final List<String>? selectedTagNames;
  final ValueChanged<List<String>>? onTagsSelected;
  final List<SidebarTag> knownTags;
  final String? selectedTagName;
  final TopicListTagSearch search;
  final ValueChanged<String?> onSelected;

  @override
  State<_TagFilterAnchor> createState() => _TagFilterAnchorState();
}

class _TagFilterAnchorState extends State<_TagFilterAnchor> {
  final _combobox = DComboboxController<String>();
  // Initialize on first use, including for state retained across hot reload.
  late final _lookup =
      LatestWinsQueuedLookupController<String, List<_TagChoice>>(
        lookup: _searchTags,
        onResult: _received,
        onError: (_, _) => _received(_knownChoices(_query)),
      );
  Timer? _debounce;
  String _query = '';
  List<_TagChoice> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
    _combobox.dispose();
    super.dispose();
  }

  void _received(List<_TagChoice> results) {
    setState(() {
      _results = results;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _combobox.isOpen &&
          !_loading &&
          identical(_results, results)) {
        _combobox.highlight(results.firstOrNull?.value);
      }
    });
  }

  void _openChanged(bool open, DComboboxChangeReason reason) {
    _debounce?.cancel();
    _lookup.invalidate();
    setState(() {
      _query = '';
      _results = const [];
      _loading = open;
    });
    if (open) _lookup.request('');
  }

  void _changed(String value, DComboboxChangeReason reason) {
    if (reason != DComboboxChangeReason.input) return;
    _debounce?.cancel();
    _lookup.invalidate();
    _combobox.highlight(null);
    setState(() {
      _query = value;
      _results = const [];
      _loading = true;
    });
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _lookup.request(value),
    );
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
          _TagChoice(
            value: widget.selectedTagNames == null ? tag.slug : tag.name,
            label: tag.name,
          ),
    ];
  }

  bool _sameValue(String left, String right) =>
      (_selectedKnownTag(widget.knownTags, left)?.name ?? left).toLowerCase() ==
      (_selectedKnownTag(widget.knownTags, right)?.name ?? right).toLowerCase();

  @override
  Widget build(BuildContext context) {
    final values = widget.selectedTagNames ?? [?widget.selectedTagName];
    final selected = _selectedKnownTag(widget.knownTags, values.firstOrNull);
    final label = values.length > 1
        ? 'Tags · ${values.length}'
        : selected?.name ?? values.firstOrNull ?? 'Tags';
    final options = [
      const DComboboxOption(
        value: '',
        label: 'All tags',
        itemKey: ValueKey('topic-list-tag-filter-all'),
      ),
      for (final tag in _results)
        DComboboxOption(
          value: tag.value,
          label: tag.label,
          itemKey: ValueKey(('topic-list-tag-filter-option', tag.value)),
        ),
    ];
    final anchor = DComboboxTrigger<String>(
      builder: (context, trigger) => _FilterButton(
        key: const ValueKey('topic-list-tag-filter'),
        active: values.isNotEmpty,
        label: label,
        icon: const DIcon(DIcons.tag, size: 14),
        semanticLabel: values.isEmpty
            ? 'Filter by tag'
            : values.length > 1
            ? 'Filter by tags: ${values.join(', ')}'
            : 'Tag: $label',
        onPressed: trigger.toggle,
        focusNode: trigger.focusNode,
        expanded: trigger.open,
        maximumWidth: 210,
      ),
    );
    final content = DComboboxContent(
      key: const ValueKey('topic-list-tag-filter-popover'),
      semanticLabel: 'Tags',
      width: 280,
      children: [
        const Padding(
          padding: EdgeInsets.all(4),
          child: DComboboxInput<String>(
            key: ValueKey('topic-list-tag-filter-query'),
            placeholder: 'Search tags…',
            semanticLabel: 'Search tags',
            registerAsAnchor: false,
            showTrigger: false,
          ),
        ),
        DComboboxList<String>(
          itemBuilder: (context, option) => Row(
            children: [
              const DIcon(DIcons.tag, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(option.label)),
            ],
          ),
        ),
        if (_loading)
          const DComboboxStatus(
            child: Padding(
              padding: EdgeInsets.all(8),
              child: DSpinner(semanticLabel: 'Loading tags'),
            ),
          )
        else if (_results.isEmpty)
          DComboboxStatus(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _query.trim().isEmpty
                    ? 'No tags are available.'
                    : 'No matching tags.',
              ),
            ),
          ),
      ],
    );
    if (widget.onTagsSelected case final onSelected?) {
      return DCombobox<String>.multipleControlled(
        value: values.isEmpty ? const [''] : values,
        controller: _combobox,
        options: options,
        query: _query,
        equals: _sameValue,
        filterLocally: false,
        onQueryChanged: _changed,
        onOpenChanged: _openChanged,
        onValuesChanged: (next, _) {
          final clear = next.contains('') && values.isNotEmpty;
          if (_loading && !clear && next.any((value) => value.isNotEmpty)) {
            return;
          }
          onSelected(
            clear ? const [] : next.where((value) => value.isNotEmpty).toList(),
          );
        },
        anchor: anchor,
        content: content,
      );
    }
    return DCombobox<String>.controlled(
      value: widget.selectedTagName ?? '',
      controller: _combobox,
      options: options,
      query: _query,
      equals: _sameValue,
      filterLocally: false,
      onQueryChanged: _changed,
      onOpenChanged: _openChanged,
      onChanged: (value, _) {
        if (_loading && value != null && value.isNotEmpty) return;
        final normalized = value == null || value.isEmpty ? null : value;
        if (normalized != widget.selectedTagName) widget.onSelected(normalized);
      },
      anchor: anchor,
      content: content,
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onPressed,
    required this.focusNode,
    required this.expanded,
    required this.maximumWidth,
    this.icon,
    this.active = false,
  });

  final bool active;
  final String label;
  final String semanticLabel;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final bool expanded;
  final double maximumWidth;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maximumWidth),
    child: DButton(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          const DIcon(DIcons.chevronDown, size: 16),
        ],
      ),
      icon: icon,
      semanticLabel: semanticLabel,
      onPressed: onPressed,
      focusNode: focusNode,
      hasPopup: true,
      expanded: expanded,
      alignment: AlignmentDirectional.centerStart,
      variant: active ? DButtonVariant.secondary : DButtonVariant.outline,
    ),
  );
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
