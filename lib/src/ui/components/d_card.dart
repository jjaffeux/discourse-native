import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/material_surface.dart';
import '../foundation/tokens.dart';
import 'd_item.dart';

enum DCardSize { normal, small }

/// Capsule surfaces group compact actions while children retain their controls.
enum DCardVariant {
  standard,
  capsule,
  well,

  /// Latest-reply artwork that follows its containing Item's interaction.
  itemPreview,

  /// Title-bar writing actions: accent glass raised above the window ground.
  /// This artwork applies in both material modes. Reduced transparency keeps
  /// the raised accent surface with an opaque fill.
  /// Compose with chrome-density primary buttons and no outer border.
  primaryCapsule,
}

/// A passive surface. Actions, selection, loading and errors belong to children.
///
/// Parts inherit [spacing], the native equivalent of `--card-spacing`.
/// [leading] and [trailing] place images or other content against clipped edges.
/// A [footer] removes bottom padding. Children retain their native interaction
/// owners; the zero-elevation Material supports ink without creating an action.
class DCard extends ImplicitlyAnimatedWidget {
  const DCard({
    super.key,
    super.duration = Duration.zero,

    this.children = const [],
    this.child,
    this.size = DCardSize.normal,
    this.variant = DCardVariant.standard,
    this.spacing,
    this.backgroundColor,
    this.border = true,
    this.borderColor,
    this.dashedBorder = false,
    this.borderRadius,
    this.leading,
    this.trailing,
    this.footer,
  }) : assert(spacing == null || (spacing >= 0 && spacing < double.infinity)),
       super(curve: Curves.easeOutCubic);

  /// Full-surface composition, useful for an InkWell with caller-owned padding.
  final Widget? child;

  /// Resolved fill for passive artwork such as overlapping avatar rings.
  static Color surfaceColorOf(BuildContext context) =>
      _CardScope.of(context)?.surfaceColor ?? DTokens.of(context).background;
  final List<Widget> children;
  final DCardSize size;

  /// Small capsules use 4px insets, plus the side border when present.
  final DCardVariant variant;
  final double? spacing;

  /// Whether to paint the outer outline. Clipping and fill remain unchanged.
  final bool border;

  /// Optional outline tone; defaults to the Native border token.
  final Color? borderColor;

  /// Paints a dashed outline within the same visible card bounds.
  final bool dashedBorder;

  /// Overrides only the surface fill, retaining the outline, clipping and
  /// descendant theme. Supports translucent fills over a shared backdrop.
  final Color? backgroundColor;

  /// Overrides the outline and clip together, for surfaces adjoining a window.
  /// Null uses the panel radius (or the capsule variant's rounded ends).
  final BorderRadiusGeometry? borderRadius;
  final Widget? leading;
  final Widget? trailing;
  final DCardFooter? footer;

  @override
  AnimatedWidgetBaseState<DCard> createState() => _DCardState();
}

