import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../theme/discourse_typography.dart';
import '../foundation/material_theme.dart';
import '../foundation/tokens.dart';
import 'd_button.dart';

/// One labelled destination in a mobile navigation dock.
///
/// The entire icon and label share a single button target. [badge] is a
/// non-interactive compact count, placed beside the label rather than over the
/// icon. The destination owner decides which items are visible and owns routing.
class DMobileDockItem extends StatelessWidget {
  const DMobileDockItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.badge,
    this.selected = false,
    this.bare = false,
    this.collapsed = false,

    this.focusNode,
    this.expanded = false,
    this.hasPopup = false,
  });

  final Widget icon;
  final String label;
  final Widget? badge;
  final bool selected;
  final bool bare;
  final bool collapsed;

  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool expanded;
  final bool hasPopup;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final glass = DMaterialTheme.glassOf(context);
    const glassItems = LiquidGlassTabItemStyle();
    final scaleDelta = math.max(
      0.0,
      MediaQuery.textScalerOf(context).scale(11) - 11,
    );
    final labelHeight = 14 + scaleDelta;
    final measure = TextPainter(
      text: TextSpan(
        text: label,
        style: glass
            ? TextStyle(
                fontSize: glassItems.labelFontSize,
                fontWeight: glassItems.selectedFontWeight,
              )
            : Theme.of(context).textTheme.labelLarge!.copyWith(
                fontSize: DiscourseTypography.micro,
                fontWeight: FontWeight.w600,
              ),
      ),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final labelWidth = measure.width;
    measure.dispose();
    if (collapsed) {
      return DButton.iconOnly(
        density: DButtonDensity.mobileDockCollapsed,
        variant: DButtonVariant.ghost,
        shape: DButtonShape.pill,
        icon: icon,
        tooltip: label,
        focusNode: focusNode,
        onPressed: onPressed,
      );
    }
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        child: DButton(
          density: DButtonDensity.mobileDock,
          variant: DButtonVariant.ghost,
          shape: DButtonShape.pill,
          tooltip: label,
          semanticLabel: bare ? label : null,
          focusNode: focusNode,
          expanded: expanded,
          hasPopup: hasPopup,
          onPressed: onPressed,
          foregroundColor: glass
              ? glassItems.colorFor(selected: selected)
              : selected
              ? tokens.foreground
              : tokens.mutedForeground,
          backgroundColor: selected
              ? glass
                    ? const LiquidGlassTabPillStyle().effectiveRest.color
                    : Color.lerp(tokens.background, tokens.foreground, .20)
              : Colors.transparent,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const ValueKey('mobile-dock-glyph'),
                height: (glass ? glassItems.iconSize : 26) + scaleDelta,
                child: Center(child: ExcludeSemantics(child: icon)),
              ),
              if (!bare) ...[
                SizedBox(height: glass ? glassItems.iconLabelGap : 2),
                SizedBox(
                  height: labelHeight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minWidth: labelWidth),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: glass
                                  ? glassItems.fontWeightFor(selected: selected)
                                  : selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      if (badge case final count?) ...[
                        const SizedBox(width: 4),
                        count,
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
