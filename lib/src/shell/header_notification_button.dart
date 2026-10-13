import 'package:discourse_native/discourse_ui.dart';

import 'package:flutter/material.dart';

import '../theme/color_contrast.dart';
import 'platform.dart';

/// The header count control, composed from the existing Native button.
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
  bool overlayCount = false,
  DButtonSize size = DButtonSize.regular,
}) {
  final theme = Theme.of(context);
  final primary = DTokens.of(context).buttonTheme.primary;
  final backdrop = opaqueColorOnCanvas(surface, theme.brightness);
  final foreground = expanded
      ? primary.foreground
      : contrastSafeForeground(
          background: DTokens.of(context).buttonTheme.accent.hover,
          backdrop: backdrop,
          preferred: [
            color,
            for (final amount in [.25, .5, .75])
              Color.lerp(color, theme.colorScheme.onSurface, amount),
            theme.colorScheme.onSurface,
          ],
        );
  final variant = expanded ? DButtonVariant.primary : DButtonVariant.ghost;
  if (overlayCount) {
    return DButton.iconOnly(
      key: key,
      icon: ExcludeSemantics(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            icon,
            if (count > 0 && !expanded)
              PositionedDirectional(
                // Anchor the badge's lower edge; its Native size can grow
                // without covering more of the bell at larger text scales.
                top: 6,
                end: -3,
                child: FractionalTranslation(
                  translation: const Offset(0, -1),
                  child: DBadge.overlay(
                    key: countKey,
                    backgroundColor: primary.background,
                    foregroundColor: primary.foreground,
                    ringColor: surface,
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      variant: variant,
      size: size,
      density: context.isTouch
          ? DButtonDensity.standard
          : DButtonDensity.header,
      shape: DButtonShape.pill,
      tooltip: tooltip,
      semanticLabel: semanticLabel,
      focusNode: focusNode,
      hasPopup: hasPopup,
      expanded: expanded,
      onPressed: onPressed,
    );
  }
  return DButton(
    key: key,
    icon: icon,
    label: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: DSpacing.sm,
      children: [
        DSeparator(
          orientation: Axis.vertical,
          length: 15,
          color: foreground.withValues(alpha: .35),
        ),
        Text(
          count > 99 ? '99+' : '$count',
          key: countKey,
          textDirection: TextDirection.ltr,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
    variant: variant,
    size: size,
    density: context.isTouch ? DButtonDensity.standard : DButtonDensity.header,
    shape: DButtonShape.pill,
    foregroundColor: foreground,
    tooltip: tooltip,
    semanticLabel: semanticLabel,
    focusNode: focusNode,
    hasPopup: hasPopup,
    expanded: expanded,
    onPressed: onPressed,
  );
}
