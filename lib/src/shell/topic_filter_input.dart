import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/d_icons.dart';
import 'category_icon.dart';
import 'shell_controller.dart';
import 'shell_scope.dart';
import 'topic_filter_controller.dart';

class TopicFilterInput extends StatefulWidget {
  const TopicFilterInput({
    super.key,
    required this.siteUrl,
    required this.initialQuery,
    required this.options,
    required this.categories,
    required this.onSubmitted,
    this.onChanged,
    this.inputKey = const ValueKey('topic-filter-input'),
    this.clearKey = const ValueKey('clear-topic-filter'),
    this.hintText = 'Filter topics by category, tag, or other criteria',
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.enabled = true,
    this.preferSuggestionsAbove = false,
    this.tokenized = false,
    this.multiline = false,
  });

  final String siteUrl;
  final String initialQuery;
  final List<TopicFilterOption> options;
  final List<TopicCategory> categories;
  final Future<void> Function(String query) onSubmitted;
  final ValueChanged<String>? onChanged;
  final Key inputKey;
  final Key clearKey;
  final String hintText;
  final EdgeInsetsGeometry padding;
  final bool enabled;
  final bool preferSuggestionsAbove;
  final bool tokenized;
  final bool multiline;

  @override
  State<TopicFilterInput> createState() => _TopicFilterInputState();
}

class _TopicFilterInputState extends State<TopicFilterInput> {
  final FocusNode _focus = FocusNode();
  final _combobox = DComboboxController<TopicFilterSuggestion>();

  ShellController? _shell;
  TopicFilterController? _filter;
  List<String> _tokens = const [];
  bool _updatingTokenDraft = false;
  bool _visible = true;
  bool _visibilityDismissScheduled = false;

