import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../theme/d_icon.dart';
import '../../theme/d_icons.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/interactive_row.dart';
import '../foundation/tokens.dart';
import '../foundation/touch_target.dart';
import 'd_button.dart';
import 'd_dialog.dart';
import 'd_popover.dart';
import 'd_scroll_area.dart';
import 'd_separator.dart';
import 'd_sheet.dart';

typedef DDropdownMenuController = DPopoverController;
typedef DDropdownMenuOpenChange = DPopoverOpenChange;
typedef DDropdownMenuTriggerState = DPopoverTriggerState;
typedef DDropdownMenuTriggerBuilder =
    Widget Function(BuildContext context, DDropdownMenuTriggerState state);

/// Opens a Native menu at a measured anchor and returns a typed result.
/// Descendants may return that result with [DDialogClose.close].
Future<T?> showDDropdownMenu<T>({
  required BuildContext context,
  required Rect anchorRect,
  required DDropdownMenuContent Function(BuildContext context) builder,
  bool useRootNavigator = true,
  bool restoreFocus = true,
}) => showDDialog<T>(
  context: context,
  useRootNavigator: useRootNavigator,
  modal: false,
  dismissOnBarrier: false,
  dismissOnEscape: false,
  restoreFocus: restoreFocus,
  transitionDuration: Duration.zero,
  reverseTransitionDuration: Duration.zero,
  presentationBuilder: (_, presentation) => presentation.content,
  builder: (context, dialog) => Stack(
    children: [
      Positioned.fromRect(
        rect: anchorRect,
        child: DDropdownMenu(
          defaultOpen: true,
          restoreFocus: false,
          onOpenChangeComplete: (open) {
            if (!open && dialog.isOpen) dialog.close();
          },
          content: builder(context),
          child: const DPopoverAnchor(child: SizedBox.expand()),
        ),
      ),
    ],
  ),
);

enum DDropdownMenuItemVariant { standard, destructive }

/// A shadcn/Base UI dropdown menu composed on the shared popover lifecycle.
///
/// Supplying [open] enables controlled state. Borrowed controllers and trigger
/// focus nodes are never disposed; internally-created resources are owned by
/// this widget and its descendants.
class DDropdownMenu extends StatelessWidget {
  const DDropdownMenu({
    super.key,
    required this.child,
    required this.content,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.restoreFocus = true,
    this.sheetOnMobile = false,
    this.mobileSheetVariant = DSheetVariant.standard,
    this.mobileSheetSizeToContent = true,
  });

  final Widget child;
  final DDropdownMenuContent content;
  final bool? open;
  final bool defaultOpen;
  final DDropdownMenuController? controller;
  final DDropdownMenuOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool restoreFocus;

  /// Uses a bottom sheet on mobile platforms instead of an anchored menu.
  final bool sheetOnMobile;

  /// The existing Native sheet style used when [sheetOnMobile] is enabled.
  final DSheetVariant mobileSheetVariant;

  /// Whether an adaptive mobile sheet follows its content's height.
  ///
  /// When `false`, reserves the Native 55% opening height across content changes.
  /// Desktop menus retain their normal content sizing.
  final bool mobileSheetSizeToContent;

