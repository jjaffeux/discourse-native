import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'd_dropdown_menu.dart';
import 'd_popover.dart';

typedef DContextMenuController = DDropdownMenuController;
typedef DContextMenuOpenChange = DDropdownMenuOpenChange;

enum DContextMenuItemVariant { standard, destructive }

/// Imperatively asks one mounted [DContextMenuTrigger] to open at a location.
///
/// This is intended for composed gesture owners. Calls while detached are
/// ignored, and the trigger never disposes a borrowed controller.
class DContextMenuTriggerController {
  _DContextMenuTriggerState? _owner;

  void openAt(
    Offset localPosition, {
    DPopoverInteraction interaction = DPopoverInteraction.imperative,
  }) => _owner?._openFromController(localPosition, interaction);

  void openFromKeyboard() => _owner?._openKeyboardFromController();

  void _attach(_DContextMenuTriggerState owner) {
    _owner = owner;
  }

  void _detach(_DContextMenuTriggerState owner) {
    if (identical(_owner, owner)) _owner = null;
  }
}

/// A shadcn/Base UI context menu opened at a secondary-click or long-press
/// location.
///
/// The menu is an enhancement: callers should expose important actions through
/// a visible control as well. Supplying [open] enables controlled state.
class DContextMenu extends StatelessWidget {
  const DContextMenu({
    super.key,
    required this.child,
    required this.content,
    this.open,
    this.defaultOpen = false,
    this.controller,
    this.onOpenChange,
    this.onOpenChangeComplete,
    this.restoreFocus = true,
    this.disabled = false,
  });

  final Widget child;
  final DContextMenuContent content;
  final bool? open;
  final bool defaultOpen;
  final DContextMenuController? controller;
  final DContextMenuOpenChange? onOpenChange;
  final ValueChanged<bool>? onOpenChangeComplete;
  final bool restoreFocus;
  final bool disabled;

  @override
  Widget build(BuildContext context) => DDropdownMenu(
    open: disabled ? false : open,
    defaultOpen: disabled ? false : defaultOpen,
    controller: controller,
    onOpenChange: disabled ? null : onOpenChange,
    onOpenChangeComplete: onOpenChangeComplete,
    restoreFocus: restoreFocus,
    content: content,
    child: _ContextMenuEnabled(enabled: !disabled, child: child),
  );
}

class _ContextMenuEnabled extends InheritedWidget {
  const _ContextMenuEnabled({required this.enabled, required super.child});

  final bool enabled;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ContextMenuEnabled>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(_ContextMenuEnabled oldWidget) =>
      enabled != oldWidget.enabled;
}

