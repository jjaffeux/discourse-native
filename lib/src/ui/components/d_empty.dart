import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/tokens.dart';

/// A centered empty-state composition. Actions, state and scrolling belong to
/// the caller. Supply a bounded width (Expanded inside a Row). The default
/// padding follows the reference's 24px mobile and 48px desktop values; an
/// explicit [padding] disables that responsive default. In a bounded pane, wrap
/// in Center/SingleChildScrollView to allow large text to grow. Children keep
/// their native focus and Form ownership.
class DEmpty extends StatelessWidget {
  const DEmpty({
    super.key,
    required this.children,
    EdgeInsetsGeometry? padding,
    this.spacing = 24,
    this.outlined = false,
    this.backgroundColor,
    this.gradient,
  }) : padding = padding ?? const EdgeInsets.all(24),
       _usesDefaultPadding = padding == null,
       assert(spacing >= 0);

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;
  final bool outlined;
  final Color? backgroundColor;
  final Gradient? gradient;
  final bool _usesDefaultPadding;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final radius = tokens.radius * 1.4;
    final resolvedPadding =
        _usesDefaultPadding && MediaQuery.sizeOf(context).width >= 768
        ? const EdgeInsets.all(48)
        : padding;
    return CustomPaint(
      foregroundPainter: outlined
          ? _DashedOutline(color: tokens.border, radius: radius)
          : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          gradient: gradient,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Padding(
          padding: resolvedPadding.add(EdgeInsets.all(outlined ? 1 : 0)),
          child: SizedBox(
            width: double.infinity,
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              style: _textStyle(context),
              child: _Stack(spacing: spacing, children: children),
            ),
          ),
        ),
      ),
    );
  }
}

/// Media, title and description with an 8px gap and a 384px maximum width.
class DEmptyHeader extends StatelessWidget {
  const DEmptyHeader({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: _Stack(spacing: 8, children: children),
  );
}

enum DEmptyMediaVariant { plain, icon }

/// Arbitrary media, or a 40px muted tile with a default 24px icon.
/// The 8px bottom margin is additional to the header's gap. Supply an explicit
/// icon size to override the inherited size. Media does not intercept input.
class DEmptyMedia extends StatelessWidget {
  const DEmptyMedia({
    super.key,
    required this.child,
    this.variant = DEmptyMediaVariant.plain,
  });
  final Widget child;
  final DEmptyMediaVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: variant == DEmptyMediaVariant.plain
          ? child
          : Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.muted,
                borderRadius: BorderRadius.circular(tokens.radius),
              ),
              child: IconTheme.merge(
                data: IconThemeData(size: 24, color: tokens.foreground),
                child: child,
              ),
            ),
    );
  }
}

/// The reference title is a div; opt into heading semantics when appropriate
/// for the surrounding page. Native text scaling and wrapping remain enabled.
class DEmptyTitle extends StatelessWidget {
  const DEmptyTitle(
    String this.text, {
    super.key,
    this.headingLevel,
    this.style,
  }) : child = null;
  const DEmptyTitle.child({
    super.key,
    required Widget this.child,
    this.headingLevel,
    this.style,
  }) : text = null;
  final String? text;
  final Widget? child;
  final int? headingLevel;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = _textStyle(context)
        .copyWith(
          fontSize: DiscourseTypography.lg,
          height: 28 / 18,
          fontFamily: Theme.of(context).textTheme.titleMedium?.fontFamily,
          fontWeight: FontWeight.w500,
          letterSpacing:
              DiscourseTypography.lg * DiscourseTypography.trackingTight,
        )
        .merge(style);
    return Semantics(
      headingLevel: headingLevel,
      child: child == null
          ? Text(text!, textAlign: TextAlign.center, style: resolved)
          : DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              style: resolved,
              child: child!,
            ),
    );
  }
}

/// Muted 14px/22.75px explanatory text. The child constructor allows rich text
/// or native links; those controls own activation, visible focus and semantics.
class DEmptyDescription extends StatelessWidget {
  const DEmptyDescription(String this.text, {super.key}) : child = null;
  const DEmptyDescription.child({super.key, required Widget this.child})
    : text = null;
  final String? text;
  final Widget? child;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    textAlign: TextAlign.center,
    style: _textStyle(context)
        .copyWith(height: 1.625, color: DTokens.of(context).mutedForeground),
    child: child ?? Text(text!, textAlign: TextAlign.center),
  );
}

/// Full available width up to 384px, with 16px vertical gaps. Compose a Wrap
/// child for a responsive horizontal action group, or any native editable field.
class DEmptyContent extends StatelessWidget {
  const DEmptyContent({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 384),
    child: SizedBox(
      width: double.infinity,
      child: DefaultTextStyle.merge(
        textAlign: TextAlign.center,
        style: _textStyle(context),
        child: _Stack(spacing: 16, children: children),
      ),
    ),
  );
}

TextStyle _textStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium!.copyWith(
      fontSize: DiscourseTypography.sm,
      height: 20 / 14,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
      color: DTokens.of(context).foreground,
    );

class _Stack extends StatelessWidget {
  const _Stack({required this.spacing, required this.children});
  final double spacing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(height: spacing),
        children[i],
      ],
    ],
  );
}

class _DashedOutline extends CustomPainter {
  const _DashedOutline({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(0.5),
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 6) {
        canvas.drawPath(metric.extractPath(offset, offset + 3), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
