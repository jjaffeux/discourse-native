import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../foundation/control_style.dart';
import '../foundation/material_surface.dart';
import '../foundation/tokens.dart';

/// Toggle surface treatments, including the inset group's segmented choices.
enum DToggleVariant { standard, outline, segmented, inline }

/// Application artwork presets use matching hit areas.
///
/// [chatReaction] matches the chat mockup's 24px pill and 999px radius.
/// [chrome] provides 18px icons in a 32px window control.
/// [splitView] provides neutral 20px artwork in a 36px circular control,
/// with a circular hover surface and a press animation.
enum DToggleDensity {
  standard,
  chatReaction,
  tile,
  compactInset,
  chrome,
  splitView,
}

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
    this.expandArtwork = false,
  });

  final BorderRadiusGeometry? borderRadius;
  final DToggleBorderEdges borderEdges;

  /// Fill the width assigned by a parent group instead of hugging the label.
  final bool expandArtwork;
}

/// A two-state button with native pressed-toggle semantics.
///
/// Supply [pressed] for controlled state, or omit it to own state initialized
/// by [initialPressed]. [onPressedChanged] observes or updates that state but
/// is not required for the control to remain focusable. [focusNode] is
/// borrowed and never disposed. Desktop artwork follows base-nova's compact
/// bounds on every platform, without invisible target padding.
class DToggle extends StatefulWidget {
  const DToggle({
    super.key,
    required this.child,
    this.icon,
    this.selectedIcon,
    this.interactiveIcon,
    this.iconPosition = DToggleIconPosition.start,
    this.pressed,

    this.onPressedChanged,
    this.onLongPress,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.density = DToggleDensity.standard,
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
    this.interactiveIcon,
    required this.semanticLabel,
    this.pressed,

    this.onPressedChanged,
    this.onLongPress,
    this.enabled = true,
    this.readOnly = false,
    this.invalid = false,
    this.variant = DToggleVariant.standard,
    this.size = DToggleSize.regular,
    this.density = DToggleDensity.standard,
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

  /// Replacement artwork while enabled and hovered, pressed or keyboard focused.
  /// The toggle retains its normal size, semantics and activation behavior.
  final Widget? interactiveIcon;
  final DToggleIconPosition iconPosition;

  /// Non-null values are parent-owned. Null uses [initialPressed].
  final bool? pressed;

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

  /// Reaction densities supersede [size]. Chat reactions use 24px artwork,
  /// 12px emoji/counts and pill corners; ordinary reactions use 28px artwork,
  /// 18px icons and 12px counts. Text scaling grows
  /// the artwork to fit its content.
  final DToggleDensity density;
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

  static EdgeInsetsGeometry _paddingFor(
    DToggleSize size, {
    required bool hasIcon,
    required DToggleIconPosition iconPosition,
  }) {
    if (DControlStyle.isApplicationSize(size)) {
      return EdgeInsets.symmetric(
        horizontal: DControlStyle.horizontalInset(size),
      );
    }
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
  late bool _pressed = false;
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
    final segmented = widget.variant == DToggleVariant.segmented;
    final inline = widget.variant == DToggleVariant.inline;
    final outline = tokens.buttonTheme.outline;

    final chatReaction = widget.density == DToggleDensity.chatReaction;
    final tile = widget.density == DToggleDensity.tile;
    final compactInset = widget.density == DToggleDensity.compactInset;
    final chrome = widget.density == DToggleDensity.chrome;
    final splitView = widget.density == DToggleDensity.splitView;
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final interacting = _enabled && (_hovered || _pointerPressed);
    final foreground = splitView
        ? Color.lerp(tokens.colors.surface, tokens.foreground, .62)!
        : inline
        ? _current
              ? interacting
                    ? Color.lerp(tokens.primary, tokens.foreground, .25)!
                    : tokens.primary
              : interacting || _focusVisible
              ? tokens.foreground
              : tokens.buttonTheme.accent.foreground
        : segmented
        ? (_current
              ? tokens.foreground
              : Color.lerp(tokens.background, tokens.foreground, .5)!)
        : chatReaction
        ? Color.lerp(tokens.background, tokens.foreground, .62)!
        : outlined
        ? outline.foreground
        : tile && !_current
        ? tokens.mutedForeground
        : tokens.foreground;
    final scaler = MediaQuery.textScalerOf(context);
    final visualDimension = splitView
        ? 36.0 + math.max(0, scaler.scale(13) - 13)
        : chrome
        ? 32.0 + math.max(0, scaler.scale(13) - 13)
        : compactInset
        ? 26.0
        : tile
        ? 54.0
        : chatReaction
        ? (scaler.scale(12) * 1.5 + 6).clamp(24.0, double.infinity)
        : (DControlStyle.scaledHeight(widget.size, scaler, context: context));
    final visualWidth = compactInset ? 30.0 : visualDimension;
    final iconDimension = splitView
        ? 20.0
        : chrome
        ? 18.0
        : tile
        ? 20.0
        : chatReaction
        ? 12.0
        : (compactInset
              ? 12.0
              : DControlStyle.iconDimension(widget.size, context: context));
    final fontSize = tile
        ? 11.5
        : chatReaction
        ? 12.0
        : (DControlStyle.fontSize(widget.size, context: context));
    final lineHeight = tile
        ? 17.0
        : chatReaction
        ? 18.0
        : (DControlStyle.lineHeight(widget.size, context: context));
    final activeSurface = _current || interacting;
    final borderColor = widget.invalid
        ? tokens.destructive.withValues(
            alpha: tokens.destructive.a * (dark ? .5 : 1),
          )
        : splitView
        ? interacting
              ? Colors.white.withValues(alpha: dark ? .14 : .75)
              : Colors.transparent
        : chatReaction && outlined
        ? Color.lerp(
            tokens.background,
            tokens.foreground,
            activeSurface ? .32 : .22,
          )!
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
                  splitView || chatReaction
                      ? 999
                      : outlined
                      ? tokens.buttonTheme.radius
                      : DControlStyle.radius(tokens, widget.size),
                ))
            .resolve(direction);
    final edges = widget.visualStyle?.borderEdges ?? DToggleBorderEdges.all;
    final borderSide = BorderSide(
      color: borderColor,
      width: splitView || outlined ? 1 : DControlDecoration.borderWidth,
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

    final effectiveIcon =
        _enabled &&
            (interacting || (splitView ? _focusVisible : _focus.hasFocus)) &&
            widget.interactiveIcon != null
        ? widget.interactiveIcon
        : _current
        ? widget.selectedIcon ?? widget.icon
        : widget.icon;
    Widget content = widget._iconOnly
        ? ExcludeSemantics(child: effectiveIcon!)
        : DefaultTextStyle.merge(
            style: theme.textTheme.labelLarge?.copyWith(
              color: foreground,
              fontSize: fontSize,
              height: lineHeight / fontSize,
              fontWeight: segmented
                  ? (_current ? FontWeight.w600 : FontWeight.w400)
                  : tile
                  ? (_current ? FontWeight.w600 : FontWeight.w400)
                  : FontWeight.w500,
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
                : tile
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 3,
                    children: [
                      ExcludeSemantics(child: effectiveIcon),
                      ExcludeSemantics(
                        excluding: widget.semanticLabel != null,
                        child: widget.child,
                      ),
                    ],
                  )
                : _IconLabel(
                    gap: segmented
                        ? 7
                        : chatReaction
                        ? 6
                        : widget.size == DToggleSize.post
                        ? 6
                        : 4,
                    iconAtEnd: widget.iconPosition == DToggleIconPosition.end,
                    direction: direction,
                    icon: ExcludeSemantics(child: effectiveIcon),
                    label: ExcludeSemantics(
                      excluding: widget.semanticLabel != null,
                      child: widget.child,
                    ),
                  ),
          );
    content = IconTheme.merge(
      data: IconThemeData(size: iconDimension, color: foreground),
      child: content,
    );

    if (splitView || chrome || DControlStyle.isApplicationSize(widget.size)) {
      content = DIconGlyphTheme(scale: 1, naturalWidth: true, child: content);
    }

    final surfaceColor = splitView
        ? interacting
              ? Color.lerp(
                  tokens.colors.surface,
                  tokens.foreground,
                  .10,
                )!.withValues(alpha: .28)
              : Colors.transparent
        : inline
        ? Colors.transparent
        : segmented
        ? activeSurface
              ? Color.lerp(
                  Color.lerp(tokens.background, Colors.black, .14)!,
                  tokens.foreground,
                  _current ? .13 : .08,
                )!
              : Colors.transparent
        : chatReaction && outlined
        ? Color.lerp(
            tokens.background,
            tokens.foreground,
            activeSurface ? .15 : .10,
          )!
        : outlined
        ? (activeSurface ? outline.hover : outline.background)
        : activeSurface
        ? tile
              ? tokens.foreground.withValues(alpha: .13)
              : DControlStyle.rowHover(tokens)
        : Colors.transparent;
    final artwork = AnimatedContainer(
      duration: splitView && !reducedMotion
          ? const Duration(milliseconds: 150)
          : Duration.zero,
      curve: splitView ? Curves.ease : const Cubic(.4, 0, .2, 1),
      constraints: BoxConstraints(
        minWidth: visualWidth,
        minHeight: visualDimension,
      ),
      padding: (widget._iconOnly
          ? EdgeInsets.zero
          : tile
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 7)
          : chatReaction
          ? const EdgeInsets.symmetric(horizontal: 9, vertical: 2)
          : (DToggle._paddingFor(
              widget.size,
              hasIcon: effectiveIcon != null,
              iconPosition: widget.iconPosition,
            ))),
      decoration: BoxDecoration(
        color: splitView ? null : DMaterialSurface.fill(context, surfaceColor),
        gradient: splitView
            ? RadialGradient(
                center: Alignment.topCenter,
                radius: 1.2,
                transform: const _SplitViewSheenTransform(),
                // Composite the CSS highlight over its tint in the shader.
                // Setting BoxDecoration.color as well would multiply the
                // shader's opacity instead of painting a second layer.
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(
                      alpha: interacting ? (dark ? .12 : .55) : 0,
                    ),
                    surfaceColor,
                  ),
                  surfaceColor,
                ],
                stops: const [0, .62],
              )
            : null,
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
      child: Center(
        widthFactor: tile || widget.visualStyle?.expandArtwork == true
            ? null
            : 1,
        heightFactor: 1,
        child: content,
      ),
    );
    // Bare glass has only an inset rim and sheen. It does not acquire the
    // raised material's lens or outer shadow when the pointer enters.
    final surface = splitView
        ? TweenAnimationBuilder<double>(
            tween: Tween(end: interacting ? 1.0 : 0.0),
            duration: reducedMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.ease,
            child: artwork,
            builder: (context, opacity, child) => CustomPaint(
              foregroundPainter: _SplitViewCatch(
                radius,
                Colors.white.withValues(
                  alpha: (dark ? .12 : .55) * 1.4 * opacity,
                ),
              ),
              child: child,
            ),
          )
        : DMaterialSurface(radius: radius, color: surfaceColor, child: artwork);

