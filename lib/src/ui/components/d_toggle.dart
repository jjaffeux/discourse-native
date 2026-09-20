import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../foundation/control_style.dart';
import '../foundation/tokens.dart';

/// The two base-nova Toggle surface treatments.
enum DToggleVariant { standard, outline }

/// The shared button height scale.
typedef DToggleSize = DControlSize;

/// Icon placement follows the ambient reading direction.
enum DToggleIconPosition { start, end }

/// Selects which visual edges keep the Toggle's resting border.
///
/// Most callers use [all]. Toggle Group uses this to collapse the shared edge
/// of connected outline items while [DToggle] remains the painting owner.
@immutable
class DToggleBorderEdges {
  const DToggleBorderEdges({
    this.top = true,
    this.bottom = true,
    this.start = true,
    this.end = true,
  });

  static const all = DToggleBorderEdges();

  final bool top;
  final bool bottom;
  final bool start;
  final bool end;
}

/// Narrow visual overrides for documented Toggle compositions.
///
/// Interaction, semantics and size remain owned by [DToggle].
@immutable
class DToggleVisualStyle {
  const DToggleVisualStyle({
    this.borderRadius,
    this.borderEdges = DToggleBorderEdges.all,
  });

  final BorderRadiusGeometry? borderRadius;
  final DToggleBorderEdges borderEdges;
}

/// A two-state button with native pressed-toggle semantics.
///
/// Supply [pressed] for controlled state, or omit it to own state initialized
/// by [initialPressed]. [onPressedChanged] observes or updates that state but
/// is not required for the control to remain focusable. [focusNode] is
/// borrowed and never disposed. Desktop artwork follows base-nova's compact
/// bounds while touch platforms receive an invisible 48px minimum target.
class DToggle extends StatefulWidget {
  const DToggle({
    super.key,
    required this.child,
    this.icon,
    this.selectedIcon,
    this.iconPosition = DToggleIconPosition.start,
    this.pressed,
    this.initialPressed = false,
    this.onPressedChanged,
    this.onLongPress,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.semanticLabel,
    this.semanticHint,
    this.semanticLongPressHint,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChanged,
    this.visualStyle,
  }) : _iconOnly = false;

  const DToggle.iconOnly({
    super.key,
    required this.icon,
    this.selectedIcon,
    required this.semanticLabel,
    this.pressed,
    this.initialPressed = false,
    this.onPressedChanged,
    this.onLongPress,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.semanticHint,
    this.semanticLongPressHint,
    this.focusNode,
    this.autofocus = false,
    this.onFocusChanged,
    this.visualStyle,
  }) : child = const SizedBox.shrink(),
       iconPosition = DToggleIconPosition.start,
       _iconOnly = true;

  final Widget child;
  final Widget? icon;

  /// Optional replacement artwork while toggled on.
  final Widget? selectedIcon;
  final DToggleIconPosition iconPosition;

  /// Non-null values are parent-owned. Null uses [initialPressed].
  final bool? pressed;
  final bool initialPressed;
  final ValueChanged<bool>? onPressedChanged;

  /// A secondary action that does not change the pressed value.
  /// Disabled controls suppress both pointer and semantic long presses.
  final VoidCallback? onLongPress;
  final bool enabled;

  /// Keeps the value and focus available while suppressing toggle actions.
  /// Unlike a disabled control, a read-only toggle can still [onLongPress].
  final bool readOnly;
  final bool invalid;
  final DToggleVariant variant;
  final DToggleSize size;
  final String? semanticLabel;
  final String? semanticHint;
  final String? semanticLongPressHint;

  /// Borrowed from the caller and never disposed by this widget.
  final FocusNode? focusNode;
  final bool autofocus;
  final ValueChanged<bool>? onFocusChanged;

  /// Optional joined border treatment; size remains owned by this Toggle.
  final DToggleVisualStyle? visualStyle;
  final bool _iconOnly;

  static double visualDimensionFor(DToggleSize size) =>
      DControlStyle.height(size);
  static double iconDimensionFor(DToggleSize size) =>
      DControlStyle.iconDimension(size);
  static double fontSizeFor(DToggleSize size) => DControlStyle.fontSize(size);

