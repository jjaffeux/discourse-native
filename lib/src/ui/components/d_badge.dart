import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../theme/d_icon.dart';
import '../../theme/discourse_typography.dart';
import '../foundation/control_artwork.dart';
import '../foundation/control_style.dart';
import '../foundation/tokens.dart';
import 'd_link_interaction.dart';

/// The six base-nova badge treatments. A treatment does not imply interaction.
enum DBadgeVariant { primary, secondary, destructive, outline, ghost, link }

/// Badge presets for labels, compact counts, and regular control rows.
enum DBadgeSize {
  regular,
  compact,

  /// Inline topic counts: 11px bold labels with 1px/6px insets.
  unread,

  /// Matches the mockup taxonomy chips: 30px with 12.5px labels.
  control,

  /// Profile awards: 26px pills with 12px labels and 10.5px artwork.
  featured,
}

/// Optical metrics for artwork beside a paragraph-relative inline label.
enum DBadgeInlineArtwork { icon, image, square }

typedef _InlineBadge = ({
  TextStyle? baseStyle,
  Widget Function(BuildContext context, double dimension)? leadingBuilder,
  DBadgeInlineArtwork leadingArtwork,
  bool hoverable,
  bool hovered,
  bool highlighted,
});

enum _BadgeInteraction { none, action, link }

/// Tailwind's default transition timing, `cubic-bezier(.4, 0, .2, 1)`.
const _transitionCurve = Cubic(.4, 0, .2, 1);

/// A compact status, count, or label with optional decorative inline artwork.
///
/// [DBadge] is static; [DBadge.action] and [DBadge.link] own a single activation
/// target and tab stop. Their nullable callback disables interaction. The caller
/// owns navigation, loading and domain state. Compose a DSpinner in [leading]
/// or [trailing] for a changing status.
/// Children must not contain independent controls. Inline artwork is decorative
/// and fitted to 12px; label text inherits 12/18px medium metrics, can wrap,
/// and stays selectable inside an enclosing selection area like the reference
/// span. The regular visual height is 22px; [DBadgeSize.compact] uses 16px
/// height, 12/14px type and narrower insets. [DBadgeSize.control] opts into
/// regular control height, typography and artwork metrics for the platform.
/// All sizes grow with text. Actions and links use their visible pill bounds.
/// [DBadge.inline] follows its paragraph's text metrics and can project hover
/// and selection from an enclosing editor. Other static badges track hover only
/// for ghost and link treatments. Colors resolve every build, including custom
/// palettes.
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
  }) : _interaction = _BadgeInteraction.none,
       _overlay = false,
       _inline = null,
       ringColor = null,
       onPressed = null;

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
  }) : _interaction = _BadgeInteraction.none,
       _overlay = true,
       _inline = null,
       variant = DBadgeVariant.primary,
       size = DBadgeSize.compact,
       leading = null,
       trailing = null,
       borderColor = null,

       onPressed = null;

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
  }) : _interaction = _BadgeInteraction.action,
       _overlay = false,
       _inline = null,
       ringColor = null;

  /// A native link. [onPressed] opens the caller-owned route or URL.
  const DBadge.link({
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
  }) : _interaction = _BadgeInteraction.link,
       _overlay = false,
       _inline = null,
       ringColor = null;

  /// A paragraph-relative label that stays on one line and reports its text
  /// baseline. The kit owns optical artwork sizing and insets. Builders receive
  /// the artwork dimension, so callers supply artwork without control geometry.
  /// [hovered] and [highlighted] project state from an enclosing editor. Without
  /// [onPressed], the badge remains static and creates no competing tap target.
  const DBadge.inline({
    super.key,
    required this.child,
    TextStyle? baseStyle,
    Widget Function(BuildContext context, double dimension)? leadingBuilder,
    DBadgeInlineArtwork leadingArtwork = DBadgeInlineArtwork.icon,
    this.backgroundColor,
    this.foregroundColor,
    this.semanticLabel,
    this.onPressed,
    bool hoverable = false,
    bool hovered = false,
    bool highlighted = false,
  }) : _interaction = onPressed == null
           ? _BadgeInteraction.none
           : _BadgeInteraction.action,
       _overlay = false,
       _inline = (
         baseStyle: baseStyle,
         leadingBuilder: leadingBuilder,
         leadingArtwork: leadingArtwork,
         hoverable: hoverable,
         hovered: hovered,
         highlighted: highlighted,
       ),
       variant = DBadgeVariant.secondary,
       size = DBadgeSize.regular,
       leading = null,
       trailing = null,
       borderColor = null,
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

  final VoidCallback? onPressed;

  final _BadgeInteraction _interaction;
  final bool _overlay;
  final _InlineBadge? _inline;

  @override
  State<DBadge> createState() => _DBadgeState();
}