    final control = MergeSemantics(
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
            onFocusChange: (focused) {
              if (widget.interactiveIcon != null) setState(() {});
              widget.onFocusChanged?.call(focused);
            },
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
              child: Opacity(opacity: _enabled ? 1 : .6, child: surface),
            ),
          ),
        ),
      ),
    );
    return Align(
      widthFactor: 1,
      heightFactor: 1,
      child: splitView
          ? AnimatedScale(
              scale: _pointerPressed ? .92 : 1,
              duration: reducedMotion
                  ? Duration.zero
                  : Duration(milliseconds: _pointerPressed ? 80 : 400),
              curve: const Cubic(.34, 1.56, .64, 1),
              child: control,
            )
          : control,
    );
  }
}

class _SplitViewSheenTransform extends GradientTransform {
  const _SplitViewSheenTransform();

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.identity()
        ..translateByDouble(0, bounds.top, 0, 1)
        ..scaleByDouble(1, 11 / 12, 1, 1)
        ..translateByDouble(0, -bounds.top, 0, 1);
}

class _SplitViewCatch extends CustomPainter {
  const _SplitViewCatch(this.radius, this.color);

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final shape = radius.toRRect(Offset.zero & size);
    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRRect(
      shape.shift(const Offset(0, 1)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SplitViewCatch oldDelegate) =>
      radius != oldDelegate.radius || color != oldDelegate.color;
}

/// Lays the icon out at its natural width first and gives the label only what
/// remains, so a label ellipsizes against its icon rather than against an even
/// split of the row. A width narrower than the icon clamps the icon and its
/// gap as well, which keeps collapsing layouts free of overflow.
class _IconLabel extends MultiChildRenderObjectWidget {
  _IconLabel({
    required this.iconAtEnd,
    required this.direction,
    required this.gap,
    required Widget icon,
    required Widget label,
  }) : super(children: [icon, label]);