  static EdgeInsetsGeometry _paddingFor(
    DToggleSize size, {
    required bool hasIcon,
    required DToggleIconPosition iconPosition,
  }) {
    if (!hasIcon) return const EdgeInsets.symmetric(horizontal: 10);
    final iconEdge = size == DToggleSize.small ? 6.0 : 8.0;
    return switch (iconPosition) {
      DToggleIconPosition.start => EdgeInsetsDirectional.only(
        start: iconEdge,
        end: 10,
      ),
      DToggleIconPosition.end => EdgeInsetsDirectional.only(
        start: 10,
        end: iconEdge,
      ),
    };
  }

  @override
  State<DToggle> createState() => _DToggleState();
}

class _DToggleState extends State<DToggle> {
  late bool _pressed = widget.initialPressed;
  bool _focusVisible = false;
  bool _hovered = false;
  bool _pointerPressed = false;
  FocusNode? _ownedFocus;

  FocusNode get _focus =>
      widget.focusNode ?? (_ownedFocus ??= FocusNode(debugLabel: 'Toggle'));
  bool get _current => widget.pressed ?? _pressed;
  bool get _enabled => widget.enabled;
  bool get _canToggle => _enabled && !widget.readOnly;

  @override
  void didUpdateWidget(DToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_canToggle) _pointerPressed = false;
    if (oldWidget.pressed case final previous? when widget.pressed == null) {
      _pressed = previous;
    }
  }

  @override
  void dispose() {
    _ownedFocus?.dispose();
    super.dispose();
  }

  void _toggle() {
    if (!_canToggle) return;
    final next = !_current;
    if (widget.pressed == null) setState(() => _pressed = next);
    widget.onPressedChanged?.call(next);
  }

  void _setPointerPressed(bool value) {
    if (_pointerPressed == value || !mounted) return;
    setState(() => _pointerPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = DTokens.of(context);
    final dark = theme.brightness == Brightness.dark;
    final outlined = widget.variant == DToggleVariant.outline;
    final outline = tokens.buttonTheme.outline;
    final foreground = outlined ? outline.foreground : tokens.foreground;
    final visualDimension = DControlStyle.scaledHeight(
      widget.size,
      MediaQuery.textScalerOf(context),
      context: context,
    );
    final iconDimension = DControlStyle.iconDimension(
      widget.size,
      context: context,
    );
    final fontSize = DControlStyle.fontSize(widget.size, context: context);
    final touch = switch (theme.platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };
    final activeSurface =
        _current || (_enabled && (_hovered || _pointerPressed));
    final borderColor = widget.invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : outlined
        ? (activeSurface ? outline.hoverBorder : outline.border)
        : _focusVisible
        ? tokens.focusRing
        : Colors.transparent;
    final ringColor = widget.invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .4 : .2),
          )
        : _focusVisible
        ? tokens.focusRing
        : Colors.transparent;
    final direction = Directionality.of(context);
    final radius =
        (widget.visualStyle?.borderRadius ??
                BorderRadius.circular(
                  outlined
                      ? tokens.buttonTheme.radius
                      : DControlStyle.radius(tokens, widget.size),
                ))
            .resolve(direction);
    final edges = widget.visualStyle?.borderEdges ?? DToggleBorderEdges.all;
    final borderSide = BorderSide(
      color: borderColor,
      width: outlined ? 1 : DControlDecoration.borderWidth,
    );
    const noBorder = BorderSide.none;
    final border = Border(
      top: edges.top ? borderSide : noBorder,
      bottom: edges.bottom ? borderSide : noBorder,
      left: (direction == TextDirection.ltr ? edges.start : edges.end)
          ? borderSide
          : noBorder,
      right: (direction == TextDirection.ltr ? edges.end : edges.start)
          ? borderSide
          : noBorder,
    );

    final effectiveIcon = _current
        ? widget.selectedIcon ?? widget.icon
        : widget.icon;
    Widget content = widget._iconOnly
        ? ExcludeSemantics(child: effectiveIcon!)
        : DefaultTextStyle.merge(
            style: theme.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontSize: fontSize,
              height:
                  DControlStyle.lineHeight(widget.size, context: context) /
                  fontSize,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            child: effectiveIcon == null
                ? ExcludeSemantics(
                    excluding: widget.semanticLabel != null,
                    child: widget.child,
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.iconPosition == DToggleIconPosition.start) ...[
                        Flexible(child: ExcludeSemantics(child: effectiveIcon)),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: ExcludeSemantics(
                          excluding: widget.semanticLabel != null,
                          child: widget.child,
                        ),
                      ),
                      if (widget.iconPosition == DToggleIconPosition.end) ...[
                        const SizedBox(width: 4),
                        Flexible(child: ExcludeSemantics(child: effectiveIcon)),
                      ],
                    ],
                  ),
          );
    content = IconTheme.merge(
      data: IconThemeData(size: iconDimension, color: foreground),
      child: content,
    );

    final artwork = AnimatedContainer(
      duration: Duration.zero,
      curve: const Cubic(.4, 0, .2, 1),
      constraints: BoxConstraints(
        minWidth: visualDimension,
        minHeight: visualDimension,
      ),
      padding: (widget._iconOnly
          ? EdgeInsets.zero
          : DToggle._paddingFor(
              widget.size,
              hasIcon: effectiveIcon != null,
              iconPosition: widget.iconPosition,
            )),
      decoration: BoxDecoration(
        color: outlined
            ? (activeSurface ? outline.hover : outline.background)
            : activeSurface
            ? DControlStyle.rowHover(tokens)
            : Colors.transparent,
        borderRadius: radius,
        border: border,
      ),
      foregroundDecoration: DControlDecoration(
        color: Colors.transparent,
        borderColor: Colors.transparent,
        borderRadius: radius,
        ringColor: ringColor,
        ringWidth: DControlStyle.focusWidth,
        ringOffset: DControlStyle.focusOffset,
      ),
      child: Center(widthFactor: 1, heightFactor: 1, child: content),
    );

    final targetConstraints = BoxConstraints(
      minWidth: touch ? DSpacing.touchTarget : visualDimension,
      minHeight: touch ? DSpacing.touchTarget : visualDimension,
    );
    final target = ConstrainedBox(
      constraints: targetConstraints,
      child: Center(widthFactor: 1, heightFactor: 1, child: artwork),
    );

    return MergeSemantics(
      child: Semantics(
        container: true,
        button: true,
        toggled: _current,
        enabled: _enabled,
        label: widget.semanticLabel,
        hint: widget.semanticHint,
        onLongPressHint: _enabled && widget.onLongPress != null
            ? widget.semanticLongPressHint
            : null,
        onLongPress: _enabled ? widget.onLongPress : null,
        validationResult: widget.invalid
            ? SemanticsValidationResult.invalid
            : SemanticsValidationResult.none,
        onTap: _canToggle ? _toggle : null,
        child: MouseRegion(
          onEnter: (_) {
            if (!_hovered) setState(() => _hovered = true);
          },
          onExit: (_) {
            if (_hovered) setState(() => _hovered = false);
          },
          child: FocusableActionDetector(
            enabled: _enabled,
            focusNode: _focus,
            autofocus: widget.autofocus,
            mouseCursor: !_enabled
                ? SystemMouseCursors.forbidden
                : widget.readOnly
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            onShowFocusHighlight: (value) {
              if (_focusVisible != value) setState(() => _focusVisible = value);
            },
            onFocusChange: widget.onFocusChanged,
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            },
            actions: {
              ActivateIntent: CallbackAction<ActivateIntent>(
                onInvoke: (_) {
                  _toggle();
                  return null;
                },
              ),
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onLongPress: _enabled ? widget.onLongPress : null,
              onTapDown: _canToggle ? (_) => _setPointerPressed(true) : null,
              onTapUp: _canToggle ? (_) => _setPointerPressed(false) : null,
              onTapCancel: _canToggle ? () => _setPointerPressed(false) : null,
              onTap: _canToggle
                  ? () {
                      _focus.requestFocus();
                      _toggle();
                    }
                  : null,
              child: Opacity(opacity: _enabled ? 1 : .6, child: target),
            ),
          ),
        ),
      ),
    );
  }
}
