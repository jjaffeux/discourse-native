import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show kPrimaryButton, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../models/forum_workspace.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icon.dart';
import '../theme/d_icons.dart';
import '../theme/d_tooltip.dart';
import 'avatar_image.dart';
import 'emoji.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';

@immutable
class ForumTabItem {
  const ForumTabItem({
    required this.id,
    required this.title,
    this.siteUrl,
    this.icon,
    this.color,
    this.parentColor,
    this.iconColor,
    this.avatarUrl,
    this.prefixBuilder,
    this.labelSuffixBuilder,
    this.semanticDescription,
    this.emojiUrl,
    this.emojiName,
    this.badge = SidebarBadge.none,
  }) : assert(
         (emojiUrl == null) == (emojiName == null),
         'emojiUrl and emojiName must be provided together',
       );

  final String id;
  final String title;
  final String? siteUrl;
  final DIconData? icon;
  final Color? color;
  final Color? parentColor;
  final Color? iconColor;
  final String? avatarUrl;
  final SidebarRowDecorationBuilder? prefixBuilder;
  final SidebarRowDecorationBuilder? labelSuffixBuilder;
  final String? semanticDescription;
  final String? emojiUrl;
  final String? emojiName;
  final SidebarBadge badge;
}

class ForumTabsBar extends StatefulWidget {
  ForumTabsBar({
    super.key,
    required this.forumName,
    required this.items,
    required this.selectedId,
    required this.onAdd,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onCloseOthers,
    this.recentlyClosedItems = const [],
    this.onReopen,
    this.onRename,
  }) : assert(items.isNotEmpty),
       assert(items.any((item) => item.id == selectedId));

  static const double height = 38;

  static double heightFor(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium!;
    final fontSize = style.fontSize!;
    final growth =
        (MediaQuery.textScalerOf(context).scale(fontSize) - fontSize) *
        style.height!;
    return height + math.max(0, growth);
  }

  static const double minimumActionTarget = 34;

  static const double _tabContentInset = 4;

  static const double minimumTabWidth = 112 + 2 * _tabContentInset;

  static const double maximumTabWidth = 216 + 2 * _tabContentInset;

  static const double closeTargetWidth = 24;

  final String forumName;
  final List<ForumTabItem> items;
  final String selectedId;
  final VoidCallback? onAdd;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final void Function(String id, int newIndex) onReorder;
  final ValueChanged<String> onCloseOthers;
  final List<ForumTabItem> recentlyClosedItems;
  final ValueChanged<String>? onReopen;
  final void Function(String id, String title)? onRename;

  @override
  State<ForumTabsBar> createState() => _ForumTabsBarState();
}

class _ForumTabsBarState extends State<ForumTabsBar> {
  static const _tabGap = 1.0;
  static const _inactiveTabDividerHeight = 18.0;
  static const _switcherGap = 4.0;

  final Map<String, GlobalKey> _itemKeys = {};
  final GlobalKey _addKey = GlobalKey();
  final ValueNotifier<String?> _hoveredTab = ValueNotifier(null);
  double? _lastViewportWidth;

  @override
  void initState() {
    super.initState();
    _scheduleRevealSelected();
  }

  @override
  void dispose() {
    _hoveredTab.dispose();
    super.dispose();
  }

  void _handleTabHover(String id, bool hovered) {
    if (hovered) {
      _hoveredTab.value = id;
    } else if (_hoveredTab.value == id) {
      _hoveredTab.value = null;
    }
  }

  @override
  void didUpdateWidget(ForumTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final liveIds = {for (final item in widget.items) item.id};
    _itemKeys.removeWhere((id, _) => !liveIds.contains(id));
    if (!liveIds.contains(_hoveredTab.value)) _hoveredTab.value = null;
    var sameIds = oldWidget.items.length == widget.items.length;
    for (var index = 0; sameIds && index < widget.items.length; index++) {
      sameIds = oldWidget.items[index].id == widget.items[index].id;
    }
    if (oldWidget.selectedId != widget.selectedId || !sameIds) {
      _scheduleRevealSelected();
    }
  }

