import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topic.dart';
import '../models/topic_filter.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'anchored_layout.dart';
import 'hashtag.dart';
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
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 8),
    this.enabled = true,
    this.preferSuggestionsAbove = false,
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
    if (oldWidget.siteUrl != widget.siteUrl) {
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
    if (oldWidget.initialQuery != widget.initialQuery &&
        filter.text.text == oldWidget.initialQuery) {
      filter.text.text = widget.initialQuery;
    }
  }

  void _replaceController(ShellController shell) {
    _filter?.removeListener(_onFilterChanged);
    _filter?.text.removeListener(_onTextChanged);
    _filter?.dispose();
    _shell = shell;
    _filter = TopicFilterController(
      initialQuery: widget.initialQuery,
      submitQuery: widget.onSubmitted,
      engine: _engine(shell),
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
    widget.onChanged?.call(filter.text.text);
    if (mounted) setState(() {});
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
          filter.ensureFreshSuggestions().then((_) => filter.acceptSelected()),
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (filter.isOpen) {
          unawaited(
            filter.ensureFreshSuggestions().then(
              (_) => filter.acceptSelected(),
            ),
          );
        } else {
          unawaited(filter.submit());
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
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
              ),
              child: child!,
            ),
            child: TextFieldTapRegion(child: _SuggestionList(filter: filter)),
          ),
          child: KeyedSubtree(
            key: _anchorKey,
            child: TextField(
              key: widget.inputKey,
              controller: filter.text,
              focusNode: _focus,
              enabled: widget.enabled,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.hintText,
                prefixIcon: const Padding(
                  padding: EdgeInsets.all(12),
                  child: DIcon(DIcons.filter, size: 17),
                ),
                suffixIcon: filter.text.text.isEmpty
                    ? null
                    : IconButton(
                        key: widget.clearKey,
                        tooltip: 'Clear filter',
                        onPressed: widget.enabled
                            ? () => unawaited(filter.clear())
                            : null,
                        icon: const DIcon(DIcons.xmark, size: 17),
                      ),
                filled: true,
                fillColor: theme.shell.content,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: filter.inputChanged,
              onTap: () {
                if (!filter.menuRequested) {
                  unawaited(filter.openSuggestions());
                }
              },
              onTapOutside: (_) {
                filter.dismiss();
                _focus.unfocus();
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.filter});

  final TopicFilterController filter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: filter,
      builder: (context, _) {
        if (!filter.isOpen) return const SizedBox.shrink();
        return Material(
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
                      onTap: () => unawaited(filter.accept(suggestion)),
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
                              CategorySquare(
                                color: Color(category.colorValue),
                                parentColor: suggestion.parentCategory == null
                                    ? null
                                    : Color(
                                        suggestion.parentCategory!.colorValue,
                                      ),
                                size: 16,
                              ),
                              const SizedBox(width: 10),
                            ],
                            Flexible(
                              child: Text(
                                suggestion.category == null
                                    ? suggestion.name
                                    : suggestion.description ??
                                          suggestion.category!.name,
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
