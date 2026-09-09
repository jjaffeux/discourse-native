import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';
import 'd_popover.dart';

typedef DDropdownMenuController = DPopoverController;
typedef DDropdownMenuOpenChange = DPopoverOpenChange;
typedef DDropdownMenuTriggerState = DPopoverTriggerState;
typedef DDropdownMenuTriggerBuilder =
    Widget Function(BuildContext context, DDropdownMenuTriggerState state);

enum DDropdownMenuItemVariant { standard, destructive }

/// A shadcn/Base UI dropdown menu composed on the shared popover lifecycle.
///
/// Supplying [open] enables controlled state. [controller] and [triggerFocusNode]
/// are borrowed and never disposed; internally-created resources are owned by
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
  _MenuRegistration(this.node, this.label, this.activate, this.enabled);
  final FocusNode node;
  final String label;
  final VoidCallback activate;
  final bool enabled;
}

class _DDropdownMenuContentState extends State<DDropdownMenuContent> {
  final _items = <Object, _MenuRegistration>{};
  String _search = '';
  Timer? _searchTimer;
  bool _autofocused = false;

  void register(Object owner, _MenuRegistration registration) {
    _items[owner] = registration;
  }

  void unregister(Object owner) => _items.remove(owner);

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
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
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
              child: Padding(
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
    this.autofocus = false,
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
  final bool autofocus;

  @override
  Widget build(BuildContext context) => _DropdownMenuItemSurface(
    label: semanticLabel ?? _plainText(child),
    enabled: onPressed != null,
    focusNode: focusNode,
    autofocus: autofocus,
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
    trailing: trailing ?? (checked ? const _CheckIcon() : null),
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
      trailing: trailing ?? (checked ? const _CheckIcon() : null),
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

  @override
  void dispose() {
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
          onActivate: trigger.toggle,
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
    this.autofocus = false,
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
  final bool autofocus;

  @override
  State<_DropdownMenuItemSurface> createState() =>
      _DropdownMenuItemSurfaceState();
}

class _DropdownMenuItemSurfaceState extends State<_DropdownMenuItemSurface> {
  late FocusNode _ownedFocus;
  FocusNode get _focus => widget.focusNode ?? _ownedFocus;
  _DDropdownMenuContentState? _content;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

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
      _content?.unregister(this);
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
          widget.onActivate,
          widget.enabled,
        ),
      );
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
    final interactive = widget.enabled && (_hovered || _focused || _pressed);
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
    final row = AnimatedContainer(
      duration: DMotion.duration(context, DMotion.exit),
      curve: Curves.easeOut,
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
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) {
            if (!widget.enabled) return;
            setState(() => _hovered = true);
            _focus.requestFocus();
            widget.onHover?.call(true);
          },
          onExit: (_) {
            if (mounted) setState(() => _hovered = false);
            widget.onHover?.call(false);
          },
          child: Focus(
            focusNode: _focus,
            autofocus: widget.autofocus,
            canRequestFocus: widget.enabled,
            skipTraversal: !widget.enabled,
            onFocusChange: (focused) {
              if (mounted) setState(() => _focused = focused);
            },
            onKeyEvent: _onKey,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: widget.enabled
                  ? (_) => setState(() => _pressed = true)
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
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Icon(rtl ? Icons.chevron_left : Icons.chevron_right, size: 16);
  }
}

String _plainText(Widget widget) => widget is Text ? widget.data ?? '' : '';
