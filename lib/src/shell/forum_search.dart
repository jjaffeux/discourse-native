import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';

import '../models/search_results.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'open_link.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';
import 'site_emoji_text.dart';
import 'topic_title.dart';

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
  final Object _field = Object();
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode(debugLabel: 'forum search');
  final MenuController _menu = MenuController();
  ShellSearchController? _search;
  VoidCallback? _unregisterFocus;

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
      if (_focus.hasFocus) {
        _submitFromField();
      } else {
        _openSelected();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openSelected() {
    final result = _search?.selectedResult;
    if (result != null) _openResult(result);
  }

  void _submitFromField() {
    final search = _search;
    if (search == null) return;
    if (search.selectedResult case final result?) {
      _openResult(result);
    } else if (search.mode == SearchMode.facets) {
      search.showTopics();
    }
  }

  void _openResult(SearchResult result) {
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

  @override
  Widget build(BuildContext context) {
    final search = _search!;
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
          ),
          menuChildren: [
            SizedBox(
              width: panelWidth,
              child: _SearchPanel(search: search, onOpen: _openResult),
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
                    vertical: widget.dense ? 5 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.shell.floating,
                    border: Border.all(color: theme.shell.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const DIcon(DIcons.magnifyingGlass, size: 15),
                      const SizedBox(width: 8),
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
                      if (search.query.isEmpty)
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
                        )
                      else
                        IconButton(
                          key: const ValueKey('forum-search-clear'),
                          tooltip: 'Clear search',
                          onPressed: search.clear,
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 24,
                            height: 24,
                          ),
                          padding: EdgeInsets.zero,
                          icon: const DIcon(DIcons.xmark, size: 14),
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
  const _SearchPanel({required this.search, required this.onOpen});

  final ShellSearchController search;
  final ValueChanged<SearchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = switch (search.phase) {
      SearchSessionPhase.tooShort => _PanelMessage(
        text: 'Type at least ${search.minimumLength} characters to search.',
      ),
      SearchSessionPhase.waiting || SearchSessionPhase.loading =>
        const _PanelMessage(text: 'Searching…', loading: true),
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
      ),
      SearchSessionPhase.idle => const SizedBox.shrink(),
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

class _SearchResultSections extends StatelessWidget {
  const _SearchResultSections({required this.search, required this.onOpen});

  final ShellSearchController search;
  final ValueChanged<SearchResult> onOpen;

  @override
  Widget build(BuildContext context) {
    final estimatedHeight = search.sections.fold<double>(8, (height, section) {
      final rowHeight = section.kind == SearchResultKind.topic ? 94.0 : 54.0;
      return height + section.results.length * rowHeight + 1;
    });
    final actionHeight = search.mode == SearchMode.facets ? 56.0 : 0.0;
    var resultIndex = 0;

    return SizedBox(
      height: math.min(estimatedHeight + actionHeight, 420),
      child: ListView(
        primary: false,
        // Keyboard selection can advance faster than lazy layout. Keeping this
        // small, server-bounded result set alive gives every target a context
        // that can be revealed as soon as its index becomes selected.
        scrollCacheExtent: ScrollCacheExtent.pixels(
          estimatedHeight + actionHeight,
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
                      selected: selected,
                      onFocus: () => search.select(index),
                      onTap: () => onOpen(result),
                    ),
                  );
                },
              ),
          ],
        ],
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
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: ColoredBox(
          color: selected ? theme.shell.hover : Colors.transparent,
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
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchResult result;
  final String siteUrl;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => switch (result) {
    final SearchPostHit hit => _SearchHitRow(
      hit: hit,
      siteUrl: siteUrl,
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
      leading: const DIcon(DIcons.users, size: 17),
    ),
  };
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
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: ColoredBox(
          color: selected ? theme.shell.hover : Colors.transparent,
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
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle case final value?)
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
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
              child: CircularProgressIndicator(strokeWidth: 2),
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
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchPostHit hit;
  final String siteUrl;
  final bool selected;
  final VoidCallback onFocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initial = hit.username.isEmpty
        ? '?'
        : hit.username.characters.first.toUpperCase();

    return Semantics(
      button: true,
      selected: selected,
      label: '${hit.topicTitle}, post by ${hit.displayName}',
      child: InkWell(
        key: ValueKey('search-hit-${hit.postId}'),
        onFocusChange: (focused) {
          if (focused) onFocus();
        },
        onTap: onTap,
        child: ColoredBox(
          color: selected ? theme.shell.hover : Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipOval(
                  child: AvatarImage(
                    url: hit.avatarUrl,
                    size: 30,
                    fallback: CircleAvatar(
                      radius: 15,
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      child: Text(initial),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TopicTitle(
                        hit.topicTitle,
                        siteUrl: siteUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          hit.displayName,
                          if (hit.createdAt case final created?)
                            relativeTime(created),
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