class _DCardState extends AnimatedWidgetBaseState<DCard> {
  ColorTween? _fill;
  ColorTween? _outline;
  @override
  void forEachTween(TweenVisitor<dynamic> visitor) {
    _fill =
        visitor(
              _fill,
              widget.backgroundColor,
              (value) => ColorTween(begin: value as Color),
            )
            as ColorTween?;
    _outline =
        visitor(
              _outline,
              widget.borderColor,
              (value) => ColorTween(begin: value as Color),
            )
            as ColorTween?;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == DCardVariant.itemPreview) {
      final theme = Theme.of(context);
      final interaction = DItemInteraction.of(context);
      final base = theme.colorScheme.surfaceContainerHighest;
      final fill = interaction.emphasized
          ? Color.alphaBlend(
              theme.colorScheme.onSurface.withValues(
                alpha: theme.brightness == Brightness.dark ? .055 : .035,
              ),
              base,
            )
          : base;
      final outline = interaction.focused
          ? theme.colorScheme.primary.withValues(alpha: .7)
          : interaction.emphasized
          ? theme.colorScheme.onSurface.withValues(alpha: .1)
          : Colors.transparent;
      return _CardScope(
        spacing: 12,
        size: DCardSize.small,
        surfaceColor: fill,
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: outline),
            borderRadius: BorderRadius.circular(11),
          ),
          padding: const EdgeInsets.all(12),
          child: widget.child,
        ),
      );
    }
    final child = widget.child;
    final children = widget.children;
    final size = widget.size;
    final variant = widget.variant;
    final spacing = widget.spacing;
    final backgroundColor = MediaQuery.disableAnimationsOf(context)
        ? widget.backgroundColor
        : _fill?.evaluate(animation);
    final borderColor = MediaQuery.disableAnimationsOf(context)
        ? widget.borderColor
        : _outline?.evaluate(animation);
    final border = widget.border;
    final dashedBorder = widget.dashedBorder;
    final borderRadius = widget.borderRadius;
    final leading = widget.leading;
    final trailing = widget.trailing;
    final footer = widget.footer;

    final tokens = DTokens.of(context);
    final primaryCapsule = variant == DCardVariant.primaryCapsule;
    final capsule = variant == DCardVariant.capsule || primaryCapsule;
    final compactCapsule = capsule && size == DCardSize.small;
    final surfaceColor =
        backgroundColor ??
        (primaryCapsule
            ? tokens.buttonTheme.primary.background
            : compactCapsule
            ? Colors.black.withValues(
                alpha: Theme.of(context).brightness == Brightness.dark
                    ? .16
                    : .045,
              )
            : capsule
            ? DMaterialSurface.active(context)
                  ? Color.lerp(tokens.background, Colors.black, .14)!
                  : Color.alphaBlend(
                      tokens.foreground.withValues(alpha: .04),
                      tokens.background,
                    )
            : variant == DCardVariant.well
            ? Color.alphaBlend(
                Colors.black.withValues(alpha: .08),
                tokens.background,
              )
            : tokens.background);
    final inset =
        spacing ??
        (capsule
            ? DSpacing.xs
            : size == DCardSize.small
            ? DSpacing.md
            : DSpacing.lg);
    final parts = <Widget>[?leading, ?child, ...children, ?footer, ?trailing];
    final radius =
        borderRadius?.resolve(Directionality.of(context)) ??
        BorderRadius.circular(capsule ? DRadius.pill : DRadius.panel);
    return _CardScope(
      spacing: inset,
      size: size,
      surfaceColor: surfaceColor,
      child: Semantics(
        container: true,
        child: DMaterialSurface(
          depth: primaryCapsule
              ? DSurfaceDepth.primaryCapsule
              : capsule || variant == DCardVariant.well
              ? DSurfaceDepth.recessed
              : child is Expanded
              ? DSurfaceDepth.panel
              : DSurfaceDepth.card,
          radius: radius,
          color: surfaceColor,
          preserveColor: compactCapsule,
          insetEdges: compactCapsule,
          child: DMaterialBatch(
            // Pages paint opaque content between overlapping lenses. Sharing
            // an earlier read lets scrolling content tint fixed controls
            // through that content. Keep compact cards on their shared read.
            enabled: child is! Expanded,
            child: CustomPaint(
              foregroundPainter: border && dashedBorder
                  ? _DashedCardOutline(radius, borderColor ?? tokens.border)
                  : null,
              child: DecoratedBox(
                // Panels clip to their bounds and edge-to-edge children can be opaque.
                // Paint the outline inside those bounds, above the child surface.
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: border && !dashedBorder
                      ? Border.all(color: borderColor ?? tokens.border)
                      : null,
                ),
                child: Material(
                  animationDuration: Duration.zero,
                  color: primaryCapsule
                      ? Colors.transparent
                      : DMaterialSurface.fill(context, surfaceColor),
                  borderRadius: radius,
                  clipBehavior: Clip.antiAlias,
                  textStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontSize: DiscourseTypography.sm,
                    height: 20 / 14,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0,
                    color: tokens.foreground,
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: compactCapsule
                          ? DSpacing.xs + (border ? 1 : 0)
                          : capsule
                          ? DSpacing.sm
                          : 0,
                      right: compactCapsule
                          ? DSpacing.xs + (border ? 1 : 0)
                          : capsule
                          ? DSpacing.sm
                          : 0,
                      top: leading == null ? inset : 0,
                      bottom:
                          footer == null &&
                              !children.any((part) => part is DCardFooter) &&
                              trailing == null
                          ? inset
                          : 0,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < parts.length; i++) ...[
                          if (i > 0 &&
                              !(parts[i - 1] is DCardContent &&
                                  (parts[i - 1] as DCardContent).joinNext))
                            SizedBox(height: inset),
                          parts[i],
                        ],
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
}

class _CardScope extends InheritedWidget {
  const _CardScope({
    required this.spacing,
    required this.size,
    required this.surfaceColor,
    required super.child,
  });
  final double spacing;
  final DCardSize size;
  final Color surfaceColor;
  static _CardScope? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_CardScope>();
  @override
  bool updateShouldNotify(_CardScope oldWidget) =>
      spacing != oldWidget.spacing ||
      size != oldWidget.size ||
      surfaceColor != oldWidget.surfaceColor;
}

double _spacing(BuildContext context) =>
    _CardScope.of(context)?.spacing ?? DSpacing.lg;

/// Title and description share the first column; action aligns at logical end.
/// At narrow widths the action wraps below, keeping large text readable.
class DCardHeader extends StatelessWidget {
  const DCardHeader({super.key, this.title, this.description, this.action});
  final Widget? title;
  final Widget? description;
  final DCardAction? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsetsDirectional.fromSTEB(
      _spacing(context),
      0,
      _spacing(context),
      0,
    ),
    decoration: null,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final text = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ?title,
            if (title != null && description != null)
              const SizedBox(height: DSpacing.xs),
            ?description,
          ],
        );
        if (action == null) return text;
        final stacked =
            constraints.maxWidth < 240 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        // Keep the element topology stable when reflowing an interactive action.
        return Flex(
          direction: stacked ? Axis.vertical : Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(fit: stacked ? FlexFit.loose : FlexFit.tight, child: text),
            SizedBox(
              width: stacked ? 0 : DSpacing.xs,
              height: stacked ? DSpacing.xs : 0,
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: stacked ? constraints.maxWidth : 0,
                maxWidth: constraints.maxWidth * (stacked ? 1 : .5),
              ),
              child: action!,
            ),
          ],
        );
      },
    ),
  );
}

