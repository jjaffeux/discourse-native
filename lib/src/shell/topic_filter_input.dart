import 'dart:async';

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
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

  @override
  State<TopicFilterInput> createState() => _TopicFilterInputState();
}

class _TopicFilterInputState extends State<TopicFilterInput> {
  final OverlayPortalController _portal = OverlayPortalController();
  final GlobalKey _anchorKey = GlobalKey();
  final ValueNotifier<Rect?> _anchor = ValueNotifier(null);
  final FocusNode _focus = FocusNode();

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
    if (!mounted) return;
    if (filter.isOpen) {
      _anchor.value = _anchorRect();
      _portal.show();
    } else {
      _portal.hide();
    }
  }

  Rect? _anchorRect() => anchorRect(
    anchor: _anchorKey.currentContext?.findRenderObject() as RenderBox?,
    overlay: Overlay.of(context).context.findRenderObject() as RenderBox?,
  );

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown when filter.isOpen:
        filter.moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp when filter.isOpen:
        filter.moveSelection(-1);
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
    _anchor.dispose();
    super.dispose();
  }

  Widget _buildPlainInput(ThemeData theme) {
    final controlHeight = DButton.iconOnlyDimensionFor(DButtonSize.small);
    return SizedBox(
      height: controlHeight,
      child: TextField(
        key: widget.inputKey,
        controller: filter.text,
        focusNode: _focus,
        enabled: widget.enabled,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.shell.content,
          hintText: widget.hintText,
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          suffixIcon: filter.text.text.isEmpty
              ? null
              : DTooltip(
                  message: 'Clear filter',
                  labelTrigger: true,
                  child: DButton.iconOnly(
                    key: widget.clearKey,
                    tooltip: 'Clear all filters',
                    variant: DButtonVariant.ghost,
                    size: DButtonSize.small,
                    onPressed: widget.enabled
                        ? () => unawaited(filter.clear())
                        : null,
                    icon: DIcon(
                      DIcons.xmark,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
          border: _plainInputBorder(theme),
          enabledBorder: _plainInputBorder(theme),
          focusedBorder: _plainInputBorder(
            theme,
            focused: DFocusHighlight.visibleOf(context),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
        ),
        onChanged: filter.inputChanged,
        onTap: _openSuggestions,
        onTapOutside: (_) => _dismissInput(),
      ),
    );
  }

  static OutlineInputBorder _plainInputBorder(
    ThemeData theme, {
    bool focused = false,
  }) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(
      color: focused ? theme.colorScheme.primary : theme.shell.divider,
      width: focused ? 1.5 : 1,
    ),
  );

  Widget _buildTokenInput(ThemeData theme) {
    final hasQuery = _tokens.isNotEmpty || filter.text.text.trim().isNotEmpty;
    final borderColor = _focus.hasFocus
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return TextFieldTapRegion(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? _focus.requestFocus : null,
        child: Container(
          key: const ValueKey('topic-filter-token-field'),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          decoration: BoxDecoration(
            color: theme.shell.content,
            borderRadius: BorderRadius.circular(7),
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: borderColor,
              width: _focus.hasFocus ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final hint = _tokens.isEmpty
                        ? widget.hintText
                        : 'Add another filter';
                    final measure = TextPainter(
                      text: TextSpan(
                        text: filter.text.text.isEmpty
                            ? hint
                            : filter.text.text,
                        style: theme.textTheme.bodyMedium,
                      ),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final desiredWidth = measure.width + 20;
                    measure.dispose();
                    final inputWidth = _tokens.isEmpty
                        ? constraints.maxWidth
                        : (desiredWidth < 160 ? 160.0 : desiredWidth).clamp(
                            0.0,
                            constraints.maxWidth,
                          );
                    return Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (var index = 0; index < _tokens.length; index++)
                          _TopicFilterTokenChip(
                            raw: _tokens[index],
                            index: index,
                            categories: widget.categories,
                            enabled: widget.enabled,
                            onDeleted: () => _removeToken(index),
                          ),
                        SizedBox(
                          width: inputWidth,
                          child: TextField(
                            style: theme.textTheme.bodyMedium,
                            key: widget.inputKey,
                            controller: filter.text,
                            focusNode: _focus,
                            enabled: widget.enabled,
                            autocorrect: false,
                            enableSuggestions: false,
                            maxLines: 1,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              hintText: hint,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 4,
                              ),
                            ),
                            onChanged: filter.inputChanged,
                            onSubmitted: (_) => _commitTokenDraft(),
                            onTap: _openSuggestions,
                            onTapOutside: (_) => _dismissInput(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              if (hasQuery)
                DButton.iconOnly(
                  key: widget.clearKey,
                  onPressed: widget.enabled
                      ? () => unawaited(_clearTokenQuery())
                      : null,
                  variant: DButtonVariant.ghost,
                  tooltip: 'Clear all filters',
                  icon: const DIcon(DIcons.xmark),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSuggestions() {
    if (!filter.menuRequested) unawaited(filter.openSuggestions());
  }

  void _dismissInput() {
    filter.dismiss();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: widget.padding,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKey,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => ValueListenableBuilder<Rect?>(
            valueListenable: _anchor,
            builder: (context, anchor, child) => CustomSingleChildLayout(
              delegate: AnchoredLayout(
                anchor: anchor,
                maxWidth: anchor?.width ?? 720,
                preferAbove: widget.preferSuggestionsAbove,
                keepPreferredPlacement: widget.preferSuggestionsAbove,
              ),
              child: child!,
            ),
            child: TextFieldTapRegion(
              child: _SuggestionList(
                siteUrl: widget.siteUrl,
                filter: filter,
                onAccept: _acceptSuggestion,
              ),
            ),
          ),
          child: KeyedSubtree(
            key: _anchorKey,
            child: widget.tokenized
                ? _buildTokenInput(theme)
                : _buildPlainInput(theme),
          ),
        ),
      ),
    );
  }
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
    final theme = Theme.of(context);
    final label = _topicFilterTokenLabel(raw, categories);
    final foreground = theme.colorScheme.onPrimaryContainer;
    return DTooltip(
      message: raw,
      child: Material(
        key: ValueKey('topic-filter-token-$index'),
        color: enabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.38),
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 28,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Remove $label',
                child: DTooltip(
                  message: 'Remove $label',
                  child: InkWell(
                    key: ValueKey('topic-filter-token-remove-$index'),
                    onTap: enabled ? onDeleted : null,
                    child: SizedBox(
                      width: 26,
                      height: 28,
                      child: Center(
                        child: DIcon(DIcons.xmark, size: 10, color: foreground),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.siteUrl,
    required this.filter,
    required this.onAccept,
  });

  final String siteUrl;
  final TopicFilterController filter;
  final Future<void> Function(TopicFilterSuggestion suggestion) onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: filter,
      builder: (context, _) {
        if (!filter.isOpen) return const SizedBox.shrink();
        return Material(
          key: const ValueKey('topic-filter-suggestions'),
          color: theme.shell.floating,
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 360),
            decoration: BoxDecoration(
              border: Border.all(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filter.suggestions.length,
              itemBuilder: (context, index) {
                final suggestion = filter.suggestions[index];
                final isSelected = index == filter.selectedIndex;
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  onEnter: (_) => filter.select(index),
                  child: Semantics(
                    button: true,
                    selected: isSelected,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(onAccept(suggestion)),
                      child: Container(
                        key: ValueKey('topic-filter-suggestion-$index'),
                        constraints: const BoxConstraints(minHeight: 44),
                        decoration: BoxDecoration(
                          color: isSelected ? theme.shell.selected : null,
                          border: Border(
                            left: BorderSide(
                              color: isSelected
                                  ? theme.colorScheme.primary
                                  : Colors.transparent,
                              width: 3,
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.fromLTRB(9, 9, 12, 9),
                        child: Row(
                          children: [
                            if (suggestion.category case final category?) ...[
                              CategoryIcon(
                                category: category,
                                parentCategory: suggestion.parentCategory,
                                siteUrl: siteUrl,
                                size: 16,
                                squareSize: 16,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                suggestion.displayName ??
                                    (suggestion.category == null
                                        ? suggestion.name
                                        : suggestion.description ??
                                              suggestion.category!.name),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (suggestion.category == null)
                              if (suggestion.description
                                  case final description?) ...[
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
