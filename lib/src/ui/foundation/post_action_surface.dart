import 'package:flutter/material.dart';

import 'material_surface.dart';
import 'material_theme.dart';

/// Post actions retain their flat rest state and Native pointer target.
class DPostActionSurface extends StatelessWidget {
  const DPostActionSurface({
    super.key,
    required this.radius,
    required this.color,
    required this.child,
  });
  final BorderRadius radius;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DMaterialSurface(
    radius: radius,
    color: DMaterialTheme.glassOf(context) ? color : Colors.transparent,
    child: child,
  );
}