class DCardTitle extends StatelessWidget {
  const DCardTitle({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontSize: _CardScope.of(context)?.size == DCardSize.small
          ? DiscourseTypography.sm
          : DiscourseTypography.rowTitle,
      height: DiscourseTypography.lineHeightRowTitle,
      fontWeight: FontWeight.w600,
    ),
    child: child,
  );
}

class DCardDescription extends StatelessWidget {
  const DCardDescription({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: TextStyle(
      fontSize: DiscourseTypography.preview,
      height: DiscourseTypography.lineHeightPreview,
      color: DTokens.of(context).mutedForeground,
    ),
    child: child,
  );
}

class DCardAction extends StatelessWidget {
  const DCardAction({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topEnd,
    widthFactor: 1,
    heightFactor: 1,
    child: child,
  );
}

/// [edgeToEdge] removes horizontal inset; [joinNext] removes the following gap.
/// Together these express the reference's negative shared-spacing margins.
class DCardContent extends StatelessWidget {
  const DCardContent({super.key, required this.child, this.joinNext = false});
  final Widget child;

  final bool joinNext;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: (_spacing(context))),
    child: child,
  );
}

/// Footer children own their row, wrap or column composition.
class DCardFooter extends StatelessWidget {
  const DCardFooter({
    super.key,
    required this.child,

    this.rounded = false,
    this.padding,
    this.backgroundColor,
    this.borderColor,
  });
  final Widget child;

  /// Rounds the upper edge using the enclosing card's radius scale.
  final bool rounded;

  /// Defaults to the enclosing card's shared spacing.
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final Color? borderColor;
  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final radius = rounded
        ? const BorderRadius.vertical(top: Radius.circular(DRadius.panel))
        : BorderRadius.zero;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: (Border(top: BorderSide(color: borderColor ?? tokens.border))),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: ColoredBox(
          color: backgroundColor ?? ((tokens.muted.withValues(alpha: .5))),
          child: Padding(
            padding:
                padding ??
                EdgeInsets.all(
                  _spacing(context),
                ).add(const EdgeInsets.only(top: 1)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DashedCardOutline extends CustomPainter {
  const _DashedCardOutline(this.radius, this.color);

  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(radius.toRRect(Offset.zero & size).deflate(.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (var start = 0.0; start < metric.length; start += 7) {
        canvas.drawPath(metric.extractPath(start, start + 4), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedCardOutline oldDelegate) =>
      radius != oldDelegate.radius || color != oldDelegate.color;
}
