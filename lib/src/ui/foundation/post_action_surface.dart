import 'package:flutter/material.dart';

import 'material_theme.dart';
import 'tokens.dart';

/// Bare post actions acquire only an inset rim and sheen in Liquid Glass.
/// The button retains its own focus decoration, geometry and pointer target.
class DPostActionSurface extends StatelessWidget {
  const DPostActionSurface({
    super.key,
    required this.radius,
    required this.color,
    required this.interacting,
    required this.child,
  });
  final BorderRadius radius;
  final Color color;
  final bool interacting;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DMaterialTheme.glassOf(context)) return child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highlight = Colors.white.withValues(
      alpha: interacting ? (dark ? .12 : .55) : 0,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(end: interacting ? 1.0 : 0.0),
      duration: DMotion.duration(context, const Duration(milliseconds: 150)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            transform: const _PostActionSheenTransform(),
            colors: [Color.alphaBlend(highlight, color), color],
            stops: const [0, .62],
          ),
          border: Border.all(
            color: interacting
                ? Colors.white.withValues(alpha: dark ? .14 : .75)
                : Colors.transparent,
          ),
        ),
        child: child,
      ),
      builder: (context, opacity, child) => CustomPaint(
        foregroundPainter: _PostActionCatch(
          radius,
          Colors.white.withValues(alpha: (dark ? .12 : .55) * 1.4 * opacity),
        ),
        child: child,
      ),
    );
  }
}

class _PostActionSheenTransform extends GradientTransform {
  const _PostActionSheenTransform();
  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.identity()
        ..translateByDouble(0, bounds.top, 0, 1)
        ..scaleByDouble(1, 11 / 12, 1, 1)
        ..translateByDouble(0, -bounds.top, 0, 1);
}

class _PostActionCatch extends CustomPainter {
  const _PostActionCatch(this.radius, this.color);
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
  bool shouldRepaint(_PostActionCatch old) =>
      old.radius != radius || old.color != color;
}