  TopicFilterController get filter => _filter!;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_filter == null) return;
    if (mounted) setState(() {});
    if (_focus.hasFocus) {
      unawaited(filter.openSuggestions());
    } else {
      filter.dismiss();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = ShellScope.identityOf(context);
    if (!identical(_shell, shell)) _replaceController(shell);
    _visible = Visibility.of(context);
    if (_visible || _visibilityDismissScheduled) return;
    _visibilityDismissScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityDismissScheduled = false;
      if (!mounted || _visible) return;
      filter.dismiss();
      _focus.unfocus();
    });
  }

  @override
  void didUpdateWidget(TopicFilterInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteUrl != widget.siteUrl ||
        oldWidget.tokenized != widget.tokenized) {
      _replaceController(_shell!);
      return;
    }
    filter.updateEngine(_engine(_shell!));
    if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.enabled) {
          return;
        }

        filter.dismiss();
        _focus.unfocus();
      });
    }
    if (oldWidget.initialQuery != widget.initialQuery) {
      if (widget.tokenized) {
        final previous = splitTopicFilterQuery(
          oldWidget.initialQuery,
        ).join(' ');
        if (_composeTokenQuery() == previous) {
          _tokens = splitTopicFilterQuery(widget.initialQuery);
          _setTokenDraft('');
        }
      } else if (filter.text.text == oldWidget.initialQuery) {
        filter.text.text = widget.initialQuery;
      }
    }
  }

  void _replaceController(ShellController shell) {
    _filter?.removeListener(_onFilterChanged);
    _filter?.text.removeListener(_onTextChanged);
    _filter?.dispose();
    _shell = shell;
    _tokens = widget.tokenized
        ? splitTopicFilterQuery(widget.initialQuery)
        : const [];
    _filter = TopicFilterController(
      initialQuery: widget.tokenized ? '' : widget.initialQuery,
      submitQuery: (query) => widget.onSubmitted(
        widget.tokenized ? _composeTokenQuery(query) : query,
      ),
      engine: _engine(shell),
      debounce: widget.tokenized
          ? const Duration(milliseconds: 75)
          : const Duration(milliseconds: 300),
    );
    filter
      ..addListener(_onFilterChanged)
      ..text.addListener(_onTextChanged);
  }

  TopicFilterSuggestions _engine(ShellController shell) =>
      TopicFilterSuggestions(
        options: widget.options,
        categories: widget.categories,
        categoryLookup: (term) =>
            shell.searchFilterCategories(siteUrl: widget.siteUrl, term: term),
        tags: (term) =>
            shell.searchFilterTags(siteUrl: widget.siteUrl, term: term),
        tagGroups: (term) =>
            shell.searchFilterTagGroups(siteUrl: widget.siteUrl, term: term),
        users: (term) =>
            shell.searchFilterUsers(siteUrl: widget.siteUrl, term: term),
        groups: (term) =>
            shell.searchFilterGroups(siteUrl: widget.siteUrl, term: term),
      );

  void _onTextChanged() {
    if (widget.tokenized && !_updatingTokenDraft) {
      _synchronizeTokenDraft();
      return;
    }
    if (_updatingTokenDraft) return;
    widget.onChanged?.call(filter.text.text);
    if (mounted) setState(() {});
  }

  void _synchronizeTokenDraft() {
    final draft = filter.text.text;
    final parsed = splitTopicFilterQuery(draft);
    final endsWithSeparator = topicFilterQueryEndsWithSeparator(draft);
    final completedCount = endsWithSeparator
        ? parsed.length
        : parsed.length > 1
        ? parsed.length - 1
        : 0;

    if (completedCount == 0) {
      if (endsWithSeparator && parsed.isEmpty) _setTokenDraft('');
      widget.onChanged?.call(_composeTokenQuery());
      if (mounted) setState(() {});
      return;
    }

    final completed = parsed.take(completedCount);
    final remaining = endsWithSeparator ? '' : parsed.last;
    if (mounted) {
      setState(() => _tokens = [..._tokens, ...completed]);
    } else {
      _tokens = [..._tokens, ...completed];
    }
    _setTokenDraft(remaining);
    widget.onChanged?.call(_composeTokenQuery());
  }

  String _composeTokenQuery([String? draft]) {
    final currentDraft = (draft ?? filter.text.text).trim();
    return [..._tokens, if (currentDraft.isNotEmpty) currentDraft].join(' ');
  }

  void _setTokenDraft(String value) {
    _updatingTokenDraft = true;
    filter.text.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _updatingTokenDraft = false;
  }

  void _commitTokenDraft() {
    final additions = splitTopicFilterQuery(filter.text.text);
    if (additions.isEmpty) return;
    setState(() => _tokens = [..._tokens, ...additions]);
    _setTokenDraft('');
    widget.onChanged?.call(_composeTokenQuery());
    unawaited(filter.openSuggestions());
  }

  void _removeToken(int index) {
    if (!widget.enabled || index < 0 || index >= _tokens.length) return;
    setState(() => _tokens = [..._tokens]..removeAt(index));
    widget.onChanged?.call(_composeTokenQuery());
    _focus.requestFocus();
    unawaited(filter.openSuggestions());
  }

  Future<void> _clearTokenQuery() async {
    if (!widget.enabled) return;
    setState(() => _tokens = const []);
    _setTokenDraft('');
    widget.onChanged?.call('');
    await widget.onSubmitted('');
    if (mounted && _focus.hasFocus) unawaited(filter.openSuggestions());
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  void _moveSelection(int delta) {
    if (!widget.multiline) {
      filter.moveSelection(delta);
      return;
    }
    if (filter.suggestions.isEmpty) return;
    final index = (filter.selectedIndex + delta).clamp(
      0,
      filter.suggestions.length - 1,
    );
    _combobox.highlight(filter.suggestions[index]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when filter.isOpen:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when filter.isOpen:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape when filter.isOpen:
        filter.dismiss();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab when filter.isOpen:
        unawaited(
          filter.ensureFreshSuggestions().then((_) async {
            if (!mounted) return;
            await _acceptSelectedSuggestion();
          }),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.backspace
          when widget.tokenized &&
              filter.text.text.isEmpty &&
              _tokens.isNotEmpty:
        _removeToken(_tokens.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (widget.multiline) {
          if (HardwareKeyboard.instance.isMetaPressed ||
              HardwareKeyboard.instance.isControlPressed) {
            unawaited(filter.submit());
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        }
        if (filter.isOpen) {
          unawaited(_acceptSelectedOrFallback());
        } else if (widget.tokenized) {
          _commitTokenDraft();
        } else {
          unawaited(filter.submit());
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _acceptSelectedOrFallback() async {
    await filter.ensureFreshSuggestions();
    if (!mounted) return;
    if (filter.isOpen) {
      await _acceptSelectedSuggestion();
    } else if (widget.tokenized) {
      _commitTokenDraft();
    } else {
      await filter.submit();
    }
  }

  Future<void> _acceptSelectedSuggestion() async {
    final suggestion =
        filter.selected ??
        (filter.suggestions.isEmpty ? null : filter.suggestions.first);
    if (suggestion != null) await _acceptSuggestion(suggestion);
  }

  Future<void> _acceptSuggestion(TopicFilterSuggestion suggestion) async {
    final acceptance = filter.accept(suggestion);
    if (widget.tokenized && _completesClause(suggestion)) {
      _commitTokenDraft();
    }
    await acceptance;
  }

  bool _completesClause(TopicFilterSuggestion suggestion) {
    final replacement = suggestion.name.trimRight();
    if (replacement.isEmpty || replacement.endsWith(':')) return false;
    return !suggestion.delimiters.any(
      (delimiter) =>
          delimiter.name.isNotEmpty && replacement.endsWith(delimiter.name),
    );
  }

  @override
  void dispose() {
    _filter?.removeListener(_onFilterChanged);
    _filter?.text.removeListener(_onTextChanged);
    _filter?.dispose();
    _focus.removeListener(_onFocusChanged);
    _focus.dispose();
    _combobox.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: widget.padding,
    child: Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: DCombobox<TopicFilterSuggestion>.controlled(
        controller: _combobox,
        value: null,
        options: [
          for (var i = 0; i < filter.suggestions.length; i++)
            DComboboxOption(
              value: filter.suggestions[i],
              label: filter.suggestions[i].name,
              itemKey: ValueKey('topic-filter-suggestion-$i'),
            ),
        ],
        textController: filter.text,
        focusNode: _focus,
        open: filter.isOpen,
        filterLocally: false,
        loopFocus: false,
        restoreFocus: false,
        closeOnSelect: false,
        highlightedValue: filter.selected,
        highlightControlled: true,
        equals: (a, b) => a.name == b.name,
        enabled: widget.enabled,
        onQueryChanged: (query, reason) {
          if (reason == DComboboxChangeReason.input) filter.inputChanged(query);
        },
        onOpenChanged: (open, reason) {
          if (open) {
            if (!filter.menuRequested) unawaited(filter.openSuggestions());
          } else {
            filter.dismiss();
          }
        },
        onHighlightChanged: (value, reason) {
          final index = filter.suggestions.indexWhere(
            (s) => s.name == value?.name,
          );
          if (index >= 0) filter.select(index);
        },
        onChanged: (choice, reason) {
          if (reason == DComboboxChangeReason.clear) {
            unawaited(widget.tokenized ? _clearTokenQuery() : filter.clear());
          } else if (choice != null) {
            if (reason == DComboboxChangeReason.keyboard) {
              unawaited(_acceptSelectedOrFallback());
            } else {
              unawaited(_acceptSuggestion(choice));
            }
          }
        },
        anchor: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.tokenized && _tokens.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  key: const ValueKey('topic-filter-token-field'),
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _tokens.length; i++)
                      _TopicFilterTokenChip(
                        raw: _tokens[i],
                        index: i,
                        categories: widget.categories,
                        enabled: widget.enabled,
                        onDeleted: () => _removeToken(i),
                      ),
                  ],
                ),
              ),
            if (widget.multiline)
              DPopoverAnchor(
                child: DTextarea(
                  key: widget.inputKey,
                  controller: filter.text,
                  focusNode: _focus,
                  semanticLabel: 'Topic filter query',
                  hintText: widget.hintText,
                  minLines: 3,
                  maxLines: 6,
                  enabled: widget.enabled,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: filter.inputChanged,
                ),
              )
            else
              DComboboxInput<TopicFilterSuggestion>(
                key: widget.inputKey,
                semanticLabel: widget.hintText,
                placeholder: widget.hintText,
                showTrigger: false,
                onSubmitted: (_) => unawaited(_acceptSelectedOrFallback()),
                addons: [
                  if (_tokens.isNotEmpty || filter.text.text.isNotEmpty)
                    DInputGroupAddon(
                      alignment: DInputGroupAddonAlignment.inlineEnd,
                      child: DButton.iconOnly(
                        key: widget.clearKey,
                        tooltip: 'Clear all filters',
                        icon: const DIcon(DIcons.xmark),
                        variant: DButtonVariant.transparentBackground,
                        size: DButtonSize.small,
                        onPressed: widget.enabled
                            ? () => unawaited(
                                widget.tokenized
                                    ? _clearTokenQuery()
                                    : filter.clear(),
                              )
                            : null,
                      ),
                    ),
                ],
              ),
          ],
        ),
        content: DComboboxContent(
          key: const ValueKey('topic-filter-suggestions'),
          semanticLabel: 'Filter suggestions',
          side: widget.preferSuggestionsAbove
              ? DPopoverSide.top
              : DPopoverSide.bottom,
          maxHeight: 360,
          children: [
            DComboboxList<TopicFilterSuggestion>(
              itemBuilder: (context, option) {
                final suggestion = option.value;
                return Row(
                  children: [
                    if (suggestion.category case final category?) ...[
                      CategoryIcon(
                        category: category,
                        parentCategory: suggestion.parentCategory,
                        siteUrl: widget.siteUrl,
                        size: 16,
                        squareSize: 12,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.displayName ??
                                (suggestion.category == null
                                    ? suggestion.name
                                    : suggestion.description ??
                                          suggestion.name),
                          ),
                          if (suggestion.category == null &&
                              suggestion.description != null)
                            Text(
                              suggestion.description!,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: DTokens.of(context).mutedForeground,
                                  ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _TopicFilterTokenChip extends StatelessWidget {
  const _TopicFilterTokenChip({
    required this.raw,
    required this.index,
    required this.categories,
    required this.enabled,
    required this.onDeleted,
  });

  final String raw;
  final int index;
  final List<TopicCategory> categories;
  final bool enabled;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final label = _topicFilterTokenLabel(raw, categories);
    return DTooltip(
      message: raw,
      child: DBadge(
        key: ValueKey('topic-filter-token-$index'),
        variant: DBadgeVariant.secondary,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            DButton.iconOnly(
              key: ValueKey('topic-filter-token-remove-$index'),
              icon: const DIcon(DIcons.xmark),
              tooltip: 'Remove $label',
              size: DButtonSize.small,
              variant: DButtonVariant.transparentBackground,
              onPressed: enabled ? onDeleted : null,
            ),
          ],
        ),
      ),
    );
  }
}

String _topicFilterTokenLabel(String raw, List<TopicCategory> categories) {
  final match = RegExp(r'^(-=|=-|-|=)?([\w-]+):(.*)$').firstMatch(raw);
  if (match == null) return _unquoteTopicFilterValue(raw);

  final prefix = match.group(1) ?? '';
  final name = match.group(2)!;
  final rawValue = _unquoteTopicFilterValue(match.group(3)!);
  final value = name == 'category'
      ? _topicFilterCategoryLabel(rawValue, categories)
      : rawValue;
  final label = '$prefix$name:';
  return value.isEmpty ? label : '$label $value';
}

String _topicFilterCategoryLabel(String value, List<TopicCategory> categories) {
  final slugs = value.split(':');
  final byId = {for (final category in categories) category.id: category};
  for (final category in categories) {
    if (category.slug != slugs.last) continue;
    final path = <TopicCategory>[];
    final visited = <int>{};
    TopicCategory? current = category;
    while (current != null && visited.add(current.id)) {
      path.add(current);
      current = byId[current.parentCategoryId];
    }
    final ordered = path.reversed.toList(growable: false);
    if (ordered.map((item) => item.slug).join(':') == value) {
      return ordered.map((item) => item.name).join(' › ');
    }
  }
  return slugs.map(_titleCaseTopicFilterValue).join(' › ');
}

String _unquoteTopicFilterValue(String value) {
  if (value.length < 2) return value;
  final first = value[0];
  final last = value[value.length - 1];
  return (first == '"' && last == '"') || (first == "'" && last == "'")
      ? value.substring(1, value.length - 1)
      : value;
}

String _sentenceCaseTopicFilterValue(String value) {
  final words = value.replaceAll(RegExp('[_-]+'), ' ').trim();
  if (words.isEmpty) return words;
  return '${words[0].toUpperCase()}${words.substring(1)}';
}

String _titleCaseTopicFilterValue(String value) => value
    .split(RegExp('[_-]+'))
    .where((word) => word.isNotEmpty)
    .map(_sentenceCaseTopicFilterValue)
    .join(' ');
