import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../foundation/latest_wins_queued_lookup_controller.dart';
import '../models/topic.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'topic_taxonomy_button.dart';

/// The tag button and searchable dropdown shared by filters and editors.
///
/// Selection is controlled by the caller. Known tags provide filter fallbacks;
/// editors supply category-scoped search and creation/limit capabilities.
/// Closing or removing the selector retires pending searches.
class TopicTagSelector extends StatefulWidget {
  const TopicTagSelector({
    super.key,
    required this.selectedTags,
    required this.search,
    required this.onChanged,
    this.knownTags = const [],
    this.capabilities = const TopicComposerCapabilities(),
    this.multiple = true,
    this.includeAll = false,
    this.placeholder = 'Tags',
    this.semanticLabel,
    this.keyPrefix = 'tag-selector',
    this.size = DButtonSize.regular,
    this.valueKey,
  });

  final List<TopicTag> selectedTags;
  final Future<TopicTagSearch> Function(String query) search;
  final ValueChanged<List<TopicTag>>? onChanged;
  final List<TopicTag> knownTags;
  final TopicComposerCapabilities capabilities;
  final bool multiple;
  final bool includeAll;
  final String placeholder;
  final String? semanticLabel;
  final String keyPrefix;
  final DButtonSize size;
  final Key? valueKey;

  @override
  State<TopicTagSelector> createState() => _TopicTagSelectorState();
}

class _TopicTagSelectorState extends State<TopicTagSelector> {
  static const _all = TopicTag(name: '');
  final _combobox = DComboboxController<TopicTag>();
  late final _lookup = LatestWinsQueuedLookupController<String, TopicTagSearch>(
    lookup: _search,
    onResult: _received,
    onError: (_, _) => _received(
      widget.includeAll
          ? TopicTagSearch(tags: _knownMatches(_query))
          : const TopicTagSearch(forbiddenMessage: "Couldn't load tags."),
    ),
  );
  Timer? _debounce;
  String _query = '';
  TopicTagSearch _result = const TopicTagSearch();
  bool _loading = false;

  List<TopicTag> _knownMatches(String term) {
    final query = term.trim().toLowerCase();
    return widget.knownTags
        .where(
          (tag) =>
              tag.name.toLowerCase().contains(query) ||
              (tag.slug?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
  }

  Future<TopicTagSearch> _search(String query) async {
    final known = _knownMatches(query);
    final result = await widget.search(query.trim());
    final byName = <String, TopicTag>{};
    for (final tag in [...known, ...result.results]) {
      byName.putIfAbsent(tag.name.toLowerCase(), () => tag);
    }
    return TopicTagSearch(
      tags: List.unmodifiable(byName.values),
      forbidden: result.forbidden,
      forbiddenMessage: result.forbiddenMessage,
    );
  }

  void _received(TopicTagSearch result) {
    setState(() {
      _result = result;
      _loading = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          _combobox.isOpen &&
          !_loading &&
          identical(_result, result)) {
        _combobox.highlight(
          _newTag ?? _visibleResults.where(_enabled).firstOrNull,
        );
      }
    });
  }

  void _openChanged(bool open, DComboboxChangeReason _) {
    _debounce?.cancel();
    _lookup.invalidate();
    setState(() {
      _query = '';
      _result = const TopicTagSearch();
      _loading = open;
    });
    if (open) _lookup.request('');
  }

  void _queryChanged(String query, DComboboxChangeReason reason) {
    if (reason != DComboboxChangeReason.input) return;
    _debounce?.cancel();
    _lookup.invalidate();
    _combobox.highlight(null);
    setState(() {
      _query = query;
      _result = const TopicTagSearch();
      _loading = true;
    });
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _lookup.request(query),
    );
  }

  bool _sameTag(TopicTag left, TopicTag right) =>
      left.id != null && right.id != null
      ? left.id == right.id
      : left.name.toLowerCase() == right.name.toLowerCase();

  bool _selected(TopicTag tag) =>
      widget.selectedTags.any((selected) => _sameTag(selected, tag));

  bool get _atMaximum {
    final maximum = widget.capabilities.maxTagsPerTopic;
    return maximum != null && widget.selectedTags.length >= maximum;
  }

  bool _enabled(TopicTag tag) =>
      !tag.disabled && (_selected(tag) || !_atMaximum);

  List<TopicTag> get _visibleResults {
    if (_loading) return const [];
    final seen = <String>{};
    return [
      for (final tag in [
        if (!widget.includeAll)
          ...widget.selectedTags.where(
            (tag) =>
                tag.name.toLowerCase().contains(_query.trim().toLowerCase()),
          ),
        ..._result.results,
      ])
        if (seen.add(tag.name.toLowerCase())) tag,
    ];
  }