  void _scheduleRevealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final revealContext = widget.items.last.id == widget.selectedId
          ? _addKey.currentContext
          : _itemKeys[widget.selectedId]?.currentContext;
      if (revealContext == null) return;
      final reducedMotion =
          MediaQuery.maybeOf(revealContext)?.disableAnimations ?? false;
      unawaited(
        Scrollable.ensureVisible(
          revealContext,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  Widget _gapAfter(int index, Color dividerColor) {
    final left = widget.items[index];
    final right = widget.items[index + 1];
    if (left.id == widget.selectedId || right.id == widget.selectedId) {
      return const SizedBox(width: _tabGap);
    }

    return ValueListenableBuilder<String?>(
      valueListenable: _hoveredTab,
      builder: (context, hoveredId, _) => Container(
        key: ValueKey('forum-tab-divider-${left.id}'),
        width: _tabGap,
        height: _inactiveTabDividerHeight,
        color: hoveredId == left.id || hoveredId == right.id
            ? Colors.transparent
            : dividerColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      key: const ValueKey('forum-tabs-bar'),
      width: double.infinity,
      height: ForumTabsBar.heightFor(context),
      decoration: BoxDecoration(color: theme.shell.sidebar),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 3, 5, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (_lastViewportWidth != constraints.maxWidth) {
              _lastViewportWidth = constraints.maxWidth;
              _scheduleRevealSelected();
            }
            const switcherWidth = ForumTabsBar.minimumActionTarget;
            const addWidth = ForumTabsBar.minimumActionTarget;
            const newTabGap = 4.0;
            final tabViewportWidth = math.max(
              0.0,
              constraints.maxWidth -
                  switcherWidth -
                  _switcherGap -
                  addWidth -
                  newTabGap,
            );
            final gapsWidth = math.max(0, widget.items.length - 1) * _tabGap;
            final equalShare = widget.items.isEmpty
                ? 70.0
                : (tabViewportWidth - gapsWidth) / widget.items.length;
            final tabWidth = equalShare.clamp(
              ForumTabsBar.minimumTabWidth,
              ForumTabsBar.maximumTabWidth,
            );

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ForumTabSwitcher(
                  forumName: widget.forumName,
                  items: widget.items,
                  selectedId: widget.selectedId,
                  recentlyClosedItems: widget.recentlyClosedItems,
                  onSelect: widget.onSelect,
                  onClose: widget.onClose,
                  onReopen: widget.onReopen,
                ),
                const SizedBox(width: _switcherGap),
                Expanded(
                  child: ClipRect(
                    child: SingleChildScrollView(
                      key: const ValueKey('forum-tabs-scroll'),
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            role: SemanticsRole.tabBar,
                            container: true,
                            explicitChildNodes: true,
                            label: 'Open tabs in ${widget.forumName}',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (
                                  var index = 0;
                                  index < widget.items.length;
                                  index++
                                ) ...[
                                  SizedBox(
                                    key: _itemKeys.putIfAbsent(
                                      widget.items[index].id,
                                      GlobalKey.new,
                                    ),
                                    width: tabWidth,
                                    child: _ReorderableForumTab(
                                      item: widget.items[index],
                                      index: index,
                                      itemCount: widget.items.length,
                                      width: tabWidth,
                                      selected:
                                          widget.items[index].id ==
                                          widget.selectedId,
                                      onSelect: () => widget.onSelect(
                                        widget.items[index].id,
                                      ),
                                      onClose: () => widget.onClose(
                                        widget.items[index].id,
                                      ),
                                      onHoverChanged: _handleTabHover,
                                      onReorder: widget.onReorder,
                                      onCloseOthers: widget.items.length == 1
                                          ? null
                                          : () => widget.onCloseOthers(
                                              widget.items[index].id,
                                            ),
                                      onRename: widget.onRename == null
                                          ? null
                                          : (title) => widget.onRename!(
                                              widget.items[index].id,
                                              title,
                                            ),
                                    ),
                                  ),
                                  if (index != widget.items.length - 1)
                                    _gapAfter(index, theme.shell.divider),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: newTabGap),
                          SizedBox(
                            key: _addKey,
                            child: _NewTabButton(onPressed: widget.onAdd),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ForumTabSwitcher extends StatefulWidget {
  const _ForumTabSwitcher({
    required this.forumName,
    required this.items,
    required this.selectedId,
    required this.recentlyClosedItems,
    required this.onSelect,
    required this.onClose,
    required this.onReopen,
  });

  final String forumName;
  final List<ForumTabItem> items;
  final String selectedId;
  final List<ForumTabItem> recentlyClosedItems;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onClose;
  final ValueChanged<String>? onReopen;

  @override
  State<_ForumTabSwitcher> createState() => _ForumTabSwitcherState();
}

class _ForumTabSwitcherState extends State<_ForumTabSwitcher> {
  final MenuController _menu = MenuController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'tab switcher search');
  final WidgetStatesController _buttonStates = WidgetStatesController();
  bool _open = false;
  bool _historyExpanded = false;

  @override
  void dispose() {
    _buttonStates.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _handleOpen() {
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu.isOpen) _searchFocus.requestFocus();
    });
  }

  void _handleClose() {
    _searchFocus.unfocus();
    _search.clear();
    if (mounted) {
      setState(() {
        _open = false;
        _historyExpanded = false;
      });
    }
  }

  bool _matches(ForumTabItem item) {
    final query = _search.text.trim().toLowerCase();
    return query.isEmpty || item.title.toLowerCase().contains(query);
  }

  void _select(String id) {
    widget.onSelect(id);
    _menu.close();
  }

  void _reopen(String id) {
    widget.onReopen?.call(id);
    _menu.close();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final panelWidth = math.max(0.0, math.min(500.0, media.size.width - 16));
    final availablePanelHeight = math.max(
      0.0,
      media.size.height - media.padding.vertical - media.viewInsets.bottom - 72,
    );
    final openItems = widget.items.where(_matches).toList(growable: false);
    final closedItems = widget.recentlyClosedItems
        .where(_matches)
        .toList(growable: false);
    final reduceMotion = media.disableAnimations;

    return SizedBox(
      width: ForumTabsBar.minimumActionTarget,
      height: ForumTabsBar.minimumActionTarget,
      child: MenuAnchor(
        controller: _menu,
        onOpen: _handleOpen,
        onClose: _handleClose,
        style: MenuStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(8),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              side: BorderSide(color: theme.shell.divider),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        menuChildren: [
          Container(
            key: const ValueKey('forum-tabs-switcher-menu'),
            width: panelWidth,
            constraints: BoxConstraints(
              maxHeight: math.min(480.0, availablePanelHeight),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: const ValueKey('forum-tabs-switcher-search'),
                  controller: _search,
                  focusNode: _searchFocus,
                  onChanged: (_) => setState(() {}),
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'Search tabs…',
                    hintStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: DIcon(
                        DIcons.magnifyingGlass,
                        size: 17,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    filled: true,
                    fillColor: theme.shell.content,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: SingleChildScrollView(
                    primary: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TabSwitcherHeading(
                          label: _search.text.trim().isEmpty
                              ? 'Open tabs'
                              : 'Matching tabs',
                          count: openItems.length,
                        ),
                        for (final item in openItems)
                          _TabSwitcherRow(
                            key: ValueKey(
                              'forum-tabs-switcher-open-${item.id}',
                            ),
                            item: item,
                            selected: item.id == widget.selectedId,
                            onTap: () => _select(item.id),
                            trailing: _TabSwitcherRowAction(
                              label: 'Close ${item.title}',
                              icon: DIcons.xmark,
                              onPressed: () => widget.onClose(item.id),
                            ),
                          ),
                        if (openItems.isEmpty)
                          const _TabSwitcherEmpty(
                            label: 'No matching open tabs',
                          ),
                        if (widget.recentlyClosedItems.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Divider(height: 1, color: theme.shell.divider),
                          _TabSwitcherHistoryToggle(
                            count: closedItems.length,
                            expanded: _historyExpanded,
                            onTap: () => setState(
                              () => _historyExpanded = !_historyExpanded,
                            ),
                          ),
                          if (_historyExpanded) ...[
                            for (final item in closedItems)
                              _TabSwitcherRow(
                                key: ValueKey(
                                  'forum-tabs-switcher-recent-${item.id}',
                                ),
                                item: item,
                                onTap: widget.onReopen == null
                                    ? null
                                    : () => _reopen(item.id),
                                trailing: const DIcon(
                                  DIcons.arrowRotateLeft,
                                  size: 15,
                                ),
                              ),
                            if (closedItems.isEmpty)
                              const _TabSwitcherEmpty(
                                label: 'No matching recently closed tabs',
                              ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        builder: (context, controller, _) => Semantics(
          key: const ValueKey('forum-tabs-switcher'),
          button: true,
          expanded: _open,
          label: 'Browse tabs in ${widget.forumName}',
          onTap: controller.open,
          child: ExcludeSemantics(
            child: IconButton(
              statesController: _buttonStates,
              tooltip: 'Browse tabs',
              constraints: const BoxConstraints.expand(
                width: ForumTabsBar.minimumActionTarget,
                height: ForumTabsBar.minimumActionTarget,
              ),
              padding: EdgeInsets.zero,
              style: const ButtonStyle(
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: controller.isOpen ? controller.close : controller.open,
              icon: ValueListenableBuilder<Set<WidgetState>>(
                valueListenable: _buttonStates,
                builder: (context, states, _) {
                  final emphasized =
                      _open ||
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed);
                  return AnimatedContainer(
                    key: const ValueKey('forum-tabs-switcher-surface'),
                    width: 28,
                    height: 28,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: emphasized
                          ? theme.colorScheme.primaryContainer
                          : theme.shell.content,
                      border: Border.all(color: theme.shell.divider),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DIcon(
                      DIcons.chevronDown,
                      size: 15,
                      color: emphasized
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabSwitcherHeading extends StatelessWidget {
  const _TabSwitcherHeading({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      child: Text(
        count == 0 ? label : '$label  $count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _TabSwitcherHistoryToggle extends StatelessWidget {
  const _TabSwitcherHistoryToggle({
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  final int count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      expanded: expanded,
      child: InkWell(
        key: const ValueKey('forum-tabs-switcher-history'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              DIcon(
                expanded ? DIcons.chevronDown : DIcons.chevronRight,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recently closed  $count',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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

class _TabSwitcherEmpty extends StatelessWidget {
  const _TabSwitcherEmpty({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _TabSwitcherRow extends StatelessWidget {
  const _TabSwitcherRow({
    super.key,
    required this.item,
    required this.onTap,
    this.selected = false,
    this.trailing,
  });

  final ForumTabItem item;
  final VoidCallback? onTap;
  final bool selected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
    );
    final title = switch (item.siteUrl) {
      final siteUrl? => SiteEmojiText.plain(
        item.title,
        siteUrl: siteUrl,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
      null => Text(
        item.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: 0.12),
                theme.shell.floating,
              )
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: Stack(
          children: [
            if (selected)
              PositionedDirectional(
                start: 0,
                top: 12,
                bottom: 12,
                width: 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    child: DTooltip(
                      message: item.title,
                      excludeFromSemantics: true,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(7),
                        hoverColor: theme.hoverColor,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 40),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                ExcludeSemantics(
                                  child: SizedBox(
                                    width: 18,
                                    height: 20,
                                    child: Center(
                                      child:
                                          _tabPrefix(
                                            context,
                                            item,
                                            foreground,
                                            size: 17,
                                          ) ??
                                          DIcon(
                                            DIcons.layerGroup,
                                            size: 17,
                                            color: foreground,
                                          ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(child: title),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSwitcherRowAction extends StatelessWidget {
  const _TabSwitcherRowAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final DIconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    constraints: const BoxConstraints.tightFor(width: 30, height: 30),
    padding: EdgeInsets.zero,
    style: const ButtonStyle(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    onPressed: onPressed,
    icon: DIcon(icon, size: 14),
  );
}

Widget? _tabPrefix(
  BuildContext context,
  ForumTabItem item,
  Color foreground, {
  double size = 15,
}) {
  final theme = Theme.of(context);

  if (item.prefixBuilder case final builder?) {
    return builder(context, size);
  }

  if (item.avatarUrl case final url?) {
    return ClipOval(
      child: SizedBox.square(
        dimension: size + 1,
        child: AvatarImage(
          url: url,
          size: size + 1,
          fallback: ColoredBox(color: theme.shell.floating),
        ),
      ),
    );
  }

  if ((item.emojiUrl, item.emojiName) case (final url?, final name?)) {
    return EmojiImage(
      url: url,
      size: size,
      alt: ':$name:',
      style: theme.textTheme.labelSmall,
    );
  }

  if (item.color case final color?) {
    final parentColor = item.parentColor;
    return Container(
      key: ValueKey('forum-tab-prefix-${item.id}'),
      width: size - 3,
      height: size - 3,
      decoration: BoxDecoration(
        color: parentColor == null ? color : null,
        gradient: parentColor == null
            ? null
            : LinearGradient(
                colors: [parentColor, color],
                stops: const [0.5, 0.5],
              ),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }

  if (item.icon case final icon?) {
    return DIcon(icon, size: size, color: item.iconColor ?? foreground);
  }

  return null;
}

class _ReorderableForumTab extends StatelessWidget {
  const _ReorderableForumTab({
    required this.item,
    required this.index,
    required this.itemCount,
    required this.width,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onHoverChanged,
    required this.onReorder,
    required this.onCloseOthers,
    this.onRename,
  });

  final ForumTabItem item;
  final int index;
  final int itemCount;
  final double width;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(String id, bool hovered) onHoverChanged;
  final void Function(String id, int newIndex) onReorder;
  final VoidCallback? onCloseOthers;
  final ValueChanged<String>? onRename;

  @override
  Widget build(BuildContext context) {
    final tab = _ForumTab(
      key: ValueKey(item.id),
      item: item,
      selected: selected,
      onSelect: onSelect,
      onClose: onClose,
      onHoverChanged: (hovered) => onHoverChanged(item.id, hovered),
      onCloseOthers: onCloseOthers,
      onRename: onRename,
      onMoveLeft: index == 0 ? null : () => onReorder(item.id, index - 1),
      onMoveRight: index == itemCount - 1
          ? null
          : () => onReorder(item.id, index + 1),
    );
    if (itemCount < 2) return tab;

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton &&
            event.localPosition.dx <
                width -
                    ForumTabsBar.closeTargetWidth -
                    ForumTabsBar._tabContentInset) {
          onSelect();
        }
      },
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != item.id,
        onAcceptWithDetails: (details) => onReorder(details.data, index),
        builder: (context, candidates, rejected) {
          final dropTarget = candidates.isNotEmpty;
          final child = _ForumTab(
            key: ValueKey(item.id),
            item: item,
            selected: selected,
            dropTarget: dropTarget,
            selectOnPointerDown: false,
            onSelect: onSelect,
            onClose: onClose,
            onHoverChanged: (hovered) => onHoverChanged(item.id, hovered),
            onCloseOthers: onCloseOthers,
            onRename: onRename,
            onMoveLeft: index == 0 ? null : () => onReorder(item.id, index - 1),
            onMoveRight: index == itemCount - 1
                ? null
                : () => onReorder(item.id, index + 1),
          );
          return Draggable<String>(
            data: item.id,
            axis: Axis.horizontal,
            dragAnchorStrategy: childDragAnchorStrategy,
            feedback: _ForumTabDragFeedback(item: item, width: width),
            childWhenDragging: Opacity(opacity: 0.3, child: child),
            child: child,
          );
        },
      ),
    );
  }
}

class _ForumTabDragFeedback extends StatelessWidget {
  const _ForumTabDragFeedback({required this.item, required this.width});

  final ForumTabItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      color: theme.shell.content,
      shape: const _ForumTabShape(selected: true),
      child: SizedBox(
        width: width,
        height: ForumTabsBar.heightFor(context) - 3,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (item.icon case final icon?) ...[
                DIcon(
                  icon,
                  size: 15,
                  color: item.iconColor ?? theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w400,
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

class _NewTabButton extends StatefulWidget {
  const _NewTabButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  State<_NewTabButton> createState() => _NewTabButtonState();
}

class _NewTabButtonState extends State<_NewTabButton> {
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final label = widget.onPressed == null
        ? 'Close a tab before opening another'
        : 'Open a new tab';
    return Semantics(
      key: const ValueKey('forum-tabs-add'),
      container: true,
      button: true,
      enabled: widget.onPressed != null,
      label: label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: DTooltip(
          message: label,
          shortcut: widget.onPressed == null
              ? null
              : DShortcut(
                  primaryShortcutForPlatform(
                    Theme.of(context).platform,
                    LogicalKeyboardKey.keyT,
                  ),
                ),
          excludeFromSemantics: true,
          child: SizedBox(
            width: ForumTabsBar.minimumActionTarget,
            height: ForumTabsBar.minimumActionTarget,
            child: IconButton(
              statesController: _states,
              constraints: const BoxConstraints.expand(),
              padding: EdgeInsets.zero,
              style: const ButtonStyle(
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: widget.onPressed,
              icon: ValueListenableBuilder<Set<WidgetState>>(
                valueListenable: _states,
                builder: (context, states, _) {
                  final emphasized =
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed);
                  return AnimatedContainer(
                    key: const ValueKey('forum-tabs-add-surface'),
                    width: 28,
                    height: 28,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: emphasized
                          ? theme.colorScheme.primaryContainer
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DIcon(
                      DIcons.plus,
                      size: 16,
                      color: emphasized
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ForumTab extends StatefulWidget {
  const _ForumTab({
    super.key,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onHoverChanged,
    required this.onCloseOthers,
    this.dropTarget = false,
    this.selectOnPointerDown = true,
    this.onMoveLeft,
    this.onMoveRight,
    this.onRename,
  });

  final ForumTabItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback? onCloseOthers;
  final bool dropTarget;
  final bool selectOnPointerDown;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final ValueChanged<String>? onRename;

  @override
  State<_ForumTab> createState() => _ForumTabState();
}

class _ForumTabState extends State<_ForumTab> {
  static const _renameAction = CustomSemanticsAction(label: 'Rename');
  static const _dotGap = 3.0;

  bool _hovered = false;
  bool _selectedOnPointerDown = false;
  bool _renaming = false;
  late final TextEditingController _renameController = TextEditingController();
  late final FocusNode _renameFocusNode = FocusNode(
    debugLabel: 'forum tab rename',
  )..addListener(_handleRenameFocusChanged);

  @override
  void didUpdateWidget(_ForumTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onRename == null) _renaming = false;
  }

  @override
  void dispose() {
    _renameFocusNode.dispose();
    _renameController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    _selectedOnPointerDown = true;
    if (widget.selectOnPointerDown) widget.onSelect();
  }

  void _handleTap() {
    if (_selectedOnPointerDown) {
      _selectedOnPointerDown = false;
      return;
    }
    widget.onSelect();
  }

  void _handleTapCancel() {
    _selectedOnPointerDown = false;
  }

  void _handleRenameFocusChanged() {
    if (_renaming && !_renameFocusNode.hasFocus) _finishRenaming();
  }

  void _startRenaming() {
    if (widget.onRename == null || _renaming) return;
    _selectedOnPointerDown = false;
    _renameController
      ..text = widget.item.title
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.item.title.length,
      );
    setState(() => _renaming = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_renaming) return;
      _renameFocusNode.requestFocus();
    });
  }

  void _finishRenaming({bool commit = true}) {
    if (!_renaming) return;
    final title = _renameController.text.trim();
    setState(() => _renaming = false);
    _renameFocusNode.unfocus();
    if (commit && title.isNotEmpty && title != widget.item.title) {
      widget.onRename?.call(title);
    }
  }

  void _submitRename(String _) {
    // EditableText may still have caret work queued for this frame. Keeping it
    // mounted until the frame ends avoids asking that callback to inspect an
    // element that the submit handler has already removed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _finishRenaming();
    });
  }

  KeyEventResult _handleRenameKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      _finishRenaming(commit: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  String get _selectionSemanticsLabel {
    final badge = widget.item.badge;
    final description = widget.item.semanticDescription;
    final title = description == null
        ? widget.item.title
        : '${widget.item.title}, $description';
    if (!badge.isVisible) return title;
    if (badge.dot) {
      return '$title, '
          '${badge.urgent ? 'urgent unread activity' : 'unread activity'}';
    }
    return '$title, ${badge.count} '
        '${badge.count == 1 ? 'unread item' : 'unread items'}';
  }

  Widget _badge(BuildContext context) {
    final badge = widget.item.badge;
    if (!badge.isVisible) return const SizedBox.shrink();
    final theme = Theme.of(context);

    if (badge.dot) {
      return Container(
        key: ValueKey('forum-tab-badge-${widget.item.id}'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: badge.urgent
              ? theme.discourse.success
              : theme.discourse.unreadIndicator,
          shape: BoxShape.circle,
        ),
      );
    }

    return Container(
      key: ValueKey('forum-tab-badge-${widget.item.id}'),
      height: math.max(
        18,
        MediaQuery.textScalerOf(context).scale(DiscourseTypography.xs) *
                DiscourseTypography.lineHeightCaption +
            2,
      ),
      constraints: const BoxConstraints(minWidth: 19),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: badge.urgent ? theme.colorScheme.error : theme.shell.selected,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${badge.count}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: badge.urgent
              ? theme.colorScheme.onError
              : theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  bool _badgeFits(
    BuildContext context,
    double selectWidth, {
    required bool hasPrefix,
  }) {
    final badge = widget.item.badge;
    if (!badge.isVisible) return false;
    // Select padding consumes 9px. A prefix and its gap consume another 22px.
    final leadingWidth = hasPrefix ? 31 : 9;
    if (badge.dot) return selectWidth >= leadingWidth + _dotGap + 8;
    final painter = TextPainter(
      text: TextSpan(
        text: '${badge.count}',
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final estimatedBadgeWidth = math.max(19, painter.width + 10);
    painter.dispose();
    return selectWidth >= leadingWidth + estimatedBadgeWidth;
  }

  Widget _tabContents(
    BuildContext context,
    Color foreground,
    BoxConstraints constraints,
  ) {
    final theme = Theme.of(context);
    final prefix = _tabPrefix(context, widget.item, foreground);
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w400,
    );
    final label = switch (widget.item.siteUrl) {
      final siteUrl? => SiteEmojiText.plain(
        widget.item.title,
        siteUrl: siteUrl,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
      null => Text(
        widget.item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: labelStyle,
      ),
    };
    return Padding(
      padding: const EdgeInsets.only(left: 9),
      child: Row(
        children: [
          if (prefix != null) ...[
            SizedBox.square(dimension: 15, child: Center(child: prefix)),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: _renaming
                ? Focus(
                    onKeyEvent: _handleRenameKey,
                    child: TextField(
                      key: ValueKey('forum-tab-rename-${widget.item.id}'),
                      controller: _renameController,
                      focusNode: _renameFocusNode,
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      style: labelStyle,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      onSubmitted: _submitRename,
                      onTapOutside: (_) => _finishRenaming(),
                    ),
                  )
                : Row(
                    children: [
                      Flexible(child: label),
                      if (widget.item.labelSuffixBuilder case final builder?)
                        builder(context, 13),
                      if (widget.item.badge.dot &&
                          _badgeFits(
                            context,
                            constraints.maxWidth,
                            hasPrefix: prefix != null,
                          )) ...[
                        const SizedBox(width: _dotGap),
                        _badge(context),
                      ],
                    ],
                  ),
          ),
          if (!_renaming &&
              !widget.item.badge.dot &&
              _badgeFits(
                context,
                constraints.maxWidth,
                hasPrefix: prefix != null,
              ))
            _badge(context),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = widget.selected
        ? theme.colorScheme.onSurface
        : _hovered
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurfaceVariant;
    final closeLabel = 'Close ${widget.item.title}';

    return _ForumTabActions(
      tabId: widget.item.id,
      selected: widget.selected,
      label: _renaming ? null : _selectionSemanticsLabel,
      onTap: widget.onSelect,
      customSemanticsActions: {
        if (widget.onRename != null) _renameAction: _startRenaming,
        const CustomSemanticsAction(label: 'Move left'): ?widget.onMoveLeft,
        const CustomSemanticsAction(label: 'Move right'): ?widget.onMoveRight,
      },
      onClose: widget.onClose,
      onCloseOthers: widget.onCloseOthers,
      child: MouseRegion(
        key: ValueKey('forum-tab-pointer-${widget.item.id}'),
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          setState(() => _hovered = true);
          widget.onHoverChanged(true);
        },
        onExit: (_) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        },
        child: AnimatedContainer(
          key: ValueKey('forum-tab-item-${widget.item.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: ForumTabsBar._tabContentInset,
          ),
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          decoration: ShapeDecoration(
            color: widget.selected
                ? theme.shell.content
                : _hovered
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            shape: _ForumTabShape(
              selected: widget.selected,
              side: widget.dropTarget
                  ? BorderSide(color: theme.colorScheme.primary, width: 2)
                  : BorderSide.none,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _renaming
                    ? LayoutBuilder(
                        builder: (context, constraints) =>
                            _tabContents(context, foreground, constraints),
                      )
                    : ExcludeSemantics(
                        child: InkWell(
                          onTapDown: _handleTapDown,
                          onTap: _handleTap,
                          onDoubleTap: widget.onRename == null
                              ? null
                              : _startRenaming,
                          onTapCancel: _handleTapCancel,
                          hoverColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) =>
                                _tabContents(context, foreground, constraints),
                          ),
                        ),
                      ),
              ),
              _ForumTabCloseButton(
                tabId: widget.item.id,
                tabHovered: _hovered,
                label: closeLabel,
                foreground: foreground,
                shortcut: DShortcut(
                  primaryShortcutForPlatform(
                    Theme.of(context).platform,
                    LogicalKeyboardKey.keyW,
                  ),
                ),
                onPressed: widget.onClose,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ForumTabShape extends OutlinedBorder {
  const _ForumTabShape({required this.selected, super.side});

  final bool selected;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  _ForumTabShape copyWith({BorderSide? side}) =>
      _ForumTabShape(selected: selected, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) => copyWith(side: side.scale(t));

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is _ForumTabShape
      ? copyWith(side: BorderSide.lerp(a.side, side, t))
      : super.lerpFrom(a, t);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    if (!selected) {
      return Path()..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left + 2,
            rect.top + 2,
            rect.right - 2,
            rect.bottom - 3,
          ),
          const Radius.circular(12),
        ),
      );
    }

    // Keep the outward feet inside the tab's bounds so scrolling and adjacent
    // hover surfaces cannot clip or paint over the connection to the content.
    const foot = 4.0;
    const radius = 12.0;
    final Rect(:left, :top, :right, :bottom) = rect;
    return Path()
      ..moveTo(left, bottom)
      ..quadraticBezierTo(left + foot, bottom, left + foot, bottom - foot)
      ..lineTo(left + foot, top + radius)
      ..quadraticBezierTo(left + foot, top, left + foot + radius, top)
      ..lineTo(right - foot - radius, top)
      ..quadraticBezierTo(right - foot, top, right - foot, top + radius)
      ..lineTo(right - foot, bottom - foot)
      ..quadraticBezierTo(right - foot, bottom, right, bottom)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(
      getOuterPath(rect.deflate(side.width / 2), textDirection: textDirection),
      side.toPaint(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _ForumTabShape &&
      other.selected == selected &&
      other.side == side;

  @override
  int get hashCode => Object.hash(selected, side);
}

class _ForumTabActions extends StatefulWidget {
  const _ForumTabActions({
    required this.tabId,
    required this.selected,
    required this.label,
    required this.onTap,
    required this.onClose,
    required this.onCloseOthers,
    this.customSemanticsActions,
    required this.child,
  });

  final String tabId;
  final bool selected;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;
  final Widget child;

  @override
  State<_ForumTabActions> createState() => _ForumTabActionsState();
}

class _ForumTabActionsState extends State<_ForumTabActions> {
  static const _showActions = CustomSemanticsAction(label: 'Show tab actions');

  final MenuController _menu = MenuController();

  void _open(Offset? position) {
    if (_menu.isOpen) return;
    _menu.open(position: position);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      key: ValueKey('forum-tab-${widget.tabId}'),
      role: SemanticsRole.tab,
      container: true,
      explicitChildNodes: true,
      selected: widget.selected,
      label: widget.label,
      onTap: widget.onTap,
      customSemanticsActions: {
        ...?widget.customSemanticsActions,
        _showActions: () => _open(null),
      },
      child: MenuAnchor(
        controller: _menu,
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(theme.shell.floating),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        menuChildren: [
          MenuItemButton(
            key: ValueKey('forum-tab-menu-close-${widget.tabId}'),
            shortcut: widget.selected
                ? primaryShortcutForPlatform(
                    Theme.of(context).platform,
                    LogicalKeyboardKey.keyW,
                  )
                : null,
            onPressed: widget.onClose,
            child: const Text('Close tab'),
          ),
          MenuItemButton(
            key: ValueKey('forum-tab-menu-close-others-${widget.tabId}'),
            onPressed: widget.onCloseOthers,
            child: const Text('Close other tabs'),
          ),
        ],
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
                _open(null),
            const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
                _open(null),
          },
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (event.buttons & kSecondaryButton != 0) {
                _open(event.localPosition);
              }
            },
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _ForumTabCloseButton extends StatefulWidget {
  const _ForumTabCloseButton({
    required this.tabId,
    required this.tabHovered,
    required this.label,
    required this.foreground,
    required this.shortcut,
    required this.onPressed,
  });

  final String tabId;
  final bool tabHovered;
  final String label;
  final Color foreground;
  final DShortcut? shortcut;
  final VoidCallback onPressed;

  @override
  State<_ForumTabCloseButton> createState() => _ForumTabCloseButtonState();
}

class _ForumTabCloseButtonState extends State<_ForumTabCloseButton> {
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      key: ValueKey('forum-tab-close-${widget.tabId}'),
      container: true,
      button: true,
      label: widget.label,
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: DTooltip(
          message: widget.label,
          shortcut: widget.shortcut,
          excludeFromSemantics: true,
          child: SizedBox(
            width: ForumTabsBar.closeTargetWidth,
            height: double.infinity,
            child: IconButton(
              statesController: _states,
              constraints: const BoxConstraints.expand(),
              padding: EdgeInsets.zero,
              style: const ButtonStyle(
                overlayColor: WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
              ),
              onPressed: widget.onPressed,
              icon: ValueListenableBuilder<Set<WidgetState>>(
                valueListenable: _states,
                builder: (context, states, _) {
                  final emphasized =
                      states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused) ||
                      states.contains(WidgetState.pressed);
                  return AnimatedOpacity(
                    opacity: widget.tabHovered || emphasized ? 1 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 100),
                    child: AnimatedContainer(
                      key: ValueKey('forum-tab-close-surface-${widget.tabId}'),
                      width: 24,
                      height: 24,
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 100),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: emphasized
                            ? theme.shell.selected
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: DIcon(
                        DIcons.xmark,
                        size: 12,
                        color: emphasized
                            ? theme.colorScheme.onSurface
                            : widget.foreground,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

@immutable
final class _CurrentForumTabsSnapshot {
  const _CurrentForumTabsSnapshot({
    required this.siteUrl,
    required this.forumName,
    required this.tabs,
    required this.recentlyClosedTabs,
    required this.activeTabId,
    required this.presentationToken,
  });

  final String? siteUrl;
  final String? forumName;
  final List<ForumTab> tabs;
  final List<ForumTab> recentlyClosedTabs;
  final String? activeTabId;
  final Object? presentationToken;

  @override
  bool operator ==(Object other) =>
      other is _CurrentForumTabsSnapshot &&
      siteUrl == other.siteUrl &&
      forumName == other.forumName &&
      identical(tabs, other.tabs) &&
      _sameTabs(recentlyClosedTabs, other.recentlyClosedTabs) &&
      activeTabId == other.activeTabId &&
      identical(presentationToken, other.presentationToken);

  static bool _sameTabs(List<ForumTab> left, List<ForumTab> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!identical(left[index], right[index])) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    siteUrl,
    forumName,
    identityHashCode(tabs),
    Object.hashAll(recentlyClosedTabs.map(identityHashCode)),
    activeTabId,
    identityHashCode(presentationToken),
  );
}

class CurrentForumTabsBar extends StatelessWidget {
  const CurrentForumTabsBar({super.key});

  @override
  Widget build(BuildContext context) =>
      ShellSelector<_CurrentForumTabsSnapshot>(
        select: (controller) {
          final instance = controller.currentInstance;
          return _CurrentForumTabsSnapshot(
            siteUrl: instance?.url,
            forumName: instance?.title,
            tabs: controller.tabsForCurrentForum,
            recentlyClosedTabs: controller.recentlyClosedTabsForCurrentForum,
            activeTabId: controller.activeTabId,
            presentationToken: instance == null
                ? null
                : controller.presentationTokenFor(instance.url),
          );
        },
        builder: (context, state, _) {
          final siteUrl = state.siteUrl;
          final forumName = state.forumName;
          final activeTabId = state.activeTabId;
          if (siteUrl == null ||
              forumName == null ||
              activeTabId == null ||
              state.tabs.isEmpty) {
            return const SizedBox.shrink();
          }

          final controller = ShellScope.read(context);
          final registry = PluginScope.of(context).registry;
          return ListenableBuilder(
            listenable: Listenable.merge(
              registry.forumTabListenables(context, siteUrl),
            ),
            builder: (context, _) {
              ForumTabItem itemFor(ForumTab tab) {
                final route = tab.currentContent;
                final destination = registry.forumTabDestination(
                  context,
                  siteUrl,
                  tab,
                );
                if (destination != null) {
                  final emoji = destination.emoji;
                  return ForumTabItem(
                    id: tab.id,
                    title: destination.label,
                    siteUrl: siteUrl,
                    icon: destination.icon,
                    color: destination.color,
                    parentColor: destination.parentColor,
                    iconColor: destination.iconColor,
                    avatarUrl: destination.avatarUrl,
                    prefixBuilder: destination.prefixBuilder,
                    labelSuffixBuilder: destination.labelSuffixBuilder,
                    semanticDescription: destination.semanticDescription,
                    emojiUrl: emoji == null
                        ? null
                        : controller.emojiUrlFor(siteUrl, emoji),
                    emojiName: emoji,
                    badge: destination.badge ?? SidebarBadge.none,
                  );
                }

                return ForumTabItem(
                  id: tab.id,
                  title: route.title,
                  siteUrl: siteUrl,
                  icon: route.icon,
                  color: route.color,
                );
              }

              return ForumTabsBar(
                key: ValueKey(('forum-tabs', siteUrl)),
                forumName: forumName,
                items: [for (final tab in state.tabs) itemFor(tab)],
                recentlyClosedItems: [
                  for (final tab in state.recentlyClosedTabs) itemFor(tab),
                ],
                selectedId: activeTabId,
                onAdd: controller.canCreateTab ? controller.createTab : null,
                onSelect: controller.selectTab,
                onClose: controller.closeTab,
                onReorder: controller.moveTab,
                onCloseOthers: controller.closeOtherTabs,
                onReopen: controller.canCreateTab
                    ? (id) => controller.reopenClosedTab(id)
                    : null,
              );
            },
          );
        },
      );
}
