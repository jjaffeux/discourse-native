import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../models/search_results.dart';
import '../models/topic.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'external_link.dart';
import 'open_link.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';
import 'site_emoji_text.dart';

/// The global forum search input and the result panel anchored to it.
class ForumSearch extends StatefulWidget {
  const ForumSearch({super.key, this.dense = false});

  final bool dense;

  static const Key inputKey = ValueKey('forum-search-input');
  static const Key panelKey = ValueKey('forum-search-panel');

  @override
  State<ForumSearch> createState() => _ForumSearchState();
}

class _ForumSearchState extends State<ForumSearch> {
  static const Duration _secondEnterWindow = Duration(seconds: 15);

  final Object _field = Object();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'forum search');
  final MenuController _menu = MenuController();
  ShellSearchController? _search;
  VoidCallback? _unregisterFocus;
  DateTime? _lastEnterAt;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = ShellScope.read(context).search;
    if (identical(_search, next)) return;
    _detach();
    _search = next;
    next.addListener(_searchChanged);
    _unregisterFocus = next.registerFocus(_field, _requestFocus);
    _syncText();
  }

  void _detach() {
    _search?.removeListener(_searchChanged);
    _unregisterFocus?.call();
    _unregisterFocus = null;
  }

  @override
  void dispose() {
    _detach();
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  void _requestFocus() {
    if (!mounted) return;
    _focus.requestFocus();
    _search?.activateField(_field);
  }

  void _focusChanged() {
    if (_focus.hasFocus) _search?.activateField(_field);
  }

  void _searchChanged() {
    if (!mounted) return;
    _syncText();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncMenu());
  }

  void _syncText() {
    final query = _search?.query ?? '';
    if (_text.text == query) return;
    _text.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _syncMenu() {
    if (!mounted) return;
    final search = _search;
    final shouldOpen =
        search != null && search.panelOpen && search.ownsPanel(_field);
    if (shouldOpen && !_menu.isOpen) {
      _menu.open();
    } else if (!shouldOpen && _menu.isOpen) {
      _menu.close();
    }
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final search = _search;
    if (search == null) return KeyEventResult.ignored;

    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      search.closePanel();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      return search.panelOpen && search.moveSelection(1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      return search.panelOpen && search.moveSelection(-1)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
      if (!_focus.hasFocus) return KeyEventResult.ignored;
      _submitFromField(
        forceFullSearch:
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed,
      );
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submitFromField({bool forceFullSearch = false}) {
    final search = _search;
    if (search == null) return;
    if (search.selectedSuggestion case final suggestion?) {
      search.acceptSuggestion(suggestion);
      return;
    }
    if (search.selectedResult case final result?) {
      if (forceFullSearch) {
        _openResultExternally(result);
      } else {
        _openResult(result);
      }
      return;
    } else if (search.moreActionSelected) {
      _openFullSearch();
      return;
    } else if (forceFullSearch) {
      _lastEnterAt = DateTime.now();
      _openFullSearch();
      return;
    } else if (search.mode == SearchMode.facets) {
      search.showTopics();
    } else {
      final now = DateTime.now();
      final recentEnter =
          _lastEnterAt != null &&
          now.difference(_lastEnterAt!) < _secondEnterWindow;
      _lastEnterAt = now;
      if (recentEnter) {
        _openFullSearch();
      } else {
        search.refreshTopics();
      }
      return;
    }

    // Core's second-Enter window belongs only to Enter handled by the input.
    // Activating a selected assistant/result row is a different key target.
    _lastEnterAt = DateTime.now();
  }

  void _openResult(SearchResult result) {
    _search?.recordSelection(result);
    if (result case final SearchPostHit hit) {
      ShellScope.read(context).openSearchResult(hit);
      return;
    }

    final siteUrl = _search?.siteUrl;
    _search?.clear();
    unawaited(
      openLink(
        context,
        result.path,
        title: _resultTitle(result),
        siteUrl: siteUrl,
      ),
    );
  }

  void _openResultExternally(SearchResult result) {
    final search = _search;
    final siteUrl = search?.siteUrl;
    if (search == null || siteUrl == null) return;
    search.recordSelection(result);
    final url = ShellScope.read(
      context,
    ).absoluteUrl(result.path, siteUrl: siteUrl);
    search.closePanel();
    _focus.unfocus();
    unawaited(openExternalLink(url));
  }

  void _openFullSearch({bool expanded = false}) {
    final search = _search;
    final siteUrl = search?.siteUrl;
    if (search == null || siteUrl == null) return;
    final parameters = <String, String>{
      if (search.query.trim().isNotEmpty) 'q': search.query.trim(),
      if (expanded) 'expanded': 'true',
    };
    final path = Uri(path: '/search', queryParameters: parameters).toString();
    search.closePanel();
    _focus.unfocus();
    unawaited(openLink(context, path, title: 'Search', siteUrl: siteUrl));
  }

  @override
  Widget build(BuildContext context) {
    final search = _search!;
    if (search.siteUrl == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final shortcut = defaultTargetPlatform == TargetPlatform.macOS
        ? '⌘K'
        : 'Ctrl K';

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchorWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 420.0;
        final panelWidth = anchorWidth.clamp(280.0, 520.0);
        final showLeadingIcon = anchorWidth >= 140;
        final showShortcut = anchorWidth >= 180;
        // Header actions may legitimately squeeze the field down to a compact
        // text-only affordance. Keep the field usable there, then add one or
        // both trailing actions only when their fixed 44px targets fit.
        final showClear = search.query.isNotEmpty && anchorWidth >= 64;
        final showAdvanced = search.query.isEmpty
            ? anchorWidth >= 72
            : anchorWidth >= 112;

        return MenuAnchor(
          controller: _menu,
          alignmentOffset: const Offset(0, 6),
          onClose: () {
            _focus.unfocus();
            if (search.panelOpen && search.ownsPanel(_field)) {
              search.closePanel();
            }
          },
          style: const MenuStyle(
            backgroundColor: WidgetStatePropertyAll(Colors.transparent),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            shadowColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(0),
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            side: WidgetStatePropertyAll(BorderSide.none),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder()),
          ),
          menuChildren: [
            SizedBox(
              width: panelWidth,
              child: _SearchPanel(
                search: search,
                onOpen: _openResult,
                onFullSearch: _openFullSearch,
              ),
            ),
          ],
          builder: (context, menu, child) => Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _handleKey,
            child: Semantics(
              textField: true,
              label: 'Search this forum',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _requestFocus();
                  search.openPanel();
                },
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: search.query.isEmpty ? (widget.dense ? 5 : 8) : 0,
                  ),
                  decoration: BoxDecoration(
                    color: theme.shell.floating,
                    border: Border.all(color: theme.shell.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      if (showLeadingIcon) ...[
                        const DIcon(DIcons.magnifyingGlass, size: 15),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            if (search.query.isEmpty)
                              IgnorePointer(
                                child: Text(
                                  'Search this forum',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      (widget.dense
                                              ? theme.textTheme.bodySmall
                                              : theme.textTheme.bodyMedium)
                                          ?.copyWith(
                                            color: theme
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                ),
                              ),
                            EditableText(
                              key: ForumSearch.inputKey,
                              controller: _text,
                              focusNode: _focus,
                              style:
                                  (widget.dense
                                      ? theme.textTheme.bodySmall
                                      : theme.textTheme.bodyMedium) ??
                                  const TextStyle(),
                              cursorColor: theme.colorScheme.primary,
                              backgroundCursorColor: Colors.transparent,
                              selectionColor: theme.colorScheme.primary
                                  .withValues(alpha: 0.28),
                              maxLines: 1,
                              textInputAction: TextInputAction.search,
                              onChanged: search.setQuery,
                              onSubmitted: (_) => _submitFromField(),
                            ),
                          ],
                        ),
                      ),
                      if (search.query.isEmpty && showShortcut)
                        Tooltip(
                          message: shortcut,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              shortcut,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      if (showClear)
                        IconButton(
                          key: const ValueKey('forum-search-clear'),
                          tooltip: 'Clear search',
                          onPressed: () {
                            search.clearQuery();
                            _focus.requestFocus();
                            search.activateField(_field);
                          },
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          style: const ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const DIcon(DIcons.xmark, size: 14),
                        ),
                      if (showAdvanced)
                        IconButton(
                          key: const ValueKey('forum-search-advanced'),
                          tooltip: 'Advanced search',
                          onPressed: () => _openFullSearch(expanded: true),
                          constraints: const BoxConstraints.tightFor(width: 44),
                          style: const ButtonStyle(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const DIcon(DIcons.filter, size: 14),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchPanel extends StatelessWidget {
  const _SearchPanel({
    required this.search,
    required this.onOpen,
    required this.onFullSearch,
  });

  final ShellSearchController search;
  final ValueChanged<SearchResult> onOpen;
  final VoidCallback onFullSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = switch (search.phase) {
      SearchSessionPhase.tooShort => _PanelMessage(
        text: 'Type at least ${search.minimumLength} characters to search.',
      ),
      SearchSessionPhase.waiting || SearchSessionPhase.loading =>
        const _PanelMessage(text: 'Searching…', loading: true),
      SearchSessionPhase.suggestions => _SearchSuggestions(search: search),
      SearchSessionPhase.empty => const _PanelMessage(
        text: 'No results found.',
      ),
      SearchSessionPhase.refused || SearchSessionPhase.failed => _PanelMessage(
        text: search.message ?? "Couldn't search this forum.",
        error: true,
      ),
      SearchSessionPhase.results => _SearchResultSections(
        search: search,
        onOpen: onOpen,
        onFullSearch: onFullSearch,
      ),
      SearchSessionPhase.idle => _SearchInitialOptions(search: search),
    };

    return Material(
      key: ForumSearch.panelKey,
      color: theme.shell.floating,
      elevation: 10,
      clipBehavior: Clip.antiAlias,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: theme.shell.divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: body,
        ),
      ),
    );
  }
}

class _SearchInitialOptions extends StatelessWidget {
  const _SearchInitialOptions({required this.search});

  final ShellSearchController search;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tip = search.quickTip;
    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            key: const ValueKey('forum-search-quick-tip'),
            onTap: tip.clickable ? search.useQuickTip : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      child: Text(
                        tip.label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      tip.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (search.recentSearches.isNotEmpty) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 4, top: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Recent searches',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('forum-search-clear-recent'),
                    tooltip: 'Clear recent searches',
                    onPressed: search.resetRecentSearches,
                    constraints: const BoxConstraints.tightFor(
                      width: 40,
                      height: 40,
                    ),
                    padding: EdgeInsets.zero,
                    icon: const DIcon(DIcons.xmark, size: 13),
                  ),
                ],
              ),
            ),
            for (final recent in search.recentSearches)
              InkWell(
                key: ValueKey('forum-search-recent-$recent'),
                onTap: () => search.useRecentSearch(recent),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      const SizedBox.square(
                        dimension: 30,
                        child: Center(
                          child: DIcon(DIcons.arrowRotateLeft, size: 15),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          recent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SearchSuggestions extends StatelessWidget {
  const _SearchSuggestions({required this.search});

  final ShellSearchController search;

  @override
  Widget build(BuildContext context) {
    if (search.suggestions.isEmpty) {
      return const _PanelMessage(text: 'No suggestions found.');
    }
    return ListView.builder(
      primary: false,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: search.suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = search.suggestions[index];
        final selected = search.selectedSuggestionIndex == index;
        return _CompactSuggestionRow(
          suggestion: suggestion,
          selected: selected,
          onFocus: () => search.selectSuggestion(index),
          onTap: () => search.acceptSuggestion(suggestion),
        );
      },
    );
  }
}

class _CompactSuggestionRow extends StatelessWidget {
  const _CompactSuggestionRow({
    required this.suggestion,
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchSuggestion suggestion;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: [suggestion.label, ?suggestion.detail].join(', '),
      child: InkWell(
        key: ValueKey(
          'search-suggestion-${suggestion.kind.name}-${suggestion.completion}',
        ),
        hoverColor: theme.shell.hover,
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: Ink(
          color: selected ? theme.shell.selected : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 30,
                  child: Center(child: _SuggestionLeading(suggestion)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.discourse.primaryHigh,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (suggestion.detail case final detail?)
                        Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.discourse.primaryHigh,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SuggestionLeading extends StatelessWidget {
  const _SuggestionLeading(this.suggestion);

  final SearchSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (suggestion.avatarUrl case final avatar?) {
      return ClipOval(
        child: AvatarImage(
          url: avatar,
          size: 30,
          fallback: const DIcon(DIcons.users, size: 16),
        ),
      );
    }
    if (suggestion.colorValues.isNotEmpty) {
      final colors = suggestion.colorValues;
      return ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final color in colors.take(2))
              ColoredBox(
                color: Color(color),
                child: SizedBox(
                  width: 14 / math.min(colors.length, 2),
                  height: 14,
                ),
              ),
          ],
        ),
      );
    }
    return DIcon(
      switch (suggestion.kind) {
        SearchSuggestionKind.tag => DIcons.tag,
        SearchSuggestionKind.user => DIcons.users,
        SearchSuggestionKind.category => DIcons.list,
        SearchSuggestionKind.shortcut => DIcons.magnifyingGlass,
      },
      size: 16,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }
}

class _SearchResultSections extends StatelessWidget {
  const _SearchResultSections({
    required this.search,
    required this.onOpen,
    required this.onFullSearch,
  });

  final ShellSearchController search;
  final ValueChanged<SearchResult> onOpen;
  final VoidCallback onFullSearch;

  @override
  Widget build(BuildContext context) {
    final estimatedHeight = search.sections.fold<double>(8, (height, section) {
      final rowHeight = section.kind == SearchResultKind.topic ? 88.0 : 54.0;
      return height + section.results.length * rowHeight + 1;
    });
    final actionHeight = search.mode == SearchMode.facets ? 56.0 : 0.0;
    final moreHeight = search.hasMoreTopics ? 48.0 : 0.0;
    var resultIndex = 0;

    return SizedBox(
      height: math.min(estimatedHeight + actionHeight + moreHeight, 420),
      child: ListView(
        primary: false,
        // Keyboard selection can advance faster than lazy layout. Keeping this
        // small, server-bounded result set alive gives every target a context
        // that can be revealed as soon as its index becomes selected.
        scrollCacheExtent: ScrollCacheExtent.pixels(
          estimatedHeight + actionHeight + moreHeight,
        ),
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          if (search.mode == SearchMode.facets) ...[
            _RevealWhenSelected(
              selected: search.topicsActionSelected,
              child: _SearchTopicsAction(
                query: search.query.trim(),
                selected: search.topicsActionSelected,
                onFocus: search.selectTopicsAction,
                onTap: search.showTopics,
              ),
            ),
            const Divider(height: 1),
          ],
          for (
            var sectionIndex = 0;
            sectionIndex < search.sections.length;
            sectionIndex++
          ) ...[
            if (sectionIndex > 0) const Divider(height: 1),
            for (final result in search.sections[sectionIndex].results)
              Builder(
                builder: (context) {
                  final index = resultIndex++;
                  final selected = search.selectedIndex == index;
                  return _RevealWhenSelected(
                    selected: selected,
                    child: _SearchResultRow(
                      result: result,
                      siteUrl: search.siteUrl!,
                      showTags: search.taggingEnabled,
                      useTopicHeadline: search.usePgHeadlinesForExcerpt,
                      privateMessageOnly: search.isPrivateMessageOnly,
                      selected: selected,
                      onFocus: () => search.select(index),
                      onTap: () => onOpen(result),
                    ),
                  );
                },
              ),
          ],
          if (search.hasMoreTopics) ...[
            const Divider(height: 1),
            _RevealWhenSelected(
              selected: search.moreActionSelected,
              child: _MoreSearchResultsAction(
                selected: search.moreActionSelected,
                onFocus: search.selectMoreAction,
                onTap: onFullSearch,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MoreSearchResultsAction extends StatelessWidget {
  const _MoreSearchResultsAction({
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'More search results',
      child: InkWell(
        key: const ValueKey('forum-search-more-results'),
        hoverColor: theme.shell.hover,
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: Ink(
          color: selected ? theme.shell.selected : Colors.transparent,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Text('More…'),
          ),
        ),
      ),
    );
  }
}

class _RevealWhenSelected extends StatefulWidget {
  const _RevealWhenSelected({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  State<_RevealWhenSelected> createState() => _RevealWhenSelectedState();
}

class _RevealWhenSelectedState extends State<_RevealWhenSelected> {
  @override
  void didUpdateWidget(_RevealWhenSelected oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
    }
  }

  void _reveal() {
    if (!mounted || !widget.selected) return;

    // The first call handles a row below the viewport. Once it has jumped, the
    // second is a no-op; for a row above the viewport their roles are reversed.
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      ),
    );
    unawaited(
      Scrollable.ensureVisible(
        context,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SearchTopicsAction extends StatelessWidget {
  const _SearchTopicsAction({
    required this.query,
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final String query;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: 'Search $query in topics and posts',
      child: InkWell(
        key: const ValueKey('forum-search-topics-action'),
        hoverColor: theme.shell.hover,
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: Ink(
          color: selected ? theme.shell.selected : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                const SizedBox.square(
                  dimension: 30,
                  child: Center(child: DIcon(DIcons.magnifyingGlass, size: 17)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: query,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: ' in topics and posts'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Press Enter',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.result,
    required this.siteUrl,
    required this.showTags,
    required this.useTopicHeadline,
    required this.privateMessageOnly,
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchResult result;
  final String siteUrl;
  final bool showTags;
  final bool useTopicHeadline;
  final bool privateMessageOnly;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => switch (result) {
    final SearchPostHit hit => _SearchHitRow(
      hit: hit,
      siteUrl: siteUrl,
      showTags: showTags,
      useTopicHeadline: useTopicHeadline,
      privateMessageOnly: privateMessageOnly,
      selected: selected,
      onFocus: onFocus,
      onTap: onTap,
    ),
    final SearchUserHit user => _CompactSearchResultRow(
      result: result,
      title: user.name ?? user.username,
      subtitle: user.name == null ? null : '@${user.username}',
      selected: selected,
      onFocus: onFocus,
      onTap: onTap,
      leading: _SearchAvatar(user: user),
    ),
    final SearchCategoryHit category => _CompactSearchResultRow(
      result: result,
      title: category.name,
      selected: selected,
      onFocus: onFocus,
      onTap: onTap,
      leading: _CategorySwatch(color: Color(category.colorValue)),
    ),
    final SearchTagHit tag => _CompactSearchResultRow(
      result: result,
      title: tag.name,
      selected: selected,
      onFocus: onFocus,
      onTap: onTap,
      leading: const DIcon(DIcons.tag, size: 17),
    ),
    final SearchGroupHit group => _CompactSearchResultRow(
      result: result,
      title: group.fullName ?? group.name,
      subtitle: group.fullName == null ? null : group.name,
      selected: selected,
      onFocus: onFocus,
      onTap: onTap,
      leading: _GroupFlair(group: group),
    ),
  };
}

class _GroupFlair extends StatelessWidget {
  const _GroupFlair({required this.group});

  final SearchGroupHit group;

  @override
  Widget build(BuildContext context) {
    final flair = group.flairUrl;
    if (flair == null) return const DIcon(DIcons.users, size: 17);

    final foreground = _hexColor(
      group.flairColor,
      Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final background = _hexColor(
      group.flairBackgroundColor,
      Colors.transparent,
    );
    final icon = flair.contains('/') ? null : DIcons.byName[flair];
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(5),
      ),
      clipBehavior: Clip.antiAlias,
      child: icon == null
          ? AvatarImage(
              url: flair.contains('/') ? flair : null,
              size: 24,
              fallback: DIcon(DIcons.users, size: 16, color: foreground),
            )
          : DIcon(icon, size: 16, color: foreground),
    );
  }
}

Color _hexColor(String? value, Color fallback) {
  final normalized = value?.replaceFirst('#', '');
  if (normalized == null || normalized.length != 6) return fallback;
  final parsed = int.tryParse(normalized, radix: 16);
  return parsed == null ? fallback : Color(0xFF000000 | parsed);
}

class _CompactSearchResultRow extends StatelessWidget {
  const _CompactSearchResultRow({
    required this.result,
    required this.title,
    required this.selected,
    required this.onFocus,
    required this.onTap,
    required this.leading,
    this.subtitle,
  });

  final SearchResult result;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final Widget leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: [title, ?subtitle].join(', '),
      child: InkWell(
        key: ValueKey('search-${result.kind.name}-${result.id}'),
        hoverColor: theme.shell.hover,
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: Ink(
          color: selected ? theme.shell.selected : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                SizedBox.square(dimension: 30, child: Center(child: leading)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            (result.kind == SearchResultKind.user
                                    ? theme.textTheme.bodySmall
                                    : theme.textTheme.bodyMedium)
                                ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (subtitle case final value?)
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.discourse.primaryHigh,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchAvatar extends StatelessWidget {
  const _SearchAvatar({required this.user});

  final SearchUserHit user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipOval(
      child: AvatarImage(
        url: user.avatarUrl,
        size: 30,
        fallback: CircleAvatar(
          radius: 15,
          backgroundColor: theme.colorScheme.surfaceContainerHigh,
          child: Text(user.username.characters.first.toUpperCase()),
        ),
      ),
    );
  }
}

class _CategorySwatch extends StatelessWidget {
  const _CategorySwatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

String _resultTitle(SearchResult result) => switch (result) {
  final SearchPostHit hit => hit.topicTitle,
  final SearchCategoryHit category => category.name,
  final SearchTagHit tag => tag.name,
  final SearchUserHit user => user.name ?? user.username,
  final SearchGroupHit group => group.fullName ?? group.name,
};

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({
    required this.text,
    this.loading = false,
    this.error = false,
  });

  final String text;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (loading) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
          ],
          if (error) ...[
            DIcon(
              DIcons.triangleExclamation,
              size: 16,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: error
                    ? theme.colorScheme.error
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchHitRow extends StatelessWidget {
  const _SearchHitRow({
    required this.hit,
    required this.siteUrl,
    required this.showTags,
    required this.useTopicHeadline,
    required this.privateMessageOnly,
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchPostHit hit;
  final String siteUrl;
  final bool showTags;
  final bool useTopicHeadline;
  final bool privateMessageOnly;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = ShellScope.read(
      context,
    ).categoryFor(hit.categoryId, siteUrl: siteUrl);
    final title = !useTopicHeadline || hit.topicTitleExcerpt.segments.isEmpty
        ? [SiteEmojiTextRun(hit.topicTitle)]
        : [
            for (final segment in hit.topicTitleExcerpt.segments)
              SiteEmojiTextRun(
                segment.text,
                style: segment.highlighted
                    ? const TextStyle(fontWeight: FontWeight.w700)
                    : null,
              ),
          ];

    return Semantics(
      button: true,
      selected: selected,
      label: hit.topicTitle,
      child: InkWell(
        key: ValueKey('search-hit-${hit.postId}'),
        hoverColor: theme.shell.hover,
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: Ink(
          color: selected ? theme.shell.selected : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (hit.bookmarked ||
                        hit.closed ||
                        hit.archived ||
                        hit.warning ||
                        (hit.privateMessage && !privateMessageOnly) ||
                        hit.pinned ||
                        hit.unpinned ||
                        hit.invisible) ...[
                      _SearchTopicStatuses(
                        hit: hit,
                        showPrivateMessage: !privateMessageOnly,
                      ),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: SiteEmojiText(
                        title,
                        siteUrl: siteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                if (category != null || (showTags && hit.tags.isNotEmpty)) ...[
                  const SizedBox(height: 3),
                  _SearchTopicMetadata(
                    category: category,
                    tags: showTags ? hit.tags : const [],
                  ),
                ],
                if (hit.excerpt.segments.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  SiteEmojiText(
                    [
                      for (final segment in hit.excerpt.segments)
                        SiteEmojiTextRun(
                          segment.text,
                          style: segment.highlighted
                              ? const TextStyle(fontWeight: FontWeight.w700)
                              : null,
                        ),
                    ],
                    siteUrl: siteUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.discourse.primaryHigh,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchTopicStatuses extends StatelessWidget {
  const _SearchTopicStatuses({
    required this.hit,
    required this.showPrivateMessage,
  });

  final SearchPostHit hit;
  final bool showPrivateMessage;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hit.bookmarked)
          DIcon(
            DIcons.bookmark,
            size: 13,
            color: color,
            semanticLabel: 'Bookmarked',
          ),
        if (hit.closed || hit.archived)
          DIcon(
            DIcons.lock,
            size: 13,
            color: color,
            semanticLabel: hit.closed && hit.archived
                ? 'Locked and archived'
                : hit.closed
                ? 'Locked'
                : 'Archived',
          ),
        if (hit.warning || (showPrivateMessage && hit.privateMessage))
          DIcon(
            DIcons.envelope,
            size: 13,
            color: color,
            semanticLabel: hit.warning ? 'Warning' : 'Personal message',
          ),
        if (hit.pinned || hit.unpinned)
          DIcon(
            DIcons.thumbtack,
            size: 13,
            color: color,
            semanticLabel: hit.pinned ? 'Pinned' : 'Unpinned',
          ),
        if (hit.invisible)
          DIcon(
            DIcons.farEyeSlash,
            size: 13,
            color: color,
            semanticLabel: 'Unlisted',
          ),
      ],
    );
  }
}

class _SearchTopicMetadata extends StatelessWidget {
  const _SearchTopicMetadata({required this.category, required this.tags});

  final TopicCategory? category;
  final List<TopicTag> tags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 3,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (category case final category?)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Color(category.colorValue),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 5),
              Text(category.name, style: style),
            ],
          ),
        if (tags.isNotEmpty)
          Semantics(
            label: 'Tags: ${tags.map((tag) => tag.name).join(', ')}',
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 260),
              child: Text(
                tags.map((tag) => tag.name).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ),
      ],
    );
  }
}