  TopicTag? get _newTag {
    final name = _query.trim();
    if (_loading ||
        _result.isForbidden ||
        _result.explanation != null ||
        _atMaximum ||
        !widget.capabilities.canCreateTagNamed(name) ||
        [
          ...widget.selectedTags,
          ..._result.results,
        ].any((tag) => tag.name.toLowerCase() == name.toLowerCase())) {
      return null;
    }
    return TopicTag(name: name);
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
    final selected = widget.selectedTags;
    final label = selected.length > 1
        ? 'Tags · ${selected.length}'
        : selected.firstOrNull?.name ?? widget.placeholder;
    final prefix = widget.keyPrefix;
    final newTag = _newTag;
    final options = [
      if (widget.includeAll)
        DComboboxOption(
          value: _all,
          label: 'All tags',
          itemKey: ValueKey('$prefix-all'),
        ),
      if (newTag != null)
        DComboboxOption(
          value: newTag,
          label: 'Create new tag: “${newTag.name}”',
          itemKey: ValueKey('$prefix-create'),
        ),
      for (final tag in _visibleResults)
        DComboboxOption(
          value: tag,
          label: tag.name,
          enabled: _enabled(tag),
          itemKey: ValueKey((
            '$prefix-option',
            widget.multiple ? tag.name : tag.slug ?? tag.name,
          )),
        ),
    ];
    final anchor = DComboboxTrigger<TopicTag>(
      builder: (context, trigger) => TopicTaxonomyButton(
        buttonKey: widget.valueKey,
        size: widget.size,
        label: label,
        icon: const DIcon(DIcons.tag, size: 14),
        semanticLabel:
            widget.semanticLabel ??
            (selected.isEmpty
                ? widget.placeholder
                : 'Tags: ${selected.map((tag) => tag.name).join(', ')}'),
        onPressed: widget.onChanged == null ? null : trigger.toggle,
        focusNode: trigger.focusNode,
        expanded: trigger.open,
        maximumWidth: 210,
      ),
    );
    final content = DComboboxContent(
      key: ValueKey('$prefix-popover'),
      semanticLabel: 'Tags',
      width: 280,
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: DComboboxInput<TopicTag>(
            key: ValueKey('$prefix-query'),
            placeholder: 'Search tags…',
            semanticLabel: 'Search tags',
            registerAsAnchor: false,
            showTrigger: false,
          ),
        ),
        DComboboxList<TopicTag>(
          itemBuilder: (context, option) => Row(
            children: [
              DIcon(
                identical(option.value, newTag) ? DIcons.plus : DIcons.tag,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.label),
                    if (option.value.disabledReason case final reason?)
                      Text(
                        reason,
                        style: TextStyle(
                          color: DTokens.of(context).mutedForeground,
                        ),
                      ),
                  ],
                ),
              ),
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
        else if (_result.explanation != null ||
            _visibleResults.isEmpty && newTag == null)
          DComboboxStatus(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _result.explanation ??
                    (_query.trim().isEmpty
                        ? 'No tags are available.'
                        : 'No matching tags.'),
              ),
            ),
          ),
      ],
    );
    if (widget.multiple) {
      return DCombobox<TopicTag>.multipleControlled(
        controller: _combobox,
        value: selected.isEmpty && widget.includeAll ? const [_all] : selected,
        options: options,
        enabled: widget.onChanged != null,
        equals: _sameTag,
        query: _query,
        filterLocally: false,
        onQueryChanged: _queryChanged,
        onOpenChanged: _openChanged,
        onValuesChanged: (tags, _) {
          final clear = tags.contains(_all) && selected.isNotEmpty;
          if (_loading && !clear) return;
          widget.onChanged?.call(
            clear ? const [] : tags.where((tag) => tag != _all).toList(),
          );
        },
        anchor: anchor,
        content: content,
      );
    }
    return DCombobox<TopicTag>.controlled(
      controller: _combobox,
      value: selected.firstOrNull ?? (widget.includeAll ? _all : null),
      options: options,
      enabled: widget.onChanged != null,
      equals: _sameTag,
      query: _query,
      filterLocally: false,
      onQueryChanged: _queryChanged,
      onOpenChanged: _openChanged,
      onChanged: (tag, _) {
        if (_loading && tag != _all) return;
        if (tag == _all || tag == null) {
          if (selected.isNotEmpty) widget.onChanged?.call(const []);
        } else if (!_selected(tag)) {
          widget.onChanged?.call([tag]);
        }
      },
      anchor: anchor,
      content: content,
    );
  }
}
