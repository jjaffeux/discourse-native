import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'topic_taxonomy_button.dart';

/// The category button and searchable dropdown shared by filters and editors.
///
/// A null [search] filters [categories] locally. An asynchronous search owns its
/// permissions and data source; obsolete results are ignored on close/disposal.
/// [includeAll] exposes a null selection for list filtering.
/// [clearSelectionLabel] exposes the same null selection with authoring copy,
/// such as "No subcategory" when the caller restores the parent category.
class TopicCategorySelector extends StatefulWidget {
  const TopicCategorySelector({
    super.key,
    required this.siteUrl,
    required this.categories,
    required this.selected,
    required this.onSelected,
    this.search,
    this.labelFor,
    this.parent,
    this.includeAll = false,
    this.clearSelectionLabel,
    this.placeholder = 'Categories',
    this.keyPrefix = 'category-selector',
    this.valueKey,
    this.triggerBuilder,
  });

  final String siteUrl;
  final List<TopicCategory> categories;
  final TopicCategory? selected;
  final ValueChanged<TopicCategory?>? onSelected;
  final Future<List<TopicCategory>> Function(String query)? search;
  final String Function(TopicCategory category)? labelFor;
  final TopicCategory? parent;
  final bool includeAll;
  final String? clearSelectionLabel;
  final String placeholder;
  final String keyPrefix;
  final Key? valueKey;

  /// Reuses the selector popup with a caller's Native trigger composition.
  final DComboboxTriggerBuilder<int>? triggerBuilder;

  @override
  State<TopicCategorySelector> createState() => _TopicCategorySelectorState();
}

class _TopicCategorySelectorState extends State<TopicCategorySelector> {
  final _combobox = DComboboxController<int>();
  late final _lookup =
      LatestWinsQueuedLookupController<String, List<TopicCategory>>(
        lookup: (query) => widget.search!(query.trim()),
        onResult: _received,
        onError: (_, _) {
          setState(() {
            _results = const [];
            _loading = false;
            _error = "Couldn't load categories.";
          });
        },
      );
  Timer? _debounce;
  String _query = '';
  List<TopicCategory> _results = const [];
  bool _loading = false;
  String? _error;

  String _label(TopicCategory category) =>
      widget.labelFor?.call(category) ?? category.name;

  bool get _canClear => widget.includeAll || widget.clearSelectionLabel != null;

  List<TopicCategory> get _matches => widget.search != null
      ? _results
      : widget.categories
            .where(
              (category) => _label(
                category,
              ).toLowerCase().contains(_query.trim().toLowerCase()),
            )
            .toList(growable: false);

  void _highlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_combobox.isOpen || _loading) return;
      final selected = widget.selected?.id;
      _combobox.highlight(
        _query.trim().isEmpty &&
                (selected == null && _canClear ||
                    _matches.any((category) => category.id == selected))
            ? selected ?? 0
            : _matches.firstOrNull?.id,
      );
    });
  }

  void _received(List<TopicCategory> categories) {
    setState(() {
      _results = categories;
      _loading = false;
    });
    _highlight();
  }

  void _openChanged(bool open, DComboboxChangeReason _) {
    _debounce?.cancel();
    _lookup.invalidate();
    setState(() {
      _query = '';
      _results = const [];
      _error = null;
      _loading = open && widget.search != null;
    });
    if (!open) return;
    if (widget.search != null) {
      _lookup.request('');
    } else {
      _highlight();
    }
  }

  void _queryChanged(String query, DComboboxChangeReason reason) {
    if (reason != DComboboxChangeReason.input) return;
    _debounce?.cancel();
    _lookup.invalidate();
    _combobox.highlight(null);
    setState(() {
      _query = query;
      _results = const [];
      _error = null;
      _loading = widget.search != null;
    });
    if (widget.search != null) {
      _debounce = Timer(
        const Duration(milliseconds: 250),
        () => _lookup.request(query),
      );
    } else {
      _highlight();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _lookup.dispose();
    _combobox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final parent = widget.parent;
    final noun = parent == null ? 'categories' : 'subcategories';
    final label = selected == null ? widget.placeholder : _label(selected);
    final matches = _matches;
    final prefix = widget.keyPrefix;
    return DCombobox<int>.controlled(
      controller: _combobox,
      value: selected?.id ?? (_canClear ? 0 : null),
      enabled: widget.onSelected != null,
      query: _query,
      filterLocally: false,
      onQueryChanged: _queryChanged,
      onOpenChanged: _openChanged,
      options: [
        if (_canClear)
          DComboboxOption(
            value: 0,
            label: widget.clearSelectionLabel ?? 'All $noun',
            itemKey: ValueKey(('$prefix-option', 0)),
          ),
        for (final category in matches)
          DComboboxOption(
            value: category.id,
            label: _label(category),
            itemKey: ValueKey(('$prefix-option', category.id)),
          ),
      ],
      onChanged: (id, _) {
        if (id == 0 && _canClear) {
          widget.onSelected?.call(null);
        } else if (!_loading && id != null) {
          final category = matches.where((item) => item.id == id).firstOrNull;
          if (category != null) widget.onSelected?.call(category);
        }
      },
      anchor: DComboboxTrigger<int>(
        builder:
            widget.triggerBuilder ??
            (context, trigger) => TopicTaxonomyButton(
              buttonKey: widget.valueKey,
              label: label,
              icon: selected == null
                  ? null
                  : CategoryIcon(
                      key: ValueKey(('$prefix-selected-icon', selected.id)),
                      category: selected,
                      siteUrl: widget.siteUrl,
                      size: 14,
                      squareSize: 10,
                    ),
              semanticLabel: selected == null
                  ? parent == null
                        ? widget.includeAll
                              ? 'Filter by category'
                              : 'Choose category'
                        : widget.includeAll
                        ? 'Filter by subcategory of ${parent.name}'
                        : 'Choose subcategory of ${parent.name}'
                  : '${parent == null ? 'Category' : 'Subcategory'}: $label',
              tooltip: label,
              onPressed: widget.onSelected == null ? null : trigger.toggle,
              focusNode: trigger.focusNode,
              expanded: trigger.open,
              maximumWidth: parent == null ? 260 : 230,
            ),
      ),
      content: DComboboxContent(
        key: ValueKey('$prefix-popover'),
        semanticLabel: parent == null
            ? 'Categories'
            : 'Subcategories of ${parent.name}',
        width: 320,
        children: [
          Padding(
            padding: const EdgeInsets.all(4),
            child: DComboboxInput<int>(
              key: ValueKey('$prefix-query'),
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
                  DIcon(
                    widget.clearSelectionLabel == null
                        ? DIcons.layerGroup
                        : DIcons.xmark,
                    size: 16,
                  )
                else
                  CategoryIcon(
                    key: ValueKey(('category-selector-icon', option.value)),
                    category: matches.firstWhere(
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
          if (_loading)
            const DComboboxStatus(
              child: Padding(
                padding: EdgeInsets.all(8),
                child: DSpinner(semanticLabel: 'Loading categories'),
              ),
            )
          else if (_error != null || matches.isEmpty)
            DComboboxStatus(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_error ?? 'No matching $noun.'),
              ),
            ),
        ],
      ),
    );
  }
}