/// The region that owns context invocation without adding a visible control.
///
/// Secondary pointer presses open at their local position. Touch long press,
/// the Context Menu key, Shift+F10, and the accessibility long-press action use
/// the same popup and restore focus to [focusNode] (or the internally-owned
/// node) after keyboard dismissal.
class DContextMenuTrigger extends StatefulWidget {
  const DContextMenuTrigger({
    super.key,
    required this.child,
    this.focusNode,
    this.controller,
    this.enabled = true,
    this.focusable = true,
    this.longPressEnabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final FocusNode? focusNode;
  final DContextMenuTriggerController? controller;
  final bool enabled;
  final bool focusable;
  final bool longPressEnabled;
  final String? semanticLabel;

  @override
  State<DContextMenuTrigger> createState() => _DContextMenuTriggerState();
}

class _DContextMenuTriggerState extends State<DContextMenuTrigger> {
  Offset _anchor = Offset.zero;
  DDropdownMenuTriggerState? _trigger;

  bool get _enabled => widget.enabled && _ContextMenuEnabled.of(context);

  Size get _size => context.size ?? Size.zero;

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  @override
  void didUpdateWidget(DContextMenuTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
  }

  void _openFromController(Offset position, DPopoverInteraction interaction) {
    final trigger = _trigger;
    if (trigger != null) _openAt(position, trigger, interaction);
  }

  void _openKeyboardFromController() {
    final trigger = _trigger;
    if (trigger != null) _openFromKeyboard(trigger);
  }

  void _openAt(
    Offset position,
    DDropdownMenuTriggerState trigger,
    DPopoverInteraction interaction,
  ) {
    if (!_enabled) return;
    setState(
      () => _anchor = Offset(
        position.dx.clamp(0, _size.width),
        position.dy.clamp(0, _size.height),
      ),
    );
    if (trigger.focusNode.canRequestFocus) trigger.focusNode.requestFocus();
    trigger.openPopover(interaction);
  }

  void _openFromKeyboard(DDropdownMenuTriggerState trigger) {
    final direction = Directionality.of(context);
    _openAt(
      Offset(direction == TextDirection.rtl ? _size.width : 0, _size.height),
      trigger,
      DPopoverInteraction.keyboard,
    );
  }

  KeyEventResult _onKey(KeyEvent event, DDropdownMenuTriggerState trigger) {
    if (event is! KeyDownEvent || !_enabled) return KeyEventResult.ignored;
    final contextKey = event.logicalKey == LogicalKeyboardKey.contextMenu;
    final shiftedF10 =
        event.logicalKey == LogicalKeyboardKey.f10 &&
        HardwareKeyboard.instance.isShiftPressed;
    if (!contextKey && !shiftedF10) return KeyEventResult.ignored;
    _openFromKeyboard(trigger);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => DDropdownMenuTrigger(
    focusNode: widget.focusNode,
    builder: (context, trigger) {
      _trigger = trigger;
      return Semantics(
        label: widget.semanticLabel,
        enabled: _enabled,
        onLongPress: _enabled && widget.longPressEnabled
            ? () => _openFromKeyboard(trigger)
            : null,
        child: Focus(
          focusNode: trigger.focusNode,
          canRequestFocus: _enabled && widget.focusable,
          skipTraversal: !widget.focusable,
          onKeyEvent: (_, event) => _onKey(event, trigger),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            excludeFromSemantics: true,
            onSecondaryTapDown: _enabled
                ? (details) => _openAt(
                    details.localPosition,
                    trigger,
                    DPopoverInteraction.mouse,
                  )
                : null,
            onLongPressStart: _enabled && widget.longPressEnabled
                ? (details) => _openAt(
                    details.localPosition,
                    trigger,
                    DPopoverInteraction.touch,
                  )
                : null,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                widget.child,
                Positioned(
                  left: _anchor.dx,
                  top: _anchor.dy,
                  child: const DPopoverAnchor(
                    child: SizedBox.square(dimension: 1),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }
}

/// Popup geometry from base-nova: 144px minimum width, 4px padding, an `lg`
/// radius, a translucent ring, and pointer-relative start alignment.
class DContextMenuContent extends DDropdownMenuContent {
  const DContextMenuContent({
    super.key,
    required super.children,
    super.semanticLabel,
    super.side = DPopoverSide.right,
    super.align = DPopoverAlign.start,
    super.sideOffset = 0,
    super.alignOffset = 4,
    super.sideCollision = DPopoverCollision.flip,
    super.alignCollision = DPopoverCollision.shift,
    super.collisionPadding = 5,
    super.collisionBoundary,
    super.width = 144,
    super.constraints = const BoxConstraints(minWidth: 144),
    super.isSubmenu = false,
    super.autofocus = true,
  });
}

class DContextMenuGroup extends StatelessWidget {
  const DContextMenuGroup({
    super.key,
    required this.children,
    this.semanticLabel,
  });

  final List<Widget> children;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      DDropdownMenuGroup(semanticLabel: semanticLabel, children: children);
}

class DContextMenuLabel extends StatelessWidget {
  const DContextMenuLabel({super.key, required this.child, this.inset = false});

  final Widget child;
  final bool inset;

  @override
  Widget build(BuildContext context) =>
      DDropdownMenuLabel(inset: inset, child: child);
}

class DContextMenuSeparator extends StatelessWidget {
  const DContextMenuSeparator({super.key});

  @override
  Widget build(BuildContext context) => const DDropdownMenuSeparator();
}

class DContextMenuShortcut extends StatelessWidget {
  const DContextMenuShortcut(this.label, {super.key, this.semanticLabel});

  final String label;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) =>
      DDropdownMenuShortcut(label, semanticLabel: semanticLabel);
}

class DContextMenuItem extends StatelessWidget {
  const DContextMenuItem({
    super.key,
    required this.child,
    this.onPressed,
    this.leading,
    this.trailing,
    this.inset = false,
    this.variant = DContextMenuItemVariant.standard,
    this.closeOnSelect = true,
    this.semanticLabel,
    this.focusNode,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final DContextMenuItemVariant variant;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => DDropdownMenuItem(
    onPressed: onPressed,
    leading: leading,
    trailing: trailing,
    inset: inset,
    variant: variant == DContextMenuItemVariant.destructive
        ? DDropdownMenuItemVariant.destructive
        : DDropdownMenuItemVariant.standard,
    closeOnSelect: closeOnSelect,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    child: child,
  );
}

/// A controlled or uncontrolled checkbox item. Set [enabled] to false rather
/// than omitting [onChanged] when using its internal state.
class DContextMenuCheckboxItem extends StatefulWidget {
  const DContextMenuCheckboxItem({
    super.key,
    required this.child,
    this.checked,
    this.defaultChecked = false,
    this.onChanged,
    this.enabled = true,
    this.leading,
    this.trailing,
    this.inset = false,
    this.closeOnSelect = false,
    this.semanticLabel,
    this.focusNode,
  });

  final Widget child;
  final bool? checked;
  final bool defaultChecked;
  final ValueChanged<bool>? onChanged;
  final bool enabled;
  final Widget? leading;
  final Widget? trailing;
  final bool inset;
  final bool closeOnSelect;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  State<DContextMenuCheckboxItem> createState() =>
      _DContextMenuCheckboxItemState();
}

class _DContextMenuCheckboxItemState extends State<DContextMenuCheckboxItem> {
  late bool _value = widget.defaultChecked;

  bool get _effectiveValue => widget.checked ?? _value;

  void _change(bool value) {
    if (widget.checked == null) setState(() => _value = value);
    widget.onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) => DDropdownMenuCheckboxItem(
    checked: _effectiveValue,
    onChanged: widget.enabled ? _change : null,
    leading: widget.leading,
    trailing: widget.trailing,
    inset: widget.inset,
    closeOnSelect: widget.closeOnSelect,
    semanticLabel: widget.semanticLabel,
    focusNode: widget.focusNode,
    child: widget.child,
  );
}

class DContextMenuRadioGroup<T> extends StatelessWidget {
  const DContextMenuRadioGroup({
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
  Widget build(BuildContext context) => DDropdownMenuRadioGroup<T>(
    value: value,
    onChanged: onChanged,
    semanticLabel: semanticLabel,
    children: children,
  );
}

class DContextMenuRadioItem<T> extends StatelessWidget {
  const DContextMenuRadioItem({
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
  Widget build(BuildContext context) => DDropdownMenuRadioItem<T>(
    value: value,
    leading: leading,
    trailing: trailing,
    inset: inset,
    closeOnSelect: closeOnSelect,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    child: child,
  );
}

class DContextMenuSub extends StatelessWidget {
  const DContextMenuSub({
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
  Widget build(BuildContext context) => DDropdownMenuSub(
    trigger: trigger,
    leading: leading,
    inset: inset,
    enabled: enabled,
    semanticLabel: semanticLabel,
    width: width,
    children: children,
  );
}
