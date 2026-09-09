import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_dropdown_menu.dart';
import 'd_popover.dart';

typedef DMenubarOpenChange = DDropdownMenuOpenChange;
typedef DMenubarMenuController = DDropdownMenuController;

enum DMenubarItemVariant { standard, destructive }

/// A persistent in-app command menubar styled after shadcn/base-nova.
///
/// The root owns top-level roving focus and ensures that only one child menu is
/// open. It deliberately does not integrate with the operating system's native
/// application menu; platform menu ownership belongs at the application shell.
class DMenubar extends StatefulWidget {
  const DMenubar({
    super.key,
    required this.children,
    this.disabled = false,
    this.loopFocus = true,
    this.orientation = Axis.horizontal,
    this.semanticLabel = 'Menu bar',
  });

  final List<Widget> children;
  final bool disabled;
  final bool loopFocus;
  final Axis orientation;
  final String semanticLabel;

  @override
  State<DMenubar> createState() => _DMenubarState();
}

class _MenubarRegistration {
  _MenubarRegistration({
    required this.owner,
    required this.controller,
    required this.focusNode,
    required this.enabled,
  });

  final Object owner;
  final DMenubarMenuController controller;
  final FocusNode focusNode;
  bool enabled;
}

class _DMenubarState extends State<DMenubar> {
  final Map<Object, _MenubarRegistration> _menus = {};
  _MenubarRegistration? _current;
  _MenubarRegistration? _openMenu;
  bool _switching = false;

  List<_MenubarRegistration> get _enabledMenus => [
    for (final menu in _menus.values)
      if (!widget.disabled && menu.enabled && menu.focusNode.canRequestFocus)
        menu,
  ];

  void register(_MenubarRegistration menu) {
    _menus[menu.owner] = menu;
    if (_current == null && menu.enabled && !widget.disabled) _current = menu;
  }

  void update(_MenubarRegistration menu, {required bool enabled}) {
    menu.enabled = enabled;
    if (!enabled && identical(_openMenu, menu)) menu.controller.close();
    if (!enabled && identical(_current, menu)) {
      _current = _enabledMenus.firstOrNull;
    }
  }

  void unregister(_MenubarRegistration menu) {
    _menus.remove(menu.owner);
    if (identical(_openMenu, menu)) _openMenu = null;
    if (identical(_current, menu)) _current = _enabledMenus.firstOrNull;
  }

  bool isCurrent(_MenubarRegistration menu) => identical(_current, menu);

  void focused(_MenubarRegistration menu) {
    if (identical(_current, menu)) return;
    setState(() => _current = menu);
  }

  void opened(_MenubarRegistration menu) {
    if (identical(_openMenu, menu)) return;
    final previous = _openMenu;
    _switching = previous != null;
    _openMenu = menu;
    previous?.controller.close();
    _switching = false;
    if (mounted) setState(() => _current = menu);
  }

  void closed(_MenubarRegistration menu) {
    if (!identical(_openMenu, menu)) return;
    _openMenu = null;
    if (!_switching && menu.focusNode.canRequestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _openMenu == null && menu.focusNode.canRequestFocus) {
          menu.focusNode.requestFocus();
        }
      });
    }
    if (mounted) setState(() {});
  }

  void open(_MenubarRegistration menu) {
    if (widget.disabled || !menu.enabled) return;
    if (!identical(_openMenu, menu)) {
      final previous = _openMenu;
      _switching = previous != null;
      _openMenu = menu;
      previous?.controller.close();
      menu.focusNode.requestFocus();
      menu.controller.open();
      _switching = false;
      if (mounted) setState(() => _current = menu);
    }
  }

  void move(_MenubarRegistration from, int delta, {bool keepOpen = false}) {
    final menus = _enabledMenus;
    if (menus.isEmpty) return;
    final currentIndex = menus.indexOf(from);
    var next = (currentIndex < 0 ? 0 : currentIndex) + delta;
    if (widget.loopFocus) {
      next = next % menus.length;
    } else {
      next = next.clamp(0, menus.length - 1);
    }
    focus(menus[next], keepOpen: keepOpen);
  }

  void focusEdge({required bool last, bool keepOpen = false}) {
    final menus = _enabledMenus;
    if (menus.isEmpty) return;
    focus(last ? menus.last : menus.first, keepOpen: keepOpen);
  }

  void focus(_MenubarRegistration menu, {required bool keepOpen}) {
    menu.focusNode.requestFocus();
    if (keepOpen || _openMenu != null) open(menu);
    if (mounted) setState(() => _current = menu);
  }

  @override
  void didUpdateWidget(DMenubar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.disabled && !oldWidget.disabled) {
      _openMenu?.controller.close();
      _openMenu = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final horizontal = widget.orientation == Axis.horizontal;
    final content = Flex(
      direction: widget.orientation,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < widget.children.length; index++) ...[
          if (index > 0)
            SizedBox(width: horizontal ? 2 : 0, height: horizontal ? 0 : 2),
          widget.children[index],
        ],
      ],
    );
    final bar = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radius),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: horizontal
              ? SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: content,
                )
              : content,
        ),
      ),
    );
    return _MenubarScope(
      state: this,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: widget.semanticLabel,
        child: Opacity(
          opacity: widget.disabled ? 0.5 : 1,
          child: horizontal ? IntrinsicWidth(child: bar) : bar,
        ),
      ),
    );
  }
}

