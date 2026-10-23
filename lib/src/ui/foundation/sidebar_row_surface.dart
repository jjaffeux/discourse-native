import 'package:flutter/material.dart';

import 'tokens.dart';

/// Sidebar artwork adds no layout or pointer targets.
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

  static CustomPainter painterFor(
    BuildContext context, {
    required bool selected,
    required bool hovered,
    required BorderRadius radius,
    bool navigation = false,
  }) {
    final tokens = DTokens.of(context);
    final color = selected
        ? navigation
              ? Color.lerp(tokens.background, tokens.foreground, .12)!
              : tokens.foreground.withValues(alpha: .13)
        : hovered && !navigation
        ? tokens.foreground.withValues(alpha: .08)
        : Colors.transparent;
    return _SidebarRowPaint(radius, color);
  }
}

class _SidebarRowPaint extends CustomPainter {
  const _SidebarRowPaint(this.radius, this.color);
  final BorderRadius radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawRRect(
    radius.toRRect(Offset.zero & size).scaleRadii(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_SidebarRowPaint old) =>
      radius != old.radius || color != old.color;
}
