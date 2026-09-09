import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_popover.dart';
import 'd_scroll_area.dart';

typedef DDropdownMenuController = DPopoverController;
typedef DDropdownMenuOpenChange = DPopoverOpenChange;
typedef DDropdownMenuTriggerState = DPopoverTriggerState;
typedef DDropdownMenuTriggerBuilder =
    Widget Function(BuildContext context, DDropdownMenuTriggerState state);

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
  });

  final Widget child;
  final DDropdownMenuContent content;
  final bool? open;
  final bool defaultOpen;
  final DDropdownMenuController? controller;
  final DDropdownMenuOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool restoreFocus;

  @override
  Widget build(BuildContext context) {
    final ancestor = _DropdownMenuRootScope.maybeOf(context);
    return DPopover(
      open: open,
      defaultOpen: defaultOpen,
      controller: controller,
      onOpenChange: onOpenChange,
      onOpenChangeComplete: onOpenChangeComplete,
      restoreFocus: restoreFocus,
      // Menu content owns first-enabled-item focus and popup-local scrolling.
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
        constraints: content.constraints,
        padding: EdgeInsets.zero,
        // Menus own their scroll position so wheel, trackpad, and draggable
        // scrollbar interaction all operate on the same popup-local viewport.
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

  final DDropdownMenuTriggerBuilder builder;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DPopoverTrigger(
    focusNode: focusNode,
    builder: (context, state) => builder(context, state),
  );
}

/// The menu popup. Geometry follows base-nova: 128px minimum width, 4px
/// internal padding, an `lg` radius, a 1px translucent ring, and 4px offset.
class DDropdownMenuContent extends StatefulWidget {
  const DDropdownMenuContent({
    super.key,
    required this.children,
    this.semanticLabel,
    this.side = DPopoverSide.bottom,
    this.align = DPopoverAlign.start,
    this.sideOffset = 4,
    this.alignOffset = 0,
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
    this.width = 160,
    this.constraints = const BoxConstraints(minWidth: 128),
    this.isSubmenu = false,
    this.autofocus = true,
  }) : assert(width >= 96),
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
  final double width;
  final BoxConstraints constraints;
  final bool isSubmenu;
  final bool autofocus;

  @override
  State<DDropdownMenuContent> createState() => _DDropdownMenuContentState();
}

class _MenuRegistration {
  _MenuRegistration(this.node, this.label, this.enabled);
  final FocusNode node;
  final String label;
  final bool enabled;
}

class _DDropdownMenuContentState extends State<DDropdownMenuContent> {
  final _items = <Object, _MenuRegistration>{};
  final _scrollController = ScrollController();
  _DropdownMenuItemSurfaceState? _hoveredItem;
  DDropdownMenuController? _activeSubmenu;
  String _search = '';
  Timer? _searchTimer;
  bool _autofocused = false;

  void register(Object owner, _MenuRegistration registration) {
    _items[owner] = registration;
  }

  void unregister(Object owner) {
    _items.remove(owner);
    if (identical(_hoveredItem, owner)) _hoveredItem = null;
  }

  bool get hasActivePointerHighlight =>
      _hoveredItem != null || _activeSubmenu != null;

  void _refreshItemHighlights() {
    for (final owner in _items.keys) {
      if (owner is _DropdownMenuItemSurfaceState) owner.refreshHighlight();
    }
  }

  void hover(_DropdownMenuItemSurfaceState item) {
    if (identical(_hoveredItem, item)) return;
    _hoveredItem = item;
    _refreshItemHighlights();
  }

  void unhover(_DropdownMenuItemSurfaceState item) {
    if (!identical(_hoveredItem, item)) return;
    _hoveredItem = null;
    _refreshItemHighlights();
  }

  bool isHovered(_DropdownMenuItemSurfaceState item) =>
      identical(_hoveredItem, item);

  void activateSubmenu(DDropdownMenuController controller) {
    if (identical(_activeSubmenu, controller)) return;
    _activeSubmenu?.close();
    _activeSubmenu = controller;
    _refreshItemHighlights();
  }

  void deactivateSubmenu(DDropdownMenuController controller) {
    if (identical(_activeSubmenu, controller)) {
      _activeSubmenu = null;
      _refreshItemHighlights();
    }
  }

  void closeActiveSubmenu() {
    _activeSubmenu?.close();
    _activeSubmenu = null;
    _refreshItemHighlights();
  }

  List<_MenuRegistration> get _enabledItems => [
    for (final item in _items.values)
      if (item.enabled && item.node.canRequestFocus) item,
  ];

  void _focusAt(int index) {
    final items = _enabledItems;
    if (items.isEmpty) return;
    items[index % items.length].node.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = items[index % items.length].node.context;
      final target = itemContext?.findRenderObject();
      if (itemContext != null && target != null && target.attached) {
        // OverlayPortal preserves ancestors, including the trigger's scroll
        // views. Only the popup viewport should move when its items get focus.
        Scrollable.maybeOf(itemContext)?.position.ensureVisible(
          target,
          alignment: 0.5,
          duration: DMotion.duration(context, DMotion.exit),
        );
      }
    });
  }

  void _move(int delta) {
    final items = _enabledItems;
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => item.node.hasFocus);
    _focusAt(
      current < 0 ? (delta > 0 ? 0 : items.length - 1) : current + delta,
    );
  }

  void _typeahead(String character) {
    if (character.isEmpty || character.trim().isEmpty) return;
    _searchTimer?.cancel();
    final normalized = character.toLowerCase();
    _search = _search == normalized ? normalized : '$_search$normalized';
    _searchTimer = Timer(const Duration(milliseconds: 700), () => _search = '');
    final items = _enabledItems;
    if (items.isEmpty) return;
    final current = items.indexWhere((item) => item.node.hasFocus);
    for (var offset = 1; offset <= items.length; offset++) {
      final candidate = items[(current + offset) % items.length];
      if (candidate.label.toLowerCase().startsWith(_search)) {
        candidate.node.requestFocus();
        return;
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
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
      _focusAt(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _focusAt(_enabledItems.length - 1);
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
    if (!widget.autofocus || _autofocused) return;
    _autofocused = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAt(0);
    });
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
      color: tokens.foreground,
      fontSize: DiscourseTypography.sm,
      height: DiscourseTypography.lineHeightSmall,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      decoration: TextDecoration.none,
    );
    return _DropdownMenuContentScope(
      state: this,
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
              child: DScrollBar(
                controller: _scrollController,
                child: DScrollViewport(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
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
  });

  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: semanticLabel != null,
    label: semanticLabel,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
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
  const DDropdownMenuSeparator({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 9,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          PositionedDirectional(
            start: -4,
            end: -4,
            top: 4,
            height: 1,
            child: ColoredBox(color: DTokens.of(context).border),
          ),
        ],
      ),
    ),
  );
}