class _MenubarScope extends InheritedWidget {
  const _MenubarScope({required this.state, required super.child});

  final _DMenubarState state;

  static _DMenubarState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_MenubarScope>();
    assert(scope != null, 'DMenubarMenu requires a DMenubar ancestor.');
    return scope!.state;
  }

  @override
  bool updateShouldNotify(_MenubarScope oldWidget) => true;
}

/// One top-level menu and its persistent trigger.
class DMenubarMenu extends StatefulWidget {
  const DMenubarMenu({
    super.key,
    required this.trigger,
    required this.content,
    this.enabled = true,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.onOpenChange,
    this.onOpenChangeComplete,
  });

  final DMenubarTrigger trigger;
  final DMenubarContent content;
  final bool enabled;
  final bool? open;
  final bool defaultOpen;
  final DMenubarMenuController? controller;
  final DMenubarOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;

  @override
  State<DMenubarMenu> createState() => _DMenubarMenuState();
}

class _DMenubarMenuState extends State<DMenubarMenu> {
  late final _ownedController = DMenubarMenuController();
  late final _focusNode = FocusNode(debugLabel: 'Menubar trigger');
  late _MenubarRegistration _registration = _MenubarRegistration(
    owner: this,
    controller: widget.controller ?? _ownedController,
    focusNode: _focusNode,
    enabled: widget.enabled,
  );
  _DMenubarState? _root;

  DMenubarMenuController get _controller =>
      widget.controller ?? _ownedController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_controllerChanged);
  }

  void _controllerChanged() {
    if (_controller.isOpen) {
      _root?.opened(_registration);
    } else {
      _root?.closed(_registration);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final root = _MenubarScope.of(context);
    if (!identical(root, _root)) {
      _root?.unregister(_registration);
      _root = root..register(_registration);
    }
  }

  @override
  void didUpdateWidget(DMenubarMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownedController).removeListener(
        _controllerChanged,
      );
      _root?.unregister(_registration);
      _registration = _MenubarRegistration(
        owner: this,
        controller: _controller,
        focusNode: _focusNode,
        enabled: widget.enabled,
      );
      _root?.register(_registration);
      _controller.addListener(_controllerChanged);
    } else if (oldWidget.enabled != widget.enabled) {
      _root?.update(_registration, enabled: widget.enabled);
    }
  }

  @override
  void dispose() {
    _root?.unregister(_registration);
    _controller.removeListener(_controllerChanged);
    _ownedController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !(_root?.widget.disabled ?? false);
    return _MenubarMenuScope(
      registration: _registration,
      child: DDropdownMenu(
        open: active ? widget.open : false,
        defaultOpen: active && widget.defaultOpen,
        controller: _controller,
        restoreFocus: false,
        onOpenChange: (open, reason) {
          if (widget.open == null) {
            if (open) {
              _root?.opened(_registration);
            } else {
              _root?.closed(_registration);
            }
          }
          widget.onOpenChange?.call(open, reason);
        },
        onOpenChangeComplete: widget.onOpenChangeComplete,
        content: widget.content._dropdownContent(
          side:
              widget.content.side ??
              (_root?.widget.orientation == Axis.vertical
                  ? DPopoverSide.inlineEnd
                  : DPopoverSide.bottom),
        ),
        child: widget.trigger,
      ),
    );
  }
}

