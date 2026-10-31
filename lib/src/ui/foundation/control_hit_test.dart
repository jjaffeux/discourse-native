import 'package:flutter/rendering.dart';

bool isControlRenderObject(RenderObject hit) => switch (hit) {
  RenderEditable() => true,
  RenderSemanticsGestureHandler(:final onTap, :final onLongPress) =>
    onTap != null || onLongPress != null,
  RenderSemanticsAnnotations(:final properties) =>
    properties.button == true ||
        properties.link == true ||
        properties.textField == true ||
        properties.slider == true ||
        properties.toggled != null ||
        properties.checked != null ||
        properties.onTap != null,
  _ => false,
};
