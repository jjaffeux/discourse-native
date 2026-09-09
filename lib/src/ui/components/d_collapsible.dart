import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../foundation/tokens.dart';

/// A disclosure scope. Layout and decoration belong to its child composition.
///
/// [open] makes state controlled: activation only calls [onOpenChange]. Without
/// it, [defaultOpen] initializes local state. Disabled blocks activation, not
/// programmatic state changes or interaction with already visible content.
/// This is not a form field: fields inside content retain their own Form owner.
class DCollapsible extends StatefulWidget {
  const DCollapsible({
    super.key,
    required this.child,
    this.open,
    this.defaultOpen = false,
    this.onOpenChange,
    this.disabled = false,
  });

  final Widget child;
  final bool? open;
  final bool defaultOpen;
  final ValueChanged<bool>? onOpenChange;
  final bool disabled;

  /// Reads the nearest root; useful for state-dependent composition styling.
  static bool isOpenOf(BuildContext context) => _Scope.of(context).open;

  @override
  State<DCollapsible> createState() => _DCollapsibleState();
}

class _DCollapsibleState extends State<DCollapsible> {
  late bool _open = widget.defaultOpen;
  final _triggers = <FocusNode>[];
  FocusNode? _lastTrigger;
  bool get open => widget.open ?? _open;

  @override
  void didUpdateWidget(DCollapsible oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open != null && widget.open == null) _open = oldWidget.open!;
  }

  void toggle(FocusNode trigger) {
    if (widget.disabled) return;
    _lastTrigger = trigger;
    final next = !open;
    if (widget.open == null) setState(() => _open = next);
    widget.onOpenChange?.call(next);
  }

  void restoreFocus() {
    final target = _triggers.contains(_lastTrigger)
        ? _lastTrigger
        : _triggers.where((node) => node.canRequestFocus).firstOrNull;
    if (target?.canRequestFocus ?? false) target!.requestFocus();
  }

  @override
  Widget build(BuildContext context) => _Scope(
    owner: this,
    open: open,
    disabled: widget.disabled,
    child: widget.child,
  );
}

class _Scope extends InheritedWidget {
  const _Scope({
    required this.owner,
    required this.open,
    required this.disabled,
    required super.child,
  });
  final _DCollapsibleState owner;
  final bool open;
  final bool disabled;
  static _Scope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_Scope>();
    assert(scope != null, 'Collapsible parts require a DCollapsible ancestor.');
    return scope!;
  }

  @override
  bool updateShouldNotify(_Scope oldWidget) =>
      open != oldWidget.open || disabled != oldWidget.disabled;
}

/// Visual state for a trigger's non-interactive child builder.
@immutable
class DCollapsibleTriggerState {
  const DCollapsibleTriggerState({
    required this.open,
    required this.disabled,
    required this.hovered,
    required this.pressed,
    required this.focused,
  });
  final bool open;
  final bool disabled;
  final bool hovered;
  final bool pressed;
  final bool focused;
}

/// Unstyled button behavior with expanded semantics, Enter/Space activation,
/// and a visible exterior focus outline. Disabled triggers remain focusable
/// for discoverability, matching Base UI, but cannot activate. Supply passive artwork, never another
/// button, through [child] or [builder]. Padding/size/variants belong to the
/// composition, not Collapsible. A supplied [focusNode] remains caller-owned.
class DCollapsibleTrigger extends StatefulWidget {
  const DCollapsibleTrigger({
    super.key,
    this.child,
    this.builder,
    this.focusNode,
    this.semanticLabel,
    this.disabled = false,
    this.focusBorderRadius,
    this.focusBorder = false,
    this.focusRingWidth = 2,
    this.focusRingOpacity = 1,
  }) : assert((child == null) != (builder == null)),
       assert(focusRingWidth >= 0),
       assert(focusRingOpacity >= 0 && focusRingOpacity <= 1);

  final Widget? child;
  final Widget Function(BuildContext, DCollapsibleTriggerState)? builder;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool disabled;

  /// Optional rounded focus treatment for styled compositions.
  ///
  /// When [focusBorder] is true a one-pixel border is painted on the control
  /// and [focusRingWidth] is painted outside it. Null preserves the original
  /// square two-pixel Collapsible outline.
  final BorderRadius? focusBorderRadius;
  final bool focusBorder;
  final double focusRingWidth;
  final double focusRingOpacity;

  @override
  State<DCollapsibleTrigger> createState() => _TriggerState();
}

