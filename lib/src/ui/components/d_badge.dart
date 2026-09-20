import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/control_style.dart';
import '../foundation/tokens.dart';

/// The six base-nova badge treatments. A treatment does not imply interaction.
enum DBadgeVariant { primary, secondary, destructive, outline, ghost, link }

/// Badge presets for labels, compact counts, and regular control rows.
enum DBadgeSize {
  regular,
  compact,

  /// Matches regular controls: 28px/13px on desktop, 44px/15px on mobile.
  control,
}

enum _BadgeInteraction { none, action, link }

/// Tailwind's default transition timing, `cubic-bezier(.4, 0, .2, 1)`.
const _transitionCurve = Cubic(.4, 0, .2, 1);

/// A compact status, count, or label with optional decorative inline artwork.
///
/// [DBadge] is static; [DBadge.action] and [DBadge.link] own a single activation
/// target and tab stop. Their nullable callback disables interaction. The caller
/// owns navigation, loading and domain state; compose a DSpinner in [leading] or
/// [trailing] and use [semanticValue] / [liveRegion] for a changing status.
/// Children must not contain independent controls. Inline artwork is decorative
/// and fitted to 12px; label text inherits 12/16px medium metrics, can wrap,
/// and stays selectable inside an enclosing selection area like the reference
/// span. The regular visual height is 20px; [DBadgeSize.compact] uses 16px
/// height, 12/14px type and narrower insets. [DBadgeSize.control] opts into
/// regular control height, typography and artwork metrics for the platform.
/// All sizes grow with text. Touch actions
/// reserve a transparent 48px target around the compact visual. Only ghost and
/// link paint a hover treatment on a static badge, so other static variants do
/// not track the pointer. Borrowed focus nodes are never disposed. Colors are
/// resolved every build, including custom palettes.
class DBadge extends StatefulWidget {
  const DBadge({
    super.key,
    required this.child,
    this.variant = DBadgeVariant.primary,
    this.size = DBadgeSize.regular,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.semanticLabel,
    this.semanticValue,
    this.liveRegion = false,
    this.invalid = false,
  }) : _interaction = _BadgeInteraction.none,
       _overlay = false,
       ringColor = null,
       onPressed = null,
       focusNode = null,
       autofocus = false,
       url = null;

  /// A non-interactive count pill for overlaying small icons. Uses 10/12px
  /// tabular type, a 14px minimum diameter, 3px horizontal insets and an outer
  /// 1.5px surface-colored ring. It grows with the text scale and label width.
  /// Finite parent widths fit the pill down to keep its full count visible.
  /// The caller owns positioning, visibility, count formatting and semantics.
  const DBadge.overlay({
    super.key,
    required this.child,
    this.backgroundColor,
    this.foregroundColor,
    this.ringColor,
    this.semanticLabel,
    this.semanticValue,
    this.liveRegion = false,
  }) : _interaction = _BadgeInteraction.none,
       _overlay = true,
       variant = DBadgeVariant.primary,
       size = DBadgeSize.compact,
       leading = null,
       trailing = null,
       borderColor = null,
       invalid = false,
       onPressed = null,
       focusNode = null,
       autofocus = false,
       url = null;

  const DBadge.action({
    super.key,
    required this.child,
    required this.onPressed,
    this.variant = DBadgeVariant.primary,
    this.size = DBadgeSize.regular,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.semanticLabel,
    this.semanticValue,
    this.liveRegion = false,
    this.invalid = false,
    this.focusNode,
    this.autofocus = false,
  }) : _interaction = _BadgeInteraction.action,
       _overlay = false,
       ringColor = null,
       url = null;

  /// A native link. [onPressed] opens the caller-owned route or URL. [url]
  /// exposes an optional destination to accessibility; it does not launch it.
  const DBadge.link({
    super.key,
    required this.child,
    required this.onPressed,
    this.url,
    this.variant = DBadgeVariant.primary,
    this.size = DBadgeSize.regular,
    this.leading,
    this.trailing,
    this.backgroundColor,
    this.foregroundColor,
    this.borderColor,
    this.semanticLabel,
    this.semanticValue,
    this.liveRegion = false,
    this.invalid = false,
    this.focusNode,
    this.autofocus = false,
  }) : _interaction = _BadgeInteraction.link,
       _overlay = false,
       ringColor = null;

  final Widget child;
  final DBadgeVariant variant;
  final DBadgeSize size;
  final Widget? leading;
  final Widget? trailing;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? borderColor;

  /// Surrounding surface for [DBadge.overlay]; defaults to the theme background.
  final Color? ringColor;
  final String? semanticLabel;
  final String? semanticValue;
  final bool liveRegion;
  final bool invalid;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final Uri? url;
  final _BadgeInteraction _interaction;
  final bool _overlay;

  @override
  State<DBadge> createState() => _DBadgeState();
}

class _DBadgeState extends State<DBadge> {
  final FocusNode _ownedFocusNode = FocusNode(debugLabel: 'DBadge');
  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode;