class DDropdownMenuShortcut extends StatelessWidget {
  const DDropdownMenuShortcut(this.label, {super.key, this.semanticLabel});
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    label: semanticLabel ?? label,
    excludeSemantics: true,
    child: Padding(
      padding: const EdgeInsetsDirectional.only(start: 12),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall!.copyWith(
          color: DTokens.of(context).mutedForeground,
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

  @override
  Widget build(BuildContext context) => _DropdownMenuItemSurface(
    label: semanticLabel ?? _plainText(child),
    enabled: onPressed != null,
    focusNode: focusNode,
    variant: variant,
    inset: inset,
    leading: leading,
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
    this.focusNode,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => _DropdownMenuItemSurface(
    label: semanticLabel ?? _plainText(child),
    enabled: onChanged != null,
    focusNode: focusNode,
    inset: inset,
    leading: leading,
    // The reference reserves its absolute indicator column even while the
    // choice is unchecked, so labels do not reflow when state changes.
    trailing: trailing ?? _CheckIndicator(checked: checked),
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
class DDropdownMenuSub extends StatefulWidget {
  const DDropdownMenuSub({
    super.key,
    required this.trigger,
    required this.children,
    this.leading,
    this.inset = false,
    this.enabled = true,
    this.semanticLabel,
    this.width = 160,
  });

  final Widget trigger;
  final List<Widget> children;
  final Widget? leading;
  final bool inset;
  final bool enabled;
  final String? semanticLabel;
  final double width;

  @override
  State<DDropdownMenuSub> createState() => _DDropdownMenuSubState();
}

class _DDropdownMenuSubState extends State<DDropdownMenuSub> {
  final _controller = DDropdownMenuController();
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
    _parent?.deactivateSubmenu(_controller);
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
      onOpenChange: (open, _) {
        if (open) {
          _parent?.activateSubmenu(_controller);
        } else {
          _parent?.deactivateSubmenu(_controller);
        }
      },
      content: DDropdownMenuContent(
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
  });

  final String label;
  final bool enabled;
  final VoidCallback onActivate;
  final Widget child;
  final FocusNode? focusNode;
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

  @override
  State<_DropdownMenuItemSurface> createState() =>
      _DropdownMenuItemSurfaceState();
}

class _DropdownMenuItemSurfaceState extends State<_DropdownMenuItemSurface> {
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
    if (oldWidget.focusNode != widget.focusNode ||
        oldWidget.label != widget.label ||
        oldWidget.enabled != widget.enabled) {
      // Replace this State's registration in place so live labels and enabled
      // changes retain visual order for Home, arrows, and typeahead.
      _register();
    }
  }

  void _register() {
    _content = _DropdownMenuContentScope.of(context)
      ..register(this, _MenuRegistration(_focus, widget.label, widget.enabled));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
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
    final tokens = DTokens.of(context);
    final destructive = widget.variant == DDropdownMenuItemVariant.destructive;
    // Pointer hover is menu-local and deliberately does not move keyboard
    // focus. This keeps partially clipped rows from being implicitly revealed
    // while ensuring only the hovered row paints as active.
    final interactive =
        widget.enabled &&
        (_pressed ||
            _content?.isHovered(this) == true ||
            widget.expanded == true ||
            (_content?.hasActivePointerHighlight != true && _focused));
    final background = interactive
        ? destructive
              ? tokens.destructive.withValues(
                  alpha:
                      tokens.destructive.a *
                      (Theme.of(context).brightness == Brightness.dark
                          ? 0.20
                          : 0.10),
                )
              : tokens.hover
        : Colors.transparent;
    final foreground = destructive ? tokens.destructive : tokens.foreground;
    final mobile =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
    final visualHeight = mobile ? DSpacing.touchTarget : 28.0;
    final startPadding = widget.inset && widget.leading == null ? 28.0 : 6.0;
    // Active-row changes are atomic. Animating the previous row out while the
    // next row animates in briefly presents two highlighted menu choices.
    final row = Container(
      constraints: BoxConstraints(minHeight: visualHeight),
      padding: EdgeInsetsDirectional.fromSTEB(startPadding, 4, 6, 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radius * 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          if (widget.leading != null) ...[
            IconTheme.merge(
              data: IconThemeData(color: foreground, size: 16),
              child: SizedBox.square(dimension: 16, child: widget.leading),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(child: widget.child),
          if (widget.trailing != null) ...[
            const SizedBox(width: 6),
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
      excludeSemantics: widget.label.isNotEmpty,
      onTap: widget.enabled ? widget.onActivate : null,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: MouseRegion(
          // Menus use the platform's default cursor (shadcn `cursor-default`),
          // while hover/focus styling communicates the active row.
          cursor: SystemMouseCursors.basic,
          onEnter: (_) {
            if (!widget.enabled) return;
            if (!widget.preserveSubmenuOnFocus) {
              _content?.closeActiveSubmenu();
            }
            _content?.hover(this);
            widget.onHover?.call(true);
          },
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
              if (mounted) setState(() => _focused = focused);
            },
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled
                  ? (_) {
                      _focus.requestFocus();
                      setState(() => _pressed = true);
                    }
                  : null,
              onTapCancel: widget.enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              onTapUp: widget.enabled
                  ? (_) {
                      setState(() => _pressed = false);
                      widget.onActivate();
                    }
                  : null,
              child: DefaultTextStyle.merge(
                style: TextStyle(color: foreground),
                child: row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckIcon extends StatelessWidget {
  const _CheckIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(16),
    painter: _CheckPainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class _CheckIndicator extends StatelessWidget {
  const _CheckIndicator({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 16,
    child: checked ? const _CheckIcon() : null,
  );
}

class _CheckPainter extends CustomPainter {
  const _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.20, size.height * 0.52)
        ..lineTo(size.width * 0.42, size.height * 0.72)
        ..lineTo(size.width * 0.82, size.height * 0.28),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter oldDelegate) => color != oldDelegate.color;
}

class _DirectionalChevron extends StatelessWidget {
  const _DirectionalChevron();

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.chevron_right, size: 16);
}

String _plainText(Widget widget) => widget is Text ? widget.data ?? '' : '';