class _TriggerState extends State<DCollapsibleTrigger> {
  late FocusNode _focus = widget.focusNode ?? FocusNode();
  _DCollapsibleState? _owner;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = _Scope.of(context).owner;
    if (_owner != owner) {
      _owner?._triggers.remove(_focus);
      _owner = owner;
      owner._triggers.add(_focus);
    }
  }

  @override
  void didUpdateWidget(DCollapsibleTrigger oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _owner?._triggers.remove(_focus);
      if (oldWidget.focusNode == null) _focus.dispose();
      _focus = widget.focusNode ?? FocusNode();
      _owner?._triggers.add(_focus);
    }
  }

  @override
  void dispose() {
    _owner?._triggers.remove(_focus);
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = _Scope.of(context);
    final enabled = !scope.disabled && !widget.disabled;
    void activate() {
      if (enabled) {
        _focus.requestFocus();
        scope.owner.toggle(_focus);
      }
    }

    final visual =
        widget.child ??
        widget.builder!(
          context,
          DCollapsibleTriggerState(
            open: scope.open,
            disabled: !enabled,
            hovered: enabled && _hovered,
            pressed: enabled && _pressed,
            focused: _focused,
          ),
        );
    return Semantics(
      container: true,
      button: true,
      expanded: scope.open,
      enabled: enabled,
      label: widget.semanticLabel,
      onTap: enabled ? activate : null,
      child: FocusableActionDetector(
        focusNode: _focus,
        enabled: true,
        mouseCursor: enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: enabled ? activate : null,
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: (_) => setState(() => _pressed = false),
          onTapCancel: () => setState(() => _pressed = false),
          child: CustomPaint(
            foregroundPainter: _FocusOutline(
              color: DTokens.of(context).focusRing,
              visible: _focused,
              borderRadius: widget.focusBorderRadius,
              border: widget.focusBorder,
              ringWidth: widget.focusRingWidth,
              ringOpacity: widget.focusRingOpacity,
            ),
            child: SelectionContainer.disabled(
              child: ExcludeSemantics(
                excluding: widget.semanticLabel != null,
                child: visual,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FocusOutline extends CustomPainter {
  const _FocusOutline({
    required this.color,
    required this.visible,
    required this.borderRadius,
    required this.border,
    required this.ringWidth,
    required this.ringOpacity,
  });
  final Color color;
  final bool visible;
  final BorderRadius? borderRadius;
  final bool border;
  final double ringWidth;
  final double ringOpacity;
  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    if (borderRadius == null) {
      canvas.drawRect(
        (Offset.zero & size).inflate(1),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      return;
    }
    final rect = Offset.zero & size;
    final borderRRect = borderRadius!.toRRect(rect);
    if (border) {
      canvas.drawRRect(
        borderRRect.deflate(.5),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    canvas.drawDRRect(
      borderRRect.inflate(ringWidth),
      borderRRect,
      Paint()
        ..color = color.withValues(alpha: color.a * ringOpacity)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_FocusOutline oldDelegate) =>
      color != oldDelegate.color ||
      visible != oldDelegate.visible ||
      borderRadius != oldDelegate.borderRadius ||
      border != oldDelegate.border ||
      ringWidth != oldDelegate.ringWidth ||
      ringOpacity != oldDelegate.ringOpacity;
}

/// Closed content is unmounted after its exit transition by default.
/// [keepMounted] retains fields, validation and state even before first open,
/// but excludes hidden content from focus, semantics, hit testing and tickers.
/// Fields still participate in their enclosing Form when retained.
///
/// Base-nova defines no transition; [duration] therefore defaults to zero.
/// Opt into clipped height animation explicitly. Reduced motion overrides it.
/// Browser find-in-page/hidden-until-found has no native equivalent; a host
/// search can reveal a match by setting the root's controlled open value.
class DCollapsibleContent extends StatefulWidget {
  const DCollapsibleContent({
    super.key,
    required this.child,
    this.keepMounted = false,
    this.duration = Duration.zero,
    this.curve = Curves.easeInOut,
  });
  final Widget child;
  final bool keepMounted;
  final Duration duration;
  final Curve curve;
  @override
  State<DCollapsibleContent> createState() => _ContentState();
}

class _ContentState extends State<DCollapsibleContent>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(vsync: this)
    ..addStatusListener((_) {
      if (mounted) setState(() {});
    });
  final _focus = FocusNode(canRequestFocus: false);
  bool? _open;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(DCollapsibleContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final scope = _Scope.of(context);
    final duration = DMotion.duration(context, widget.duration);
    _animation.duration = duration;
    if (!scope.open && _open == true && _focus.hasFocus) {
      scope.owner.restoreFocus();
    }
    if (_open == null || duration == Duration.zero) {
      _animation.value = scope.open ? 1 : 0;
    } else if (scope.open != _open) {
      unawaited(scope.open ? _animation.forward() : _animation.reverse());
    }
    _open = scope.open;
  }

  @override
  void dispose() {
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = _Scope.of(context).open;
    if (!open && _animation.isDismissed && !widget.keepMounted) {
      return const SizedBox.shrink();
    }
    return Offstage(
      offstage: !open && _animation.isDismissed,
      child: ExcludeSemantics(
        excluding: !open,
        child: ExcludeFocus(
          excluding: !open,
          child: IgnorePointer(
            ignoring: !open,
            child: TickerMode(
              enabled: open,
              child: Focus(
                focusNode: _focus,
                child: SizeTransition(
                  alignment: AlignmentDirectional.topStart,
                  sizeFactor: _animation.drive(CurveTween(curve: widget.curve)),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
