import 'dart:math' as math;

import 'package:flutter/widgets.dart';

Rect? anchorRect({required RenderBox? anchor, required RenderBox? overlay}) {
  if (anchor == null || overlay == null) return null;
  if (!anchor.attached || !anchor.hasSize || !overlay.attached) return null;
  return Rect.fromPoints(
    anchor.localToGlobal(Offset.zero, ancestor: overlay),
    anchor.localToGlobal(
      anchor.size.bottomRight(Offset.zero),
      ancestor: overlay,
    ),
  );
}

class AnchoredLayout extends SingleChildLayoutDelegate {
  const AnchoredLayout({
    required this.anchor,
    required this.maxWidth,
    this.gap = 8,
    this.margin = 12,
    this.preferAbove = false,
    this.keepPreferredPlacement = false,
  });

  final Rect? anchor;

  final double maxWidth;

  final double gap;

  final double margin;

  final bool preferAbove;

  final bool keepPreferredPlacement;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = constraints.maxWidth - margin * 2;
    var availableHeight = math.max(0.0, constraints.maxHeight - margin * 2);
    final target = anchor;
    if (preferAbove && keepPreferredPlacement && target != null) {
      availableHeight = math.min(
        availableHeight,
        math.max(0.0, target.top - gap - margin),
      );
    }
    return BoxConstraints.loose(
      Size(math.min(maxWidth, math.max(0, available)), availableHeight),
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
      top = keepPreferredPlacement
          ? math.max(margin, above)
          : fitsAbove
          ? above
          : math.min(below, size.height - margin - childSize.height);
    } else {
      top = fitsBelow ? below : math.max(margin, above);
    }

    final maxLeft = math.max(margin, size.width - childSize.width - margin);
    final maxTop = math.max(margin, size.height - childSize.height - margin);
    return Offset(
      target.left.clamp(margin, maxLeft),
      top.clamp(margin, maxTop),
    );
  }

  @override
  bool shouldRelayout(AnchoredLayout oldDelegate) =>
      oldDelegate.anchor != anchor ||
      oldDelegate.maxWidth != maxWidth ||
      oldDelegate.gap != gap ||
      oldDelegate.margin != margin ||
      oldDelegate.preferAbove != preferAbove ||
      oldDelegate.keepPreferredPlacement != keepPreferredPlacement;
}