class _MenubarMenuScope extends InheritedWidget {
  const _MenubarMenuScope({required this.registration, required super.child});

  final _MenubarRegistration registration;

  static _MenubarRegistration of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MenubarMenuScope>();
    assert(scope != null, 'DMenubarTrigger requires a DMenubarMenu ancestor.');
    return scope!.registration;
  }

  @override
  bool updateShouldNotify(_MenubarMenuScope oldWidget) =>
      registration != oldWidget.registration;
}

/// The compact top-level trigger. Its focus node participates in root roving
/// focus while the Dropdown Menu remains the popup lifecycle owner.
class DMenubarTrigger extends StatefulWidget {
  const DMenubarTrigger({super.key, required this.child, this.semanticLabel});

  final Widget child;
  final String? semanticLabel;

  @override
  State<DMenubarTrigger> createState() => _DMenubarTriggerState();
}

class _DMenubarTriggerState extends State<DMenubarTrigger> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _revealFocusedTrigger() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focused) return;
      Scrollable.ensureVisible(
        context,
        duration: DMotion.duration(context, DMotion.exit),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  KeyEventResult _onKey(
    KeyEvent event,
    _DMenubarState root,
    _MenubarRegistration menu,
    DDropdownMenuTriggerState trigger,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final horizontal = root.widget.orientation == Axis.horizontal;
    final direction = Directionality.of(context);
    final previousKey = horizontal
        ? direction == TextDirection.ltr
              ? LogicalKeyboardKey.arrowLeft
              : LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowUp;
    final nextKey = horizontal
        ? direction == TextDirection.ltr
              ? LogicalKeyboardKey.arrowRight
              : LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowDown;
    if (event.logicalKey == previousKey || event.logicalKey == nextKey) {
      root.move(
        menu,
        event.logicalKey == nextKey ? 1 : -1,
        keepOpen: trigger.open,
      );
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home ||
        event.logicalKey == LogicalKeyboardKey.end) {
      root.focusEdge(
        last: event.logicalKey == LogicalKeyboardKey.end,
        keepOpen: trigger.open,
      );
      return KeyEventResult.handled;
    }
    final openKey = horizontal
        ? LogicalKeyboardKey.arrowDown
        : direction == TextDirection.ltr
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowLeft;
    if (event.logicalKey == openKey ||
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.space) {
      trigger.openPopover(DPopoverInteraction.keyboard);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final root = _MenubarScope.of(context);
    final menu = _MenubarMenuScope.of(context);
    final enabled = !root.widget.disabled && menu.enabled;
    final tokens = DTokens.of(context);
    return DDropdownMenuTrigger(
      focusNode: menu.focusNode,
      builder: (context, trigger) {
        final active =
            enabled && (_hovered || _pressed || _focused || trigger.open);
        final mobile = defaultTargetPlatform == TargetPlatform.iOS;
        final style = Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: tokens.foreground,
          fontSize: DiscourseTypography.sm,
          height: DiscourseTypography.lineHeightSmall,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          decoration: TextDecoration.none,
        );
        return Semantics(
          button: true,
          enabled: enabled,
          expanded: trigger.open,
          label: widget.semanticLabel,
          excludeSemantics: widget.semanticLabel != null,
          onTap: enabled ? trigger.toggle : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: MouseRegion(
              cursor: enabled
                  ? SystemMouseCursors.click
                  : SystemMouseCursors.basic,
              onEnter: (_) {
                if (!enabled) return;
                setState(() => _hovered = true);
                if (root._openMenu != null && !trigger.open) root.open(menu);
              },
              onExit: (_) {
                if (mounted) setState(() => _hovered = false);
              },
              child: Focus(
                focusNode: trigger.focusNode,
                canRequestFocus: enabled,
                skipTraversal: !root.isCurrent(menu),
                onFocusChange: (focused) {
                  if (focused) {
                    root.focused(menu);
                    _revealFocusedTrigger();
                  }
                  if (mounted) setState(() => _focused = focused);
                },
                onKeyEvent: (_, event) => _onKey(event, root, menu, trigger),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: enabled
                      ? (_) => setState(() => _pressed = true)
                      : null,
                  onTapCancel: enabled
                      ? () => setState(() => _pressed = false)
                      : null,
                  onTapUp: enabled
                      ? (_) {
                          setState(() => _pressed = false);
                          trigger.toggle();
                        }
                      : null,
                  child: AnimatedContainer(
                    duration: DMotion.duration(context, DMotion.exit),
                    constraints: BoxConstraints(
                      minWidth: mobile ? DSpacing.touchTarget : 0,
                      minHeight: mobile ? DSpacing.touchTarget : 24,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: active ? tokens.muted : Colors.transparent,
                      borderRadius: BorderRadius.circular(tokens.radius * 0.6),
                    ),
                    child: DefaultTextStyle(style: style, child: widget.child),
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

/// Popup configuration for one top-level menu.
class DMenubarContent {
  const DMenubarContent({
    required this.children,
    this.semanticLabel,
    this.side,
    this.align = DPopoverAlign.start,
    this.alignOffset = -4,
    this.sideOffset = 8,
    this.width = 160,
    this.constraints = const BoxConstraints(minWidth: 144),
    this.sideCollision = DPopoverCollision.flip,
    this.alignCollision = DPopoverCollision.shift,
    this.collisionPadding = 5,
    this.collisionBoundary,
  });

  final List<Widget> children;
  final String? semanticLabel;
  final DPopoverSide? side;
  final DPopoverAlign align;
  final double alignOffset;
  final double sideOffset;
  final double width;
  final BoxConstraints constraints;
  final DPopoverCollision sideCollision;
  final DPopoverCollision alignCollision;
  final double collisionPadding;
  final Rect? collisionBoundary;

  DDropdownMenuContent _dropdownContent({required DPopoverSide side}) =>
      DDropdownMenuContent(
        semanticLabel: semanticLabel,
        side: side,
        align: align,
        alignOffset: alignOffset,
        sideOffset: sideOffset,
        width: width,
        constraints: constraints,
        sideCollision: sideCollision,
        alignCollision: alignCollision,
        collisionPadding: collisionPadding,
        collisionBoundary: collisionBoundary,
        children: [
          _MenubarContentKeyboardBridge(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      );
}

class _MenubarContentKeyboardBridge extends StatelessWidget {
  const _MenubarContentKeyboardBridge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final root = _MenubarScope.of(context);
    final menu = _MenubarMenuScope.of(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final horizontal = root.widget.orientation == Axis.horizontal;
        final direction = Directionality.of(context);
        final previous = horizontal
            ? direction == TextDirection.ltr
                  ? LogicalKeyboardKey.arrowLeft
                  : LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowUp;
        final next = horizontal
            ? direction == TextDirection.ltr
                  ? LogicalKeyboardKey.arrowRight
                  : LogicalKeyboardKey.arrowLeft
            : LogicalKeyboardKey.arrowDown;
        if (event.logicalKey == previous || event.logicalKey == next) {
          root.move(menu, event.logicalKey == next ? 1 : -1, keepOpen: true);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.home ||
            event.logicalKey == LogicalKeyboardKey.end) {
          root.focusEdge(
            last: event.logicalKey == LogicalKeyboardKey.end,
            keepOpen: true,
          );
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

class DMenubarGroup extends StatelessWidget {
  const DMenubarGroup({super.key, required this.children, this.semanticLabel});

  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      DDropdownMenuGroup(semanticLabel: semanticLabel, children: children);
}

class DMenubarItem extends StatelessWidget {
  const DMenubarItem({
    super.key,
    required this.child,
    this.onPressed,
    this.leading,
    this.trailing,
    this.inset = false,
    this.variant = DMenubarItemVariant.standard,
    this.closeOnSelect = true,
    this.semanticLabel,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final DMenubarItemVariant variant;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DDropdownMenuItem(
    onPressed: onPressed,
    leading: leading,
    trailing: trailing,
    inset: inset,
    variant: variant == DMenubarItemVariant.destructive
        ? DDropdownMenuItemVariant.destructive
        : DDropdownMenuItemVariant.standard,
    closeOnSelect: closeOnSelect,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    child: child,
  );
}

class DMenubarCheckboxItem extends StatelessWidget {
  const DMenubarCheckboxItem({
    super.key,
    required this.checked,
    required this.onChanged,
    required this.child,
    this.inset = false,
    this.closeOnSelect = false,
    this.semanticLabel,
    this.focusNode,
  });

  final bool checked;
  final ValueChanged<bool>? onChanged;
  final Widget child;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DDropdownMenuCheckboxItem(
    checked: checked,
    onChanged: onChanged,
    inset: inset,
    closeOnSelect: closeOnSelect,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    leading: checked
        ? const _MenubarCheckIcon()
        : const SizedBox.square(dimension: 16),
    trailing: const SizedBox.shrink(),
    child: child,
  );
}

class DMenubarRadioGroup<T> extends StatelessWidget {
  const DMenubarRadioGroup({
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
  Widget build(BuildContext context) => _MenubarRadioValueScope<T>(
    value: value,
    child: DDropdownMenuRadioGroup<T>(
      value: value,
      onChanged: onChanged,
      semanticLabel: semanticLabel,
      children: children,
    ),
  );
}

class DMenubarRadioItem<T> extends StatelessWidget {
  const DMenubarRadioItem({
    super.key,
    required this.value,
    required this.child,
    this.inset = false,
    this.closeOnSelect = false,
    this.semanticLabel,
    this.focusNode,
  });

  final T value;
  final Widget child;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scope = _MenubarRadioValueScope.of<T>(context);
    final checked = scope.value == value;
    return DDropdownMenuRadioItem<T>(
      value: value,
      inset: inset,
      closeOnSelect: closeOnSelect,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      leading: checked
          ? const _MenubarCheckIcon()
          : const SizedBox.square(dimension: 16),
      trailing: const SizedBox.shrink(),
      child: child,
    );
  }
}

class _MenubarRadioValueScope<T> extends InheritedWidget {
  const _MenubarRadioValueScope({required this.value, required super.child});
  final T value;

  static _MenubarRadioValueScope<T> of<T>(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MenubarRadioValueScope<T>>();
    assert(scope != null, 'DMenubarRadioItem requires DMenubarRadioGroup<$T>.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_MenubarRadioValueScope<T> oldWidget) =>
      value != oldWidget.value;
}

class DMenubarLabel extends StatelessWidget {
  const DMenubarLabel({super.key, required this.child, this.inset = false});

  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: EdgeInsetsDirectional.fromSTEB(inset ? 28 : 6, 4, 6, 4),
      child: DefaultTextStyle.merge(
        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
          color: DTokens.of(context).foreground,
          fontSize: DiscourseTypography.sm,
          height: DiscourseTypography.lineHeightSmall,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
        ),
        child: child,
      ),
    ),
  );
}

class DMenubarSeparator extends StatelessWidget {
  const DMenubarSeparator({super.key});

  @override
  Widget build(BuildContext context) => const DDropdownMenuSeparator();
}

class DMenubarShortcut extends StatelessWidget {
  const DMenubarShortcut(this.label, {super.key, this.semanticLabel});
  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      DDropdownMenuShortcut(label, semanticLabel: semanticLabel);
}

class DMenubarSub extends StatelessWidget {
  const DMenubarSub({super.key, required this.trigger, required this.content});

  final DMenubarSubTrigger trigger;
  final DMenubarSubContent content;

  @override
  Widget build(BuildContext context) => DDropdownMenuSub(
    trigger: trigger.child,
    leading: trigger.leading,
    inset: trigger.inset,
    enabled: trigger.enabled,
    semanticLabel: trigger.semanticLabel,
    width: content.width,
    children: content.children,
  );
}

class DMenubarSubTrigger {
  const DMenubarSubTrigger({
    required this.child,
    this.leading,
    this.inset = false,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final Widget? leading;
  final bool inset;
  final bool enabled;
  final String? semanticLabel;
}

class DMenubarSubContent {
  const DMenubarSubContent({required this.children, this.width = 160});
  final List<Widget> children;
  final double width;
}

class _MenubarCheckIcon extends StatelessWidget {
  const _MenubarCheckIcon();

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(16),
    painter: _MenubarCheckPainter(IconTheme.of(context).color ?? Colors.black),
  );
}

class _MenubarCheckPainter extends CustomPainter {
  const _MenubarCheckPainter(this.color);
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
  bool shouldRepaint(_MenubarCheckPainter oldDelegate) =>
      color != oldDelegate.color;
}
