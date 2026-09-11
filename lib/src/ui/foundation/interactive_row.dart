import 'package:flutter/widgets.dart';

/// Paints an interactive list row without interpolating its active state.
///
/// Menus, choices, commands, and actionable items must switch backgrounds in
/// the same frame: fading independent rows produces two simultaneous highlights.
/// The caller owns the active row and keeps selection indicators separate.
Container interactiveRowSurface({
  Key? key,
  double? height,
  BoxConstraints? constraints,
  EdgeInsetsGeometry? padding,
  Decoration? decoration,
  Decoration? foregroundDecoration,
  required Widget child,
}) => Container(
  key: key,
  height: height,
  constraints: constraints,
  padding: padding,
  decoration: decoration,
  foregroundDecoration: foregroundDecoration,
  child: child,
);
