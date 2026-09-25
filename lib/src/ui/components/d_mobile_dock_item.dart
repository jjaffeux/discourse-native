import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    this.semanticLabel,
    this.focusNode,
    this.expanded = false,
    this.hasPopup = false,
  });

  final Widget icon;
  final String label;
  final Widget? badge;
  final bool selected;
  final String? semanticLabel;
  final VoidCallback? onPressed;
  final FocusNode? focusNode;
  final bool expanded;
  final bool hasPopup;

  @override
  Widget build(BuildContext context) {
    final tokens = DTokens.of(context);
    final accent = tokens.buttonTheme.primary;
    final scaleDelta = MediaQuery.textScalerOf(context).scale(11) - 11;
    final labelHeight = math.max(14.0, 14 + scaleDelta);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    return Semantics(
      selected: selected,
      child: DButton(
        density: DButtonDensity.mobileDock,
        variant: DButtonVariant.transparentBackground,
        shape: DButtonShape.pill,
        tooltip: label,
        semanticLabel: semanticLabel,
        focusNode: focusNode,
        expanded: expanded,
        hasPopup: hasPopup,
        onPressed: onPressed,
        foregroundColor: selected ? tokens.primary : tokens.mutedForeground,
        label: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              key: const ValueKey('mobile-dock-capsule'),
              duration: duration,
              curve: Curves.easeOut,
              width: 44 + scaleDelta,
              height: 30 + scaleDelta,
              decoration: BoxDecoration(
                color: selected ? accent.background : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  size: 20 + scaleDelta,
                  color: selected ? accent.foreground : tokens.mutedForeground,
                ),
                child: Center(child: ExcludeSemantics(child: icon)),
              ),
            ),
            const SizedBox(height: 2),
            SizedBox(
              height: labelHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w500,
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
        ),
      ),
    );
  }
}
