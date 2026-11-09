import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A list that keeps the reader's text still when media inside it takes its
/// height.
abstract interface class LateMediaExtentListener {
  void lateMediaResized(RenderBox box, double heightChange);
}

/// Wraps media whose height is unknown until it loads, so the enclosing
/// [LateMediaExtentListener] can tell which part of a row changed.
class LateMediaExtent extends SingleChildRenderObjectWidget {
  const LateMediaExtent({super.key, required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLateMediaExtent();
}

class _RenderLateMediaExtent extends RenderProxyBox {
  @override
  void performLayout() {
    final previousHeight = hasSize ? size.height : null;
    super.performLayout();
    if (previousHeight == null) return;
    final heightChange = size.height - previousHeight;
    if (heightChange.abs() <= precisionErrorTolerance) return;
    for (var ancestor = parent; ancestor != null; ancestor = ancestor.parent) {
      if (ancestor case final LateMediaExtentListener listener) {
        listener.lateMediaResized(this, heightChange);
        return;
      }
    }
  }
}
