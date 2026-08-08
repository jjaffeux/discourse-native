import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/search_results.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'relative_time.dart';
import 'shell_scope.dart';
import 'shell_search_controller.dart';

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
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final search = _search;
    if (search == null) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      search.closePanel();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      search.moveSelection(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      search.moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _openSelected();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _openSelected() {
    final hit = _search?.selectedHit;
    if (hit != null) ShellScope.read(context).openSearchResult(hit);
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
              child: _SearchPanel(search: search),
            ),
          ],
          builder: (context, menu, child) => Focus(
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
                              onSubmitted: (_) => _openSelected(),
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
  const _SearchPanel({required this.search});

  final ShellSearchController search;

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
        text: 'No matching posts.',
      ),
      SearchSessionPhase.refused || SearchSessionPhase.failed => _PanelMessage(
        text: search.message ?? "Couldn't search this forum.",
        error: true,
      ),
      SearchSessionPhase.results => SizedBox(
        height: math.min(search.hits.length * 94.0 + 8, 420),
        child: ListView.separated(
          primary: false,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: search.hits.length,
          separatorBuilder: (context, _) =>
              Divider(height: 1, color: theme.shell.divider),
          itemBuilder: (context, index) => _SearchHitRow(
            hit: search.hits[index],
            selected: search.selectedIndex == index,
            onFocus: () => search.select(index),
            onTap: () =>
                ShellScope.read(context).openSearchResult(search.hits[index]),
          ),
        ),
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
    required this.selected,
    required this.onFocus,
    required this.onTap,
  });

  final SearchPostHit hit;
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
      label: '${hit.topicTitle}, post by ${hit.displayName}',
      child: InkWell(
        key: ValueKey('search-hit-${hit.postId}'),
        autofocus: selected,
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
                      Text(
                        hit.topicTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: [
                            for (final segment in hit.excerpt.segments)
                              TextSpan(
                                text: segment.text,
                                style: segment.highlighted
                                    ? const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      )
                                    : null,
                              ),
                          ],
                        ),
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
