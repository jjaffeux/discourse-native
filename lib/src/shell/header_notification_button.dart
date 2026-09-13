import 'package:discourse_native/discourse_ui.dart';
import 'package:flutter/material.dart';

import '../theme/color_contrast.dart';

/// The approved header capsule, composed from the existing Native button.
/// Callers retain their notification policy, exact accessible count and popup.
DButton headerNotificationButton(
  BuildContext context, {
  required Key key,
  required Key countKey,
  required Widget icon,
  required int count,
  required Color color,
  required Color surface,
  required String tooltip,
  required String semanticLabel,
  required VoidCallback? onPressed,
  FocusNode? focusNode,
  bool hasPopup = false,
  bool expanded = false,
}) {
  final theme = Theme.of(context);
  final background = color.withValues(alpha: .14);
  final hover = color.withValues(alpha: .22);
  final backdrop = opaqueColorOnCanvas(surface, theme.brightness);
  // Preserve the scenario's hue while darkening/lightening ink enough for
  // count text on the approved soft fill, including its stronger hover tint.
  final foreground = contrastSafeForeground(
    background: hover,
    backdrop: backdrop,
    preferred: [
      color,
      for (final amount in [.25, .5, .75])
        Color.lerp(color, theme.colorScheme.onSurface, amount),
      theme.colorScheme.onSurface,
    ],
  );
  return DButton(
    key: key,
    icon: icon,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.sm,
      children: [
        DSeparator(
          orientation: Axis.vertical,
          length: 14,
          color: foreground.withValues(alpha: .25),
        ),
        Text(key: countKey, count > 99 ? '99+' : '$count'),
      ],
    ),
    variant: DButtonVariant.ghost,
    borderRadius: BorderRadius.circular(999),
    backgroundColor: background,
    foregroundColor: foreground,
    interactiveBackgroundColor: hover,
    tooltip: tooltip,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    hasPopup: hasPopup,
    expanded: expanded,
    onPressed: onPressed,
  );
}
