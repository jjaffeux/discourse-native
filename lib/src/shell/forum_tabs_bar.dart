import 'dart:async';
import 'dart:math' as math;

import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/gestures.dart' show kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../app_shortcuts.dart';
import '../models/forum_workspace.dart';
import '../models/sidebar.dart';
import '../plugin_api/plugin_registry.dart';
import '../plugin_api/plugin_scope.dart';
import '../theme/app_theme.dart';
import '../theme/d_icons.dart';
import 'avatar_image.dart';
import 'emoji.dart';
import 'open_link.dart';
import 'panel_rail.dart';
import 'shell_controller.dart';
import 'shell_metrics.dart';
import 'shell_scope.dart';
import 'site_emoji_text.dart';
import 'start_page_drag.dart';

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

  Object get _presentation => (
    id,
    title,
    siteUrl,
    icon,
    color,
    parentColor,
    iconColor,
    avatarUrl,
    prefixBuilder,
    labelSuffixBuilder,
    semanticDescription,
    emojiUrl,
    emojiName,
    badge,
  );
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
    this.showAdd = true,
    this.acceptsTab,
    this.onDropTab,
    this.incomingTab,
    this.itemForDrop,
    this.acceptsLink,
    this.onDropLink,
    this.panel,
    this.onMoveToPanel,
  }) : assert(items.isNotEmpty),
       assert(items.any((item) => item.id == selectedId));

  static const double height = workspaceTabStripHeight;

  static double heightFor(BuildContext context) =>
      workspaceTabStripHeightFor(context);

  static const double minimumActionTarget = 30;

  static const double _tabContentInset = 2;

  static const double maximumTabWidth = 170;

  static const double closeTargetWidth = 18;

  final bool showAdd;
  final bool Function(String id)? acceptsTab;
  final void Function(String id, int index)? onDropTab;
  final ForumTabItem? incomingTab;
  final ForumTabItem? Function(String id)? itemForDrop;
  final bool Function(StartPageDrag link)? acceptsLink;
  final void Function(StartPageDrag link, int index)? onDropLink;
  final ForumPanel? panel;
  final void Function(String id, ForumPanel panel)? onMoveToPanel;
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
  static const _tabGap = 6.0;
  static const _switcherGap = 8.0;
  Widget? _contents;
  final _barKey = GlobalKey();
  final _tabKeys = <String, GlobalKey>{};
  ForumTabItem? _dropItem;
  int _dropIndex = 0;
  String? _geometryTabId;
  List<double> _tabCenters = const [];
  List<Rect> _tabRects = const [];

  void _captureDropGeometry(String id) {
    if (_geometryTabId == id) return;
    _geometryTabId = id;
    _tabRects = [
      for (final item in widget.items)
        if (_tabKeys[item.id]?.currentContext?.findRenderObject()
            case final RenderBox box)
          box.localToGlobal(Offset.zero) & box.size,
    ];
    _tabCenters = [for (final rect in _tabRects) rect.center.dx];
  }

  void _scheduleGeometryReset() {
    // Crossing a child DragTarget leaves and re-enters this target in one
    // pointer event. Keep the original geometry through that transition.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _dropItem == null && widget.incomingTab == null) {
        _geometryTabId = null;
        _tabCenters = const [];
        _tabRects = const [];
      }
    });
  }

  /// The gap [id] would be inserted into when dropped at [position].
  ///
  /// The two gaps touching a strip tab's own slot would not move it, so a
  /// neighbour answers its far side wherever the pointer is on it, and the
  /// slot itself answers a gap that [_destinationFor] declines.
  int _indexAt(String id, Offset position) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    var gap = widget.items.length;
    for (var index = 0; index < _tabCenters.length; index++) {
      if (rtl
          ? position.dx > _tabCenters[index]
          : position.dx < _tabCenters[index]) {
        gap = index;
        break;
      }
    }
    final source = widget.items.indexWhere((item) => item.id == id);
    if (source < 0 || _tabRects.length != widget.items.length) return gap;
    final slot = _tabRects[source];
    if (position.dx >= slot.left && position.dx <= slot.right) return source;
    if (gap == source && source > 0) return source - 1;
    if (gap == source + 1 && source + 2 <= widget.items.length) {
      return source + 2;
    }
    return gap;
  }

  /// Where [id] lands when dropped at gap [insertion], or null when that gap
  /// borders the tab's own slot and dropping there would not move it.
  int? _destinationFor(String id, int insertion) {
    final source = widget.items.indexWhere((item) => item.id == id);
    if (source < 0) return insertion;
    if (insertion == source || insertion == source + 1) return null;
    return source < insertion ? insertion - 1 : insertion;
  }

  /// The strip's own tabs and tabs arriving from another strip share one
  /// insertion bar, so every strip reorders the same way whether or not it
  /// can also receive tabs.
  ForumTabItem? _droppable(String id) {
    for (final item in widget.items) {
      if (item.id == id) {
        return (widget.acceptsTab?.call(id) ?? true) ? item : null;
      }
    }
    return widget.onDropTab == null ? null : widget.itemForDrop?.call(id);
  }

  bool _startDrop(DragTargetDetails<String> details) {
    final item = _droppable(details.data);
    if (item == null) return false;
    _captureDropGeometry(item.id);
    setState(() {
      _dropItem = item;
      _dropIndex = _indexAt(item.id, details.offset);
      _contents = null;
    });
    return true;
  }

  bool _startLinkDrop(DragTargetDetails<StartPageDrag> details) {
    if (widget.onDropLink == null ||
        !(widget.acceptsLink?.call(details.data) ?? false)) {
      return false;
    }
    final item = ForumTabItem(
      id: 'incoming-start-page-link',
      title: details.data.title,
      icon: DIcons.link,
    );
    _captureDropGeometry(item.id);
    setState(() {
      _dropItem = item;
      _dropIndex = _indexAt(item.id, details.offset);
      _contents = null;
    });
    return true;
  }

  void _moveLinkDrop(DragTargetDetails<StartPageDrag> details) {
    if (_dropItem == null) return;
    final index = _indexAt('incoming-start-page-link', details.offset);
    if (index == _dropIndex) return;
    setState(() {
      _dropIndex = index;
      _contents = null;
    });
  }

  void _moveDrop(DragTargetDetails<String> details) {
    if (_dropItem == null) return;
    final index = _indexAt(details.data, details.offset);
    if (index == _dropIndex) return;
    setState(() {
      _dropIndex = index;
      _contents = null;
    });
  }

  void _clearDrop() {
    if (_dropItem == null) return;
    setState(() {
      _dropItem = null;
      _contents = null;
    });
    _scheduleGeometryReset();
  }

  static bool _sameItems(List<ForumTabItem> a, List<ForumTabItem> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index]._presentation != b[index]._presentation) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(ForumTabsBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tabKeys.removeWhere((id, _) => !widget.items.any((tab) => tab.id == id));
    if (widget.incomingTab case final item?) {
      _captureDropGeometry(item.id);
    } else if (oldWidget.incomingTab != null) {
      _scheduleGeometryReset();
    }
    // Reading anchors and plugin notifications can replace the input models
    // without changing any tab. Keep their control trees mounted and clean.
    // Callbacks below delegate through `widget` so they always stay current.
    if (widget.forumName != oldWidget.forumName ||
        widget.selectedId != oldWidget.selectedId ||
        widget.showAdd != oldWidget.showAdd ||
        widget.incomingTab?._presentation !=
            oldWidget.incomingTab?._presentation ||
        (widget.onDropTab == null) != (oldWidget.onDropTab == null) ||
        (widget.onAdd == null) != (oldWidget.onAdd == null) ||
        (widget.onReopen == null) != (oldWidget.onReopen == null) ||
        (widget.onRename == null) != (oldWidget.onRename == null) ||
        widget.panel != oldWidget.panel ||
        (widget.onMoveToPanel == null) != (oldWidget.onMoveToPanel == null) ||
        !_sameItems(widget.items, oldWidget.items) ||
        !_sameItems(
          widget.recentlyClosedItems,
          oldWidget.recentlyClosedItems,
        )) {
      _contents = null;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _contents = null;
  }

  @override
  void reassemble() {
    super.reassemble();
    _contents = null;
  }

  @override
  Widget build(BuildContext context) => DragTarget<StartPageDrag>(
    onWillAcceptWithDetails: _startLinkDrop,
    onMove: _moveLinkDrop,
    onLeave: (_) => _clearDrop(),
    onAcceptWithDetails: (details) {
      final index = _indexAt('incoming-start-page-link', details.offset);
      _clearDrop();
      widget.onDropLink?.call(details.data, index);
    },
    builder: (context, links, rejectedLinks) => DragTarget<String>(
      onWillAcceptWithDetails: _startDrop,
      onMove: _moveDrop,
      onLeave: (_) => _clearDrop(),
      onAcceptWithDetails: (details) {
        final destination = _destinationFor(
          details.data,
          _indexAt(details.data, details.offset),
        );
        _clearDrop();
        if (destination == null || _droppable(details.data) == null) return;
        (widget.onDropTab ?? widget.onReorder)(details.data, destination);
      },
      // Build against this State's context: its inherited reads (text scale,
      // theme, direction) must reach didChangeDependencies, which is what
      // discards the cached contents. The builder's own context would only
      // rebuild the builder and keep returning the stale strip.
      builder: (_, candidates, rejected) =>
          _contents ??= _buildContents(this.context),
    ),
  );

  Widget _buildContents(BuildContext context) {
    final incoming = _dropItem ?? widget.incomingTab;
    final insertion = _dropItem == null
        ? widget.items.length
        : _dropIndex.clamp(0, widget.items.length);
    final tabCount = widget.items.length;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    double? indicatorLeft;
    if (incoming != null &&
        _tabRects.length == tabCount &&
        tabCount > 0 &&
        _destinationFor(incoming.id, insertion) != null) {
      final previous = insertion == 0 ? null : _tabRects[insertion - 1];
      final next = insertion == tabCount ? null : _tabRects[insertion];
      final position = previous == null
          ? (rtl ? next!.right + _tabGap / 2 : next!.left - _tabGap / 2)
          : next == null
          ? (rtl ? previous.left - _tabGap / 2 : previous.right + _tabGap / 2)
          : (rtl
                ? (previous.left + next.right) / 2
                : (previous.right + next.left) / 2);
      if (_barKey.currentContext?.findRenderObject() case final RenderBox box) {
        indicatorLeft = position - box.localToGlobal(Offset.zero).dx - 1.5;
      }
    }
    return Container(
      key: const ValueKey('forum-tabs-bar'),
      width: double.infinity,
      height: ForumTabsBar.heightFor(context),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Stack(
        key: _barKey,
        children: [
          Positioned.fill(
            // Only the tabs take the strip's vertical inset. The switcher and
            // add actions are regular-size squares, taller than that inset
            // leaves, so they center on the full strip instead of being
            // squashed into the tab lane.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    widthFactor: 1,
                    child: _ForumTabSwitcher(
                      forumName: widget.forumName,
                      items: widget.items,
                      selectedId: widget.selectedId,
                      recentlyClosedItems: widget.recentlyClosedItems,
                      onSelect: (id) => widget.onSelect(id),
                      onClose: (id) => widget.onClose(id),
                      onReopen: widget.onReopen == null
                          ? null
                          : (id) => widget.onReopen!(id),
                    ),
                  ),
                  const SizedBox(width: _switcherGap),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scaler = MediaQuery.textScalerOf(context);
                        final closeWidth = DControlStyle.scaledHeight(
                          DControlSize.tabClose,
                          scaler,
                          context: context,
                        );
                        final addWidth = DControlStyle.scaledHeight(
                          DControlSize.tabAction,
                          scaler,
                          context: context,
                        );
                        // Reserve the active tab's close action and outer
                        // insets before sharing the remaining width. Otherwise
                        // crowded tabs can squeeze the close button past its row.
                        final selectedWidth =
                            closeWidth + 2 * ForumTabsBar._tabContentInset;
                        final labelWidth = math.max(
                          0.0,
                          (constraints.maxWidth -
                                  (widget.showAdd ? addWidth + 6 : 0) -
                                  _tabGap * (tabCount - 1) -
                                  selectedWidth) /
                              tabCount,
                        );
                        return Row(
                          children: [
                            Flexible(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10.5,
                                ),
                                child: Semantics(
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
                                        ConstrainedBox(
                                          key: _tabKeys.putIfAbsent(
                                            widget.items[index].id,
                                            () => GlobalKey(),
                                          ),
                                          constraints: BoxConstraints(
                                            maxWidth: math.min(
                                              ForumTabsBar.maximumTabWidth,
                                              labelWidth +
                                                  (widget.items[index].id ==
                                                          widget.selectedId
                                                      ? selectedWidth
                                                      : 0),
                                            ),
                                          ),
                                          child: _ReorderableForumTab(
                                            item: widget.items[index],
                                            index: index,
                                            itemCount: widget.items.length,
                                            movesBetweenStrips:
                                                widget.onDropTab != null,
                                            selected:
                                                widget.items[index].id ==
                                                widget.selectedId,
                                            onSelect: () => widget.onSelect(
                                              widget.items[index].id,
                                            ),
                                            onClose: () => widget.onClose(
                                              widget.items[index].id,
                                            ),
                                            onReorder: (id, index) =>
                                                widget.onReorder(id, index),
                                            onCloseOthers:
                                                widget.items.length == 1
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
                                            moveToPanel:
                                                widget.panel == null ||
                                                    widget.onMoveToPanel == null
                                                ? null
                                                : () => widget.onMoveToPanel!(
                                                    widget.items[index].id,
                                                    widget.panel ==
                                                            ForumPanel.main
                                                        ? ForumPanel.secondary
                                                        : ForumPanel.main,
                                                  ),
                                            moveToPanelLabel:
                                                widget.panel == null
                                                ? null
                                                : widget.panel ==
                                                      ForumPanel.main
                                                ? 'Move to secondary panel'
                                                : 'Move to main panel',
                                          ),
                                        ),
                                        if (index != widget.items.length - 1)
                                          const SizedBox(width: _tabGap),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (widget.showAdd) ...[
                              const SizedBox(width: 6),
                              _NewTabButton(
                                onPressed: widget.onAdd == null
                                    ? null
                                    : () => widget.onAdd!(),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (incoming != null && indicatorLeft != null)
            Positioned(
              left: indicatorLeft,
              top: (ForumTabsBar.heightFor(context) - 28) / 2,
              width: 3,
              height: 28,
              child: IgnorePointer(
                child: _ForumTabDropPlaceholder(item: incoming),
              ),
            ),
        ],
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
  final DPopoverController _menu = DPopoverController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'tab switcher search');
  bool _historyExpanded = false;

  @override
  void dispose() {
    _menu.dispose();
    _searchFocus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _handleOpen() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu.isOpen) _searchFocus.requestFocus();
    });
  }

  void _handleClose() {
    _searchFocus.unfocus();
    _search.clear();
    if (mounted) {
      setState(() {
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
    final viewportSize = MediaQuery.sizeOf(context);
    final panelWidth = math.max(0.0, math.min(500.0, viewportSize.width - 16));
    final availablePanelHeight = math.max(
      0.0,
      viewportSize.height -
          MediaQuery.paddingOf(context).vertical -
          MediaQuery.viewInsetsOf(context).bottom -
          72,
    );
    final openItems = widget.items.where(_matches).toList(growable: false);
    final closedItems = widget.recentlyClosedItems
        .where(_matches)
        .toList(growable: false);

    return Center(
      widthFactor: 1,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        child: DPopover(
          controller: _menu,
          focusContentOnOpen: false,
          onOpenChange: (open, reason) {
            if (open) {
              _handleOpen();
            } else {
              _handleClose();
            }
          },
          content: DPopoverContent(
            semanticLabel: 'Browse tabs',
            width: panelWidth,
            padding: EdgeInsets.zero,
            scrollable: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                      DInput(
                        key: const ValueKey('forum-tabs-switcher-search'),
                        controller: _search,
                        focusNode: _searchFocus,
                        onChanged: (_) => setState(() {}),
                        textInputAction: TextInputAction.search,
                        hintText: 'Search tabs…',
                        prefix: const DIcon(DIcons.magnifyingGlass),
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
                                DSeparator(
                                  space: 1,
                                  color: theme.shell.divider,
                                ),
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
            ),
          ),
          child: DPopoverTrigger(
            builder: (context, state) => DButton.iconOnly(
              key: const ValueKey('forum-tabs-switcher'),
              semanticLabel: 'Browse tabs in ${widget.forumName}',
              tooltip: 'Browse tabs',
              variant: DButtonVariant.outline,
              size: DControlSize.tabAction,
              icon: const DIcon(DIcons.chevronDown),
              focusNode: state.focusNode,
              hasPopup: true,
              expanded: state.open,
              onPressed: state.toggle,
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
      style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
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
  Widget build(BuildContext context) => DButton.iconOnly(
    onPressed: onPressed,
    variant: DButtonVariant.ghost,
    tooltip: label,
    icon: DIcon(icon),
  );
}

Widget? _tabPrefix(
  BuildContext context,
  ForumTabItem item,
  Color foreground, {
  double size = 15,
  double? avatarSize,
}) {
  final theme = Theme.of(context);

  if (item.prefixBuilder case final builder?) {
    return builder(context, size);
  }

  if (item.avatarUrl case final url?) {
    final dimension = avatarSize ?? size + 1;
    return DAvatar.frame(
      child: SizedBox.square(
        dimension: dimension,
        child: AvatarImage(
          url: url,
          size: dimension,
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
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onReorder,
    required this.onCloseOthers,
    this.onRename,
    this.movesBetweenStrips = false,
    this.moveToPanel,
    this.moveToPanelLabel,
  });

  /// Whether another strip can receive this tab, which frees the drag from
  /// the strip's axis. The drop itself is always handled by [ForumTabsBar].
  final bool movesBetweenStrips;
  final ForumTabItem item;
  final int index;
  final int itemCount;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final void Function(String id, int newIndex) onReorder;
  final VoidCallback? onCloseOthers;
  final ValueChanged<String>? onRename;
  final VoidCallback? moveToPanel;
  final String? moveToPanelLabel;

  _ForumTab _tab({required bool selectOnPointerDown}) => _ForumTab(
    key: ValueKey(item.id),
    item: item,
    selected: selected,
    selectOnPointerDown: selectOnPointerDown,
    onSelect: onSelect,
    onClose: onClose,
    onCloseOthers: onCloseOthers,
    onRename: onRename,
    moveToPanel: moveToPanel,
    moveToPanelLabel: moveToPanelLabel,
    onMoveLeft: index == 0 ? null : () => onReorder(item.id, index - 1),
    onMoveRight: index == itemCount - 1
        ? null
        : () => onReorder(item.id, index + 1),
  );

  @override
  Widget build(BuildContext context) {
    if (itemCount < 2 && !movesBetweenStrips) {
      return _tab(selectOnPointerDown: true);
    }

    return Listener(
      onPointerDown: (event) {
        if (event.buttons == kPrimaryButton &&
            event.localPosition.dx <
                (context.findRenderObject()! as RenderBox).size.width -
                    (selected
                        ? DControlStyle.scaledHeight(
                            DControlSize.tabClose,
                            MediaQuery.textScalerOf(context),
                            context: context,
                          )
                        : 0) -
                    ForumTabsBar._tabContentInset) {
          onSelect();
        }
      },
      child: Draggable<String>(
        data: item.id,
        axis: movesBetweenStrips ? null : Axis.horizontal,
        // Target offsets follow the pointer. Keep the floating tab below
        // it so the insertion placeholder remains visible in the strip.
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: Transform.translate(
          offset: Offset(DSpacing.md, ForumTabsBar.heightFor(context) / 2),
          child: ForumTabDragFeedback(
            item: item,
            width: ForumTabsBar.maximumTabWidth,
          ),
        ),
        child: _tab(selectOnPointerDown: false),
      ),
    );
  }
}

class _ForumTabDropPlaceholder extends StatelessWidget {
  const _ForumTabDropPlaceholder({required this.item});

  final ForumTabItem item;

  @override
  Widget build(BuildContext context) => Semantics(
    key: const ValueKey('forum-tab-drop-placeholder'),
    role: SemanticsRole.tab,
    selected: false,
    enabled: false,
    label: 'Drop ${item.title} here',
    liveRegion: true,
    child: Center(
      child: Container(
        width: 3,
        height: 28,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

class ForumTabDragFeedback extends StatelessWidget {
  const ForumTabDragFeedback({
    super.key,
    required this.item,
    required this.width,
  });

  final ForumTabItem item;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: width,
        height: ForumTabsBar.heightFor(context) - 21,
        child: DDocumentTab(
          size: DControlSize.documentTab,
          selected: true,
          onSelect: () {},
          onClose: () {},
          closeLabel: 'Close ${item.title}',
          child: Row(
            children: [
              if (item.icon case final icon?) ...[
                DIcon(icon, size: 12, color: item.iconColor),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewTabButton extends StatelessWidget {
  const _NewTabButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Center(
    widthFactor: 1,
    child: DButton.iconOnly(
      key: const ValueKey('forum-tabs-add'),
      tooltip: onPressed == null
          ? 'Close a tab before opening another'
          : 'Open a new tab',
      shortcut: onPressed == null
          ? null
          : DShortcut(
              primaryShortcutForPlatform(
                Theme.of(context).platform,
                LogicalKeyboardKey.keyT,
              ),
            ),
      variant: DButtonVariant.inline,
      size: DControlSize.tabAction,
      icon: const DIcon(DIcons.plus),
      onPressed: onPressed,
    ),
  );
}

class _ForumTab extends StatefulWidget {
  const _ForumTab({
    super.key,
    required this.item,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    this.selectOnPointerDown = true,
    this.onMoveLeft,
    this.onMoveRight,
    this.onRename,
    this.moveToPanel,
    this.moveToPanelLabel,
  });

  final ForumTabItem item;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final bool selectOnPointerDown;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final ValueChanged<String>? onRename;
  final VoidCallback? moveToPanel;
  final String? moveToPanelLabel;

  @override
  State<_ForumTab> createState() => _ForumTabState();
}

class _ForumTabState extends State<_ForumTab> {
  static const _renameAction = CustomSemanticsAction(label: 'Rename');
  static const _dotGap = 3.0;

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
      return DNotificationDot(
        key: ValueKey('forum-tab-badge-${widget.item.id}'),
        color: badge.urgent
            ? theme.discourse.success
            : theme.discourse.unreadIndicator,
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
        color: badge.urgent ? theme.discourse.success : theme.shell.selected,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        '${badge.count}',
        style: theme.textTheme.labelSmall?.copyWith(
          color: badge.urgent
              ? theme.discourse.notificationForeground
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
    // DButton has already applied selection padding to these constraints.
    final leadingWidth = hasPrefix ? 22 : 0;
    if (badge.dot) return selectWidth >= leadingWidth + _dotGap + 8;
    final painter = TextPainter(
      text: TextSpan(
        text: '${badge.count}',
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      textDirection: DDirection.of(context),
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
    // Keep the title readable before spending narrow-tab space on adornments.
    final compact =
        constraints.maxWidth < MediaQuery.textScalerOf(context).scale(60);
    final hasAvatar =
        widget.item.avatarUrl != null && widget.item.prefixBuilder == null;
    final prefixSize = hasAvatar ? 16.0 : 12.0;
    final prefix = !compact
        ? _tabPrefix(
            context,
            widget.item,
            foreground,
            size: 12,
            avatarSize: prefixSize,
          )
        : null;
    // Tab labels are controls: the same role as DDocumentTab's own default
    // and the drag feedback, so a dragged tab keeps its size.
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: foreground,
      fontWeight: FontWeight.w400,
    );
    final label = switch (widget.item.siteUrl) {
      final siteUrl? => SiteEmojiText.plain(
        widget.item.title,
        siteUrl: siteUrl,
        maxLines: 1,
        overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
        style: labelStyle,
      ),
      null => Text(
        widget.item.title,
        maxLines: 1,
        overflow: compact ? TextOverflow.clip : TextOverflow.ellipsis,
        style: labelStyle,
      ),
    };
    return Row(
      children: [
        if (prefix != null) ...[
          SizedBox.square(
            dimension: prefixSize,
            child: Center(child: prefix),
          ),
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
                    if (!compact)
                      if (widget.item.labelSuffixBuilder case final builder?)
                        builder(context, 13),
                    if (!compact &&
                        widget.item.badge.dot &&
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
        if (!compact &&
            !_renaming &&
            !widget.item.badge.dot &&
            _badgeFits(
              context,
              constraints.maxWidth,
              hasPrefix: prefix != null,
            ))
          _badge(context),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => IntrinsicWidth(
        child: _ForumTabActions(
          tabId: widget.item.id,
          selected: widget.selected,
          label: _renaming ? null : _selectionSemanticsLabel,
          onTap: widget.onSelect,
          customSemanticsActions: {
            if (widget.onRename != null) _renameAction: _startRenaming,
            const CustomSemanticsAction(label: 'Move left'): ?widget.onMoveLeft,
            const CustomSemanticsAction(label: 'Move right'):
                ?widget.onMoveRight,
          },
          onClose: widget.onClose,
          onCloseOthers: widget.onCloseOthers,
          moveToPanel: widget.moveToPanel,
          moveToPanelLabel: widget.moveToPanelLabel,
          child: DDocumentTab(
            size: DControlSize.documentTab,
            excludeSelectionSemantics: true,
            surfaceKey: ValueKey('forum-tab-item-${widget.item.id}'),
            pointerKey: ValueKey('forum-tab-pointer-${widget.item.id}'),
            closeKey: ValueKey('forum-tab-close-${widget.item.id}'),
            selected: widget.selected,
            closeOnlyWhenSelected: true,
            onSelect: _handleTap,
            onTapDown: _handleTapDown,
            onTapCancel: _handleTapCancel,
            onDoubleTap: widget.onRename == null ? null : _startRenaming,
            onClose: widget.onClose,
            closeLabel: 'Close ${widget.item.title}',
            closeShortcut: DShortcut(
              primaryShortcutForPlatform(
                Theme.of(context).platform,
                LogicalKeyboardKey.keyW,
              ),
            ),
            editor: _renaming ? _contents(constraints) : null,
            child: ExcludeSemantics(child: _contents(constraints)),
          ),
        ),
      ),
    );
  }

  Widget _contents(BoxConstraints constraints) => Builder(
    builder: (context) => _tabContents(
      context,
      DefaultTextStyle.of(context).style.color!,
      // Intrinsic sizing needs the content tree without a nested LayoutBuilder.
      // Badge visibility uses the available width after Native control insets.
      constraints.deflate(
        EdgeInsets.symmetric(
          horizontal:
              ForumTabsBar._tabContentInset +
              8 +
              (widget.selected
                  ? DControlStyle.scaledHeight(
                          DControlSize.tabClose,
                          MediaQuery.textScalerOf(context),
                          context: context,
                        ) /
                        2
                  : 0),
        ),
      ),
    ),
  );
}

class _ForumTabActions extends StatefulWidget {
  const _ForumTabActions({
    required this.tabId,
    required this.selected,
    required this.label,
    required this.onTap,
    required this.onClose,
    required this.onCloseOthers,
    this.moveToPanel,
    this.moveToPanelLabel,
    this.customSemanticsActions,
    required this.child,
  });

  final String tabId;
  final bool selected;
  final String? label;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback? onCloseOthers;
  final VoidCallback? moveToPanel;
  final String? moveToPanelLabel;
  final Map<CustomSemanticsAction, VoidCallback>? customSemanticsActions;
  final Widget child;

  @override
  State<_ForumTabActions> createState() => _ForumTabActionsState();
}

class _ForumTabActionsState extends State<_ForumTabActions> {
  static const _showActions = CustomSemanticsAction(label: 'Show tab actions');
  final _trigger = DContextMenuTriggerController();

  @override
  Widget build(BuildContext context) => Semantics(
    key: ValueKey('forum-tab-${widget.tabId}'),
    role: SemanticsRole.tab,
    container: true,
    explicitChildNodes: true,
    selected: widget.selected,
    label: widget.label,
    onTap: widget.onTap,
    customSemanticsActions: {
      ...?widget.customSemanticsActions,
      _showActions: _trigger.openFromKeyboard,
    },
    child: DContextMenu(
      content: DContextMenuContent(
        semanticLabel: 'Tab actions',
        width: 280,
        children: [
          if (widget.moveToPanel != null)
            DContextMenuItem(
              key: ValueKey('forum-tab-menu-move-${widget.tabId}'),
              onPressed: widget.moveToPanel,
              child: Text(widget.moveToPanelLabel!),
            ),
          DContextMenuItem(
            key: ValueKey('forum-tab-menu-close-${widget.tabId}'),
            trailing: widget.selected
                ? DShortcutKeycaps(
                    shortcut: DShortcut(
                      primaryShortcutForPlatform(
                        Theme.of(context).platform,
                        LogicalKeyboardKey.keyW,
                      ),
                    ),
                  )
                : null,
            onPressed: widget.onClose,
            child: const Text('Close tab'),
          ),
          DContextMenuItem(
            key: ValueKey('forum-tab-menu-close-others-${widget.tabId}'),
            onPressed: widget.onCloseOthers,
            child: const Text('Close other tabs'),
          ),
        ],
      ),
      child: DContextMenuTrigger(
        controller: _trigger,
        focusable: false,
        longPressEnabled: false,
        child: widget.child,
      ),
    ),
  );
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
    required this.listTabId,
  });

  factory _CurrentForumTabsSnapshot.of(ShellController controller) {
    final instance = controller.currentInstance;
    return _CurrentForumTabsSnapshot(
      siteUrl: instance?.url,
      forumName: instance?.title,
      tabs: controller.tabsForCurrentForum,
      recentlyClosedTabs: controller.recentlyClosedTabsForCurrentForum,
      activeTabId: controller.activeTabId,
      listTabId: controller.listPanelTab?.id,
      presentationToken: instance == null
          ? null
          : controller.presentationTokenFor(instance.url),
    );
  }

  final String? siteUrl;
  final String? forumName;
  final List<ForumTab> tabs;
  final List<ForumTab> recentlyClosedTabs;
  final String? activeTabId;
  final Object? presentationToken;
  final String? listTabId;

  @override
  bool operator ==(Object other) =>
      other is _CurrentForumTabsSnapshot &&
      siteUrl == other.siteUrl &&
      forumName == other.forumName &&
      identical(tabs, other.tabs) &&
      _sameTabs(recentlyClosedTabs, other.recentlyClosedTabs) &&
      activeTabId == other.activeTabId &&
      listTabId == other.listTabId &&
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
    listTabId,
    identityHashCode(presentationToken),
  );
}

class CurrentForumTabsBar extends StatelessWidget {
  const CurrentForumTabsBar({super.key, this.panel, this.incomingTabId});
  final ForumPanel? panel;
  final String? incomingTabId;

  @override
  Widget build(
    BuildContext context,
  ) => ShellSelector<_CurrentForumTabsSnapshot>(
    select: _CurrentForumTabsSnapshot.of,
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
      final tabs = state.tabs
          .where((tab) => (panel == null || tab.panel == panel))
          .toList();
      final selectedId = panel == null
          ? activeTabId
          : controller.selectedTabIn(panel!)?.id;
      final registry = PluginScope.of(context).registry;
      return ListenableBuilder(
        listenable: Listenable.merge(
          registry.forumTabListenables(context, siteUrl),
        ),
        builder: (context, _) {
          ForumTabItem itemFor(ForumTab tab) => _forumTabItem(
            context,
            controller: controller,
            registry: registry,
            siteUrl: siteUrl,
            tab: tab,
          );

          ForumTabItem? itemForDrop(String id) {
            final tab = controller.currentWorkspace?.tabById(id);
            return panel != null && tab != null ? itemFor(tab) : null;
          }

          final incoming = incomingTabId == null
              ? null
              : controller.currentWorkspace?.tabById(incomingTabId!)?.panel ==
                    panel
              ? null
              : itemForDrop(incomingTabId!);
          if (tabs.isEmpty) {
            return DragTarget<StartPageDrag>(
              onWillAcceptWithDetails: (details) =>
                  details.data.siteUrl == siteUrl && controller.canCreateTab,
              onAcceptWithDetails: (details) => unawaited(
                openLink(
                  context,
                  details.data.path,
                  title: details.data.title,
                  siteUrl: details.data.siteUrl,
                  newTab: true,
                  panel: panel,
                  tabIndex: 0,
                ),
              ),
              builder: (context, links, rejected) => Row(
                children: [
                  if (links.isNotEmpty || incoming != null) ...[
                    _ForumTabDropPlaceholder(
                      item:
                          incoming ??
                          ForumTabItem(
                            id: 'incoming-start-page-link',
                            title: links.first!.title,
                          ),
                    ),
                    const SizedBox(width: DSpacing.controlGap),
                  ],
                  DButton.iconOnly(
                    key: ValueKey('add-empty-${panel?.name}'),
                    icon: const DIcon(DIcons.plus),
                    tooltip: 'Open a new tab',
                    variant: DButtonVariant.inline,
                    onPressed: controller.canCreateTab
                        ? () => controller.createTab(panel: panel)
                        : null,
                  ),
                ],
              ),
            );
          }

          return ForumTabsBar(
            key: ValueKey(('forum-tabs', siteUrl, panel)),
            forumName: forumName,
            panel: panel,
            onMoveToPanel: panel == null ? null : controller.moveTabToPanel,
            showAdd: true,
            incomingTab: incoming,
            itemForDrop: itemForDrop,
            acceptsLink: (link) =>
                link.siteUrl == siteUrl && controller.canCreateTab,
            onDropLink: (link, index) => unawaited(
              openLink(
                context,
                link.path,
                title: link.title,
                siteUrl: link.siteUrl,
                newTab: true,
                panel: panel,
                tabIndex: index,
              ),
            ),
            items: [for (final tab in tabs) itemFor(tab)],
            recentlyClosedItems: [
              for (final tab in state.recentlyClosedTabs)
                if (panel == null || tab.panel == panel) itemFor(tab),
            ],
            selectedId: tabs.any((tab) => tab.id == selectedId)
                ? selectedId!
                : tabs.first.id,
            onAdd: controller.canCreateTab
                ? () => controller.createTab(panel: panel)
                : null,
            acceptsTab: (id) =>
                controller.currentWorkspace?.tabById(id) != null,
            onDropTab: panel == null
                ? null
                : (id, index) =>
                      controller.moveTabToPanel(id, panel!, index: index),
            onSelect: controller.selectTab,
            onClose: controller.closeTab,
            onReorder: (id, index) => controller.moveTab(
              id,
              state.tabs.indexWhere((tab) => tab.id == tabs[index].id),
            ),
            onCloseOthers: (id) => controller.closeOtherTabs(id, panel: panel),
            onReopen: controller.canCreateTab
                ? (id) {
                    if (controller.reopenClosedTab(id)) {
                      controller.selectTab(id);
                    }
                  }
                : null,
          );
        },
      );
    },
  );
}

ForumTabItem _forumTabItem(
  BuildContext context, {
  required ShellController controller,
  required PluginRegistry registry,
  required String siteUrl,
  required ForumTab tab,
}) {
  final route = tab.currentContent;
  final destination = registry.forumTabDestination(context, siteUrl, tab);
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
      emojiUrl: emoji == null ? null : controller.emojiUrlFor(siteUrl, emoji),
      emojiName: emoji,
      badge: destination.badge ?? SidebarBadge.none,
    );
  }

  return ForumTabItem(
    id: tab.id,
    title: route.tabTitle,
    siteUrl: siteUrl,
    icon: route.icon,
    color: route.color,
  );
}

/// A minimized panel's tabs, docked as a [PanelRail] where the panel was.
class CurrentForumTabsRail extends StatelessWidget {
  const CurrentForumTabsRail({
    super.key,
    required this.panel,
    required this.semanticLabel,
    required this.onRestore,
    required this.onSelect,
    required this.onNewTab,
    this.opensTowardStart = false,
  });

  final ForumPanel panel;
  final String semanticLabel;
  final VoidCallback onRestore;
  final ValueChanged<String> onSelect;
  final VoidCallback onNewTab;
  final bool opensTowardStart;

  @override
  Widget build(BuildContext context) =>
      ShellSelector<_CurrentForumTabsSnapshot>(
        select: _CurrentForumTabsSnapshot.of,
        builder: (context, state, _) {
          final controller = ShellScope.read(context);
          final siteUrl = state.siteUrl;
          Widget rail(List<PanelRailTab> tabs) => PanelRail(
            semanticLabel: semanticLabel,
            tabs: tabs,
            onRestore: onRestore,
            onSelect: onSelect,
            onNewTab: controller.canCreateTab ? onNewTab : null,
            opensTowardStart: opensTowardStart,
          );
          if (siteUrl == null) return rail(const []);
          final selectedId = controller.selectedTabIn(panel)?.id;
          final registry = PluginScope.of(context).registry;
          return ListenableBuilder(
            listenable: Listenable.merge(
              registry.forumTabListenables(context, siteUrl),
            ),
            builder: (context, _) => rail([
              for (final tab in state.tabs)
                if (tab.panel == panel)
                  _railTab(
                    _forumTabItem(
                      context,
                      controller: controller,
                      registry: registry,
                      siteUrl: siteUrl,
                      tab: tab,
                    ),
                    selected: tab.id == selectedId,
                  ),
            ]),
          );
        },
      );

  static PanelRailTab _railTab(ForumTabItem item, {required bool selected}) =>
      PanelRailTab(
        id: item.id,
        title: item.title,
        selected: selected,
        icon: Builder(
          builder: (context) =>
              _tabPrefix(
                context,
                item,
                IconTheme.of(context).color ?? DTokens.of(context).foreground,
                size: 13,
              ) ??
              const DIcon(DIcons.farFileLines),
        ),
        label: switch (item.siteUrl) {
          final siteUrl? => SiteEmojiText.plain(
            item.title,
            siteUrl: siteUrl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          null => null,
        },
      );
}
