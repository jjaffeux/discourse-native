import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/discourse_typography.dart';
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

    final scaleDelta = math.max(
      0.0,
      MediaQuery.textScalerOf(context).scale(11) - 11,
    );
    final labelHeight = 14 + scaleDelta;
    final measure = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge!.copyWith(
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
          // The bar marks the current place on its own edge; the item says
          // it only by its colour and weight.
          foregroundColor: selected
              ? tokens.foreground
              : tokens.mutedForeground,
          backgroundColor: Colors.transparent,
          label: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                key: const ValueKey('mobile-dock-glyph'),
                height: (26) + scaleDelta,
                child: Center(child: ExcludeSemantics(child: icon)),
              ),
              if (!bare) ...[
                const SizedBox(height: 2),
                SizedBox(
                  height: labelHeight,
                  child: CustomMultiChildLayout(
                    delegate: _LabelAndCount(
                      textDirection: Directionality.of(context),
                      height: labelHeight,
                      labelWidth: labelWidth,
                    ),
                    children: [
                      LayoutId(
                        id: _LabelAndCount.label,
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
                      if (badge case final count?)
                        LayoutId(id: _LabelAndCount.count, child: count),
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

/// The label and its count side by side, centred in the column. The label
/// gives way first, cut to one line, and the count keeps its own width until
/// the column cannot hold even that, so neither can push past the column.
class _LabelAndCount extends MultiChildLayoutDelegate {
  _LabelAndCount({
    required this.textDirection,
    required this.height,
    required this.labelWidth,
  });

  static const label = 'label';
  static const count = 'count';
  static const gap = 4.0;

  final TextDirection textDirection;
  final double height;

  /// The label's natural width, which stands in for the column's where
  /// nothing bounds it.
  final double labelWidth;

  @override
  Size getSize(BoxConstraints constraints) => Size(
    constraints.hasBoundedWidth ? constraints.maxWidth : labelWidth,
    height,
  );

  @override
  void performLayout(Size size) {
    var countSize = Size.zero;
    var spacing = 0.0;
    if (hasChild(count)) {
      countSize = layoutChild(count, BoxConstraints.loose(size));
      spacing = gap;
    }
    final labelSize = layoutChild(
      label,
      BoxConstraints(
        maxWidth: math.max(0, size.width - countSize.width - spacing),
        maxHeight: size.height,
      ),
    );
    final total = labelSize.width + spacing + countSize.width;
    final start = (size.width - total) / 2;
    final ltr = textDirection == TextDirection.ltr;
    double left(double fromStart, double width) =>
        ltr ? start + fromStart : size.width - start - fromStart - width;
    positionChild(
      label,
      Offset(left(0, labelSize.width), (size.height - labelSize.height) / 2),
    );
    if (hasChild(count)) {
      positionChild(
        count,
        Offset(
          left(labelSize.width + spacing, countSize.width),
          (size.height - countSize.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_LabelAndCount oldDelegate) =>
      textDirection != oldDelegate.textDirection ||
      height != oldDelegate.height ||
      labelWidth != oldDelegate.labelWidth;
}
