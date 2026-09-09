import 'package:flutter/widgets.dart';

/// Internal composition metadata for controls that share a joined edge.
///
/// A group wraps only its direct children. Nested groups install a new scope,
/// so their radii cannot leak into buttons inside menus, tooltips, or overlays.
class DJoinedControlScope extends InheritedWidget {
  const DJoinedControlScope({
    super.key,
    required this.axis,
    required this.first,
    required this.last,
    required super.child,
  });

  final Axis axis;
  final bool first;
  final bool last;

  bool get omitsLeadingBorder => !first;

  static DJoinedControlScope? maybeOf(BuildContext context) =>
      LookupBoundary.dependOnInheritedWidgetOfExactType<DJoinedControlScope>(
        context,
      );

  BorderRadius resolveRadius(
    BorderRadiusGeometry radius,
    TextDirection direction,
  ) {
    final resolved = radius.resolve(direction);
    if (first && last) return resolved;
    if (axis == Axis.vertical) {
      return BorderRadius.only(
        topLeft: first ? resolved.topLeft : Radius.zero,
        topRight: first ? resolved.topRight : Radius.zero,
        bottomLeft: last ? resolved.bottomLeft : Radius.zero,
        bottomRight: last ? resolved.bottomRight : Radius.zero,
      );
    }
    final firstOnLeft = direction == TextDirection.ltr;
    final keepLeft = firstOnLeft ? first : last;
    final keepRight = firstOnLeft ? last : first;
    return BorderRadius.only(
      topLeft: keepLeft ? resolved.topLeft : Radius.zero,
      bottomLeft: keepLeft ? resolved.bottomLeft : Radius.zero,
      topRight: keepRight ? resolved.topRight : Radius.zero,
      bottomRight: keepRight ? resolved.bottomRight : Radius.zero,
    );
  }

  @override
  bool updateShouldNotify(DJoinedControlScope oldWidget) =>
      axis != oldWidget.axis ||
      first != oldWidget.first ||
      last != oldWidget.last;
}