  @override
  Widget build(BuildContext context) {
    final ancestor = _DropdownMenuRootScope.maybeOf(context);
    return DPopover(
      sheetOnMobile: sheetOnMobile,
      mobileSheetVariant: mobileSheetVariant,
      mobileSheetSizeToContent: mobileSheetSizeToContent,
      open: open,
      defaultOpen: defaultOpen,
      controller: controller,
      onOpenChange: onOpenChange,
      onOpenChangeComplete: onOpenChangeComplete,
      restoreFocus: restoreFocus,
      // Menu content owns first-enabled-item focus and conditional overflow.
      focusContentOnOpen: false,
      content: DPopoverContent(
        semanticLabel: content.semanticLabel,
        side: content.side,
        align: content.align,
        sideOffset: content.sideOffset,
        alignOffset: content.alignOffset,
        sideCollision: content.sideCollision,
        alignCollision: content.alignCollision,
        collisionPadding: content.collisionPadding,
        collisionBoundary: content.collisionBoundary,
        width: content.width,
        cornerRadius: content.cornerRadius,
        variant: content.variant,
        constraints: content.constraints,
        padding: EdgeInsets.zero,
        // The menu adds a popup-local viewport only when its rows overflow.
        scrollable: false,
        child: DPopoverClose(
          builder: (context, close) => _DropdownMenuRootScope(
            closeSelf: close,
            closeAll: ancestor?.closeAll ?? close,
            child: content,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// Composes an existing trigger control without adding a second button or
/// semantic node.
class DDropdownMenuTrigger extends StatelessWidget {
  const DDropdownMenuTrigger({
    super.key,
    required this.builder,
    this.focusNode,
  });

  /// Standard action-menu trigger. The menu owns behavior and DButton owns
  /// appearance; use the builder constructor only for richer compositions.
  factory DDropdownMenuTrigger.button({
    Key? key,
    required Widget label,

    FocusNode? focusNode,
  }) => DDropdownMenuTrigger(
    key: key,
    focusNode: focusNode,
    builder: (context, state) => DButton(
      label: label,
      icon: null,
      iconPosition: DButtonIconPosition.start,
      variant: DButtonVariant.outline,
      size: DButtonSize.regular,
      semanticLabel: null,
      focusNode: state.focusNode,
      hasPopup: true,
      expanded: state.open,
      onPressed: state.toggle,
    ),
  );

  final DDropdownMenuTriggerBuilder builder;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DPopoverTrigger(
    focusNode: focusNode,
    builder: (context, state) => builder(context, state),
  );
}

/// The menu popup. Geometry follows base-nova: 128px minimum width, 4px
/// internal padding, the theme’s control radius, a 1px translucent ring, and 4px offset.
class DDropdownMenuContent extends StatefulWidget {
  const DDropdownMenuContent({
    super.key,
    required this.children,
    this.semanticLabel,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.start,
    this.sideOffset = DSpacing.controlGap,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.width = 160,
    this.cornerRadius,
    this.variant = DPopoverVariant.standard,
    this.padding = DInsets.menu,
    this.constraints = const BoxConstraints(minWidth: 128),
    this.isSubmenu = false,
    this.autofocus = true,
    this.highlightInitialFocus = true,
    this.scrollable = true,
  }) : assert(width == null || width >= 96),
       assert(cornerRadius == null || cornerRadius >= 0),
       assert(sideOffset >= 0),
       assert(collisionPadding >= 0);

  final List<Widget> children;
  final String? semanticLabel;
  final DPopoverSide side;
  final DPopoverAlign align;
  final double sideOffset;
  final double alignOffset;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;
  final double? width;

  /// Uniform popup corner radius. Null keeps the Native menu default.
  final double? cornerRadius;

  /// Timeline uses the mockup panel, muted, positive and destructive mixes.
  final DPopoverVariant variant;

  /// Interior spacing, including any inset needed for the popup's ring.
  final EdgeInsetsGeometry padding;
  final BoxConstraints constraints;
  final bool isSubmenu;

  /// Focuses the first enabled item once it is available, including items
  /// inserted or enabled after asynchronous loading.
  final bool autofocus;

  /// Keeps initial keyboard focus without highlighting a pointer-opened menu.
  /// Keyboard navigation still reveals the focused row.
  final bool highlightInitialFocus;

  /// Composite menus can own a fixed header and their bounded feed viewport.
  final bool scrollable;

  @override
  State<DDropdownMenuContent> createState() => _DDropdownMenuContentState();
}

class _MenuRegistration {
  _MenuRegistration(this.node, this.label, this.enabled, this.index);
  final FocusNode node;
  final String label;
  final bool enabled;
  final int? index;
}

class _MenuLazyRow {
  const _MenuLazyRow(
    this.child, {
    this.label = '',
    this.enabled = false,
    this.focusNode,
  });

  final Widget child;
  final String label;
  final bool enabled;
  final FocusNode? focusNode;

  Object get identity => child.key ?? focusNode ?? child;
}

List<_MenuLazyRow>? _menuLazyRows(DDropdownMenuContent content) {
  if (!content.scrollable ||
      content.width == null ||
      content.children.length <= 64) {
    return null;
  }
  final rows = <_MenuLazyRow>[];
  for (final child in content.children) {
    switch (child) {
      case DDropdownMenuItem():
        rows.add(
          _MenuLazyRow(
            child,
            label: child.semanticLabel ?? _plainText(child.child),
            enabled: child.onPressed != null,
            focusNode: child.focusNode,
          ),
        );
      case DDropdownMenuCheckboxItem():
        rows.add(
          _MenuLazyRow(
            child,
            label: child.semanticLabel ?? _plainText(child.child),
            enabled: child.onChanged != null,
            focusNode: child.focusNode,
          ),
        );
      case DDropdownMenuSub():
        rows.add(
          _MenuLazyRow(
            child,
            label: child.semanticLabel ?? _plainText(child.trigger),
            enabled: child.enabled,
          ),
        );
      case DDropdownMenuLabel() || DDropdownMenuSeparator():
        rows.add(_MenuLazyRow(child));
      default:
        return null;
    }
  }
  return rows;
}

class _MenuRowKey extends ValueKey<Object> {
  const _MenuRowKey(super.value);
}

class _MenuRowScope extends InheritedWidget {
  const _MenuRowScope({super.key, required this.index, required super.child});
  final int index;

  @override
  bool updateShouldNotify(_MenuRowScope oldWidget) => index != oldWidget.index;
}

class _DDropdownMenuContentState extends State<DDropdownMenuContent> {
  final _items = <Object, _MenuRegistration>{};
  final _scrollController = ScrollController();
  final _listController = ListController();
  List<_MenuLazyRow>? _lazyRows;
  int? _focusedIndex;
  int? _pendingIndex;
  int _focusGeneration = 0;

  @override
  void initState() {
    super.initState();
    _lazyRows = _menuLazyRows(widget);
  }

  bool get _usesLazyRows => _lazyRows != null && _listController.isAttached;

  void focused(Object owner) {
    if (_items[owner]?.index case final index?) _focusedIndex = index;
  }

  List<int> get _enabledLazyIndexes => [
    for (var index = 0; index < _lazyRows!.length; index++)
      if (_lazyRows![index].enabled &&
          (_lazyRows![index].focusNode?.canRequestFocus ?? true))
        index,
  ];

  int? get _currentLazyIndex {
    if (_pendingIndex != null) return _pendingIndex;
    for (final item in _items.values) {
      if (item.node.hasFocus) return item.index;
    }
    return _focusedIndex;
  }

  void _focusLazy(int index) {
    final active = _activeSubmenu;
    if (active != null &&
        !_items.values.any(
          (item) =>
              item.index == index && identical(item.node, active._focusNode),
        )) {
      closeActiveSubmenu();
    }
    final generation = ++_focusGeneration;
    _pendingIndex = index;
    void reveal([int attempt = 0]) {
      if (!mounted || generation != _focusGeneration || !_usesLazyRows) return;
      for (final item in _items.values) {
        if (item.index == index && item.enabled && item.node.canRequestFocus) {
          _pendingIndex = null;
          _focusedIndex = index;
          _focusAt([item], 0);
          return;
        }
      }
      if (attempt == 3 || !_scrollController.hasClients) {
        _pendingIndex = null;
        return;
      }
      _listController.jumpToItem(
        index: index,
        scrollController: _scrollController,
        alignment: .5,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => reveal(attempt + 1));
      WidgetsBinding.instance.scheduleFrame();
    }

    reveal();
  }

  void _focusEdge(bool last) {
    if (_usesLazyRows) {
      final indexes = _enabledLazyIndexes;
      if (indexes.isNotEmpty) _focusLazy(last ? indexes.last : indexes.first);
    } else {
      final items = _enabledItems;
      _focusAt(items, last ? items.length - 1 : 0);
    }
  }

  _DDropdownMenuContentState? _parentContent;
  _DropdownMenuItemSurfaceState? _hoveredItem;
  _DDropdownMenuSubState? _activeSubmenu;
  _DropdownMenuItemSurfaceState? _pendingHover;
  Offset? _submenuOrigin;
  Offset? _pointerPosition;
  Timer? _hoverTimer;
  String _search = '';
  Timer? _searchTimer;
  bool _autofocused = false;
  bool _autofocusScheduled = false;
  bool _pointerHighlight = false;
  bool _keyboardHighlight = false;

  void register(Object owner, _MenuRegistration registration) {
    _items[owner] = registration;
    _scheduleAutofocus();
  }

  void _scheduleAutofocus() {
    if (!widget.autofocus || _autofocused || _autofocusScheduled) return;
    _autofocusScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autofocusScheduled = false;
      if (!mounted || !widget.autofocus || _autofocused) return;
      if (_usesLazyRows) {
        if (_enabledLazyIndexes.isEmpty) return;
        _autofocused = true;
        if (!_items.values.any((item) => item.node.hasFocus)) {
          final indexes = _enabledLazyIndexes;
          _focusLazy(
            indexes.contains(_focusedIndex) ? _focusedIndex! : indexes.first,
          );
        }
        return;
      }
      final items = _enabledItems;
      if (items.isEmpty) return;
      _autofocused = true;
      if (!items.any((item) => item.node.hasFocus)) _focusAt(items, 0);
    });
  }

  void unregister(Object owner) {
    _items.remove(owner);
    if (identical(_hoveredItem, owner)) _hoveredItem = null;
    if (identical(_pendingHover, owner)) _cancelPendingHover();
  }

  // Mobile menus retain keyboard focus without painting the first action as
  // active before the user has navigated with a keyboard.
  bool get showFocusHighlight =>
      !_pointerHighlight &&
      _activeSubmenu == null &&
      (widget.highlightInitialFocus && !DControlStyle.isTouch(context) ||
          _keyboardHighlight);

  void _usePointerHighlight() {
    _parentContent?._usePointerHighlight();
    if (_pointerHighlight) return;
    _pointerHighlight = true;
    _refreshItemHighlights();
  }

  void useKeyboardHighlight() {
    cancelPointerIntent();
    if (_pointerHighlight || !_keyboardHighlight) {
      _keyboardHighlight = true;
      _pointerHighlight = false;
      _hoveredItem = null;
      _refreshItemHighlights();
    }
    _parentContent?.useKeyboardHighlight();
  }

  void _refreshItemHighlights() {
    for (final owner in _items.keys) {
      if (owner is _DropdownMenuItemSurfaceState) owner.refreshHighlight();
    }
  }

  void hover(_DropdownMenuItemSurfaceState item) {
    if (identical(_hoveredItem, item)) return;
    if (!item.widget.preserveSubmenuOnFocus) closeActiveSubmenu();
    _hoveredItem = item;
    _refreshItemHighlights();
    item.widget.onHover?.call(true);
  }

  void pointerHover(_DropdownMenuItemSurfaceState item, PointerEvent event) {
    _usePointerHighlight();
    if (!item.widget.enabled) return;
    final position = event.position;
    final previous = _pointerPosition;
    if (position == previous &&
        (identical(_pendingHover, item) || identical(_hoveredItem, item))) {
      return;
    }
    _pointerPosition = position;
    final activeTrigger = identical(_activeSubmenu?._focusNode, item._focus);
    if (!activeTrigger &&
        event.kind == PointerDeviceKind.mouse &&
        _movingTowardSubmenu(position, previous)) {
      _cancelPendingHover();
      _pendingHover = item;
      // Continue protecting a slow diagonal path, but let a deliberate pause
      // over another row select it without requiring another pointer event.
      _hoverTimer = Timer(const Duration(milliseconds: 300), () {
        _cancelPendingHover();
        _submenuOrigin = null;
        if (mounted && item.mounted && item.widget.enabled) hover(item);
      });
      return;
    }
    _cancelPendingHover();
    _submenuOrigin = null;
    hover(item);
    _pointerPosition = position;
    if (identical(_activeSubmenu?._focusNode, item._focus)) {
      _submenuOrigin = position;
    }
  }

  bool _movingTowardSubmenu(Offset position, Offset? previous) {
    final origin = _submenuOrigin;
    final submenu = _activeSubmenu;
    final popup = submenu?._contentKey.currentContext?.findRenderObject();
    if (origin == null ||
        previous == null ||
        submenu == null ||
        !submenu._controller.isOpen ||
        popup is! RenderBox ||
        !popup.attached ||
        !popup.hasSize) {
      return false;
    }
    final bounds = MatrixUtils.transformRect(
      popup.getTransformTo(null),
      Offset.zero & popup.size,
    );
    // Use the rendered near edge, so RTL, collision flips, vertical shifts,
    // scrolling and nested overlay transforms all use the actual destination.
    final edge = bounds.center.dx > origin.dx ? bounds.left : bounds.right;
    final distance = edge - origin.dx;
    if (distance == 0 || (position.dx - previous.dx) * distance <= 0) {
      return false;
    }
    final progress = (position.dx - origin.dx) / distance;
    if (progress <= 0 || progress > 1) return false;
    const tolerance = 8.0;
    final top = origin.dy + (bounds.top - tolerance - origin.dy) * progress;
    final bottom =
        origin.dy + (bounds.bottom + tolerance - origin.dy) * progress;
    return position.dy >= top && position.dy <= bottom;
  }

  void _cancelPendingHover() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _pendingHover = null;
  }

  void focusFromPointer(Object owner) {
    _focusGeneration++;
    _pendingIndex = null;
    focused(owner);
    cancelPointerIntent();
  }

  void cancelPointerIntent() {
    _cancelPendingHover();
    _submenuOrigin = null;
    _pointerPosition = null;
    _parentContent?.cancelPointerIntent();
  }

  void unhover(_DropdownMenuItemSurfaceState item) {
    if (identical(_pendingHover, item)) _cancelPendingHover();
    if (!identical(_hoveredItem, item)) return;
    _hoveredItem = null;
    _refreshItemHighlights();
  }

  bool isHovered(_DropdownMenuItemSurfaceState item) =>
      identical(_hoveredItem, item);

  void activateSubmenu(_DDropdownMenuSubState submenu) {
    if (identical(_activeSubmenu, submenu)) return;
    closeActiveSubmenu();
    _activeSubmenu = submenu;
    _refreshItemHighlights();
  }

  void deactivateSubmenu(_DDropdownMenuSubState submenu) {
    if (identical(_activeSubmenu, submenu)) {
      cancelPointerIntent();
      _activeSubmenu = null;
      _refreshItemHighlights();
    }
  }

  void closeActiveSubmenu() {
    cancelPointerIntent();
    _activeSubmenu?._controller.close();
    _activeSubmenu = null;
    _refreshItemHighlights();
  }

  // A row registers when it first mounts, so registration order goes stale as
  // soon as a row is inserted above others or rows are reordered. Navigation
  // follows the element tree instead: the order rows are laid out in, and the
  // DOM order the reference's roving focus uses. A row never contains another
  // row and a nested submenu's content owns its rows, so neither subtree is
  // searched. Element walks are invalid during build, so this is read only
  // from key handlers and post-frame autofocus.
  List<_MenuRegistration> get _enabledItems {
    final items = <_MenuRegistration>[];
    void visit(Element element) {
      if (element is StatefulElement) {
        final state = element.state;
        if (state is _DDropdownMenuContentState) return;
        if (_items[state] case final item?) {
          if (item.enabled && item.node.canRequestFocus) items.add(item);
          return;
        }
      }
      element.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    return items;
  }

  void _focusAt(List<_MenuRegistration> items, int index) {
    if (items.isEmpty) return;
    final generation = ++_focusGeneration;
    _pendingIndex = null;
    items[index % items.length].node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _focusGeneration) return;
      final itemContext = items[index % items.length].node.context;
      final target = itemContext?.findRenderObject();
      if (itemContext != null && target != null && target.attached) {
        // OverlayPortal preserves ancestors, including the trigger's scroll
        // views. A fitting menu has no scroll owner; never fall through to an
        // enclosing page when revealing a focused row in an overflowing menu.
        final scrollable = Scrollable.maybeOf(itemContext);
        if (_scrollController.hasClients &&
            scrollable != null &&
            identical(scrollable.position, _scrollController.position)) {
          scrollable.position.ensureVisible(
            target,
            alignment: 0.5,
            duration: DMotion.duration(context, DMotion.exit),
          );
        }
      }
    });
  }

  void _move(int delta) {
    if (_usesLazyRows) {
      final indexes = _enabledLazyIndexes;
      if (indexes.isEmpty) return;
      final current = indexes.indexOf(_currentLazyIndex ?? -1);
      _focusLazy(
        indexes[(current < 0
                ? (delta > 0 ? 0 : indexes.length - 1)
                : current + delta) %
            indexes.length],
      );
      return;
    }
    final items = _enabledItems;
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => item.node.hasFocus);
    _focusAt(
      items,
      current < 0 ? (delta > 0 ? 0 : items.length - 1) : current + delta,
    );
  }

