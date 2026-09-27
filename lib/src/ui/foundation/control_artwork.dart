import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Marks the visible bounds of a control.
class DControlArtwork extends SingleChildRenderObjectWidget {
  const DControlArtwork({super.key, required super.child});

  @override
  RenderDControlArtwork createRenderObject(BuildContext context) =>
      RenderDControlArtwork();
}

class RenderDControlArtwork extends RenderProxyBox {
  Rect layoutBounds = Rect.zero;

  @override
  void performLayout() {
    super.performLayout();
    layoutBounds = Offset.zero & size;
  }
}
