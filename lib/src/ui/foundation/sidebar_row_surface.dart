import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'material_theme.dart';
import 'tokens.dart';

/// Internal sidebar artwork shared by navigation buttons and rich inbox rows.
/// Painting adds no layout, hit targets, or pointer/focus behavior.
class DSidebarRowSurface extends StatelessWidget {
  const DSidebarRowSurface({
    super.key,
    required this.selected,
    required this.hovered,
    required this.radius,
    required this.child,
    this.navigation = false,
  });

  final bool selected;
  final bool hovered;
  final bool navigation;
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: painterFor(
      context,
      selected: selected,
      hovered: hovered,
      navigation: navigation,
      radius: radius,
    ),
    child: child,
  );

  // Item already owns a CustomPaint for its focus ring; reuse that layer.
  static CustomPainter painterFor(
    BuildContext context, {
    required bool selected,
    required bool hovered,
    required BorderRadius radius,
    bool navigation = false,
  }) {
    final tokens = DTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glass = selected && DMaterialTheme.glassOf(context);
    final color = glass
        ? Color.lerp(
            tokens.background,
            tokens.foreground,
            .1,
          )!.withValues(alpha: dark ? .42 : .5)
        : selected
        ? navigation
              ? Color.lerp(tokens.background, tokens.foreground, .12)!
              : tokens.foreground.withValues(alpha: .13)
        : hovered && !navigation
        ? tokens.foreground.withValues(alpha: .08)
        : Colors.transparent;
    return _SidebarRowPaint(radius, color, glass, dark);
  }
}

class _SidebarRowPaint extends CustomPainter {
  const _SidebarRowPaint(this.radius, this.color, this.glass, this.dark);
  final BorderRadius radius;
  final Color color;
  final bool glass;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = radius.toRRect(rect).scaleRadii();
    if (glass) {
      // CSS outer shadows leave the translucent border box clear.
      canvas.save();
      canvas.clipPath(
        Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(24))
          ..addRRect(shape),
      );
      canvas.drawRRect(
        shape.shift(const Offset(0, 2)),
        BoxShadow(
          color: Colors.black.withValues(alpha: dark ? .2 : .08),
          blurRadius: 8,
        ).toPaint(),
      );
      canvas.restore();
    }
    canvas.drawRRect(shape, Paint()..color = color);
    if (!glass || size.isEmpty) return;

    final highlight = dark ? .12 : .55;
    canvas.save();
    canvas.clipRRect(shape);
    canvas.save();
    // app.css: radial-gradient(120% 110% at 35% -25%, white, clear 62%).
    canvas.translate(size.width * .35, size.height * -.25);
    canvas.scale(size.width * 1.2, size.height * 1.1);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset.zero,
          1,
          [
            Colors.white.withValues(alpha: highlight),
            Colors.white.withValues(alpha: 0),
          ],
          const [0, .62],
        ),
    );
    canvas.restore();
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(8))
        ..addRRect(shape.shift(const Offset(0, 1))),
      Paint()
        ..color = Colors.white.withValues(alpha: highlight * 1.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, .5),
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: dark ? .14 : .75),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SidebarRowPaint old) =>
      radius != old.radius ||
      color != old.color ||
      glass != old.glass ||
      dark != old.dark;
}