  void _typeahead(String character) {
    if (character.isEmpty || character.trim().isEmpty) return;
    _searchTimer?.cancel();
    final normalized = character.toLowerCase();
    _search = _search == normalized ? normalized : '$_search$normalized';
    _searchTimer = Timer(const Duration(milliseconds: 700), () => _search = '');
    if (_usesLazyRows) {
      final indexes = _enabledLazyIndexes;
      final current = indexes.indexOf(_currentLazyIndex ?? -1);
      for (var offset = 1; offset <= indexes.length; offset++) {
        final index = indexes[(current + offset) % indexes.length];
        if (_lazyRows![index].label.toLowerCase().startsWith(_search)) {
          _focusLazy(index);
          return;
        }
      }
      return;
    }
    final items = _enabledItems;
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => item.node.hasFocus);
    for (var offset = 1; offset <= items.length; offset++) {
      final index = (current + offset) % items.length;
      if (items[index].label.toLowerCase().startsWith(_search)) {
        _focusAt(items, index);
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    useKeyboardHighlight();
    final key = event.logicalKey;
    final direction = Directionality.of(context);
    if (key == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _focusEdge(false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _focusEdge(true);
      return KeyEventResult.handled;
    }
    final closeDirection = direction == TextDirection.ltr
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowRight;
    if (widget.isSubmenu && key == closeDirection) {
      _DropdownMenuRootScope.of(context).closeSelf();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _DropdownMenuRootScope.of(context).closeAll();
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null &&
        !HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        !HardwareKeyboard.instance.isAltPressed) {
      _typeahead(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parentContent = context
        .dependOnInheritedWidgetOfExactType<_DropdownMenuContentScope>()
        ?.state;
    _scheduleAutofocus();
  }

  @override
  void didUpdateWidget(DDropdownMenuContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = _lazyRows;
    final hadFocus = _items.values.any((item) => item.node.hasFocus);
    final focused = _currentLazyIndex;
    final identity =
        previous != null && focused != null && focused < previous.length
        ? previous[focused].identity
        : null;
    _focusGeneration++;
    _pendingIndex = null;
    _lazyRows = _menuLazyRows(widget);
    final next = identity == null
        ? -1
        : _lazyRows?.indexWhere((row) => row.identity == identity) ?? -1;
    _focusedIndex = next < 0 ? null : next;
    // Only lazy rows have identities to follow. A short menu whose focused
    // item is disabled must not take focus back when its items re-enable.
    if (hadFocus &&
        ((previous != null && next < 0) ||
            (previous == null) != (_lazyRows == null))) {
      _autofocused = false;
      _focusedIndex ??= focused;
    }
    _scheduleAutofocus();
  }

  @override
  void dispose() {
    _cancelPendingHover();
    _searchTimer?.cancel();
    _focusGeneration++;
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseTokens = DTokens.of(context);
    final tokens = widget.variant == DPopoverVariant.timeline
        ? baseTokens.copyWith(
            surface: Color.lerp(
              baseTokens.background,
              baseTokens.foreground,
              .03,
            ),
            colors: baseTokens.colors.copyWith(
              onSurfaceVariant: Color.lerp(
                baseTokens.background,
                baseTokens.foreground,
                .50,
              ),
              error: Color.lerp(
                baseTokens.foreground,
                baseTokens.destructive,
                .50,
              ),
            ),
            successColor: Color.lerp(
              baseTokens.foreground,
              baseTokens.success,
              .50,
            ),
          )
        : baseTokens;
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: tokens.foreground,
      fontSize: DControlStyle.labelFontSize,
      height: DControlStyle.labelLineHeight / DControlStyle.labelFontSize,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      decoration: TextDecoration.none,
    );
    return Theme(
      data: Theme.of(context).copyWith(
        extensions: [
          ...Theme.of(
            context,
          ).extensions.values.where((extension) => extension is! DTokens),
          tokens,
        ],
      ),
      child: _DropdownMenuContentScope(
        state: this,
        child: MouseRegion(
          onEnter: (_) => _usePointerHighlight(),
          onHover: (_) => _usePointerHighlight(),
          onExit: (_) => cancelPointerIntent(),
          child: Semantics(
            container: true,
            explicitChildNodes: true,
            label: widget.semanticLabel,
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onKeyEvent: _onKey,
              child: DefaultTextStyle(
                style: textStyle,
                child: IconTheme.merge(
                  data: IconThemeData(color: tokens.foreground, size: 16),
                  child: _lazyRows != null
                      ? _lazyViewport()
                      : widget.scrollable
                      ? _DropdownMenuOverflowViewport(
                          controller: _scrollController,
                          padding: widget.padding,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _indexedChildren,
                          ),
                        )
                      : Padding(
                          padding: widget.padding,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final child in widget.children)
                                Flexible(child: child),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> get _indexedChildren => [
    for (var index = 0; index < widget.children.length; index++)
      _MenuRowScope(
        key: _MenuRowKey(widget.children[index].key ?? index),
        index: index,
        child: widget.children[index],
      ),
  ];

  Widget _lazyViewport() => LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedHeight) {
        return Padding(
          padding: widget.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: widget.children,
          ),
        );
      }
      final rows = _lazyRows!;
      return DScrollBar(
        backgroundColor: DTokens.of(context).surface,
        controller: _scrollController,
        child: CustomScrollView(
          controller: _scrollController,
          primary: false,
          shrinkWrap: true,
          slivers: [
            SliverPadding(
              padding: widget.padding,
              sliver: SuperSliverList.builder(
                listController: _listController,
                layoutKeptAliveChildren: true,
                itemCount: rows.length,
                findChildIndexCallback: (key) {
                  for (var index = 0; index < rows.length; index++) {
                    if (key == _MenuRowKey(rows[index].child.key ?? index)) {
                      return index;
                    }
                  }
                  return null;
                },
                itemBuilder: (context, index) => _MenuRowScope(
                  key: _MenuRowKey(rows[index].child.key ?? index),
                  index: index,
                  child: rows[index].child,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Matches CSS `overflow-y: auto`: fitting menus are ordinary static content,
/// while collision- or caller-constrained menus gain one local scroll owner.
class _DropdownMenuOverflowViewport extends StatefulWidget {
  const _DropdownMenuOverflowViewport({
    required this.controller,
    required this.padding,
    required this.child,
  });

  final ScrollController controller;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  State<_DropdownMenuOverflowViewport> createState() =>
      _DropdownMenuOverflowViewportState();
}

class _DropdownMenuOverflowViewportState
    extends State<_DropdownMenuOverflowViewport> {
  final _probeKey = GlobalKey();
  bool _overflows = false;
  bool _measurementScheduled = false;
  BoxConstraints? _measurementConstraints;

  Widget get _paddedChild => KeyedSubtree(
    key: _probeKey,
    child: Padding(padding: widget.padding, child: widget.child),
  );

  void _setOverflowAfterLayout(bool value) {
    if (_overflows == value) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _overflows == value) return;
      setState(() => _overflows = value);
    });
  }

  void _measureAfterLayout(BoxConstraints constraints) {
    // Popover can lay out twice: first against the viewport, then against the
    // space beside the trigger. Measure overflow against the final layout.
    _measurementConstraints = constraints;
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final naturalHeight = _probeKey.currentContext?.size?.height;
      if (naturalHeight == null) return;
      final constraints = _measurementConstraints!;
      _setOverflowAfterLayout(
        constraints.hasBoundedHeight &&
            naturalHeight > constraints.maxHeight + precisionErrorTolerance,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_overflows) {
      return DScrollBar(
        backgroundColor: DTokens.of(context).surface,
        controller: widget.controller,
        child: DScrollViewport(
          controller: widget.controller,
          child: _paddedChild,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        _measureAfterLayout(constraints);
        return UnconstrainedBox(
          constrainedAxis: Axis.horizontal,
          alignment: AlignmentDirectional.topStart,
          clipBehavior: Clip.hardEdge,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _measureAfterLayout(constraints);
              return false;
            },
            child: SizeChangedLayoutNotifier(child: _paddedChild),
          ),
        );
      },
    );
  }
}

class _DropdownMenuRootScope extends InheritedWidget {
  const _DropdownMenuRootScope({
    required this.closeSelf,
    required this.closeAll,
    required super.child,
  });

  final VoidCallback closeSelf;
  final VoidCallback closeAll;

  static _DropdownMenuRootScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'Dropdown menu content requires DDropdownMenu.');
    return scope!;
  }

  static _DropdownMenuRootScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DropdownMenuRootScope>();

  @override
  bool updateShouldNotify(_DropdownMenuRootScope oldWidget) => false;
}

class _DropdownMenuContentScope extends InheritedWidget {
  const _DropdownMenuContentScope({required this.state, required super.child});
  final _DDropdownMenuContentState state;

  static _DDropdownMenuContentState of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DropdownMenuContentScope>();
    assert(scope != null, 'Menu items require DDropdownMenuContent.');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(_DropdownMenuContentScope oldWidget) => false;
}

/// A structural group. [semanticLabel] names its grouped choices.
class DDropdownMenuGroup extends StatelessWidget {
  const DDropdownMenuGroup({
    super.key,
    required this.children,
    this.semanticLabel,
    this.showGuide = false,
  });

  final List<Widget> children;
  final String? semanticLabel;

  /// Indents the group beneath its label with a sidebar-style vertical guide.
  /// Children should use their normal padding rather than `inset: true`.
  final bool showGuide;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (showGuide) {
      content = Stack(
        children: [
          PositionedDirectional(
            start: 15,
            top: 0,
            bottom: 0,
            child: DSeparator(
              orientation: Axis.vertical,
              color: _dropdownGuideColor(context),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22),
            child: content,
          ),
        ],
      );
    }
    return Semantics(
      container: semanticLabel != null,
      label: semanticLabel,
      child: content,
    );
  }
}

// Match the sidebar's subtle guide, including palettes whose border blends
// into the surface. Resolve during build so open menus follow theme changes.
Color _dropdownGuideColor(BuildContext context) {
  final tokens = DTokens.of(context);
  final surfaceLuminance = tokens.surface.computeLuminance() + 0.05;
  double contrast(Color color) {
    final luminance =
        Color.alphaBlend(color, tokens.surface).computeLuminance() + 0.05;
    return luminance > surfaceLuminance
        ? luminance / surfaceLuminance
        : surfaceLuminance / luminance;
  }

  if (contrast(tokens.border) >= 1.25) return tokens.border;
  for (final alpha in const [.10, .12, .14, .16, .20, .24, .30]) {
    final candidate = Color.alphaBlend(
      tokens.foreground.withValues(alpha: alpha),
      tokens.surface,
    );
    if (contrast(candidate) >= 1.25) return candidate;
  }
  return tokens.foreground;
}

class DDropdownMenuLabel extends StatelessWidget {
  const DDropdownMenuLabel({
    super.key,
    required this.child,
    this.inset = false,
  });

  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(inset ? 28 : 6, 4, 6, 4),
        child: DefaultTextStyle.merge(
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
            color: tokens.mutedForeground,
            fontSize: DiscourseTypography.xs,
            height: DiscourseTypography.lineHeightCaption,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
          child: child,
        ),
      ),
    );
  }
}

class DDropdownMenuSeparator extends StatelessWidget {
  const DDropdownMenuSeparator({
    super.key,
    this.inset = false,
    this.space = 9,
    this.color,
  });

  /// Aligns the rule with menu item content instead of the popup edges.
  final bool inset;
  final double space;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    // A site's content border can disappear against its floating surface.
    // Preserve stronger palette borders; otherwise use the same subtle
    // foreground tint as the popup's exterior ring.
    final fallback = Color.alphaBlend(
      tokens.foreground.withValues(alpha: tokens.foreground.a * 0.10),
      tokens.surface,
    );
    final surfaceLuminance = tokens.surface.computeLuminance() + 0.05;
    double contrast(Color color) {
      final luminance =
          Color.alphaBlend(color, tokens.surface).computeLuminance() + 0.05;
      return luminance > surfaceLuminance
          ? luminance / surfaceLuminance
          : surfaceLuminance / luminance;
    }

    final color =
        this.color ??
        (contrast(tokens.border) >= contrast(fallback)
            ? tokens.border
            : fallback);
    return ExcludeSemantics(
      child: SizedBox(
        height: space,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            PositionedDirectional(
              start: inset ? DInsets.menuItem.start : -DInsets.menu.left,
              end: inset ? DInsets.menuItem.end : -DInsets.menu.right,
              top: (space - 1) / 2,
              height: 1,
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// A keyboard shortcut hint, hidden on mobile platforms.
class DDropdownMenuShortcut extends StatelessWidget {
  const DDropdownMenuShortcut(this.label, {super.key, this.semanticLabel});
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => DControlStyle.isTouch(context)
      ? const SizedBox.shrink()
      : Semantics(
          label: semanticLabel ?? label,
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall!.copyWith(
                // The item supplies muted color at rest and accent foreground while
                // active, matching the reference's group-focus shortcut selector.
                color:
                    IconTheme.of(context).color ??
                    DTokens.of(context).mutedForeground,
                fontSize: DiscourseTypography.xs,
                height: DiscourseTypography.lineHeightCaption,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.2,
              ),
            ),
          ),
        );
}

class DDropdownMenuItem extends StatelessWidget {
  const DDropdownMenuItem({
    super.key,
    required this.child,
    this.onPressed,
    this.leading,
    this.trailing,
    this.inset = false,
    this.variant = DDropdownMenuItemVariant.standard,
    this.closeOnSelect = true,
    this.semanticLabel,
    this.focusNode,
    this.padding,
    this.leadingGap = 6,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final DDropdownMenuItemVariant variant;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  /// Account headers can use their ordinary visible content padding.
  final EdgeInsetsGeometry? padding;
  final double leadingGap;

  @override
  Widget build(BuildContext context) => _DropdownMenuItemSurface(
    label: semanticLabel ?? _plainText(child),
    enabled: onPressed != null,
    focusNode: focusNode,
    variant: variant,
    inset: inset,
    leading: leading,
    padding: padding,
    leadingGap: leadingGap,
    trailing: trailing,
    onActivate: () {
      onPressed?.call();
      if (closeOnSelect) _DropdownMenuRootScope.of(context).closeAll();
    },
    child: child,
  );
}

class DDropdownMenuCheckboxItem extends StatelessWidget {
  const DDropdownMenuCheckboxItem({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.child,
    this.leading,
    this.trailing,
    this.inset = false,
    this.closeOnSelect = false,
    this.semanticLabel,
    this.semanticValue,
    this.focusNode,
    this.indicatorSize = 11,
    this.leadingGap = 6,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final String? semanticValue;
  final FocusNode? focusNode;
  final double indicatorSize;
  final double leadingGap;

  @override
  Widget build(BuildContext context) => _DropdownMenuItemSurface(
    label: semanticLabel ?? _plainText(child),
    semanticValue: semanticValue,
    enabled: onChanged != null,
    focusNode: focusNode,
    inset: inset,
    leading: leading,
    leadingGap: leadingGap,
    // The reference reserves its absolute indicator column even while the
    // choice is unchecked, so labels do not reflow when state changes.
    trailing:
        trailing ?? _CheckIndicator(checked: checked, size: indicatorSize),
    checked: checked,
    onActivate: () {
      onChanged?.call(!checked);
      if (closeOnSelect) _DropdownMenuRootScope.of(context).closeAll();
    },
    child: child,
  );
}

class DDropdownMenuRadioGroup<T> extends StatelessWidget {
  const DDropdownMenuRadioGroup({
    super.key,
    required this.value,
    required this.onChanged,
    required this.children,
    this.semanticLabel,
  });

  final T value;
  final ValueChanged<T>? onChanged;
  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => _DropdownMenuRadioScope<T>(
    value: value,
    onChanged: onChanged,
    child: Semantics(
      container: true,
      label: semanticLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
}

class DDropdownMenuRadioItem<T> extends StatelessWidget {
  const DDropdownMenuRadioItem({
    super.key,
    required this.value,
    required this.child,
    this.leading,
    this.trailing,
    this.inset = false,
    this.closeOnSelect = false,
    this.semanticLabel,
    this.focusNode,
  });

  final T value;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scope = _DropdownMenuRadioScope.of<T>(context);
    final checked = scope.value == value;
    return _DropdownMenuItemSurface(
      label: semanticLabel ?? _plainText(child),
      enabled: scope.onChanged != null,
      focusNode: focusNode,
      inset: inset,
      leading: leading,
      trailing: trailing ?? _CheckIndicator(checked: checked),
      checked: checked,
      inMutuallyExclusiveGroup: true,
      onActivate: () {
        scope.onChanged?.call(value);
        if (closeOnSelect) _DropdownMenuRootScope.of(context).closeAll();
      },
      child: child,
    );
  }
}

class _DropdownMenuRadioScope<T> extends InheritedWidget {
  const _DropdownMenuRadioScope({
    required this.value,
    required this.onChanged,
    required super.child,
  });
  final T value;
  final ValueChanged<T>? onChanged;

  static _DropdownMenuRadioScope<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_DropdownMenuRadioScope<T>>();
    assert(scope != null, 'Radio items require DDropdownMenuRadioGroup<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_DropdownMenuRadioScope<T> oldWidget) =>
      value != oldWidget.value || onChanged != oldWidget.onChanged;
}

/// A nested menu. Its focus node is shared between the parent roving-focus item
/// and the popover trigger, so Escape and directional closing restore exactly
/// to the owning row.
/// Mouse movement toward the popup protects it from incidental sibling hovers.
class DDropdownMenuSub extends StatefulWidget {
  const DDropdownMenuSub({
    super.key,
    required this.trigger,
    required this.children,
    this.leading,
    this.inset = false,
    this.enabled = true,
    this.semanticLabel,
    this.width = 96,
  });

  final Widget trigger;
  final List<Widget> children;
  final Widget? leading;
  final bool inset;
  final bool enabled;
  final String? semanticLabel;

  /// A fixed submenu width. The 96px default matches the reference minimum;
  /// pass null for intrinsic sizing or a larger value for richer rows.
  final double? width;

  @override
  State<DDropdownMenuSub> createState() => _DDropdownMenuSubState();
}

class _DDropdownMenuSubState extends State<DDropdownMenuSub> {
  final _controller = DDropdownMenuController();
  final _contentKey = GlobalKey<_DDropdownMenuContentState>();
  late final _focusNode = FocusNode(
    debugLabel:
        'Dropdown item ${widget.semanticLabel ?? _plainText(widget.trigger)}',
  );
  _DDropdownMenuContentState? _parent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _parent = _DropdownMenuContentScope.of(context);
  }

  @override
  void dispose() {
    _parent?.deactivateSubmenu(this);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final openKey = direction == TextDirection.ltr
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    return DDropdownMenu(
      controller: _controller,
      onOpenChange: (open, reason) {
        // Popover handles Escape before menu rows receive the key event.
        if (reason == DPopoverChangeReason.escape) {
          _parent?.useKeyboardHighlight();
        }
        if (open) {
          _parent?.activateSubmenu(this);
        } else {
          _parent?.deactivateSubmenu(this);
        }
      },
      content: DDropdownMenuContent(
        key: _contentKey,
        isSubmenu: true,
        side: DPopoverSide.inlineEnd,
        sideOffset: 0,
        alignOffset: -3,
        width: widget.width,
        constraints: const BoxConstraints(minWidth: 96),
        children: widget.children,
      ),
      child: DDropdownMenuTrigger(
        focusNode: _focusNode,
        builder: (context, trigger) => _DropdownMenuItemSurface(
          label: widget.semanticLabel ?? _plainText(widget.trigger),
          enabled: widget.enabled,
          focusNode: trigger.focusNode,
          inset: widget.inset,
          leading: widget.leading,
          trailing: const _DirectionalChevron(),
          expanded: trigger.open,
          onHover: (hovered) {
            if (hovered && widget.enabled) {
              trigger.openPopover(DPopoverInteraction.mouse);
            }
          },
          onKey: (event) {
            if (event.logicalKey == openKey) {
              trigger.openPopover(DPopoverInteraction.keyboard);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          // Pointer hover may already have opened this submenu before the
          // ensuing press is delivered. A press activates the submenu; it
          // must not toggle that hover-open state closed again.
          onActivate: () {
            if (!trigger.open) trigger.openPopover();
          },
          preserveSubmenuOnFocus: true,
          child: widget.trigger,
        ),
      ),
    );
  }
}

class _DropdownMenuItemSurface extends StatefulWidget {
  const _DropdownMenuItemSurface({
    required this.label,
    required this.enabled,
    required this.onActivate,
    required this.child,
    this.focusNode,
    this.semanticValue,
    this.leading,
    this.trailing,
    this.inset = false,
    this.variant = DDropdownMenuItemVariant.standard,
    this.checked,
    this.inMutuallyExclusiveGroup = false,
    this.expanded,
    this.onHover,
    this.onKey,
    this.preserveSubmenuOnFocus = false,
    this.padding,
    this.leadingGap = 6,
  });

  final String label;
  final bool enabled;
  final VoidCallback onActivate;
  final Widget child;
  final FocusNode? focusNode;
  final String? semanticValue;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final DDropdownMenuItemVariant variant;
  final bool? checked;
  final bool inMutuallyExclusiveGroup;
  final bool? expanded;
  final ValueChanged<bool>? onHover;
  final KeyEventResult Function(KeyEvent event)? onKey;
  final bool preserveSubmenuOnFocus;
  final EdgeInsetsGeometry? padding;
  final double leadingGap;

  @override
  State<_DropdownMenuItemSurface> createState() =>
      _DropdownMenuItemSurfaceState();
}

class _DropdownMenuItemSurfaceState extends State<_DropdownMenuItemSurface>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => _focused || widget.expanded == true;
  late FocusNode _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  _DDropdownMenuContentState? _content;
  bool _pressed = false;
  bool _focused = false;

  void refreshHighlight() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ownedFocus = FocusNode(debugLabel: 'Dropdown item ${widget.label}');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _register();
  }

  @override
  void didUpdateWidget(_DropdownMenuItemSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Disabling drops the tap handlers: no tap-up will release a press still
    // down, and the discarded recognizer cancels it mid-build, where the
    // cancel must find nothing left to rebuild.
    if (!widget.enabled) _pressed = false;
    if (oldWidget.expanded != widget.expanded) updateKeepAlive();
    if (oldWidget.focusNode != widget.focusNode ||
        oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      // Navigation reads this row's live label, enabled state and focus node
      // from its registration; its position comes from the element tree.
      _register();
    }
  }

  void _register() {
    _content = _DropdownMenuContentScope.of(context)
      ..register(
        this,
        _MenuRegistration(
          _focus,
          widget.label,
          widget.enabled,
          context.dependOnInheritedWidgetOfExactType<_MenuRowScope>()?.index,
        ),
      );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      _content?.useKeyboardHighlight();
      final custom = widget.onKey?.call(event);
      if (custom == KeyEventResult.handled) return custom!;
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.space) {
        if (widget.enabled) widget.onActivate();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _content?.unregister(this);
    _ownedFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final tokens = DTokens.of(context);
    final destructive = widget.variant == DDropdownMenuItemVariant.destructive;
    // Pointer hover is menu-local and deliberately does not move keyboard
    // focus. This keeps partially clipped rows from being implicitly revealed
    // while ensuring only the hovered row paints as active. Crossing a gap
    // keeps stale focus hidden until keyboard input resumes.
    final interactive =
        widget.enabled &&
        (_pressed ||
            _content?.isHovered(this) == true ||
            widget.expanded == true ||
            (_content?.showFocusHighlight == true && _focused));
    final referencePalette =
        _content?.widget.variant == DPopoverVariant.timeline;

    final referenceHover = (tokens.foreground).withValues(alpha: .08);
    final background = interactive
        ? referencePalette
              ? referenceHover
              : destructive
              ? tokens.destructive.withValues(
                  alpha:
                      tokens.destructive.a *
                      (Theme.of(context).brightness == Brightness.dark
                          ? 0.20
                          : 0.10),
                )
              // Resolve against the floating surface so adjacent rows retain
              // a distinct neutral highlight in every forum palette.
              : DControlStyle.rowHover(tokens)
        : Colors.transparent;
    final foreground = destructive ? tokens.destructive : tokens.foreground;
    final startPadding = widget.inset ? 28.0 : 8.0;
    const endPadding = 8.0;
    const trailingGap = 8.0;
    // Active-row changes are atomic. Animating the previous row out while the
    // next row animates in briefly presents two highlighted menu choices.
    final row = interactiveRowSurface(
      constraints: const BoxConstraints(minHeight: DControlStyle.rowHeight),
      padding:
          widget.padding ??
          EdgeInsetsDirectional.fromSTEB(
            startPadding,
            DControlStyle.menuVerticalInset(context),
            endPadding,
            DControlStyle.menuVerticalInset(context),
          ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(DControlStyle.rowRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (widget.leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(color: foreground, size: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 16),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: widget.leading,
                ),
              ),
            ),
            SizedBox(width: widget.leadingGap),
          ],
          Expanded(child: widget.child),
          if (widget.trailing != null) ...[
            const SizedBox(width: trailingGap),
            IconTheme.merge(
              data: IconThemeData(
                color: destructive
                    ? tokens.destructive
                    : interactive
                    ? foreground
                    : tokens.mutedForeground,
                size: 16,
              ),
              child: widget.trailing!,
            ),
          ],
        ],
      ),
    );
    return Semantics(
      button: widget.checked == null && !widget.inMutuallyExclusiveGroup,
      enabled: widget.enabled,
      checked: widget.checked,
      inMutuallyExclusiveGroup: widget.inMutuallyExclusiveGroup,
      expanded: widget.expanded,
      label: widget.label.isEmpty ? null : widget.label,
      value: widget.semanticValue,
      excludeSemantics: widget.label.isNotEmpty,
      onTap: widget.enabled ? widget.onActivate : null,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: MouseRegion(
          // Menus use the platform's default cursor (shadcn `cursor-default`),
          // while hover/focus styling communicates the active row.
          cursor: SystemMouseCursors.basic,
          onEnter: (event) => _content?.pointerHover(this, event),
          onHover: (event) => _content?.pointerHover(this, event),
          onExit: (_) {
            _content?.unhover(this);
            widget.onHover?.call(false);
          },
          child: Focus(
            focusNode: _focus,
            canRequestFocus: widget.enabled,
            skipTraversal: !widget.enabled,
            onFocusChange: (focused) {
              if (focused && !widget.preserveSubmenuOnFocus) {
                _content?.closeActiveSubmenu();
              }
              if (focused) _content?.focused(this);
              if (mounted) {
                setState(() => _focused = focused);
                updateKeepAlive();
              }
            },
            onKeyEvent: _onKey,
            child: DTouchTarget(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: widget.enabled
                    ? (_) {
                        _content?.focusFromPointer(this);
                        _focus.requestFocus();
                        setState(() => _pressed = true);
                      }
                    : null,
                onTapCancel: widget.enabled
                    ? () {
                        if (_pressed) setState(() => _pressed = false);
                      }
                    : null,
                onTapUp: widget.enabled
                    ? (_) {
                        setState(() => _pressed = false);
                        widget.onActivate();
                      }
                    : null,
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: foreground),
                  child: Center(heightFactor: 1, child: row),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckIndicator extends StatelessWidget {
  const _CheckIndicator({required this.checked, this.size = 11});

  final bool checked;
  final double size;

  @override
  Widget build(BuildContext context) => DIconGlyphTheme(
    scale: 1,
    naturalWidth: true,
    child: Opacity(
      opacity: checked ? 1 : 0,
      child: DIcon(DIcons.check, size: size),
    ),
  );
}

class _DirectionalChevron extends StatelessWidget {
  const _DirectionalChevron();

  @override
  Widget build(BuildContext context) => DIconGlyphTheme(
    scale: 1,
    child: DIcon(
      Directionality.of(context) == TextDirection.rtl
          ? DIcons.chevronLeft
          : DIcons.chevronRight,
      size: 16,
    ),
  );
}

String _plainText(Widget widget) => widget is Text ? widget.data ?? '' : '';