  @override
  void dispose() {
    _ownedFocusNode.dispose();
    super.dispose();
  }

  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget._interaction != _BadgeInteraction.none;
  bool get _enabled => !_interactive || widget.onPressed != null;
  bool get _tracksHover =>
      _interactive ||
      widget.variant == DBadgeVariant.ghost ||
      widget.variant == DBadgeVariant.link;

  @override
  void didUpdateWidget(DBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
    // A removed MouseRegion reports no exit, so a hover it observed must not
    // resurface when a later rebuild returns to a hover-painting treatment.
    if (!_tracksHover) _hovered = false;
  }

  void _activate() {
    if (_enabled) widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final compact = widget.size == DBadgeSize.compact;
    final overlay = widget._overlay;
    final control = widget.size == DBadgeSize.control;
    final fontSize = control
        ? DControlStyle.fontSize(DControlSize.regular, context: context)
        : overlay
        ? 10.0
        : DiscourseTypography.xs;
    final lineHeight = control
        ? DControlStyle.lineHeight(DControlSize.regular, context: context) /
              fontSize
        : overlay
        ? 1.2
        : compact
        ? 14 / DiscourseTypography.xs
        : DiscourseTypography.lineHeightCaption;
    final artworkSize = control
        ? DControlStyle.iconDimension(DControlSize.regular, context: context)
        : 12.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = _enabled && (_hovered || _pressed);
    final actionHover = active && _interactive;
    final (baseBackground, baseForeground) = switch (widget.variant) {
      DBadgeVariant.primary => (
        tokens.primary.withValues(alpha: actionHover ? .8 : 1),
        tokens.primaryForeground,
      ),
      DBadgeVariant.secondary => (
        tokens.muted.withValues(alpha: actionHover ? .8 : 1),
        tokens.foreground,
      ),
      DBadgeVariant.destructive => (
        tokens.destructive.withValues(alpha: dark || actionHover ? .2 : .1),
        tokens.destructive,
      ),
      DBadgeVariant.outline => (
        actionHover ? tokens.muted : Colors.transparent,
        actionHover ? tokens.mutedForeground : tokens.foreground,
      ),
      DBadgeVariant.ghost => (
        active
            ? tokens.muted.withValues(alpha: dark ? .5 : 1)
            : Colors.transparent,
        active ? tokens.mutedForeground : tokens.foreground,
      ),
      DBadgeVariant.link => (Colors.transparent, tokens.primary),
    };
    final foreground = widget.foregroundColor ?? baseForeground;
    final focus = _focused && _enabled;
    final destructiveRing =
        widget.invalid || widget.variant == DBadgeVariant.destructive;
    final ringColor = destructiveRing ? tokens.destructive : tokens.focusRing;
    final radius = BorderRadius.circular(overlay ? 999 : tokens.radius * 2.6);
    final border = widget.invalid
        ? tokens.destructive
        : focus
        ? tokens.focusRing
        : widget.borderColor ??
              (widget.variant == DBadgeVariant.outline
                  ? tokens.border
                  : Colors.transparent);
    Widget visual = _BadgeHoverTransition(
      hovered: _hovered,
      builder: (hoverChanged) => AnimatedContainer(
        duration: hoverChanged
            ? Duration.zero
            : DMotion.duration(context, const Duration(milliseconds: 150)),
        curve: _transitionCurve,
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          minWidth: overlay ? 14 : 0,
          minHeight: control
              ? DControlStyle.scaledHeight(
                  DControlSize.regular,
                  MediaQuery.textScalerOf(context),
                  context: context,
                )
              : overlay
              ? 14
              : (compact ? 16 : 20),
        ),
        decoration: BoxDecoration(
          color: widget.backgroundColor ?? baseBackground,
          border: overlay ? null : Border.all(color: border),
          borderRadius: radius,
        ),
        foregroundDecoration: _BadgeRing(
          radius: radius,
          width: overlay ? 1.5 : (focus ? 3 : 0),
          color: overlay
              ? widget.ringColor ?? tokens.background
              : ringColor.withValues(
                  alpha: destructiveRing ? (dark ? .4 : .2) : .5,
                ),
        ),
        // Compact counts keep 12px type with 14px leading inside a 1px border.
        padding: overlay
            ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
            : EdgeInsetsDirectional.fromSTEB(
                compact ? 4 : (widget.leading == null ? 8 : 6),
                compact ? 0 : 1,
                compact ? 4 : (widget.trailing == null ? 8 : 6),
                compact ? 0 : 1,
              ),
        child: IconTheme.merge(
          data: IconThemeData(size: artworkSize, color: foreground),
          child: DefaultTextStyle(
            style: (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
                .copyWith(
                  fontSize: fontSize,
                  height: lineHeight,
                  fontWeight: overlay ? FontWeight.w600 : FontWeight.w500,
                  fontFeatures: overlay
                      ? const [FontFeature.tabularFigures()]
                      : null,
                  letterSpacing: 0,
                  color: foreground,
                  decoration: widget.variant == DBadgeVariant.link && active
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: foreground,
                ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: overlay
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (widget.leading case final leading?) ...[
                  _artwork(leading, artworkSize),
                  const SizedBox(width: DSpacing.xs),
                ],
                Flexible(child: widget.child),
                if (widget.trailing case final trailing?) ...[
                  const SizedBox(width: DSpacing.xs),
                  _artwork(trailing, artworkSize),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    if (overlay) {
      visual = FittedBox(fit: BoxFit.scaleDown, child: visual);
    }
    visual = Opacity(opacity: _enabled ? 1 : .5, child: visual);
    if (_interactive &&
        switch (Theme.of(context).platform) {
          TargetPlatform.iOS ||
          TargetPlatform.android ||
          TargetPlatform.fuchsia => true,
          _ => false,
        }) {
      visual = ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: DSpacing.touchTarget,
          minHeight: DSpacing.touchTarget,
        ),
        child: Center(widthFactor: 1, heightFactor: 1, child: visual),
      );
    }
    final semantics = Semantics(
      container: _interactive,
      button: widget._interaction == _BadgeInteraction.action,
      link: widget._interaction == _BadgeInteraction.link,
      linkUrl: widget.url,
      enabled: _interactive ? _enabled : null,
      label: widget.semanticLabel,
      value: widget.semanticValue,
      liveRegion: widget.liveRegion,
      validationResult: widget.invalid
          ? SemanticsValidationResult.invalid
          : SemanticsValidationResult.none,
      excludeSemantics: widget.semanticLabel != null,
      onTap: _interactive && _enabled ? _activate : null,
      child: overlay ? IgnorePointer(child: visual) : visual,
    );
    if (!_interactive) {
      if (!_tracksHover) return semantics;
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: semantics,
      );
    }
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: FocusableActionDetector(
        focusNode: _focusNode,
        autofocus: widget.autofocus,
        enabled: _enabled,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: <ShortcutActivator, Intent>{
          const SingleActivator(LogicalKeyboardKey.enter):
              const ActivateIntent(),
          const SingleActivator(
            LogicalKeyboardKey.space,
          ): widget._interaction == _BadgeInteraction.action
              ? const ActivateIntent()
              : const DoNothingIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _enabled
              ? () {
                  _focusNode.requestFocus();
                  _activate();
                }
              : null,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: () => setState(() => _pressed = false),
          child: semantics,
        ),
      ),
    );
  }

  Widget _artwork(Widget child, double dimension) => ExcludeSemantics(
    child: IgnorePointer(
      child: ExcludeFocus(
        child: SizedBox.square(
          dimension: dimension,
          child: FittedBox(child: child),
        ),
      ),
    ),
  );
}

// Hover entry and exit paint immediately, while theme and focus changes keep
// the badge's usual transition. In particular, leaving a tag cannot trail fill
// across the containing topic row.
class _BadgeHoverTransition extends StatefulWidget {
  const _BadgeHoverTransition({required this.hovered, required this.builder});

  final bool hovered;
  final Widget Function(bool hoverChanged) builder;

  @override
  State<_BadgeHoverTransition> createState() => _BadgeHoverTransitionState();
}

class _BadgeHoverTransitionState extends State<_BadgeHoverTransition> {
  bool _hoverChanged = false;

  @override
  void didUpdateWidget(_BadgeHoverTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hoverChanged = widget.hovered != oldWidget.hovered;
  }

  @override
  Widget build(BuildContext context) => widget.builder(_hoverChanged);
}

/// CSS outer shadows exclude the border box, even with translucent backgrounds.
/// A foreground decoration keeps the child clip independent of the exterior ring.
class _BadgeRing extends Decoration {
  const _BadgeRing({
    required this.radius,
    required this.width,
    required this.color,
  });

  final BorderRadius radius;
  final double width;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _BadgeRing &&
      other.radius == radius &&
      other.width == width &&
      other.color == color;

  @override
  int get hashCode => Object.hash(radius, width, color);

  @override
  Decoration? lerpFrom(Decoration? a, double t) {
    if (a is _BadgeRing) {
      return _BadgeRing(
        radius: BorderRadius.lerp(a.radius, radius, t)!,
        width: a.width + (width - a.width) * t,
        color: Color.lerp(a.color, color, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  Decoration? lerpTo(Decoration? b, double t) =>
      b is _BadgeRing ? b.lerpFrom(this, t) : super.lerpTo(b, t);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _BadgeRingPainter(this);
}

class _BadgeRingPainter extends BoxPainter {
  _BadgeRingPainter(this.ring);
  final _BadgeRing ring;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    if (ring.width <= 0) return;
    final inner = ring.radius
        .toRRect(offset & configuration.size!)
        .scaleRadii();
    Radius expand(Radius radius) => radius == Radius.zero
        ? Radius.zero
        : radius + Radius.circular(ring.width);
    final outer = RRect.fromRectAndCorners(
      inner.outerRect.inflate(ring.width),
      topLeft: expand(inner.tlRadius),
      topRight: expand(inner.trRadius),
      bottomLeft: expand(inner.blRadius),
      bottomRight: expand(inner.brRadius),
    );
    canvas.drawDRRect(outer, inner, Paint()..color = ring.color);
  }
}