  final bool iconAtEnd;
  final TextDirection direction;
  final double gap;

  @override
  _RenderIconLabel createRenderObject(BuildContext context) =>
      _RenderIconLabel(iconAtEnd, direction, gap);

  @override
  void updateRenderObject(BuildContext context, _RenderIconLabel renderObject) {
    renderObject
      ..iconAtEnd = iconAtEnd
      ..direction = direction
      ..gap = gap;
  }
}

class _IconLabelParentData extends ContainerBoxParentData<RenderBox> {}

typedef _IconLabelMetrics = ({
  Size size,
  BoxConstraints iconConstraints,
  Size icon,
  BoxConstraints labelConstraints,
  Size label,
  double gap,
});

class _RenderIconLabel extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _IconLabelParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _IconLabelParentData> {
  _RenderIconLabel(this._iconAtEnd, this._direction, this._gap);

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  bool _iconAtEnd;
  set iconAtEnd(bool value) {
    if (value == _iconAtEnd) return;
    _iconAtEnd = value;
    markNeedsLayout();
  }

  TextDirection _direction;
  set direction(TextDirection value) {
    if (value == _direction) return;
    _direction = value;
    markNeedsLayout();
  }

  RenderBox get _icon => firstChild!;
  RenderBox get _label => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _IconLabelParentData) {
      child.parentData = _IconLabelParentData();
    }
  }

  _IconLabelMetrics _measure(
    BoxConstraints constraints,
    ChildLayouter layoutChild,
  ) {
    final available = constraints.maxWidth;
    final iconConstraints = BoxConstraints(
      maxWidth: available,
      maxHeight: constraints.maxHeight,
    );
    final icon = layoutChild(_icon, iconConstraints);
    final gap = math.min(_gap, math.max(0.0, available - icon.width));
    final labelConstraints = BoxConstraints(
      maxWidth: math.max(0.0, available - icon.width - gap),
      maxHeight: constraints.maxHeight,
    );
    final label = layoutChild(_label, labelConstraints);
    return (
      size: constraints.constrain(
        Size(
          icon.width + gap + label.width,
          math.max(icon.height, label.height),
        ),
      ),
      iconConstraints: iconConstraints,
      icon: icon,
      labelConstraints: labelConstraints,
      label: label,
      gap: gap,
    );
  }

  /// Children sit at the start of the reading direction and are centred
  /// across it, as they were in the row this replaces.
  (Offset icon, Offset label) _offsets(_IconLabelMetrics metrics) {
    final iconStart = _iconAtEnd ? metrics.label.width + metrics.gap : 0.0;
    final labelStart = _iconAtEnd ? 0.0 : metrics.icon.width + metrics.gap;
    Offset place(double start, Size child) => Offset(
      _direction == TextDirection.ltr
          ? start
          : metrics.size.width - start - child.width,
      (metrics.size.height - child.height) / 2,
    );
    return (place(iconStart, metrics.icon), place(labelStart, metrics.label));
  }

  @override
  void performLayout() {
    final metrics = _measure(constraints, ChildLayoutHelper.layoutChild);
    size = metrics.size;
    final (icon, label) = _offsets(metrics);
    (_icon.parentData! as _IconLabelParentData).offset = icon;
    (_label.parentData! as _IconLabelParentData).offset = label;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, ChildLayoutHelper.dryLayoutChild).size;

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) {
    final metrics = _measure(constraints, ChildLayoutHelper.dryLayoutChild);
    final (iconOffset, labelOffset) = _offsets(metrics);
    final icon = _icon.getDryBaseline(metrics.iconConstraints, baseline);
    final label = _label.getDryBaseline(metrics.labelConstraints, baseline);
    return switch ((icon, label)) {
      (null, null) => null,
      (final icon?, null) => icon + iconOffset.dy,
      (null, final label?) => label + labelOffset.dy,
      (final icon?, final label?) => math.min(
        icon + iconOffset.dy,
        label + labelOffset.dy,
      ),
    };
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _icon.getMinIntrinsicWidth(height) +
      _gap +
      _label.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _icon.getMaxIntrinsicWidth(height) +
      _gap +
      _label.getMaxIntrinsicWidth(height);

  double _intrinsicHeight(double width, {required bool maximum}) {
    final icon = math.min(width, _icon.getMaxIntrinsicWidth(double.infinity));
    final label = math.max(0.0, width - icon - _gap);
    return math.max(
      maximum
          ? _icon.getMaxIntrinsicHeight(icon)
          : _icon.getMinIntrinsicHeight(icon),
      maximum
          ? _label.getMaxIntrinsicHeight(label)
          : _label.getMinIntrinsicHeight(label),
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _intrinsicHeight(width, maximum: false);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _intrinsicHeight(width, maximum: true);

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