class _DBadgeState extends State<DBadge> {
  final FocusNode _ownedFocusNode = FocusNode(debugLabel: 'DBadge');
  FocusNode get _focusNode => (_ownedFocusNode);

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
      (widget._inline?.hoverable ?? false) ||
      widget.variant == DBadgeVariant.ghost ||
      widget.variant == DBadgeVariant.link;

  @override
  void didUpdateWidget(DBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_enabled) _pressed = false;
    if (!_interactive) _focused = false;
    // A removed MouseRegion reports no exit, so a hover it observed must not
    // resurface when a later rebuild returns to a hover-painting treatment.
    if (!_tracksHover) _hovered = false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final linkActivation = DLinkInteractionBinding.capture(
      context,
      widget.onPressed,
    );
    void activate() {
      if (_enabled) linkActivation.onPressed?.call();
    }

    final inline = widget._inline;
    Widget complete(Widget child) {
      final control = linkActivation.wrap(child);
      return inline == null
          ? control
          : Align(
              alignment: AlignmentDirectional.centerStart,
              widthFactor: 1,
              heightFactor: 1,
              child: control,
            );
    }

    final compact = widget.size == DBadgeSize.compact;
    final featured = widget.size == DBadgeSize.featured;

    final unread = widget.size == DBadgeSize.unread;
    final overlay = widget._overlay;
    final control = widget.size == DBadgeSize.control;
    final fontSize = inline != null
        ? (inline.baseStyle?.fontSize ?? DiscourseTypography.base) * .93
        : control
        ? DControlStyle.fontSize(DControlSize.filter, context: context)
        : overlay
        ? 10.0
        : (unread)
        ? DiscourseTypography.micro
        : DiscourseTypography.xs;
    final lineHeight = inline != null
        ? 1.0
        : control
        ? DControlStyle.lineHeight(DControlSize.filter, context: context) /
              fontSize
        : overlay
        ? 1.2
        : compact
        ? 14 / DiscourseTypography.xs
        : DiscourseTypography.lineHeightCaption;
    final artworkSize = inline != null
        ? fontSize *
              switch (inline.leadingArtwork) {
                DBadgeInlineArtwork.icon => .93 / DIcon.glyphScale,
                DBadgeInlineArtwork.image => .93,
                DBadgeInlineArtwork.square => .72,
              }
        : featured
        ? 10.5
        : control
        ? DControlStyle.iconDimension(DControlSize.filter, context: context)
        : 12.0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active =
        _enabled &&
        (_hovered ||
            _pressed ||
            (inline?.hovered ?? false) ||
            (inline != null && _focused));
    final actionHover = active && _interactive;
    final (baseBackground, baseForeground) = switch (widget.variant) {
      DBadgeVariant.primary => (
        tokens.primary.withValues(alpha: actionHover ? .8 : 1),
        tokens.primaryForeground,
      ),
      DBadgeVariant.secondary => (
        control
            ? (actionHover
                  ? tokens.buttonTheme.outline.hover
                  : tokens.buttonTheme.outline.background)
            : tokens.muted.withValues(alpha: actionHover ? .8 : 1),
        control ? tokens.buttonTheme.outline.foreground : tokens.foreground,
      ),
      DBadgeVariant.destructive => (
        tokens.destructive.withValues(alpha: dark || actionHover ? .2 : .1),
        tokens.destructive,
      ),
      DBadgeVariant.outline => (
        actionHover
            ? (control ? tokens.buttonTheme.outline.background : tokens.muted)
            : Colors.transparent,
        control
            ? Color.lerp(tokens.background, tokens.foreground, .40)!
            : actionHover
            ? tokens.mutedForeground
            : tokens.foreground,
      ),
      DBadgeVariant.ghost => (
        active
            ? tokens.muted.withValues(alpha: dark ? .5 : 1)
            : Colors.transparent,
        active ? tokens.mutedForeground : tokens.foreground,
      ),
      DBadgeVariant.link => (Colors.transparent, tokens.primary),
    };
    final foreground =
        widget.foregroundColor ??
        (inline == null
            ? baseForeground
            : inline.baseStyle?.color ??
                  DefaultTextStyle.of(context).style.color ??
                  tokens.foreground);
    final fill =
        widget.backgroundColor ??
        (inline == null ? baseBackground : tokens.muted);
    final background = inline != null && active
        ? Color.alphaBlend(tokens.foreground.withValues(alpha: .08), fill)
        : fill;
    final focus = _focused && _enabled;
    final destructiveRing = (widget.variant == DBadgeVariant.destructive);
    final ringColor = destructiveRing ? tokens.destructive : tokens.focusRing;
    final radius = BorderRadius.circular(unread ? 10 : DRadius.pill);
    final border = (focus
        ? tokens.focusRing
        : widget.borderColor ??
              (control &&
                      (widget.variant == DBadgeVariant.secondary ||
                          widget.variant == DBadgeVariant.outline)
                  ? tokens.buttonTheme.outline.border
                  : widget.variant == DBadgeVariant.outline
                  ? tokens.border
                  : Colors.transparent));
    Widget visual = _BadgeHoverTransition(
      hovered: _hovered || (inline?.hovered ?? false),
      builder: (hoverChanged) => AnimatedContainer(
        duration: hoverChanged
            ? Duration.zero
            : DMotion.duration(context, const Duration(milliseconds: 150)),
        curve: _transitionCurve,
        clipBehavior: Clip.antiAlias,
        constraints: BoxConstraints(
          minWidth: overlay ? 14 : (unread ? 18 : 0),
          minHeight: inline != null
              ? 0
              : featured
              ? 26 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 1.5
              : control
              ? DControlStyle.scaledHeight(
                  DControlSize.filter,
                  MediaQuery.textScalerOf(context),
                  context: context,
                )
              : overlay
              ? 14
              : ((unread) ? 0 : (compact ? 16 : 20)),
        ),
        decoration: BoxDecoration(
          color: background,
          border: overlay || unread || inline != null
              ? null
              : Border.all(color: border),
          borderRadius: radius,
        ),
        foregroundDecoration: inline != null
            ? inline.highlighted || focus
                  ? BoxDecoration(
                      border: Border.all(color: tokens.primary, width: 1.5),
                      borderRadius: radius,
                    )
                  : null
            : _BadgeRing(
                radius: radius,
                width: overlay ? 1.5 : (focus ? 3 : 0),
                color: overlay
                    ? widget.ringColor ?? tokens.background
                    : ringColor.withValues(
                        alpha: destructiveRing ? (dark ? .4 : .2) : .5,
                      ),
              ),
        // Compact counts keep 12px type with 14px leading inside a 1px border.
        padding: inline != null
            ? EdgeInsets.symmetric(
                horizontal: fontSize * .34,
                vertical: fontSize * .2,
              )
            : overlay
            ? const EdgeInsets.symmetric(horizontal: 3, vertical: 1)
            : (unread
                  ? const EdgeInsets.symmetric(horizontal: 6, vertical: 1)
                  : EdgeInsetsDirectional.fromSTEB(
                      featured
                          ? 10
                          : control
                          ? 11
                          : compact
                          ? 4
                          : (widget.leading == null ? 8 : 6),
                      compact ? 0 : 1,
                      featured
                          ? 10
                          : control
                          ? 11
                          : compact
                          ? 4
                          : (widget.trailing == null ? 8 : 6),
                      compact ? 0 : 1,
                    )),
        child: IconTheme.merge(
          data: IconThemeData(
            size: artworkSize,
            color: inline == null ? foreground : null,
          ),
          child: DefaultTextStyle(
            maxLines: inline == null ? null : 1,
            softWrap: inline == null,
            overflow: inline == null
                ? TextOverflow.clip
                : TextOverflow.ellipsis,
            style:
                (inline == null
                        ? Theme.of(context).textTheme.bodySmall ??
                              const TextStyle()
                        : DefaultTextStyle.of(
                            context,
                          ).style.merge(inline.baseStyle))
                    .copyWith(
                      fontSize: fontSize,
                      height: lineHeight,
                      fontWeight: inline != null
                          ? FontWeight.w400
                          : overlay
                          ? FontWeight.w600
                          : unread
                          ? FontWeight.w700
                          : (control ? FontWeight.w400 : FontWeight.w500),
                      fontFeatures: overlay
                          ? const [FontFeature.tabularFigures()]
                          : null,
                      letterSpacing: inline == null
                          ? 0
                          : inline.baseStyle?.letterSpacing,
                      color: foreground,
                      decoration:
                          inline == null &&
                              widget.variant == DBadgeVariant.link &&
                              active
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
                if (inline?.leadingBuilder case final builder?) ...[
                  _inlineArtwork(
                    builder(context, artworkSize),
                    artworkSize,
                    inset: inline!.leadingArtwork == DBadgeInlineArtwork.square
                        ? fontSize * .1
                        : 0,
                  ),
                  SizedBox(width: fontSize * .287),
                ],
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
    visual = DControlArtwork(
      child: Opacity(opacity: _enabled ? 1 : .5, child: visual),
    );
    final semantics = Semantics(
      container: _interactive,
      button: widget._interaction == _BadgeInteraction.action,
      link: widget._interaction == _BadgeInteraction.link,
      linkUrl: null,
      enabled: _interactive ? _enabled : null,
      focusable: _interactive ? _enabled : null,
      focused: _interactive ? _focusNode.hasFocus : null,
      onFocus:
          _interactive &&
              _enabled &&
              defaultTargetPlatform != TargetPlatform.iOS
          ? _focusNode.requestFocus
          : null,
      label: widget.semanticLabel,
      value: null,
      liveRegion: false,
      validationResult: SemanticsValidationResult.none,
      excludeSemantics: widget.semanticLabel != null,
      onTap: _interactive && _enabled ? activate : null,
      child: overlay ? IgnorePointer(child: visual) : visual,
    );
    if (!_interactive) {
      if (!_tracksHover) return complete(semantics);
      return complete(
        MouseRegion(
          cursor: inline != null ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: semantics,
        ),
      );
    }
    return complete(
      MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: FocusableActionDetector(
          focusNode: _focusNode,
          autofocus: false,
          enabled: _enabled,
          includeFocusSemantics: false,
          mouseCursor: _enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onFocusChange: (value) => setState(() {
            if (inline != null) _focused = value;
          }),
          onShowFocusHighlight: inline != null
              ? null
              : (value) => setState(() => _focused = value),
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
                activate();
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
                    activate();
                  }
                : null,
            onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel: () => setState(() => _pressed = false),
            child: semantics,
          ),
        ),
      ),
    );
  }

  Widget _inlineArtwork(
    Widget child,
    double dimension, {
    required double inset,
  }) => Padding(
    padding: EdgeInsetsDirectional.only(start: inset),
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: ExcludeFocus(
          child: SizedBox.square(dimension: dimension, child: child),
        ),
      ),
    ),
  );

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
