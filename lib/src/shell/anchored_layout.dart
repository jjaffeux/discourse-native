import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Places a floating panel under whatever it is about, flipping above it when
/// there is no room below and sliding along the edge rather than off it.
///
/// A layout delegate rather than a positioned overlay child because the panel's
/// height is not known until it has been built — how many rows a list has, how
/// long a bio runs — and where it goes depends on that. Being asked for a
/// position after the child is measured is exactly what this gets.
///
/// [anchor] is in the coordinates of whatever is being laid out in: the overlay
/// for a dialog, the overlay for an [OverlayPortal]. A null one means the thing
/// it was about is no longer laid out, and the panel is centered instead of
/// dropped — an aside with nowhere to point is still worth reading.
class AnchoredLayout extends SingleChildLayoutDelegate {
  const AnchoredLayout({
    required this.anchor,
    required this.maxWidth,
    this.gap = 8,
    this.margin = 12,
    this.preferAbove = false,
  });

  final Rect? anchor;

  /// What the panel is allowed to grow to, before the window is taken into
  /// account. A narrower window wins.
  final double maxWidth;

  /// Between the panel and the thing it hangs off.
  final double gap;

  /// The smallest gap between the panel and the window's own edges.
  final double margin;

  /// Whether to try above the anchor before below it.
  ///
  /// The composer's completion list wants this. The field it hangs off sits at
  /// the bottom of the window, so "below unless it does not fit" happens to
  /// land above anyway — and a layout that is right by accident stops being
  /// right the first time the panel changes height.
  final bool preferAbove;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = constraints.maxWidth - margin * 2;
    return BoxConstraints.loose(
      Size(
        math.min(maxWidth, math.max(0, available)),
        math.max(0, constraints.maxHeight - margin * 2),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final target = anchor;
    if (target == null) {
      return Offset(
        (size.width - childSize.width) / 2,
        (size.height - childSize.height) / 2,
      );
    }

    final below = target.bottom + gap;
    final above = target.top - gap - childSize.height;
    final fitsBelow = below + childSize.height <= size.height - margin;
    final fitsAbove = above >= margin;

    final double top;
    if (preferAbove) {
      top = fitsAbove
          ? above
          : math.min(below, size.height - margin - childSize.height);
    } else {
      top = fitsBelow ? below : math.max(margin, above);
    }

    final maxLeft = math.max(margin, size.width - childSize.width - margin);
    return Offset(target.left.clamp(margin, maxLeft), top);
  }

  @override
  bool shouldRelayout(AnchoredLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.gap != gap ||
      oldDelegate.margin != margin ||
      oldDelegate.preferAbove != preferAbove;
}
